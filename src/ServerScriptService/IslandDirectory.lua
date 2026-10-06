--[[
	IslandDirectory

	Which private server is whose island.

		IslandDirectory.accessCodeFor(ownerUserId) -> accessCode?, err
		IslandDirectory.ownerOfServer(privateServerId) -> ownerUserId?, err

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
function IslandDirectory.accessCodeFor(ownerUserId)
	if codeCache[ownerUserId] then
		return codeCache[ownerUserId]
	end

	if PlaceConfig.IslandPlaceId == 0 then
		return nil, "the Island place ID is not set in PlaceConfig"
	end

	local dataStore, storeError = getStore()
	if not dataStore then
		return nil, storeError
	end

	local key = "owner_" .. ownerUserId

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
		dataStore:SetAsync("server_" .. record.serverId, ownerUserId)
	end)
	if not linked then
		return nil, "could not record the island server: " .. tostring(linkError)
	end

	codeCache[ownerUserId] = record.code
	return record.code
end

--[[
	For an island server: whose island it is, from its own PrivateServerId.
	nil when the server is not one this directory reserved.
]]
function IslandDirectory.ownerOfServer(privateServerId)
	if type(privateServerId) ~= "string" or privateServerId == "" then
		return nil, "not a reserved server"
	end

	local dataStore, storeError = getStore()
	if not dataStore then
		return nil, storeError
	end

	local ok, result = withRetry(function()
		return dataStore:GetAsync("server_" .. privateServerId)
	end)
	if not ok then
		return nil, result
	end

	return tonumber(result)
end

return IslandDirectory
