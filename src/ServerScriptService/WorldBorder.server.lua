--[[
	Invisible collision at the edge of the world; the force field players see
	there is drawn by WorldBorderClient. Parts cap out at 2048 studs, so each
	side is a row of them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))

if not PlaceConfig.isWorld() then
	return
end

local WORLD_EDGE = TerrainConfig.WorldRadiusBlocks * TerrainConfig.StudSize
local WALL_LENGTH = 2048
local WALL_HEIGHT = 2048
local WALL_CENTRE_Y = 800
local WALL_THICKNESS = 16

local folder = Instance.new("Folder")
folder.Name = "WorldBorderWalls"

local function wall(position, size)
	local part = Instance.new("Part")
	part.Name = "BorderWall"
	part.Anchored = true
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = size
	part.Position = position
	part.Parent = folder
end

local offset = WALL_THICKNESS / 2
local count = math.ceil((WORLD_EDGE * 2) / WALL_LENGTH)
for i = 0, count - 1 do
	local along = -WORLD_EDGE + (i + 0.5) * WALL_LENGTH
	for _, sign in { -1, 1 } do
		local edge = sign * (WORLD_EDGE + offset)
		wall(Vector3.new(edge, WALL_CENTRE_Y, along), Vector3.new(WALL_THICKNESS, WALL_HEIGHT, WALL_LENGTH))
		wall(Vector3.new(along, WALL_CENTRE_Y, edge), Vector3.new(WALL_LENGTH, WALL_HEIGHT, WALL_THICKNESS))
	end
end

folder.Parent = workspace
