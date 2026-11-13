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

	SITES. Each category (Small, Large, Network, Colossal; see CaveConfig) cuts
	the world into a grid of cells. A cell hashes to decide whether it hosts a
	cave and, if so, where its origin is. The origin column's biome picks the
	profile, and a little more hashing fixes the cave's HUB: the point
	underground where it starts. A site is cheap - one column sample - and it
	is all another cave needs to know to tunnel across to this one.

	PLANS. From its site, a deterministic walk draws the cave as a list of
	PRIMITIVES in absolute coordinates:

	  capsule     a tunnel: two points and a radius at each (so it can taper)
	  ellipsoid   a room, chamber or cavern lobe, cut off flat at its floor

	Tunnels are walked a segment at a time: the bend carries over from one
	segment to the next so they swing rather than zig-zag, the height follows a
	target depth under the surface actually above each node, the radius drifts
	and now and then swells, and a stretch may wind into a spiral descent. An
	end never just stops: it joins another part of the cave, climbs out to a
	mouth, or opens into a pocket. Shafts join levels that pass over one
	another, and links tunnel across to neighbouring caves' hubs.

	Every chunk a plan reaches rebuilds the identical plan from the identical
	hash, which is what makes a tunnel continue across a border without the
	chunks ever talking. A plan has ONE biome, read at its origin, for its
	SHAPE; the rock it runs through, and what grows in it, are each column's
	own.

	CARVING. For a chunk, the plans in reach are gathered and their primitives
	filtered down to the ones whose box touches the chunk - a long network
	reaches hundreds of chunks and puts a tunnel through a few dozen of them,
	and the rest must cost nothing. Each column then tests only the primitives
	covering it, and only the rows inside the primitive's Y range. Roughness
	is a 3D noise WARP of the radius - the primitive is still one coherent
	shape, so there are no stray single-block pockets - and it is only sampled
	in the shell where it can change the answer: the inside of a great hall is
	marked without a single noise call. Each column clamps its air below the
	surface cover and above the bedrock margin, except under a deliberate
	entrance mouth. The result is one RECORD per chunk: per cell, a short list
	of contiguous air intervals. CaveDecor then seats the biome's decorations
	on the floors and ceilings, as cells left solid (record.decor).

	ENTRANCES are part of the plan: a sloped ramp from a validated surface
	site (dry, flat enough, far from spawn) down to a tunnel. Only the ramp
	near its mouth is allowed through the surface cover.

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
local CaveDecor = require(TerrainFolder:WaitForChild("CaveDecor"))
local TerrainGrid = require(TerrainFolder:WaitForChild("TerrainGrid"))

local CaveMap = {}

-- ---------------------------------------------------------------------------
-- Localised config
-- ---------------------------------------------------------------------------

local CHUNK_SIZE = TerrainConfig.ChunkSize
local HALO_SIZE = CHUNK_SIZE + 2
local FLOOR_Y = TerrainConfig.WorldFloorY
local WORLD_RADIUS = TerrainConfig.WorldRadiusBlocks
local EDGE_FALLOFF = TerrainConfig.EdgeFalloffBlocks

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
local MIN_RADIUS = ENTRANCE.MinRadius
local TUNNEL = CaveConfig.Tunnel
local SHAFT = CaveConfig.Shaft
local LINK = CaveConfig.Link
local FLOOR_CUT = CaveConfig.ChamberFloorCut
local ROOF_CUT = CaveConfig.ChamberRoofCut
local ROUGH_AMP = CaveConfig.RoughnessAmplitude
local INV_ROUGH_SCALE = 1 / CaveConfig.RoughnessScaleBlocks
local INV_CAVERN_SCALE = 1 / CaveConfig.CavernRoughnessScaleBlocks
local CURL = math.rad(TUNNEL.CurlDegrees)
local MAX_TURN = math.rad(TUNNEL.MaxTurnDegrees)

local CATEGORY_NAMES = CaveConfig.CategoryOrder
local CATEGORY_COUNT = #CATEGORY_NAMES
local CATEGORY_LETTER = { Small = "S", Large = "L", Network = "N", Colossal = "C" }
local CATEGORIES = {}
local CATEGORY_INDEX = {}
local FREQUENCY_FIELD = {}
local DEPTH_FIELD = {}
local CELL_CHANCE = {} -- Chance * DensityMultiplier, capped at 1
local SMALL, LARGE, NETWORK, COLOSSAL = 1, 2, 3, 4

-- Furthest any primitive can lie from its plan origin: the extent box, plus
-- the largest radius the category draws with its roughness, plus the little a
-- link's bow or a gallery stair may swing outside the box. Bounds the grid
-- search.
local PLAN_REACH = {}
-- Rock a category's hub needs between the cover and the bedrock margin.
local HUB_ROOM = {}

for index, name in ipairs(CATEGORY_NAMES) do
	local category = CaveConfig.Categories[name]
	CATEGORIES[index] = category
	CATEGORY_INDEX[name] = index
	FREQUENCY_FIELD[index] = CaveConfig.FrequencyField[name]
	DEPTH_FIELD[index] = CaveConfig.DepthField[name]
	CELL_CHANCE[index] = math.min(1, category.Chance * CaveConfig.DensityMultiplier)

	local widest = if name == "Colossal" then CaveConfig.MaxCavernRadius else CaveConfig.MaxChamberRadius
	PLAN_REACH[index] = category.MaxExtentBlocks + widest * (1 + ROUGH_AMP) + 24
	HUB_ROOM[index] = if name == "Colossal" then 28 elseif name == "Large" then CaveConfig.MaxChamberRadius * 1.5 else 8
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
local EMPTY = { empty = true, plans = {}, planCount = 0, prims = {}, primOwner = {}, primCount = 0,
	cells = {}, owner = {}, low = {}, high = {}, surface = {}, entrance = {}, biome = {}, ground = {},
	halo = {}, haloOwner = {}, decor = {}, decorCount = 0, raw = {}, count = 0, blocks = 0 }

local stats = {
	plansBuilt = 0,
	plansSmall = 0,
	plansLarge = 0,
	plansNetwork = 0,
	plansColossal = 0,
	plansRejectedChance = 0,
	plansRejectedSpawn = 0,
	plansRejectedEdge = 0,
	plansRejectedWet = 0,
	plansRejectedDepth = 0,
	entrancesPlanned = 0,
	loopsPlanned = 0,
	pocketsPlanned = 0,
	shaftsPlanned = 0,
	linksPlanned = 0,
	recordsBuilt = 0,
	recordsEmpty = 0,
	carvedBlocks = 0,
	decorations = 0,
	planCacheRotations = 0,
	recordCacheRotations = 0,
	siteCacheRotations = 0,
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
local siteCache = newCache(CaveConfig.SiteCacheLimit, "siteCacheRotations")

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

-- The same packing TerrainManager and ChunkEdits use.
local chunkKeyOf = TerrainGrid.chunkKey

local function planKeyOf(catIndex, gx, gz)
	return (catIndex * 65536 + (gx + 32768)) * 65536 + (gz + 32768)
end

-- ---------------------------------------------------------------------------
-- Primitives
-- ---------------------------------------------------------------------------

-- A tunnel from one point to another, r0 wide at the first and r1 at the
-- second.
local function addCapsule(plan, x0, y0, z0, x1, y1, z1, r0, r1, tag, breaksSurface)
	if plan.primCount >= MAX_PRIMS then
		return nil
	end

	local radius = if r0 > r1 then r0 else r1
	local rough = plan.profile.roughness
	local margin = radius * (1 + ROUGH_AMP * rough) + 1
	local prim = {
		kind = CAPSULE,
		x0 = x0, y0 = y0, z0 = z0,
		x1 = x1, y1 = y1, z1 = z1,
		r0 = r0,
		dr = r1 - r0,
		r = radius,
		reach = margin, -- XZ rejection distance
		rough = rough,
		inv = INV_ROUGH_SCALE,
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

--[[
	A room. `floorY`, when given, cuts the bottom off flat at that height (the
	floor then undulates a block either way, see carveColumn); `inv` is the
	roughness scale to warp it at.
]]
local function addEllipsoid(plan, cx, cy, cz, rx, ry, rz, tag, floorY, inv, roofY)
	if plan.primCount >= MAX_PRIMS then
		return nil
	end

	local roughness = plan.profile.roughness
	local rough = 1 + ROUGH_AMP * roughness
	local prim = {
		kind = ELLIPSOID,
		cx = cx, cy = cy, cz = cz,
		rx = rx, ry = ry, rz = rz,
		invRx = 1 / rx, invRy = 1 / ry, invRz = 1 / rz,
		angular = plan.profile.angularity,
		rough = roughness,
		inv = inv or INV_ROUGH_SCALE,
		floorRow = if floorY then math.ceil(floorY) else nil,
		roofRow = if roofY then math.floor(roofY) else nil,
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
	A room whose flat floor is at floorY: the ellipsoid's centre sits FLOOR_CUT
	of its vertical radius above that, so the floor is nearly as wide as the
	room. With `flatRoof` the top is cut off level too, ROOF_CUT above the
	centre - the big chambers and the cavern lobes, where a dome would be drawn
	as hundreds of thin rings and a level roof is a few large Parts.
]]
local function addChamber(plan, x, floorY, z, rx, ry, rz, tag, inv, flatRoof)
	local cy = floorY + ry * FLOOR_CUT
	return addEllipsoid(plan, x, cy, z, rx, ry, rz, tag, floorY, inv, if flatRoof then cy + ry * ROOF_CUT else nil)
end

--[[
	Is the block centre (px, py, pz) inside the primitive, roughness included?

	Roughness is only sampled in the shell where it can change the answer -
	well inside or well outside skips the noise entirely.
]]
local function containsPoint(prim, px, py, pz)
	local amp = ROUGH_AMP * prim.rough

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
		local r = prim.r0 + prim.dr * t

		if d <= r * (1 - amp) then
			return true
		elseif d > r * (1 + amp) then
			return false
		end
		local inv = prim.inv
		return d <= r * (1 + amp * Perlin:noise(px * inv + noiseOffX, py * inv + noiseOffY, pz * inv + noiseOffZ))
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
	local inv = prim.inv
	return d <= 1 + amp * Perlin:noise(px * inv + noiseOffX, py * inv + noiseOffY, pz * inv + noiseOffZ)
end

-- ---------------------------------------------------------------------------
-- Plan helpers
-- ---------------------------------------------------------------------------

local function newPlan(site)
	local catIndex = site.catIndex
	local name = CATEGORY_NAMES[catIndex]
	return {
		id = string.format("%s:%d:%d", CATEGORY_LETTER[name], site.gx, site.gz),
		key = site.key,
		category = name,
		catIndex = catIndex,
		gx = site.gx,
		gz = site.gz,
		originX = site.originX,
		originZ = site.originZ,
		originY = site.height,
		hubX = site.hubX,
		hubY = site.hubY,
		hubZ = site.hubZ,
		yLow = site.yLow,
		extent = CATEGORIES[catIndex].MaxExtentBlocks,
		biome = site.biome,
		profile = site.profile,
		prims = {},
		primCount = 0,
		-- Content candidate seeds: { kind, x, y, z, radius }. Every path node
		-- is one, and so are rooms, ledges and mouths.
		nodes = {},
		-- The tunnel graph: the nodes tunnels run between, which is what
		-- loops, shafts, branches and links attach to.
		path = {},
		walks = 0,
		length = 0, -- blocks of tunnel drawn
		entrance = nil, -- the first mouth, as { x, z, y }
		entrances = {},
		links = 0,
		shafts = 0,
		minX = math.huge, maxX = -math.huge,
		minZ = math.huge, maxZ = -math.huge,
		minY = math.huge, maxY = -math.huge,
		candidates = nil,
	}
end

local function addNode(plan, kind, x, y, z, radius)
	local node = { kind = kind, x = x, y = y, z = z, radius = radius }
	plan.nodes[#plan.nodes + 1] = node
	return node
end

-- A node tunnels can attach to. `heading` is the direction a tunnel arrived
-- from, when one did.
local function addPathNode(plan, kind, x, y, z, radius, walkId, heading)
	local node = addNode(plan, kind, x, y, z, radius)
	node.walk = walkId
	node.heading = heading
	local index = #plan.path + 1
	node.index = index
	plan.path[index] = node
	return node
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
local function clampExtent(plan, x, z)
	local extent = plan.extent
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
	May a plan put a tunnel node here? Inside its own box, outside the spawn
	square with room for the tunnel's width, and not out in the coastal
	falloff where the ground runs down into the sea.
]]
local function nodeOk(plan, x, z)
	local extent = plan.extent
	if math.abs(x - plan.originX) > extent or math.abs(z - plan.originZ) > extent then
		return false
	end
	local ax, az = math.abs(x), math.abs(z)
	local reach = if ax > az then ax else az
	return reach >= SPAWN_EXCLUSION + 10 and reach <= WORLD_RADIUS - EDGE_FALLOFF
end

--[[
	The highest a tunnel of this radius may be centred under a column: below
	the surface cover (thicker under water) with room for its own roof. Also
	returns the surface, which is what a tunnel's target depth is measured
	from - the ground actually above this node, not above the plan's origin,
	so a long cave dives under a valley instead of being cut off by it.
]]
local function ceilingAt(x, z, radius)
	local height, _biome, water = sampler(math.floor(x), math.floor(z))
	local cover = if water > height then COVER_WET else COVER
	return height - cover - 1 - radius * 0.85, height
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
	local dx, dz = tx - startX, tz - startZ
	local len = math.sqrt(dx * dx + dz * dz)
	local pieces = math.clamp(math.ceil(len / 13), 3, 8)
	local px, py, pz = startX, startY, startZ

	for i = 1, pieces do
		local f = i / pieces
		local nx = startX + dx * f
		local ny = startY + (ty - startY) * f
		local nz = startZ + dz * f

		if i < pieces and len > 0 then
			-- A sideways wobble so the ramp is not a ruler line.
			local wobble = (nextUnit(stream) - 0.5) * radius * 1.5
			nx += -dz / len * wobble
			nz += dx / len * wobble
		end

		addCapsule(plan, px, py, pz, nx, ny, nz, radius, radius, "entrance", i == 1)
		if i == 1 then
			-- The candidate sits at the end of the first piece: just inside
			-- the mouth, where the ramp has full headroom, rather than on the
			-- surface block itself.
			addNode(plan, "entrance", nx, ny, nz, radius)
		end
		px, py, pz = nx, ny, nz
	end

	local mouth = { x = sx, z = sz, y = surfaceHeight }
	plan.entrances[#plan.entrances + 1] = mouth
	if not plan.entrance then
		plan.entrance = mouth
	end
	plan.length += len
	stats.entrancesPlanned += 1
end

--[[
	Tries to give the point (tx, ty, tz) a way up to the surface: looks round
	it, at the distance the entrance slope needs, for a site a mouth may open
	at. Six directions, and the distance is corrected for the height the
	ground actually has there. Returns whether a ramp was added.
]]
local function tryEntrance(plan, stream, tx, ty, tz, radius, maxDepth)
	local surface = sampler(math.floor(tx), math.floor(tz))
	local depth = surface - ty
	local base = nextUnit(stream) * math.pi * 2
	if depth < 2 or depth > maxDepth or plan.primCount > MAX_PRIMS - 10 then
		return false
	end

	local slope = ENTRANCE.MaxSlope
	if radius < MIN_RADIUS then
		radius = MIN_RADIUS
	end

	for attempt = 0, 5 do
		local h = base + attempt * math.pi / 3
		local c, s = math.cos(h), math.sin(h)
		local run = math.max(8, depth / slope)

		for _ = 1, 3 do
			local sx, sz = math.floor(tx + c * run), math.floor(tz + s * run)
			if math.abs(sx - plan.originX) > plan.extent or math.abs(sz - plan.originZ) > plan.extent
				or not isInWorld(sx, sz)
			then
				break
			end

			local need = (sampler(sx, sz) + 0.6 - ty) / slope
			if need <= 0 then
				break
			end
			if math.abs(need - run) <= 3 then
				local ok, siteHeight = entranceSiteOk(sx, sz)
				if ok then
					addEntranceRamp(plan, stream, sx, sz, siteHeight, tx, ty, tz, radius)
					return true
				end
				break
			end
			run = math.max(8, need)
		end
	end

	return false
end

-- ---------------------------------------------------------------------------
-- Tunnels
-- ---------------------------------------------------------------------------

local function clampTunnel(profile, radius)
	local range = profile.tunnelRadius
	if radius < range.min then
		return range.min
	elseif radius > range.max then
		return range.max
	end
	return radius
end

-- What a category's tunnels are like in this profile. One table per plan.
local function tunnelOptions(category, profile)
	return {
		segLen = category.SegmentLength,
		slope = math.min(MAX_SLOPE, profile.verticality * category.SlopeScale * MAX_SLOPE),
		radius = profile.tunnelRadius,
		wide = profile.wideRadius,
		roomChance = category.RoomChance,
		spiralChance = category.SpiralChance,
		exitChance = profile.exitChance,
		-- How far a branch's target depth may differ from where it starts,
		-- and the band it must stay in.
		depthSwing = if category == CATEGORIES[SMALL] then 16 else 34,
		depthMin = profile.depth.small.min + 2,
		depthMax = profile.depth.networkEnd.max + 10,
		tag = "tunnel",
	}
end

-- A room on a tunnel: its floor is the tunnel's floor, so the tunnel walks
-- straight in, and its roof stays under `top`.
local function addRoom(plan, stream, x, y, z, radius, top)
	local profile = plan.profile
	local rr = nextRange(stream, profile.roomRadius)
	local rz = rr * (0.8 + nextUnit(stream) * 0.4)
	local floorY = y - radius
	local ry = math.max(2.4, rr * profile.chamberFlatten)
	local room = (top - floorY) / (1 + FLOOR_CUT)
	if ry > room then
		ry = math.max(2.2, room)
	end
	addChamber(plan, x, floorY, z, rr, ry, rz, "room")
	return rr
end

--[[
	Walks a tunnel `count` segments from a path node, adding a capsule and a
	path node per segment. Returns the last node reached (the starting node if
	it could not take a step).

	  heading   the way it sets off, radians
	  radius    how wide it starts
	  depthTo   how far below the surface it wants to be by the end; the
	            target eases there from the depth it starts at

	The bend (curl) is carried between segments, so the tunnel swings in long
	curves. Each node reads the surface above itself: the target depth and the
	ceiling are both measured from there. A spiral holds one hard bend and the
	steepest slope for a few segments - a helix down to a lower level, which
	addShafts then usually pierces with a shaft.
]]
local function walk(plan, stream, opts, from, heading, radius, count, walkId, depthTo)
	local x, y, z = from.x, from.y, from.z
	local depthFrom = sampler(math.floor(x), math.floor(z)) - y
	local yLow = plan.yLow
	local curl, spiral, spiralTurn = 0, 0, 0
	local widen, goal = 0, radius
	local depthBias = 0
	local sinceRoom = 2
	local last = from

	for i = 1, count do
		if plan.primCount >= MAX_PRIMS - 6 then
			break
		end
		local f = i / count

		if spiral > 0 then
			heading += spiralTurn
		else
			curl = curl * 0.55 + (nextUnit(stream) - 0.5) * 2 * CURL
			if curl > MAX_TURN then curl = MAX_TURN elseif curl < -MAX_TURN then curl = -MAX_TURN end
			heading += curl
			if count - i >= 4 and nextUnit(stream) < opts.spiralChance then
				spiral = nextInt(stream, TUNNEL.SpiralSegments)
				spiralTurn = math.rad(nextRange(stream, TUNNEL.SpiralTurnDegrees))
				if nextUnit(stream) < 0.5 then
					spiralTurn = -spiralTurn
				end
			end
		end

		local len = nextRange(stream, opts.segLen)
		if spiral > 0 then
			len *= 0.75
		end

		local nx = x + math.cos(heading) * len
		local nz = z + math.sin(heading) * len
		if not nodeOk(plan, nx, nz) then
			-- The edge of the box, the spawn square or the coast: turn back
			-- inward. Toward a point picked somewhere in the middle of the
			-- box rather than toward the origin itself - every tunnel that
			-- met an edge heading straight home made the hub the centre of
			-- a star of spokes.
			local half = plan.extent * 0.6
			local tx = plan.originX + 0.5 + (nextUnit(stream) - 0.5) * 2 * half
			local tz = plan.originZ + 0.5 + (nextUnit(stream) - 0.5) * 2 * half
			heading = math.atan2(tz - z, tx - x)
			curl, spiral = 0, 0
			nx = x + math.cos(heading) * len
			nz = z + math.sin(heading) * len
			if not nodeOk(plan, nx, nz) then
				break
			end
		end

		-- Width: drifts a little every segment, and now and then swells
		-- toward the wide band for a stretch, easing in and out.
		if widen > 0 then
			widen -= 1
			if widen == 0 then
				goal = nextRange(stream, opts.radius)
			end
		elseif nextUnit(stream) < TUNNEL.WidenChance then
			widen = nextInt(stream, TUNNEL.WidenSegments)
			goal = nextRange(stream, opts.wide)
		else
			goal = clampY(goal + (nextUnit(stream) - 0.5) * 0.5, opts.radius.min, opts.radius.max)
		end
		local nr = radius + (goal - radius) * 0.45
		if nr < MIN_RADIUS then
			nr = MIN_RADIUS
		end

		-- Height.
		local ceiling, surface = ceilingAt(nx, nz, nr)
		if ceiling < yLow + nr then
			break -- no rock to tunnel through under here
		end

		local dy
		if spiral > 0 then
			dy = -len * MAX_SLOPE * 0.9
			if y + dy < yLow + nr + 2 then
				spiral, dy = 0, 0
			else
				spiral -= 1
				depthBias -= dy
			end
		else
			local limit = len * opts.slope
			local target = surface - (depthFrom + (depthTo - depthFrom) * f + depthBias)
			dy = (target - y) * 0.25 + (nextUnit(stream) - 0.5) * limit * 0.6
			if dy > limit then dy = limit elseif dy < -limit then dy = -limit end
		end

		local ny = y + dy
		if ny > ceiling then
			ny = ceiling
		end
		if ny < yLow + nr then
			ny = yLow + nr
		end

		addCapsule(plan, x, y, z, nx, ny, nz, radius, nr, opts.tag)
		plan.length += len

		local kind = "tunnel"
		sinceRoom += 1
		if sinceRoom >= 3 and i < count and spiral == 0 and nextUnit(stream) < opts.roomChance then
			addRoom(plan, stream, nx, ny, nz, nr, ceiling + nr * 0.85)
			kind = "room"
			sinceRoom = 0
		end

		last = addPathNode(plan, kind, nx, ny, nz, nr, walkId, heading)
		x, y, z, radius = nx, ny, nz, nr
	end

	return last
end

--[[
	Finishes the end of a tunnel so it is not a blank wall:

	  1. a LOOP, if another part of the cave lies in reach at a walkable
	     slope - the end tunnels across and joins it;
	  2. a way OUT, if the end is shallow enough and a mouth can open nearby;
	  3. a POCKET - a rounded room a little wider than the tunnel.
]]
local function finishEnd(plan, stream, node, opts, host)
	if nextUnit(stream) < TUNNEL.LoopChance then
		local best, bestD2 = nil, TUNNEL.LoopReachBlocks * TUNNEL.LoopReachBlocks
		local index = node.index
		for j, other in ipairs(plan.path) do
			-- Not its own last few segments, and not the stretch of tunnel a
			-- branch has only just left: those would be knots, not loops.
			local own = other.walk == node.walk and math.abs(j - index) <= 6
			local nearHost = host ~= nil and (other == host
				or (other.walk == host.walk and math.abs(j - host.index) <= 3))
			if not own and not nearHost then
				local dx, dy, dz = other.x - node.x, other.y - node.y, other.z - node.z
				local d2 = dx * dx + dz * dz
				if d2 >= 25 and d2 < bestD2 and math.abs(dy) <= math.sqrt(d2) * MAX_SLOPE then
					best, bestD2 = other, d2
				end
			end
		end
		if best then
			local r0 = clampTunnel(plan.profile, node.radius)
			addCapsule(plan, node.x, node.y, node.z, best.x, best.y, best.z, r0, clampTunnel(plan.profile, best.radius), "tunnel")
			plan.length += math.sqrt(bestD2)
			if node.kind == "tunnel" then
				node.kind = "junction"
			end
			stats.loopsPlanned += 1
			return
		end
	end

	if #plan.entrances < 3 and nextUnit(stream) < opts.exitChance
		and tryEntrance(plan, stream, node.x, node.y, node.z, clampTunnel(plan.profile, node.radius), ENTRANCE.MaxDepthBlocks)
	then
		return
	end

	local rr = math.max(2.6, node.radius * nextRange(stream, TUNNEL.PocketRadius))
	local top = ceilingAt(node.x, node.z, 0)
	local floorY = node.y - node.radius
	local ry = math.min(math.max(2.2, rr * 0.8), math.max(2, (top - floorY) / (1 + FLOOR_CUT)))
	addChamber(plan, node.x, floorY, node.z, rr, ry, rr * (0.8 + nextUnit(stream) * 0.4), "pocket")
	node.kind = "deadEnd"
	stats.pocketsPlanned += 1
end

--[[
	Side tunnels. Each leaves one of `hosts` (path nodes) to one side, wanders
	off with a target depth of its own - some climb, some sink - and is
	finished like any other end. A branch may have one branch of its own.
]]
local function addBranches(plan, stream, category, opts, hosts, count, allowSub)
	local profile = plan.profile
	for _ = 1, count do
		if #hosts == 0 or plan.primCount >= MAX_PRIMS - 12 then
			break
		end

		local host = hosts[1 + math.floor(nextUnit(stream) * #hosts)]
		local side = nextUnit(stream)
		local swing = nextUnit(stream)
		local heading
		if host.heading then
			heading = host.heading + (if side < 0.5 then 1 else -1) * math.rad(50 + swing * 70)
		else
			heading = side * math.pi * 2
		end

		local depthNow = sampler(math.floor(host.x), math.floor(host.z)) - host.y
		local depthTo = clampY(depthNow + (nextUnit(stream) * 2 - 0.9) * opts.depthSwing, opts.depthMin, opts.depthMax)
		local radius = nextRange(stream, profile.tunnelRadius)
		local segments = nextInt(stream, category.BranchSegments)

		plan.walks += 1
		local first = #plan.path + 1
		local last = walk(plan, stream, opts, host, heading, radius, segments, plan.walks, depthTo)
		if last ~= host then
			if host.kind == "tunnel" then
				host.kind = "junction"
			end
			local lastIndex = #plan.path
			finishEnd(plan, stream, last, opts, host)

			if allowSub and lastIndex - first >= 3 and nextUnit(stream) < category.SubBranchChance then
				local sub = plan.path[first + math.floor(nextUnit(stream) * (lastIndex - first))]
				addBranches(plan, stream, category, opts, { sub }, 1, false)
			end
		end
	end
end

--[[
	Vertical passages: where two path nodes sit nearly above one another,
	further apart in height than any tunnel could climb in that distance, a
	steep shaft joins them. Both are already connected the long way round.
]]
local function addShafts(plan, stream, wanted)
	local path = plan.path
	local n = #path
	if wanted <= 0 or n < 8 then
		return
	end

	local maxOffset2 = SHAFT.MaxOffsetBlocks * SHAFT.MaxOffsetBlocks
	local start = math.floor(nextUnit(stream) * n)
	local made = 0

	for k = 0, n - 1 do
		if made >= wanted or plan.primCount >= MAX_PRIMS - 2 then
			break
		end
		local a = path[(start + k) % n + 1]
		if not a.shaft then
			for j = 1, n do
				local b = path[j]
				if not b.shaft and math.abs(b.index - a.index) > 4 then
					local drop = a.y - b.y
					if drop >= SHAFT.MinDropBlocks and drop <= SHAFT.MaxDropBlocks then
						local dx, dz = b.x - a.x, b.z - a.z
						local d2 = dx * dx + dz * dz
						if d2 <= maxOffset2 and drop > math.sqrt(d2) * MAX_SLOPE * 1.5 then
							local radius = nextRange(stream, SHAFT.Radius)
							addCapsule(plan, a.x, a.y, a.z, b.x, b.y, b.z, radius, radius, "shaft")
							a.shaft, b.shaft = true, true
							made += 1
							plan.shafts += 1
							stats.shaftsPlanned += 1
							break
						end
					end
				end
			end
		end
	end
end

-- Does the straight line between two points pass too near the spawn square?
local function crossesSpawn(x0, z0, x1, z1)
	local limit = SPAWN_EXCLUSION + 18
	for i = 0, 8 do
		local f = i / 8
		local ax, az = math.abs(x0 + (x1 - x0) * f), math.abs(z0 + (z1 - z0) * f)
		if (if ax > az then ax else az) < limit then
			return true
		end
	end
	return false
end

-- A bowed, wobbling tunnel from a path node to a fixed point.
local function tunnelTo(plan, stream, from, tx, ty, tz)
	local dx, dz = tx - from.x, tz - from.z
	local dist = math.sqrt(dx * dx + dz * dz)
	local pieces = math.max(2, math.ceil(dist / LINK.SegmentBlocks))
	if plan.primCount + pieces > MAX_PRIMS - 2 then
		return false
	end

	local sideX, sideZ = -dz / dist, dx / dist
	local profile = plan.profile
	local radius = clampTunnel(profile, from.radius)
	local bow = (nextUnit(stream) - 0.5) * 2 * math.min(dist * 0.18, 14)
	local heading = math.atan2(dz, dx)
	local x, y, z = from.x, from.y, from.z

	plan.walks += 1
	for i = 1, pieces do
		local f = i / pieces
		local nx, ny, nz, nr
		if i == pieces then
			nx, ny, nz = tx, ty, tz
			nr = radius
		else
			local off = math.sin(f * math.pi) * bow + (nextUnit(stream) - 0.5) * 5
			nx = from.x + dx * f + sideX * off
			nz = from.z + dz * f + sideZ * off
			nr = clampTunnel(profile, radius + (nextUnit(stream) - 0.5) * 0.5)
			ny = from.y + (ty - from.y) * f + (nextUnit(stream) - 0.5) * 3
			local ceiling = ceilingAt(nx, nz, nr)
			if ny > ceiling then
				ny = ceiling
			end
			if ny < plan.yLow + nr then
				ny = plan.yLow + nr
			end
		end

		addCapsule(plan, x, y, z, nx, ny, nz, radius, nr, "link")
		if i < pieces then
			addPathNode(plan, "tunnel", nx, ny, nz, nr, plan.walks, heading)
		end
		x, y, z, radius = nx, ny, nz, nr
	end

	plan.length += dist
	return true
end

local getSite -- defined under Sites; links ask about other cells' sites

-- Of the two caves `own` and `other` (plan keys), is `own` the one that
-- tunnels to the other? The same hash from either side, so exactly one is.
local function linksFrom(own, other)
	local low, high = own, other
	if low > high then
		low, high = high, low
	end
	local lowFirst = hashUnit(low % 65536, high % 65536, (low // 65536 + high // 65536) % 4096, 9001) < 0.5
	return (own == low) == lowFirst
end

local function byDistance(a, b)
	if a.d2 ~= b.d2 then
		return a.d2 < b.d2
	end
	return a.site.key < b.site.key
end

--[[
	Links: with the category's LinkChance, tunnels from this cave across to
	the hubs of up to MaxLinks others whose hubs lie in its extent box - the
	nearest first. The other cave always carves its own hub, so the tunnel
	always arrives somewhere; and only a site is asked for, never the other
	plan, so two caves that each reach for the other cannot recurse.
]]
local function addLinks(plan, stream, category)
	local roll = nextUnit(stream)
	local wanted = 1 + math.floor(nextUnit(stream) * category.MaxLinks)
	if roll >= category.LinkChance or #plan.path == 0 then
		return
	end

	local extent = plan.extent
	local found = {}
	for catIndex = 1, CATEGORY_COUNT do
		local cell = CATEGORIES[catIndex].CellBlocks
		for gx = math.floor((plan.originX - extent) / cell), math.floor((plan.originX + extent) / cell) do
			for gz = math.floor((plan.originZ - extent) / cell), math.floor((plan.originZ + extent) / cell) do
				if not (catIndex == plan.catIndex and gx == plan.gx and gz == plan.gz) then
					local site = getSite(catIndex, gx, gz)
					-- One tunnel per pair: of two caves that could each reach
					-- for the other, a hash of the pair picks which one does.
					if site and linksFrom(plan.key, site.key)
						and math.abs(site.hubX - plan.originX - 0.5) <= extent
						and math.abs(site.hubZ - plan.originZ - 0.5) <= extent
					then
						-- Our nearest tunnel node to that hub.
						local best, bestD2 = nil, math.huge
						for _, node in ipairs(plan.path) do
							local dx, dz = site.hubX - node.x, site.hubZ - node.z
							local d2 = dx * dx + dz * dz
							if d2 < bestD2 then
								best, bestD2 = node, d2
							end
						end
						found[#found + 1] = { site = site, node = best, d2 = bestD2 }
					end
				end
			end
		end
	end

	table.sort(found, byDistance)

	local made = 0
	for _, entry in ipairs(found) do
		if made >= wanted then
			break
		end
		local dist = math.sqrt(entry.d2)
		if dist > LINK.MaxBlocks then
			break -- sorted: every later one is further still
		end
		local site, node = entry.site, entry.node
		if dist >= LINK.MinBlocks
			and math.abs(site.hubY - node.y) <= dist * MAX_SLOPE * 0.85
			and not crossesSpawn(node.x, node.z, site.hubX, site.hubZ)
			and tunnelTo(plan, stream, node, site.hubX, site.hubY, site.hubZ)
		then
			made += 1
			plan.links += 1
			stats.linksPlanned += 1
		end
	end
end

-- The path nodes of one walk that a branch may leave from: everything
-- between its first node and its last.
local function interiorNodes(plan, first, last, into)
	for index = first + 1, last - 1 do
		into[#into + 1] = plan.path[index]
	end
	return into
end

-- ---------------------------------------------------------------------------
-- Small plans
-- ---------------------------------------------------------------------------

local function buildSmallPlan(plan, stream, category)
	local profile = plan.profile
	local opts = tunnelOptions(category, profile)

	local radius = nextRange(stream, profile.tunnelRadius)
	local heading = nextUnit(stream) * math.pi * 2
	local hub = addPathNode(plan, "tunnel", plan.hubX, plan.hubY, plan.hubZ, radius, 1, nil)
	plan.walks = 1

	-- A mouth, most of the time: the hub is shallow, so the ramp is short.
	if nextUnit(stream) < profile.entranceChance then
		tryEntrance(plan, stream, hub.x, hub.y, hub.z, radius, ENTRANCE.MaxDepthBlocks)
	end

	local depthTo = nextRange(stream, profile.depth.small)
	local segments = nextInt(stream, category.Segments)
	local last = walk(plan, stream, opts, hub, heading, radius, segments, 1, depthTo)
	if last == hub then
		return plan.primCount > 0
	end
	finishEnd(plan, stream, last, opts)

	local hosts = interiorNodes(plan, 1, last.index, {})
	addBranches(plan, stream, category, opts, hosts, nextInt(stream, category.Branches), true)
	addShafts(plan, stream, nextInt(stream, category.Shafts))
	addLinks(plan, stream, category)
	return true
end

-- ---------------------------------------------------------------------------
-- Network plans
-- ---------------------------------------------------------------------------

local function buildNetworkPlan(plan, stream, category)
	local profile = plan.profile
	local opts = tunnelOptions(category, profile)

	local radius = nextRange(stream, profile.tunnelRadius)
	local heading = nextUnit(stream) * math.pi * 2
	local hub = addPathNode(plan, "tunnel", plan.hubX, plan.hubY, plan.hubZ, radius, 1, nil)
	plan.walks = 1

	if nextUnit(stream) < profile.networkEntranceChance then
		tryEntrance(plan, stream, hub.x, hub.y, hub.z, radius, ENTRANCE.MaxDepthBlocks)
	end

	-- The main run: long, and sinking toward the deep band as it goes.
	local hosts = {}
	local segments = nextInt(stream, category.Segments)
	local last = walk(plan, stream, opts, hub, heading, radius, segments, 1, nextRange(stream, profile.depth.networkEnd))
	if last ~= hub then
		finishEnd(plan, stream, last, opts)
		interiorNodes(plan, 1, last.index, hosts)
	end

	-- Often it runs the other way from the hub too, so the hub is somewhere
	-- along the system rather than at one end of it.
	local twoWay = nextUnit(stream)
	local backHeading = heading + math.pi + (nextUnit(stream) - 0.5) * 1.2
	local backDepth = nextRange(stream, profile.depth.networkEnd)
	if twoWay < category.TwoWayChance then
		plan.walks += 1
		local first = #plan.path
		local back = walk(plan, stream, opts, hub, backHeading, radius, math.ceil(segments * 0.65), plan.walks, backDepth)
		if back ~= hub then
			finishEnd(plan, stream, back, opts)
			interiorNodes(plan, first, back.index, hosts)
		end
	end

	if plan.primCount == 0 then
		return false
	end

	addBranches(plan, stream, category, opts, hosts, nextInt(stream, category.Branches), true)
	addShafts(plan, stream, nextInt(stream, category.Shafts))
	addLinks(plan, stream, category)
	return true
end

-- ---------------------------------------------------------------------------
-- Large plans
-- ---------------------------------------------------------------------------

-- The floor a chamber of vertical radius `ry` can have under this column:
-- `wanted`, lowered until the roof clears the surface cover.
local function fitFloor(plan, x, z, wanted, ry)
	local top = ceilingAt(x, z, 0)
	local floorY = wanted
	if floorY + ry * (FLOOR_CUT + ROOF_CUT) > top then
		floorY = top - ry * (FLOOR_CUT + ROOF_CUT)
	end
	if floorY < plan.yLow then
		floorY = plan.yLow
	end
	return floorY
end

local function buildLargePlan(plan, stream, category)
	local profile = plan.profile
	local opts = tunnelOptions(category, profile)
	local yLow = plan.yLow

	-- Epicentres: a chain of chambers at different levels. Each is entered
	-- at its floor: `y` below is where a tunnel arrives.
	local count = nextInt(stream, category.Epicentres)
	local epic = {}
	local heading = nextUnit(stream) * math.pi * 2
	local cx, cz = plan.hubX, plan.hubZ
	local floorY = plan.hubY - 2

	for i = 1, count do
		local r = nextRange(stream, profile.chamberRadius)
		local ry = math.max(3, r * profile.chamberFlatten)
		local rz = r * (0.75 + nextUnit(stream) * 0.5)
		floorY = fitFloor(plan, cx, cz, floorY, ry)
		addChamber(plan, cx, floorY, cz, r, ry, rz, "epicentre", nil, true)

		local node = addPathNode(plan, "epicentre", cx, floorY + 2, cz, math.max(r, rz), 0, nil)
		node.chamberRadius = r
		node.depthBelow = sampler(math.floor(cx), math.floor(cz)) - node.y
		epic[i] = node

		-- Ledges: shelves cut high in the wall, with a floor of their own.
		for _ = 1, nextInt(stream, category.Ledges) do
			local a = nextUnit(stream) * math.pi * 2
			local lx = cx + math.cos(a) * r * 0.8
			local lz = cz + math.sin(a) * rz * 0.8
			local ledgeFloor = floorY + ry * (0.5 + nextUnit(stream) * 0.5)
			local lr = math.max(2.5, r * 0.45)
			addChamber(plan, lx, ledgeFloor, lz, lr, math.max(2.2, lr * 0.55), lr, "ledge")
			addNode(plan, "ledge", lx, ledgeFloor + 1, lz, lr)
		end

		if i < count then
			heading += (nextUnit(stream) - 0.5) * math.rad(120)
			local spacing = nextRange(stream, category.EpicentreSpacing)
			local nx = cx + math.cos(heading) * spacing
			local nz = cz + math.sin(heading) * spacing
			if not nodeOk(plan, nx, nz) then
				heading = math.atan2(plan.originZ + 0.5 - cz, plan.originX + 0.5 - cx)
				nx = cx + math.cos(heading) * spacing
				nz = cz + math.sin(heading) * spacing
				nx, nz = clampExtent(plan, nx, nz)
			end
			cx, cz = nx, nz
			floorY = math.max(yLow, floorY + (nextUnit(stream) - 0.5) * 2 * category.EpicentreLevelChange)
		end
	end

	-- Broad passages between consecutive chambers, bending and changing
	-- level a little, with a path node at every bend.
	local hosts = table.clone(epic)
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
		local along = math.atan2(dz, dx)

		for i = 1, pieces do
			local f = i / pieces
			local nx, ny, nz
			if i == pieces then
				nx, ny, nz = b.x, b.y, b.z
			else
				local side = (nextUnit(stream) - 0.5) * len * 0.4
				nx = a.x + dx * f + nxp * side
				nz = a.z + dz * f + nzp * side
				nx, nz = clampExtent(plan, nx, nz)
				local ceiling = ceilingAt(nx, nz, radius)
				ny = clampY(a.y + (b.y - a.y) * f + (nextUnit(stream) - 0.5) * 6, yLow + radius, math.max(yLow + radius, ceiling))
			end

			-- Bound the slope of each piece.
			local hx, hz = nx - px, nz - pz
			local horizontal = math.sqrt(hx * hx + hz * hz)
			local maxRise = math.max(1, horizontal) * MAX_SLOPE
			if i < pieces then
				if ny - py > maxRise then ny = py + maxRise elseif py - ny > maxRise then ny = py - maxRise end
			end

			local nr = radius * (0.9 + nextUnit(stream) * 0.2)
			addCapsule(plan, px, py, pz, nx, ny, nz, nr, nr, "passage")
			plan.length += horizontal
			if i < pieces then
				hosts[#hosts + 1] = addPathNode(plan, "passage", nx, ny, nz, radius, 0, along)
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

	-- Sub-chambers: a short tunnel out to a room.
	for _ = 1, nextInt(stream, category.SubChambers) do
		local a = hosts[1 + math.floor(nextUnit(stream) * #hosts)]
		local angle = nextUnit(stream) * math.pi * 2
		local len = 8 + nextUnit(stream) * 8 + (a.chamberRadius or 0)
		local tr = nextRange(stream, profile.tunnelRadius)
		local nx = a.x + math.cos(angle) * len
		local nz = a.z + math.sin(angle) * len
		nx, nz = clampExtent(plan, nx, nz)
		local ceiling = ceilingAt(nx, nz, tr)
		local ny = clampY(a.y + (nextUnit(stream) - 0.5) * 2 * 6 * profile.verticality, yLow + tr, math.max(yLow + tr, ceiling))
		addCapsule(plan, a.x, a.y, a.z, nx, ny, nz, tr, tr, "tunnel")
		plan.length += len
		local rr = addRoom(plan, stream, nx, ny, nz, tr, ceiling + tr * 0.85)
		addPathNode(plan, "subChamber", nx, ny, nz, rr, 0, angle)
	end

	-- Side tunnels wandering off, each finished as a loop, a way out or a
	-- pocket.
	addBranches(plan, stream, category, opts, hosts, nextInt(stream, category.Branches), true)

	-- A mouth, from the chamber nearest the surface that one can reach.
	if nextUnit(stream) < profile.largeEntranceChance then
		local order = table.clone(epic)
		table.sort(order, function(a, b)
			if a.depthBelow ~= b.depthBelow then
				return a.depthBelow < b.depthBelow
			end
			return a.index < b.index
		end)
		local radius = nextRange(stream, profile.tunnelRadius)
		for _, top in ipairs(order) do
			if tryEntrance(plan, stream, top.x, top.y, top.z, radius, ENTRANCE.MaxDepthBlocks * 1.8) then
				break
			end
		end
	end

	addShafts(plan, stream, nextInt(stream, category.Shafts))
	addLinks(plan, stream, category)
	return true
end

-- ---------------------------------------------------------------------------
-- Colossal plans
-- ---------------------------------------------------------------------------

--[[
	One enormous hall: a wandering line of big, low lobes that overlap into a
	single space, each with its own floor level and a broad ramp cut to the
	next. Galleries sit up on the walls, each with a stair tunnel that leaves
	the floor, climbs round behind the wall and comes out on the shelf.

	Feeders are what make it a discovery: long narrow tunnels leaving the rim
	of the hall, climbing toward the surface, branching, and sometimes coming
	out through a mouth - so the way in is a tight passage that suddenly opens.
]]
local function buildColossalPlan(plan, stream, category)
	local profile = plan.profile
	local opts = tunnelOptions(category, profile)
	local yLow = plan.yLow
	local maxRadius = CaveConfig.MaxCavernRadius

	local count = nextInt(stream, category.Lobes)
	local lobes = {}
	local hosts = {}
	local heading = nextUnit(stream) * math.pi * 2
	local cx, cz = plan.hubX, plan.hubZ
	local floorY = plan.hubY - 2

	for i = 1, count do
		local r = math.min(maxRadius, nextRange(stream, profile.cavernRadius) * (if i == 1 then 1 else 0.75 + nextUnit(stream) * 0.35))
		local rz = math.min(maxRadius, r * (0.7 + nextUnit(stream) * 0.5))
		local ry = math.max(7, r * profile.cavernFlatten * (0.85 + nextUnit(stream) * 0.3))
		floorY = fitFloor(plan, cx, cz, floorY, ry)
		addChamber(plan, cx, floorY, cz, r, ry, rz, "cavern", INV_CAVERN_SCALE, true)

		local node = addPathNode(plan, "cavern", cx, floorY + 2.5, cz, math.max(r, rz), 0, nil)
		lobes[i] = node

		-- A broad ramp down (or up) from the previous lobe's floor to this
		-- one's: where the floors step, this is the way between them.
		if i > 1 then
			local prev = lobes[i - 1]
			addCapsule(plan, prev.x, prev.y + 0.5, prev.z, cx, node.y + 0.5, cz, 3.4, 3.4, "passage")
		end

		-- Rim nodes: where feeders leave from, at floor level just inside
		-- the wall, pointing outward.
		for k = 1, 3 do
			local a = nextUnit(stream) * math.pi * 2
			local rim = addPathNode(plan, "tunnel", cx + math.cos(a) * r * 0.82, floorY + 2.2, cz + math.sin(a) * rz * 0.82, 2.2, 0, a)
			rim.rim = true
			hosts[#hosts + 1] = rim
			-- Rim nodes are attachment points, not content spots of their own.
			if k > 1 then
				rim.kind = "junction"
			end
		end

		-- Galleries.
		for _ = 1, nextInt(stream, category.Galleries) do
			local a = nextUnit(stream) * math.pi * 2
			local turn = if nextUnit(stream) < 0.5 then 1 else -1
			local lift = ry * (0.55 + nextUnit(stream) * 0.4)
			local gr = 4.5 + nextUnit(stream) * 3
			local gx, gz = cx + math.cos(a) * r * 0.92, cz + math.sin(a) * rz * 0.92
			local galleryFloor = floorY + lift
			addChamber(plan, gx, galleryFloor, gz, gr, math.max(2.6, gr * 0.6), gr, "gallery")
			addNode(plan, "ledge", gx, galleryFloor + 1, gz, gr)

			-- The stair: out through the wall at floor level a quarter turn
			-- along, round behind it, and up onto the shelf.
			local a0, a1 = a + turn * 0.85, a + turn * 0.42
			local sx, sz = cx + math.cos(a0) * r * 0.95, cz + math.sin(a0) * rz * 0.95
			local mx, mz = cx + math.cos(a1) * r * 1.22, cz + math.sin(a1) * rz * 1.22
			addCapsule(plan, sx, floorY + 2, sz, mx, floorY + 2 + lift * 0.5, mz, 2.1, 2.1, "tunnel")
			addCapsule(plan, mx, floorY + 2 + lift * 0.5, mz, gx, galleryFloor + 2, gz, 2.1, 2.1, "tunnel")
		end

		if i < count then
			heading += (nextUnit(stream) - 0.5) * math.rad(100)
			local spacing = r * nextRange(stream, category.LobeSpacing)
			local nx = cx + math.cos(heading) * spacing
			local nz = cz + math.sin(heading) * spacing
			if not nodeOk(plan, nx, nz) then
				heading = math.atan2(plan.originZ + 0.5 - cz, plan.originX + 0.5 - cx)
				nx = cx + math.cos(heading) * spacing
				nz = cz + math.sin(heading) * spacing
				nx, nz = clampExtent(plan, nx, nz)
			end
			cx, cz = nx, nz
			floorY = math.max(yLow, floorY + (nextUnit(stream) - 0.5) * 2 * category.LobeLevelChange)
		end
	end

	-- Feeders. They want to end far shallower than the hall, so they climb,
	-- and one that gets near the surface is keen to come out: a narrow mouth
	-- with a great hall at the bottom of it.
	opts.exitChance = math.max(opts.exitChance, category.FeederExitChance)
	opts.depthSwing = 0
	local feederDepth = profile.depth.network
	opts.depthMin = feederDepth.min
	opts.depthMax = feederDepth.max + 20
	local feeders = nextInt(stream, category.Branches)
	for _ = 1, feeders do
		if plan.primCount >= MAX_PRIMS - 24 then
			break
		end
		local host = hosts[1 + math.floor(nextUnit(stream) * #hosts)]
		local radius = nextRange(stream, profile.tunnelRadius)
		local depthTo = nextRange(stream, feederDepth) + nextUnit(stream) * 20
		local segments = nextInt(stream, category.BranchSegments)
		plan.walks += 1
		local first = #plan.path + 1
		local last = walk(plan, stream, opts, host, host.heading, radius, segments, plan.walks, depthTo)
		if last ~= host then
			local lastIndex = #plan.path
			finishEnd(plan, stream, last, opts, host)
			if lastIndex - first >= 3 and nextUnit(stream) < category.SubBranchChance then
				local sub = plan.path[first + math.floor(nextUnit(stream) * (lastIndex - first))]
				opts.depthSwing = 30
				addBranches(plan, stream, category, opts, { sub }, 1, false)
				opts.depthSwing = 0
			end
		end
	end

	addShafts(plan, stream, nextInt(stream, category.Shafts))
	addLinks(plan, stream, category)
	return true
end

-- ---------------------------------------------------------------------------
-- Sites and plan lookup
-- ---------------------------------------------------------------------------

local MAX_FREQUENCY = {}
for index, name in ipairs(CATEGORY_NAMES) do
	MAX_FREQUENCY[index] = CaveConfig.maxFrequency(name)
end

-- Draws a site consumes from the cell's stream; a plan's builder starts
-- after them, so the two never share a number.
local SITE_DRAWS = 8

--[[
	The site hosted by grid cell (gx, gz) of a category, or false: whether a
	cave starts here, where its origin is, which biome shapes it and where
	underground its hub lies. Cached.

	Rejections in cost order: the hash against the ceiling chance (no world
	sampling at all), then spawn and world-edge distance, then the origin
	column's biome, wetness and depth of rock.
]]
local function buildSite(catIndex, gx, gz)
	local category = CATEGORIES[catIndex]
	local cell = category.CellBlocks
	local stream = { gx = gx, gz = gz, salt = catIndex * 1000, n = 0 }

	local roll = nextUnit(stream)
	if roll >= CELL_CHANCE[catIndex] * MAX_FREQUENCY[catIndex] then
		stats.plansRejectedChance += 1
		return false
	end

	local originX = gx * cell + math.floor(nextUnit(stream) * cell)
	local originZ = gz * cell + math.floor(nextUnit(stream) * cell)
	local hubRoll = nextUnit(stream)
	local reach = math.max(math.abs(originX), math.abs(originZ))

	-- A cave starts clear of the protected square round spawn. Its tunnels
	-- may come up to the square's edge, never into it (nodeOk, carveColumn).
	if reach < SPAWN_EXCLUSION + CaveConfig.SpawnOriginMarginBlocks then
		stats.plansRejectedSpawn += 1
		return false
	end

	-- Nor out toward the coast: the border is sea, and sea has no dry caves.
	if reach > WORLD_RADIUS - EDGE_FALLOFF - 32 then
		stats.plansRejectedEdge += 1
		return false
	end

	local height, biome, water = sampler(originX, originZ)
	if water > height then
		stats.plansRejectedWet += 1
		return false
	end

	local profile = CaveConfig.profileFor(biome)
	if roll >= CELL_CHANCE[catIndex] * profile[FREQUENCY_FIELD[catIndex]] then
		stats.plansRejectedChance += 1
		return false
	end

	-- Everything below the surface cover, above the bedrock margin.
	local depth = profile.depth[DEPTH_FIELD[catIndex]]
	local yHigh = height - depth.min - 1
	local yLow = FLOOR_LIMIT + 3
	if yHigh - yLow < HUB_ROOM[catIndex] then
		stats.plansRejectedDepth += 1
		return false
	end

	local spread = math.min(category.HubDepthSpread, depth.max - depth.min)
	local hubY = clampY(height - depth.min - hubRoll * spread, yLow + HUB_ROOM[catIndex] * 0.5, yHigh)

	return {
		catIndex = catIndex,
		gx = gx,
		gz = gz,
		key = planKeyOf(catIndex, gx, gz),
		originX = originX,
		originZ = originZ,
		height = height,
		biome = biome,
		profile = profile,
		hubX = originX + 0.5,
		hubY = hubY,
		hubZ = originZ + 0.5,
		yLow = yLow,
	}
end

function getSite(catIndex, gx, gz)
	local key = planKeyOf(catIndex, gx, gz)
	local cached = cacheGet(siteCache, key)
	if cached ~= nil then
		return cached
	end

	local site = buildSite(catIndex, gx, gz)
	cacheSet(siteCache, key, site)
	return site
end

local BUILDERS = {
	[SMALL] = buildSmallPlan,
	[LARGE] = buildLargePlan,
	[NETWORK] = buildNetworkPlan,
	[COLOSSAL] = buildColossalPlan,
}
local PLAN_STAT = { "plansSmall", "plansLarge", "plansNetwork", "plansColossal" }

-- Plans walked so far (cache misses that had a site). collectPlans watches it
-- to know when a lookup did real work.
local planBuilds = 0

-- The plan hosted by grid cell (gx, gz) of a category, or false. Cached.
local function getPlan(catIndex, gx, gz)
	local key = planKeyOf(catIndex, gx, gz)
	local cached = cacheGet(planCache, key)
	if cached ~= nil then
		return cached
	end

	local plan = false
	local site = getSite(catIndex, gx, gz)
	if site then
		planBuilds += 1
		local built = newPlan(site)
		local stream = { gx = gx, gz = gz, salt = catIndex * 1000, n = SITE_DRAWS }
		if BUILDERS[catIndex](built, stream, CATEGORIES[catIndex]) and built.primCount > 0 then
			plan = finishPlan(built)
			stats.plansBuilt += 1
			stats[PLAN_STAT[catIndex]] += 1
		end
	end

	cacheSet(planCache, key, plan)
	return plan
end

local function byKey(a, b)
	return a.key < b.key
end

-- Every plan whose box touches chunk (cx, cz) or the one-block ring round
-- it, in a fixed order. `onSlice` is called after each plan that had to be
-- built rather than read from the cache, and may yield: walking into new
-- country means a dozen plans at once, and the longest are a few
-- milliseconds each.
local function collectPlans(cx, cz, out, onSlice)
	local minX = cx * CHUNK_SIZE - 1
	local minZ = cz * CHUNK_SIZE - 1
	local maxX = minX + CHUNK_SIZE + 1
	local maxZ = minZ + CHUNK_SIZE + 1
	local count = 0

	for catIndex = 1, CATEGORY_COUNT do
		local cell = CATEGORIES[catIndex].CellBlocks
		local reach = PLAN_REACH[catIndex]
		local gxMin = math.floor((minX - reach) / cell)
		local gxMax = math.floor((maxX + reach) / cell)
		local gzMin = math.floor((minZ - reach) / cell)
		local gzMax = math.floor((maxZ + reach) / cell)

		for gx = gxMin, gxMax do
			for gz = gzMin, gzMax do
				local before = planBuilds
				local plan = getPlan(catIndex, gx, gz)
				if plan and plan.minX <= maxX and plan.maxX >= minX and plan.minZ <= maxZ and plan.maxZ >= minZ then
					count += 1
					out[count] = plan
				end
				if onSlice and planBuilds ~= before then
					onSlice()
				end
			end
		end
	end

	if count > 1 then
		table.sort(out, byKey)
	end
	return count
end

-- ---------------------------------------------------------------------------
-- Carving
-- ---------------------------------------------------------------------------

-- Scratch for one column: [by - FLOOR_Y + 1] -> true while marked.
local airMark = table.create(TerrainConfig.WorldCeilingY - FLOOR_Y + 2, false)

--[[
	Carves one column against a chunk's primitives and writes its air
	intervals into `record` under `slot` (a cell index, or a halo index when
	`halo`). Returns the number of air blocks.

	Deliberately a top-level function with no closures: it runs 256 times per
	cave chunk and up to a few thousand block tests inside.
]]
local function carveColumn(x, z, prims, owners, primCount, record, slot, halo)
	-- Never inside the protected square round spawn, whatever a plan drew.
	local ax, az = if x < 0 then -x else x, if z < 0 then -z else z
	if (if ax > az then ax else az) <= SPAWN_EXCLUSION then
		return 0
	end

	local height, biome, water = sampler(x, z)
	local wet = water > height
	local coverTop = height - (if wet then COVER_WET else COVER) - 1
	if coverTop < FLOOR_LIMIT then
		return 0
	end

	local px, pz = x + 0.5, z + 0.5
	local markLo, markHi = math.huge, -math.huge
	local owner = nil
	local mouth = false

	for k = 1, primCount do
		local prim = prims[k]
		if x >= prim.minX and x <= prim.maxX and z >= prim.minZ and z <= prim.maxZ then
			local hiLimit = coverTop
			-- Rows worth testing in this column, tightened below from the
			-- primitive's shape at this XZ rather than its whole box; and
			-- inside those, the rows that are air whatever the roughness says.
			local yLo, yHi = prim.minY, prim.maxY
			local sureLo, sureHi = 1, 0
			local inReach = true

			if prim.kind == CAPSULE then
				-- Where along the axis does the XZ disc of radius `reach`
				-- cover this column? Solve the quadratic in t; the axis
				-- height over that stretch, plus the radius, bounds the rows.
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
				local amp = ROUGH_AMP * prim.rough
				local limit = 1 + amp + 0.05
				local exz2 = ex * ex + ez * ez
				if exz2 > limit * limit then
					inReach = false
				else
					local cy, ry = prim.cy, prim.ry
					local half = ry * math.sqrt(limit * limit - exz2) + 0.5
					yLo = math.floor(cy - half)
					yHi = math.ceil(cy + half)

					-- Inside (1 - amp) no roughness can close the block, and
					-- the box norm only ever opens more: those rows are air
					-- without asking. In a great hall that is nearly all of
					-- them.
					local inner = 1 - amp
					if exz2 < inner * inner then
						local sure = ry * math.sqrt(inner * inner - exz2) - 0.5
						sureLo = math.ceil(cy - sure - 0.5)
						sureHi = math.floor(cy + sure - 0.5)
					end

					-- The flat floor, and for the great chambers the flat roof,
					-- each stepping a block up or down in broad patches.
					local floorRow = prim.floorRow
					if floorRow then
						local n = Perlin:noise(px * 0.085 + noiseOffZ, floorRow * 0.31 + noiseOffY, pz * 0.085 + noiseOffX)
						floorRow += math.floor(n * 2 + 0.5)
						if yLo < floorRow then
							yLo = floorRow
						end
					end
					local roofRow = prim.roofRow
					if roofRow then
						local n = Perlin:noise(pz * 0.07 + noiseOffX, roofRow * 0.37 + noiseOffZ, px * 0.07 + noiseOffY)
						roofRow += math.floor(n * 2 + 0.5)
						if yHi > roofRow then
							yHi = roofRow
						end
					end
				end
			end

			if inReach then
				if yLo < FLOOR_LIMIT then yLo = FLOOR_LIMIT end
				if yHi > hiLimit then yHi = hiLimit end

				for by = yLo, yHi do
					if (by >= sureLo and by <= sureHi) or containsPoint(prim, px, by + 0.5, pz) then
						airMark[by - FLOOR_Y + 1] = true
						if by < markLo then markLo = by end
						if by > markHi then markHi = by end
						if owner == nil then owner = owners[k] end
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
	record.biome[slot] = biome
	record.ground[slot] = height
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
	of columns and may yield: the primitive list belongs to this record and
	the column scratch is self-contained, so another chunk building in the
	meantime cannot disturb this one.
]]
local function buildRecord(cx, cz, onSlice)
	local plans = {}
	local planCount = collectPlans(cx, cz, plans, onSlice)
	if planCount == 0 then
		stats.recordsEmpty += 1
		return EMPTY
	end

	--[[
		Down to the primitives whose box touches this chunk or the ring round
		it. A network's box covers hundreds of chunks and its tunnels cross a
		few dozen; every other chunk in the box drops it here, for the price
		of one pass over its primitives, instead of testing each of them
		against all 256 columns. The ring is included so the halo columns see
		exactly the primitives the neighbouring chunk sees for them.
	]]
	local minX = cx * CHUNK_SIZE
	local minZ = cz * CHUNK_SIZE
	local loX, hiX = minX - 1, minX + CHUNK_SIZE
	local loZ, hiZ = minZ - 1, minZ + CHUNK_SIZE

	local prims, owners, kept = {}, {}, {}
	local primCount, keptCount = 0, 0
	for p = 1, planCount do
		local plan = plans[p]
		local index = nil
		for k = 1, plan.primCount do
			local prim = plan.prims[k]
			if prim.minX <= hiX and prim.maxX >= loX and prim.minZ <= hiZ and prim.maxZ >= loZ then
				if index == nil then
					if keptCount >= MAX_PLANS then
						break
					end
					keptCount += 1
					kept[keptCount] = plan
					index = keptCount
				end
				primCount += 1
				prims[primCount] = prim
				owners[primCount] = index
			end
		end
	end

	if primCount == 0 then
		stats.recordsEmpty += 1
		return EMPTY
	end

	local record = {
		cx = cx,
		cz = cz,
		plans = kept, -- the plans that put something in or beside this chunk
		planCount = keptCount,
		prims = prims,
		primOwner = owners, -- prim index -> index into plans
		primCount = primCount,
		cells = {}, -- cell -> {lo, hi, lo, hi, ...}
		owner = {}, -- cell -> index into plans
		low = {}, -- cell -> lowest air y
		high = {}, -- cell -> highest air y
		biome = {}, -- cell -> the column's biome name
		ground = {}, -- cell -> the column's generated surface height
		surface = {}, -- cell -> lowered surface, entrance cells only
		entrance = {}, -- cell -> true
		halo = {}, -- haloIndex -> intervals, for the ring just outside
		haloOwner = {}, -- haloIndex -> index into plans
		-- Decorations, as flat (cell, by, type index) triples: cells CaveDecor
		-- left solid on a floor or ceiling. raw holds the intervals of any
		-- cell it changed, as carved. See CaveDecor.
		decor = {},
		decorCount = 0,
		raw = {},
		count = 0,
		blocks = 0,
	}

	for bx = 0, CHUNK_SIZE - 1 do
		for bz = 0, CHUNK_SIZE - 1 do
			carveColumn(minX + bx, minZ + bz, prims, owners, primCount, record, bx * CHUNK_SIZE + bz + 1, false)
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

	-- The one-block ring outside, so border walls and border faces know
	-- about air in the neighbour without that neighbour existing yet.
	for i = 0, CHUNK_SIZE - 1 do
		carveColumn(minX - 1, minZ + i, prims, owners, primCount, record, 0 * HALO_SIZE + (i + 1) + 1, true)
		carveColumn(minX + CHUNK_SIZE, minZ + i, prims, owners, primCount, record, (CHUNK_SIZE + 1) * HALO_SIZE + (i + 1) + 1, true)
		carveColumn(minX + i, minZ - 1, prims, owners, primCount, record, (i + 1) * HALO_SIZE + 0 + 1, true)
		carveColumn(minX + i, minZ + CHUNK_SIZE, prims, owners, primCount, record, (i + 1) * HALO_SIZE + (CHUNK_SIZE + 1) + 1, true)
	end

	stats.carvedBlocks += record.blocks
	stats.decorations += CaveDecor.decorate(record, minX, minZ)
	return record
end

--[[
	The carve record for a chunk. Cached; EMPTY (record.empty == true) for
	every chunk no tunnel reaches.
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

	-- Another generator may have built the same record during the yields;
	-- keep that one, so every reader holds the same table.
	local raced = cacheGet(recordCache, key)
	if raced then
		return raced, false
	end
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
	one of them -1 or ChunkSize. Used for what lines the wall across a border.
	As carved: the neighbour's decorations are not in it.
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
	if not intervals or #intervals == 0 then
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
	cavern = "chamber",
	room = "chamber",
	subChamber = "chamber",
	pocket = "chamber",
	ledge = "ledge",
	gallery = "ledge",
	shaft = "shaft",
	passage = "tunnel",
	link = "tunnel",
	tunnel = "tunnel",
}

--[[
	What cave is this block in? nil when it is not cave air.

	  { plan, id, category, biome, kind, tag, depth, tags }

	kind is "entrance", "chamber", "ledge", "shaft" or "tunnel"; tag is the
	primitive's own label (epicentre, cavern, room, pocket, passage, link ...).
	Query path only: it re-evaluates the primitives at the point, and
	allocates.
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
	local bestPrim, bestPlan, bestRank = nil, nil, -1
	for k = 1, record.primCount do
		local prim = record.prims[k]
		if px >= prim.minX and px <= prim.maxX and pz >= prim.minZ and pz <= prim.maxZ
			and py >= prim.minY and py <= prim.maxY
			and (prim.floorRow == nil or by >= prim.floorRow - 2)
			and (prim.roofRow == nil or by <= prim.roofRow + 2)
			and containsPoint(prim, px, py, pz)
		then
			local rank = if prim.breaksSurface then 3 elseif prim.kind == ELLIPSOID then 2 else 1
			if rank > bestRank then
				bestPrim, bestPlan, bestRank = prim, record.plans[record.primOwner[k]], rank
			end
		end
	end

	-- Clamping can leave air no primitive claims at the point; fall back to
	-- the column's owner.
	local plan = bestPlan or record.plans[record.owner[cell]]
	local tag = if bestPrim then bestPrim.tag else "tunnel"

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
	  planId, category, biome, kind ("entrance" | "epicentre" | "cavern" |
	                   "room" | "subChamber" | "ledge" | "tunnel" |
	                   "junction" | "passage" | "deadEnd")
	  x, z            block column
	  y               the lowest air block: where something stands
	  floorY          the solid block under it
	  clearance       air blocks from floor to ceiling in that column
	  radius          the primitive's approximate radius
	  depth           blocks below the surface
	  floorSupported  true when there is a solid floor and room to stand
	  tags, content   from the biome profile

	Computed once per plan and kept on it. Placing nothing is the point:
	chests, props and spawns decide later what to do with these.
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

		if intervals and #intervals > 0 then
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
	category or any. Walks grid cells by their sites (one column sample each)
	and only builds the plans it has to.
]]
function CaveMap.findNearestPlan(blockX, blockZ, radius, category)
	if not isReady then
		return nil
	end

	local first, last = 1, CATEGORY_COUNT
	if category then
		first = CATEGORY_INDEX[category]
		last = first
		if not first then
			return nil
		end
	end

	local found = {}
	for catIndex = first, last do
		local cell = CATEGORIES[catIndex].CellBlocks
		for gx = math.floor((blockX - radius) / cell), math.floor((blockX + radius) / cell) do
			for gz = math.floor((blockZ - radius) / cell), math.floor((blockZ + radius) / cell) do
				local site = getSite(catIndex, gx, gz)
				if site then
					local dx, dz = site.originX - blockX, site.originZ - blockZ
					local d2 = dx * dx + dz * dz
					if d2 <= radius * radius then
						found[#found + 1] = { site = site, d2 = d2 }
					end
				end
			end
		end
	end

	-- A site whose walk could not take a step has no plan; try the next.
	table.sort(found, byDistance)
	for _, entry in ipairs(found) do
		local site = entry.site
		local plan = getPlan(site.catIndex, site.gx, site.gz)
		if plan then
			return plan
		end
	end
	return nil
end

-- Every plan of a category across the whole world, for audits. Expensive:
-- builds every plan there is. `onProgress`, when given, is called every few
-- hundred cells and may yield.
function CaveMap.forEachPlan(category, visit, onProgress)
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
			if onProgress and visited % 256 == 0 then
				onProgress()
			end
		end
	end
	return visited
end

function CaveMap.getPlanAt(category, gx, gz)
	return getPlan(CATEGORY_INDEX[category], gx, gz)
end

-- How far from its origin a plan of this category may reach, in blocks.
function CaveMap.planReach(category)
	return PLAN_REACH[CATEGORY_INDEX[category]]
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

	-- Registers the decoration blocks, so it has to come before the terrain
	-- builds its block templates.
	CaveDecor.init(activeSeed)

	CaveMap.clearCaches()
	isReady = true
end

function CaveMap.clearCaches()
	cacheClear(planCache)
	cacheClear(recordCache)
	cacheClear(siteCache)
end

-- Drops the carve records only, keeping the plans they are carved from. For
-- the audit, which re-carves chunks in different orders.
function CaveMap.clearRecords()
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
	out.siteCacheSize = siteCache.count
	out.floorLimit = FLOOR_LIMIT
	return out
end

CaveMap.FloorLimit = FLOOR_LIMIT
CaveMap.Categories = CATEGORY_NAMES

return CaveMap
