-- One clock for Astral Verdict's server hits and every observer. A
-- constellation in the shape of a sword is drawn in the sky over the aim;
-- it becomes a blade of starlight, turns point-down, falls into a star seal
-- on the ground, and after a moment shatters into stars that rain outwards.
local Plan = {}

Plan.Tuning = {
	Draw = 0.6,
	Forge = 0.35,
	Turn = 0.35,
	Windup = 0.15,
	Drop = 0.14,
	-- The blade stands in the ground this long before it shatters.
	Embed = 0.9,
	Aftermath = 1,
	-- The blade's middle hangs this high over the aim.
	Height = 26,
	Length = 18,
	Rise = 4,
	-- How deep the tip sinks into the ground.
	Bury = 3,
	SealRadius = 9,
	ImpactRadius = 10,
	ImpactDamage = 55,
	ImpactPush = 30,
	ImpactLift = 30,
	Shards = 14,
	ShardFlight = 0.35,
	RainRadius = 15,
	RainDamage = 14,
	RainPush = 14,
	RainLift = 18,
}

local T = Plan.Tuning

function Plan.turnAt()
	return T.Draw + T.Forge
end

function Plan.dropAt()
	return Plan.turnAt() + T.Turn + T.Windup
end

function Plan.impactAt()
	return Plan.dropAt() + T.Drop
end

function Plan.shatterAt()
	return Plan.impactAt() + T.Embed
end

-- When the falling stars land.
function Plan.rainAt()
	return Plan.shatterAt() + T.ShardFlight
end

function Plan.duration()
	return Plan.rainAt() + T.Aftermath
end

-- The blade's frame: `look` is the caster's flat facing, `side` across it.
function Plan.frame(origin)
	local look = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	return look, look:Cross(Vector3.yAxis).Unit
end

-- The constellation, a sword in stars with its tip up: pommel, guard centre,
-- the guard's two ends, two along the blade and the tip, shuffled a little
-- by the seed. `links` joins them into the outline.
function Plan.stars(seed, middle, side)
	local random = Random.new(seed)
	local up = Vector3.yAxis
	local half = T.Length / 2
	local function jitter(amount)
		return side * random:NextNumber(-amount, amount) + up * random:NextNumber(-amount, amount)
	end
	return {
		middle - up * (half + 3) + jitter(0.6),
		middle - up * half,
		middle - up * half - side * 4 + jitter(0.8),
		middle - up * half + side * 4 + jitter(0.8),
		middle - up * (half / 3) + jitter(1.2),
		middle + up * (half / 3) + jitter(1.2),
		middle + up * half,
	}
end

Plan.links = {{1, 2}, {3, 2}, {2, 4}, {2, 5}, {5, 6}, {6, 7}}

-- Where each star of the shattered blade lands round the aim, and when.
function Plan.shards(seed)
	local random = Random.new(seed + 7)
	local list = {}
	for i = 1, T.Shards do
		local angle = (i - 1) / T.Shards * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		list[i] = {
			along = random:NextNumber(0.1, 1),
			offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(5, T.RainRadius - 1),
			flight = T.ShardFlight * random:NextNumber(0.8, 1),
			lift = random:NextNumber(6, 12),
		}
	end
	return list
end

-- The ground under the aim, and which way is up from it.
function Plan.ground(target, params)
	local hit = workspace:Raycast(target + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	if hit then
		return hit.Position, if hit.Normal.Y > 0.5 then hit.Normal else Vector3.yAxis
	end
	return target, Vector3.yAxis
end

return Plan
