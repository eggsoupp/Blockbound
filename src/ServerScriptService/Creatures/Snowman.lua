--[[
	Snowman - skates. It glides over the ground with momentum, waddling from
	side to side and kicking up snow, and once it is close it circles you
	rather than charging. It only hops to get up a step; the hop is the
	ordinary movement, which this hands back to for that one tick.

	VOLLEY (`minRange` to `range`). It leans back and lobs three snowballs in
	a spread across where you stand: the middle one is aimed, the side ones
	cut off the obvious sidestep. Each is a real projectile on a real arc,
	simulated here and drawn by every client from the same launch numbers;
	it bursts on the first block or player it meets.

	BROOM SPIN (within `spinRange`). It winds back and spins twice with its
	broom out, hitting everything around it once. Backing off during the
	wind-up is the answer.
]]

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	-- Skating: top speed, how quickly it reaches it, and the distance it
	-- likes to circle at once it has closed in.
	skateSpeed = 9,
	acceleration = 3.5,
	circleDistance = 11,
	-- Studs of rise or fall it will glide over; more is a hop.
	slideStep = 2,
	waddle = 0.14,
	waddleRate = 7,

	range = 46,
	minRange = 9,
	volleyWindup = 0.55,
	volleyCount = 3,
	volleyGap = 0.14,
	-- How far either side of you the outer snowballs land, in studs.
	volleySpread = 4.5,
	volleyCooldown = 3.6,

	throwSpeed = 32,
	gravity = 70,
	minFlight = 0.45,
	maxFlight = 1.5,
	damage = 9,
	splash = 3.5,
	hitRadius = 2.2,
	maxLife = 3,
	-- Where it leaves the hand: over its own head, so a throw up a slope
	-- does not start in the hill.
	handHeight = 1.05,
	handForward = 0.5,

	spinRange = 7,
	spinWindup = 0.45,
	spinSeconds = 0.6,
	spinTurns = 2,
	spinRadius = 7.5,
	spinDamage = 12,
	spinCooldown = 3,
}

local Trait = {}
Trait.Tuning = Tuning

local function splash(entry, point: Vector3, id: string)
	CreatureKit.hurtSphere(entry, point, Tuning.splash, Tuning.damage, 0.6)
	CreatureKit.fx("splash", id, point)
end

--[[
	Flies one snowball to whatever it meets. Its own Heartbeat connection, so
	the ball outlives the snowman that threw it.
]]
local function launch(entry, origin: Vector3, velocity: Vector3)
	local id = HttpService:GenerateGUID(false)
	local startedAt = os.clock()
	local last = origin
	CreatureKit.fx("throw", id, origin, velocity, Tuning.gravity)

	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startedAt
		local point = origin + velocity * t + Vector3.new(0, -0.5 * Tuning.gravity * t * t, 0)

		local hitPlayer = #CreatureKit.playersAlong(last, point, Tuning.hitRadius) > 0
		local block = CreatureKit.firstBlock(last, point, 0.5) or (CreatureKit.solidAt(point) and point)
		last = point

		if hitPlayer or block or t >= Tuning.maxLife then
			connection:Disconnect()
			splash(entry, if block then block else point, id)
		end
	end)
end

local function throw(entry, aim: Vector3)
	local feet = CreatureKit.feet(entry)
	local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
	local origin = feet + Vector3.new(0, entry.height * Tuning.handHeight, 0) + look * Tuning.handForward
	if CreatureKit.solidAt(origin) then
		-- Hemmed in under a ledge: nothing to throw through.
		return
	end

	local offset = aim - origin
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local flight = math.clamp(flat.Magnitude / Tuning.throwSpeed, Tuning.minFlight, Tuning.maxFlight)
	local horizontal = flat / flight
	local vertical = (offset.Y + 0.5 * Tuning.gravity * flight * flight) / flight
	launch(entry, origin, Vector3.new(horizontal.X, vertical, horizontal.Z))
end

-- Lean back by `share` of a wind-up, with the waddle stilled.
local function leanBack(share: number): CFrame
	return CFrame.Angles(0.35 * share, 0, 0)
end

local function stepVolley(entry, move, targetPosition: Vector3?, now: number)
	local elapsed = now - move.startedAt
	if elapsed < Tuning.volleyWindup then
		CreatureKit.place(entry, CreatureKit.feet(entry), nil, leanBack(elapsed / Tuning.volleyWindup))
		return
	end

	-- The aim is where you are as the first ball leaves, then fixed.
	if not move.aim then
		move.aim = targetPosition or move.lastAim
		local across = CreatureKit.flat(move.aim - CreatureKit.feet(entry)):Cross(Vector3.yAxis)
		move.offsets = { 0, -Tuning.volleySpread, Tuning.volleySpread }
		move.across = across
	end

	local due = math.floor((elapsed - Tuning.volleyWindup) / Tuning.volleyGap) + 1
	while (move.thrown or 0) < math.min(due, Tuning.volleyCount) do
		move.thrown = (move.thrown or 0) + 1
		throw(entry, move.aim + move.across * move.offsets[move.thrown])
	end
	CreatureKit.place(entry, CreatureKit.feet(entry))

	if move.thrown >= Tuning.volleyCount then
		entry.move = nil
		entry.nextVolleyAt = now + Tuning.volleyCooldown
	end
end

local function stepSpin(entry, move, now: number)
	local elapsed = now - move.startedAt
	if elapsed < Tuning.spinWindup then
		CreatureKit.place(entry, CreatureKit.feet(entry), nil, leanBack(elapsed / Tuning.spinWindup))
		return
	end

	if not move.started then
		move.started = true
		move.hit = {}
		CreatureKit.fx("spin", entry.model, Tuning.spinSeconds, Tuning.spinRadius)
	end

	local t = math.min(1, (elapsed - Tuning.spinWindup) / Tuning.spinSeconds)
	local angle = t * Tuning.spinTurns * math.pi * 2
	CreatureKit.place(entry, CreatureKit.feet(entry), (CFrame.Angles(0, angle, 0) * CFrame.new(move.facing)).Position)

	local centre = CreatureKit.feet(entry) + Vector3.new(0, 2, 0)
	for _, player in ipairs(CreatureKit.playersAlong(centre, centre, Tuning.spinRadius)) do
		if not move.hit[player] then
			move.hit[player] = true
			CreatureKit.hurt(entry, player, Tuning.spinDamage)
		end
	end

	if t >= 1 then
		entry.move = nil
		entry.nextSpinAt = now + Tuning.spinCooldown
	end
end

-- Skating: momentum toward a point beside you, circling once close.
local function skate(entry, targetPosition: Vector3, position: Vector3, dt: number, now: number): boolean
	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

	entry.circle = entry.circle or (if math.random() < 0.5 then 1 else -1)
	local around = toward:Cross(Vector3.yAxis) * entry.circle
	local closing = math.clamp((distance - Tuning.circleDistance) / 6, -1, 1)
	local wanted = (toward * closing + around * (1 - math.abs(closing)) * 0.8)
	if wanted.Magnitude > 1 then
		wanted = wanted.Unit
	end

	local velocity = entry.skate or Vector3.zero
	velocity += (wanted * Tuning.skateSpeed - velocity) * math.min(1, Tuning.acceleration * dt)
	entry.skate = velocity

	-- Faces you, waddling, leaning into its speed.
	local lean = velocity.Magnitude / Tuning.skateSpeed
	local tilt = CFrame.Angles(-0.12 * lean, 0, math.sin(now * Tuning.waddleRate) * Tuning.waddle * (0.3 + lean))
	if not CreatureKit.slide(entry, velocity * dt, toward, tilt, Tuning.slideStep) then
		entry.skate = Vector3.zero
		return false
	end
	CreatureKit.service().touch(entry, CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.4, 0))
	return true
end

function Trait.start(entry)
	entry.model:SetAttribute("SnowTrail", true)
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		entry.skate = Vector3.zero
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "volley" then
			stepVolley(entry, move, targetPosition, now)
		else
			stepSpin(entry, move, now)
		end
		return true
	end

	if not (target and targetPosition) then
		return false
	end

	local distance = (targetPosition - position).Magnitude
	if distance <= Tuning.spinRange and now >= (entry.nextSpinAt or 0) then
		entry.move = { kind = "spin", startedAt = now, facing = CreatureKit.flat(targetPosition - position) }
		entry.skate = Vector3.zero
		CreatureKit.fx("flare", entry.model, Color3.fromRGB(200, 235, 255))
		return true
	end

	if distance >= Tuning.minRange and distance <= Tuning.range and now >= (entry.nextVolleyAt or 0) then
		entry.move = { kind = "volley", startedAt = now, lastAim = targetPosition }
		entry.skate = Vector3.zero
		CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(targetPosition - position))
		CreatureKit.fx("flare", entry.model, Color3.fromRGB(200, 235, 255))
		return true
	end

	return skate(entry, targetPosition, position, dt, now)
end

return Trait
