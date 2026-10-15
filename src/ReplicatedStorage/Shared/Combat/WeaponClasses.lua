--[[
	WeaponClasses

	What kind of weapon something is: a main class and a subclass, set per item
	in ItemDefinitions as `weaponClass` and `weaponSubclass`.

		Sword       -> Longsword (the tier swords, VoidReaver), Katana (Bloodfang)
		HeavySword  -> Broadsword (Thunderveil)
		Lance       -> Spear (LightLance)

	The class decides how a weapon is carried - its walk, in ToolConfig.
	WalkAnimations - and both are shown at the head of its description:

		WeaponClasses.label(definition)        -> "Sword -> Katana"
		WeaponClasses.description(definition)  -> "Sword -> Katana\nA sword that bleeds. ..."

	Presentation only. Damage, range and cooldown are WeaponConfig's and do
	not read the class.
]]

local WeaponClasses = {}

-- Class key -> how it is written on screen.
WeaponClasses.Classes = {
	Sword = "Sword",
	HeavySword = "Heavy Sword",
	Lance = "Lance",
}

-- The class key of an item definition, or nil for anything that is not a
-- classed weapon. A misspelt class reads as no class: normal walk, no label.
function WeaponClasses.classOf(definition)
	local key = definition and definition.weaponClass
	if type(key) == "string" and WeaponClasses.Classes[key] then
		return key
	end
	return nil
end

-- "Sword -> Katana", "Lance" with no subclass, or nil for an unclassed item.
function WeaponClasses.label(definition)
	local key = WeaponClasses.classOf(definition)
	if not key then
		return nil
	end

	local name = WeaponClasses.Classes[key]
	local subclass = definition.weaponSubclass
	if type(subclass) == "string" and subclass ~= "" then
		return string.format("%s -> %s", name, subclass)
	end
	return name
end

--[[
	The text to show as an item's description: its class line first for a
	weapon, then the description it was written with. Every place that shows a
	description asks this, so the class can never be shown in one and missing
	from another.
]]
function WeaponClasses.description(definition)
	local text = definition and definition.description
	if type(text) ~= "string" then
		text = ""
	end

	local label = WeaponClasses.label(definition)
	if not label then
		return text
	end

	return if text ~= "" then label .. "\n" .. text else label
end

return WeaponClasses
