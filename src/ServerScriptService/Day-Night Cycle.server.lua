--[[
	DayNightCycle

	Keeps Lighting on the world clock. The time itself is WorldClock's - shared
	by every server, so it is morning everywhere at once, and /time moves it in
	all of them. This script only copies it onto Lighting.

	Lighting's time is a replicated property, so every write is a network update
	to every client. Four a second still steps by well under a minute of game
	time, and nobody can see finer than that.
]]

local Lighting = game:GetService("Lighting")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldClock = require(ServerScriptService:WaitForChild("WorldClock"))

local UPDATE_INTERVAL = 0.25

while true do
	Lighting:SetMinutesAfterMidnight(WorldClock.minutes())
	task.wait(UPDATE_INTERVAL)
end
