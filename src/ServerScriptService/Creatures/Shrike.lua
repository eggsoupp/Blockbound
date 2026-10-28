--[[
	Yellow-billed Shrike - a big bird that never comes at you straight. It
	circles above you, banking into the turn, and every few seconds cries out,
	folds and swoops: down through where you are standing and back up the
	far side into its circle.

	THE SWOOP is a curve fixed the moment it starts - through the point you
	were standing on at the cry - so the cry is the tell and moving off that
	spot is the dodge. Only the swoop hurts; circling overhead it is out of
	reach of a sword and harmless, which is also when it is easiest to see
	coming.

	No rig: the wings are held out, and the flight is in the banking and
	pitching of the whole body.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	orbitRadius = 14,
	-- Low enough to stay in a third-person camera's view.
	orbitHeight = 8,
	-- Radians a second round the circle, and how fast it flies to keep up.
	orbitSpeed = 0.6,
	flySpeed = 22,
	-- How hard it leans into the turn, in radians.
	bank = 0.55,
	-- Seconds per beat-and-glide cycle, and the share of it spent beating.
	wingCycle = 3.2,
	beatShare = 0.55,

	swoopEvery = NumberRange.new(3.5, 5.5),
	swoopRange = 40,
	crySeconds = 0.45,
	swoopSeconds = 1.15,
	swoopDamage = 14,
}

local Trait = {}
Trait.Tuning = Tuning

local function nextSwoop(now: number): number
	local r = Tuning.swoopEvery
	return now + r.Min + math.random() * (r.Max - r.Min)
end

-- A quadratic curve from `a` to `c` that passes through `through` halfway.
local function curve(a: Vector3, through: Vector3, c: Vector3, t: number): (Vector3, Vector3)
	local control = through * 2 - (a + c) * 0.5
	local u = 1 - t
	local point = a * (u * u) + control * (2 * u * t) + c * (t * t)
	local tangent = (control - a) * (2 * u) + (c - control) * (2 * t)
	return point, tangent
end

local function circle(entry, targetPosition: Vector3, position: Vector3, dt: number, now: number)
	entry.orbitAngle = (entry.orbitAngle or math.random() * math.pi * 2) + Tuning.orbitSpeed * entry.orbitTurn * dt

	local spot = targetPosition
		+ Vector3.new(math.cos(entry.orbitAngle), 0, math.sin(entry.orbitAngle)) * Tuning.orbitRadius
		+ Vector3.new(0, Tuning.orbitHeight + math.sin(now * 0.9) * 1.2, 0)
	local delta = spot - position
	local stride = math.min(Tuning.flySpeed * dt, delta.Magnitude)
	local moved = if delta.Magnitude > 1e-3 then position + delta.Unit * stride else position

	-- Facing along the circle, leaning in.
	local tangent = Vector3.new(-math.sin(entry.orbitAngle), 0, math.cos(entry.orbitAngle)) * entry.orbitTurn
	local lean = CFrame.Angles(0, 0, -Tuning.bank * entry.orbitTurn)
	CreatureKit.place(entry, moved - Vector3.new(0, entry.feetOffset, 0), tangent, lean)

	-- A few beats, then a glide, like a real bird working a thermal; always
	-- beating while it climbs back up to its circle.
	local climbing = delta.Y > 2
	local beating = climbing or (now + entry.wingPhase) % Tuning.wingCycle < Tuning.wingCycle * Tuning.beatShare
	CreatureKit.wings(entry, if beating then "flap" else "glide")
end

function Trait.start(entry)
	entry.orbitTurn = if math.random() < 0.5 then 1 else -1
	entry.nextSwoopAt = nextSwoop(os.clock())
	entry.wingPhase = math.random() * Tuning.wingCycle
	CreatureKit.wings(entry, "flap")
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	local swoop = entry.swoop

	if swoop then
		if swoop.phase == "cry" then
			-- Hangs, flared, looking down at its mark.
			CreatureKit.place(entry, position - Vector3.new(0, entry.feetOffset, 0), swoop.through - position)
			if now >= swoop.endsAt then
				swoop.phase = "dive"
				CreatureKit.wings(entry, "fold")
				swoop.startedAt = now
				swoop.from = position
				local across = CreatureKit.flat(swoop.through - position)
				swoop.to = swoop.through + across * Tuning.orbitRadius + Vector3.new(0, Tuning.orbitHeight, 0)
				CreatureKit.fx("dive", entry.model, Tuning.swoopSeconds)
			end
			return true
		end

		local t = math.min(1, (now - swoop.startedAt) / Tuning.swoopSeconds)
		local point, tangent = curve(swoop.from, swoop.through, swoop.to, t)
		CreatureKit.place(entry, point - Vector3.new(0, entry.feetOffset, 0), tangent)
		CreatureKit.service().touch(entry, point, Tuning.swoopDamage)

		if t >= 1 then
			entry.swoop = nil
			entry.nextSwoopAt = nextSwoop(now)
			-- Pick the circle up from where the swoop came out.
			if targetPosition then
				local away = point - targetPosition
				entry.orbitAngle = math.atan2(away.Z, away.X)
			end
		end
		return true
	end

	if not (target and targetPosition) then
		return false
	end

	if now >= (entry.nextSwoopAt or 0) and (targetPosition - position).Magnitude <= Tuning.swoopRange then
		entry.swoop = { phase = "cry", endsAt = now + Tuning.crySeconds, through = targetPosition }
		CreatureKit.wings(entry, "spread")
		CreatureKit.fx("flare", entry.model, Color3.fromRGB(255, 220, 120))
		return true
	end

	circle(entry, targetPosition, position, dt, now)
	return true
end

return Trait
