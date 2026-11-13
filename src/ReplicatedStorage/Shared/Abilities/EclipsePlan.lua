-- One clock for Eclipse Prison's server hits and every observer.
--
-- The caster calls the dark: black spikes split the ground round them and the
-- world dims. At the aim, magenta blocks climb out of the ground and stack
-- into a black monolith-cage round everything standing there, glowing at its
-- edges. Black swords gather in the air round it and stab in one after
-- another; then the whole cage flares solid magenta and comes apart in
-- vertical streaks.
--
-- Everything inside the cage's footprint is held still from the moment the
-- blocks start to rise until the flare. Each sword hits everyone inside for a
-- little; the flare is the big hit.
local Plan = {}

Plan.Tuning = {
	-- The caster's call, before anything happens at the aim.
	Call = 0.75,
	-- The cage rising layer by layer, then its lid.
	Build = 1.45,
	-- The finished black cage stands this long before the first sword lands.
	Hold = 0.25,
	-- Swords stab in one after another across this span.
	Barrage = 1,
	-- After the last sword the cage charges up this long before the flare,
	-- with lightning striking round it.
	Settle = 0.55,
	-- The cage blows apart, and the world's light returns.
	Shatter = 1.3,
	Aftermath = 0.9,

	-- The cage: a hollow box this many cells across, deep and tall
	-- (42 x 42 x 66 studs).
	Cell = 6,
	Cells = 7,
	Layers = 11,
	-- How far a sword flies, and how long it takes.
	Swords = 26,
	SwordFlight = 0.14,
	SwordDistance = 52,

	-- An enemy this close to the aim (across the ground) pulls the cage onto
	-- it. Small on purpose: the player aims, this only forgives a near miss.
	Snap = 4.5,
	-- Who counts as inside: the footprint plus this much, up to the roof.
	Margin = 1,
	SwordDamage = 2.5,
	FlareDamage = 55,
	-- Survivors are thrown out of the broken cage.
	FlarePush = 34,
	FlareLift = 28,
}

local T = Plan.Tuning

function Plan.size()
	return T.Cell * T.Cells
end

function Plan.height()
	return T.Cell * T.Layers
end

-- When the blocks start rising: everyone inside is held from here.
function Plan.buildAt()
	return T.Call
end

function Plan.closedAt()
	return T.Call + T.Build
end

-- When sword `i` (1..Swords) lands.
function Plan.swordAt(i)
	local first = Plan.closedAt() + T.Hold + T.SwordFlight
	return first + (i - 1) * T.Barrage / math.max(T.Swords - 1, 1)
end

-- When sword `i` leaves the air.
function Plan.launchAt(i)
	return Plan.swordAt(i) - T.SwordFlight
end

function Plan.flareAt()
	return Plan.swordAt(T.Swords) + T.Settle
end

function Plan.duration()
	return Plan.flareAt() + T.Shatter + T.Aftermath
end

-- The cage's floor under the aim, and which way is up from it.
function Plan.ground(target, params)
	local hit = workspace:Raycast(target + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	if hit then
		return hit.Position
	end
	return target
end

-- The cage's floor frame: on `centre`, upright, one face square to the caster.
function Plan.frame(centre, casterPosition)
	local look = Vector3.new(centre.X - casterPosition.X, 0, centre.Z - casterPosition.Z)
	if look.Magnitude < 0.05 then
		look = Vector3.zAxis
	end
	return CFrame.lookAt(centre, centre + look.Unit)
end

-- Is `position` inside the cage standing on `frame`?
function Plan.inside(frame, position)
	local half = Plan.size() * 0.5 + T.Margin
	local offset = frame:PointToObjectSpace(position)
	return math.abs(offset.X) <= half and math.abs(offset.Z) <= half
		and offset.Y >= -3 and offset.Y <= Plan.height() + 2
end

return Plan
