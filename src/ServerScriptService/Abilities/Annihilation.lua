local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Abilities.AnnihilationPlan)
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))

local Annihilation = {}

function Annihilation.duration(): number
	return Plan.duration()
end

local function strike(context, ground, amount)
	local tuning = Plan.Tuning
	local centre = ground + Vector3.new(0, (tuning.BeamHeight - 4) / 2, 0)
	local queryRadius = math.sqrt(((tuning.BeamHeight + 4) / 2)^2 + tuning.DamageRadius^2)
	local struck = {}
	EnemyService.forEachNear(centre, queryRadius, function(model, position)
		if struck[model] then return end
		struck[model] = true
		local offset = position - ground
		local multiplier = Plan.damageMultiplier(offset.X, offset.Y, offset.Z)
		if multiplier > 0 then context.damage(model, amount * multiplier) end
	end)
	-- Iterate players directly so dense terrain cannot consume a spatial query cap.
	for _, victim in ipairs(Players:GetPlayers()) do
		if victim == context.player then continue end
		local character = victim.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then continue end
		local offset = root.Position - ground
		local multiplier = Plan.damageMultiplier(offset.X, offset.Y, offset.Z)
		if multiplier > 0 then CombatService.applyDamage(victim, amount * multiplier, context.abilityName) end
	end
end

function Annihilation.cast(context): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { context.character }
	-- AbilityService validates and clamps the cursor target before it reaches us.
	local position = context.target
	local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -18, 0), params)
	local ground = if hit then hit.Position else position
	-- Damage and presentation use this same frozen, server-validated cursor point.
	context.broadcast({
		origin = CFrame.new(ground),
		startedAt = workspace:GetServerTimeNow(),
	})
	context.scope:delay(Plan.hitAt(), function()
		strike(context, ground, Plan.Tuning.ImpactDamage)
		local rewards={}
		local _,debris=TerrainManager:MineAbilityCrater(ground,
			function(item) return InventoryService.CanAddItem(context.player,item,1) end,
			function(item) rewards[item]=(rewards[item] or 0)+1 end,
			Plan.Tuning.BeamHeight, Plan.Tuning.ExcavationRadius)
		if debris and #debris>0 then context.broadcastDebris(debris,ground) end
		-- One inventory update per block type, after terrain and debris are delivered.
		for item,count in pairs(rewards) do
			local low,high=0,count
			while low<high do
				local mid=math.ceil((low+high)/2)
				if InventoryService.CanAddItem(context.player,item,mid) then low=mid else high=mid-1 end
			end
			if low>0 then InventoryService.AddItemByName(context.player,item,low) end
		end
	end)
	for tickIndex = 1, Plan.Tuning.TickCount do
		context.scope:delay(Plan.hitAt() + tickIndex * Plan.Tuning.TickInterval, function()
			strike(context, ground, Plan.Tuning.TickDamage)
		end)
	end
	return true
end

return Annihilation
