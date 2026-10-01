--[[
	BenchClient

	The client half of the terrain benchmark. Inert unless the server asks for a
	measurement window, and it only ever reports numbers - it never changes
	anything about how the game behaves.

	It exists because the numbers that decide whether a view distance is
	playable simply are not visible from the server. The server can see how long
	a chunk took to build and how many parts it is holding; it cannot see the
	frame the player actually got, how much of the world was replicated down to
	them, or how much memory their machine is spending to draw it. Benchmarking
	render distance from the server alone would measure the half of the problem
	that is already known to be cheap.

	PROTOCOL  (server drives, client answers)
	  server -> "begin"          start a window, clear accumulators
	  server -> "end", label     close the window and report it
	  client -> "report", label, data

	FRAME TIMES
	  Sampled on RenderStepped, which is the frame the player sees. Heartbeat
	  would miss render-bound stalls, which is exactly the failure mode a wider
	  view distance is expected to cause.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

-- Timed rather than an open-ended wait: the remote is created by the server's
-- TerrainBench, and a place that has stripped the debug tooling out should
-- leave this script quietly inert rather than parked on an infinite yield.
local BenchTelemetry = Remotes.wait("BenchTelemetry", 30)

local player = Players.LocalPlayer

-- Ring of frame durations, in seconds. Capped so a benchmark left running by
-- accident cannot grow without bound; 20k frames is over five minutes at 60fps.
local MAX_FRAMES = 20000

local frames = table.create(2048)
local frameCount = 0
local recording = false
local windowStart = 0
local connection = nil

-- Anything past this is a stutter a player would notice rather than frame-time
-- noise. 33ms is a dropped frame at 60fps; 100ms is a visible hitch.
local HITCH_MS = 33
local STALL_MS = 100

--[[
	What actually made it down to this client, broken down by class.

	The total on its own is misleading. The first sweep reported a dead-flat
	7.16 client instances per server part at every view distance, which is not a
	streaming effect - it is a fixed number of CHILDREN riding on every block.
	Six face Textures on a cube would produce exactly that, and would mean six
	sevenths of the client's instance load is decoration hanging off the parts
	rather than the parts themselves.

	So the census reports the breakdown. "How many Parts" and "how many
	instances" are different questions with different fixes, and the total
	answers neither.
]]
local function terrainCensus()
	local census = {
		total = 0,
		parts = 0,
		textures = 0,
		decals = 0,
		surfaceAppearances = 0,
		folders = 0,
		models = 0,
		other = 0,
	}

	local root = workspace:FindFirstChild("GeneratedTerrain")
	if not root then
		return census
	end

	local descendants = root:GetDescendants()
	census.total = #descendants

	for _, instance in ipairs(descendants) do
		if instance:IsA("BasePart") then
			census.parts += 1
		elseif instance:IsA("Texture") then
			census.textures += 1
		elseif instance:IsA("Decal") then
			census.decals += 1
		elseif instance:IsA("SurfaceAppearance") then
			census.surfaceAppearances += 1
		elseif instance:IsA("Folder") then
			census.folders += 1
		elseif instance:IsA("Model") then
			census.models += 1
		else
			census.other += 1
		end
	end

	return census
end

local function readMemory()
	local total = 0
	local ok, value = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	if ok and type(value) == "number" then
		total = value
	end
	return total
end

local function readReceiveKbps()
	local ok, value = pcall(function()
		return Stats.DataReceiveKbps
	end)
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

local function startWindow()
	table.clear(frames)
	frameCount = 0
	windowStart = os.clock()
	recording = true

	if not connection then
		connection = RunService.RenderStepped:Connect(function(dt)
			if not recording or frameCount >= MAX_FRAMES then
				return
			end
			frameCount += 1
			frames[frameCount] = dt
		end)
	end
end

--[[
	Turns the raw frame list into the handful of numbers worth comparing between
	runs.

	Mean FPS on its own hides the thing being looked for: a view distance that
	averages 55fps but drops to 12 whenever a chunk lands is worse to play than
	one that sits flat at 45. So the lows are reported as percentiles of the
	SLOWEST frames, which is where that shows up.
]]
local function summarise()
	recording = false

	local census = terrainCensus()

	local summary = {
		frames = frameCount,
		windowSeconds = os.clock() - windowStart,
		memoryMb = readMemory(),
		receiveKbps = readReceiveKbps(),
		terrainInstances = census.total,
		census = census,
		fpsMean = 0,
		frameMeanMs = 0,
		frameP50Ms = 0,
		frameP99Ms = 0,
		frameMaxMs = 0,
		fpsLow1 = 0,
		fpsLow01 = 0,
		hitches = 0,
		stalls = 0,
	}

	if frameCount == 0 then
		return summary
	end

	local sorted = table.create(frameCount)
	local total = 0

	for i = 1, frameCount do
		local dt = frames[i]
		total += dt
		sorted[i] = dt
		if dt * 1000 >= STALL_MS then
			summary.stalls += 1
		elseif dt * 1000 >= HITCH_MS then
			summary.hitches += 1
		end
	end

	table.sort(sorted)

	local function percentile(fraction)
		local index = math.clamp(math.ceil(frameCount * fraction), 1, frameCount)
		return sorted[index] * 1000
	end

	-- The mean of the worst n% of frames, expressed as fps. This is the usual
	-- "1% low" - an average over the tail, not a single sample from it, so one
	-- freak frame cannot define the number.
	local function lowFps(fraction)
		local take = math.max(1, math.floor(frameCount * fraction))
		local sum = 0
		for i = frameCount - take + 1, frameCount do
			sum += sorted[i]
		end
		local mean = sum / take
		return if mean > 0 then 1 / mean else 0
	end

	local meanFrame = total / frameCount

	summary.fpsMean = if meanFrame > 0 then 1 / meanFrame else 0
	summary.frameMeanMs = meanFrame * 1000
	summary.frameP50Ms = percentile(0.50)
	summary.frameP99Ms = percentile(0.99)
	summary.frameMaxMs = sorted[frameCount] * 1000
	summary.fpsLow1 = lowFps(0.01)
	summary.fpsLow01 = lowFps(0.001)

	return summary
end

if BenchTelemetry then
	BenchTelemetry.OnClientEvent:Connect(function(command, label)
		if command == "begin" then
			startWindow()
		elseif command == "end" then
			local summary = summarise()
			summary.player = player.Name
			BenchTelemetry:FireServer("report", label, summary)
		end
	end)
else
	warn("[BenchClient] no BenchTelemetry remote; terrain benchmarking is unavailable.")
end
