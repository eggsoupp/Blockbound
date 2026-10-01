--[[
	Starts the weapon ability system.

	Separate from AbilityService for the same reason InitCombat is separate from
	CombatService: requiring a module should not have side effects, so that
	anything wanting to cancel a player's casts can pull AbilityService in
	without also deciding when the remotes get connected.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local AbilityService = require(ServerScriptService:WaitForChild("AbilityService"))
local ScrollService = require(ServerScriptService:WaitForChild("ScrollService"))

AbilityService.init()

-- Scrolls are how an ability is EARNED, so they start with the system they
-- feed rather than getting an init script of their own. See ScrollService.
ScrollService.start()
