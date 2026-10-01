--[[
	InventoryClass

	One player's bag: pure data and the operations on it, with no knowledge of
	remotes, saving or the UI. InventoryService owns the live instances.

	  slot = { name = string?, count = number }   empty is name = nil, count = 0

	Every mutating operation is all-or-nothing. That matters most for Add and
	Remove: a partial success that still reports failure is how a caller ends up
	destroying items it thought it had put back.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConstants = require(ReplicatedStorage:WaitForChild("InventoryConstants"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local SLOTS = InventoryConstants.SlotCount
local DEFAULT_STACK = 64

local Inventory = {}
Inventory.__index = Inventory

local function maxStackOf(def)
	return (def and tonumber(def.maxStack)) or DEFAULT_STACK
end

local function emptySlot()
	return { name = nil, count = 0 }
end

local function normalise(slot)
	if not slot or not slot.name or (slot.count or 0) <= 0 then
		return emptySlot()
	end
	return slot
end

function Inventory.new(initialData)
	local data = table.create(SLOTS)
	for i = 1, SLOTS do
		data[i] = emptySlot()
	end

	if type(initialData) == "table" then
		for i = 1, math.min(#initialData, SLOTS) do
			local saved = initialData[i]
			if type(saved) == "table" then
				data[i] = normalise({ name = saved.name, count = tonumber(saved.count) or 0 })
			end
		end
	end

	return setmetatable({ data = data }, Inventory)
end

local function inRange(index)
	return type(index) == "number" and index % 1 == 0 and index >= 1 and index <= SLOTS
end

-- Whether `itemName` is allowed in `index`, given that slot's restriction.
local function slotAccepts(index, itemName)
	local restriction = InventoryConstants.getSlotRestriction(index)
	if not restriction then
		return true
	end
	if not itemName then
		return true
	end

	local def = ItemDefinitions[itemName]
	return def ~= nil and def.classification == restriction
end

--[[
	Moves the contents of one slot to another, or throws one away.

	THE BIN IS A SWAP THAT ONLY GOES ONE WAY. Dropping something onto an
	occupied bin destroys what was in it instead of sending it back where the
	new item came from - that is the whole feature, and it lives here rather
	than in the remote handler so that every route into the server obeys it,
	including one a modified client invents.

	Note which direction it applies to. Dragging OUT of the bin onto a full slot
	is an ordinary swap: the player asked to take something out, not to throw
	the other thing away, and nothing is destroyed. Only a drop ONTO the bin
	deletes, which is what makes "it is only gone once you put something else
	there" true.

	The third return is the item that was destroyed, so the caller can say so.
]]
function Inventory:SwapSlots(index1, index2)
	if not (inRange(index1) and inRange(index2)) then
		return false, "Invalid indices"
	end

	local item1 = self.data[index1]
	local item2 = self.data[index2]


	--[[
		Dropping ONTO the bin, with something to drop.

		The `item1.name` test is not politeness. Without it a client that asked
		to swap an EMPTY slot onto a full bin would destroy what was in there
		and put nothing in its place - the bin would empty itself on a request
		no honest client can make, and the one rule the player was promised
		would be broken by the one action they did not take.
	]]
	if
		InventoryConstants.isBinSlot(index2)
		and not InventoryConstants.isBinSlot(index1)
		and item1.name
	then
		local discarded = item2.name and { name = item2.name, count = item2.count } or nil

		self.data[index2] = normalise(item1)
		self.data[index1] = emptySlot()

		return true, "Binned", discarded
	end

	if not slotAccepts(index1, item2.name) then
		return false, "Item does not match slot restriction for slot " .. index1
	end
	if not slotAccepts(index2, item1.name) then
		return false, "Item does not match slot restriction for slot " .. index2
	end

	self.data[index1], self.data[index2] = normalise(item2), normalise(item1)
	return true, "Swap successful"
end

--[[
	Moves up to `amount` from one slot to another, merging stacks.

	Returns (true, transferred) or (false, reason). Non-stackable items only
	move into an empty slot; the caller wants SwapSlots for anything else.
]]
function Inventory:TransferStack(srcIndex, dstIndex, amount)
	if not (inRange(srcIndex) and inRange(dstIndex)) then
		return false, "Invalid indices"
	end
	if type(amount) ~= "number" or amount <= 0 then
		return false, "Invalid amount"
	end

	--[[
		Nothing MERGES into the bin.

		Transfer tops one stack up from another, which for the bin would mean
		dropping five stone onto ten stone leaves fifteen - the old ten kept,
		not destroyed. A drop onto the bin is always a replacement, so this
		refuses and the client sends a swap instead.
	]]
	if InventoryConstants.isBinSlot(dstIndex) then
		return false, "The bin does not stack"
	end

	local src = self.data[srcIndex]
	local dst = self.data[dstIndex]

	if not src.name or src.count <= 0 then
		return false, "Source slot empty"
	end

	if not slotAccepts(dstIndex, src.name) then
		return false, "Destination slot restriction prevents placing this item"
	end

	local def = ItemDefinitions[src.name]
	if not def then
		return false, "Invalid item definition for source item"
	end

	if dst.name and dst.name ~= src.name then
		return false, "Destination contains different item"
	end

	local maxStack = maxStackOf(def)
	if maxStack == 1 then
		if dst.name then
			return false, "Destination occupied; non-stackable items cannot be merged"
		end

		self.data[dstIndex] = { name = src.name, count = src.count }
		self.data[srcIndex] = emptySlot()
		return true, self.data[dstIndex].count
	end

	local dstCount = if dst.name then dst.count else 0
	local space = maxStack - dstCount
	if space <= 0 then
		return false, "Destination has no space"
	end

	local moved = math.min(space, src.count, amount)
	if moved <= 0 then
		return false, "Nothing to transfer"
	end

	local left = src.count - moved
	self.data[srcIndex] = if left > 0 then { name = src.name, count = left } else emptySlot()
	self.data[dstIndex] = { name = src.name, count = dstCount + moved }

	return true, moved
end

-- How many of an item the player is holding, across every slot.
function Inventory:Count(itemName)
	if not itemName then
		return 0
	end

	local total = 0
	for i = 1, SLOTS do
		local slot = self.data[i]
		if slot.name == itemName then
			total += slot.count
		end
	end
	return total
end

--[[
	Would Add succeed in full? Answers without touching anything, so callers
	that must be all-or-nothing - crafting, and mining before it destroys the
	block - can check before committing.

	Gear slots are not counted: Add never fills them, so neither may this.
]]
function Inventory:CanAdd(itemName, amount)
	local def = ItemDefinitions[itemName]
	if not def then
		return false, "Invalid item"
	end
	if type(amount) ~= "number" or amount <= 0 then
		return false, "Invalid amount"
	end

	local stackSize = maxStackOf(def)
	local room = 0

	for i = 1, SLOTS do
		if InventoryConstants.isGeneralSlot(i) then
			local slot = self.data[i]
			if not slot.name then
				room += stackSize
			elseif slot.name == itemName then
				room += math.max(0, stackSize - slot.count)
			end

			if room >= amount then
				return true
			end
		end
	end

	return false, "No space in inventory"
end

--[[
	Places as much of `amount` as will fit and returns how many landed, topping
	up existing stacks before opening a new one.

	The partial version, for the one caller that wants it: repairing a corrupt
	save, where restoring some of an over-stacked slot beats restoring none.
	Everything else wants Add.
]]
function Inventory:AddUpTo(itemName, amount)
	if not ItemDefinitions[itemName] then
		return 0
	end
	if type(amount) ~= "number" or amount <= 0 then
		return 0
	end

	local stackSize = maxStackOf(ItemDefinitions[itemName])
	local remaining = math.floor(amount)
	local placed = 0

	for i = 1, SLOTS do
		if InventoryConstants.isGeneralSlot(i) then
			local slot = self.data[i]
			if slot.name == itemName and slot.count < stackSize then
				local toAdd = math.min(remaining, stackSize - slot.count)
				slot.count += toAdd
				remaining -= toAdd
				placed += toAdd
				if remaining <= 0 then
					return placed
				end
			end
		end
	end

	for i = 1, SLOTS do
		if InventoryConstants.isGeneralSlot(i) then
			local slot = self.data[i]
			if not slot.name then
				local toPut = math.min(remaining, stackSize)
				self.data[i] = { name = itemName, count = toPut }
				remaining -= toPut
				placed += toPut
				if remaining <= 0 then
					return placed
				end
			end
		end
	end

	return placed
end

--[[
	Grants items into the ordinary storage slots.

	All-or-nothing: nothing is written unless the whole amount fits. The
	previous version filled what it could and then reported failure, so a caller
	told "no room" had in fact already been given part of the stack.
]]
function Inventory:Add(itemName, amount)
	if not ItemDefinitions[itemName] then
		return false, "Invalid item"
	end
	if type(amount) ~= "number" or amount <= 0 then
		return false, "Invalid amount"
	end

	amount = math.floor(amount)

	local fits, reason = self:CanAdd(itemName, amount)
	if not fits then
		return false, reason
	end

	self:AddUpTo(itemName, amount)
	return true
end

--[[
	Takes items. Counts first, then removes, so a short bag consumes nothing -
	the previous version emptied slots as it walked and only discovered it was
	short at the end, destroying what it had already taken.
]]
function Inventory:Remove(itemName, amount)
	if not ItemDefinitions[itemName] then
		return false, "Invalid item"
	end
	if type(amount) ~= "number" or amount <= 0 then
		return false, "Invalid amount"
	end

	if self:Count(itemName) < amount then
		return false, "Not enough items"
	end

	local remaining = amount
	for i = 1, SLOTS do
		local slot = self.data[i]
		if slot.name == itemName then
			if slot.count > remaining then
				slot.count -= remaining
				return true
			end

			remaining -= slot.count
			self.data[i] = emptySlot()
			if remaining <= 0 then
				return true
			end
		end
	end

	return true
end

function Inventory:GetAll()
	return self.data
end

function Inventory:ToJSON()
	return HttpService:JSONEncode(self.data)
end

function Inventory.FromJSON(json)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if ok and type(data) == "table" then
		return Inventory.new(data)
	end
	return nil
end

return Inventory
