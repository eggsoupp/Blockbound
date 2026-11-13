--[[
	ChunkBuilder

	Builds one chunk from nothing - columns, caves, structures, replayed player
	edits, Parts, water, models - in budgeted slices, and tears one down again.
	Part of TerrainManager; see TerrainManager for the map of terrain modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))
local StructureRegistry = require(TerrainShared:WaitForChild("StructureRegistry"))
local StrataConfig = require(TerrainShared:WaitForChild("StrataConfig"))
local BiomeConfig = require(TerrainShared:WaitForChild("BiomeConfig"))
local ChunkEdits = require(TerrainShared:WaitForChild("ChunkEdits"))
local CaveConfig = require(TerrainShared:WaitForChild("CaveConfig"))
local CaveMap = require(TerrainShared:WaitForChild("CaveMap"))
local CaveDecor = require(TerrainShared:WaitForChild("CaveDecor"))
local OreConfig = require(TerrainShared:WaitForChild("OreConfig"))
local OreRegistry = require(TerrainShared:WaitForChild("OreRegistry"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local GeneratedColumns = require(script.Parent:WaitForChild("GeneratedColumns"))
local ChunkData = require(script.Parent:WaitForChild("ChunkData"))
local OreDepletion = require(script.Parent:WaitForChild("OreDepletion"))
local BlockParts = require(script.Parent:WaitForChild("BlockParts"))
local ChunkMesher = require(script.Parent:WaitForChild("ChunkMesher"))
local ColumnVisibility = require(script.Parent:WaitForChild("ColumnVisibility"))
local TerrainWater = require(script.Parent:WaitForChild("TerrainWater"))
local GenerationBudget = require(script.Parent:WaitForChild("GenerationBudget"))

local ChunkBuilder = {}

local CHUNK_SIZE = TerrainConfig.ChunkSize
local CHUNK_AREA = TerrainGrid.CHUNK_AREA
local FLOOR_Y = TerrainConfig.WorldFloorY
local BEDROCK_TOP_Y = FLOOR_Y + StrataConfig.BedrockThickness - 1
local STRATA_JITTER = StrataConfig.JitterBlocks

-- Biome name -> its own stone, and the stone of a biome that has none. A
-- column's stone is its biome's from the soil down to bedrock (BiomeConfig
-- `stoneBlock`); the Island's biome is not in the table, so it keeps Stone.
local DEEP_BLOCK = StrataConfig.getDeepBlock()
local STONE_BY_BIOME = {}
for name, definition in pairs(BiomeConfig.Definitions) do
	STONE_BY_BIOME[name] = definition.stoneBlock
end
local DIR_X = TerrainGrid.DIR_X
local DIR_Z = TerrainGrid.DIR_Z

local ColumnSource = GeneratedColumns.source
local CAVES_ENABLED = GeneratedColumns.cavesEnabled
local getGeneratedColumn = GeneratedColumns.get

local chunks = ChunkData.chunks
local generatingChunks = ChunkData.generating
local pendingUnload = ChunkData.pendingUnload
local pinnedChunks = ChunkData.pinnedChunks
local isChunkWanted = ChunkData.isWanted
local markRemoved = ChunkData.markRemoved
local applyRemoval = ChunkData.applyRemoval
local applyPlacement = ChunkData.applyPlacement
local makeWriter = ChunkData.makeWriter

local chunkKey = TerrainGrid.chunkKey
local isChunkInBounds = TerrainGrid.isChunkInBounds
local isBlockInWorld = TerrainGrid.isBlockInWorld

local releasePart = BlockParts.releasePart
local flushChunkMesh = ChunkMesher.flushChunkMesh
local flushChunkMeshSliced = ChunkMesher.flushChunkMeshSliced
local updateColumnVisibility = ColumnVisibility.updateColumnVisibility
local refreshChunkBorders = ColumnVisibility.refreshChunkBorders
local syncChunkWater = TerrainWater.syncChunkWater
local clearChunkWater = TerrainWater.clearChunkWater

-- Ore on cave surfaces (see ORE ON SHOW). The depth band is read per call:
-- OreRegistry only knows it once it has been given the seed.
local EXPOSE_ORES = OreConfig.Enabled and OreConfig.CaveExposure.Enabled
local ORE_GONE_STRIDE = OreDepletion.STRIDE
local ORE_MIN_DEPTH, ORE_MAX_DEPTH = 0, math.huge
local exposedOreAt = OreRegistry.exposedBlockAt
local decorBlockName = CaveDecor.blockName
local intervalsContain = CaveMap.intervalsContain

local chargeBudget = GenerationBudget.chargeBudget
local newGenBudget = GenerationBudget.newGenBudget
local chunkCpuSpent = GenerationBudget.chunkCpuSpent
local yieldIfOverBudget = GenerationBudget.yieldIfOverBudget

local TerrainRoot = workspace:FindFirstChild("GeneratedTerrain")
if not TerrainRoot then
	TerrainRoot = Instance.new("Folder")
	TerrainRoot.Name = "GeneratedTerrain"
	TerrainRoot.Parent = workspace
end

-- The world seed, set once at Init (strataJitter is a hash of it).
local baseSeed = 0

-- Called at Init, after OreRegistry has its seed.
function ChunkBuilder.setSeed(seed)
	baseSeed = seed

	local ores = OreRegistry.getStats()
	if ores.ores > 0 then
		ORE_MIN_DEPTH, ORE_MAX_DEPTH = ores.minDepth, ores.maxDepth
	else
		ORE_MIN_DEPTH, ORE_MAX_DEPTH = math.huge, -math.huge
	end
end

--[[
	Per-column offset of the soil/stone boundary. A pure hash of the column's
	absolute position, so it is identical every time the chunk streams in and
	continuous across chunk borders.
]]
local function strataJitter(blockX, blockZ)
	if STRATA_JITTER <= 0 then
		return 0
	end

	local v = math.sin(blockX * 91.7 + blockZ * 47.3 + baseSeed * 0.618) * 43758.5453
	v -= math.floor(v)
	return math.floor(v * (2 * STRATA_JITTER + 1)) - STRATA_JITTER
end

--[[
	Restyles one natural block, for a cave floor, ceiling or wall. Never a
	bedrock layer, never a block that is already air, never anything above the
	column's current top.
]]
local function overrideNatural(data, cell, by, name)
	if by <= BEDROCK_TOP_Y or by >= data.currentHeight[cell] then
		return
	end
	local removed = data.removed[cell]
	if removed and removed[by] then
		return
	end
	local override = data.override[cell]
	if not override then
		override = {}
		data.override[cell] = override
	end
	override[by] = name
end

local function restyleWall(data, cell, intervals, name)
	for i = 1, #intervals, 2 do
		for by = intervals[i], intervals[i + 1] do
			overrideNatural(data, cell, by, name)
		end
	end
end

-- The wall at our border cell (bx, bz) facing the halo column (hx, hz) just
-- outside, in the material of the plan that carved that column.
local function restyleHaloEdge(data, record, hx, hz, bx, bz)
	local intervals, owner = CaveMap.haloIntervals(record, hx, hz)
	if intervals and owner then
		local wallBlock = record.plans[owner].profile.materials.wall
		if wallBlock then
			restyleWall(data, bx * CHUNK_SIZE + bz + 1, intervals, wallBlock)
		end
	end
end

--[[
	ORE ON SHOW

	The rock lining a generated cave carries far more ore than rock sealed in
	the ground (OreConfig.CaveExposure), which is what makes walking a cave
	more rewarding than tunnelling blind. Every block that faces cave air - a
	floor, a ceiling, a wall - is asked OreRegistry.exposedBlockAt once, here,
	while the chunk is built, and an answer is written as an ordinary override.

	Decided from the caves the WORLD carved, never from what players dig, so
	mining cannot conjure ore; and an ore that has already been harvested
	(data.oreGone, see OreDepletion) is left as rock, so a chunk that regrows
	does not put it back.

	A block's answer depends only on its own position, so the wall a chunk
	shares with its neighbour comes out the same from either side.
]]
local exposedOres = 0

local function exposeOre(data, cell, by)
	if by <= BEDROCK_TOP_Y or by >= data.currentHeight[cell] then
		return
	end

	local height = data.height[cell]
	local depth = height - 1 - by
	if depth < ORE_MIN_DEPTH or depth > ORE_MAX_DEPTH then
		return
	end

	local override = data.override[cell]
	if override and override[by] then
		return -- already decided, by this pass or by a cave material
	end

	local base = StrataConfig.blockAt(depth, data.underName[cell], data.jitter[cell], data.stoneName[cell])
	local index = cell - 1
	local ore = exposedOreAt(data.minBlockX + index // CHUNK_SIZE, by, data.minBlockZ + index % CHUNK_SIZE, base, depth)
	if not ore then
		return
	end

	local gone = data.oreGone
	if gone and gone[cell * ORE_GONE_STRIDE + (by - FLOOR_Y)] then
		return
	end

	local removed = data.removed[cell]
	if removed and removed[by] then
		return
	end
	if not override then
		override = {}
		data.override[cell] = override
	end
	override[by] = ore
	exposedOres += 1
end

-- The rows of `air` (a neighbouring column's cave air) beside which the
-- column `cell` is solid: its wall. `own` is that column's own air, or nil.
local function exposeWall(data, cell, air, own)
	for i = 1, #air, 2 do
		for by = air[i], air[i + 1] do
			if own == nil or not intervalsContain(own, by) then
				exposeOre(data, cell, by)
			end
		end
	end
end

local function exposeHaloEdge(data, record, hx, hz, bx, bz)
	local air = CaveMap.haloIntervals(record, hx, hz)
	if air then
		local cell = bx * CHUNK_SIZE + bz + 1
		exposeWall(data, cell, air, record.cells[cell])
	end
end

local function exposeCaveOres(data, record)
	local cells = record.cells
	exposedOres = 0

	for cell, intervals in pairs(cells) do
		local index = cell - 1
		local bx, bz = index // CHUNK_SIZE, index % CHUNK_SIZE

		for i = 1, #intervals, 2 do
			exposeOre(data, cell, intervals[i] - 1)
			exposeOre(data, cell, intervals[i + 1] + 1)
		end

		for d = 1, 4 do
			local nbx, nbz = bx + DIR_X[d], bz + DIR_Z[d]
			if nbx >= 0 and nbx < CHUNK_SIZE and nbz >= 0 and nbz < CHUNK_SIZE then
				local neighbour = nbx * CHUNK_SIZE + nbz + 1
				exposeWall(data, neighbour, intervals, cells[neighbour])
			end
		end
	end

	-- Our border blocks that face air in the chunk next door.
	for i = 0, CHUNK_SIZE - 1 do
		exposeHaloEdge(data, record, -1, i, 0, i)
		exposeHaloEdge(data, record, CHUNK_SIZE, i, CHUNK_SIZE - 1, i)
		exposeHaloEdge(data, record, i, -1, i, 0)
		exposeHaloEdge(data, record, i, CHUNK_SIZE, i, CHUNK_SIZE - 1)
	end

	return exposedOres
end

--[[
	Names the cells CaveDecor left standing on the cave's floors and ceilings
	(record.decor). They were never carved, so they are ordinary solid cells
	with a block name of their own. A collectible one that was harvested
	before (OreDepletion) is carved away instead: the crystal does not regrow.
]]
local function applyDecor(data, record)
	local decor = record.decor
	local gone = data.oreGone
	for i = 1, record.decorCount * 3, 3 do
		local cell, by = decor[i], decor[i + 1]
		if by < data.currentHeight[cell] then
			if gone and gone[cell * ORE_GONE_STRIDE + (by - FLOOR_Y)] then
				markRemoved(data, cell, by)
			else
				overrideNatural(data, cell, by, decorBlockName(decor[i + 2]))
			end
		end
	end
end

--[[
	Carves a chunk's caves into its data from the CaveMap record, then decides
	what the surfaces that now face the air are made of: the biome profile's
	materials where it names any, ore on show, and the decorations.

	Air is marked top-down per column through markRemoved, so an entrance that
	reaches the surface lowers the column exactly as mining its top would, and
	a tunnel below the surface becomes a disturbed band the general visibility
	path scans. Materials and ores are plain overrides on the blocks around
	each interval; walls shared with the next chunk are found through the
	record's halo, so both sides of a border wall agree.
]]
local function applyCaves(data, record)
	local plans = record.plans
	local cells = record.cells
	local carved = 0

	for cell, intervals in pairs(cells) do
		local currentHeight = data.currentHeight
		for i = #intervals - 1, 1, -2 do
			for by = intervals[i + 1], intervals[i], -1 do
				if by < currentHeight[cell] then
					markRemoved(data, cell, by)
					carved += 1
				end
			end
		end
	end

	for cell, intervals in pairs(cells) do
		local materials = plans[record.owner[cell]].profile.materials
		local floorBlock, ceilingBlock, wallBlock = materials.floor, materials.ceiling, materials.wall

		if floorBlock or ceilingBlock or wallBlock then
			local index = cell - 1
			local bx, bz = index // CHUNK_SIZE, index % CHUNK_SIZE

			for i = 1, #intervals, 2 do
				local lo, hi = intervals[i], intervals[i + 1]
				if floorBlock then
					overrideNatural(data, cell, lo - 1, floorBlock)
				end
				if ceilingBlock then
					overrideNatural(data, cell, hi + 1, ceilingBlock)
				end
			end

			if wallBlock then
				for d = 1, 4 do
					local nbx, nbz = bx + DIR_X[d], bz + DIR_Z[d]
					if nbx >= 0 and nbx < CHUNK_SIZE and nbz >= 0 and nbz < CHUNK_SIZE then
						restyleWall(data, nbx * CHUNK_SIZE + nbz + 1, intervals, wallBlock)
					end
				end
			end
		end
	end

	-- Our border blocks that face air in the chunk next door.
	for i = 0, CHUNK_SIZE - 1 do
		restyleHaloEdge(data, record, -1, i, 0, i)
		restyleHaloEdge(data, record, CHUNK_SIZE, i, CHUNK_SIZE - 1, i)
		restyleHaloEdge(data, record, i, -1, i, 0)
		restyleHaloEdge(data, record, i, CHUNK_SIZE, i, CHUNK_SIZE - 1)
	end

	-- Ore after the materials (a restyled block is not asked again) and the
	-- decorations last, since a floor material lands on the cell under the
	-- lowest air, which is where a floor decoration stands.
	local ores = 0
	if EXPOSE_ORES then
		ores = exposeCaveOres(data, record)
	end
	if record.decorCount > 0 then
		applyDecor(data, record)
	end

	return carved, ores
end

--[[
	May a structure stand here? The column source's own rule first (the
	island's clearing), then the caves: nothing is seated over cave air within
	CaveConfig.StructureSupportDepthBlocks of the surface, at the origin or at
	the corners and edges of the footprint.
]]
local function structureHasSupport(blockX, blockZ, radius)
	if ColumnSource.allowStructureAt and not ColumnSource.allowStructureAt(blockX, blockZ, radius) then
		return false
	end
	if not CAVES_ENABLED then
		return true
	end

	local depth = CaveConfig.StructureSupportDepthBlocks
	if CaveMap.hasAirBelowSurface(blockX, blockZ, depth) then
		return false
	end

	radius = math.floor(radius or 0)
	if radius > 0 then
		for dx = -radius, radius, radius do
			for dz = -radius, radius, radius do
				if (dx ~= 0 or dz ~= 0)
					and isBlockInWorld(blockX + dx, blockZ + dz)
					and CaveMap.hasAirBelowSurface(blockX + dx, blockZ + dz, depth)
				then
					return false
				end
			end
		end
	end

	return true
end

local function generateChunk(cx, cz, job)
	if not isChunkInBounds(cx, cz) then
		return
	end

	local key = chunkKey(cx, cz)
	if chunks[key] or not isChunkWanted(key) then
		return
	end

	local ctx = newGenBudget()
	ctx.cx, ctx.cz, ctx.job = cx, cz, job
	Profiler.count("Terrain.chunkGenerated")

	local phaseStart = 0

	-- Phase 0: columns. Built into locals first so a yield can never expose a
	-- half-populated chunk to BreakBlock or to a neighbour's visibility pass.
	local height = table.create(CHUNK_AREA, 0)
	local currentHeight = table.create(CHUNK_AREA, 0)
	local topName = table.create(CHUNK_AREA)
	local underName = table.create(CHUNK_AREA)
	local biomeName = table.create(CHUNK_AREA)
	local stoneName = table.create(CHUNK_AREA)
	local waterTop = table.create(CHUNK_AREA, 0)
	local jitter = table.create(CHUNK_AREA, 0)
	local topScan = table.create(CHUNK_AREA, 0)
	local distLow = table.create(CHUNK_AREA, math.huge)
	local distHigh = table.create(CHUNK_AREA, -math.huge)
	local visible = table.create(CHUNK_AREA)

	local minBlockX = cx * CHUNK_SIZE
	local minBlockZ = cz * CHUNK_SIZE

	for cell = 1, CHUNK_AREA do
		local index = cell - 1
		local blockX = minBlockX + index // CHUNK_SIZE
		local blockZ = minBlockZ + index % CHUNK_SIZE

		local columnHeight, biome, top, under, _variant, water =
			getGeneratedColumn(blockX, blockZ)

		height[cell] = columnHeight
		currentHeight[cell] = columnHeight
		topName[cell] = top
		underName[cell] = under
		biomeName[cell] = biome
		stoneName[cell] = STONE_BY_BIOME[biome] or DEEP_BLOCK
		waterTop[cell] = water
		jitter[cell] = strataJitter(blockX, blockZ)
		visible[cell] = {}

		-- The scan ceiling has to clear the water as well as the ground, or the
		-- slow path would never look at the blocks the water occupies.
		topScan[cell] = if water > columnHeight then water else columnHeight

		yieldIfOverBudget(ctx)
	end

	Profiler.sample("Terrain.gen.1columns", chunkCpuSpent(ctx) * 1000, "ms")

	if not isChunkWanted(key) then
		return
	end

	--[[
		Phase 0b: plan and carve the caves, still before the chunk is published
		in `chunks`, so a neighbour reading our cells during the yields below
		sees generated ground rather than a cave half carved. Nearly every
		chunk gets the shared empty record back in a few hash lookups; one a
		cave crosses carves in time slices like everything else.
	]]
	local function slice()
		yieldIfOverBudget(ctx)
	end

	local caveRecord = nil
	if CAVES_ENABLED then
		phaseStart = chunkCpuSpent(ctx)
		caveRecord = CaveMap.prepareRecord(cx, cz, slice)

		-- The neighbours' records too, while we can still yield: the
		-- visibility pass asks about border columns in unloaded chunks, and
		-- a record built from inside that pass could not be time-sliced.
		--
		-- Three chunks out rather than one, because structure planning below
		-- asks too: candidates come from the 5x5 chunks around this one, and
		-- each tests the caves under its footprint, which can reach into the
		-- next chunk again. Any record not built here was built there, whole,
		-- inside one slice - the 30ms spikes in gen.1d_structurePlan. Already
		-- built records cost one cache read each.
		for dx = -3, 3 do
			for dz = -3, 3 do
				local ncx, ncz = cx + dx, cz + dz
				if (dx ~= 0 or dz ~= 0) and isChunkInBounds(ncx, ncz) then
					CaveMap.prepareRecord(ncx, ncz, slice)
				end
			end
		end
		Profiler.sample("Terrain.gen.1b_cavePlan", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")

		if not isChunkWanted(key) then
			return
		end
	end

	--[[
		Phase 0c: which structures stand in and around this chunk. Working that
		out means candidates for the 5x5 chunks around it and an overlap contest
		over the 3x3, and on fresh ground that measured up to 50ms - in one
		frame, because applyBlocks below cannot yield. Done here in slices
		instead; applyBlocks and applyModels then read the cached answer.
	]]
	phaseStart = chunkCpuSpent(ctx)
	StructureRegistry.prepare(cx, cz, slice)
	Profiler.sample("Terrain.gen.1d_structurePlan", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")

	if not isChunkWanted(key) then
		return
	end

	-- Built OUT of the world and parented once at the end of generation (see
	-- Phase 5). Parenting each Part into the live world one by one measured
	-- about a third more server time than building them in a loose folder and
	-- parenting that, and only the loose build can be sliced across frames.
	-- It also means a client receives the chunk whole, not layer by layer.
	--
	-- A MODEL, NOT A FOLDER, and this one word is the largest performance fact
	-- in the file. With chunks in Folders, the engine's instance streaming
	-- (StreamingSolverV2 and its sender, in the MicroProfiler) spent 50-80ms
	-- of EVERY server frame while chunks were loading and unloading - against
	-- under 7ms for all of this script - and held the server near 14 frames a
	-- second for as long as a player kept moving. Chunks reached clients late
	-- for the same reason, which is what left players falling through ground
	-- the server had already built. The same Parts under a Model: 58 frames a
	-- second on the same route, and a mountain view filled in 7 seconds
	-- instead of 18. Measured three times each way; why the engine cares is
	-- its own business.
	--
	-- ModelStreamingMode is left at Default, so each Part still streams to a
	-- client by distance exactly as it did under a Folder. Everything parented
	-- to a chunk is a block Part or a structure Model, so the nearest Model
	-- above a tree's part is still the tree.
	local model = Instance.new("Model")
	model.Name = string.format("Chunk_%d_%d", cx, cz)

	local data = {
		cx = cx,
		cz = cz,
		minBlockX = minBlockX,
		minBlockZ = minBlockZ,
		model = model,
		height = height,
		currentHeight = currentHeight,
		topName = topName,
		underName = underName,
		biomeName = biomeName,
		stoneName = stoneName,
		waterTop = waterTop,
		jitter = jitter,
		topScan = topScan,
		distLow = distLow,
		distHigh = distHigh,
		visible = visible,

		-- Which layers need their Parts rebuilt, and how many there are. A Part
		-- now spans columns, so meshing cannot happen inside the per-column
		-- visibility pass - the whole batch of columns has to settle first.
		layerParts = {},
		dirtyLayers = {},
		dirtyCount = 0,
		visibleCount = 0,

		removed = {},
		extra = {},
		override = {},
		complex = {},

		-- Ore already harvested in this chunk, if any (see OreDepletion).
		oreGone = OreDepletion.forChunk(key),

		-- Edit zones (see EDIT ZONES): cell -> when its zone time runs out,
		-- and the Parts on their way off screen.
		hot = {},
		hotCount = 0,
		retiring = {},
	}

	chunks[key] = data
	ChunkData.loadedCount += 1

	local writer = makeWriter(cx, cz, data)

	-- Phase 1: structure terrain edits, before anything is rendered, so the
	-- chunk is built once rather than built and then patched.
	phaseStart = chunkCpuSpent(ctx)

	-- The column source's own carving, before structures so a tree can still
	-- stand on what is left. Only the island has any (the space under it);
	-- BiomeMap leaves this nil.
	if ColumnSource.applyBlocks then
		ColumnSource.applyBlocks(cx, cz, writer)
		yieldIfOverBudget(ctx)
	end

	-- Caves next: before structures, so nothing is seated over them, and
	-- before edits, so a player's changes win over the cave. See CAVES.
	if caveRecord and not caveRecord.empty then
		phaseStart = chunkCpuSpent(ctx)
		local carved, ores = applyCaves(data, caveRecord)
		Profiler.count("Terrain.cave.chunksWithCaves")
		Profiler.sample("Terrain.cave.carvedBlocks", carved, "blocks")
		Profiler.sample("Terrain.cave.exposedOres", ores, "blocks")
		Profiler.sample("Terrain.cave.decorations", caveRecord.decorCount, "blocks")
		Profiler.sample("Terrain.cave.plansInChunk", caveRecord.planCount, "plans")
		Profiler.sample("Terrain.gen.1c_caveCarve", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")
		yieldIfOverBudget(ctx)
	end

	StructureRegistry.applyBlocks(cx, cz, writer)
	Profiler.sample("Terrain.gen.2structures", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")
	yieldIfOverBudget(ctx)

	-- Phase 2: replay what players have done here. After structures, so a mined
	-- structure block stays mined and a placed block wins over both.
	phaseStart = chunkCpuSpent(ctx)
	ChunkEdits.applyTo(key, function(cell, by)
		applyRemoval(data, cell, by)
	end, function(cell, by, name)
		applyPlacement(data, cell, by, name)
	end)
	Profiler.sample("Terrain.gen.3edits", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")
	yieldIfOverBudget(ctx)

	-- Phase 3: render.
	phaseStart = chunkCpuSpent(ctx)

	-- From here on the chunk has Parts whose faces depend on its cells, so a
	-- change to a cell has to reach them. See HIDDEN FACES.
	data.trackFaces = true

	-- Neighbours that finished before this point are read in full below.
	data.bordersStale = nil
	for index = 0, CHUNK_AREA - 1 do
		updateColumnVisibility(cx, cz, index // CHUNK_SIZE, index % CHUNK_SIZE)
		yieldIfOverBudget(ctx)
	end

	-- One that finished DURING a yield may have changed an edge column after
	-- it was scanned, and left this flag rather than drawing us half-built (see
	-- refreshChunkBorders). Re-read the edges until no yield brings another.
	local function settleBorders()
		while data.bordersStale do
			data.bordersStale = nil
			for j = 0, CHUNK_SIZE - 1 do
				updateColumnVisibility(cx, cz, 0, j)
				updateColumnVisibility(cx, cz, CHUNK_SIZE - 1, j)
				updateColumnVisibility(cx, cz, j, 0)
				updateColumnVisibility(cx, cz, j, CHUNK_SIZE - 1)
				yieldIfOverBudget(ctx)
			end
		end
	end
	settleBorders()

	-- Every column has decided what it wants drawn; now turn that into the
	-- smallest set of Parts that draws it. Meshing after the whole chunk rather
	-- than per column is what lets a rectangle span columns at all. A layer at
	-- a time, yielding between: the chunk is not in the world yet, so nobody
	-- can see it half drawn.
	flushChunkMeshSliced(data, slice)

	-- Water last, once every edit has been replayed: a block a player put in a
	-- lake has to be in place before the water around it is written.
	syncChunkWater(data)
	Profiler.sample("Terrain.gen.4render", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")

	-- How much more a cave chunk draws than a plain one: the two samples side
	-- by side are the cost of cave geometry, since nothing else differs.
	if caveRecord and not caveRecord.empty then
		Profiler.sample("Terrain.cave.visibleBlocks", data.visibleCount, "blocks")
	else
		Profiler.sample("Terrain.plainChunkVisibleBlocks", data.visibleCount, "blocks")
	end

	-- Phase 4: structure models, sliced between models: cloning, scaling and
	-- seating a forest's worth used to run as one unbroken block.
	phaseStart = chunkCpuSpent(ctx)
	StructureRegistry.applyModels(cx, cz, writer, slice)

	-- Those yields are a window for a neighbour to finish too. Nothing yields
	-- after this loop, so once it exits the flush below is the last word.
	settleBorders()
	flushChunkMesh(data)
	Profiler.sample("Terrain.gen.5models", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")

	-- Phase 5: into the world, whole, and let already-loaded neighbours see
	-- anything that crossed into them - in the same frame, so the seam between
	-- them never shows.
	phaseStart = chunkCpuSpent(ctx)
	model.Parent = TerrainRoot
	refreshChunkBorders(cx, cz)
	Profiler.sample("Terrain.gen.6borders", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")

	-- Whole-chunk CPU, excluding the between-slice sleeps. Compare against
	-- Terrain.chunkLatencyMs to see how much of a chunk's wall clock was work.
	Profiler.sample("Terrain.chunkCpuMs", chunkCpuSpent(ctx) * 1000, "ms")

	-- The last stretch since the final yield is charged too, or a frame that
	-- finished a chunk would read cheaper than it was.
	local tail = os.clock() - ctx.sliceStart
	chargeBudget(tail)
	Profiler.sample("Terrain.sliceMs", tail * 1000, "ms")
end

local function unloadChunk(cx, cz)
	local key = chunkKey(cx, cz)
	if pinnedChunks[key] then return end
	if generatingChunks[key] then
		return
	end

	local data = chunks[key]
	if not data then
		return
	end

	chunks[key] = nil
	ChunkData.loadedCount -= 1
	ChunkMesher.forgetVisible(data.visibleCount)
	pendingUnload[key] = nil

	local startedAt = os.clock()
	local released = 0

	--[[
		Out of the world FIRST, as one piece. Taking the Parts out of a chunk
		that is still in the world is a separate removal for every Part - a
		hundred or so per chunk, each one something the engine's streaming has
		to account for and send to every client. Detached, the whole chunk
		leaves as a single removal, and the Parts go back to the pool from a
		folder nothing is watching.
	]]
	if data.model then
		data.model.Parent = nil
	end

	for by, bucket in pairs(data.layerParts) do
		for i = #bucket, 1, -1 do
			releasePart(bucket[i])
			bucket[i] = nil
			released += 1
		end
		data.layerParts[by] = nil
	end

	-- Parts on their way off screen go now, before the folder they are in is
	-- destroyed - their timers would otherwise hand a destroyed Part back to
	-- the pool.
	for part in pairs(data.retiring) do
		releasePart(part)
	end
	table.clear(data.retiring)

	if data.model then
		data.model:Destroy()
	end

	clearChunkWater(data)

	--[[
		A chunk is not split across frames: its Parts leave together, so each
		client rebuilds what it draws there once. Releasing them a few at a time
		measured fewer frames per second in the client than the unload ever
		cost, for a few large chunks' worth of server time. processPendingUnloads
		spreads whole chunks over frames instead.
	]]
	Profiler.sample("Terrain.chunkUnloadMs", (os.clock() - startedAt) * 1000, "ms")
	Profiler.sample("Terrain.chunkUnloadParts", released, "parts")
	Profiler.count("Terrain.chunkUnloaded")
end

ChunkBuilder.generateChunk = generateChunk
ChunkBuilder.unloadChunk = unloadChunk
ChunkBuilder.structureHasSupport = structureHasSupport

return ChunkBuilder
