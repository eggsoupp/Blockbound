--[[
	Handless Norg - a tusked purple blob of the Corruption with no hands and a
	great deal of mouth. Head (mouth and tusks), legs and tail are jointed
	(Shared.Enemies.CreatureRigs.HandlessNorg).

	INHALE (within `inhaleRange`, in front of it). It throws its mouth open
	and breathes in for `inhaleSeconds`: everyone in front of it is dragged
	toward its mouth at `pullSpeed` - slower than you can walk, so you can
	fight it off by walking away. The pull itself is drawn and applied by each
	player's own client (StarterPlayerScripts.CreatureFX "inhale"); the
	server only says when and where.

	CHOMP. At the end of the inhale, or whenever you are right at its mouth,
	it chomps: `chompDamage` to anyone within `chompReach` of its mouth.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 5.5,
	slideStep = 2,

	inhaleRange = 18,
	inhaleMin = 5,
	inhaleSeconds = 1.8,
	-- Half-angle of the cone it pulls from, in degrees.
	inhaleArc = 45,
	pullSpeed = 10,
	inhaleCooldown = 7,

	chompRange = 3.5,
	chompReach = 2.4,
	chompWindup = 0.2,
	chompSeconds = 0.6,
	chompDamage = 12,
	chompCooldown = 1.8,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "HandlessNorg")
	entry.nextInhaleAt = os.clock() + 2
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

local function mouth(entry): Vector3
	return CreatureKit.feet(entry) + look(entry) * 2.6 + Vector3.new(0, entry.height * 0.4, 0)
end

local function chomp(entry, now: number)
	entry.move = { kind = "chomp", hitAt = now + Tuning.chompWindup, untilAt = now + Tuning.chompSeconds }
	entry.nextChompAt = now + Tuning.chompCooldown
	CreatureKit.pose(entry, "chomp")
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		if entry.move and entry.move.kind == "inhale" then
			CreatureKit.fx("inhaleend", entry.model)
		end
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "inhale" then
			if targetPosition then
				CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(targetPosition - position))
			end
			if now >= move.untilAt then
				CreatureKit.fx("inhaleend", entry.model)
				chomp(entry, now)
			end
			return true
		elseif move.kind == "chomp" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local at = mouth(entry)
				for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp and (hrp.Position - at).Magnitude <= Tuning.chompReach + 1.5 then
						CreatureKit.hurt(entry, player, Tuning.chompDamage)
					end
				end
				CreatureKit.fx("chop", at - Vector3.new(0, entry.height * 0.3, 0))
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

	if distance <= Tuning.chompRange and now >= (entry.nextChompAt or 0) then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		chomp(entry, now)
		return true
	end

	if distance >= Tuning.inhaleMin and distance <= Tuning.inhaleRange and now >= entry.nextInhaleAt
		and not CreatureKit.firstBlock(position + Vector3.new(0, 1.5, 0), targetPosition, 1) then
		entry.nextInhaleAt = now + Tuning.inhaleCooldown
		entry.move = { kind = "inhale", untilAt = now + Tuning.inhaleSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "inhale")
		CreatureKit.fx("inhale", entry.model, Tuning.inhaleSeconds, Tuning.inhaleRange, Tuning.inhaleArc, Tuning.pullSpeed)
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.chompRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

function Trait.finish(entry)
	if entry.move and entry.move.kind == "inhale" then
		CreatureKit.fx("inhaleend", entry.model)
	end
end

return Trait
