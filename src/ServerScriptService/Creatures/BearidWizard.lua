--[[
	Bearid Wizard - a robed bear mage of the snow. Heavy and slow; it holds
	the middle distance and makes the ground itself dangerous. Head, arms
	(the staff in its right paw) and legs are jointed (Shared.Enemies.
	CreatureRigs.BearidWizard).

	FROST SPIKES (`spikeMin` to `spikeRange`). It raises its staff for
	`channelSeconds`, then slams it down: frost circles appear on the ground
	where you are and either side of you (led a little toward where you are
	going), and `eruptDelay` later ice erupts from each. A spike that catches
	you does `spikeDamage` and slows you. Keep moving - but not into the
	side circles.

	BONK (within `bonkRange`). Close in and it swings the staff over its head
	and down at you.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 5.5,
	slideStep = 2,
	-- It stops closing at this distance: a caster, not a brawler.
	holdDistance = 12,

	spikeRange = 34,
	spikeMin = 6,
	channelSeconds = 0.7,
	slamSeconds = 0.35,
	spikeCooldown = 5,
	-- Seconds of lead on your movement for the middle circle.
	lead = 0.6,
	sideSpacing = 4.5,
	eruptDelay = 1.0,
	spikeRadius = 2.6,
	spikeDamage = 14,
	slowMultiplier = 0.55,
	slowSeconds = 1.6,

	bonkRange = 5,
	bonkWindup = 0.35,
	bonkSeconds = 0.6,
	bonkDamage = 12,
	bonkCooldown = 2,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "BearidWizard")
	CreatureKit.pose(entry, "walk")
end

-- Marks three circles about `target`, and erupts them `eruptDelay` later.
local function castSpikes(entry, target: Player, targetPosition: Vector3)
	local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
	local centre = targetPosition + Vector3.new(velocity.X, 0, velocity.Z) * Tuning.lead
	local feet = CreatureKit.feet(entry)
	local across = CreatureKit.flat(centre - feet):Cross(Vector3.yAxis)
	if across.Magnitude < 1e-3 then
		across = Vector3.xAxis
	end

	local points = {}
	for _, offset in ipairs({ 0, -Tuning.sideSpacing, Tuning.sideSpacing }) do
		local at = centre + across * offset
		local ground = CreatureKit.service().groundAt(at.X, at.Z, targetPosition.Y)
		local point = Vector3.new(at.X, ground, at.Z)
		table.insert(points, point)
		CreatureKit.fx("frostmark", point, Tuning.spikeRadius, Tuning.eruptDelay)
	end

	task.delay(Tuning.eruptDelay, function()
		local hit = {}
		for _, point in ipairs(points) do
			CreatureKit.fx("frostspike", point, Tuning.spikeRadius)
			local centreOfSpike = point + Vector3.new(0, 2, 0)
			for _, player in ipairs(CreatureKit.playersAlong(centreOfSpike, centreOfSpike, Tuning.spikeRadius + 0.5)) do
				if not hit[player] then
					hit[player] = true
					CreatureKit.hurt(entry, player, Tuning.spikeDamage)
					CreatureKit.slow(player, Tuning.slowMultiplier, Tuning.slowSeconds)
				end
			end
		end
	end)
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "spikes" then
			if not move.slammed and now >= move.slamAt then
				move.slammed = true
				CreatureKit.pose(entry, "slam")
				if target and targetPosition then
					castSpikes(entry, target, targetPosition)
				end
			end
			if now >= move.slamAt + Tuning.slamSeconds then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
		elseif move.kind == "bonk" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
				CreatureKit.service().touch(entry, CreatureKit.feet(entry) + look * 3.5 + Vector3.new(0, 2, 0), Tuning.bonkDamage)
				CreatureKit.fx("slam", CreatureKit.feet(entry) + look * 3.5, 3)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
		end
		return true
	end

	if not (target and targetPosition) then
		CreatureKit.pose(entry, "walk")
		return false
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

	if distance <= Tuning.bonkRange and now >= (entry.nextBonkAt or 0) then
		entry.nextBonkAt = now + Tuning.bonkCooldown
		entry.move = { kind = "bonk", hitAt = now + Tuning.bonkWindup, untilAt = now + Tuning.bonkSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "bonk")
		return true
	end

	if distance >= Tuning.spikeMin and distance <= Tuning.spikeRange and now >= (entry.nextSpikeAt or 0) then
		entry.nextSpikeAt = now + Tuning.spikeCooldown
		entry.move = { kind = "spikes", slamAt = now + Tuning.channelSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "channel")
		CreatureKit.fx("flare", entry.model, Color3.fromRGB(180, 230, 255))
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.holdDistance and distance > Tuning.bonkRange then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
