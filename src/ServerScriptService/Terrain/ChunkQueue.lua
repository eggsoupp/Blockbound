--[[
	ChunkQueue

	The generation queue: chunks players want that are not built yet, bucketed
	by priority, plus when each was first asked for (for latency samples) and
	the rebuild that re-orders it from where players are heading. Part of
	TerrainManager; see TerrainManager for the map of terrain modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))

local ChunkData = require(script.Parent:WaitForChild("ChunkData"))

local ChunkQueue = {}

--[[
	MAX_PRIORITY is the ceiling of the dequeue scan, so it is derived from the
	largest distance ANYONE may ask for rather than from the current default -
	a chunk queued at a priority past it would never be dequeued at all.

	URGENT_PRIORITY: the 3x3 a player stands in (see GenerationBudget).
]]
local MAX_VIEW_DISTANCE = TerrainConfig.MaxViewDistanceChunks
local MAX_PRIORITY = 2 * MAX_VIEW_DISTANCE * MAX_VIEW_DISTANCE
local URGENT_PRIORITY = 2
ChunkQueue.MAX_PRIORITY = MAX_PRIORITY
ChunkQueue.URGENT_PRIORITY = URGENT_PRIORITY

local chunks = ChunkData.chunks
local generatingChunks = ChunkData.generating
local playerChunk = ChunkData.playerChunk
local isChunkWanted = ChunkData.isWanted
local chunkKey = TerrainGrid.chunkKey
local isChunkInBounds = TerrainGrid.isChunkInBounds

local queueBuckets = {} -- priority -> array of queue items
local queuedPriority = {} -- chunkKey -> best queued priority
local queuedCount = 0 -- live size of queuedPriority, kept incrementally
local queuedAt = {} -- chunkKey -> os.clock() when a player first asked for it
ChunkQueue.buckets = queueBuckets
ChunkQueue.priorityOf = queuedPriority
ChunkQueue.requestedAt = queuedAt

-- player -> { x, z }: where they are heading, in chunks. See requeue.
ChunkQueue.lead = setmetatable({}, { __mode = "k" })

-- Set when players have moved since the queue was last ordered; the next
-- Heartbeat rebuilds it (see requeue).
ChunkQueue.stale = nil

-- Bucketed by priority instead of linearly scanned. Priority is squared chunk
-- distance from the player, so it only ever spans 0..2*ViewDistance^2 and a
-- bucket array is both simpler and faster than a heap.

local function enqueueChunk(cx, cz, priority)
	if not isChunkInBounds(cx, cz) then
		return
	end

	local key = chunkKey(cx, cz)
	if chunks[key] then
		return
	end

	local existing = queuedPriority[key]
	if existing ~= nil and existing <= priority then
		return
	end

	if existing == nil then
		queuedCount += 1
		-- Stamped on the FIRST request, not on a later re-queue at a better
		-- priority: latency is "how long after a player wanted this chunk did
		-- they get it", and re-prioritising does not restart that clock.
		-- (Kept across a queue rebuild, which empties queuedPriority.)
		if queuedAt[key] == nil then
			queuedAt[key] = os.clock()
		end
	end

	queuedPriority[key] = priority

	local bucket = queueBuckets[priority]
	if not bucket then
		bucket = {}
		queueBuckets[priority] = bucket
	end
	bucket[#bucket + 1] = { key = key, cx = cx, cz = cz, priority = priority }
end

local function dequeueChunk()
	for priority = 0, MAX_PRIORITY do
		local bucket = queueBuckets[priority]
		if bucket then
			local count = #bucket
			while count > 0 do
				local item = bucket[count]
				bucket[count] = nil
				count -= 1

				-- Stale entries are left behind when a chunk is re-queued at a
				-- better priority; drop them rather than pay to remove them.
				if queuedPriority[item.key] == item.priority then
					queuedPriority[item.key] = nil
					queuedCount -= 1
					return item
				end
			end
		end
	end

	return nil
end

--[[
	Rebuilds the queue from where every player is NOW.

	A queued chunk kept the priority it was given when it was first asked for,
	and could only ever be moved up. So a player travelling fast left a trail of
	chunks behind them still queued as "next to the player", and the generator
	worked through those while the ground in front ran out - at view distance 7
	one chunk of travel asks for fifteen new chunks, more than it can build, so
	what it spends its time on decides whether there is ground to land on.

	Priority is still squared chunk distance, lowest first, with two changes:

	  * it is measured from where the player will be in about a second (their
	    velocity, capped at two chunks), so the chunks ahead of a moving player
	    come before the ones beside and behind;
	  * the 3x3 they stand in keeps its true distance, 0..URGENT_PRIORITY, so
	    nothing ahead can be put before the ground under their feet.

	A chunk several players want takes the best of their priorities, as before.
	Which chunks load, and what is in them, is unchanged: only the order.
]]
local function requeue()
	ChunkQueue.stale = nil

	table.clear(queueBuckets)
	table.clear(queuedPriority)
	queuedCount = 0

	for player, info in pairs(playerChunk) do
		local lead = ChunkQueue.lead[player]
		local leadX, leadZ = 0, 0
		if lead then
			leadX, leadZ = lead.x, lead.z
		end
		local moving = leadX ~= 0 or leadZ ~= 0

		for key, coord in pairs(info.active) do
			if not chunks[key] and not generatingChunks[key] then
				local dx, dz = coord.cx - info.x, coord.cz - info.z
				local priority = dx * dx + dz * dz

				if moving and priority > URGENT_PRIORITY then
					local ax, az = dx - leadX, dz - leadZ
					priority = math.clamp(
						math.floor(ax * ax + az * az + 0.5), URGENT_PRIORITY + 1, MAX_PRIORITY
					)
				end

				enqueueChunk(coord.cx, coord.cz, priority)
			end
		end
	end
end

--[[
	Takes the next chunk that is still wanted, discarding stale queue entries.
]]
local function nextWantedItem()
	local item = dequeueChunk()

	while item and (chunks[item.key] or generatingChunks[item.key] or not isChunkWanted(item.key)) do
		queuedAt[item.key] = nil
		item = dequeueChunk()
	end

	return item
end

-- A chunk nobody wants any more, dropped from the queue if it was in it.
function ChunkQueue.forget(key)
	if queuedPriority[key] ~= nil then
		queuedCount -= 1
	end
	queuedPriority[key] = nil
	queuedAt[key] = nil
end

-- Live number of distinct chunks queued.
function ChunkQueue.count()
	return queuedCount
end

ChunkQueue.enqueue = enqueueChunk
ChunkQueue.nextWanted = nextWantedItem
ChunkQueue.requeue = requeue

return ChunkQueue
