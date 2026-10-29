--[[
	Pit Devil - a horned imp of the Crimson with a halberd, and a duelist: it
	does not just walk at you. Head, arms, legs and the halberd are jointed
	(Shared.Enemies.CreatureRigs.PitDevil).

	BLINK (`blinkMin` to `blinkRange`). It vanishes in a burst of fire and
	reappears at your side or behind you, `blinkVanish` seconds later, and
	cleaves at once. The flash where it vanished is the tell: turn round.

	FIRE SPEAR (`throwMin` to `throwRange`). It hauls back and hurls a spear
	of fire on a flat, fast line. Blocks stop it.

	CLEAVE (within `swingRange`). Up close it sweeps the halberd round.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 9,
	slideStep = 2,

	blinkRange = 30,
	blinkMin = 10,
	blinkCooldown = 6.5,
	blinkVanish = 0.35,
	-- Where it reappears: this far from you, off to a side or behind.
	blinkOffset = 3.5,

	throwRange = 38,
	throwMin = 12,
	throwWindup = 0.5,
	throwCooldown = 4.5,
	spearSpeed = 60,
	spearGravity = 12,
	spearDamage = 13,

	swingRange = 4.8,
	swingWindup = 0.3,
	swingSeconds = 0.55,
	swingDamage = 12,
	swingCooldown = 1.5,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "PitDevil")
	CreatureKit.pose(entry, "walk")
end

-- Hides or shows every part, remembering each one's own transparency.
local function setVisible(entry, visible: boolean)
	entry.shown = entry.shown or {}
	for _, part in ipairs(entry.model:GetDescendants()) do
		if part:IsA("BasePart") then
			if visible then
				part.Transparency = entry.shown[part] or 0
			else
				entry.shown[part] = entry.shown[part] or part.Transparency
				part.Transparency = 1
			end
		end
	end
end

local function startSwing(entry, toward: Vector3, now: number, windup: number)
	entry.move = { kind = "swing", hitAt = now + windup, untilAt = now + windup + Tuning.swingSeconds }
	entry.nextSwingAt = now + Tuning.swingCooldown + windup
	CreatureKit.place(entry, CreatureKit.feet(entry), toward)
	CreatureKit.pose(entry, "swing")
end

local function throwSpear(entry, targetPosition: Vector3)
	local feet = CreatureKit.feet(entry)
	local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
	local origin = feet + Vector3.new(0, entry.height * 0.75, 0) + look * 1.5
	if CreatureKit.solidAt(origin) then
		return
	end
	local offset = targetPosition - origin
	local flight = math.max(0.1, Vector3.new(offset.X, 0, offset.Z).Magnitude / Tuning.spearSpeed)
	CreatureKit.projectile({
		origin = origin,
		velocity = Vector3.new(offset.X / flight, (offset.Y + 0.5 * Tuning.spearGravity * flight * flight) / flight, offset.Z / flight),
		gravity = Tuning.spearGravity,
		hitRadius = 2,
		style = "fire",
		onHit = function(_point, players)
			for _, player in ipairs(players) do
				CreatureKit.hurt(entry, player, Tuning.spearDamage)
			end
		end,
	})
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		if entry.move and entry.move.kind == "blink" then
			setVisible(entry, true)
		end
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "blink" then
			if now >= move.appearAt then
				-- Reappear beside or behind you, and cleave at once.
				local goal = (targetPosition or move.aim)
				local away = CreatureKit.flat(position - goal)
				local side = away:Cross(Vector3.yAxis) * move.side
				local spot = goal + (side * 0.8 - away * 0.6).Unit * Tuning.blinkOffset
				local Service = CreatureKit.service()
				local ground = Service.groundAt(spot.X, spot.Z, goal.Y)
				local yours = Service.groundAt(goal.X, goal.Z, goal.Y)
				local feet = Vector3.new(spot.X, ground, spot.Z)
				-- Into a wall or off a ledge from you: come back where it left.
				if math.abs(ground - yours) > 2 or CreatureKit.solidAt(feet + Vector3.new(0, entry.height * 0.5, 0)) then
					feet = CreatureKit.feet(entry)
				end
				CreatureKit.place(entry, feet, CreatureKit.flat(goal - feet))
				setVisible(entry, true)
				CreatureKit.fx("blink", feet + Vector3.new(0, entry.height * 0.5, 0))
				startSwing(entry, CreatureKit.flat(goal - feet), now, Tuning.swingWindup * 0.6)
			end
			return true
		elseif move.kind == "throw" then
			if now >= move.at then
				entry.move = nil
				entry.nextThrowAt = now + Tuning.throwCooldown
				CreatureKit.pose(entry, "walk")
				throwSpear(entry, targetPosition or move.aim)
			end
			return true
		elseif move.kind == "swing" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
				local reach = CreatureKit.feet(entry) + look * 3.2 + Vector3.new(0, entry.height * 0.4, 0)
				CreatureKit.service().touch(entry, reach, Tuning.swingDamage)
				CreatureKit.fx("cleave", entry.model)
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

	if distance <= Tuning.swingRange and now >= (entry.nextSwingAt or 0) then
		startSwing(entry, toward, now, Tuning.swingWindup)
		return true
	end

	if distance >= Tuning.blinkMin and distance <= Tuning.blinkRange and now >= (entry.nextBlinkAt or 0) then
		entry.nextBlinkAt = now + Tuning.blinkCooldown
		entry.move = { kind = "blink", appearAt = now + Tuning.blinkVanish, aim = targetPosition, side = if math.random() < 0.5 then 1 else -1 }
		CreatureKit.pose(entry, "blink")
		CreatureKit.fx("blink", CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.5, 0))
		setVisible(entry, false)
		return true
	end

	if distance >= Tuning.throwMin and distance <= Tuning.throwRange and now >= (entry.nextThrowAt or 0)
		and not CreatureKit.firstBlock(position + Vector3.new(0, 2, 0), targetPosition, 1) then
		entry.move = { kind = "throw", at = now + Tuning.throwWindup, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "throw")
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.swingRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

function Trait.finish(entry)
	if entry.move and entry.move.kind == "blink" then
		setVisible(entry, true)
	end
end

return Trait
