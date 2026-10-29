--[[
	Crab Monster - a crab-man of the Swamp with a pincer on each arm, and a
	wall: you have to get round it. Head, arms, claws, legs and tail are
	jointed (Shared.Enemies.CreatureRigs.CrabMonster).

	GUARD. Whenever it is facing you and not attacking, its claws are up
	crossed in front of it and a blow from in front (within `guardArc` of where
	it looks) does only `guardShare` of its damage, with a clank of sparks. From
	the side or behind, or while it is pinching, it takes the lot.

	SCUTTLE (`scuttleMin` to `scuttleRange`). It closes in sideways, circling
	as it comes, claws up - which is what makes flanking it work.

	PINCH (within `pinchRange`). The guard drops, the claws are thrown wide for
	`pinchWindup` and snapped shut: whoever is in front is hurt and held - barely
	able to move - for `holdSeconds`, then crushed once more if still in reach.
	The wide claws are the tell and the opening.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 5,
	scuttleSpeed = 7,
	slideStep = 2,

	scuttleRange = 20,
	scuttleMin = 5,
	-- How hard it turns in while circling: 0 circles for ever, 1 walks straight.
	scuttleIn = 0.45,
	scuttleFlip = 2.5,

	guardShare = 0.25,
	-- Degrees either side of its facing that the guard covers.
	guardArc = 70,

	pinchRange = 4.2,
	pinchReach = 3.2,
	pinchRadius = 2.6,
	pinchWindup = 0.55,
	pinchDamage = 9,
	holdSeconds = 1.1,
	holdSlow = 0.1,
	crushDamage = 7,
	pinchCooldown = 3.2,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "CrabMonster")
	entry.side = if math.random() < 0.5 then 1 else -1
	CreatureKit.pose(entry, "guard")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- The players in its claws: in front, within the pinch's reach.
local function inClaws(entry)
	local center = CreatureKit.feet(entry) + look(entry) * Tuning.pinchReach + Vector3.new(0, entry.height * 0.4, 0)
	local found = {}
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - center).Magnitude <= Tuning.pinchRadius + 1 then
			table.insert(found, player)
		end
	end
	return found
end

function Trait.guard(entry, _amount, dealer)
	local pose = entry.model:GetAttribute("Pose")
	if entry.state ~= "Grounded" or (pose ~= "guard" and pose ~= "scuttle") then
		return 1
	end
	local character = typeof(dealer) == "Instance" and dealer:IsA("Player") and dealer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return 1
	end
	local toward = CreatureKit.flat(hrp.Position - entry.model:GetPivot().Position)
	if toward:Dot(look(entry)) < math.cos(math.rad(Tuning.guardArc)) then
		return 1
	end
	CreatureKit.fx("clank", entry.model)
	return Tuning.guardShare
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "pinch" then
			if now >= move.snapAt then
				local held = inClaws(entry)
				for _, player in ipairs(held) do
					CreatureKit.hurt(entry, player, Tuning.pinchDamage)
					CreatureKit.slow(player, Tuning.holdSlow, Tuning.holdSeconds)
				end
				CreatureKit.fx("snap", entry.model, #held > 0)
				if #held > 0 then
					entry.move = { kind = "hold", untilAt = now + Tuning.holdSeconds, held = held }
					CreatureKit.pose(entry, "hold")
				else
					entry.move = { kind = "recover", untilAt = now + 0.5 }
				end
			end
			return true
		elseif move.kind == "hold" then
			if now >= move.untilAt then
				local still = inClaws(entry)
				for _, player in ipairs(still) do
					if table.find(move.held, player) then
						CreatureKit.hurt(entry, player, Tuning.crushDamage)
					end
				end
				CreatureKit.fx("snap", entry.model, #still > 0)
				entry.move = { kind = "recover", untilAt = now + 0.4 }
			end
			return true
		elseif move.kind == "recover" then
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "guard")
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

	if distance <= Tuning.pinchRange and now >= (entry.nextPinchAt or 0) then
		entry.nextPinchAt = now + Tuning.pinchCooldown
		entry.move = { kind = "pinch", snapAt = now + Tuning.pinchWindup }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "pinch")
		return true
	end

	if distance <= Tuning.pinchRange * 0.8 then
		CreatureKit.pose(entry, "guard")
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end

	local step
	if distance >= Tuning.scuttleMin and distance <= Tuning.scuttleRange then
		-- Sideways and inward, facing you all the while; now and then it
		-- changes which way it circles.
		if now >= (entry.flipAt or 0) then
			entry.flipAt = now + Tuning.scuttleFlip * (0.6 + math.random() * 0.8)
			entry.side = -(entry.side or 1)
		end
		local across = toward:Cross(Vector3.yAxis) * entry.side
		local heading = (across * (1 - Tuning.scuttleIn) + toward * Tuning.scuttleIn).Unit
		step = heading * Tuning.scuttleSpeed * dt
		CreatureKit.pose(entry, "scuttle")
	else
		step = toward * Tuning.walkSpeed * dt
		CreatureKit.pose(entry, "guard")
	end
	if not CreatureKit.slide(entry, step, toward, nil, Tuning.slideStep) then
		-- A step or a wall in the way of the circle: try the other way next.
		entry.side = -(entry.side or 1)
		return false
	end
	return true
end

return Trait
