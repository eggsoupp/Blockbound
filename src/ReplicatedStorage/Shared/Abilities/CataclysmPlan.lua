-- One clock and trajectory for the server hit and every observer's meteor.
local Plan = {}

Plan.Tuning = {
	Windup = 0.8,
	FallTime = 2.1,
	SpawnHeight = 210,
	MeteorRadius = 13.75,
	BlockSize = 5,
	CraterRadius = 32,
	CraterDepth = 24,
	DamageRadius = 44,
	ImpactDamage = 260,
	Aftermath = 5.5,
}

function Plan.hitAt()
	return Plan.Tuning.Windup + Plan.Tuning.FallTime
end

function Plan.duration()
	return Plan.hitAt() + Plan.Tuning.Aftermath
end

function Plan.meteorPosition(ground, elapsed)
	local t = math.clamp((elapsed - Plan.Tuning.Windup) / Plan.Tuning.FallTime, 0, 1)
	-- An accelerating, nearly vertical fall. The centre ends half buried.
	local progress = 0.18 * t + 0.82 * t * t
	return ground + Vector3.new(32 * (1 - progress),
		Plan.Tuning.SpawnHeight * (1 - progress) + Plan.Tuning.MeteorRadius * 0.35, 0)
end

function Plan.damageAt(distance)
	if distance > Plan.Tuning.DamageRadius then return 0 end
	return Plan.Tuning.ImpactDamage * (1 - 0.7 * math.clamp(distance / Plan.Tuning.DamageRadius, 0, 1))
end

return Plan
