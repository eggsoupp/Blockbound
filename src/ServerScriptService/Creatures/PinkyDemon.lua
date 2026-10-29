--[[
	Pinky Demon - a hunched pink brute of the Crimson, slow and enormously
	strong. Head, arms and legs are jointed (Shared.Enemies.CreatureRigs.
	PinkyDemon).

	GROUND POUND (within `poundRange`). Both fists hauled overhead for
	`poundWindup` and driven into the ground, and `waveCount` shockwaves roll
	out across it one after another (`waveGap` apart), each a ring growing at
	`waveSpeed` to `waveRadius`. A wave hurts anyone ON THE GROUND as it passes
	them (`waveDamage`, once per wave) - jump it.

	PUNCH (within `punchRange`). A slow, heavy right.
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 5,
	slideStep = 2,

	poundRange = 14,
	poundWindup = 0.9,
	poundSeconds = 1.6,
	poundCooldown = 7,
	waveCount = 3,
	waveGap = 0.65,
	waveSpeed = 13,
	waveRadius = 18,
	-- How thick the ring is that hurts, in studs.
	waveBand = 1.4,
	waveDamage = 11,
	-- Feet this far above the ground under them clear a wave.
	jumpClear = 1.2,

	punchRange = 4.5,
	punchReach = 3.6,
	punchWindup = 0.5,
	punchSeconds = 0.9,
	punchDamage = 14,
	punchCooldown = 2,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "PinkyDemon")
	entry.waves = {}
	entry.nextPoundAt = os.clock() + 2
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- Every live wave grows each tick and hurts whoever on the ground it
-- passes over.
local function stepWaves(entry, now: number)
	local Service = CreatureKit.service()
	for i = #entry.waves, 1, -1 do
		local wave = entry.waves[i]
		local radius = (now - wave.startedAt) * Tuning.waveSpeed
		if radius > Tuning.waveRadius + Tuning.waveBand then
			table.remove(entry.waves, i)
		elseif radius > 0 then
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if hrp and humanoid and not wave.hit[player] then
					local offset = Vector3.new(hrp.Position.X - wave.center.X, 0, hrp.Position.Z - wave.center.Z)
					if math.abs(offset.Magnitude - radius) <= Tuning.waveBand
						and math.abs(hrp.Position.Y - wave.center.Y) <= 8 then
						local ground = Service.groundAt(hrp.Position.X, hrp.Position.Z, hrp.Position.Y)
						local feetY = hrp.Position.Y - humanoid.HipHeight - hrp.Size.Y * 0.5
						if feetY - ground <= Tuning.jumpClear then
							wave.hit[player] = true
							CreatureKit.hurt(entry, player, Tuning.waveDamage)
						end
					end
				end
			end
		end
	end
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	stepWaves(entry, now)

	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "pound" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local center = CreatureKit.feet(entry) + look(entry) * 2
				for k = 0, Tuning.waveCount - 1 do
					table.insert(entry.waves, { center = center, startedAt = now + k * Tuning.waveGap, hit = {} })
				end
				CreatureKit.fx("slam", center, 4)
				CreatureKit.fx("shockwave", center, Tuning.waveSpeed, Tuning.waveRadius, Tuning.waveCount, Tuning.waveGap)
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

	if distance <= Tuning.poundRange and now >= (entry.nextPoundAt or 0) then
		entry.nextPoundAt = now + Tuning.poundCooldown
		entry.move = { kind = "pound", hitAt = now + Tuning.poundWindup, untilAt = now + Tuning.poundSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "pound")
		CreatureKit.fx("roar", entry.model, Tuning.poundWindup)
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.punchRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
