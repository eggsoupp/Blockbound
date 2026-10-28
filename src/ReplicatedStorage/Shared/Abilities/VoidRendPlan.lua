-- One clock, flight path and claw layout for the server hit and every observer.
-- Two presses: the first leaps straight up and hovers; the second (left click
-- or the same key) dives along whatever way the caster is facing and rakes
-- three claws into the ground there. Hovering too long strikes on its own.
local Plan = {}

Plan.Tuning = {
	Rise = 0.24,
	ApexHeight = 11,
	MaxHover = 0.75,
	Dive = 0.13,
	DiveReach = 22,
	DiveMin = 4,
	ClawCount = 3,
	ClawSpacing = 3.4,
	ClawStart = 0.5,
	ClawLength = 17,
	-- The middle claw starts a little behind and reaches a little further.
	MiddleExtra = 1.5,
	HitHalfWidth = 6.5,
	HitBehind = 4,
	HitHeight = 8,
	Damage = 95,
	Push = 26,
	Lift = 22,
	Glow = 0.95,
	Aftermath = 2.4,
}

local T = Plan.Tuning
local PATH = Vector3.new(2.4, 3, 2.4)

-- How long the server keeps a cast alive: leap, the longest hover, the dive
-- and the scars cooling.
function Plan.duration()
	return T.Rise + T.MaxHover + T.Dive + T.Aftermath + 0.3
end

-- How long either half of the effect (leap or strike) can draw for.
function Plan.effectDuration()
	return math.max(T.Rise + T.MaxHover + 0.4, T.Dive + T.Aftermath)
end

function Plan.flat(direction)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

function Plan.apex(origin)
	return origin + Vector3.new(0, T.ApexHeight, 0)
end

-- Root position while leaping: a decelerating rise, then a slow bob.
function Plan.hover(origin, elapsed)
	local apex = Plan.apex(origin)
	if elapsed <= T.Rise then
		local a = math.clamp(elapsed / T.Rise, 0, 1)
		return origin:Lerp(apex, 1 - (1 - a) * (1 - a))
	end
	return apex + Vector3.new(0, math.sin((elapsed - T.Rise) * 5) * 0.35, 0)
end

-- One front flip through the rise.
function Plan.flip(elapsed)
	local t = math.clamp(elapsed / T.Rise, 0, 1)
	return CFrame.Angles(-math.pi * 2 * t * t * (3 - 2 * t), 0, 0)
end

-- Root position while diving: accelerating from the apex onto the landing.
function Plan.dive(apex, landing, elapsed)
	local a = math.clamp(elapsed / T.Dive, 0, 1)
	return apex:Lerp(landing, a * a)
end

--[[
	Where a dive from `apex` along `direction` lands: the furthest reach with
	ground under it and a clear path to it, else straight down. Shared so the
	caster's aim preview shows the same spot the server will choose.
]]
function Plan.findLanding(apex, direction, params, standing)
	local forward = Plan.flat(direction)
	local drop = Vector3.new(0, -(T.ApexHeight + 30), 0)
	for reach = T.DiveReach, T.DiveMin, -2 do
		local hit = workspace:Raycast(apex + forward * reach, drop, params)
		if hit and hit.Normal.Y > 0.5 then
			local landing = hit.Position + Vector3.new(0, standing + 0.1, 0)
			if not workspace:Blockcast(CFrame.new(apex), PATH, landing + Vector3.yAxis - apex, params) then
				return landing, hit.Position
			end
		end
	end
	local hit = workspace:Raycast(apex, drop, params)
	if hit then
		return hit.Position + Vector3.new(0, standing + 0.1, 0), hit.Position
	end
	return nil
end

-- The three claw lines on the ground, as {from, to} pairs.
function Plan.claws(ground, direction)
	local forward = Plan.flat(direction)
	local right = forward:Cross(Vector3.yAxis).Unit
	local lines = {}
	local half = (T.ClawCount + 1) / 2
	for i = 1, T.ClawCount do
		local lateral = (i - half) * T.ClawSpacing
		local middle = i == math.round(half)
		local start = T.ClawStart - (if middle then T.MiddleExtra else 0)
		local length = T.ClawLength + (if middle then T.MiddleExtra * 2 else 0)
		local from = ground + right * lateral + forward * start
		table.insert(lines, {from = from, to = from + forward * length})
	end
	return lines
end

-- Is a world point inside the raked area?
function Plan.inside(ground, direction, point)
	local forward = Plan.flat(direction)
	local right = forward:Cross(Vector3.yAxis).Unit
	local delta = point - ground
	local along = delta:Dot(forward)
	local reach = T.ClawStart + T.ClawLength + T.MiddleExtra
	return along >= -T.HitBehind and along <= reach
		and math.abs(delta:Dot(right)) <= T.HitHalfWidth
		and math.abs(delta.Y) <= T.HitHeight
end

return Plan
