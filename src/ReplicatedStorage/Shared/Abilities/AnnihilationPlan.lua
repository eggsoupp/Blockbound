-- Shared timeline: original circle timing, followed by a sustained energy column.
local Plan = {}

Plan.Tuning = {
	Step = 0.28,
	Reveal = 0.32,
	Hold = 2.4,
	Fade = 0.7,
	BeamHeight = 280,
	SummoningRadius = 65,
	SummoningReveal = 0.55,
	BeamRadius = 9.5,
	ExcavationRadius = 20,
	CageRadius = 17.2,
	PressureInterval = 0.14,
	ParticleTail = 3,
	DamageRadius = 22,
	ImpactDamage = 240,
	TickDamage = 60,
	TickCount = 6,
	TickInterval = 0.35,
	-- Heights relative to the cursor target, radii in studs.
	Circles = {
		{ height = 0.18, radius = 10, speed = 0.24 },
		{ height = 14, radius = 15, speed = -0.32 },
		{ height = 30, radius = 21, speed = 0.27 },
		{ height = 48, radius = 26, speed = -0.2 },
		{ height = 68, radius = 9, speed = 0.65 },
		{ height = 88, radius = 15, speed = -0.38 },
		{ height = 110, radius = 24, speed = 0.22 },
		{ height = 132, radius = 12, speed = -0.28 },
		{ height = 154, radius = 18, speed = 0.31 },
		{ height = 176, radius = 27, speed = -0.22 },
		{ height = 198, radius = 16, speed = 0.3 },
		{ height = 220, radius = 30, speed = -0.18 },
	},
}

function Plan.revealAt(index: number): number
	return (index - 1) * Plan.Tuning.Step
end

function Plan.fadeAt(): number
	return Plan.revealAt(#Plan.Tuning.Circles) + Plan.Tuning.Reveal + Plan.Tuning.Hold
end

function Plan.circlesEnd(): number
	return Plan.fadeAt() + Plan.Tuning.Fade
end

function Plan.duration(): number
	return Plan.circlesEnd() + Plan.Tuning.ParticleTail
end

function Plan.fireAt(): number
	return Plan.revealAt(#Plan.Tuning.Circles) + Plan.Tuning.Reveal
end

function Plan.hitAt(): number
	return Plan.fireAt() + 0.12
end

-- Integrate angular speed so ignition accelerates without snapping orientation.
function Plan.rotation(age: number, firingAge: number): number
	local active = math.max(0, firingAge)
	local ramp = math.min(active, 0.4)
	return math.max(0, age) * 5 + 5 * (ramp * ramp / 0.8 + math.max(0, active - 0.4))
end

function Plan.summoningSample(elapsed: number): (number, number)
	local age = elapsed - (Plan.fireAt() - Plan.Tuning.SummoningReveal)
	if age < 0 or elapsed >= Plan.circlesEnd() then return 0, 0 end
	local reveal = math.clamp(age / Plan.Tuning.SummoningReveal, 0, 1)
	local eased = 1 - (1 - reveal) ^ 3
	local fade = math.clamp((elapsed - Plan.fadeAt()) / Plan.Tuning.Fade, 0, 1)
	local firingAge = elapsed - Plan.fireAt()
	local flare = if firingAge > 0 then 0.12 * math.sin(math.min(firingAge / 0.45, 1) * math.pi) else 0
	return 0.12 + 0.88 * eased + flare + 0.15 * fade, eased * (1 - fade)
end

-- Repeated pillar punches and pressure waves inspired by cool.rbxlx's R attack.
function Plan.impactPulse(elapsed: number): number
	local age = elapsed-Plan.hitAt()
	if age<0 or elapsed>=Plan.fadeAt() then return 0 end
	return math.exp(-((age%0.28)/0.28)*7)
end

function Plan.pressureAge(index: number, elapsed: number): number
	local first = Plan.hitAt()+(index-1)*Plan.Tuning.PressureInterval
	if elapsed<first then return -1 end
	local period=6*Plan.Tuning.PressureInterval
	local cycle=math.floor((elapsed-first)/period)
	local lastCycle=math.max(0,math.floor((Plan.fadeAt()-first)/period))
	return elapsed-(first+math.min(cycle,lastCycle)*period)
end

-- Cylinder matches the vertical column. Outer pressure field deals 35% damage.
function Plan.damageMultiplier(dx: number, dy: number, dz: number): number
	local distance = math.sqrt(dx * dx + dz * dz)
	if dy < -4 or dy > Plan.Tuning.BeamHeight or distance > Plan.Tuning.DamageRadius then return 0 end
	local falloff = math.clamp((distance - Plan.Tuning.BeamRadius) / (Plan.Tuning.DamageRadius - Plan.Tuning.BeamRadius), 0, 1)
	return 1 - 0.65 * falloff
end

function Plan.beamSample(elapsed: number): (number, number)
	local age = elapsed - Plan.fireAt()
	if age < 0 or elapsed >= Plan.circlesEnd() then return 0, 0 end
	local attack = math.clamp(age / 0.18, 0, 1)
	local fade = 1 - math.clamp((elapsed - Plan.fadeAt()) / Plan.Tuning.Fade, 0, 1)
	return (1 - (1 - attack) ^ 3) * fade, math.clamp(age / 0.12, 0, 1)
end

-- Pure timeline sampling makes late packets and low frame rates deterministic.
function Plan.sample(index: number, elapsed: number): (number, number)
	local age = elapsed - Plan.revealAt(index)
	if age < 0 or elapsed >= Plan.circlesEnd() then
		return 0, 0
	end
	local reveal = math.clamp(age / Plan.Tuning.Reveal, 0, 1)
	local eased = 1 - (1 - reveal) ^ 3
	local fade = math.clamp((elapsed - Plan.fadeAt()) / Plan.Tuning.Fade, 0, 1)
	return 0.18 + 0.82 * eased + 0.07 * fade, eased * (1 - fade)
end

return Plan
