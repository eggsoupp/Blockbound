--[[
	WeaponShotService

	The server half of legendary weapon shots (Shared.Combat.WeaponShots).
	WeaponServer calls `fire` at a swing's hit moment; this aims the shot,
	flies it, and resolves what it hits. Only enemies are hit, as by the blade.

	Every client is told twice: once at the launch, with everything needed to
	draw the whole straight flight, and again for every enemy it passes
	through ("pierce") and where it stops ("hit" against something, "expire"
	at the end of its range). The packet for a hit goes out BEFORE the damage,
	so the thrower's client knows the hit it is about to be told of was the
	shot's and not the blade's (TargetFeedback).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Shots = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponShots"))
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))

local WeaponShot = Remotes.ensure("WeaponShot", "RemoteEvent")

local Service = {}

-- player -> when their last shot left.
local lastShot = setmetatable({}, { __mode = "k" })

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

local function broadcast(packet, near: Vector3)
	local radius = Shots.BroadcastRadius
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - near).Magnitude <= radius then
			WeaponShot:FireClient(player, packet)
		end
	end
end

-- The world a shot can run into: blocks and props, never a character or an
-- enemy (those are tested by hand) and nothing that does not collide.
local function worldParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local exclude = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local enemies = workspace:FindFirstChild(EnemyConfig.WorldFolder)
	if enemies then
		table.insert(exclude, enemies)
	end
	params.FilterDescendantsInstances = exclude
	return params
end

-- Soft aim: the enemy nearest the facing inside the cone and the range.
local function aimAt(root: BasePart, profile)
	local look = flat(root.CFrame.LookVector)
	local cone = math.cos(math.rad(Shots.AimCone))
	local best, bestDot = nil, cone
	EnemyService.forEachNear(root.Position, profile.range, function(_, at)
		local offset = at - root.Position
		local across = Vector3.new(offset.X, 0, offset.Z)
		if across.Magnitude < 1 then
			return
		end
		local dot = across.Unit:Dot(look)
		if dot >= bestDot then
			best, bestDot = at, dot
		end
	end)
	return best
end

-- How big an enemy's body is, for a shot's hit test.
local function bodyRadius(model: Model): number
	local ok, size = pcall(model.GetExtentsSize, model)
	return if ok then math.clamp(size.Magnitude * 0.25, 1.5, 6) else 2
end

--[[
	Throws `player`'s shot for the weapon `itemName`, from a swing that hit for
	`swingDamage`. `finisher` is the combo's last step. Returns true if a shot
	left; false inside the weapon's refire gap or with no profile.
]]
function Service.fire(player: Player, itemName: string, swingDamage: number, finisher: boolean?): boolean
	local profile = Shots.profileFor(itemName)
	if not profile then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local now = os.clock()
	if now - (lastShot[player] or -math.huge) < profile.gap then
		return false
	end
	lastShot[player] = now

	local look = flat(root.CFrame.LookVector)
	local origin = root.Position + Vector3.yAxis * Shots.LaunchHeight + look * Shots.LaunchForward
	local target = aimAt(root, profile)
	local direction = look
	if target then
		local toward = target + Vector3.yAxis * 0.5 - origin
		-- Aimed, but never steeply into the ground or the sky.
		local across = Vector3.new(toward.X, 0, toward.Z)
		if across.Magnitude > 1 then
			local rise = math.clamp(toward.Y / across.Magnitude, -0.35, 0.35)
			direction = (across.Unit + Vector3.yAxis * rise).Unit
		end
	end
	local scale = if finisher then Shots.Finisher.scale else 1
	local damage = math.max(Shots.MinDamage,
		math.floor(swingDamage * profile.damage * (if finisher then Shots.Finisher.damage else 1) + 0.5))
	local radius = profile.radius * scale

	local id = HttpService:GenerateGUID(false)
	local launched = workspace:GetServerTimeNow()
	broadcast({
		id = id, event = "launch", weapon = itemName, origin = origin, direction = direction,
		speed = profile.speed, range = profile.range, scale = scale, startedAt = launched, shooter = player,
	}, origin)

	local params = worldParams()
	local hitModels = {}
	local pierced = 0
	local position, travelled = origin, 0
	local finished = false
	local connection

	local function signal(event: string, at: Vector3, normal: Vector3?)
		broadcast({ id = id, event = event, position = at, normal = normal or -direction, startedAt = workspace:GetServerTimeNow() }, at)
	end

	local function finish(at: Vector3, normal: Vector3?, event: string)
		if finished then
			return
		end
		finished = true
		connection:Disconnect()
		signal(event, at, normal)
		if profile.splash and event == "hit" then
			local splash = math.max(1, math.floor(damage * profile.splashDamage + 0.5))
			EnemyService.forEachNear(at, profile.splash * scale + 4, function(model, where)
				if not hitModels[model] and (where - at).Magnitude <= profile.splash * scale + bodyRadius(model) then
					hitModels[model] = true
					EnemyService.damage(model, splash, player)
				end
			end)
		end
	end

	connection = RunService.Heartbeat:Connect(function()
		if finished then
			return
		end
		if not player.Parent then
			finished = true
			connection:Disconnect()
			return
		end
		local expected = math.min(profile.range, (workspace:GetServerTimeNow() - launched) * profile.speed)
		local distance = expected - travelled
		if distance <= 0 then
			return
		end
		local step = direction * distance
		local world = workspace:Spherecast(position, Shots.WorldRadius, step, params)
		local limit = if world then world.Distance / distance else 1

		-- Every enemy the shot passes on this step, nearest first.
		local crossed = {}
		EnemyService.forEachNear(position + step * 0.5, distance * 0.5 + 10, function(model, at)
			if hitModels[model] then
				return
			end
			local t = math.clamp((at - position):Dot(step) / step:Dot(step), 0, 1)
			if t <= limit and (position + step * t - at).Magnitude <= radius + bodyRadius(model) then
				table.insert(crossed, { model = model, t = t })
			end
		end)
		table.sort(crossed, function(a, b)
			return a.t < b.t
		end)
		for _, crossing in ipairs(crossed) do
			local at = position + step * crossing.t
			hitModels[crossing.model] = true
			if pierced >= profile.pierce then
				-- This one stops it: the packet first, then the damage.
				finish(at, -direction, "hit")
				EnemyService.damage(crossing.model, damage, player)
				return
			end
			pierced += 1
			signal("pierce", at, -direction)
			EnemyService.damage(crossing.model, damage, player)
		end

		if world then
			finish(world.Position, world.Normal, "hit")
			return
		end
		position += step
		travelled = expected
		if travelled >= profile.range then
			finish(position, -direction, "expire")
		end
	end)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	lastShot[player] = nil
end)

return Service
