local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Plan = require(RS.Shared.Abilities.SkyfallPlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local SkyfallVolley = {}

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

function SkyfallVolley.duration()
	return Plan.duration()
end

-- Within `radius` across the ground and a body's height above or below it.
local function near(point, position, radius)
	local offset = position - point
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= 8
end

local function strike(context, point, radius, amount, push, lift)
	EnemyService.forEachNear(point, radius + 6, function(model, position)
		if not near(point, position, radius) then return end
		context.damage(model, amount)
		if push > 0 then
			local away = Vector3.new(position.X - point.X, 0, position.Z - point.Z)
			EnemyService.knockback(model, if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis, push, lift)
		end
	end)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		if root and near(point, root.Position, radius) then
			CombatService.applyDamage(victim, amount, context.abilityName)
			if push > 0 then
				local away = Vector3.new(root.Position.X - point.X, 0, root.Position.Z - point.Z)
				away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
				root:ApplyImpulse((away * push + Vector3.new(0, lift, 0)) * root.AssemblyMass)
			end
		end
	end
end

function SkyfallVolley.cast(context)
	local centre, normal = Plan.landing(context.target, params(context.character))
	local startedAt = workspace:GetServerTimeNow()
	context.broadcast({
		origin = context.origin,
		centre = centre,
		normal = normal,
		startedAt = startedAt,
		seed = context.seed,
	})
	local arrows = Plan.volley(context.seed)
	local nextArrow = 1
	local connection
	connection = context.scope:add(RunService.Heartbeat:Connect(function()
		local elapsed = workspace:GetServerTimeNow() - startedAt
		while nextArrow <= #arrows and arrows[nextArrow].lands <= elapsed do
			strike(context, centre + arrows[nextArrow].offset, T.ArrowRadius, T.ArrowDamage, 0, 0)
			nextArrow += 1
		end
		if nextArrow > #arrows then connection:Disconnect() end
	end))
	context.scope:delay(T.FinaleAt + T.FinaleFall, function()
		strike(context, centre, T.FinaleRadius, T.FinaleDamage, T.FinalePush, T.FinaleLift)
	end)
	return true
end

return SkyfallVolley
