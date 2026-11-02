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

	The trip itself is ServerScriptService.Travel's.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))
local Permissions = require(Shared:WaitForChild("Permissions"))

local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local Travel = require(ServerScriptService:WaitForChild("Travel"))

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

local function travel(player, destination)
	Travel.go(player, destination)
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

-- The tutorial's "Go to my island" button: open to every player once the
-- tutorial has reached its island step, not only to admins.
local tutorialTravel = require(Shared.Net.Remotes).ensure("TutorialTravel", "RemoteEvent")
tutorialTravel.OnServerEvent:Connect(function(player)
	local step = player:GetAttribute("TutorialStep")
	if step ~= "island" and step ~= "done" then return end
	local now = os.clock()
	if now - (lastTravelAt[player] or -math.huge) < MIN_INTERVAL then return end
	lastTravelAt[player] = now
	travel(player, "island")
end)

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
