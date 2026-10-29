--[[
	Green Raptor - a small two-legged hunter of the Desert that hunts as a
	pack. Head, legs and tail are jointed (Shared.Enemies.CreatureRigs.
	GreenRaptor).

	TAKING TURNS. A pack never rushes you all at once. The raptors circle at
	`circleRadius`, hissing, and one at a time - whichever holds the pack's
	turn on you - darts in, bites, and runs back out to the circle, and then
	the next one goes. You are always turning to meet the one coming.

	DART AND BITE. The one whose turn it is sprints in at `dartSpeed`; in
	reach it bites (`biteDamage`) and retreats at once.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	circleRadius = 9,
	circleSpeed = 8,
	-- How hard it holds its distance while circling: 0 drifts, 1 snaps.
	circlePull = 0.6,

	dartSpeed = 18,
	dartReach = 2.6,
	dartSeconds = 1.6,
	biteWindup = 0.15,
	biteDamage = 7,
	retreatSeconds = 0.8,
	-- After its turn, how long before the same raptor may go again.
	turnRest = 2.5,
}

local Trait = {}
Trait.Tuning = Tuning

-- Whose turn it is to dart in at each player: player -> entry.
local turns = setmetatable({}, { __mode = "k" })

local function holds(entry, player): boolean
	local holder = turns[player]
	if holder == entry then
		return true
	end
	if holder == nil or holder.dead or not holder.model.Parent then
		turns[player] = entry
		return true
	end
	return false
end

local function release(entry, player)
	if player and turns[player] == entry then
		turns[player] = nil
	end
end

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "GreenRaptor")
	entry.side = if math.random() < 0.5 then 1 else -1
	entry.nextTurnAt = os.clock() + math.random() * 1.5
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "dart" then
			if not (targetPosition and target == move.player) or now >= move.untilAt then
				release(entry, move.player)
				entry.move = nil
				entry.nextTurnAt = now + Tuning.turnRest
				return true
			end
			local toward = CreatureKit.flat(targetPosition - position)
			local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude
			if distance <= Tuning.dartReach then
				entry.move = { kind = "bite", player = move.player, hitAt = now + Tuning.biteWindup }
				CreatureKit.place(entry, CreatureKit.feet(entry), toward)
				CreatureKit.pose(entry, "bite")
				return true
			end
			if not CreatureKit.slide(entry, toward * Tuning.dartSpeed * dt, toward, nil, 2) then
				return false
			end
			return true
		elseif move.kind == "bite" then
			if now >= move.hitAt then
				local reach = CreatureKit.feet(entry) + look(entry) * 1.6 + Vector3.new(0, 1, 0)
				CreatureKit.service().touch(entry, reach, Tuning.biteDamage)
				CreatureKit.fx("cut", entry.model)
				entry.move = { kind = "retreat", player = move.player, untilAt = now + Tuning.retreatSeconds }
				CreatureKit.pose(entry, "dart")
			end
			return true
		elseif move.kind == "retreat" then
			if now >= move.untilAt or not targetPosition then
				release(entry, move.player)
				entry.move = nil
				entry.nextTurnAt = now + Tuning.turnRest
				return true
			end
			local away = CreatureKit.flat(position - targetPosition)
			if not CreatureKit.slide(entry, away * Tuning.dartSpeed * 0.8 * dt, -away, nil, 2) then
				release(entry, move.player)
				entry.move = nil
				entry.nextTurnAt = now + Tuning.turnRest
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

	if now >= (entry.nextTurnAt or 0) and holds(entry, target) then
		entry.move = { kind = "dart", player = target, untilAt = now + Tuning.dartSeconds }
		CreatureKit.pose(entry, "dart")
		return true
	end

	-- Circling: round the target, pulled back to the ring, facing in.
	local around = toward:Cross(Vector3.yAxis) * entry.side
	local pull = (distance - Tuning.circleRadius) / Tuning.circleRadius
	local heading = around + toward * math.clamp(pull, -1, 1) * Tuning.circlePull * 2
	if heading.Magnitude > 1e-3 then
		heading = heading.Unit
	end
	CreatureKit.pose(entry, if distance <= Tuning.circleRadius * 1.3 then "hiss" else "walk")
	if not CreatureKit.slide(entry, heading * Tuning.circleSpeed * dt, toward, nil, 2) then
		entry.side = -entry.side
		return false
	end
	return true
end

function Trait.finish(entry)
	entry.dead = true
	local move = entry.move
	if move and move.player then
		release(entry, move.player)
	end
end

return Trait
