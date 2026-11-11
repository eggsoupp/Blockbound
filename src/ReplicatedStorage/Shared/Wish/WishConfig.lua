--[[
	WishConfig

	The Starfall banner: what a wish costs, the odds, the pity, and where Wish
	Stars come from. Shared, because the banner window shows the rates and the
	pity counter, and the server rolls from the same numbers.

	THE ODDS

	Each wish is one ASPECT (Shared.Abilities.AspectConfig), chosen in two
	steps: a rarity, then an aspect of that rarity, evenly. Duplicates are
	allowed - a second Ember goes to aspect storage like any other, even past
	the bought extra slots, so a wish is never lost.

	  Legendary  1.5%, rising from the 22nd wish without one, certain on the 30th
	  Epic       7%, and at least one in every 10 wishes (a Legendary counts)
	  Rare       20%
	  Uncommon   30%
	  Common     the rest (41.5%)

	The two counters carry over between sessions and between single and ten
	wishes - they count wishes, not purchases.

	PRODUCTS

	Wish Stars can be bought with Robux as two Developer Products. Create them
	on the Creator Dashboard (Monetization > Developer Products) and paste the
	ids below; 0 keeps a product off sale and hides its button.
]]

local WishConfig = {}

WishConfig.BannerName = "Starfall Wish"
WishConfig.CurrencyName = "Wish Stars"

-- Wish Stars per wish.
WishConfig.Cost = 1

-- The two buttons on the banner.
WishConfig.Batches = { 1, 10 }

WishConfig.Rates = {
	Legendary = 0.015,
	Epic = 0.07,
	Rare = 0.20,
	Uncommon = 0.30,
	-- Common takes whatever is left.
}

-- The Legendary is certain on this wish, counting from the last one.
WishConfig.LegendaryPity = 30
-- From this wish on, each wish without one adds SoftPityStep to its chance:
-- 11.5% on the 22nd, 81.5% on the 29th.
WishConfig.SoftPityFrom = 22
WishConfig.SoftPityStep = 0.10

-- At least one Epic or better in this many wishes.
WishConfig.EpicPity = 10

-- Highest first: the order the summary and the meteor's colour are chosen in.
WishConfig.Tiers = { "Legendary", "Epic", "Rare", "Uncommon", "Common" }

-- Stars on a reveal card, by rarity.
WishConfig.Stars = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

-- Aspects that never come out of the banner (a name from AspectConfig).
WishConfig.Excluded = {}

-- Robux products: Wish Stars each one grants. Ids from the Creator Dashboard.
WishConfig.Products = {
	{ id = 0, stars = 1, label = "1" },
	{ id = 0, stars = 10, label = "10" },
}

-- Where Wish Stars come from.
WishConfig.Earn = {
	Welcome = 10, -- once, the first time a player's save loads with this feature
	Daily = 3, -- the first session of each UTC day
	Quest = 2, -- each quest completed
	Boss = 5, -- the killing blow on a boss
	EnemyChance = 0.01, -- any other kill: this chance of one star
}

-- Chance of a Legendary on the wish `sinceLegendary + 1`.
function WishConfig.legendaryChance(sinceLegendary: number): number
	local nth = sinceLegendary + 1
	if nth >= WishConfig.LegendaryPity then
		return 1
	end
	local soft = math.max(0, nth - WishConfig.SoftPityFrom + 1) * WishConfig.SoftPityStep
	return math.min(1, WishConfig.Rates.Legendary + soft)
end

return WishConfig
