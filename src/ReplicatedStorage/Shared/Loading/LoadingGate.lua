--[[
	LoadingGate

	Holds back work that would compete with the loading screen for downloads,
	until the screen has gone. Client only; on the server it never waits.

		LoadingGate.defer(fn, ...)   -- fn(...) once the screen is gone,
		                             -- or now if it already is
		LoadingGate.isDone()

	WHY
	  Every script's ContentProvider:PreloadAsync goes through one engine
	  queue. At join the boss's effects, every creature effect and the whole
	  combat sound bank were asked for in the same instant as the hotbar's
	  tools, and the UI atlas waited 2.5 s behind ~300 of them. The startup
	  preloads that nothing needs in the first seconds of play wait here
	  instead, and the screen gets the queue to itself.

	It never holds anything for long: at most MAX_WAIT seconds after this
	module is first required, so a missing or broken loading screen costs a
	few seconds of warm-up, not the warm-up itself.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")

local MAX_WAIT = 8

local LoadingGate = {}

local released = false
local waiting = {}

local function release()
	if released then
		return
	end
	released = true
	local list = waiting
	waiting = {}
	for _, entry in ipairs(list) do
		task.spawn(table.unpack(entry, 1, entry.n))
	end
end

function LoadingGate.isDone(): boolean
	return released
end

function LoadingGate.defer(fn: (...any) -> ...any, ...)
	if released then
		task.spawn(fn, ...)
		return
	end
	table.insert(waiting, table.pack(fn, ...))
end

local player = Players.LocalPlayer

if not RunService:IsClient() or not player then
	release()
elseif player:GetAttribute("LoadingScreenDone") or not ReplicatedFirst:FindFirstChild("LoadingScreen") then
	release()
else
	player:GetAttributeChangedSignal("LoadingScreenDone"):Connect(function()
		if player:GetAttribute("LoadingScreenDone") then
			release()
		end
	end)
	task.delay(MAX_WAIT, release)
end

return LoadingGate
