--[[
	TerrainBench

	Measures what a view distance actually costs, at several view distances, in
	one server session.

	WHY IT EXISTS

	The obvious way to answer "can we afford a wider render distance?" is to
	change ViewDistanceChunks, play for a bit, and see whether it feels bad.
	That answer is unreliable in both directions: it depends on which machine is
	running the client, which part of the world was walked into, and whether the
	caches happened to be warm. It also cannot say WHICH cost grew - generation,
	replication, instance count or draw time - which is the only part that tells
	you what to fix.

	So this sweeps the dial instead, holding everything else still. One server,
	one seed, one client, one route, four view distances. Anything that differs
	between the rows was caused by the dial.

	WHAT EACH RUN MEASURES, AND WHY THOSE THREE PHASES

	  COLD   Every chunk destroyed and every pure-function cache dropped, then
	         timed until the world is whole again. This is what a joining player
	         experiences, and it is the number that grows quadratically with the
	         radius while the generator's throughput stays fixed.

	  REST   Standing still, nothing streaming. Isolates the cost of merely
	         HOLDING the world: resident parts, memory on both ends, idle
	         replication, and the frame rate the player gets for it.

	  TRAVEL The character is flown along a fixed route at a fixed speed, so
	         load and unload churn is identical between runs. This is where
	         streaming stalls show up, and it is the phase a hand-played test
	         can never reproduce twice.

	The client half lives in StarterPlayerScripts.BenchClient; the server cannot
	see frame times, client memory, or what was actually replicated.

	USAGE
	  /bbbench              full sweep with the defaults
	  /bbbench 2 3          only those view distances
	  /bbbench quick        shorter windows, for a smoke test

	Everything is restored afterwards: view distance, the character's position,
	and whether the profiler was running.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Stats = game:GetService("Stats")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))

local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))

local BenchTelemetry = Remotes.ensure("BenchTelemetry", "RemoteEvent")

local TerrainBench = {}

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local DEFAULTS = {
	viewDistances = { 2, 3, 4, 5 },

	-- Long enough that one slow chunk cannot dominate the average, short enough
	-- that a full sweep is a coffee rather than a lunch.
	restSeconds = 12,
	travelSeconds = 24,

	-- Comfortably above walk speed, so the route crosses enough chunk borders
	-- to exercise streaming instead of ambling around inside one chunk.
	travelStudsPerSecond = 32,

	-- A 5-chunk radius from cold is the slowest thing here by a wide margin.
	-- If this trips, that IS the finding.
	loadTimeoutSeconds = 240,

	settleSeconds = 2,
}

local QUICK = {
	restSeconds = 5,
	travelSeconds = 8,
	loadTimeoutSeconds = 120,
	settleSeconds = 1,
}

-- Frames slower than these are stutters rather than noise. Matched to
-- BenchClient so both halves describe the same thing.
local HITCH_MS = 33
local STALL_MS = 100

local isRunning = false

-- label -> { player -> summary }, filled in by the client's reply.
local clientReports = {}

BenchTelemetry.OnServerEvent:Connect(function(player, command, label, data)
	if command ~= "report" or type(label) ~= "string" or type(data) ~= "table" then
		return
	end

	local bucket = clientReports[label]
	if bucket then
		bucket[player] = data
	end
end)

-- ---------------------------------------------------------------------------
-- Server-side frame collector
-- ---------------------------------------------------------------------------

--[[
	Heartbeat deltas, which on the server are the frame. Kept as a running
	summary rather than an array: the server is the thing under test, and
	appending to a table sixty times a second for four minutes is not nothing.
]]
local function newFrameCollector()
	local collector = {
		frames = 0,
		totalSeconds = 0,
		maxSeconds = 0,
		hitches = 0,
		stalls = 0,
		connection = nil,
	}

	function collector:start()
		self.frames = 0
		self.totalSeconds = 0
		self.maxSeconds = 0
		self.hitches = 0
		self.stalls = 0

		self.connection = RunService.Heartbeat:Connect(function(dt)
			self.frames += 1
			self.totalSeconds += dt
			if dt > self.maxSeconds then
				self.maxSeconds = dt
			end

			local ms = dt * 1000
			if ms >= STALL_MS then
				self.stalls += 1
			elseif ms >= HITCH_MS then
				self.hitches += 1
			end
		end)
	end

	function collector:stop()
		if self.connection then
			self.connection:Disconnect()
			self.connection = nil
		end

		local mean = if self.frames > 0 then self.totalSeconds / self.frames else 0
		return {
			frames = self.frames,
			meanMs = mean * 1000,
			maxMs = self.maxSeconds * 1000,
			fps = if mean > 0 then 1 / mean else 0,
			hitches = self.hitches,
			stalls = self.stalls,
		}
	end

	return collector
end

-- ---------------------------------------------------------------------------
-- Slow samplers
-- ---------------------------------------------------------------------------

local function readNumber(getter)
	local ok, value = pcall(getter)
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

local function serverMemoryMb()
	return readNumber(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
end

local function instanceMemoryMb()
	return readNumber(function()
		return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Instances)
	end)
end

local function sendKbps()
	return readNumber(function()
		return Stats.DataSendKbps
	end)
end

local SLOW_FIELDS = {
	"serverMemoryMb", "instanceMemoryMb", "sendKbps",
	"renderedParts", "pooledParts", "loadedChunks", "queuedChunks", "cachedColumns",
	"visibleBlocks", "blocksPerPart", "generateBudgetMs",
}

--[[
	Averages the things that only mean something over a window - memory,
	outgoing bandwidth, resident part count - and keeps their peaks alongside,
	because a mean hides the moment that actually hurt.
]]
local function newSlowSampler()
	local sampler = { samples = 0, running = false }

	local function reset()
		for _, field in ipairs(SLOW_FIELDS) do
			sampler[field] = 0
			sampler[field .. "Peak"] = 0
		end
		sampler.samples = 0
	end

	local function take()
		local stats = TerrainManager:GetStats()
		local values = {
			serverMemoryMb = serverMemoryMb(),
			instanceMemoryMb = instanceMemoryMb(),
			sendKbps = sendKbps(),
			renderedParts = stats.renderedParts,
			pooledParts = stats.pooledParts,
			loadedChunks = stats.loadedChunks,
			queuedChunks = stats.queuedChunks,
			cachedColumns = stats.cachedColumns,
			visibleBlocks = stats.visibleBlocks,
			blocksPerPart = stats.blocksPerPart,
			generateBudgetMs = stats.generateBudgetMs,
		}

		sampler.samples += 1
		for _, field in ipairs(SLOW_FIELDS) do
			local value = values[field]
			sampler[field] += value
			if value > sampler[field .. "Peak"] then
				sampler[field .. "Peak"] = value
			end
		end
	end

	function sampler:start()
		reset()
		self.running = true
		task.spawn(function()
			while self.running do
				take()
				task.wait(0.5)
			end
		end)
	end

	function sampler:stop()
		self.running = false

		local result = { samples = self.samples }
		local divisor = math.max(1, self.samples)
		for _, field in ipairs(SLOW_FIELDS) do
			result[field] = self[field] / divisor
			result[field .. "Peak"] = self[field .. "Peak"]
		end
		return result
	end

	return sampler
end

-- ---------------------------------------------------------------------------
-- Profiler snapshots
-- ---------------------------------------------------------------------------

local SAMPLED_BUCKETS = {
	"Terrain.chunkCpuMs",
	"Terrain.chunkQueueWaitMs",
	"Terrain.chunkLatencyMs",
	"Terrain.chunkUnloadMs",
	"Terrain.chunkUnloadParts",
	"Terrain.queueDepth",
	"Terrain.activeGenerations",
	"Terrain.genBudgetMs",
	"Terrain.serverFrameMs",
	"Terrain.gen.1columns",
	"Terrain.gen.2structures",
	"Terrain.gen.3edits",
	"Terrain.gen.4render",
	"Terrain.gen.5models",
	"Terrain.gen.6borders",
}

local COUNTED_BUCKETS = {
	"Terrain.chunkGenerated",
	"Terrain.chunkUnloaded",
	"Terrain.partPlaced",
	"Terrain.partCloned",
	"Terrain.partReused",
	"Terrain.partDestroyed",
	"Terrain.partTrimmed",
	"Terrain.columnSampled",
	"Terrain.columnPromoted",
	"Terrain.columnCacheRotated",
	"Terrain.columnSlowPath",
	"Terrain.layerMeshed",
	"Terrain.partReshaped",
}

local function snapshotProfiler()
	local snapshot = { sampled = {}, counted = {} }

	for _, name in ipairs(SAMPLED_BUCKETS) do
		local row = Profiler.get(name)
		if row then
			snapshot.sampled[name] = { n = row.calls, mean = row.mean, max = row.max }
		end
	end

	for _, name in ipairs(COUNTED_BUCKETS) do
		local row = Profiler.get(name)
		if row then
			snapshot.counted[name] = row.calls
		end
	end

	return snapshot
end

-- ---------------------------------------------------------------------------
-- Client coordination
-- ---------------------------------------------------------------------------

local function clientsBegin()
	BenchTelemetry:FireAllClients("begin")
end

--[[
	Closes the client window and waits for the replies. Bounded: a client that
	left mid-run must not stall the sweep.
]]
local function clientsEnd(label)
	clientReports[label] = {}
	BenchTelemetry:FireAllClients("end", label)

	local expected = #Players:GetPlayers()
	local deadline = os.clock() + 3

	while os.clock() < deadline do
		local received = 0
		for _ in pairs(clientReports[label]) do
			received += 1
		end
		if expected > 0 and received >= expected then
			break
		end
		task.wait(0.1)
	end

	local reports = clientReports[label]
	clientReports[label] = nil

	-- One client is the normal case. If several are connected their frame times
	-- are not comparable to each other, so the first is reported and the count
	-- is noted, rather than averaging them into a meaningless middle.
	local first, count = nil, 0
	for _, summary in pairs(reports) do
		count += 1
		if not first then
			first = summary
		end
	end

	return first, count
end

-- ---------------------------------------------------------------------------
-- The route
-- ---------------------------------------------------------------------------

--[[
	Flies the character along a fixed diagonal at a fixed speed, hugging the
	generated surface.

	Anchored and driven by CFrame rather than walked: a walked route depends on
	terrain shape, snags on cliffs, and is never the same route twice. The
	diagonal is deliberate - it crosses chunk borders on both axes, so the
	unload path is exercised as hard as the load path.

	Height comes from TerrainManager:GetSurfaceY, which answers from the
	generator for chunks that have not streamed in yet, so the route is known
	before the terrain exists and does not depend on load order.
]]
local function runTravel(player, seconds, studsPerSecond)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, "no character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local restoreAnchored = hrp.Anchored
	local restoreCFrame = hrp.CFrame
	local restoreAutoRotate = if humanoid then humanoid.AutoRotate else nil

	local origin = hrp.Position
	local direction = Vector3.new(1, 0, 1).Unit

	hrp.Anchored = true
	if humanoid then
		humanoid.AutoRotate = false
	end

	local elapsed = 0
	while elapsed < seconds do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt

		if not hrp.Parent then
			break
		end

		local x = origin.X + direction.X * studsPerSecond * elapsed
		local z = origin.Z + direction.Z * studsPerSecond * elapsed

		local surfaceY = TerrainManager:GetSurfaceY(x, z)
		if not surfaceY then
			-- Ran out of world. Stop rather than fly into the void; the window
			-- is reported as shortened rather than silently wrong.
			break
		end

		hrp.CFrame = CFrame.new(x, surfaceY + 6, z)
	end

	if hrp.Parent then
		hrp.CFrame = restoreCFrame
		hrp.Anchored = restoreAnchored
	end
	if humanoid and restoreAutoRotate ~= nil then
		humanoid.AutoRotate = restoreAutoRotate
	end

	return true
end

-- ---------------------------------------------------------------------------
-- Phases
-- ---------------------------------------------------------------------------

--[[
	Blocks until nothing is queued and nothing is generating, and has stayed that
	way briefly - one quiet frame is not the same as done, because a chunk
	finishing can enqueue border work.
]]
local function waitForQuiet(timeoutSeconds)
	local startedAt = os.clock()
	local deadline = startedAt + timeoutSeconds
	local quietSince = nil

	while os.clock() < deadline do
		local stats = TerrainManager:GetStats()

		if stats.queuedChunks == 0 and not stats.generating then
			if not quietSince then
				quietSince = os.clock()
			end
			if os.clock() - quietSince >= 0.5 then
				return true, quietSince - startedAt
			end
		else
			quietSince = nil
		end

		task.wait(0.1)
	end

	return false, os.clock() - startedAt
end

--[[
	Runs one measurement window: client recording, server frame collection, slow
	sampling and a fresh profiler window, all opened and closed together so that
	every number in a row describes the same slice of time.
]]
local function measure(label, body)
	Profiler.reset()

	local frameCollector = newFrameCollector()
	local sampler = newSlowSampler()

	clientsBegin()
	frameCollector:start()
	sampler:start()

	local result = body()

	local server = frameCollector:stop()
	local slow = sampler:stop()
	local profile = snapshotProfiler()
	local client, clientCount = clientsEnd(label)

	return {
		label = label,
		body = result,
		server = server,
		slow = slow,
		profile = profile,
		client = client,
		clientCount = clientCount,
	}
end

-- ---------------------------------------------------------------------------
-- Reporting
-- ---------------------------------------------------------------------------

local function fmt(value, decimals)
	if type(value) ~= "number" then
		return "-"
	end
	return string.format("%." .. tostring(decimals or 1) .. "f", value)
end

local function printPhase(phase)
	local server = phase.server
	local slow = phase.slow
	local client = phase.client

	print(string.format("  -- %s --", string.upper(phase.label)))
	print(string.format(
		"     server frame   mean %sms  max %sms  hitches %d  stalls %d",
		fmt(server.meanMs, 2), fmt(server.maxMs, 1), server.hitches, server.stalls
	))

	if client then
		print(string.format(
			"     client frame   mean %sms (%s fps)  p99 %sms  max %sms",
			fmt(client.frameMeanMs, 2), fmt(client.fpsMean, 1),
			fmt(client.frameP99Ms, 1), fmt(client.frameMaxMs, 1)
		))
		print(string.format(
			"     client lows    1pct low %s fps  0.1pct low %s fps  hitches %d  stalls %d",
			fmt(client.fpsLow1, 1), fmt(client.fpsLow01, 1),
			client.hitches or 0, client.stalls or 0
		))
		print(string.format(
			"     client load    %d terrain instances  %s MB  %s Kbps in",
			client.terrainInstances or 0, fmt(client.memoryMb, 1), fmt(client.receiveKbps, 1)
		))

		-- The split matters more than the total: parts and the decoration hanging
		-- off them are different costs with different fixes.
		local census = client.census
		if census then
			print(string.format(
				"     client census  %d parts  %d textures  %d decals  %d models  %d folders  %d other",
				census.parts or 0, census.textures or 0, census.decals or 0,
				census.models or 0, census.folders or 0, census.other or 0
			))
			if (census.parts or 0) > 0 then
				print(string.format(
					"                    %.2f instances per part",
					(census.total or 0) / census.parts
				))
			end
		end
	else
		print("     client frame   (no client reported)")
	end

	print(string.format(
		"     server load    %s parts resident (peak %d)  %s pooled  %s chunks",
		fmt(slow.renderedParts, 0), slow.renderedPartsPeak,
		fmt(slow.pooledParts, 0), fmt(slow.loadedChunks, 1)
	))
	print(string.format(
		"     meshing        %s blocks drawn by %s parts = %sx merge  |  budget %s ms/frame",
		fmt(slow.visibleBlocks, 0), fmt(slow.renderedParts, 0),
		fmt(slow.blocksPerPart, 2), fmt(slow.generateBudgetMs, 2)
	))
	print(string.format(
		"     server memory  %s MB total  %s MB instances  %s Kbps out (peak %s)",
		fmt(slow.serverMemoryMb, 1), fmt(slow.instanceMemoryMb, 1),
		fmt(slow.sendKbps, 1), fmt(slow.sendKbpsPeak, 1)
	))

	local sampled = phase.profile.sampled
	local counted = phase.profile.counted

	local function line(name, unit)
		local row = sampled[name]
		if row and row.n > 0 then
			print(string.format(
				"     %-26s n=%-5d mean %s %s   max %s %s",
				name, row.n, fmt(row.mean, 2), unit, fmt(row.max, 2), unit
			))
		end
	end

	line("Terrain.chunkCpuMs", "ms")
	line("Terrain.chunkQueueWaitMs", "ms")
	line("Terrain.chunkLatencyMs", "ms")
	line("Terrain.chunkUnloadMs", "ms")
	line("Terrain.queueDepth", "chunks")
	line("Terrain.activeGenerations", "chunks")
	line("Terrain.genBudgetMs", "ms")
	line("Terrain.serverFrameMs", "ms")

	print(string.format(
		"     churn          %d gen  %d unloaded  %d placed  %d cloned  %d reused  %d trimmed",
		counted["Terrain.chunkGenerated"] or 0,
		counted["Terrain.chunkUnloaded"] or 0,
		counted["Terrain.partPlaced"] or 0,
		counted["Terrain.partCloned"] or 0,
		counted["Terrain.partReused"] or 0,
		counted["Terrain.partTrimmed"] or 0
	))

	-- Rotations climbing while the player stands still means ColumnCacheLimit is
	-- too small for this view distance, and the cache is copying itself instead
	-- of saving work.
	print(string.format(
		"     column cache   %d sampled  %d promoted  %d rotations",
		counted["Terrain.columnSampled"] or 0,
		counted["Terrain.columnPromoted"] or 0,
		counted["Terrain.columnCacheRotated"] or 0
	))
end

local function printComparison(rows)
	print("")
	print("======== view distance comparison ========")
	print(string.format(
		"%-4s %-7s %-8s %-7s %-8s %-8s %-8s %-8s %-9s %-8s %-8s %-7s",
		"VD", "chunks", "parts", "merge", "srvMB", "cliMB", "cliInst", "outKbps",
		"cold(s)", "fps", "fps1pct", "stalls"
	))

	for _, row in ipairs(rows) do
		local rest = row.rest
		local travel = row.travel
		local client = rest.client
		local travelStalls = travel.server.stalls
		if travel.client then
			travelStalls += travel.client.stalls or 0
		end

		print(string.format(
			"%-4d %-7s %-8s %-7s %-8s %-8s %-8s %-8s %-9s %-8s %-8s %-7d",
			row.viewDistance,
			fmt(rest.slow.loadedChunks, 0),
			fmt(rest.slow.renderedParts, 0),
			fmt(rest.slow.blocksPerPart, 2),
			fmt(rest.slow.serverMemoryMb, 1),
			if client then fmt(client.memoryMb, 1) else "-",
			if client then tostring(client.terrainInstances or 0) else "-",
			fmt(rest.slow.sendKbps, 1),
			fmt(row.cold.body.seconds, 1),
			if client then fmt(client.fpsMean, 1) else "-",
			if client then fmt(client.fpsLow1, 1) else "-",
			travelStalls
		))
	end

	print("")
	print("  merge    blocks drawn per Part; 1.00 means merging achieved nothing")
	print("  cold(s)  seconds to rebuild the whole view from nothing")
	print("  fps      the CLIENT, standing still, with the world already loaded")
	print("  stalls   frames over 100ms while travelling, server and client added")
	print("==========================================")
end

-- ---------------------------------------------------------------------------
-- The sweep
-- ---------------------------------------------------------------------------

local function runOne(viewDistance, settings, player)
	print(string.format("[bbbench] view distance %d ...", viewDistance))

	TerrainManager:SetViewDistance(viewDistance)

	-- Let any chunk still building from the previous row finish, so the flush
	-- below cannot skip it and leave one stale chunk standing.
	waitForQuiet(30)

	-- Torn down OUTSIDE the measurement window: destroying ten thousand Parts
	-- is a real spike, but it is this harness's spike, not something a joining
	-- player would ever pay. Pools go too - a warm pool would make the second
	-- row of a sweep look faster than the first for reasons that have nothing
	-- to do with view distance.
	TerrainManager:_FlushAll(true)
	task.wait(settings.settleSeconds)

	-- COLD. The window opens on an empty world and closes when it is whole.
	local cold = measure("cold", function()
		TerrainManager:_ReseatPlayers()
		local completed, seconds = waitForQuiet(settings.loadTimeoutSeconds)
		return { completed = completed, seconds = seconds }
	end)

	if not cold.body.completed then
		warn(string.format(
			"[bbbench] view distance %d did not finish loading within %ds. That is "
				.. "itself a result, but the rest of this row describes an "
				.. "incomplete world.",
			viewDistance, settings.loadTimeoutSeconds
		))
	end

	task.wait(settings.settleSeconds)

	local rest = measure("rest", function()
		task.wait(settings.restSeconds)
		return {}
	end)

	local travel = measure("travel", function()
		local ok, reason = runTravel(player, settings.travelSeconds, settings.travelStudsPerSecond)
		return { ok = ok, reason = reason }
	end)

	print(string.format("[bbbench] view distance %d:", viewDistance))
	printPhase(cold)
	printPhase(rest)
	printPhase(travel)

	return {
		viewDistance = viewDistance,
		cold = cold,
		rest = rest,
		travel = travel,
	}
end

--[[
	Runs the sweep. Refuses to start a second one, because two overlapping
	sweeps would mostly be measuring each other.
]]
function TerrainBench.run(options)
	if isRunning then
		warn("[bbbench] already running")
		return
	end

	local player = Players:GetPlayers()[1]
	if not player then
		warn("[bbbench] needs a player in the server: the streaming anchor, the "
			.. "frame times and the replication load all belong to a client.")
		return
	end

	options = options or {}

	local settings = {}
	for key, value in pairs(DEFAULTS) do
		settings[key] = value
	end
	if options.quick then
		for key, value in pairs(QUICK) do
			settings[key] = value
		end
	end

	local distances = options.viewDistances or settings.viewDistances

	isRunning = true

	local restoreViewDistance = TerrainManager:GetViewDistance()
	local restoreProfiler = Profiler.Enabled
	Profiler.setEnabled(true)

	print("")
	print("======== bbbench: terrain view distance sweep ========")
	print(string.format(
		"  distances %s | rest %ds | travel %ds at %d studs/s | seed %s",
		table.concat(distances, ", "), settings.restSeconds, settings.travelSeconds,
		settings.travelStudsPerSecond, tostring(TerrainManager:GetStats().seed)
	))
	print(string.format(
		"  chunk %d blocks at %d studs | world floor %d | StreamingEnabled %s",
		TerrainConfig.ChunkSize, TerrainConfig.StudSize, TerrainConfig.WorldFloorY,
		tostring(workspace.StreamingEnabled)
	))
	print("")

	local rows = {}

	local ok, err = pcall(function()
		for _, distance in ipairs(distances) do
			table.insert(rows, runOne(distance, settings, player))
		end
	end)

	if not ok then
		warn("[bbbench] aborted:", err)
	end

	if #rows > 0 then
		printComparison(rows)
	end

	TerrainManager:SetViewDistance(restoreViewDistance)
	Profiler.setEnabled(restoreProfiler)
	isRunning = false

	print(string.format("[bbbench] done; view distance restored to %d", restoreViewDistance))

	return rows
end

function TerrainBench.isRunning()
	return isRunning
end

return TerrainBench
