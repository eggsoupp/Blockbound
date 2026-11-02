--[[
	QuestState

	The client's view of the quests: which are complete (the server's word,
	from ServerScriptService.QuestService) and how far along the rest are
	(worked out here from the bag and the bestiary, for drawing only).

		QuestState.status(quest)   "done", "open" (can be worked on) or "locked"
		QuestState.context()       QuestBook's context for progress bars
		QuestState.focus()         the first open quest, or nil when none are
		QuestState.counts()        done, total
		QuestState.Changed         fires when any of that may have changed
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local QuestBook = require(Shared:WaitForChild("Quests"):WaitForChild("QuestBook"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local InventoryMirror = require(Shared:WaitForChild("Inventory"):WaitForChild("InventoryMirror"))
local BestiaryState = require(script.Parent:WaitForChild("BestiaryState"))

local QuestState = {}

local done: { [string]: boolean } = {}
local changed = Instance.new("BindableEvent")
QuestState.Changed = changed.Event

local function poke()
	changed:Fire()
end
InventoryMirror.onChanged(poke)
BestiaryState.Changed:Connect(poke)

function QuestState.status(quest): string
	if done[quest.id] then
		return "done"
	end
	return if QuestBook.unlocked(quest, done) then "open" else "locked"
end

function QuestState.context()
	return QuestBook.context(InventoryMirror.get(), BestiaryState.get())
end

function QuestState.focus()
	for _, quest in ipairs(QuestBook.Quests) do
		if QuestState.status(quest) == "open" then
			return quest
		end
	end
	return nil
end

function QuestState.counts(): (number, number)
	local count = 0
	for _, quest in ipairs(QuestBook.Quests) do
		if done[quest.id] then
			count += 1
		end
	end
	return count, #QuestBook.Quests
end

task.spawn(function()
	local remote = Remotes.wait("Quests", 60)
	if not remote then
		return
	end
	remote.OnClientEvent:Connect(function(list)
		if type(list) ~= "table" then
			return
		end
		done = {}
		for _, id in ipairs(list) do
			if type(id) == "string" then
				done[id] = true
			end
		end
		poke()
	end)
	remote:FireServer("sync")
end)

return QuestState
