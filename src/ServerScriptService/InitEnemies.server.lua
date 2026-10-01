--[[
	Starts the enemy system.

	Separate from EnemyService itself for the same reason InitTerrain is separate
	from TerrainManager: requiring a module should not have side effects, so that
	a command or another system can pull it in to ask a question without
	accidentally starting it.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))

EnemyService.init()
