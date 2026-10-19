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
		Both slimes drop the same thing for now.

		Common on purpose: this is the drop being used to prove the projectile,
		the trail colour and the arrival line all work, and a one-in-fifty drop
		would take a long afternoon to see twice.
	]]
	BlueSlime = {
		{ item = "Wood", chance = 0.8, min = 1, max = 2 },
	},

	GreenSlime = {
		{ item = "Wood", chance = 0.8, min = 1, max = 2 },
	},

	--[[
		Nothing yet.

		Deliberately empty rather than absent, so that "the Ghost has no drops"
		is a decision somebody wrote down and not an entry somebody forgot.
	]]
	Ghost = {},

	-- A boss should be worth the fight. Guaranteed, and a lot of it: the
	-- quantities are the only thing separating this from farming slimes.
	SlimeEmperor = {
		{ item = "Wood", chance = 1, min = 20, max = 32 },
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
