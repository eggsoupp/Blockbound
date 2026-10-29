--[[
	Green Spider - a swamp hunter on eight jointed legs. It scuttles over the
	ground in quick bursts with little stops between, the way a spider does,
	its legs stepping in two alternating sets (drawn by each client from the
	speed it is actually moving at; see Shared.Enemies.CreatureRigs).

	WEB (`webRange`). It rears, then spits a glob of web on a flat arc. A hit
	does a little damage and SLOWS you for `slowSeconds` - which is what sets
	up the pounce. Blocks stop it.

	POUNCE (within `pounceRange`). Front legs up for `pounceWindup` - the
	tell - then a committed leap at you. The leap is the ordinary hop
	movement's lunge (EnemyConfig's lunge numbers), so it lands, takes
	knockback and climbs steps like any hopper.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	scuttleSpeed = 11,
	-- Seconds of scuttling, then of stillness, each rolled in this range.
	burst = NumberRange.new(0.7, 1.5),
	stop = NumberRange.new(0.15, 0.45),
	slideStep = 2,
	-- Distance it likes to keep while the web is on cooldown.
	closeDistance = 2,

	webRange = 30,
	webMinRange = 9,
	webWindup = 0.45,
	webCooldown = 6,
	webSpeed = 42,
	webGravity = 30,
	webDamage = 5,
	slowMultiplier = 0.45,
	slowSeconds = 2.6,

	pounceRange = 11,
	pounceWindup = 0.55,
	pounceCooldown = 3.2,
}

local Trait = {}
Trait.Tuning = Tuning

local function roll(range: NumberRange): number
	return range.Min + math.random() * (range.Max - range.Min)
end

local function spit(entry, targetPosition: Vector3)
	local feet = CreatureKit.feet(entry)
	local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
	local origin = feet + Vector3.new(0, entry.height * 0.8, 0) + look * 1.5
	if CreatureKit.solidAt(origin) then
		return
	end

	local offset = targetPosition - origin
	local flight = math.clamp(Vector3.new(offset.X, 0, offset.Z).Magnitude / Tuning.webSpeed, 0.2, 1.2)
	local velocity = Vector3.new(offset.X / flight, (offset.Y + 0.5 * Tuning.webGravity * flight * flight) / flight, offset.Z / flight)

	CreatureKit.projectile({
		origin = origin,
		velocity = velocity,
		gravity = Tuning.webGravity,
		hitRadius = 2,
		style = "web",
		onHit = function(_point, players)
			for _, player in ipairs(players) do
				CreatureKit.hurt(entry, player, Tuning.webDamage)
				CreatureKit.slow(player, Tuning.slowMultiplier, Tuning.slowSeconds)
			end
		end,
	})
end

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "GreenSpider")
	CreatureKit.pose(entry, "walk")
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	-- In the air (a pounce, a fall, a knockback): the hop movement has it.
	if entry.state ~= "Grounded" then
		entry.move = nil
		local pose = if entry.lunging then "leap"
			elseif entry.state == "Windup" and entry.pendingLunge then "rear"
			else "walk"
		CreatureKit.pose(entry, pose)
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "web" then
			if now >= move.fireAt then
				entry.move = nil
				entry.nextWebAt = now + Tuning.webCooldown
				CreatureKit.pose(entry, "walk")
				spit(entry, targetPosition or move.aim)
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

	-- Pounce: hand a lunge wind-up to the hop movement, which leaps when it ends.
	if distance <= Tuning.pounceRange and now >= (entry.nextPounceAt or 0) then
		entry.nextPounceAt = now + Tuning.pounceCooldown + Tuning.pounceWindup
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "rear")
		CreatureKit.fx("flare", entry.model, Color3.fromRGB(150, 255, 90))
		entry.state = "Windup"
		entry.pendingLunge = true
		entry.stateUntil = now + Tuning.pounceWindup
		return false
	end

	-- Web: rear and spit.
	if distance >= Tuning.webMinRange and distance <= Tuning.webRange and now >= (entry.nextWebAt or 0)
		and not CreatureKit.firstBlock(position, targetPosition, 1) then
		entry.move = { kind = "web", fireAt = now + Tuning.webWindup, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "rear")
		return true
	end

	-- Scuttle in bursts.
	if now >= (entry.burstEndsAt or 0) then
		if entry.stopped then
			entry.stopped = false
			entry.burstEndsAt = now + roll(Tuning.burst)
		else
			entry.stopped = true
			entry.burstEndsAt = now + roll(Tuning.stop)
		end
	end

	if entry.stopped or distance <= Tuning.closeDistance then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end

	if not CreatureKit.slide(entry, toward * Tuning.scuttleSpeed * dt, toward, nil, Tuning.slideStep) then
		-- A step or a drop: an ordinary hop gets it over.
		return false
	end
	CreatureKit.service().touch(entry, CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.5, 0))
	return true
end

return Trait
