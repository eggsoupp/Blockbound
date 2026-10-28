local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.DelugePlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local Deluge = {}

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

function Deluge.duration()
	return Plan.duration()
end

local function away(offset, fallback)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	return if flat.Magnitude > 0.1 then flat.Unit else fallback
end

-- Everything within `radius` of `centre`, players and enemies alike.
local function splash(context, centre, radius, amount, push, lift, fallback)
	EnemyService.forEachNear(centre, radius, function(model, position)
		context.damage(model, amount)
		EnemyService.knockback(model, away(position - centre, fallback), push, lift)
	end)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - centre).Magnitude <= radius then
			CombatService.applyDamage(victim, amount, context.abilityName)
			root:ApplyImpulse((away(root.Position - centre, fallback) * push + Vector3.new(0, lift, 0)) * root.AssemblyMass)
		end
	end
end

function Deluge.cast(context)
	local from = Plan.orbStart(context.origin)
	local landing, normal = Plan.landing(context.target, params(context.character))
	context.broadcast({
		from = from,
		landing = landing,
		normal = normal,
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})
	local fallback = context.origin.LookVector
	context.scope:delay(Plan.hitAt(), function()
		splash(context, landing, T.Radius, T.Damage, T.Push, T.Lift, fallback)
	end)
	-- One surge, timed to the middle ring, reaching as far as the last.
	context.scope:delay(Plan.surgeAt(2), function()
		splash(context, landing, T.SurgeReach, T.SurgeDamage, T.SurgePush, T.SurgeLift, fallback)
	end)
	return true
end

return Deluge
