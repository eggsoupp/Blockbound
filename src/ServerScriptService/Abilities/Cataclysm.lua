local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.CataclysmPlan)
local TerrainManager = require(SSS.TerrainManager)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local GroundDrops = require(SSS.GroundDrops)
local Cataclysm = {}

function Cataclysm.duration()
	return Plan.duration()
end

-- Runs before mana/cooldown payment. Never trusts a client supplied ground height.
function Cataclysm.validate(context)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { context.character }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(ignore, player.Character) end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local head = context.character:FindFirstChild("Head")
	local eye = if head and head:IsA("BasePart") then head.Position else context.origin.Position
	local surface = TerrainManager:GetSurfaceY(eye.X, eye.Z)
	if not surface or eye.Y < surface - 0.25
		or workspace:Raycast(eye, Vector3.new(0, Plan.Tuning.SpawnHeight + 30, 0), params) then
		return false, "Cataclysm needs open sky. You cannot cast it underground or under cover."
	end
	local hit = workspace:Raycast(context.target + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), params)
	local terrain = workspace:FindFirstChild("GeneratedTerrain")
	if not hit or not terrain or not hit.Instance:IsDescendantOf(terrain) or hit.Normal.Y < 0.5 then
		return false, "Aim Cataclysm at exposed terrain."
	end
	local ground = hit.Position
	if (ground - context.origin.Position).Magnitude > context.definition.castRange + 1 then
		return false, "That impact point is out of range."
	end
	local top = TerrainManager:GetSurfaceY(ground.X, ground.Z)
	if not top or ground.Y < top - 0.25 then
		return false, "The meteor cannot reach an underground target."
	end
	local destination = Plan.meteorPosition(ground, Plan.hitAt())
	local start = Plan.meteorPosition(ground, 0)
	-- Check the actual descent corridor, including the meteor's width.
	local clearance = Plan.Tuning.MeteorRadius * 0.82
	for _, offset in ipairs({Vector3.zero, Vector3.new(clearance,0,0), Vector3.new(-clearance,0,0), Vector3.new(0,0,clearance), Vector3.new(0,0,-clearance)}) do
		local base = destination + offset + Vector3.new(0, Plan.Tuning.MeteorRadius, 0)
		if workspace:Raycast(base, start - destination, params) then
			return false, "The meteor's descent is obstructed. Choose an open impact point."
		end
	end
	return true, nil, { ground = ground }
end

function Cataclysm.cast(context)
	local ground = context.prepared.ground
	local startedAt = workspace:GetServerTimeNow()
	context.broadcast({ origin = CFrame.new(ground), startedAt = startedAt, seed = context.seed })
	context.scope:delay(Plan.hitAt(), function()
		local seen = {}
		EnemyService.forEachNear(ground, Plan.Tuning.DamageRadius, function(model, position)
			if seen[model] then return end
			seen[model] = true
			local damage = Plan.damageAt((position - ground).Magnitude)
			if damage > 0 then context.damage(model, damage) end
		end)
		for _, victim in ipairs(Players:GetPlayers()) do
			if victim == context.player then continue end
			local root = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local damage = Plan.damageAt((root.Position - ground).Magnitude)
				if damage > 0 then CombatService.applyDamage(victim, damage, context.abilityName) end
			end
		end
		local removed, _, rewards = TerrainManager:MineMeteorCrater(ground, Plan.Tuning.CraterRadius, Plan.Tuning.CraterDepth)
		-- Cosmetic fragments are authored rock particles in CataclysmVFX.
		for item, count in pairs(rewards) do GroundDrops.spawn(item, count, ground, context.player) end
		-- Useful to Studio diagnostics without replicating the excavation plan.
		context.root:SetAttribute("LastCataclysmBlocks", removed)
	end)
	return true
end

return Cataclysm
