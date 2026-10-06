--[[
	IslandService

	Runs a player's island: decides whose island this server is, loads it before
	any terrain is built, keeps it saved, and saves it one last time on the way
	down. Island place only - in the open world it stands down immediately.

	LOAD ORDER IS THE WHOLE TRICK

	An island is the shared template plus its owner's edits, and edits are
	replayed only when a chunk is BUILT (see ChunkEdits). So they must be in
	ChunkEdits before the first chunk generates, or the island would appear as
	the bare template and stay that way until each chunk happened to stream
	out and back in.

	  1. The server starts with terrain generation held.
	  2. The first player decides whose island it is. Their character is frozen
	     where it spawned while the save loads, so nobody falls through ground
	     that does not exist yet.
	  3. The save goes into ChunkEdits and StationService; generation resumes.
	  4. Each frozen character is let go once the ground under it is built.

	WHOSE ISLAND

	A reserved server (where /island sends you) looks its owner up in
	IslandDirectory by its own PrivateServerId, so a visitor who happens to
	arrive first can never claim someone else's island. Anywhere else - Studio,
	or a plain server of the island place - the first player to arrive owns it.

	SAVING

	Every IslandConfig.AutosaveInterval seconds while there are unsaved changes,
	whenever the owner leaves, and a final save on shutdown that also gives up
	the session lock. A read-only island - DataStores unavailable, or the island
	open on another server - is playable but never written, and every player on
	it is told so.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))

if not PlaceConfig.isIsland() then
	return
end

local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))

-- Before anything below can yield: no chunk may be built until the owner's
-- edits are in. Released by finishLoading whatever happens, including a
-- failed load.
local LOAD_HOLD = "IslandLoad"
TerrainManager:HoldGeneration(LOAD_HOLD)

local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local IslandConfig = require(TerrainShared:WaitForChild("IslandConfig"))
local ChunkEdits = require(TerrainShared:WaitForChild("ChunkEdits"))
local BlockConfig = require(Shared:WaitForChild("Blocks"):WaitForChild("BlockConfig"))

local StationService = require(ServerScriptService:WaitForChild("StationService"))
local IslandStore = require(ServerScriptService:WaitForChild("IslandStore"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local IslandDirectory = require(ServerScriptService:WaitForChild("IslandDirectory"))

-- Restoring a station needs its world folder, which init creates. Idempotent,
-- so it does not matter who calls it first.
StationService.init(TerrainManager)

local CHUNK_STUDS = TerrainConfig.ChunkStuds

-- How often the autosave loop looks for work. Small against the interval so
-- a save is never much later than it should be.
local AUTOSAVE_TICK = 5

-- A frozen character is let go after this long no matter what, so a load
-- that hangs can never trap a player in the air for good.
local CHARACTER_HOLD_LIMIT = 30

-- Joining players are told about a read-only island after this delay: their
-- client needs a moment to start listening for messages.
local MESSAGE_DELAY = 4

local ownerUserId = nil
local loaded = false
local readOnly = true
local readOnlyReason = nil
local dirty = false
local lastSaveAt = 0
local saving = false

local function log(...)
	print("[IslandService]", ...)
end

local function readOnlyMessage()
	if readOnlyReason == "datastore unavailable" then
		return "Island saving is off: DataStores are unavailable. In Studio, turn on "
			.. "Game Settings > Security > Enable Studio Access to API Services."
	elseif readOnlyReason == "locked" then
		return "This island is open on another server, so changes made here won't be saved."
	elseif readOnlyReason == "owner unknown" then
		return "Couldn't tell whose island this is, so changes made here won't be saved."
	end
	return "This island couldn't be opened for saving, so changes made here won't be saved."
end

-- ---------------------------------------------------------------------------
-- Snapshots
-- ---------------------------------------------------------------------------

-- The live island as plain data, for IslandStore. Copies out of ChunkEdits'
-- maps without yielding, as forEachChunk requires.
local function snapshotIsland()
	local chunks = {}

	ChunkEdits.forEachChunk(function(key, removed, placed)
		local cx, cz = TerrainManager:ChunkCoords(key)
		local chunk = { cx = cx, cz = cz, removed = {}, placed = {} }

		for cell, column in pairs(removed) do
			for by in pairs(column) do
				table.insert(chunk.removed, { cell, by })
			end
		end

		for cell, column in pairs(placed) do
			for by, name in pairs(column) do
				table.insert(chunk.placed, { cell, by, name })
			end
		end

		table.insert(chunks, chunk)
	end)

	return { chunks = chunks, stations = StationService.exportAll() }
end

--[[
	A saved island back into the world. Only valid while generation is held
	(see the header). Returns block changes loaded, stations restored, and how
	many entries were skipped - a block or station that no longer exists in
	the game, or a station cell already taken.
]]
local function applySnapshot(snapshot)
	local edits, stations, skipped = 0, 0, 0

	for _, chunk in ipairs(snapshot.chunks) do
		local list = {}

		for _, edit in ipairs(chunk.removed) do
			table.insert(list, { edit[1], edit[2], false })
		end

		for _, edit in ipairs(chunk.placed) do
			if BlockConfig.isPlaceable(edit[3]) then
				table.insert(list, { edit[1], edit[2], edit[3] })
			else
				skipped += 1
			end
		end

		edits += ChunkEdits.importChunk(TerrainManager:ChunkKey(chunk.cx, chunk.cz), list)
	end

	for _, station in ipairs(snapshot.stations) do
		if StationService.restore(station.id, station.x, station.y, station.z, ownerUserId) then
			stations += 1
		else
			skipped += 1
		end
	end

	return edits, stations, skipped
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

local function loadIsland()
	local record, info = IslandStore.load(ownerUserId)
	readOnly = info.readOnly
	readOnlyReason = info.reason

	if record == nil then
		log(string.format(
			"Island %d: %s.",
			ownerUserId,
			if info.source == "new" then "a brand new island" else "loaded as the bare template (" .. info.source .. ")"
		))
		return
	end

	local snapshot, problems = IslandStore.decode(record)
	local edits, stations, skipped = applySnapshot(snapshot)

	if record.template ~= nil and record.template ~= IslandConfig.TemplateVersion then
		warn(string.format(
			"[IslandService] Island %d was saved on island template %s; this server runs template %d. "
				.. "Its changes are replayed onto the current template.",
			ownerUserId, tostring(record.template), IslandConfig.TemplateVersion
		))
	end

	log(string.format(
		"Loaded island %d: %d block changes, %d stations%s.",
		ownerUserId, edits, stations,
		if problems + skipped > 0 then string.format(" (%d entries skipped)", problems + skipped) else ""
	))
end

local function finishLoading()
	loaded = true
	lastSaveAt = os.clock()

	workspace:SetAttribute("IslandOwnerId", ownerUserId)
	workspace:SetAttribute("IslandSaving", not readOnly)

	TerrainManager:ReleaseGeneration(LOAD_HOLD)

	if readOnly then
		local message = readOnlyMessage()
		for _, player in ipairs(Players:GetPlayers()) do
			task.delay(MESSAGE_DELAY, CommandFeedback.tell, player, message, "bad")
		end
	end
end

--[[
	Whose island this server is.

	A reserved server - which is what /island teleports into - looks its owner
	up in IslandDirectory, keyed by its own PrivateServerId, so nobody can claim
	it by arriving first. Anything else (Studio, a public server of the island
	place) falls back to the first player in. If the lookup fails the island
	still loads for the first player, but read-only, since it may not be theirs.
]]
local function resolveOwner(firstPlayer)
	local serverId = game.PrivateServerId
	if serverId ~= "" and game.PrivateServerOwnerId == 0 then
		local owner, err = IslandDirectory.ownerOfServer(serverId)
		if owner then
			return owner, false
		end
		warn("[IslandService] Could not tell whose island this server is:", err)
		return firstPlayer.UserId, true
	end
	return firstPlayer.UserId, false
end

local function beginLoading(firstPlayer)
	task.spawn(function()
		local resolved, owner, unknown = pcall(resolveOwner, firstPlayer)
		if not resolved then
			warn("[IslandService] Owner lookup errored:", owner)
			owner, unknown = firstPlayer.UserId, true
		end
		ownerUserId = owner
		log(string.format("This server is island %d.", ownerUserId))

		if unknown then
			readOnly = true
			readOnlyReason = "owner unknown"
			finishLoading()
			return
		end

		local ok, err = pcall(loadIsland)
		if not ok then
			warn("[IslandService] Loading the island failed; it will not be saved this session:", err)
			-- Whatever made it in is a partial island. Never write that over the
			-- real save - and hand the lock back so the next session is not
			-- locked out for the timeout.
			readOnly = true
			readOnlyReason = readOnlyReason or "load error"
			IslandStore.release(ownerUserId)
		end
		finishLoading()
	end)
end

-- ---------------------------------------------------------------------------
-- Characters
-- ---------------------------------------------------------------------------

-- Is the ground under this position built? Checks the chunks under a small
-- square, because a player standing on a chunk corner rests on up to four.
local function groundReadyAt(position)
	for dx = -1, 1, 2 do
		for dz = -1, 1, 2 do
			local cx = math.floor((position.X + dx * 2) / CHUNK_STUDS)
			local cz = math.floor((position.Z + dz * 2) / CHUNK_STUDS)
			if not TerrainManager:GetChunk(cx, cz) then
				return false
			end
		end
	end
	return true
end

local function holdCharacter(character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or (loaded and groundReadyAt(root.Position)) then
		return
	end

	root.Anchored = true

	local startedAt = os.clock()
	while root.Parent and character.Parent and os.clock() - startedAt < CHARACTER_HOLD_LIMIT do
		if loaded and groundReadyAt(root.Position) then
			break
		end
		task.wait(0.1)
	end

	if root.Parent then
		root.Anchored = false
	end
end

-- ---------------------------------------------------------------------------
-- Saving
-- ---------------------------------------------------------------------------

local function markDirty()
	dirty = true
end

ChunkEdits.setChangeListener(markDirty)
StationService.setChangeListener(markDirty)

--[[
	Writes the island now. `release` makes this the session's final save,
	giving up the lock in the same write; nothing is saved after it.
	Returns whether it was written.
]]
local function saveNow(reason, release)
	if not loaded or readOnly or ownerUserId == nil then
		return false
	end

	-- One save at a time: an autosave and the shutdown save can overlap, and
	-- two writes racing each other gain nothing.
	while saving do
		task.wait(0.1)
	end
	if readOnly then
		return false
	end

	saving = true
	-- Cleared before the snapshot rather than after the write, so an edit made
	-- while the save is in flight marks the island dirty again.
	dirty = false

	local ok, saved, err = pcall(function()
		local payload, skipped = IslandStore.encode(
			snapshotIsland(), TerrainConfig.WorldFloorY, IslandConfig.TemplateVersion
		)
		if skipped > 0 then
			warn(string.format("[IslandService] %d island entries could not be encoded and were left out.", skipped))
		end
		return IslandStore.save(ownerUserId, payload, reason, release)
	end)

	saving = false

	if not ok then
		err = saved
		saved = false
	end

	if saved then
		lastSaveAt = os.clock()
	else
		dirty = true
		warn(string.format("[IslandService] Island %d was not saved (%s): %s", ownerUserId, reason, tostring(err)))
	end

	if release then
		if not saved then
			IslandStore.release(ownerUserId)
		end
		readOnly = true
	end

	return saved == true
end

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_TICK)
		if
			loaded and not readOnly and dirty
			and os.clock() - lastSaveAt >= IslandConfig.AutosaveInterval
		then
			saveNow("autosave")
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------

local loadStarted = false

local function onPlayerAdded(player)
	if not loadStarted then
		loadStarted = true
		beginLoading(player)
	elseif loaded and readOnly then
		task.delay(MESSAGE_DELAY, CommandFeedback.tell, player, readOnlyMessage(), "bad")
	end

	player.CharacterAdded:Connect(holdCharacter)
	if player.Character then
		task.spawn(holdCharacter, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	if player.UserId == ownerUserId and dirty then
		task.spawn(saveNow, "owner left")
	end
end)

game:BindToClose(function()
	if ownerUserId == nil then
		return
	end

	-- A shutdown during the load still has to end the session properly.
	local waited = 0
	while not loaded and waited < 20 do
		task.wait(0.25)
		waited += 0.25
	end

	if not readOnly then
		saveNow("shutdown", true)
	end
end)
