-- One clock and one arc for the Deluge server hits and every observer. Water
-- gathers into an orb over the caster, the orb is lobbed along a high arc,
-- and where it lands it bursts into a towering splash that throws everything
-- up; a beat later the water surges outwards in a ring of geysers.
local Plan = {}

Plan.Tuning = {
	Gather = 0.34,
	Flight = 0.5,
	-- The orb forms this far over the caster's root.
	Hold = 6.5,
	-- Arc height over the higher end: a base plus a share of the throw.
	Apex = 7,
	ApexPerStud = 0.22,
	Radius = 11,
	Damage = 40,
	Lift = 52,
	Push = 14,
	-- The surge: geysers in widening rings after the splash.
	SurgeDelay = 0.26,
	SurgeRings = {7.5, 12, 16.5},
	SurgeStep = 0.12,
	SurgeReach = 18,
	SurgeDamage = 16,
	SurgePush = 38,
	SurgeLift = 16,
	Aftermath = 1.7,
}

local T = Plan.Tuning

function Plan.orbStart(origin)
	return origin.Position + Vector3.new(0, T.Hold, 0) - origin.LookVector * 0.5
end

function Plan.hitAt()
	return T.Gather + T.Flight
end

function Plan.surgeAt(ring)
	return Plan.hitAt() + T.SurgeDelay + (ring - 1) * T.SurgeStep
end

function Plan.duration()
	return Plan.surgeAt(#T.SurgeRings) + T.Aftermath + 0.3
end

-- The ground under the aim point, else the aim point itself (an air burst).
function Plan.landing(target, params)
	local hit = workspace:Raycast(target + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	if hit then return hit.Position, hit.Normal end
	return target, Vector3.yAxis
end

-- The orb's position `t` (0..1) along its throw: a quadratic arc whose
-- control point sits over the middle, high enough to clear what is between.
function Plan.arc(from, to, t)
	local mid = (from + to) / 2
	local top = math.max(from.Y, to.Y) + T.Apex + (to - from).Magnitude * T.ApexPerStud
	local control = Vector3.new(mid.X, top, mid.Z)
	local u = 1 - t
	return from * (u * u) + control * (2 * u * t) + to * (t * t)
end

return Plan
