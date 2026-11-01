local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.ThunderPlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local Thunderhead = {}

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

function Thunderhead.duration()
	return Plan.duration()
end

-- Everyone within `radius` of `point` (across the ground and a body's height).
local function strike(context, point, radius, amount, push, lift)
	EnemyService.forEachNear(point, radius + 4, function(model, position)
		local offset = position - point
		local away = Vector3.new(offset.X, 0, offset.Z)
		if away.Magnitude > radius or math.abs(offset.Y) > 10 then return end
		context.damage(model, amount)
		if push then
			EnemyService.knockback(model, if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis, push, lift)
		end
	end)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		local offset = root and root.Position - point
		local away = offset and Vector3.new(offset.X, 0, offset.Z)
		if away and away.Magnitude <= radius and math.abs(offset.Y) <= 10 then
			CombatService.applyDamage(victim, amount, context.abilityName)
			if push then
				away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
				root:ApplyImpulse((away * push + Vector3.new(0, lift, 0)) * root.AssemblyMass)
			end
		end
	end
end

function Thunderhead.cast(context)
	local p = params(context.character)
	local centre, normal = Plan.ground(context.target, p)
	local points = Plan.boltPoints(centre, context.seed, p)
	context.broadcast({
		origin = context.origin,
		centre = centre,
		normal = normal,
		points = points,
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})
	local scope = context.scope
	for i, point in ipairs(points) do
		scope:delay(Plan.boltAt(i), function()
			strike(context, point, T.BoltRadius, T.BoltDamage)
		end)
	end
	scope:delay(Plan.finalAt(), function()
		strike(context, centre, T.FinalRadius, T.FinalDamage, T.FinalPush, T.FinalLift)
	end)
	return true
end

return Thunderhead
