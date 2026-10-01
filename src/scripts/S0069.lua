--[[
	CombatConfig

	How much a hit actually hurts. Kept separate from whatever swung, so a
	slime, a fall, a trap and a future boss all arrive at the same arithmetic.

	    taken = damage * Scale / (Scale + defense)

	Proportional rather than `damage - defense`, which always has a defense
	number that makes an enemy do literally nothing. This never reaches zero, so
	armour always feels worth wearing and there is no cliff to balance around.

	The server is the only thing allowed to APPLY this (see CombatService); it
	is shared so the UI can EXPLAIN it with the same curve rather than a
	duplicate that drifts.
]]

local CombatConfig = {}

-- Replaces the Roblox default of 100 so the number is ours.
CombatConfig.BaseMaxHealth = 100

CombatConfig.BaseDefense = 0

-- The defense value that halves incoming damage - the single dial deciding how
-- strong armour feels. With armour handing out 5 and 15, 100 means leather
-- shaves ~5% and iron ~13%: noticeable, not decisive.
CombatConfig.DefenseScale = 100

-- Belt and braces on top of the curve: nothing becomes unhittable through
-- arithmetic alone.
CombatConfig.MinimumDamage = 1

-- Grace period after a hit. Zero: both current enemies already rate-limit
-- themselves per player, so this would only hide that.
CombatConfig.InvulnerableSeconds = 0

-- Rounded rather than truncated, or a stack of small hits each lose their
-- fraction and the player quietly takes less than the numbers on screen.
function CombatConfig.mitigate(damage, defense)
	damage = math.max(0, tonumber(damage) or 0)
	if damage <= 0 then
		return 0
	end

	defense = math.max(0, tonumber(defense) or 0)

	local scale = CombatConfig.DefenseScale
	local taken = damage * scale / (scale + defense)

	return math.max(CombatConfig.MinimumDamage, math.floor(taken + 0.5))
end

-- The fraction of damage a defense value removes, 0 to 1, so a readout can say
-- what armour is buying without the player taking a hit to find out.
function CombatConfig.reductionFor(defense)
	defense = math.max(0, tonumber(defense) or 0)
	local scale = CombatConfig.DefenseScale
	return 1 - (scale / (scale + defense))
end

return CombatConfig
