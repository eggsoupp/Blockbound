--[[
	OreDepletion

	Which ore blocks have already been harvested, so that ground which regrows
	does not carry its ore a second time. Part of TerrainManager; see
	TerrainManager for the map of terrain modules.

	Ore is a pure function of position (OreRegistry), and a mined block is only
	a ChunkEdits removal. Once that removal is forgotten - the chunk
	regenerated, or ChunkEdits evicted it - the generator would put the same
	ore back, and mining, leaving and returning would be a farm. So every ore
	block that is removed, by a pickaxe, an ability or a boss, is remembered
	here for the life of the server, and ChunkData.blockNameFor answers with
	the plain rock for those cells. The rock comes back; the ore does not.

	One number per harvested ore block, in memory only: nothing is saved (the
	world is new on every server) and nothing is written per block anywhere.
	Bounded by TerrainConfig.Regeneration.MaxDepletedOres: past it the chunks
	whose ore was taken longest ago are forgotten first.

	A chunk's set is handed to its chunk data as `data.oreGone` (ChunkBuilder
	at build, BlockEdits when the first ore there is taken), so the per-block
	lookup is a table read with no call into this module.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TerrainConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Terrain"):WaitForChild("TerrainConfig")
)

local OreDepletion = {}

local FLOOR_Y = TerrainConfig.WorldFloorY
local MAX_ENTRIES = TerrainConfig.Regeneration.MaxDepletedOres

-- A cell of a chunk as one number: cell * STRIDE + (by - FLOOR_Y). The
-- world is about 400 blocks from floor to ceiling, so 512 layers is enough.
-- ChunkData.blockNameFor packs the same way.
local STRIDE = 512
OreDepletion.STRIDE = STRIDE
assert(TerrainConfig.MaxHeight + TerrainConfig.StructureHeadroom - FLOOR_Y < STRIDE, "[OreDepletion] world too tall for STRIDE")

local byChunk = {} -- chunkKey -> { [packed cell] = true }
local counts = {} -- chunkKey -> entries in that set
local lastTaken = {} -- chunkKey -> os.clock() of the latest ore taken there
local total = 0
local forgotten = 0

-- Drops the chunks mined longest ago until a tenth of the room is free, so
-- this runs once per many thousand ores rather than on every one.
local function evict(keep)
	local keys = {}
	for key in pairs(byChunk) do
		if key ~= keep then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys, function(a, b)
		return lastTaken[a] < lastTaken[b]
	end)

	local target = math.floor(MAX_ENTRIES * 0.9)
	for _, key in ipairs(keys) do
		if total <= target then
			break
		end
		total -= counts[key]
		forgotten += counts[key]
		byChunk[key], counts[key], lastTaken[key] = nil, nil, nil
	end
end

-- The set for a chunk, or nil when no ore has been taken there.
function OreDepletion.forChunk(chunkKey)
	return byChunk[chunkKey]
end

-- Remembers one harvested ore block. Returns the chunk's set, which the
-- caller stores on the chunk data (it may have just been created).
function OreDepletion.record(chunkKey, cell, by)
	local gone = byChunk[chunkKey]
	if not gone then
		gone = {}
		byChunk[chunkKey] = gone
		counts[chunkKey] = 0
	end

	local packed = cell * STRIDE + (by - FLOOR_Y)
	if not gone[packed] then
		gone[packed] = true
		counts[chunkKey] += 1
		lastTaken[chunkKey] = os.clock()
		total += 1
		if total > MAX_ENTRIES then
			evict(chunkKey)
		end
	end

	return gone
end

function OreDepletion.getStats()
	return { depletedOres = total, forgotten = forgotten, max = MAX_ENTRIES }
end

return OreDepletion
