--[[
	Wormy Horror - the Corruption's stalker: a hanging, mouthed body on four
	long arched legs (Shared.Enemies.CreatureRigs.WormyHorror). It walks
	slowly and never stops coming.

	ICHOR (`spitMin` to `spitRange`, with a clear line). It throws its mouth
	up and spits a glob of corrupt ichor. A hit burns: `ichorDamage` on
	impact, then `burnTicks` more every `burnInterval`.

	IMPALE (within `impaleRange`). It rears its two front legs high - the
	tell - and stabs them down at a point in front of itself, fixed when the
	rear began. Anyone inside `impaleRadius` of it is skewered. Stepping
	back out of reach, or round to its side, is the answer.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 6.5,
	slideStep = 2.2,
	keepDistance = 4,

	spitRange = 32,
	spitMin = 10,
	spitWindup = 0.5,
	spitCooldown = 5,
	spitSpeed = 36,
	spitGravity = 45,
	ichorDamage = 5,
	burnTicks = 3,
	burnInterval = 0.8,
	burnDamage = 3,

	impaleRange = 8,
	rearSeconds = 0.7,
	stabSeconds = 0.4,
	impaleReach = 4.5,
	impaleRadius = 3.5,
	impaleDamage = 17,
	impaleCooldown = 2.8,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "WormyHorror")
	CreatureKit.pose(entry, "walk")
end

local function spit(entry, targetPosition: Vector3)
	local feet = CreatureKit.feet(entry)
	local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
	local origin = feet + Vector3.new(0, entry.height * 0.55, 0) + look * 2
	if CreatureKit.solidAt(origin) then
		return
	end
	local offset = targetPosition - origin
	local flight = math.clamp(Vector3.new(offset.X, 0, offset.Z).Magnitude / Tuning.spitSpeed, 0.25, 1.2)
	CreatureKit.projectile({
		origin = origin,
		velocity = Vector3.new(offset.X / flight, (offset.Y + 0.5 * Tuning.spitGravity * flight * flight) / flight, offset.Z / flight),
		gravity = Tuning.spitGravity,
		hitRadius = 2,
		style = "ichor",
		onHit = function(_point, players)
			for _, player in ipairs(players) do
				CreatureKit.hurt(entry, player, Tuning.ichorDamage)
				for tick = 1, Tuning.burnTicks do
					task.delay(tick * Tuning.burnInterval, function()
						if player.Parent then
							CreatureKit.hurt(entry, player, Tuning.burnDamage)
						end
					end)
				end
				CreatureKit.fx("burn", player.Character, Tuning.burnTicks * Tuning.burnInterval)
			end
		end,
	})
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "spit" then
			if now >= move.fireAt then
				entry.move = nil
				entry.nextSpitAt = now + Tuning.spitCooldown
				spit(entry, targetPosition or move.aim)
				CreatureKit.pose(entry, "walk")
			end
		elseif move.kind == "impale" then
			if not move.stabbed and now >= move.stabAt then
				move.stabbed = true
				CreatureKit.pose(entry, "stab")
				local centre = move.point + Vector3.new(0, 2, 0)
				for _, player in ipairs(CreatureKit.playersAlong(centre, centre, Tuning.impaleRadius)) do
					CreatureKit.hurt(entry, player, Tuning.impaleDamage)
				end
				CreatureKit.fx("impale", move.point, Tuning.impaleRadius)
			end
			if now >= move.stabAt + Tuning.stabSeconds then
				entry.move = nil
				entry.nextImpaleAt = now + Tuning.impaleCooldown
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

	if distance <= Tuning.impaleRange and now >= (entry.nextImpaleAt or 0) then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		entry.move = {
			kind = "impale",
			stabAt = now + Tuning.rearSeconds,
			point = CreatureKit.feet(entry) + toward * Tuning.impaleReach,
		}
		CreatureKit.pose(entry, "rear")
		CreatureKit.fx("flare", entry.model, Color3.fromRGB(170, 110, 255))
		return true
	end

	if distance >= Tuning.spitMin and distance <= Tuning.spitRange and now >= (entry.nextSpitAt or 0)
		and not CreatureKit.firstBlock(position + Vector3.new(0, 2, 0), targetPosition, 1) then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		entry.move = { kind = "spit", fireAt = now + Tuning.spitWindup, aim = targetPosition }
		CreatureKit.pose(entry, "spit")
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.keepDistance then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
