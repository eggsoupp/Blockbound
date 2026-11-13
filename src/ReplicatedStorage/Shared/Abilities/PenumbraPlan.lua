-- One clock for Penumbra's server hits and every observer.
--
-- Penumbra (Celestial, F) is cast round the caster, on the ground or in the
-- air. They gather the dark in (magenta streaks pulled into their chest),
-- then vanish into a white-hot magenta dome while crescent slashes whip round
-- it; a shroud of dark violet ribbons billows out where they stood, crackling,
-- and they step back out of it as it thins into black wisps.
--
-- The burst is the big hit and throws everything out of the dome; the shroud
-- nicks whatever is still inside it a few times. The caster cannot be hurt
-- while they are gone.
--
-- In the air (wings, Flying) the dome is a whole sphere, the hit and the
-- throw reach above and below as well, there is no ground under it, and the
-- caster's pose is different (CastPose: tucked, then flung open like a star,
-- rather than crouched, then arms thrown up).
local Plan = {}

Plan.Tuning = {
	-- Drawing the dark in, before the burst.
	Gather = 0.32,
	-- The dome flashes out to Radius in this long, then fades.
	Flash = 0.13,
	-- The caster is gone (invisible and unhurt) from the burst for this long.
	Vanish = 0.3,
	-- The shroud billows this long, then thins away.
	Shroud = 1.45,
	Fade = 0.8,

	Radius = 22,
	-- On the ground: how far above or below the caster still counts.
	Reach = 10,
	BurstDamage = 42,
	BurstPush = 46,
	BurstLift = 26,
	-- The shroud nicks what is inside it at these times after the burst.
	Ticks = {0.42, 0.78, 1.14},
	TickDamage = 6,
}

local T = Plan.Tuning

function Plan.burstAt()
	return T.Gather
end

function Plan.shroudEnd()
	return T.Gather + T.Shroud
end

function Plan.duration()
	return Plan.shroudEnd() + T.Fade
end

-- Is `position` inside the burst centred on `centre`? `air` is a sphere,
-- the ground a squat cylinder.
function Plan.inside(centre, position, air, radius)
	radius = radius or T.Radius
	local offset = position - centre
	if air then
		return offset.Magnitude <= radius
	end
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= T.Reach
end

-- Away from the centre: across the ground, or every way in the air.
function Plan.away(centre, position, air, fallback)
	local offset = position - centre
	if not air then
		offset = Vector3.new(offset.X, 0, offset.Z)
	end
	return if offset.Magnitude > 0.1 then offset.Unit else fallback
end

-- The ground under the caster, or nil when there is none near (flying high).
function Plan.ground(position, params)
	local hit = workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -9, 0), params)
	return hit and hit.Position or nil
end

return Plan
