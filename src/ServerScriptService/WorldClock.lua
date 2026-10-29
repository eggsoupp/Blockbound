--[[
	WorldClock

	The time of day, the same in every server of the experience at once.

	It is not counted up from when a server started - that gave every server
	its own sky. It is read off the clock all Roblox servers share
	(workspace:GetServerTimeNow(), synced UTC): the day is that time, plus an
	offset, modulo the cycle length. Two servers with the same offset show the
	same minute without ever talking to each other.

	Changing the time (/time in DebugConsole) only changes the offset, and the
	new offset goes two ways:
	  MessagingService  to every server running now, within a second or so
	  DataStore         for servers that start later, and as the backstop for
	                    a message that never arrived: every server re-reads it
	                    every few minutes
	Each offset carries the moment it was set, and the newest always wins, so
	two admins changing the time at once settle on the same answer everywhere.

		WorldClock.minutes()        minutes after midnight, right now
		WorldClock.setHour(8.5)     08:30 now, in every server
]]

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")

local WorldClock = {}

-- One full day, in real seconds. The cycle has always been 12 minutes.
WorldClock.CycleSeconds = 12 * 60

local TOPIC = "WorldClock"
local STORE_NAME = "WorldClock"
local STORE_KEY = "offset"
-- How often a server re-reads the stored offset in case it missed a message.
local RESYNC_SECONDS = 300

local MINUTES_IN_A_DAY = 24 * 60

local offset = 0
-- Server time the current offset was chosen. 0 = never set: the default day.
local stamp = 0

local store = nil
do
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
	if ok then
		store = result
	else
		warn("[WorldClock] No DataStore (" .. tostring(result) .. "); /time will not outlive this server.")
	end
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Takes an offset if it is newer than the one held. True when it changed.
local function adopt(newOffset: any, newStamp: any): boolean
	if type(newOffset) ~= "number" or type(newStamp) ~= "number" or newOffset ~= newOffset then
		return false
	end
	if newStamp <= stamp then
		return false
	end
	offset = newOffset % WorldClock.CycleSeconds
	stamp = newStamp
	return true
end

local function readStore()
	if not store then
		return
	end
	local ok, record = pcall(store.GetAsync, store, STORE_KEY)
	if ok and type(record) == "table" then
		adopt(record.offset, record.stamp)
	elseif not ok then
		warn("[WorldClock] Could not read the stored time: " .. tostring(record))
	end
end

function WorldClock.minutes(): number
	local cycle = WorldClock.CycleSeconds
	return ((now() + offset) % cycle) / cycle * MINUTES_IN_A_DAY
end

--[[
	Sets the time to `hour` (0-24, fractions are minutes) everywhere. Applies
	here at once; the broadcast and the save happen in the background, and
	the second result says whether they could be started at all.
]]
function WorldClock.setHour(hour: number): (boolean, string?)
	local cycle = WorldClock.CycleSeconds
	local setAt = now()
	local newOffset = ((hour % 24) / 24 * cycle - setAt) % cycle
	adopt(newOffset, setAt)

	local record = { offset = newOffset, stamp = setAt }

	task.spawn(function()
		local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, record)
		if not ok then
			warn("[WorldClock] Broadcast failed, other servers catch up from the save: " .. tostring(err))
		end
	end)

	if not store then
		return true, "not saved: no DataStore here"
	end

	task.spawn(function()
		local ok, err = pcall(store.UpdateAsync, store, STORE_KEY, function(old)
			-- Someone set it later than this while the request was in flight.
			if type(old) == "table" and type(old.stamp) == "number" and old.stamp >= setAt then
				return nil
			end
			return record
		end)
		if not ok then
			warn("[WorldClock] Could not save the time: " .. tostring(err))
		end
	end)

	return true, nil
end

-- "08:30", for replies.
function WorldClock.format(minutes: number): string
	local whole = math.floor(minutes) % MINUTES_IN_A_DAY
	return string.format("%02d:%02d", whole // 60, whole % 60)
end

-- --------------------------------------------------------------------------
-- Start-up: the stored offset, then live updates, then the periodic re-read.
-- --------------------------------------------------------------------------

task.spawn(function()
	readStore()

	local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
		local data = message.Data
		if type(data) == "table" then
			adopt(data.offset, data.stamp)
		end
	end)
	if not ok then
		warn("[WorldClock] Not listening for time changes from other servers: " .. tostring(err))
	end

	while true do
		task.wait(RESYNC_SECONDS)
		readStore()
	end
end)

return WorldClock
