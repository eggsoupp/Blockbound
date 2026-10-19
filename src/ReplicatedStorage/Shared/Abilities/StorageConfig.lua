--[[
	StorageConfig

	The gamepass that unlocks the three ability storage slots.

	Shared rather than server-only because the client needs it too: the panel
	behind the storage box says "+3 STORAGE · GAMEPASS" while it is locked, and
	AbilityLoadout sends the id down with every storage push so the client never
	has to hard-code it a second time.

	SET THIS TO 0 TO TAKE THE FEATURE OFF SALE. Every path checks it: the
	server refuses to prompt a purchase, refuses to unlock, and tells the player
	it is not on sale yet rather than opening an empty purchase dialog.

	Ownership itself is never stored here or anywhere else. It is asked of
	MarketplaceService and cached for the session, because a gamepass is owned
	on the Roblox account, not in our save file - a player who buys it, plays on
	one server and joins another still owns it, and a refund has to be able to
	take it away. What IS persisted is the contents of the slots (see the
	abilityStorage section in AbilityLoadout), which survive whether or not the
	pass is still owned.
]]

return {
	-- The "+3 ability storage" Game Pass of this experience (a Pass, not a
	-- Developer Product: UserOwnsGamePassAsync can only answer for a Pass).
	-- It has to be switched on for sale on the Creator Dashboard to be bought.
	AbilityStoragePassId = 2040735675,
}
