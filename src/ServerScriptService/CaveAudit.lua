--[[
	CaveAudit

	Deterministic checks of the cave generator against its own rules, on the
	running world's seed. Read-only: it builds plans and carve records through
	CaveMap and inspects them; it never touches chunk data.

		local report = CaveAudit.run()            -- the pure checks
		CaveAudit.printReport(report)             -- to Output
		CaveAudit.summarise(report)               -- one line for a player
		CaveAudit.describe(worldPosition)         -- what cave is here, if any
		CaveAudit.editRoundTrip(player)           -- live check, needs a cave

	In game the owner types /bbcaves (see DebugConsole). From the Studio
	command bar, with a server running:

		require(game.ServerScriptService.CaveAudit).printReport()

	WHAT IT CHECKS

	  determinism      the same chunk carved twice, caches dropped between,
	                   gives identical intervals
	  order            a chunk carved on its own matches the same chunk carved
	                   after its neighbours, so load order cannot cut a cave off
	  borders          air on either side of a chunk border continues: a
	                   column's intervals equal what the neighbouring record's
	                   halo says about it
	  spawn            no cave air and no entrance inside the protected square
	  thickness        every interval sits under the surface cover (unless its
	                   column is a deliberate entrance) and above the bedrock
	                   margin; no entrance in a wet column
	  categories       every kind of cave occurs; large and colossal ones are
	                   rarer than small ones by at least the configured ratios;
	                   counts, mean tunnel length, mouths, links and shafts are
	                   reported per category, and counts per biome
	  bounds           no plan exceeds its primitive cap or its reach
	  decor            every decoration is a solid cell on a cave floor or
	                   under a cave ceiling, with headroom left beside it
	  connectivity     from a sample cave's hub, the air it carved reaches its
	                   tunnel nodes: nothing pinched a passage shut
	  plainCost        a block of chunks nothing carves resolves quickly

	The one thing it cannot do from here is play: editRoundTrip stands in for
	that, and the Studio checklist in the session report covers the rest.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TerrainFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Terrain")
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))
local CaveConfig = require(TerrainFolder:WaitForChild("CaveConfig"))
local CaveMap = require(TerrainFolder:WaitForChild("CaveMap"))
local CaveDecorConfig = require(TerrainFolder:WaitForChild("CaveDecorConfig"))

local CaveAudit = {}

local CHUNK = TerrainConfig.ChunkSize
local STUD = TerrainConfig.StudSize

-- Large plans must be at least this many times rarer than small ones, and
-- colossal ones rarer again: the great halls are meant to be discoveries.
CaveAudit.MinSmallToLargeRatio = 4
CaveAudit.MinSmallToColossalRatio = 12

-- Share of a sample cave's tunnel nodes that must be reachable through its
-- own air from its hub.
CaveAudit.MinReachableNodes = 0.85

-- How many of a sample cave's carved chunks are rebuilt and compared.
CaveAudit.SampleChunksPerPlan = 30

local CATEGORIES = CaveMap.Categories

local function newReport()
	return { checks = {}, errors = 0, warnings = 0, seed = CaveMap.getStats().seed }
end

local function check(report, name, ok, detail, severity)
	local entry = { name = name, ok = ok, detail = detail or "", severity = severity or "error" }
	table.insert(report.checks, entry)
	if not ok then
		if entry.severity == "warning" then
			report.warnings += 1
		else
			report.errors += 1
		end
	end
	return ok
end

local function sameIntervals(a, b)
	if a == nil or b == nil then
		return a == b
	end
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function sameRecords(a, b)
	if a.empty ~= b.empty then
		return false, "one empty"
	end
	if a.empty then
		return true
	end
	if a.count ~= b.count or a.blocks ~= b.blocks then
		return false, string.format("count %d/%d blocks %d/%d", a.count, b.count, a.blocks, b.blocks)
	end
	if a.decorCount ~= b.decorCount then
		return false, string.format("decorations %d/%d", a.decorCount, b.decorCount)
	end
	for i = 1, a.decorCount * 3 do
		if a.decor[i] ~= b.decor[i] then
			return false, "decoration " .. ((i - 1) // 3 + 1)
		end
	end
	for cell, intervals in pairs(a.cells) do
		if not sameIntervals(intervals, b.cells[cell]) then
			return false, "cell " .. cell
		end
		if a.entrance[cell] ~= b.entrance[cell] or a.surface[cell] ~= b.surface[cell] then
			return false, "entrance at cell " .. cell
		end
	end
	for cell in pairs(b.cells) do
		if a.cells[cell] == nil then
			return false, "extra cell " .. cell
		end
	end
	return true
end

-- The chunks a plan touches, as a list of {cx, cz}.
local function chunksOf(plan)
	local list = {}
	for cx = plan.minX // CHUNK, plan.maxX // CHUNK do
		for cz = plan.minZ // CHUNK, plan.maxZ // CHUNK do
			list[#list + 1] = { cx, cz }
		end
	end
	return list
end

-- The nearest plan of each category to the origin, to have something real
-- to carve.
local function samplePlans()
	local plans = {}
	for _, category in ipairs(CATEGORIES) do
		local plan = CaveMap.findNearestPlan(0, 0, 4000, category)
		if plan then
			plans[#plans + 1] = plan
		end
	end
	return plans
end

--[[
	How much of a plan can be walked into: floods the air the plan's chunks
	carved, six ways, from the hub, and counts the plan's tunnel nodes whose
	block (or the one above or below it) the flood reached. Not a test of
	slopes - only that no passage was pinched shut on the way.
]]
local function reachableNodes(plan)
	local function key(x, y, z)
		return ((x + 65536) * 131072 + (z + 65536)) * 1024 + (y - TerrainConfig.WorldFloorY)
	end

	local seen = {}
	local queue = {}
	local head, tail = 1, 0
	local function push(x, y, z)
		local k = key(x, y, z)
		if not seen[k] and CaveMap.isAirAt(x, y, z) then
			seen[k] = true
			tail += 3
			queue[tail - 2], queue[tail - 1], queue[tail] = x, y, z
		end
	end

	-- Start in the hub's column, at whatever air is nearest the hub's height.
	local hx, hz = math.floor(plan.hubX), math.floor(plan.hubZ)
	for dy = 0, 6 do
		push(hx, math.floor(plan.hubY) + dy, hz)
		push(hx, math.floor(plan.hubY) - dy, hz)
		if tail > 0 then
			break
		end
	end

	local steps = 0
	while head <= tail do
		local x, y, z = queue[head], queue[head + 1], queue[head + 2]
		head += 3
		push(x + 1, y, z)
		push(x - 1, y, z)
		push(x, y + 1, z)
		push(x, y - 1, z)
		push(x, y, z + 1)
		push(x, y, z - 1)
		steps += 1
		if steps % 4000 == 0 then
			task.wait()
		end
		if steps > 400000 then
			break -- joined a neighbour's system; far enough to judge this one
		end
	end

	local reached, total = 0, 0
	for _, node in ipairs(plan.path) do
		total += 1
		local x, y, z = math.floor(node.x), math.floor(node.y), math.floor(node.z)
		if seen[key(x, y, z)] or seen[key(x, y + 1, z)] or seen[key(x, y - 1, z)]
			or seen[key(x, y + 2, z)] or seen[key(x, y - 2, z)]
		then
			reached += 1
		end
	end
	return reached, total, steps
end

--[[
	Runs every pure check. `sampler(blockX, blockZ) -> height, biome, water`
	is optional; without it the thickness check reads heights through
	TerrainManager when that module is present, else it is skipped.
]]
function CaveAudit.run(options)
	options = options or {}
	local report = newReport()
	local startedAt = os.clock()

	if not CaveMap.isReady() then
		check(report, "ready", false, "CaveMap.init has not run (caves disabled in this place?)")
		return report
	end

	local sampler = options.sampler
	if not sampler then
		local TerrainManager = ServerScriptService:FindFirstChild("TerrainManager")
		if TerrainManager then
			local tm = require(TerrainManager)
			sampler = function(blockX, blockZ)
				local y, biome = tm:GetSurfaceY(blockX * STUD, blockZ * STUD)
				return if y then y / STUD else 0, biome, TerrainConfig.WorldFloorY
			end
		end
	end

	-- ---- categories, rarity, bounds ------------------------------------
	local counts, withMouth, mouths, length, links, shafts, prims, byBiome = {}, {}, {}, {}, {}, {}, {}, {}
	local boundsOk, boundsDetail = true, ""
	local scanned = 0

	for _, category in ipairs(CATEGORIES) do
		counts[category], withMouth[category], mouths[category] = 0, 0, 0
		length[category], links[category], shafts[category], prims[category] = 0, 0, 0, 0
		byBiome[category] = {}

		local reach = CaveMap.planReach(category)
		scanned += CaveMap.forEachPlan(category, function(plan)
			counts[category] += 1
			if plan.entrance then
				withMouth[category] += 1
			end
			mouths[category] += #plan.entrances
			length[category] += plan.length
			links[category] += plan.links
			shafts[category] += plan.shafts
			prims[category] = math.max(prims[category], plan.primCount)
			byBiome[category][plan.biome] = (byBiome[category][plan.biome] or 0) + 1

			if plan.primCount > CaveConfig.MaxPrimitivesPerPlan then
				boundsOk, boundsDetail = false, plan.id .. " has " .. plan.primCount .. " primitives"
			end
			if plan.minX < plan.originX - reach or plan.maxX > plan.originX + reach + 1
				or plan.minZ < plan.originZ - reach or plan.maxZ > plan.originZ + reach + 1
			then
				boundsOk, boundsDetail = false, plan.id .. " exceeds its reach"
			end
			for _, node in ipairs(plan.nodes) do
				if node.kind == "entrance" then
					local d = math.sqrt(node.x * node.x + node.z * node.z)
					if d < CaveConfig.EntranceSafeDistanceBlocks - 8 then
						boundsOk, boundsDetail = false, plan.id .. " entrance inside the safe distance"
					end
				end
			end
		end, task.wait)
	end

	for _, category in ipairs(CATEGORIES) do
		local n = math.max(1, counts[category])
		check(report, "categories." .. string.lower(category), counts[category] > 0, string.format(
			"%d plans; %d with a mouth (%d mouths); mean %.0f blocks of tunnel; %d links, %d shafts; most primitives %d",
			counts[category], withMouth[category], mouths[category], length[category] / n,
			links[category], shafts[category], prims[category]
		))
	end
	check(report, "categories.cells", true, string.format("%d grid cells scanned", scanned))
	check(report, "categories.largeRarity", counts.Large > 0 and counts.Small / counts.Large >= CaveAudit.MinSmallToLargeRatio,
		string.format("small:large = %d:%d", counts.Small, counts.Large))
	check(report, "categories.colossalRarity",
		counts.Colossal > 0 and counts.Small / counts.Colossal >= CaveAudit.MinSmallToColossalRatio,
		string.format("small:colossal = %d:%d", counts.Small, counts.Colossal))
	check(report, "categories.entrances",
		withMouth.Small > 0 and withMouth.Small < counts.Small and withMouth.Network > 0 and withMouth.Network < counts.Network,
		"some small and network caves open to the surface and some are hidden", "warning")
	check(report, "categories.linked", links.Network > 0 and links.Network < counts.Network * CaveConfig.Categories.Network.MaxLinks,
		"some caves are linked into systems and some are not", "warning")
	check(report, "bounds", boundsOk, boundsDetail)

	for _, category in ipairs(CATEGORIES) do
		local parts = {}
		for biome, n in pairs(byBiome[category]) do
			parts[#parts + 1] = biome .. "=" .. n
		end
		table.sort(parts)
		check(report, "categories." .. string.lower(category) .. "ByBiome", true, table.concat(parts, " "))
	end

	-- ---- spawn protection --------------------------------------------------
	local spawnChunks = math.ceil(CaveConfig.SpawnExclusionBlocks / CHUNK)
	local spawnAir, spawnEntrances = 0, 0
	for cx = -spawnChunks, spawnChunks do
		for cz = -spawnChunks, spawnChunks do
			local record = CaveMap.getRecord(cx, cz)
			if not record.empty then
				for cell in pairs(record.cells) do
					local index = cell - 1
					local x, z = cx * CHUNK + index // CHUNK, cz * CHUNK + index % CHUNK
					if math.max(math.abs(x), math.abs(z)) <= CaveConfig.SpawnExclusionBlocks then
						spawnAir += 1
						if record.entrance[cell] then
							spawnEntrances += 1
						end
					end
				end
			end
		end
	end
	check(report, "spawn.noAir", spawnAir == 0, string.format("%d cave columns inside the exclusion square", spawnAir))
	check(report, "spawn.noEntrances", spawnEntrances == 0, string.format("%d entrance columns inside it", spawnEntrances))

	-- ---- determinism, order independence, borders, thickness, decor -----
	local plans = samplePlans()
	local sampled = {}
	for _, plan in ipairs(plans) do
		sampled[#sampled + 1] = plan.id
	end
	check(report, "sample.plans", #plans == #CATEGORIES, "nearest of each kind: " .. table.concat(sampled, ", "), "warning")

	local deterministic, detDetail = true, ""
	local orderOk, orderDetail = true, ""
	local borderOk, borderDetail = true, ""
	local coverOk, coverDetail = true, ""
	local floorOk, floorDetail = true, ""
	local wetOk, wetDetail = true, ""
	local decorOk, decorDetail = true, ""
	local carvedCells, carvedBlocks, chunksChecked, decorChecked = 0, 0, 0, 0

	for _, plan in ipairs(plans) do
		-- The chunks the plan actually carves, thinned to a few dozen: a
		-- network's box is hundreds of chunks and most hold none of it.
		local carvedChunks = {}
		for index, c in ipairs(chunksOf(plan)) do
			if not CaveMap.getRecord(c[1], c[2]).empty then
				carvedChunks[#carvedChunks + 1] = c
			end
			if index % 64 == 0 then
				task.wait()
			end
		end
		local stride = math.max(1, math.ceil(#carvedChunks / CaveAudit.SampleChunksPerPlan))

		for pick = 1, #carvedChunks, stride do
			local cx, cz = carvedChunks[pick][1], carvedChunks[pick][2]
			chunksChecked += 1
			task.wait()

			-- Cold build, then the cached one from the first pass: identical?
			local cached = CaveMap.getRecord(cx, cz)
			local fresh = CaveMap._buildRecordUncached(cx, cz)
			local same, why = sameRecords(cached, fresh)
			if not same then
				deterministic, detDetail = false, string.format("chunk %d,%d: %s", cx, cz, why)
			end

			-- Carved after every neighbour was carved first: identical?
			CaveMap.clearRecords()
			for dx = -1, 1 do
				for dz = -1, 1 do
					if dx ~= 0 or dz ~= 0 then
						CaveMap.getRecord(cx + dx, cz + dz)
					end
				end
			end
			local afterNeighbours = CaveMap.getRecord(cx, cz)
			same, why = sameRecords(fresh, afterNeighbours)
			if not same then
				orderOk, orderDetail = false, string.format("chunk %d,%d: %s", cx, cz, why)
			end

			if not fresh.empty then
				carvedCells += fresh.count
				carvedBlocks += fresh.blocks

				-- Our edge columns, as carved, against the neighbour's halo
				-- view of them. (Decorations are seated after carving and are
				-- not part of a halo; record.raw holds a decorated column as
				-- it was carved.)
				for i = 0, CHUNK - 1 do
					local edges = {
						{ cx - 1, cz, CHUNK, i, 0, i }, { cx + 1, cz, -1, i, CHUNK - 1, i },
						{ cx, cz - 1, i, CHUNK, i, 0 }, { cx, cz + 1, i, -1, i, CHUNK - 1 },
					}
					for _, e in ipairs(edges) do
						local neighbour = CaveMap.getRecord(e[1], e[2])
						if not neighbour.empty then
							local haloView = CaveMap.haloIntervals(neighbour, e[3], e[4])
							local cell = e[5] * CHUNK + e[6] + 1
							local own = fresh.raw[cell] or fresh.cells[cell]
							if not sameIntervals(own, haloView) then
								borderOk, borderDetail = false, string.format("chunk %d,%d edge column %d,%d", cx, cz, e[5], e[6])
							end
						end
					end
				end

				-- Cover, floor and dry mouths.
				if sampler then
					for cell, intervals in pairs(fresh.cells) do
						local index = cell - 1
						local x, z = cx * CHUNK + index // CHUNK, cz * CHUNK + index % CHUNK
						local height, _biome, water = sampler(x, z)
						local wet = water > height
						local cover = if wet then CaveConfig.MinSurfaceCoverUnderWaterBlocks else CaveConfig.MinSurfaceCoverBlocks
						for k = 1, #intervals, 2 do
							local lo, hi = intervals[k], intervals[k + 1]
							if lo < CaveMap.FloorLimit then
								floorOk, floorDetail = false, string.format("(%d,%d) air at y %d", x, z, lo)
							end
							if not fresh.entrance[cell] and hi > height - cover - 1 then
								coverOk, coverDetail = false, string.format("(%d,%d) air up to y %d under surface %d", x, z, hi, height)
							end
							if fresh.entrance[cell] and wet and not CaveConfig.AllowUnderwaterEntrances then
								wetOk, wetDetail = false, string.format("(%d,%d) entrance under water", x, z)
							end
						end
					end
				end

				-- Decorations: solid cells, each touching the cave's air (or
				-- the next block of its own stack), with headroom left.
				local decorAt = {}
				for i = 1, fresh.decorCount * 3, 3 do
					decorAt[fresh.decor[i] * 1024 + (fresh.decor[i + 1] - TerrainConfig.WorldFloorY)] = true
				end
				for i = 1, fresh.decorCount * 3, 3 do
					local cell, by = fresh.decor[i], fresh.decor[i + 1]
					local intervals = fresh.cells[cell]
					local packed = cell * 1024 + (by - TerrainConfig.WorldFloorY)
					decorChecked += 1
					if intervals == nil or CaveMap.intervalsContain(intervals, by) then
						decorOk, decorDetail = false, string.format("chunk %d,%d cell %d y %d is air", cx, cz, cell, by)
					elseif not (CaveMap.intervalsContain(intervals, by + 1) or CaveMap.intervalsContain(intervals, by - 1)
						or decorAt[packed + 1] or decorAt[packed - 1])
					then
						decorOk, decorDetail = false, string.format("chunk %d,%d cell %d y %d floats in rock", cx, cz, cell, by)
					end
					if fresh.entrance[cell] then
						decorOk, decorDetail = false, string.format("chunk %d,%d cell %d is an entrance column", cx, cz, cell)
					end
				end
				for cell, intervals in pairs(fresh.cells) do
					local raw = fresh.raw[cell]
					if raw then
						for k = 1, #intervals, 2 do
							-- Only the stretches a decoration actually shortened.
							local changed = raw[k] ~= intervals[k] or raw[k + 1] ~= intervals[k + 1]
							if changed and intervals[k + 1] - intervals[k] + 1 < CaveDecorConfig.MinHeadroomBlocks then
								decorOk, decorDetail = false, string.format("chunk %d,%d cell %d left under the headroom", cx, cz, cell)
							end
						end
					end
				end
			end
		end
	end

	check(report, "determinism", deterministic, detDetail)
	check(report, "orderIndependence", orderOk, orderDetail)
	check(report, "borders", borderOk, borderDetail)
	check(report, "thickness.cover", coverOk, if sampler then coverDetail else "skipped: no sampler", if sampler then "error" else "warning")
	check(report, "thickness.floor", floorOk, if sampler then floorDetail else "skipped: no sampler", if sampler then "error" else "warning")
	check(report, "entrances.dry", wetOk, wetDetail)
	check(report, "decor", decorOk, if decorOk then string.format("%d decoration blocks checked", decorChecked) else decorDetail)
	check(report, "sample.carved", carvedBlocks > 0,
		string.format("%d air blocks in %d columns over %d chunks", carvedBlocks, carvedCells, chunksChecked), "warning")

	-- Clamping is allowed to flatten a roof, not to pinch a passage shut:
	-- every candidate the plans offer should have standing room, and the
	-- air of each sample cave should reach its tunnel nodes from its hub.
	local candidates, supported = 0, 0
	for _, plan in ipairs(plans) do
		for _, candidate in ipairs(CaveMap.getCandidates(plan)) do
			candidates += 1
			if candidate.floorSupported then
				supported += 1
			end
		end
		task.wait()
	end
	check(report, "candidates.supported", candidates == 0 or supported / candidates >= 0.8,
		string.format("%d of %d candidates have floor and clearance", supported, candidates), "warning")

	for _, plan in ipairs(plans) do
		local reached, total, flooded = reachableNodes(plan)
		check(report, "connectivity." .. string.lower(plan.category),
			total == 0 or reached / total >= CaveAudit.MinReachableNodes,
			string.format("%s: %d of %d tunnel nodes reached from the hub through %d air blocks", plan.id, reached, total, flooded),
			"warning")
	end

	-- ---- plain chunk cost ------------------------------------------------
	CaveMap.clearCaches()
	local plainStart = os.clock()
	local plain = 0
	local side = 6
	for cx = -side, side do
		for cz = -side, side do
			if CaveMap.getRecord(cx, cz).empty then
				plain += 1
			end
		end
	end
	local perChunkMs = (os.clock() - plainStart) * 1000 / ((2 * side + 1) ^ 2)
	check(report, "plainCost", perChunkMs < 2.0,
		string.format("%d of %d spawn-area chunks empty, %.2f ms per chunk cold", plain, (2 * side + 1) ^ 2, perChunkMs), "warning")

	report.elapsedMs = (os.clock() - startedAt) * 1000
	report.stats = CaveMap.getStats()
	return report
end

function CaveAudit.printReport(report)
	report = report or CaveAudit.run()
	print(string.format("======== cave audit (seed %s) ========", tostring(report.seed)))
	for _, entry in ipairs(report.checks) do
		local mark = if entry.ok then "ok  " elseif entry.severity == "warning" then "WARN" else "FAIL"
		print(string.format("  %s %-28s %s", mark, entry.name, entry.detail))
	end
	print(string.format("  %d error(s), %d warning(s), %.0f ms", report.errors, report.warnings, report.elapsedMs or 0))
	return report
end

function CaveAudit.summarise(report)
	return string.format("Cave audit: %d error(s), %d warning(s) over %d checks. Detail in the output window.",
		report.errors, report.warnings, #report.checks)
end

-- One line about the cave at a world position, for /bbcaves here.
function CaveAudit.describe(worldPosition)
	local blockX = math.floor(worldPosition.X / STUD)
	local by = math.floor(worldPosition.Y / STUD)
	local blockZ = math.floor(worldPosition.Z / STUD)

	local info = CaveMap.describeAt(blockX, by, blockZ)
	if info then
		return string.format("Inside %s cave %s (%s): %s [%s], %d blocks deep.",
			string.lower(info.category), info.id, info.biome, info.kind, info.tag, info.depth)
	end

	local nearest = CaveMap.findNearestPlan(blockX, blockZ, 600)
	if nearest then
		local dx, dz = nearest.originX - blockX, nearest.originZ - blockZ
		return string.format("Not in a cave. Nearest plan %s (%s, %s) is %d blocks away%s.",
			nearest.id, string.lower(nearest.category), nearest.biome, math.floor(math.sqrt(dx * dx + dz * dz)),
			if nearest.entrance then string.format(", mouth at %d, %d", nearest.entrance.x * STUD, nearest.entrance.z * STUD) else ", no surface mouth")
	end
	return "Not in a cave, and no plan within 600 blocks."
end

--[[
	The live edit check: the player must be standing inside a loaded cave.

	Places a block in the cave air beside them, confirms the terrain reports
	it solid, breaks a wall block beside the cave, confirms that reads empty,
	and that both are in ChunkEdits so they replay. The blocks are then put
	back the way they were. Returns ok, message.
]]
function CaveAudit.editRoundTrip(player)
	local TerrainManagerModule = ServerScriptService:FindFirstChild("TerrainManager")
	if not TerrainManagerModule then
		return false, "TerrainManager not found"
	end
	local TerrainManager = require(TerrainManagerModule)
	local ChunkEdits = require(TerrainFolder:WaitForChild("ChunkEdits"))

	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "no character"
	end

	local blockX = math.floor(root.Position.X / STUD)
	local by = math.floor(root.Position.Y / STUD)
	local blockZ = math.floor(root.Position.Z / STUD)

	if not CaveMap.isAirAt(blockX, by, blockZ) then
		return false, "stand inside a cave first (/bbcaves here tells you where one is)"
	end
	if TerrainManager:IsSolidAt(blockX, by, blockZ) then
		return false, "cave air reads solid: the chunk may still be loading"
	end

	-- A cave air cell next to the player, two blocks up so it is not inside
	-- them, with support from the floor or a wall.
	local placeX, placeY, placeZ = blockX + 1, by + 2, blockZ
	if TerrainManager:IsSolidAt(placeX, placeY, placeZ) then
		placeX = blockX - 1
	end
	local okPlace, whyPlace = TerrainManager:PlaceBlock(player, placeX, placeY, placeZ, "Stone")
	if not okPlace then
		return false, "placement in cave air refused: " .. tostring(whyPlace)
	end
	if not TerrainManager:IsSolidAt(placeX, placeY, placeZ) then
		return false, "placed block does not read solid"
	end
	local key = TerrainManager:ChunkKey(placeX // CHUNK, placeZ // CHUNK)
	local cell = (placeX % CHUNK) * CHUNK + (placeZ % CHUNK) + 1
	if not ChunkEdits.isPlaced(key, cell, placeY) then
		return false, "placement was not recorded in ChunkEdits"
	end

	-- Undo it: mining a placed block forgets the placement.
	local okBreak = TerrainManager:BreakBlock(placeX * STUD + 2, placeY * STUD + 2, placeZ * STUD + 2, player)
	if not okBreak or TerrainManager:IsSolidAt(placeX, placeY, placeZ) then
		return false, "could not mine the placed block back out"
	end

	-- The floor under the player is generated cave floor: mine it and check
	-- it reads empty and is remembered, then put a block back in the hole.
	local floorY = by - 1
	while floorY > TerrainConfig.WorldFloorY and not TerrainManager:IsSolidAt(blockX, floorY, blockZ) do
		floorY -= 1
	end
	local okFloor, _item, whyFloor = TerrainManager:BreakBlock(blockX * STUD + 2, floorY * STUD + 2, blockZ * STUD + 2, player)
	if not okFloor then
		return false, "could not mine the cave floor: " .. tostring(whyFloor)
	end
	if TerrainManager:IsSolidAt(blockX, floorY, blockZ) then
		return false, "mined floor still reads solid"
	end
	local okRefill, whyRefill = TerrainManager:PlaceBlock(player, blockX, floorY, blockZ, "Stone")
	if not okRefill then
		return false, "could not refill the floor: " .. tostring(whyRefill)
	end

	return true, "placed into cave air, mined back, mined the floor and refilled it; all recorded for replay"
end

return CaveAudit
