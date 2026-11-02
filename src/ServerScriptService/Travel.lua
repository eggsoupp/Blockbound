--[[
	Travel

	Moving a player between BlockBound's two places. One copy, used by the
	admin chat commands (TravelCommands), the tutorial's island button and the
	island recall (IslandRecall).

		Travel.go(player, "island" | "world") -> true when a teleport was sent

	WHAT A TRIP COSTS

	The player leaves this server and joins another, so everything that saves
	on leaving - their inventory, and the island they are leaving if it is
	theirs - saves on the way out exactly as it would if they had quit. The
	server they arrive at waits for that save to land before loading them; see
	InventoryStore's session lock.

	Teleports do not work in Studio. Asking for one there says so instead of
	failing silently.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local PlaceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlaceConfig"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local IslandDirectory = require(ServerScriptService:WaitForChild("IslandDirectory"))
local IslandSlots = require(ServerScriptService:WaitForChild("IslandSlots"))

local tell = CommandFeedback.tell

local Travel = {}

local function teleport(player, placeId, accessCode): boolean
	local options = Instance.new("TeleportOptions")
	if accessCode then
		options.ReservedServerAccessCode = accessCode
	end

	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, placeId, { player }, options)
	if not ok then
		tell(player, "Teleport failed: " .. tostring(err), "bad")
	end
	return ok
end

-- Whether `player` is standing on the island they would travel to - their own,
-- and the one they have chosen (IslandSlots) - right now.
function Travel.onOwnIsland(player): boolean
	return PlaceConfig.isIsland()
		and workspace:GetAttribute("IslandOwnerId") == player.UserId
		and (workspace:GetAttribute("IslandSlot") or 1) == IslandSlots.active(player)
end

function Travel.go(player, destination: string): boolean
	if RunService:IsStudio() then
		tell(player, "Teleports don't work in Studio. Publish the game and try this in a live server.", "bad")
		return false
	end

	if destination == "world" then
		if PlaceConfig.isWorld() then
			tell(player, "You're already in the world.", "bad")
			return false
		end
		if PlaceConfig.WorldPlaceId == 0 then
			tell(player, "The World place ID isn't set in PlaceConfig.", "bad")
			return false
		end

		tell(player, "Heading to the world...", "good")
		return teleport(player, PlaceConfig.WorldPlaceId)
	end

	-- To their island. Already there only if this IS their island's server.
	if Travel.onOwnIsland(player) then
		tell(player, "You're already on your island.", "bad")
		return false
	end

	tell(player, if IslandSlots.count(player) > 1
		then string.format("Heading to island %d...", IslandSlots.active(player))
		else "Heading to your island...", "good")

	local slot = IslandSlots.active(player)
	local code, err = IslandDirectory.accessCodeFor(player.UserId, slot)
	if not code then
		tell(player, "Couldn't find your island: " .. tostring(err), "bad")
		return false
	end

	return teleport(player, PlaceConfig.IslandPlaceId, code)
end

return Travel
