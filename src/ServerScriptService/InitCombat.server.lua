--[[
	Starts the combat system.

	Separate from CombatService for the same reason InitTerrain is separate from
	TerrainManager: requiring a module should not have side effects, so that
	EnemyService can pull it in to deal damage without also deciding when it
	starts.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))

CombatService.init()
