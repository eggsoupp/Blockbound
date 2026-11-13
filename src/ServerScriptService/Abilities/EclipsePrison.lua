--[[
	Eclipse Prison (Celestial). Timing and the cage's shape are EclipsePlan's;
	the cage itself, the swords and the flare are drawn by EclipseVFX.

	The server owns three things:
	  - where the cage stands: the aim, pulled onto an enemy only when one is
	    within Tuning.Snap of it, so a near miss still lands
	  - who is held: every enemy inside the footprint when the blocks start to
	    rise stops where it is until the flare (a boss takes the damage but
	    cannot be held - EnemyService.hold refuses anything that drives itself)
	  - the hits: each sword hits everyone inside for a little, the flare for a
	    lot, and throws the survivors out of the broken cage
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.EclipsePlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local EclipsePrison = {}

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

function EclipsePrison.duration()
	return Plan.duration()
end

-- The aim, or the nearest enemy within Snap of it (measured across the ground).
local function snapped(target)
	local best, bestDistance = nil, T.Snap
	EnemyService.forEachNear(target, T.Snap + 8, function(_, position)
		local flat = Vector3.new(position.X - target.X, 0, position.Z - target.Z).Magnitude
		if flat <= bestDistance and math.abs(position.Y - target.Y) <= 10 then
			best, bestDistance = position, flat
		end
	end)
	if best then
		return Vector3.new(best.X, target.Y, best.Z)
	end
	return target
end

-- Every enemy whose body is inside the cage.
local function eachInside(frame, visit)
	local reach = Plan.size() + Plan.height()
	EnemyService.forEachNear(frame.Position + Vector3.yAxis * Plan.height() * 0.5, reach, function(model, position)
		if Plan.inside(frame, position) then visit(model, position) end
	end)
end

-- Other players standing in the cage are hurt like everyone else's abilities
-- hurt them; they are never held.
local function eachPlayerInside(context, frame, visit)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		if root and Plan.inside(frame, root.Position) then visit(victim, root) end
	end
end

function EclipsePrison.cast(context)
	local origin = context.origin
	local aim = snapped(context.target)
	local centre = Plan.ground(aim, params(context.character))
	local frame = Plan.frame(centre, origin.Position)

	context.broadcast({
		origin = origin,
		centre = centre,
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})

	local scope = context.scope
	-- One holder per cast: EnemyService refuses a second grip on the same body.
	local holder = {}
	local grips = {}
	local function releaseAll()
		for _, grip in ipairs(grips) do grip:release() end
		table.clear(grips)
	end
	-- A cancelled cast (death, reset, leaving) lets go too.
	scope:add(releaseAll)

	scope:delay(Plan.buildAt(), function()
		eachInside(frame, function(model)
			local grip = EnemyService.hold(model, holder)
			if grip then table.insert(grips, grip) end
		end)
	end)

	for i = 1, T.Swords do
		scope:delay(Plan.swordAt(i), function()
			eachInside(frame, function(model)
				context.damage(model, T.SwordDamage)
			end)
			eachPlayerInside(context, frame, function(victim)
				CombatService.applyDamage(victim, T.SwordDamage, context.abilityName)
			end)
		end)
	end

	scope:delay(Plan.flareAt(), function()
		releaseAll()
		eachInside(frame, function(model, position)
			context.damage(model, T.FlareDamage)
			local away = Vector3.new(position.X - centre.X, 0, position.Z - centre.Z)
			EnemyService.knockback(model, if away.Magnitude > 0.1 then away.Unit else frame.LookVector, T.FlarePush, T.FlareLift)
		end)
		eachPlayerInside(context, frame, function(victim, root)
			CombatService.applyDamage(victim, T.FlareDamage, context.abilityName)
			local away = Vector3.new(root.Position.X - centre.X, 0, root.Position.Z - centre.Z)
			away = if away.Magnitude > 0.1 then away.Unit else frame.LookVector
			root:ApplyImpulse((away * T.FlarePush + Vector3.new(0, T.FlareLift, 0)) * root.AssemblyMass)
		end)
	end)
	return true
end

return EclipsePrison
