--[[
	TravelCommands

	Chat commands for moving between BlockBound's two places.

	  /island, /home   to your own island
	  /world           to the open world
	  /savestatus      whether your inventory and this island are saving

	ADMIN ONLY FOR NOW

	Travel is a developer tool until the join menu and island permissions
	exist; until then nobody else has an island worth going to. Who counts is
	Permissions.isAdmin, the same rule every other command uses.

	WHAT A TRIP COSTS

	The player leaves this server and joins another, so everything that saves
	on leaving - their inventory, and the island they are leaving if it is
	theirs - saves on the way out exactly as it would if they had quit. The
	server they arrive at waits for that save to land before loading them; see
	InventoryStore's session lock.

	Teleports do not work in Studio. Typing these there says so instead of
	failing silently.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))
local Permissions = require(Shared:WaitForChild("Permissions"))

local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local IslandDirectory = require(ServerScriptService:WaitForChild("IslandDirectory"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))

local tell = CommandFeedback.tell

-- First thing in every server's log: which place this is and which PUBLISHED
-- version it runs. A server keeps the version it started with, and Studio
-- edits only reach live servers through File > Publish - so when live
-- behaves like old code, this line is how to tell.
print(string.format("[BlockBound] %s place (id %d), published version %d", PlaceConfig.kind(), game.PlaceId, game.PlaceVersion))

local COMMANDS = {
	["/island"] = "island",
	["/home"] = "island",
	["/world"] = "world",
	["/savestatus"] = "status",
}

-- Seconds between travel requests from one player. A teleport takes longer
-- than this anyway; it stops a double-press starting two.
local MIN_INTERVAL = 3

local lastTravelAt = {}

local function teleport(player, placeId, accessCode)
	local options = Instance.new("TeleportOptions")
	if accessCode then
		options.ReservedServerAccessCode = accessCode
	end

	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, placeId, { player }, options)
	if not ok then
		tell(player, "Teleport failed: " .. tostring(err), "bad")
	end
end

local function travel(player, destination)
	if RunService:IsStudio() then
		tell(player, "Teleports don't work in Studio. Publish the game and try this in a live server.", "bad")
		return
	end

	if destination == "world" then
		if PlaceConfig.isWorld() then
			tell(player, "You're already in the world.", "bad")
			return
		end
		if PlaceConfig.WorldPlaceId == 0 then
			tell(player, "The World place ID isn't set in PlaceConfig.", "bad")
			return
		end

		tell(player, "Heading to the world...", "good")
		teleport(player, PlaceConfig.WorldPlaceId)
		return
	end

	-- To their island. Already there only if this IS their island's server.
	if PlaceConfig.isIsland() and workspace:GetAttribute("IslandOwnerId") == player.UserId then
		tell(player, "You're already on your island.", "bad")
		return
	end

	tell(player, "Heading to your island...", "good")

	local code, err = IslandDirectory.accessCodeFor(player.UserId)
	if not code then
		tell(player, "Couldn't find your island: " .. tostring(err), "bad")
		return
	end

	teleport(player, PlaceConfig.IslandPlaceId, code)
end

-- The island half of /savestatus, read off the attributes IslandService keeps
-- on Workspace. nil in the open world.
local function describeIsland()
	if not PlaceConfig.isIsland() then
		return nil
	end

	local owner = workspace:GetAttribute("IslandOwnerId")
	if owner == nil then
		return "Island: still loading"
	end

	if not workspace:GetAttribute("IslandSaving") then
		return string.format(
			"Island %d: saving OFF (%s)", owner, tostring(workspace:GetAttribute("IslandSaveProblem"))
		)
	end

	local lastSaved = workspace:GetAttribute("IslandLastSaved")
	return string.format(
		"Island %d: saving on, %s%s",
		owner,
		if lastSaved then string.format("last saved %ds ago", os.time() - lastSaved) else "not saved yet this session",
		if workspace:GetAttribute("IslandUnsaved") then ", unsaved changes" else ""
	)
end

local function onChatted(player, message)
	local command = string.match(message, "^%s*(/%a+)%s*$")
	local destination = command and COMMANDS[string.lower(command)]
	if not destination then
		return
	end

	if not Permissions.isAdmin(player) then
		tell(player, "Travel is limited to the game owner for now.", "bad")
		return
	end

	if destination == "status" then
		tell(player, string.format("Place: %s, published version %d", PlaceConfig.kind(), game.PlaceVersion))
		tell(player, "Inventory: " .. InventoryStore.summary(player))
		local island = describeIsland()
		if island then
			tell(player, island)
		end
		return
	end

	local now = os.clock()
	local last = lastTravelAt[player]
	if last and now - last < MIN_INTERVAL then
		return
	end
	lastTravelAt[player] = now

	travel(player, destination)
end

-- A teleport can also fail after TeleportAsync has returned - the destination
-- refusing, or the player's connection dropping. Say so, and let them retry.
TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
	lastTravelAt[player] = nil
	tell(player, string.format("Teleport failed (%s): %s", tostring(result), tostring(errorMessage)), "bad")
end)

local function watch(player)
	player.Chatted:Connect(function(message)
		local ok, err = pcall(onChatted, player, message)
		if not ok then
			warn("[TravelCommands] errored for", player.Name, err)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end
Players.PlayerAdded:Connect(watch)

Players.PlayerRemoving:Connect(function(player)
	lastTravelAt[player] = nil
end)
