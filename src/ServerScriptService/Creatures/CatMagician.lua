--[[
	Black Cat Magician - a top-hatted cat of the Hallow with a wand. It keeps
	its distance and does tricks. Head, arms, wand, legs and tail are jointed
	(Shared.Enemies.CreatureRigs.CatMagician).

	WAND BOLT (`boltMin` to `boltRange`). A flourish, then a bolt of
	sparkling magic straight at you. Blocks stop it.

	SMOKE AND MIRRORS (within `trickRange`). It throws its arms up and goes
	up in smoke, and three magicians step out of smoke around you, evenly
	spaced, in no particular order: itself and `decoys` copies. The copies move,
	cast and look exactly like it, but their bolts are harmless and any blow
	pops them. They fade after `decoyLife`, or when the real one dies.

	VANISH (inside `vanishRange`). Too close for comfort: a puff of smoke and
	it is `vanishDistance` away.

	DECOYS are their own enemy, CatMagicianDecoy, on this same trait: one
	health, no drops, flagged `decoy` on the definition.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 7,
	slideStep = 2,
	-- The band it tries to stay in.
	keepMin = 9,
	keepMax = 15,

	boltRange = 30,
	boltMin = 5,
	boltWindup = 0.45,
	boltCooldown = 2.2,
	boltSpeed = 38,
	boltDamage = 10,

	trickRange = 22,
	trickWindup = 0.5,
	trickCooldown = 14,
	decoys = 2,
	ringRadius = 8,
	decoyLife = 10,

	vanishRange = 4,
	vanishDistance = 11,
	vanishCooldown = 5,
}

local Trait = {}
Trait.Tuning = Tuning

local DECOY = "CatMagicianDecoy"

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "CatMagician")
	CreatureKit.pose(entry, "walk")
	-- Not straight into a trick the moment it turns up.
	entry.nextTrickAt = os.clock() + 4
	if entry.def.decoy then
		entry.expiresAt = os.clock() + Tuning.decoyLife
		-- The real one may still be inside its own wind-up; give the copies
		-- the same short pause before they act.
		entry.nextBoltAt = os.clock() + 0.6 + math.random() * 0.6
	end
end

local function chest(entry): Vector3
	return CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.55, 0)
end

local function poof(entry)
	CreatureKit.fx("poof", chest(entry))
end

-- A decoy hit by anything goes up in smoke, taking none of it: no number,
-- no death burst, nothing to tell it from a vanishing trick.
function Trait.guard(entry)
	if not entry.def.decoy then
		return 1
	end
	if not entry.popped then
		entry.popped = true
		poof(entry)
		local model = entry.model
		task.defer(function()
			CreatureKit.service().despawn(model, "popped")
		end)
	end
	return 0
end

-- Where the ground is under a spot, or nil if it is in a wall or off a ledge.
local function standAt(spot: Vector3, nearY: number, height: number): Vector3?
	local ground = CreatureKit.service().groundAt(spot.X, spot.Z, nearY)
	local feet = Vector3.new(spot.X, ground, spot.Z)
	if math.abs(ground - nearY) > 4 or CreatureKit.solidAt(feet + Vector3.new(0, height * 0.5, 0)) then
		return nil
	end
	return feet
end

local function bolt(entry, aim: Vector3)
	local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
	local origin = chest(entry) + look * 1.6
	if CreatureKit.solidAt(origin) then
		return
	end
	local direction = (aim - origin)
	if direction.Magnitude < 1e-3 then
		return
	end
	local harmless = entry.def.decoy
	CreatureKit.projectile({
		origin = origin,
		velocity = direction.Unit * Tuning.boltSpeed,
		gravity = 0,
		hitRadius = 1.8,
		maxLife = Tuning.boltRange / Tuning.boltSpeed + 0.2,
		style = "magic",
		onHit = function(_point, players)
			if harmless then
				return
			end
			for _, player in ipairs(players) do
				CreatureKit.hurt(entry, player, Tuning.boltDamage)
			end
		end,
	})
end

-- The trick itself: the real one and its copies placed round the target.
local function trick(entry, targetPosition: Vector3)
	local Service = CreatureKit.service()
	poof(entry)
	local ground = Service.groundAt(targetPosition.X, targetPosition.Z, targetPosition.Y)
	local count = Tuning.decoys + 1
	local turn = math.random() * math.pi * 2
	local spots = {}
	for i = 0, count - 1 do
		local angle = turn + i / count * math.pi * 2
		local spot = Vector3.new(targetPosition.X, ground, targetPosition.Z)
			+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * Tuning.ringRadius
		local feet = standAt(spot, ground, entry.height)
		if feet then
			table.insert(spots, feet)
		end
	end
	if #spots == 0 then
		return
	end

	-- Which spot is the real one is a coin toss among them.
	local mine = table.remove(spots, math.random(1, #spots))
	CreatureKit.place(entry, mine, CreatureKit.flat(targetPosition - mine))
	poof(entry)

	entry.decoys = entry.decoys or {}
	for _, feet in ipairs(spots) do
		local model = Service.spawn(DECOY, feet)
		if model then
			table.insert(entry.decoys, model)
			CreatureKit.fx("poof", feet + Vector3.new(0, entry.height * 0.55, 0))
		end
	end
end

local function clearDecoys(entry)
	for _, model in ipairs(entry.decoys or {}) do
		if model.Parent then
			CreatureKit.fx("poof", model:GetPivot().Position)
			CreatureKit.service().despawn(model, "faded")
		end
	end
	entry.decoys = {}
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.def.decoy and now >= (entry.expiresAt or math.huge) then
		if not entry.popped then
			entry.popped = true
			poof(entry)
			local model = entry.model
			task.defer(function()
				CreatureKit.service().despawn(model, "faded")
			end)
		end
		return true
	end

	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "bolt" then
			if now >= move.at then
				entry.move = nil
				bolt(entry, (targetPosition or move.aim) + Vector3.new(0, 1, 0))
				CreatureKit.pose(entry, "walk")
			end
			return true
		elseif move.kind == "trick" then
			if now >= move.at then
				entry.move = nil
				trick(entry, targetPosition or move.aim)
				CreatureKit.pose(entry, "walk")
				entry.nextBoltAt = now + 0.9
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
	local real = not entry.def.decoy

	if real and distance <= Tuning.vanishRange and now >= (entry.nextVanishAt or 0) then
		entry.nextVanishAt = now + Tuning.vanishCooldown
		local away = -toward
		for _, turn in ipairs({ 0, 0.8, -0.8, 1.6, -1.6 }) do
			local heading = CFrame.Angles(0, turn, 0):VectorToWorldSpace(away)
			local feet = standAt(targetPosition + heading * Tuning.vanishDistance, CreatureKit.feet(entry).Y, entry.height)
			if feet then
				poof(entry)
				CreatureKit.place(entry, feet, CreatureKit.flat(targetPosition - feet))
				poof(entry)
				return true
			end
		end
	end

	if real and distance <= Tuning.trickRange and now >= (entry.nextTrickAt or 0) then
		entry.nextTrickAt = now + Tuning.trickCooldown
		entry.move = { kind = "trick", at = now + Tuning.trickWindup, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "trick")
		return true
	end

	if distance >= Tuning.boltMin and distance <= Tuning.boltRange and now >= (entry.nextBoltAt or 0)
		and not CreatureKit.firstBlock(position + Vector3.new(0, 1.5, 0), targetPosition, 1) then
		entry.nextBoltAt = now + Tuning.boltCooldown * (0.85 + math.random() * 0.3)
		entry.move = { kind = "bolt", at = now + Tuning.boltWindup, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "cast")
		return true
	end

	CreatureKit.pose(entry, "walk")
	-- Into the band from either side; inside it, idle facing you.
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
	if not entry.def.decoy then
		clearDecoys(entry)
	end
end

return Trait
