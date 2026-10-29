--[[
	Goat Shaman - a robed goat of the Snow with a fire-orbed staff. It keeps
	back and works weather. Head, arms, staff and legs are jointed
	(Shared.Enemies.CreatureRigs.GoatShaman).

	FIRE ORB (`lobMin` to `lobRange`). The staff swung up flings a ball of
	fire on a high arc; it bursts where it lands, hurting everyone within
	`orbRadius`.

	BLIZZARD (within `stormRange`). It raises its staff and chants, and a
	blizzard comes down where you stood - `stormRadius` across, for as long as
	it keeps chanting (`stormSeconds`). Inside, every `stormInterval` you are
	chilled for `stormDamage` and slowed to `stormSlow`. Walk out of it - or
	break the chant: `breakDamage` worth of hits while it chants ends the storm
	at once.

	STAFF JAB (within `jabRange`). Up close it jabs you with the staff.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 6,
	slideStep = 2,
	keepMin = 9,
	keepMax = 17,

	lobRange = 28,
	lobMin = 6,
	lobWindup = 0.5,
	lobCooldown = 3,
	lobFlight = 0.9,
	orbRadius = 3.2,
	orbDamage = 10,

	stormRange = 24,
	stormWindup = 0.6,
	stormSeconds = 5,
	stormRadius = 7,
	stormInterval = 0.5,
	stormDamage = 3,
	stormSlow = 0.5,
	stormCooldown = 13,
	breakDamage = 15,

	jabRange = 4,
	jabReach = 3.5,
	jabWindup = 0.25,
	jabSeconds = 0.6,
	jabDamage = 8,
	jabCooldown = 1.8,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "GoatShaman")
	entry.nextStormAt = os.clock() + 3
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

local function endStorm(entry, now: number)
	local storm = entry.move
	if storm and storm.kind == "storm" then
		CreatureKit.fx("blizzardend", storm.id)
		entry.move = { kind = "recover", untilAt = now + 0.4 }
		CreatureKit.pose(entry, "walk")
	end
end

-- Hits taken while it chants add up; enough of them break the chant.
function Trait.guard(entry, amount)
	local storm = entry.move
	if storm and storm.kind == "storm" then
		storm.taken += amount
		if storm.taken >= Tuning.breakDamage then
			CreatureKit.fx("stunned", entry.model, 0.8)
			endStorm(entry, os.clock())
		end
	end
	return 1
end

local function lob(entry, aim: Vector3)
	local origin = CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.8, 0) + look(entry) * 1.5
	if CreatureKit.solidAt(origin) then
		return
	end
	local gravity = 50
	local t = Tuning.lobFlight
	local offset = aim - origin
	CreatureKit.projectile({
		origin = origin,
		velocity = Vector3.new(offset.X / t, (offset.Y + 0.5 * gravity * t * t) / t, offset.Z / t),
		gravity = gravity,
		hitRadius = 1.6,
		maxLife = t + 1,
		style = "fire",
		onHit = function(point)
			CreatureKit.hurtSphere(entry, point + Vector3.new(0, 1, 0), Tuning.orbRadius, Tuning.orbDamage, 0.5)
		end,
	})
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		endStorm(entry, now)
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "lob" then
			if now >= move.at then
				entry.move = nil
				lob(entry, targetPosition or move.aim)
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "summon" then
			if now >= move.at then
				local ground = CreatureKit.service().groundAt(move.aim.X, move.aim.Z, move.aim.Y)
				local center = Vector3.new(move.aim.X, ground, move.aim.Z)
				local id = tostring(entry.model) .. tostring(now)
				entry.move = {
					kind = "storm", id = id, center = center, taken = 0,
					untilAt = now + Tuning.stormSeconds, nextChillAt = now + Tuning.stormInterval,
				}
				CreatureKit.fx("blizzard", id, center, Tuning.stormRadius, Tuning.stormSeconds)
			end
			return true
		elseif move.kind == "storm" then
			if targetPosition then
				CreatureKit.place(entry, CreatureKit.feet(entry), CreatureKit.flat(targetPosition - position))
			end
			if now >= move.nextChillAt then
				move.nextChillAt = now + Tuning.stormInterval
				for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						local offset = hrp.Position - move.center
						if Vector3.new(offset.X, 0, offset.Z).Magnitude <= Tuning.stormRadius and math.abs(offset.Y) <= 8 then
							CreatureKit.hurt(entry, player, Tuning.stormDamage)
							CreatureKit.slow(player, Tuning.stormSlow, Tuning.stormInterval + 0.3)
						end
					end
				end
			end
			if now >= move.untilAt then
				endStorm(entry, now)
			end
			return true
		elseif move.kind == "jab" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local reach = CreatureKit.feet(entry) + look(entry) * Tuning.jabReach + Vector3.new(0, 1.5, 0)
				CreatureKit.service().touch(entry, reach, Tuning.jabDamage)
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

	if distance <= Tuning.jabRange and now >= (entry.nextJabAt or 0) then
		entry.nextJabAt = now + Tuning.jabCooldown
		entry.move = { kind = "jab", hitAt = now + Tuning.jabWindup, untilAt = now + Tuning.jabSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "jab")
		return true
	end

	if distance <= Tuning.stormRange and now >= (entry.nextStormAt or 0)
		and not CreatureKit.firstBlock(position + Vector3.new(0, 2, 0), targetPosition, 1) then
		entry.nextStormAt = now + Tuning.stormCooldown
		entry.move = { kind = "summon", at = now + Tuning.stormWindup, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "chant")
		CreatureKit.fx("flare", entry.model, Color3.fromRGB(190, 230, 255))
		return true
	end

	if distance >= Tuning.lobMin and distance <= Tuning.lobRange and now >= (entry.nextLobAt or 0) then
		entry.nextLobAt = now + Tuning.lobCooldown
		entry.move = { kind = "lob", at = now + Tuning.lobWindup, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "lob")
		return true
	end

	CreatureKit.pose(entry, "walk")
	local heading
	if distance > Tuning.keepMax then
		heading = toward
	elseif distance < Tuning.keepMin then
		heading = -toward
	else
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, heading * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		if heading == toward then
			return false
		end
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
	end
	return true
end

function Trait.finish(entry)
	local storm = entry.move
	if storm and storm.kind == "storm" then
		CreatureKit.fx("blizzardend", storm.id)
	end
end

return Trait
