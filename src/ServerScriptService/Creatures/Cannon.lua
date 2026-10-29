--[[
	Cannon - an abandoned cannon on the Plains that still works, and still
	shoots at whoever comes near. It never moves; it turns on its carriage
	(`turnRate`) to bear on you. Only the barrel is jointed
	(Shared.Enemies.CreatureRigs.Cannon).

	CANNONBALL (`fireMin` to `fireRange`, once it is facing you within
	`fireArc`). The barrel comes up for `aimSeconds`, then it fires a ball on
	a high arc at where you stood; it bursts where it lands, hurting everyone
	within `blastRadius`. Keep moving.

	UP CLOSE (inside `fireMin`) it cannot bring the barrel to bear at all -
	the place to be.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	turnRate = 1.4,
	fireRange = 42,
	fireMin = 7,
	fireArc = 12,
	aimSeconds = 0.8,
	fireCooldown = 3.2,
	-- Time in the air, at the longest range; shorter shots fly shorter.
	flightSeconds = 1.3,
	gravity = 70,
	blastRadius = 3.6,
	blastDamage = 15,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "Cannon")
	entry.nextFireAt = os.clock() + 1.5
	CreatureKit.pose(entry, "idle")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

local function fire(entry, aim: Vector3)
	local feet = CreatureKit.feet(entry)
	local muzzle = feet + Vector3.new(0, entry.height * 0.85, 0) + look(entry) * 3.6
	local offset = aim - muzzle
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local t = math.max(0.5, Tuning.flightSeconds * flat.Magnitude / Tuning.fireRange)
	CreatureKit.fx("muzzle", muzzle, look(entry))
	CreatureKit.projectile({
		origin = muzzle,
		velocity = Vector3.new(offset.X / t, (offset.Y + 0.5 * Tuning.gravity * t * t) / t, offset.Z / t),
		gravity = Tuning.gravity,
		hitRadius = 1.5,
		maxLife = t + 1,
		style = "iron",
		onHit = function(point)
			CreatureKit.hurtSphere(entry, point + Vector3.new(0, 1, 0), Tuning.blastRadius, Tuning.blastDamage, 0.4)
			CreatureKit.fx("slam", point, Tuning.blastRadius)
		end,
	})
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	local move = entry.move
	if move then
		if move.kind == "aim" then
			if now >= move.at then
				fire(entry, targetPosition or move.aim)
				entry.move = { kind = "fire", untilAt = now + 0.6 }
				CreatureKit.pose(entry, "fire")
			end
		elseif move.kind == "fire" and now >= move.untilAt then
			entry.move = nil
			CreatureKit.pose(entry, "idle")
		end
		return true
	end

	-- It never walks, hops or falls: everything happens where it stands.
	if not (target and targetPosition) then
		return true
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude
	local facing = look(entry)

	-- Turn toward the target, no faster than the carriage can.
	local angle = math.atan2(facing:Cross(toward).Y, facing:Dot(toward))
	local turn = math.clamp(angle, -Tuning.turnRate * dt, Tuning.turnRate * dt)
	local turned = CFrame.Angles(0, turn, 0):VectorToWorldSpace(facing)
	CreatureKit.place(entry, CreatureKit.feet(entry), turned)

	if distance >= Tuning.fireMin and distance <= Tuning.fireRange and now >= entry.nextFireAt
		and math.abs(angle) <= math.rad(Tuning.fireArc) then
		entry.nextFireAt = now + Tuning.fireCooldown
		entry.move = { kind = "aim", at = now + Tuning.aimSeconds, aim = targetPosition }
		CreatureKit.pose(entry, "aim")
	end
	return true
end

return Trait
