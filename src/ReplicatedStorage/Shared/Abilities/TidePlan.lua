-- One clock for Tidecaller's server hits and every observer. The caster
-- stamps a tide pool open at their feet; water orbs rise out of it and circle
-- them, and the server fires them one at a time at whichever enemy nearby has
-- been hit least, each landing in a splash.
local Plan = {}

Plan.Tuning = {
	Shots = 8,
	FirstShot = 0.6,
	ShotGap = 0.26,
	Flight = 0.4,
	-- The pool stays open this long after the last splash.
	Linger = 0.8,
	-- Enemies are looked for this far from the caster.
	Range = 34,
	PoolRadius = 9,
	OrbitRadius = 4.2,
	-- Above the caster's root.
	OrbitHeight = 2.2,
	OrbitSpeed = 2.4,
	SplashRadius = 4.5,
	SplashDamage = 13,
	SplashPush = 12,
	SplashLift = 16,
}

local T = Plan.Tuning

function Plan.shotAt(index)
	return T.FirstShot + (index - 1) * T.ShotGap
end

function Plan.duration()
	return Plan.shotAt(T.Shots) + T.Flight + T.Linger
end

-- Orb `index` circling a caster whose root is at `centre`, `elapsed` into the
-- cast: it rises out of the pool at their feet, then circles and bobs.
function Plan.orbit(centre, index, elapsed)
	local rise = math.clamp((elapsed - 0.15) / 0.4, 0, 1)
	rise = rise * rise * (3 - 2 * rise)
	local angle = (index - 1) / T.Shots * math.pi * 2 + elapsed * T.OrbitSpeed
	local radius = T.OrbitRadius * (0.5 + 0.5 * rise)
	local height = -3 + (T.OrbitHeight + 3) * rise + 0.35 * math.sin(elapsed * 5 + index)
	return centre + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
end

-- A water bolt's arc from `from` to `to`, `t` from 0 to 1.
function Plan.arc(from, to, t)
	local control = (from + to) / 2 + Vector3.new(0, 3 + (to - from).Magnitude * 0.22, 0)
	return from:Lerp(control, t):Lerp(control:Lerp(to, t), t)
end

return Plan
