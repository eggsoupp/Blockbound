-- Phase assignments. Player impacts use the server's AbilityImpact packets;
-- boss cues use the same BossEffect packets as their presentation.
local Audio = require(script.Parent.CombatAudio)
local Cues = {}
-- Each entry is a list of { recipe or bank key, volume, pitch }; CombatRecipes
-- builds the layered impacts these name.
local references = {
	Fireball = {cast={{"cast.magic",.4,1.15}}, release={{"cast.launch",.45,1.15}}, hit={{"impact.fire",.65,1.05}}},
	VioletTempest = {cast={{"cast.magic",.45,.85}}, strike={{"impact.lightning",.62,1.05}}},
	CelestialLance = {cast={{"charge.energy",.45,1}}, release={{"cast.launch",.5,1.2},{"laser_shot",.3,1.1}}, hit={{"impact.energy",.65,1.05}}},
	WraithfireOrb = {cast={{"cast.dark",.45,.8}}, release={{"cast.launch",.45,.85}}, hit={{"impact.fire",.6,.8},{"impact.dark",.36,1.15}}},
	RiftMaelstrom = {cast={{"air_suction",.4,.8}}, pulse={{"ability_portal",.25,1.1}}, collapse={{"portal_close",.45,.8},{"impact.dark",.65,.9}}},
}

local bosses = {
	Signus = {
		cast={{"signus.cast",.5,1}}, beamCharge={{"electric_hum",.4,.75},{"charge.energy",.35,.7}},
		beamFire={{"signus.beamFire",.65,1}}, beamImpact={{"signus.beamImpact",.5,1}},
		referenceImpact={{"signus.spellImpact",.65,1}},
		thunderStrike={{"signus.thunder",.62,1}},
		crescentBreak={{"signus.break",.5,1}},
		shatter={{"signus.break",.55,.9}}, impact={{"impact.heavy",.5,.85}}, erupt={{"signus.erupt",.6,1}},
		blackSun={{"signus.blackSun",.7,1}},
		totality={{"signus.totality",.72,1}},
		crown={{"orb_chime",.4,.7}},
		step={{"signus.blink",.45,1}},
		death={{"signus.death",.7,1}},
		takeoff={{"heavy_whoosh",.3,.85}}, land={{"impact_body",.25,.7}},
	},
	Blightborer = {
		rumble={{"earth_crumble",.35,.6}}, erupt={{"boss.groundErupt",.65,1},{"alien_bug3",.3,.7}},
		dive={{"alien_bug2",.3,.7},{"boss.rock",.45,.85}},
		furrowline={{"earth_crumble",.3,.65}}, furrow={{"impact.debris",.4,.8}},
		spit={{"alien_bug1",.45,.8}}, splash={{"boss.splat",.5,.9}},
		sinkwarn={{"bass_drop",.4,.7}}, collapse={{"boss.collapse",.7,1}},
		burst={{"alien_bug3",.45,.8},{"boss.splat",.45,.8}}, brood={{"alien_chirp",.5,.65}},
		death={{"monster_roar",.5,.8},{"boss.death",.6,.9}},
	},
	SlimeEmperor = {
		pancake={{"air_suction",.35,.8}}, slam={{"boss.bodySlam",.7,1}},
		claim={{"bubbles",.5,.7}}, absorb={{"air_suction",.5,.65}}, decree={{"magic_lock",.5,.8}},
		coronation={{"power_up",.5,.75}}, coronationImpact={{"impact.grand",.68,.8}},
		rain={{"bubbles",.4,1.1}}, rainImpact={{"boss.splat",.32,1.1}}, shift={{"ability_shield_on",.45,.75}},
		land={{"boss.splat",.4,.7},{"body_fall1",.35,.6}}, death={{"boss.bodySlam",.6,.8},{"ability_shield_off",.4,.7}},
	},
	AllSeeingEye = {
		charge={{"heavy_whoosh",.45,.7}}, dash={{"boss.dash",.6,1}},
		gaze={{"electric_hum",.45,.8}}, beam={{"electric_shock",.45,.8},{"rail_fire",.45,.85}},
		summon={{"alien_chirp",.5,.7}}, uproot={{"boss.groundErupt",.55,1.05}},
		rockImpact={{"boss.rock",.55,1}}, tears={{"bubbles",.45,.8}}, tearImpact={{"boss.splat",.4,.9}},
		transform={{"boss.transform",.7,1}},
		death={{"monster_roar",.45,.65},{"boss.death",.65,1}},
	},
}
Cues.ReferenceProfiles, Cues.BossProfiles = references, bosses

local function play(layers, position, scope)
	for _, layer in ipairs(layers or {}) do
		local sound = Audio.play(layer[1], position, layer[2], layer[3])
		if scope and sound then scope:add(sound) end
	end
end
function Cues.cast(payload, scope)
	local profile = references[payload.ability]
	if profile and workspace:GetServerTimeNow()-(payload.startedAt or 0)<.65 then
		play(profile.cast, payload.origin.Position, scope)
		if payload.ability == "Fireball" then
			local age = workspace:GetServerTimeNow()-payload.startedAt
			if age < .22 then
				scope:delay(.22-age,function() play(profile.release,payload.origin.Position) end)
			end
		end
	end
end
function Cues.packet(packet)
	local profile = references[packet.ability]
	if not profile or workspace:GetServerTimeNow()-(packet.startedAt or 0)>.65 then return end
	play(profile[packet.event or "hit"], packet.position)
end

local recent = {}
function Cues.boss(payload)
	local profile = bosses[payload.boss]
	local layers = profile and profile[payload.kind]
	if not layers or workspace:GetServerTimeNow()-(payload.startedAt or 0)>.65 then return end
	-- A Mirror Veil decoy broken by a blow shatters; a spell on the ground only cracks.
	if payload.boss=="Signus" and payload.kind=="crescentBreak" and payload.struck then
		layers={{"signus.shatter",.6,1}}
	end
	local p = payload.position
	local bucket = payload.boss..":"..payload.kind..":"..math.floor(p.X/24)..":"..math.floor(p.Z/24)
	local now = os.clock()
	local gap = if payload.kind=="furrow" or payload.kind=="beamImpact" or payload.kind=="rainImpact" then .2 else .08
	if now-(recent[bucket] or -math.huge)<gap then return end
	recent[bucket] = now
	for key, at in pairs(recent) do if now-at>4 then recent[key]=nil end end
	play(layers, p)
end
return Cues
