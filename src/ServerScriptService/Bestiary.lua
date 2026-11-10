--[[
	Bestiary

	Which creatures each player has met, and how many of each they have
	killed. The Tab menu's bestiary (Shared.UI.BestiaryWindow) draws it.

		Bestiary.init()                 once, from InitEnemies
		Bestiary.killed(player, name)   from EnemyService, on a killing blow
		Bestiary.kills(player, name)    how many, for anything that asks
		Bestiary.record(player)         the whole record (QuestService)

	MET is being close: within DISCOVER_RANGE of one, checked once a second. A
	kill also counts, for the thing finished off from range.

	Saved as the "bestiary" section of the player's InventoryStore record:
	{ [enemy] = kills }, where 0 means met but never killed. Only enemies in
	EnemyConfig.Order are kept, under the name the bestiary lists them by
	(ALIASES: the eyes the All Seeing Eye sends are Demon Eyes).

	The client is sent the whole table over the Bestiary remote whenever it
	changes, at most once a second; it is a few dozen numbers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

local DISCOVER_RANGE = 45
local TICK = 1
local MAX_KILLS = 1e7

local ALIASES = {
	ServantEye = "DemonEye",
}

-- Not listed: the Blightborer's Blightlings have no model of their own.
local HIDDEN = {
	Blightling = true,
}

local Bestiary = {}

local listed = {}
for _, name in ipairs(EnemyConfig.Order) do
	if not ALIASES[name] and not HIDDEN[name] and EnemyConfig.Definitions[name] then
		listed[name] = true
	end
end

-- player -> { [enemy] = kills }. Weak-keyed so the leave-save can still read it.
local records = setmetatable({}, { __mode = "k" })
local dirty = {}
local remote

local function canonical(name: string?): string?
	if type(name) ~= "string" then
		return nil
	end
	name = ALIASES[name] or name
	return if listed[name] then name else nil
end

local function meet(player: Player, name: string): boolean
	local record = records[player]
	if not record or record[name] ~= nil then
		return false
	end
	record[name] = 0
	dirty[player] = true
	InventoryStore.markDirty(player)

	local def = EnemyConfig.Definitions[name]
	CommandFeedback.tell(player, "New bestiary entry: " .. (def.displayName or name), "good")
	return true
end

function Bestiary.killed(player: Player?, name: string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	name = canonical(name)
	local record = records[player]
	if not name or not record then
		return
	end
	meet(player, name)
	record[name] = math.min((record[name] or 0) + 1, MAX_KILLS)
	dirty[player] = true
	InventoryStore.markDirty(player)

	-- Wish Stars for the kill: always for a boss, now and then for anything
	-- else. Required here, not at the top: WishService is a later addition and
	-- this keeps the bestiary loading whatever happens to it.
	local ok, WishService = pcall(require, script.Parent:FindFirstChild("WishService"))
	if ok and WishService then
		local Earn = require(game:GetService("ReplicatedStorage").Shared.Wish.WishConfig).Earn
		local def = EnemyConfig.Definitions[name]
		if def and def.boss then
			WishService.award(player, Earn.Boss, (def.displayName or name) .. " defeated")
		elseif math.random() < Earn.EnemyChance then
			WishService.award(player, 1, "found on " .. (def and def.displayName or name))
		end
	end
end

-- The whole record, { [enemy] = kills }, or nil before it has loaded.
function Bestiary.record(player: Player)
	return records[player]
end

function Bestiary.kills(player: Player, name: string): number
	local record = records[player]
	return record and record[canonical(name) or name] or 0
end

local function push(player: Player)
	dirty[player] = nil
	if remote and player.Parent then
		remote:FireClient(player, records[player] or {})
	end
end

function Bestiary.init()
	remote = Remotes.ensure("Bestiary", "RemoteEvent")

	InventoryStore.registerSection("bestiary", function(player)
		return records[player] or {}
	end, function(player, value)
		local record = {}
		if type(value) == "table" then
			for name, kills in pairs(value) do
				local key = canonical(name)
				if key and type(kills) == "number" then
					record[key] = math.clamp(math.floor(kills), 0, MAX_KILLS)
				end
			end
		end
		records[player] = record
		push(player)
	end)

	remote.OnServerEvent:Connect(function(player, action)
		if action == "sync" and records[player] then
			push(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)

	-- Resolved here rather than at the top: EnemyService requires this module.
	local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))

	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, player in ipairs(Players:GetPlayers()) do
				local root = records[player] and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					EnemyService.forEachNear(root.Position, DISCOVER_RANGE, function(model)
						local name = canonical(EnemyService.describe(model))
						if name then
							meet(player, name)
						end
					end)
				end
				if dirty[player] then
					push(player)
				end
			end
		end
	end)
end

return Bestiary
