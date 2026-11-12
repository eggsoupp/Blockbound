--[[
	ChunkRegeneration

	Puts abandoned open-world chunks back the way the generator made them.
	Part of TerrainManager; see TerrainManager for the map of terrain modules.

	A chunk is "changed" from the moment something in it is edited: a block
	mined or placed (heard from ChunkEdits), or a station put down
	(StationService, through noteChange). It stays changed, and untouched by
	this module, for as long as somebody keeps editing it or stands within
	Regeneration.NearbyChunks of it. Once neither has happened for the zone's
	time - StarterSeconds round spawn, WildSeconds elsewhere - it is reset:

	  * its ChunkEdits are discarded, so mined blocks are back and placed
	    blocks are gone the next time it builds;
	  * reset listeners run (StationService removes the stations there);
	  * if it is loaded - somebody can see it from further off - it is
	    unloaded and queued again, and comes back through the ordinary
	    generation path, budget and all.

	Ore that was harvested does NOT come back with the rock: OreDepletion
	remembers it separately and this module never touches that.

	WHY NOBODY IS EVER CAUGHT IN ONE

	A reset needs every player to have been at least NearbyChunks + 1 chunks
	away for the whole timer, not merely at the moment of the sweep, and any
	edit restarts the timer. Mining and building need the player within reach,
	which is far inside that distance. Chunks holding blocks in flight
	(pinned) or mid-build are skipped and looked at again next sweep.

	COST

	One table entry per changed chunk, dropped when it resets. A sweep every
	SweepSeconds does a handful of lookups per player and one comparison per
	changed chunk; nothing here runs per block or per frame. Rebuilding a
	loaded chunk is a normal chunk build, capped at MaxRebuildsPerSweep.

	The Island place never starts this: everything there is kept.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))
local ChunkEdits = require(TerrainShared:WaitForChild("ChunkEdits"))
local WorldZones = require(TerrainShared:WaitForChild("WorldZones"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local ChunkData = require(script.Parent:WaitForChild("ChunkData"))
local ChunkQueue = require(script.Parent:WaitForChild("ChunkQueue"))
local ChunkBuilder = require(script.Parent:WaitForChild("ChunkBuilder"))

local ChunkRegeneration = {}

local CONFIG = TerrainConfig.Regeneration
local CHUNK_SIZE = TerrainConfig.ChunkSize
local NEARBY = CONFIG.NearbyChunks

local chunks = ChunkData.chunks
local generatingChunks = ChunkData.generating
local pinnedChunks = ChunkData.pinnedChunks
local playerChunk = ChunkData.playerChunk
local chunkKey = TerrainGrid.chunkKey
local chunkCoords = TerrainGrid.chunkCoords
local isStarterChunk = WorldZones.isStarterChunk

-- Mutable so /bbregen can shorten them for a test; see setTimers.
local starterSeconds = CONFIG.StarterSeconds
local wildSeconds = CONFIG.WildSeconds

-- chunkKey -> os.clock() when it was last edited or had a player nearby.
-- Holds changed chunks only.
local lastActive = {}
local changedCount = 0

local resetListeners = {}
local started = false
local resetCount = 0
local rebuiltCount = 0

local function touch(key)
	if lastActive[key] == nil then
		changedCount += 1
	end
	lastActive[key] = os.clock()
end

local function resetChunk(key, cx, cz)
	lastActive[key] = nil
	changedCount -= 1
	resetCount += 1

	ChunkEdits.discard(key)

	for _, listener in ipairs(resetListeners) do
		local ok, err = pcall(listener, cx, cz)
		if not ok then
			warn("[ChunkRegeneration] reset listener failed:", err)
		end
	end

	if chunks[key] then
		ChunkBuilder.unloadChunk(cx, cz)
		rebuiltCount += 1

		-- Still in somebody's view: build it again. Queued last and marked
		-- stale, so the next Heartbeat gives it its real priority.
		if ChunkData.isWanted(key) then
			ChunkQueue.enqueue(cx, cz, ChunkQueue.MAX_PRIORITY)
			ChunkQueue.stale = true
		end
	end
end

local function sweep()
	local now = os.clock()

	-- A player keeps the changed chunks around them as they are.
	for _, info in pairs(playerChunk) do
		for dx = -NEARBY, NEARBY do
			for dz = -NEARBY, NEARBY do
				local key = chunkKey(info.x + dx, info.z + dz)
				if lastActive[key] then
					lastActive[key] = now
				end
			end
		end
	end

	local rebuilds = 0
	for key, last in pairs(lastActive) do
		local cx, cz = chunkCoords(key)
		local limit = if isStarterChunk(cx, cz) then starterSeconds else wildSeconds

		if now - last >= limit and not pinnedChunks[key] and not generatingChunks[key] then
			if not chunks[key] then
				resetChunk(key, cx, cz)
			elseif rebuilds < CONFIG.MaxRebuildsPerSweep then
				rebuilds += 1
				resetChunk(key, cx, cz)
			end
		end
	end

	if rebuilds > 0 then
		Profiler.count("Terrain.regenRebuilt", rebuilds)
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Begins watching for abandoned chunks. Called once from TerrainManager:Init;
-- does nothing on an island or with Regeneration.Enabled off.
function ChunkRegeneration.start()
	if started or not WorldZones.enabled or not CONFIG.Enabled then
		return
	end
	started = true

	ChunkEdits.setChangeListener(touch)

	task.spawn(function()
		while true do
			task.wait(CONFIG.SweepSeconds)
			local ok, err = pcall(sweep)
			if not ok then
				warn("[ChunkRegeneration] sweep failed:", err)
			end
		end
	end)
end

function ChunkRegeneration.isActive()
	return started
end

--[[
	Marks the chunk holding a block column as changed, for something that is
	not a terrain edit but should still be cleared away when the area is
	abandoned - a station. Terrain edits are heard from ChunkEdits directly.
]]
function ChunkRegeneration.noteChange(blockX, blockZ)
	if started then
		touch(chunkKey(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE))
	end
end

-- listener(cx, cz) runs when a chunk is reset, loaded or not. It must not
-- yield, and must not edit terrain.
function ChunkRegeneration.onReset(listener)
	table.insert(resetListeners, listener)
end

-- Test hook (/bbregen): changes both timers for this server.
function ChunkRegeneration.setTimers(starter, wild)
	starterSeconds = math.max(0, tonumber(starter) or starterSeconds)
	wildSeconds = math.max(0, tonumber(wild) or wildSeconds)
end

function ChunkRegeneration.getStats()
	return {
		active = started,
		changedChunks = changedCount,
		resets = resetCount,
		rebuiltLoaded = rebuiltCount,
		starterSeconds = starterSeconds,
		wildSeconds = wildSeconds,
	}
end

return ChunkRegeneration
