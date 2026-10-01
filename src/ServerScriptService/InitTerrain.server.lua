--[[
	Starts terrain generation.

	Separate from TerrainManager for the same reason as the other Init scripts:
	requiring a module should not have side effects, so anything that needs to
	ask the terrain a question can pull it in without also starting it.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))

TerrainManager:Init()
