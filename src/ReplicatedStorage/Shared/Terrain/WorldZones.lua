--[[
	WorldZones

	Which part of the open world a block column is in, for the rules that
	differ near spawn (TerrainConfig.SpawnZones):

	  protected   the immediate spawn. Nothing there may change.
	  starter     the square around it, protected core included. Mining is
	              normal, building is capped, abandoned ground regrows fast.
	  wild        everything else.

	Pure functions of position, so the server enforces with them and a client
	may ask the same question to explain a refusal. An island has no zones:
	every answer is false there.
]]

local TerrainFolder = script.Parent
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))
local PlaceConfig = require(TerrainFolder.Parent:WaitForChild("PlaceConfig"))

local WorldZones = {}

local ENABLED = not PlaceConfig.isIsland()
local STUD_SIZE = TerrainConfig.StudSize
local CHUNK_SIZE = TerrainConfig.ChunkSize
local PROTECTED_SQUARED = TerrainConfig.SpawnZones.ProtectedBlocks ^ 2
local STARTER = TerrainConfig.SpawnZones.StarterBlocks

WorldZones.enabled = ENABLED
WorldZones.StarterBuildHeight = TerrainConfig.SpawnZones.StarterBuildHeight

-- Measured to the centre of the column, so the edge is a circle of whole blocks.
local function isProtected(blockX, blockZ)
	if not ENABLED then
		return false
	end
	local x, z = blockX + 0.5, blockZ + 0.5
	return x * x + z * z <= PROTECTED_SQUARED
end
WorldZones.isProtected = isProtected

function WorldZones.isProtectedPosition(position)
	return isProtected(math.floor(position.X / STUD_SIZE), math.floor(position.Z / STUD_SIZE))
end

local function isStarter(blockX, blockZ)
	return ENABLED and blockX >= -STARTER and blockX < STARTER and blockZ >= -STARTER and blockZ < STARTER
end
WorldZones.isStarter = isStarter

function WorldZones.isStarterPosition(position)
	return isStarter(math.floor(position.X / STUD_SIZE), math.floor(position.Z / STUD_SIZE))
end

-- StarterBlocks is whole chunks, so a chunk is in the area or out of it.
function WorldZones.isStarterChunk(cx, cz)
	return isStarter(cx * CHUNK_SIZE, cz * CHUNK_SIZE)
end

return WorldZones
