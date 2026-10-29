--[[
	Rabbic Cleric - a robed rabbit priest of the Hallow, and a SUPPORT enemy:
	the reason a fight in the Hallow is harder than the creatures in it.

	It bounds rather than walks - real hops along arcs, `hopSeconds` each with
	a short rest between - and keeps its distance, backing off when you close
	in and circling when you hold back. Ears, legs, arms and head are jointed
	(Shared.Enemies.CreatureRigs.RabbicCleric).

	HOLY ORB (`orbRange`). It thrusts its staff and looses a slow, glowing orb
	that HOMES on you for `orbLife` seconds, turning at `orbTurn` radians a
	second - outrun it round a corner or let a block take it. `orbDamage` on
	a hit.

	MEND. Every `healCooldown` seconds, if anything within `healRange` -
	itself included - is hurt, it raises its staff and heals every wounded
	creature there by `healAmount`. Kill it first.
]]

local RunService = game:GetService("RunService")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	hopSeconds = 0.42,
	hopHeight = 1.8,
	hopDistance = 4.5,
	restSeconds = NumberRange.new(0.12, 0.35),
	-- The band of distance it likes to fight from.
	nearest = 13,
	furthest = 24,
	-- Rise or fall a hop will take; more and it tries another way.
	hopStep = 4.5,

	orbRange = 40,
	castSeconds = 0.55,
	orbCooldown = 3.6,
	orbSpeed = 13,
	orbTurn = 1.6,
	orbLife = 5,
	orbHitRadius = 2.2,
	orbDamage = 10,

	healRange = 22,
	healAmount = 22,
	healCooldown = 8,
	healSeconds = 0.8,
	-- Below this share of its health a creature counts as hurt.
	hurtShare = 0.92,
}

local Trait = {}
Trait.Tuning = Tuning

local function roll(range: NumberRange): number
	return range.Min + math.random() * (range.Max - range.Min)
end

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "RabbicCleric")
	entry.circle = if math.random() < 0.5 then 1 else -1
	CreatureKit.pose(entry, "walk")
end

--[[
	The orb: an invisible anchored host the server flies, which every client
	dresses in light (CreatureFX "orb"). Homing is a capped turn toward the
	target each frame, so it curves after you rather than snapping.
]]
local orbFolder

local function loose(entry, target: Player, origin: Vector3, direction: Vector3)
	if not (orbFolder and orbFolder.Parent) then
		orbFolder = Instance.new("Folder")
		orbFolder.Name = "CreatureOrbs"
		orbFolder.Parent = workspace
	end
	local host = Instance.new("Part")
	host.Name = "HolyOrb"
	host.Size = Vector3.one * 0.4
	host.Transparency = 1
	host.Anchored, host.CanCollide, host.CanTouch, host.CanQuery, host.CastShadow = true, false, false, false, false
	host.CFrame = CFrame.new(origin)
	host.Parent = orbFolder
	CreatureKit.fx("orb", host, Tuning.orbLife)

	local heading = direction.Unit
	local startedAt = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local position = host.Position
		local character = target.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local want = (root.Position - position)
			if want.Magnitude > 1e-3 then
				want = want.Unit
				local angle = math.acos(math.clamp(heading:Dot(want), -1, 1))
				local turn = math.min(1, Tuning.orbTurn * dt / math.max(angle, 1e-3))
				heading = heading:Lerp(want, turn).Unit
			end
		end
		local nextPosition = position + heading * Tuning.orbSpeed * dt

		local hits = CreatureKit.playersAlong(position, nextPosition, Tuning.orbHitRadius)
		local block = CreatureKit.solidAt(nextPosition)
		if #hits > 0 or block or os.clock() - startedAt > Tuning.orbLife then
			connection:Disconnect()
			for _, player in ipairs(hits) do
				CreatureKit.hurt(entry, player, Tuning.orbDamage)
			end
			CreatureKit.fx("orbpop", nextPosition)
			host:Destroy()
			return
		end
		host.CFrame = CFrame.new(nextPosition)
	end)
end

local function wounded(position: Vector3)
	local Service = CreatureKit.service()
	local list = {}
	Service.forEachNear(position, Tuning.healRange, function(model)
		local _, health, maxHealth = Service.describe(model)
		if health and maxHealth and health < maxHealth * Tuning.hurtShare then
			table.insert(list, model)
		end
	end)
	return list
end

-- One bound toward `goal` (flat), or false if the ground there is a wall or a cliff.
local function startHop(entry, goal: Vector3, now: number): boolean
	local feet = CreatureKit.feet(entry)
	local flat = CreatureKit.flat(goal - feet)
	if flat.Magnitude < 1e-3 then
		return false
	end
	local landing = feet + flat * Tuning.hopDistance
	local ground = CreatureKit.service().groundAt(landing.X, landing.Z, feet.Y)
	if math.abs(ground - feet.Y) > Tuning.hopStep then
		return false
	end
	entry.hop = {
		from = feet,
		to = Vector3.new(landing.X, ground, landing.Z),
		startedAt = now,
		look = flat,
	}
	return true
end

local function stepHop(entry, now: number)
	local hop = entry.hop
	local t = math.min(1, (now - hop.startedAt) / Tuning.hopSeconds)
	local point = hop.from:Lerp(hop.to, t) + Vector3.new(0, 4 * Tuning.hopHeight * t * (1 - t), 0)
	CreatureKit.place(entry, point, entry.lookAt or hop.look)
	if t >= 1 then
		entry.hop = nil
		entry.restUntil = now + roll(Tuning.restSeconds)
	end
end

function Trait.step(entry, target, targetPosition, position, _dt, now)
	if entry.state ~= "Grounded" then
		entry.hop, entry.move = nil, nil
		return false
	end

	local move = entry.move
	if move then
		if now >= move.at then
			entry.move = nil
			CreatureKit.pose(entry, "walk")
			if move.kind == "cast" and target and target.Parent then
				local look = CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
				local origin = CreatureKit.feet(entry) + Vector3.new(0, entry.height * 0.55, 0) + look * 2.2
				loose(entry, target, origin, (move.aim - origin))
			elseif move.kind == "heal" then
				local Service = CreatureKit.service()
				for _, model in ipairs(wounded(position)) do
					if Service.heal(model, Tuning.healAmount) > 0 then
						CreatureKit.fx("healed", model)
					end
				end
			end
		end
		return true
	end

	if entry.hop then
		stepHop(entry, now)
		return true
	end

	if not (target and targetPosition) then
		CreatureKit.pose(entry, "walk")
		return false
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude
	entry.lookAt = toward

	-- Mend first: keeping the others up is its job.
	if now >= (entry.nextHealAt or 0) and #wounded(position) > 0 then
		entry.nextHealAt = now + Tuning.healCooldown
		entry.move = { kind = "heal", at = now + Tuning.healSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "heal")
		CreatureKit.fx("mend", entry.model, Tuning.healSeconds, Tuning.healRange)
		return true
	end

	if distance <= Tuning.orbRange and now >= (entry.nextOrbAt or 0)
		and not CreatureKit.firstBlock(position + Vector3.new(0, 2, 0), targetPosition, 1) then
		entry.nextOrbAt = now + Tuning.orbCooldown
		entry.move = { kind = "cast", at = now + Tuning.castSeconds, aim = targetPosition }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "cast")
		CreatureKit.fx("flare", entry.model, Color3.fromRGB(255, 235, 150))
		return true
	end

	if now < (entry.restUntil or 0) then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end

	-- Bound: away when you are close, in when you are far, round you between.
	local across = toward:Cross(Vector3.yAxis) * entry.circle
	local goal
	if distance < Tuning.nearest then
		goal = -toward + across * 0.5
	elseif distance > Tuning.furthest then
		goal = toward + across * 0.3
	else
		goal = across
	end
	local feet = CreatureKit.feet(entry)
	if not startHop(entry, feet + goal * 10, now) then
		-- Blocked that way: circle the other way next time, and try straight.
		entry.circle = -entry.circle
		if not startHop(entry, feet + (if distance < Tuning.nearest then -toward else toward) * 10, now) then
			return false
		end
	end
	stepHop(entry, now)
	return true
end

function Trait.finish(entry)
	entry.hop = nil
end

return Trait
