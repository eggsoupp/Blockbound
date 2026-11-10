--[[
	QuestService

	Decides when a player's quests (Shared.Quests.QuestBook) are complete,
	saves them, and tells the client.

		QuestService.init()   once, from InitEnemies, after the Bestiary

	Every CHECK_SECONDS each loaded player's bag (InventoryService) and
	bestiary record (Bestiary) are checked against the book; whatever is newly
	complete is announced, marked dirty for saving and pushed. Once complete,
	a quest stays complete.

	Saved as the "quests" section of the InventoryStore record: a list of
	completed ids. An id the book no longer has is dropped on load.

	The client is sent the completed ids over the Quests remote, and can ask
	again with "sync".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestBook = require(Shared:WaitForChild("Quests"):WaitForChild("QuestBook"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local Bestiary = require(ServerScriptService:WaitForChild("Bestiary"))

local CHECK_SECONDS = 2

local QuestService = {}

-- player -> { [id] = true }. Weak-keyed so the leave-save can still read it.
local done = setmetatable({}, { __mode = "k" })
local remote

local function push(player: Player)
	local list = {}
	for id in pairs(done[player] or {}) do
		table.insert(list, id)
	end
	remote:FireClient(player, list)
end

local function check(player: Player)
	local record = done[player]
	local inventory = InventoryService.GetInventory(player)
	local bestiary = Bestiary.record(player)
	if not record or not inventory or not bestiary then
		return
	end

	local context = QuestBook.context(inventory.data, bestiary)
	local completed = QuestBook.advance(record, context)
	if #completed == 0 then
		return
	end

	InventoryStore.markDirty(player)
	push(player)

	-- One line for one quest; a returning player catching up on a dozen gets
	-- a count rather than a dozen lines.
	if #completed == 1 then
		CommandFeedback.tell(player, "Quest complete: " .. QuestBook.byId[completed[1]].title, "good")
	else
		CommandFeedback.tell(player, string.format("%d quests complete", #completed), "good")
	end

	-- Wish Stars for each one (see Shared.Wish.WishConfig.Earn).
	local ok, WishService = pcall(require, script.Parent:FindFirstChild("WishService"))
	if ok and WishService then
		local Earn = require(game:GetService("ReplicatedStorage").Shared.Wish.WishConfig).Earn
		WishService.award(player, Earn.Quest * #completed, if #completed == 1 then "quest complete" else "quests complete")
	end
end

function QuestService.init()
	remote = Remotes.ensure("Quests", "RemoteEvent")

	InventoryStore.registerSection("quests", function(player)
		local list = {}
		for id in pairs(done[player] or {}) do
			table.insert(list, id)
		end
		return list
	end, function(player, value)
		local record = {}
		if type(value) == "table" then
			for _, id in ipairs(value) do
				if type(id) == "string" and QuestBook.byId[id] then
					record[id] = true
				end
			end
		end
		done[player] = record
		push(player)
	end)

	remote.OnServerEvent:Connect(function(player, action)
		if action == "sync" and done[player] then
			push(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(check, player)
				if not ok then
					warn("[QuestService]", err)
				end
			end
		end
	end)
end

return QuestService
