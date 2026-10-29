--[[
	Zombie Rat - a rotting rat of the Corruption, in packs, that does not stay
	dead. Head, paws, hind legs and tail are jointed
	(Shared.Enemies.CreatureRigs.ZombieRat).

	ROTTING BITE (within `biteRange`). It lunges its head in for `biteDamage`
	and leaves rot in the wound: `rotTicks` more hits of `rotDamage`, one every
	`rotInterval`.

	NOT DEAD YET. The first blow that would kill it does not: it collapses
	with one health for `downSeconds`, twitching, and then drags itself back up
	with `riseShare` of its health. Hit it while it is down and it stays down.
	The second death is the real one.
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 6.5,
	slideStep = 2,

	biteRange = 2.8,
	biteReach = 1.8,
	biteWindup = 0.3,
	biteSeconds = 0.6,
	biteDamage = 4,
	biteCooldown = 1.4,
	rotTicks = 3,
	rotDamage = 2,
	rotInterval = 0.8,

	downSeconds = 2.4,
	riseShare = 0.5,
	riseSeconds = 0.7,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "ZombieRat")
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- The first killing blow leaves it on one health, collapsed.
function Trait.guard(entry, amount)
	if entry.risen or entry.health - amount > 0 then
		return 1
	end
	entry.risen = true
	entry.move = { kind = "down", untilAt = os.clock() + Tuning.downSeconds }
	CreatureKit.pose(entry, "down")
	CreatureKit.fx("collapse", CreatureKit.feet(entry))
	return math.max(0, (entry.health - 1) / amount)
end

-- Rot left in a bite: a few more small hurts, if they are still around.
local function rot(entry, player: Player)
	CreatureKit.fx("rot", player.Character, Tuning.rotTicks * Tuning.rotInterval)
	for i = 1, Tuning.rotTicks do
		task.delay(i * Tuning.rotInterval, function()
			local humanoid = player.Parent and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				CreatureKit.hurt(entry, player, Tuning.rotDamage)
			end
		end)
	end
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	local move = entry.move
	if move and move.kind == "down" then
		-- Down is down even in the air: no hop, no turning.
		if now >= move.untilAt then
			local Service = CreatureKit.service()
			Service.heal(entry.model, entry.def.health * Tuning.riseShare)
			entry.move = { kind = "rise", untilAt = now + Tuning.riseSeconds }
			CreatureKit.pose(entry, "rise")
			CreatureKit.fx("rise", CreatureKit.feet(entry))
		end
		return true
	end

	if entry.state ~= "Grounded" then
		if not (move and move.kind == "rise") then
			entry.move = nil
		end
		return false
	end

	if move then
		if move.kind == "rise" then
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "bite" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local reach = CreatureKit.feet(entry) + look(entry) * Tuning.biteReach + Vector3.new(0, 1, 0)
				for _, player in ipairs(Players:GetPlayers()) do
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp and (hrp.Position - reach).Magnitude <= 3 then
						CreatureKit.hurt(entry, player, Tuning.biteDamage)
						rot(entry, player)
					end
				end
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
