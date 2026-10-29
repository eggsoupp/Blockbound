--[[
	Axe Golem - a wooden construct of the Desert holding two pole-axes out at
	arm's length. Head, arms, both pole-axes and legs are jointed
	(Shared.Enemies.CreatureRigs.AxeGolem).

	CYCLONE (within `cycloneRange`). It lays both poles out level and spins,
	whirling toward you for `cycloneSeconds`, cutting everyone within
	`cycloneRadius` every `cycloneInterval`. Then it has to stop, swaying, for
	`dizzySeconds` - the time to hit it.

	DOUBLE CHOP (within `chopRange`). Both poles tipped back and brought over
	and down in front of it, the top axes biting the ground.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 5.5,
	slideStep = 2,

	cycloneRange = 11,
	cycloneWindup = 0.6,
	cycloneSeconds = 2,
	cycloneRadius = 4.5,
	cycloneInterval = 0.3,
	cycloneDamage = 3,
	cycloneTurn = 16,
	cycloneDrift = 6,
	cycloneCooldown = 8,
	dizzySeconds = 1.8,

	chopRange = 4.5,
	chopReach = 3.2,
	chopWindup = 0.55,
	chopSeconds = 1.1,
	chopDamage = 14,
	chopCooldown = 2.2,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "AxeGolem")
	entry.nextCycloneAt = os.clock() + 2
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

local function dizzy(entry, now: number)
	entry.move = { kind = "dizzy", untilAt = now + Tuning.dizzySeconds }
	CreatureKit.pose(entry, "dizzy")
	CreatureKit.fx("stunned", entry.model, Tuning.dizzySeconds)
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		if entry.move and entry.move.kind == "cyclone" then
			dizzy(entry, now)
			return false
		end
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "windup" then
			if now >= move.at then
				entry.move = { kind = "cyclone", untilAt = now + Tuning.cycloneSeconds, nextCutAt = now, angle = 0 }
				CreatureKit.pose(entry, "cyclone")
				CreatureKit.fx("whirl", entry.model, Tuning.cycloneSeconds, Tuning.cycloneRadius)
			end
			return true
		elseif move.kind == "cyclone" then
			move.angle += Tuning.cycloneTurn * dt
			local facing = Vector3.new(math.sin(move.angle), 0, math.cos(move.angle))
			local drift = if targetPosition then CreatureKit.flat(targetPosition - position) else Vector3.zero
			if not CreatureKit.slide(entry, drift * Tuning.cycloneDrift * dt, facing, nil, Tuning.slideStep) then
				CreatureKit.place(entry, CreatureKit.feet(entry), facing)
			end
			if now >= move.nextCutAt then
				move.nextCutAt = now + Tuning.cycloneInterval
				CreatureKit.hurtSphere(entry, CreatureKit.feet(entry) + Vector3.new(0, 2, 0), Tuning.cycloneRadius, Tuning.cycloneDamage, 1)
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
		elseif move.kind == "chop" then
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
		end
	end

	if not (target and targetPosition) then
		CreatureKit.pose(entry, "walk")
		return false
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

	if distance <= Tuning.chopRange and now >= (entry.nextChopAt or 0) then
		entry.nextChopAt = now + Tuning.chopCooldown
		entry.move = { kind = "chop", hitAt = now + Tuning.chopWindup, untilAt = now + Tuning.chopSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "chop")
		return true
	end

	if distance <= Tuning.cycloneRange and now >= entry.nextCycloneAt then
		entry.nextCycloneAt = now + Tuning.cycloneCooldown
		entry.move = { kind = "windup", at = now + Tuning.cycloneWindup }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "cyclone")
		CreatureKit.fx("roar", entry.model, Tuning.cycloneWindup)
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.chopRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
