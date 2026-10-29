--[[
	Rooster - a big, belligerent cockerel of the Plains, and a rabble-rouser.
	Not much on its own; deadly in company. Head, wings, legs and tail are
	jointed (Shared.Enemies.CreatureRigs.Rooster).

	RALLYING CROW (with a target within `crowRange`). It stops, puffs up and
	crows, and every other creature within `rallyRadius` of it hits
	`rallyScale` times as hard for `rallySeconds` - each one marked with a red
	glow while it lasts. Kill the rooster first.

	FLUTTERING LEAP (`leapMin` to `leapRange`). Wings beating, it hops at you
	- the ordinary hop's lunge.

	PECKS (within `peckRange`). A flurry of `peckCount` quick stabs.
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 9,
	slideStep = 2,

	crowRange = 30,
	crowWindup = 0.5,
	crowSeconds = 1.2,
	crowCooldown = 11,
	rallyRadius = 26,
	rallyScale = 1.5,
	rallySeconds = 6,

	leapRange = 12,
	leapMin = 5,
	leapWindup = 0.3,
	leapCooldown = 3.5,

	peckRange = 2.6,
	peckReach = 1.8,
	peckCount = 3,
	peckGap = 0.16,
	peckDamage = 3,
	peckCooldown = 1.4,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "Rooster")
	entry.nextCrowAt = os.clock() + 1.5
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- Every other creature nearby hits harder for a while; one rally at a time
-- each, taken back off exactly as it was put on.
local function rally(entry)
	local Service = CreatureKit.service()
	local position = entry.model:GetPivot().Position
	CreatureKit.fx("crow", entry.model)
	Service.forEachNear(position, Tuning.rallyRadius, function(model)
		if model == entry.model or model:GetAttribute("Rallied") then
			return
		end
		local scale = Service.damageScaleOf(model)
		if not scale then
			return
		end
		model:SetAttribute("Rallied", true)
		Service.setDamageScale(model, scale * Tuning.rallyScale)
		CreatureKit.fx("rallied", model, Tuning.rallySeconds)
		task.delay(Tuning.rallySeconds, function()
			if model.Parent then
				model:SetAttribute("Rallied", nil)
				local now = Service.damageScaleOf(model)
				if now then
					Service.setDamageScale(model, now / Tuning.rallyScale)
				end
			end
		end)
	end)
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "crow" then
			if not move.fired and now >= move.at then
				move.fired = true
				rally(entry)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "peck" then
			local due = move.startedAt + Tuning.peckGap * (move.done + 1)
			if move.done < Tuning.peckCount and now >= due then
				move.done += 1
				local reach = CreatureKit.feet(entry) + look(entry) * Tuning.peckReach + Vector3.new(0, 1.2, 0)
				for _, player in ipairs(Players:GetPlayers()) do
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp and (hrp.Position - reach).Magnitude <= 2.6 then
						CreatureKit.hurt(entry, player, Tuning.peckDamage)
					end
				end
			end
			if now >= move.startedAt + Tuning.peckGap * (Tuning.peckCount + 1) + 0.2 then
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

	if distance <= Tuning.crowRange and now >= (entry.nextCrowAt or 0) then
		entry.nextCrowAt = now + Tuning.crowCooldown
		entry.move = { kind = "crow", at = now + Tuning.crowWindup, untilAt = now + Tuning.crowSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "crow")
		return true
	end

	if distance <= Tuning.peckRange and now >= (entry.nextPeckAt or 0) then
		entry.nextPeckAt = now + Tuning.peckCooldown
		entry.move = { kind = "peck", startedAt = now, done = 0 }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "peck")
		return true
	end

	if distance >= Tuning.leapMin and distance <= Tuning.leapRange and now >= (entry.nextLeapAt or 0) then
		entry.nextLeapAt = now + Tuning.leapCooldown
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "flutter")
		entry.state = "Windup"
		entry.pendingLunge = true
		entry.stateUntil = now + Tuning.leapWindup
		return false
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.peckRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
