local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Plan = require(RS.Shared.Abilities.VoidRendPlan)
local Remotes = require(RS.Shared.Net.Remotes)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local VoidRend = {}

local T = Plan.Tuning
local PATH = Vector3.new(2.4, 3, 2.4)

-- The second press. It only says which way the caster faces; where that dive
-- lands, and what it hits, is worked out here.
local StrikeRemote = Remotes.ensure("VoidRendStrike", "RemoteEvent")

-- player -> the strike waiting on their second press
local pending = setmetatable({}, { __mode = "k" })

StrikeRemote.OnServerEvent:Connect(function(player, direction)
	local strike = pending[player]
	if strike and typeof(direction) == "Vector3" and direction.X == direction.X and direction.Z == direction.Z then
		strike(direction)
	end
end)

local function params(character)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {character}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclude, player.Character) end
	end
	p.FilterDescendantsInstances = exclude
	p.RespectCanCollide = true
	return p
end

local function standingHeight(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid.HipHeight + root.Size.Y * 0.5
end

function VoidRend.duration()
	return Plan.duration()
end

-- Needs headroom for the leap. A second key press while hovering lands here
-- too and is turned away quietly; the strike remote handles that press.
function VoidRend.validate(context)
	if pending[context.player] then
		return false
	end
	local p = params(context.character)
	local origin = context.origin.Position
	if workspace:Blockcast(CFrame.new(origin), PATH, Plan.apex(origin) - origin, p) then
		return false, "Void Rend needs open space above you."
	end
	local standing = standingHeight(context.character)
	local takeoff = workspace:Raycast(origin, Vector3.new(0, -(standing + 6), 0), p)
	return true, nil, {
		takeoff = if takeoff then takeoff.Position else origin - Vector3.new(0, standing, 0),
	}
end

local function rake(context, ground, direction)
	local seen = {}
	EnemyService.forEachNear(ground + direction * (T.ClawLength * 0.5), T.ClawLength, function(model, position)
		if seen[model] or not Plan.inside(ground, direction, position) then return end
		seen[model] = true
		context.damage(model, T.Damage)
		EnemyService.knockback(model, direction, T.Push, T.Lift)
	end)
	for _, victim in ipairs(Players:GetPlayers()) do
		if victim == context.player then continue end
		local victimRoot = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		if victimRoot and victimRoot:IsA("BasePart") and Plan.inside(ground, direction, victimRoot.Position) then
			CombatService.applyDamage(victim, T.Damage, context.abilityName)
			victimRoot:ApplyImpulse((direction * T.Push + Vector3.new(0, T.Lift, 0)) * victimRoot.AssemblyMass)
		end
	end
end

function VoidRend.cast(context)
	local player, scope = context.player, context.scope
	local origin = context.origin.Position
	local apex = Plan.apex(origin)
	local id = HttpService:GenerateGUID(false)
	local startedAt = workspace:GetServerTimeNow()
	context.broadcast({
		phase = "leap",
		id = id,
		origin = context.origin,
		takeoff = context.prepared.takeoff,
		startedAt = startedAt,
		seed = context.seed,
	})

	local struck = false
	local function dive(direction)
		local root = context.root
		if scope:isDead() or not root.Parent or context.humanoid.Health <= 0 then return end
		local forward = Plan.flat(direction)
		local standing = standingHeight(context.character)
		local landing, ground = Plan.findLanding(apex, forward, params(context.character), standing)
		if not landing then
			ground = context.prepared.takeoff
			landing = ground + Vector3.new(0, standing + 0.1, 0)
		end
		context.broadcast({
			phase = "strike",
			id = id,
			apex = apex,
			landing = landing,
			ground = ground,
			direction = forward,
			startedAt = workspace:GetServerTimeNow(),
			seed = context.seed,
		})
		scope:delay(T.Dive, function()
			if not root.Parent or context.humanoid.Health <= 0 then return end
			-- The caster's client flew the character; the server's landing stands.
			if (root.Position - landing).Magnitude > 6 then
				context.character:PivotTo(CFrame.lookAt(landing, landing + forward))
			end
			root.AssemblyLinearVelocity = Vector3.zero
			rake(context, ground, forward)
		end)
	end
	local function strike(direction)
		if struck then return end
		struck = true
		if pending[player] == strike then pending[player] = nil end
		-- Pressed during the rise: dive the moment the apex is reached.
		local early = T.Rise - (workspace:GetServerTimeNow() - startedAt)
		if early > 0 then
			scope:delay(early, function() dive(direction) end)
		else
			dive(direction)
		end
	end
	pending[player] = strike
	scope:add(function()
		if pending[player] == strike then pending[player] = nil end
	end)
	scope:delay(T.Rise + T.MaxHover, function()
		-- Studio-only: a held hover frame (see VoidRendVFX) is not cut short.
		if RunService:IsStudio() and workspace:GetAttribute("VoidRendFreezeLeap") then return end
		local root = context.root
		strike(if root.Parent then root.CFrame.LookVector else context.origin.LookVector)
	end)
	return true
end

return VoidRend
