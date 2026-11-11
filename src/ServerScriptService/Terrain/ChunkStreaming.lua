--[[
	ChunkStreaming

	Which chunks should exist: each player's view distance and active set,
	reference counts, the unload grace period, starting chunk builds within
	the frame budget, and the per-frame Heartbeat work. Also lifts a player
	who ends up inside solid ground. Part of TerrainManager; see
	TerrainManager for the map of terrain modules.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local ChunkData = require(script.Parent:WaitForChild("ChunkData"))
local ChunkQueue = require(script.Parent:WaitForChild("ChunkQueue"))
local GenerationBudget = require(script.Parent:WaitForChild("GenerationBudget"))
local ChunkBuilder = require(script.Parent:WaitForChild("ChunkBuilder"))
local BlockParts = require(script.Parent:WaitForChild("BlockParts"))
local EditZones = require(script.Parent:WaitForChild("EditZones"))
local FaceCulling = require(script.Parent:WaitForChild("FaceCulling"))

local ChunkStreaming = {}

local STUD_SIZE = TerrainConfig.StudSize
local CHUNK_SIZE = TerrainConfig.ChunkSize
local CHUNK_STUDS = TerrainConfig.ChunkStuds
local FLOOR_Y = TerrainConfig.WorldFloorY
local MAX_BLOCK_Y = TerrainConfig.WorldCeilingY
local URGENT_PRIORITY = ChunkQueue.URGENT_PRIORITY

local chunks = ChunkData.chunks
local generatingChunks = ChunkData.generating
local usageCounts = ChunkData.usage
local pendingUnload = ChunkData.pendingUnload
local playerChunk = ChunkData.playerChunk
local isChunkWanted = ChunkData.isWanted
local isPresentInData = ChunkData.isPresentInData
local chunkKey = TerrainGrid.chunkKey
local isChunkInBounds = TerrainGrid.isChunkInBounds
local normalizeCell = TerrainGrid.normalizeCell
local cellOf = TerrainGrid.cellOf
local getChunkCoordX = TerrainGrid.getChunkCoordX
local getChunkCoordZ = TerrainGrid.getChunkCoordZ
local enqueueChunk = ChunkQueue.enqueue
local nextWantedItem = ChunkQueue.nextWanted
local budgetRemaining = GenerationBudget.budgetRemaining
local hasUrgentWork = GenerationBudget.hasUrgentWork
local generateChunk = ChunkBuilder.generateChunk
local unloadChunk = ChunkBuilder.unloadChunk

--[[
	The DEFAULT view distance, and the bounds a player may choose within.

	Mutable rather than constant so a benchmark sweep can walk it 2 -> 5 inside
	one server session; see ChunkStreaming.setViewDistance. Players who have not
	chosen for themselves follow it.
]]
local VIEW_DISTANCE = TerrainConfig.ViewDistanceChunks
local MIN_VIEW_DISTANCE = TerrainConfig.MinViewDistanceChunks
local MAX_VIEW_DISTANCE = TerrainConfig.MaxViewDistanceChunks

--[[
	player -> their chosen view distance, absent while they are on the default.

	Per player rather than per server because it is a CLIENT cost being traded:
	the resident part count is what a machine struggles with, and one person on
	a laptop turning theirs down should not decide it for everybody else.

	The server still pays something - it generates the union of what everyone
	wants - but chunks are shared and reference counted, so two players standing
	together at different distances cost the larger of the two rather than the
	sum.
]]
local playerViewDistance = setmetatable({}, { __mode = "k" })

local function viewDistanceFor(player)
	return playerViewDistance[player] or VIEW_DISTANCE
end

-- How many chunk coroutines are in flight. Replaces a boolean: chunks may now
-- overlap, bounded by TerrainConfig.MaxConcurrentChunks and, more importantly,
-- by the shared frame budget they all draw from.
local activeGenerations = 0
local movementAccumulator = 0

local function releaseChunkUse(key, cx, cz)
	local count = math.max(0, (usageCounts[key] or 1) - 1)
	usageCounts[key] = count

	if count <= 0 then
		if chunks[key] then
			-- Grace period instead of a wider unload radius: walking back and
			-- forth over a chunk border costs nothing, and the loaded set stays
			-- bounded by the view distance.
			pendingUnload[key] = {
				cx = cx,
				cz = cz,
				dueAt = os.clock() + TerrainConfig.UnloadGraceSeconds,
			}
		else
			ChunkQueue.forget(key)
		end
	end
end

local function refreshPlayerChunks(player, newCX, newCZ)
	local previous = playerChunk[player]
	local previousActive = previous and previous.active or nil
	local active = {}

	local distance = viewDistanceFor(player)

	for dx = -distance, distance do
		for dz = -distance, distance do
			local cx, cz = newCX + dx, newCZ + dz
			if isChunkInBounds(cx, cz) then
				local key = chunkKey(cx, cz)
				local priority = dx * dx + dz * dz
				active[key] = { cx = cx, cz = cz }

				if not previousActive or not previousActive[key] then
					usageCounts[key] = (usageCounts[key] or 0) + 1
				end

				pendingUnload[key] = nil

				-- Not one already being built: a second entry for it would be
				-- dequeued and built a second time, side by side with the first.
				if not chunks[key] and not generatingChunks[key] then
					enqueueChunk(cx, cz, priority)
				end
			end
		end
	end

	-- Everything still queued was prioritised from where its players stood
	-- when it was asked for. See ChunkQueue.requeue.
	ChunkQueue.stale = true

	if previousActive then
		for oldKey, coord in pairs(previousActive) do
			if not active[oldKey] then
				releaseChunkUse(oldKey, coord.cx, coord.cz)
			end
		end
	end

	playerChunk[player] = { x = newCX, z = newCZ, active = active }
end

local function onPlayerMoved(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local position = hrp.Position
	local cx = getChunkCoordX(position.X)
	local cz = getChunkCoordZ(position.Z)
	local previous = playerChunk[player]

	-- Where they will be in about a second, in chunks from where they are, for
	-- ordering the queue (ChunkQueue.requeue). Capped: a fling or a
	-- teleport's velocity should not send generation off over the horizon.
	local velocity = hrp.AssemblyLinearVelocity
	local leadX, leadZ = velocity.X / CHUNK_STUDS, velocity.Z / CHUNK_STUDS
	local leadLength = math.sqrt(leadX * leadX + leadZ * leadZ)
	if leadLength < 0.25 then
		leadX, leadZ = 0, 0
	elseif leadLength > 2 then
		leadX, leadZ = leadX / leadLength * 2, leadZ / leadLength * 2
	end
	local lead = ChunkQueue.lead[player]
	if not lead then
		lead = {}
		ChunkQueue.lead[player] = lead
	end
	lead.x, lead.z = leadX, leadZ

	if not previous or previous.x ~= cx or previous.z ~= cz then
		refreshPlayerChunks(player, cx, cz)
	end
end

local function onPlayerRemoving(player)
	local data = playerChunk[player]
	if data then
		for key, coord in pairs(data.active) do
			releaseChunkUse(key, coord.cx, coord.cz)
		end
	end
	playerChunk[player] = nil
	playerViewDistance[player] = nil
end

--[[
	Unloads whatever has outlived its grace period, a few per frame.

	Everything a player leaves behind falls due together: teleport, respawn or
	travel and every chunk of the old view expires in the same Heartbeat, 5
	seconds later. Unloading all of them at once measured 213ms in one frame at
	view distance 7 (225 chunks at ~1ms each) - a freeze arriving five seconds
	after the move that caused it. Spread over frames it is invisible, and a
	chunk nobody can see lingering a few frames longer changes nothing.

	At least one per frame, so the backlog always drains however slow the frame.
]]
local function processPendingUnloads()
	local now = os.clock()
	local deadline = now + TerrainConfig.UnloadBudgetSeconds
	local unloaded = 0

	for key, entry in pairs(pendingUnload) do
		if isChunkWanted(key) then
			pendingUnload[key] = nil
		elseif generatingChunks[key] then
			-- Leave it scheduled; the generator re-checks on completion.
			continue
		elseif now >= entry.dueAt then
			if unloaded > 0 and os.clock() >= deadline then
				break
			end
			pendingUnload[key] = nil
			unloadChunk(entry.cx, entry.cz)
			unloaded += 1
		end
	end

	if unloaded > 0 then
		Profiler.sample("Terrain.unloadFrameMs", (os.clock() - now) * 1000, "ms")
	end
end

local pumpGeneration

local function startGeneration(item)
	activeGenerations += 1
	generatingChunks[item.key] = true
	-- A table, because a chunk can BECOME urgent while it builds (see
	-- yieldIfOverBudget), and the count has to come back down either way.
	local job = { urgent = item.priority <= URGENT_PRIORITY }
	if job.urgent then
		GenerationBudget.urgentStarted()
	end

	local requestedAt = ChunkQueue.requestedAt[item.key]
	ChunkQueue.requestedAt[item.key] = nil
	if requestedAt then
		-- How long the chunk sat behind other chunks before its turn came. At a
		-- wide view distance this used to be where nearly all of the wall clock
		-- went - 23 seconds against 58ms of actual work.
		Profiler.sample("Terrain.chunkQueueWaitMs", (os.clock() - requestedAt) * 1000, "ms")
	end

	task.spawn(function()
		local ok, err = pcall(generateChunk, item.cx, item.cz, job)
		generatingChunks[item.key] = nil
		activeGenerations -= 1
		if job.urgent then
			GenerationBudget.urgentFinished()
		end

		if not ok then
			warn("[TerrainManager] Chunk generation failed:", err)
			-- Drop whatever was half-built so a retry starts clean.
			unloadChunk(item.cx, item.cz)
		elseif not isChunkWanted(item.key) then
			unloadChunk(item.cx, item.cz)
		elseif requestedAt then
			-- End to end: player wanted it -> it is standing there. This is the
			-- number that decides whether a view distance feels playable, and
			-- the one that CPU cost alone hides.
			Profiler.sample("Terrain.chunkLatencyMs", (os.clock() - requestedAt) * 1000, "ms")
			if job.urgent then
				Profiler.sample("Terrain.urgentLatencyMs", (os.clock() - requestedAt) * 1000, "ms")
			end
		end

		-- A chunk finishing halfway through a frame used to waste the rest of
		-- that frame's allowance, because the next chunk was only ever started
		-- from the next Heartbeat. Refill immediately instead.
		pumpGeneration()
	end)
end

--[[
	Starts chunks while this frame still has allowance and there is room in
	flight.

	Re-entrancy guarded: task.spawn runs the new coroutine synchronously until it
	first yields, so a chunk that finishes without yielding calls back into here
	from inside the loop below. Returning early is correct there - the loop that
	is already running will carry on.
]]
local pumping = false

-- reason -> true while something has asked for generation to wait. See
-- ChunkStreaming.hold (TerrainManager:HoldGeneration).
local generationHolds = {}

function pumpGeneration()
	if pumping or next(generationHolds) ~= nil then
		return
	end
	pumping = true

	local maxConcurrent = TerrainConfig.MaxConcurrentChunks

	while budgetRemaining() > 0 do
		-- One slot over the limit, only for ground a player is standing at:
		-- it must not have to wait for a distant chunk to finish first. The
		-- distant ones stand aside while it builds (yieldIfOverBudget), so
		-- this does not split the allowance any further.
		if
			activeGenerations >= maxConcurrent
			and (activeGenerations > maxConcurrent or not hasUrgentWork(true))
		then
			break
		end

		local item = nextWantedItem()
		if not item then
			break
		end
		startGeneration(item)
	end

	pumping = false
end

local function onHeartbeatGenerate(dt)
	GenerationBudget.beginFrame()

	-- Before the budget is set, which looks in the queue for urgent work.
	if ChunkQueue.stale then
		ChunkQueue.requeue()
	end

	GenerationBudget.update(dt)

	Profiler.sample("Terrain.queueDepth", ChunkQueue.count(), "chunks")
	Profiler.sample("Terrain.activeGenerations", activeGenerations, "chunks")

	pumpGeneration()

	processPendingUnloads()
	BlockParts.trimPoolsIfNeeded()
	EditZones.closeExpired()

	-- Anything an edit changed without flushing a redraw of its own.
	FaceCulling.processChanges()
end

--[[
	Lifts a player who has ended up INSIDE solid ground back on top of it.

	Nobody can legitimately be inside a block: every solid cell that touches air
	is drawn, and drawn blocks collide. A player whose body is in one has
	slipped through a gap - in practice the moment between an edit taking
	ground away on their client and the replacement Part arriving (see
	applyLayerPlans) - and is falling through the world. Their client runs
	their physics, so it cannot be stopped there; but the server knows where
	the ground really is, so it puts them back on it within a frame or two
	instead of at the bottom of the world.

	Checked every frame because it is a handful of table reads per player, and
	a falling body crosses a thin floor quickly.
]]
local function rescueBuriedPlayer(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.Health <= 0 or root.Anchored then
		return
	end

	local position = root.Position
	local blockX = math.floor(position.X / STUD_SIZE)
	local blockZ = math.floor(position.Z / STUD_SIZE)
	local by = math.floor(position.Y / STUD_SIZE)

	local cx, cz, bx, bz = normalizeCell(
		blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE, blockX % CHUNK_SIZE, blockZ % CHUNK_SIZE
	)
	local key = chunkKey(cx, cz)
	local data = chunks[key]

	-- A chunk still being built may not have its edits replayed yet, so what it
	-- says is solid is not final.
	if not data or generatingChunks[key] then
		return
	end

	local cell = cellOf(bx, bz)
	if by < FLOOR_Y or by > MAX_BLOCK_Y or not isPresentInData(data, cell, by) then
		return
	end

	-- The first gap above them two blocks tall: room to stand, with ground
	-- under it, since everything scanned past on the way was solid.
	local feet = by + 1
	while feet <= MAX_BLOCK_Y and (isPresentInData(data, cell, feet) or isPresentInData(data, cell, feet + 1)) do
		feet += 1
	end
	if feet > MAX_BLOCK_Y then
		return
	end

	local lift = root.Size.Y * 0.5 + humanoid.HipHeight
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(position.X, feet * STUD_SIZE + lift + 0.05, position.Z) * root.CFrame.Rotation
	Profiler.count("Terrain.playerRescued")
end

local function onHeartbeatMovement(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		rescueBuriedPlayer(player)
	end

	movementAccumulator += dt
	if movementAccumulator < TerrainConfig.MovementCheckInterval then
		return
	end
	movementAccumulator = 0

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerMoved(player)
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle and settings (TerrainManager's public API delegates here)
-- ---------------------------------------------------------------------------

local function seatSoon(player)
	task.delay(0.15, function()
		if player.Parent then
			onPlayerMoved(player)
		end
	end)
end

-- Connects player tracking and the Heartbeat work. Called once from Init,
-- after everything a chunk build reads has been initialised.
function ChunkStreaming.start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			seatSoon(player)
		end)

		seatSoon(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			seatSoon(player)
		end
	end

	Players.PlayerRemoving:Connect(onPlayerRemoving)
	RunService.Heartbeat:Connect(onHeartbeatGenerate)
	RunService.Heartbeat:Connect(onHeartbeatMovement)
end

function ChunkStreaming.hold(reason)
	generationHolds[reason] = true
end

function ChunkStreaming.release(reason)
	generationHolds[reason] = nil
end

function ChunkStreaming.activeGenerations()
	return activeGenerations
end

--[[
	Re-queues everything every player currently wants.

	After a flush the usage counts still say the chunks are wanted, but nothing
	re-queues them: enqueueing happens when a player crosses a chunk border, and
	nobody moved. This is the call that actually restarts the load - kept
	separate from _FlushAll so a benchmark can tear the world down OUTSIDE its
	measurement window and time only the rebuild, rather than timing its own
	teardown spike as if it were load cost.
]]
local function reseatPlayers()
	for player, previous in pairs(playerChunk) do
		if player.Parent then
			refreshPlayerChunks(player, previous.x, previous.z)
		end
	end
end
ChunkStreaming.reseatPlayers = reseatPlayers

--[[
	Changes how far terrain streams, at runtime.

	Exists so a benchmark can sweep 2 -> 5 inside one server session, which is
	the only way to compare view distances without also comparing two different
	world seeds, two different sets of warm caches and two different machines.

	Every player's active set is re-seated immediately: chunks that fell outside
	the new radius go into the normal unload grace, chunks that came inside are
	queued at their real priority. Nothing about the streaming rules changes -
	only the radius they are applied over.
]]
--[[
	Changes the view distance for EVERYONE, and puts them all back on it.

	Personal choices are discarded rather than left standing. That is what both
	callers want and neither could get otherwise: the benchmark sweeps 2 -> 5
	and has to be measuring the distance it swept to, and /bbvd is an admin
	saying what the server is doing. A sweep silently measuring a developer's
	own leftover setting is a benchmark that reports the wrong number without
	ever looking wrong.

	MAX_PRIORITY is no longer re-derived here - it is fixed at what the largest
	permitted distance needs, because a player may sit above the default.
]]
function ChunkStreaming.setViewDistance(distance)
	distance = math.floor(tonumber(distance) or VIEW_DISTANCE)
	distance = math.clamp(distance, 0, MAX_VIEW_DISTANCE)

	local hadOverrides = next(playerViewDistance) ~= nil
	if distance == VIEW_DISTANCE and not hadOverrides then
		return VIEW_DISTANCE
	end

	VIEW_DISTANCE = distance
	table.clear(playerViewDistance)

	reseatPlayers()

	return VIEW_DISTANCE
end

function ChunkStreaming.getViewDistance()
	return VIEW_DISTANCE
end

--[[
	One player's own view distance.

	Clamped to the configured bounds here rather than trusted, because this is
	reachable from a remote - and the number decides how much work the SERVER
	does on that player's behalf, so it is not theirs to set freely.

	Returns what was actually applied, which is what the caller should show:
	asking for 12 and being given 7 has to be visible, or the option reads as
	broken.
]]
function ChunkStreaming.setPlayerViewDistance(player, distance)
	distance = math.floor(tonumber(distance) or VIEW_DISTANCE)
	distance = math.clamp(distance, MIN_VIEW_DISTANCE, MAX_VIEW_DISTANCE)

	if viewDistanceFor(player) == distance then
		return distance
	end

	playerViewDistance[player] = distance

	-- Re-seat only this player. Their chunks are reference counted against
	-- everyone else's, so widening loads what is missing and narrowing releases
	-- what nobody else wants, without touching anything anyone else is standing
	-- in.
	local previous = playerChunk[player]
	if previous then
		refreshPlayerChunks(player, previous.x, previous.z)
	end

	return distance
end

function ChunkStreaming.getPlayerViewDistance(player)
	return viewDistanceFor(player)
end

function ChunkStreaming.getViewDistanceRange()
	return MIN_VIEW_DISTANCE, MAX_VIEW_DISTANCE
end

return ChunkStreaming
