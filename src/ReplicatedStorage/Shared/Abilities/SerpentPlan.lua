-- One plan for Serpent Flare's server hits and every observer. Flame serpents
-- burst out round the caster, weave up and over and dive one after another
-- onto a ring round the aim; the scorched ring then ignites, closes in and
-- erupts as a column of fire.
local Plan = {}

Plan.Tuning = {
	Serpents = 6,
	Launch = 0.15,
	Stagger = 0.09,
	FlightMin = 1,
	FlightMax = 1.25,
	RingRadius = 7,
	StrikeRadius = 4.5,
	StrikeDamage = 10,
	StrikePush = 10,
	StrikeLift = 18,
	-- After the last serpent lands.
	Ignite = 0.15,
	-- The ring closes in this long before it erupts.
	Collapse = 0.45,
	PullLift = 12,
	EruptRadius = 9,
	EruptDamage = 30,
	EruptPush = 20,
	EruptLift = 30,
	ColumnHeight = 30,
	Aftermath = 1.2,
}

local T = Plan.Tuning
-- The hop enemies' gravity, from EnemyConfig: how far a pull carries them.
local ENEMY_GRAVITY = 115

-- The serpents, the same on the server and every client: where each bursts
-- out round the caster, when it launches, how long it flies, where on the
-- ring it lands, and how it swings out and slithers on the way.
function Plan.serpents(seed, origin)
	local random = Random.new(seed)
	local turn = random:NextNumber(0, math.pi * 2)
	local list = {}
	for i = 1, T.Serpents do
		local side = (i - (T.Serpents + 1) / 2) * 2.2
		list[i] = {
			start = (origin * CFrame.new(side, random:NextNumber(2.5, 6), random:NextNumber(1.5, 3.5))).Position,
			launch = T.Launch + (i - 1) * T.Stagger,
			flight = random:NextNumber(T.FlightMin, T.FlightMax),
			angle = turn + (i - 1) / T.Serpents * math.pi * 2,
			rise = origin.RightVector * (side * 3 + random:NextNumber(-4, 4)) - origin.LookVector * random:NextNumber(0, 4)
				+ Vector3.new(0, random:NextNumber(10, 18), 0),
			drop = Vector3.new(random:NextNumber(-10, 10), random:NextNumber(16, 24), random:NextNumber(-10, 10)),
			coils = random:NextNumber(3, 5),
			phase = random:NextNumber(0, math.pi * 2),
			sway = random:NextNumber(3, 5),
		}
	end
	return list
end

function Plan.ringPoint(centre, serpent)
	return centre + Vector3.new(math.cos(serpent.angle), 0, math.sin(serpent.angle)) * T.RingRadius
end

function Plan.landsAt(serpent)
	return serpent.launch + serpent.flight
end

function Plan.igniteAt(serpents)
	local last = 0
	for _, serpent in ipairs(serpents) do last = math.max(last, Plan.landsAt(serpent)) end
	return last + T.Ignite
end

function Plan.eruptAt(serpents)
	return Plan.igniteAt(serpents) + T.Collapse
end

-- Long enough for the slowest possible set of serpents.
function Plan.duration()
	return T.Launch + (T.Serpents - 1) * T.Stagger + T.FlightMax + T.Ignite + T.Collapse + T.Aftermath
end

-- Where `serpent` is `t` (0 to 1) along its flight to `landing`: a cubic
-- bezier that swings up and out, over, and dives, speeding up as it falls,
-- with a sideways slither that dies away at both ends.
function Plan.path(serpent, landing, t)
	t = math.clamp(t, 0, 1)
	local s = t ^ 1.35
	local u = 1 - s
	local c1 = serpent.start + serpent.rise
	local c2 = landing + serpent.drop
	local point = serpent.start * (u * u * u) + c1 * (3 * u * u * s) + c2 * (3 * u * s * s) + landing * (s * s * s)
	local across = (landing - serpent.start):Cross(Vector3.yAxis)
	across = if across.Magnitude > 0.01 then across.Unit else Vector3.xAxis
	local wave = math.sin(t * math.pi * serpent.coils + serpent.phase) * math.sin(t * math.pi) * serpent.sway
	return point + across * wave + Vector3.yAxis * (wave * 0.4)
end

-- The horizontal speed that carries a hop of `PullLift` most of the way in
-- from `distance`.
function Plan.pullSpeed(distance)
	return distance * 0.8 / (2 * T.PullLift / ENEMY_GRAVITY)
end

return Plan
