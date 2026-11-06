--[[
	WeaponShots

	Legendary weapons throw a shot of their own element with every swing, at
	the swing's hit moment, so they reach past the blade. A shot is a weapon
	attack, not an ability: it costs no mana and has no ability cooldown, only
	a short refire gap of its own so a fast combo cannot carpet the screen, and
	it hits for a share of the swing that threw it. The combo's last step
	throws an empowered one.

	WeaponShotService (server) owns the aim, the flight and the damage; every
	client draws the same straight flight from the launch packet
	(Shared.Abilities.VFX.WeaponShotVFX).

	Profile fields:
	  look          which WeaponShotVFX look draws it
	  speed, range  studs a second, studs
	  radius        how wide it hits
	  damage        share of the swing's damage
	  pierce        enemies it passes through before the next one stops it
	  splash        radius of a burst where it stops, hitting for splashDamage
	                of the shot's damage (enemies it already hit are spared)
	  gap           least seconds between two of its shots
]]

local WeaponShots = {}

WeaponShots.Profiles = {
	-- A javelin of light: fast, long, and it goes through the first enemies.
	LightLance = { look = "Light", speed = 115, range = 72, radius = 1.8, damage = 0.5, pierce = 2, gap = 0.45 },
	-- A lightning bolt off the edge: the fastest, cracking open where it lands.
	Thunderveil = { look = "Thunder", speed = 150, range = 60, radius = 2, damage = 0.5, pierce = 0, splash = 6, splashDamage = 0.4, gap = 0.6 },
	-- A burning fang: slower, bursting into flame where it hits.
	DragonSword = { look = "Dragon", speed = 85, range = 60, radius = 2, damage = 0.45, pierce = 0, splash = 7, splashDamage = 0.45, gap = 0.55 },
	-- A spinning spirit axe: heavy and short-ranged, through one enemy.
	ValhallaAxe = { look = "Valhalla", speed = 70, range = 48, radius = 2.6, damage = 0.55, pierce = 1, gap = 0.7 },
	-- A wide crescent of blood: slow, short, cutting through a crowd.
	BloodmoonGiantSword = { look = "Blood", speed = 72, range = 46, radius = 4, damage = 0.5, pierce = 4, gap = 0.8 },
	-- A void orb.
	VoidReaver = { look = "Void", speed = 95, range = 60, radius = 2.2, damage = 0.4, pierce = 1, gap = 0.5 },
}

-- The combo's last step: a bigger shot, a little harder on top of that
-- step's own heavier swing (WeaponAnimations' finisher damage).
WeaponShots.Finisher = { damage = 1.2, scale = 1.35 }

-- No shot hits for less than this.
WeaponShots.MinDamage = 4

-- How wide a shot is against blocks. Much thinner than against enemies: at a
-- profile's full radius, a shot aimed down at something small clips the
-- ground in front of it and stops short.
WeaponShots.WorldRadius = 0.5

-- Soft aim: an enemy this many degrees off the swing's facing, inside the
-- shot's range, is aimed at; otherwise it flies straight ahead.
WeaponShots.AimCone = 25

-- Where shots leave from, relative to the thrower's root: a little up and in front.
WeaponShots.LaunchHeight = 1.2
WeaponShots.LaunchForward = 2.5

-- Clients further than this from a shot are not told about it.
WeaponShots.BroadcastRadius = 300

function WeaponShots.profileFor(itemName: string?)
	return if type(itemName) == "string" then WeaponShots.Profiles[itemName] else nil
end

-- Where a shot is `t` seconds after it was thrown. Shots fly straight.
function WeaponShots.position(origin: Vector3, direction: Vector3, speed: number, t: number): Vector3
	return origin + direction * speed * math.max(t, 0)
end

return WeaponShots
