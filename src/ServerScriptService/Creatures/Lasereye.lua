--[[
	Lasereye - a heavy swamp blob with one great red eye. It lumbers after you
	in slow, high hops (high enough to clear a block), and its eye is the
	threat. Two beams, chosen by range:

	SWEEP (within `sweepRange`). It stares, the eye gathers, and a beam rakes
	the ground at ANKLE height across an arc that passes through where you
	stand, its whole body turning with it. The beam is low on purpose: jump
	it as it comes past. Blocks stop it, so cover works too. Each sweep can
	hit a player once.

	LANCE (further out). A tracked shot: the aim follows you for most of the
	charge, then LOCKS for the last `lockSeconds` - the telegraph line stops
	following you and stepping off it is the dodge. It fires at chest height
	and hits harder, and also stops at the first block.

	The server decides every beam and every hit; StarterPlayerScripts.
	CreatureFX draws them from the same numbers.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	minRange = 4,
	sweepRange = 24,
	lanceRange = 46,
	cooldown = 3.6,

	sweepCharge = 0.85,
	sweepSeconds = 1.1,
	-- Degrees either side of you that the rake starts and ends.
	sweepArc = 40,
	sweepLength = 30,
	-- Studs below the target's root that the rake is aimed at: the ankle.
	sweepDrop = 2.6,
	sweepRadius = 1.3,
	sweepDamage = 16,

	lanceCharge = 1.2,
	lockSeconds = 0.45,
	lanceSeconds = 0.45,
	lanceRadius = 1.8,
	lanceDamage = 22,

	-- Where the eye is, as shares of the model: up its height, and out to
	-- the front face from the middle of its depth (1 is the face itself).
	eyeHeight = 0.7,
	eyeForward = 1,
}

local Trait = {}
Trait.Tuning = Tuning

local function eyePosition(entry): Vector3
	local size = entry.model:GetExtentsSize()
	local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
	return CreatureKit.feet(entry) + Vector3.new(0, entry.height * Tuning.eyeHeight, 0)
		+ look * (size.Z * 0.5 * Tuning.eyeForward + 0.3)
end

-- A flat direction turned about the vertical by `degrees`.
local function yaw(direction: Vector3, degrees: number): Vector3
	return (CFrame.Angles(0, math.rad(degrees), 0) * CFrame.new(direction)).Position
end

-- The sweep's direction `t` (0..1) of the way through, pitched down at its mark.
local function sweepDirection(beam, t: number): Vector3
	local eased = t * t * (3 - 2 * t)
	local flat = yaw(beam.base, beam.from + (beam.to - beam.from) * eased)
	return (flat * math.cos(beam.pitch) + Vector3.new(0, math.sin(beam.pitch), 0)).Unit
end

-- The beam from `eye` along `direction`, stopped by the first block.
local function reach(eye: Vector3, direction: Vector3, length: number): Vector3
	local finish = eye + direction * length
	return CreatureKit.firstBlock(eye, finish, 1) or finish
end

local function cancel(entry, now)
	entry.beam = nil
	entry.nextBeamAt = now + Tuning.cooldown * 0.5
	CreatureKit.fx("cancel", entry.model)
end

local function startSweep(entry, targetPosition: Vector3, now: number)
	local eye = eyePosition(entry)
	local mark = targetPosition - Vector3.new(0, Tuning.sweepDrop, 0)
	local offset = mark - eye
	local flat = CreatureKit.flat(offset)
	local side = if math.random() < 0.5 then 1 else -1

	local beam = {
		kind = "sweep",
		eye = eye,
		base = flat,
		pitch = math.atan2(offset.Y, Vector3.new(offset.X, 0, offset.Z).Magnitude),
		from = -Tuning.sweepArc * side,
		to = Tuning.sweepArc * side,
		fireAt = now + Tuning.sweepCharge,
		hit = {},
	}
	entry.beam = beam

	-- The telegraph points where the rake will start.
	local first = sweepDirection(beam, 0)
	CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(first))
	CreatureKit.fx("charge", entry.model, eye, Tuning.sweepCharge, 0, reach(eye, first, Tuning.sweepLength))
end

local function stepSweep(entry, beam, now: number)
	if now < beam.fireAt then
		return
	end

	if not beam.started then
		beam.started = true
		beam.startedAt = now
		CreatureKit.fx(
			"sweep", entry.model, beam.eye, beam.base, beam.pitch,
			beam.from, beam.to, Tuning.sweepSeconds, Tuning.sweepLength
		)
	end

	local t = math.min(1, (now - beam.startedAt) / Tuning.sweepSeconds)
	local direction = sweepDirection(beam, t)
	local finish = reach(beam.eye, direction, Tuning.sweepLength)

	-- Its whole body turns with the eye.
	CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(direction))

	for _, player in ipairs(CreatureKit.playersAlong(beam.eye, finish, Tuning.sweepRadius, Tuning.sweepDrop)) do
		if not beam.hit[player] then
			beam.hit[player] = true
			CreatureKit.hurt(entry, player, Tuning.sweepDamage)
		end
	end

	if t >= 1 then
		entry.beam = nil
		entry.nextBeamAt = now + Tuning.cooldown
	end
end

local function startLance(entry, target, targetPosition: Vector3, now: number)
	local eye = eyePosition(entry)
	entry.beam = {
		kind = "lance",
		aim = targetPosition,
		lockAt = now + Tuning.lanceCharge - Tuning.lockSeconds,
		fireAt = now + Tuning.lanceCharge,
	}
	CreatureKit.fx("charge", entry.model, eye, Tuning.lanceCharge, Tuning.lanceCharge - Tuning.lockSeconds, target.Character)
end

local function stepLance(entry, beam, targetPosition: Vector3?, position: Vector3, now: number)
	if beam.phase == "fire" then
		if now >= beam.doneAt then
			entry.beam = nil
			entry.nextBeamAt = now + Tuning.cooldown
		end
		return
	end

	if now < beam.lockAt then
		if targetPosition then
			beam.aim = targetPosition
			CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(targetPosition - position))
		end
	elseif not beam.locked then
		beam.locked = true
		CreatureKit.fx("lock", entry.model, beam.aim)
	end

	if now >= beam.fireAt then
		local eye = eyePosition(entry)
		local direction = beam.aim - eye
		direction = if direction.Magnitude > 1e-3 then direction.Unit else entry.facing
		local finish = reach(eye, direction, Tuning.lanceRange + 8)

		for _, player in ipairs(CreatureKit.playersAlong(eye, finish, Tuning.lanceRadius)) do
			CreatureKit.hurt(entry, player, Tuning.lanceDamage)
		end

		CreatureKit.fx("laser", entry.model, eye, finish, Tuning.lanceSeconds)
		beam.phase = "fire"
		beam.doneAt = now + Tuning.lanceSeconds
	end
end

function Trait.step(entry, target, targetPosition, position, _dt, now)
	local beam = entry.beam

	if beam then
		-- Knocked off its feet: the beam is lost.
		if entry.state ~= "Grounded" then
			cancel(entry, now)
			return false
		end
		if beam.kind == "sweep" then
			stepSweep(entry, beam, now)
		else
			stepLance(entry, beam, targetPosition, position, now)
		end
		return true
	end

	if not (target and targetPosition) or entry.state ~= "Grounded" then
		return false
	end
	if now < (entry.nextBeamAt or 0) then
		return false
	end

	local distance = (targetPosition - position).Magnitude
	if distance > Tuning.lanceRange or distance < Tuning.minRange then
		return false
	end

	-- Needs a line on you to start; tries again shortly rather than every tick.
	CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(targetPosition - position))
	if CreatureKit.firstBlock(eyePosition(entry), targetPosition, 1) then
		entry.nextBeamAt = now + 0.5
		return false
	end

	if distance <= Tuning.sweepRange then
		startSweep(entry, targetPosition, now)
	else
		startLance(entry, target, targetPosition, now)
	end
	return true
end

function Trait.finish(entry)
	if entry.beam then
		CreatureKit.fx("cancel", entry.model)
	end
end

return Trait
