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
	  Terrain.ChunkEdits         what players have changed
	  Blocks.BlockConfig         what a block drops and how hard it is

	Adding a biome, ore, block or structure never requires touching this file.

	PUBLIC API
	  TerrainManager:Init()
	  TerrainManager:InspectBlock(part | x, y, z, initiator) -> name, item, reason
	  TerrainManager:BreakBlock(part | x, y, z, initiator) -> ok, itemName, reason
	  TerrainManager:PlaceBlock(player, blockX, by, blockZ, name) -> ok, reason
	  TerrainManager:IsSolidAt(blockX, by, blockZ) -> boolean
	  TerrainManager:GetChunk(cx, cz)
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

--[[
	Where columns come from: the open world's BiomeMap, or in the Island place
	the island template. Both answer sampleColumn with the same six values, so
	nothing below this line knows which place it is in. TerrainConfig and
	OreConfig make the matching size, depth and ore adjustments themselves.
]]
local ColumnSource = if PlaceConfig.isIsland() then IslandShape else BiomeMap

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

	local height = getGeneratedColumn(cx * CHUNK_SIZE + bx, cz * CHUNK_SIZE + bz)
	return by < height
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

	local height, _biome, _top, _under, _variant, water =
		getGeneratedColumn(cx * CHUNK_SIZE + bx, cz * CHUNK_SIZE + bz)
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
	Rebuilds the Parts for one Y layer of a chunk from its visible set.

	Two passes. The first turns the visible set into the final list of
	rectangles. The second walks that list against the parts already drawing this
	layer, reusing each in order where the block type still matches, and only
	falling back to pool traffic where it does not. A layer that did not really
	change therefore costs a handful of property writes rather than a full
	teardown.
]]
local function remeshLayer(data, by)
	table.clear(layerGrid)

	local visible = data.visible
	local anything = false

	for cell = 1, CHUNK_AREA do
		local column = visible[cell]
		local name = column[by]
		if name ~= nil then
			layerGrid[cell] = name
			anything = true
		end
	end

	local existing = data.layerParts[by]
	local existingCount = if existing then #existing else 0

	if not anything then
		if existing then
			for i = existingCount, 1, -1 do
				releasePart(existing[i])
				existing[i] = nil
			end
			data.layerParts[by] = nil
		end
		return
	end

	-- Pass 1: rectangles.
	table.clear(layerRects)
	local count = TerrainMesher.meshLayer(
		layerGrid, CHUNK_SIZE, TerrainConfig.MergeSurfaceRuns, layerRects
	)

	table.clear(finalRects)
	local write = 0

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
					finalRects[write + 1] = bx + dx
					finalRects[write + 2] = bz + dz
					finalRects[write + 3] = 1
					finalRects[write + 4] = 1
					finalRects[write + 5] = name
					write += 5
				end
			end
		else
			finalRects[write + 1] = bx
			finalRects[write + 2] = bz
			finalRects[write + 3] = sizeX
			finalRects[write + 4] = sizeZ
			finalRects[write + 5] = name
			write += 5
		end
	end

	-- Pass 2: reconcile against what is already drawn.
	local bucket = existing
	if not bucket then
		bucket = {}
		data.layerParts[by] = bucket
	end

	local kept = 0
	local rectCount = write // 5

	for index = 0, rectCount - 1 do
		local base = index * 5
		local bx = finalRects[base + 1]
		local bz = finalRects[base + 2]
		local sizeX = finalRects[base + 3]
		local sizeZ = finalRects[base + 4]
		local name = finalRects[base + 5]

		local slot = index + 1
		local reuse = bucket[slot]
		local part

		-- Consumed the moment it is read. `kept` can fall behind `slot` when a
		-- block has no usable template, and without this the part would be
		-- written to a lower slot while its original slot still referenced it -
		-- the tail sweep below would then release a part that is still in play.
		bucket[slot] = nil

		if reuse and reuse.Name == name then
			reshapeMeshPart(data, reuse, bx, bz, sizeX, sizeZ, by)
			part = reuse
		else
			if reuse then
				-- Wrong block type for this slot; it goes back to its own pool.
				releasePart(reuse)
			end
			part = emitMeshPart(data, bx, bz, sizeX, sizeZ, by, name)
		end

		-- part is nil only when the block has no usable template, which warns
		-- elsewhere. Skipping the slot keeps the bucket a dense array.
		if part then
			kept += 1
			bucket[kept] = part
		end
	end

	for i = existingCount, kept + 1, -1 do
		local leftover = bucket[i]
		if leftover then
			releasePart(leftover)
		end
		bucket[i] = nil
	end

	Profiler.count("Terrain.layerMeshed")
end

--[[
	Rebuilds every layer that changed since the last flush.

	Visibility is decided per column, but a Part now spans columns, so the two
	cannot be done in one step: the whole column pass has to finish before the
	layers it touched can be meshed. Callers do a batch of column updates and
	then flush once.
]]
local function flushChunkMesh(data)
	if data.dirtyCount == 0 then
		return
	end

	for by in pairs(data.dirtyLayers) do
		remeshLayer(data, by)
	end

	table.clear(data.dirtyLayers)
	data.dirtyCount = 0
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
local function scanColumnRange(data, cx, cz, bx, bz, cell, column, low, high, waterLow, waterHigh)
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
			local visible = not isBlockPresent(cx, cz, bx, bz, by + 1)

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
		The water band: the part of this column's water that its neighbours do
		not already hide.

		Water is NOT part of the heightmap - `currentHeight` is still the top of
		the solid ground, so mining, placement, collision and the strata below
		are all untouched by it. It is drawn as its own short band on top, which
		is what keeps the fast path below exactly as cheap as it was.

		Clamped so at least the surface block is always drawn: in the middle of a
		lake every neighbour covers everything, and the band would otherwise come
		out empty and leave a hole in the water.
	]]
	local water = data.waterTop[cell]
	local waterLow, waterHigh = 1, 0 -- empty

	if water > currentHeight then
		waterHigh = water - 1
		waterLow = if minCover > currentHeight then minCover else currentHeight
		if waterLow > waterHigh then
			waterLow = waterHigh
		end
	end

	if not data.complex[cell] and not neighbourComplex then
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

		for by = waterLow, waterHigh do
			setVisible(data, cell, by, WATER_BLOCK)
		end

		Profiler.leave("Terrain.columnVisibility")
		return
	end

	-- General path. Two bands: the surface, and whatever has been dug into.
	-- One block of margin on the disturbed band covers the blocks that line a
	-- hole from below and above.
	local scanTop = data.topScan[cell]

	local lowA, highA = surfaceLow, scanTop - 1
	local lowB, highB = 1, 0 -- empty by default

	if bandLow <= bandHigh then
		lowB = bandLow - 1
		highB = bandHigh + 1
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

	scanColumnRange(data, cx, cz, bx, bz, cell, column, lowB, highB, waterLow, waterHigh)
	scanColumnRange(data, cx, cz, bx, bz, cell, column, lowA, highA, waterLow, waterHigh)

	-- After the scans, so a structure block standing in the water keeps the
	-- slot: isPresentInData is the authority on what is solid, and water only
	-- fills what is left.
	for by = waterLow, waterHigh do
		if not isPresentInData(data, cell, by) then
			setVisible(data, cell, by, WATER_BLOCK)
		end
	end

	Profiler.count("Terrain.columnSlowPath")
	Profiler.leave("Terrain.columnVisibility")
end

--[[
	Re-evaluates a column and its four neighbours after an edit, then rebuilds
	whatever layers that touched.

	The flush happens once, after all five columns have settled, and covers every
	chunk involved - an edit on a chunk border moves blocks in two of them, and
	meshing one before the other had finished would build a rectangle out of a
	half-updated layer.
]]
local function refreshAdjacentColumns(cx, cz, bx, bz)
	local touched = {}

	local own = chunks[chunkKey(cx, cz)]
	if own then
		touched[own] = true
	end

	updateColumnVisibility(cx, cz, bx, bz)

	for i = 1, 4 do
		local ncx, ncz, nbx, nbz = normalizeCell(cx, cz, bx + DIR_X[i], bz + DIR_Z[i])
		if isChunkInBounds(ncx, ncz) then
			local neighbour = chunks[chunkKey(ncx, ncz)]
			if neighbour then
				touched[neighbour] = true
				updateColumnVisibility(ncx, ncz, nbx, nbz)
			end
		end
	end

	for data in pairs(touched) do
		flushChunkMesh(data)
	end
end

--[[
	Re-evaluates the border columns of already-loaded neighbours after a chunk
	appears. Heights alone would not need this (an unloaded neighbour already
	answers with its generated height), but added blocks would: a boulder that
	spills across the border only exists once both chunks are built.
]]
local function refreshChunkBorders(cx, cz)
	for i = 1, 4 do
		local ncx = cx + DIR_X[i]
		local ncz = cz + DIR_Z[i]

		local neighbour = isChunkInBounds(ncx, ncz) and chunks[chunkKey(ncx, ncz)]
		if neighbour then
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
	}

	chunks[key] = data
	loadedChunkCount += 1

	local writer = makeWriter(cx, cz, data)

	-- Phase 1: structure terrain edits, before anything is rendered, so the
	-- chunk is built once rather than built and then patched.
	phaseStart = chunkCpuSpent(ctx)
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
	for index = 0, CHUNK_AREA - 1 do
		updateColumnVisibility(cx, cz, index // CHUNK_SIZE, index % CHUNK_SIZE)
		yieldIfOverBudget(ctx)
	end

	-- Every column has decided what it wants drawn; now turn that into the
	-- smallest set of Parts that draws it. Meshing after the whole chunk rather
	-- than per column is what lets a rectangle span columns at all.
	flushChunkMesh(data)
	Profiler.sample("Terrain.gen.4render", (chunkCpuSpent(ctx) - phaseStart) * 1000, "ms")

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

	if data.model then
		data.model:Destroy()
	end

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

function pumpGeneration()
	if pumping then
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
end

local function onHeartbeatMovement(dt)
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

	local ok, item, reason = removeResolvedBlock(data, cell, by)
	return finish(ok, item, reason)
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
		refreshAdjacentColumns(column[1],column[2],column[3],column[4])
	end
	-- Keep ground fragments visible even when a dense overhead shaft fills the cap.
	local groundLimit=math.min(#groundDebris,math.max(32,64-#shaftDebris))
	for i=1,math.min(#shaftDebris,64-groundLimit) do table.insert(debris,shaftDebris[i]) end
	for i=1,groundLimit do table.insert(debris,groundDebris[i]) end
	return removed,debris
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
	ensureGeneratedTemplates()

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

		-- Optional: the island keeps its spawn clearing and beach free of
		-- trees. BiomeMap has no such rule and leaves this nil.
		allowStructureAt = ColumnSource.allowStructureAt,
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
	return height * STUD_SIZE, biome
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
