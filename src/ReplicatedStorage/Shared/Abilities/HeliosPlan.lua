-- One clock and one sweep for the Helios Lance server hits and every
-- observer. A small sun gathers over the caster, then pours a beam of fire
-- down at the aim and drags it sideways across the ground, carving a burning
-- scar; the beam collapses in a blast at the end of the sweep and the scar
-- burns on for a while.
local Plan = {}

Plan.Tuning = {
	Charge = 0.7,
	Sweep = 1.6,
	Aftermath = 2.2,
	-- The sun, over the caster's root.
	Height = 10,
	-- The sweep runs this far either side of the aim, across the aim line.
	HalfWidth = 7.5,
	Tick = 0.12,
	BeamRadius = 6,
	BeamDamage = 10,
	BlastRadius = 9,
	BlastDamage = 40,
	BlastPush = 30,
	BlastLift = 28,
	-- The scar is a wall of fire across the aim: whatever crosses it burns.
	ScarWidth = 3.5,
	Burn = 7,
	BurnTick = 0.4,
}

local T = Plan.Tuning

function Plan.blastAt()
	return T.Charge + T.Sweep
end

function Plan.duration()
	return Plan.blastAt() + T.Aftermath + 0.3
end

function Plan.flat(direction)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

function Plan.sun(origin)
	return origin.Position + Vector3.new(0, T.Height, 0)
end

-- The two ends of the sweep, aim-side first then across: right to left as
-- the caster sees it.
function Plan.ends(origin, target)
	local forward = Plan.flat(target - origin.Position)
	local right = forward:Cross(Vector3.yAxis).Unit
	return target + right * T.HalfWidth, target - right * T.HalfWidth
end

-- 0..1 along the sweep at `elapsed`, eased in and out.
function Plan.progress(elapsed)
	local t = math.clamp((elapsed - T.Charge) / T.Sweep, 0, 1)
	return t * t * (3 - 2 * t)
end

--[[
	Where the beam lands for a point on the sweep line: straight from the sun
	towards a spot dropped onto the ground, stopping at the first thing in the
	way. Shared so the server's hits and every client's beam agree.
]]
function Plan.landing(sun, along, params)
	local ground = workspace:Raycast(along + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	local aim = if ground then ground.Position else along
	local toward = aim - sun
	local hit = workspace:Raycast(sun, toward.Unit * (toward.Magnitude + 2), params)
	if hit then return hit.Position, hit.Normal end
	return aim, Vector3.yAxis
end

return Plan
