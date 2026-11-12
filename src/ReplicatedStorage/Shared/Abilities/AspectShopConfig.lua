--[[
	AspectShopConfig

	The Aspect Shop: PERMANENT aspects, bought with Robux. A permanent aspect
	is the player's for good - they can equip it at any time, and swapping it
	out never destroys it (unlike a stored aspect, which is used up).

	EACH ASPECT IS A GAME PASS. A Game Pass is the right tool for "owned
	forever": Roblox itself remembers who bought it, so ownership survives
	anything that happens to our save. Create one pass per aspect on the
	Creator Dashboard (Monetization > Passes), set its price there, and paste
	its id below. 0 keeps that aspect off sale; the shop shows it greyed out.

	The price shown in the shop is read from Roblox, so it is only ever set in
	one place - the dashboard.
]]

local AspectShopConfig = {}

-- Aspect name (AspectConfig) -> Game Pass id. 0 = not on sale.
AspectShopConfig.Passes = {
	Ember = 0,
	Tide = 0,
	Gale = 0,
	Stone = 0,
	Storm = 0,
	Ink = 0,
	Abyss = 0,
	Chaos = 0,
	Celestial = 0,
	Divinity = 0,
}

function AspectShopConfig.passFor(aspectName: string?): number
	local id = aspectName and AspectShopConfig.Passes[aspectName]
	return if type(id) == "number" then id else 0
end

-- The aspect a Game Pass id sells, or nil.
function AspectShopConfig.aspectForPass(passId: number): string?
	for aspectName, id in pairs(AspectShopConfig.Passes) do
		if id > 0 and id == passId then
			return aspectName
		end
	end
	return nil
end

return AspectShopConfig
