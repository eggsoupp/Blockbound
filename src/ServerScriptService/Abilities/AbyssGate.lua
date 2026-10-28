local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.AbyssPlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local AbyssGate = {}

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

function AbyssGate.duration()
	return Plan.duration()
end

-- Everyone within `radius` of the gate (across the ground and a pillar's
-- height above it), with the flat offset from the middle.
local function within(context, centre, radius, height, visit)
	EnemyService.forEachNear(centre, radius + height, function(model, position)
		local offset = position - centre
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude <= radius and offset.Y > -6 and offset.Y < height then
			visit(model, nil, flat)
		end
	end)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		local offset = root and root.Position - centre
		local flat = offset and Vector3.new(offset.X, 0, offset.Z)
		if flat and flat.Magnitude <= radius and offset.Y > -6 and offset.Y < height then
			visit(nil, victim, flat, root)
		end
	end
end

local function towards(flat)
	return if flat.Magnitude > 0.1 then -flat.Unit else Vector3.xAxis
end

function AbyssGate.cast(context)
	local centre, normal = Plan.ground(context.target, params(context.character))
	context.broadcast({
		origin = context.origin,
		centre = centre,
		normal = normal,
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})
	local scope = context.scope
	-- The sigil drags everything near it inwards.
	for _, at in ipairs(T.PullAt) do
		scope:delay(at, function()
			within(context, centre, T.PullRadius, 10, function(model, victim, flat, root)
				local speed = Plan.pullSpeed(flat.Magnitude)
				if model then
					EnemyService.knockback(model, towards(flat), speed, T.PullLift)
				else
					root:ApplyImpulse((towards(flat) * speed * 0.5 + Vector3.new(0, T.PullLift, 0)) * root.AssemblyMass)
				end
			end)
		end)
	end
	-- The pillar burns and juggles whatever is in it.
	for i = 0, math.floor(T.Erupt / T.Tick) - 1 do
		scope:delay(T.Open + i * T.Tick, function()
			within(context, centre, T.PillarRadius, T.PillarHeight, function(model, victim, flat, root)
				if model then
					context.damage(model, T.TickDamage)
					EnemyService.knockback(model, towards(flat), math.min(flat.Magnitude * 3, 10), T.TickLift)
				else
					CombatService.applyDamage(victim, T.TickDamage, context.abilityName)
					root:ApplyImpulse(Vector3.new(0, T.TickLift, 0) * root.AssemblyMass)
				end
			end)
		end)
	end
	-- The gate implodes and throws the survivors out.
	scope:delay(Plan.collapseAt(), function()
		within(context, centre, T.CollapseRadius, T.PillarHeight, function(model, victim, flat, root)
			local away = -towards(flat)
			if model then
				context.damage(model, T.CollapseDamage)
				EnemyService.knockback(model, away, T.CollapsePush, T.CollapseLift)
			else
				CombatService.applyDamage(victim, T.CollapseDamage, context.abilityName)
				root:ApplyImpulse((away * T.CollapsePush + Vector3.new(0, T.CollapseLift, 0)) * root.AssemblyMass)
			end
		end)
	end)
	return true
end

return AbyssGate
