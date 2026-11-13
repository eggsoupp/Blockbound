--[[
	AspectConfig

	Aspects are what a player owns now. An aspect is a themed set of abilities
	(4-5 when it is finished; fewer today, since no abilities were made for
	this change). Abilities themselves still live in AbilityConfig, with their
	cooldowns, mana costs and modules; this file only says which aspect each
	one belongs to.

	THE RULES (enforced by AbilityLoadout on the server)

	  - A player has ONE active aspect. Its abilities are the only ones they
	    can put on Z / X / V / F and cast.
	  - Using another aspect replaces the active one, and the replaced aspect is
	    gone for good.
	  - Storage keeps aspects that are not in use: one copy of every aspect for
	    free, plus extra copies in bought storage slots (StorageConfig).
	  - Wishes and scrolls hand out aspects, not abilities.

	ADDING AN ABILITY TO AN ASPECT is adding its AbilityConfig name to the
	aspect's `abilities` list. validate() fails at start-up if an ability is in
	no aspect, in two, or is not a real ability.

	`abilities` is in slot order: when an aspect becomes active, the first
	SlotCount of them fill Z / X / V / F. The tutorial's three starters (Fireball,
	Wind Burst, Water Blade) are first in their aspects for that reason.
]]

local AbilityConfig = require(script.Parent.AbilityConfig)

local AspectConfig = {}

AspectConfig.Definitions = {
	Ember = {
		displayName = "Ember", rarity = "Common", order = 1, icon = "tome_fire",
		blurb = "Fire thrown, coiled, focused.",
		abilities = { "Fireball", "SerpentFlare", "HeliosLance" },
	},
	Tide = {
		displayName = "Tide", rarity = "Common", order = 2, icon = "tome_water",
		blurb = "Water that cuts and floods.",
		abilities = { "WaterBlade", "Deluge", "Tidecaller" },
	},
	Gale = {
		displayName = "Gale", rarity = "Uncommon", order = 3, icon = "feather",
		blurb = "Wind, and arrows riding it.",
		abilities = { "WindBurst", "SkyfallVolley" },
	},
	Stone = {
		displayName = "Stone", rarity = "Uncommon", order = 4, icon = "shield_iron",
		blurb = "The ground, raised as a wall.",
		abilities = { "BlockWall" },
	},
	Storm = {
		displayName = "Storm", rarity = "Rare", order = 5, icon = "tome_lightning",
		blurb = "Thunder and a lightning step.",
		abilities = { "Thunderhead", "EchoStep" },
	},
	Ink = {
		displayName = "Ink", rarity = "Rare", order = 6, icon = "orb_shadow",
		blurb = "Ink strokes, painted petals.",
		abilities = { "SumiWhirl", "BlossomRoad" },
	},
	Abyss = {
		displayName = "Abyss", rarity = "Epic", order = 7, icon = "tome_void",
		blurb = "The dark below and its blight.",
		abilities = { "AbyssGate", "WraithfireOrb" },
	},
	Chaos = {
		displayName = "Chaos", rarity = "Legendary", order = 8, icon = "tome_blood",
		blurb = "Rifts, tempests, world's end.",
		abilities = { "Cataclysm", "RiftMaelstrom", "VioletTempest" },
	},
	Celestial = {
		displayName = "Celestial", rarity = "Legendary", order = 9, icon = "moon_charm_gold",
		blurb = "Starlight and falling comets.",
		abilities = { "CelestialLance", "AzureComet", "EclipsePrison", "Penumbra" },
	},
	Divinity = {
		displayName = "Divinity", rarity = "Legendary", order = 10, icon = "sun_charm",
		blurb = "Dawn light and holy judgement.",
		abilities = { "Dawnbreaker", "AstralVerdict" },
	},
}

-- ability name -> aspect name, built once.
local aspectOfAbility: { [string]: string } = {}
for aspectName, definition in pairs(AspectConfig.Definitions) do
	for _, abilityName in ipairs(definition.abilities) do
		-- A second owner is reported by validate(); the first one wins until then.
		if aspectOfAbility[abilityName] == nil then
			aspectOfAbility[abilityName] = aspectName
		end
	end
end

local function squash(text: string): string
	return (string.gsub(string.lower(text), "%s", ""))
end

function AspectConfig.get(aspectName: string?)
	if type(aspectName) ~= "string" then
		return nil
	end
	return AspectConfig.Definitions[aspectName]
end

-- Every aspect name, in display order (common first, legendaries last).
function AspectConfig.names(): { string }
	local names = {}
	for name in pairs(AspectConfig.Definitions) do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		return (AspectConfig.Definitions[a].order or 0) < (AspectConfig.Definitions[b].order or 0)
	end)
	return names
end

-- The aspect an ability belongs to, or nil.
function AspectConfig.aspectOf(abilityName: string?): string?
	if type(abilityName) ~= "string" then
		return nil
	end
	return aspectOfAbility[abilityName]
end

-- An aspect's abilities that exist in AbilityConfig, in slot order. A copy.
function AspectConfig.abilitiesOf(aspectName: string?): { string }
	local definition = AspectConfig.get(aspectName)
	local list = {}
	if definition then
		for _, abilityName in ipairs(definition.abilities) do
			if AbilityConfig.get(abilityName) then
				table.insert(list, abilityName)
			end
		end
	end
	return list
end

function AspectConfig.contains(aspectName: string?, abilityName: string?): boolean
	return abilityName ~= nil and aspectName ~= nil and aspectOfAbility[abilityName] == aspectName
end

function AspectConfig.displayName(aspectName: string?): string
	local definition = AspectConfig.get(aspectName)
	return if definition then definition.displayName or aspectName else tostring(aspectName)
end

--[[
	The real aspect behind what someone typed: "ember", "Ember Aspect" and
	"EMBER" all find Ember. nil when nothing matches.
]]
function AspectConfig.resolve(text: string?): string?
	if type(text) ~= "string" then
		return nil
	end
	local wanted = squash(text)
	wanted = string.gsub(wanted, "aspect$", "")
	if wanted == "" then
		return nil
	end
	for name, definition in pairs(AspectConfig.Definitions) do
		if string.lower(name) == wanted or squash(definition.displayName or name) == wanted then
			return name
		end
	end
	return nil
end

--[[
	An aspect from an aspect name OR the name of one of its abilities. For
	scrolls and commands authored before aspects existed: a scroll that says
	"Fireball" now teaches Ember.
]]
function AspectConfig.resolveAny(text: string?): string?
	local aspect = AspectConfig.resolve(text)
	if aspect then
		return aspect
	end
	local ability = AbilityConfig.resolve(text)
	return ability and aspectOfAbility[ability] or nil
end

-- "Fireball, Serpent Flare, Helios Lance": the line under an aspect's name.
function AspectConfig.abilityLine(aspectName: string?): string
	local parts = {}
	for _, abilityName in ipairs(AspectConfig.abilitiesOf(aspectName)) do
		local definition = AbilityConfig.get(abilityName)
		table.insert(parts, definition.displayName or abilityName)
	end
	return table.concat(parts, ", ")
end

local RARITIES = { Common = true, Uncommon = true, Rare = true, Epic = true, Legendary = true }

-- Fails loudly at start-up rather than leaving an ability nobody can get.
function AspectConfig.validate()
	local owner = {}
	for aspectName, definition in pairs(AspectConfig.Definitions) do
		assert(RARITIES[definition.rarity], string.format("[AspectConfig] '%s' has no valid rarity", aspectName))
		assert(type(definition.abilities) == "table" and #definition.abilities > 0,
			string.format("[AspectConfig] '%s' has no abilities", aspectName))
		for _, abilityName in ipairs(definition.abilities) do
			assert(AbilityConfig.get(abilityName),
				string.format("[AspectConfig] '%s' lists '%s', which is not in AbilityConfig", aspectName, abilityName))
			assert(owner[abilityName] == nil, string.format(
				"[AspectConfig] '%s' is in both '%s' and '%s'", abilityName, tostring(owner[abilityName]), aspectName))
			owner[abilityName] = aspectName
		end
	end
	for _, abilityName in ipairs(AbilityConfig.names()) do
		assert(owner[abilityName], string.format("[AspectConfig] ability '%s' belongs to no aspect", abilityName))
	end
end

return AspectConfig
