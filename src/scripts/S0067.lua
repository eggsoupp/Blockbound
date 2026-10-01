--[[
	InventoryMirror

	The client's copy of this player's bag, and the single place that
	understands the wire format.

	The server sends only the slots that moved; this applies them to a local
	copy and hands subscribers the whole snapshot plus the changed indices, so
	a consumer that can redraw one slot does not redraw forty-two.

	  InventoryMirror.get()          -> the whole bag, right now
	  InventoryMirror.onChanged(fn)  -> fn(snapshot, changedIndices); nil
	                                    indices means "redraw it all". Returns
	                                    a disconnect function.

	snapshot[i] = { name = string?, count = number }, matching the server's
	Inventory.data exactly. The table is REUSED between updates, so treat it as
	read-only; a consumer wanting to keep a copy has to make one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryMirror = {}

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InventoryChanged")

local snapshot = {}
local listeners = {}

-- First sync, an explicit RequestFullInventory, and the fallback for a payload
-- in an unrecognised shape.
local function applyFull(slots)
	table.clear(snapshot)

	if type(slots) ~= "table" then
		return
	end

	for index, slot in pairs(slots) do
		if type(index) == "number" and type(slot) == "table" then
			snapshot[index] = { name = slot.name, count = slot.count or 0 }
		end
	end
end

-- A list of { s = slotIndex, n = name, c = count }; a missing name means the
-- slot emptied. Returns the indices touched.
local function applyDelta(changes)
	if type(changes) ~= "table" then
		return nil
	end

	local touched = {}

	for _, change in ipairs(changes) do
		local index = change.s
		if type(index) == "number" then
			local slot = snapshot[index]
			if slot then
				slot.name = change.n
				slot.count = change.c or 0
			else
				snapshot[index] = { name = change.n, count = change.c or 0 }
			end
			touched[#touched + 1] = index
		end
	end

	return touched
end

local function notify(changedIndices)
	for _, listener in ipairs(listeners) do
		local ok, err = pcall(listener, snapshot, changedIndices)
		if not ok then
			warn("[InventoryMirror] listener errored:", err)
		end
	end
end

remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "full" then
		applyFull(payload)
		notify(nil)
	elseif kind == "delta" then
		notify(applyDelta(payload))
	else
		-- Older single-argument form: the whole bag arrived as the first
		-- argument with no tag. Treated as a full replace so a hand-authored
		-- script in the place file firing the original shape still works.
		applyFull(kind)
		notify(nil)
	end
end)

function InventoryMirror.get()
	return snapshot
end

-- Returns an unsubscribe function; a session-long consumer can ignore it.
function InventoryMirror.onChanged(listener)
	assert(type(listener) == "function", "[InventoryMirror] onChanged needs a function")

	listeners[#listeners + 1] = listener

	return function()
		for index, existing in ipairs(listeners) do
			if existing == listener then
				table.remove(listeners, index)
				return
			end
		end
	end
end

return InventoryMirror
