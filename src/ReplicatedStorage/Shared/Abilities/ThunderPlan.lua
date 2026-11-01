-- One clock for the Thunderhead server hits and every observer. A storm cloud
-- gathers over the aim, bolts strike the ground around it one after another,
-- and a last strike lands in the middle and throws everything back.
local Plan = {}

Plan.Tuning = {
	Gather = 0.8,
	Bolts = 3,
	BoltGap = 0.26,
	BoltRadius = 8,
	BoltDamage = 16,
	-- How far from the aim the bolts land.
	Scatter = 11,
	FinalGap = 0.34,
	FinalRadius = 13,
	FinalDamage = 34,
	FinalPush = 32,
	FinalLift = 26,
	CloudHeight = 26,
	Aftermath = 1.3,
}

local T = Plan.Tuning

function Plan.boltAt(index)
	return T.Gather + (index - 1) * T.BoltGap
end

function Plan.finalAt()
	return Plan.boltAt(T.Bolts) + T.FinalGap
end

function Plan.duration()
	return Plan.finalAt() + T.Aftermath
end

-- The ground under a point, and which way is up from it.
function Plan.ground(target, params)
	local hit = workspace:Raycast(target + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	if hit then
		return hit.Position, if hit.Normal.Y > 0.5 then hit.Normal else Vector3.yAxis
	end
	return target, Vector3.yAxis
end

-- Where each bolt lands: spaced round the aim, from the cast's seed.
function Plan.boltPoints(centre, seed, params)
	local rng = Random.new(seed)
	local start = rng:NextNumber(0, math.pi * 2)
	local points = {}
	for i = 1, T.Bolts do
		local angle = start + (i - 1) * math.pi * 2 / T.Bolts + rng:NextNumber(-0.4, 0.4)
		local reach = rng:NextNumber(T.Scatter * 0.6, T.Scatter)
		local point = Plan.ground(centre + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach), params)
		points[i] = point
	end
	return points
end

return Plan
