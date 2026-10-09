--[[
	Eclipse (server)

	What actually happens when an Eclipse goes off.

	The caster gathers a black star at their chest for half a second and then
	drops it. Everything inside EclipsePlan.Radius takes damage on a linear
	falloff, hardest at the caster's feet.

	Like every ability here this module is the authority and nothing else. It
	makes no parts, no particles and no sounds - it broadcasts one CFrame, and
	each client near enough to see it draws the whole thing for itself from
	EclipsePlan.

	WHY IT IS CENTRED ON THE CASTER AND TAKES NO TARGET

	Because Sacred Rain already takes one. The two abilities are on the same
	weapon, and an ability is only worth adding if pressing it is a different
	decision: Sacred Rain is "that place, in a moment", Eclipse is "everything
	around me, now". Making this one aimable would collapse the two into the
	same button with different particles.

	WHERE IT IS CENTRED IS FIXED AT THE CAST

	`context.origin` is the caster's root at the moment the server accepted the
	request, and the blast resolves there half a second later even if they have
	run off. That is deliberate and it matches the wind-up the victims saw: the
	telegraph is the orb hanging in the air at a place, so the damage has to
	happen at that place.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EclipsePlan = require(Shared:WaitForChild("Abilities"):WaitForChild("EclipsePlan"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))

local Tuning = EclipsePlan.Tuning

local Eclipse = {}

function Eclipse.duration(): number
	return EclipsePlan.duration()
end

--[[
	Applies the blast.

	Two queries, for the same reason Sacred Rain uses two: EnemyService knows
	exactly where every enemy is and does not require them to be query-able or
	to carry a Humanoid, while players are a known shape that a spatial query
	handles well.
]]
local function resolve(context)
	local centre = context.origin.Position
	local struck = {}
	local hits = 0

	EnemyService.forEachNear(centre, Tuning.Radius, function(model, position)
		if struck[model] then
			return
		end
		struck[model] = true

		local damage = EclipsePlan.damageAt((position - centre).Magnitude)
		if damage > 0 then
			context.damage(model, damage)
			hits += 1
		end
	end)

	--[[
		Players, by sphere query.

		The caster and the terrain are excluded before the query rather than
		filtered after it: MaxParts caps what the engine RETURNS, and a 26-stud
		sphere in a world made of blocks is mostly blocks, so unfiltered terrain
		could use up the whole cap before the engine ever reached a character.
	]]
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.MaxParts = Tuning.MaxParts

	local excluded = { context.character }

	local terrainRoot = workspace:FindFirstChild("GeneratedTerrain")
	if terrainRoot then
		table.insert(excluded, terrainRoot)
	end

	params.FilterDescendantsInstances = excluded

	for _, part in ipairs(workspace:GetPartBoundsInRadius(centre, Tuning.Radius, params)) do
		local model = part.Parent
		local victim = model and Players:GetPlayerFromCharacter(model)

		if victim and model ~= context.character and not struck[model] then
			struck[model] = true

			--[[
				Measured from the root, not from the part the query happened to
				return. A character is fifteen parts spread over five studs, and
				taking the distance to whichever one the engine listed first
				would make the damage depend on which way the victim was facing.
			]]
			local root = (model :: Model):FindFirstChild("HumanoidRootPart")
			local position = if root and root:IsA("BasePart") then root.Position else part.Position

			local damage = EclipsePlan.damageAt((position - centre).Magnitude)
			if damage > 0 then
				-- Raw damage in; CombatService decides what it costs after armour.
				CombatService.applyDamage(victim, damage, context.abilityName)
				hits += 1
			end
		end
	end

	Profiler.sample("Ability.eclipse.hits", hits, "targets")
end

function Eclipse.cast(context)
	--[[
		The whole packet. Where the caster was standing is all a client needs:
		the timings and the radius are in EclipsePlan, which both sides have.
	]]
	context.broadcast({
		origin = context.origin,
	})

	context.scope:delay(EclipsePlan.impactAt(), function()
		resolve(context)
	end)

	return true
end

return Eclipse
