--[[
	TradeConfig

	The rules of player-to-player trading that both sides need to agree on:
	limits, timings, and WHAT MAY BE TRADED AT ALL. Shared, so the client can
	grey out what the server would refuse - the server still checks everything
	(ServerScriptService.Trade).

	WHAT CAN BE TRADED

	  Aspects   STORED copies only - the one-use kind a wish or a scroll gives.

	  Permanent passes
	            what buying an aspect's Game Pass puts in the inventory
	            (AbilityLoadout.claimPass). While it is UNREDEEMED it can be
	            traded like anything else. Redeeming it makes the aspect
	            permanent, and from then on it cannot be traded. Roblox cannot
	            move a Game Pass between accounts, so the buyer "owns" it for
	            ever and can never buy that one again - only trade for a pass.
	            Switch the whole thing off with PermanentAspectsTradable.

	WHAT CANNOT

	  Bag items (ItemsTradable = false): a strong player handing a new one
	  their gear skips the game. The code for it is still here; turning the
	  switch on brings it back, item by item if UntradableItems is used.

	  Redeemed permanent aspects, bought storage slots, and the aspect IN USE:
	  a player trades a stored copy instead.

	TO MAKE SOMETHING ACCOUNT-BOUND, add its name to UntradableItems,
	UntradableAspects or UntradablePermanent here (or put `tradable = false` on
	the item). Nothing else needs to change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local AspectConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Abilities"):WaitForChild("AspectConfig"))

local TradeConfig = {}

-- Whether anything from the bag may be traded at all. Off: only aspects and
-- permanent passes change hands.
TradeConfig.ItemsTradable = false

-- [itemName] = true: never offered, never accepted.
TradeConfig.UntradableItems = {
}

-- [aspectName] = true: stored copies of this aspect stay with their owner.
TradeConfig.UntradableAspects = {
}

-- Whether permanent aspects may be traded at all, and any that may not.
TradeConfig.PermanentAspectsTradable = true
TradeConfig.UntradablePermanent = {
}

-- How many different things one side may put up, per kind. Twelve in all,
-- which is what the trade window has tiles for.
TradeConfig.MaxItemEntries = 6
TradeConfig.MaxAspectEntries = 3
TradeConfig.MaxPermanentEntries = 3

-- The most of one item in one offer. Far above any real stack of stacks; it
-- only bounds what a modified client can ask the server to count.
TradeConfig.MaxItemCount = 9999

-- A request nobody answers goes away after this long.
TradeConfig.RequestSeconds = 30

-- Between two requests from one player, and before the same player may ask
-- someone who has just declined them again.
TradeConfig.RequestCooldown = 2
TradeConfig.DeclinedCooldown = 20

-- After ANY change to either offer, nobody can confirm for this long. It is
-- what stops the oldest trick there is: swapping the offer the instant
-- before the other player clicks.
TradeConfig.ConfirmDelay = 2

-- An open trade nobody has touched for this long is cancelled.
TradeConfig.IdleSeconds = 300

function TradeConfig.itemTradable(itemName): boolean
	if not TradeConfig.ItemsTradable or type(itemName) ~= "string" or TradeConfig.UntradableItems[itemName] then
		return false
	end
	local definition = ItemDefinitions[itemName]
	return definition ~= nil and definition.tradable ~= false
end

function TradeConfig.aspectTradable(aspectName): boolean
	if type(aspectName) ~= "string" or TradeConfig.UntradableAspects[aspectName] then
		return false
	end
	local definition = AspectConfig.get(aspectName)
	return definition ~= nil and definition.tradable ~= false
end

function TradeConfig.permanentTradable(aspectName): boolean
	if not TradeConfig.PermanentAspectsTradable or type(aspectName) ~= "string" then
		return false
	end
	return not TradeConfig.UntradablePermanent[aspectName] and AspectConfig.get(aspectName) ~= nil
end

-- One question for all three kinds: "item", "aspect" (a stored copy) or
-- "permanent".
function TradeConfig.tradable(kind, name): boolean
	if kind == "item" then
		return TradeConfig.itemTradable(name)
	elseif kind == "aspect" then
		return TradeConfig.aspectTradable(name)
	elseif kind == "permanent" then
		return TradeConfig.permanentTradable(name)
	end
	return false
end

function TradeConfig.maxEntries(kind): number
	if kind == "item" then
		return TradeConfig.MaxItemEntries
	elseif kind == "aspect" then
		return TradeConfig.MaxAspectEntries
	end
	return TradeConfig.MaxPermanentEntries
end

return TradeConfig
