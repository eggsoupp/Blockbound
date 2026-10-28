-- One clock for the Abyss Gate server hits and every observer. A void sigil
-- opens on the ground at the aim and drags everything near it inwards; the
-- gate then erupts as a black pillar that juggles whatever stands in it, and
-- finally implodes, throwing the survivors back out.
local Plan = {}

Plan.Tuning = {
	-- The sigil draws itself and pulls.
	Open = 1,
	-- The pillar stands.
	Erupt = 1.2,
	Aftermath = 1.2,
	Radius = 11,
	-- Enemies this close are dragged towards the middle while the sigil opens.
	PullRadius = 16,
	PullAt = {0.35, 0.7},
	PullLift = 14,
	-- Each pull lands an enemy this much of the way in.
	PullShare = 0.7,
	PillarHeight = 60,
	PillarRadius = 7,
	Tick = 0.2,
	TickDamage = 8,
	-- Enough to keep a body hovering between ticks.
	TickLift = 20,
	CollapseRadius = 12,
	CollapseDamage = 45,
	CollapsePush = 36,
	CollapseLift = 24,
}

local T = Plan.Tuning
-- The hop enemies' gravity, from EnemyConfig: how far a pull carries them.
local ENEMY_GRAVITY = 115

function Plan.collapseAt()
	return T.Open + T.Erupt
end

function Plan.duration()
	return Plan.collapseAt() + T.Aftermath + 0.3
end

-- The horizontal speed that carries a hop of `PullLift` from `distance` out
-- to `PullShare` of the way in.
function Plan.pullSpeed(distance)
	local airtime = 2 * T.PullLift / ENEMY_GRAVITY
	return distance * T.PullShare / airtime
end

-- The gate's floor under the aim, and which way is up from it.
function Plan.ground(target, params)
	local hit = workspace:Raycast(target + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	if hit then
		local normal = if hit.Normal.Y > 0.5 then hit.Normal else Vector3.yAxis
		return hit.Position, normal
	end
	return target, Vector3.yAxis
end

return Plan
