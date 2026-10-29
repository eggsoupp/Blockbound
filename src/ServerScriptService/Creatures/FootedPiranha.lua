--[[
	Footed Piranha - a swamp fish that grew legs and never learned not to
	bite. Small, quick and frail, it comes in little schools: each one
	scurries at you on eight pattering legs, snapping as it closes, and
	LEAPS the last few blocks jaws-first. A missed leap leaves it flopping on
	its side for a moment - the time to swat it. Legs, tail and jaw are
	jointed (Shared.Enemies.CreatureRigs.FootedPiranha).

	The leap is the hop movement's lunge (EnemyConfig's lunge numbers), wound
	up here; landing near you is a bite, landing anywhere else is a flop.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	runSpeed = 13,
	slideStep = 2,
	-- Snapping its jaw within this, before it leaps.
	chompRange = 12,

	leapRange = 9,
	leapWindup = 0.3,
	leapCooldown = 2.2,
	-- Landing further than this from you is a miss, and it flops.
	missDistance = 4,
	flopSeconds = 0.9,
	-- How far it rolls onto its side while flopping.
	flopRoll = 1.25,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "FootedPiranha")
	CreatureKit.pose(entry, "walk")
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		if entry.leaping then
			CreatureKit.pose(entry, if entry.state == "Windup" then "chomp" else "leap")
			entry.wasAirborne = entry.wasAirborne or entry.state == "Airborne"
		end
		return false
	end

	-- Landed: on target it bit (the lunge's contact damage); otherwise a flop.
	if entry.leaping and entry.wasAirborne then
		entry.leaping, entry.wasAirborne = false, false
		local missed = not targetPosition or (targetPosition - position).Magnitude > Tuning.missDistance
		if missed then
			entry.flopUntil = now + Tuning.flopSeconds
			entry.flopSide = if math.random() < 0.5 then 1 else -1
			CreatureKit.pose(entry, "flop")
			CreatureKit.fx("splash", "", CreatureKit.feet(entry) + Vector3.new(0, 0.5, 0), "water")
		end
	end

	if entry.flopUntil then
		if now < entry.flopUntil then
			local k = math.sin((1 - (entry.flopUntil - now) / Tuning.flopSeconds) * math.pi)
			local wobble = math.sin(now * 25) * 0.15
			CreatureKit.place(entry, CreatureKit.feet(entry), nil, CFrame.Angles(0, 0, (Tuning.flopRoll * k + wobble) * entry.flopSide))
			return true
		end
		entry.flopUntil = nil
		CreatureKit.pose(entry, "walk")
	end

	if not (target and targetPosition) then
		CreatureKit.pose(entry, "walk")
		return false
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

	if distance <= Tuning.leapRange and now >= (entry.nextLeapAt or 0) then
		entry.nextLeapAt = now + Tuning.leapCooldown + Tuning.leapWindup
		entry.leaping, entry.wasAirborne = true, false
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "chomp")
		entry.state = "Windup"
		entry.pendingLunge = true
		entry.stateUntil = now + Tuning.leapWindup
		return false
	end

	CreatureKit.pose(entry, if distance <= Tuning.chompRange then "chomp" else "walk")
	if distance <= 2 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.service().touch(entry, CreatureKit.feet(entry) + Vector3.new(0, 1, 0))
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.runSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	CreatureKit.service().touch(entry, CreatureKit.feet(entry) + Vector3.new(0, 1, 0))
	return true
end

return Trait
