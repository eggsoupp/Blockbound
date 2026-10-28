--[[
	Cobra - a desert snake that slithers after you along the ground, swaying,
	and when you come within reach rears back and strikes.

	It moves by sliding over the surface rather than hopping. Anything taller
	than half a block, or a drop, is handed to the ordinary hop movement, so it
	still gets up a step and down a ledge - and a knockback still throws it.

	THE STRIKE: it rears back for `windupSeconds` (the tell), lunges its
	length forward along a line fixed at the start of the rear, holds, and
	recoils. Only the lunge hurts. Backing out of reach during the rear is the
	answer; so is hitting it while it recoils.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	slitherSpeed = 6.5,
	-- Studs of rise or fall it will slide over; more is a hop.
	slideStep = 2,

	strikeRange = 8,
	windupSeconds = 0.5,
	lungeSeconds = 0.14,
	holdSeconds = 0.2,
	recoilSeconds = 0.35,
	reach = 5.5,
	cooldown = 2.2,
	strikeDamage = 13,

	-- The sway, in radians of yaw, and how fast.
	sway = 0.32,
	swayRate = 2.4,
	-- How far it leans: back on the rear, forward on the lunge.
	rearBack = 0.3,
	lungeLean = 0.35,
}

local Trait = {}
Trait.Tuning = Tuning

local function sway(now: number): CFrame
	return CFrame.Angles(0, math.sin(now * Tuning.swayRate) * Tuning.sway, 0)
end

function Trait.pose(entry, now)
	CreatureKit.tilt(entry, sway(now))
end

local function strike(entry, now: number): boolean
	local s = entry.strike
	local elapsed = now - s.startedAt
	local w, l, h, r = Tuning.windupSeconds, Tuning.lungeSeconds, Tuning.holdSeconds, Tuning.recoilSeconds

	local reach, lean = 0, 0
	if elapsed < w then
		local k = elapsed / w
		reach, lean = -0.6 * k, -Tuning.rearBack * k
	elseif elapsed < w + l then
		local k = (elapsed - w) / l
		reach, lean = Tuning.reach * k, Tuning.lungeLean * k
		if not s.announced then
			s.announced = true
			CreatureKit.fx("strike", entry.model, l + h)
		end
	elseif elapsed < w + l + h then
		reach, lean = Tuning.reach, Tuning.lungeLean
	elseif elapsed < w + l + h + r then
		local k = 1 - (elapsed - w - l - h) / r
		reach, lean = Tuning.reach * k, Tuning.lungeLean * k
	else
		entry.strike = nil
		entry.nextStrikeAt = now + Tuning.cooldown
		CreatureKit.place(entry, s.base, s.direction)
		return true
	end

	local feet = s.base + s.direction * reach
	CreatureKit.place(entry, feet, s.direction, CFrame.Angles(-lean, 0, 0))

	-- The bite is at the head: up the body, at the front of where it reached.
	if elapsed >= w and elapsed < w + l + h then
		local head = feet + s.direction * (entry.bodyRadius or 1.5) + Vector3.new(0, entry.height * 0.6, 0)
		CreatureKit.service().touch(entry, head, Tuning.strikeDamage)
	end
	return true
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.strike = nil
		return false
	end

	if entry.strike then
		return strike(entry, now)
	end

	if not (target and targetPosition) then
		return false
	end

	local feet = CreatureKit.feet(entry)
	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

	if distance <= Tuning.strikeRange and now >= (entry.nextStrikeAt or 0) then
		entry.strike = { startedAt = now, base = feet, direction = toward }
		CreatureKit.fx("flare", entry.model, Color3.fromRGB(255, 200, 60))
		return strike(entry, now)
	end

	-- Close enough already: hold ground and sway, facing the target.
	if distance <= Tuning.strikeRange then
		CreatureKit.place(entry, feet, toward, sway(now))
		return true
	end

	local ahead = feet + toward * Tuning.slitherSpeed * dt
	local ground = CreatureKit.service().groundAt(ahead.X, ahead.Z, feet.Y)
	if math.abs(ground - feet.Y) > Tuning.slideStep then
		-- A step or a drop: the hop movement climbs it.
		return false
	end

	local moved = Vector3.new(ahead.X, ground, ahead.Z)
	CreatureKit.place(entry, moved, toward, sway(now))
	CreatureKit.service().touch(entry, moved + Vector3.new(0, entry.height * 0.5, 0))
	entry.groundY = ground
	return true
end

return Trait
