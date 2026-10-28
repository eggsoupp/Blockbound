local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.CometPlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local AzureComet = {}

local T = Plan.Tuning

local function params(character)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {character}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclude, player.Character) end
	end
	local enemies = workspace:FindFirstChild(EnemyConfig.WorldFolder)
	if enemies then table.insert(exclude, enemies) end
	p.FilterDescendantsInstances = exclude
	p.RespectCanCollide = true
	return p
end

function AzureComet.duration()
	return Plan.duration()
end

-- Everyone within `radius` of `point` (across the ground and a body's height),
-- thrown outwards.
local function blast(context, point, radius, amount, push, lift)
	EnemyService.forEachNear(point, radius + 4, function(model, position)
		local offset = position - point
		local away = Vector3.new(offset.X, 0, offset.Z)
		if away.Magnitude > radius or math.abs(offset.Y) > 8 then return end
		context.damage(model, amount)
		EnemyService.knockback(model, if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis, push, lift)
	end)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		local offset = root and root.Position - point
		local away = offset and Vector3.new(offset.X, 0, offset.Z)
		if away and away.Magnitude <= radius and math.abs(offset.Y) <= 8 then
			CombatService.applyDamage(victim, amount, context.abilityName)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
			root:ApplyImpulse((away * push + Vector3.new(0, lift, 0)) * root.AssemblyMass)
		end
	end
end

function AzureComet.cast(context)
	local sky = Plan.sky(context.origin)
	local impact, normal = Plan.impact(sky, context.target, params(context.character))
	context.broadcast({
		origin = context.origin,
		sky = sky,
		impact = impact,
		normal = normal,
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})
	local scope = context.scope
	scope:delay(Plan.impactAt(), function()
		blast(context, impact, T.ImpactRadius, T.ImpactDamage, T.ImpactPush, T.ImpactLift)
	end)
	for i = 1, T.Pulses do
		scope:delay(Plan.pulseAt(i), function()
			blast(context, impact, T.PulseRadius, T.PulseDamage, T.PulsePush, T.PulseLift)
		end)
	end
	return true
end

return AzureComet
