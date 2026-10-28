-- One clock for the Sumi Whirl server hit and every observer. The caster
-- paints a ring of ink around themselves in one brushstroke, then the ring
-- cuts: everything inside is slashed and flung outwards in a burst of ink.
local Plan = {}

Plan.Tuning = {
	Windup = 0.12,
	Stroke = 0.24,
	CutAt = 0.44,
	-- The ring, around the caster at waist height.
	Radius = 9.5,
	Height = -0.6,
	Reach = 12,
	Damage = 58,
	Push = 36,
	Lift = 20,
	Aftermath = 1.5,
}

local T = Plan.Tuning

function Plan.duration()
	return T.CutAt + T.Aftermath + 0.3
end

-- How far round the brush has painted, 0..1, eased so it whips through.
function Plan.painted(elapsed)
	local t = math.clamp((elapsed - T.Windup) / T.Stroke, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

-- Angle along the stroke, starting behind the caster's right shoulder and
-- turning the way a right-handed sweep goes.
function Plan.angle(facing, along)
	local start = math.atan2(-facing.Z, facing.X) - math.pi * 0.75
	return start - along * math.pi * 2
end

function Plan.point(centre, facing, along, radius)
	local a = Plan.angle(facing, along)
	return centre + Vector3.new(math.cos(a), 0, -math.sin(a)) * radius
end

return Plan
