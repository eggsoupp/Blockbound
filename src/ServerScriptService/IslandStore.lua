--[[
	IslandStore

	The persistence layer for player islands: DataStore keys, retries, session
	locking, and the save format. It knows nothing about terrain, chunks or
	players - IslandService turns the live island into a plain snapshot and
	back, and this only stores snapshots.

	  IslandStore.load(ownerUserId)                         -> record?, info
	  IslandStore.save(ownerUserId, payload, why, release?) -> ok, err
	  IslandStore.release(ownerUserId)
	  IslandStore.encode(snapshot, floorY, templateVersion) -> payload, skipped
	  IslandStore.decode(record)                            -> snapshot, problems

	WHAT A SNAPSHOT IS

	  {
	    chunks = {
	      { cx = 0, cz = -1,
	        removed = { { cell, by }, ... },            -- natural blocks mined
	        placed  = { { cell, by, blockName }, ... },  -- blocks put down
	      },
	    },
	    stations = { { id = "Workbench", x = 3, y = 38, z = -2 }, ... },
	  }

	Only what players CHANGED. The island itself is a template every island
	shares (see IslandConfig), so a fresh island is an empty snapshot and a
	busy one is a few thousand entries.

	THE STORED FORMAT

	Each chunk's edits are one string, six characters per edit: three 12-bit
	fields - cell, height above the floor, and what is there (0 = removed,
	otherwise an index into a palette of block names) - two characters each
	from a 64-letter alphabet that is plain in JSON. A 200,000-edit island is
	about 1.2 MB, comfortably inside the 4 MB a DataStore entry may hold.

	The floor height is stored alongside, so edits keep their real height even
	if the island's floor is moved later.

	WHY A SESSION LOCK

	The same reason as InventoryStore: two servers holding one island at once
	both write, and whichever writes last silently throws the other's building
	away. The island place is meant to run one server per island, but a crash,
	a slow shutdown or a fast rejoin can still overlap two. Each load claims
	the island for this server; each save refuses to write over a claim that
	belongs to someone else.

	WHAT HAPPENS WHEN THINGS GO WRONG

	  Studio API access disabled  memory-only for the session: the island loads
	                              as the bare template and nothing is saved
	  DataStore failing           retried with backoff, then read-only
	  Locked by a live server     waited on, then shown READ-ONLY: what the
	                              other server last saved, never written back
	  Unreadable record           read-only bare template; the stored bytes are
	                              left exactly as they are
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local IslandStore = {}

-- ===========================================================================
-- CONFIGURATION
-- ===========================================================================

local CONFIG = {
	-- Change DataStoreName (or KeyPrefix) to give every player a fresh island
	-- without touching the old records.
	DataStoreName = "PlayerIslands_v1",
	KeyPrefix = "island_",

	-- Bumped whenever the stored shape changes. A record from a NEWER format
	-- than this is never overwritten; see load.
	FormatVersion = 1,

	-- Retry policy for a DataStore call that throws: 1s, 2s, 4s.
	MaxRetries = 4,
	RetryBaseDelay = 1,

	-- A lock older than this belonged to a server that died without releasing
	-- it, and is taken over. Studio's is short because a playtest killed hard
	-- never releases, and fifteen minutes locked out of your own island looks
	-- exactly like broken saving. Same reasoning as InventoryStore.
	SessionLockTimeout = 900,
	StudioSessionLockTimeout = 30,

	-- How long to wait for another server to let go before loading read-only:
	-- about twenty seconds, enough for a server that is shutting down to land
	-- its final save.
	LockWaitAttempts = 10,
	LockWaitDelay = 2,

	-- A DataStore value may be 4,000,000 characters of JSON. A save over this
	-- is refused outright rather than truncated or allowed to error halfway.
	MaxRecordCharacters = 3900000,
}

-- Identifies this server when claiming a lock. JobId is empty in Studio, so a
-- generated id stands in.
local SERVER_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

local dataStore = nil
local storeUnavailableReason = nil

-- ownerUserId -> { readOnly } for islands this server has loaded.
local sessions = {}

local function swarn(...)
	warn("[IslandStore]", ...)
end

-- ===========================================================================
-- DATASTORE PLUMBING
-- ===========================================================================

local function isApiDisabled(err)
	local message = string.lower(tostring(err))
	return string.find(message, "studio access to api", 1, true) ~= nil
		or string.find(message, "access to apis is not allowed", 1, true) ~= nil
end

local function markUnavailable(reason)
	if storeUnavailableReason then
		return
	end
	storeUnavailableReason = tostring(reason)
	swarn(
		"DataStore unavailable, running in memory-only mode for this session. "
			.. "The island will NOT be saved. Reason: " .. storeUnavailableReason
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

local function keyFor(ownerUserId)
	return CONFIG.KeyPrefix .. tostring(ownerUserId)
end

-- Runs a DataStore call with backoff. Returns ok, value.
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

local function lockIsForeign(record)
	if type(record) ~= "table" then
		return false
	end

	local lockId = record.lockId
	if type(lockId) ~= "string" or lockId == "" or lockId == SERVER_ID then
		return false
	end

	local lockedAt = tonumber(record.lockedAt) or 0
	-- A lock written BY Studio expires as fast as one seen from Studio: a
	-- playtest often dies before releasing, and must not keep the live game off
	-- the island for fifteen minutes. See the same rule in InventoryStore.
	local timeout = if RunService:IsStudio() or string.sub(lockId, 1, 7) == "studio-"
		then CONFIG.StudioSessionLockTimeout
		else CONFIG.SessionLockTimeout

	return (os.time() - lockedAt) < timeout
end

-- A record this code can read. Anything else is kept exactly as it is and
-- never written over: a newer format means a newer server wrote it.
local function isReadable(record)
	if record == nil then
		return true
	end
	if type(record) ~= "table" then
		return false
	end
	local format = tonumber(record.format) or CONFIG.FormatVersion
	return format <= CONFIG.FormatVersion
end

-- ===========================================================================
-- FORMAT
-- ===========================================================================

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

local DIGIT_CHAR = {} -- 0..63 -> character
local CHAR_DIGIT = {} -- byte  -> 0..63

for index = 1, #ALPHABET do
	local char = string.sub(ALPHABET, index, index)
	DIGIT_CHAR[index - 1] = char
	CHAR_DIGIT[string.byte(char)] = index - 1
end

-- Every field is two characters: 0 to 4095.
local FIELD_MAX = 64 * 64 - 1

-- Cells are 1..ChunkSize^2 in memory, stored 0-based.
local CELL_FIELD_MAX = 255

local EDIT_WIDTH = 6

local function packField(value)
	return DIGIT_CHAR[value // 64] .. DIGIT_CHAR[value % 64]
end

local function unpackField(text, at)
	local high = CHAR_DIGIT[string.byte(text, at)]
	local low = CHAR_DIGIT[string.byte(text, at + 1)]
	if high == nil or low == nil then
		return nil
	end
	return high * 64 + low
end

local function isInteger(value)
	return type(value) == "number" and value == value and value == math.floor(value)
end

--[[
	Snapshot -> the table that goes into the DataStore.

	Returns the payload and how many entries had to be dropped because they
	could not be represented (a height outside the format's range, more than
	4095 different block types). Both should be zero in practice; they are
	counted rather than allowed to corrupt the record.
]]
function IslandStore.encode(snapshot, floorY, templateVersion)
	local palette = {}
	local paletteIndex = {}
	local chunks = {}
	local editCount = 0
	local skipped = 0

	for _, chunk in ipairs(snapshot.chunks or {}) do
		local pieces = {}

		local function add(cell, by, kind)
			local cellField = cell - 1
			local heightField = by - floorY

			if
				not isInteger(cellField) or cellField < 0 or cellField > CELL_FIELD_MAX
				or not isInteger(heightField) or heightField < 0 or heightField > FIELD_MAX
				or kind > FIELD_MAX
			then
				skipped += 1
				return
			end

			pieces[#pieces + 1] = packField(cellField) .. packField(heightField) .. packField(kind)
			editCount += 1
		end

		for _, edit in ipairs(chunk.removed or {}) do
			add(edit[1], edit[2], 0)
		end

		for _, edit in ipairs(chunk.placed or {}) do
			local name = edit[3]
			local index = paletteIndex[name]
			if not index then
				palette[#palette + 1] = name
				index = #palette
				paletteIndex[name] = index
			end
			add(edit[1], edit[2], index)
		end

		if #pieces > 0 and isInteger(chunk.cx) and isInteger(chunk.cz) then
			chunks[chunk.cx .. "," .. chunk.cz] = table.concat(pieces)
		end
	end

	local stations = {}
	for _, station in ipairs(snapshot.stations or {}) do
		if
			type(station.id) == "string"
			and isInteger(station.x) and isInteger(station.y) and isInteger(station.z)
		then
			stations[#stations + 1] = { id = station.id, x = station.x, y = station.y, z = station.z }
		else
			skipped += 1
		end
	end

	return {
		format = CONFIG.FormatVersion,
		template = templateVersion,
		floorY = floorY,
		palette = palette,
		chunks = chunks,
		stations = stations,
		editCount = editCount,
		savedAt = os.time(),
	}, skipped
end

--[[
	Stored record -> snapshot. Never errors on bad data: anything it cannot make
	sense of is skipped and counted in `problems`, and everything else still
	loads.
]]
function IslandStore.decode(record)
	local snapshot = { chunks = {}, stations = {} }
	if type(record) ~= "table" then
		return snapshot, 0
	end

	local problems = 0
	local floorY = tonumber(record.floorY)
	local palette = if type(record.palette) == "table" then record.palette else {}

	if type(record.chunks) == "table" then
		if not floorY then
			-- Edits without the floor they were measured from cannot be placed.
			for _ in pairs(record.chunks) do
				problems += 1
			end
		else
			for key, encoded in pairs(record.chunks) do
				local cxText, czText = string.match(tostring(key), "^(%-?%d+),(%-?%d+)$")
				if not cxText or type(encoded) ~= "string" or #encoded % EDIT_WIDTH ~= 0 then
					problems += 1
					continue
				end

				local chunk = {
					cx = tonumber(cxText),
					cz = tonumber(czText),
					removed = {},
					placed = {},
				}

				for at = 1, #encoded, EDIT_WIDTH do
					local cellField = unpackField(encoded, at)
					local heightField = unpackField(encoded, at + 2)
					local kind = unpackField(encoded, at + 4)

					if not cellField or not heightField or not kind or cellField > CELL_FIELD_MAX then
						problems += 1
						continue
					end

					local cell = cellField + 1
					local by = heightField + floorY

					if kind == 0 then
						table.insert(chunk.removed, { cell, by })
					else
						local name = palette[kind]
						if type(name) == "string" and name ~= "" then
							table.insert(chunk.placed, { cell, by, name })
						else
							problems += 1
						end
					end
				end

				table.insert(snapshot.chunks, chunk)
			end
		end
	end

	if type(record.stations) == "table" then
		for _, station in ipairs(record.stations) do
			if
				type(station) == "table"
				and type(station.id) == "string"
				and isInteger(station.x) and isInteger(station.y) and isInteger(station.z)
			then
				table.insert(snapshot.stations, {
					id = station.id,
					x = station.x,
					y = station.y,
					z = station.z,
				})
			else
				problems += 1
			end
		end
	end

	return snapshot, problems
end

-- ===========================================================================
-- PUBLIC API
-- ===========================================================================

--[[
	Loads an island, claiming it for this server.

	Returns the stored record (nil for an island that has never been saved)
	and an info table:

	  info.source    "datastore" | "new" | "memory" | "fallback"
	  info.readOnly  true when nothing may be written for this island this
	                 session. Never write over real data with a guess.
	  info.reason    why it is read-only, when it is
]]
function IslandStore.load(ownerUserId)
	local session = { readOnly = false }
	sessions[ownerUserId] = session

	local store = getStore()
	if not store then
		session.readOnly = true
		return nil, { source = "memory", readOnly = true, reason = "datastore unavailable" }
	end

	local key = keyFor(ownerUserId)

	for attempt = 1, CONFIG.LockWaitAttempts do
		--[[
			One atomic read-claim-write. UpdateAsync can run its callback more
			than once if the key changes underneath it, so the captured values
			are reset at the top of every run rather than assumed fresh.
		]]
		local ok, result = withRetry("load/UpdateAsync", function()
			local captured = nil
			local blocked = nil

			store:UpdateAsync(key, function(old)
				captured = nil
				blocked = nil

				if not isReadable(old) then
					blocked = "unreadable"
					return nil
				end

				if lockIsForeign(old) then
					-- Kept, so the island can at least be SHOWN as it was last
					-- saved while another server holds it.
					blocked = "locked"
					captured = old
					return nil
				end

				captured = old

				local claimed = if type(old) == "table" then old else { format = CONFIG.FormatVersion }
				claimed.lockId = SERVER_ID
				claimed.lockedAt = os.time()
				return claimed
			end)

			return { record = captured, blocked = blocked }
		end)

		if not ok then
			session.readOnly = true

			-- The first call is where Studio reports API access being off, so
			-- this is usually the memory-only case rather than a real failure.
			if storeUnavailableReason then
				return nil, { source = "memory", readOnly = true, reason = "datastore unavailable" }
			end

			swarn(string.format("Could not read island %d; loading read-only.", ownerUserId))
			return nil, { source = "fallback", readOnly = true, reason = "datastore error" }
		end

		if result.blocked == "unreadable" then
			session.readOnly = true
			swarn(string.format(
				"Island %d's save is unreadable (newer format or corrupt); loading the bare island read-only so it is not overwritten.",
				ownerUserId
			))
			return nil, { source = "fallback", readOnly = true, reason = "unreadable" }
		end

		if result.blocked ~= "locked" then
			return result.record, {
				source = if result.record ~= nil then "datastore" else "new",
				readOnly = false,
			}
		end

		if attempt < CONFIG.LockWaitAttempts then
			task.wait(CONFIG.LockWaitDelay)
		else
			session.readOnly = true
			swarn(string.format(
				"Island %d is held by another server; showing its last save read-only.",
				ownerUserId
			))
			return result.record, { source = "datastore", readOnly = true, reason = "locked" }
		end
	end

	-- Unreachable: the last attempt always returns above.
	session.readOnly = true
	return nil, { source = "fallback", readOnly = true, reason = "unreachable" }
end

--[[
	Writes an island back.

	Refuses when the island is read-only, refuses again inside UpdateAsync if
	another server has since claimed it, and refuses a payload too large to
	store rather than letting the write fail halfway. `release` writes the
	record with this server's lock already removed - the final save of a
	session, in a single write.

	Returns ok, err.
]]
function IslandStore.save(ownerUserId, payload, reason, release)
	local session = sessions[ownerUserId]
	if not session or session.readOnly then
		return false, "read-only"
	end

	local store = getStore()
	if not store then
		return false, "datastore unavailable"
	end

	local encodedOk, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
	if not encodedOk then
		swarn(string.format("Island %d could not be encoded: %s", ownerUserId, tostring(encoded)))
		return false, "encode failed"
	end
	if #encoded > CONFIG.MaxRecordCharacters then
		swarn(string.format(
			"Island %d is too large to save (%d characters, limit %d). Nothing was written.",
			ownerUserId, #encoded, CONFIG.MaxRecordCharacters
		))
		return false, "too large"
	end

	local ok, result = withRetry("save/UpdateAsync", function()
		local wrote = false

		store:UpdateAsync(keyFor(ownerUserId), function(old)
			wrote = false

			if lockIsForeign(old) or not isReadable(old) then
				return nil
			end

			if release then
				payload.lockId = nil
				payload.lockedAt = nil
			else
				payload.lockId = SERVER_ID
				payload.lockedAt = os.time()
			end

			wrote = true
			return payload
		end)

		return wrote
	end)

	if not ok then
		return false, tostring(result)
	end

	if not result then
		swarn(string.format(
			"Skipped saving island %d (%s): another server holds it now.",
			ownerUserId, tostring(reason)
		))
		return false, "lock lost"
	end

	if release then
		-- The session is over. A late autosave must not re-claim the lock the
		-- final save just gave up.
		sessions[ownerUserId] = nil
	end

	return true
end

--[[
	Drops this server's claim without writing anything else, for a session that
	ends without a final save.
]]
function IslandStore.release(ownerUserId)
	local session = sessions[ownerUserId]
	sessions[ownerUserId] = nil

	if not session or session.readOnly then
		return
	end

	local store = getStore()
	if not store then
		return
	end

	withRetry("release/UpdateAsync", function()
		store:UpdateAsync(keyFor(ownerUserId), function(old)
			if type(old) ~= "table" or old.lockId ~= SERVER_ID then
				return nil
			end
			old.lockId = nil
			old.lockedAt = nil
			return old
		end)
	end)
end

function IslandStore.isReadOnly(ownerUserId)
	local session = sessions[ownerUserId]
	return session == nil or session.readOnly
end

return IslandStore
