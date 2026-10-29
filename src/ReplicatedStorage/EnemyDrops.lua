--[[
	EnemyDrops

	What each enemy leaves behind. One entry per enemy, keyed by the same name
	as Shared.Enemies.EnemyConfig.Definitions.

	  item     a key in ItemDefinitions
	  chance   0..1, rolled per kill, per line
	  min/max  how many, inclusive, when it does drop

	Every line is rolled independently, so an enemy can drop all of its table,
	some of it, or nothing.

	WHAT THIS FILE USED TO BE

	Four rows naming items and enemies that do not exist - VoidReaver from a
	"Void Overlord", a FlameHammer from an "Inferno Dragon" - in a shape nothing
	read, keyed by the ITEM rather than by the creature. It was a sketch of a
	loot system from before there were enemies to hang it on, and nothing ever
	required it. It is now keyed by the enemy, because that is the question the
	code actually asks: something died, what does it leave?

	THE CONTENTS ARE PLACEHOLDER AND SAY SO

	Elias asked for wood off a slime "just for the sake of testing", and that is
	what this is: a real drop pipeline with a deliberately silly table on the
	end of it. Slimes do not carry logs. Change the rows; the pipeline does not
	care what is in them.

	Read by ServerScriptService.EnemyService, which rolls this on a kill, and by
	nothing else - it is in ReplicatedStorage rather than ServerScriptService so
	the client could show a "drops" list later without a remote for it.
]]

local EnemyDrops = {}

EnemyDrops.Tables = {
	--[[
		Slimes drop Gel: what they are made of, and the bulk of the Gelatinous
		Crown (100 of it, see CraftingRecipes). Guaranteed, one or two a kill,
		so the crown is a session of slime hunting rather than a lottery.

		This replaced the placeholder Wood drop that was only ever there to prove
		the drop pipeline worked.
	]]
	BlueSlime = {
		{ item = "Gel", chance = 1, min = 1, max = 2 },
	},

	GreenSlime = {
		{ item = "Gel", chance = 1, min = 1, max = 2 },
	},

	--[[
		Nothing yet.

		Deliberately empty rather than absent, so that "the Ghost has no drops"
		is a decision somebody wrote down and not an entry somebody forgot.
	]]
	Ghost = {},

	-- A boss should be worth the fight. Guaranteed, and a lot of it: the
	-- quantities are the only thing separating this from farming slimes. He is
	-- made of the same stuff his subjects are, so a good part of the crown
	-- that called him comes back out of him.
	SlimeEmperor = {
		{ item = "Gel", chance = 1, min = 40, max = 60 },
	},

	--[[
		The Eye of Cthulhu drops ore and potions; this drops ore and the
		game's own magic material. Gold and Essence Shards always, Mythril
		half the time - a step up from the Slime Emperor, which it is.
	]]
	AllSeeingEye = {
		{ item = "GoldOre", chance = 1, min = 10, max = 18 },
		{ item = "EssenceShard", chance = 1, min = 4, max = 8 },
		{ item = "MythrilOre", chance = 0.5, min = 2, max = 5 },
	},

	-- The Crimson's eye. Leather now and then, and rarely a shard of the
	-- magic the All Seeing Eye is made of.
	DemonEye = {
		{ item = "Leather", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.06, min = 1, max = 1 },
	},

	-- The Demon Eyes the All Seeing Eye summons: now and then a herb, the way
	-- Terraria's servants drop hearts.
	ServantEye = {
		{ item = "Herb", chance = 0.25, min = 1, max = 1 },
	},

	--[[
		The Eater of Worlds drops the Corruption's ore and its own scales; this
		drops what it has been eating its way through - deep ore and the
		game's magic material, always, and now and then a shard of the void it
		came up from. A step up from the All Seeing Eye.
	]]
	Blightborer = {
		{ item = "MythrilOre", chance = 1, min = 6, max = 12 },
		{ item = "EssenceShard", chance = 1, min = 5, max = 9 },
		{ item = "VoidCrystal", chance = 0.35, min = 1, max = 2 },
	},

	-- Its brood, which it makes a lot of: now and then a scrap of leather.
	Blightling = {
		{ item = "Leather", chance = 0.2, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.04, min = 1, max = 1 },
	},

	-- The voxel creatures. Each drops what it is made of, plus a small chance
	-- of the shared magic material.
	Lasereye = {
		{ item = "Gel", chance = 1, min = 2, max = 3 },
		{ item = "EssenceShard", chance = 0.12, min = 1, max = 1 },
	},

	Snowman = {
		{ item = "Snow", chance = 1, min = 2, max = 4 },
		{ item = "Coal", chance = 0.6, min = 1, max = 2 },
		{ item = "Stick", chance = 0.4, min = 1, max = 2 },
	},

	GreenWasp = {
		{ item = "Herb", chance = 0.35, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.05, min = 1, max = 1 },
	},

	Shrike = {
		{ item = "Leather", chance = 0.6, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.08, min = 1, max = 1 },
	},

	Cobra = {
		{ item = "Leather", chance = 0.7, min = 1, max = 2 },
		{ item = "Herb", chance = 0.2, min = 1, max = 1 },
	},

	-- Silk is not an item yet; leather and the odd herb from its lair.
	GreenSpider = {
		{ item = "Leather", chance = 0.5, min = 1, max = 2 },
		{ item = "Herb", chance = 0.35, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.05, min = 1, max = 1 },
	},

	-- Vermin: a scrap of leather now and then, and the Crimson's own dirt.
	EvilRat = {
		{ item = "Leather", chance = 0.3, min = 1, max = 1 },
		{ item = "CrimsonDirt", chance = 0.25, min = 1, max = 2 },
	},

	-- A big animal: a good haul of leather, sometimes the magic material.
	Gorilla = {
		{ item = "Leather", chance = 1, min = 2, max = 4 },
		{ item = "EssenceShard", chance = 0.15, min = 1, max = 1 },
	},

	-- A tough hide, and now and then the magic material.
	Pentasaurus = {
		{ item = "Leather", chance = 1, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 0.08, min = 1, max = 1 },
	},

	-- The Corruption made flesh: its ground, and a fair chance of the magic material.
	WormyHorror = {
		{ item = "CorruptedDirt", chance = 0.6, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 0.2, min = 1, max = 2 },
	},

	-- A priest's purse: herbs from its satchel, and the magic material.
	RabbicCleric = {
		{ item = "Herb", chance = 0.7, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
		{ item = "HallowedDirt", chance = 0.3, min = 1, max = 2 },
	},

	-- Gel-slick scales and swamp herbs caught in its teeth.
	FootedPiranha = {
		{ item = "Gel", chance = 0.4, min = 1, max = 1 },
		{ item = "Herb", chance = 0.3, min = 1, max = 1 },
	},

	-- A bear's hide, and the mage's reagents.
	BearidWizard = {
		{ item = "Leather", chance = 1, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
		{ item = "ManaPotion", chance = 0.1, min = 1, max = 1 },
	},

	-- Leather, the Crimson's dirt, and sometimes the magic material.
	PitDevil = {
		{ item = "Leather", chance = 1, min = 1, max = 2 },
		{ item = "CrimsonDirt", chance = 0.5, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},

	-- Shell and swamp: leather from its hide, herbs off its back, and now
	-- and then the magic material.
	CrabMonster = {
		{ item = "Leather", chance = 1, min = 1, max = 3 },
		{ item = "Herb", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.2, min = 1, max = 2 },
	},

	-- A stretched hide, the Corruption's dirt, and as often as not the magic
	-- material - it is hard to kill well.
	Longleg = {
		{ item = "Leather", chance = 0.7, min = 1, max = 2 },
		{ item = "CorruptedDirt", chance = 0.5, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 0.35, min = 1, max = 2 },
	},

	-- A heavy hide, and a fair chance of the metal off its axes.
	OgreBrute = {
		{ item = "Leather", chance = 1, min = 2, max = 4 },
		{ item = "GoldOre", chance = 0.3, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.2, min = 1, max = 2 },
	},

	-- A magician's pockets: mana, the Hallow's dirt, sometimes the magic
	-- material. (Its decoys have no table, so they drop nothing.)
	CatMagician = {
		{ item = "ManaPotion", chance = 0.4, min = 1, max = 1 },
		{ item = "HallowedDirt", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
	},

	-- A shaman's bag: snow, mana and herbs, and sometimes the magic material.
	GoatShaman = {
		{ item = "Snow", chance = 0.6, min = 1, max = 3 },
		{ item = "ManaPotion", chance = 0.3, min = 1, max = 1 },
		{ item = "Herb", chance = 0.4, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},

	-- A warrior's hide and purse: leather, gold now and then, and the magic
	-- material.
	TigerBlademaster = {
		{ item = "Leather", chance = 1, min = 1, max = 3 },
		{ item = "GoldOre", chance = 0.25, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
	},

	-- Scraps: a bit of hide and the Corruption's dirt.
	ZombieRat = {
		{ item = "Leather", chance = 0.3, min = 1, max = 1 },
		{ item = "CorruptedDirt", chance = 0.3, min = 1, max = 2 },
	},

	-- Rock and fire: coal for certain, the Crimson's dirt, and a good chance of
	-- the magic material.
	LavaGolem = {
		{ item = "Coal", chance = 1, min = 3, max = 6 },
		{ item = "CrimsonDirt", chance = 0.5, min = 2, max = 4 },
		{ item = "EssenceShard", chance = 0.4, min = 1, max = 3 },
	},

	-- A thin hide, and now and then the magic material.
	BatMutant = {
		{ item = "Leather", chance = 0.6, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.15, min = 1, max = 1 },
	},

	-- A bird's worth: a bit of leather (no feathers in the game yet).
	Rooster = {
		{ item = "Leather", chance = 0.5, min = 1, max = 1 },
		{ item = "Herb", chance = 0.3, min = 1, max = 1 },
	},

	-- A big hide: plenty of leather.
	Auroch = {
		{ item = "Leather", chance = 1, min = 2, max = 4 },
	},

	-- Scaled hide, swamp herbs, and now and then the magic material.
	LizardWarrior = {
		{ item = "Leather", chance = 1, min = 1, max = 2 },
		{ item = "Herb", chance = 0.4, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},

	-- Little: a scrap of hide, the Crimson's dirt.
	VampireDuck = {
		{ item = "Leather", chance = 0.4, min = 1, max = 1 },
		{ item = "CrimsonDirt", chance = 0.4, min = 1, max = 2 },
	},

	-- A spotted hide, the Corruption's dirt, and a fair chance of the magic
	-- material.
	SpottedDemon = {
		{ item = "Leather", chance = 1, min = 1, max = 2 },
		{ item = "CorruptedDirt", chance = 0.5, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
	},

	-- A lord's purse and a wolf's pelt: leather, gold, and the magic material.
	WerewolfLord = {
		{ item = "Leather", chance = 1, min = 2, max = 3 },
		{ item = "GoldOre", chance = 0.4, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 0.35, min = 1, max = 2 },
	},

	-- A scrap of hide.
	Beagle = {
		{ item = "Leather", chance = 0.6, min = 1, max = 1 },
	},

	-- A hide.
	BeisaOryx = {
		{ item = "Leather", chance = 1, min = 1, max = 2 },
	},

	-- A great deal of hide, and now and then the magic material.
	Bronto = {
		{ item = "Leather", chance = 1, min = 3, max = 6 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
	},

	-- A scaly hide.
	GreenRaptor = {
		{ item = "Leather", chance = 0.7, min = 1, max = 1 },
	},

	-- A monk's few things: the Hallow's dirt, a little mana, sometimes the magic material.
	CatMonk = {
		{ item = "HallowedDirt", chance = 0.5, min = 1, max = 2 },
		{ item = "ManaPotion", chance = 0.2, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},

	-- Powder and shot: coal, and now and then some metal worth having.
	Cannon = {
		{ item = "Coal", chance = 1, min = 2, max = 4 },
		{ item = "GoldOre", chance = 0.2, min = 1, max = 2 },
	},

	-- A brute's haul: the Crimson's dirt, the magic material more often than not, some gold.
	PinkyDemon = {
		{ item = "CrimsonDirt", chance = 1, min = 2, max = 4 },
		{ item = "EssenceShard", chance = 0.6, min = 1, max = 3 },
		{ item = "GoldOre", chance = 0.3, min = 1, max = 3 },
	},

	-- Slime and the Corruption's dirt, and now and then the magic material.
	HandlessNorg = {
		{ item = "Gel", chance = 0.6, min = 1, max = 3 },
		{ item = "CorruptedDirt", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},

	-- A ringed pelt, the Hallow's dirt, and sometimes the magic material.
	LemurianWarrior = {
		{ item = "Leather", chance = 0.8, min = 1, max = 2 },
		{ item = "HallowedDirt", chance = 0.4, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},

	-- Rare, so it pays: a stack of gel, the magic material for certain, and
	-- a fair chance of gold.
	RainbowSlime = {
		{ item = "Gel", chance = 1, min = 12, max = 20 },
		{ item = "EssenceShard", chance = 1, min = 2, max = 4 },
		{ item = "GoldOre", chance = 0.5, min = 2, max = 5 },
	},
}

--[[
	Rolls one enemy's table.

	Returns an array of { item, amount }, which may be empty. The random source
	is passed in rather than made here so a caller that wants a reproducible
	kill - a test, a seeded replay - can have one.
]]
function EnemyDrops.roll(enemyName: string, random: Random): { { item: string, amount: number } }
	local rows = EnemyDrops.Tables[enemyName]
	local dropped = {}

	if type(rows) ~= "table" then
		return dropped
	end

	for _, row in ipairs(rows) do
		if random:NextNumber() <= (row.chance or 0) then
			local low = math.max(1, math.floor(row.min or 1))
			local high = math.max(low, math.floor(row.max or low))

			table.insert(dropped, {
				item = row.item,
				amount = random:NextInteger(low, high),
			})
		end
	end

	return dropped
end

return EnemyDrops
