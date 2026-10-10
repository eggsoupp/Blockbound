--[[
	WeaponConfig

	What a weapon puts into CombatConfig's arithmetic - a per-item question,
	which is why it is not in CombatConfig.

		WeaponConfig.get("IronSword")  -> stats, or nil if not a weapon

	Resolved first-hit-wins:
	  1. Overrides[name]        hand-tuned
	  2. ItemDefinitions buffs  an item declaring buffs.damage means it
	  3. the material tier      longest Tiers key prefixing the name
	  4. DefaultDamage

	Only classification == "Weapon" deals damage; a pickaxe mines and an axe
	harvests. That is checked by the caller, being an ItemDefinitions question.

	The numbers below are chosen, not derived - nothing recorded melee damage
	before. Anchored to the enemies that exist: BlueSlime/GreenSlime 25hp and
	Ghost 40hp against CopperSword's 7 is four and six hits. Retune freely.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local WeaponConfig = {}

-- Well short of mining reach (34), and deliberately past the enemies' own
-- contactRange (5): a player who can only hit what is already touching them
-- cannot fight anything that hurts on contact.
WeaponConfig.DefaultRange = 11

-- Total forward arc in degrees, so 120 is 60 either side of where you look.
-- Wide enough not to demand precision the mouse cannot express, narrow enough
-- to read as a swing rather than an aura.
WeaponConfig.DefaultArcDegrees = 120

-- The cap on damage per second, and why clicking faster does not win.
-- buffs.attackSpeed shortens it: 0.2 is 20% quicker.
WeaponConfig.DefaultCooldown = 0.55

-- Raising this turns every weapon into a cleave, which is a balance decision
-- rather than a tuning one.
WeaponConfig.DefaultMaxTargets = 1

WeaponConfig.DefaultDamage = 8

-- Matched as a PREFIX, longest first, exactly as ToolConfig.Materials is.
WeaponConfig.Tiers = {
	Wood = { damage = 5 },
	Stone = { damage = 6 },
	Copper = { damage = 7 },
	Iron = { damage = 10 },
	Gold = { damage = 13 },
	Mythril = { damage = 18 },
	Void = { damage = 26 },

	-- Mid-tier, so testing combat with the debug set is neither trivial nor a
	-- slog.
	Test = { damage = 12 },
}

-- Hand-tuned weapons; wins over both buffs and the tier table.
WeaponConfig.Overrides = {
	-- "LightLance" prefixes no tier, so without this it would fall through to
	-- DefaultDamage by accident rather than by decision. 25 sits between gold
	-- and mythril: a real weapon, without being the reason you carry it. That
	-- reason is Sacred Rain.
	LightLance = { damage = 35 },
	Thunderveil = { damage = 25 },
	Bloodfang = { damage = 22 },
	TestSword = { damage = 150 },
}

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

local resolved = {}

local function tierFor(itemName)
	local best, bestLength = nil, 0

	for name, tier in pairs(WeaponConfig.Tiers) do
		local length = #name
		if length > bestLength and string.sub(itemName, 1, length) == name then
			best, bestLength = tier, length
		end
	end

	return best
end

-- The `buffs` keys WeaponConfig.get reads below, and only from a Weapon.
-- ContentAudit reports any other buff on a weapon as doing nothing. Keep this
-- in step with the code that reads them.
WeaponConfig.BuffsRead = { "damage", "attackSpeed" }

-- Cached: asked on every swing, and the answer cannot change without a code
-- change. Non-weapons cache as `false` so a pickaxe swung a hundred times a
-- minute does not re-walk the tier table.
function WeaponConfig.get(itemName)
	if type(itemName) ~= "string" then
		return nil
	end

	local cached = resolved[itemName]
	if cached ~= nil then
		return cached or nil
	end

	local definition = ItemDefinitions[itemName]
	if not definition or definition.classification ~= "Weapon" then
		resolved[itemName] = false
		return nil
	end

	local override = WeaponConfig.Overrides[itemName]
	local buffs = definition.buffs
	local tier = tierFor(itemName)

	local damage = (override and override.damage)
		or (buffs and tonumber(buffs.damage))
		or (tier and tier.damage)
		or WeaponConfig.DefaultDamage

	local cooldown = (override and override.cooldown)
		or (tier and tier.cooldown)
		or WeaponConfig.DefaultCooldown

	-- Clamped so a future 1.5 cannot produce a zero or negative cooldown.
	local attackSpeed = buffs and tonumber(buffs.attackSpeed)
	if attackSpeed then
		cooldown *= math.clamp(1 - attackSpeed, 0.2, 2)
	end

	local stats = {
		name = itemName,
		damage = math.max(1, math.floor(damage + 0.5)),
		cooldown = math.max(0.05, cooldown),
		range = (override and override.range) or WeaponConfig.DefaultRange,
		arcDegrees = (override and override.arcDegrees) or WeaponConfig.DefaultArcDegrees,
		maxTargets = (override and override.maxTargets) or WeaponConfig.DefaultMaxTargets,
	}

	-- The arc test is a dot product against this; acos in the hot path is waste.
	stats.arcCosine = math.cos(math.rad(stats.arcDegrees * 0.5))

	resolved[itemName] = stats
	return stats
end

-- Only useful if something rewrites Overrides or Tiers at runtime; exists so a
-- live-tuning command can.
function WeaponConfig.clearCache()
	table.clear(resolved)
end

-- itemName -> one readable line, for the debug console.
function WeaponConfig.describe()
	local rows = {}

	for itemName, definition in pairs(ItemDefinitions) do
		if definition.classification == "Weapon" then
			local stats = WeaponConfig.get(itemName)
			if stats then
				rows[itemName] = string.format(
					"%d dmg / %.2fs  (%.1f dps)  range %d",
					stats.damage, stats.cooldown, stats.damage / stats.cooldown, stats.range
				)
			end
		end
	end

	return rows
end

return WeaponConfig
