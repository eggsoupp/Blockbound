-- One clock and one volley for the Skyfall Volley server hits and every
-- observer. The caster draws and looses a signal arrow straight up; a jade
-- circle marks the target; a storm of light-arrows falls inside it, each
-- landing where the cast's seed says; then one great arrow pins the centre.
local Plan = {}

Plan.Tuning = {
	Draw = 0.32,
	Rise = 0.3,
	MarkAt = 0.5,
	RainStart = 0.95,
	RainTime = 1.35,
	Arrows = 26,
	Radius = 12,
	-- Each arrow drops this far in this long.
	DropHeight = 40,
	Fall = 0.16,
	ArrowRadius = 3.6,
	ArrowDamage = 8,
	FinaleAt = 2.55,
	FinaleFall = 0.14,
	FinaleRadius = 9,
	FinaleDamage = 42,
	FinalePush = 30,
	FinaleLift = 26,
	Aftermath = 1.3,
}

local T = Plan.Tuning

function Plan.duration()
	return T.FinaleAt + T.Aftermath + 0.3
end

--[[
	Where and when every arrow lands, from the cast's seed alone, so the
	server's hits and every client's arrows agree without sending positions.
	Spread evenly over the rain with a little jitter, uniform over the disc.
]]
function Plan.volley(seed)
	local random = Random.new(seed)
	local arrows = {}
	for i = 1, T.Arrows do
		local slot = (i - 0.5) / T.Arrows
		local at = T.RainStart + T.RainTime * math.clamp(slot + random:NextNumber(-0.4, 0.4) / T.Arrows, 0, 1)
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = T.Radius * math.sqrt(random:NextNumber(0.02, 1))
		table.insert(arrows, {
			at = at,
			lands = at + T.Fall,
			offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance),
		})
	end
	table.sort(arrows, function(a, b) return a.at < b.at end)
	return arrows
end

-- The ground under the aim point, else the aim point itself.
function Plan.landing(target, params)
	local hit = workspace:Raycast(target + Vector3.new(0, 8, 0), Vector3.new(0, -50, 0), params)
	if hit then return hit.Position, hit.Normal end
	return target, Vector3.yAxis
end

return Plan
