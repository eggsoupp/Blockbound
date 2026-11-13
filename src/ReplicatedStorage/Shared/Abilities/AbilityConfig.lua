-- Active player abilities. Removed names are rejected by the existing loadout,
-- storage and private-scroll restore filters, so old saves cannot cast them.
local Plan = require(script.Parent.StarterPlan)
local AbilityConfig = {}
AbilityConfig.RequestsPerSecond = 8
AbilityConfig.MaxMana = 100
AbilityConfig.ManaRegenPerSecond = 2
AbilityConfig.SlotCount = 4
AbilityConfig.SlotKeys = {Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.V, Enum.KeyCode.F}
AbilityConfig.DefaultCastWeapon = "TestSword"
AbilityConfig.BroadcastRadius = 520
AbilityConfig.Definitions = {
 VioletTempest = {
  displayName="Violet Tempest", rarity="Legendary", server="ReferenceAbilities", vfx="LegendaryVFX",
  cooldown=18, manaCost=40, requiresTarget=true, castRange=110, maxConcurrent=1,
 },
 CelestialLance = {
  displayName="Celestial Lance", rarity="Legendary", server="ReferenceAbilities", vfx="LegendaryVFX",
  cooldown=16, manaCost=38, requiresTarget=true, castRange=140, maxConcurrent=1,
 },
 -- Keep the saved identifier so existing loadouts and scrolls retain this ability.
 WraithfireOrb = {
  displayName="Blighted Fireball", rarity="Legendary", server="ReferenceAbilities", vfx="LegendaryVFX",
  cooldown=18, manaCost=42, requiresTarget=true, castRange=120, maxConcurrent=1,
 },
 RiftMaelstrom = {
  displayName="Rift Maelstrom", rarity="Legendary", server="ReferenceAbilities", vfx="LegendaryVFX",
  cooldown=22, manaCost=48, requiresTarget=true, castRange=110, maxConcurrent=1,
 },
 Cataclysm = {
  displayName="Cataclysm", rarity="Legendary", server="Cataclysm", vfx="CataclysmVFX",
  cooldown=45, manaCost=80, requiresTarget=true, castRange=220, maxConcurrent=1,
 },
 Fireball = {
  displayName="Fireball", rarity="Common", server="StarterAbilities", vfx="StarterVFX",
  cooldown=5, manaCost=10, requiresTarget=true, castRange=90, maxConcurrent=1, tuning=Plan.Fireball,
 },
 WindBurst = {
  displayName="Wind Burst", rarity="Common", server="StarterAbilities", vfx="StarterVFX",
  cooldown=5, manaCost=10, requiresTarget=false, maxConcurrent=1, tuning=Plan.WindBurst,
 },
 WaterBlade = {
  displayName="Water Blade", rarity="Common", server="StarterAbilities", vfx="StarterVFX",
  cooldown=6, manaCost=12, requiresTarget=true, castRange=80, maxConcurrent=1, tuning=Plan.WaterBlade,
 },
 EchoStep = {
  displayName="Echo Step", rarity="Common", server="StarterAbilities", vfx="StarterVFX",
  cooldown=7, manaCost=14, requiresTarget=false, maxConcurrent=1, tuning=Plan.EchoStep,
 },
 BlockWall = {
  displayName="Block Wall", rarity="Common", server="StarterAbilities", vfx="StarterVFX",
  cooldown=10, manaCost=16, requiresTarget=false, maxConcurrent=1, tuning=Plan.BlockWall,
 },
 Dawnbreaker = {
  displayName="Dawnbreaker", rarity="Rare", server="Dawnbreaker", vfx="DawnbreakerVFX",
  cooldown=10, manaCost=28, requiresTarget=true, castRange=90, maxConcurrent=1,
 },
 Deluge = {
  displayName="Deluge", rarity="Uncommon", server="Deluge", vfx="DelugeVFX",
  cooldown=9, manaCost=22, requiresTarget=true, castRange=70, maxConcurrent=1,
 },
 SkyfallVolley = {
  displayName="Skyfall Volley", rarity="Epic", server="SkyfallVolley", vfx="SkyfallVFX",
  cooldown=14, manaCost=35, requiresTarget=true, castRange=80, maxConcurrent=1,
 },
 SumiWhirl = {
  displayName="Sumi Whirl", rarity="Rare", server="SumiWhirl", vfx="SumiVFX",
  cooldown=8, manaCost=24, requiresTarget=false, maxConcurrent=1,
 },
 BlossomRoad = {
  displayName="Blossom Road", rarity="Rare", server="BlossomRoad", vfx="BlossomVFX",
  cooldown=12, manaCost=30, requiresTarget=true, castRange=60, maxConcurrent=1,
 },
 HeliosLance = {
  displayName="Helios Lance", rarity="Epic", server="HeliosLance", vfx="HeliosVFX",
  cooldown=16, manaCost=40, requiresTarget=true, castRange=70, maxConcurrent=1,
 },
 AbyssGate = {
  displayName="Abyss Gate", rarity="Legendary", server="AbyssGate", vfx="AbyssVFX",
  cooldown=20, manaCost=50, requiresTarget=true, castRange=75, maxConcurrent=1,
 },
 AzureComet = {
  displayName="Azure Comet", rarity="Rare", server="AzureComet", vfx="CometVFX",
  cooldown=11, manaCost=30, requiresTarget=true, castRange=85, maxConcurrent=1,
 },
 EclipsePrison = {
  displayName="Eclipse Prison", rarity="Legendary", server="EclipsePrison", vfx="EclipseVFX",
  cooldown=20, manaCost=50, requiresTarget=true, castRange=90, maxConcurrent=1,
 },
 -- Celestial's F: sink into the ground and come up where the mouse is (in the
 -- air too, as a burst and a streak).
 Penumbra = {
  displayName="Penumbra", rarity="Legendary", server="Penumbra", vfx="PenumbraVFX",
  cooldown=12, manaCost=34, requiresTarget=true, castRange=64, maxConcurrent=1,
 },
 Thunderhead = {
  displayName="Thunderhead", rarity="Epic", server="Thunderhead", vfx="ThunderVFX",
  cooldown=14, manaCost=36, requiresTarget=true, castRange=80, maxConcurrent=1,
 },
 Tidecaller = {
  displayName="Tidecaller", rarity="Uncommon", server="Tidecaller", vfx="TideVFX",
  cooldown=10, manaCost=22, requiresTarget=false, maxConcurrent=1,
 },
 SerpentFlare = {
  displayName="Serpent Flare", rarity="Epic", server="SerpentFlare", vfx="SerpentVFX",
  cooldown=14, manaCost=38, requiresTarget=true, castRange=80, maxConcurrent=1,
 },
 AstralVerdict = {
  displayName="Astral Verdict", rarity="Legendary", server="AstralVerdict", vfx="AstralVFX",
  cooldown=22, manaCost=55, requiresTarget=true, castRange=80, maxConcurrent=1,
 },
}

function AbilityConfig.get(abilityName: string?)
	if type(abilityName) ~= "string" then
		return nil
	end
	return AbilityConfig.Definitions[abilityName]
end

--[[
	Every ability name, alphabetically.

	Built fresh rather than cached: it is asked for by the /add command and by
	the error message that lists what a player could have typed instead, neither
	of which is a hot path.
]]
function AbilityConfig.names(): { string }
	local names = {}

	for name in pairs(AbilityConfig.Definitions) do
		table.insert(names, name)
	end

	table.sort(names)
	return names
end

--[[
	The real name behind whatever a player typed, or nil.

	Case-insensitive, and it ignores spaces, so "water blade", "WaterBlade" and
	"waterblade" all find the same ability. That is the whole reason this is
	here: a chat command that only accepts the exact internal spelling is a
	command that mostly reports failure.
]]
function AbilityConfig.resolve(text: string?): string?
	if type(text) ~= "string" then
		return nil
	end

	local wanted = string.gsub(string.lower(text), "%s", "")
	if wanted == "" then
		return nil
	end

	for name in pairs(AbilityConfig.Definitions) do
		local displayName = AbilityConfig.Definitions[name].displayName or name
		if string.lower(name) == wanted or string.gsub(string.lower(displayName), "%s", "") == wanted then
			return name
		end
	end

	return nil
end

--[[
	The key that casts slot `index`, or nil for a slot that has none.

	Slots without a key are not an error - SlotCount could be raised past the
	keys someone has bound - but the readout says so rather than showing a blank
	where a key should be.
]]
-- "18s  40 mana": the line the Tab menu shows under an ability.
function AbilityConfig.statsText(def): string
	local parts = {}
	if type(def.cooldown) == "number" then
		table.insert(parts, string.format("%gs", def.cooldown))
	end
	if type(def.manaCost) == "number" and def.manaCost > 0 then
		table.insert(parts, string.format("%d mana", def.manaCost))
	end
	return table.concat(parts, "  ")
end

function AbilityConfig.keyForSlot(index: number)
	return AbilityConfig.SlotKeys[index]
end

--[[
	Fails loudly at require time rather than leaving a slot nobody can press.
]]
function AbilityConfig.validate()
	assert(
		type(AbilityConfig.SlotCount) == "number" and AbilityConfig.SlotCount >= 1,
		"[AbilityConfig] SlotCount must be at least 1"
	)
	assert(
		#AbilityConfig.SlotKeys == AbilityConfig.SlotCount,
		string.format(
			"[AbilityConfig] SlotCount is %d but SlotKeys has %d entries; every slot needs a "
				.. "key or it can never be cast",
			AbilityConfig.SlotCount, #AbilityConfig.SlotKeys
		)
	)

	local seen = {}
	for index, key in ipairs(AbilityConfig.SlotKeys) do
		assert(
			typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode,
			string.format("[AbilityConfig] SlotKeys[%d] must be an Enum.KeyCode", index)
		)
		assert(
			not seen[key],
			string.format("[AbilityConfig] SlotKeys[%d] repeats %s", index, key.Name)
		)
		seen[key] = true
	end

	for name, definition in pairs(AbilityConfig.Definitions) do
		assert(
			type(definition.server) == "string" and definition.server ~= "",
			string.format("[AbilityConfig] '%s' needs a server module name", name)
		)
		assert(
			type(definition.cooldown) == "number" and definition.cooldown >= 0,
			string.format("[AbilityConfig] '%s' needs a non-negative cooldown", name)
		)
	end
end

return AbilityConfig
