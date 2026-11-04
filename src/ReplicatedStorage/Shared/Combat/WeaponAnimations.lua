-- Published pack owned by group 275555347. Times are authored Swing/Hit/Reset markers.
local WeaponAnimations = {}
local function attack(id, swing, hit, reset, length, finisher)
	local hitEnd = math.min(hit + 0.12, reset - 0.01)
	return {
		animationId = "rbxassetid://" .. id, swingTime = swing,
		hit = hit, hitEnd = hitEnd, recover = reset, length = length,
		trail = { swing, hitEnd },
		damage = if finisher then 1.5 else 1,
		maxTargets = if finisher then 4 else nil,
	}
end
-- Dash clips: `dash` is one clip turned to face the dash; `dashes` is a
-- four-way set played relative to where the character faces.
local function dashes(forward, back, left, right)
	return { Forward = "rbxassetid://" .. forward, Back = "rbxassetid://" .. back,
		Left = "rbxassetid://" .. left, Right = "rbxassetid://" .. right }
end
local RAPIER_DASHES = dashes(91145799880460, 120109952883158, 90097878508361, 90417616630084)
WeaponAnimations.Classes = {
	Axe = {
		pack = "MediumAxe",
		idle = "rbxassetid://106868211337000",
		-- The pack has no axe walk or run: the light axe's carry the same grip.
		walk = "rbxassetid://105304620701106",
		run = "rbxassetid://116843864841470",
		dash = "rbxassetid://114457376577526",
		steps = {
			attack(117740941421559, 14/60, 20/60, 44/60, 0.7333333333333333),
			attack(103484890837751, 15/60, 20/60, 44/60, 0.7333333333333333),
			attack(129073473993964, 13/60, 19/60, 44/60, 0.7333333333333333),
			attack(82861650389987, 17/60, 20/60, 44/60, 0.7333333333333333),
			attack(92860397729107, 13/60, 18/60, 44/60, 0.7333333333333333, true),
		},
	},
	HeavySword = {
		pack = "Blade",
		dash = "rbxassetid://74540258241796",
		idle = "rbxassetid://137403951001319",
		walk = "rbxassetid://83574917210470",
		run = "rbxassetid://124944133880245",
		steps = {
			attack(78879549841119, 27/60, 37/60, 59/60, 0.9833333333333333),
			attack(100727282760937, 29/60, 33/60, 59/60, 0.9833333333333333),
			attack(75577381232417, 34/60, 37/60, 59/60, 0.9833333333333333),
			attack(81483144695303, 31/60, 36/60, 59/60, 0.9833333333333333),
			attack(76878295372126, 26/60, 32/60, 59/60, 0.9833333333333333, true),
		},
	},
	Lance = {
		pack = "Glaive",
		-- No Glaive dash; it already moves with the rapier's thrusting set.
		dashes = RAPIER_DASHES,
		steps = {
			attack(72764549574322, 9.5/60, 16/60, 22/60, 1),
			attack(77147794363277, 7/60, 12/60, 20/60, 1),
			attack(132580298645891, 6/60, 12/60, 20/60, 1),
			attack(83775114520581, 10/60, 12/60, 20/60, 1),
			attack(139395854317712, 10/60, 14/60, 34/60, 1, true),
		},
	},
	Sword = {
		pack = "LightAxe",
		dash = "rbxassetid://83762537828114",
		-- The pack's clip labelled Idle (105304620701106) is a walking cycle.
		idle = "rbxassetid://89807765848542",
		walk = "rbxassetid://105304620701106",
		run = "rbxassetid://116843864841470",
		steps = {
			attack(87389099476775, 11/60, 15/60, 29/60, 0.48333333333333334),
			attack(115024889700075, 13/60, 14/60, 29/60, 0.48333333333333334),
			attack(79690988884206, 10/60, 12/60, 29/60, 0.48333333333333334),
			attack(74058595523695, 9/60, 12/60, 29/60, 0.48333333333333334),
			attack(132902305305947, 16/60, 17/60, 34/60, 0.5666666666666667, true),
		},
	},
}
-- Empty hands and non-weapon tools dash with the rapier's four-way set.
WeaponAnimations.DefaultDashes = RAPIER_DASHES
-- Missing gaits deliberately keep ToolConfig's existing class-specific gait.
function WeaponAnimations.forClass(class)
	return WeaponAnimations.Classes[class] or WeaponAnimations.Classes.Sword
end
function WeaponAnimations.forId(id)
	local key = tostring(id):match("%d+")
	for _, profile in pairs(WeaponAnimations.Classes) do
		for _, step in ipairs(profile.steps) do
			if step.animationId:match("%d+") == key then return step end
		end
	end
	return nil
end
return WeaponAnimations
