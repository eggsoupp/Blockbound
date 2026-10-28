--[[
	Snowman - hops through the snow after you, and from range stops, winds up
	and lobs a snowball.

	The snowball is a real projectile on a real arc, simulated here and drawn
	by every client from the same launch numbers (StarterPlayerScripts.
	CreatureFX), so what you see coming is what can hit you. It is aimed at
	where you were standing when it left the hand: keep moving and it lands
	behind you; stand still mining and it does not. It bursts on the first
	block or player it meets, hurting anyone in `splash`.
]]

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	range = 46,
	minRange = 9,
	windupSeconds = 0.55,
	cooldown = 3.4,

	-- Horizontal studs a second, and the arc's own gravity: lower than the
	-- world's so the lob reads, and steep enough to clear a block or two.
	throwSpeed = 32,
	gravity = 70,
	minFlight = 0.45,
	maxFlight = 1.5,

	damage = 10,
	splash = 3.5,
	-- How close the ball has to pass a player to burst on them.
	hitRadius = 2.2,
	-- A ball still flying this long after launch has missed everything.
	maxLife = 3,

	-- Where it leaves the hand: up the snowman's height, out from its front.
	-- Over its own head, so a throw up a slope does not start in the hill.
	handHeight = 1.05,
	handForward = 0.5,
}

local Trait = {}
Trait.Tuning = Tuning

local function splash(entry, point: Vector3, id: string)
	CreatureKit.hurtSphere(entry, point, Tuning.splash, Tuning.damage, 0.6)
	CreatureKit.fx("splash", id, point)
end

--[[
	Flies one snowball to whatever it meets. Its own Heartbeat connection, so
	the ball outlives the snowman that threw it - killing the thrower does not
	stop a ball already in the air.
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

local function throw(entry, targetPosition: Vector3)
	local feet = CreatureKit.feet(entry)
	local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
	local origin = feet + Vector3.new(0, entry.height * Tuning.handHeight, 0) + look * Tuning.handForward
	if CreatureKit.solidAt(origin) then
		-- Hemmed in under a ledge: nothing to throw through.
		return
	end

	local offset = targetPosition - origin
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local flight = math.clamp(flat.Magnitude / Tuning.throwSpeed, Tuning.minFlight, Tuning.maxFlight)
	local horizontal = flat / flight
	local vertical = (offset.Y + 0.5 * Tuning.gravity * flight * flight) / flight

	launch(entry, origin, Vector3.new(horizontal.X, vertical, horizontal.Z))
end

function Trait.step(entry, target, targetPosition, position, _dt, now)
	if entry.throwAt then
		if entry.state ~= "Grounded" then
			entry.throwAt = nil
			return false
		end
		if now >= entry.throwAt then
			entry.throwAt = nil
			entry.nextThrowAt = now + Tuning.cooldown
			throw(entry, targetPosition or entry.throwAim)
		end
		return true
	end

	if not (target and targetPosition) or entry.state ~= "Grounded" or now < (entry.nextThrowAt or 0) then
		return false
	end

	local distance = (targetPosition - position).Magnitude
	if distance > Tuning.range or distance < Tuning.minRange then
		return false
	end

	CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(targetPosition - position))
	entry.throwAt = now + Tuning.windupSeconds
	entry.throwAim = targetPosition
	if entry.body then
		entry.body:crouch(Tuning.windupSeconds)
	end
	CreatureKit.fx("flare", entry.model, Color3.fromRGB(200, 235, 255))
	return true
end

return Trait
