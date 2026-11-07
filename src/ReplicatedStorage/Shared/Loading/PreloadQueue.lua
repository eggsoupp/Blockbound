--[[
	PreloadQueue

	ContentProvider:PreloadAsync behind a priority queue and a few workers, so
	a slow asset holds up one worker and nothing else. Client only.

		local queue = PreloadQueue.new(4)
		queue:add({ key = tool, label = "tools", items = { tool } }, 1)
		queue:progress(2)        -- doneWeight, totalWeight over tiers 1 and 2
		queue:remaining(1)       -- tier-1 jobs not finished yet
		queue:waitingOn(2, 1.0)  -- tier-2 jobs worth waiting for (not stuck)
		queue:setMaxTier(3)      -- let background jobs start
		queue:setWorkers(2)      -- fewer workers once the game is playing
		queue:setReserve(0)      -- stop keeping a worker free for tier 1
		queue.Progressed         -- fires (job) whenever a job finishes

	A JOB is { key, label, items, weight, run? }:
	  key     anything unique: the Instance itself, or an asset id string.
	          Adding the same key twice keeps the better (lower) tier.
	  label   what the loading screen says it is doing ("tools", "effects")
	  items   what PreloadAsync is given: Instances, each preloading every
	          asset under it
	  weight  how much of the bar it is worth; 1 if missing
	  run     optional: done instead of PreloadAsync (fonts, tests)

	TIERS
	  1  essential   the loading screen waits for these (up to its deadline)
	  2  first pass  loaded while the screen is up, if there is time
	  3  background  only once the screen has gone

	Nothing here ever waits on a job. A worker stuck on an asset that will not
	answer just stays stuck, and the others carry on with the queue; the screen
	decides when it is done by the clock, not by this.
]]

local ContentProvider = game:GetService("ContentProvider")

local PreloadQueue = {}
PreloadQueue.__index = PreloadQueue

local TIERS = 3
local SLOW_AFTER = 1.0

function PreloadQueue.new(workers: number)
	local self = setmetatable({}, PreloadQueue)

	self.jobs = {} -- key -> job
	self.waiting = {} -- tier -> first-in first-out list of jobs
	for tier = 1, TIERS do
		self.waiting[tier] = {}
	end

	self.maxTier = 2
	self.target = math.max(1, workers)
	-- Workers kept free of tier 2 and 3, for essentials that arrive late (the
	-- hotbar comes from the server a second or two in). Set to 0 once only
	-- background work is left.
	self.reserve = 1
	self.runningLow = 0 -- running jobs of tier 2 or 3
	self.running = 0
	self.idle = {} -- worker threads parked until there is work
	self.current = nil -- the job started most recently

	-- A job still running after this long is WRITTEN OFF: it keeps loading,
	-- but its worker's place goes to a fresh worker, so a failing asset (an
	-- engine retrying three times) cannot sit on a slot. At most `stuckCap`
	-- written-off jobs at once, so a run of them cannot grow without bound.
	self.slowAfter = SLOW_AFTER
	self.stuck = 0
	self.stuckCap = self.target * 2

	-- Asset counts from PreloadAsync's callback, across every job.
	self.loaded = 0
	self.failed = 0

	-- Cached sums, recomputed when a job is added, moved or finished.
	self.dirty = true
	self.sums = {}

	self.progressed = Instance.new("BindableEvent")
	self.Progressed = self.progressed.Event

	self:_spawnWorkers()
	return self
end

-- ---------------------------------------------------------------------------
-- Queueing
-- ---------------------------------------------------------------------------

function PreloadQueue:get(key)
	return self.jobs[key]
end

function PreloadQueue:add(job, tier: number)
	tier = math.clamp(tier, 1, TIERS)

	local existing = self.jobs[job.key]
	if existing then
		if tier < existing.tier then
			-- Still waiting: move it up the queue. Already started or done: it
			-- just counts towards the better tier from now on.
			if existing.state == "waiting" then
				local list = self.waiting[existing.tier]
				local index = table.find(list, existing)
				if index then
					table.remove(list, index)
				end
				table.insert(self.waiting[tier], existing)
			end
			existing.tier = tier
			self.dirty = true
			self:_wake()
		end
		return existing
	end

	job.tier = tier
	job.state = "waiting"
	job.weight = job.weight or 1
	job.failures = 0

	self.jobs[job.key] = job
	table.insert(self.waiting[tier], job)
	self.dirty = true
	self:_wake()
	return job
end

function PreloadQueue:setMaxTier(tier: number)
	self.maxTier = math.clamp(tier, 1, TIERS)
	self:_wakeAll()
end

function PreloadQueue:setWorkers(count: number)
	self.target = math.max(1, count)
	self:_spawnWorkers()
	-- Parked workers over the new count wake up to notice and leave.
	self:_wakeAll()
end

-- ---------------------------------------------------------------------------
-- Progress
-- ---------------------------------------------------------------------------

function PreloadQueue:_sum()
	if not self.dirty then
		return
	end
	self.dirty = false

	local sums = {}
	for tier = 1, TIERS do
		sums[tier] = { done = 0, total = 0, doneJobs = 0, jobs = 0 }
	end

	for _, job in pairs(self.jobs) do
		local sum = sums[job.tier]
		sum.total += job.weight
		sum.jobs += 1
		if job.state == "done" then
			sum.done += job.weight
			sum.doneJobs += 1
		end
	end

	self.sums = sums
end

-- Weight finished and weight queued, over every tier up to `maxTier`, then
-- the same in jobs.
function PreloadQueue:progress(maxTier: number): (number, number, number, number)
	self:_sum()
	local done, total, doneJobs, jobs = 0, 0, 0, 0
	for tier = 1, math.clamp(maxTier, 1, TIERS) do
		local sum = self.sums[tier]
		done += sum.done
		total += sum.total
		doneJobs += sum.doneJobs
		jobs += sum.jobs
	end
	return done, total, doneJobs, jobs
end

-- Jobs at or under `maxTier` that have not finished.
function PreloadQueue:remaining(maxTier: number): number
	local _, _, doneJobs, jobs = self:progress(maxTier)
	return jobs - doneJobs
end

--[[
	Jobs of exactly `tier` still worth waiting for: not finished, and not
	running for longer than `slowAfter` seconds. A job that slow is an asset
	that is failing or crawling; it keeps loading, but nothing should wait on
	it. A job marked holdScreen (tests) is never written off.
]]
function PreloadQueue:waitingOn(tier: number, slowAfter: number): number
	local now = os.clock()
	local count = 0
	for _, job in pairs(self.jobs) do
		if job.tier == tier and job.state ~= "done" then
			local slow = job.state == "running" and now - job.startedAt > slowAfter
			if job.holdScreen or not slow then
				count += 1
			end
		end
	end
	return count
end

function PreloadQueue:setReserve(count: number)
	self.reserve = math.max(0, count)
	self:_wakeAll()
end

-- ---------------------------------------------------------------------------
-- Workers
-- ---------------------------------------------------------------------------

function PreloadQueue:_next()
	for tier = 1, self.maxTier do
		local list = self.waiting[tier]
		if #list > 0 then
			if tier > 1 and self.target > 1 and self.runningLow >= self.target - self.reserve then
				return nil
			end
			return table.remove(list, 1)
		end
	end
	return nil
end

-- Returns true when the job was written off while it ran: its worker's
-- place has gone to another, so this worker should leave.
function PreloadQueue:_run(job): boolean
	job.state = "running"
	job.startedAt = os.clock()
	self.current = job
	local low = job.tier > 1
	if low then
		self.runningLow += 1
	end

	-- The write-off. Checked once, after slowAfter: a job done by then is
	-- left alone.
	task.delay(self.slowAfter, function()
		if job.state ~= "running" or self.stuck >= self.stuckCap then
			return
		end
		job.writtenOff = true
		self.stuck += 1
		self.running -= 1
		if low then
			self.runningLow -= 1
		end
		self:_spawnWorkers()
		self:_wake()
	end)

	if job.run then
		local ok, err = pcall(job.run)
		if not ok then
			job.failures += 1
			warn("[PreloadQueue]", tostring(job.label), err)
		end
	elseif job.items and #job.items > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(job.items, function(_, status)
				if status == Enum.AssetFetchStatus.Success then
					self.loaded += 1
				elseif status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
					self.failed += 1
					job.failures += 1
				end
			end)
		end)
	end

	job.state = "done"
	job.finishedAt = os.clock()
	if job.writtenOff then
		self.stuck -= 1
	elseif low then
		self.runningLow -= 1
		-- A reserved slot may have opened for a parked worker.
		self:_wake()
	end
	self.dirty = true
	self.progressed:Fire(job)
	return job.writtenOff == true
end

function PreloadQueue:_worker()
	while true do
		if self.running > self.target then
			self.running -= 1
			return
		end

		local job = self:_next()
		if job then
			if self:_run(job) then
				-- Written off: a replacement took this worker's place (and its
				-- count) while it waited, so it simply ends.
				return
			end
		else
			table.insert(self.idle, coroutine.running())
			coroutine.yield()
		end
	end
end

function PreloadQueue:_spawnWorkers()
	while self.running < self.target do
		self.running += 1
		task.spawn(self._worker, self)
	end
end

function PreloadQueue:_wake()
	local thread = table.remove(self.idle)
	if thread then
		task.spawn(thread)
	end
end

function PreloadQueue:_wakeAll()
	local threads = self.idle
	self.idle = {}
	for _, thread in ipairs(threads) do
		task.spawn(thread)
	end
end

return PreloadQueue
