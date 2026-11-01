-- Published assets only. Empty hands never resolve to a weapon profile.
local Weapons = require(script.Parent.Parent.Combat.WeaponAnimations)
local Profiles = {}
Profiles.Unarmed = {name = "Unarmed", idle = "rbxassetid://507766388",
	walk = "rbxassetid://913402848", run = "rbxassetid://913376220"}
local pickaxe = {name = "Pickaxe", idle = Profiles.Unarmed.idle,
	walk = Profiles.Unarmed.walk, run = Profiles.Unarmed.run,
	rightArm = {Idle = "rbxassetid://117479624548456",
		Walk = "rbxassetid://134569109224529", Run = "rbxassetid://133950607844393"}}
local axe = {name = "Axe", idle = "rbxassetid://89807765848542",
	walk = "rbxassetid://105304620701106", run = "rbxassetid://116843864841470"}
function Profiles.forDefinition(definition)
	if not definition then return Profiles.Unarmed end
	if definition.classification == "Pickaxe" then return pickaxe end
	if definition.classification == "Tool" then return axe end
	local class = definition.weaponClass
	local weapon = class and Weapons.Classes[class]
	if not weapon then return Profiles.Unarmed end
	-- Glaive has no gaits: use the published thrusting-weapon movement set.
	if class == "Lance" then
		return {name = class, idle = "rbxassetid://110058777633931",
			walk = "rbxassetid://91531872067690", run = "rbxassetid://132091308356957"}
	end
	return {name = class, idle = weapon.idle or Profiles.Unarmed.idle,
		walk = weapon.walk or weapon.run or Profiles.Unarmed.walk,
		run = weapon.run or Profiles.Unarmed.run,
		walkReference = if weapon.walk then 16 else 25}
end
return Profiles
