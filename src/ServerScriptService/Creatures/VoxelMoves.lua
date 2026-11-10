--[[
	VoxelMoves

	What the ten big voxel creatures share (assets/voxel-enemies): a move
	runner that times every blow to the creature's animation clip, the shapes
	a blow can cover, what it does to the players it catches, projectiles and
	lingering zones. Each creature's trait is a declarative list of moves
	built with VoxelMoves.trait.

	TIMING. A move plays the clip of the same name from
	Shared.Enemies.VoxelRigs.<Rig>, and its events are keyed by that clip's
	marks, so the server lands a hit on the very beat the client shows it.

	EFFECTS. Everything visible goes to the clients as one VoxelRigFX message
	(StarterPlayerScripts.VoxelRigFX draws it from Shared.Enemies.VoxelRigs.
	Effects); this side never builds an effect itself.

	  VoxelMoves.trait(spec) -> trait table for EnemyService
	    spec.rig        rig module name (and the Rig attribute)
	    spec.walkSpeed  studs/second it walks after its target
	    spec.closeTo    how near it walks before it stops and turns
	    spec.gap        seconds of plain walking between two moves
	    spec.moves      { name, range = {min, max}, cooldown, weight, when,
	                      track, lunge, start, tick, events = { mark = fn } }
	    spec.guard      optional EnemyService guard hook
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local CreatureKit = require(script.Parent.CreatureKit)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Rigs = ReplicatedStorage.Shared.Enemies.VoxelRigs

local RigFX = Remotes.ensure("VoxelRigFX", "RemoteEvent")

local VoxelMoves = {}
VoxelMoves.Kit = CreatureKit

function VoxelMoves.fx(kind: string, ...)
	RigFX:FireAllClients(kind, ...)
end

function VoxelMoves.fxTo(player: Player, kind: string, ...)
	RigFX:FireClient(player, kind, ...)
end

-- ---------------------------------------------------------------------------
-- Where things are
-- ---------------------------------------------------------------------------

function VoxelMoves.scale(entry): number
	return entry.model:GetScale()
end

function VoxelMoves.look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- A rest-pose point of the rig (voxel units, the design's axes) in the world.
function VoxelMoves.point(entry, voxel: Vector3): Vector3
	return entry.model:GetPivot() * (voxel * entry.rigSpec.voxel * entry.model:GetScale())
end

-- On the ground `studs` ahead of the feet (scaled with the model).
function VoxelMoves.ahead(entry, studs: number): Vector3
	return CreatureKit.feet(entry) + VoxelMoves.look(entry) * studs * VoxelMoves.scale(entry)
end

-- The ground under a point, so a mark lies on what the player stands on.
function VoxelMoves.ground(point: Vector3): Vector3
	local y = CreatureKit.service().groundAt(point.X, point.Z, point.Y + 4)
	return Vector3.new(point.X, y, point.Z)
end

local function living()
	local found = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			table.insert(found, { player = player, root = root })
		end
	end
	return found
end

-- Players whose root is within `radius` of `center` across the ground and
-- within `height` of it up and down.
function VoxelMoves.inCircle(center: Vector3, radius: number, height: number?): { Player }
	local found = {}
	for _, p in ipairs(living()) do
		local offset = p.root.Position - center
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= (height or 7) then
			table.insert(found, p.player)
		end
	end
	return found
end

-- Players inside a cone from `origin` along `direction`.
function VoxelMoves.inCone(origin: Vector3, direction: Vector3, range: number, halfAngle: number, height: number?): { Player }
	local found = {}
	local flat = CreatureKit.flat(direction)
	local cosine = math.cos(math.rad(halfAngle))
	for _, p in ipairs(living()) do
		local offset = p.root.Position - origin
		local across = Vector3.new(offset.X, 0, offset.Z)
		if across.Magnitude <= range and math.abs(offset.Y) <= (height or 8)
			and (across.Magnitude < 2 or across.Unit:Dot(flat) >= cosine) then
			table.insert(found, p.player)
		end
	end
	return found
end

function VoxelMoves.along(a: Vector3, b: Vector3, radius: number): { Player }
	return CreatureKit.playersAlong(a, b, radius)
end

-- ---------------------------------------------------------------------------
-- What a blow does
-- ---------------------------------------------------------------------------

-- Pushes a player's character: their client owns it, so it is asked to.
function VoxelMoves.knock(player: Player, velocity: Vector3)
	VoxelMoves.fxTo(player, "knock", velocity)
end

local function rootOf(player: Player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

--[[
	Hurts each player for `damage` (scaled like contact damage) and applies:
	  slow = { multiplier, seconds }
	  dot  = { ticks, damage, interval, style }   damage over time
	  knock = { from = Vector3, speed, lift }     pushed away from `from`
	  pull  = { to = Vector3, speed, lift }       hauled toward `to`
	  hitFx = style                               a hit spark on each one
	Returns how many it hit.
]]
function VoxelMoves.hit(entry, players: { Player }, damage: number, opts)
	opts = opts or {}
	if #players > 0 and damage > 0 and workspace:GetAttribute("VoxelDebug") then
		print(string.format("[VoxelMoves] %s hit %d player(s) for %s", entry.name, #players, tostring(damage)))
	end
	for _, player in ipairs(players) do
		if damage > 0 then
			CreatureKit.hurt(entry, player, damage)
		end
		local root = rootOf(player)
		if opts.slow then
			CreatureKit.slow(player, opts.slow[1], opts.slow[2])
		end
		if opts.dot then
			local ticks, each, interval, style = opts.dot[1], opts.dot[2], opts.dot[3], opts.dot[4]
			if style and player.Character then
				VoxelMoves.fx("afflict", player.Character, style, ticks * interval)
			end
			for i = 1, ticks do
				task.delay(i * interval, function()
					local humanoid = player.Parent and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						CreatureKit.hurt(entry, player, each)
					end
				end)
			end
		end
		if root and opts.knock then
			local away = CreatureKit.flat(root.Position - opts.knock.from)
			if away.Magnitude < 0.5 then
				away = VoxelMoves.look(entry)
			end
			VoxelMoves.knock(player, away * opts.knock.speed + Vector3.yAxis * (opts.knock.lift or 0))
		end
		if root and opts.pull then
			local toward = opts.pull.to - root.Position
			local flat = Vector3.new(toward.X, 0, toward.Z)
			local speed = math.min(opts.pull.speed, flat.Magnitude * 3)
			VoxelMoves.knock(player, (if flat.Magnitude > 0.5 then flat.Unit else Vector3.zero) * speed + Vector3.yAxis * (opts.pull.lift or 0))
		end
		if root and opts.hitFx then
			VoxelMoves.fx("burst", opts.hitFx, root.Position, 1)
		end
	end
	return #players
end

--[[
	A ground hazard: every `interval` seconds for `seconds`, players inside
	`radius` of `center` take `damage` (and `slow`, if given). Drawn by the
	clients from `style`.
]]
function VoxelMoves.zone(entry, center: Vector3, radius: number, seconds: number, interval: number, damage: number, style: string, slow)
	VoxelMoves.fx("zone", style, center, radius, seconds)
	local started = os.clock()
	local nextAt = started + interval
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - started >= seconds then
			connection:Disconnect()
			return
		end
		if now >= nextAt then
			nextAt += interval
			local caught = VoxelMoves.inCircle(center, radius, 6)
			if #caught > 0 and entry.model.Parent then
				VoxelMoves.hit(entry, caught, damage, { slow = slow })
			end
		end
	end)
end

--[[
	A projectile on a real arc, simulated here; the clients draw it from the
	same launch numbers. Bursts on a block, a player, or after `maxLife`.
	spec: origin, velocity, gravity, radius, maxLife, style, onHit(point, players)
]]
function VoxelMoves.projectile(spec)
	local id = HttpService:GenerateGUID(false)
	local origin, velocity, gravity = spec.origin, spec.velocity, spec.gravity or 0
	local startedAt = os.clock()
	local last = origin
	VoxelMoves.fx("shot", spec.style, id, origin, velocity, gravity)

	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startedAt
		local point = origin + velocity * t + Vector3.new(0, -0.5 * gravity * t * t, 0)
		local players = CreatureKit.playersAlong(last, point, spec.radius or 2)
		local block = (t > 0.08 and CreatureKit.firstBlock(last, point, 0.5)) or nil
		last = point
		if #players > 0 or block or t >= (spec.maxLife or 3) then
			connection:Disconnect()
			local at = block or point
			VoxelMoves.fx("shotEnd", spec.style, id, at)
			spec.onHit(at, players)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- The move runner
-- ---------------------------------------------------------------------------

local function face(entry, toward: Vector3)
	local flat = CreatureKit.flat(toward)
	if flat.Magnitude > 0.1 then
		CreatureKit.place(entry, CreatureKit.feet(entry), flat)
	end
end
VoxelMoves.face = face

-- Turns toward a direction by at most `rate` radians this tick.
function VoxelMoves.turnToward(entry, toward: Vector3, rate: number)
	local want = CreatureKit.flat(toward)
	local have = VoxelMoves.look(entry)
	if want.Magnitude < 0.1 then
		return
	end
	local angle = math.acos(math.clamp(have:Dot(want), -1, 1))
	if angle <= rate then
		face(entry, want)
		return
	end
	local sign = if have:Cross(want).Y >= 0 then 1 else -1
	face(entry, CFrame.Angles(0, sign * rate, 0):VectorToWorldSpace(have))
end

local function begin(entry, spec, move, target, targetPosition, now)
	local clipData = entry.rigSpec.moves[move.clip or move.name]
	local active = {
		def = move,
		clip = clipData,
		started = now,
		target = target,
		aim = targetPosition,
		fired = {},
		hitSet = {},
		endAt = now + (move.duration or (clipData and clipData.duration) or 1),
	}
	entry.move = active
	entry.cooldowns[move.name] = now + (move.cooldown or 3)
	entry.nextMoveAt = now + (move.duration or (clipData and clipData.duration) or 1) + (spec.gap or 0.5)
	if targetPosition then
		face(entry, targetPosition - CreatureKit.feet(entry))
	end
	CreatureKit.pose(entry, move.clip or move.name)
	if workspace:GetAttribute("VoxelDebug") then
		print(string.format("[VoxelMoves] %s -> %s", entry.name, move.name))
	end
	if move.start then
		move.start(entry, active)
	end
	return active
end

-- When an event keyed by a mark name (or a number of seconds) is due.
local function markTime(active, key)
	if type(key) == "number" then
		return key
	end
	local marks = active.clip and active.clip.marks
	return (marks and marks[key]) or 0
end

local function runActive(entry, active, target, targetPosition, now, dt)
	local def = active.def
	local t = now - active.started
	active.target = target or active.target
	if targetPosition then
		active.targetPosition = targetPosition
	end
	if def.track and t < def.track and targetPosition then
		VoxelMoves.turnToward(entry, targetPosition - CreatureKit.feet(entry), (def.turnRate or 4) * dt)
	end
	if def.events then
		for key, fn in pairs(def.events) do
			if not active.fired[key] and t >= markTime(active, key) then
				active.fired[key] = true
				local ok, err = pcall(fn, entry, active)
				if not ok then
					warn(string.format("[VoxelMoves] %s.%s %s: %s", entry.name, def.name, tostring(key), tostring(err)))
				end
			end
		end
	end
	if def.tick then
		local ok, err = pcall(def.tick, entry, active, t, dt)
		if not ok then
			warn(string.format("[VoxelMoves] %s.%s tick: %s", entry.name, def.name, tostring(err)))
		end
	end
	if now >= active.endAt or active.cancel then
		entry.move = nil
		CreatureKit.pose(entry, "walk")
	end
end

local function pick(entry, spec, distance, now)
	local choices, total = {}, 0
	for _, move in ipairs(spec.moves) do
		local range = move.range or { 0, math.huge }
		if distance >= range[1] and distance <= range[2]
			and now >= (entry.cooldowns[move.name] or 0)
			and (not move.when or move.when(entry, distance)) then
			local weight = move.weight or 1
			table.insert(choices, { move = move, weight = weight })
			total += weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for _, c in ipairs(choices) do
		roll -= c.weight
		if roll <= 0 then
			return c.move
		end
	end
	return choices[#choices].move
end

function VoxelMoves.trait(spec)
	local rigSpec = require(Rigs:WaitForChild(spec.rig))
	local Trait = { Spec = spec }

	function Trait.start(entry)
		entry.rigSpec = rigSpec
		entry.cooldowns = {}
		-- A first move a moment after it notices you, never on the spot.
		entry.nextMoveAt = os.clock() + 1.2
		entry.model:SetAttribute("Rig", spec.rig)
		CreatureKit.pose(entry, "walk")
		-- First uses come staggered, so two of the same do not open in step.
		for _, move in ipairs(spec.moves) do
			entry.cooldowns[move.name] = os.clock() + (move.opener or math.random() * 2)
		end
		if spec.start then
			spec.start(entry)
		end
	end

	Trait.guard = spec.guard

	function Trait.finish(entry)
		entry.move = nil
	end

	function Trait.step(entry, target, targetPosition, position, dt, now)
		if not entry.rigSpec then
			Trait.start(entry)
		end
		local active = entry.move
		if active then
			if entry.state ~= "Grounded" and not active.def.airborne then
				entry.move = nil
				return false
			end
			runActive(entry, active, target, targetPosition, now, dt)
			return true
		end

		if entry.state ~= "Grounded" then
			return false
		end

		-- QA: ForceMove = "<move>" on the model starts that move now, in
		-- range or not, whatever its cooldown.
		local forced = entry.model:GetAttribute("ForceMove")
		if forced then
			entry.model:SetAttribute("ForceMove", nil)
			for _, move in ipairs(spec.moves) do
				if move.name == forced and not move.lunge then
					begin(entry, spec, move, target, targetPosition or VoxelMoves.ahead(entry, 12), now)
					return true
				end
			end
		end

		if not (target and targetPosition) then
			CreatureKit.pose(entry, "walk")
			return false
		end

		local toward = CreatureKit.flat(targetPosition - position)
		local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

		if now >= (entry.nextMoveAt or 0) then
			local move = pick(entry, spec, distance, now)
			if move then
				if move.lunge then
					-- The ordinary hop's lunge carries it; the pose holds in the air.
					entry.cooldowns[move.name] = now + (move.cooldown or 5)
					entry.nextMoveAt = now + (spec.gap or 0.5) + 1
					face(entry, toward)
					CreatureKit.pose(entry, move.clip or move.name)
					entry.state = "Windup"
					entry.pendingLunge = true
					entry.stateUntil = now + (entry.def.lungeWindup or 0.4)
					if move.start then
						move.start(entry, { def = move, aim = targetPosition, target = target, started = now })
					end
					return false
				end
				begin(entry, spec, move, target, targetPosition, now)
				return true
			end
		end

		CreatureKit.pose(entry, "walk")
		local close = (spec.closeTo or 5) * VoxelMoves.scale(entry)
		if distance <= close then
			VoxelMoves.turnToward(entry, toward, 3 * dt)
			return true
		end
		if not CreatureKit.slide(entry, toward * spec.walkSpeed * dt, toward, nil, spec.slideStep or 2.2) then
			return false
		end
		return true
	end

	return Trait
end

--[[
	Drives the creature straight along its facing at `speed` for a tick (a
	charge, a rush). False when a wall or a drop stops it.
]]
function VoxelMoves.rush(entry, speed: number, dt: number): boolean
	local look = VoxelMoves.look(entry)
	return CreatureKit.slide(entry, look * speed * dt, look, nil, 2.5)
end

return VoxelMoves
