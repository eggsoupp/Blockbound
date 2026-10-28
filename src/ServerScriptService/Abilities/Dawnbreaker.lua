local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Plan = require(RS.Shared.Abilities.DawnbreakerPlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local Dawnbreaker = {}

local T = Plan.Tuning

-- The crescent cuts through fighters, so only the world stops it.
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

function Dawnbreaker.duration()
	return Plan.duration()
end

local function hurtPlayer(context, victim, amount, push)
	CombatService.applyDamage(victim, amount, context.abilityName)
	local root = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then root:ApplyImpulse(push * root.AssemblyMass) end
end

function Dawnbreaker.cast(context)
	local from = Plan.launchPoint(context.origin)
	local direction = Plan.direction(from, context.target, context.origin.LookVector)
	local finish, normal, distance = Plan.trace(from, direction, params(context.character))
	local startedAt = workspace:GetServerTimeNow()
	context.broadcast({
		origin = CFrame.lookAt(from, from + direction),
		finish = finish,
		normal = normal,
		distance = distance,
		startedAt = startedAt,
		seed = context.seed,
	})

	-- The flight: whatever the crescent's middle passed since last frame.
	local cut, travelled = {}, 0
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local shove = (if flat.Magnitude > 0.05 then flat.Unit else Vector3.zero) * T.PiercePush + Vector3.new(0, 8, 0)
	local connection
	connection = context.scope:add(RunService.Heartbeat:Connect(function()
		local reach = Plan.reach(workspace:GetServerTimeNow() - startedAt, distance)
		if reach <= travelled then return end
		local near, far = travelled, reach
		travelled = reach
		local mid = from + direction * ((near + far) / 2)
		EnemyService.forEachNear(mid, (far - near) / 2 + T.HitHalfWidth + 2, function(model, position)
			if cut[model] or not Plan.swept(from, direction, near, far, position) then return end
			cut[model] = true
			context.damage(model, T.PierceDamage)
			EnemyService.knockback(model, direction, T.PiercePush, 8)
		end)
		for _, victim in ipairs(Players:GetPlayers()) do
			local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
			if root and not cut[victim] and Plan.swept(from, direction, near, far, root.Position) then
				cut[victim] = true
				hurtPlayer(context, victim, T.PierceDamage, shove)
			end
		end
		if reach >= distance then connection:Disconnect() end
	end))

	-- The burst: full damage at the centre, half at the edge.
	context.scope:delay(Plan.hitAt(distance), function()
		EnemyService.forEachNear(finish, T.BurstRadius, function(model, position)
			local offset = position - finish
			local falloff = 1 - 0.5 * math.clamp(offset.Magnitude / T.BurstRadius, 0, 1)
			context.damage(model, T.BurstDamage * falloff)
			local away = Vector3.new(offset.X, 0, offset.Z)
			EnemyService.knockback(model, if away.Magnitude > 0.1 then away.Unit else direction, T.BurstPush, T.BurstLift)
		end)
		for _, victim in ipairs(Players:GetPlayers()) do
			local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
			local offset = root and root.Position - finish
			if offset and offset.Magnitude <= T.BurstRadius then
				local away = Vector3.new(offset.X, 0, offset.Z)
				away = if away.Magnitude > 0.1 then away.Unit else direction
				local falloff = 1 - 0.5 * offset.Magnitude / T.BurstRadius
				hurtPlayer(context, victim, T.BurstDamage * falloff, away * T.BurstPush + Vector3.new(0, T.BurstLift, 0))
			end
		end
	end)
	return true
end

return Dawnbreaker
