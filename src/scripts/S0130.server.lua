--[[
	SettingsServer

	The settings a player may change that the SERVER has to agree to.

	Right now that is one: view distance. It lives here rather than on the
	client because it decides how much terrain the server generates and holds on
	that player's behalf, so the number has to be clamped somewhere a modified
	client cannot reach.

		client -> RequestViewDistance(n)
		server -> ViewDistanceChanged(applied, min, max)

	The reply is sent whether or not the value changed, and carries the bounds,
	because the menu builds itself from it: that is how the stepper knows where
	to stop, and how asking for something out of range shows up as the value
	snapping rather than as nothing happening.

	Anything purely local - music volume - is not here and should not be. The
	test for this file is whether the server has to spend something on it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))

local RequestViewDistance = Remotes.ensure("RequestViewDistance", "RemoteEvent")
local ViewDistanceChanged = Remotes.ensure("ViewDistanceChanged", "RemoteEvent")

--[[
	Minimum gap between one player's requests.

	Not a courtesy: a change re-seats that player's whole active set, which at
	the top of the range queues over two hundred chunks. Holding the arrow key
	down on the stepper would otherwise ask the generator to do that several
	times a second.
]]
local MIN_REQUEST_INTERVAL = 0.3

local lastRequestAt = {}

local function reply(player)
	local minimum, maximum = TerrainManager:GetViewDistanceRange()
	ViewDistanceChanged:FireClient(
		player, TerrainManager:GetPlayerViewDistance(player), minimum, maximum
	)
end

RequestViewDistance.OnServerEvent:Connect(function(player, distance)
	--[[
		Anything that is not a number is a QUERY: "tell me what I am on".

		The menu asks this every time it opens, which is what keeps it honest
		after something else moved the value - /bbvd and the benchmark both put
		every player back on the default, and without this the panel would go on
		showing a number nobody is using any more.
	]]
	if type(distance) ~= "number" or distance ~= distance then
		reply(player)
		return
	end

	local now = os.clock()
	local last = lastRequestAt[player]
	if last and now - last < MIN_REQUEST_INTERVAL then
		-- Still answer, so a client that got ahead of itself is corrected back
		-- to what the server actually holds rather than left showing its guess.
		reply(player)
		return
	end
	lastRequestAt[player] = now

	TerrainManager:SetPlayerViewDistance(player, distance)
	reply(player)
end)

--[[
	The starting value.

	Deferred rather than sent on PlayerAdded: the client's own scripts are still
	loading at that point, and a reply that arrives before the menu is listening
	leaves the option showing nothing until the player touches it.
]]
Players.PlayerAdded:Connect(function(player)
	task.delay(1, function()
		if player.Parent then
			reply(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
end)
