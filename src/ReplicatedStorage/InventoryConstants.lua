--[[
	InventoryConstants

	The shape of a player's bag, shared by the server's Inventory, the client's
	grid and CombatService's gear walk. The layout matches InventoryUI's rows:
	9 / 9 / 9 / 9 / 5 / 1, and then the bin.

	Slots 37-42 are gear. Nothing may be auto-deposited into them and only an
	item of the matching classification may be dragged in, which is what makes
	them mean something rather than being six more squares.

	SLOT 43 IS THE BIN, and it is a slot rather than a separate thing on
	purpose. Everything that already moves items between squares - the drag
	system, the swap remote, the render pass, the save format - works on slot
	indices, so the bin being one of them means it needs no parallel copy of any
	of that. What it needs instead is two rules, and only two:

	  nothing is ever auto-deposited into it (isGeneralSlot says no, which is
	  the same gate that keeps Add out of the gear slots);

	  an item dropped onto an OCCUPIED bin destroys what was there, rather than
	  swapping with it. That one lives in Inventory:SwapSlots, because it is a
	  fact about the slot and every path into the server goes through there.

	It takes no restriction, because anything may be thrown away.
]]

local InventoryConstants = {}

InventoryConstants.SlotCount = 43
InventoryConstants.HotbarSlots = 9

InventoryConstants.AccessoryRange = { first = 37, last = 41 }
InventoryConstants.ArmorRange = { first = 42, last = 42 }
InventoryConstants.BinSlot = 43

-- The classification a slot will accept, or nil for an ordinary slot.
function InventoryConstants.getSlotRestriction(slotIndex)
	if type(slotIndex) ~= "number" then
		return nil
	end

	local accessory = InventoryConstants.AccessoryRange
	if slotIndex >= accessory.first and slotIndex <= accessory.last then
		return "Accessory"
	end

	local armor = InventoryConstants.ArmorRange
	if slotIndex >= armor.first and slotIndex <= armor.last then
		return "Armor"
	end

	return nil
end

function InventoryConstants.isBinSlot(slotIndex)
	return slotIndex == InventoryConstants.BinSlot
end

--[[
	True for the ordinary storage slots: the ones Add is allowed to fill.

	The bin is excluded even though it carries no restriction, and that is the
	whole of what stops a pickup, a harvest or a repaired save quietly landing
	in it. A square whose contents the next drop destroys is not somewhere the
	game may put things on a player's behalf.
]]
function InventoryConstants.isGeneralSlot(slotIndex)
	return InventoryConstants.getSlotRestriction(slotIndex) == nil
		and not InventoryConstants.isBinSlot(slotIndex)
end

return InventoryConstants
