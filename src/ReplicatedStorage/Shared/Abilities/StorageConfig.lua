--[[
	StorageConfig

	Ability storage: slots an ability can be parked in instead of thrown away,
	sold three at a time, as many times over as a player likes up to MaxSlots.

	Shared rather than server-only because the client needs it too: the storage
	panel shows the price, the "+3" and how far there is to go, and AbilityLoadout
	sends the numbers down with every storage push so nothing is hard-coded twice.

	A DEVELOPER PRODUCT, NOT A GAME PASS

	A Game Pass can only ever be bought once, so a "+3, and again, and again"
	purchase has to be a Developer Product. Unlike a pass, Roblox does not
	remember who bought a product: each purchase arrives once through
	ProcessReceipt (ServerScriptService.Purchases) and the slots it bought are
	written into the player's save record before the purchase is confirmed.

	SET AbilityStorageProductId TO 0 TO TAKE IT OFF SALE. Every path checks it:
	the panel says it is not on sale, and the server refuses to prompt.

	(The game has an older "+3 ability storage" Game Pass, 2040735675. It was
	never put on sale, so nobody owns it, and nothing here reads it any more.)
]]

return {
	-- The "+3 ability storage" Developer Product, from the Creator Dashboard:
	-- Monetization > Developer Products. R$300 when it was set up.
	AbilityStorageProductId = 3726866739,

	-- Slots one purchase adds.
	SlotsPerPurchase = 3,

	-- The most anyone can have. Ten purchases; the panel scrolls.
	MaxSlots = 30,
}
