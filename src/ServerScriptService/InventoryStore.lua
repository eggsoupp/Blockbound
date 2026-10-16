--[[
	InventoryStore

	The persistence layer for player inventories. Owns everything to do with
	DataStoreService: keys, retries, session locking, serialisation, validation
	and migration.

	It deliberately knows nothing about remotes, UI or player lifecycle - that is
	InventoryManager's job. This module only answers three questions:

	  InventoryStore.load(player)                  -> inventory, info
	  InventoryStore.save(player, inventory, why)  -> ok, err
	  InventoryStore.release(player, inventory, why)

	The inventory is the bulk of what a player carries between sessions but not
	all of it. Other systems attach their own state to the same record with
	registerSection, so everything shares one key and one session lock rather
	than racing a second one; see the note on it.

	WHY A SESSION LOCK
	  Without one, two servers can hold the same player's inventory at once - the
	  classic case being a player who leaves and rejoins fast enough to land on a
	  new server before the old one has finished saving. Both then write, and
	  whichever writes last wins, which is how items get duplicated or lost. Each
	  load claims the key for this server; each save refuses to write over a lock
	  that belongs to someone else.

	WHAT HAPPENS WHEN THINGS GO WRONG
	  DataStore down / throwing   retried with backoff; if it never succeeds the
	                              player is loaded read-only so a bad read can
	                              never be written back over good data
	  Locked by a live server     waited on, then loaded read-only
	  Studio API access disabled  detected once, then the whole module runs in
	                              memory-only mode so the game is still playable
	  Corrupt or partial record   repaired slot by slot; anything unrecognisable
	                              is dropped, and over-stacked slots overflow
	                              into free space rather than being truncated
	  No record at all            the configured starting inventory

	The one rule that keeps items from duplicating: a session is loaded exactly
	once and never merged with anything.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inventory = require(ServerScriptService:WaitForChild("InventoryClass"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local InventoryStore = {}

-- ===========================================================================
-- CONFIGURATION
-- ===========================================================================

local CONFIG = {
	-- Change DataStoreName (or KeyPrefix) to start every player from scratch
	-- without touching the old records - useful while the item list is still
	-- moving around.
	DataStoreName = "PlayerInventory_v1",
	KeyPrefix = "inv_",

	-- Bumped whenever the stored shape changes. See migrateRecord.
	SchemaVersion = 2,

	-- Retry policy for a DataStore call that throws. Delays are
	-- RetryBaseDelay * 2^(attempt-1), so 1s, 2s, 4s.
	MaxRetries = 4,
	RetryBaseDelay = 1,

	-- A lock older than this is assumed to belong to a server that crashed
	-- without releasing it, and is taken over. Must comfortably exceed the
	-- longest plausible session-save gap.
	SessionLockTimeout = 900,

	-- Studio uses a much shorter timeout. A playtest that is killed hard - Studio
	-- crashing, or being closed outright - never runs BindToClose, so it leaves
	-- its lock behind. With the production timeout that would lock the developer
	-- out of their own save for fifteen minutes and look exactly like broken
	-- persistence. Studio is a single-session environment, so a short timeout
	-- costs nothing there.
	StudioSessionLockTimeout = 30,

	-- How long to wait for another server to let go of a live lock before
	-- giving up and loading read-only. Teleporting between places makes this
	-- the normal case rather than a rare one: the server being left is still
	-- writing its final save when the next one asks. About twenty seconds.
	LockWaitAttempts = 10,
	LockWaitDelay = 2,
}

--[[
	Items granted to a player who has never played before.

	Empty by default, which is exactly what the game did before this module
	existed - a brand new player got an empty 42-slot bag. Add entries here to
	give starting gear; they go through Inventory:Add, so stack limits apply.

		InventoryStore.DefaultInventory = {
			{ name = "TestPickaxe", count = 1 },
			{ name = "Wood", count = 8 },
		}
]]
InventoryStore.DefaultInventory = {}

-- ===========================================================================
-- STATE
-- ===========================================================================

-- Identifies this server when claiming a lock. JobId is empty in Studio, so a
-- generated id stands in - otherwise two Studio sessions would look like the
-- same server to each other.
local SERVER_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

-- Mirrors InventoryClass's slot count without hardcoding 42 a second time. If
-- the inventory ever grows, this follows it.
local SLOT_COUNT = #Inventory.new():GetAll()

local dataStore = nil
local storeUnavailableReason = nil

-- userId -> session bookkeeping for players currently on this server.
local sessions = {}

-- userId -> number of saves currently in flight, so a rejoin cannot read the key
-- before the previous session has finished writing to it. A counter rather than
-- a flag because an autosave and a leave-save can overlap, and the first to
-- finish must not clear the second's marker.
local savesInFlight = {}

local function beginSave(userId)
	savesInFlight[userId] = (savesInFlight[userId] or 0) + 1
end

local function endSave(userId)
	local count = (savesInFlight[userId] or 1) - 1
	savesInFlight[userId] = if count > 0 then count else nil
end

local function swarn(...)
	warn("[InventoryStore]", ...)
end

-- ===========================================================================
-- DATASTORE PLUMBING
-- ===========================================================================

--[[
	Studio refuses DataStore calls unless "Enable Studio Access to API Services"
	is ticked, and every server refuses them in a place that has never been
	published. Both are permanent conditions for the session rather than
	transient faults, so they are detected and latched instead of retried.
]]
local function isApiDisabled(err)
	local message = string.lower(tostring(err))
	return string.find(message, "studio access to api", 1, true) ~= nil
		or string.find(message, "access to apis is not allowed", 1, true) ~= nil
		or string.find(message, "publish this place", 1, true) ~= nil
		-- "Cannot write to DataStore from studio if API access is not enabled",
		-- which is what UpdateAsync says rather than the wording above.
		or string.find(message, "api access is not enabled", 1, true) ~= nil
		or string.find(message, "studioaccesstoapisnotallowed", 1, true) ~= nil
end

local function markUnavailable(reason)
	if storeUnavailableReason then
		return
	end
	storeUnavailableReason = tostring(reason)
	swarn(
		"DataStore unavailable, running in memory-only mode for this session. "
			.. "Inventories will NOT persist. Reason: " .. storeUnavailableReason
	)
end

local function getStore()
	if storeUnavailableReason then
		return nil
	end
	if dataStore then
		return dataStore
	end

	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, CONFIG.DataStoreName)
	if not ok then
		markUnavailable(result)
		return nil
	end

	dataStore = result
	return dataStore
end

local function keyFor(userId)
	return CONFIG.KeyPrefix .. tostring(userId)
end

--[[
	Runs a DataStore call with backoff. Returns ok, value.

	Only genuinely transient failures are retried; a disabled API latches the
	module into memory-only mode immediately rather than burning seven seconds
	discovering the same thing four times.
]]
local function withRetry(label, fn, ...)
	for attempt = 1, CONFIG.MaxRetries do
		local ok, result = pcall(fn, ...)
		if ok then
			return true, result
		end

		if isApiDisabled(result) then
			markUnavailable(result)
			return false, result
		end

		if attempt == CONFIG.MaxRetries then
			swarn(string.format("%s failed after %d attempts: %s", label, attempt, tostring(result)))
			return false, result
		end

		task.wait(CONFIG.RetryBaseDelay * 2 ^ (attempt - 1))
	end

	return false, "unreachable"
end

-- ===========================================================================
-- SERIALISATION
-- ===========================================================================

-- The same rule InventoryClass uses, kept in step with it deliberately.
local function getMaxStack(def)
	return (def and tonumber(def.maxStack)) or 64
end

--[[
	Inventory -> stored record.

	Only occupied slots are written, each tagged with its index, so the record
	stays small and a change to SLOT_COUNT does not shift everyone's items
	sideways. Nothing else about the inventory is stored: the equipped hotbar
	slot lives only on the client and is UI state, not inventory state.
]]
--[[
	OTHER PER-PLAYER STATE THAT RIDES ON THIS RECORD.

	  InventoryStore.registerSection("abilities", save, load)
	    save(player)         -> a JSON-safe value, or nil to store nothing
	    load(player, value)  -> called with whatever was stored, on a real load

	The inventory is the bulk of what a player carries between sessions but it
	was never going to be all of it, and the alternative - a second DataStore
	per system - means a second session lock that can disagree with this one
	about which server owns the player. Two locks racing is how a rejoin loses
	half a save and keeps the other half.

	So everything shares one key, one lock, one retry policy and one autosave.
	The dependency points the right way too: a gameplay module registers itself
	here, rather than this file learning what an ability is.

	A section's loader is called ONLY when a real record came back. Every
	failure path - no DataStore, a foreign lock, an unreadable record - loads
	nothing, which leaves each section on whatever it defaults to. That is
	deliberate: a read-only session must not present a guess as saved state.
]]
local sections = {}
local sectionOrder = {}

local function runSectionLoad(name, player, value)
	local ok, err = pcall(sections[name].load, player, value)
	if not ok then
		swarn(string.format("Section '%s' failed to load for %s: %s", name, player.Name, err))
	end
end

function InventoryStore.registerSection(name, save, load)
	assert(type(name) == "string" and name ~= "", "[InventoryStore] a section needs a name")
	assert(type(save) == "function", "[InventoryStore] a section needs a save function")
	assert(type(load) == "function", "[InventoryStore] a section needs a load function")
	assert(sections[name] == nil, "[InventoryStore] section '" .. name .. "' is already registered")

	sections[name] = { save = save, load = load }
	table.insert(sectionOrder, name)

	--[[
		Catch up anyone already loaded.

		The order server scripts run in is not defined, and load() yields on the
		DataStore for whole seconds - so a section can easily be registered after
		a player's record has already come back. Without this it would simply
		never be told, and the symptom is the worst kind: persistence that looks
		like it works until someone rejoins.
	]]
	for userId, session in pairs(sessions) do
		local player = Players:GetPlayerByUserId(userId)
		if player and session.sectionData ~= nil then
			runSectionLoad(name, player, session.sectionData[name])
		end
	end
end

--[[
	Restores every registered section from a loaded record.

	The raw data is kept on the session as well, so a section that registers
	later can still be given it - see registerSection.

	Errors are contained per section: one that throws must not cost the player
	the inventory that came back with it.
]]
local function applySections(player, record)
	local stored = if type(record) == "table" and type(record.sections) == "table"
		then record.sections
		else {}

	local session = sessions[player.UserId]
	if session then
		session.sectionData = stored
	end

	for _, name in ipairs(sectionOrder) do
		runSectionLoad(name, player, stored[name])
	end
end

--[[
	`player` is optional: preview() serialises an inventory on its own to show
	what would be written, and has nobody to ask for the sections.
]]
local function serialize(inventory, player)
	local slots = {}
	local data = inventory:GetAll()

	for index = 1, SLOT_COUNT do
		local slot = data[index]
		if slot and slot.name and (slot.count or 0) > 0 then
			table.insert(slots, {
				s = index,
				n = slot.name,
				c = math.floor(slot.count),
			})
		end
	end

	local extra = nil
	if player then
		for _, name in ipairs(sectionOrder) do
			local ok, value = pcall(sections[name].save, player)
			if not ok then
				swarn(string.format("Section '%s' failed to save for %s: %s", name, player.Name, value))
			elseif value ~= nil then
				extra = extra or {}
				extra[name] = value
			end
		end
	end

	return {
		version = CONFIG.SchemaVersion,
		slots = slots,
		sections = extra,
		savedAt = os.time(),
	}
end

--[[
	Brings older shapes up to the current one. Returns a record in v2 form, or
	nil if it cannot be understood at all.

	Known history:
	  v1 / unversioned  a dense array of { name, count }, one entry per slot.
	                    This is what Inventory:ToJSON produces, and what the old
	                    player-attribute "persistence" stored.
	  v2                { version, slots = { {s,n,c}, ... }, savedAt }
]]
local function migrateRecord(record)
	if type(record) == "string" then
		-- A raw ToJSON string, which is what the pre-DataStore code kept on a
		-- player attribute. Decode it and fall through to the array handling.
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, record)
		if not ok or type(decoded) ~= "table" then
			return nil
		end
		record = decoded
	end

	if type(record) ~= "table" then
		return nil
	end

	if record.version == nil and record.slots == nil then
		-- Dense array form: index is the slot number.
		local slots = {}
		for index, slot in ipairs(record) do
			if type(slot) == "table" and slot.name then
				table.insert(slots, { s = index, n = slot.name, c = slot.count })
			end
		end
		return { version = CONFIG.SchemaVersion, slots = slots, savedAt = record.savedAt }
	end

	if type(record.slots) ~= "table" then
		return nil
	end

	if record.version ~= nil and type(record.version) == "number" and record.version > CONFIG.SchemaVersion then
		-- Written by a newer build. Reading it with old rules risks mangling it,
		-- so refuse and let the caller load read-only.
		return nil, "newer schema"
	end

	return record
end

--[[
	Stored record -> a live Inventory, repairing whatever is wrong on the way.

	Returns inventory, repairCount.

	Repairs, in order of how much they can cost the player:
	  * unknown item name        dropped (nothing sensible to restore it as)
	  * bad or duplicate slot    kept, but re-placed via Inventory:Add
	  * count over the stack cap kept, with the excess re-placed via Add
	  * count <= 0 or non-number dropped

	Over-stacked and misplaced items go through Inventory:Add rather than being
	truncated, so a corrupt record costs the player as little as possible.
]]
local function deserialize(record)
	local slots = table.create(SLOT_COUNT)
	for index = 1, SLOT_COUNT do
		slots[index] = { name = nil, count = 0 }
	end

	local overflow = {}
	local repairs = 0

	for _, entry in ipairs(record.slots or {}) do
		if type(entry) ~= "table" then
			repairs += 1
			continue
		end

		local name = entry.n
		local count = tonumber(entry.c)
		local index = tonumber(entry.s)

		local definition = type(name) == "string" and ItemDefinitions[name] or nil

		if not definition then
			-- An item that no longer exists, or a renamed one. There is nothing
			-- to restore it as, so it goes - loudly.
			repairs += 1
			swarn(string.format("Dropping unknown item '%s' from a saved inventory.", tostring(name)))
			continue
		end

		if not count or count <= 0 or count ~= count then
			repairs += 1
			continue
		end

		count = math.floor(count)
		local maxStack = getMaxStack(definition)

		local placeable = 0
		if index and index == math.floor(index) and index >= 1 and index <= SLOT_COUNT
			and not slots[index].name
		then
			placeable = math.min(count, maxStack)
			slots[index] = { name = name, count = placeable }
		else
			-- Out of range, non-integer, or a slot something else already claims.
			repairs += 1
		end

		local leftover = count - placeable
		if leftover > 0 then
			if placeable > 0 then
				repairs += 1 -- over-stacked slot
			end
			table.insert(overflow, { name = name, count = leftover })
		end
	end

	local inventory = Inventory.new(slots)

	-- Anything that could not go back where it came from is re-added through
	-- the inventory's own logic, which respects stack sizes and finds free
	-- space the same way a normal pickup would. Partial on purpose: restoring
	-- some of an over-stacked slot beats restoring none of it.
	for _, entry in ipairs(overflow) do
		local placed = inventory:AddUpTo(entry.name, entry.count)
		if placed < entry.count then
			swarn(string.format(
				"No room to restore %d x %s; they were dropped.",
				entry.count - placed, entry.name
			))
		end
	end

	return inventory, repairs
end

--[[
	A fresh inventory for a player with no save data.
]]
local function buildDefaultInventory()
	local inventory = Inventory.new()

	for _, entry in ipairs(InventoryStore.DefaultInventory) do
		if type(entry) == "table" and ItemDefinitions[entry.name] then
			inventory:Add(entry.name, entry.count or 1)
		elseif type(entry) == "table" then
			swarn("DefaultInventory lists unknown item:", tostring(entry.name))
		end
	end

	return inventory
end

-- ===========================================================================
-- SESSION LOCKING
-- ===========================================================================

local function lockIsForeign(record)
	if type(record) ~= "table" then
		return false
	end

	local lockId = record.lockId
	if type(lockId) ~= "string" or lockId == "" or lockId == SERVER_ID then
		return false
	end

	local lockedAt = tonumber(record.lockedAt) or 0

	--[[
		The short timeout applies to a lock WRITTEN by Studio as well as to every
		lock seen FROM Studio.

		Studio and live servers share one DataStore. A playtest stopped in Studio
		often dies before its leave-save finishes, and the lock it leaves behind
		used to hold the live game off the player's inventory for the full
		fifteen minutes - a live session then loaded an empty, unsaveable bag,
		which looks exactly like "my inventory never saves". A Studio session is
		one developer at a keyboard; thirty seconds is plenty.
	]]
	local timeout = if RunService:IsStudio() or string.sub(lockId, 1, 7) == "studio-"
		then CONFIG.StudioSessionLockTimeout
		else CONFIG.SessionLockTimeout

	-- A lock older than the timeout belonged to a server that went away without
	-- releasing it, and is safe to take over.
	return (os.time() - lockedAt) < timeout
end

-- ===========================================================================
-- PUBLIC API
-- ===========================================================================

--[[
	Loads a player's inventory, claiming the session lock for this server.

	Always returns a usable Inventory - never nil - so the caller has nothing to
	branch on. The second return describes what happened:

	  info.source    "datastore" | "default" | "fallback"
	  info.readOnly  true when saving is forbidden for this session, because
	                 whatever we loaded is not known to be that player's real,
	                 current data. Never write over good data with a guess.
	  info.repairs   how many slots had to be fixed up
]]
function InventoryStore.load(player)
	local userId = player.UserId

	-- If this player's previous session is still writing (a fast rejoin, or a
	-- rejoin onto the same server), let it finish first. Reading the key mid
	-- write is how a player loses whatever they picked up just before leaving.
	local waited = 0
	while savesInFlight[userId] and waited < 10 do
		task.wait(0.1)
		waited += 0.1
	end

	local session = {
		userId = userId,
		readOnly = false,
		lastSaveAt = 0,
		dirty = false,
	}
	sessions[userId] = session

	local store = getStore()
	if not store then
		-- Memory-only mode. A default bag, and saving is off, so nothing can be
		-- written over real data if the API comes back later in the session.
		session.readOnly = true
		session.readOnlyReason = "DataStores unavailable"
		return buildDefaultInventory(), { source = "default", readOnly = true, reason = "unavailable", repairs = 0 }
	end

	local key = keyFor(userId)
	local loaded = nil
	local blockedBy = nil -- "locked" | "corrupt" | nil

	for attempt = 1, CONFIG.LockWaitAttempts do
		blockedBy = nil

		--[[
			One atomic read-claim-write. UpdateAsync hands us the current value
			and takes whatever we return, so there is no window between deciding
			the key is free and marking it ours.

			Returning nil aborts the update, leaving the record untouched - that
			is how a foreign lock is refused.
		]]
		local ok, result = withRetry("load/UpdateAsync", function()
			local captured = nil
			local blocked = nil

			store:UpdateAsync(key, function(old)
				if lockIsForeign(old) then
					blocked = "locked"
					return nil
				end

				local migrated, migrateError = migrateRecord(old)
				if old ~= nil and not migrated then
					-- Present but unreadable. Keep the bytes exactly as they are
					-- and let the session run read-only, so a parser bug or a
					-- newer schema cannot cost the player their items.
					swarn(string.format(
						"Unreadable save for userId %d (%s).",
						userId, tostring(migrateError or "corrupt")
					))
					blocked = "corrupt"
					return nil
				end

				captured = migrated

				local claimed = migrated or { version = CONFIG.SchemaVersion, slots = {} }
				claimed.lockId = SERVER_ID
				claimed.lockedAt = os.time()
				return claimed
			end)

			return { record = captured, blocked = blocked }
		end)

		if not ok then
			-- DataStore is failing outright. Do not guess at their inventory, and
			-- above all do not write anything back.
			-- A disabled API is noticed inside withRetry and latched; that is a
			-- setting, not a fault with this player's save, and is reported so.
			local reason = if storeUnavailableReason then "unavailable" else "error"
			session.readOnly = true
			session.readOnlyReason = if reason == "unavailable"
				then "DataStores unavailable"
				else "the save could not be read"
			swarn(string.format("Could not read save for %s; loading read-only.", player.Name))
			return Inventory.new(), { source = "fallback", readOnly = true, reason = reason, repairs = 0 }
		end

		blockedBy = result.blocked

		if blockedBy == "locked" then
			-- Another server may be about to release it, so it is worth waiting.
			if attempt < CONFIG.LockWaitAttempts then
				task.wait(CONFIG.LockWaitDelay)
			end
		else
			-- Either loaded, or corrupt. Retrying a corrupt record just produces
			-- the same corrupt record, so stop either way.
			loaded = result.record
			break
		end
	end

	if blockedBy then
		--[[
			Read-only, and deliberately an EMPTY bag rather than the starting
			inventory.

			Their real items either live on another server right now, or are
			sitting in a record we could not parse. Handing out starting items on a
			failure path would mean a DataStore hiccup quietly mints free gear, and
			the empty bag makes it obvious to the player that something is wrong
			rather than looking like a normal fresh start.
		]]
		session.readOnly = true

		local explanation = if blockedBy == "locked"
			then "held by another session"
			else "unreadable"
		session.readOnlyReason = "the save was " .. explanation .. " when you joined"

		swarn(string.format(
			"%s's save is %s; loading read-only so nothing can overwrite it.",
			player.Name, explanation
		))
		return Inventory.new(), { source = "fallback", readOnly = true, reason = blockedBy, repairs = 0 }
	end

	--[[
		Deciding whether this player gets the starting inventory.

		"Has no record" is not a good enough test on its own. Claiming the session
		lock writes a placeholder record, so a brand new player who joins and
		leaves again within a few seconds already HAS a record - and would then be
		treated as a returning player forever, silently robbed of their starting
		kit.

		Nor is "record with an empty bag" good enough in the other direction: that
		is also what a returning player looks like after they spend everything,
		and re-granting there would mint free items every time someone emptied
		their inventory.

		So the record carries an explicit `granted` marker. Starting items are
		handed out once, to a player who has neither items nor the marker, and the
		marker is written with their next save.
	]]
	-- `loaded` is nil for a player with no record at all, so both tests have to
	-- tolerate that.
	local hasItems = loaded ~= nil and type(loaded.slots) == "table" and #loaded.slots > 0
	local wasGranted = loaded ~= nil and loaded.granted == true

	-- Set before every return below: once a session has been through this
	-- decision, its saves record that the grant has happened.
	session.granted = true

	-- Everything else this player carries between sessions, out of the same
	-- record. Before the three returns below because all of them are decisions
	-- about the INVENTORY, and none of them changes what a section holds.
	applySections(player, loaded)

	if not hasItems and not wasGranted then
		return buildDefaultInventory(), { source = "default", readOnly = false, repairs = 0 }
	end

	if not hasItems then
		return Inventory.new(), { source = "datastore", readOnly = false, repairs = 0 }
	end

	local inventory, repairs = deserialize(loaded)
	return inventory, { source = "datastore", readOnly = false, repairs = repairs }
end

--[[
	Writes the inventory back.

	Refuses when the session is read-only, and refuses again inside UpdateAsync
	if the lock has since been taken by another server - checked at the moment of
	writing rather than trusted from load time.

	Returns ok, err.
]]
function InventoryStore.save(player, inventory, reason)
	local userId = player.UserId
	local session = sessions[userId]

	if not inventory then
		return false, "no inventory"
	end

	if session and session.readOnly then
		return false, "read-only session"
	end

	local store = getStore()
	if not store then
		return false, "datastore unavailable"
	end

	local payload = serialize(inventory, player)

	-- Records that this player has already been given the starting inventory, so
	-- emptying their bag never re-triggers it. See the grant decision in load.
	if session and session.granted then
		payload.granted = true
	end

	local key = keyFor(userId)

	beginSave(userId)

	local ok, result = withRetry("save/UpdateAsync", function()
		local wrote = false

		store:UpdateAsync(key, function(old)
			if lockIsForeign(old) then
				-- Another server owns this player now. Ours is the stale copy.
				return nil
			end

			payload.lockId = SERVER_ID
			payload.lockedAt = os.time()
			wrote = true
			return payload
		end)

		return wrote
	end)

	endSave(userId)

	if not ok then
		return false, tostring(result)
	end

	if not result then
		swarn(string.format(
			"Skipped save for %s (%s): the lock is held by another server.",
			player.Name, tostring(reason)
		))
		return false, "lock lost"
	end

	if session then
		session.lastSaveAt = os.clock()
		session.dirty = false
	end

	return true
end

--[[
	Final save for a player who is leaving, then drops the lock so their next
	server can pick the record straight up instead of waiting out the timeout.
]]
function InventoryStore.release(player, inventory, reason)
	local userId = player.UserId
	local session = sessions[userId]

	-- A shutdown fires BindToClose and PlayerRemoving, so this can be called
	-- twice for one player at once. The second caller waits for the first rather
	-- than returning early, otherwise BindToClose could decide the save was done
	-- and let the server die mid-write.
	if session and session.releasing then
		local waited = 0
		while sessions[userId] == session and waited < 15 do
			task.wait(0.1)
			waited += 0.1
		end
		return true
	end

	if session then
		session.releasing = true
	end

	local saved, err = false, nil
	local store = getStore()

	if store then
		beginSave(userId)

		if inventory and session and not session.readOnly then
			--[[
				The final save and the unlock in ONE write.

				They used to be two back-to-back UpdateAsyncs on the same key, and
				DataStores hold a second write to a key for about six seconds - so
				the lock stayed up long after the save, and the server the player
				was teleporting to waited it out or gave up and loaded read-only.
			]]
			local payload = serialize(inventory, player)
			if session.granted then
				payload.granted = true
			end

			local ok, result = withRetry("release/UpdateAsync", function()
				local wrote = false

				store:UpdateAsync(keyFor(userId), function(old)
					wrote = false
					if lockIsForeign(old) then
						-- Another server owns this player now. Ours is the stale copy.
						return nil
					end

					payload.lockId = nil
					payload.lockedAt = nil
					wrote = true
					return payload
				end)

				return wrote
			end)

			if not ok then
				err = tostring(result)
			elseif not result then
				err = "lock lost"
				swarn(string.format(
					"Skipped the final save for %s (%s): the lock is held by another server.",
					player.Name, tostring(reason)
				))
			else
				saved = true
			end
		else
			--[[
				Nothing to save, but drop the lock if this server still holds it.

				Holding on after a failed load protects nothing: the record in the
				store is still the last good save. All a retained lock would achieve
				is forcing this player's NEXT session to run read-only until the
				timeout expires. The guard still refuses to touch a lock that has
				since been claimed by someone else.
			]]
			withRetry("release/UpdateAsync", function()
				store:UpdateAsync(keyFor(userId), function(old)
					if type(old) ~= "table" or old.lockId ~= SERVER_ID then
						return nil
					end
					old.lockId = nil
					old.lockedAt = nil
					return old
				end)
			end)
		end

		endSave(userId)
	end

	-- Only clear the session if it is still the one we were releasing. A player
	-- who rejoins this same server during the release would otherwise have their
	-- brand new session deleted out from under them, silently disabling autosave
	-- for the rest of it.
	if sessions[userId] == session then
		sessions[userId] = nil
	end

	return saved, err
end

--[[
	Housekeeping used by the autosave loop.
]]
function InventoryStore.markDirty(player)
	local session = sessions[player.UserId]
	if session then
		session.dirty = true
	end
end

function InventoryStore.shouldAutosave(player, minInterval)
	local session = sessions[player.UserId]
	if not session or session.readOnly or not session.dirty then
		return false
	end
	return (os.clock() - session.lastSaveAt) >= (minInterval or 0)
end

function InventoryStore.isReadOnly(player)
	local session = sessions[player.UserId]
	return session ~= nil and session.readOnly
end

--[[
	Whether any save or release is still being written, for anyone.

	BindToClose needs this, not just the list of players: when the last player
	leaves, their leave-save is already in flight by the time the server starts
	closing, and they are no longer in Players to be waited on by name.
]]
function InventoryStore.hasPendingWrites()
	return next(savesInFlight) ~= nil
end

--[[
	A one-line description of a player's save state, for /savestatus.

	Called summary rather than describe: describe, further down, is the debug
	console's table of the same facts, and the two used to share a name - the
	second definition silently replaced the first, and /savestatus errored
	trying to glue a table onto a string.
]]
function InventoryStore.summary(player)
	if storeUnavailableReason then
		return "OFF - DataStores unavailable (" .. storeUnavailableReason .. ")"
	end

	local session = sessions[player.UserId]
	if not session then
		return "not loaded"
	end
	if session.readOnly then
		return "OFF - this session is read-only (" .. tostring(session.readOnlyReason or "unspecified") .. ")"
	end

	local since = if session.lastSaveAt > 0
		then string.format("last saved %ds ago", math.floor(os.clock() - session.lastSaveAt))
		else "not saved yet this session"

	return string.format("on, %s%s", since, if session.dirty then ", unsaved changes" else "")
end

--[[
	Latches a session read-only so nothing can ever be written for it.

	The caller of last resort: if load itself fails in a way it did not plan for,
	whatever inventory the player ends up holding is a guess, and a guess must
	never be allowed to overwrite their real saved data.
]]
function InventoryStore.setReadOnly(player, reason)
	local session = sessions[player.UserId]
	if not session then
		session = { userId = player.UserId, lastSaveAt = 0, dirty = false }
		sessions[player.UserId] = session
	end

	if not session.readOnly then
		session.readOnly = true
		session.readOnlyReason = tostring(reason or "unspecified")
		swarn(string.format(
			"Saving disabled for %s: %s", player.Name, tostring(reason or "unspecified")
		))
	end
end

function InventoryStore.isAvailable()
	return storeUnavailableReason == nil
end

--[[
	Exposed for the debug console and for tests: what would be written for this
	inventory right now.
]]
function InventoryStore.preview(inventory)
	return serialize(inventory)
end

--[[
	A fresh inventory containing DefaultInventory. Public so the debug console can
	reset a player without duplicating the starting-items logic.
]]
function InventoryStore.buildDefault()
	return buildDefaultInventory()
end

--[[
	Deletes a player's saved record outright. Intended for testing the
	"never played before" path without needing a second account.

	The caller is responsible for also resetting the live inventory - otherwise
	the next save simply writes it straight back.
]]
function InventoryStore.wipe(player)
	local store = getStore()
	if not store then
		return false, storeUnavailableReason or "datastore unavailable"
	end

	local ok, err = withRetry("wipe/RemoveAsync", function()
		store:RemoveAsync(keyFor(player.UserId))
	end)

	if ok then
		local session = sessions[player.UserId]
		if session then
			session.dirty = false
			session.lastSaveAt = os.clock()
		end
	end

	return ok, err
end

--[[
	Human-readable session state, for the debug console.
]]
function InventoryStore.describe(player)
	local session = sessions[player.UserId]

	return {
		storeAvailable = storeUnavailableReason == nil,
		unavailableReason = storeUnavailableReason,
		serverId = SERVER_ID,
		key = keyFor(player.UserId),
		hasSession = session ~= nil,
		readOnly = session ~= nil and session.readOnly or false,
		dirty = session ~= nil and session.dirty or false,
		secondsSinceSave = if session and session.lastSaveAt > 0
			then math.floor(os.clock() - session.lastSaveAt)
			else -1,
		savesInFlight = savesInFlight[player.UserId] or 0,
	}
end

InventoryStore.SLOT_COUNT = SLOT_COUNT
InventoryStore.SERVER_ID = SERVER_ID
InventoryStore.CONFIG = CONFIG

return InventoryStore
