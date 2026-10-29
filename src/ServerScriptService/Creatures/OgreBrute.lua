--[[
	Ogre Brute - a desert ogre with a double axe in each fist. Slow, tough, and
	every move is a commitment, for it and for you. Head, arms, axes and legs
	are jointed (Shared.Enemies.CreatureRigs.OgreBrute).

	CHOP (within `chopRange`). Both axes hauled overhead and brought down
	together in front of it. Slow to come, and it hurts.

	WHIRLWIND (within `whirlRange`). It roars with its arms flung out for
	`whirlWindup`, then spins with both axes out for `whirlSeconds`, drifting
	toward you and cutting everything within `whirlRadius` every
	`whirlInterval`. Afterwards it is dizzy for `dizzySeconds` - the opening.

	AXE THROW (`throwMin` to `throwRange`). The right-hand axe itself - the
	part off its rig - is flung at you, spinning, and comes back to its hand
	`boomerangSeconds` later, cutting on the way out and on the way back.
	Until it is caught the ogre will not throw again. Blocks turn it round
	early.
]]

local RunService = game:GetService("RunService")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 5,
	slideStep = 2,

	chopRange = 5,
	chopReach = 3.5,
	chopWindup = 0.65,
	chopSeconds = 1.1,
	chopDamage = 16,
	chopCooldown = 2.4,

	whirlRange = 12,
	whirlWindup = 0.7,
	whirlSeconds = 2.2,
	whirlRadius = 4.8,
	whirlInterval = 0.35,
	whirlDamage = 6,
	whirlTurn = 13,
	whirlDrift = 5.5,
	whirlCooldown = 9,
	dizzySeconds = 1.6,

	throwRange = 26,
	throwMin = 9,
	throwWindup = 0.55,
	throwCooldown = 6,
	boomerangSeconds = 1.3,
	axeDamage = 11,
	axeRadius = 2.2,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "OgreBrute")
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- Where its right hand is, for the axe to leave from and come back to.
local function rightHand(entry): Vector3
	local arm = entry.model:FindFirstChild("RightArm")
	if arm then
		return arm.Position - Vector3.new(0, arm.Size.Y * 0.35, 0) + look(entry) * 0.8
	end
	return CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.4, 0)
end

-- Puts a thrown axe back in the hand, or gets rid of it if there is no hand.
local function catch(entry)
	local flight = entry.axeFlight
	if not flight then
		return
	end
	entry.axeFlight = nil
	flight.connection:Disconnect()
	local axe, motor = flight.axe, flight.motor
	if entry.model.Parent and motor.Parent then
		axe.Anchored = false
		axe.Parent = entry.model
		motor.Enabled = true
	else
		axe:Destroy()
	end
end

--[[
	The axe off the rig, flown by the server: unhooked from the wrist,
	anchored, and taken out of the model while it is away (the model is pivoted
	every tick, which would drag an axe that is still in it). Out to the aim
	point on an easing curve, then home to wherever the hand has got to.
]]
local function throwAxe(entry, aim: Vector3)
	local arm = entry.model:FindFirstChild("RightArm")
	local motor = arm and arm:FindFirstChild("RightAxe")
	local axe = entry.model:FindFirstChild("RightAxe")
	if not (motor and axe) then
		return
	end

	local from = rightHand(entry)
	local reach = aim - from
	if reach.Magnitude > Tuning.throwRange then
		reach = reach.Unit * Tuning.throwRange
	end
	local far = from + reach
	local block = CreatureKit.firstBlock(from, far, 0.5)
	if block then
		far = block - reach.Unit * 1
	end

	motor.Enabled = false
	axe.Anchored = true
	axe.Parent = workspace
	CreatureKit.fx("axeflight", axe, Tuning.boomerangSeconds)

	local half = Tuning.boomerangSeconds / 2
	local startedAt = os.clock()
	local last = axe.Position
	local hitOut, hitBack = {}, {}
	local flight = { axe = axe, motor = motor }
	entry.axeFlight = flight
	flight.connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startedAt
		local point
		local hit
		if t < half then
			local k = t / half
			point = from:Lerp(far, 1 - (1 - k) * (1 - k))
			hit = hitOut
		else
			local k = math.min(1, (t - half) / half)
			point = far:Lerp(rightHand(entry), k * k)
			hit = hitBack
		end
		axe.CFrame = CFrame.new(point) * CFrame.Angles(0, t * 22, math.rad(80))
		for _, player in ipairs(CreatureKit.playersAlong(last, point, Tuning.axeRadius)) do
			if not hit[player] then
				hit[player] = true
				CreatureKit.hurt(entry, player, Tuning.axeDamage)
			end
		end
		last = point
		if t >= Tuning.boomerangSeconds then
			catch(entry)
			if entry.model.Parent then
				CreatureKit.pose(entry, "catch")
				entry.catchUntil = os.clock() + 0.35
			end
		end
	end)
end

local function dizzy(entry, now: number)
	entry.move = { kind = "dizzy", untilAt = now + Tuning.dizzySeconds }
	CreatureKit.pose(entry, "dizzy")
	CreatureKit.fx("stunned", entry.model, Tuning.dizzySeconds)
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		if entry.move and entry.move.kind == "whirl" then
			dizzy(entry, now)
			return false
		end
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "chop" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local reach = CreatureKit.feet(entry) + look(entry) * Tuning.chopReach + Vector3.new(0, 1.5, 0)
				CreatureKit.service().touch(entry, reach, Tuning.chopDamage)
				CreatureKit.fx("chop", CreatureKit.feet(entry) + look(entry) * Tuning.chopReach)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "windup" then
			if now >= move.untilAt then
				entry.move = { kind = "whirl", untilAt = now + Tuning.whirlSeconds, nextCutAt = now, angle = 0 }
				CreatureKit.pose(entry, "spin")
				CreatureKit.fx("whirl", entry.model, Tuning.whirlSeconds, Tuning.whirlRadius)
			end
			return true
		elseif move.kind == "whirl" then
			move.angle += Tuning.whirlTurn * dt
			local facing = Vector3.new(math.sin(move.angle), 0, math.cos(move.angle))
			local drift = if targetPosition then CreatureKit.flat(targetPosition - position) else Vector3.zero
			if not CreatureKit.slide(entry, drift * Tuning.whirlDrift * dt, facing, nil, Tuning.slideStep) then
				CreatureKit.place(entry, CreatureKit.feet(entry), facing)
			end
			if now >= move.nextCutAt then
				move.nextCutAt = now + Tuning.whirlInterval
				CreatureKit.hurtSphere(entry, CreatureKit.feet(entry) + Vector3.new(0, 1.5, 0), Tuning.whirlRadius, Tuning.whirlDamage, 1)
			end
			if now >= move.untilAt then
				dizzy(entry, now)
			end
			return true
		elseif move.kind == "dizzy" then
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "throw" then
			if now >= move.at then
				entry.move = nil
				throwAxe(entry, (targetPosition or move.aim) + Vector3.new(0, -0.5, 0))
				CreatureKit.pose(entry, "walk")
			end
			return true
		end
	end

	if entry.catchUntil and os.clock() >= entry.catchUntil then
		entry.catchUntil = nil
		CreatureKit.pose(entry, "walk")
	end

	if not (target and targetPosition) then
		return false
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude
	local armed = entry.axeFlight == nil

	if distance <= Tuning.chopRange and now >= (entry.nextChopAt or 0) then
		entry.nextChopAt = now + Tuning.chopCooldown
		entry.move = { kind = "chop", hitAt = now + Tuning.chopWindup, untilAt = now + Tuning.chopSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "chop")
		return true
	end

	if armed and distance <= Tuning.whirlRange and now >= (entry.nextWhirlAt or 0) then
		entry.nextWhirlAt = now + Tuning.whirlCooldown
		entry.move = { kind = "windup", untilAt = now + Tuning.whirlWindup }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "windup")
		CreatureKit.fx("roar", entry.model, Tuning.whirlWindup)
		return true
	end

	if armed and distance >= Tuning.throwMin and distance <= Tuning.throwRange and now >= (entry.nextThrowAt or 0)
		and not CreatureKit.firstBlock(position + Vector3.new(0, 2, 0), targetPosition, 1) then
		entry.nextThrowAt = now + Tuning.throwCooldown
		entry.move = { kind = "throw", at = now + Tuning.throwWindup, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "throw")
		return true
	end

	if not entry.catchUntil then
		CreatureKit.pose(entry, "walk")
	end
	if distance <= Tuning.chopRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

function Trait.finish(entry)
	if entry.axeFlight then
		entry.axeFlight.connection:Disconnect()
		entry.axeFlight.axe:Destroy()
		entry.axeFlight = nil
	end
end

return Trait
