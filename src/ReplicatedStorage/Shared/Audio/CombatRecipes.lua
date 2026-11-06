--[[
	CombatRecipes

	Whole impacts built from CombatSoundBank clips. One clip rarely sells a hit:
	a hit has a transient (the crack or snap that says WHEN), a body (the punch
	that says HOW HARD), low end (the weight) and often debris or a tail (what
	it did to the world). A recipe stacks those, offset by a few milliseconds
	and pitched a little differently every time, so the same blow repeated never
	sounds like a sample on a loop.

	Each layer is { bank key, volume, pitch, delay seconds, pitch variance }.
	Volumes mix against each other: the bank has already brought every clip to
	the same loudness. `duck` (0..1) dips the music under the heaviest hits for
	a moment; `range` is how far away the recipe is still heard.

	CombatAudio.play takes a recipe name anywhere it takes a bank key; the
	caller's volume scales the whole recipe (0.6 is as written) and its pitch
	multiplies every layer's.

	Outcomes are kept apart by spectrum, as well as by loudness: a weapon hit
	is a dry mid crack, a kill adds a bright sparkle and a body falling, being
	hurt is a dull low thump. Spell impacts are bigger and wetter, and the boss
	cues bigger again, so you can tell your hits from its spells without looking.
]]

local R = {}

local function recipe(layers, options)
	options = options or {}
	return { layers = layers, duck = options.duck, range = options.range, near = options.near }
end

-- ---------------------------------------------------------------------------
-- Melee: what your weapon sounds like connecting, by weapon class
-- ---------------------------------------------------------------------------

R["melee.Sword"] = recipe({
	{ "knife_hit", 0.55, 1.0, 0, 0.06 },
	{ "sword_hit", 0.42, 1.05, 0, 0.05 },
	{ "crack_punch", 0.32, 1.15, 0.005, 0.06 },
}, { range = 120 })
R["melee.HeavySword"] = recipe({
	{ "punch_a", 0.6, 0.85, 0, 0.05 },
	{ "metal_crack", 0.36, 0.9, 0, 0.05 },
	{ "sword_hit", 0.34, 0.85, 0.01, 0.05 },
	{ "thump_tight", 0.3, 0.8, 0.01, 0.04 },
}, { range = 130 })
R["melee.Axe"] = recipe({
	{ "axe_hit", 0.5, 1.0, 0, 0.06 },
	{ "punch_b", 0.5, 0.95, 0, 0.05 },
	{ "grit_concrete3", 0.22, 1.2, 0.01, 0.08 },
}, { range = 120 })
R["melee.Lance"] = recipe({
	{ "knife_hit", 0.5, 1.15, 0, 0.06 },
	{ "hit_grenade", 0.36, 1.1, 0, 0.06 },
	{ "crack_punch", 0.3, 1.0, 0.008, 0.05 },
}, { range = 120 })
-- Anything else swung at an enemy: a tool, a fist.
R["melee.Blunt"] = recipe({
	{ "punch_a", 0.5, 1.0, 0, 0.06 },
	{ "thump_tight", 0.38, 1.0, 0, 0.05 },
}, { range = 110 })
-- The killing blow, on top of the hit: a pop, a bright confirm, the body down.
R["melee.kill"] = recipe({
	{ "pop_blast", 0.45, 0.9, 0, 0.05 },
	{ "star_impact", 0.3, 1.45, 0.02, 0.05 },
	{ "kill_pop", 0.32, 1.0, 0.02, 0.04 },
	{ "body_fall1", 0.34, 0.9, 0.09, 0.06 },
}, { range = 140 })
-- You were hit: dull and low, nothing like your own weapon.
R["player.hurt"] = recipe({
	{ "hurt_hit", 0.42, 0.95, 0, 0.06 },
	{ "thump_tight", 0.32, 0.75, 0, 0.05 },
}, { range = 60 })
R["player.hurtHeavy"] = recipe({
	{ "hurt_hit", 0.5, 0.85, 0, 0.05 },
	{ "punch_b", 0.4, 0.7, 0, 0.04 },
	{ "boom_deep1", 0.25, 1.2, 0.01, 0.04 },
}, { range = 60 })

-- ---------------------------------------------------------------------------
-- Ability impacts, by material
-- ---------------------------------------------------------------------------

R["impact.light"] = recipe({
	{ "crack_punch", 0.5, 1.0, 0, 0.07 },
	{ "star_impact", 0.34, 1.15, 0, 0.06 },
	{ "grit_sand1", 0.22, 1.1, 0.01, 0.08 },
})
R["impact.heavy"] = recipe({
	{ "cine_hit", 0.55, 1.0, 0, 0.05 },
	{ "punch_a", 0.45, 0.8, 0, 0.05 },
	{ "boom_deep1", 0.36, 1.0, 0.015, 0.04 },
	{ "grit_concrete1", 0.3, 1.0, 0.02, 0.08 },
}, { duck = 0.35, range = 260 })
R["impact.explosion"] = recipe({
	{ "explosion", 0.58, 1.0, 0, 0.05 },
	{ "glitch_blast", 0.4, 0.9, 0, 0.05 },
	{ "boom_deep1", 0.45, 0.8, 0.02, 0.04 },
	{ "grit_concrete2", 0.28, 1.0, 0.05, 0.08 },
}, { duck = 0.5, range = 320, near = 20 })
R["impact.fire"] = recipe({
	{ "flame_blast3", 0.5, 1.05, 0, 0.06 },
	{ "explosion_round", 0.42, 1.1, 0, 0.05 },
	{ "pop_blast", 0.36, 0.95, 0, 0.05 },
	{ "boom_deep1", 0.25, 1.1, 0.02, 0.04 },
}, { duck = 0.25, range = 260 })
R["impact.lightning"] = recipe({
	{ "bolt_impact", 0.58, 1.0, 0, 0.05 },
	{ "zap_quick", 0.38, 1.0, 0, 0.08 },
	{ "crack_punch", 0.3, 0.8, 0, 0.05 },
	{ "boom_deep1", 0.32, 0.9, 0.03, 0.04 },
}, { duck = 0.35, range = 300 })
R["impact.water"] = recipe({
	{ "explosive_whoosh", 0.45, 1.25, 0, 0.06 },
	{ "poof_air", 0.38, 0.85, 0, 0.06 },
	{ "slime_pop", 0.34, 0.8, 0.01, 0.08 },
	{ "bubbles", 0.22, 1.1, 0.06, 0.08 },
}, { range = 240 })
R["impact.ice"] = recipe({
	{ "glass_crisp", 0.42, 1.1, 0, 0.06 },
	{ "grit_glass", 0.36, 1.0, 0, 0.06 },
	{ "ice_chunk", 0.4, 1.0, 0.02, 0.06 },
	{ "thump_tight", 0.3, 0.85, 0, 0.05 },
}, { range = 240 })
R["impact.blade"] = recipe({
	{ "knife_hit", 0.5, 1.05, 0, 0.06 },
	{ "plasma_cut", 0.42, 1.2, 0, 0.06 },
	{ "axe_hit", 0.25, 1.15, 0.01, 0.06 },
}, { range = 220 })
R["impact.energy"] = recipe({
	{ "energy_blast", 0.48, 1.0, 0, 0.05 },
	{ "star_impact", 0.4, 1.0, 0, 0.05 },
	{ "punch_a", 0.36, 0.85, 0, 0.05 },
}, { duck = 0.25, range = 260 })
-- Celestial and grand finishers: a ringing strike over a cinematic hit.
R["impact.grand"] = recipe({
	{ "ring_hit", 0.45, 1.0, 0, 0.04 },
	{ "cine_hit", 0.5, 0.95, 0, 0.04 },
	{ "string_hit2", 0.36, 1.0, 0.01, 0.04 },
	{ "boom_deep1", 0.4, 0.85, 0.02, 0.03 },
}, { duck = 0.6, range = 340, near = 24 })
R["impact.slam"] = recipe({
	{ "ground_slam", 0.6, 1.0, 0, 0.05 },
	{ "punch_b", 0.45, 0.8, 0, 0.05 },
	{ "grit_concrete1", 0.34, 0.95, 0.01, 0.08 },
	{ "earth_crumble", 0.3, 1.0, 0.1, 0.08 },
}, { duck = 0.4, range = 280 })
R["impact.debris"] = recipe({
	{ "grit_concrete3", 0.4, 1.0, 0, 0.1 },
	{ "grit_sand2", 0.3, 1.0, 0.02, 0.1 },
}, { range = 120 })
R["impact.dark"] = recipe({
	{ "cine_hit", 0.5, 0.8, 0, 0.04 },
	{ "explosion", 0.36, 0.75, 0, 0.04 },
	{ "boom_deep1", 0.42, 0.7, 0.02, 0.03 },
	{ "teleport_whomp", 0.3, 0.8, 0.03, 0.05 },
}, { duck = 0.45, range = 300 })

-- ---------------------------------------------------------------------------
-- Movement, casting and charging
-- ---------------------------------------------------------------------------

R["whoosh.light"] = recipe({
	{ "whoosh_thick", 0.42, 1.15, 0, 0.08 },
}, { range = 120 })
R["whoosh.heavy"] = recipe({
	{ "heavy_whoosh", 0.5, 0.95, 0, 0.06 },
	{ "whoosh_thick", 0.34, 0.8, 0, 0.06 },
}, { range = 160 })
R["whoosh.blade"] = recipe({
	{ "sword_swing", 0.45, 1.1, 0, 0.06 },
	{ "whoosh_thick", 0.3, 1.3, 0, 0.06 },
}, { range = 140 })
R["cast.magic"] = recipe({
	{ "magic_cast", 0.45, 1.0, 0, 0.05 },
	{ "poof_punch", 0.34, 1.0, 0, 0.06 },
}, { range = 160 })
R["cast.dark"] = recipe({
	{ "magic_cast", 0.42, 0.8, 0, 0.04 },
	{ "teleport_whomp", 0.36, 0.9, 0, 0.05 },
}, { range = 180 })
R["cast.blink"] = recipe({
	{ "teleport_whomp", 0.45, 1.05, 0, 0.06 },
	{ "poof_air", 0.32, 1.1, 0, 0.06 },
}, { range = 160 })
R["cast.launch"] = recipe({
	{ "launch_blast", 0.5, 1.0, 0, 0.05 },
	{ "whoosh_thick", 0.32, 0.9, 0, 0.06 },
}, { range = 200 })
R["charge.energy"] = recipe({
	{ "plasma_charged", 0.4, 1.0, 0, 0.04 },
	{ "recharge", 0.28, 1.0, 0, 0.04 },
}, { range = 180 })

-- ---------------------------------------------------------------------------
-- Signus
-- ---------------------------------------------------------------------------

R["signus.cast"] = recipe({
	{ "magic_cast", 0.42, 0.85, 0, 0.04 },
	{ "whoosh_thick", 0.28, 0.85, 0, 0.05 },
}, { range = 220 })
R["signus.spellImpact"] = recipe({
	{ "cine_hit", 0.56, 0.85, 0, 0.04 },
	{ "explosion", 0.4, 0.8, 0, 0.04 },
	{ "boom_deep1", 0.46, 0.75, 0.02, 0.03 },
	{ "grit_concrete1", 0.34, 0.95, 0.03, 0.08 },
	{ "earth_crumble", 0.26, 0.9, 0.14, 0.08 },
}, { duck = 0.55, range = 340, near = 24 })
R["signus.thunder"] = recipe({
	{ "bolt_impact", 0.6, 0.9, 0, 0.05 },
	{ "zap_quick", 0.4, 0.85, 0, 0.08 },
	{ "crack_punch", 0.32, 0.75, 0, 0.05 },
	{ "boom_deep1", 0.38, 0.8, 0.03, 0.04 },
	{ "grit_sand1", 0.24, 1.0, 0.04, 0.1 },
}, { duck = 0.35, range = 320 })
R["signus.blackSun"] = recipe({
	{ "explosion", 0.6, 0.7, 0, 0.03 },
	{ "ring_hit", 0.5, 0.7, 0, 0.03 },
	{ "bolt_impact", 0.44, 0.75, 0, 0.04 },
	{ "boom_deep1", 0.6, 0.6, 0.02, 0.03 },
	{ "distant_boom", 0.42, 0.9, 0.15, 0.04 },
	{ "earth_crumble", 0.32, 0.8, 0.2, 0.06 },
}, { duck = 0.85, range = 420, near = 32 })
R["signus.totality"] = recipe({
	{ "ring_hit", 0.56, 0.6, 0, 0.02 },
	{ "cine_hit", 0.56, 0.7, 0, 0.03 },
	{ "bolt_impact", 0.46, 0.7, 0, 0.03 },
	{ "boom_deep1", 0.62, 0.6, 0.02, 0.02 },
	{ "string_hit2", 0.42, 0.7, 0.04, 0.03 },
	{ "distant_boom", 0.4, 0.8, 0.3, 0.04 },
}, { duck = 1, range = 460, near = 36 })
R["signus.beamFire"] = recipe({
	{ "rail_fire", 0.55, 0.7, 0, 0.04 },
	{ "plasma_rifle", 0.34, 0.6, 0, 0.04 },
	{ "boom_deep1", 0.34, 0.9, 0.01, 0.03 },
}, { duck = 0.3, range = 320 })
R["signus.beamImpact"] = recipe({
	{ "grit_concrete2", 0.3, 0.9, 0, 0.12 },
	{ "plasma_cut", 0.24, 0.85, 0, 0.08 },
}, { range = 200 })
-- A decoy broken by a blow, and a spell breaking on the ground.
R["signus.shatter"] = recipe({
	{ "glass_crisp", 0.5, 0.95, 0, 0.05 },
	{ "grit_glass", 0.38, 0.9, 0, 0.06 },
	{ "teleport_whomp", 0.34, 1.0, 0.02, 0.05 },
}, { range = 220 })
R["signus.break"] = recipe({
	{ "glass_break2", 0.34, 1.1, 0, 0.06 },
	{ "grit_sand2", 0.26, 1.0, 0, 0.08 },
}, { range = 180 })
R["signus.blink"] = recipe({
	{ "teleport_whomp", 0.45, 0.85, 0, 0.05 },
	{ "poof_air", 0.3, 0.8, 0, 0.06 },
}, { range = 220 })
R["signus.erupt"] = recipe({
	{ "ground_slam", 0.52, 0.85, 0, 0.05 },
	{ "boom_deep1", 0.4, 0.8, 0.02, 0.04 },
	{ "earth_crumble", 0.32, 0.9, 0.08, 0.08 },
}, { duck = 0.3, range = 300 })
R["signus.death"] = recipe({
	{ "string_hit2", 0.5, 0.7, 0, 0.03 },
	{ "explosion", 0.42, 0.65, 0.02, 0.03 },
	{ "ring_hit", 0.42, 0.55, 0.05, 0.03 },
	{ "portal_close", 0.4, 0.7, 0.3, 0.04 },
}, { duck = 0.8, range = 420, near = 32 })

-- ---------------------------------------------------------------------------
-- The other bosses
-- ---------------------------------------------------------------------------

R["boss.groundErupt"] = recipe({
	{ "ground_slam", 0.55, 0.85, 0, 0.05 },
	{ "punch_b", 0.4, 0.65, 0, 0.05 },
	{ "earth_crumble", 0.4, 0.85, 0.06, 0.08 },
	{ "grit_concrete1", 0.3, 0.9, 0.02, 0.1 },
}, { duck = 0.35, range = 300 })
R["boss.collapse"] = recipe({
	{ "explosion_round", 0.45, 0.7, 0, 0.04 },
	{ "boom_deep1", 0.55, 0.7, 0.02, 0.03 },
	{ "earth_crumble", 0.5, 0.8, 0.05, 0.06 },
	{ "distant_boom", 0.3, 1.0, 0.2, 0.05 },
}, { duck = 0.6, range = 340, near = 28 })
R["boss.bodySlam"] = recipe({
	{ "punch_a", 0.55, 0.6, 0, 0.04 },
	{ "body_fall1", 0.5, 0.65, 0, 0.05 },
	{ "slime_pop", 0.4, 0.6, 0.01, 0.06 },
	{ "boom_deep1", 0.45, 0.8, 0.02, 0.03 },
}, { duck = 0.45, range = 300 })
R["boss.splat"] = recipe({
	{ "slime_pop", 0.45, 0.85, 0, 0.1 },
	{ "poof_air", 0.3, 0.8, 0, 0.08 },
}, { range = 200 })
R["boss.rock"] = recipe({
	{ "punch_b", 0.45, 0.8, 0, 0.06 },
	{ "grit_concrete1", 0.4, 0.9, 0, 0.1 },
	{ "earth_crumble", 0.3, 1.0, 0.04, 0.08 },
}, { range = 240 })
R["boss.dash"] = recipe({
	{ "heavy_whoosh", 0.55, 0.8, 0, 0.05 },
	{ "explosive_whoosh", 0.4, 0.9, 0, 0.05 },
}, { range = 240 })
R["boss.transform"] = recipe({
	{ "monster_roar", 0.5, 0.85, 0, 0.03 },
	{ "cine_hit", 0.5, 0.75, 0, 0.03 },
	{ "boom_deep1", 0.5, 0.7, 0.02, 0.03 },
}, { duck = 0.8, range = 420 })
R["boss.death"] = recipe({
	{ "string_hit1", 0.5, 0.8, 0, 0.03 },
	{ "explosion_round", 0.4, 0.7, 0.02, 0.03 },
	{ "boom_deep1", 0.5, 0.65, 0.03, 0.03 },
}, { duck = 0.7, range = 400 })

-- ---------------------------------------------------------------------------
-- Creatures (CreatureFX): their attacks landing
-- ---------------------------------------------------------------------------

R["creature.hit"] = recipe({
	{ "punch_b", 0.45, 1.0, 0, 0.08 },
	{ "crack_punch", 0.3, 1.0, 0, 0.08 },
}, { range = 140 })
R["creature.boom"] = recipe({
	{ "explosion_round", 0.45, 1.0, 0, 0.06 },
	{ "pop_blast", 0.38, 1.0, 0, 0.06 },
	{ "boom_deep1", 0.3, 1.0, 0.02, 0.05 },
}, { duck = 0.2, range = 220 })

return R
