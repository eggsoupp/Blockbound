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

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local BiomeConfig = require(TerrainShared:WaitForChild("BiomeConfig"))
local BiomeMap = require(TerrainShared:WaitForChild("BiomeMap"))
local StructureRegistry = require(TerrainShared:WaitForChild("StructureRegistry"))
local StrataConfig = require(TerrainShared:WaitForChild("StrataConfig"))
local OreRegistry = require(TerrainShared:WaitForChild("OreRegistry"))
local ChunkEdits = require(TerrainShared:WaitForChild("ChunkEdits"))
local TerrainMesher = require(TerrainShared:WaitForChild("TerrainMesher"))
local LandformConfig = require(TerrainShared:WaitForChild("LandformConfig"))
local BlockConfig = require(Shared:WaitForChild("Blocks"):WaitForChild("BlockConfig"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))
local IslandShape = require(TerrainShared:WaitForChild("IslandShape"))
local CaveConfig = require(TerrainShared:WaitForChild("CaveConfig"))
local CaveMap = require(TerrainShared:WaitForChild("CaveMap"))

--[[
	Where columns come from: the open world's BiomeMap, or in the Island place
	the island template. Both answer sampleColumn with the same six values, so
	nothing below this line knows which place it is in. TerrainConfig and
	OreConfig make the matching size, depth and ore adjustments themselves.
]]
local ColumnSource = if PlaceConfig.isIsland() then IslandShape else BiomeMap

--[[
	CAVES

	The heightmap says a column is solid from the floor to its height. Caves
	are the second thing, after the island's underside, that make that untrue
	for GENERATED ground - so every place that reads the heightmap for a chunk
	that is not loaded also asks CaveMap, and a loaded chunk has its cave
	cells marked removed at generation, before structures and before player
	edits are replayed. From then on cave air is mined-out space, which the
	renderer, mining, placement, support queries and persistence already
	understand: nothing stores it, and a chunk carves it again identically
	every time it streams in.
]]
local CAVES_ENABLED = CaveConfig.Enabled and (CaveConfig.EnabledOnIsland or not PlaceConfig.isIsland())

local TerrainManager = {}

-- ---------------------------------------------------------------------------
-- Localised config
-- ---------------------------------------------------------------------------

local STUD_SIZE = TerrainConfig.StudSize
local CHUNK_SIZE = TerrainConfig.ChunkSize
local CHUNK_STUDS = TerrainConfig.ChunkStuds
local CHUNK_AREA = CHUNK_SIZE * CHUNK_SIZE

local MIN_CHUNK_X = TerrainConfig.MinChunkX
local MAX_CHUNK_X = TerrainConfig.MaxChunkX
local MIN_CHUNK_Z = TerrainConfig.MinChunkZ
local MAX_CHUNK_Z = TerrainConfig.MaxChunkZ

--[[
	The DEFAULT view distance, and the bounds a player may choose within.

	Mutable rather than constant so a benchmark sweep can walk it 2 -> 5 inside
	one server session; see TerrainManager:SetViewDistance. Players who have not
	chosen for themselves follow it.

	MAX_PRIORITY is the ceiling of the dequeue scan, so it is derived from the
	largest distance ANYONE may ask for rather than from the current default -
	a chunk queued at a priority past it would never be dequeued at all.
]]
local VIEW_DISTANCE = TerrainConfig.ViewDistanceChunks
local MIN_VIEW_DISTANCE = TerrainConfig.MinViewDistanceChunks
local MAX_VIEW_DISTANCE = TerrainConfig.MaxViewDistanceChunks
local MAX_PRIORITY = 2 * MAX_VIEW_DISTANCE * MAX_VIEW_DISTANCE

-- Vertical bounds of everything: rendering, mining, placement, structures.
local FLOOR_Y = TerrainConfig.WorldFloorY
local MAX_BLOCK_Y = TerrainConfig.WorldCeilingY

local WATER_BLOCK = LandformConfig.WaterBlock

local BEDROCK_BLOCK = StrataConfig.BedrockBlock
local BEDROCK_TOP_Y = FLOOR_Y + StrataConfig.BedrockThickness - 1
local STRATA_JITTER = StrataConfig.JitterBlocks

local MAX_REACH_STUDS = 34

-- Chunk and block coordinates are packed into single numbers. String keys used
-- to be built inside the visibility loop, which allocated tens of thousands of
-- strings per chunk.
local CHUNK_KEY_OFFSET = 8192
local CHUNK_KEY_STRIDE = 65536
local BLOCK_KEY_OFFSET = 65536
local BLOCK_KEY_STRIDE = 262144

local DIR_X = { 1, -1, 0, 0 }
local DIR_Z = { 0, 0, 1, -1 }

-- ---------------------------------------------------------------------------
-- Assets
-- ---------------------------------------------------------------------------

local TerrainAssets = ReplicatedStorage:WaitForChild("TerrainAssets")
local BlocksFolder = TerrainAssets:WaitForChild("Blocks")

local TerrainRoot = workspace:FindFirstChild("GeneratedTerrain")
if not TerrainRoot then
	TerrainRoot = Instance.new("Folder")
	TerrainRoot.Name = "GeneratedTerrain"
	TerrainRoot.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local chunks = {} -- chunkKey -> chunk data
local loadedChunkCount = 0 -- live size of `chunks`, kept incrementally
local usageCounts = {} -- chunkKey -> how many players want it
local pendingUnload = {} -- chunkKey -> { cx, cz, dueAt }
local playerChunk = {} -- player -> { x, z, active }

--[[
	player -> their chosen view distance, absent while they are on the default.

	Per player rather than per server because it is a CLIENT cost being traded:
	the resident part count is what a machine struggles with, and one person on
	a laptop turning theirs down should not decide it for everybody else.

	The server still pays something - it generates the union of what everyone
	wants - but chunks are shared and reference counted, so two players standing
	together at different distances cost the larger of the two rather than the
	sum.
]]
local playerViewDistance = setmetatable({}, { __mode = "k" })

local function viewDistanceFor(player)
	return playerViewDistance[player] or VIEW_DISTANCE
end
local partPool = {} -- blockName -> array of parts
-- blockName -> fewest parts left in that pool since the last trim. Parts below
-- that line were never needed during the interval, which is what makes them
-- safe to release; see trimPoolsIfNeeded.
local poolLowWater = {}
local generatingChunks = {} -- chunkKey -> true while a coroutine is building it

local queueBuckets = {} -- priority -> array of queue items
local queuedPriority = {} -- chunkKey -> best queued priority
local queuedCount = 0 -- live size of queuedPriority, kept incrementally
local queuedAt = {} -- chunkKey -> os.clock() when a player first asked for it

local resolvedTemplateName = {}
local resolvedTemplatePart = {}

-- Running totals, maintained at the two places parts enter and leave play.
-- Counting them on demand meant walking every cell of every loaded chunk, which
-- is fine for a chat command and far too expensive to sample once a second
-- during a benchmark.
local renderedParts = 0
local pooledParts = 0

-- How many BLOCKS are currently drawn, as opposed to how many Parts draw them.
-- The ratio between the two is the merge ratio, and it is the single number that
-- says whether meshing is earning its complexity in this world.
local visibleBlocks = 0

--[[
	Which blocks a rendered part is currently drawing.

	One part no longer means one block: the mesher collapses a run of identical
	neighbouring blocks into a single elongated Part, so this records the
	RECTANGLE a part covers - chunk, minimum corner, extent and layer - rather
	than a single cell.

	Weak-keyed, and cleared by releasePart on the way back to the pool, so an
	entry can never outlive the part or describe a part that has since been
	reused for something else.

	This replaces the six SetAttribute calls the original renderer made on every
	part it placed. Attributes replicate to every client, so those were pure
	network cost for data only the server reads.
]]
local partRect = setmetatable({}, { __mode = "k" })

local baseSeed = 0
local isInitialized = false
-- How many chunk coroutines are in flight. Replaces a boolean: chunks may now
-- overlap, bounded by TerrainConfig.MaxConcurrentChunks and, more importantly,
-- by the shared frame budget they all draw from.
local activeGenerations = 0
local movementAccumulator = 0
local lastPoolTrim = 0

-- ---------------------------------------------------------------------------
-- Coordinate helpers
-- ---------------------------------------------------------------------------

local function chunkKey(cx, cz)
	return (cx + CHUNK_KEY_OFFSET) * CHUNK_KEY_STRIDE + (cz + CHUNK_KEY_OFFSET)
end

local function isChunkInBounds(cx, cz)
	return cx >= MIN_CHUNK_X and cx <= MAX_CHUNK_X and cz >= MIN_CHUNK_Z and cz <= MAX_CHUNK_Z
end

local function isBlockInWorld(blockX, blockZ)
	local cx = blockX // CHUNK_SIZE
	local cz = blockZ // CHUNK_SIZE
	return isChunkInBounds(cx, cz)
end

local function getChunkWorldOrigin(cx, cz)
	return cx * CHUNK_STUDS, cz * CHUNK_STUDS
end

local function getChunkCoordX(worldX)
	return math.floor(worldX / CHUNK_STUDS + 0.000001)
end

local function getChunkCoordZ(worldZ)
	return math.floor(worldZ / CHUNK_STUDS + 0.000001)
end

--[[
	Moves a (chunk, local cell) pair back into range when the cell index has
	walked off the edge of its chunk.
]]
local function normalizeCell(cx, cz, bx, bz)
	if bx < 0 or bx >= CHUNK_SIZE then
		local shift = bx // CHUNK_SIZE
		cx += shift
		bx -= shift * CHUNK_SIZE
	end

	if bz < 0 or bz >= CHUNK_SIZE then
		local shift = bz // CHUNK_SIZE
		cz += shift
		bz -= shift * CHUNK_SIZE
	end

	return cx, cz, bx, bz
end

local function worldToChunkLocal(wx, wz)
	local cx = getChunkCoordX(wx)
	local cz = getChunkCoordZ(wz)
	local ox, oz = getChunkWorldOrigin(cx, cz)
	local bx = math.floor((wx - ox) / STUD_SIZE)
	local bz = math.floor((wz - oz) / STUD_SIZE)
	return normalizeCell(cx, cz, bx, bz)
end

-- 1-based so every per-chunk table stays a true array rather than degrading
-- into a hash part at index 0.
local function cellOf(bx, bz)
	return bx * CHUNK_SIZE + bz + 1
end

-- ---------------------------------------------------------------------------
-- Generated column cache
-- ---------------------------------------------------------------------------
-- BiomeMap is a pure function of position, so this is purely a speed cache and
-- can be dropped at any time. It exists because visibility culling and
-- structure validation ask about neighbouring columns constantly, including
-- columns in chunks that are not loaded.

-- EVICTION. Two generations rather than one map wiped when it fills. Wiping is
-- correct - these are pure functions of position - but it discards the columns
-- in active use together with the cold ones, so a player crossing the boundary
-- pays to recompute the ground they are standing on. Worse here than for the
-- lattice, because the visibility pass asks about neighbouring columns
-- constantly, including columns in chunks that are not loaded.
--
-- A full young generation is demoted; a hit in old is promoted back into young.
-- Anything still in use therefore survives every rotation, and anything cold is
-- released one rotation after it stops being touched. Each generation is capped
-- at half of ColumnCacheLimit, so the configured ceiling is unchanged.

local genHeight = {}
local genBiome = {}
local genTop = {}
local genUnder = {}
local genVariant = {}
local genWater = {}
local genCount = 0

local oldHeight = {}
local oldBiome = {}
local oldTop = {}
local oldUnder = {}
local oldVariant = {}
local oldWater = {}
local oldGenCount = 0

local COLUMN_GENERATION_LIMIT = math.max(1, math.floor(TerrainConfig.ColumnCacheLimit / 2))

local function rotateColumnGenerations()
	oldHeight, genHeight = genHeight, {}
	oldBiome, genBiome = genBiome, {}
	oldTop, genTop = genTop, {}
	oldUnder, genUnder = genUnder, {}
	oldVariant, genVariant = genVariant, {}
	oldWater, genWater = genWater, {}
	oldGenCount = genCount
	genCount = 0
	Profiler.count("Terrain.columnCacheRotated")
end

--[[
	height is the top of the SOLID ground; water, when there is any, stands in
	[height, waterTop). Both come from BiomeMap and are pure functions of
	position, so this is only ever a speed cache.
]]
local function getGeneratedColumn(blockX, blockZ)
	local key = (blockX + BLOCK_KEY_OFFSET) * BLOCK_KEY_STRIDE + (blockZ + BLOCK_KEY_OFFSET)

	local height = genHeight[key]
	if height ~= nil then
		return height, genBiome[key], genTop[key], genUnder[key], genVariant[key], genWater[key]
	end

	-- Read out of the old generation BEFORE any rotation, which would otherwise
	-- overwrite the table these values live in.
	local agedHeight = oldHeight[key]
	if agedHeight ~= nil then
		local agedBiome = oldBiome[key]
		local agedTop = oldTop[key]
		local agedUnder = oldUnder[key]
		local agedVariant = oldVariant[key]
		local agedWater = oldWater[key]

		if genCount >= COLUMN_GENERATION_LIMIT then
			rotateColumnGenerations()
		end

		genHeight[key] = agedHeight
		genBiome[key] = agedBiome
		genTop[key] = agedTop
		genUnder[key] = agedUnder
		genVariant[key] = agedVariant
		genWater[key] = agedWater
		genCount += 1

		Profiler.count("Terrain.columnPromoted")
		return agedHeight, agedBiome, agedTop, agedUnder, agedVariant, agedWater
	end

	if genCount >= COLUMN_GENERATION_LIMIT then
		rotateColumnGenerations()
	end

	local biome, top, under, variant, water
	height, biome, top, under, variant, water = ColumnSource.sampleColumn(blockX, blockZ)

	--[[
		A dry column reports its water at or below its ground (BiomeMap uses 0).
		Pinned to the floor here so it stays dry however deep the column is dug:
		the renderer draws water wherever waterTop is above the CURRENT height,
		so a dry shaft dug below y = 0 used to grow a phantom water block, and an
		island's sky columns - whose ground IS the floor, below 0 - drew a ring
		of water around the island.
	]]
	if water <= height then
		water = FLOOR_Y
	end

	genHeight[key] = height
	genBiome[key] = biome
	genTop[key] = top
	genUnder[key] = under
	genVariant[key] = variant
	genWater[key] = water
	genCount += 1

	Profiler.count("Terrain.columnSampled")
	return height, biome, top, under, variant, water
end

-- ---------------------------------------------------------------------------
-- Block templates and part pooling
-- ---------------------------------------------------------------------------

--[[
	Builds a stand-in part for a block that has no authored asset - bedrock and
	the ores, unless someone drops real parts into TerrainAssets.Blocks, in which
	case those win and this never runs for that name.

	Cloned from an existing block so it inherits the project's block size and
	surface settings rather than inventing its own.
]]
local function buildGeneratedTemplate(name, description)
	local donor = BlocksFolder:FindFirstChild("Stone")
		or BlocksFolder:FindFirstChildWhichIsA("BasePart")

	local part
	if donor and donor:IsA("BasePart") then
		part = donor:Clone()
		-- Decals from the donor would show the wrong texture on the new block.
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("Decal") or child:IsA("Texture") then
				child:Destroy()
			end
		end
	else
		part = Instance.new("Part")
		part.Size = Vector3.new(STUD_SIZE, STUD_SIZE, STUD_SIZE)
	end

	part.Name = name
	part.Color = description.color or Color3.fromRGB(120, 120, 120)
	part.Material = description.material or Enum.Material.Rock
	part.Reflectance = description.reflectance or 0
	part.Transparency = description.transparency or 0
	part.Anchored = true
	part.Parent = BlocksFolder

	return part
end

--[[
	Makes sure every block name the configs can produce has a template, building
	stand-ins for the ones that do not. Runs once at Init.
]]
local function ensureGeneratedTemplates()
	for name, description in pairs(BlockConfig.Generated) do
		if not BlocksFolder:FindFirstChild(name) then
			buildGeneratedTemplate(name, description)
		end
	end
end

--[[
	Reports what the block templates carry on their faces, and converts Decals
	into tiled Textures so runs of blocks can be merged.

	WHY THIS DECIDES WHETHER MERGING WORKS AT ALL

	A Decal STRETCHES to fill whatever face it is on. A Texture TILES, at
	StudsPerTile. On a single 4-stud cube the two are indistinguishable - one
	image, one face - which is why authored blocks are often either. On a Part
	stretched across ten blocks they are completely different: the Decal smears
	one image over the whole run, the Texture repeats ten times and looks
	exactly like ten cubes.

	So a Decal is unmergeable, and a block world made of Decals cannot be meshed
	at all. Converting is lossless on the cube it started as - same image, same
	face, same colour, same transparency, one tile per block - and is what makes
	the run version correct.

	The count is printed once, because "what is on my block faces" turned out to
	be the single most load-bearing fact about this renderer and it is not
	visible from anywhere in the source: the templates live in the place file.
]]
local function normaliseBlockFaces()
	local textures, decals, converted = 0, 0, 0

	local function visit(part)
		for _, child in ipairs(part:GetChildren()) do
			-- ClassName rather than IsA, because Texture derives from Decal.
			if child.ClassName == "Texture" then
				textures += 1
				child.StudsPerTileU = STUD_SIZE
				child.StudsPerTileV = STUD_SIZE
			elseif child.ClassName == "Decal" then
				decals += 1

				if TerrainConfig.ConvertDecalsToTextures then
					local texture = Instance.new("Texture")
					texture.Name = child.Name
					texture.Texture = child.Texture
					texture.Face = child.Face
					texture.Color3 = child.Color3
					texture.Transparency = child.Transparency
					texture.StudsPerTileU = STUD_SIZE
					texture.StudsPerTileV = STUD_SIZE
					texture.Parent = part

					child:Destroy()
					converted += 1
				end
			end
		end
	end

	for _, template in ipairs(BlocksFolder:GetChildren()) do
		if template:IsA("BasePart") then
			visit(template)
		elseif template:IsA("Model") then
			for _, descendant in ipairs(template:GetDescendants()) do
				if descendant:IsA("BasePart") then
					visit(descendant)
				end
			end
		end
	end

	print(string.format(
		"[TerrainManager] Block faces: %d texture(s), %d decal(s), %d converted to tiled textures.",
		textures, decals, converted
	))

	if decals > converted then
		warn(
			"[TerrainManager] Some block faces are still Decals. Decals cannot tile, so those "
				.. "blocks are drawn one Part per block and will hold the merge ratio down. Set "
				.. "TerrainConfig.ConvertDecalsToTextures = true to convert them."
		)
	end
end

local function resolveTemplateName(requested)
	local cached = resolvedTemplateName[requested]
	if cached ~= nil then
		return cached
	end

	if BlocksFolder:FindFirstChild(requested) then
		resolvedTemplateName[requested] = requested
		return requested
	end

	for _, fallbackName in ipairs(TerrainConfig.BlockFallbackOrder) do
		if BlocksFolder:FindFirstChild(fallbackName) then
			warn(string.format(
				"[TerrainManager] Missing block template '%s'; using '%s'.",
				tostring(requested), fallbackName
			))
			resolvedTemplateName[requested] = fallbackName
			return fallbackName
		end
	end

	warn(string.format(
		"[TerrainManager] Missing block template '%s' and no fallback was found.",
		tostring(requested)
	))
	resolvedTemplateName[requested] = false
	return false
end

local function getBlockPartTemplate(name)
	local actualName = resolveTemplateName(name)
	if not actualName then
		return nil
	end

	local cached = resolvedTemplatePart[actualName]
	if cached then
		return cached
	end

	local template = BlocksFolder:FindFirstChild(actualName)
	if template and template:IsA("BasePart") then
		resolvedTemplatePart[actualName] = template
		return template
	end

	if template and template:IsA("Model") then
		local part = template.PrimaryPart or template:FindFirstChildWhichIsA("BasePart")
		if part then
			resolvedTemplatePart[actualName] = part
			return part
		end
	end

	warn(string.format(
		"[TerrainManager] Block template '%s' is not a usable part/model.",
		tostring(actualName)
	))
	return nil
end

local function getPooledPart(name)
	local pool = partPool[name]
	if pool then
		local count = #pool
		if count > 0 then
			local part = pool[count]
			pool[count] = nil
			pooledParts -= 1

			local remaining = count - 1
			local low = poolLowWater[name]
			if low == nil or remaining < low then
				poolLowWater[name] = remaining
			end

			Profiler.count("Terrain.partReused")
			return part
		end
	end

	local template = getBlockPartTemplate(name)
	if not template then
		return nil
	end

	--[[
		Most blocks are solid opaque cubes and are forced to be, because an
		authored template can carry anything. The exceptions are declared in
		BlockConfig.Surfaces - water being the whole reason it exists: it has to
		be see-through so the bed reads through it, non-solid so a player wades
		instead of walking on it, and invisible to the mouse ray so aiming at a
		shoreline targets the ground rather than the surface.

		Read once per CLONE, not per placement, which is safe because the pool
		is keyed by block name: every part in a pool is the same kind of block.
	]]
	local surface = BlockConfig.surfaceFor(name)

	local part = template:Clone()
	part.Name = name
	part.Size = Vector3.new(STUD_SIZE, STUD_SIZE, STUD_SIZE)
	part.Anchored = true
	part.CanCollide = if surface then surface.collides ~= false else true
	part.CanQuery = if surface then surface.query ~= false else true
	part.CanTouch = false
	part.Transparency = if surface then surface.transparency or 0 else 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = TerrainConfig.CastTerrainShadows
	CollectionService:AddTag(part, "TerrainBlock")

	-- Pin every face texture to one tile per block, so a part stretched over a
	-- run of ten blocks shows ten tiles instead of one smeared image. On a 1x1
	-- part this is exactly what an untiled texture already did, so it changes
	-- nothing for blocks that never get merged.
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Texture") then
			child.StudsPerTileU = STUD_SIZE
			child.StudsPerTileV = STUD_SIZE
		end
	end

	Profiler.count("Terrain.partCloned")
	return part
end

--[[
	Returns a part to its pool.
]]
local function releasePart(part)
	if not part then
		return
	end

	part.Parent = nil
	partRect[part] = nil
	renderedParts -= 1

	local name = part.Name
	local pool = partPool[name]
	if not pool then
		pool = {}
		partPool[name] = pool
		-- A brand new pool has never been drawn from, so nothing is provably
		-- surplus yet. Starting at zero buys it one interval of grace before
		-- the trim starts measuring it.
		poolLowWater[name] = 0
	end

	if #pool < TerrainConfig.MaxPoolPerType then
		pool[#pool + 1] = part
		pooledParts += 1
	else
		part:Destroy()
		Profiler.count("Terrain.partDestroyed")
	end
end

--[[
	Shrinks the pools toward recent demand.

	A pool exists to absorb the gap between parts being released (a chunk
	unloading) and re-acquired (the next chunk loading). How wide that gap gets
	is a property of how the player is moving, which no fixed number can know -
	so this measures it instead of guessing.

	LOW WATER MARK. Every acquire records how few parts of that type were left
	behind. The smallest value seen across an interval is the number that sat
	untouched for the whole interval: nothing needed them, so they are surplus.
	Half the surplus is released each pass, which decays an idle pool
	geometrically while leaving a busy one - whose low water sits near zero -
	completely alone.

	This replaces trimming to a flat MaxPoolPerType, which never actually fired:
	releasePart already refuses to grow a pool past that cap, so the old trim
	could only ever find work if the cap had been lowered at runtime. The pools
	therefore only ever grew, and a session that had visited a snow biome kept
	its snow parts for the rest of the server's life.

	Bounded per pass, because destroying a few hundred Parts inside one frame is
	exactly the sort of spike the rest of this file works to avoid.
]]
local function trimPoolsIfNeeded()
	local now = os.clock()
	if now - lastPoolTrim < TerrainConfig.PoolTrimInterval then
		return
	end
	lastPoolTrim = now

	local hardLimit = TerrainConfig.MaxPoolPerType
	local floorSize = TerrainConfig.MinPoolPerType
	local fraction = TerrainConfig.PoolTrimFraction
	local budget = TerrainConfig.PoolTrimMaxPerTick

	for name, pool in pairs(partPool) do
		local size = #pool
		local target = size

		if target > hardLimit then
			target = hardLimit
		end

		local surplus = (poolLowWater[name] or 0) - floorSize
		if surplus > 0 then
			local shrunk = size - math.ceil(surplus * fraction)
			if shrunk < target then
				target = shrunk
			end
		end

		if target < floorSize then
			target = floorSize
		end

		while size > target and budget > 0 do
			local part = pool[size]
			pool[size] = nil
			size -= 1
			pooledParts -= 1
			budget -= 1
			if part then
				part:Destroy()
			end
			Profiler.count("Terrain.partTrimmed")
		end

		-- Restart the measurement from where the pool now stands, so the next
		-- interval reports its own idleness rather than inheriting this one's.
		poolLowWater[name] = size

		if budget <= 0 then
			break
		end
	end
end

local function warnForMissingTemplates()
	local seen = {}
	local missing = {}

	local function check(name)
		if name and not seen[name] then
			seen[name] = true
			if not BlocksFolder:FindFirstChild(name) then
				table.insert(missing, name)
			end
		end
	end

	for _, name in ipairs(TerrainConfig.BlockFallbackOrder) do
		check(name)
	end
	for _, biomeName in ipairs(BiomeConfig.Order) do
		local def = BiomeConfig.Definitions[biomeName]
		check(def.topBlock)
		check(def.underBlock)
	end
	for _, name in ipairs(OreRegistry.getBlockNames()) do
		check(name)
	end
	check(BEDROCK_BLOCK)
	check(StrataConfig.getDeepBlock())

	-- The surface blocks altitude can substitute for a biome's own, and the
	-- water. None of these belongs to any one biome, so nothing above catches
	-- them if that biome is ever removed.
	check(LandformConfig.RockBlock)
	check(LandformConfig.SnowBlock)
	check(WATER_BLOCK)

	if #missing > 0 then
		warn("[TerrainManager] Missing block templates: " .. table.concat(missing, ", "))
	end
end

-- ---------------------------------------------------------------------------
-- Chunk data access
-- ---------------------------------------------------------------------------
--
-- A chunk stores one flat array per property, indexed by cell. Flat arrays beat
-- nested [bx][bz] tables on both allocation count and lookup cost.
--
--   height        surface height as generated (never changes)
--   currentHeight surface height right now (drops as the top is mined)
--   topName       surface block name, from the biome
--   underName     subsurface block name, from the biome
--   biomeName     dominant biome for the column
--   jitter        per-column offset of the soil/stone boundary
--   topScan       exclusive upper bound for a full column scan
--   distLow       lowest y disturbed in this column (math.huge if untouched)
--   distHigh      highest y disturbed in this column (-math.huge if untouched)
--   parts         [by] -> rendered part
--   removed       [by] -> true, for holes punched below the surface
--   extra         [by] -> name, for blocks added above the terrain
--   override      [by] -> name, for column blocks a structure restyled
--   complex       true once a column has holes or extras, which disables the
--                 fast visibility path for it and its neighbours

--[[
	Is a block solid, given a loaded chunk's live data?
]]
local function isPresentInData(data, cell, by)
	if by < FLOOR_Y then
		return false
	end

	local extra = data.extra[cell]
	if extra and extra[by] then
		return true
	end

	if by >= data.currentHeight[cell] then
		return false
	end

	local removed = data.removed[cell]
	return not (removed and removed[by])
end

--[[
	Same question for an arbitrary position, which may be in another chunk or in
	a chunk that is not loaded. Unloaded chunks answer from the generated
	heightmap, which is exactly what they will contain once they do load - that
	is what keeps chunk borders seamless.
]]
local function isBlockPresent(cx, cz, bx, bz, by)
	if by < FLOOR_Y or by > MAX_BLOCK_Y then
		return false
	end

	cx, cz, bx, bz = normalizeCell(cx, cz, bx, bz)
	if not isChunkInBounds(cx, cz) then
		return false
	end

	local data = chunks[chunkKey(cx, cz)]
	if data then
		return isPresentInData(data, bx * CHUNK_SIZE + bz + 1, by)
	end

	local blockX = cx * CHUNK_SIZE + bx
	local blockZ = cz * CHUNK_SIZE + bz
	local height = getGeneratedColumn(blockX, blockZ)
	if by >= height then
		return false
	end

	-- The island carves out the space under itself at generation (see
	-- IslandShape.applyBlocks), which the heightmap alone does not show.
	if ColumnSource.baseAt then
		local base = ColumnSource.baseAt(blockX, blockZ)
		if base and by < base then
			return false
		end
	end

	-- Nor does it show the caves, which the chunk will carve when it loads.
	if CAVES_ENABLED and CaveMap.isAirAt(blockX, by, blockZ) then
		return false
	end

	return true
end

--[[
	Surface height, whether the column needs the slow visibility path, how
	deep/high it has been disturbed, and where its water stands.

	The water surface is here for the same reason the ground height is: a column
	only has to draw the part of its water that its neighbours do not already
	cover, so the interior of a lake is one block thick and only the shoreline
	pays for the edge wall.
]]
local function neighbourColumn(cx, cz, bx, bz)
	if not isChunkInBounds(cx, cz) then
		-- Outside the world. Reported as ground level rather than as the world
		-- floor on purpose: exposing the full depth of the border wall would
		-- render thousands of faces nobody can reach, since chunks beyond the
		-- bounds never load.
		return 0, false, math.huge, -math.huge, 0
	end

	local data = chunks[chunkKey(cx, cz)]
	if data then
		local cell = bx * CHUNK_SIZE + bz + 1
		return data.currentHeight[cell],
			data.complex[cell] == true,
			data.distLow[cell],
			data.distHigh[cell],
			data.waterTop[cell]
	end

	local blockX = cx * CHUNK_SIZE + bx
	local blockZ = cz * CHUNK_SIZE + bz
	local height, _biome, _top, _under, _variant, water = getGeneratedColumn(blockX, blockZ)

	-- An unloaded neighbour with a cave under it reports the cave as its
	-- disturbed band, exactly as it will once it loads. That puts this
	-- column on the general path now, so the wall it shares with the cave is
	-- drawn from the first frame instead of when the neighbour arrives.
	if CAVES_ENABLED then
		local record = CaveMap.getRecord(cx, cz)
		if not record.empty then
			local cell = bx * CHUNK_SIZE + bz + 1
			local low = record.low[cell]
			if low then
				return record.surface[cell] or height, true, low, record.high[cell], water
			end
		end
	end

	return height, false, math.huge, -math.huge, water
end

--[[
	Marks a column as disturbed at `by`, which is what tells the visibility pass
	that the band around `by` needs the slow six-face test. Everything outside
	the disturbed band stays buried and is never looked at.
]]
local function markDisturbed(data, cell, by)
	if by < data.distLow[cell] then
		data.distLow[cell] = by
	end
	if by > data.distHigh[cell] then
		data.distHigh[cell] = by
	end
	data.complex[cell] = true
end

--[[
	What block sits at (cell, by)?

	Order of precedence:
	  structure restyle  ->  added block / player placement  ->  natural terrain

	Natural terrain is resolved from the strata table plus an ore lookup, both
	pure functions of position and seed. Nothing about the column below the
	surface is stored, which is what lets the world be 190 blocks deep without
	the per-chunk cost changing at all.
]]
local function blockNameFor(data, cell, by)
	local override = data.override[cell]
	if override then
		local name = override[by]
		if name then
			return name
		end
	end

	local extra = data.extra[cell]
	if extra then
		local name = extra[by]
		if name then
			return name
		end
	end

	if by <= BEDROCK_TOP_Y then
		return BEDROCK_BLOCK
	end

	local height = data.height[cell]

	-- The surface block keeps its biome's top material only while the column is
	-- untouched; once the top has been mined, everything below is subsurface.
	if by == height - 1 and data.currentHeight[cell] == height then
		return data.topName[cell]
	end

	local depth = height - 1 - by
	local base = StrataConfig.blockAt(depth, data.underName[cell], data.jitter[cell])

	local index = cell - 1
	local ore = OreRegistry.blockAt(
		data.minBlockX + index // CHUNK_SIZE,
		by,
		data.minBlockZ + index % CHUNK_SIZE,
		base,
		depth
	)

	return ore or base
end

-- ---------------------------------------------------------------------------
-- Meshing
-- ---------------------------------------------------------------------------

--[[
	Can a run of this block be drawn as one stretched Part?

	A Texture tiles - StudsPerTile is set to one block when the part is built,
	so a 10-block run reads as ten tiles and looks identical to ten cubes. A
	Decal does NOT tile; it stretches to fit whatever face it is on, so spreading
	one across a run would smear a single image over the whole thing. Those
	blocks fall back to one Part each.

	Cached: it is a property of the template, and the answer is needed once per
	emitted rectangle.
]]
local mergeableByName = {}

local function isMergeable(blockName)
	local cached = mergeableByName[blockName]
	if cached ~= nil then
		return cached
	end

	local mergeable = true
	local template = getBlockPartTemplate(blockName)
	if template then
		-- Stretching a wedge, sphere, or authored mesh across a rectangle
		-- creates slivers and uncovered cells. Only full cubes can tile it.
		mergeable = template:IsA("Part") and template.Shape == Enum.PartType.Block
		for _, child in ipairs(template:GetChildren()) do
			-- ClassName, NOT IsA. Texture derives from Decal in Roblox, so
			-- IsA("Decal") is true for a Texture as well - which marked every
			-- textured block in the game unmergeable and pinned the merge ratio
			-- at exactly 1.00. A ratio of precisely 1 is what gave it away: real
			-- terrain would have produced some ragged fraction.
			if child.ClassName == "Decal" or child:IsA("DataModelMesh") then
				mergeable = false
				break
			end
		end
	end

	mergeableByName[blockName] = mergeable
	return mergeable
end

--[[
	Emits one rectangle of identical blocks as a single Part.

	sizeX / sizeZ are in blocks. A 1x1 rectangle is exactly the cube the old
	renderer drew, so the unmerged mode costs nothing extra here.
]]
local function emitMeshPart(data, bx, bz, sizeX, sizeZ, by, blockName)
	local part = getPooledPart(blockName)
	if not part then
		return nil
	end

	part.Name = blockName
	part.Size = Vector3.new(sizeX * STUD_SIZE, STUD_SIZE, sizeZ * STUD_SIZE)
	part.CFrame = CFrame.new(
		(data.minBlockX + bx) * STUD_SIZE + sizeX * STUD_SIZE * 0.5,
		by * STUD_SIZE + STUD_SIZE * 0.5,
		(data.minBlockZ + bz) * STUD_SIZE + sizeZ * STUD_SIZE * 0.5
	)

	partRect[part] = {
		cx = data.cx,
		cz = data.cz,
		bx = bx,
		bz = bz,
		sizeX = sizeX,
		sizeZ = sizeZ,
		by = by,
	}

	part.Parent = data.model
	renderedParts += 1

	Profiler.count("Terrain.partPlaced")
	return part
end

-- Scratch, reused across every layer of every chunk. Meshing never yields, so
-- nothing can observe these half-written.
local layerGrid = {}
local layerRects = {}

--[[
	Moves an existing part onto a different rectangle instead of replacing it.

	This is the whole reason the reconciliation below is worth its complexity.
	Releasing a part unparents it and emitting one parents it again, and to every
	client that reads as "this block was deleted, and a different one appeared" -
	so rebuilding a layer from scratch would make the ground around a player
	flicker every single time they mined a block. Moving and resizing a part that
	stays parented replicates as a property change, which does not.
]]
local function reshapeMeshPart(data, part, bx, bz, sizeX, sizeZ, by)
	part.Size = Vector3.new(sizeX * STUD_SIZE, STUD_SIZE, sizeZ * STUD_SIZE)
	part.CFrame = CFrame.new(
		(data.minBlockX + bx) * STUD_SIZE + sizeX * STUD_SIZE * 0.5,
		by * STUD_SIZE + STUD_SIZE * 0.5,
		(data.minBlockZ + bz) * STUD_SIZE + sizeZ * STUD_SIZE * 0.5
	)

	local rect = partRect[part]
	if rect then
		rect.cx = data.cx
		rect.cz = data.cz
		rect.bx = bx
		rect.bz = bz
		rect.sizeX = sizeX
		rect.sizeZ = sizeZ
		rect.by = by
	else
		partRect[part] = {
			cx = data.cx, cz = data.cz,
			bx = bx, bz = bz,
			sizeX = sizeX, sizeZ = sizeZ,
			by = by,
		}
	end

	Profiler.count("Terrain.partReshaped")
end

-- The mesher's rectangles after decalled blocks have been split back into
-- cubes: five entries each, same layout as layerRects.
local finalRects = {}

--[[
	EDIT ZONES

	Merging is what keeps the part count affordable, and it is also what makes
	editing jitter: break one block out of a slab and the slab has to become
	several new Parts, which every client receives a moment after the old slab
	went. At an end-game mining speed that is a visible flicker every swing, and
	a floor that can vanish under you.

	So the ground around an edit is drawn differently for a while:

	  * every block is its own Part - breaking one removes exactly that Part,
	    and nothing else on screen changes;
	  * the layers just under the exposed ones are drawn too (EditZone.Depth),
	    hidden behind the surface. The block a break uncovers is therefore
	    already standing on every client before the break happens; the only
	    new Parts an edit needs are the ones it will uncover NEXT time.

	A zone is opened around a mining target when the swing starts (MiningServer)
	and around every break and placement, and lasts EditZone.Seconds after the
	last one, after which it merges back into slabs.

	data.hot[cell] is when that column's zone time runs out.
]]
local EDIT_ZONE = TerrainConfig.EditZone
local EDIT_RADIUS = EDIT_ZONE.Radius
local EDIT_DEPTH = EDIT_ZONE.Depth
local EDIT_SECONDS = EDIT_ZONE.Seconds
local RETIRE_SECONDS = EDIT_ZONE.RetireSeconds

local function rectKey(bx, bz, sizeX, sizeZ)
	-- Sizes run 1..ChunkSize, so 32 leaves room; bx/bz are 0..ChunkSize-1.
	return ((bx * CHUNK_SIZE + bz) * 32 + sizeX) * 32 + sizeZ
end

local function markLayerDirty(data, by)
	if not data.dirtyLayers[by] then
		data.dirtyLayers[by] = true
		data.dirtyCount += 1
	end
end

--[[
	Works out how one Y layer of a chunk should be drawn, without touching any
	Part yet - applyLayerPlans does that, for every layer of an edit at once.

	A Part already drawing EXACTLY one of the new rectangles is kept, untouched.
	Every other rectangle gets a new Part. Existing Parts are never moved or
	resized: a Part moving under a client is visible as jitter, and shrinking a
	slab before the pieces replacing it have arrived opens a hole.

	A Part nothing wants any more is either released at once - when none of
	the ground it covered is still drawn (a mined block) - or RETIRED: left in
	place a moment longer because the ground it covers is still there and the
	Parts now drawing it are new and may not have reached every client yet.
]]
local function planLayer(data, by)
	table.clear(layerGrid)

	local visible = data.visible
	local hot = data.hot

	-- cell -> name of every block drawn on this layer, zone or not, for
	-- deciding below whether an old Part still covers anything.
	local drawn = {}
	local hotCells = {}

	for cell = 1, CHUNK_AREA do
		local name = visible[cell][by]
		if name ~= nil then
			drawn[cell] = name
			if hot[cell] then
				table.insert(hotCells, cell)
			else
				layerGrid[cell] = name
			end
		end
	end

	local plan = {
		data = data,
		by = by,
		rects = {}, -- five entries per rectangle: bx, bz, sizeX, sizeZ, name
		count = 0,
		parts = {}, -- rectangle -> the Part that will draw it
		release = {}, -- old Parts covering nothing that is still drawn
		retire = {}, -- old Parts covering ground that is still drawn
	}

	-- Rectangles: merged outside edit zones, one per block inside them.
	table.clear(layerRects)
	local count = TerrainMesher.meshLayer(
		layerGrid, CHUNK_SIZE, TerrainConfig.MergeSurfaceRuns, layerRects
	)

	table.clear(finalRects)
	local write = 0

	local function push(bx, bz, sizeX, sizeZ, name)
		finalRects[write + 1] = bx
		finalRects[write + 2] = bz
		finalRects[write + 3] = sizeX
		finalRects[write + 4] = sizeZ
		finalRects[write + 5] = name
		write += 5
	end

	for index = 0, count - 1 do
		local base = index * 5
		local bx = layerRects[base + 1]
		local bz = layerRects[base + 2]
		local sizeX = layerRects[base + 3]
		local sizeZ = layerRects[base + 4]
		local name = layerRects[base + 5]

		if (sizeX > 1 or sizeZ > 1) and not isMergeable(name) then
			-- Decalled block. Broken back into cubes rather than smearing one
			-- decal across the whole run.
			for dx = 0, sizeX - 1 do
				for dz = 0, sizeZ - 1 do
					push(bx + dx, bz + dz, 1, 1, name)
				end
			end
		else
			push(bx, bz, sizeX, sizeZ, name)
		end
	end

	for _, cell in ipairs(hotCells) do
		local index = cell - 1
		push(index // CHUNK_SIZE, index % CHUNK_SIZE, 1, 1, drawn[cell])
	end

	-- Copied out of the scratch buffer: plans are applied after every dirty
	-- layer has been planned, and the next planLayer reuses finalRects.
	local rects = plan.rects
	table.move(finalRects, 1, write, 1, rects)
	plan.count = write // 5

	local existing = data.layerParts[by]
	if not existing or #existing == 0 then
		return plan
	end

	-- Exact matches, through a lookup so a big layer is not n * m.
	local byShape = {}
	for index, part in ipairs(existing) do
		local rect = partRect[part]
		if rect then
			local key = rectKey(rect.bx, rect.bz, rect.sizeX, rect.sizeZ)
			local list = byShape[key]
			if not list then
				list = {}
				byShape[key] = list
			end
			table.insert(list, index)
		end
	end

	local taken = {}
	for r = 1, plan.count do
		local base = (r - 1) * 5
		local list = byShape[rectKey(rects[base + 1], rects[base + 2], rects[base + 3], rects[base + 4])]
		if list then
			for _, index in ipairs(list) do
				local part = existing[index]
				if not taken[index] and part.Name == rects[base + 5] then
					taken[index] = true
					plan.parts[r] = part
					break
				end
			end
		end
	end

	for index, part in ipairs(existing) do
		if not taken[index] then
			local rect = partRect[part]
			local stillDrawn = false

			if rect then
				for dx = 0, rect.sizeX - 1 do
					for dz = 0, rect.sizeZ - 1 do
						if drawn[cellOf(rect.bx + dx, rect.bz + dz)] then
							stillDrawn = true
							break
						end
					end
					if stillDrawn then
						break
					end
				end
			end

			table.insert(if stillDrawn then plan.retire else plan.release, part)
		end
	end

	return plan
end

--[[
	A Part leaving the screen a moment from now rather than at once - see
	planLayer. Kept parented and drawing its old rectangle until then; tracked
	on the chunk so an unload can release it early.
]]
local function retirePart(data, part)
	data.retiring[part] = true
	task.delay(RETIRE_SECONDS, function()
		if data.retiring[part] then
			data.retiring[part] = nil
			releasePart(part)
		end
	end)
end

--[[
	Applies a set of layer plans: every new Part first, on every layer, then
	removals. `immediate` releases retiring Parts at once instead of after the
	delay - for an ability crater, where the hole should open with the blast.
]]
local function applyLayerPlans(plans, immediate)
	for _, plan in ipairs(plans) do
		local rects = plan.rects
		for r = 1, plan.count do
			if not plan.parts[r] then
				local base = (r - 1) * 5
				-- false only when the block has no usable template, which
				-- warns elsewhere.
				plan.parts[r] = emitMeshPart(
					plan.data, rects[base + 1], rects[base + 2], rects[base + 3], rects[base + 4],
					plan.by, rects[base + 5]
				) or false
			end
		end
	end

	for _, plan in ipairs(plans) do
		for _, part in ipairs(plan.release) do
			releasePart(part)
		end

		for _, part in ipairs(plan.retire) do
			if immediate then
				releasePart(part)
			else
				retirePart(plan.data, part)
			end
		end

		local bucket = {}
		for r = 1, plan.count do
			local part = plan.parts[r]
			if part then
				table.insert(bucket, part)
			end
		end

		plan.data.layerParts[plan.by] = if #bucket > 0 then bucket else nil
		Profiler.count("Terrain.layerMeshed")
	end
end

--[[
	Rebuilds every layer that changed since the last flush, across every chunk
	given - an edit on a chunk border changes two chunks, and they have to be
	applied together for new-before-old to hold across the border.

	Visibility is decided per column, but a Part spans columns, so the two
	cannot be done in one step: the whole column pass has to finish before the
	layers it touched can be meshed. Callers do a batch of column updates and
	then flush once.
]]
local function flushChunks(list, immediate)
	local plans = {}

	for _, data in ipairs(list) do
		if data.dirtyCount > 0 then
			for by in pairs(data.dirtyLayers) do
				table.insert(plans, planLayer(data, by))
			end
			table.clear(data.dirtyLayers)
			data.dirtyCount = 0
		end
	end

	if #plans > 0 then
		applyLayerPlans(plans, immediate)
	end
end

local function flushChunkMesh(data)
	flushChunks({ data })
end

--[[
	Records that a block should be drawn, and that its layer therefore needs
	rebuilding.

	Writing the same name again is deliberately free. Re-running visibility over
	an unchanged column is common - every edit refreshes its four neighbours -
	and marking those layers dirty would remesh the whole chunk for nothing.
]]
local function setVisible(data, cell, by, blockName)
	local column = data.visible[cell]
	local previous = column[by]

	if previous ~= blockName then
		if previous == nil then
			visibleBlocks += 1
			data.visibleCount += 1
		end

		column[by] = blockName

		if not data.dirtyLayers[by] then
			data.dirtyLayers[by] = true
			data.dirtyCount += 1
		end
	end
end

local function clearVisible(data, cell, by)
	local column = data.visible[cell]

	if column[by] ~= nil then
		column[by] = nil
		visibleBlocks -= 1
		data.visibleCount -= 1

		if not data.dirtyLayers[by] then
			data.dirtyLayers[by] = true
			data.dirtyCount += 1
		end
	end
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------

--[[
	Decides which blocks of one column need a real part.

	A block is worth rendering only if one of its six faces is exposed.

	FAST PATH. In an untouched column - no mined holes, no added blocks, and the
	same for its four neighbours - a block is exposed exactly when it is the top
	block or when it sits at or above the shortest neighbouring column. So the
	visible band is simply [min(neighbourHeights), currentHeight - 1] and
	everything buried below it is never looked at. This is why the world can be
	160 blocks deep and still cost one part per flat column.

	GENERAL PATH. Once a column or one of its neighbours has been dug into, some
	blocks below the surface band may be exposed. Rather than scan the whole
	column - which is what would make a deep world expensive - each column
	remembers the band it has actually been disturbed in, and only that band plus
	the surface band is tested. A tunnel 140 blocks down therefore costs a
	handful of tests, not 190.
]]
--[[
	The six-face test, over one contiguous band of a column.

	Deliberately a top-level function rather than a closure inside
	updateColumnVisibility: that runs once per column per chunk load, and a
	closure there would allocate on every single call.
]]
local function scanColumnRange(data, cx, cz, bx, bz, cell, column, low, high, waterLow, waterHigh, force)
	for by = low, high do
		if not isPresentInData(data, cell, by) then
			-- Anything in the water band belongs to the water pass below, which
			-- runs after this one. Clearing it here would delete the surface and
			-- then have it put straight back, dirtying the layer every time a
			-- neighbouring chunk loads.
			if by >= waterLow and by <= waterHigh then
				-- left alone
			elseif column[by] ~= nil then
				clearVisible(data, cell, by)
			end
		else
			-- In an edit zone every block in the band is drawn, exposed or not:
			-- that is the layer of warning a fast edit needs. See EDIT ZONES.
			local visible = force or not isBlockPresent(cx, cz, bx, bz, by + 1)

			if not visible and by > FLOOR_Y and not isBlockPresent(cx, cz, bx, bz, by - 1) then
				visible = true
			end

			if not visible then
				for i = 1, 4 do
					if not isBlockPresent(cx, cz, bx + DIR_X[i], bz + DIR_Z[i], by) then
						visible = true
						break
					end
				end
			end

			if visible then
				-- As in the fast path: an already-drawn block keeps the name it
				-- was given. Anything that could change that name - a mined
				-- block, a placement, a structure override - clears the slot
				-- first, so a filled slot is by construction still correct.
				if column[by] == nil then
					setVisible(data, cell, by, blockNameFor(data, cell, by))
				end
			elseif column[by] ~= nil then
				clearVisible(data, cell, by)
			end
		end
	end
end

local function updateColumnVisibility(cx, cz, bx, bz)
	local data = chunks[chunkKey(cx, cz)]
	if not data then
		return
	end

	Profiler.enter("Terrain.columnVisibility")

	local cell = cellOf(bx, bz)
	local column = data.visible[cell]
	local currentHeight = data.currentHeight[cell]

	-- In an edit zone: drawn a little deeper, every block in the bands. Always
	-- the general path, which is the one that knows how to.
	local zoned = data.hot[cell] ~= nil
	local extra = if zoned then EDIT_DEPTH else 0

	local minNeighbour = math.huge
	local bandLow = data.distLow[cell]
	local bandHigh = data.distHigh[cell]
	local neighbourComplex = false

	-- The lowest point any neighbour covers, counting its own water as cover.
	-- This is what makes a lake interior one block thick: its neighbours' water
	-- reaches the same level, so there is no edge to draw.
	local minCover = math.huge

	for i = 1, 4 do
		local ncx, ncz, nbx, nbz = normalizeCell(cx, cz, bx + DIR_X[i], bz + DIR_Z[i])
		local height, complex, low, high, water = neighbourColumn(ncx, ncz, nbx, nbz)
		if height < minNeighbour then
			minNeighbour = height
		end

		local cover = if water > height then water else height
		if cover < minCover then
			minCover = cover
		end

		if complex then
			neighbourComplex = true
		end
		if low < bandLow then
			bandLow = low
		end
		if high > bandHigh then
			bandHigh = high
		end
	end

	-- Lower edge of the surface band, shared by both paths.
	local surfaceLow = minNeighbour
	if surfaceLow > currentHeight - 1 then
		surfaceLow = currentHeight - 1
	end
	if surfaceLow < FLOOR_Y then
		surfaceLow = FLOOR_Y
	end

	--[[
		No water is drawn here any more. Water is Roblox Terrain, written as a
		whole volume by syncColumnWater - see WATER below for why. The band is
		kept, empty, so the block passes below still have one place that says
		which cells are not theirs to touch.

		Water is still NOT part of the heightmap: `currentHeight` is the top of
		the solid ground, so mining, placement and the strata below are all
		untouched by it.
	]]
	local waterLow, waterHigh = 1, 0 -- empty

	if not data.complex[cell] and not neighbourComplex and not zoned then
		if currentHeight <= FLOOR_Y then
			for by in pairs(column) do
				clearVisible(data, cell, by)
			end
			Profiler.leave("Terrain.columnVisibility")
			return
		end

		for by in pairs(column) do
			if
				(by < surfaceLow or by >= currentHeight)
				and not (by >= waterLow and by <= waterHigh)
			then
				clearVisible(data, cell, by)
			end
		end

		-- Only blocks that are not already drawn need their name worked out.
		-- On this path the column and its neighbours are untouched, so
		-- blockNameFor is a pure function of position that cannot have changed
		-- since the slot was filled - and it is not cheap, being a strata
		-- lookup plus an ore lookup. Border refreshes re-run this pass over
		-- sixteen columns per neighbouring chunk load, so skipping the settled
		-- ones matters.
		for by = surfaceLow, currentHeight - 1 do
			if column[by] == nil then
				setVisible(data, cell, by, blockNameFor(data, cell, by))
			end
		end

		Profiler.leave("Terrain.columnVisibility")
		return
	end

	-- General path. Two bands: the surface, and whatever has been dug into.
	-- One block of margin on the disturbed band covers the blocks that line a
	-- hole from below and above.
	local scanTop = data.topScan[cell]

	local lowA, highA = surfaceLow - extra, scanTop - 1
	if lowA < FLOOR_Y then
		lowA = FLOOR_Y
	end
	local lowB, highB = 1, 0 -- empty by default

	if bandLow <= bandHigh then
		lowB = bandLow - 1 - extra
		highB = bandHigh + 1 + extra
		if lowB < FLOOR_Y then
			lowB = FLOOR_Y
		end
		if highB > scanTop - 1 then
			highB = scanTop - 1
		end

		if highB >= lowA - 1 then
			-- The bands touch; treat them as one so nothing is tested twice.
			if lowB < lowA then
				lowA = lowB
			end
			lowB, highB = 1, 0
		end
	end

	for by in pairs(column) do
		if
			not ((by >= lowA and by <= highA) or (by >= lowB and by <= highB))
			and not (by >= waterLow and by <= waterHigh)
		then
			clearVisible(data, cell, by)
		end
	end

	scanColumnRange(data, cx, cz, bx, bz, cell, column, lowB, highB, waterLow, waterHigh, zoned)
	scanColumnRange(data, cx, cz, bx, bz, cell, column, lowA, highA, waterLow, waterHigh, zoned)

	Profiler.count("Terrain.columnSlowPath")
	Profiler.leave("Terrain.columnVisibility")
end

-- ---------------------------------------------------------------------------
-- Water
-- ---------------------------------------------------------------------------

--[[
	Water is Roblox Terrain, not blocks.

	It used to be drawn like any other block - see-through Parts, culled to the
	band a viewer could see - and that could never work as water:

	  * nobody can swim in a Part. Humanoids only swim in Terrain water, which
	    is also what gives the underwater tint and the swim animation;
	  * culling drew a lake as a skin one block deep, so diving through the
	    surface left you standing in nothing;
	  * every seam between two transparent Parts showed through.

	Terrain voxels are four studs, exactly a block, so a water cell is one voxel
	and the two grids agree everywhere. Water fills [currentHeight, waterTop) in
	a column, except for any cell holding a block - which is how a block placed
	in a lake displaces the water around it, and a lake bed mined out fills in.

	The server writes it; it replicates to every client like any other terrain.
	A chunk's water is written once when the chunk is built, one column at a time
	after each edit, and cleared when the chunk unloads. data.waterLow/waterHigh
	remember how far down and up this chunk has ever written, so unloading can
	clear exactly that.
]]
local TerrainVoxels = workspace.Terrain
local WATER_MATERIAL = Enum.Material.Water
local AIR_MATERIAL = Enum.Material.Air

--[[
	Writes a box of voxels, in BLOCK coordinates, as water wherever
	isWet(ix, iy, iz) says (0-based offsets into the box) and air elsewhere.
]]
local function writeWaterBox(minX, minY, minZ, sizeX, sizeY, sizeZ, isWet)
	if sizeX <= 0 or sizeY <= 0 or sizeZ <= 0 then
		return
	end

	local materials = table.create(sizeX)
	local occupancy = table.create(sizeX)

	for ix = 0, sizeX - 1 do
		local materialX = table.create(sizeY)
		local occupancyX = table.create(sizeY)
		materials[ix + 1] = materialX
		occupancy[ix + 1] = occupancyX

		for iy = 0, sizeY - 1 do
			local materialY = table.create(sizeZ)
			local occupancyY = table.create(sizeZ)
			materialX[iy + 1] = materialY
			occupancyX[iy + 1] = occupancyY

			for iz = 0, sizeZ - 1 do
				local wet = isWet(ix, iy, iz)
				materialY[iz + 1] = if wet then WATER_MATERIAL else AIR_MATERIAL
				occupancyY[iz + 1] = if wet then 1 else 0
			end
		end
	end

	local low = Vector3.new(minX, minY, minZ) * STUD_SIZE
	local high = Vector3.new(minX + sizeX, minY + sizeY, minZ + sizeZ) * STUD_SIZE
	TerrainVoxels:WriteVoxels(Region3.new(low, high), STUD_SIZE, materials, occupancy)
end

local function isWaterCell(data, cell, by)
	return by >= data.currentHeight[cell]
		and by < data.waterTop[cell]
		and not isPresentInData(data, cell, by)
end

local function widenWaterSpan(data, low, high)
	if not data.waterLow or low < data.waterLow then
		data.waterLow = low
	end
	if not data.waterHigh or high > data.waterHigh then
		data.waterHigh = high
	end
end

-- Every wet column of a freshly built chunk, in one write.
local function syncChunkWater(data)
	local low, high = math.huge, -math.huge
	for cell = 1, CHUNK_AREA do
		local bottom = data.currentHeight[cell]
		local top = data.waterTop[cell]
		if top > bottom then
			if bottom < low then
				low = bottom
			end
			if top > high then
				high = top
			end
		end
	end

	if low >= high then
		return -- a dry chunk, which is nearly all of them
	end

	widenWaterSpan(data, low, high)

	writeWaterBox(data.minBlockX, low, data.minBlockZ, CHUNK_SIZE, high - low, CHUNK_SIZE, function(ix, iy, iz)
		return isWaterCell(data, cellOf(ix, iz), low + iy)
	end)
end

--[[
	One column after an edit. Covers everything from the column's current floor
	to its water surface, so a block placed in the water clears its cell and a
	mined-out lake bed fills.
]]
local function syncColumnWater(data, cell)
	local bottom = data.currentHeight[cell]
	local top = data.waterTop[cell]
	if top <= bottom then
		return -- dry, and nothing here was ever water
	end

	widenWaterSpan(data, bottom, top)

	local index = cell - 1
	writeWaterBox(
		data.minBlockX + index // CHUNK_SIZE, bottom, data.minBlockZ + index % CHUNK_SIZE,
		1, top - bottom, 1,
		function(_, iy)
			return isWaterCell(data, cell, bottom + iy)
		end
	)
end

-- Removes everything this chunk ever wrote, as it unloads.
local function clearChunkWater(data)
	if not data.waterLow then
		return
	end

	writeWaterBox(
		data.minBlockX, data.waterLow, data.minBlockZ,
		CHUNK_SIZE, data.waterHigh - data.waterLow, CHUNK_SIZE,
		function()
			return false
		end
	)

	data.waterLow, data.waterHigh = nil, nil
end

--[[
	Re-evaluates a column and its four neighbours after an edit, then rebuilds
	whatever layers that touched.

	The flush happens once, after all five columns have settled, and covers every
	chunk involved - an edit on a chunk border moves blocks in two of them, and
	meshing one before the other had finished would build a rectangle out of a
	half-updated layer.
]]
local function refreshAdjacentColumns(cx, cz, bx, bz, immediate)
	local touched = {}

	local own = chunks[chunkKey(cx, cz)]
	if own then
		touched[own] = true
		-- Only the edited column's water can have changed: water does not flow,
		-- so a neighbour's stays exactly where it was.
		syncColumnWater(own, cellOf(bx, bz))
	end

	updateColumnVisibility(cx, cz, bx, bz)

	for i = 1, 4 do
		local ncx, ncz, nbx, nbz = normalizeCell(cx, cz, bx + DIR_X[i], bz + DIR_Z[i])
		if isChunkInBounds(ncx, ncz) then
			local nkey = chunkKey(ncx, ncz)
			local neighbour = chunks[nkey]
			if neighbour and generatingChunks[nkey] then
				-- Never draw a half-built chunk; see refreshChunkBorders.
				neighbour.bordersStale = true
			elseif neighbour then
				touched[neighbour] = true
				updateColumnVisibility(ncx, ncz, nbx, nbz)
			end
		end
	end

	-- Together, so new Parts in one chunk are made before old ones in the
	-- other are removed. See applyLayerPlans.
	local list = {}
	for data in pairs(touched) do
		table.insert(list, data)
	end
	flushChunks(list, immediate)
end

-- ---------------------------------------------------------------------------
-- Edit zones (see EDIT ZONES above)
-- ---------------------------------------------------------------------------

-- Redraws one column for a zone opening or closing on it: the visibility
-- pass picks up the change in depth, and every layer it draws is remeshed so
-- its blocks are split out of (or merged back into) the slabs around them.
local function redrawZoneColumn(data, cell, touched)
	local index = cell - 1
	updateColumnVisibility(data.cx, data.cz, index // CHUNK_SIZE, index % CHUNK_SIZE)
	for by in pairs(data.visible[cell]) do
		markLayerDirty(data, by)
	end
	touched[data] = true
end

local function flushTouched(touched)
	local list = {}
	for data in pairs(touched) do
		table.insert(list, data)
	end
	flushChunks(list)
end

--[[
	Opens (or extends) an edit zone around a block position. Columns already
	in a zone just get more time; only newly zoned ones are redrawn, so calling
	this on every swing costs next to nothing once the zone exists.
]]
local function openEditZone(blockX, blockZ)
	local expiresAt = os.clock() + EDIT_SECONDS
	local touched = {}

	for dx = -EDIT_RADIUS, EDIT_RADIUS do
		for dz = -EDIT_RADIUS, EDIT_RADIUS do
			local x, z = blockX + dx, blockZ + dz
			local cx, cz, bx, bz = normalizeCell(x // CHUNK_SIZE, z // CHUNK_SIZE, x % CHUNK_SIZE, z % CHUNK_SIZE)
			local key = chunkKey(cx, cz)
			local data = chunks[key]

			if data and not generatingChunks[key] then
				local cell = cellOf(bx, bz)
				local was = data.hot[cell]
				data.hot[cell] = expiresAt

				if not was then
					data.hotCount += 1
					redrawZoneColumn(data, cell, touched)
				end
			end
		end
	end

	flushTouched(touched)
end

-- Merges zones nobody has edited in EditZone.Seconds back into slabs.
local lastZoneSweep = 0

local function closeExpiredEditZones()
	local now = os.clock()
	if now - lastZoneSweep < 1 then
		return
	end
	lastZoneSweep = now

	local touched = {}

	for key, data in pairs(chunks) do
		if data.hotCount > 0 and not generatingChunks[key] then
			for cell, expiresAt in pairs(data.hot) do
				if expiresAt <= now then
					data.hot[cell] = nil
					data.hotCount -= 1
					redrawZoneColumn(data, cell, touched)
				end
			end
		end
	end

	flushTouched(touched)
end

--[[
	Re-evaluates the border columns of already-loaded neighbours after a chunk
	appears. Heights alone would not need this (an unloaded neighbour already
	answers with its generated height), but added blocks would: a boulder that
	spills across the border only exists once both chunks are built.

	A neighbour that is itself still generating is NOT touched. It sits in
	`chunks` from its structure phase onward, so flushing it here would mesh and
	publish whatever part of it was drawn so far - before its structures and
	replayed edits were in - and its own flush a few frames later would then
	replace those Parts with differently shaped ones. With two chunks in flight
	side by side that is the pop and flicker at the streaming edge. It is
	flagged instead, and re-reads its own borders before its one flush.
]]
local function refreshChunkBorders(cx, cz)
	for i = 1, 4 do
		local ncx = cx + DIR_X[i]
		local ncz = cz + DIR_Z[i]

		local nkey = chunkKey(ncx, ncz)
		local neighbour = isChunkInBounds(ncx, ncz) and chunks[nkey]
		if neighbour and generatingChunks[nkey] then
			neighbour.bordersStale = true
		elseif neighbour then
			for j = 0, CHUNK_SIZE - 1 do
				local bx, bz
				if DIR_X[i] == 1 then
					bx, bz = 0, j
				elseif DIR_X[i] == -1 then
					bx, bz = CHUNK_SIZE - 1, j
				elseif DIR_Z[i] == 1 then
					bx, bz = j, 0
				else
					bx, bz = j, CHUNK_SIZE - 1
				end
				updateColumnVisibility(ncx, ncz, bx, bz)
			end

			-- Whole border done; now the neighbour's affected layers can be
			-- rebuilt as complete rows rather than sixteen times over.
			flushChunkMesh(neighbour)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Terrain edits
-- ---------------------------------------------------------------------------

--[[
	Marks one solid block gone.

	Removing the top of a column lowers the column instead of recording a hole,
	which is what keeps ordinary surface mining - and digging straight down - on
	the fast visibility path.
]]
local function markRemoved(data, cell, by)
	local currentHeight = data.currentHeight[cell]

	if by == currentHeight - 1 then
		local newHeight = currentHeight - 1
		local removed = data.removed[cell]
		if removed then
			while newHeight > FLOOR_Y and removed[newHeight - 1] do
				newHeight -= 1
			end
		end
		data.currentHeight[cell] = newHeight
	else
		local removed = data.removed[cell]
		if not removed then
			removed = {}
			data.removed[cell] = removed
		end
		removed[by] = true
		markDisturbed(data, cell, by)
	end
end

--[[
	Applies a removal the way BreakBlock does, without any of the validation.
	Used to replay stored player edits onto a freshly generated chunk.
]]
local function applyRemoval(data, cell, by)
	local extra = data.extra[cell]
	if extra and extra[by] then
		extra[by] = nil
		markDisturbed(data, cell, by)
		return
	end

	if by >= FLOOR_Y and by < data.currentHeight[cell] then
		markRemoved(data, cell, by)
	end
end

local function applyPlacement(data, cell, by, name)
	if by < FLOOR_Y or by > MAX_BLOCK_Y or isPresentInData(data, cell, by) then
		return
	end

	local extra = data.extra[cell]
	if not extra then
		extra = {}
		data.extra[cell] = extra
	end

	extra[by] = name
	markDisturbed(data, cell, by)
	if by + 1 > data.topScan[cell] then
		data.topScan[cell] = by + 1
	end
end

-- ---------------------------------------------------------------------------
-- Structure writer
-- ---------------------------------------------------------------------------

--[[
	The interface StructureRegistry writes through. Coordinates arrive as
	absolute block positions; anything outside this chunk is dropped, because
	the chunk that owns those cells recomputes the same structure and writes its
	own share.
]]
local function makeWriter(cx, cz, data)
	local minBlockX = cx * CHUNK_SIZE
	local minBlockZ = cz * CHUNK_SIZE

	local function toCell(blockX, blockZ)
		local bx = blockX - minBlockX
		local bz = blockZ - minBlockZ
		if bx < 0 or bx >= CHUNK_SIZE or bz < 0 or bz >= CHUNK_SIZE then
			return nil
		end
		return bx * CHUNK_SIZE + bz + 1
	end

	return {
		setBlock = function(blockX, blockZ, by, name)
			if by < FLOOR_Y or by > MAX_BLOCK_Y or type(name) ~= "string" then
				return
			end

			local cell = toCell(blockX, blockZ)
			if not cell then
				return
			end

			applyPlacement(data, cell, by, name)
		end,

		overrideBlock = function(blockX, blockZ, by, name)
			if type(name) ~= "string" then
				return
			end

			local cell = toCell(blockX, blockZ)
			if not cell or by < FLOOR_Y or by >= data.currentHeight[cell] then
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
		end,

		carve = function(blockX, blockZ, by)
			local cell = toCell(blockX, blockZ)
			if not cell or by < FLOOR_Y or by >= data.currentHeight[cell] then
				return
			end
			markRemoved(data, cell, by)
		end,

		--[[
			The surface height of a column AS THIS CHUNK WILL RENDER IT, or nil
			for a column this chunk does not own.

			The generated heightmap is not the same answer. By the time models
			are placed this chunk has already had structure blocks written into
			it and every stored player edit replayed over the top, so a column
			whose ground somebody raised or mined reads higher or lower here
			than the generator would ever say. A tree seated on the generated
			height would sink into the ground somebody built up, and would do it
			again every time the chunk streamed back in.

			nil rather than a fallback, because the honest answer for a column
			in the next chunk is "ask the generator" and only the caller knows
			whether that is good enough.
		]]
		surfaceAt = function(blockX, blockZ)
			local cell = toCell(blockX, blockZ)
			if not cell then
				return nil
			end
			return data.currentHeight[cell]
		end,

		addModel = function(model)
			model.Parent = data.model
		end,
	}
end

-- ---------------------------------------------------------------------------
-- Generation
-- ---------------------------------------------------------------------------

--[[
	THE FRAME BUDGET, AND WHY IT IS SHARED AND ADAPTIVE

	The first benchmark sweep measured the cost of the old arrangement exactly:
	at view distance 5 a chunk took ~58ms of CPU but waited ~23 SECONDS in the
	queue, with 120 chunks backed up behind it. The server was not busy. It was
	asleep.

	Three things caused that, and all three are fixed here.

	  1. The budget was per chunk. A chunk spent 4ms, called task.wait(), and
	     slept until the next frame - so the world filled at 4ms of work per
	     frame regardless of how much headroom the frame actually had.

	  2. The budget was fixed. 4ms is a reasonable guess for a loaded server and
	     a terrible one for an idle server holding a player at a black horizon.
	     currentBudget is now a control loop: it climbs while frames stay
	     healthy and backs off the moment they stretch, so it finds the real
	     headroom instead of assuming it.

	  3. Nothing could use the rest of a frame. When a chunk finished mid-frame
	     the remaining budget was simply lost, because the next chunk was only
	     ever started from the next Heartbeat. The pump now refills inside the
	     same frame.

	The budget is charged globally rather than per chunk, so concurrency cannot
	multiply the server's cost: two chunks in flight share one frame's
	allowance, they do not each get one.
]]

-- Bumped once per Heartbeat. Used to notice that a frame boundary has passed
-- without depending on which connection ran first, which task.wait's
-- resumption order does not guarantee.
local frameTick = 0
local budgetTick = -1
local budgetUsed = 0

local currentBudget = TerrainConfig.GenerateBudgetSeconds
local smoothedFrame = 1 / 60

local function chargeBudget(seconds)
	if budgetTick ~= frameTick then
		budgetTick = frameTick
		budgetUsed = 0
	end
	budgetUsed += seconds
end

local function budgetRemaining()
	if budgetTick ~= frameTick then
		return currentBudget
	end
	return currentBudget - budgetUsed
end

--[[
	One chunk's slice accounting. Per chunk rather than global because chunks can
	now overlap, and a single shared accumulator would credit one chunk with
	another's work and report both wrongly.
]]
local function newGenBudget()
	return { cpu = 0, sliceStart = os.clock() }
end

--[[
	CPU seconds this chunk has spent: the slices already banked, plus however far
	into the current slice we are.
]]
local function chunkCpuSpent(ctx)
	return ctx.cpu + (os.clock() - ctx.sliceStart)
end

--[[
	Yields when THIS FRAME's shared allowance is gone - not when this chunk has
	had its turn.

	Terrain.chunkCpuMs (work) and Terrain.chunkLatencyMs (wall clock) stay
	separate buckets, so the gap between them remains visible rather than
	inferred. Closing that gap is what this whole mechanism is for.
]]
local function yieldIfOverBudget(ctx)
	local now = os.clock()
	local spent = now - ctx.sliceStart

	ctx.cpu += spent
	chargeBudget(spent)

	if budgetRemaining() > 0 then
		ctx.sliceStart = now
		return
	end

	task.wait()
	ctx.sliceStart = os.clock()
end

--[[
	Moves the per-frame allowance toward whatever the server can actually afford.

	The signal is the server's own frame time, which already INCLUDES this work -
	so the loop is self-limiting. It climbs while frames stay under target and
	retreats when they stretch, which is the difference between "spend 4ms
	because that felt safe" and "spend whatever is going spare right now".

	Asymmetric on purpose: creeps up, drops fast. Overshooting costs the player a
	visible hitch, and undershooting only costs a little load time, so the two
	errors are not worth the same.
]]
local function updateGenerationBudget(dt)
	smoothedFrame += (dt - smoothedFrame) * TerrainConfig.GenerateFrameSmoothing

	local minBudget = TerrainConfig.GenerateBudgetMinSeconds
	local maxBudget = TerrainConfig.GenerateBudgetMaxSeconds

	if smoothedFrame >= TerrainConfig.GenerateFrameCeilingSeconds then
		-- Something is badly wrong with this frame. Halve rather than step.
		currentBudget *= 0.5
	elseif smoothedFrame > TerrainConfig.GenerateFrameTargetSeconds then
		currentBudget -= TerrainConfig.GenerateBudgetFallStep
	elseif queuedCount > 0 then
		-- Only climb when there is actually work waiting. Growing the budget on
		-- an empty queue would just raise the ceiling for the next burst
		-- without anyone having measured whether the server can pay it.
		currentBudget += TerrainConfig.GenerateBudgetRiseStep
	end

	if currentBudget < minBudget then
		currentBudget = minBudget
	elseif currentBudget > maxBudget then
		currentBudget = maxBudget
	end

	Profiler.sample("Terrain.genBudgetMs", currentBudget * 1000, "ms")
	Profiler.sample("Terrain.serverFrameMs", smoothedFrame * 1000, "ms")
end

local function isChunkWanted(key)
	local count = usageCounts[key]
	return count ~= nil and count > 0
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
	Carves a chunk's caves into its data from the CaveMap record, then applies
	the biome profile's materials to the surfaces that now face the air.

	Air is marked top-down per column through markRemoved, so an entrance that
	reaches the surface lowers the column exactly as mining its top would, and
	a tunnel below the surface becomes a disturbed band the general visibility
	path scans. Materials are plain overrides on the blocks around each
	interval; walls shared with the next chunk are found through the record's
	halo, so both sides of a border wall agree.
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

	return carved
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

local function generateChunk(cx, cz)
	if not isChunkInBounds(cx, cz) then
		return
	end

	local key = chunkKey(cx, cz)
	if chunks[key] or not isChunkWanted(key) then
		return
	end

	local ctx = newGenBudget()
	Profiler.count("Terrain.chunkGenerated")

	local phaseStart = 0

	-- Phase 0: columns. Built into locals first so a yield can never expose a
	-- half-populated chunk to BreakBlock or to a neighbour's visibility pass.
	local height = table.create(CHUNK_AREA, 0)
	local currentHeight = table.create(CHUNK_AREA, 0)
	local topName = table.create(CHUNK_AREA)
	local underName = table.create(CHUNK_AREA)
	local biomeName = table.create(CHUNK_AREA)
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
	local caveRecord = nil
	if CAVES_ENABLED then
		phaseStart = chunkCpuSpent(ctx)
		local function slice()
			yieldIfOverBudget(ctx)
		end
		caveRecord = CaveMap.prepareRecord(cx, cz, slice)

		-- The neighbours' records too, while we can still yield: the
		-- visibility pass asks about border columns in unloaded chunks, and
		-- a record built from inside that pass could not be time-sliced.
		for i = 1, 4 do
			local ncx, ncz = cx + DIR_X[i], cz + DIR_Z[i]
			if isChunkInBounds(ncx, ncz) then
				CaveMap.prepareRecord(ncx, ncz, slice)
			end
		end
		Profiler.sample("Terrain.gen.1b_cavePlan", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")

		if not isChunkWanted(key) then
			return
		end
	end

	local model = Instance.new("Folder")
	model.Name = string.format("Chunk_%d_%d", cx, cz)
	model.Parent = TerrainRoot

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

		-- Edit zones (see EDIT ZONES): cell -> when its zone time runs out,
		-- and the Parts on their way off screen.
		hot = {},
		hotCount = 0,
		retiring = {},
	}

	chunks[key] = data
	loadedChunkCount += 1

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
		local carved = applyCaves(data, caveRecord)
		Profiler.count("Terrain.cave.chunksWithCaves")
		Profiler.sample("Terrain.cave.carvedBlocks", carved, "blocks")
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

	-- Neighbours that finished before this point are read in full below.
	data.bordersStale = nil
	for index = 0, CHUNK_AREA - 1 do
		updateColumnVisibility(cx, cz, index // CHUNK_SIZE, index % CHUNK_SIZE)
		yieldIfOverBudget(ctx)
	end

	-- One that finished DURING the pass may have changed an edge column after
	-- it was scanned, and left this flag rather than drawing us half-built (see
	-- refreshChunkBorders). Re-read the edges until no yield brings another.
	-- Nothing yields between here and the end of generation, so once this loop
	-- exits the flush below is the last word.
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

	-- Every column has decided what it wants drawn; now turn that into the
	-- smallest set of Parts that draws it. Meshing after the whole chunk rather
	-- than per column is what lets a rectangle span columns at all.
	flushChunkMesh(data)

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

	-- Phase 4: structure models.
	phaseStart = chunkCpuSpent(ctx)
	StructureRegistry.applyModels(cx, cz, writer)
	Profiler.sample("Terrain.gen.5models", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")

	-- Phase 5: let already-loaded neighbours see anything that crossed into
	-- them.
	phaseStart = chunkCpuSpent(ctx)
	refreshChunkBorders(cx, cz)
	Profiler.sample("Terrain.gen.6borders", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")

	-- Whole-chunk CPU, excluding the between-slice sleeps. Compare against
	-- Terrain.chunkLatencyMs to see how much of a chunk's wall clock was work.
	Profiler.sample("Terrain.chunkCpuMs", chunkCpuSpent(ctx) * 1000, "ms")
end

function TerrainManager:_UnloadChunk(cx, cz)
	local key = chunkKey(cx, cz)
	if generatingChunks[key] then
		return
	end

	local data = chunks[key]
	if not data then
		return
	end

	chunks[key] = nil
	loadedChunkCount -= 1
	visibleBlocks -= data.visibleCount
	pendingUnload[key] = nil

	local startedAt = os.clock()
	local released = 0

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

	-- Unload is not time-sliced: it runs to completion inside one Heartbeat, so
	-- unlike generation its wall clock IS its cost, and a slow one shows up
	-- directly as a server frame spike.
	Profiler.sample("Terrain.chunkUnloadMs", (os.clock() - startedAt) * 1000, "ms")
	Profiler.sample("Terrain.chunkUnloadParts", released, "parts")
	Profiler.count("Terrain.chunkUnloaded")
end

-- ---------------------------------------------------------------------------
-- Generation queue
-- ---------------------------------------------------------------------------
-- Bucketed by priority instead of linearly scanned. Priority is squared chunk
-- distance from the player, so it only ever spans 0..2*ViewDistance^2 and a
-- bucket array is both simpler and faster than a heap.

local function enqueueChunk(cx, cz, priority)
	if not isChunkInBounds(cx, cz) then
		return
	end

	local key = chunkKey(cx, cz)
	if chunks[key] then
		return
	end

	local existing = queuedPriority[key]
	if existing ~= nil and existing <= priority then
		return
	end

	if existing == nil then
		queuedCount += 1
		-- Stamped on the FIRST request, not on a later re-queue at a better
		-- priority: latency is "how long after a player wanted this chunk did
		-- they get it", and re-prioritising does not restart that clock.
		queuedAt[key] = os.clock()
	end

	queuedPriority[key] = priority

	local bucket = queueBuckets[priority]
	if not bucket then
		bucket = {}
		queueBuckets[priority] = bucket
	end
	bucket[#bucket + 1] = { key = key, cx = cx, cz = cz, priority = priority }
end

local function dequeueChunk()
	for priority = 0, MAX_PRIORITY do
		local bucket = queueBuckets[priority]
		if bucket then
			local count = #bucket
			while count > 0 do
				local item = bucket[count]
				bucket[count] = nil
				count -= 1

				-- Stale entries are left behind when a chunk is re-queued at a
				-- better priority; drop them rather than pay to remove them.
				if queuedPriority[item.key] == item.priority then
					queuedPriority[item.key] = nil
					queuedCount -= 1
					return item
				end
			end
		end
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- Streaming
-- ---------------------------------------------------------------------------

local function releaseChunkUse(key, cx, cz)
	local count = math.max(0, (usageCounts[key] or 1) - 1)
	usageCounts[key] = count

	if count <= 0 then
		if chunks[key] then
			-- Grace period instead of a wider unload radius: walking back and
			-- forth over a chunk border costs nothing, and the loaded set stays
			-- bounded by the view distance.
			pendingUnload[key] = {
				cx = cx,
				cz = cz,
				dueAt = os.clock() + TerrainConfig.UnloadGraceSeconds,
			}
		else
			if queuedPriority[key] ~= nil then
				queuedCount -= 1
			end
			queuedPriority[key] = nil
			queuedAt[key] = nil
		end
	end
end

local function refreshPlayerChunks(player, newCX, newCZ)
	local previous = playerChunk[player]
	local previousActive = previous and previous.active or nil
	local active = {}

	local distance = viewDistanceFor(player)

	for dx = -distance, distance do
		for dz = -distance, distance do
			local cx, cz = newCX + dx, newCZ + dz
			if isChunkInBounds(cx, cz) then
				local key = chunkKey(cx, cz)
				local priority = dx * dx + dz * dz
				active[key] = { cx = cx, cz = cz }

				if not previousActive or not previousActive[key] then
					usageCounts[key] = (usageCounts[key] or 0) + 1
				end

				pendingUnload[key] = nil

				if not chunks[key] then
					enqueueChunk(cx, cz, priority)
				end
			end
		end
	end

	if previousActive then
		for oldKey, coord in pairs(previousActive) do
			if not active[oldKey] then
				releaseChunkUse(oldKey, coord.cx, coord.cz)
			end
		end
	end

	playerChunk[player] = { x = newCX, z = newCZ, active = active }
end

local function onPlayerMoved(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local position = hrp.Position
	local cx = getChunkCoordX(position.X)
	local cz = getChunkCoordZ(position.Z)
	local previous = playerChunk[player]

	if not previous or previous.x ~= cx or previous.z ~= cz then
		refreshPlayerChunks(player, cx, cz)
	end
end

local function onPlayerRemoving(player)
	local data = playerChunk[player]
	if data then
		for key, coord in pairs(data.active) do
			releaseChunkUse(key, coord.cx, coord.cz)
		end
	end
	playerChunk[player] = nil
	playerViewDistance[player] = nil
end

local function processPendingUnloads()
	local now = os.clock()
	for key, entry in pairs(pendingUnload) do
		if isChunkWanted(key) then
			pendingUnload[key] = nil
		elseif generatingChunks[key] then
			-- Leave it scheduled; the generator re-checks on completion.
			continue
		elseif now >= entry.dueAt then
			pendingUnload[key] = nil
			TerrainManager:_UnloadChunk(entry.cx, entry.cz)
		end
	end
end

--[[
	Takes the next chunk that is still wanted, discarding stale queue entries.
]]
local function nextWantedItem()
	local item = dequeueChunk()

	while item and (chunks[item.key] or not isChunkWanted(item.key)) do
		queuedAt[item.key] = nil
		item = dequeueChunk()
	end

	return item
end

local pumpGeneration

local function startGeneration(item)
	activeGenerations += 1
	generatingChunks[item.key] = true

	local requestedAt = queuedAt[item.key]
	queuedAt[item.key] = nil
	if requestedAt then
		-- How long the chunk sat behind other chunks before its turn came. At a
		-- wide view distance this used to be where nearly all of the wall clock
		-- went - 23 seconds against 58ms of actual work.
		Profiler.sample("Terrain.chunkQueueWaitMs", (os.clock() - requestedAt) * 1000, "ms")
	end

	task.spawn(function()
		local ok, err = pcall(generateChunk, item.cx, item.cz)
		generatingChunks[item.key] = nil
		activeGenerations -= 1

		if not ok then
			warn("[TerrainManager] Chunk generation failed:", err)
			-- Drop whatever was half-built so a retry starts clean.
			TerrainManager:_UnloadChunk(item.cx, item.cz)
		elseif not isChunkWanted(item.key) then
			TerrainManager:_UnloadChunk(item.cx, item.cz)
		elseif requestedAt then
			-- End to end: player wanted it -> it is standing there. This is the
			-- number that decides whether a view distance feels playable, and
			-- the one that CPU cost alone hides.
			Profiler.sample("Terrain.chunkLatencyMs", (os.clock() - requestedAt) * 1000, "ms")
		end

		-- A chunk finishing halfway through a frame used to waste the rest of
		-- that frame's allowance, because the next chunk was only ever started
		-- from the next Heartbeat. Refill immediately instead.
		pumpGeneration()
	end)
end

--[[
	Starts chunks while this frame still has allowance and there is room in
	flight.

	Re-entrancy guarded: task.spawn runs the new coroutine synchronously until it
	first yields, so a chunk that finishes without yielding calls back into here
	from inside the loop below. Returning early is correct there - the loop that
	is already running will carry on.
]]
local pumping = false

-- reason -> true while something has asked for generation to wait. See
-- TerrainManager:HoldGeneration.
local generationHolds = {}

function pumpGeneration()
	if pumping or next(generationHolds) ~= nil then
		return
	end
	pumping = true

	while
		activeGenerations < TerrainConfig.MaxConcurrentChunks
		and budgetRemaining() > 0
	do
		local item = nextWantedItem()
		if not item then
			break
		end
		startGeneration(item)
	end

	pumping = false
end

local function onHeartbeatGenerate(dt)
	frameTick += 1
	updateGenerationBudget(dt)

	Profiler.sample("Terrain.queueDepth", queuedCount, "chunks")
	Profiler.sample("Terrain.activeGenerations", activeGenerations, "chunks")

	pumpGeneration()

	processPendingUnloads()
	trimPoolsIfNeeded()
	closeExpiredEditZones()
end

--[[
	Lifts a player who has ended up INSIDE solid ground back on top of it.

	Nobody can legitimately be inside a block: every solid cell that touches air
	is drawn, and drawn blocks collide. A player whose body is in one has
	slipped through a gap - in practice the moment between an edit taking
	ground away on their client and the replacement Part arriving (see
	applyLayerPlans) - and is falling through the world. Their client runs
	their physics, so it cannot be stopped there; but the server knows where
	the ground really is, so it puts them back on it within a frame or two
	instead of at the bottom of the world.

	Checked every frame because it is a handful of table reads per player, and
	a falling body crosses a thin floor quickly.
]]
local function rescueBuriedPlayer(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.Health <= 0 or root.Anchored then
		return
	end

	local position = root.Position
	local blockX = math.floor(position.X / STUD_SIZE)
	local blockZ = math.floor(position.Z / STUD_SIZE)
	local by = math.floor(position.Y / STUD_SIZE)

	local cx, cz, bx, bz = normalizeCell(
		blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE, blockX % CHUNK_SIZE, blockZ % CHUNK_SIZE
	)
	local key = chunkKey(cx, cz)
	local data = chunks[key]

	-- A chunk still being built may not have its edits replayed yet, so what it
	-- says is solid is not final.
	if not data or generatingChunks[key] then
		return
	end

	local cell = cellOf(bx, bz)
	if by < FLOOR_Y or by > MAX_BLOCK_Y or not isPresentInData(data, cell, by) then
		return
	end

	-- The first gap above them two blocks tall: room to stand, with ground
	-- under it, since everything scanned past on the way was solid.
	local feet = by + 1
	while feet <= MAX_BLOCK_Y and (isPresentInData(data, cell, feet) or isPresentInData(data, cell, feet + 1)) do
		feet += 1
	end
	if feet > MAX_BLOCK_Y then
		return
	end

	local lift = root.Size.Y * 0.5 + humanoid.HipHeight
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(position.X, feet * STUD_SIZE + lift + 0.05, position.Z) * root.CFrame.Rotation
	Profiler.count("Terrain.playerRescued")
end

local function onHeartbeatMovement(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		rescueBuriedPlayer(player)
	end

	movementAccumulator += dt
	if movementAccumulator < TerrainConfig.MovementCheckInterval then
		return
	end
	movementAccumulator = 0

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerMoved(player)
	end
end

-- ---------------------------------------------------------------------------
-- Edits
-- ---------------------------------------------------------------------------

--[[
	Resolves a block from a world position alone, trusting nothing about which
	part the caller named.

	Searches outward from the block the click landed in rather than scanning the
	whole column: with a 190-block-deep world a full scan would be the most
	expensive thing mining does, and it would get worse every time the floor is
	lowered.
]]
local function resolveByPosition(clickPos)
	local cx, cz, bx, bz = worldToChunkLocal(clickPos.X, clickPos.Z)
	if not isChunkInBounds(cx, cz) then
		return nil
	end

	local data = chunks[chunkKey(cx, cz)]
	if not data then
		return nil
	end

	local cell = cellOf(bx, bz)
	local scanTop = data.topScan[cell]
	local guess = math.floor(clickPos.Y / STUD_SIZE)

	local function candidate(by)
		return by >= FLOOR_Y and by < scanTop and isPresentInData(data, cell, by)
	end

	if candidate(guess) then
		return data, cell, guess
	end

	for radius = 1, 2 do
		if candidate(guess - radius) then
			return data, cell, guess - radius
		end
		if candidate(guess + radius) then
			return data, cell, guess + radius
		end
	end

	return nil
end

--[[
	Resolves a mining target to (chunk, cell, by).

	ONE PART IS NO LONGER ONE BLOCK. A part covers a rectangle of identical
	blocks, so knowing which part was hit is not enough - the position within it
	decides which block the player actually pointed at.

	That position comes from the client, and it is CLAMPED to the rectangle
	before it is used. So the worst a lying client can do is pick a different
	block inside the part it genuinely clicked, which it could always do by
	aiming a few studs over. It cannot reach past the part, cannot reach a
	different chunk, and cannot reach anything out of range - validateReach has
	already run against the same position.

	The staleness guard is Parent rather than an identity check against the
	stored cell: releasePart unparents and clears the rect together, so a part
	that is still parented to the chunk it claims is still drawing that
	rectangle. A part reused from the pool has had its rect overwritten.
]]
local function resolveTarget(targetPart, clickPos)
	if targetPart and clickPos then
		local rect = partRect[targetPart]

		if rect and isChunkInBounds(rect.cx, rect.cz) then
			local data = chunks[chunkKey(rect.cx, rect.cz)]

			if data and targetPart.Parent == data.model then
				local minBlockX = rect.cx * CHUNK_SIZE + rect.bx
				local minBlockZ = rect.cz * CHUNK_SIZE + rect.bz

				-- The claimed hit point must actually lie on this rectangle.
				--
				-- Without this the clamp below would be an exploit rather than a
				-- safeguard: a client could name a distant part, claim a hit
				-- point next to their own feet to satisfy the reach check, and
				-- have it clamped into the far rectangle. Requiring both to be
				-- true of the SAME point closes that - a point cannot be within
				-- reach of the player and on a part they cannot reach.
				--
				-- Half a stud of slack because a click lands exactly on a face.
				local minX = minBlockX * STUD_SIZE - 0.5
				local minZ = minBlockZ * STUD_SIZE - 0.5
				local maxX = (minBlockX + rect.sizeX) * STUD_SIZE + 0.5
				local maxZ = (minBlockZ + rect.sizeZ) * STUD_SIZE + 0.5
				local minY = rect.by * STUD_SIZE - 0.5
				local maxY = (rect.by + 1) * STUD_SIZE + 0.5

				local onRect = clickPos.X >= minX and clickPos.X <= maxX
					and clickPos.Y >= minY and clickPos.Y <= maxY
					and clickPos.Z >= minZ and clickPos.Z <= maxZ

				if not onRect then
					-- Fall through to resolving purely from the position, which
					-- trusts nothing about which part was named.
					return resolveByPosition(clickPos)
				end

				local blockX = math.clamp(
					math.floor(clickPos.X / STUD_SIZE), minBlockX, minBlockX + rect.sizeX - 1
				)
				local blockZ = math.clamp(
					math.floor(clickPos.Z / STUD_SIZE), minBlockZ, minBlockZ + rect.sizeZ - 1
				)

				local cell = cellOf(blockX - rect.cx * CHUNK_SIZE, blockZ - rect.cz * CHUNK_SIZE)
				local by = rect.by

				if isPresentInData(data, cell, by) then
					return data, cell, by
				end
			end
		end
	end

	-- No usable part, or the named part did not hold up. Resolve from position.
	if not clickPos then
		return nil
	end

	return resolveByPosition(clickPos)
end

--[[
	Turns whatever the caller handed us - a rendered part, or a world position -
	into a point in space. Shared by the two entry points below so they can never
	disagree about which block a request refers to.
]]
local function toClickPosition(wx, wy, wz)
	if typeof(wx) == "Instance" then
		-- A part plus the point on it that was hit. Required now that one part
		-- can cover a whole run of blocks: its centre would resolve to the
		-- middle of the run rather than to the block the player aimed at. The
		-- position is clamped to the part's own rectangle in resolveTarget, so
		-- accepting it from the caller does not widen what a client can reach.
		if typeof(wy) == "Vector3" then
			return wx, wy
		end

		if wx:IsA("BasePart") then
			return wx, wx.Position
		end
		if wx:IsA("Model") then
			local primary = wx.PrimaryPart or wx:FindFirstChildWhichIsA("BasePart")
			return wx, primary and primary.Position or nil
		end
		return wx, nil
	end

	if typeof(wx) == "number" and typeof(wy) == "number" and typeof(wz) == "number" then
		return nil, Vector3.new(wx, wy, wz)
	end

	return nil, nil
end

--[[
	Server-authoritative reach check. Returns the click position only if the
	player is genuinely standing next to it.
]]
local function validateReach(player, clickPos)
	if not clickPos then
		return false, "bad_target"
	end

	if not (player and typeof(player) == "Instance" and player:IsA("Player")) then
		return false, "no_player"
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, "no_character"
	end

	if (hrp.Position - clickPos).Magnitude > MAX_REACH_STUDS then
		return false, "too_far"
	end

	return true
end

--[[
	What block is the player pointing at, without touching it?

	Mining needs this before it starts its timer: how long a block takes to break
	is a property of the block, and the server has to decide that rather than
	take the client's word for it.

	Returns blockName, itemName (what it would drop), reason, resolved cell centre.
]]
function TerrainManager:InspectBlock(wx, wy, wz, initiator)
	local targetPart, clickPos = toClickPosition(wx, wy, wz)

	local ok, reason = validateReach(initiator, clickPos)
	if not ok then
		return nil, nil, reason
	end

	local data, cell, by = resolveTarget(targetPart, clickPos)
	if not data then
		return nil, nil, "no_block"
	end

	local blockName = blockNameFor(data, cell, by)
	if BlockConfig.isUnbreakable(blockName) then
		return blockName, nil, "unbreakable"
	end

	local index = cell - 1
	local centre = Vector3.new(
		(data.minBlockX + index // CHUNK_SIZE + 0.5) * STUD_SIZE,
		(by + 0.5) * STUD_SIZE,
		(data.minBlockZ + index % CHUNK_SIZE + 0.5) * STUD_SIZE
	)
	return blockName, BlockConfig.getDrop(blockName), "ok", centre
end

--[[
	Removes one block.

	Accepts either a rendered part or world coordinates, and returns
	(ok, itemName, reason). itemName is what the player should receive, which is
	BlockConfig's business, not the caller's.
]]
local function removeResolvedBlock(data, cell, by, refresh)
	local blockName = blockNameFor(data, cell, by)
	if BlockConfig.isUnbreakable(blockName) then
		return false, nil, "unbreakable"
	end

	local key = chunkKey(data.cx, data.cz)
	local extra = data.extra[cell]

	if extra and extra[by] then
		-- A block sitting above the terrain: either a structure's, or one a
		-- player put there. Those are remembered differently, because forgetting
		-- a placement restores the ground beneath it while a structure block has
		-- to be actively suppressed on the next regeneration.
		if ChunkEdits.isPlaced(key, cell, by) then
			ChunkEdits.clearPlacement(key, cell, by)
		else
			ChunkEdits.recordRemoval(key, cell, by)
		end

		extra[by] = nil
		markDisturbed(data, cell, by)
	else
		local override = data.override[cell]
		if override and override[by] then
			override[by] = nil
		end

		ChunkEdits.recordRemoval(key, cell, by)
		markRemoved(data, cell, by)
	end

	-- The block stops being drawn; refreshAdjacentColumns below re-derives the
	-- rest of the column and its neighbours and rebuilds the affected layers in
	-- one pass. Releasing an individual Part here would be wrong now - the Part
	-- covering this block probably covers several others that are still there.
	clearVisible(data, cell, by)

	local index = cell - 1
	if refresh ~= false then
		refreshAdjacentColumns(data.cx, data.cz, index // CHUNK_SIZE, index % CHUNK_SIZE)
	end

	return true, BlockConfig.getDrop(blockName), "ok"
end

function TerrainManager:BreakBlock(wx, wy, wz, initiator)
	Profiler.enter("Terrain.breakBlock")

	local function finish(ok, item, reason)
		Profiler.leave("Terrain.breakBlock")
		return ok, item, reason
	end

	local targetPart, clickPos = toClickPosition(wx, wy, wz)

	local reachOk, reachReason = validateReach(initiator, clickPos)
	if not reachOk then
		return finish(false, nil, reachReason)
	end

	local data, cell, by = resolveTarget(targetPart, clickPos)
	if not data then
		return finish(false, nil, "no_block")
	end

	-- Usually already open from when the swing started (OpenEditZone); this
	-- covers anything that breaks blocks without one, and keeps it alive.
	local index = cell - 1
	openEditZone(data.minBlockX + index // CHUNK_SIZE, data.minBlockZ + index % CHUNK_SIZE)

	local ok, item, reason = removeResolvedBlock(data, cell, by)
	return finish(ok, item, reason)
end

--[[
	Opens an edit zone around a world position (see EDIT ZONES). MiningServer
	calls it when a swing STARTS, so the ground around the target is already
	split into single blocks - and the layer under it drawn - by the time the
	block breaks, and the swing time is the warning clients get.
]]
function TerrainManager:OpenEditZone(position: Vector3)
	if typeof(position) ~= "Vector3" then
		return
	end
	openEditZone(math.floor(position.X / STUD_SIZE), math.floor(position.Z / STUD_SIZE))
end

-- Server-only ability excavation. Exact loaded cells, no mining-reach override on
-- BreakBlock and no client remote. Clear the beam shaft as well as the crater.
function TerrainManager:MineAbilityCrater(centre, canCollect, collect, beamHeight, beamRadius)
	if typeof(centre) ~= "Vector3" or centre.X ~= centre.X or centre.Y ~= centre.Y or centre.Z ~= centre.Z then return 0 end
	if math.abs(centre.X)>1e6 or math.abs(centre.Y)>1e6 or math.abs(centre.Z)>1e6 then return 0 end
	local top = math.floor((centre.Y-0.05)/STUD_SIZE)
	local shaftHeight = math.clamp(beamHeight or 280, 0, 280)
	local shaftRadius = math.clamp(beamRadius or 20, 0, 20) / STUD_SIZE
	local shaftTop = math.floor((centre.Y+shaftHeight-0.05)/STUD_SIZE)
	local dirty, removed, debris = {}, 0, {}
	local groundDebris, shaftDebris = {}, {}
	local groundRemoved, shaftRemoved = 0, 0
	-- Descend through overhangs before excavating the six tapered ground layers.
	-- The pressure field clears overhangs across the crater's footprint too.
	for depth = top-shaftTop, 5 do
		local radius = if depth < 0 then shaftRadius else 5-depth
		local extent = math.ceil(radius)
		for dx = -extent, extent do
			for dz = -extent, extent do
				if dx*dx+dz*dz>radius*radius then continue end
				local cx,cz,bx,bz=worldToChunkLocal(centre.X+dx*STUD_SIZE,centre.Z+dz*STUD_SIZE)
				if not isChunkInBounds(cx,cz) then continue end
				local data=chunks[chunkKey(cx,cz)]
				local by=top-depth
				local cell=cellOf(bx,bz)
				if not data or by<FLOOR_Y or not isPresentInData(data,cell,by) then continue end
				local name=blockNameFor(data,cell,by)
				if BlockConfig.isUnbreakable(name) then continue end
				local ok,item=removeResolvedBlock(data,cell,by,false)
				if ok then
					removed+=1
					local samples
					local zoneCount
					if depth<0 then shaftRemoved+=1; samples=shaftDebris; zoneCount=shaftRemoved
					else groundRemoved+=1; samples=groundDebris; zoneCount=groundRemoved end
					if zoneCount%3==1 and #samples<64 then
						local ox,oz=getChunkWorldOrigin(cx,cz)
						table.insert(samples,{position=Vector3.new(ox+(bx+.5)*STUD_SIZE,(by+.5)*STUD_SIZE,oz+(bz+.5)*STUD_SIZE),block=name})
					end
					dirty[chunkKey(cx,cz)..":"..cell]={cx,cz,bx,bz}
					-- Ability destruction still works when there is no room for loot.
					if item and canCollect(item) then collect(item) end
				end
			end
		end
	end
	for _,column in pairs(dirty) do
		-- Immediate: a crater should open with the blast, not a moment after it.
		refreshAdjacentColumns(column[1],column[2],column[3],column[4],true)
	end
	-- Keep ground fragments visible even when a dense overhead shaft fills the cap.
	local groundLimit=math.min(#groundDebris,math.max(32,64-#shaftDebris))
	for i=1,math.min(#shaftDebris,64-groundLimit) do table.insert(debris,shaftDebris[i]) end
	for i=1,groundLimit do table.insert(debris,groundDebris[i]) end
	return removed,debris
end

--[[
	BOUNDED SERVER-OWNED EXCAVATION - a boss eating the ground.

	MineAbilityCrater above is shaped around one thing: a 280-stud beam shaft
	and a six-layer tapered crater. A boss that takes shallow bites out of the
	floor at the ends of a few tendrils wants none of that shape, so this is the
	general operation underneath: "here are some columns, remove the top block
	or two of each, tell me what actually went".

	It is in TWO STEPS on purpose. The caller plans first and executes later,
	because a telegraph has to promise the ground that will actually be hit:
	the plan is the frozen list of cells the warning is drawn from, and the
	execution removes exactly those cells - re-validated, because a player may
	have mined or built there during the warning - and nothing else.

	TERRAIN SAFETY RULES, all enforced here rather than trusted to the caller:

	  loaded only       a column whose chunk is not resident, or is still being
	                    generated, is skipped. Nothing is ever written into
	                    chunk data that is about to be replaced.
	  world bounds      chunk bounds, the world floor and the ceiling.
	  unbreakable       BlockConfig.isUnbreakable wins over everything.
	  natural only      by default a cell is skipped if it is an ADDED block
	                    (data.extra: a structure's block or a player's
	                    placement - ChunkEdits tells them apart, and neither is
	                    the boss's to eat) or a RESTYLED one (data.override: a
	                    structure's restyle of the ground under it, or a cave
	                    wall). Overrides cannot be told apart from each other,
	                    so both are protected; the cost is that he bites less
	                    around caves, which is fine.
	  dry only          by default a column under standing water is skipped. A
	                    bite under a lake would be invisible and the water sync
	                    would have to redraw for nothing.
	  no loot           the item a removed block would have dropped is thrown
	                    away. This is not mining; a boss must not be a farm.
	  hard caps         on columns considered, cells planned, cells removed and
	                    samples returned, whatever the caller asks for.
	  no reach check    this is a server-owned action, not a player's request.
	                    Nothing here reads a client, and no client chooses a
	                    cell or reports a removal.

	Removal goes through removeResolvedBlock, so ChunkEdits records it exactly
	as a mined block and the renderer re-derives the column - and dirty columns
	are deduplicated and refreshed once each at the end rather than per block.

	The sample records are `{ position = Vector3, block = name }` of blocks
	that were REALLY removed, for clients to animate copies of. A client never
	sees a block the server did not take.
]]
local EXCAVATE_MAX_COLUMNS = 48
local EXCAVATE_MAX_CELLS = 64
local EXCAVATE_MAX_SAMPLES = 24
local EXCAVATE_MAX_DEPTH = 3

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and math.abs(value) < 1e6
end

-- Natural, expendable ground: not added, not restyled. See the rules above.
local function isNaturalCell(data, cell, by)
	local extra = data.extra[cell]
	if extra and extra[by] then
		return false
	end
	local override = data.override[cell]
	if override and override[by] then
		return false
	end
	return true
end

local function cellAllowed(data, cell, by, options)
	if not isPresentInData(data, cell, by) then
		return false
	end
	if options.naturalOnly ~= false and not isNaturalCell(data, cell, by) then
		return false
	end
	if BlockConfig.isUnbreakable(blockNameFor(data, cell, by)) then
		return false
	end
	return true
end

--[[
	Resolves a set of columns into the exact cells a later ExecuteExcavation
	will remove.

	  columns  { { x = worldX, z = worldZ, y = worldY, depth = n }, ... }
	           y is where to start looking for the top of the ground (the
	           caller's idea of the floor there); depth is how many blocks
	           down from that top block to take, 1..EXCAVATE_MAX_DEPTH.
	  options  naturalOnly (default true), skipWet (default true),
	           maxCells (clamped to EXCAVATE_MAX_CELLS)

	Returns an array of cell records, top-down within each column so that
	removing them in order lowers the column the way mining it would.
]]
function TerrainManager:PlanExcavation(columns, options)
	options = options or {}
	local maxCells = math.clamp(tonumber(options.maxCells) or EXCAVATE_MAX_CELLS, 0, EXCAVATE_MAX_CELLS)
	local plan = {}

	if type(columns) ~= "table" then
		return plan
	end

	for index, column in ipairs(columns) do
		if index > EXCAVATE_MAX_COLUMNS or #plan >= maxCells then
			break
		end
		if type(column) ~= "table" or not (isFiniteNumber(column.x) and isFiniteNumber(column.z) and isFiniteNumber(column.y)) then
			continue
		end

		local cx, cz, bx, bz = worldToChunkLocal(column.x, column.z)
		if not isChunkInBounds(cx, cz) then
			continue
		end
		local key = chunkKey(cx, cz)
		local data = chunks[key]
		if not data or generatingChunks[key] then
			continue
		end

		local cell = cellOf(bx, bz)

		if options.skipWet ~= false and data.waterTop[cell] > data.currentHeight[cell] then
			continue
		end

		-- The top solid block near the caller's floor height: a short scan,
		-- two blocks up for a step and four down for a hollow, never further.
		local from = math.min(MAX_BLOCK_Y, math.floor(column.y / STUD_SIZE) + 2)
		local to = math.max(FLOOR_Y, from - 6)
		local top = nil
		for by = from, to, -1 do
			if isPresentInData(data, cell, by) then
				top = by
				break
			end
		end
		if not top then
			continue
		end

		local depth = math.clamp(math.floor(tonumber(column.depth) or 1), 1, EXCAVATE_MAX_DEPTH)
		local ox, oz = getChunkWorldOrigin(cx, cz)

		for step = 0, depth - 1 do
			local by = top - step
			if #plan >= maxCells then
				break
			end
			-- A protected block ends the column: biting out from under an
			-- unbreakable or placed block would leave it floating, and a
			-- bite is a surface thing anyway.
			if not cellAllowed(data, cell, by, options) then
				break
			end
			table.insert(plan, {
				cx = cx, cz = cz, cell = cell, by = by,
				bx = bx, bz = bz,
				position = Vector3.new(ox + (bx + 0.5) * STUD_SIZE, (by + 0.5) * STUD_SIZE, oz + (bz + 0.5) * STUD_SIZE),
				block = blockNameFor(data, cell, by),
			})
		end
	end

	return plan
end

--[[
	Removes the cells of a plan from PlanExcavation. Every cell is checked
	again - still loaded, still present, still natural, still breakable -
	because the world may have moved between the plan and now.

	Returns the number of blocks actually removed and a capped sample of
	`{ position, block }` records for the blocks that really went.
]]
function TerrainManager:ExecuteExcavation(plan, options)
	options = options or {}
	local maxRemoved = math.clamp(tonumber(options.maxRemoved) or EXCAVATE_MAX_CELLS, 0, EXCAVATE_MAX_CELLS)
	local maxSamples = math.clamp(tonumber(options.maxSamples) or EXCAVATE_MAX_SAMPLES, 0, EXCAVATE_MAX_SAMPLES)

	local removed, samples, dirty = 0, {}, {}
	local gone = {}

	if type(plan) ~= "table" then
		return 0, samples
	end

	Profiler.enter("Terrain.excavate")

	for index, record in ipairs(plan) do
		if index > EXCAVATE_MAX_CELLS or removed >= maxRemoved then
			break
		end
		if type(record) ~= "table" then
			continue
		end

		local key = chunkKey(record.cx, record.cz)
		local data = chunks[key]
		if not data or generatingChunks[key] or not isChunkInBounds(record.cx, record.cz) then
			continue
		end
		if not cellAllowed(data, record.cell, record.by, options) then
			continue
		end

		local name = blockNameFor(data, record.cell, record.by)
		local ok = removeResolvedBlock(data, record.cell, record.by, false)
		if ok then
			removed += 1
			-- The drop is deliberately not collected: see the rules above.
			dirty[key .. ":" .. record.cell] = { record.cx, record.cz, record.bx, record.bz }
			table.insert(gone, { position = record.position, block = name })
		end
	end

	-- Once per column, immediately: the bite opens with the attack that made
	-- it, and a column with two blocks gone is rebuilt once, not twice.
	for _, column in pairs(dirty) do
		refreshAdjacentColumns(column[1], column[2], column[3], column[4], true)
	end

	-- Spread the samples over everything that went rather than taking the
	-- first N, so the debris comes from the whole bite and not one corner.
	if maxSamples > 0 and #gone > 0 then
		local stride = math.max(1, math.ceil(#gone / maxSamples))
		for index = 1, #gone, stride do
			if #samples >= maxSamples then
				break
			end
			table.insert(samples, gone[index])
		end
	end

	Profiler.leave("Terrain.excavate")
	Profiler.count("Terrain.excavated", removed)

	return removed, samples
end

--[[
	Puts a block down.

	Player placement goes through the same chunk data and the same renderer as
	generated terrain, which is the whole point: a placed block is then mineable,
	occludes and is occluded correctly, and is culled and pooled like everything
	else. It used to be a separate folder of loose parts, which is why mining one
	broke the terrain underneath it instead.

	Every check here is server-side. The caller supplies a grid cell and a block
	name; nothing about the client's view of the world is trusted.
]]
function TerrainManager:PlaceBlock(player, blockX, by, blockZ, blockName)
	Profiler.enter("Terrain.placeBlock")

	local function finish(ok, reason)
		Profiler.leave("Terrain.placeBlock")
		return ok, reason
	end

	if type(blockX) ~= "number" or type(by) ~= "number" or type(blockZ) ~= "number" then
		return finish(false, "Bad position")
	end

	blockX = math.floor(blockX)
	by = math.floor(by)
	blockZ = math.floor(blockZ)

	if by < FLOOR_Y or by > MAX_BLOCK_Y then
		return finish(false, "Out of range")
	end

	if not isBlockInWorld(blockX, blockZ) then
		return finish(false, "Outside the world")
	end

	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return finish(false, "No character")
	end

	local centre = Vector3.new(
		blockX * STUD_SIZE + STUD_SIZE * 0.5,
		by * STUD_SIZE + STUD_SIZE * 0.5,
		blockZ * STUD_SIZE + STUD_SIZE * 0.5
	)
	if (hrp.Position - centre).Magnitude > MAX_REACH_STUDS then
		return finish(false, "Too far")
	end

	-- Not inside yourself. The client's preview cannot see the character - it
	-- filters it out of its own raycast - so aiming down at your feet asks for
	-- a block in the cell you are standing in, which seals you in.
	local characterCF, characterSize = character:GetBoundingBox()
	local gap = characterCF.Position - centre
	local halfX = characterSize.X * 0.5 + STUD_SIZE * 0.5
	local halfY = characterSize.Y * 0.5 + STUD_SIZE * 0.5
	local halfZ = characterSize.Z * 0.5 + STUD_SIZE * 0.5
	if
		math.abs(gap.X) < halfX
		and math.abs(gap.Y) < halfY
		and math.abs(gap.Z) < halfZ
	then
		return finish(false, "You are standing there")
	end

	local cx, cz, bx, bz = normalizeCell(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE,
		blockX % CHUNK_SIZE, blockZ % CHUNK_SIZE)

	local key = chunkKey(cx, cz)
	local data = chunks[key]
	if not data then
		return finish(false, "Area not loaded")
	end

	local cell = cellOf(bx, bz)
	if isPresentInData(data, cell, by) then
		return finish(false, "Cell occupied")
	end

	-- A block has to touch something, so players cannot build floating islands
	-- out in the air.
	local supported = false
	for i = 1, 4 do
		if isBlockPresent(cx, cz, bx + DIR_X[i], bz + DIR_Z[i], by) then
			supported = true
			break
		end
	end
	if not supported then
		supported = isBlockPresent(cx, cz, bx, bz, by + 1)
			or isBlockPresent(cx, cz, bx, bz, by - 1)
	end
	if not supported then
		return finish(false, "Needs support")
	end

	if not getBlockPartTemplate(blockName) then
		return finish(false, "Missing template")
	end

	-- Before the edit, so the ground around it is already drawn block by block
	-- when it changes. See EDIT ZONES.
	openEditZone(blockX, blockZ)

	applyPlacement(data, cell, by, blockName)
	ChunkEdits.recordPlacement(key, cell, by, blockName)

	refreshAdjacentColumns(cx, cz, bx, bz)
	return finish(true, "Placed")
end

--[[
	Is there a solid block at this grid cell? Used by the placement preview path
	and by station placement, so both agree with the renderer about what is where.
]]
function TerrainManager:IsSolidAt(blockX, by, blockZ)
	if by < FLOOR_Y or by > MAX_BLOCK_Y or not isBlockInWorld(blockX, blockZ) then
		return false
	end

	local cx, cz, bx, bz = normalizeCell(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE,
		blockX % CHUNK_SIZE, blockZ % CHUNK_SIZE)

	return isBlockPresent(cx, cz, bx, bz, by)
end

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

	ensureGeneratedTemplates()

	-- Water is Terrain; its look is Terrain's. See WATER.
	local waterLook = TerrainConfig.Water
	TerrainVoxels.WaterColor = waterLook.Color
	TerrainVoxels.WaterTransparency = waterLook.Transparency
	TerrainVoxels.WaterReflectance = waterLook.Reflectance
	TerrainVoxels.WaterWaveSize = waterLook.WaveSize
	TerrainVoxels.WaterWaveSpeed = waterLook.WaveSpeed

	-- Before anything is cloned from a template, so every pooled part inherits
	-- tiled faces rather than being fixed up one clone at a time.
	normaliseBlockFaces()

	-- Lets ChunkEdits bound itself without ever dropping edits for a chunk that
	-- is streamed in, whose stored edits and rendered parts have to agree.
	ChunkEdits.setResidencyCheck(function(key)
		return chunks[key] ~= nil
	end)

	StructureRegistry.init({
		seed = baseSeed,
		chunkSize = CHUNK_SIZE,
		studSize = STUD_SIZE,
		assetsRoot = TerrainAssets,
		blocksFolder = BlocksFolder,
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
		allowStructureAt = structureHasSupport,
	})

	warnForMissingTemplates()

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.delay(0.15, function()
				if player.Parent then
					onPlayerMoved(player)
				end
			end)
		end)

		task.delay(0.15, function()
			if player.Parent then
				onPlayerMoved(player)
			end
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			task.delay(0.15, function()
				if player.Parent then
					onPlayerMoved(player)
				end
			end)
		end
	end

	Players.PlayerRemoving:Connect(onPlayerRemoving)
	RunService.Heartbeat:Connect(onHeartbeatGenerate)
	RunService.Heartbeat:Connect(onHeartbeatMovement)
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
	generationHolds[reason or "default"] = true
end

function TerrainManager:ReleaseGeneration(reason)
	generationHolds[reason or "default"] = nil
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
	return key // CHUNK_KEY_STRIDE - CHUNK_KEY_OFFSET, key % CHUNK_KEY_STRIDE - CHUNK_KEY_OFFSET
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

	local cx, cz, bx, bz = normalizeCell(
		blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE,
		blockX % CHUNK_SIZE, blockZ % CHUNK_SIZE
	)

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

	local cx, cz, bx, bz = normalizeCell(
		blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE,
		blockX % CHUNK_SIZE, blockZ % CHUNK_SIZE
	)

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
		meanChunkRelief = relief / math.max(1, loadedChunkCount),
	}
end

function TerrainManager:GetStats()
	return {
		seed = baseSeed,
		viewDistance = VIEW_DISTANCE,
		loadedChunks = loadedChunkCount,
		queuedChunks = queuedCount,
		generating = activeGenerations > 0,
		activeGenerations = activeGenerations,
		generateBudgetMs = currentBudget * 1000,
		renderedParts = renderedParts,
		pooledParts = pooledParts,
		visibleBlocks = visibleBlocks,

		-- Blocks drawn per Part. 1.0 means merging achieved nothing; the higher
		-- it climbs the fewer Instances the client is holding for the same world.
		blocksPerPart = if renderedParts > 0 then visibleBlocks / renderedParts else 0,
		cachedColumns = genCount + oldGenCount,
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
	distance = math.floor(tonumber(distance) or VIEW_DISTANCE)
	distance = math.clamp(distance, 0, MAX_VIEW_DISTANCE)

	local hadOverrides = next(playerViewDistance) ~= nil
	if distance == VIEW_DISTANCE and not hadOverrides then
		return VIEW_DISTANCE
	end

	VIEW_DISTANCE = distance
	table.clear(playerViewDistance)

	TerrainManager:_ReseatPlayers()

	return VIEW_DISTANCE
end

function TerrainManager:GetViewDistance()
	return VIEW_DISTANCE
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
	distance = math.floor(tonumber(distance) or VIEW_DISTANCE)
	distance = math.clamp(distance, MIN_VIEW_DISTANCE, MAX_VIEW_DISTANCE)

	if viewDistanceFor(player) == distance then
		return distance
	end

	playerViewDistance[player] = distance

	-- Re-seat only this player. Their chunks are reference counted against
	-- everyone else's, so widening loads what is missing and narrowing releases
	-- what nobody else wants, without touching anything anyone else is standing
	-- in.
	local previous = playerChunk[player]
	if previous then
		refreshPlayerChunks(player, previous.x, previous.z)
	end

	return distance
end

function TerrainManager:GetPlayerViewDistance(player)
	return viewDistanceFor(player)
end

function TerrainManager:GetViewDistanceRange()
	return MIN_VIEW_DISTANCE, MAX_VIEW_DISTANCE
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
		TerrainManager:_UnloadChunk(entry.cx, entry.cz)
	end

	for key, data in pairs(chunks) do
		if not generatingChunks[key] then
			TerrainManager:_UnloadChunk(data.cx, data.cz)
		end
	end

	table.clear(genHeight)
	table.clear(genBiome)
	table.clear(genTop)
	table.clear(genUnder)
	table.clear(genVariant)
	table.clear(genWater)
	genCount = 0

	table.clear(oldHeight)
	table.clear(oldBiome)
	table.clear(oldTop)
	table.clear(oldUnder)
	table.clear(oldVariant)
	table.clear(oldWater)
	oldGenCount = 0

	ColumnSource.clearCaches()
	if CAVES_ENABLED then
		CaveMap.clearCaches()
	end

	if alsoDropPools then
		for name, pool in pairs(partPool) do
			for i = #pool, 1, -1 do
				local part = pool[i]
				pool[i] = nil
				if part then
					part:Destroy()
				end
			end
			partPool[name] = nil
			poolLowWater[name] = nil
		end
		pooledParts = 0
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
	for player, previous in pairs(playerChunk) do
		if player.Parent then
			refreshPlayerChunks(player, previous.x, previous.z)
		end
	end
end

return TerrainManager
