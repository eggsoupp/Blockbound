--[[
	ItemFeedback

	Says what the bag just gained or lost, in the feedback column.

		mine a block   ->  "+1 Stone"
		mine six more  ->  "+7 Stone"   (the same line, counting up)
		place one      ->  "+6 Stone"
		place six      ->  the line goes away

	IT WATCHES TOTALS, NOT SLOTS

	The mirror reports which SLOTS moved, and most slot movement is not a gain
	or a loss at all: dragging a stack between two slots touches two of them and
	changes nothing about what the player owns, and a pickup that tops up an
	existing stack and spills into a new one touches two and is one gain. So
	this keeps a count per ITEM and diffs that, which makes every one of those
	cases fall out correctly without being special-cased.

	It is also why the whole snapshot is walked on every change rather than only
	the indices handed over: a total is a sum over all slots, and there is no
	cheaper honest way to know a stack shrank than to add the others up. Forty-
	two slots on an event that fires when something moves is nothing.

	NOTHING IS SAID ABOUT THE FIRST SNAPSHOT

	Joining with a full bag is not forty gains. The first change establishes the
	baseline and reports nothing, exactly the way AbilityClient's loadout
	announcement skips the restore on join.

	THE COALESCING IS Shared.UI.Feedback's, NOT THIS FILE'S

	This reports deltas as they happen and does not care that mining sends a lot
	of them. Feedback.item is what turns a stream of "+1" into one line counting
	up; see the note there.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Feedback = require(Shared:WaitForChild("UI"):WaitForChild("Feedback"))
local InventoryMirror = require(Shared:WaitForChild("Inventory"):WaitForChild("InventoryMirror"))

-- itemName -> how many the bag held last time it was counted. nil until the
-- first snapshot arrives; see the note above.
local held = nil

local function countFrom(snapshot): { [string]: number }
	local totals = {}

	for _, slot in pairs(snapshot) do
		local name = slot and slot.name

		if type(name) == "string" and name ~= "" then
			totals[name] = (totals[name] or 0) + (tonumber(slot.count) or 0)
		end
	end

	return totals
end

InventoryMirror.onChanged(function(snapshot)
	local totals = countFrom(snapshot)

	if not held then
		held = totals
		return
	end

	--[[
		Both directions, in one pass over the union of the two tables.

		Walking only the new totals would miss an item that went to zero - the
		last of something dropped or crafted away - which is exactly the loss
		most worth reporting, because it is the one that empties a slot the
		player was relying on.
	]]
	for name, count in pairs(totals) do
		local before = held[name] or 0
		if count ~= before then
			Feedback.item(name, count - before)
		end
	end

	for name, before in pairs(held) do
		if totals[name] == nil and before ~= 0 then
			Feedback.item(name, -before)
		end
	end

	held = totals
end)
