--[[
	Pentasaurus - a young horned dinosaur of the desert, jointed head, tail
	and legs (Shared.Enemies.CreatureRigs.Pentasaurus).

	THE CHARGE (`chargeMin` to `chargeRange`, with a clear line). It stops,
	lowers its head and paws the ground for `pawSeconds` - snorting dust, the
	tell - then charges along the line it was facing when the pawing ended.
	It cannot turn once it goes: step aside and it thunders past. Anyone it
	runs into takes `chargeDamage` (once per charge).

	THE CRASH. A charge that runs into a block too high to slide over stops
	dead, and it stands STUNNED for `stunSeconds`, head shaking, stars
	circling - the time to hit it. Baiting it into a wall is the play.

	GORE (within `goreRange`). Up close it tosses its horns instead.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 6,
	slideStep = 2,

	chargeRange = 40,
	chargeMin = 9,
	pawSeconds = 0.95,
	chargeSpeed = 34,
	chargeSeconds = 1.6,
	chargeDamage = 18,
	chargeCooldown = 5,
	-- A charge only stops at a step this high; it ploughs over anything lower.
	chargeStep = 2.2,

	stunSeconds = 1.8,

	goreRange = 5,
	goreSeconds = 0.4,
	goreDamage = 11,
	goreCooldown = 1.5,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "Pentasaurus")
	CreatureKit.pose(entry, "walk")
end

local function crash(entry, now: number)
	entry.move = { kind = "stunned", untilAt = now + Tuning.stunSeconds }
	entry.nextChargeAt = now + Tuning.chargeCooldown
	CreatureKit.pose(entry, "stunned")
	CreatureKit.fx("stunned", entry.model, Tuning.stunSeconds)
	local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
	CreatureKit.fx("slam", CreatureKit.feet(entry) + look * 3, 5)
end

local function stepCharge(entry, move, dt: number, now: number)
	if now < move.goAt then
		return
	end
	if not move.going then
		move.going = true
		move.hit = {}
		CreatureKit.pose(entry, "charge")
		CreatureKit.fx("dive", entry.model, Tuning.chargeSeconds)
	end

	if not CreatureKit.slide(entry, move.direction * Tuning.chargeSpeed * dt, move.direction, nil, Tuning.chargeStep) then
		crash(entry, now)
		return
	end

	local horns = CreatureKit.feet(entry) + move.direction * 3 + Vector3.new(0, entry.height * 0.5, 0)
	for _, player in ipairs(CreatureKit.playersAlong(horns, horns, 3.5)) do
		if not move.hit[player] then
			move.hit[player] = true
			CreatureKit.hurt(entry, player, Tuning.chargeDamage)
		end
	end

	if now >= move.goAt + Tuning.chargeSeconds then
		entry.move = nil
		entry.nextChargeAt = now + Tuning.chargeCooldown
		CreatureKit.pose(entry, "walk")
	end
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "charge" then
			-- Still pawing: it keeps turning to face you until it goes.
			if not move.going and targetPosition then
				move.direction = CreatureKit.flat(targetPosition - position)
				CreatureKit.place(entry, CreatureKit.feet(entry), move.direction)
			end
			stepCharge(entry, move, dt, now)
		elseif now >= move.untilAt then
			entry.move = nil
			CreatureKit.pose(entry, "walk")
		elseif move.kind == "gore" and not move.hit and now >= move.hitAt then
			move.hit = true
			local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
			CreatureKit.service().touch(entry, CreatureKit.feet(entry) + look * 3 + Vector3.new(0, 2, 0), Tuning.goreDamage)
		end
		return true
	end

	if not (target and targetPosition) then
		CreatureKit.pose(entry, "walk")
		return false
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

	if distance <= Tuning.goreRange and now >= (entry.nextGoreAt or 0) then
		entry.nextGoreAt = now + Tuning.goreCooldown
		entry.move = { kind = "gore", hitAt = now + Tuning.goreSeconds * 0.4, untilAt = now + Tuning.goreSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "gore")
		return true
	end

	if distance >= Tuning.chargeMin and distance <= Tuning.chargeRange and now >= (entry.nextChargeAt or 0)
		and not CreatureKit.firstBlock(position + Vector3.new(0, 1, 0), targetPosition, 1) then
		-- Aim now; the direction is fixed when the pawing ends.
		entry.move = { kind = "charge", goAt = now + Tuning.pawSeconds, direction = toward }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "paw")
		CreatureKit.fx("snort", entry.model, Tuning.pawSeconds)
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.goreRange * 0.8 then
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
