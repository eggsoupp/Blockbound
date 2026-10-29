--[[
	Bat Mutant - a wingless bat of the Desert, all ears and teeth, that bounds
	about where you cannot quite pin it and screams at you. Head, arms and legs
	are jointed (Shared.Enemies.CreatureRigs.BatMutant).

	ERRATIC BOUNDS (`boundMin` to `boundRange`). Every `boundEvery` or so it
	squats and leaps - forward, but well off to one side or the other, never
	straight at you - in a short arc `boundLength` long.

	SCREECH (within `screechRange`). Head thrown back, then a scream in a cone
	in front of it (`screechAngle` either side): everyone in it is hurt for
	`screechDamage` and slowed to `screechSlow` for `screechSlowSeconds`. Get
	out of the cone - to its side - in the half second it takes to draw breath.

	BITE (within `biteRange`).
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 7,
	slideStep = 2,

	boundRange = 22,
	boundMin = 4,
	boundEvery = 1.8,
	boundCrouch = 0.25,
	boundLength = 7,
	boundSeconds = 0.5,
	boundHeight = 3,
	-- How far off the straight line to you it aims, in radians either way.
	boundSwerve = 0.9,

	screechRange = 9,
	screechAngle = 35,
	screechWindup = 0.5,
	screechSeconds = 0.9,
	screechDamage = 8,
	screechSlow = 0.5,
	screechSlowSeconds = 1.8,
	screechCooldown = 4.5,

	biteRange = 2.8,
	biteReach = 2,
	biteWindup = 0.2,
	biteSeconds = 0.5,
	biteDamage = 6,
	biteCooldown = 1.2,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "BatMutant")
	entry.nextBoundAt = os.clock() + 0.8
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- Where a bound in `heading` would land, or nil into a wall or off a ledge.
local function landing(entry, from: Vector3, heading: Vector3): Vector3?
	local spot = from + heading * Tuning.boundLength
	local ground = CreatureKit.service().groundAt(spot.X, spot.Z, from.Y)
	if math.abs(ground - from.Y) > 4.5 then
		return nil
	end
	local feet = Vector3.new(spot.X, ground, spot.Z)
	if CreatureKit.solidAt(feet + Vector3.new(0, entry.height * 0.5, 0))
		or CreatureKit.firstBlock(from + Vector3.new(0, entry.height * 0.6, 0), feet + Vector3.new(0, entry.height * 0.6 + Tuning.boundHeight * 0.5, 0), 1) then
		return nil
	end
	return feet
end

local function screech(entry)
	local origin = CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.75, 0)
	local facing = look(entry)
	local cosine = math.cos(math.rad(Tuning.screechAngle))
	CreatureKit.fx("screech", origin, facing, Tuning.screechRange)
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local offset = hrp.Position - origin
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude <= Tuning.screechRange and math.abs(offset.Y) <= 5
				and (flat.Magnitude < 1 or flat.Unit:Dot(facing) >= cosine) then
				CreatureKit.hurt(entry, player, Tuning.screechDamage)
				CreatureKit.slow(player, Tuning.screechSlow, Tuning.screechSlowSeconds)
			end
		end
	end
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	local move = entry.move
	if move and move.kind == "bound" then
		-- Its own arc: placed every tick, so the hop movement never sees it
		-- leave the ground.
		local k = math.min(1, (now - move.startedAt) / Tuning.boundSeconds)
		local at = move.from:Lerp(move.to, k) + Vector3.new(0, math.sin(k * math.pi) * Tuning.boundHeight, 0)
		CreatureKit.place(entry, at, move.facing)
		if k >= 1 then
			entry.groundY = move.to.Y
			entry.move = nil
			CreatureKit.pose(entry, "walk")
			CreatureKit.fx("chop", move.to)
		end
		return true
	end

	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	if move then
		if move.kind == "crouch" then
			if now >= move.at then
				local from = CreatureKit.feet(entry)
				local aim = targetPosition or move.aim
				local toward = CreatureKit.flat(aim - from)
				local side = if math.random() < 0.5 then 1 else -1
				local to
				for _, swerve in ipairs({ side * Tuning.boundSwerve, -side * Tuning.boundSwerve, side * Tuning.boundSwerve * 1.6 }) do
					to = landing(entry, from, CFrame.Angles(0, swerve, 0):VectorToWorldSpace(toward))
					if to then
						break
					end
				end
				if to then
					entry.move = { kind = "bound", from = from, to = to, startedAt = now, facing = CreatureKit.flat(aim - to) }
					CreatureKit.pose(entry, "bound")
				else
					entry.move = nil
					CreatureKit.pose(entry, "walk")
				end
			end
			return true
		elseif move.kind == "screech" then
			if not move.fired and now >= move.at then
				move.fired = true
				screech(entry)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "bite" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local reach = CreatureKit.feet(entry) + look(entry) * Tuning.biteReach + Vector3.new(0, 1.5, 0)
				CreatureKit.service().touch(entry, reach, Tuning.biteDamage)
			end
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

	if distance <= Tuning.biteRange and now >= (entry.nextBiteAt or 0) then
		entry.nextBiteAt = now + Tuning.biteCooldown
		entry.move = { kind = "bite", hitAt = now + Tuning.biteWindup, untilAt = now + Tuning.biteSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "bite")
		return true
	end

	if distance <= Tuning.screechRange and now >= (entry.nextScreechAt or 0) then
		entry.nextScreechAt = now + Tuning.screechCooldown
		entry.move = { kind = "screech", at = now + Tuning.screechWindup, untilAt = now + Tuning.screechSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "screech")
		return true
	end

	if distance >= Tuning.boundMin and distance <= Tuning.boundRange and now >= (entry.nextBoundAt or 0) then
		entry.nextBoundAt = now + Tuning.boundEvery * (0.7 + math.random() * 0.6)
		entry.move = { kind = "crouch", at = now + Tuning.boundCrouch, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "crouch")
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.biteRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
