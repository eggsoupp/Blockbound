--[[
	Profiler

	Lightweight, always-present, off-by-default instrumentation.

	The point is to be able to answer "where did the frame go?" on a live server
	without shipping the cost of measuring. When Enabled is false every entry
	point is a single boolean test that Luau inlines away to nothing, so call
	sites can be left in permanently.

	USAGE

		local Profiler = require(ReplicatedStorage.Shared.Debug.Profiler)

		-- Timed section. Always pair; use a pcall-free straight line between.
		Profiler.enter("Terrain.generateChunk")
		... work ...
		Profiler.leave("Terrain.generateChunk")

		-- Counter, for "how many of these are we doing?" questions.
		Profiler.count("Terrain.partsPlaced")

		-- Distribution of a number that is not a duration, for
		-- "how big / how deep / how long did that take end to end?" questions.
		Profiler.sample("Terrain.chunkLatency", 83.4, "ms")

	TURNING IT ON

		Profiler.setEnabled(true)   -- from a debug command; see DebugConsole

	Enabling also emits Roblox MicroProfiler labels (debug.profilebegin), so the
	Studio MicroProfiler lines up with these buckets.

	Buckets are cheap: three parallel numeric maps keyed by name, no allocation
	per event once a name has been seen.
]]

local Profiler = {}

-- Production default. Nothing measures until something flips this.
Profiler.Enabled = false

local totalTime = {} -- name -> accumulated seconds, or accumulated raw value
local callCount = {} -- name -> number of enter() / count() / sample() events
local maxTime = {} -- name -> worst single sample, seconds or raw value
local openedAt = {} -- name -> os.clock() of the current open scope
local depth = {} -- name -> re-entrancy depth, so nesting cannot corrupt totals

-- name -> unit label, set only by sample(). Its presence is what marks a bucket
-- as holding raw numbers rather than seconds, so report() knows not to convert.
local unitOf = {}

local startedAt = os.clock()

local function touch(name)
	if totalTime[name] == nil then
		totalTime[name] = 0
		callCount[name] = 0
		maxTime[name] = 0
		depth[name] = 0
	end
end

--[[
	Flips instrumentation on or off. Turning it on resets the accumulators, so a
	report always describes one measurement window rather than everything since
	server start.
]]
function Profiler.setEnabled(enabled)
	enabled = enabled == true
	if enabled == Profiler.Enabled then
		return
	end

	Profiler.Enabled = enabled
	Profiler.reset()
end

function Profiler.reset()
	table.clear(totalTime)
	table.clear(callCount)
	table.clear(maxTime)
	table.clear(openedAt)
	table.clear(depth)
	table.clear(unitOf)
	startedAt = os.clock()
end

--[[
	Opens a timed scope. Re-entrant: only the outermost enter/leave pair for a
	given name contributes time, so a recursive caller reports wall time rather
	than a multiple of it.
]]
function Profiler.enter(name)
	if not Profiler.Enabled then
		return
	end

	touch(name)

	local d = depth[name]
	depth[name] = d + 1
	if d == 0 then
		openedAt[name] = os.clock()
		debug.profilebegin(name)
	end
end

function Profiler.leave(name)
	if not Profiler.Enabled then
		return
	end

	local d = depth[name]
	if d == nil or d <= 0 then
		return
	end

	d -= 1
	depth[name] = d
	if d > 0 then
		return
	end

	debug.profileend()

	local elapsed = os.clock() - (openedAt[name] or os.clock())
	openedAt[name] = nil

	totalTime[name] += elapsed
	callCount[name] += 1
	if elapsed > maxTime[name] then
		maxTime[name] = elapsed
	end
end

--[[
	Increments an event counter. `amount` defaults to 1.
]]
function Profiler.count(name, amount)
	if not Profiler.Enabled then
		return
	end

	touch(name)
	callCount[name] += (amount or 1)
end

--[[
	Records one observation of a number that is NOT a duration of the calling
	scope: end-to-end latency measured elsewhere, a queue depth, a part count.

	enter/leave cannot express those - it only times the code between the two
	calls, and a chunk's wall-clock latency spans dozens of frames during which
	the generator was deliberately asleep. Reported as count/mean/max in whatever
	`unit` says, so a latency bucket and a queue-depth bucket can coexist without
	one being silently read as milliseconds.
]]
function Profiler.sample(name, value, unit)
	if not Profiler.Enabled then
		return
	end
	if type(value) ~= "number" then
		return
	end

	touch(name)
	unitOf[name] = unit or "units"

	totalTime[name] += value
	callCount[name] += 1
	if value > maxTime[name] then
		maxTime[name] = value
	end
end

--[[
	One bucket, for code that wants to read a measurement rather than print it -
	the benchmark harness builds its comparison table out of these.

	Times come back in milliseconds so the caller never has to know which of the
	two storage conventions a bucket uses.
]]
function Profiler.get(name)
	local total = totalTime[name]
	if total == nil then
		return nil
	end

	local calls = callCount[name]
	local scale = if unitOf[name] then 1 else 1000

	return {
		name = name,
		calls = calls,
		unit = unitOf[name] or "ms",
		total = total * scale,
		mean = if calls > 0 then (total * scale) / calls else 0,
		max = maxTime[name] * scale,
	}
end

--[[
	Sorted snapshot. Sorted by total time so the expensive things are first, and
	pure counters (zero time) fall to the bottom.
]]
function Profiler.report()
	local timed = {}
	local sampled = {}
	local counted = {}

	for name, total in pairs(totalTime) do
		local calls = callCount[name]
		local unit = unitOf[name]

		if unit then
			table.insert(sampled, {
				name = name,
				calls = calls,
				unit = unit,
				total = total,
				mean = if calls > 0 then total / calls else 0,
				max = maxTime[name],
			})
		elseif total > 0 then
			table.insert(timed, {
				name = name,
				calls = calls,
				totalMs = total * 1000,
				meanMs = if calls > 0 then (total * 1000) / calls else 0,
				maxMs = maxTime[name] * 1000,
			})
		else
			table.insert(counted, { name = name, calls = calls })
		end
	end

	table.sort(timed, function(a, b)
		if a.totalMs ~= b.totalMs then
			return a.totalMs > b.totalMs
		end
		return a.name < b.name
	end)
	table.sort(sampled, function(a, b)
		return a.name < b.name
	end)
	table.sort(counted, function(a, b)
		if a.calls ~= b.calls then
			return a.calls > b.calls
		end
		return a.name < b.name
	end)

	return {
		enabled = Profiler.Enabled,
		windowSeconds = os.clock() - startedAt,
		timed = timed,
		sampled = sampled,
		counted = counted,

		-- Kept so existing readers that just want "the expensive things, first"
		-- keep working unchanged.
		rows = timed,
	}
end

--[[
	Human-readable dump, for a chat command or the output window.
]]
function Profiler.format()
	local report = Profiler.report()

	if not report.enabled then
		return "[Profiler] disabled"
	end

	local lines = {
		string.format("[Profiler] %.1fs window", report.windowSeconds),
	}

	if #report.timed > 0 then
		table.insert(lines, string.format(
			"%-34s %9s %10s %9s %9s", "timed bucket", "calls", "total ms", "mean ms", "max ms"
		))
		for _, row in ipairs(report.timed) do
			table.insert(lines, string.format(
				"%-34s %9d %10.2f %9.3f %9.3f",
				row.name, row.calls, row.totalMs, row.meanMs, row.maxMs
			))
		end
	end

	if #report.sampled > 0 then
		table.insert(lines, "")
		table.insert(lines, string.format(
			"%-34s %9s %10s %9s %9s", "sampled bucket", "count", "mean", "max", "unit"
		))
		for _, row in ipairs(report.sampled) do
			table.insert(lines, string.format(
				"%-34s %9d %10.2f %9.2f %9s",
				row.name, row.calls, row.mean, row.max, row.unit
			))
		end
	end

	if #report.counted > 0 then
		table.insert(lines, "")
		table.insert(lines, string.format("%-34s %9s", "counter", "events"))
		for _, row in ipairs(report.counted) do
			table.insert(lines, string.format("%-34s %9d", row.name, row.calls))
		end
	end

	return table.concat(lines, "\n")
end

return Profiler
