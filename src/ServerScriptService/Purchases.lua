--[[
	Purchases

	The game's one MarketplaceService.ProcessReceipt. Roblox allows a single
	callback per server, so every Developer Product registers a handler here
	rather than setting the callback itself and silently replacing another's.

		Purchases.register(productId, function(player, receipt): boolean
			-- grant it AND SAVE IT, then return true
		end)

	HOW A RECEIPT IS SETTLED

	Roblox keeps offering a receipt - now, and again each time the buyer joins a
	server - until a handler says it was granted. So a handler returns true only
	once the purchase is in the player's save, and false for anything that could
	not be finished (save not loaded yet, DataStore down, player gone). False
	costs nothing: the Robux are held and the receipt comes back.

	Because a receipt can come back after it was granted (the save went through
	but the server died before answering), a handler must be idempotent: keep
	the receipt's PurchaseId with what it bought and answer true straight away
	when it sees one twice. AbilityLoadout's storage purchase does.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Purchases = {}

local handlers: { [number]: (Player, any) -> boolean } = {}

function Purchases.register(productId: number, handler: (Player, any) -> boolean)
	if type(productId) ~= "number" or productId <= 0 then
		return
	end
	assert(handlers[productId] == nil, "[Purchases] product " .. productId .. " already has a handler")
	handlers[productId] = handler
end

MarketplaceService.ProcessReceipt = function(receipt)
	local handler = handlers[receipt.ProductId]
	if not handler then
		-- A product nothing here sells any more, or one registered by a script
		-- that has not loaded yet. Held, not lost: it is offered again.
		warn("[Purchases] no handler for product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(handler, player, receipt)
	if not ok then
		warn("[Purchases] product", receipt.ProductId, "for", player.Name, "errored:", granted)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return if granted
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

return Purchases
