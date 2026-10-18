--[[
	ChestServer

	Opens chests and moves things in and out of them. A chest is a storage
	station (StationConfig `storage`): StationService places it, picks it up,
	saves it with the island and keeps what is in it on its own record. This
	is the only thing that changes what is in it.

	PROTOCOL

	  ChestState    server -> client, to everyone with that chest open
	    { key, title, size, slots = { { s = slot, n = name, c = count }, ... } }
	    nil   - it closed: you walked off, it was picked up, you died

	  ChestRequest  client -> server
	    "move", fromSide, fromIndex, toSide, toIndex, amount?
	          a drag. Sides are "chest" and "bag". Onto an empty slot or the
	          same item it moves (up to a stack); onto a different item it
	          swaps, whole stacks only.
	    "quick", side, index
	          a click: the whole stack to the other side, merging first and
	          then filling empty slots, as much as fits.
	    "close"

	The chest is opened by its prompt, server side; a client never says
	which chest it means, so it cannot ask for one it is not standing at.
	While anybody has it open it shows its open model - the lid up - and
	shuts again when the last of them closes it (StationService.setOpen).

	EVERY MOVE IS CHECKED HERE, AND EVERY MOVE IS WHOLE

	The chest must still exist and be in reach; both slots must exist (the
	bag's ordinary slots only - not gear, not the bin); the item must be a
	real item and the stack no bigger than a stack. Where a move touches
	both sides it writes the side that can refuse first and puts it back if
	the second refuses, so nothing is ever in two places or in none.

	THE TWO SAVES MUST AGREE

	A chest is saved with the island; the bag is saved with the player. If
	one of those saves is working and the other is not, taking something out
	and leaving would duplicate it, and putting something in would lose it -
	so the chest refuses to change. When neither is saving (Studio with API
	access off) nothing persists at all and it works as normal.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local StationConfig = require(Shared:WaitForChild("Crafting"):WaitForChild("StationConfig"))
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))
local InventoryConstants = require(ReplicatedStorage:WaitForChild("InventoryConstants"))

local StationService = require(ServerScriptService:WaitForChild("StationService"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local InventoryClass = require(ServerScriptService:WaitForChild("InventoryClass"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

local ChestState = Remotes.ensure("ChestState", "RemoteEvent")
local ChestRequest = Remotes.ensure("ChestRequest", "RemoteEvent")

-- Studs past a chest's useRange before it closes on you: enough that
-- stepping back while sorting does not slam the lid.
local REACH_SLACK = 6

-- Seconds between requests from one player. Fast enough for a player
-- clicking through a full chest, too slow to be a flood.
local MIN_INTERVAL = 0.04

-- How often open chests are checked for being walked away from.
local WATCH_INTERVAL = 0.5

-- player -> the station record of the chest they have open.
local open: { [Player]: any } = {}
local lastRequest: { [Player]: number } = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character:FindFirstChild("HumanoidRootPart")
	end
	return nil
end

local function defOf(station)
	return StationConfig.get(station.stationId)
end

local function inReach(player: Player, station): boolean
	local root = livingRoot(player)
	local def = defOf(station)
	if not (root and def) then
		return false
	end
	return (root.Position - StationService.centreOf(station)).Magnitude <= def.useRange + REACH_SLACK
end

local function isIndex(value): boolean
	return type(value) == "number" and value == value and value % 1 == 0
end

-- What the chest holds, for the wire: a list, because a sparse table of
-- numbers does not survive a remote.
local function stateFor(station)
	local def = defOf(station)
	local slots = {}
	for slot, stack in pairs(station.items) do
		if stack.name and (stack.count or 0) > 0 then
			table.insert(slots, { s = slot, n = stack.name, c = stack.count })
		end
	end
	return {
		key = station.key,
		title = def.displayName or def.id,
		size = def.storage,
		slots = slots,
	}
end

-- Everyone looking into this chest sees it as it is now.
local function push(station)
	local state = stateFor(station)
	for player, viewed in pairs(open) do
		if viewed == station then
			ChestState:FireClient(player, state)
		end
	end
end

-- The lid is up while anybody at all is looking in, and down once the last
-- of them is gone. A chest with no open model ignores it.
local function updateLid(station)
	if not StationService.isLive(station) then
		return
	end
	local watched = false
	for _, viewed in pairs(open) do
		if viewed == station then
			watched = true
			break
		end
	end
	StationService.setOpen(station, watched)
end

local function close(player: Player)
	local station = open[player]
	if station then
		open[player] = nil
		ChestState:FireClient(player, nil)
		updateLid(station)
	end
end

-- Why the chest will not change right now, or nil. See the header.
local function saveProblem(player: Player): string?
	local bagSaving = not InventoryStore.isReadOnly(player)

	local chestSaving = false
	if PlaceConfig.isIsland() then
		local saving = workspace:GetAttribute("IslandSaving")
		if saving == nil then
			return "The island is still loading."
		end
		chestSaving = saving == true
	end

	if bagSaving ~= chestSaving then
		return "Your items can't be saved right now, so the chest is locked."
	end
	return nil
end

--[[
	A held tool whose item has just gone into a chest goes with it. The
	equip system hands out a copy of the item, tagged with its name, and
	nothing else would notice the original had left the bag.
]]
local function dropOrphanedTools(player: Player, inventory)
	for _, place in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
		if place then
			for _, child in ipairs(place:GetChildren()) do
				if child:IsA("Tool") then
					local name = child:GetAttribute("ItemName")
					if type(name) == "string" and inventory:Count(name) <= 0 then
						child:Destroy()
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Sides
-- ---------------------------------------------------------------------------

--[[
	A side is somewhere stacks sit: the open chest, or the player's bag. Each
	answers the same four questions, so a move is written once for every
	direction - chest to bag, bag to chest, and within either.
]]
local function sideFor(player: Player, station, name)
	if name == "chest" then
		local size = defOf(station).storage
		return {
			name = "chest",
			valid = function(index)
				return isIndex(index) and index >= 1 and index <= size
			end,
			get = function(index)
				local stack = station.items[index]
				if stack then
					return stack.name, stack.count
				end
				return nil, 0
			end,
			set = function(index, item, count)
				station.items[index] = if item and count > 0 then { name = item, count = count } else nil
				return true
			end,
		}
	elseif name == "bag" then
		local inventory = InventoryService.GetInventory(player)
		if not inventory then
			return nil
		end
		return {
			name = "bag",
			inventory = inventory,
			valid = function(index)
				return isIndex(index) and index >= 1 and index <= InventoryConstants.SlotCount
					and InventoryConstants.isGeneralSlot(index)
			end,
			get = function(index)
				return inventory:GetSlot(index)
			end,
			set = function(index, item, count)
				return inventory:SetSlot(index, item, count)
			end,
		}
	end
	return nil
end

-- Writes two slots as one change: if the second refuses, the first is put
-- back as it was.
local function writeBoth(first, firstIndex, firstName, firstCount, second, secondIndex, secondName, secondCount)
	local oldName, oldCount = first.get(firstIndex)
	if not first.set(firstIndex, firstName, firstCount) then
		return false
	end
	if not second.set(secondIndex, secondName, secondCount) then
		first.set(firstIndex, oldName, oldCount)
		return false
	end
	return true
end

-- A drag from one slot to another. See the header.
local function move(from, fromIndex, to, toIndex, amount): boolean
	if from.name == to.name and fromIndex == toIndex then
		return false
	end

	local name, count = from.get(fromIndex)
	if not name or count <= 0 then
		return false
	end
	amount = if isIndex(amount) then math.clamp(amount, 1, count) else count

	local destName, destCount = to.get(toIndex)
	local stack = InventoryClass.MaxStack(name)

	-- The bag is the side that can refuse (SetSlot), so it is written first.
	local function commit(toName, toCount, fromName, fromCount)
		if to.name == "bag" or from.name == to.name then
			return writeBoth(to, toIndex, toName, toCount, from, fromIndex, fromName, fromCount)
		end
		return writeBoth(from, fromIndex, fromName, fromCount, to, toIndex, toName, toCount)
	end

	if not destName then
		local moved = math.min(amount, stack)
		return commit(name, moved, name, count - moved)
	elseif destName == name then
		local moved = math.min(amount, stack - destCount)
		if moved <= 0 then
			return false
		end
		return commit(name, destCount + moved, name, count - moved)
	elseif amount == count then
		return commit(name, count, destName, destCount)
	end
	return false
end

-- A click: the whole stack to the other side, as much as fits.
local function quick(player: Player, station, from, index): (boolean, number)
	local name, count = from.get(index)
	if not name or count <= 0 then
		return false, 0
	end

	local remaining = count
	if from.name == "chest" then
		local inventory = InventoryService.GetInventory(player)
		if not inventory then
			return false, 0
		end
		-- Merges into stacks already in the bag, then fills empty ordinary
		-- slots; it never touches gear or the bin. Unknown items place none.
		remaining -= inventory:AddUpTo(name, count)
	else
		local size = defOf(station).storage
		local stack = InventoryClass.MaxStack(name)
		local items = station.items
		for pass = 1, 2 do
			for slot = 1, size do
				if remaining <= 0 then
					break
				end
				local held = items[slot]
				if pass == 1 and held and held.name == name and held.count < stack then
					local moved = math.min(remaining, stack - held.count)
					held.count += moved
					remaining -= moved
				elseif pass == 2 and not held then
					local moved = math.min(remaining, stack)
					items[slot] = { name = name, count = moved }
					remaining -= moved
				end
			end
		end
	end

	if remaining == count then
		return false, 0
	end
	from.set(index, name, remaining)
	return true, count - remaining
end

-- ---------------------------------------------------------------------------
-- Opening
-- ---------------------------------------------------------------------------

local function openFor(player: Player, station)
	if not StationService.isLive(station) or type(station.items) ~= "table" then
		return
	end
	if not inReach(player, station) then
		return
	end
	if open[player] and open[player] ~= station then
		close(player)
	end
	open[player] = station
	updateLid(station)
	ChestState:FireClient(player, stateFor(station))
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if type(prompt:GetAttribute("StorageId")) ~= "string" then
		return
	end
	local station = StationService.fromInstance(prompt.Parent)
	if station then
		openFor(player, station)
	end
end)

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------

local function handle(player: Player, action, a, b, c, d, e)
	if action == "close" then
		close(player)
		return
	end

	local station = open[player]
	if not station then
		return
	end
	if not StationService.isLive(station) or not inReach(player, station) then
		close(player)
		return
	end

	local problem = saveProblem(player)
	if problem then
		CommandFeedback.tell(player, problem, "bad")
		ChestState:FireClient(player, stateFor(station))
		return
	end

	local changed = false
	local bagTouched = false

	if action == "move" then
		local from, to = sideFor(player, station, a), sideFor(player, station, c)
		if from and to and from.valid(b) and to.valid(d) then
			changed = move(from, b, to, d, e)
			bagTouched = from.name == "bag" or to.name == "bag"
		end
	elseif action == "quick" then
		local from = sideFor(player, station, a)
		if from and from.valid(b) then
			local moved = quick(player, station, from, b)
			changed = moved
			bagTouched = moved
			if not moved then
				CommandFeedback.tell(player, if a == "chest" then "Your bag is full." else "The chest is full.", "bad")
			end
		end
	end

	if changed and bagTouched then
		InventoryService.SaveAndSync(player)
		local inventory = InventoryService.GetInventory(player)
		if inventory then
			dropOrphanedTools(player, inventory)
		end
	end

	if changed then
		StationService.markChanged()
		push(station)
	else
		-- Answered anyway, so a client that guessed wrong redraws the truth.
		ChestState:FireClient(player, stateFor(station))
	end
end

ChestRequest.OnServerEvent:Connect(function(player, action, a, b, c, d, e)
	local now = os.clock()
	if now - (lastRequest[player] or -1) < MIN_INTERVAL then
		return
	end
	lastRequest[player] = now

	local ok, err = pcall(handle, player, action, a, b, c, d, e)
	if not ok then
		warn("[ChestServer] request failed:", err)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local station = open[player]
	open[player] = nil
	lastRequest[player] = nil
	if station then
		updateLid(station)
	end
end)

-- Walked off, died, or the chest was picked up: the window closes, and the
-- lid with it once nobody else is looking.
task.spawn(function()
	while true do
		task.wait(WATCH_INTERVAL)
		for player, station in pairs(open) do
			if not player.Parent then
				open[player] = nil
				updateLid(station)
			elseif not StationService.isLive(station) or not inReach(player, station) then
				close(player)
			end
		end
	end
end)
