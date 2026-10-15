--[[
	CaveMap

	Turns the world seed into caves: WHERE they are, WHAT SHAPE they take and,
	for any chunk, exactly which blocks are air. Pure function of (seed,
	position), so every chunk - and every query about an unloaded chunk -
	gets the same answer in any order.

	  CaveMap.init(seed, options)
	  CaveMap.getRecord(cx, cz)            -> record     what a chunk carves
	  CaveMap.isAirAt(blockX, by, blockZ)  -> boolean
	  CaveMap.columnAir(blockX, blockZ)    -> intervals? {lo, hi, lo, hi, ...}
	  CaveMap.hasAirBelowSurface(blockX, blockZ, depth) -> boolean
	  CaveMap.isEntranceColumn(blockX, blockZ) -> boolean
	  CaveMap.surfaceAt(blockX, blockZ)    -> height?    lowered by an entrance
	  CaveMap.describeAt(blockX, by, blockZ) -> info?    cave, kind, biome ...
	  CaveMap.getPlansIntersectingChunk(cx, cz) -> { plan }
	  CaveMap.getCandidates(plan)          -> { candidate }  future content
	  CaveMap.getCandidatesInChunk(cx, cz) -> { candidate }
	  CaveMap.findNearestPlan(blockX, blockZ, radius, category?) -> plan?
	  CaveMap.getStats() / clearCaches()

	=========================================================================
	HOW A CAVE IS MADE
	=========================================================================

	PLANS. Each category (Small, Large; see CaveConfig) cuts the world into a
	grid of cells. A cell hashes to decide whether it hosts a plan and, if so,
	where in the cell the plan's origin is. The origin column's biome picks
	the profile, and a deterministic walk draws the cave as a list of
	PRIMITIVES in absolute coordinates:

	  capsule     a tunnel: two points and a radius
	  ellipsoid   a room, chamber or ledge pocket

	Every chunk the plan's bounding box touches rebuilds the identical plan
	from the identical hash, which is what makes a tunnel continue across a
	border without the chunks ever talking. A plan has ONE biome, read at its
	origin, so a tunnel never changes character half way because the surface
	biome changed above it.

	CARVING. For a chunk, the plans in reach are gathered (bounded by
	MaxPlansPerChunk), and each column tests only the primitives whose XZ
	bounding box covers it, then only the rows inside the primitive's Y
	range. Roughness is a 3D noise WARP of the radius - the primitive is
	still one coherent shape, so there are no stray single-block pockets.
	Each column clamps its air below the surface cover and above the bedrock
	margin, except under a deliberate entrance mouth. The result is one
	RECORD per chunk: per cell, a short list of contiguous air intervals.
	Records and plans are cached in two generations.

	ENTRANCES are part of the plan: a sloped ramp from a validated surface
	site (dry, flat enough, far from spawn) down to the first tunnel. Only
	the ramp near its mouth is allowed through the surface cover.

	WHAT THIS MODULE DOES NOT DO: touch chunk data, draw anything, or know
	about edits. TerrainManager reads the record and marks the cells
	removed, exactly as the Island's underside is carved.

	All coordinates are BLOCK coordinates. A block (x, by, z) is tested at
	its centre (x + 0.5, by + 0.5, z + 0.5).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Perlin = require(ReplicatedStorage:WaitForChild("Perlin"))

local TerrainFolder = script.Parent
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))
local StrataConfig = require(TerrainFolder:WaitForChild("StrataConfig"))
local CaveConfig = require(TerrainFolder:WaitForChild("CaveConfig"))

local CaveMap = {}

-- ---------------------------------------------------------------------------
-- Localised config
-- ---------------------------------------------------------------------------

local CHUNK_SIZE = TerrainConfig.ChunkSize
local HALO_SIZE = CHUNK_SIZE + 2
local FLOOR_Y = TerrainConfig.WorldFloorY
local WORLD_RADIUS = TerrainConfig.WorldRadiusBlocks

local COVER = CaveConfig.MinSurfaceCoverBlocks
local COVER_WET = CaveConfig.MinSurfaceCoverUnderWaterBlocks
local FLOOR_LIMIT = FLOOR_Y + StrataConfig.BedrockThickness + CaveConfig.MinFloorThicknessBlocks
local SPAWN_EXCLUSION = CaveConfig.SpawnExclusionBlocks
local ENTRANCE_SAFE = CaveConfig.EntranceSafeDistanceBlocks
local ALLOW_WET_ENTRANCE = CaveConfig.AllowUnderwaterEntrances
local MAX_PLANS = CaveConfig.MaxPlansPerChunk
local MAX_PRIMS = CaveConfig.MaxPrimitivesPerPlan
local MAX_SLOPE = CaveConfig.MaxTunnelSlope
local ENTRANCE = CaveConfig.Entrance
local ROUGH_AMP = CaveConfig.RoughnessAmplitude
local INV_ROUGH_SCALE = 1 / CaveConfig.RoughnessScaleBlocks

local CATEGORY_NAMES = { "Small", "Large" }
local CATEGORIES = { CaveConfig.Categories.Small, CaveConfig.Categories.Large }
local CATEGORY_INDEX = { Small = 1, Large = 2 }

-- Furthest any primitive can lie from its plan origin: node extent plus the
-- largest radius plus the roughness margin. Bounds the grid search.
local PLAN_REACH = {}
for i, category in ipairs(CATEGORIES) do
	PLAN_REACH[i] = category.MaxExtentBlocks + CaveConfig.MaxChamberRadius * (1 + ROUGH_AMP) + 2
end

local CAPSULE = 1
local ELLIPSOID = 2

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local hashSeed = 0
local activeSeed = 0
local noiseOffX, noiseOffY, noiseOffZ = 0, 0, 0
local isReady = false

-- Injected. sampler(blockX, blockZ) -> height, biomeName, waterTop.
local sampler = nil
local isInWorld = nil

-- A chunk nothing carves. Shared and never written to.
local EMPTY = { empty = true, plans = {}, planCount = 0, cells = {}, owner = {}, low = {}, high = {},
	surface = {}, entrance = {}, halo = {}, haloOwner = {}, count = 0, blocks = 0 }

local stats = {
	plansBuilt = 0,
	plansSmall = 0,
	plansLarge = 0,
	plansRejectedChance = 0,
	plansRejectedSpawn = 0,
	plansRejectedEdge = 0,
	plansRejectedWet = 0,
	entrancesPlanned = 0,
	recordsBuilt = 0,
	recordsEmpty = 0,
	carvedBlocks = 0,
	planCacheRotations = 0,
	recordCacheRotations = 0,
}

-- ---------------------------------------------------------------------------
-- Two-generation caches (see TerrainManager's column cache for the idea)
-- ---------------------------------------------------------------------------

local function newCache(limit, statKey)
	return { young = {}, old = {}, count = 0, limit = math.max(1, math.floor(limit / 2)), statKey = statKey }
end

local function cacheGet(cache, key)
	local value = cache.young[key]
	if value ~= nil then
		return value
	end
	value = cache.old[key]
	if value ~= nil then
		if cache.count >= cache.limit then
			cache.old, cache.young = cache.young, {}
			cache.count = 0
			stats[cache.statKey] += 1
		end
		cache.young[key] = value
		cache.count += 1
	end
	return value
end

local function cacheSet(cache, key, value)
	if cache.count >= cache.limit then
		cache.old, cache.young = cache.young, {}
		cache.count = 0
		stats[cache.statKey] += 1
	end
	cache.young[key] = value
	cache.count += 1
end

local function cacheClear(cache)
	table.clear(cache.young)
	table.clear(cache.old)
	cache.count = 0
end

local planCache = newCache(CaveConfig.PlanCacheLimit, "planCacheRotations")
local recordCache = newCache(CaveConfig.RecordCacheLimit, "recordCacheRotations")

-- ---------------------------------------------------------------------------
-- Hashing
-- ---------------------------------------------------------------------------

-- Same family as OreRegistry.hashUnit: deterministic [0, 1) from integers,
-- no allocation, two sine terms so it does not stripe.
local function hashUnit(a, b, c, salt)
	local x = a * 127.1 + b * 311.7 + c * 74.7 + salt * 269.5 + hashSeed
	local y = a * 269.5 + b * 183.3 + c * 246.1 + salt * 113.5 + hashSeed
	local v = math.sin(x) * 43758.5453 + math.sin(y) * 28001.8384
	return v - math.floor(v)
end

-- A plan's private stream of numbers: the cell's hash, advanced by a counter.
-- Order within a plan is fixed by the code, so the stream is reproducible.
local function nextUnit(stream)
	local n = stream.n + 1
	stream.n = n
	return hashUnit(stream.gx, stream.gz, n, stream.salt)
end

local function nextRange(stream, range)
	return range.min + nextUnit(stream) * (range.max - range.min)
end

local function nextInt(stream, range)
	return range.min + math.floor(nextUnit(stream) * (range.max - range.min + 0.999))
end

local function noise3(px, py, pz)
	return Perlin:noise(px * INV_ROUGH_SCALE + noiseOffX, py * INV_ROUGH_SCALE + noiseOffY, pz * INV_ROUGH_SCALE + noiseOffZ)
end

local function chunkKeyOf(cx, cz)
	return (cx + 8192) * 65536 + (cz + 8192)
end

local function planKeyOf(catIndex, gx, gz)
	return (catIndex * 65536 + (gx + 32768)) * 65536 + (gz + 32768)
end

-- ---------------------------------------------------------------------------
-- Primitives
-- ---------------------------------------------------------------------------

local function addCapsule(plan, x0, y0, z0, x1, y1, z1, radius, tag, breaksSurface)
	if plan.primCount >= MAX_PRIMS then
		return nil
	end

	local margin = radius * (1 + ROUGH_AMP * plan.profile.roughness) + 1
	local prim = {
		kind = CAPSULE,
		x0 = x0, y0 = y0, z0 = z0,
		x1 = x1, y1 = y1, z1 = z1,
		r = radius,
		reach = margin, -- XZ rejection distance
		tag = tag,
		breaksSurface = breaksSurface or false,
		minX = math.floor(math.min(x0, x1) - margin),
		maxX = math.ceil(math.max(x0, x1) + margin),
		minY = math.floor(math.min(y0, y1) - margin),
		maxY = math.ceil(math.max(y0, y1) + margin),
		minZ = math.floor(math.min(z0, z1) - margin),
		maxZ = math.ceil(math.max(z0, z1) + margin),
	}

	-- Squared segment length, for the closest-point projection.
	local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
	prim.len2 = dx * dx + dy * dy + dz * dz

	if breaksSurface then
		-- Only the stretch near the mouth may break the surface cover. Past
		-- it the ramp is deeper than the cover anyway, and if the ground
		-- happened to fall away along the ramp the cover rule takes over
		-- rather than letting a second hole open.
		local slope = ENTRANCE.MaxSlope
		local horizontal = math.sqrt(dx * dx + dz * dz)
		local depthRun = (COVER + radius + 1) / slope
		prim.mouthReach2 = (math.min(horizontal, depthRun) + margin) ^ 2
	end

	plan.primCount += 1
	plan.prims[plan.primCount] = prim
	return prim
end

local function addEllipsoid(plan, cx, cy, cz, rx, ry, rz, tag)
	if plan.primCount >= MAX_PRIMS then
		return nil
	end

	local rough = 1 + ROUGH_AMP * plan.profile.roughness
	local prim = {
		kind = ELLIPSOID,
		cx = cx, cy = cy, cz = cz,
		rx = rx, ry = ry, rz = rz,
		invRx = 1 / rx, invRy = 1 / ry, invRz = 1 / rz,
		angular = plan.profile.angularity,
		tag = tag,
		breaksSurface = false,
		minX = math.floor(cx - rx * rough - 1),
		maxX = math.ceil(cx + rx * rough + 1),
		minY = math.floor(cy - ry * rough - 1),
		maxY = math.ceil(cy + ry * rough + 1),
		minZ = math.floor(cz - rz * rough - 1),
		maxZ = math.ceil(cz + rz * rough + 1),
	}

	plan.primCount += 1
	plan.prims[plan.primCount] = prim
	return prim
end

--[[
	Is the block centre (px, py, pz) inside the primitive, roughness included?

	Roughness is only sampled in the shell where it can change the answer -
	well inside or well outside skips the noise entirely.
]]
local function containsPoint(prim, px, py, pz, roughness)
	local amp = ROUGH_AMP * roughness

	if prim.kind == CAPSULE then
		local x0, y0, z0 = prim.x0, prim.y0, prim.z0
		local dx, dy, dz = prim.x1 - x0, prim.y1 - y0, prim.z1 - z0
		local t = 0
		if prim.len2 > 0 then
			t = ((px - x0) * dx + (py - y0) * dy + (pz - z0) * dz) / prim.len2
			if t < 0 then
				t = 0
			elseif t > 1 then
				t = 1
			end
		end
		local qx, qy, qz = px - (x0 + dx * t), py - (y0 + dy * t), pz - (z0 + dz * t)
		local d = math.sqrt(qx * qx + qy * qy + qz * qz)
		local r = prim.r

		if d <= r * (1 - amp) then
			return true
		elseif d > r * (1 + amp) then
			return false
		end
		return d <= r * (1 + amp * noise3(px, py, pz))
	end

	local ex = (px - prim.cx) * prim.invRx
	local ey = (py - prim.cy) * prim.invRy
	local ez = (pz - prim.cz) * prim.invRz
	local d = math.sqrt(ex * ex + ey * ey + ez * ez)

	local angular = prim.angular
	if angular > 0 then
		-- Blend toward the box norm: 1 is a squared-off room.
		local ax = if ex < 0 then -ex else ex
		local ay = if ey < 0 then -ey else ey
		local az = if ez < 0 then -ez else ez
		local box = if ax > ay then (if ax > az then ax else az) else (if ay > az then ay else az)
		d += (box - d) * angular
	end

	if d <= 1 - amp then
		return true
	elseif d > 1 + amp then
		return false
	end
	return d <= 1 + amp * noise3(px, py, pz)
end

-- ---------------------------------------------------------------------------
-- Plan helpers
-- ---------------------------------------------------------------------------

local function newPlan(catIndex, gx, gz, originX, originZ, originY, biome, profile)
	local plan = {
		id = string.format("%s:%d:%d", if catIndex == 1 then "S" else "L", gx, gz),
		key = planKeyOf(catIndex, gx, gz),
		category = CATEGORY_NAMES[catIndex],
		catIndex = catIndex,
		gx = gx,
		gz = gz,
		originX = originX,
		originZ = originZ,
		originY = originY,
		biome = biome,
		profile = profile,
		prims = {},
		primCount = 0,
		nodes = {}, -- content candidate seeds: { kind, x, y, z, radius }
		entrance = nil, -- the mouth, as a node, when the plan has one
		minX = math.huge, maxX = -math.huge,
		minZ = math.huge, maxZ = -math.huge,
		minY = math.huge, maxY = -math.huge,
		candidates = nil,
	}
	return plan
end

local function addNode(plan, kind, x, y, z, radius)
	plan.nodes[#plan.nodes + 1] = { kind = kind, x = x, y = y, z = z, radius = radius }
end

-- Bounding boxes from the primitives, once the plan is drawn.
local function finishPlan(plan)
	for i = 1, plan.primCount do
		local prim = plan.prims[i]
		if prim.minX < plan.minX then plan.minX = prim.minX end
		if prim.maxX > plan.maxX then plan.maxX = prim.maxX end
		if prim.minZ < plan.minZ then plan.minZ = prim.minZ end
		if prim.maxZ > plan.maxZ then plan.maxZ = prim.maxZ end
		if prim.minY < plan.minY then plan.minY = prim.minY end
		if prim.maxY > plan.maxY then plan.maxY = prim.maxY end
	end
	return plan
end

-- Keeps a point inside the plan's allowed box; returns the clamped point.
local function clampExtent(plan, extent, x, z)
	local ox, oz = plan.originX, plan.originZ
	if x < ox - extent then x = ox - extent elseif x > ox + extent then x = ox + extent end
	if z < oz - extent then z = oz - extent elseif z > oz + extent then z = oz + extent end
	return x, z
end

local function clampY(y, low, high)
	if y < low then
		return low
	elseif y > high then
		return high
	end
	return y
end

--[[
	Could a cave mouth open here? Dry, inside the height band, far enough
	from spawn, and the ground around it not too broken to walk out of.
]]
local function entranceSiteOk(x, z)
	if x * x + z * z < ENTRANCE_SAFE * ENTRANCE_SAFE then
		return false
	end
	if not isInWorld(x, z) then
		return false
	end

	local height, _biome, water = sampler(x, z)
	if height < ENTRANCE.MinSurfaceHeight or height > ENTRANCE.MaxSurfaceHeight then
		return false
	end
	if water > height and not ALLOW_WET_ENTRANCE then
		return false
	end

	local relief = ENTRANCE.MaxSurfaceRelief
	for dx = -2, 2, 2 do
		for dz = -2, 2, 2 do
			if dx ~= 0 or dz ~= 0 then
				if not isInWorld(x + dx, z + dz) then
					return false
				end
				local h, _b, w = sampler(x + dx, z + dz)
				if math.abs(h - height) > relief then
					return false
				end
				if w > h and not ALLOW_WET_ENTRANCE then
					return false
				end
			end
		end
	end

	return true, height
end

--[[
	A ramp from a surface site down to a point underground, in pieces that
	bend a little, each no steeper than the entrance slope. The first piece
	is the only one allowed through the surface cover.
]]
local function addEntranceRamp(plan, stream, sx, sz, surfaceHeight, tx, ty, tz, radius)
	local startX, startY, startZ = sx + 0.5, surfaceHeight + 0.6, sz + 0.5
	local pieces = 3
	local px, py, pz = startX, startY, startZ

	for i = 1, pieces do
		local f = i / pieces
		local nx = startX + (tx - startX) * f
		local ny = startY + (ty - startY) * f
		local nz = startZ + (tz - startZ) * f

		if i < pieces then
			-- A sideways wobble so the ramp is not a ruler line.
			local wobble = (nextUnit(stream) - 0.5) * radius * 1.5
			local dx, dz = tx - startX, tz - startZ
			local len = math.sqrt(dx * dx + dz * dz)
			if len > 0 then
				nx += -dz / len * wobble
				nz += dx / len * wobble
			end
		end

		addCapsule(plan, px, py, pz, nx, ny, nz, radius, "entrance", i == 1)
		if i == 1 then
			-- The candidate sits at the end of the first piece: just inside
			-- the mouth, where the ramp has full headroom, rather than on the
			-- surface block itself.
			addNode(plan, "entrance", nx, ny, nz, radius)
		end
		px, py, pz = nx, ny, nz
	end

	plan.entrance = { x = sx, z = sz, y = surfaceHeight }
	stats.entrancesPlanned += 1
end

-- ---------------------------------------------------------------------------
-- Small plans
-- ---------------------------------------------------------------------------

local function buildSmallPlan(plan, stream, category)
	local profile = plan.profile
	local depth = profile.depth.small
	local surface = plan.originY
	local extent = category.MaxExtentBlocks

	-- Everything below the surface cover, above the bedrock margin.
	local yHigh = surface - depth.min - 1
	local yLow = FLOOR_LIMIT + CaveConfig.MaxChamberRadius
	if yHigh <= yLow then
		return false
	end

	local radius = nextRange(stream, profile.tunnelRadius)
	local heading = nextUnit(stream) * math.pi * 2
	local x, z = plan.originX + 0.5, plan.originZ + 0.5
	local y

	local wantsEntrance = nextUnit(stream) < profile.entranceChance
	local siteOk, siteHeight = false, nil
	if wantsEntrance then
		siteOk, siteHeight = entranceSiteOk(plan.originX, plan.originZ)
	end

	if siteOk then
		-- Ramp down to a shallow first node at the entrance slope.
		local entryDepth = depth.min + nextUnit(stream) * 6
		local run = entryDepth / ENTRANCE.MaxSlope
		local nx = x + math.cos(heading) * run
		local nz = z + math.sin(heading) * run
		nx, nz = clampExtent(plan, extent, nx, nz)
		y = clampY(siteHeight - entryDepth, yLow, yHigh)
		addEntranceRamp(plan, stream, plan.originX, plan.originZ, siteHeight, nx, y, nz, radius)
		x, z = nx, nz
	else
		-- No mouth: start just under the surface so shallow digging finds it.
		y = clampY(surface - category.NearSurfaceBlocks - nextUnit(stream) * 4, yLow, yHigh)
	end

	addNode(plan, "tunnel", x, y, z, radius)

	-- Where the tunnel wants to end up, depth-wise.
	local targetY = clampY(surface - nextRange(stream, depth), yLow, yHigh)
	local segments = nextInt(stream, category.Segments)
	local rooms = nextInt(stream, category.Rooms)
	local roomAt = {}
	for _ = 1, rooms do
		roomAt[1 + math.floor(nextUnit(stream) * segments)] = true
	end
	local forkAt = if nextUnit(stream) < category.ForkChance then 1 + math.floor(nextUnit(stream) * (segments - 1)) else nil

	local maxDrop = profile.verticality * MAX_SLOPE

	local function walk(fromX, fromY, fromZ, fromHeading, count, isBranch)
		local cx, cy, cz, h = fromX, fromY, fromZ, fromHeading
		for i = 1, count do
			local turn = math.rad(nextRange(stream, category.Turn))
			if nextUnit(stream) < 0.5 then
				turn = -turn
			end
			h += turn

			local len = nextRange(stream, category.SegmentLength)
			local nx = cx + math.cos(h) * len
			local nz = cz + math.sin(h) * len
			local bx, bz = clampExtent(plan, extent, nx, nz)
			if bx ~= nx or bz ~= nz then
				-- Hit the extent box: turn back toward the origin.
				h = math.atan2(plan.originZ + 0.5 - cz, plan.originX + 0.5 - cx) + (nextUnit(stream) - 0.5)
				nx = cx + math.cos(h) * len
				nz = cz + math.sin(h) * len
				nx, nz = clampExtent(plan, extent, nx, nz)
			end

			-- Drift toward the target depth, bounded by the slope the profile
			-- allows for this length of tunnel.
			local pull = (targetY - cy) * 0.5
			local wander = (nextUnit(stream) - 0.5) * len * maxDrop
			local dy = pull + wander
			local limit = len * maxDrop
			if dy > limit then dy = limit elseif dy < -limit then dy = -limit end
			local ny = clampY(cy + dy, yLow, yHigh)

			local segRadius = radius * (0.85 + nextUnit(stream) * 0.3)
			if segRadius < ENTRANCE.MinRadius then
				segRadius = ENTRANCE.MinRadius
			end
			addCapsule(plan, cx, cy, cz, nx, ny, nz, segRadius, "tunnel")

			local last = i == count
			if not isBranch and roomAt[i] then
				local rr = nextRange(stream, profile.roomRadius)
				local ry = math.max(2, rr * profile.chamberFlatten)
				addEllipsoid(plan, nx, ny, nz, rr, ry, rr * (0.8 + nextUnit(stream) * 0.4), "room")
				addNode(plan, "room", nx, ny, nz, rr)
			elseif last then
				addNode(plan, "deadEnd", nx, ny, nz, segRadius)
			elseif not isBranch and forkAt == i then
				addNode(plan, "junction", nx, ny, nz, segRadius)
			else
				addNode(plan, "tunnel", nx, ny, nz, segRadius)
			end

			if not isBranch and forkAt == i then
				local branchHeading = h + (if nextUnit(stream) < 0.5 then 1 else -1) * math.rad(60 + nextUnit(stream) * 50)
				walk(nx, ny, nz, branchHeading, nextInt(stream, category.ForkSegments), true)
			end

			cx, cy, cz = nx, ny, nz
		end
	end

	walk(x, y, z, heading, segments, false)
	return true
end

-- ---------------------------------------------------------------------------
-- Large plans
-- ---------------------------------------------------------------------------

local function buildLargePlan(plan, stream, category)
	local profile = plan.profile
	local depth = profile.depth.large
	local surface = plan.originY
	local extent = category.MaxExtentBlocks

	local yHigh = surface - depth.min
	local yLow = FLOOR_LIMIT + CaveConfig.MaxChamberRadius + 1
	if yHigh - yLow < CaveConfig.MaxChamberRadius then
		return false
	end

	-- Epicentres: a chain of chambers at different levels.
	local count = nextInt(stream, category.Epicentres)
	local epic = {}
	local heading = nextUnit(stream) * math.pi * 2
	local cx, cz = plan.originX + 0.5, plan.originZ + 0.5
	local cy = clampY(surface - nextRange(stream, depth), yLow, yHigh)

	for i = 1, count do
		local r = nextRange(stream, profile.chamberRadius)
		local ry = math.max(3, r * profile.chamberFlatten)
		-- Keep the roof under the cover band and the floor off the bedrock.
		cy = clampY(cy, yLow, yHigh - ry)
		local rz = r * (0.75 + nextUnit(stream) * 0.5)
		addEllipsoid(plan, cx, cy, cz, r, ry, rz, "epicentre")
		addNode(plan, "epicentre", cx, cy, cz, math.max(r, rz))
		epic[i] = { x = cx, y = cy, z = cz, r = r, ry = ry }

		-- Ledges: pockets cut high in the wall, reached by climbing the rubble
		-- of the roughness or by a side tunnel that happens to land there.
		for _ = 1, nextInt(stream, category.Ledges) do
			local a = nextUnit(stream) * math.pi * 2
			local lx = cx + math.cos(a) * r * 0.8
			local lz = cz + math.sin(a) * rz * 0.8
			local ly = cy + ry * (0.1 + nextUnit(stream) * 0.4)
			local lr = math.max(2.5, r * 0.45)
			addEllipsoid(plan, lx, ly, lz, lr, math.max(1.8, lr * 0.5), lr, "ledge")
			addNode(plan, "ledge", lx, ly, lz, lr)
		end

		if i < count then
			heading += (nextUnit(stream) - 0.5) * math.rad(120)
			local spacing = nextRange(stream, category.EpicentreSpacing)
			local nx = cx + math.cos(heading) * spacing
			local nz = cz + math.sin(heading) * spacing
			local bx, bz = clampExtent(plan, extent, nx, nz)
			if bx ~= nx or bz ~= nz then
				heading = math.atan2(plan.originZ + 0.5 - cz, plan.originX + 0.5 - cx)
				nx = cx + math.cos(heading) * spacing
				nz = cz + math.sin(heading) * spacing
				nx, nz = clampExtent(plan, extent, nx, nz)
			end
			cx, cz = nx, nz
			cy = clampY(cy + (nextUnit(stream) - 0.5) * 2 * category.EpicentreLevelChange, yLow, yHigh)
		end
	end

	-- Broad passages between consecutive epicentres, bending and changing
	-- level a little, with a node at every bend for future content.
	local passageNodes = {}
	local function passage(a, b)
		local pieces = nextInt(stream, category.PassageSegments)
		local px, py, pz = a.x, a.y, a.z
		local dx, dz = b.x - a.x, b.z - a.z
		local len = math.sqrt(dx * dx + dz * dz)
		local nxp, nzp = 0, 0
		if len > 0 then
			nxp, nzp = -dz / len, dx / len
		end
		local radius = nextRange(stream, profile.passageRadius)

		for i = 1, pieces do
			local f = i / pieces
			local nx, ny, nz
			if i == pieces then
				nx, ny, nz = b.x, b.y, b.z
			else
				local side = (nextUnit(stream) - 0.5) * len * 0.4
				nx = a.x + dx * f + nxp * side
				nz = a.z + dz * f + nzp * side
				nx, nz = clampExtent(plan, extent, nx, nz)
				ny = clampY(a.y + (b.y - a.y) * f + (nextUnit(stream) - 0.5) * 6, yLow, yHigh - radius)
			end

			-- Bound the slope of each piece.
			local hx, hz = nx - px, nz - pz
			local horizontal = math.sqrt(hx * hx + hz * hz)
			local maxRise = math.max(1, horizontal) * MAX_SLOPE
			if ny - py > maxRise then ny = py + maxRise elseif py - ny > maxRise then ny = py - maxRise end

			addCapsule(plan, px, py, pz, nx, ny, nz, radius * (0.9 + nextUnit(stream) * 0.2), "passage")
			if i < pieces then
				addNode(plan, "passage", nx, ny, nz, radius)
				passageNodes[#passageNodes + 1] = { x = nx, y = ny, z = nz }
			end
			px, py, pz = nx, ny, nz
		end
	end

	for i = 1, count - 1 do
		passage(epic[i], epic[i + 1])
	end
	if count >= 3 and nextUnit(stream) < category.LoopChance then
		passage(epic[count], epic[1])
	end

	-- Anchors side content can hang off: every epicentre and passage bend.
	local anchors = {}
	for _, e in ipairs(epic) do
		anchors[#anchors + 1] = e
	end
	for _, p in ipairs(passageNodes) do
		anchors[#anchors + 1] = p
	end

	local function pickAnchor()
		return anchors[1 + math.floor(nextUnit(stream) * #anchors)]
	end

	-- Sub-chambers: a short tunnel out to a room.
	for _ = 1, nextInt(stream, category.SubChambers) do
		local a = pickAnchor()
		local angle = nextUnit(stream) * math.pi * 2
		local len = 8 + nextUnit(stream) * 8
		local rr = nextRange(stream, profile.roomRadius)
		local nx = a.x + math.cos(angle) * (len + rr)
		local nz = a.z + math.sin(angle) * (len + rr)
		nx, nz = clampExtent(plan, extent, nx, nz)
		local ny = clampY(a.y + (nextUnit(stream) - 0.5) * 2 * 6 * profile.verticality, yLow, yHigh - rr)
		local tr = nextRange(stream, profile.tunnelRadius)
		addCapsule(plan, a.x, a.y, a.z, nx, ny, nz, tr, "tunnel")
		addEllipsoid(plan, nx, ny, nz, rr, math.max(2, rr * profile.chamberFlatten), rr * (0.8 + nextUnit(stream) * 0.4), "subChamber")
		addNode(plan, "subChamber", nx, ny, nz, rr)
	end

	-- Tight side tunnels wandering off to dead ends.
	local maxDrop = profile.verticality * MAX_SLOPE
	for _ = 1, nextInt(stream, category.SideTunnels) do
		local a = pickAnchor()
		local h = nextUnit(stream) * math.pi * 2
		local px, py, pz = a.x, a.y, a.z
		local tr = nextRange(stream, profile.tunnelRadius)
		local pieces = nextInt(stream, category.SideTunnelSegments)
		for i = 1, pieces do
			h += (nextUnit(stream) - 0.5) * math.rad(90)
			local len = nextRange(stream, category.SideTunnelLength)
			local nx = px + math.cos(h) * len
			local nz = pz + math.sin(h) * len
			nx, nz = clampExtent(plan, extent, nx, nz)
			local ny = clampY(py + (nextUnit(stream) - 0.5) * 2 * len * maxDrop, yLow, yHigh - tr)
			addCapsule(plan, px, py, pz, nx, ny, nz, tr, "tunnel")
			addNode(plan, if i == pieces then "deadEnd" else "tunnel", nx, ny, nz, tr)
			px, py, pz = nx, ny, nz
		end
	end

	-- An entrance ramp down to an epicentre, shallowest first, if a site can
	-- be found at the entrance slope inside the extent box.
	if nextUnit(stream) < profile.largeEntranceChance then
		table.sort(epic, function(a, b)
			return a.y + a.ry > b.y + b.ry
		end)

		local radius = nextRange(stream, profile.tunnelRadius)
		local baseHeading = nextUnit(stream) * math.pi * 2
		local placed = false

		for _, top in ipairs(epic) do
			local attachY = top.y + top.ry * 0.3
			for attempt = 0, 5 do
				local h = baseHeading + attempt * math.pi / 3
				-- Run estimated from the origin's surface; the slope is then
				-- checked against the surface actually at the site.
				local run = (surface - attachY) / ENTRANCE.MaxSlope
				local sx = math.floor(top.x + math.cos(h) * (run + top.r))
				local sz = math.floor(top.z + math.sin(h) * (run + top.r))
				local inside = math.abs(sx - plan.originX) <= extent and math.abs(sz - plan.originZ) <= extent

				if inside then
					local ok, siteHeight = entranceSiteOk(sx, sz)
					if ok then
						local dx, dz = sx + 0.5 - top.x, sz + 0.5 - top.z
						local horizontal = math.sqrt(dx * dx + dz * dz)
						local drop = siteHeight + 0.6 - attachY
						if drop > 0 and drop / math.max(1, horizontal) <= ENTRANCE.MaxSlope then
							-- Attach at the chamber wall rather than its centre.
							local ax = top.x + dx / horizontal * top.r * 0.6
							local az = top.z + dz / horizontal * top.r * 0.6
							addEntranceRamp(plan, stream, sx, sz, siteHeight, ax, attachY, az, radius)
							placed = true
							break
						end
					end
				end
			end
			if placed then
				break
			end
		end
	end

	return true
end

-- ---------------------------------------------------------------------------
-- Plan lookup
-- ---------------------------------------------------------------------------

local MAX_FREQUENCY = { CaveConfig.maxFrequency("Small"), CaveConfig.maxFrequency("Large") }

--[[
	The plan hosted by grid cell (gx, gz) of a category, or false. Cached.

	Rejections in cost order: the hash against the ceiling chance (no world
	sampling at all), then spawn and world-edge distance, then the origin
	column's biome and wetness.
]]
local function buildPlan(catIndex, gx, gz)
	local category = CATEGORIES[catIndex]
	local cell = category.CellBlocks
	local stream = { gx = gx, gz = gz, salt = catIndex * 1000, n = 0 }

	local roll = nextUnit(stream)
	if roll >= category.Chance * MAX_FREQUENCY[catIndex] then
		stats.plansRejectedChance += 1
		return false
	end

	local originX = gx * cell + math.floor(nextUnit(stream) * cell)
	local originZ = gz * cell + math.floor(nextUnit(stream) * cell)
	local extent = category.MaxExtentBlocks

	-- Nothing of the plan may reach the protected square around spawn.
	if math.max(math.abs(originX), math.abs(originZ)) < SPAWN_EXCLUSION + PLAN_REACH[catIndex] then
		stats.plansRejectedSpawn += 1
		return false
	end

	-- Nor past the coast: the border is sea, and sea has no dry caves.
	if math.max(math.abs(originX), math.abs(originZ)) > WORLD_RADIUS - extent - TerrainConfig.EdgeFalloffBlocks then
		stats.plansRejectedEdge += 1
		return false
	end

	local height, biome, water = sampler(originX, originZ)
	if water > height then
		stats.plansRejectedWet += 1
		return false
	end

	local profile = CaveConfig.profileFor(biome)
	local frequency = if catIndex == 1 then profile.smallFrequency else profile.largeFrequency
	if roll >= category.Chance * frequency then
		stats.plansRejectedChance += 1
		return false
	end

	local plan = newPlan(catIndex, gx, gz, originX, originZ, height, biome, profile)
	local ok = if catIndex == 1 then buildSmallPlan(plan, stream, category) else buildLargePlan(plan, stream, category)
	if not ok or plan.primCount == 0 then
		return false
	end

	finishPlan(plan)
	stats.plansBuilt += 1
	if catIndex == 1 then
		stats.plansSmall += 1
	else
		stats.plansLarge += 1
	end
	return plan
end

local function getPlan(catIndex, gx, gz)
	local key = planKeyOf(catIndex, gx, gz)
	local cached = cacheGet(planCache, key)
	if cached ~= nil then
		return cached
	end

	local plan = buildPlan(catIndex, gx, gz)
	cacheSet(planCache, key, plan)
	return plan
end

local function byKey(a, b)
	return a.key < b.key
end

-- Every plan whose box touches chunk (cx, cz), in a fixed order, capped.
local function collectPlans(cx, cz, out)
	local minX = cx * CHUNK_SIZE
	local minZ = cz * CHUNK_SIZE
	local maxX = minX + CHUNK_SIZE - 1
	local maxZ = minZ + CHUNK_SIZE - 1
	local count = 0

	for catIndex = 1, 2 do
		local cell = CATEGORIES[catIndex].CellBlocks
		local reach = PLAN_REACH[catIndex]
		local gxMin = math.floor((minX - reach) / cell)
		local gxMax = math.floor((maxX + reach) / cell)
		local gzMin = math.floor((minZ - reach) / cell)
		local gzMax = math.floor((maxZ + reach) / cell)

		for gx = gxMin, gxMax do
			for gz = gzMin, gzMax do
				local plan = getPlan(catIndex, gx, gz)
				if plan and plan.minX <= maxX and plan.maxX >= minX and plan.minZ <= maxZ and plan.maxZ >= minZ then
					count += 1
					out[count] = plan
				end
			end
		end
	end

	if count > 1 then
		table.sort(out, byKey)
	end
	if count > MAX_PLANS then
		for i = count, MAX_PLANS + 1, -1 do
			out[i] = nil
		end
		count = MAX_PLANS
	end
	return count
end

-- ---------------------------------------------------------------------------
-- Carving
-- ---------------------------------------------------------------------------

-- Scratch for one column: [by - FLOOR_Y + 1] -> true while marked.
local airMark = table.create(TerrainConfig.WorldCeilingY - FLOOR_Y + 2, false)
local scratchPlans = {}

--[[
	Carves one column against a plan list and writes its air intervals into
	`record` under `slot` (a cell index, or a halo index when `halo`). Returns
	the number of air blocks.

	Deliberately a top-level function with no closures: it runs 256 times per
	cave chunk and up to a few thousand block tests inside.
]]
local function carveColumn(x, z, plans, planCount, record, slot, halo)
	local height, _biome, water = sampler(x, z)
	local wet = water > height
	local coverTop = height - (if wet then COVER_WET else COVER) - 1
	if coverTop < FLOOR_LIMIT then
		return 0
	end

	local px, pz = x + 0.5, z + 0.5
	local markLo, markHi = math.huge, -math.huge
	local owner = nil
	local mouth = false

	for p = 1, planCount do
		local plan = plans[p]
		if x >= plan.minX and x <= plan.maxX and z >= plan.minZ and z <= plan.maxZ then
			local prims = plan.prims
			local roughness = plan.profile.roughness
			local amp = 1 + ROUGH_AMP * roughness

			for k = 1, plan.primCount do
				local prim = prims[k]
				if x >= prim.minX and x <= prim.maxX and z >= prim.minZ and z <= prim.maxZ then
					local hiLimit = coverTop
					-- Rows worth testing in this column, tightened below from
					-- the primitive's shape at this XZ rather than its whole box.
					local yLo, yHi = prim.minY, prim.maxY
					local inReach = true

					if prim.kind == CAPSULE then
						-- Where along the axis does the XZ disc of radius
						-- `reach` cover this column? Solve the quadratic in t;
						-- the axis height over that stretch, plus the radius,
						-- bounds the rows.
						local x0, z0 = prim.x0, prim.z0
						local dx, dz = prim.x1 - x0, prim.z1 - z0
						local ox, oz = px - x0, pz - z0
						local a = dx * dx + dz * dz
						local b = -2 * (ox * dx + oz * dz)
						local c = ox * ox + oz * oz - prim.reach * prim.reach
						local tMin, tMax = 0, 1
						if a > 1e-6 then
							local disc = b * b - 4 * a * c
							if disc < 0 then
								inReach = false
							else
								local root = math.sqrt(disc)
								tMin = (-b - root) / (2 * a)
								tMax = (-b + root) / (2 * a)
								if tMax < 0 or tMin > 1 then
									inReach = false
								else
									if tMin < 0 then tMin = 0 end
									if tMax > 1 then tMax = 1 end
								end
							end
						elseif c > 0 then
							inReach = false
						end

						if inReach then
							local dy = prim.y1 - prim.y0
							local ya, yb = prim.y0 + dy * tMin, prim.y0 + dy * tMax
							if ya > yb then ya, yb = yb, ya end
							yLo = math.floor(ya - prim.reach)
							yHi = math.ceil(yb + prim.reach)

							if prim.breaksSurface and (not wet or ALLOW_WET_ENTRANCE) then
								local mx, mz = px - x0, pz - z0
								if mx * mx + mz * mz <= prim.mouthReach2 then
									hiLimit = height - 1
									mouth = true
								end
							end
						end
					else
						local ex = (px - prim.cx) * prim.invRx
						local ez = (pz - prim.cz) * prim.invRz
						-- The box norm can only enlarge the shape; a disc at
						-- (1 + amp) still bounds the rounded one.
						local limit = amp + 0.05
						local exz2 = ex * ex + ez * ez
						if exz2 > limit * limit then
							inReach = false
						else
							local half = prim.ry * math.sqrt(limit * limit - exz2) + 0.5
							yLo = math.floor(prim.cy - half)
							yHi = math.ceil(prim.cy + half)
						end
					end

					if inReach then
						if yLo < FLOOR_LIMIT then yLo = FLOOR_LIMIT end
						if yHi > hiLimit then yHi = hiLimit end

						for by = yLo, yHi do
							if containsPoint(prim, px, by + 0.5, pz, roughness) then
								airMark[by - FLOOR_Y + 1] = true
								if by < markLo then markLo = by end
								if by > markHi then markHi = by end
								if owner == nil then owner = p end
							end
						end
					end
				end
			end
		end
	end

	if owner == nil then
		return 0
	end

	-- A mouth opens cleanly or not at all: if the ramp reached into the cover
	-- band here, the column is open to the sky rather than left with a crust
	-- one block thick over a pocket.
	if mouth and markHi > coverTop then
		for by = markHi + 1, height - 1 do
			airMark[by - FLOOR_Y + 1] = true
		end
		if height - 1 > markHi then
			markHi = height - 1
		end
	end

	-- Marks -> sorted contiguous intervals, clearing the scratch as we go.
	local intervals = {}
	local write = 0
	local blocks = 0
	local runStart = nil
	for by = markLo, markHi + 1 do
		local index = by - FLOOR_Y + 1
		local marked = by <= markHi and airMark[index]
		if marked then
			airMark[index] = false
			blocks += 1
			if runStart == nil then
				runStart = by
			end
		elseif runStart ~= nil then
			intervals[write + 1] = runStart
			intervals[write + 2] = by - 1
			write += 2
			runStart = nil
		end
	end

	if halo then
		record.halo[slot] = intervals
		record.haloOwner[slot] = owner
		return blocks
	end

	record.cells[slot] = intervals
	record.owner[slot] = owner
	record.low[slot] = markLo
	record.high[slot] = markHi
	record.count += 1
	record.blocks += blocks

	-- An interval reaching the top block is an opening: the column's surface
	-- drops to the bottom of that interval.
	if markHi == height - 1 then
		record.entrance[slot] = true
		record.surface[slot] = intervals[write - 1]
	end

	return blocks
end

--[[
	Builds a chunk's record. `onSlice`, when given, is called after each row
	of columns and may yield: the plan list is copied before carving and the
	column scratch is self-contained, so another chunk building in the
	meantime cannot disturb this one.
]]
local function buildRecord(cx, cz, onSlice)
	local plans = scratchPlans
	table.clear(plans)
	local planCount = collectPlans(cx, cz, plans)

	if planCount == 0 then
		stats.recordsEmpty += 1
		return EMPTY
	end

	local record = {
		cx = cx,
		cz = cz,
		plans = table.move(plans, 1, planCount, 1, {}),
		planCount = planCount,
		cells = {}, -- cell -> {lo, hi, lo, hi, ...}
		owner = {}, -- cell -> index into plans
		low = {}, -- cell -> lowest air y
		high = {}, -- cell -> highest air y
		surface = {}, -- cell -> lowered surface, entrance cells only
		entrance = {}, -- cell -> true
		halo = {}, -- haloIndex -> intervals, for the ring just outside
		haloOwner = {}, -- haloIndex -> index into plans
		count = 0,
		blocks = 0,
	}

	local minX = cx * CHUNK_SIZE
	local minZ = cz * CHUNK_SIZE
	for bx = 0, CHUNK_SIZE - 1 do
		for bz = 0, CHUNK_SIZE - 1 do
			carveColumn(minX + bx, minZ + bz, record.plans, planCount, record, bx * CHUNK_SIZE + bz + 1, false)
		end
		if onSlice then
			onSlice()
		end
	end

	stats.recordsBuilt += 1
	if record.count == 0 then
		stats.recordsEmpty += 1
		return EMPTY
	end

	-- The one-block ring outside, so wall restyling and border faces know
	-- about air in the neighbour without that neighbour existing yet.
	for i = 0, CHUNK_SIZE - 1 do
		carveColumn(minX - 1, minZ + i, record.plans, planCount, record, 0 * HALO_SIZE + (i + 1) + 1, true)
		carveColumn(minX + CHUNK_SIZE, minZ + i, record.plans, planCount, record, (CHUNK_SIZE + 1) * HALO_SIZE + (i + 1) + 1, true)
		carveColumn(minX + i, minZ - 1, record.plans, planCount, record, (i + 1) * HALO_SIZE + 0 + 1, true)
		carveColumn(minX + i, minZ + CHUNK_SIZE, record.plans, planCount, record, (i + 1) * HALO_SIZE + (CHUNK_SIZE + 1) + 1, true)
	end

	stats.carvedBlocks += record.blocks
	return record
end

--[[
	The carve record for a chunk. Cached; EMPTY (record.empty == true) for
	the great majority of chunks, which no plan reaches.
]]
function CaveMap.getRecord(cx, cz)
	if not isReady then
		return EMPTY
	end

	local key = chunkKeyOf(cx, cz)
	local record = cacheGet(recordCache, key)
	if record then
		return record
	end

	record = buildRecord(cx, cz)
	cacheSet(recordCache, key, record)
	return record
end

--[[
	getRecord for chunk generation: builds the record time-sliced, calling
	`onSlice` between rows so the generator can yield when the frame's budget
	is spent. Returns the record and whether it had to be built.
]]
function CaveMap.prepareRecord(cx, cz, onSlice)
	if not isReady then
		return EMPTY, false
	end

	local key = chunkKeyOf(cx, cz)
	local record = cacheGet(recordCache, key)
	if record then
		return record, false
	end

	record = buildRecord(cx, cz, onSlice)
	cacheSet(recordCache, key, record)
	return record, true
end

-- Uncached build, for validation of order independence. Not for the hot path.
function CaveMap._buildRecordUncached(cx, cz)
	return buildRecord(cx, cz)
end

--[[
	Air intervals for a column just OUTSIDE the record's chunk, and the index
	into record.plans of the plan that carved it: dx/dz are chunk-local with
	one of them -1 or ChunkSize. Used for wall restyling across the border.
]]
function CaveMap.haloIntervals(record, dx, dz)
	local slot = (dx + 1) * HALO_SIZE + (dz + 1) + 1
	return record.halo[slot], record.haloOwner[slot]
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

local function intervalsContain(intervals, by)
	for i = 1, #intervals, 2 do
		if by >= intervals[i] and by <= intervals[i + 1] then
			return true
		end
	end
	return false
end

CaveMap.intervalsContain = intervalsContain

function CaveMap.columnAir(blockX, blockZ)
	local record = CaveMap.getRecord(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE)
	if record.empty then
		return nil
	end
	return record.cells[(blockX % CHUNK_SIZE) * CHUNK_SIZE + (blockZ % CHUNK_SIZE) + 1]
end

function CaveMap.isAirAt(blockX, by, blockZ)
	local intervals = CaveMap.columnAir(blockX, blockZ)
	return intervals ~= nil and intervalsContain(intervals, by)
end

-- Any cave air within `depth` blocks below this column's surface?
function CaveMap.hasAirBelowSurface(blockX, blockZ, depth)
	local intervals = CaveMap.columnAir(blockX, blockZ)
	if not intervals then
		return false
	end
	local height = sampler(blockX, blockZ)
	return intervals[#intervals] >= height - depth
end

function CaveMap.isEntranceColumn(blockX, blockZ)
	local record = CaveMap.getRecord(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE)
	return not record.empty and record.entrance[(blockX % CHUNK_SIZE) * CHUNK_SIZE + (blockZ % CHUNK_SIZE) + 1] == true
end

-- The surface height after an entrance has opened this column, or nil.
function CaveMap.surfaceAt(blockX, blockZ)
	local record = CaveMap.getRecord(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE)
	if record.empty then
		return nil
	end
	return record.surface[(blockX % CHUNK_SIZE) * CHUNK_SIZE + (blockZ % CHUNK_SIZE) + 1]
end

local KIND_BY_TAG = {
	entrance = "entrance",
	epicentre = "chamber",
	room = "chamber",
	subChamber = "chamber",
	ledge = "ledge",
	passage = "tunnel",
	tunnel = "tunnel",
}

--[[
	What cave is this block in? nil when it is not cave air.

	  { plan, id, category, biome, kind, tag, depth, tags }

	kind is "entrance", "chamber", "ledge" or "tunnel"; tag is the primitive's
	own label (epicentre, room, subChamber, passage ...). Query path only:
	it re-evaluates the primitives at the point, and allocates.
]]
function CaveMap.describeAt(blockX, by, blockZ)
	local record = CaveMap.getRecord(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE)
	if record.empty then
		return nil
	end
	local cell = (blockX % CHUNK_SIZE) * CHUNK_SIZE + (blockZ % CHUNK_SIZE) + 1
	local intervals = record.cells[cell]
	if not intervals or not intervalsContain(intervals, by) then
		return nil
	end

	local px, py, pz = blockX + 0.5, by + 0.5, blockZ + 0.5
	local height = sampler(blockX, blockZ)

	-- Prefer the most specific primitive: chambers over the tunnels that
	-- enter them, entrances over everything.
	local best, bestRank = nil, -1
	for p = 1, record.planCount do
		local plan = record.plans[p]
		for k = 1, plan.primCount do
			local prim = plan.prims[k]
			if px >= prim.minX and px <= prim.maxX and pz >= prim.minZ and pz <= prim.maxZ
				and py >= prim.minY and py <= prim.maxY
				and containsPoint(prim, px, py, pz, plan.profile.roughness)
			then
				local rank = if prim.breaksSurface then 3 elseif prim.kind == ELLIPSOID then 2 else 1
				if rank > bestRank then
					best, bestRank = { plan = plan, prim = prim }, rank
				end
			end
		end
	end

	-- Clamping can leave air no primitive claims at the point; fall back to
	-- the column's owner.
	local plan = if best then best.plan else record.plans[record.owner[cell]]
	local tag = if best then best.prim.tag else "tunnel"

	return {
		plan = plan,
		id = plan.id,
		category = plan.category,
		biome = plan.biome,
		kind = KIND_BY_TAG[tag] or "tunnel",
		tag = tag,
		depth = height - by,
		tags = plan.profile.content.tags,
	}
end

function CaveMap.getPlansIntersectingChunk(cx, cz)
	return CaveMap.getRecord(cx, cz).plans
end

--[[
	Stable content candidates for a plan: one per node the walk laid down,
	seated on the actual carved floor of its column.

	  id              "<plan id>#<n>", stable for the seed
	  planId, category, biome, kind ("entrance" | "chamber" | "ledge" |
	                   "tunnel" | "junction" | "deadEnd" ...)
	  x, z            block column
	  y               the lowest air block: where something stands
	  floorY          the solid block under it
	  clearance       air blocks from floor to ceiling in that column
	  radius          the primitive's approximate radius
	  depth           blocks below the surface
	  floorSupported  true when there is a solid floor and room to stand
	  tags, content   from the biome profile

	Computed once per plan and kept on it. Placing nothing is the point:
	chests, pockets, props and spawns decide later what to do with these.
]]
function CaveMap.getCandidates(plan)
	if plan.candidates then
		return plan.candidates
	end

	local list = {}
	for index, node in ipairs(plan.nodes) do
		local x, z = math.floor(node.x), math.floor(node.z)
		local by = math.floor(node.y)
		local intervals = CaveMap.columnAir(x, z)
		local lo, hi = nil, nil

		if intervals then
			-- The interval holding the node, else the nearest one below it,
			-- else the lowest.
			for i = 1, #intervals, 2 do
				local a, b = intervals[i], intervals[i + 1]
				if by >= a and by <= b then
					lo, hi = a, b
					break
				elseif b < by then
					lo, hi = a, b
				end
			end
			if lo == nil then
				lo, hi = intervals[1], intervals[2]
			end
		end

		local height = sampler(x, z)
		local supported = lo ~= nil and (hi - lo + 1) >= 2 and lo - 1 >= FLOOR_LIMIT - 1
		list[#list + 1] = {
			id = string.format("%s#%d", plan.id, index),
			planId = plan.id,
			category = plan.category,
			biome = plan.biome,
			kind = node.kind,
			x = x,
			z = z,
			y = lo or by,
			floorY = if lo then lo - 1 else nil,
			clearance = if lo then hi - lo + 1 else 0,
			radius = node.radius,
			depth = height - (lo or by),
			floorSupported = supported,
			tags = plan.profile.content.tags,
			content = plan.profile.content,
		}
	end

	plan.candidates = list
	return list
end

-- Candidates whose column lies inside chunk (cx, cz), across every plan
-- that reaches it. For chunk-scoped future spawning.
function CaveMap.getCandidatesInChunk(cx, cz)
	local record = CaveMap.getRecord(cx, cz)
	local out = {}
	if record.empty then
		return out
	end
	local minX, minZ = cx * CHUNK_SIZE, cz * CHUNK_SIZE
	for p = 1, record.planCount do
		for _, candidate in ipairs(CaveMap.getCandidates(record.plans[p])) do
			if candidate.x >= minX and candidate.x < minX + CHUNK_SIZE and candidate.z >= minZ and candidate.z < minZ + CHUNK_SIZE then
				out[#out + 1] = candidate
			end
		end
	end
	return out
end

--[[
	The plan whose origin is nearest a point, within `radius` blocks, of one
	category or either. Walks grid cells, so a large radius costs plan builds.
]]
function CaveMap.findNearestPlan(blockX, blockZ, radius, category)
	local best, bestD2 = nil, math.huge
	local first, last = 1, 2
	if category then
		first = CATEGORY_INDEX[category]
		last = first
		if not first then
			return nil
		end
	end

	for catIndex = first, last do
		local cell = CATEGORIES[catIndex].CellBlocks
		for gx = math.floor((blockX - radius) / cell), math.floor((blockX + radius) / cell) do
			for gz = math.floor((blockZ - radius) / cell), math.floor((blockZ + radius) / cell) do
				local plan = getPlan(catIndex, gx, gz)
				if plan then
					local dx, dz = plan.originX - blockX, plan.originZ - blockZ
					local d2 = dx * dx + dz * dz
					if d2 < bestD2 and d2 <= radius * radius then
						best, bestD2 = plan, d2
					end
				end
			end
		end
	end
	return best
end

-- Every plan of a category across the whole world, for audits. Expensive:
-- samples one column per grid cell.
function CaveMap.forEachPlan(category, visit)
	local catIndex = CATEGORY_INDEX[category]
	local cell = CATEGORIES[catIndex].CellBlocks
	local cells = math.ceil(WORLD_RADIUS / cell)
	local visited = 0
	for gx = -cells, cells do
		for gz = -cells, cells do
			visited += 1
			local plan = getPlan(catIndex, gx, gz)
			if plan then
				visit(plan)
			end
		end
	end
	return visited
end

function CaveMap.getPlanAt(category, gx, gz)
	return getPlan(CATEGORY_INDEX[category], gx, gz)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--[[
	options = {
	  sampler   function(blockX, blockZ) -> height, biomeName, waterTop
	            waterTop at or below height means dry.
	  isInWorld function(blockX, blockZ) -> boolean
	}
]]
function CaveMap.init(seed, options)
	assert(type(options) == "table" and type(options.sampler) == "function", "[CaveMap] init needs options.sampler")
	assert(type(options.isInWorld) == "function", "[CaveMap] init needs options.isInWorld")

	CaveConfig.validate()

	activeSeed = seed or 0
	hashSeed = (activeSeed % 4096) * 2.0943951024
	sampler = options.sampler
	isInWorld = options.isInWorld

	-- Slides the roughness field through Perlin's lattice per seed.
	noiseOffX = hashUnit(1, 2, 3, 7) * 200
	noiseOffY = hashUnit(4, 5, 6, 7) * 200
	noiseOffZ = hashUnit(7, 8, 9, 7) * 200

	CaveMap.clearCaches()
	isReady = true
end

function CaveMap.clearCaches()
	cacheClear(planCache)
	cacheClear(recordCache)
end

function CaveMap.isReady()
	return isReady
end

function CaveMap.getStats()
	local out = table.clone(stats)
	out.seed = activeSeed
	out.planCacheSize = planCache.count
	out.recordCacheSize = recordCache.count
	out.floorLimit = FLOOR_LIMIT
	return out
end

CaveMap.FloorLimit = FLOOR_LIMIT
CaveMap.Categories = CATEGORY_NAMES

return CaveMap
