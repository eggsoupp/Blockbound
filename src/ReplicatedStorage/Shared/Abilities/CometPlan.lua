-- One clock and one flight path for the Azure Comet server hits and every
-- observer. A comet gathers high over the caster, dives at the aim and
-- craters; three pressure rings then slam down onto the crater.
local Plan = {}

Plan.Tuning = {
	Charge = 0.9,
	Flight = 0.4,
	-- The comet forms this high over the caster, a little behind them.
	Height = 32,
	Back = 4,
	ImpactRadius = 14,
	ImpactDamage = 40,
	ImpactPush = 34,
	ImpactLift = 26,
	-- The pressure rings after the impact.
	Pulses = 3,
	PulseGap = 0.3,
	PulseRadius = 12,
	PulseDamage = 6,
	PulsePush = 10,
	PulseLift = 6,
	Aftermath = 1.2,
}

local T = Plan.Tuning

function Plan.impactAt()
	return T.Charge + T.Flight
end

function Plan.pulseAt(index)
	return Plan.impactAt() + index * T.PulseGap
end

function Plan.duration()
	return Plan.pulseAt(T.Pulses) + T.Aftermath
end

function Plan.sky(origin)
	local look = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	return origin.Position + Vector3.new(0, T.Height, 0) - look * T.Back
end

-- Where the comet lands: straight from the sky towards the aim, stopping at
-- the first thing in the way. Shared so the server's hits and every
-- client's crater agree.
function Plan.impact(sky, target, params)
	local toward = target - sky
	local hit = workspace:Raycast(sky, toward.Unit * (toward.Magnitude + 6), params)
	if hit then
		local normal = if hit.Normal.Y > 0.5 then hit.Normal else Vector3.yAxis
		return hit.Position, normal
	end
	return target, Vector3.yAxis
end

-- The comet at `elapsed`, accelerating down its path, and how far along.
function Plan.flight(sky, impact, elapsed)
	local t = math.clamp((elapsed - T.Charge) / T.Flight, 0, 1)
	return sky:Lerp(impact, t * t), t
end

return Plan
