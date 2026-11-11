--[[
	IslandDirectory

	Which private server is whose island.

		IslandDirectory.accessCodeFor(ownerUserId, slot?) -> accessCode?, err
		IslandDirectory.ownerOfServer(privateServerId) -> ownerUserId?, slot | err, kind
		IslandDirectory.confirmOwner(privateServerId, userId, slot?) -> boolean?, err

	A player can own more than one island (Shared.IslandSlots). Island 1 keeps
	the keys it always had, so existing islands are found where they were;
	island 2 is "owner_<id>_2", and its server records "<id>_2" as its owner.

	Every player gets ONE reserved server of the Island place, reserved the
	first time anyone travels to their island and remembered from then on.
	Teleporting with the same access code always lands in the same server if it
	is running, and starts it if not - which is what lets the owner, and later
	their friends, all end up on the one copy of the island.

	The island server asks the other way round: "I am private server X; whose
	island am I?" That answer comes from here, on the server, rather than from
	the teleport data a client carries with it - teleport data can be edited by
	the player it travels with, so trusting it would let anyone claim to own
	anyone's island.

	Both directions are written together when the server is reserved, and
	never change afterwards.
]]

local DataStoreService = game:GetService("DataStoreService")
local TeleportService = game:GetService("TeleportService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlaceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlaceConfig"))

local IslandDirectory = {}

local DATASTORE_NAME = "IslandServers_v1"

local MAX_ATTEMPTS = 3

local store = nil

-- ownerUserId -> accessCode, so travelling twice in a session asks once.
local codeCache = {}

local function getStore()
	if not store then
		local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, DATASTORE_NAME)
		if not ok then
			return nil, tostring(result)
		end
		store = result
	end
	return store
end

local function withRetry(fn)
	local lastError = nil
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < MAX_ATTEMPTS then
			task.wait(attempt)
		end
	end
	return false, tostring(lastError)
end

--[[
	The access code for a player's island server, reserving it on first use.

	UpdateAsync makes the reservation race-safe: if two servers reserve for the
	same player at once, whichever writes second sees the first's code and
	keeps it, so the player never ends up with two islands.
]]
function IslandDirectory.accessCodeFor(ownerUserId, slot)
	slot = slot or 1
	local suffix = if slot > 1 then "_" .. slot else ""
	local cacheKey = tostring(ownerUserId) .. suffix
	if codeCache[cacheKey] then
		return codeCache[cacheKey]
	end

	if PlaceConfig.IslandPlaceId == 0 then
		return nil, "the Island place ID is not set in PlaceConfig"
	end

	local dataStore, storeError = getStore()
	if not dataStore then
		return nil, storeError
	end

	local key = "owner_" .. ownerUserId .. suffix

	local ok, existing = withRetry(function()
		return dataStore:GetAsync(key)
	end)
	if not ok then
		return nil, existing
	end

	local record = nil

	if type(existing) == "table" and type(existing.code) == "string" and type(existing.serverId) == "string" then
		record = existing
	else
		local reserved, code, serverId = pcall(TeleportService.ReserveServer, TeleportService, PlaceConfig.IslandPlaceId)
		if not reserved then
			return nil, "could not reserve a server: " .. tostring(code)
		end

		local wrote, result = withRetry(function()
			local kept = nil
			dataStore:UpdateAsync(key, function(old)
				if type(old) == "table" and type(old.code) == "string" and type(old.serverId) == "string" then
					kept = old
					return nil
				end
				kept = { code = code, serverId = serverId }
				return kept
			end)
			return kept
		end)
		if not wrote or type(result) ~= "table" then
			return nil, tostring(result)
		end
		record = result
	end

	--[[
		The reverse lookup the island server reads. Written every first time a
		session needs the code, not only when reserving: it never changes, so
		rewriting it is harmless, and it repairs a link whose first write failed
		- without which the island server could not tell whose island it is.
	]]
	local linked, linkError = withRetry(function()
		-- Island 1 stays a bare number, as every server reserved before islands
		-- had numbers recorded it.
		dataStore:SetAsync("server_" .. record.serverId, if slot > 1 then cacheKey else ownerUserId)
	end)
	if not linked then
		return nil, "could not record the island server: " .. tostring(linkError)
	end

	codeCache[cacheKey] = record.code
	return record.code
end

--[[
	For an island server: whose island it is, from its own PrivateServerId.

	Returns ownerUserId, slot - or nil, message, kind, where kind says which
	of two very different things went wrong:

	  "error"     the directory could not be read. Worth asking again.
	  "unlisted"  it was read, and has no entry for this server. Asking again
	              gives the same answer; IslandDirectory.confirmOwner is the
	              other way to find out.
]]
function IslandDirectory.ownerOfServer(privateServerId)
	if type(privateServerId) ~= "string" or privateServerId == "" then
		return nil, "not a reserved server", "unlisted"
	end

	local dataStore, storeError = getStore()
	if not dataStore then
		return nil, storeError, "error"
	end

	local ok, result = withRetry(function()
		return dataStore:GetAsync("server_" .. privateServerId)
	end)
	if not ok then
		return nil, result, "error"
	end

	-- A number for island 1; "<id>_<slot>" for any later one.
	if type(result) == "string" then
		local owner, slot = string.match(result, "^(%d+)_(%d+)$")
		if owner then
			return tonumber(owner), tonumber(slot)
		end
	end

	local owner = tonumber(result)
	if owner then
		return owner, 1
	end
	return nil, "this server has no entry in the island directory", "unlisted"
end

--[[
	The same question asked the other way round: is `privateServerId` the
	server reserved for island `slot` of `userId`?

	ownerOfServer reads the reverse link, "server_<id>", which is a second
	record written after the reservation and so can be missing when the
	reservation itself is fine. This reads the reservation, "owner_<id>", which
	is the record the access code came from in the first place. It is just as
	safe to trust: only this module writes it, on the server, and it names the
	one server that is that player's island.

	Returns true, false, or nil with a message when it could not be read. A
	confirmed owner has the missing reverse link written back, so the next
	start of this server finds it the quick way.
]]
function IslandDirectory.confirmOwner(privateServerId, userId, slot)
	slot = slot or 1
	if type(privateServerId) ~= "string" or privateServerId == "" or type(userId) ~= "number" then
		return false
	end

	local dataStore, storeError = getStore()
	if not dataStore then
		return nil, storeError
	end

	local suffix = if slot > 1 then "_" .. slot else ""
	local ok, record = withRetry(function()
		return dataStore:GetAsync("owner_" .. userId .. suffix)
	end)
	if not ok then
		return nil, record
	end

	if type(record) ~= "table" or record.serverId ~= privateServerId then
		return false
	end

	-- Best effort: the island is identified either way.
	pcall(function()
		dataStore:SetAsync("server_" .. privateServerId, if slot > 1 then tostring(userId) .. suffix else userId)
	end)
	return true
end

return IslandDirectory
