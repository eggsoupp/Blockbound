--[[
	Cat Monk - a robed cat of the Hallow with a long staff, and very hard to
	hit. Head, arms, staff and legs are jointed (Shared.Enemies.CreatureRigs.
	CatMonk).

	EVASION. A blow struck while it is not itself attacking is dodged
	`dodgeChance` of the time: no damage, and it slips `dodgeStep` studs aside
	in a blur. Hit it while it strikes and it cannot.

	FLURRY (within `flurryRange`). Three quick staff jabs, at `jabTimes`, each
	`jabDamage`.

	SWEEP (within `sweepRange`, every `sweepCooldown`). A crouch and the staff
	spun flat round low: everyone around it is hurt for `sweepDamage` and
	tripped - slowed to `tripSlow` for `tripSeconds`.
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 8,
	slideStep = 2,

	dodgeChance = 0.35,
	dodgeStep = 3,
	dodgeCooldown = 0.8,

	flurryRange = 4.5,
	jabReach = 4,
	jabTimes = { 0.2, 0.4, 0.6 },
	flurrySeconds = 0.85,
	jabDamage = 4,
	flurryCooldown = 1.8,

	sweepRange = 4,
	sweepRadius = 4.5,
	sweepWindup = 0.3,
	sweepSeconds = 0.9,
	sweepDamage = 6,
	tripSlow = 0.3,
	tripSeconds = 1.2,
	sweepCooldown = 6,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "CatMonk")
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

function Trait.guard(entry)
	local now = os.clock()
	if entry.move or entry.state ~= "Grounded" or now < (entry.nextDodgeAt or 0) or math.random() >= Tuning.dodgeChance then
		return 1
	end
	entry.nextDodgeAt = now + Tuning.dodgeCooldown
	-- A step to whichever side is clear.
	local feet = CreatureKit.feet(entry)
	local across = look(entry):Cross(Vector3.yAxis)
	for _, side in ipairs({ 1, -1 }) do
		local spot = feet + across * side * Tuning.dodgeStep
		local ground = CreatureKit.service().groundAt(spot.X, spot.Z, feet.Y)
		if math.abs(ground - feet.Y) <= 2 and not CreatureKit.solidAt(Vector3.new(spot.X, ground + entry.height * 0.5, spot.Z)) then
			CreatureKit.fx("poof", feet + Vector3.new(0, entry.height * 0.5, 0))
			CreatureKit.place(entry, Vector3.new(spot.X, ground, spot.Z), look(entry))
			break
		end
	end
	entry.move = { kind = "dodge", untilAt = now + 0.3 }
	CreatureKit.pose(entry, "dodge")
	return 0
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "flurry" then
			local due = Tuning.jabTimes[move.done + 1]
			if due and now >= move.startedAt + due then
				move.done += 1
				local from = CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.4, 0)
				for _, player in ipairs(CreatureKit.playersAlong(from, from + look(entry) * Tuning.jabReach, 1.8)) do
					CreatureKit.hurt(entry, player, Tuning.jabDamage)
				end
			end
			if now >= move.startedAt + Tuning.flurrySeconds then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "sweep" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local feet = CreatureKit.feet(entry)
				for _, player in ipairs(Players:GetPlayers()) do
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp and Vector3.new(hrp.Position.X - feet.X, 0, hrp.Position.Z - feet.Z).Magnitude <= Tuning.sweepRadius
						and math.abs(hrp.Position.Y - feet.Y - 2) <= 3 then
						CreatureKit.hurt(entry, player, Tuning.sweepDamage)
						CreatureKit.slow(player, Tuning.tripSlow, Tuning.tripSeconds)
					end
				end
				CreatureKit.fx("whirl", entry.model, 0.35, Tuning.sweepRadius)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "dodge" then
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

	if distance <= Tuning.sweepRange and now >= (entry.nextSweepAt or 0) then
		entry.nextSweepAt = now + Tuning.sweepCooldown
		entry.nextFlurryAt = math.max(entry.nextFlurryAt or 0, now + 1)
		entry.move = { kind = "sweep", hitAt = now + Tuning.sweepWindup, untilAt = now + Tuning.sweepSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "sweep")
		return true
	end

	if distance <= Tuning.flurryRange and now >= (entry.nextFlurryAt or 0) then
		entry.nextFlurryAt = now + Tuning.flurryCooldown
		entry.move = { kind = "flurry", startedAt = now, done = 0 }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "flurry")
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.flurryRange * 0.6 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
