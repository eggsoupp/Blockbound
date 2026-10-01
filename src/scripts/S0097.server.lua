--[[
	DayNightCycle

	Advances the clock so a full day takes DAY_LENGTH_MINUTES.

	Lighting's time is a replicated property, so every write is a network update
	to every client. Four a second still steps by well under a minute of game
	time, and nobody can see finer than that.
]]

local Lighting = game:GetService("Lighting")

local DAY_LENGTH_MINUTES = 12
local UPDATE_INTERVAL = 0.25

local MINUTES_IN_A_DAY = 24 * 60

local dayLength = math.max(0.1, DAY_LENGTH_MINUTES)
local cycleSeconds = dayLength * 60
local timeRatio = MINUTES_IN_A_DAY / cycleSeconds

-- Start from wherever Lighting already is, so the cycle picks up the time set
-- in Studio rather than snapping to midnight on launch.
local startTime = os.clock() - (Lighting:GetMinutesAfterMidnight() / MINUTES_IN_A_DAY) * cycleSeconds

while true do
	local elapsed = os.clock() - startTime
	if elapsed >= cycleSeconds then
		startTime += cycleSeconds
		elapsed -= cycleSeconds
	end

	Lighting:SetMinutesAfterMidnight(elapsed * timeRatio)
	task.wait(UPDATE_INTERVAL)
end
