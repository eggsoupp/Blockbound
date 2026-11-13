--[[
	TradeService

	Player-to-player trading: who has asked whom, what each side has put up,
	who has confirmed. Everything a client says is a request; this decides.

	ONE REMOTE, "Trade"

	  client -> server
	    ("request" and "respond" are refused from clients: trades start at the
	    spawn village's trade booths, see TradeStations)
	    "offer", kind, name, count       set how many of one thing I am offering
	                                     (kind "item" | "aspect" | "permanent";
	                                     0 takes it out)
	    "confirm", rev                   I agree to the trade as it stands at rev
	    "unconfirm"                      I take that back
	    "cancel"                         leave the trade

	  server -> client
	    "request", fromUserId, name, seconds     someone is asking
	    "requestGone", fromUserId                ...and no longer is
	    "state", view                            the whole trade, after any change
	    "closed"                                 the trade is over (a line of
	                                             CommandFeedback says how)

	WHAT KEEPS IT HONEST

	  * An offer is a COUNT, not a move: nothing leaves anybody's bag until both
	    have confirmed. Cancelling, leaving and declining therefore have nothing
	    to undo.
	  * Setting an offer is absolute ("12 Wood"), so a message sent twice asks
	    for the same thing twice. Any real change bumps `rev`, clears BOTH
	    confirmations and starts TradeConfig.ConfirmDelay.
	  * A confirmation names the `rev` it saw. One that arrives for an older
	    offer - the other side changed something as the button was pressed - is
	    ignored.
	  * Offers are clamped to what the player really holds, on every change and
	    once a second, so dropping an offered item mid-trade un-offers it (and
	    clears the confirmations).
	  * When both have confirmed the trade is "settling": every message is
	    ignored until TradeSettlement has finished, so nothing can be
	    confirmed, changed or cancelled twice.

	The exchange itself - and everything about it surviving failed saves and
	dead servers - is TradeSettlement, TradeEscrow and TradeLedger.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local TradeConfig = require(Shared:WaitForChild("Trade"):WaitForChild("TradeConfig"))
local AspectConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AspectConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local TradeEscrow = require(script.Parent:WaitForChild("TradeEscrow"))
local TradeSettlement = require(script.Parent:WaitForChild("TradeSettlement"))

local Remote = Remotes.ensure("Trade", "RemoteEvent")

local tell = CommandFeedback.tell

-- The most unanswered requests one player can have waiting on them.
local MAX_WAITING_REQUESTS = 5

-- The shortest gap between two messages from one client. Clicking cannot beat
-- it; a script flooding the remote can, and is dropped.
local MIN_MESSAGE_GAP = 0.04

-- target -> { [from] = expiresAt (os.clock) }
local requests = {}
-- from -> { [targetUserId] = when they were declined }
local declined = {}
local lastRequestAt = {}
local lastMessageAt = {}

-- player -> the trade they are in.
local tradeOf = {}

-- ---------------------------------------------------------------------------
-- Offers
-- ---------------------------------------------------------------------------

local function newOffer()
	return { item = {}, aspect = {}, permanent = {} }
end

local function sortedNames(counts)
	local names = {}
	for name in pairs(counts) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- An offer as TradeEscrow's goods.
local function goodsOf(offer)
	local goods = { items = {}, aspects = {}, permanent = {} }
	for _, name in ipairs(sortedNames(offer.permanent)) do
		for _ = 1, offer.permanent[name] do
			table.insert(goods.permanent, name)
		end
	end
	for _, name in ipairs(sortedNames(offer.item)) do
		table.insert(goods.items, { n = name, c = offer.item[name] })
	end
	for _, name in ipairs(sortedNames(offer.aspect)) do
		for _ = 1, offer.aspect[name] do
			table.insert(goods.aspects, name)
		end
	end
	return goods
end

-- An offer as the client draws it: { { n, c }, ... } for each kind.
local function listOf(counts)
	local list = {}
	for _, name in ipairs(sortedNames(counts)) do
		table.insert(list, { n = name, c = counts[name] })
	end
	return list
end

local function isEmptyOffer(offer): boolean
	return next(offer.item) == nil and next(offer.aspect) == nil and next(offer.permanent) == nil
end

-- "3 x Wood, Ember aspect", for the line that says what arrived.
local function describe(offer): string
	local parts = {}
	for _, name in ipairs(sortedNames(offer.permanent)) do
		local count = offer.permanent[name]
		local label = "permanent " .. AspectConfig.displayName(name) .. " pass"
		table.insert(parts, if count > 1 then string.format("%d x %s", count, label) else label)
	end
	for _, name in ipairs(sortedNames(offer.aspect)) do
		local count = offer.aspect[name]
		local label = AspectConfig.displayName(name) .. " aspect"
		table.insert(parts, if count > 1 then string.format("%d x %s", count, label) else label)
	end
	for _, name in ipairs(sortedNames(offer.item)) do
		local definition = ItemDefinitions[name]
		local label = definition and definition.displayName or name
		local count = offer.item[name]
		table.insert(parts, if count > 1 then string.format("%d x %s", count, label) else label)
	end
	return if #parts > 0 then table.concat(parts, ", ") else "nothing"
end

-- Cuts an offer down to what its player still holds. Returns whether it changed.
local function clampOffer(player, offer): boolean
	local changed = false
	for kind, counts in pairs(offer) do
		for name, count in pairs(counts) do
			local held = TradeEscrow.count(player, kind, name)
			if held < count then
				counts[name] = if held > 0 then held else nil
				changed = true
			end
		end
	end
	return changed
end

-- ---------------------------------------------------------------------------
-- Trades
-- ---------------------------------------------------------------------------

local function partnerOf(trade, player)
	return if trade.players[1] == player then trade.players[2] else trade.players[1]
end

local function send(player, ...)
	if player.Parent then
		Remote:FireClient(player, ...)
	end
end

local function push(trade)
	local confirmIn = math.max(0, TradeConfig.ConfirmDelay - (os.clock() - trade.changedAt))
	for _, player in ipairs(trade.players) do
		local partner = partnerOf(trade, player)
		local mine, theirs = trade.offers[player], trade.offers[partner]
		send(player, "state", {
			rev = trade.rev,
			phase = trade.phase,
			confirmIn = confirmIn,
			partner = { userId = partner.UserId, name = partner.DisplayName },
			mine = {
				items = listOf(mine.item), aspects = listOf(mine.aspect), permanent = listOf(mine.permanent),
				confirmed = trade.confirmed[player] == true,
			},
			theirs = {
				items = listOf(theirs.item), aspects = listOf(theirs.aspect), permanent = listOf(theirs.permanent),
				confirmed = trade.confirmed[partner] == true,
			},
		})
	end
end

-- Every change to what is on the table comes through here.
local function offersChanged(trade)
	trade.rev += 1
	trade.confirmed = {}
	trade.changedAt = os.clock()
	trade.touchedAt = trade.changedAt
	push(trade)
end

local function close(trade)
	trade.phase = "closed"
	for _, player in ipairs(trade.players) do
		if tradeOf[player] == trade then
			tradeOf[player] = nil
		end
		send(player, "closed")
	end
end

local function dropRequests(player)
	local waiting = requests[player]
	if waiting then
		for from in pairs(waiting) do
			send(player, "requestGone", from.UserId)
		end
		requests[player] = nil
	end
	for target, list in pairs(requests) do
		if list[player] then
			list[player] = nil
			send(target, "requestGone", player.UserId)
		end
	end
end

local function begin(a, b)
	dropRequests(a)
	dropRequests(b)

	local trade = {
		id = HttpService:GenerateGUID(false),
		players = { a, b },
		offers = { [a] = newOffer(), [b] = newOffer() },
		confirmed = {},
		rev = 1,
		phase = "open",
		changedAt = os.clock(),
		touchedAt = os.clock(),
	}
	tradeOf[a] = trade
	tradeOf[b] = trade
	push(trade)
end

-- Why two players cannot start trading, as a line for `asker`; nil if they can.
local function obstacle(asker, other): string?
	if tradeOf[asker] then
		return "You are already in a trade."
	end
	local can, why = TradeEscrow.canTrade(asker)
	if not can then
		return string.format("You can't trade right now: you are %s.", why)
	end
	if tradeOf[other] then
		return string.format("%s is in another trade.", other.DisplayName)
	end
	if not TradeEscrow.canTrade(other) then
		return string.format("%s can't trade right now.", other.DisplayName)
	end
	return nil
end

--[[
	Both have confirmed. From here until TradeSettlement answers the trade is
	"settling" and deaf to its players.
]]
local function settle(trade)
	trade.phase = "settling"
	push(trade)

	local a, b = trade.players[1], trade.players[2]
	local offerA, offerB = trade.offers[a], trade.offers[b]

	local ran, outcome, detail = pcall(TradeSettlement.run, trade.id, a, b, goodsOf(offerA), goodsOf(offerB))
	if not ran then
		warn("[TradeService] Settlement errored:", outcome)
		-- Whatever was held is in both saves as pending; let recovery ask.
		TradeEscrow.orphan(trade.id)
		outcome, detail = "pending", nil
	end

	if outcome == "refused" then
		-- Nothing was touched. Back to the table, with the reason.
		for _, player in ipairs(trade.players) do
			tell(player, "The trade can't go through - " .. tostring(detail) .. ".", "bad")
		end
		if a.Parent and b.Parent then
			trade.phase = "open"
			clampOffer(a, offerA)
			clampOffer(b, offerB)
			offersChanged(trade)
		else
			close(trade)
		end
		return
	end

	if outcome == "done" then
		tell(a, "Trade complete. You received: " .. describe(offerB) .. ".", "good")
		tell(b, "Trade complete. You received: " .. describe(offerA) .. ".", "good")
	elseif outcome == "failed" then
		for _, player in ipairs(trade.players) do
			tell(player, "The trade could not be saved, so it was called off. Nothing changed hands.", "bad")
		end
	else
		for _, player in ipairs(trade.players) do
			tell(
				player,
				"The trade is still being confirmed. Your items are held safely and will be delivered or returned shortly.",
				"bad"
			)
		end
	end
	close(trade)
end

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------

local handlers = {}

function handlers.request(player, targetUserId)
	if type(targetUserId) ~= "number" then
		return
	end
	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < TradeConfig.RequestCooldown then
		return
	end
	lastRequestAt[player] = now

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		tell(player, "That player is not here.", "bad")
		return
	end

	local problem = obstacle(player, target)
	if problem then
		tell(player, problem, "bad")
		return
	end

	-- They have already asked me: asking back is saying yes.
	local theirs = requests[player] and requests[player][target]
	if theirs and theirs > now then
		begin(player, target)
		return
	end

	local declinedAt = declined[player] and declined[player][targetUserId]
	if declinedAt and now - declinedAt < TradeConfig.DeclinedCooldown then
		tell(player, string.format("%s declined. Give them a moment before asking again.", target.DisplayName), "bad")
		return
	end

	local waiting = requests[target]
	if not waiting then
		waiting = {}
		requests[target] = waiting
	end
	if waiting[player] and waiting[player] > now then
		tell(player, string.format("You have already asked %s.", target.DisplayName), "bad")
		return
	end

	local count = 0
	for _ in pairs(waiting) do
		count += 1
	end
	if count >= MAX_WAITING_REQUESTS then
		tell(player, string.format("%s has too many trade requests waiting.", target.DisplayName), "bad")
		return
	end

	waiting[player] = now + TradeConfig.RequestSeconds
	send(target, "request", player.UserId, player.DisplayName, TradeConfig.RequestSeconds)
	tell(player, string.format("Trade request sent to %s.", target.DisplayName), "good")
end

function handlers.respond(player, fromUserId, accept)
	if type(fromUserId) ~= "number" then
		return
	end
	local from = Players:GetPlayerByUserId(fromUserId)
	local waiting = requests[player]
	local expiresAt = from and waiting and waiting[from]
	if not expiresAt then
		return
	end

	waiting[from] = nil
	send(player, "requestGone", fromUserId)

	if expiresAt <= os.clock() then
		tell(player, "That trade request has expired.", "bad")
		return
	end

	if accept ~= true then
		declined[from] = declined[from] or {}
		declined[from][player.UserId] = os.clock()
		tell(from, string.format("%s declined your trade request.", player.DisplayName), "bad")
		return
	end

	local problem = obstacle(player, from)
	if problem then
		tell(player, problem, "bad")
		tell(from, string.format("%s accepted, but the trade could not start.", player.DisplayName), "bad")
		return
	end
	begin(from, player)
end

function handlers.offer(player, kind, name, count)
	local trade = tradeOf[player]
	if not trade or trade.phase ~= "open" then
		return
	end
	if (kind ~= "item" and kind ~= "aspect" and kind ~= "permanent") or type(name) ~= "string" or type(count) ~= "number" then
		return
	end
	if count ~= count or count < 0 then
		return
	end
	count = math.min(math.floor(count), TradeConfig.MaxItemCount)

	if not TradeConfig.tradable(kind, name) then
		tell(player, "That can't be traded.", "bad")
		return
	end

	-- Never more than they hold: bag items, stored copies of an aspect, or the
	-- one permanent copy there can be (TradeEscrow.count).
	count = math.min(count, TradeEscrow.count(player, kind, name))

	local counts = trade.offers[player][kind]
	local wanted = if count > 0 then count else nil
	if counts[name] == wanted then
		return -- the same message twice, or nothing to offer: no change, no reset
	end

	if wanted and counts[name] == nil then
		local entries = 0
		for _ in pairs(counts) do
			entries += 1
		end
		if entries >= TradeConfig.maxEntries(kind) then
			tell(player, "Your side of the trade is full.", "bad")
			return
		end
	end

	counts[name] = wanted
	offersChanged(trade)
end

function handlers.confirm(player, rev)
	local trade = tradeOf[player]
	if not trade or trade.phase ~= "open" or trade.confirmed[player] then
		return
	end
	-- Agreed to something that is no longer on the table: show them what is.
	if rev ~= trade.rev or os.clock() - trade.changedAt < TradeConfig.ConfirmDelay then
		push(trade)
		return
	end

	local partner = partnerOf(trade, player)
	if isEmptyOffer(trade.offers[player]) and isEmptyOffer(trade.offers[partner]) then
		tell(player, "There is nothing in the trade yet.", "bad")
		return
	end

	trade.confirmed[player] = true
	trade.touchedAt = os.clock()

	if trade.confirmed[partner] then
		settle(trade)
	else
		push(trade)
	end
end

function handlers.unconfirm(player)
	local trade = tradeOf[player]
	if trade and trade.phase == "open" and trade.confirmed[player] then
		trade.confirmed[player] = nil
		trade.touchedAt = os.clock()
		push(trade)
	end
end

function handlers.cancel(player)
	local trade = tradeOf[player]
	if not trade or trade.phase ~= "open" then
		return -- a settling trade can no longer be walked away from
	end
	local partner = partnerOf(trade, player)
	tell(player, "Trade cancelled.")
	tell(partner, string.format("%s cancelled the trade.", player.DisplayName), "bad")
	close(trade)
end

local function onMessage(player, action, ...)
	local handler = type(action) == "string" and handlers[action]
	if not handler then
		return
	end

	local now = os.clock()
	if now - (lastMessageAt[player] or -math.huge) < MIN_MESSAGE_GAP then
		return
	end
	lastMessageAt[player] = now

	local ok, err = pcall(handler, player, ...)
	if not ok then
		warn("[TradeService]", action, "errored for", player.Name, err)
	end
end

-- Trades start only at the spawn village's trade booths (TradeStations), so
-- a client can no longer ask someone directly. The handlers stay for the
-- Studio test hook below, which calls onMessage itself.
local STATION_ONLY = { request = true, respond = true }
Remote.OnServerEvent:Connect(function(player, action, ...)
	if STATION_ONLY[action] then
		return
	end
	onMessage(player, action, ...)
end)

-- A physical station supplies two fresh, server-validated consents. All
-- inventory, session, confirmation and settlement rules stay in this service.
task.spawn(function()
	local hub = workspace:WaitForChild("StarfallHub", 90)
	if not hub then return end
	require(script.Parent:WaitForChild("TradeStations")).bind(hub, function(a, b)
		local problem = obstacle(a, b)
		if problem then
			tell(a, problem, "bad")
			tell(b, "Your partner cannot start a trade right now.", "bad")
			return
		end
		begin(a, b)
	end, tell)
end)

--[[
	STUDIO ONLY: a way to test trading with two players and no hands.

	A local test server has two real players but only one of them can be
	driven from outside, and nothing outside this script can see the game's
	module state. So in Studio (never in a live server) two instances sit
	under this script:

	  TradeTestInput  BindableEvent   :Fire(player, action, ...) is exactly a
	                                  message from that player's client, through
	                                  the same checks. Two extra actions hand
	                                  out test goods: "testItem", name, count
	                                  and "testAspect", name.
	  TradeTestProbe  BindableFunction :Invoke() -> what every player holds and
	                                  the state of their trade and escrow.
]]
if game:GetService("RunService"):IsStudio() then
	local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
	local AbilityLoadout = require(ServerScriptService:WaitForChild("AbilityLoadout"))

	local input = Instance.new("BindableEvent")
	input.Name = "TradeTestInput"
	input.Parent = script
	input.Event:Connect(function(player, action, ...)
		local a, b = ...
		if action == "testItem" then
			InventoryService.AddItemByName(player, a, b)
		elseif action == "testAspect" then
			AbilityLoadout.grantAspect(player, a, "trade", true)
		elseif action == "testPass" then
			-- As if Roblox had just said this account owns the aspect's pass.
			AbilityLoadout.claimPass(player, a)
		elseif action == "testRedeem" then
			AbilityLoadout.redeemPass(player, a)
		else
			onMessage(player, action, ...)
		end
	end)

	-- The aspects for which `test(player, name)` holds.
	local function owned(player, test)
		local names = {}
		for _, name in ipairs(AspectConfig.names()) do
			if test(player, name) then
				table.insert(names, name)
			end
		end
		return names
	end

	local probe = Instance.new("BindableFunction")
	probe.Name = "TradeTestProbe"
	probe.Parent = script
	probe.OnInvoke = function()
		local report = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local items = {}
			local inventory = InventoryService.GetInventory(player)
			for _, slot in ipairs(if inventory then inventory:GetAll() else {}) do
				if slot.name then
					items[slot.name] = (items[slot.name] or 0) + slot.count
				end
			end
			local trade = tradeOf[player]
			report[player.Name] = {
				items = items,
				aspect = AbilityLoadout.aspect(player),
				stored = AbilityLoadout.stored(player),
				permanent = owned(player, AbilityLoadout.ownsPermanent),
				claimed = owned(player, AbilityLoadout.passClaimed),
				passes = (function()
					local held = {}
					for _, name in ipairs(AspectConfig.names()) do
						local count = AbilityLoadout.passCount(player, name)
						if count > 0 then
							held[name] = count
						end
					end
					return held
				end)(),
				escrow = TradeEscrow.describe(player),
				trade = trade and {
					phase = trade.phase,
					rev = trade.rev,
					confirmed = trade.confirmed[player] == true,
					offer = listOf(trade.offers[player].item),
					offerAspects = listOf(trade.offers[player].aspect),
					offerPermanent = listOf(trade.offers[player].permanent),
				} or nil,
			}
		end
		return report
	end
end

-- ---------------------------------------------------------------------------
-- Housekeeping
-- ---------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()

		for target, waiting in pairs(requests) do
			for from, expiresAt in pairs(waiting) do
				if expiresAt <= now then
					waiting[from] = nil
					send(target, "requestGone", from.UserId)
					tell(from, string.format("%s did not answer your trade request.", target.DisplayName))
				end
			end
			if next(waiting) == nil then
				requests[target] = nil
			end
		end

		local seen = {}
		for _, trade in pairs(tradeOf) do
			if not seen[trade] and trade.phase == "open" then
				seen[trade] = true
				local a, b = trade.players[1], trade.players[2]
				if now - trade.touchedAt >= TradeConfig.IdleSeconds then
					tell(a, "The trade timed out.", "bad")
					tell(b, "The trade timed out.", "bad")
					close(trade)
				else
					-- Something offered has left its owner's bag since.
					local changedA = clampOffer(a, trade.offers[a])
					local changedB = clampOffer(b, trade.offers[b])
					if changedA or changedB then
						offersChanged(trade)
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	dropRequests(player)
	declined[player] = nil
	lastRequestAt[player] = nil
	lastMessageAt[player] = nil

	local trade = tradeOf[player]
	if trade and trade.phase == "open" then
		-- Nothing has left anybody's bag, so there is nothing to give back.
		tell(partnerOf(trade, player), string.format("%s left, so the trade was cancelled.", player.DisplayName), "bad")
		close(trade)
	end
	-- A settling trade finishes on its own (TradeSettlement), and closes then.
end)
