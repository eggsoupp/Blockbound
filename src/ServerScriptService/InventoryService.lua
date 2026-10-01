--[[
	InventoryService

	The live Inventory for each connected player, and the operations other server
	systems need. This is the ONLY supported way for a server script to touch a
	player's inventory: mining, placement and crafting all go through here, so
	one place saves and re-syncs after a change instead of three that each
	half-remember to.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inventoryUpdate = remotes:WaitForChild("InventoryChanged")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local InventoryService = {}

local playerInventories = {}

-- What each client currently believes, held as two flat arrays rather than a
-- copy of the slot tables: a diff is then two comparisons per slot and
-- allocates nothing unless something actually moved.
local sentName = {}
local sentCount = {}

-- Players whose inventory is still being fetched from the DataStore. See
-- AddItemByName for why this matters.
local loadingPlayers = {}
local pendingAdds = {}

-- Called after every mutation so the persistence layer knows this player has
-- unsaved changes. Kept as a plain hook rather than a require so this module
-- stays dependency-free and unit-testable.
local changeListener = nil

local function swarn(...)
	warn("[InventoryService]", ...)
end

-- Called with (player) after every change. Deliberately only one: a second
-- subscriber would mean something other than persistence is reacting to writes.
function InventoryService.SetChangeListener(listener)
	changeListener = listener
end

-- Anything granted between here and Register is buffered rather than lost.
function InventoryService.BeginLoading(player)
	if not player then
		return
	end
	loadingPlayers[player] = true
	pendingAdds[player] = {}
end

function InventoryService.IsLoading(player)
	return loadingPlayers[player] == true
end

function InventoryService.Register(player, inventoryInstance)
	if not player or not inventoryInstance then
		return
	end

	playerInventories[player] = inventoryInstance
	loadingPlayers[player] = nil

	-- A different bag than whatever this client was last told about, so drop
	-- the baseline and let the next sync be a full one.
	sentName[player] = nil
	sentCount[player] = nil

	-- Drain anything the player earned while their save was in flight. This runs
	-- exactly once per session, on a freshly loaded inventory, so it can add
	-- items but can never duplicate them.
	local queued = pendingAdds[player]
	pendingAdds[player] = nil

	local applied = 0
	if queued then
		for _, entry in ipairs(queued) do
			local ok = inventoryInstance:Add(entry.name, entry.amount)
			if ok then
				applied += 1
			else
				swarn(string.format(
					"No room for queued %d x %s for %s; it was dropped.",
					entry.amount, entry.name, player.Name
				))
			end
		end
	end

	-- Lets the caller decide whether the freshly loaded inventory already
	-- differs from what is in the DataStore.
	return applied
end

function InventoryService.Unregister(player)
	playerInventories[player] = nil
	loadingPlayers[player] = nil
	pendingAdds[player] = nil
	sentName[player] = nil
	sentCount[player] = nil
end

-- The whole bag, recorded as the new baseline. First sync of a session and
-- explicit RequestFullInventory; everything after is a delta against it.
function InventoryService.SyncFull(player)
	local inv = playerInventories[player]
	if not inv then
		return
	end

	local slots = inv:GetAll()
	local names = {}
	local counts = {}

	for index = 1, #slots do
		local slot = slots[index]
		names[index] = slot and slot.name or nil
		counts[index] = slot and slot.count or 0
	end

	sentName[player] = names
	sentCount[player] = counts

	pcall(function()
		inventoryUpdate:FireClient(player, "full", slots)
	end)
end

-- Only the slots that differ. An ordinary change costs one slot on the wire
-- rather than forty-two, and a call that changed nothing costs nothing - which
-- matters because every entry point below ends in a sync, refusals included.
function InventoryService.SyncDelta(player)
	local inv = playerInventories[player]
	if not inv then
		return
	end

	local names = sentName[player]
	local counts = sentCount[player]
	if not names or not counts then
		-- This client has no baseline to diff against yet.
		InventoryService.SyncFull(player)
		return
	end

	local slots = inv:GetAll()
	local changes = nil

	for index = 1, #slots do
		local slot = slots[index]
		local name = slot and slot.name or nil
		local count = slot and slot.count or 0

		if names[index] ~= name or counts[index] ~= count then
			names[index] = name
			counts[index] = count

			if not changes then
				changes = {}
			end
			changes[#changes + 1] = { s = index, n = name, c = count }
		end
	end

	if not changes then
		return
	end

	pcall(function()
		inventoryUpdate:FireClient(player, "delta", changes)
	end)
end

function InventoryService.GetInventory(player)
	return playerInventories[player]
end

-- Flags the inventory dirty and pushes the authoritative delta. Every mutating
-- call below ends here, so the client never has to guess and cannot drift.
function InventoryService.SaveAndSync(player)
	local inv = playerInventories[player]
	if not inv then
		return
	end

	if changeListener then
		local ok, err = pcall(changeListener, player)
		if not ok then
			swarn("Change listener errored for", player.Name, err)
		end
	end

	InventoryService.SyncDelta(player)
end

--[[
	Grants items. True only if the whole amount landed.

	A grant made before the inventory has arrived from the DataStore is QUEUED
	rather than refused. That window is short but real, and refusing in it would
	cost the player something they had already earned. Queued grants are applied
	exactly once, in Register.
]]
function InventoryService.AddItemByName(player, itemName, amount)
	local inv = playerInventories[player]

	if not inv then
		local queue = pendingAdds[player]
		if loadingPlayers[player] and queue then
			-- Validated here rather than on flush, so a caller passing a bogus
			-- item still gets an honest answer instead of a delayed warning.
			if not ItemDefinitions[itemName] then
				return false, "Invalid item"
			end
			if type(amount) ~= "number" or amount <= 0 then
				amount = 1
			end

			table.insert(queue, { name = itemName, amount = math.floor(amount) })
			return true
		end
		return false, "No inventory"
	end

	local ok, reason = inv:Add(itemName, amount or 1)
	InventoryService.SaveAndSync(player)
	return ok == true, reason
end

--[[
	Would AddItemByName succeed in full, without changing anything?

	For callers that destroy something before they pay out - mining a block,
	felling a tree - so they can refuse up front rather than deleting the world
	and then finding there was nowhere to put the drop.

	A player whose save is still in flight answers yes: the grant would be
	queued rather than refused, so the room question is not settled yet.
]]
function InventoryService.CanAddItem(player, itemName, amount)
	local inv = playerInventories[player]
	if not inv then
		if loadingPlayers[player] then
			return ItemDefinitions[itemName] ~= nil
		end
		return false, "No inventory"
	end

	return inv:CanAdd(itemName, amount or 1)
end

--[[
	Takes items. All-or-nothing: nothing is consumed unless the full amount was
	there (see Inventory:Remove).
]]
function InventoryService.RemoveItemByName(player, itemName, amount)
	local inv = playerInventories[player]
	if not inv then
		return false, "No inventory"
	end

	local ok, reason = inv:Remove(itemName, amount or 1)
	InventoryService.SaveAndSync(player)
	return ok == true, reason
end

-- itemName, count - nil and 0 for an empty or invalid slot.
function InventoryService.GetSlot(player, slotIndex)
	local inv = playerInventories[player]
	if not inv or type(slotIndex) ~= "number" then
		return nil, 0
	end

	local slot = inv:GetAll()[math.floor(slotIndex)]
	if not slot or not slot.name then
		return nil, 0
	end

	return slot.name, slot.count or 0
end

return InventoryService
