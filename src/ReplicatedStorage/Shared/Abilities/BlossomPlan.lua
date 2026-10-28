-- One clock and one lane for the Blossom Road server hits and every observer.
-- A gust of petals runs out along the aim, flowers bursting up behind it one
-- after another, and the last one blooms huge. The lane then stays as a road
-- of drifting petals for a few seconds, mending every player who walks it and
-- stinging every enemy.
local Plan = {}

Plan.Tuning = {
	Blooms = 8,
	Spacing = 4.5,
	-- Where the first bloom sits, ahead of the caster's feet.
	Lead = 3,
	-- How far the lane climbs or drops between two blooms.
	StepUp = 6.5,
	StepDown = 10,
	FirstBloom = 0.12,
	BloomStep = 0.07,
	BloomRadius = 5.5,
	BloomDamage = 16,
	BloomLift = 30,
	FinaleRadius = 9,
	FinaleDamage = 34,
	FinaleLift = 40,
	FinalePush = 18,
	-- The road.
	Road = 4,
	Pulse = 0.8,
	RoadWidth = 4.5,
	Heal = 6,
	Sting = 5,
}

local T = Plan.Tuning

function Plan.bloomAt(index)
	return T.FirstBloom + (index - 1) * T.BloomStep
end

function Plan.finaleAt(count)
	return Plan.bloomAt(count) + 0.12
end

function Plan.duration()
	return Plan.finaleAt(T.Blooms) + T.Road + 0.4
end

function Plan.flat(direction)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

--[[
	The ground points the lane passes through, nearest first. It walks out a
	point at a time, climbing steps up to StepUp and dropping down slopes, and
	stops at a wall taller than that or a drop deeper than StepDown, so the
	road follows blocky hills.
]]
function Plan.lane(feet, direction, params)
	local points = {}
	local height, previous = feet.Y, feet
	for i = 1, T.Blooms do
		local column = feet + direction * (T.Lead + T.Spacing * (i - 1))
		local from = Vector3.new(previous.X, height + T.StepUp, previous.Z)
		local over = Vector3.new(column.X, height + T.StepUp, column.Z)
		if workspace:Raycast(from, over - from, params) then break end
		local ground = workspace:Raycast(over, Vector3.new(0, -(T.StepUp + T.StepDown), 0), params)
		if not ground then break end
		height = ground.Position.Y
		previous = Vector3.new(column.X, height, column.Z)
		table.insert(points, previous)
	end
	return points
end

-- Distance from `point` to the lane, across the ground.
function Plan.distanceToLane(points, point)
	local best = math.huge
	local flat = Vector3.new(point.X, 0, point.Z)
	for i = 1, #points - 1 do
		local a = Vector3.new(points[i].X, 0, points[i].Z)
		local b = Vector3.new(points[i + 1].X, 0, points[i + 1].Z)
		local ab = b - a
		local t = math.clamp((flat - a):Dot(ab) / math.max(ab:Dot(ab), 1e-3), 0, 1)
		best = math.min(best, (flat - (a + ab * t)).Magnitude)
	end
	if #points == 1 then best = (flat - Vector3.new(points[1].X, 0, points[1].Z)).Magnitude end
	return best
end

return Plan
