--[[
	TradeSettlement

	Carries out one agreed trade between two players on this server, so that
	it happens for both of them or for neither - whatever fails, and whenever.

		TradeSettlement.run(tradeId, a, b, goodsA, goodsB) -> outcome, detail

	`goodsA` is what player a gives (and b receives); `goodsB` the reverse.

	  "done"      the trade happened and both players have their goods
	  "refused"   it could not start (someone no longer has the goods, or has
	              no room). Nothing was touched; `detail` says who and why.
	  "failed"    it started and was undone. Everybody has their own goods.
	  "pending"   the outcome could not be learned. Both players' goods are
	              held safely in their saves and TradeEscrow keeps asking.

	HOW, AND WHY IN THIS ORDER

	  1. CHECK both players, then HOLD both: each player's goods leave their
	     bag and their record gains a pending entry for this trade. No yield
	     from the first check to the last hold, so nothing can change under it.

	  2. SAVE both records. Now each save, on its own, says what its player put
	     in and what they are owed. If either save fails, both players are
	     given their goods back and the trade is over. The ledger has never
	     heard of this trade, so a record that did get saved as pending can
	     only ever resolve to "aborted" - the same answer.

	  3. COMMIT: one write to TradeLedger. This is the trade. Before it, the
	     trade has not happened; after it, it has, for both players at once.

	  4. SETTLE both players with whatever the ledger said, and save.

	A server that dies after step 2 leaves two records with a pending entry
	and a ledger that says either nothing (it died before 3: both players get
	their own goods back when they next load) or "committed" (it died after:
	both get what they were promised). There is no moment at which one player
	can end up with both halves, or with neither.

	A player leaving mid-way changes nothing: their leave save carries the
	pending entry or the settled result, whichever was true when it ran, and
	both lead to the same place.

	This module holds no state and knows nothing about offers, confirmations
	or remotes - that is TradeService.
]]

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local TradeEscrow = require(script.Parent:WaitForChild("TradeEscrow"))
local TradeLedger = require(script.Parent:WaitForChild("TradeLedger"))

local TradeSettlement = {}

--[[
	Studio-only fault injection, read from Workspace attributes so a test can
	set them from outside:

	  TradeTestFailSave   a UserId whose save in step 2 is treated as failed
	  TradeTestStopAfter  "save" or "commit": the settlement simply stops
	                      there, as if the server had died at that point
	  TradeTestLedgerDown (in TradeLedger) the ledger cannot be reached
]]
local IS_STUDIO = RunService:IsStudio()

local function testValue(name)
	return if IS_STUDIO then workspace:GetAttribute(name) else nil
end

local function save(player, reason): boolean
	if testValue("TradeTestFailSave") == player.UserId then
		return false
	end
	local inventory = InventoryService.GetInventory(player)
	if not inventory then
		return false
	end
	local ok, saved = pcall(InventoryStore.save, player, inventory, reason)
	return ok and saved == true
end

-- Both saves at once; returns when both have answered.
local function saveBoth(a, b, reason): (boolean, boolean)
	local savedA, savedB = nil, nil
	task.spawn(function()
		savedA = save(a, reason)
	end)
	task.spawn(function()
		savedB = save(b, reason)
	end)
	while savedA == nil or savedB == nil do
		task.wait(0.1)
	end
	return savedA, savedB
end

function TradeSettlement.run(tradeId: string, a, b, goodsA, goodsB): (string, string?)
	-- 1. Check and hold. Nothing between here and the last hold may yield.
	for _, side in ipairs({ { a, goodsA, goodsB }, { b, goodsB, goodsA } }) do
		local player, give, get = side[1], side[2], side[3]
		local can, why = TradeEscrow.canTrade(player)
		if not can then
			return "refused", string.format("%s is %s", player.DisplayName, why)
		end
		local ok, reason = TradeEscrow.check(player, give, get)
		if not ok then
			return "refused", string.format("%s: %s", player.DisplayName, tostring(reason))
		end
	end

	if not TradeEscrow.hold(a, tradeId, goodsA, goodsB, b.UserId) then
		TradeEscrow.orphan(tradeId)
		return "refused", string.format("%s's goods could not be taken", a.DisplayName)
	end
	if not TradeEscrow.hold(b, tradeId, goodsB, goodsA, a.UserId) then
		TradeEscrow.settle(a, tradeId, false)
		TradeEscrow.orphan(tradeId)
		return "refused", string.format("%s's goods could not be taken", b.DisplayName)
	end

	-- 2. Both records must say "pending" before anything is decided.
	local savedA, savedB = saveBoth(a, b, "trade hold")

	if testValue("TradeTestStopAfter") == "save" then
		return "pending", "test: stopped after saving"
	end

	if not (savedA and savedB) then
		-- Undone here, without the ledger: nobody else can commit this trade,
		-- and a record that kept the pending entry resolves to "aborted".
		TradeEscrow.settle(a, tradeId, false)
		TradeEscrow.settle(b, tradeId, false)
		TradeEscrow.orphan(tradeId)
		return "failed", "the trade could not be saved"
	end

	-- 3. The trade itself.
	local outcome = TradeLedger.decide(tradeId, "committed")

	if testValue("TradeTestStopAfter") == "commit" then
		return "pending", "test: stopped after committing"
	end

	if not outcome then
		-- Unknown, so nothing may be guessed. The goods stay held in both
		-- saves and recovery asks the ledger until it answers.
		TradeEscrow.orphan(tradeId)
		return "pending", "the trade could not be confirmed yet"
	end

	-- 4. Whatever the ledger says, for both.
	local committed = outcome == "committed"
	TradeEscrow.settle(a, tradeId, committed)
	TradeEscrow.settle(b, tradeId, committed)
	TradeEscrow.orphan(tradeId)

	-- Not needed for safety - a record still saved as pending settles the same
	-- way on its next load - but it closes that window straight away.
	task.spawn(saveBoth, a, b, "trade settled")

	return if committed then "done" else "failed", nil
end

return TradeSettlement
