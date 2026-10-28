local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.SumiPlan)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local SumiWhirl = {}

local T = Plan.Tuning

function SumiWhirl.duration()
	return Plan.duration()
end

local function outward(offset, fallback)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	return if flat.Magnitude > 0.1 then flat.Unit else fallback
end

function SumiWhirl.cast(context)
	local origin = context.origin
	context.broadcast({
		origin = origin,
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})
	-- The ring is painted on the world where the cast began, and cuts there.
	context.scope:delay(T.CutAt, function()
		local centre = origin.Position
		local fallback = origin.LookVector
		EnemyService.forEachNear(centre, T.Reach, function(model, position)
			if math.abs(position.Y - centre.Y) > 8 then return end
			context.damage(model, T.Damage)
			EnemyService.knockback(model, outward(position - centre, fallback), T.Push, T.Lift)
		end)
		for _, victim in ipairs(Players:GetPlayers()) do
			local victimRoot = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
			local offset = victimRoot and victimRoot.Position - centre
			if offset and offset.Magnitude <= T.Reach and math.abs(offset.Y) <= 8 then
				CombatService.applyDamage(victim, T.Damage, context.abilityName)
				victimRoot:ApplyImpulse((outward(offset, fallback) * T.Push + Vector3.new(0, T.Lift, 0)) * victimRoot.AssemblyMass)
			end
		end
	end)
	return true
end

return SumiWhirl
