--[[
	Green Wasp - flies at you like any flyer, buzzing, and from a few blocks
	away backs off, hangs there, and darts in to sting.

	THE DART is a straight line, aimed once at the end of the hang and never
	steered, so the hang is the tell and a sidestep is the answer. It flies
	on past where you were by `overshoot`, then needs `recoverSeconds` to
	gather itself before chasing again - the window to hit it back.

	It has no rig. The buzz is a small fast jitter of its whole body; the dart
	pitches it along its own line of flight.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	-- From any closer range: hovering over your head it still backs off and
	-- darts rather than just bumping into you.
	diveRange = 22,
	minRange = 0,

	windupSeconds = 0.55,
	-- Studs a second it backs away while hanging.
	backoffSpeed = 5,

	diveSpeed = 50,
	overshoot = 5,
	maxDiveSeconds = 0.8,
	recoverSeconds = 0.7,
	cooldown = 3,

	stingDamage = 12,

	-- The buzz: radians of jitter, and how fast.
	buzzPitch = 0.05,
	buzzRoll = 0.09,
	buzzRate = 38,
}

local Trait = {}
Trait.Tuning = Tuning

local function buzz(now: number, scale: number?): CFrame
	local s = scale or 1
	return CFrame.Angles(
		math.sin(now * Tuning.buzzRate) * Tuning.buzzPitch * s,
		0,
		math.sin(now * Tuning.buzzRate * 1.37 + 1) * Tuning.buzzRoll * s
	)
end

-- The wings are separate parts on hinges; StarterPlayerScripts.CreatureFX
-- beats them every frame. Folded only for the dart.
function Trait.start(entry)
	CreatureKit.wings(entry, "flap")
end

function Trait.pose(entry, now)
	CreatureKit.tilt(entry, buzz(now))
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	local dive = entry.dive

	if dive then
		local pivot = position
		if dive.phase == "windup" then
			if targetPosition then
				dive.aim = targetPosition
			end
			local away = CreatureKit.flat(pivot - dive.aim)
			pivot += away * Tuning.backoffSpeed * dt
			CreatureKit.place(entry, pivot - Vector3.new(0, entry.feetOffset, 0), CreatureKit.flat(dive.aim - pivot), buzz(now, 1.8))

			if now >= dive.endsAt then
				-- Aimed at the chest, then committed.
				local line = dive.aim - pivot
				dive.phase = "dart"
				CreatureKit.wings(entry, "fold")
				dive.direction = if line.Magnitude > 1e-3 then line.Unit else entry.facing
				dive.remaining = line.Magnitude + Tuning.overshoot
				dive.endsAt = now + Tuning.maxDiveSeconds
				CreatureKit.fx("dive", entry.model, math.min(Tuning.maxDiveSeconds, dive.remaining / Tuning.diveSpeed) + 0.1)
			end
			return true
		end

		if dive.phase == "dart" then
			local stride = math.min(Tuning.diveSpeed * dt, dive.remaining)
			dive.remaining -= stride
			pivot += dive.direction * stride
			CreatureKit.place(entry, pivot - Vector3.new(0, entry.feetOffset, 0), dive.direction)
			CreatureKit.service().touch(entry, pivot, Tuning.stingDamage)

			if dive.remaining <= 0 or now >= dive.endsAt then
				dive.phase = "recover"
				CreatureKit.wings(entry, "flap")
				dive.endsAt = now + Tuning.recoverSeconds
			end
			return true
		end

		-- Recovering: drifting, levelling out, harmless.
		pivot += Vector3.new(0, 2 * dt, 0)
		CreatureKit.place(entry, pivot - Vector3.new(0, entry.feetOffset, 0), CreatureKit.flat(entry.facing), buzz(now, 0.5))
		if now >= dive.endsAt then
			entry.dive = nil
			entry.nextDiveAt = now + Tuning.cooldown
		end
		return true
	end

	if not (target and targetPosition) or now < (entry.nextDiveAt or 0) then
		return false
	end

	local distance = (targetPosition - position).Magnitude
	if distance > Tuning.diveRange or distance < Tuning.minRange then
		return false
	end

	entry.dive = { phase = "windup", aim = targetPosition, endsAt = now + Tuning.windupSeconds }
	CreatureKit.fx("flare", entry.model, Color3.fromRGB(190, 255, 90))
	return true
end

return Trait
