-- Combat sound library: SFX pack asset IDs, each verified to load in a normal
-- client of this experience (a Sound reaching IsLoaded; ContentProvider's
-- "Success" also reports private assets, which then never play). Generated from
-- measurements of the decoded pack files (assets/audio/downloaded):
--   gain      brings each clip's loudest 100 ms to about -17 dB, so layers mix
--             by their recipe volumes rather than by how loudly they were mastered
--   start     seconds of leading silence skipped, so an impact lands on its frame
--   duration  the clip's length; `clip` cuts a long clip short with a fade
-- CombatRecipes layers these into whole impacts.
local Bank = {
	air_suction = {id="rbxassetid://411286671", gain=0.313, duration=1.009, start=0.320},
	energy_blast = {id="rbxassetid://1841310110", gain=0.412, duration=4.415, start=0.025},
	electric_shock = {id="rbxassetid://8060079174", gain=0.631, duration=1.594, start=0.100},
	electric_hum = {id="rbxassetid://6987804397", gain=1.318, duration=1.120},
	energy_sword = {id="rbxassetid://187747824", gain=2.427, duration=1.351},
	magic_warp = {id="rbxassetid://96643104586269", gain=0.269, duration=1.933, start=0.115},
	magic_lock = {id="rbxassetid://7846700665", gain=0.617, duration=2.194},
	plasma_cast = {id="rbxassetid://9558660562", gain=0.513, duration=1.312},
	plasma_cut = {id="rbxassetid://4882986173", gain=1.622, duration=0.700},
	plasma_trail = {id="rbxassetid://9125742262", gain=0.955, duration=33.163},
	portal_close = {id="rbxassetid://89974036761299", gain=0.398, duration=0.683, start=0.040},
	power_up = {id="rbxassetid://9065783664", gain=0.631, duration=2.769},
	charge_short = {id="rbxassetid://9125980459", gain=1.778, duration=1.771, start=0.080},
	alien_chirp = {id="rbxassetid://9114279576", gain=3.000, duration=1.134},
	alien_bug1 = {id="rbxassetid://136128007074351", gain=0.776, duration=1.215},
	alien_bug2 = {id="rbxassetid://137326052365300", gain=0.881, duration=1.231},
	alien_bug3 = {id="rbxassetid://96071203271536", gain=0.804, duration=1.569},
	lightning_close = {id="rbxassetid://18650085033", gain=0.398, duration=5.520, start=0.040},
	boom_deep1 = {id="rbxassetid://9125401975", gain=0.668, duration=2.922},
	boom_deep2 = {id="rbxassetid://9125402735", gain=0.668, duration=2.882},
	ice_chunk = {id="rbxassetid://9114857307", gain=1.905, duration=2.115, start=0.205},
	poof_punch = {id="rbxassetid://9116406151", gain=1.259, duration=1.489},
	poof_air = {id="rbxassetid://9125639499", gain=1.698, duration=0.969},
	metal_pound = {id="rbxassetid://9116908179", gain=0.380, duration=0.906},
	punch_heavy1 = {id="rbxassetid://9117969687", gain=0.327, duration=0.618},
	punch_heavy2 = {id="rbxassetid://9117969717", gain=0.279, duration=0.905},
	metal_crash = {id="rbxassetid://9125819216", gain=0.355, duration=1.126, start=0.020},
	bass_drop = {id="rbxassetid://9045206449", gain=0.501, duration=3.918, start=0.250},
	sword_hit = {id="rbxassetid://86812684303392", gain=1.084, duration=0.877},
	sword_swing = {id="rbxassetid://7171591581", gain=0.610, duration=1.346, start=0.040},
	synth_blast = {id="rbxassetid://9119783432", gain=1.012, duration=2.933, start=0.190},
	sparkle = {id="rbxassetid://9119834423", gain=2.089, duration=0.590},
	flame_blast1 = {id="rbxassetid://9120009740", gain=0.861, duration=2.368, start=0.170},
	flame_blast2 = {id="rbxassetid://9120010041", gain=0.955, duration=2.347, start=0.170},
	flame_blast3 = {id="rbxassetid://9120010568", gain=0.861, duration=1.619},
	flame_blast4 = {id="rbxassetid://9120009225", gain=0.708, duration=2.635, start=0.155},
	flame_blast5 = {id="rbxassetid://9120009533", gain=0.733, duration=2.112, start=0.175},
	explosive_whoosh = {id="rbxassetid://9120705982", gain=0.403, duration=1.754},
	heavy_whoosh = {id="rbxassetid://9120728815", gain=0.676, duration=0.666, start=0.035},
	swing_air = {id="rbxassetid://9113305311", gain=1.365, duration=0.467},
	impact_body = {id="rbxassetid://9113312550", gain=0.531, duration=1.009},
	slime_pop = {id="rbxassetid://9119668788", gain=0.716, duration=0.612},
	bubbles = {id="rbxassetid://9112752575", gain=1.084, duration=13.885, start=0.245},
	earth_crumble = {id="rbxassetid://8044058354", gain=1.567, duration=1.660},
	monster_roar = {id="rbxassetid://18929141493", gain=1.259, duration=7.846, start=0.030},
	glass_break1 = {id="rbxassetid://6737582037", gain=0.422, duration=1.919},
	glass_break2 = {id="rbxassetid://6737582452", gain=0.372, duration=1.839},
	blast_short = {id="rbxassetid://104406219115733", gain=0.211, duration=1.471},
	force_hit = {id="rbxassetid://8844155653", gain=0.610, duration=1.591},
	water_walk = {id="rbxassetid://122684680935247", gain=3.000, duration=1.667},
	crack_punch = {id="rbxassetid://8595980577", gain=0.631, duration=0.397},
	punch_tail = {id="rbxassetid://8595984380", gain=0.380, duration=2.551},
	punch_a = {id="rbxassetid://8646342913", gain=0.232, duration=0.584},
	punch_b = {id="rbxassetid://8278630896", gain=0.232, duration=0.584},
	thump_tight = {id="rbxassetid://9113565281", gain=0.933, duration=0.666},
	hit_wild = {id="rbxassetid://87950231155857", gain=0.299, duration=0.713},
	hit_grenade = {id="rbxassetid://70698610794457", gain=0.531, duration=0.384},
	metal_crack = {id="rbxassetid://626985498", gain=0.309, duration=1.149, start=0.030},
	knife_hit = {id="rbxassetid://4678745096", gain=0.263, duration=0.575, start=0.020},
	axe_hit = {id="rbxassetid://6999081790", gain=0.432, duration=0.894},
	glitch_blast = {id="rbxassetid://8880764455", gain=0.359, duration=1.349},
	pop_blast = {id="rbxassetid://269146157", gain=0.684, duration=1.821},
	explosion = {id="rbxassetid://3802269741", gain=0.211, duration=1.802, start=0.025},
	explosion_round = {id="rbxassetid://4334729976", gain=0.442, duration=4.585},
	cine_hit = {id="rbxassetid://9046295513", gain=0.380, duration=3.851},
	string_hit1 = {id="rbxassetid://18601481435", gain=0.473, duration=1.971},
	string_hit2 = {id="rbxassetid://18601481435", gain=0.473, duration=1.971},
	ring_hit = {id="rbxassetid://1837829449", gain=0.351, duration=6.583},
	orchestra_hit = {id="rbxassetid://18601481435", gain=0.473, duration=1.971},
	bolt_impact = {id="rbxassetid://168586621", gain=0.204, duration=2.483},
	star_impact = {id="rbxassetid://4612384643", gain=0.266, duration=1.174},
	starbar_impact = {id="rbxassetid://4612386227", gain=0.363, duration=2.158},
	launch_blast = {id="rbxassetid://8593251455", gain=0.295, duration=1.981},
	ground_slam = {id="rbxassetid://74149238738530", gain=0.569, duration=2.194, start=0.020},
	distant_boom = {id="rbxassetid://7423520828", gain=0.724, duration=6.758, start=0.035},
	glass_crisp = {id="rbxassetid://2596202821", gain=0.367, duration=2.000},
	grit_concrete1 = {id="rbxassetid://1476374050", gain=0.550, duration=1.788, start=0.060},
	grit_concrete2 = {id="rbxassetid://2640195159", gain=0.331, duration=0.421},
	grit_sand1 = {id="rbxassetid://2640194863", gain=0.343, duration=0.322},
	grit_sand2 = {id="rbxassetid://2640195272", gain=0.367, duration=0.426},
	grit_metal = {id="rbxassetid://7842407284", gain=0.617, duration=0.475},
	grit_glass = {id="rbxassetid://142082167", gain=0.316, duration=1.094},
	grit_concrete3 = {id="rbxassetid://142082166", gain=0.452, duration=0.770},
	kill_pop = {id="rbxassetid://8555780469", gain=1.175, duration=0.366, start=0.035},
	hurt_hit = {id="rbxassetid://127155960884656", gain=0.376, duration=0.415},
	body_fall1 = {id="rbxassetid://7446607140", gain=0.260, duration=0.731, start=0.080},
	body_fall3 = {id="rbxassetid://9113312550", gain=0.531, duration=1.009},
	zap_quick = {id="rbxassetid://9116278972", gain=0.933, duration=0.632},
	laser_shot = {id="rbxassetid://1898322396", gain=0.299, duration=1.371},
	rail_fire = {id="rbxassetid://6792814749", gain=0.473, duration=2.586},
	whoosh_thick = {id="rbxassetid://9120742716", gain=0.479, duration=0.538},
	punch_swing = {id="rbxassetid://5835032207", gain=0.269, duration=0.313, start=0.020},
	swish_rise = {id="rbxassetid://9114890978", gain=0.759, duration=0.907},
	recharge = {id="rbxassetid://217733697", gain=0.385, duration=2.024},
	orb_chime = {id="rbxassetid://6494675393", gain=0.750, duration=1.305},
	teleport_whomp = {id="rbxassetid://119600335076441", gain=0.380, duration=1.531},
	power_on = {id="rbxassetid://7066931333", gain=0.684, duration=3.146},
	plasma_charged = {id="rbxassetid://9065783664", gain=0.631, duration=2.769},
	plasma_rifle = {id="rbxassetid://6150724423", gain=0.200, duration=6.457},
	magic_cast = {id="rbxassetid://182765513", gain=0.631, duration=1.229, start=0.025},
}
-- Long or slow clips that only their opening is wanted from.
Bank.plasma_trail.clip = 1.65
Bank.bubbles.clip = 0.85
Bank.monster_roar.clip = 2.6
Bank.axe_hit.clip = 0.9
Bank.ring_hit.clip = 2.4
Bank.orb_chime.clip = 1.6
Bank.distant_boom.clip = 3
Bank.string_hit2.clip = 2.2
local Imported = require(script.Parent.DownloadedSounds)
for key, id in pairs(Imported) do
	if string.sub(key, 1, 8) == "ability_" then
		Bank[key] = {id=id, gain=1, duration=if key=="ability_charge" then 10 else 7}
	end
end
return Bank
