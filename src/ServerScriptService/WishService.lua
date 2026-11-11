--[[
	WishService

	The Starfall banner, server side: Wish Stars, the rolls, the pity, and the
	grants. Shared.Wish.WishConfig holds every number.

		WishService.award(player, stars, why)   -- give Wish Stars, with a toast
		WishService.state(player)               -- the client's view, or nil

	A WISH, START TO FINISH

	The client invokes WishPull with 1 or 10. Everything is checked here - the
	save has loaded and can be written, storage can take what comes out, the
	player has the stars - then the stars are taken, each wish rolls an ASPECT
	and is granted through AbilityLoadout.grantWished, and the results go back in the
	reply for the reveal to play. Nothing the client says picks a result.

	The results are granted BEFORE the reply is sent, so a client that drops
	the reply, closes the game during the meteor or skips the reveal has still
	got exactly what it rolled.

	SAVED IN THE ONE RECORD

	A section of InventoryStore's record, like the loadout, so it shares its
	session lock and autosave: { stars, sinceLegendary, sinceEpic, wishes,
	welcomed, lastDaily, receipts, history }. A Robux purchase saves before it
	is confirmed (see Purchases), the same way ability storage does.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AspectConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AspectConfig"))
local WishConfig = require(Shared:WaitForChild("Wish"):WaitForChild("WishConfig"))

local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local AbilityLoadout = require(ServerScriptService:WaitForChild("AbilityLoadout"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local Purchases = require(ServerScriptService:WaitForChild("Purchases"))
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))

local WishService = {}

local PullRemote = Remotes.ensure("WishPull", "RemoteFunction")
local StateRemote = Remotes.ensure("WishState", "RemoteEvent")
local BuyRemote = Remotes.ensure("WishBuy", "RemoteEvent")

local MarketplaceService = game:GetService("MarketplaceService")

-- The most stars a save can hold, so a bug or exploit cannot write a number
-- that breaks the record.
local MAX_STARS = 100000
-- Recent wishes kept for the banner's history line.
local HISTORY_KEPT = 20
local RECEIPTS_KEPT = 20
-- The shortest gap between two pulls: the reveal takes longer than this.
local PULL_COOLDOWN = 1.0

local random = Random.new()

--[[
	player -> record. Weak-keyed and never cleared on PlayerRemoving, for the
	reason AbilityLoadout gives: the leave save reads it after scripts' own
	PlayerRemoving handlers may already have run.
]]
local records = setmetatable({}, { __mode = "k" })
local busy = {}
local lastPull = {}

-- Every aspect by rarity, built once: the pool each tier draws from.
local pools = {}
do
	local excluded = {}
	for _, name in ipairs(WishConfig.Excluded) do
		excluded[name] = true
	end
	for _, name in ipairs(AspectConfig.names()) do
		local definition = AspectConfig.get(name)
		local rarity = definition.rarity or "Common"
		if not excluded[name] and WishConfig.Stars[rarity] then
			pools[rarity] = pools[rarity] or {}
			table.insert(pools[rarity], name)
		end
	end
end

local function dayNumber(): number
	return math.floor(os.time() / 86400)
end

local function clampStars(value): number
	return math.clamp(math.floor(tonumber(value) or 0), 0, MAX_STARS)
end

function WishService.state(player)
	local record = records[player]
	if not record then
		return nil
	end
	local products = {}
	for _, product in ipairs(WishConfig.Products) do
		if product.id > 0 then
			table.insert(products, { id = product.id, stars = product.stars, label = product.label })
		end
	end
	return {
		stars = record.stars,
		sinceLegendary = record.sinceLegendary,
		sinceEpic = record.sinceEpic,
		wishes = record.wishes,
		history = table.clone(record.history),
		products = products,
	}
end

local function push(player)
	local state = WishService.state(player)
	if state and player.Parent then
		StateRemote:FireClient(player, state)
	end
end

--[[
	Gives Wish Stars and says so. `why` finishes the toast: "+2 Wish Stars -
	quest complete". Ignored before the save has loaded - there is nothing to
	add them to that would be saved.
]]
function WishService.award(player: Player, stars: number, why: string?)
	local record = records[player]
	stars = math.floor(tonumber(stars) or 0)
	if not record or stars <= 0 then
		return false
	end
	record.stars = clampStars(record.stars + stars)
	InventoryStore.markDirty(player)
	push(player)
	CommandFeedback.tell(player, string.format(
		"+%d %s%s", stars, if stars == 1 then "Wish Star" else WishConfig.CurrencyName,
		if why then " - " .. why else ""
	), "good")
	return true
end

-- One roll: a rarity by the odds and pity, then an aspect of it.
local function rollOne(record): (string, string)
	local legendaryChance = WishConfig.legendaryChance(record.sinceLegendary)
	local epicDue = record.sinceEpic + 1 >= WishConfig.EpicPity

	local rarity
	local roll = random:NextNumber()
	if roll < legendaryChance then
		rarity = "Legendary"
	elseif epicDue then
		rarity = "Epic"
	else
		-- The rest of the range, in order; Common takes what is left.
		local edge = legendaryChance
		rarity = "Common"
		for _, tier in ipairs({ "Epic", "Rare", "Uncommon" }) do
			edge += WishConfig.Rates[tier]
			if roll < edge then
				rarity = tier
				break
			end
		end
	end

	-- A tier with nothing in it falls to the next one down that has something.
	local start = table.find(WishConfig.Tiers, rarity)
	local pool
	for index = start, #WishConfig.Tiers do
		pool = pools[WishConfig.Tiers[index]]
		if pool and #pool > 0 then
			rarity = WishConfig.Tiers[index]
			break
		end
	end

	if rarity == "Legendary" then
		record.sinceLegendary = 0
		record.sinceEpic = 0
	elseif rarity == "Epic" then
		record.sinceLegendary += 1
		record.sinceEpic = 0
	else
		record.sinceLegendary += 1
		record.sinceEpic += 1
	end

	return rarity, pool[random:NextInteger(1, #pool)]
end

local function pull(player: Player, count)
	if count ~= 1 and count ~= 10 then
		return { ok = false, message = "Choose one wish or ten." }
	end

	local record = records[player]
	if not record or InventoryService.IsLoading(player) or InventoryStore.isReadOnly(player) then
		return { ok = false, message = "Your save is not ready. Please try again." }
	end
	if not AbilityLoadout.canReceive(player) then
		return { ok = false, message = "Aspect storage is full or not loaded yet." }
	end

	local cost = count * WishConfig.Cost
	if record.stars < cost then
		return { ok = false, message = string.format("You need %d %s.", cost, WishConfig.CurrencyName), short = true }
	end

	record.stars -= cost
	local results = {}
	for _ = 1, count do
		local rarity, name = rollOne(record)
		local where, isNew = AbilityLoadout.grantWished(player, name)
		if not where then
			-- Storage filled up part way: hand back what was not rolled, so a
			-- full store costs nothing. The pity it advanced stays advanced.
			record.stars += (count - #results) * WishConfig.Cost
			break
		end
		record.wishes += 1
		table.insert(record.history, 1, { name = name, rarity = rarity })
		table.insert(results, {
			name = name,
			rarity = rarity,
			displayName = AspectConfig.displayName(name),
			where = where,
			isNew = isNew,
		})
	end
	while #record.history > HISTORY_KEPT do
		table.remove(record.history)
	end

	-- No damage while the reveal holds the camera in the sky; lifted when the
	-- client says it closed (WishState "done"), and never longer than this.
	if #results > 0 then
		CombatService.shield(player, if count == 1 then 20 else 50)
	end

	InventoryStore.markDirty(player)
	push(player)
	return { ok = #results > 0, results = results, state = WishService.state(player) }
end

PullRemote.OnServerInvoke = function(player, count)
	if busy[player] or os.clock() - (lastPull[player] or -10) < PULL_COOLDOWN then
		return { ok = false, message = "One wish at a time." }
	end
	busy[player] = true
	lastPull[player] = os.clock()
	local ok, reply = pcall(pull, player, count)
	busy[player] = nil
	if not ok then
		warn("[WishService]", reply)
		return { ok = false, message = "The banner is unavailable. Please try again." }
	end
	return reply
end

StateRemote.OnServerEvent:Connect(function(player, message)
	if message == "done" then
		CombatService.shield(player, 0)
		return
	end
	push(player)
end)

-- A buy button: the prompt is Roblox's; the stars arrive through grantProduct.
BuyRemote.OnServerEvent:Connect(function(player, productId)
	for _, product in ipairs(WishConfig.Products) do
		if product.id > 0 and product.id == productId then
			if not records[player] or InventoryStore.isReadOnly(player) then
				CommandFeedback.tell(player, "Your save is not ready. Please try again.", "bad")
			else
				MarketplaceService:PromptProductPurchase(player, product.id)
			end
			return
		end
	end
end)

--[[
	A Robux purchase. Adds the stars and SAVES before answering true, so a
	receipt is only confirmed once the stars cannot be lost; idempotent on the
	PurchaseId. See Purchases.
]]
local function grantProduct(stars)
	return function(player, receipt)
		local record = records[player]
		local purchaseId = tostring(receipt.PurchaseId)
		if not record or InventoryStore.isReadOnly(player) then
			return false
		end
		if table.find(record.receipts, purchaseId) then
			return true
		end
		local inventory = InventoryService.GetInventory(player)
		if not inventory then
			return false
		end

		record.stars = clampStars(record.stars + stars)
		table.insert(record.receipts, purchaseId)
		while #record.receipts > RECEIPTS_KEPT do
			table.remove(record.receipts, 1)
		end

		if not InventoryStore.save(player, inventory, "wish purchase") then
			record.stars = clampStars(record.stars - stars)
			table.remove(record.receipts, table.find(record.receipts, purchaseId))
			return false
		end

		push(player)
		CommandFeedback.tell(player, string.format("+%d %s", stars, WishConfig.CurrencyName), "good")
		return true
	end
end

for _, product in ipairs(WishConfig.Products) do
	Purchases.register(product.id, grantProduct(product.stars))
end

-- For DebugConsole's Studio-only /wish command.
function WishService.debugSet(player, field, value)
	local record = records[player]
	if not record then
		return false
	end
	if field == "stars" then
		record.stars = clampStars(value)
	elseif field == "pity" then
		record.sinceLegendary = math.clamp(math.floor(value), 0, WishConfig.LegendaryPity - 1)
	end
	InventoryStore.markDirty(player)
	push(player)
	return true
end

InventoryStore.registerSection("wish", function(player)
	local record = records[player]
	if not record then
		return nil
	end
	return {
		stars = record.stars,
		sinceLegendary = record.sinceLegendary,
		sinceEpic = record.sinceEpic,
		wishes = record.wishes,
		welcomed = record.welcomed,
		lastDaily = record.lastDaily,
		receipts = table.clone(record.receipts),
		history = table.clone(record.history),
	}
end, function(player, value)
	value = if type(value) == "table" then value else {}

	local history = {}
	if type(value.history) == "table" then
		for _, entry in ipairs(value.history) do
			-- Entries from before aspects name abilities, and are dropped.
			if type(entry) == "table" and AspectConfig.get(entry.name) and WishConfig.Stars[entry.rarity] then
				table.insert(history, { name = entry.name, rarity = entry.rarity })
			end
		end
	end
	local receipts = {}
	if type(value.receipts) == "table" then
		for _, id in ipairs(value.receipts) do
			if type(id) == "string" then
				table.insert(receipts, id)
			end
		end
	end

	local record = {
		stars = clampStars(value.stars),
		sinceLegendary = math.clamp(math.floor(tonumber(value.sinceLegendary) or 0), 0, WishConfig.LegendaryPity - 1),
		sinceEpic = math.clamp(math.floor(tonumber(value.sinceEpic) or 0), 0, WishConfig.EpicPity - 1),
		wishes = math.max(0, math.floor(tonumber(value.wishes) or 0)),
		welcomed = value.welcomed == true,
		lastDaily = math.floor(tonumber(value.lastDaily) or 0),
		receipts = receipts,
		history = history,
	}
	records[player] = record

	-- The gifts are given once the record exists, so they are saved with it.
	task.delay(4, function()
		if records[player] ~= record or not player.Parent then
			return
		end
		if not record.welcomed then
			record.welcomed = true
			WishService.award(player, WishConfig.Earn.Welcome, "a gift to start you wishing")
		end
		local today = dayNumber()
		if record.lastDaily ~= today then
			record.lastDaily = today
			WishService.award(player, WishConfig.Earn.Daily, "daily gift")
		end
	end)

	push(player)
end)

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
	lastPull[player] = nil
end)

return WishService
