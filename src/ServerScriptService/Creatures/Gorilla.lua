--[[
	Gorilla - a heavy brute of the plains. It knuckle-walks after you,
	steady rather than fast, and its arms, legs and head are jointed
	(Shared.Enemies.CreatureRigs.Gorilla).

	CHEST POUND, then SLAM (within `slamRange`). It stops and beats its chest
	for `poundSeconds` - loud, unmistakable, the time to get clear - then
	leaps at where you are, arms overhead, and drives both fists into the
	ground. The landing is a shockwave: everyone within `slamRadius` takes
	damage, more the closer they are. The leap is the hop movement's lunge,
	so it lands where the arc takes it and climbs like any hopper.

	SWIPE (within `swipeRange`). Up close it swings an arm across instead.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 8,
	slideStep = 2,

	slamRange = 22,
	slamMinRange = 6,
	poundSeconds = 1.1,
	slamCooldown = 6,
	slamRadius = 11,
	slamDamage = 24,
	slamEdgeShare = 0.3,
	slamPoseSeconds = 0.45,

	swipeRange = 5,
	swipeWindup = 0.3,
	swipeSeconds = 0.35,
	swipeDamage = 13,
	swipeCooldown = 2,
	-- Seconds after a slam before it may swipe, so the landing is not a combo.
	slamSwipeDelay = 1.2,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "Gorilla")
	CreatureKit.pose(entry, "walk")
end

local function slam(entry, now: number)
	local feet = CreatureKit.feet(entry)
	local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
	local centre = feet + look * 2 + Vector3.new(0, 1.5, 0)
	CreatureKit.hurtSphere(entry, centre, Tuning.slamRadius, Tuning.slamDamage, Tuning.slamEdgeShare)
	CreatureKit.fx("slam", feet + look * 2, Tuning.slamRadius)
	CreatureKit.pose(entry, "slam")
	entry.nextSwipeAt = math.max(entry.nextSwipeAt or 0, now + Tuning.slamSwipeDelay)
	entry.move = { kind = "recover", untilAt = now + Tuning.slamPoseSeconds }
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	-- Airborne: the leap belongs to the hop movement.
	if entry.state ~= "Grounded" then
		if entry.leaping then
			CreatureKit.pose(entry, if entry.state == "Windup" then "pound" else "leap")
			entry.wasAirborne = entry.wasAirborne or entry.state == "Airborne"
		end
		return false
	end

	-- Landed from the leap: the slam.
	if entry.leaping and entry.wasAirborne then
		entry.leaping, entry.wasAirborne = false, false
		slam(entry, now)
		return true
	end

	local move = entry.move
	if move then
		if move.kind == "recover" then
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "swipe" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
				local reachPoint = CreatureKit.feet(entry) + look * 3 + Vector3.new(0, 2.5, 0)
				CreatureKit.service().touch(entry, reachPoint, Tuning.swipeDamage)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		end
	end

	if not (target and targetPosition) then
		CreatureKit.pose(entry, "walk")
		return false
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

	if distance <= Tuning.swipeRange and now >= (entry.nextSwipeAt or 0) then
		entry.nextSwipeAt = now + Tuning.swipeCooldown
		entry.move = { kind = "swipe", hitAt = now + Tuning.swipeWindup, untilAt = now + Tuning.swipeSeconds + Tuning.swipeWindup }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "swipe")
		return true
	end

	-- Pound, then hand a lunge wind-up of the same length to the hop movement.
	if distance >= Tuning.slamMinRange and distance <= Tuning.slamRange and now >= (entry.nextSlamAt or 0) then
		entry.nextSlamAt = now + Tuning.slamCooldown
		entry.leaping, entry.wasAirborne = true, false
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "pound")
		CreatureKit.fx("roar", entry.model, Tuning.poundSeconds)
		entry.state = "Windup"
		entry.pendingLunge = true
		entry.stateUntil = now + Tuning.poundSeconds
		return false
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.swipeRange * 0.8 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	CreatureKit.service().touch(entry, CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.5, 0))
	return true
end

return Trait
