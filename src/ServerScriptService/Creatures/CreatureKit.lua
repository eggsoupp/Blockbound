--[[
	CreatureKit

	What the creature traits in this folder share: telling clients what to draw,
	hurting players in an area, testing a line through the block grid and
	placing a model with a cosmetic tilt.

	A trait (see EnemyService.traitFor) is an ordinary creature's signature
	move layered on top of its Fly or Hop movement. The traits never draw
	anything themselves - every visible effect goes to the clients as one
	CreatureFX message and StarterPlayerScripts.CreatureFX builds it from the
	curated pack emitters in Shared.Enemies.CreatureParticles.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))

local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))

local STUD_SIZE = TerrainConfig.StudSize

--[[
	CreatureFX(kind, ...) to every client. A receipt of something the server
	has already decided - where the laser went, where the snowball burst - never
	something a client can ask for.
]]
local CreatureFX = Remotes.ensure("CreatureFX", "RemoteEvent")

local CreatureKit = {}

-- EnemyService requires the traits lazily, so by the time one runs this is a
-- finished module; requiring it at the top of this file would be a cycle.
function CreatureKit.service()
	return require(ServerScriptService:WaitForChild("EnemyService"))
end

function CreatureKit.fx(kind: string, ...)
	CreatureFX:FireAllClients(kind, ...)
end

function CreatureKit.flat(v: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
end

-- Where the creature's feet are: what EnemyService.placeModel takes.
function CreatureKit.feet(entry): Vector3
	return entry.model:GetPivot().Position - Vector3.new(0, entry.feetOffset, 0)
end

--[[
	Stands the creature at `feet` looking along `look`, then leans it by
	`tilt` about its pivot. `look` may point up or down - a diving wasp looks
	where it is going - so its climb is clamped short of vertical, where lookAt
	has no sensible "up".

	The lean is cosmetic and never accumulates: EnemyService reads only the
	pivot's position back, and every placement rebuilds the rotation from the
	facing.
]]
function CreatureKit.place(entry, feet: Vector3, look: Vector3?, tilt: CFrame?)
	local Service = CreatureKit.service()

	if look and look.Magnitude > 1e-3 then
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			flat = entry.facing or Vector3.new(0, 0, -1)
		end
		local unit = look.Unit
		local climb = math.clamp(math.asin(math.clamp(unit.Y, -1, 1)), -1.1, 1.1)
		look = flat.Unit * math.cos(climb) + Vector3.new(0, math.sin(climb), 0)
	end

	Service.placeModel(entry, feet, look)
	if tilt then
		CreatureKit.tilt(entry, tilt)
	end
end

-- Leans an already-placed model about its pivot, inside the asset's own
-- orientation correction.
function CreatureKit.tilt(entry, tilt: CFrame)
	local orient = entry.orient or CFrame.identity
	local pivot = entry.model:GetPivot()
	entry.model:PivotTo(pivot * orient:Inverse() * tilt * orient)
end

-- Raw damage to one player, scaled like contact damage.
function CreatureKit.hurt(entry, player: Player, damage: number)
	CombatService.applyDamage(player, damage * (entry.damageScale or 1), entry.name)
end

--[[
	Every living player whose root is within `radius` of `center`, hit for
	`damage` falling off to `edgeShare` of it at the rim. Scaled like contact
	damage, so a tutorial-tamed creature is tamed here too.
]]
function CreatureKit.hurtSphere(entry, center: Vector3, radius: number, damage: number, edgeShare: number?)
	local hit = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - center).Magnitude
			if distance <= radius then
				local share = 1 - (1 - (edgeShare or 1)) * (distance / radius)
				CreatureKit.hurt(entry, player, damage * share)
				hit += 1
			end
		end
	end
	return hit
end

--[[
	Living players within `radius` of the segment a -> b, measured from their
	root or, with `drop`, from that many studs below it: 2.5 is about the
	ankle, which is what a beam raking the ground has to be jumped over at.
]]
function CreatureKit.playersAlong(a: Vector3, b: Vector3, radius: number, drop: number?)
	local found = {}
	local axis = b - a
	local lengthSquared = axis:Dot(axis)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local at = root.Position - Vector3.new(0, drop or 0, 0)
			local t = if lengthSquared > 0 then math.clamp((at - a):Dot(axis) / lengthSquared, 0, 1) else 0
			if (a + axis * t - at).Magnitude <= radius then
				table.insert(found, player)
			end
		end
	end
	return found
end

--[[
	Slides a grounded creature over the surface by `step` (a flat offset),
	looking along `look`, leaning by `tilt`. Returns false without moving when
	the ground ahead rises or falls more than `maxStep` studs - a step or a
	drop - so the caller can hand the tick to the ordinary hop, which climbs it.
]]
function CreatureKit.slide(entry, step: Vector3, look: Vector3?, tilt: CFrame?, maxStep: number?): boolean
	local feet = CreatureKit.feet(entry)
	local ahead = feet + Vector3.new(step.X, 0, step.Z)
	local ground = CreatureKit.service().groundAt(ahead.X, ahead.Z, feet.Y)
	if math.abs(ground - feet.Y) > (maxStep or 2) then
		return false
	end
	CreatureKit.place(entry, Vector3.new(ahead.X, ground, ahead.Z), look, tilt)
	entry.groundY = ground
	return true
end

--[[
	Slows a player to `multiplier` of their speed for `seconds`, through the
	SpeedMultiplier character attribute the walk script honours. A newer slow
	replaces an older one; only the latest one's expiry clears it.
]]
local slowTokens = setmetatable({}, { __mode = "k" })

function CreatureKit.slow(player: Player, multiplier: number, seconds: number)
	local character = player.Character
	if not character then
		return
	end
	local token = {}
	slowTokens[character] = token
	character:SetAttribute("SpeedMultiplier", multiplier)
	task.delay(seconds, function()
		if slowTokens[character] == token and character.Parent then
			slowTokens[character] = nil
			character:SetAttribute("SpeedMultiplier", nil)
		end
	end)
end

--[[
	A projectile on a real arc, simulated here and drawn by every client from
	the same launch numbers (CreatureFX "throw"; `style` picks its look). It
	bursts on the first block or player it meets, or after `maxLife`, and
	`onHit(point, playersHit)` decides what that does. Its own Heartbeat
	connection, so it outlives whatever threw it.
]]
function CreatureKit.projectile(spec)
	local id = HttpService:GenerateGUID(false)
	local origin, velocity, gravity = spec.origin, spec.velocity, spec.gravity
	local startedAt = os.clock()
	local last = origin
	CreatureKit.fx("throw", id, origin, velocity, gravity, spec.style)

	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startedAt
		local point = origin + velocity * t + Vector3.new(0, -0.5 * gravity * t * t, 0)

		local players = CreatureKit.playersAlong(last, point, spec.hitRadius or 2)
		local block = CreatureKit.firstBlock(last, point, 0.5) or (CreatureKit.solidAt(point) and point)
		last = point

		if #players > 0 or block or t >= (spec.maxLife or 3) then
			connection:Disconnect()
			local at = if block then block else point
			CreatureKit.fx("splash", id, at, spec.style)
			spec.onHit(at, players)
		end
	end)
end

-- Sets the Pose attribute a rigged creature's client animation reads.
function CreatureKit.pose(entry, pose: string)
	if entry.model:GetAttribute("Pose") ~= pose then
		entry.model:SetAttribute("Pose", pose)
	end
end

--[[
	How a winged model's wings should move: "flap", "glide", "fold" or
	"spread". An attribute, read by StarterPlayerScripts.CreatureFX, which
	does the flapping itself every frame; the server only says which.
]]
function CreatureKit.wings(entry, mode: string)
	if entry.model:GetAttribute("WingMode") ~= mode then
		entry.model:SetAttribute("WingMode", mode)
	end
end

function CreatureKit.solidAt(point: Vector3): boolean
	return TerrainManager:IsSolidAt(
		math.floor(point.X / STUD_SIZE), math.floor(point.Y / STUD_SIZE), math.floor(point.Z / STUD_SIZE)
	)
end

--[[
	Walks the block grid from `a` towards `b` and returns the first point
	inside a solid block, or nil when the way is clear. Asked of the voxel
	data rather than the physics world, so it sees exactly the blocks a player
	sees and nothing else - not a dropped item, not another enemy.
]]
function CreatureKit.firstBlock(a: Vector3, b: Vector3, step: number?): Vector3?
	local delta = b - a
	local length = delta.Magnitude
	if length < 1e-3 then
		return nil
	end
	local stride = step or 1
	local direction = delta / length
	local travelled = stride
	while travelled < length do
		local point = a + direction * travelled
		if CreatureKit.solidAt(point) then
			return point
		end
		travelled += stride
	end
	return nil
end

return CreatureKit
