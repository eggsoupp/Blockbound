--[[
	Lasereye - a heavy swamp blob with one great red eye. It shuffles after
	you in short, slow hops, and from range it stops, charges and fires a
	laser.

	THE DODGE. The charge tracks you for most of its length and then LOCKS:
	for the last `lockSeconds` the aim is fixed, the telegraph stops following
	you, and stepping sideways out of the line is the answer. The beam needs
	a clear line through the blocks when the charge starts, and it stops at
	the first block in its way when it fires - so cover works too.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	range = 42,
	minRange = 7,

	chargeSeconds = 1.25,
	lockSeconds = 0.45,
	fireSeconds = 0.35,
	cooldown = 4.5,

	damage = 18,
	-- How far from the beam's centre line still counts as standing in it.
	beamRadius = 1.6,

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

local function cancel(entry, now)
	entry.laser = nil
	entry.nextLaserAt = now + Tuning.cooldown * 0.5
	CreatureKit.fx("cancel", entry.model)
end

local function fire(entry, laser)
	local eye = eyePosition(entry)
	local direction = laser.aim - eye
	if direction.Magnitude < 1e-3 then
		direction = entry.facing
	end
	local finish = eye + direction.Unit * (Tuning.range + 8)

	-- Cover stops it: the beam ends at the first block it meets.
	finish = CreatureKit.firstBlock(eye, finish, 1) or finish

	for _, player in ipairs(CreatureKit.playersAlong(eye, finish, Tuning.beamRadius)) do
		CreatureKit.hurt(entry, player, Tuning.damage)
	end

	CreatureKit.fx("laser", entry.model, eye, finish, Tuning.fireSeconds)
end

function Trait.step(entry, target, targetPosition, position, _dt, now)
	local laser = entry.laser

	if laser then
		-- Knocked off its feet: the charge is lost.
		if entry.state ~= "Grounded" then
			cancel(entry, now)
			return false
		end

		if laser.phase == "charge" then
			if now < laser.lockAt then
				if targetPosition then
					laser.aim = targetPosition
					CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(targetPosition - position))
				end
			elseif not laser.locked then
				laser.locked = true
				CreatureKit.fx("lock", entry.model, laser.aim)
			end

			if now >= laser.fireAt then
				fire(entry, laser)
				laser.phase = "fire"
				laser.doneAt = now + Tuning.fireSeconds
			end
			return true
		end

		if now >= laser.doneAt then
			entry.laser = nil
			entry.nextLaserAt = now + Tuning.cooldown
		end
		return true
	end

	if not (target and targetPosition) or entry.state ~= "Grounded" then
		return false
	end
	if now < (entry.nextLaserAt or 0) then
		return false
	end

	local distance = (targetPosition - position).Magnitude
	if distance > Tuning.range or distance < Tuning.minRange then
		return false
	end

	CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(targetPosition - position))
	local eye = eyePosition(entry)
	if CreatureKit.firstBlock(eye, targetPosition, 1) then
		-- No line on it. Try again shortly rather than every tick.
		entry.nextLaserAt = now + 0.5
		return false
	end

	entry.laser = {
		phase = "charge",
		aim = targetPosition,
		lockAt = now + Tuning.chargeSeconds - Tuning.lockSeconds,
		fireAt = now + Tuning.chargeSeconds,
	}
	CreatureKit.fx(
		"charge", entry.model, eye, Tuning.chargeSeconds, Tuning.chargeSeconds - Tuning.lockSeconds, target.Character
	)
	return true
end

function Trait.finish(entry)
	if entry.laser then
		CreatureKit.fx("cancel", entry.model)
	end
end

return Trait
