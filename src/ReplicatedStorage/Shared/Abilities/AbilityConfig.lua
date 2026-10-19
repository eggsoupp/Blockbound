-- Active player abilities. Removed names are rejected by the existing loadout,
-- storage and private-scroll restore filters, so old saves cannot cast them.
local Plan = require(script.Parent.StarterPlan)
local AbilityConfig = {}
AbilityConfig.RequestsPerSecond = 8
AbilityConfig.MaxMana = 100
AbilityConfig.ManaRegenPerSecond = 2
AbilityConfig.SlotCount = 3
AbilityConfig.SlotKeys = {Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.V}
AbilityConfig.DefaultCastWeapon = "TestSword"
AbilityConfig.BroadcastRadius = 520
AbilityConfig.Definitions = {
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
