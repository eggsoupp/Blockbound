--[[
	Penumbra (Celestial, F). Timing and reach are PenumbraPlan's; the dome, the
	crescents, the shroud and the caster's pose are drawn by PenumbraVFX.

	The server owns:
	  - where it happens: round the caster where they stood when they cast,
	    and whether that was in the air (the character's Flying attribute,
	    which WingService keeps)
	  - the caster's cover: they cannot be hurt while they are gone
	  - the hits: the burst hits everything in the dome hard and throws it
	    out; the shroud nicks whatever is still inside a few times
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.PenumbraPlan)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local Penumbra = {}

local T = Plan.Tuning

function Penumbra.duration()
	return Plan.duration()
end

-- Every enemy in the burst.
local function eachInside(centre, air, visit)
	EnemyService.forEachNear(centre, T.Radius + T.Reach, function(model, position)
		if Plan.inside(centre, position, air) then visit(model, position) end
	end)
end

-- Other players in it are hurt like everyone else's abilities hurt them.
local function eachPlayerInside(context, centre, air, visit)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		if root and Plan.inside(centre, root.Position, air) then visit(victim, root) end
	end
end

function Penumbra.cast(context)
	local origin = context.origin
	local centre = origin.Position
	local air = context.character:GetAttribute("Flying") == true
	local fallback = origin.LookVector

	context.broadcast({
		origin = origin,
		air = air,
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})

	local scope = context.scope
	scope:delay(Plan.burstAt(), function()
		-- Gone into the flash: nothing lands on them until they step back out.
		CombatService.shield(context.player, T.Vanish + 0.1)
		eachInside(centre, air, function(model, position)
			context.damage(model, T.BurstDamage)
			EnemyService.knockback(model, Plan.away(centre, position, false, fallback), T.BurstPush, T.BurstLift)
		end)
		eachPlayerInside(context, centre, air, function(victim, root)
			CombatService.applyDamage(victim, T.BurstDamage, context.abilityName)
			local away = Plan.away(centre, root.Position, air, fallback)
			root:ApplyImpulse((away * T.BurstPush + Vector3.new(0, T.BurstLift, 0)) * root.AssemblyMass)
		end)
	end)

	for _, at in ipairs(T.Ticks) do
		scope:delay(Plan.burstAt() + at, function()
			eachInside(centre, air, function(model)
				context.damage(model, T.TickDamage)
			end)
			eachPlayerInside(context, centre, air, function(victim)
				CombatService.applyDamage(victim, T.TickDamage, context.abilityName)
			end)
		end)
	end
	return true
end

return Penumbra
