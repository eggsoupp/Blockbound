--[[
	Werewolf Lord - a wolf of the Snow in a long coat, with a long sword and a
	temper. Head, arms, sword and legs are jointed
	(Shared.Enemies.CreatureRigs.WerewolfLord).

	REND (within `slashRange`). The blade swept flat across in front of it:
	everyone in the arc ahead is cut for `slashDamage` and BLEEDS -
	`bleedTicks` more hurts of `bleedDamage`, one every `bleedInterval`.

	THRUST (`thrustMin` to `thrustRange`). Drawn back, then driven straight
	out along its long blade for `thrustDamage`.

	LEAP (`leapMin` to `leapRange`). Sword up, it leaps at you - the ordinary
	hop's lunge.

	HOWL. The first time it falls below `howlAt` of its health it stops and
	howls, and fights ENRAGED from then on: `rageSpeed` times as fast, its
	moves coming `rageHaste` times as often, and hitting `rageScale` times as
	hard - marked with a red glow.
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 7.5,
	slideStep = 2,

	slashRange = 5,
	slashReach = 5.5,
	-- Degrees either side of straight ahead the sweep covers.
	slashArc = 75,
	slashWindup = 0.4,
	slashSeconds = 0.8,
	slashDamage = 9,
	slashCooldown = 1.8,
	bleedTicks = 3,
	bleedDamage = 2,
	bleedInterval = 0.7,

	thrustRange = 9,
	thrustMin = 5,
	thrustWindup = 0.45,
	thrustSeconds = 0.75,
	thrustDamage = 12,
	thrustCooldown = 3,

	leapRange = 16,
	leapMin = 9,
	leapWindup = 0.35,
	leapCooldown = 5,

	howlAt = 0.5,
	howlSeconds = 1.1,
	rageSpeed = 1.35,
	rageHaste = 0.65,
	rageScale = 1.3,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "WerewolfLord")
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

local function haste(entry): number
	return if entry.enraged then Tuning.rageHaste else 1
end

-- The first time it is hurt below half, it will howl at the next chance.
function Trait.guard(entry, amount)
	if not entry.howled and entry.health - amount <= entry.def.health * Tuning.howlAt then
		entry.howled = true
		entry.wantsHowl = true
	end
	return 1
end

local function bleed(entry, player: Player)
	CreatureKit.fx("rot", player.Character, Tuning.bleedTicks * Tuning.bleedInterval)
	for i = 1, Tuning.bleedTicks do
		task.delay(i * Tuning.bleedInterval, function()
			local humanoid = player.Parent and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				CreatureKit.hurt(entry, player, Tuning.bleedDamage)
			end
		end)
	end
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "slash" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local feet = CreatureKit.feet(entry)
				local facing = look(entry)
				local cosine = math.cos(math.rad(Tuning.slashArc))
				for _, player in ipairs(Players:GetPlayers()) do
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						local offset = Vector3.new(hrp.Position.X - feet.X, 0, hrp.Position.Z - feet.Z)
						if offset.Magnitude <= Tuning.slashReach and math.abs(hrp.Position.Y - feet.Y - 2) <= 4
							and (offset.Magnitude < 1 or offset.Unit:Dot(facing) >= cosine) then
							CreatureKit.hurt(entry, player, Tuning.slashDamage)
							bleed(entry, player)
						end
					end
				end
				CreatureKit.fx("cut", entry.model)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "thrust" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local from = CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.4, 0)
				local to = from + look(entry) * Tuning.thrustRange
				for _, player in ipairs(CreatureKit.playersAlong(from, to, 1.8)) do
					CreatureKit.hurt(entry, player, Tuning.thrustDamage)
				end
				CreatureKit.fx("cut", entry.model)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "howl" then
			if now >= move.untilAt then
				entry.move = nil
				entry.enraged = true
				local Service = CreatureKit.service()
				Service.setDamageScale(entry.model, (Service.damageScaleOf(entry.model) or 1) * Tuning.rageScale)
				CreatureKit.fx("rallied", entry.model, 600)
				CreatureKit.pose(entry, "walk")
			end
			return true
		end
	end

	if entry.wantsHowl then
		entry.wantsHowl = false
		entry.move = { kind = "howl", untilAt = now + Tuning.howlSeconds }
		CreatureKit.pose(entry, "howl")
		CreatureKit.fx("roar", entry.model, Tuning.howlSeconds)
		return true
	end

	if not (target and targetPosition) then
		CreatureKit.pose(entry, "walk")
		return false
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude
	local h = haste(entry)

	if distance <= Tuning.slashRange and now >= (entry.nextSlashAt or 0) then
		entry.nextSlashAt = now + Tuning.slashCooldown * h
		entry.move = { kind = "slash", hitAt = now + Tuning.slashWindup, untilAt = now + Tuning.slashSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "slash")
		return true
	end

	if distance >= Tuning.thrustMin and distance <= Tuning.thrustRange and now >= (entry.nextThrustAt or 0) then
		entry.nextThrustAt = now + Tuning.thrustCooldown * h
		entry.move = { kind = "thrust", hitAt = now + Tuning.thrustWindup, untilAt = now + Tuning.thrustSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "thrust")
		return true
	end

	if distance >= Tuning.leapMin and distance <= Tuning.leapRange and now >= (entry.nextLeapAt or 0) then
		entry.nextLeapAt = now + Tuning.leapCooldown * h
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "leap")
		entry.state = "Windup"
		entry.pendingLunge = true
		entry.stateUntil = now + Tuning.leapWindup
		return false
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.slashRange * 0.6 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	local speed = Tuning.walkSpeed * (if entry.enraged then Tuning.rageSpeed else 1)
	if not CreatureKit.slide(entry, toward * speed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
