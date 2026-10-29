--[[
	Lizard Warrior - a swamp lizard with a sickle in each hand and a heavy
	tail, and nowhere safe to stand. Head, arms, both blades, legs and tail are
	jointed (Shared.Enemies.CreatureRigs.LizardWarrior).

	TWO-BLADE COMBO (within `comboRange`, in front). The right sickle hooked
	back over its shoulder for `comboWindup` and chopped down (`chopDamage`),
	then the left blade swept across low (`sweepDamage`, at `comboSecond`).

	TAIL LASH (anyone close BEHIND or beside it, within `lashRange`). Circling
	round it is no answer: it lashes its tail round through everyone at its
	back and flanks.

	LEAP (`leapMin` to `leapRange`). Blades up, it leaps at you - the ordinary
	hop's lunge.
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 7.5,
	slideStep = 2,

	comboRange = 4.2,
	comboReach = 2.8,
	comboWindup = 0.35,
	comboSecond = 0.62,
	comboSeconds = 0.95,
	chopDamage = 11,
	sweepDamage = 6,
	comboCooldown = 1.8,

	lashRange = 5,
	-- Anyone further round than this from straight ahead counts as behind.
	lashAngle = 75,
	lashWindup = 0.25,
	lashSeconds = 0.6,
	lashDamage = 9,
	lashCooldown = 2.5,

	leapRange = 12,
	leapMin = 6,
	leapWindup = 0.35,
	leapCooldown = 4,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "LizardWarrior")
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- Players in front of it within reach of a blade.
local function inFront(entry, radius: number)
	local center = CreatureKit.feet(entry) + look(entry) * Tuning.comboReach + Vector3.new(0, 1.5, 0)
	local found = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - center).Magnitude <= radius then
			table.insert(found, player)
		end
	end
	return found
end

-- Whether anyone is close at its back or flank, where the blades cannot go.
local function flanked(entry, position: Vector3): boolean
	local facing = look(entry)
	local cosine = math.cos(math.rad(Tuning.lashAngle))
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local offset = Vector3.new(hrp.Position.X - position.X, 0, hrp.Position.Z - position.Z)
			if offset.Magnitude <= Tuning.lashRange and offset.Magnitude > 0.5 and offset.Unit:Dot(facing) < cosine then
				return true
			end
		end
	end
	return false
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "combo" then
			local elapsed = now - move.startedAt
			if not move.chopped and elapsed >= Tuning.comboWindup then
				move.chopped = true
				for _, player in ipairs(inFront(entry, 2.8)) do
					CreatureKit.hurt(entry, player, Tuning.chopDamage)
				end
				CreatureKit.fx("cut", entry.model)
			end
			if not move.swept and elapsed >= Tuning.comboSecond then
				move.swept = true
				for _, player in ipairs(inFront(entry, 3)) do
					CreatureKit.hurt(entry, player, Tuning.sweepDamage)
				end
				CreatureKit.fx("cut", entry.model)
			end
			if elapsed >= Tuning.comboSeconds then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "lash" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local feet = CreatureKit.feet(entry)
				local facing = look(entry)
				local cosine = math.cos(math.rad(Tuning.lashAngle))
				for _, player in ipairs(Players:GetPlayers()) do
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						local offset = Vector3.new(hrp.Position.X - feet.X, 0, hrp.Position.Z - feet.Z)
						if offset.Magnitude <= Tuning.lashRange + 0.5 and math.abs(hrp.Position.Y - feet.Y) <= 5
							and (offset.Magnitude < 0.5 or offset.Unit:Dot(facing) < cosine) then
							CreatureKit.hurt(entry, player, Tuning.lashDamage)
						end
					end
				end
				CreatureKit.fx("slam", feet - facing * 2, 3)
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

	if now >= (entry.nextLashAt or 0) and flanked(entry, position) then
		entry.nextLashAt = now + Tuning.lashCooldown
		entry.move = { kind = "lash", hitAt = now + Tuning.lashWindup, untilAt = now + Tuning.lashSeconds }
		CreatureKit.pose(entry, "sweep")
		return true
	end

	if distance <= Tuning.comboRange and now >= (entry.nextComboAt or 0) then
		entry.nextComboAt = now + Tuning.comboCooldown
		entry.move = { kind = "combo", startedAt = now }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "combo")
		return true
	end

	if distance >= Tuning.leapMin and distance <= Tuning.leapRange and now >= (entry.nextLeapAt or 0) then
		entry.nextLeapAt = now + Tuning.leapCooldown
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "leap")
		entry.state = "Windup"
		entry.pendingLunge = true
		entry.stateUntil = now + Tuning.leapWindup
		return false
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.comboRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
