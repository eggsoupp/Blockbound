local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.HeliosPlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local HeliosLance = {}

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

function HeliosLance.duration()
	return Plan.duration()
end

-- Everyone within `radius` of `point` (across the ground and a body's height).
local function scorch(context, point, radius, amount, push, lift)
	EnemyService.forEachNear(point, radius + 4, function(model, position)
		local offset = position - point
		if Vector3.new(offset.X, 0, offset.Z).Magnitude > radius or math.abs(offset.Y) > 8 then return end
		context.damage(model, amount)
		if push > 0 then
			local away = Vector3.new(offset.X, 0, offset.Z)
			EnemyService.knockback(model, if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis, push, lift)
		end
	end)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		local offset = root and root.Position - point
		if offset and Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= 8 then
			CombatService.applyDamage(victim, amount, context.abilityName)
			if push > 0 then
				local away = Vector3.new(offset.X, 0, offset.Z)
				away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
				root:ApplyImpulse((away * push + Vector3.new(0, lift, 0)) * root.AssemblyMass)
			end
		end
	end
end

function HeliosLance.cast(context)
	local origin = context.origin
	local sun = Plan.sun(origin)
	local from, to = Plan.ends(origin, context.target)
	local rayParams = params(context.character)
	context.broadcast({
		origin = origin,
		sun = sun,
		from = from,
		to = to,
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})
	local scope = context.scope
	-- The sweep: a tick of fire wherever the beam is landing.
	local scar = {}
	local ticks = math.floor(T.Sweep / T.Tick)
	for i = 0, ticks do
		local at = T.Charge + i * T.Tick
		scope:delay(at, function()
			local point = Plan.landing(sun, from:Lerp(to, Plan.progress(at)), rayParams)
			table.insert(scar, point)
			scorch(context, point, T.BeamRadius, T.BeamDamage, 0, 0)
		end)
	end
	scope:delay(Plan.blastAt(), function()
		local point = Plan.landing(sun, to, rayParams)
		scorch(context, point, T.BlastRadius, T.BlastDamage, T.BlastPush, T.BlastLift)
	end)
	-- The scar burns whatever stands on it.
	for i = 1, math.floor(T.Aftermath / T.BurnTick) do
		scope:delay(Plan.blastAt() + i * T.BurnTick, function()
			local burned = {}
			for _, point in ipairs(scar) do
				EnemyService.forEachNear(point, T.ScarWidth, function(model)
					if burned[model] then return end
					burned[model] = true
					context.damage(model, T.Burn)
				end)
			end
		end)
	end
	return true
end

return HeliosLance
