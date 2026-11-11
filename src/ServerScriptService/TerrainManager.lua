--[[
	TerrainManager

	Streams a block world around the players: decides which chunks should exist,
	generates their columns, renders only the block faces that are actually
	visible, and applies every edit - mined or placed - through one path.

	It owns the *plumbing*. Everything that decides what the world looks like
	lives in ReplicatedStorage.Shared:

	  Terrain.TerrainConfig      world size, chunk size, streaming, budgets
	  Terrain.BiomeConfig        biomes, their size, rarity and compatibility
	  Terrain.StructureConfig    trees / rocks / ruins
	  Terrain.StrataConfig       what the world is made of as you go down
	  Terrain.OreConfig          which ores exist and at what depths
	  Terrain.BiomeMap           position -> height + biome
	  Terrain.IslandShape        the same, for the Island place (see PlaceConfig)
	  Terrain.StructureRegistry  position -> what gets built there
	  Terrain.OreRegistry        position -> which ore, if any
	  Terrain.CaveConfig         how caves occur and how each biome shapes them
	  Terrain.CaveMap            position -> cave air, plans, content candidates
	  Terrain.ChunkEdits         what players have changed
	  Blocks.BlockConfig         what a block drops and how hard it is

	Adding a biome, ore, block, structure or cave profile never requires
	touching this file.

	HOW THE SERVER SIDE IS SPLIT

	This file is the coordinator: Init wires the world together, and the public
	API below delegates to the module that owns each job. Extend THOSE modules,
	not this file. ServerScriptService.Terrain:

	  GeneratedColumns   the column source (BiomeMap / IslandShape), caves on or
	                     off, and the generated-column cache
	  ChunkData          loaded chunks, residency state, cell queries
	                     (isPresentInData, blockNameFor...), edit primitives
	                     (markRemoved, applyPlacement) and the structure writer
	  BlockParts         block templates, face variants, part pools, partRect
	  FaceCulling        which faces of a drawn Part show their images
	  ChunkMesher        visible blocks -> merged Parts, layer plans, flushes
	  ColumnVisibility   which blocks of a column are drawn; edit/border refresh
	  EditZones          per-block drawing around recent edits
	  TerrainWater       water as Terrain voxels
	  ChunkQueue         the generation queue and its re-ordering
	  GenerationBudget   the shared adaptive frame budget and urgency
	  ChunkBuilder       building and unloading one chunk
	  ChunkStreaming     view distances, active sets, unloads, Heartbeat work
	  BlockEdits         click resolution, inspect / break / place
	  TerrainExcavation  craters, boss bites, block walls, displacement

	Shared.Terrain.TerrainGrid holds the coordinate helpers and key packing.

	PUBLIC API
	  TerrainManager:Init()
	  TerrainManager:InspectBlock(part | x, y, z, initiator) -> name, item, reason
	  TerrainManager:BreakBlock(part | x, y, z, initiator) -> ok, itemName, reason
	  TerrainManager:PlaceBlock(player, blockX, by, blockZ, name) -> ok, reason
	  TerrainManager:IsSolidAt(blockX, by, blockZ) -> boolean
	  TerrainManager:GetCaveInfo(worldPosition) -> info?
	  TerrainManager:GetChunk(cx, cz)
	  TerrainManager:HoldGeneration(reason) / :ReleaseGeneration(reason)
	  TerrainManager:ChunkKey(cx, cz) -> key / :ChunkCoords(key) -> cx, cz
	  TerrainManager:GetStats()

	COORDINATE SYSTEMS
	  world studs   what Roblox uses
	  block         world studs / StudSize. Block (0,0,0) starts at stud (0,0,0).
	                Block Y may be negative, down to TerrainConfig.WorldFloorY.
	  chunk         block / ChunkSize, horizontally only. Chunks are full-depth
	                columns of world, which is what keeps a much deeper world
	                from turning into one enormous generation operation.
	  cell          a column inside a chunk, packed as bx * ChunkSize + bz + 1
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))
local StructureRegistry = require(TerrainShared:WaitForChild("StructureRegistry"))
local OreRegistry = require(TerrainShared:WaitForChild("OreRegistry"))
local ChunkEdits = require(TerrainShared:WaitForChild("ChunkEdits"))
local CaveMap = require(TerrainShared:WaitForChild("CaveMap"))

local Modules = script.Parent:WaitForChild("Terrain")
local GeneratedColumns = require(Modules:WaitForChild("GeneratedColumns"))
local BlockParts = require(Modules:WaitForChild("BlockParts"))
local ChunkData = require(Modules:WaitForChild("ChunkData"))
local ChunkMesher = require(Modules:WaitForChild("ChunkMesher"))
local TerrainWater = require(Modules:WaitForChild("TerrainWater"))
local ChunkQueue = require(Modules:WaitForChild("ChunkQueue"))
local GenerationBudget = require(Modules:WaitForChild("GenerationBudget"))
local ChunkBuilder = require(Modules:WaitForChild("ChunkBuilder"))
local ChunkStreaming = require(Modules:WaitForChild("ChunkStreaming"))
local BlockEdits = require(Modules:WaitForChild("BlockEdits"))
local TerrainExcavation = require(Modules:WaitForChild("TerrainExcavation"))

local TerrainManager = {}

local STUD_SIZE = TerrainConfig.StudSize
local CHUNK_SIZE = TerrainConfig.ChunkSize
local CHUNK_AREA = TerrainGrid.CHUNK_AREA
local FLOOR_Y = TerrainConfig.WorldFloorY
local MAX_BLOCK_Y = TerrainConfig.WorldCeilingY

local ColumnSource = GeneratedColumns.source
local CAVES_ENABLED = GeneratedColumns.cavesEnabled
local getGeneratedColumn = GeneratedColumns.get
local chunks = ChunkData.chunks
local generatingChunks = ChunkData.generating
local pendingUnload = ChunkData.pendingUnload
local isBlockPresent = ChunkData.isBlockPresent
local chunkKey = TerrainGrid.chunkKey
local isBlockInWorld = TerrainGrid.isBlockInWorld
local cellOf = TerrainGrid.cellOf
local blockToChunkLocal = TerrainGrid.blockToChunkLocal

local baseSeed = 0
local isInitialized = false

-- ---------------------------------------------------------------------------
-- Edits (BlockEdits, TerrainExcavation)
-- ---------------------------------------------------------------------------

TerrainManager.InspectBlock = BlockEdits.InspectBlock
TerrainManager.BreakBlock = BlockEdits.BreakBlock
TerrainManager.OpenEditZone = BlockEdits.OpenEditZone
TerrainManager.PlaceBlock = BlockEdits.PlaceBlock
TerrainManager.IsSolidAt = BlockEdits.IsSolidAt

TerrainManager.MineMeteorCrater = TerrainExcavation.MineMeteorCrater
TerrainManager.MineAbilityCrater = TerrainExcavation.MineAbilityCrater
TerrainManager.PlanExcavation = TerrainExcavation.PlanExcavation
TerrainManager.ExecuteExcavation = TerrainExcavation.ExecuteExcavation
TerrainManager.PlanBlockWall = TerrainExcavation.PlanBlockWall
TerrainManager.TakeBlockWall = TerrainExcavation.TakeBlockWall
TerrainManager.FinishBlockWall = TerrainExcavation.FinishBlockWall
TerrainManager.BeginBossDisplacement = TerrainExcavation.BeginBossDisplacement
TerrainManager.FinishBossDisplacement = TerrainExcavation.FinishBossDisplacement

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function TerrainManager:Init()
	if isInitialized then
		return
	end
	isInitialized = true

	baseSeed = TerrainConfig.WorldSeed
	if type(baseSeed) ~= "number" then
		baseSeed = math.floor(os.clock() * 1000000) % 2147483647
	end

	ColumnSource.init(baseSeed)
	OreRegistry.init(baseSeed)
	ChunkBuilder.setSeed(baseSeed)

	-- Caves read the surface through the same cached column path everything
	-- else uses, so a plan's origin and the cover under a column come from
	-- exactly the heightmap the chunk will build.
	if CAVES_ENABLED then
		CaveMap.init(baseSeed, {
			sampler = function(blockX, blockZ)
				local height, biome, _top, _under, _variant, water = getGeneratedColumn(blockX, blockZ)
				return height, biome, water
			end,
			isInWorld = isBlockInWorld,
		})
	end

	BlockParts.ensureGeneratedTemplates()
	TerrainWater.applyLook()

	-- Before anything is cloned from a template, so every pooled part inherits
	-- tiled faces rather than being fixed up one clone at a time.
	BlockParts.normaliseBlockFaces()

	-- Lets ChunkEdits bound itself without ever dropping edits for a chunk that
	-- is streamed in, whose stored edits and rendered parts have to agree.
	ChunkEdits.setResidencyCheck(function(key)
		return chunks[key] ~= nil
	end)

	StructureRegistry.init({
		seed = baseSeed,
		chunkSize = CHUNK_SIZE,
		studSize = STUD_SIZE,
		assetsRoot = BlockParts.TerrainAssets,
		blocksFolder = BlockParts.BlocksFolder,
		castStructureShadows = TerrainConfig.CastStructureShadows,
		candidateCacheLimit = TerrainConfig.CandidateCacheLimit,

		getColumn = function(blockX, blockZ)
			local height, biome, top, _under, variant, water = getGeneratedColumn(blockX, blockZ)

			-- `top` is last so the four callers that only want the first four
			-- keep working unchanged. StructureRegistry uses it to keep trees
			-- off bare rock: the surface block is the only thing that says a
			-- column is a ridge rather than a meadow, and it is decided here
			-- rather than by the height, so height alone cannot tell them apart.
			return height, biome, variant, water, top
		end,

		isInWorld = isBlockInWorld,

		-- The island keeps its spawn clearing and beach free of trees; the
		-- open world keeps structures off ground a cave has hollowed out.
		allowStructureAt = ChunkBuilder.structureHasSupport,
	})

	BlockParts.warnForMissingTemplates()

	ChunkStreaming.start()
end

function TerrainManager:GetChunk(cx, cz)
	return chunks[chunkKey(cx, cz)]
end

--[[
	Pauses chunk generation until every hold is released. Chunks players walk
	toward are still queued; they are simply not built yet.

	For a server that has to put stored edits into ChunkEdits before any chunk
	is generated - an island loading its owner's save - since edits replay only
	when a chunk is built. Holds are keyed by reason so two callers cannot
	release each other's.
]]
function TerrainManager:HoldGeneration(reason)
	ChunkStreaming.hold(reason or "default")
end

function TerrainManager:ReleaseGeneration(reason)
	ChunkStreaming.release(reason or "default")
end

--[[
	The key ChunkEdits stores a chunk under, and back. ChunkEdits only ever
	sees these opaque numbers, so anything saving its contents needs the
	coordinates to write something that survives a change to the packing.
]]
function TerrainManager:ChunkKey(cx, cz)
	return chunkKey(cx, cz)
end

function TerrainManager:ChunkCoords(key)
	return TerrainGrid.chunkCoords(key)
end

--[[
	Surface height in STUDS at a world position, plus the biome name there.

	Answers from the loaded chunk when there is one, and from the generator
	otherwise - so it is valid before anything has streamed in, which is what
	SpawnServer needs to place the spawn platform on the ground.
]]
function TerrainManager:GetSurfaceY(worldX, worldZ)
	local blockX = math.floor(worldX / STUD_SIZE)
	local blockZ = math.floor(worldZ / STUD_SIZE)

	if not isBlockInWorld(blockX, blockZ) then
		return nil, nil
	end

	local cx, cz, bx, bz = blockToChunkLocal(blockX, blockZ)

	local data = chunks[chunkKey(cx, cz)]
	if data then
		local cell = cellOf(bx, bz)
		return data.currentHeight[cell] * STUD_SIZE, data.biomeName[cell]
	end

	local height, biome = getGeneratedColumn(blockX, blockZ)

	-- A cave mouth lowers its columns when the chunk builds; answer with that
	-- so nothing is dropped onto air over a hole that is about to open.
	if CAVES_ENABLED then
		local opened = CaveMap.surfaceAt(blockX, blockZ)
		if opened then
			height = opened
		end
	end

	return height * STUD_SIZE, biome
end

--[[
	What cave, if any, a world position is inside. nil for solid ground, open
	air above the surface, or a mined-out hole that no plan carved.

	  { id, category ("Small" | "Large"), biome, kind ("entrance" | "chamber"
	    | "ledge" | "tunnel"), tag, depth, tags, plan }

	Answers from CaveMap, so it is valid for unloaded chunks and never depends
	on what has been mined. Future cave content asks here, or CaveMap directly
	for candidates; see CaveMap.getCandidates.
]]
function TerrainManager:GetCaveInfo(worldPosition)
	if not CAVES_ENABLED or typeof(worldPosition) ~= "Vector3" then
		return nil
	end

	local blockX = math.floor(worldPosition.X / STUD_SIZE)
	local by = math.floor(worldPosition.Y / STUD_SIZE)
	local blockZ = math.floor(worldPosition.Z / STUD_SIZE)
	if not isBlockInWorld(blockX, blockZ) then
		return nil
	end

	return CaveMap.describeAt(blockX, by, blockZ)
end

function TerrainManager:CavesEnabled()
	return CAVES_ENABLED
end

--[[
	The top of the highest SOLID BLOCK in a column, within a band around
	referenceY. Returned in world studs; nil when the band holds nothing to stand
	on.

	HOW THIS DIFFERS FROM GetSurfaceY, AND WHY BOTH EXIST

	GetSurfaceY answers with the terrain column's height. That is O(1) and it is
	the right answer for "where is the ground", which is why spawning and the
	spawn platform use it - but it describes the GENERATED terrain, so it does
	not see a tower a player built, a bridge they placed, or a structure block
	sitting above the surface. Anything walking on those needs a different
	question.

	This one asks the renderer's own "is this cell solid" test, the same one
	mining and placement use, so it agrees with everything a player can actually
	stand on: generated terrain, structure blocks, player placements, and the
	holes left where any of them were mined out.

	It is a bounded downward scan, not a search. The caller says how far up to
	look (climb, for stepping onto something) and how far down (drop, for
	falling into a hole), and a world 190 blocks deep costs the same as a flat
	one because nothing outside that band is ever touched.
]]
function TerrainManager:GetSupportY(worldX, worldZ, referenceY, climbBlocks, dropBlocks)
	local blockX = math.floor(worldX / STUD_SIZE)
	local blockZ = math.floor(worldZ / STUD_SIZE)

	if not isBlockInWorld(blockX, blockZ) then
		return nil
	end

	local cx, cz, bx, bz = blockToChunkLocal(blockX, blockZ)

	local from = math.floor((referenceY or 0) / STUD_SIZE) + math.max(0, climbBlocks or 2)
	local to = from - math.max(0, climbBlocks or 2) - math.max(0, dropBlocks or 8)

	if from > MAX_BLOCK_Y then
		from = MAX_BLOCK_Y
	end
	if to < FLOOR_Y then
		to = FLOOR_Y
	end

	for by = from, to, -1 do
		if isBlockPresent(cx, cz, bx, bz, by) then
			-- The TOP of that block: what something standing on it rests on.
			return (by + 1) * STUD_SIZE
		end
	end

	return nil
end

--[[
	Everything the counters know, in O(1).

	Deliberately cheap enough to call on a timer: the benchmark harness samples
	it once a second for the whole length of a run, and a version that walked
	every cell of every chunk would have been measuring itself.
]]
--[[
	A summary of the ground currently loaded: how high it got, how much of it is
	under water, and how steep it is.

	Walks the loaded chunks rather than sampling the world, so it describes what
	the player is actually standing in. Only called from the debug console.
]]
local function surfaceStats()
	local columns, wet, total, lowest, highest = 0, 0, 0, math.huge, -math.huge
	local relief = 0

	for _, data in pairs(chunks) do
		local height = data.height
		local waterTop = data.waterTop

		for cell = 1, CHUNK_AREA do
			local h = height[cell]
			columns += 1
			total += h

			if h < lowest then
				lowest = h
			end
			if h > highest then
				highest = h
			end
			if waterTop[cell] > h then
				wet += 1
			end
		end

		-- Relief across one chunk, as a stand-in for steepness: the cost of
		-- rendering is driven by height DIFFERENCE, not by height.
		local chunkLow, chunkHigh = math.huge, -math.huge
		for cell = 1, CHUNK_AREA do
			local h = height[cell]
			if h < chunkLow then
				chunkLow = h
			end
			if h > chunkHigh then
				chunkHigh = h
			end
		end
		if chunkHigh > chunkLow then
			relief += chunkHigh - chunkLow
		end
	end

	if columns == 0 then
		return { columns = 0 }
	end

	return {
		columns = columns,
		meanHeight = total / columns,
		lowest = lowest,
		highest = highest,
		underwaterPercent = wet / columns * 100,
		meanChunkRelief = relief / math.max(1, ChunkData.loadedCount),
	}
end

function TerrainManager:GetStats()
	local counts = BlockParts.counts
	local renderedParts = counts.rendered
	local visibleBlocks = ChunkMesher.visibleBlocks()
	local activeGenerations = ChunkStreaming.activeGenerations()

	return {
		seed = baseSeed,
		viewDistance = ChunkStreaming.getViewDistance(),
		loadedChunks = ChunkData.loadedCount,
		queuedChunks = ChunkQueue.count(),
		generating = activeGenerations > 0,
		activeGenerations = activeGenerations,
		generateBudgetMs = GenerationBudget.current() * 1000,
		renderedParts = renderedParts,
		pooledParts = counts.pooled,
		visibleBlocks = visibleBlocks,

		-- Blocks drawn per Part. 1.0 means merging achieved nothing; the higher
		-- it climbs the fewer Instances the client is holding for the same world.
		blocksPerPart = if renderedParts > 0 then visibleBlocks / renderedParts else 0,
		cachedColumns = GeneratedColumns.count(),
		floorY = FLOOR_Y,
		ceilingY = MAX_BLOCK_Y,

		-- What the loaded chunks actually came out as. Worth having on the
		-- stats line because the geography is now the thing most likely to be
		-- retuned, and "how much of this is water" and "how tall did it get"
		-- are the two questions a tuning pass keeps asking.
		surface = surfaceStats(),
		biome = ColumnSource.getStats(),
		structures = StructureRegistry.getStats(),
		ores = OreRegistry.getStats(),
		edits = ChunkEdits.getStats(),
		caves = if CAVES_ENABLED then CaveMap.getStats() else { enabled = false },
	}
end

-- ---------------------------------------------------------------------------
-- View distance (ChunkStreaming)
-- ---------------------------------------------------------------------------

--[[
	Changes how far terrain streams, at runtime.

	Exists so a benchmark can sweep 2 -> 5 inside one server session, which is
	the only way to compare view distances without also comparing two different
	world seeds, two different sets of warm caches and two different machines.

	Every player's active set is re-seated immediately: chunks that fell outside
	the new radius go into the normal unload grace, chunks that came inside are
	queued at their real priority. Nothing about the streaming rules changes -
	only the radius they are applied over.
]]
--[[
	Changes the view distance for EVERYONE, and puts them all back on it.

	Personal choices are discarded rather than left standing. That is what both
	callers want and neither could get otherwise: the benchmark sweeps 2 -> 5
	and has to be measuring the distance it swept to, and /bbvd is an admin
	saying what the server is doing. A sweep silently measuring a developer's
	own leftover setting is a benchmark that reports the wrong number without
	ever looking wrong.

	MAX_PRIORITY is no longer re-derived here - it is fixed at what the largest
	permitted distance needs, because a player may sit above the default.
]]
function TerrainManager:SetViewDistance(distance)
	return ChunkStreaming.setViewDistance(distance)
end

function TerrainManager:GetViewDistance()
	return ChunkStreaming.getViewDistance()
end

--[[
	One player's own view distance.

	Clamped to the configured bounds here rather than trusted, because this is
	reachable from a remote - and the number decides how much work the SERVER
	does on that player's behalf, so it is not theirs to set freely.

	Returns what was actually applied, which is what the caller should show:
	asking for 12 and being given 7 has to be visible, or the option reads as
	broken.
]]
function TerrainManager:SetPlayerViewDistance(player, distance)
	return ChunkStreaming.setPlayerViewDistance(player, distance)
end

function TerrainManager:GetPlayerViewDistance(player)
	return ChunkStreaming.getPlayerViewDistance(player)
end

function TerrainManager:GetViewDistanceRange()
	return ChunkStreaming.getViewDistanceRange()
end

-- ---------------------------------------------------------------------------
-- Benchmark hooks (TerrainBench)
-- ---------------------------------------------------------------------------

function TerrainManager:_UnloadChunk(cx, cz)
	ChunkBuilder.unloadChunk(cx, cz)
end

--[[
	Tears the streamed world down to nothing and empties the pure-function
	caches, so the next load is genuinely cold.

	Benchmark-only. Measuring a "load 49 chunks" pass against caches still warm
	from the previous run at a different view distance would report the cost of
	the cache, not the cost of the chunks.
]]
function TerrainManager:_FlushAll(alsoDropPools)
	for _, entry in pairs(pendingUnload) do
		ChunkBuilder.unloadChunk(entry.cx, entry.cz)
	end

	for key, data in pairs(chunks) do
		if not generatingChunks[key] then
			ChunkBuilder.unloadChunk(data.cx, data.cz)
		end
	end

	GeneratedColumns.clear()

	ColumnSource.clearCaches()
	if CAVES_ENABLED then
		CaveMap.clearCaches()
	end

	if alsoDropPools then
		BlockParts.dropPools()
	end
end

--[[
	Re-queues everything every player currently wants.

	After a flush the usage counts still say the chunks are wanted, but nothing
	re-queues them: enqueueing happens when a player crosses a chunk border, and
	nobody moved. This is the call that actually restarts the load - kept
	separate from _FlushAll so a benchmark can tear the world down OUTSIDE its
	measurement window and time only the rebuild, rather than timing its own
	teardown spike as if it were load cost.
]]
function TerrainManager:_ReseatPlayers()
	ChunkStreaming.reseatPlayers()
end

return TerrainManager
