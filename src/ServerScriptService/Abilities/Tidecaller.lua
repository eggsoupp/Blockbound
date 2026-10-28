local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.TidePlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local Tidecaller = {}

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

function Tidecaller.duration()
	return Plan.duration()
end

local function ground(point, rayParams)
	local hit = workspace:Raycast(point + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), rayParams)
	return if hit then hit.Position else point
end

-- The enemy near the caster that has been hit least, nearest first.
local function pick(centre, hits)
	local best, bestPoint, bestScore
	EnemyService.forEachNear(centre, T.Range, function(model, position)
		local score = (hits[model] or 0) * 1000 + (position - centre).Magnitude
		if not bestScore or score < bestScore then
			best, bestPoint, bestScore = model, position, score
		end
	end)
	return best, bestPoint
end

-- Everyone within the splash (across the ground and a body's height), thrown
-- outwards.
local function splash(context, point)
	EnemyService.forEachNear(point, T.SplashRadius + 4, function(model, position)
		local offset = position - point
		local away = Vector3.new(offset.X, 0, offset.Z)
		if away.Magnitude > T.SplashRadius or math.abs(offset.Y) > 6 then return end
		context.damage(model, T.SplashDamage)
		EnemyService.knockback(model, if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis, T.SplashPush, T.SplashLift)
	end)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		local offset = root and root.Position - point
		local away = offset and Vector3.new(offset.X, 0, offset.Z)
		if away and away.Magnitude <= T.SplashRadius and math.abs(offset.Y) <= 6 then
			CombatService.applyDamage(victim, T.SplashDamage, context.abilityName)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
			root:ApplyImpulse((away * T.SplashPush + Vector3.new(0, T.SplashLift, 0)) * root.AssemblyMass)
		end
	end
end

function Tidecaller.cast(context)
	local id = HttpService:GenerateGUID(false)
	local rayParams = params(context.character)
	context.broadcast({
		phase = "summon",
		id = id,
		origin = context.origin,
		pool = ground(context.origin.Position - Vector3.new(0, 2.5, 0), rayParams),
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})
	local scope = context.scope
	local hits = {}
	local random = Random.new(context.seed)
	for i = 1, T.Shots do
		scope:delay(Plan.shotAt(i), function()
			local root = context.root
			if not root.Parent or context.humanoid.Health <= 0 then return end
			local target, point = pick(root.Position, hits)
			if target then
				hits[target] = (hits[target] or 0) + 1
			else
				-- Nobody to chase: the bolt rains down somewhere round the caster.
				local angle = random:NextNumber(0, math.pi * 2)
				point = root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(6, 13)
			end
			local landing = ground(point, rayParams)
			context.broadcast({
				phase = "shot",
				id = id,
				index = i,
				from = Plan.orbit(root.Position, i, Plan.shotAt(i)),
				landing = landing,
				startedAt = workspace:GetServerTimeNow(),
				seed = context.seed + i,
			})
			scope:delay(T.Flight, function()
				splash(context, landing)
			end)
		end)
	end
	return true
end

return Tidecaller
