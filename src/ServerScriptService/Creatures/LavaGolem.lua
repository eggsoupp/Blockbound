--[[
	Lava Golem - a slow, enormous lump of the Crimson's rock with lava in its
	cracks. It does not chase so much as take the ground away from you. Head,
	arms and legs are jointed (Shared.Enemies.CreatureRigs.LavaGolem).

	MAGMA FOOTSTEPS. While it walks it leaves a pool of magma every
	`trailInterval`, `poolRadius` across, for `poolSeconds`. Standing in one
	burns for `poolDamage` every `poolInterval`. The pools outlive the golem.

	ERUPTION LINE (`eruptMin` to `eruptRange`). Fists raised, then driven into
	the ground: a line of `eruptCount` eruptions bursts from its feet toward
	where you stood, one after another, each hurting everyone within
	`eruptRadius` once. Step off the line.

	PUNCH (within `punchRange`). A slow, heavy fist.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 4.5,
	slideStep = 2,

	trailInterval = 1.1,
	poolRadius = 2.4,
	poolSeconds = 5,
	poolInterval = 0.5,
	poolDamage = 3,

	eruptRange = 22,
	eruptMin = 6,
	eruptWindup = 0.9,
	eruptCount = 7,
	eruptSpacing = 3,
	eruptDelay = 0.12,
	eruptRadius = 2.4,
	eruptDamage = 12,
	eruptCooldown = 7,
	eruptSeconds = 1.3,

	punchRange = 4.5,
	punchReach = 3.5,
	punchWindup = 0.55,
	punchSeconds = 1,
	punchDamage = 14,
	punchCooldown = 2.2,
}

local Trait = {}
Trait.Tuning = Tuning

--[[
	Every pool any golem has left, ticked here rather than by its golem, so a
	pool keeps burning after the thing that made it has died.
]]
local pools = {}
local ticker

local function tickPools()
	local now = os.clock()
	for i = #pools, 1, -1 do
		local pool = pools[i]
		if now >= pool.untilAt then
			table.remove(pools, i)
		elseif now >= pool.nextBurnAt then
			pool.nextBurnAt = now + Tuning.poolInterval
			for _, player in ipairs(Players:GetPlayers()) do
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local offset = hrp.Position - pool.center
					if Vector3.new(offset.X, 0, offset.Z).Magnitude <= Tuning.poolRadius and offset.Y >= -1 and offset.Y <= 4.5 then
						CreatureKit.hurt(pool.entry, player, Tuning.poolDamage)
					end
				end
			end
		end
	end
	if #pools == 0 and ticker then
		ticker:Disconnect()
		ticker = nil
	end
end

local function dropPool(entry, at: Vector3)
	for _, pool in ipairs(pools) do
		if (pool.center - at).Magnitude < Tuning.poolRadius * 1.2 then
			return
		end
	end
	local now = os.clock()
	table.insert(pools, { entry = entry, center = at, untilAt = now + Tuning.poolSeconds, nextBurnAt = now + Tuning.poolInterval })
	CreatureKit.fx("magma", at, Tuning.poolRadius, Tuning.poolSeconds)
	if not ticker then
		ticker = RunService.Heartbeat:Connect(tickPools)
	end
end

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "LavaGolem")
	entry.nextPoolAt = os.clock() + Tuning.trailInterval
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- The line of eruptions, one at a time outward from its feet.
local function erupt(entry, toward: Vector3)
	local Service = CreatureKit.service()
	local feet = CreatureKit.feet(entry)
	local hit = {}
	for i = 1, Tuning.eruptCount do
		task.delay(i * Tuning.eruptDelay, function()
			local along = feet + toward * (1.5 + i * Tuning.eruptSpacing)
			local ground = Service.groundAt(along.X, along.Z, feet.Y)
			if math.abs(ground - feet.Y) > 6 then
				return
			end
			local at = Vector3.new(along.X, ground, along.Z)
			CreatureKit.fx("erupt", at, Tuning.eruptRadius)
			for _, player in ipairs(Players:GetPlayers()) do
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and not hit[player] then
					local offset = hrp.Position - at
					if Vector3.new(offset.X, 0, offset.Z).Magnitude <= Tuning.eruptRadius and offset.Y <= 6 and offset.Y >= -2 then
						hit[player] = true
						CreatureKit.hurt(entry, player, Tuning.eruptDamage)
					end
				end
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
		if move.kind == "slam" then
			if not move.fired and now >= move.at then
				move.fired = true
				CreatureKit.fx("slam", CreatureKit.feet(entry) + look(entry) * 1.5, 3)
				erupt(entry, move.toward)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "punch" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local reach = CreatureKit.feet(entry) + look(entry) * Tuning.punchReach + Vector3.new(0, 2, 0)
				CreatureKit.service().touch(entry, reach, Tuning.punchDamage)
				CreatureKit.fx("chop", CreatureKit.feet(entry) + look(entry) * Tuning.punchReach)
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

	if distance <= Tuning.punchRange and now >= (entry.nextPunchAt or 0) then
		entry.nextPunchAt = now + Tuning.punchCooldown
		entry.move = { kind = "punch", hitAt = now + Tuning.punchWindup, untilAt = now + Tuning.punchSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "punch")
		return true
	end

	if distance >= Tuning.eruptMin and distance <= Tuning.eruptRange and now >= (entry.nextEruptAt or 0) then
		entry.nextEruptAt = now + Tuning.eruptCooldown
		entry.move = { kind = "slam", at = now + Tuning.eruptWindup, untilAt = now + Tuning.eruptSeconds, toward = toward }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "slam")
		CreatureKit.fx("roar", entry.model, Tuning.eruptWindup)
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.punchRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	-- Walking or hopping a step, it is on the move and leaves its trail.
	if now >= entry.nextPoolAt then
		entry.nextPoolAt = now + Tuning.trailInterval
		dropPool(entry, CreatureKit.feet(entry))
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
