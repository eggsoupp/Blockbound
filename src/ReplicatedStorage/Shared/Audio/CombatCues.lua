-- Phase assignments. Player impacts use the server's AbilityImpact packets;
-- boss cues use the same BossEffect packets as their presentation.
local Audio = require(script.Parent.CombatAudio)
local Cues = {}
local references = {
	Fireball = {cast={{"ability_magic_poof",.25,1.2}}, release={{"flame_blast3",.3,1.2}}, hit={{"flame_blast1",.5,1.1}}},
	VioletTempest = {cast={{"ability_magic_cast",.4,.85}}, strike={{"ability_lightning",.5,1},{"boom_deep1",.23,1.2}}},
	CelestialLance = {cast={{"charge_short",.4,1}}, release={{"plasma_cast",.5,1.1}}, hit={{"energy_blast",.6,1.1},{"metal_pound",.22,1}}},
	WraithfireOrb = {cast={{"ability_magic_cast",.4,.7}}, release={{"flame_blast3",.4,.8}}, hit={{"flame_blast2",.65,.85},{"synth_blast",.3,.8}}},
	RiftMaelstrom = {cast={{"air_suction",.4,.8}}, pulse={{"ability_portal",.25,1.1}}, collapse={{"portal_close",.5,.8},{"boom_deep2",.65,.8}}},
}

local bosses = {
	Signus = {
		cast={{"magic_warp",.4,.8}}, beamCharge={{"electric_hum",.4,.75}},
		beamFire={{"blast_short",.6,.8},{"electric_shock",.35,.8}}, beamImpact={{"plasma_cut",.24,.8}},
		referenceImpact={{"synth_blast",.6,.8},{"boom_deep2",.4,.9}},
		crescentBreak={{"glass_break2",.3,1.15}}, lungeImpact={{"explosive_whoosh",.5,.9}},
		shatter={{"glass_break1",.4,.85}}, impact={{"blast_short",.5,.9}}, erupt={{"boom_deep1",.6,.8}},
		blackSun={{"lightning_close",.6,.8},{"bass_drop",.65,.85}},
		totality={{"lightning_close",.65,.7},{"boom_deep2",.65,.7}},
		crown={{"force_hit",.5,.65}}, nova={{"synth_blast",.65,.65}},
		death={{"portal_close",.6,.7},{"boom_deep1",.6,.65}},
		takeoff={{"heavy_whoosh",.3,.85}}, land={{"impact_body",.25,.7}},
	},
	Blightborer = {
		rumble={{"earth_crumble",.35,.6}}, erupt={{"earth_crumble",.55,.85},{"punch_heavy2",.5,.65}},
		dive={{"alien_bug2",.3,.7},{"earth_crumble",.35,.8}},
		furrowline={{"earth_crumble",.3,.65}}, furrow={{"ice_chunk",.3,.7}},
		spit={{"alien_bug1",.45,.8}}, splash={{"water_walk",.5,.7},{"slime_pop",.3,.8}},
		sinkwarn={{"bass_drop",.4,.7}}, collapse={{"earth_crumble",.6,.65},{"boom_deep1",.55,.8}},
		burst={{"alien_bug3",.5,.8},{"slime_pop",.35,.8}}, brood={{"alien_chirp",.5,.65}},
		death={{"monster_roar",.5,.8},{"earth_crumble",.5,.7}},
	},
	SlimeEmperor = {
		pancake={{"air_suction",.35,.8}}, slam={{"water_walk",.6,.7},{"punch_heavy2",.5,.7}},
		claim={{"bubbles",.5,.7}}, absorb={{"air_suction",.5,.65}}, decree={{"magic_lock",.5,.8}},
		coronation={{"power_up",.5,.75}}, coronationImpact={{"force_hit",.65,.7},{"boom_deep1",.5,.85}},
		rain={{"bubbles",.4,1.1}}, rainImpact={{"slime_pop",.4,1.1}}, shift={{"ability_shield_on",.45,.75}},
		land={{"slime_pop",.22,.65}}, death={{"water_walk",.6,.65},{"ability_shield_off",.4,.7}},
	},
	AllSeeingEye = {
		charge={{"heavy_whoosh",.45,.7}}, dash={{"explosive_whoosh",.45,.8}},
		gaze={{"electric_hum",.45,.8}}, beam={{"electric_shock",.5,.8}},
		summon={{"alien_chirp",.5,.7}}, uproot={{"earth_crumble",.5,.7}},
		rockImpact={{"metal_crash",.4,.7}}, tears={{"bubbles",.45,.8}}, tearImpact={{"slime_pop",.4,.7}},
		transform={{"monster_roar",.55,.85},{"force_hit",.45,.65}},
		death={{"monster_roar",.5,.65},{"poof_punch",.6,.6}},
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
	if payload.boss=="Signus" and payload.kind=="crescentBreak" and payload.struck then
		layers={{"glass_break1",.4,.9}}
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
