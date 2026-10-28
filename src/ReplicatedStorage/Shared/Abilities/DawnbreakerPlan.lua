-- One clock and one flight path for the Dawnbreaker server hits and every
-- observer. A short swing, then a wide golden crescent flies along the aim,
-- cutting through everything in its way, and bursts into a sun-dome where it
-- meets a wall, the ground, or the end of its reach.
local Plan = {}

Plan.Tuning = {
	Windup = 0.16,
	Speed = 125,
	Range = 64,
	-- The crescent stands across its flight like an arch: tip to tip, how
	-- far the crown rises over the tips, and how far it leads them.
	Width = 17,
	Arch = 6,
	Bow = 2.5,
	-- The flying crescent's hit slab, around the aim line.
	HitHalfWidth = 8,
	HitHalfHeight = 4.5,
	-- Wall check: a thin box the size of the crescent's middle.
	Probe = Vector3.new(5, 2.5, 1),
	PierceDamage = 32,
	PiercePush = 16,
	BurstRadius = 14,
	BurstDamage = 64,
	BurstPush = 38,
	BurstLift = 22,
	Aftermath = 1.9,
}

local T = Plan.Tuning

-- Where the crescent leaves from: chest height, a little ahead.
function Plan.launchPoint(origin)
	return (origin * CFrame.new(0, 0.6, -2.5)).Position
end

function Plan.direction(from, target, fallback)
	local delta = if typeof(target) == "Vector3" then target - from else Vector3.zero
	if delta.Magnitude < 1 then delta = fallback end
	return delta.Unit
end

function Plan.travelTime(distance)
	return distance / T.Speed
end

-- How far along its line the crescent's middle is `elapsed` into the cast.
function Plan.reach(elapsed, distance)
	return math.clamp((elapsed - T.Windup) * T.Speed, 0, distance)
end

function Plan.hitAt(distance)
	return T.Windup + Plan.travelTime(distance)
end

function Plan.duration()
	return T.Windup + Plan.travelTime(T.Range) + T.Aftermath + 0.3
end

--[[
	Where a crescent from `from` along `direction` ends: the first thing solid
	in its way, else full reach. Returns the burst point, the surface normal
	(or the reverse of the flight when it ran out of reach) and the distance.
]]
function Plan.trace(from, direction, params)
	local frame = CFrame.lookAt(from, from + direction)
	local hit = workspace:Blockcast(frame, T.Probe, direction * T.Range, params)
	if hit then
		return hit.Position + hit.Normal * 0.6, hit.Normal, math.max(hit.Distance, 0)
	end
	return from + direction * T.Range, -direction, T.Range
end

-- Is `point` inside the slab the crescent sweeps between `near` and `far`
-- studs along its line?
function Plan.swept(from, direction, near, far, point)
	local delta = point - from
	local along = delta:Dot(direction)
	if along < near - 1 or along > far + 1 then return false end
	local right = direction:Cross(Vector3.yAxis)
	right = if right.Magnitude > 0.05 then right.Unit else Vector3.xAxis
	local up = right:Cross(direction).Unit
	return math.abs(delta:Dot(right)) <= T.HitHalfWidth and math.abs(delta:Dot(up)) <= T.HitHalfHeight
end

return Plan
