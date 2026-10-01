--[[
	ChunkEdits

	Remembers what players have done to the world, so that streaming a chunk out
	and back in does not undo it.

	Chunk data is disposable by design - regenerated from noise every load, which
	is what keeps memory flat as the world grows. That is right for generated
	terrain and wrong for anything a player did, so this is the small persistent
	layer beside it.

	Two maps per chunk, mirroring the two things a player can do:

	  removed[cell][by] = true    a block that was mined out
	  placed[cell][by]  = name    a block the player put down

	Replay order at generation matters and is fixed by applyTo:
	  base columns -> structures -> removals -> placements
	so a player can mine a structure block (removal wins over the structure) and
	place a block into a hole they dug (placement wins over the removal).

	Removals are replayed top-down within a column because removing the current
	top block lowers the column rather than recording a hole, and that collapse
	only coalesces correctly in descending order.

	COORDINATES
	  cell is the chunk-local packed column index used by TerrainManager,
	  bx * ChunkSize + bz + 1. Callers pass it through rather than recomputing.
]]

local TerrainFolder = script.Parent
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))

local ChunkEdits = {}

-- chunkKey -> { removed = {...}, placed = {...}, count = n }
local chunkStore = {}

-- chunkKey -> os.clock() when this chunk's edits were last written or replayed.
-- Drives eviction order; see evictIfNeeded.
local lastTouched = {}

local totalEdits = 0
local editedChunks = 0
local evictedChunks = 0
local evictedEdits = 0

-- Injected by TerrainManager. A resident chunk's rendered parts and stored
-- edits have to agree, so residency is a hard veto on eviction rather than a
-- weighting. An injected predicate for the same reason the replay callbacks
-- are: this module never learns how terrain is stored.
local isChunkResident = nil

function ChunkEdits.setResidencyCheck(predicate)
	isChunkResident = predicate
end

-- Scratch buffer for the descending-order removal replay. Reused; never
-- survives a yield.
local scratchLevels = {}

local function descending(a, b)
	return a > b
end

-- The terrain there reverts to whatever the generator produces, which is why
-- this is only ever done to chunks nobody is standing in.
local function forget(chunkKey)
	local entry = chunkStore[chunkKey]
	if not entry then
		return
	end

	chunkStore[chunkKey] = nil
	lastTouched[chunkKey] = nil
	editedChunks -= 1
	totalEdits -= entry.count
	evictedChunks += 1
	evictedEdits += entry.count
end

--[[
	Keeps the store bounded. Two ceilings, because either alone can be defeated:
	a chunk count (many lightly-touched chunks) and a total edit count (one
	chunk somebody tunnelled through for an hour). Whichever trips, the least
	recently touched chunks that are NOT loaded are dropped until the store is
	under nine tenths of both, so the scan amortises rather than running on
	every write.

	Nothing loaded is ever evicted, so this cannot disagree with terrain a
	player is looking at. What it costs is that ground nobody has visited in a
	very long time heals back to its generated shape.
]]
local function evictIfNeeded()
	local maxChunks = TerrainConfig.MaxEditedChunks
	local maxEdits = TerrainConfig.MaxStoredEdits

	if editedChunks <= maxChunks and totalEdits <= maxEdits then
		return
	end

	local candidates = {}
	for chunkKey in pairs(chunkStore) do
		if not (isChunkResident and isChunkResident(chunkKey)) then
			candidates[#candidates + 1] = chunkKey
		end
	end

	table.sort(candidates, function(a, b)
		return (lastTouched[a] or 0) < (lastTouched[b] or 0)
	end)

	local targetChunks = math.floor(maxChunks * 0.9)
	local targetEdits = math.floor(maxEdits * 0.9)

	for _, chunkKey in ipairs(candidates) do
		if editedChunks <= targetChunks and totalEdits <= targetEdits then
			break
		end
		forget(chunkKey)
	end
end

local function getOrCreate(chunkKey)
	local entry = chunkStore[chunkKey]
	if not entry then
		entry = { removed = {}, placed = {}, count = 0 }
		chunkStore[chunkKey] = entry
		editedChunks += 1
		evictIfNeeded()
	end

	lastTouched[chunkKey] = os.clock()
	return entry
end

-- Zero count means both maps are empty and the entry is pure overhead. Unlike
-- eviction this loses nothing: placing a block and mining it again used to
-- leave a record behind for the rest of the session.
local function releaseIfEmpty(chunkKey, entry)
	if entry.count > 0 then
		return
	end

	chunkStore[chunkKey] = nil
	lastTouched[chunkKey] = nil
	editedChunks -= 1
end

local function setIn(map, cell, by, value)
	local column = map[cell]

	if value == nil then
		if column then
			column[by] = nil
		end
		return
	end

	if not column then
		column = {}
		map[cell] = column
	end
	column[by] = value
end

local function getIn(map, cell, by)
	local column = map[cell]
	return column and column[by]
end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------

function ChunkEdits.recordRemoval(chunkKey, cell, by)
	local entry = getOrCreate(chunkKey)

	if getIn(entry.removed, cell, by) then
		return
	end

	setIn(entry.removed, cell, by, true)
	entry.count += 1
	totalEdits += 1
end

function ChunkEdits.recordPlacement(chunkKey, cell, by, blockName)
	local entry = getOrCreate(chunkKey)

	if getIn(entry.placed, cell, by) == nil then
		entry.count += 1
		totalEdits += 1
	end

	setIn(entry.placed, cell, by, blockName)
end

-- The placement is forgotten entirely rather than turned into a removal, so
-- whatever the terrain would naturally have here comes back.
function ChunkEdits.clearPlacement(chunkKey, cell, by)
	local entry = chunkStore[chunkKey]
	if not entry then
		return
	end

	if getIn(entry.placed, cell, by) == nil then
		return
	end

	setIn(entry.placed, cell, by, nil)
	entry.count -= 1
	totalEdits -= 1
	lastTouched[chunkKey] = os.clock()

	releaseIfEmpty(chunkKey, entry)
end

-- Mining needs to know: breaking a placed block and a structure block are
-- recorded differently.
function ChunkEdits.isPlaced(chunkKey, cell, by)
	local entry = chunkStore[chunkKey]
	return entry ~= nil and getIn(entry.placed, cell, by) ~= nil
end

-- ---------------------------------------------------------------------------
-- Replay
-- ---------------------------------------------------------------------------

--[[
	Replays every stored edit for a chunk onto a freshly generated one.

	  removeBlock(cell, by)          same semantics as breaking a block
	  placeBlock(cell, by, name)     same semantics as a structure adding one

	Both callbacks are supplied by TerrainManager, which owns the chunk data
	layout; this module only remembers what happened, never how to apply it.
]]
function ChunkEdits.applyTo(chunkKey, removeBlock, placeBlock)
	local entry = chunkStore[chunkKey]
	if not entry or entry.count == 0 then
		return
	end

	-- Being loaded counts as use. Without this a chunk a player keeps walking
	-- back into would age exactly like one they abandoned, and could be evicted
	-- out from under them on their next visit.
	lastTouched[chunkKey] = os.clock()

	-- Removals, top-down per column.
	for cell, column in pairs(entry.removed) do
		local count = 0
		for by in pairs(column) do
			count += 1
			scratchLevels[count] = by
		end

		for index = count + 1, #scratchLevels do
			scratchLevels[index] = nil
		end

		table.sort(scratchLevels, descending)

		for index = 1, count do
			removeBlock(cell, scratchLevels[index])
		end
	end

	table.clear(scratchLevels)

	-- Placements. Order does not matter: each writes an independent cell.
	for cell, column in pairs(entry.placed) do
		for by, name in pairs(column) do
			placeBlock(cell, by, name)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Housekeeping
-- ---------------------------------------------------------------------------

function ChunkEdits.getStats()
	return {
		editedChunks = editedChunks,
		totalEdits = totalEdits,
		evictedChunks = evictedChunks,
		evictedEdits = evictedEdits,
		maxEditedChunks = TerrainConfig.MaxEditedChunks,
		maxStoredEdits = TerrainConfig.MaxStoredEdits,
	}
end

return ChunkEdits
