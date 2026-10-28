local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.SerpentPlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local SerpentFlare = {}

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

function SerpentFlare.duration()
	return Plan.duration()
end

local function ground(point, rayParams)
	local hit = workspace:Raycast(point + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), rayParams)
	return if hit then hit.Position else point
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

-- The closing ring drags the enemies inside it towards the middle.
local function pull(centre)
	EnemyService.forEachNear(centre, T.RingRadius + 6, function(model, position)
		local offset = position - centre
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude > T.RingRadius + 2 or flat.Magnitude < 0.5 or math.abs(offset.Y) > 8 then return end
		EnemyService.knockback(model, -flat.Unit, Plan.pullSpeed(flat.Magnitude), T.PullLift)
	end)
end

function SerpentFlare.cast(context)
	local rayParams = params(context.character)
	local centre = ground(context.target, rayParams)
	local serpents = Plan.serpents(context.seed, context.origin)
	local landings = {}
	for i, serpent in ipairs(serpents) do
		landings[i] = ground(Plan.ringPoint(centre, serpent), rayParams)
	end
	context.broadcast({
		origin = context.origin,
		centre = centre,
		landings = landings,
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})
	local scope = context.scope
	for i, serpent in ipairs(serpents) do
		scope:delay(Plan.landsAt(serpent), function()
			blast(context, landings[i], T.StrikeRadius, T.StrikeDamage, T.StrikePush, T.StrikeLift)
		end)
	end
	scope:delay(Plan.igniteAt(serpents) + 0.1, function()
		pull(centre)
	end)
	scope:delay(Plan.eruptAt(serpents), function()
		blast(context, centre, T.EruptRadius, T.EruptDamage, T.EruptPush, T.EruptLift)
	end)
	return true
end

return SerpentFlare
