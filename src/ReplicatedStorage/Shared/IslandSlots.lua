--[[
	IslandSlots

	How many islands a player can have, and what unlocks the next one.

	Everyone has island 1. Island 2 is a Game Pass - a one-time purchase that
	Roblox remembers on the account, which is what a second island should be.
	Set SecondIslandPassId to the pass's ID from the Creator Dashboard
	(Monetization > Passes); while it is 0, island 2 is not on sale and
	/switchisland says so.

	Each island is its own save record and its own reserved server, so a second
	island costs nothing against the first's DataStore limits. See
	ServerScriptService.IslandSlots for ownership and the switch command.
]]

return {
	SecondIslandPassId = 2064556930,

	-- The most islands anyone can have. Raising it needs a pass per island.
	MaxIslands = 2,
}
