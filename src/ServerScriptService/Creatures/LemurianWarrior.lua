--[[
	Lemurian Warrior - a ring-tailed lemur of the Hallow with a long blade at
	its hip, and an acrobat. Head, arms, blade, legs and tail are jointed
	(Shared.Enemies.CreatureRigs.LemurianWarrior).

	TAIL VAULT (`vaultMin` to `vaultRange`). It crouches, then springs right
	over your head in a high arc and lands `vaultPast` studs beyond you, facing
	you, slashing as it lands (`landDamage` to anyone within `landRadius`).
	Turn round.

	SLASH (within `slashRange`). The blade swept flat across in front of it.
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 8.5,
	slideStep = 2,

	vaultRange = 15,
	vaultMin = 6,
	vaultCrouch = 0.35,
	vaultSeconds = 0.75,
	vaultHeight = 8,
	vaultPast = 3.5,
	vaultCooldown = 5,
	landRadius = 3.5,
	landDamage = 10,

	slashRange = 4,
	slashReach = 4.5,
	slashArc = 70,
	slashWindup = 0.3,
	slashSeconds = 0.7,
	slashDamage = 9,
	slashCooldown = 1.5,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "LemurianWarrior")
	entry.nextVaultAt = os.clock() + 1
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

local function slashHit(entry, damage: number, radius: number, arc: number?)
	local feet = CreatureKit.feet(entry)
	local facing = look(entry)
	local cosine = math.cos(math.rad(arc or 180))
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local offset = Vector3.new(hrp.Position.X - feet.X, 0, hrp.Position.Z - feet.Z)
			if offset.Magnitude <= radius and math.abs(hrp.Position.Y - feet.Y - 2) <= 4
				and (offset.Magnitude < 1 or offset.Unit:Dot(facing) >= cosine) then
				CreatureKit.hurt(entry, player, damage)
			end
		end
	end
	CreatureKit.fx("cut", entry.model)
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	local move = entry.move
	if move and move.kind == "vault" then
		-- Its own arc, placed every tick.
		local k = math.min(1, (now - move.startedAt) / Tuning.vaultSeconds)
		local at = move.from:Lerp(move.to, k) + Vector3.new(0, math.sin(k * math.pi) * Tuning.vaultHeight, 0)
		-- It turns in the air to land facing back the way it came.
		local facing = move.heading:Lerp(-move.heading, math.clamp(k * 1.5 - 0.25, 0, 1))
		if facing.Magnitude < 1e-3 then
			facing = move.heading:Cross(Vector3.yAxis)
		end
		CreatureKit.place(entry, at, facing)
		if k >= 1 then
			entry.groundY = move.to.Y
			entry.move = { kind = "slash", hitAt = now + 0.05, untilAt = now + 0.5, damage = Tuning.landDamage, radius = Tuning.landRadius }
			CreatureKit.pose(entry, "slash")
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
				local heading = CreatureKit.flat(aim - from)
				local spot = Vector3.new(aim.X, from.Y, aim.Z) + heading * Tuning.vaultPast
				local ground = CreatureKit.service().groundAt(spot.X, spot.Z, aim.Y)
				local to = Vector3.new(spot.X, ground, spot.Z)
				if math.abs(ground - from.Y) > 6 or CreatureKit.solidAt(to + Vector3.new(0, entry.height * 0.5, 0)) then
					entry.move = nil
					CreatureKit.pose(entry, "walk")
				else
					entry.move = { kind = "vault", from = from, to = to, heading = heading, startedAt = now }
					CreatureKit.pose(entry, "vault")
				end
			end
			return true
		elseif move.kind == "slash" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				slashHit(entry, move.damage or Tuning.slashDamage, move.radius or Tuning.slashReach, if move.radius then nil else Tuning.slashArc)
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

	if distance <= Tuning.slashRange and now >= (entry.nextSlashAt or 0) then
		entry.nextSlashAt = now + Tuning.slashCooldown
		entry.move = { kind = "slash", hitAt = now + Tuning.slashWindup, untilAt = now + Tuning.slashSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "slash")
		return true
	end

	if distance >= Tuning.vaultMin and distance <= Tuning.vaultRange and now >= entry.nextVaultAt then
		entry.nextVaultAt = now + Tuning.vaultCooldown
		entry.move = { kind = "crouch", at = now + Tuning.vaultCrouch, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "crouch")
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.slashRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
