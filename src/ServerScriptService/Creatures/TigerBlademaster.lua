--[[
	Tiger Blademaster - a caped tiger of the Plains with two crossed swords,
	and a swordsman: patient, then very fast. Head, legs and the crossed
	arms-and-blades are jointed (Shared.Enemies.CreatureRigs.TigerBlademaster).

	COUNTER STANCE (within `stanceRange`). It stops and raises its crossed
	blades for `stanceSeconds`. A blow struck at it then does nothing - it is
	parried with a ring of steel - and it answers at once with a dash straight
	through whoever struck it (`counterDamage`). The tell is the stillness: wait
	it out.

	DASH SLASH (`dashMin` to `dashRange`). A short crouch, then it dashes in a
	straight line through you and out the other side, cutting once on the way
	(`dashDamage`).

	DOUBLE CUT (within `cutRange`). Two quick sweeps of the blades.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 8,
	slideStep = 2,

	stanceRange = 8,
	stanceSeconds = 1.6,
	stanceCooldown = 7,
	counterDamage = 15,

	dashRange = 18,
	dashMin = 7,
	dashWindup = 0.4,
	dashSpeed = 34,
	dashOvershoot = 4,
	dashDamage = 11,
	dashCooldown = 4,
	dashRadius = 2.4,

	cutRange = 3.8,
	cutReach = 2.8,
	cutDamage = 7,
	cutTimes = { 0.25, 0.55 },
	cutSeconds = 0.9,
	cutCooldown = 1.6,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "TigerBlademaster")
	entry.nextStanceAt = os.clock() + 2
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- A dash in a straight line for `length` studs, cutting each player it
-- passes once.
local function dash(entry, heading: Vector3, length: number, damage: number, now: number)
	entry.move = {
		kind = "dash", heading = heading, left = length, damage = damage, hit = {},
		untilAt = now + length / Tuning.dashSpeed + 0.3,
	}
	CreatureKit.place(entry, CreatureKit.feet(entry), heading)
	CreatureKit.pose(entry, "dash")
	CreatureKit.fx("dashtrail", entry.model, length / Tuning.dashSpeed)
end

function Trait.guard(entry, _amount, dealer)
	local move = entry.move
	if not (move and move.kind == "stance") then
		return 1
	end
	-- Parried: no damage, and the answer comes at once.
	local character = typeof(dealer) == "Instance" and dealer:IsA("Player") and dealer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	CreatureKit.fx("parry", entry.model)
	if hrp then
		local position = entry.model:GetPivot().Position
		local offset = Vector3.new(hrp.Position.X - position.X, 0, hrp.Position.Z - position.Z)
		local heading = if offset.Magnitude > 1e-3 then offset.Unit else look(entry)
		dash(entry, heading, offset.Magnitude + Tuning.dashOvershoot, Tuning.counterDamage, os.clock())
	else
		entry.move = nil
		CreatureKit.pose(entry, "walk")
	end
	return 0
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "stance" then
			if targetPosition then
				CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(targetPosition - position))
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "crouch" then
			if now >= move.at then
				local aim = targetPosition or move.aim
				local offset = Vector3.new(aim.X - position.X, 0, aim.Z - position.Z)
				dash(entry, CreatureKit.flat(offset), offset.Magnitude + Tuning.dashOvershoot, Tuning.dashDamage, now)
			end
			return true
		elseif move.kind == "dash" then
			local step = math.min(move.left, Tuning.dashSpeed * dt)
			local from = position + Vector3.new(0, entry.height * 0.3, 0)
			local moved = step > 0 and CreatureKit.slide(entry, move.heading * step, move.heading, nil, Tuning.slideStep)
			if moved then
				move.left -= step
				for _, player in ipairs(CreatureKit.playersAlong(from, from + move.heading * (step + 1.5), Tuning.dashRadius)) do
					if not move.hit[player] then
						move.hit[player] = true
						CreatureKit.hurt(entry, player, move.damage)
						CreatureKit.fx("cut", entry.model)
					end
				end
			end
			if not moved and move.left > 2 and next(move.hit) == nil then
				-- A step in the way: the rest of the dash is a leap, the
				-- ordinary hop's lunge, straight away.
				entry.move = nil
				entry.state = "Windup"
				entry.pendingLunge = true
				entry.stateUntil = now
				return false
			end
			if not moved or move.left <= 0 or now >= move.untilAt then
				entry.move = { kind = "recover", untilAt = now + 0.35 }
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "cut" then
			local due = Tuning.cutTimes[move.done + 1]
			if due and now >= move.startedAt + due then
				move.done += 1
				local reach = CreatureKit.feet(entry) + look(entry) * Tuning.cutReach + Vector3.new(0, 1.5, 0)
				-- touch() keeps one contact interval per player; a second cut
				-- in the same breath goes through hurt() directly.
				for _, player in ipairs(CreatureKit.playersAlong(reach - look(entry), reach + look(entry), 2.4)) do
					CreatureKit.hurt(entry, player, Tuning.cutDamage)
				end
				CreatureKit.fx("cut", entry.model)
			end
			if now >= move.startedAt + Tuning.cutSeconds then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "recover" then
			if now >= move.untilAt then
				entry.move = nil
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

	if distance <= Tuning.stanceRange and now >= (entry.nextStanceAt or 0) then
		entry.nextStanceAt = now + Tuning.stanceCooldown
		entry.move = { kind = "stance", untilAt = now + Tuning.stanceSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "stance")
		CreatureKit.fx("flare", entry.model, Color3.fromRGB(235, 245, 255))
		return true
	end

	if distance <= Tuning.cutRange and now >= (entry.nextCutAt or 0) then
		entry.nextCutAt = now + Tuning.cutCooldown
		entry.move = { kind = "cut", startedAt = now, done = 0 }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "slash")
		return true
	end

	if distance >= Tuning.dashMin and distance <= Tuning.dashRange and now >= (entry.nextDashAt or 0)
		and not CreatureKit.firstBlock(position + Vector3.new(0, 1.5, 0), targetPosition, 1) then
		entry.nextDashAt = now + Tuning.dashCooldown
		entry.move = { kind = "crouch", at = now + Tuning.dashWindup, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "crouch")
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.cutRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
