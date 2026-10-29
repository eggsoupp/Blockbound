--[[
	Spotted Demon - a hunched demon of the Corruption that walks on its
	knuckles and hunts unseen. Head, arms and legs are jointed
	(Shared.Enemies.CreatureRigs.SpottedDemon).

	CAMOUFLAGE. While it stalks it is all but invisible - a shimmer of its
	spots (`camoTransparency`). It shows itself when it attacks, and for
	`revealSeconds` after, and whenever it is hurt.

	POUNCE (`pounceMin` to `pounceRange`). It gathers itself for
	`pounceWindup`, then leaps in a high arc to where you stood and lands on
	you: everyone within `landRadius` is hurt for `landDamage`.

	CLAW (within `clawRange`). Up close it rakes with its long right arm.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 7,
	slideStep = 2,

	camoTransparency = 0.88,
	revealSeconds = 3,

	pounceRange = 20,
	pounceMin = 8,
	pounceWindup = 0.55,
	pounceSeconds = 0.65,
	pounceHeight = 6,
	pounceCooldown = 6,
	landRadius = 3.5,
	landDamage = 13,

	clawRange = 3.8,
	clawReach = 3,
	clawWindup = 0.35,
	clawSeconds = 0.7,
	clawDamage = 10,
	clawCooldown = 1.4,
}

local Trait = {}
Trait.Tuning = Tuning

-- Fades the whole model toward `share` transparency, remembering each part's
-- own so it can come back exactly.
local function fade(entry, share: number)
	if entry.faded == share then
		return
	end
	entry.faded = share
	entry.own = entry.own or {}
	for _, part in ipairs(entry.model:GetDescendants()) do
		if part:IsA("BasePart") then
			local own = entry.own[part]
			if own == nil then
				own = part.Transparency
				entry.own[part] = own
			end
			part.Transparency = own + (1 - own) * share
		end
	end
end

local function reveal(entry, now: number)
	entry.revealUntil = now + Tuning.revealSeconds
	if entry.faded ~= 0 then
		fade(entry, 0)
		CreatureKit.fx("poof", CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.5, 0))
	end
end

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "SpottedDemon")
	CreatureKit.pose(entry, "walk")
	fade(entry, Tuning.camoTransparency)
end

function Trait.guard(entry)
	reveal(entry, os.clock())
	return 1
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	local move = entry.move
	if move and move.kind == "pounce" then
		local k = math.min(1, (now - move.startedAt) / Tuning.pounceSeconds)
		local at = move.from:Lerp(move.to, k) + Vector3.new(0, math.sin(k * math.pi) * Tuning.pounceHeight, 0)
		CreatureKit.place(entry, at, move.facing)
		if k >= 1 then
			entry.groundY = move.to.Y
			entry.move = { kind = "recover", untilAt = now + 0.4 }
			CreatureKit.pose(entry, "walk")
			CreatureKit.fx("slam", move.to, Tuning.landRadius)
			CreatureKit.hurtSphere(entry, move.to + Vector3.new(0, 1.5, 0), Tuning.landRadius, Tuning.landDamage, 0.6)
		end
		return true
	end

	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	-- Unseen again once nothing has given it away for a while.
	if not move and now >= (entry.revealUntil or 0) then
		fade(entry, Tuning.camoTransparency)
	end

	if move then
		if move.kind == "crouch" then
			if now >= move.at then
				local from = CreatureKit.feet(entry)
				local aim = targetPosition or move.aim
				local flat = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z)
				-- Land just short of the target, on the ground there.
				local spot = from + flat - flat.Unit * 1
				local ground = CreatureKit.service().groundAt(spot.X, spot.Z, aim.Y)
				local to = Vector3.new(spot.X, ground, spot.Z)
				if math.abs(ground - from.Y) > 8 or CreatureKit.solidAt(to + Vector3.new(0, entry.height * 0.5, 0)) then
					entry.move = nil
					CreatureKit.pose(entry, "walk")
				else
					entry.move = { kind = "pounce", from = from, to = to, startedAt = now, facing = flat.Unit }
					CreatureKit.pose(entry, "pounce")
				end
			end
			return true
		elseif move.kind == "claw" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local reach = CreatureKit.feet(entry) + look(entry) * Tuning.clawReach + Vector3.new(0, 1.5, 0)
				CreatureKit.service().touch(entry, reach, Tuning.clawDamage)
				CreatureKit.fx("cut", entry.model)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "recover" then
			if now >= move.untilAt then
				entry.move = nil
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

	if distance <= Tuning.clawRange and now >= (entry.nextClawAt or 0) then
		entry.nextClawAt = now + Tuning.clawCooldown
		entry.move = { kind = "claw", hitAt = now + Tuning.clawWindup, untilAt = now + Tuning.clawSeconds }
		reveal(entry, now)
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "claw")
		return true
	end

	if distance >= Tuning.pounceMin and distance <= Tuning.pounceRange and now >= (entry.nextPounceAt or 0)
		and not CreatureKit.firstBlock(position + Vector3.new(0, 2, 0), targetPosition, 1) then
		entry.nextPounceAt = now + Tuning.pounceCooldown
		entry.move = { kind = "crouch", at = now + Tuning.pounceWindup, aim = targetPosition }
		reveal(entry, now)
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "crouch")
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.clawRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
