-- One clock for Penumbra's server hits, the caster's own movement and every
-- observer.
--
-- Penumbra (Celestial, F) is a teleport through the ground. The caster raises
-- their hands and crouches; a white-hot magenta dome bursts round them and
-- they SINK into the ground, leaving a shroud of dark ribbons where they
-- stood. A moment later, where they aimed, their hands break the surface, a
-- second burst goes off and they RISE out of the ground inside its shroud,
-- climb out on their hands and knees, and stand.
--
-- Flying (wings, the character's Flying attribute), there is no ground to sink
-- into: the caster folds into the first burst and is gone, streaks through the
-- air as a dark comet, and bursts out of the second one flung open like a
-- star, still flying.
--
-- Both bursts hit whatever is in them and throw it out; the arrival shroud
-- nicks whatever is still in it a few times. The caster cannot be hurt from
-- the first burst until they are out of the ground.
local Plan = {}

Plan.Tuning = {
	-- Hands up, then a crouch, before the first burst.
	Windup = 0.38,
	-- Sinking from standing to buried.
	Sink = 0.32,
	-- The second burst, from the start of the cast. The hands break the
	-- surface a little before it.
	Arrive = 1.5,
	HandsEarly = 0.14,
	-- Rising from buried to standing, from the second burst.
	Rise = 0.38,
	-- On hands and knees, then standing up.
	Crawl = 0.48,
	StandUp = 0.4,
	-- How deep the caster goes: their root this far below standing.
	Depth = 7,

	-- Each burst's dome flashes out to Radius in Flash, then fades. The
	-- departure shroud lasts DepartShroud; the arrival one ArriveShroud; both
	-- thin away over Fade.
	Flash = 0.13,
	DepartShroud = 0.95,
	ArriveShroud = 1.25,
	Fade = 0.7,

	-- How far the aim may be (AbilityConfig castRange clamps it first), and
	-- how far back toward the caster a landing is searched for when the aim
	-- itself has nowhere to stand.
	Range = 64,
	SearchStep = 3,
	-- Room a standing body needs (EchoStep's box).
	Body = Vector3.new(3.2, 4.8, 3.2),

	Radius = 20,
	-- On the ground: how far above or below a burst still counts.
	Reach = 10,
	DepartDamage = 24,
	ArriveDamage = 40,
	BurstPush = 44,
	BurstLift = 26,
	-- The arrival shroud nicks what is inside it at these times after the
	-- second burst.
	Ticks = {0.42, 0.78, 1.14},
	TickDamage = 6,
}

local T = Plan.Tuning

-- The collision group the caster's body is in while it passes through the
-- ground: it collides with nothing (Abilities/Penumbra registers it). A
-- Humanoid keeps forcing CanCollide back on its torso, so CanCollide alone
-- cannot take a body underground.
Plan.GhostGroup = "PenumbraGhost"

function Plan.departAt()
	return T.Windup
end

-- Fully under (or, flying, gone).
function Plan.goneAt()
	return T.Windup + T.Sink
end

function Plan.handsAt()
	return T.Arrive - T.HandsEarly
end

function Plan.arriveAt()
	return T.Arrive
end

function Plan.risenAt()
	return T.Arrive + T.Rise
end

function Plan.standAt()
	return Plan.risenAt() + T.Crawl
end

function Plan.departShroudEnd()
	return T.Windup + T.DepartShroud
end

function Plan.arriveShroudEnd()
	return T.Arrive + T.ArriveShroud
end

function Plan.duration()
	return math.max(Plan.arriveShroudEnd() + T.Fade, Plan.standAt() + T.StandUp)
end

-- Is `position` inside a burst centred on `centre`? `air` is a sphere, the
-- ground a squat cylinder.
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

-- The ground under `position`, or nil when there is none near (flying high).
function Plan.ground(position, params)
	local hit = workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -9, 0), params)
	return hit and hit.Position or nil
end

--[[
	Where the caster's root is at `t`, given where it stood (`from`) and
	where it comes up (`to`), both standing positions. nil when the caster is
	free (before the sink, and after they have risen).

	Ground: down into the ground at `from`, gliding underground to under
	`to`, and up out of it. Air: held where they are while the first burst
	takes them, moved straight to `to` while gone, held there while the
	second one gives them back.
]]
local function ease(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

function Plan.rootAt(t, from, to, air)
	local departAt, goneAt, risenAt = Plan.departAt(), Plan.goneAt(), Plan.risenAt()
	-- Held a moment after rising: on the ground that is the climb out on hands
	-- and knees.
	if t < departAt or t >= risenAt + (if air then 0.2 else T.Crawl * 0.6) then
		return nil
	end
	if air then
		return if t < goneAt then from else to
	end
	local down = Vector3.new(0, T.Depth, 0)
	if t < goneAt then
		local u = (t - departAt) / (goneAt - departAt)
		return from - down * (u * u)
	end
	local startRise = Plan.handsAt() - 0.12
	if t < startRise then
		return (from - down):Lerp(to - down, ease((t - goneAt) / (startRise - goneAt)))
	end
	local u = math.clamp((t - startRise) / (risenAt - startRise), 0, 1)
	return to - down * (1 - u) ^ 1.6
end

return Plan
