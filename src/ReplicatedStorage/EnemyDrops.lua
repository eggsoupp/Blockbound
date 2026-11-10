-- Enemy loot, keyed by EnemyConfig.Definitions names.
-- Each row rolls independently; chance is 0..1, min/max are inclusive.
-- Progression ores and gel remain available. Creature materials use atlas
-- entries. Reserved weapons, keys and unopened bags are not loot rewards.
-- CatMagicianDecoy is an illusion and deliberately awards nothing.
local EnemyDrops = {}

EnemyDrops.Tables = {
	AshenLich = {
		{ item = "Bone", chance = 1, min = 2, max = 4 },
		{ item = "Ectoplasm", chance = 0.8, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 1, min = 2, max = 4 },
		{ item = "VoidCrystal", chance = 0.2, min = 1, max = 1 },
	},
	BrassSentinel = {
		{ item = "IronOre", chance = 1, min = 4, max = 8 },
		{ item = "GoldOre", chance = 0.6, min = 1, max = 3 },
		{ item = "Coal", chance = 1, min = 2, max = 4 },
		{ item = "EssenceShard", chance = 1, min = 2, max = 3 },
	},
	MantisReaver = {
		{ item = "GreenScale", chance = 1, min = 1, max = 3 },
		{ item = "Claws", chance = 0.5, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 1, min = 1, max = 3 },
	},
	MoonmothMatriarch = {
		{ item = "Feather", chance = 0.8, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 1, min = 2, max = 4 },
		{ item = "GoldOre", chance = 0.3, min = 1, max = 2 },
	},
	Sporeking = {
		{ item = "Herb", chance = 1, min = 2, max = 5 },
		{ item = "RottenChunk", chance = 0.4, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 1, min = 1, max = 3 },
	},
	RimewyrmDrake = {
		{ item = "Leather", chance = 1, min = 2, max = 4 },
		{ item = "Fang", chance = 0.6, min = 1, max = 2 },
		{ item = "Claws", chance = 0.5, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 1, min = 2, max = 4 },
		{ item = "MythrilOre", chance = 0.3, min = 1, max = 2 },
	},
	AbyssalKraken = {
		{ item = "Gel", chance = 1, min = 3, max = 6 },
		{ item = "Lens", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 1, min = 2, max = 4 },
		{ item = "VoidCrystal", chance = 0.3, min = 1, max = 1 },
	},
	Shardstinger = {
		{ item = "Claws", chance = 0.5, min = 1, max = 2 },
		{ item = "MythrilOre", chance = 0.5, min = 1, max = 2 },
		{ item = "VoidCrystal", chance = 0.4, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 1, min = 2, max = 3 },
	},
	Gloomrider = {
		{ item = "Bone", chance = 1, min = 2, max = 4 },
		{ item = "Ectoplasm", chance = 0.8, min = 1, max = 3 },
		{ item = "IronOre", chance = 0.7, min = 2, max = 4 },
		{ item = "DarkHorns", chance = 0.3, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 1, min = 2, max = 4 },
	},
	TempestDjinn = {
		{ item = "GoldOre", chance = 1, min = 2, max = 4 },
		{ item = "EssenceShard", chance = 1, min = 3, max = 5 },
		{ item = "VoidCrystal", chance = 0.25, min = 1, max = 1 },
	},
	BlueSlime = {
		{ item = "Gel", chance = 1, min = 1, max = 2 },
	},
	GreenSlime = {
		{ item = "Gel", chance = 1, min = 1, max = 2 },
		{ item = "GreenGel", chance = 0.35, min = 1, max = 1 },
	},
	Ghost = {
		{ item = "Ectoplasm", chance = 0.65, min = 1, max = 2 },
	},
	SlimeEmperor = {
		{ item = "Gel", chance = 1, min = 40, max = 60 },
		{ item = "PinkGel", chance = 1, min = 3, max = 6 },
	},
	AllSeeingEye = {
		{ item = "GoldOre", chance = 1, min = 10, max = 18 },
		{ item = "EssenceShard", chance = 1, min = 4, max = 8 },
		{ item = "MythrilOre", chance = 0.5, min = 2, max = 5 },
		{ item = "SoulofSight", chance = 1, min = 1, max = 2 },
		{ item = "BlackLens", chance = 0.3, min = 1, max = 1 },
	},
	DemonEye = {
		{ item = "Lens", chance = 0.65, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.06, min = 1, max = 1 },
	},
	ServantEye = {
		{ item = "Lens", chance = 0.15, min = 1, max = 1 },
	},
	Blightborer = {
		{ item = "MythrilOre", chance = 1, min = 6, max = 12 },
		{ item = "EssenceShard", chance = 1, min = 5, max = 9 },
		{ item = "VoidCrystal", chance = 0.35, min = 1, max = 2 },
		{ item = "GreenScale", chance = 1, min = 4, max = 8 },
	},
	Blightling = {
		{ item = "GreenScale", chance = 0.2, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.04, min = 1, max = 1 },
	},
	Signus = {
		{ item = "MythrilOre", chance = 1, min = 5, max = 9 },
		{ item = "EssenceShard", chance = 1, min = 5, max = 8 },
		{ item = "SoulofFright", chance = 1, min = 1, max = 2 },
		{ item = "VoidLens", chance = 0.25, min = 1, max = 1 },
	},
	Lasereye = {
		{ item = "Lens", chance = 1, min = 1, max = 1 },
		{ item = "Gel", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.12, min = 1, max = 1 },
	},
	Snowman = {
		{ item = "Snow", chance = 1, min = 2, max = 4 },
		{ item = "Coal", chance = 0.6, min = 1, max = 2 },
		{ item = "Stick", chance = 0.4, min = 1, max = 2 },
	},
	GreenWasp = {
		{ item = "Stinger", chance = 0.7, min = 1, max = 1 },
		{ item = "VenomSac", chance = 0.2, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.05, min = 1, max = 1 },
	},
	Shrike = {
		{ item = "Feather", chance = 1, min = 1, max = 2 },
		{ item = "Claws", chance = 0.2, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.08, min = 1, max = 1 },
	},
	Cobra = {
		{ item = "GreenScale", chance = 0.7, min = 1, max = 2 },
		{ item = "Fang", chance = 0.35, min = 1, max = 1 },
		{ item = "VenomSac", chance = 0.2, min = 1, max = 1 },
	},
	GreenSpider = {
		{ item = "Silk", chance = 1, min = 1, max = 2 },
		{ item = "Cobweb", chance = 0.4, min = 1, max = 2 },
		{ item = "VenomSac", chance = 0.25, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.05, min = 1, max = 1 },
	},
	EvilRat = {
		{ item = "Pelt", chance = 0.3, min = 1, max = 1 },
		{ item = "Fang", chance = 0.15, min = 1, max = 1 },
	},
	Gorilla = {
		{ item = "Leather", chance = 1, min = 2, max = 4 },
		{ item = "DarkPelt", chance = 0.4, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.15, min = 1, max = 1 },
	},
	Pentasaurus = {
		{ item = "Leather", chance = 1, min = 1, max = 3 },
		{ item = "Horns", chance = 0.4, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.08, min = 1, max = 1 },
	},
	WormyHorror = {
		{ item = "RottenChunk", chance = 0.8, min = 1, max = 3 },
		{ item = "CorruptedDirt", chance = 0.3, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.2, min = 1, max = 2 },
	},
	RabbicCleric = {
		{ item = "Herb", chance = 0.7, min = 1, max = 3 },
		{ item = "Hallowlily", chance = 0.3, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},
	FootedPiranha = {
		{ item = "GreenScale", chance = 0.6, min = 1, max = 1 },
		{ item = "Fang", chance = 0.3, min = 1, max = 1 },
	},
	BearidWizard = {
		{ item = "Leather", chance = 1, min = 1, max = 3 },
		{ item = "Pelt", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
		{ item = "ManaPotion", chance = 0.1, min = 1, max = 1 },
	},
	PitDevil = {
		{ item = "Leather", chance = 1, min = 1, max = 2 },
		{ item = "DarkHorns", chance = 0.35, min = 1, max = 1 },
		{ item = "FleshChunk", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},
	CrabMonster = {
		{ item = "CrabShell", chance = 1, min = 1, max = 3 },
		{ item = "Claws", chance = 0.4, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.2, min = 1, max = 2 },
	},
	Longleg = {
		{ item = "Leather", chance = 0.7, min = 1, max = 2 },
		{ item = "RottenChunk", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.35, min = 1, max = 2 },
	},
	OgreBrute = {
		{ item = "Leather", chance = 1, min = 2, max = 4 },
		{ item = "IronOre", chance = 0.3, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.2, min = 1, max = 2 },
	},
	CatMagician = {
		{ item = "ManaPotion", chance = 0.4, min = 1, max = 1 },
		{ item = "PurpleCloth", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
	},
	CatMagicianDecoy = {
	},
	GoatShaman = {
		{ item = "Wool", chance = 0.8, min = 1, max = 3 },
		{ item = "ManaPotion", chance = 0.3, min = 1, max = 1 },
		{ item = "Shiverthorn", chance = 0.4, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},
	TigerBlademaster = {
		{ item = "Leather", chance = 1, min = 1, max = 3 },
		{ item = "Claws", chance = 0.4, min = 1, max = 1 },
		{ item = "GoldOre", chance = 0.25, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
	},
	ZombieRat = {
		{ item = "RottenChunk", chance = 0.5, min = 1, max = 1 },
		{ item = "Bone", chance = 0.25, min = 1, max = 1 },
	},
	LavaGolem = {
		{ item = "Coal", chance = 1, min = 3, max = 6 },
		{ item = "EmberDust", chance = 0.7, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 0.4, min = 1, max = 3 },
	},
	BatMutant = {
		{ item = "BatWing", chance = 0.65, min = 1, max = 2 },
		{ item = "Fang", chance = 0.25, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.15, min = 1, max = 1 },
	},
	Rooster = {
		{ item = "Feather", chance = 1, min = 1, max = 2 },
		{ item = "Egg", chance = 0.2, min = 1, max = 1 },
	},
	Auroch = {
		{ item = "Leather", chance = 1, min = 2, max = 4 },
		{ item = "Horns", chance = 0.4, min = 1, max = 1 },
	},
	LizardWarrior = {
		{ item = "Leather", chance = 1, min = 1, max = 2 },
		{ item = "GreenScale", chance = 0.65, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},
	VampireDuck = {
		{ item = "BlackFeather", chance = 0.6, min = 1, max = 2 },
		{ item = "BloodSac", chance = 0.3, min = 1, max = 1 },
	},
	SpottedDemon = {
		{ item = "Leather", chance = 1, min = 1, max = 2 },
		{ item = "DarkHorns", chance = 0.35, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
	},
	WerewolfLord = {
		{ item = "Leather", chance = 1, min = 2, max = 3 },
		{ item = "DarkPelt", chance = 0.75, min = 1, max = 2 },
		{ item = "Claws", chance = 0.4, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.35, min = 1, max = 2 },
	},
	Beagle = {
		{ item = "Pelt", chance = 0.6, min = 1, max = 1 },
	},
	BeisaOryx = {
		{ item = "Leather", chance = 1, min = 1, max = 2 },
		{ item = "Horns", chance = 0.35, min = 1, max = 1 },
	},
	Bronto = {
		{ item = "Leather", chance = 1, min = 3, max = 6 },
		{ item = "Bone", chance = 0.5, min = 2, max = 4 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
	},
	GreenRaptor = {
		{ item = "GreenScale", chance = 0.7, min = 1, max = 1 },
		{ item = "Claws", chance = 0.25, min = 1, max = 1 },
	},
	CatMonk = {
		{ item = "BlueCloth", chance = 0.5, min = 1, max = 2 },
		{ item = "ManaPotion", chance = 0.2, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},
	Cannon = {
		{ item = "Coal", chance = 1, min = 2, max = 4 },
		{ item = "IronOre", chance = 0.4, min = 1, max = 2 },
	},
	PinkyDemon = {
		{ item = "FleshChunk", chance = 1, min = 2, max = 4 },
		{ item = "DarkHorns", chance = 0.4, min = 1, max = 1 },
		{ item = "EssenceShard", chance = 0.6, min = 1, max = 3 },
		{ item = "GoldOre", chance = 0.3, min = 1, max = 3 },
	},
	HandlessNorg = {
		{ item = "PurpleGel", chance = 0.6, min = 1, max = 3 },
		{ item = "RottenChunk", chance = 0.5, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},
	LemurianWarrior = {
		{ item = "Pelt", chance = 0.8, min = 1, max = 2 },
		{ item = "Leather", chance = 0.4, min = 1, max = 2 },
		{ item = "EssenceShard", chance = 0.25, min = 1, max = 2 },
	},
	AxeGolem = {
		{ item = "Wood", chance = 1, min = 2, max = 4 },
		{ item = "Stick", chance = 0.5, min = 1, max = 3 },
		{ item = "EssenceShard", chance = 0.3, min = 1, max = 2 },
	},
	RainbowSlime = {
		{ item = "Gel", chance = 1, min = 12, max = 20 },
		{ item = "PinkGel", chance = 1, min = 2, max = 4 },
		{ item = "EssenceShard", chance = 1, min = 2, max = 4 },
		{ item = "GoldOre", chance = 0.5, min = 2, max = 5 },
	},
}

function EnemyDrops.roll(enemyName: string, random: Random): { { item: string, amount: number } }
	local rows = EnemyDrops.Tables[enemyName]
	local dropped = {}

	if type(rows) ~= "table" then
		return dropped
	end

	for _, row in ipairs(rows) do
		if random:NextNumber() < (row.chance or 0) then
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
