--[[
	SettingsServer

	The settings a player may change that the SERVER has to agree to.

	Right now that is one: view distance. It lives here rather than on the
	client because it decides how much terrain the server generates and holds on
	that player's behalf, so the number has to be clamped somewhere a modified
	client cannot reach.

		client -> RequestViewDistance(n)
		server -> ViewDistanceChanged(applied, min, max, default)

	The reply is sent whether or not the value changed, and carries the bounds,
	because the menu builds itself from it: that is how the stepper knows where
	to stop, and how asking for something out of range shows up as the value
	snapping rather than as nothing happening.

	Anything purely local - music volume - is not DECIDED here and should not
	be. The test for that is whether the server has to spend something on it.

	IT DOES KEEP THEM, THOUGH

	Every setting is saved with the player, as the "settings" section of their
	save record (see InventoryStore.registerSection): the local ones as the
	client sends them (Shared.UI.PlayerSettings), and view distance as the
	server last applied it. When the record loads, the local ones go back to
	the client and the distance is put back on the terrain.

		client -> SettingsSync(nil)      "send me what is saved"
		client -> SettingsSync(table)    "save these"
		server -> SettingsSync(table)    what is saved
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))

local RequestViewDistance = Remotes.ensure("RequestViewDistance", "RemoteEvent")
local ViewDistanceChanged = Remotes.ensure("ViewDistanceChanged", "RemoteEvent")
local SettingsSync = Remotes.ensure("SettingsSync", "RemoteEvent")

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
		player,
		TerrainManager:GetPlayerViewDistance(player),
		minimum,
		maximum,
		TerrainManager:GetViewDistance()
	)
end

-- ---------------------------------------------------------------------------
-- Saved settings
-- ---------------------------------------------------------------------------

--[[
	What a client may have saved, and what each has to be. Anything else in a
	request is dropped. Shared.UI.PlayerSettings.Definitions is the client's
	half of this list; a setting added there has to be added here.
]]
local STORED = {
	musicVolume = "volume",
	sfxVolume = "volume",
	damageNumbers = "boolean",
	hitFlash = "boolean",
}

--[[
	Each player's saved settings.

	WEAK-KEYED and not cleared on PlayerRemoving, for the reason AbilityLoadout
	gives for its own tables: the leave save reads every section, and the order
	two scripts' PlayerRemoving handlers run in is undefined. Clearing this there
	would save an empty table over the player's settings about half the time.
]]
local saved = setmetatable({}, { __mode = "k" })

-- True once the player's record has come back. Nothing is saved before then:
-- a session that could not read the record must not write a guess over it.
local loadedFor = {}

local function isVolume(value)
	return type(value) == "number" and value == value and value >= 0 and value <= 1
end

-- Only the known settings, each of the right kind.
local function cleanLocal(value)
	local clean = {}
	if type(value) ~= "table" then
		return clean
	end
	for key, kind in pairs(STORED) do
		local item = value[key]
		if (kind == "volume" and isVolume(item)) or (kind == "boolean" and type(item) == "boolean") then
			clean[key] = item
		end
	end
	return clean
end

InventoryStore.registerSection("settings", function(player)
	local entry = saved[player]
	return if entry then table.clone(entry) else nil
end, function(player, value)
	local entry = cleanLocal(value)

	if type(value) == "table" and type(value.viewDistance) == "number" then
		-- Put back through TerrainManager, which clamps it to today's bounds.
		entry.viewDistance = TerrainManager:SetPlayerViewDistance(player, value.viewDistance)
		reply(player)
	end

	saved[player] = entry
	loadedFor[player] = true
	SettingsSync:FireClient(player, cleanLocal(entry))
end)

-- Keeps the distance the server just applied, so it is what the next join gets.
local function rememberDistance(player)
	local entry = saved[player]
	if not (entry and loadedFor[player]) then
		return
	end
	local distance = TerrainManager:GetPlayerViewDistance(player)
	if entry.viewDistance ~= distance then
		entry.viewDistance = distance
		InventoryStore.markDirty(player)
	end
end

SettingsSync.OnServerEvent:Connect(function(player, values)
	if values == nil then
		if loadedFor[player] then
			SettingsSync:FireClient(player, cleanLocal(saved[player]))
		end
		return
	end

	if not loadedFor[player] or type(values) ~= "table" then
		return
	end

	-- No rate limit: merging four values costs nothing, and the actual write is
	-- the autosave's, which keeps its own interval. Dropping a request here
	-- would lose a change.
	local entry = saved[player]
	local changed = false
	for key, item in pairs(cleanLocal(values)) do
		if entry[key] ~= item then
			entry[key] = item
			changed = true
		end
	end

	if changed then
		InventoryStore.markDirty(player)
	end
end)

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
	rememberDistance(player)
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
	-- Everything except `saved`, which the leave save may not have read yet.
	loadedFor[player] = nil
end)
