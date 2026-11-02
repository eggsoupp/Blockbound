--[[
	BestiaryState

	The client's copy of ServerScriptService.Bestiary: which creatures this
	player has met and how many of each they have killed.

		BestiaryState.get()            { [enemy] = kills }, 0 = met only
		BestiaryState.entries()        the listed enemies, in EnemyConfig.Order
		BestiaryState.counts()         met, total
		BestiaryState.Changed          fires with the table when it changes

	Read-only from here; the server decides what counts as met.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

-- Left out: the All Seeing Eye's eyes are Demon Eyes, and a Blightling is
-- the Blightborer's and has no model of its own. Kept in step with the server.
local ALIASES = { ServantEye = true, Blightling = true }

local BestiaryState = {}

local record = {}
local changed = Instance.new("BindableEvent")
BestiaryState.Changed = changed.Event

local listed = {}
for _, name in ipairs(EnemyConfig.Order) do
	if not ALIASES[name] and EnemyConfig.Definitions[name] then
		table.insert(listed, name)
	end
end

function BestiaryState.get()
	return record
end

function BestiaryState.entries(): { string }
	return listed
end

function BestiaryState.counts(): (number, number)
	local met = 0
	for _, name in ipairs(listed) do
		if record[name] ~= nil then
			met += 1
		end
	end
	return met, #listed
end

task.spawn(function()
	local remote = Remotes.wait("Bestiary", 60)
	if not remote then
		return
	end
	remote.OnClientEvent:Connect(function(value)
		if type(value) == "table" then
			record = value
			changed:Fire(record)
		end
	end)
	remote:FireServer("sync")
end)

return BestiaryState
