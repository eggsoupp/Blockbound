local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.BlossomPlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local BlossomRoad = {}

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

function BlossomRoad.duration()
	return Plan.duration()
end

local function standing(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid.HipHeight + root.Size.Y * 0.5
end

local function burst(context, centre, radius, amount, lift, push)
	EnemyService.forEachNear(centre, radius + 3, function(model, position)
		local offset = position - centre
		if Vector3.new(offset.X, 0, offset.Z).Magnitude > radius or math.abs(offset.Y) > 9 then return end
		context.damage(model, amount)
		local away = Vector3.new(offset.X, 0, offset.Z)
		EnemyService.knockback(model, if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis, push, lift)
	end)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		local offset = root and root.Position - centre
		if offset and Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= 9 then
			CombatService.applyDamage(victim, amount, context.abilityName)
			root:ApplyImpulse(Vector3.new(0, lift, 0) * root.AssemblyMass)
		end
	end
end

-- The lane is laid out here, so a cast straight into a wall is refused before
-- it costs anything.
function BlossomRoad.validate(context)
	local origin = context.origin
	local direction = Plan.flat(context.target - origin.Position)
	local feet = origin.Position - Vector3.new(0, standing(context.character), 0)
	local points = Plan.lane(feet, direction, params(context.character))
	if #points == 0 then
		return false, "Blossom Road needs open ground ahead."
	end
	return true, nil, {feet = feet, direction = direction, points = points}
end

function BlossomRoad.cast(context)
	local feet, direction, points = context.prepared.feet, context.prepared.direction, context.prepared.points
	local startedAt = workspace:GetServerTimeNow()
	context.broadcast({
		feet = feet,
		direction = direction,
		points = points,
		startedAt = startedAt,
		seed = context.seed,
	})
	local scope = context.scope
	for index, point in ipairs(points) do
		scope:delay(Plan.bloomAt(index), function()
			burst(context, point, T.BloomRadius, T.BloomDamage, T.BloomLift, 4)
		end)
	end
	local finaleAt = Plan.finaleAt(#points)
	scope:delay(finaleAt, function()
		burst(context, points[#points], T.FinaleRadius, T.FinaleDamage, T.FinaleLift, T.FinalePush)
	end)
	-- The road: every pulse mends players standing on it and stings enemies.
	local pulses = math.floor(T.Road / T.Pulse)
	for pulse = 1, pulses do
		scope:delay(finaleAt + pulse * T.Pulse, function()
			for _, player in ipairs(Players:GetPlayers()) do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and Plan.distanceToLane(points, root.Position) <= T.RoadWidth then
					CombatService.heal(player, T.Heal)
				end
			end
			local seen = {}
			for _, point in ipairs(points) do
				EnemyService.forEachNear(point, T.Spacing + T.RoadWidth, function(model, position)
					if seen[model] or Plan.distanceToLane(points, position) > T.RoadWidth then return end
					seen[model] = true
					context.damage(model, T.Sting)
				end)
			end
		end)
	end
	return true
end

return BlossomRoad
