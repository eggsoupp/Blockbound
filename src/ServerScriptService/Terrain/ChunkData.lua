--[[
	ChunkData

	The loaded chunks and every question and primitive edit on their cells:
	what is solid, what block is where, marking blocks removed or placed, and
	the writer structures build through. Also the residency registry the other
	terrain modules share - which chunks are loaded, building, wanted, pinned,
	and where each player stands - so none of them has to own another's state.
	Part of TerrainManager; see TerrainManager for the map of terrain modules.

	All tables here keep their identity for the life of the server, so other
	modules may hold them in locals.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local StrataConfig = require(TerrainShared:WaitForChild("StrataConfig"))
local OreRegistry = require(TerrainShared:WaitForChild("OreRegistry"))
local CaveMap = require(TerrainShared:WaitForChild("CaveMap"))

local GeneratedColumns = require(script.Parent:WaitForChild("GeneratedColumns"))

local ChunkData = {}

local CHUNK_SIZE = TerrainConfig.ChunkSize
local FLOOR_Y = TerrainConfig.WorldFloorY
local MAX_BLOCK_Y = TerrainConfig.WorldCeilingY
local BEDROCK_BLOCK = StrataConfig.BedrockBlock
local BEDROCK_TOP_Y = FLOOR_Y + StrataConfig.BedrockThickness - 1

--[[
	Inlinable copies of TerrainGrid helpers, on purpose. Luau's optimiser only
	inlines a `local function` defined in the same script, and these run per
	block in the visibility and face passes; calling TerrainGrid's versions
	across modules measured ~10% slower there. Keep them identical to
	TerrainGrid (the canonical definitions).
]]
local function chunkKey(cx, cz)
	return (cx + 8192) * 65536 + (cz + 8192)
end
local MIN_CHUNK_X, MAX_CHUNK_X = TerrainConfig.MinChunkX, TerrainConfig.MaxChunkX
local MIN_CHUNK_Z, MAX_CHUNK_Z = TerrainConfig.MinChunkZ, TerrainConfig.MaxChunkZ
local function isChunkInBounds(cx, cz)
	return cx >= MIN_CHUNK_X and cx <= MAX_CHUNK_X and cz >= MIN_CHUNK_Z and cz <= MAX_CHUNK_Z
end
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
local getGeneratedColumn = GeneratedColumns.get
local ColumnSource = GeneratedColumns.source
local CAVES_ENABLED = GeneratedColumns.cavesEnabled

-- ---------------------------------------------------------------------------
-- Residency
-- ---------------------------------------------------------------------------

local chunks = {} -- chunkKey -> chunk data
ChunkData.chunks = chunks
ChunkData.loadedCount = 0 -- live size of `chunks`, kept incrementally

-- chunkKey -> true while a coroutine is building it
ChunkData.generating = {}

-- chunkKey -> { cx, cz, dueAt }: loaded chunks nobody wants, unloading once
-- their grace period is up (see ChunkStreaming).
ChunkData.pendingUnload = {}

-- chunkKey -> how many players want it
local usageCounts = {}
ChunkData.usage = usageCounts

-- player -> { x, z, active }: the chunk each player stands in and the set
-- they want loaded around it.
ChunkData.playerChunk = {}

-- Server-owned earth movement (block walls, boss displacement): cell id ->
-- the loan that reserved it, and chunkKey -> how many loans keep it resident.
ChunkData.reservedCells = {}
ChunkData.pinnedChunks = {}

function ChunkData.isWanted(key)
	local count = usageCounts[key]
	return count ~= nil and count > 0
end

-- ---------------------------------------------------------------------------
-- Solidity changes, for FaceCulling
-- ---------------------------------------------------------------------------

-- Cells whose solidity changed since FaceCulling last processed them, as flat
-- data, cell, by triples.
local solidChanges = {}
local solidChangeCount = 0

--[[
	Records that a cell became solid or empty, once the chunk is being drawn
	(data.trackFaces). Before that nothing has a Part yet, and every Part will
	be decided from the finished data when it is emitted.
]]
local function noteSolidChange(data, cell, by)
	if not data.trackFaces then
		return
	end
	solidChanges[solidChangeCount + 1] = data
	solidChanges[solidChangeCount + 2] = cell
	solidChanges[solidChangeCount + 3] = by
	solidChangeCount += 3
end
ChunkData.noteSolidChange = noteSolidChange

-- The pending changes (flat triples) and how many entries are in use.
function ChunkData.solidChanges()
	return solidChanges, solidChangeCount
end

function ChunkData.clearSolidChanges()
	table.clear(solidChanges)
	solidChangeCount = 0
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
	noteSolidChange(data, cell, by)

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
		noteSolidChange(data, cell, by)
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
	noteSolidChange(data, cell, by)
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

ChunkData.isPresentInData = isPresentInData
ChunkData.isBlockPresent = isBlockPresent
ChunkData.neighbourColumn = neighbourColumn
ChunkData.markDisturbed = markDisturbed
ChunkData.blockNameFor = blockNameFor
ChunkData.markRemoved = markRemoved
ChunkData.applyRemoval = applyRemoval
ChunkData.applyPlacement = applyPlacement
ChunkData.makeWriter = makeWriter

return ChunkData
