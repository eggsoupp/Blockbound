--[[
	TerrainGrid

	The block world's coordinate systems and the packing of chunk keys, in one
	place. Pure functions of TerrainConfig: no state, safe on server and client.

	  world studs   what Roblox uses
	  block         world studs / StudSize. Block (0,0,0) starts at stud (0,0,0).
	  chunk         block / ChunkSize, horizontally only (chunks are full-depth).
	  cell          a column inside a chunk, packed as bx * ChunkSize + bz + 1
	                (1-based so per-chunk tables stay true arrays).

	Chunk and block coordinates are packed into single numbers. String keys used
	to be built inside the visibility loop, which allocated tens of thousands of
	strings per chunk. ChunkEdits stores edits under chunkKey, so the packing is
	part of the save path: TerrainManager:ChunkKey / :ChunkCoords convert it.

	Hot callers localise the functions they use (`local chunkKey =
	TerrainGrid.chunkKey`), which keeps each call an upvalue call.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TerrainConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Terrain"):WaitForChild("TerrainConfig"))

local TerrainGrid = {}

local STUD_SIZE = TerrainConfig.StudSize
local CHUNK_SIZE = TerrainConfig.ChunkSize
local CHUNK_STUDS = TerrainConfig.ChunkStuds

local MIN_CHUNK_X = TerrainConfig.MinChunkX
local MAX_CHUNK_X = TerrainConfig.MaxChunkX
local MIN_CHUNK_Z = TerrainConfig.MinChunkZ
local MAX_CHUNK_Z = TerrainConfig.MaxChunkZ

local CHUNK_KEY_OFFSET = 8192
local CHUNK_KEY_STRIDE = 65536

TerrainGrid.CHUNK_AREA = CHUNK_SIZE * CHUNK_SIZE
TerrainGrid.CHUNK_KEY_OFFSET = CHUNK_KEY_OFFSET
TerrainGrid.CHUNK_KEY_STRIDE = CHUNK_KEY_STRIDE
TerrainGrid.BLOCK_KEY_OFFSET = 65536
TerrainGrid.BLOCK_KEY_STRIDE = 262144

-- The four horizontal neighbours, as parallel arrays.
TerrainGrid.DIR_X = { 1, -1, 0, 0 }
TerrainGrid.DIR_Z = { 0, 0, 1, -1 }

function TerrainGrid.chunkKey(cx, cz)
	return (cx + CHUNK_KEY_OFFSET) * CHUNK_KEY_STRIDE + (cz + CHUNK_KEY_OFFSET)
end

function TerrainGrid.chunkCoords(key)
	return key // CHUNK_KEY_STRIDE - CHUNK_KEY_OFFSET, key % CHUNK_KEY_STRIDE - CHUNK_KEY_OFFSET
end

local function isChunkInBounds(cx, cz)
	return cx >= MIN_CHUNK_X and cx <= MAX_CHUNK_X and cz >= MIN_CHUNK_Z and cz <= MAX_CHUNK_Z
end
TerrainGrid.isChunkInBounds = isChunkInBounds

function TerrainGrid.isBlockInWorld(blockX, blockZ)
	local cx = blockX // CHUNK_SIZE
	local cz = blockZ // CHUNK_SIZE
	return isChunkInBounds(cx, cz)
end

local function getChunkWorldOrigin(cx, cz)
	return cx * CHUNK_STUDS, cz * CHUNK_STUDS
end
TerrainGrid.getChunkWorldOrigin = getChunkWorldOrigin

local function getChunkCoordX(worldX)
	return math.floor(worldX / CHUNK_STUDS + 0.000001)
end
TerrainGrid.getChunkCoordX = getChunkCoordX

local function getChunkCoordZ(worldZ)
	return math.floor(worldZ / CHUNK_STUDS + 0.000001)
end
TerrainGrid.getChunkCoordZ = getChunkCoordZ

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
TerrainGrid.normalizeCell = normalizeCell

function TerrainGrid.worldToChunkLocal(wx, wz)
	local cx = getChunkCoordX(wx)
	local cz = getChunkCoordZ(wz)
	local ox, oz = getChunkWorldOrigin(cx, cz)
	local bx = math.floor((wx - ox) / STUD_SIZE)
	local bz = math.floor((wz - oz) / STUD_SIZE)
	return normalizeCell(cx, cz, bx, bz)
end

-- 1-based so every per-chunk table stays a true array rather than degrading
-- into a hash part at index 0.
function TerrainGrid.cellOf(bx, bz)
	return bx * CHUNK_SIZE + bz + 1
end

-- The (chunk, local cell) holding an absolute block column.
function TerrainGrid.blockToChunkLocal(blockX, blockZ)
	return normalizeCell(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE, blockX % CHUNK_SIZE, blockZ % CHUNK_SIZE)
end

return TerrainGrid
