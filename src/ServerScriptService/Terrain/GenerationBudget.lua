--[[
	GenerationBudget

	The shared, adaptive per-frame allowance every chunk in flight draws on,
	the per-chunk slice accounting, and urgency (ground a player is standing
	on goes first). Part of TerrainManager; see TerrainManager for the map of
	terrain modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local ChunkData = require(script.Parent:WaitForChild("ChunkData"))
local ChunkQueue = require(script.Parent:WaitForChild("ChunkQueue"))

local GenerationBudget = {}

local URGENT_PRIORITY = ChunkQueue.URGENT_PRIORITY
local queueBuckets = ChunkQueue.buckets
local queuedPriority = ChunkQueue.priorityOf
local usageCounts = ChunkData.usage
local playerChunk = ChunkData.playerChunk

--[[
	THE FRAME BUDGET, AND WHY IT IS SHARED AND ADAPTIVE

	The first benchmark sweep measured the cost of the old arrangement exactly:
	at view distance 5 a chunk took ~58ms of CPU but waited ~23 SECONDS in the
	queue, with 120 chunks backed up behind it. The server was not busy. It was
	asleep.

	Three things caused that, and all three are fixed here.

	  1. The budget was per chunk. A chunk spent 4ms, called task.wait(), and
	     slept until the next frame - so the world filled at 4ms of work per
	     frame regardless of how much headroom the frame actually had.

	  2. The budget was fixed. 4ms is a reasonable guess for a loaded server and
	     a terrible one for an idle server holding a player at a black horizon.
	     currentBudget is now a control loop: it climbs while frames stay
	     healthy and backs off the moment they stretch, so it finds the real
	     headroom instead of assuming it.

	  3. Nothing could use the rest of a frame. When a chunk finished mid-frame
	     the remaining budget was simply lost, because the next chunk was only
	     ever started from the next Heartbeat. The pump now refills inside the
	     same frame.

	The budget is charged globally rather than per chunk, so concurrency cannot
	multiply the server's cost: two chunks in flight share one frame's
	allowance, they do not each get one.
]]

-- Bumped once per Heartbeat. Used to notice that a frame boundary has passed
-- without depending on which connection ran first, which task.wait's
-- resumption order does not guarantee.
local frameTick = 0
local budgetTick = -1
local budgetUsed = 0

local currentBudget = TerrainConfig.GenerateBudgetSeconds
local smoothedFrame = 1 / 60

--[[
	This frame's allowance: currentBudget, or the most the config allows while a
	player is missing ground right around them - a chunk queued or building at
	priority URGENT_PRIORITY or less, which is the 3x3 they are standing in the
	middle of. Those are the chunks a player is held still waiting for after a
	teleport or respawn (StreamingIntegrityMode pauses them), so they go first
	and fast; the rest of the view fills at the normal pace.
]]
local frameAllowance = currentBudget
local urgentGenerations = 0 -- in-flight chunks queued at URGENT_PRIORITY or less

local function chargeBudget(seconds)
	if budgetTick ~= frameTick then
		budgetTick = frameTick
		budgetUsed = 0
	end
	budgetUsed += seconds
end

local function budgetRemaining()
	if budgetTick ~= frameTick then
		return frameAllowance
	end
	return frameAllowance - budgetUsed
end

-- Whether any chunk at URGENT_PRIORITY or less is building, or queued and
-- still wanted. Only the first few buckets are looked at, and they are small.
local function hasUrgentWork(queuedOnly)
	if urgentGenerations > 0 and not queuedOnly then
		return true
	end
	for priority = 0, URGENT_PRIORITY do
		local bucket = queueBuckets[priority]
		if bucket then
			for i = #bucket, 1, -1 do
				local item = bucket[i]
				if queuedPriority[item.key] == item.priority and (usageCounts[item.key] or 0) > 0 then
					return true
				end
			end
		end
	end
	return false
end

--[[
	One chunk's slice accounting. Per chunk rather than global because chunks can
	now overlap, and a single shared accumulator would credit one chunk with
	another's work and report both wrongly.
]]
local function newGenBudget()
	return { cpu = 0, sliceStart = os.clock() }
end

--[[
	CPU seconds this chunk has spent: the slices already banked, plus however far
	into the current slice we are.
]]
local function chunkCpuSpent(ctx)
	return ctx.cpu + (os.clock() - ctx.sliceStart)
end

--[[
	Yields when THIS FRAME's shared allowance is gone - not when this chunk has
	had its turn.

	Terrain.chunkCpuMs (work) and Terrain.chunkLatencyMs (wall clock) stay
	separate buckets, so the gap between them remains visible rather than
	inferred. Closing that gap is what this whole mechanism is for.
]]
local function yieldIfOverBudget(ctx)
	local now = os.clock()
	local spent = now - ctx.sliceStart

	ctx.cpu += spent
	chargeBudget(spent)
	-- The longest stretch generation ran without a chance to yield. Its max is
	-- the worst frame hitch terrain can cause, whatever the budget says.
	Profiler.sample("Terrain.sliceMs", spent * 1000, "ms")

	--[[
		Ground a player is standing on or beside goes first. Every chunk in
		flight draws on the same frame allowance, and whichever coroutine wakes
		first spends it - so a distant chunk could take the whole frame while the
		one under a player's feet waited its turn. A distant chunk stands aside
		until no urgent one is building.

		Urgency is re-read here, not fixed when the chunk was started: a chunk
		begun far ahead of a fast player is under them a second later.
	]]
	local job = ctx.job
	if job and not job.urgent then
		for _, info in pairs(playerChunk) do
			local dx, dz = info.x - ctx.cx, info.z - ctx.cz
			if dx >= -1 and dx <= 1 and dz >= -1 and dz <= 1 then
				job.urgent = true
				urgentGenerations += 1
				break
			end
		end

		if not job.urgent and urgentGenerations > 0 then
			repeat
				task.wait()
			until urgentGenerations <= 0
			ctx.sliceStart = os.clock()
			return
		end
	end

	if budgetRemaining() > 0 then
		ctx.sliceStart = now
		return
	end

	task.wait()
	ctx.sliceStart = os.clock()
end

--[[
	Moves the per-frame allowance toward whatever the server can actually afford.

	The signal is the server's own frame time, which already INCLUDES this work -
	so the loop is self-limiting. It climbs while frames stay under target and
	retreats when they stretch, which is the difference between "spend 4ms
	because that felt safe" and "spend whatever is going spare right now".

	Asymmetric on purpose: creeps up, drops fast. Overshooting costs the player a
	visible hitch, and undershooting only costs a little load time, so the two
	errors are not worth the same.
]]
local function updateGenerationBudget(dt)
	smoothedFrame += (dt - smoothedFrame) * TerrainConfig.GenerateFrameSmoothing

	local minBudget = TerrainConfig.GenerateBudgetMinSeconds
	local maxBudget = TerrainConfig.GenerateBudgetMaxSeconds

	if smoothedFrame >= TerrainConfig.GenerateFrameCeilingSeconds then
		-- Something is badly wrong with this frame. Halve rather than step.
		currentBudget *= 0.5
	elseif smoothedFrame > TerrainConfig.GenerateFrameTargetSeconds then
		currentBudget -= TerrainConfig.GenerateBudgetFallStep
	elseif ChunkQueue.count() > 0 then
		-- Only climb when there is actually work waiting. Growing the budget on
		-- an empty queue would just raise the ceiling for the next burst
		-- without anyone having measured whether the server can pay it.
		currentBudget += TerrainConfig.GenerateBudgetRiseStep
	end

	if currentBudget < minBudget then
		currentBudget = minBudget
	elseif currentBudget > maxBudget then
		currentBudget = maxBudget
	end

	frameAllowance = if hasUrgentWork() then maxBudget else currentBudget

	Profiler.sample("Terrain.genBudgetMs", frameAllowance * 1000, "ms")
	Profiler.sample("Terrain.serverFrameMs", smoothedFrame * 1000, "ms")
end

--[[
	Marks a frame boundary, first thing on each generation Heartbeat. Samples
	what generation actually spent last frame, slices and overruns included.
	serverFrameMs is the whole frame - in Studio, the client's rendering too.
]]
function GenerationBudget.beginFrame()
	if budgetTick == frameTick then
		Profiler.sample("Terrain.genFrameWorkMs", budgetUsed * 1000, "ms")
	end
	frameTick += 1
end

-- An urgent chunk (queued at URGENT_PRIORITY or less) starting or finishing.
function GenerationBudget.urgentStarted()
	urgentGenerations += 1
end

function GenerationBudget.urgentFinished()
	urgentGenerations -= 1
end

-- The adaptive allowance before any urgent boost, for stats.
function GenerationBudget.current()
	return currentBudget
end

GenerationBudget.chargeBudget = chargeBudget
GenerationBudget.budgetRemaining = budgetRemaining
GenerationBudget.hasUrgentWork = hasUrgentWork
GenerationBudget.newGenBudget = newGenBudget
GenerationBudget.chunkCpuSpent = chunkCpuSpent
GenerationBudget.yieldIfOverBudget = yieldIfOverBudget
GenerationBudget.update = updateGenerationBudget

return GenerationBudget
