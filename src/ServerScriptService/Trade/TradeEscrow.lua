--[[
	TradeEscrow

	What a player has put into a trade, and what they are owed out of one -
	held as part of THEIR OWN save, so it survives anything that happens to
	the server.

		TradeEscrow.canTrade(player)                    -> ok, why
		TradeEscrow.count(player, kind, name)           -> how many they could offer
		TradeEscrow.check(player, give, get)            -> ok, why   (changes nothing)
		TradeEscrow.hold(player, tradeId, give, get, partnerUserId) -> ok
		TradeEscrow.settle(player, tradeId, committed)  -> whether it was pending
		TradeEscrow.orphan(tradeId)                     hand a stuck trade to recovery

	GOODS are plain data, the same shape everywhere:

		{ items = { { n = "Wood", c = 12 }, ... }, aspects = { "Ember", "Ember" },
		  permanent = { "Storm" } }

	`aspects` are stored one-use copies; `permanent` are UNREDEEMED permanent
	passes, one entry each (see TradeConfig for how a Game Pass purchase can
	change hands). `items` is kept in the format for saves already written,
	though bag items are not tradable (TradeConfig.ItemsTradable).

	THE "trades" SECTION of the player's InventoryStore record:

		pending[tradeId] = { give = goods, get = goods, partner = userId, at = time }
		owed             = goods

	`hold` takes `give` out of the bag and aspect storage and writes the
	pending entry in the same breath - no yield between, so no save can ever
	see the goods in both places or in neither. From then on the record itself
	says "these left for trade X; if X happened I am owed `get`, otherwise I
	get `give` back". `settle` turns the entry into `owed` once TradeLedger has
	said which, and `owed` is poured into the bag and storage as room allows.

	A pending entry is only ever settled by what TradeLedger says (or by the
	server that created it, before it has asked the ledger to commit - see
	TradeSettlement). That is what makes the two halves of a trade agree.

	RECOVERY

	A record that loads with pending entries was cut off mid-trade: the server
	died, or the player left while it was settling. Nobody is running those
	trades any more, so each one is put to the ledger as "aborted" - first
	writer wins - and settled by whatever the ledger answers. If the ledger
	cannot be reached the goods stay held and it is asked again every
	RETRY_SECONDS. A player with anything still pending cannot start another
	trade.

	`owed` outlives the trade: goods that did not fit (the bag filled while the
	trade was saving) wait here, in the save, and are delivered when there is
	room. Nothing is ever dropped to make a trade fit.

	State is weak-keyed by player and NOT cleared on PlayerRemoving: the leave
	save reads this section after other scripts' handlers have run (see the
	note in AbilityLoadout).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TradeConfig = require(Shared:WaitForChild("Trade"):WaitForChild("TradeConfig"))
local AspectConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AspectConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local Inventory = require(ServerScriptService:WaitForChild("InventoryClass"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local AbilityLoadout = require(ServerScriptService:WaitForChild("AbilityLoadout"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local TradeLedger = require(script.Parent:WaitForChild("TradeLedger"))

local TradeEscrow = {}

-- How often stuck trades are put to the ledger again and waiting goods are
-- offered to the bag again.
local RETRY_SECONDS = 15

-- Between two "your goods are waiting for room" reminders to one player.
local REMIND_SECONDS = 60

-- player -> { pending = { [tradeId] = entry }, owed = goods }
local records = setmetatable({}, { __mode = "k" })

-- True once the section has loaded from a real record. Cleared on leave.
local loaded = {}

-- Trades a TradeSettlement on THIS server is running right now. Recovery
-- keeps its hands off them: asking the ledger to abort a trade that is about
-- to commit would be consistent, but it would also be wrong.
local live = {}

local recovering = {}
local lastReminder = setmetatable({}, { __mode = "k" })

local function emptyGoods()
	return { items = {}, aspects = {}, permanent = {} }
end

-- A copy holding only what the format allows. Names are NOT checked against
-- the game's current item list: goods nobody recognises today are kept, not
-- destroyed, in case the item comes back.
local function cleanGoods(value)
	local goods = emptyGoods()
	if type(value) ~= "table" then
		return goods
	end
	if type(value.items) == "table" then
		for _, entry in ipairs(value.items) do
			if type(entry) == "table" and type(entry.n) == "string" then
				local count = math.floor(tonumber(entry.c) or 0)
				if count > 0 then
					table.insert(goods.items, { n = entry.n, c = count })
				end
			end
		end
	end
	if type(value.aspects) == "table" then
		for _, name in ipairs(value.aspects) do
			if type(name) == "string" then
				table.insert(goods.aspects, name)
			end
		end
	end
	-- Absent from saves written before permanent aspects could be traded.
	if type(value.permanent) == "table" then
		for _, name in ipairs(value.permanent) do
			if type(name) == "string" then
				table.insert(goods.permanent, name)
			end
		end
	end
	return goods
end

local function isEmpty(goods): boolean
	return #goods.items == 0 and #goods.aspects == 0 and #goods.permanent == 0
end

local function recordFor(player)
	local record = records[player]
	if not record then
		record = { pending = {}, owed = emptyGoods() }
		records[player] = record
	end
	return record
end

-- ---------------------------------------------------------------------------
-- The section
-- ---------------------------------------------------------------------------

InventoryStore.registerSection("trades", function(player)
	local record = records[player]
	if not record or (next(record.pending) == nil and isEmpty(record.owed)) then
		return nil
	end

	local pending = {}
	for tradeId, entry in pairs(record.pending) do
		pending[tradeId] = {
			give = cleanGoods(entry.give),
			get = cleanGoods(entry.get),
			partner = entry.partner,
			at = entry.at,
		}
	end
	return { pending = pending, owed = cleanGoods(record.owed) }
end, function(player, value)
	local record = { pending = {}, owed = emptyGoods() }

	if type(value) == "table" then
		record.owed = cleanGoods(value.owed)
		if type(value.pending) == "table" then
			for tradeId, entry in pairs(value.pending) do
				if type(tradeId) == "string" and type(entry) == "table" then
					record.pending[tradeId] = {
						give = cleanGoods(entry.give),
						get = cleanGoods(entry.get),
						partner = tonumber(entry.partner),
						at = tonumber(entry.at),
					}
				end
			end
		end
	end

	records[player] = record
	loaded[player] = true
end)

-- ---------------------------------------------------------------------------
-- Delivering what is owed
-- ---------------------------------------------------------------------------

-- Whether goods can be moved in or out of this player right now.
local function reachable(player): boolean
	return loaded[player] == true
		and player.Parent ~= nil
		and InventoryService.GetInventory(player) ~= nil
		and not InventoryService.IsLoading(player)
		and AbilityLoadout.isReady(player)
end

--[[
	Pours `owed` into the bag and aspect storage, as much as fits. Whatever
	does not stays owed, in the save, for the next try.

	Aspects arrive the way a wish does (storage may overflow its bought slots):
	the trade was checked for room before it began, and an aspect that has
	already changed hands must never be stuck for want of a slot.
]]
local function flush(player)
	local record = records[player]
	if not record or isEmpty(record.owed) or not reachable(player) then
		return
	end

	local inventory = InventoryService.GetInventory(player)
	local moved = false

	local items = record.owed.items
	for index = #items, 1, -1 do
		local entry = items[index]
		local placed = inventory:AddUpTo(entry.n, entry.c)
		if placed > 0 then
			moved = true
			entry.c -= placed
			if entry.c <= 0 then
				table.remove(items, index)
			end
		end
	end

	local aspects = record.owed.aspects
	for index = #aspects, 1, -1 do
		if AbilityLoadout.grantAspect(player, aspects[index], "trade", true) then
			moved = true
			table.remove(aspects, index)
		end
	end

	-- Permanent passes arrive unredeemed, exactly as they left: the receiver
	-- decides whether to redeem one or trade it on.
	local permanent = record.owed.permanent
	for index = #permanent, 1, -1 do
		if AbilityLoadout.addPass(player, permanent[index]) then
			moved = true
			table.remove(permanent, index)
		end
	end

	if moved then
		-- Marks the record dirty and sends the bag to the client.
		InventoryService.SaveAndSync(player)
		InventoryStore.markDirty(player)
	end

	if not isEmpty(record.owed) then
		local now = os.clock()
		if now - (lastReminder[player] or -REMIND_SECONDS) >= REMIND_SECONDS then
			lastReminder[player] = now
			CommandFeedback.tell(
				player,
				"Some of your trade is waiting for room. Free up space in your bag and it will arrive.",
				"bad"
			)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function TradeEscrow.canTrade(player): (boolean, string?)
	if InventoryStore.isReadOnly(player) then
		-- Nothing a read-only session does is kept, so a trade from one would
		-- hand over goods that are still in its real save.
		return false, "not saving this session"
	end
	if not reachable(player) then
		return false, "still loading"
	end
	local record = recordFor(player)
	if next(record.pending) ~= nil then
		return false, "finishing an earlier trade"
	end
	if not isEmpty(record.owed) then
		return false, "waiting for room for an earlier trade"
	end
	return true
end

-- How many of something a player could put up: bag items by name, or STORED
-- copies of an aspect. Permanent aspects and the one in use never count.
function TradeEscrow.count(player, kind: string, name: string): number
	if kind == "item" then
		local inventory = InventoryService.GetInventory(player)
		if not inventory or not TradeConfig.itemTradable(name) then
			return 0
		end
		return inventory:Count(name)
	elseif kind == "aspect" then
		if not TradeConfig.aspectTradable(name) then
			return 0
		end
		local count = 0
		for _, stored in ipairs(AbilityLoadout.stored(player)) do
			if stored == name then
				count += 1
			end
		end
		return count
	elseif kind == "permanent" then
		-- UNREDEEMED permanent passes only. A redeemed one is the player's for
		-- good and is never counted here.
		return if TradeConfig.permanentTradable(name) then AbilityLoadout.passCount(player, name) else 0
	end
	return 0
end

--[[
	Could this player give `give` and then take `get`, right now? Changes
	nothing. The bag is tried out on a copy, so "room" means room after their
	own goods have left, counted exactly the way the real moves will count it.
]]
function TradeEscrow.check(player, give, get): (boolean, string?)
	local inventory = InventoryService.GetInventory(player)
	if not inventory then
		return false, "the bag is not loaded"
	end

	local trial = Inventory.new(inventory:GetAll())

	for _, entry in ipairs(give.items) do
		if not TradeConfig.itemTradable(entry.n) then
			return false, string.format("%s cannot be traded", entry.n)
		end
		if not trial:Remove(entry.n, entry.c) then
			local definition = ItemDefinitions[entry.n]
			return false, string.format("not enough %s", definition and definition.displayName or entry.n)
		end
	end

	for _, entry in ipairs(get.items) do
		if not trial:Add(entry.n, entry.c) then
			return false, "not enough room in the bag"
		end
	end

	for _, aspectName in ipairs(give.aspects) do
		if not TradeConfig.aspectTradable(aspectName) then
			return false, string.format("the %s aspect cannot be traded", AspectConfig.displayName(aspectName))
		end
	end

	local giving = {}
	for _, aspectName in ipairs(give.permanent) do
		if not TradeConfig.permanentTradable(aspectName) then
			return false, string.format("the permanent %s pass cannot be traded", AspectConfig.displayName(aspectName))
		end
		giving[aspectName] = (giving[aspectName] or 0) + 1
		if giving[aspectName] > AbilityLoadout.passCount(player, aspectName) then
			return false, string.format("no unredeemed permanent %s pass to give", AspectConfig.displayName(aspectName))
		end
	end

	return AbilityLoadout.canExchange(player, give.aspects, get.aspects)
end

--[[
	Takes `give` out of the player's bag and storage and records the trade as
	pending. Call only straight after a successful `check`, with no yield in
	between. Does not yield itself.

	If a removal fails anyway everything already taken is put back and false is
	returned, with the player exactly as they were.
]]
function TradeEscrow.hold(player, tradeId: string, give, get, partnerUserId: number): boolean
	local inventory = InventoryService.GetInventory(player)
	local record = recordFor(player)
	if not inventory or record.pending[tradeId] then
		return false
	end

	local takenItems, takenAspects, takenPermanent = {}, {}, {}
	local ok = true

	for _, entry in ipairs(give.items) do
		if inventory:Remove(entry.n, entry.c) then
			table.insert(takenItems, entry)
		else
			ok = false
			break
		end
	end

	if ok then
		for _, aspectName in ipairs(give.aspects) do
			if AbilityLoadout.unstore(player, aspectName) then
				table.insert(takenAspects, aspectName)
			else
				ok = false
				break
			end
		end
	end

	if ok then
		for _, aspectName in ipairs(give.permanent) do
			if AbilityLoadout.removePass(player, aspectName) then
				table.insert(takenPermanent, aspectName)
			else
				ok = false
				break
			end
		end
	end

	if not ok then
		for _, entry in ipairs(takenItems) do
			inventory:AddUpTo(entry.n, entry.c)
		end
		for _, aspectName in ipairs(takenAspects) do
			AbilityLoadout.grantAspect(player, aspectName, "trade", true)
		end
		for _, aspectName in ipairs(takenPermanent) do
			AbilityLoadout.addPass(player, aspectName)
		end
		InventoryService.SaveAndSync(player)
		return false
	end

	record.pending[tradeId] = {
		give = cleanGoods(give),
		get = cleanGoods(get),
		partner = partnerUserId,
		at = os.time(),
	}
	live[tradeId] = true

	InventoryService.SaveAndSync(player)
	InventoryStore.markDirty(player)
	return true
end

--[[
	Ends a pending trade for one player: with what they were promised if it
	committed, with their own goods back if it did not. Returns whether there
	was such a trade to end - a second call for the same one does nothing, so
	the live settlement and recovery can never both pay out.

	Works on a player who has already left: there is then nothing to deliver
	to, and the record they saved on the way out still lists the trade as
	pending, to be settled the same way when they next load it.
]]
function TradeEscrow.settle(player, tradeId: string, committed: boolean): boolean
	local record = records[player]
	local entry = record and record.pending[tradeId]
	if not entry then
		return false
	end

	record.pending[tradeId] = nil

	local goods = if committed then entry.get else entry.give
	for _, item in ipairs(goods.items) do
		table.insert(record.owed.items, { n = item.n, c = item.c })
	end
	for _, aspectName in ipairs(goods.aspects) do
		table.insert(record.owed.aspects, aspectName)
	end
	for _, aspectName in ipairs(goods.permanent) do
		table.insert(record.owed.permanent, aspectName)
	end

	InventoryStore.markDirty(player)
	flush(player)
	return true
end

-- A settlement that could not learn its trade's outcome gives it up here, and
-- recovery asks the ledger until it answers. Also called when one ends.
function TradeEscrow.orphan(tradeId: string)
	live[tradeId] = nil
end

-- What is held and owed for a player, as plain data, for looking at.
function TradeEscrow.describe(player)
	local record = records[player]
	if not record then
		return { loaded = false, pending = {}, owed = emptyGoods() }
	end
	local pending = {}
	for tradeId, entry in pairs(record.pending) do
		table.insert(pending, { id = tradeId, give = cleanGoods(entry.give), get = cleanGoods(entry.get), live = live[tradeId] == true })
	end
	return { loaded = loaded[player] == true, pending = pending, owed = cleanGoods(record.owed) }
end

-- ---------------------------------------------------------------------------
-- Recovery
-- ---------------------------------------------------------------------------

local function recover(player)
	if recovering[player] or not reachable(player) then
		return
	end
	local record = records[player]
	if not record then
		return
	end

	local ids = {}
	for tradeId in pairs(record.pending) do
		if not live[tradeId] then
			table.insert(ids, tradeId)
		end
	end
	if #ids == 0 then
		return
	end

	recovering[player] = true
	for _, tradeId in ipairs(ids) do
		-- Nobody is running this trade any more. If it never reached the
		-- ledger it did not happen, and this makes that final.
		local outcome = TradeLedger.decide(tradeId, "aborted")
		if not player.Parent then
			break
		end
		if outcome and TradeEscrow.settle(player, tradeId, outcome == "committed") then
			if outcome == "committed" then
				CommandFeedback.tell(player, "A trade that was interrupted went through. What you were owed has been delivered.", "good")
			else
				CommandFeedback.tell(player, "A trade that was interrupted did not go through. Your items are back.", "good")
			end
		end
	end
	recovering[player] = nil
end

task.spawn(function()
	while true do
		task.wait(RETRY_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			local record = records[player]
			if record and loaded[player] then
				if next(record.pending) ~= nil then
					task.spawn(recover, player)
				end
				if not isEmpty(record.owed) then
					local ok, err = pcall(flush, player)
					if not ok then
						warn("[TradeEscrow] delivery errored for", player.Name, err)
					end
				end
			end
		end
	end
end)

--[[
	The first look, as soon as a joining player's bag and storage are both up,
	rather than up to RETRY_SECONDS later: a player cut off mid-trade should
	find their goods waiting, not arriving.
]]
local function watch(player)
	task.spawn(function()
		local waited = 0
		while player.Parent and not reachable(player) and waited < 60 do
			task.wait(0.5)
			waited += 0.5
		end
		if player.Parent and reachable(player) then
			recover(player)
			pcall(flush, player)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end

Players.PlayerRemoving:Connect(function(player)
	-- Only the flags. The goods are read by the leave save; see the header.
	loaded[player] = nil
	recovering[player] = nil
end)

return TradeEscrow
