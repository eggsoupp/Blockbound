--[[
	Beast - the shared trait of the plain animals (Beagle, Beisa Oryx, Bronto):
	a passive creature (EnemyConfig `passive`) that walks to whoever hurt it
	and fights with a short list of timed moves. Each animal's own module is
	just a call to Beast.trait with its numbers.

	  rig        the Shared.Enemies.CreatureRigs entry (they use `quadruped`)
	  walkSpeed  studs/second it closes in at
	  herd       optional { radius, pose, seconds }: the first time it is hurt
	             by someone it calls every one of its kind within `radius` onto
	             them too (EnemyService.provoke), playing `pose` - a bark, a
	             bellow - for `seconds`
	  moves      tried in order each tick; the first that is ready and whose
	             target is where it wants it is used:
	    pose, windup, seconds, cooldown
	    where      "front" (target within `range` ahead), "behind" (anyone
	               within `range` behind or beside it), "near" (within `range`)
	    hit        { shape = "reach" | "behind" | "around", radius, damage,
	               slow = { share, seconds }?, fx = kind? } at the wind-up's end
    lean       optional radians the whole body tips back by through the wind-up
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Beast = {}

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- Players in a move's hit shape, with how far round from ahead each is.
local function inShape(entry, shape: string, radius: number)
	local feet = CreatureKit.feet(entry)
	local facing = look(entry)
	local found = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and math.abs(hrp.Position.Y - feet.Y - entry.height * 0.4) <= entry.height + 3 then
			local offset = Vector3.new(hrp.Position.X - feet.X, 0, hrp.Position.Z - feet.Z)
			local ahead = if offset.Magnitude > 0.5 then offset.Unit:Dot(facing) else 0
			local ok
			if shape == "reach" then
				local center = feet + facing * (radius * 0.7 + 0.5)
				ok = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z).Magnitude <= radius
			elseif shape == "behind" then
				ok = offset.Magnitude <= radius and ahead < 0.3
			else
				ok = offset.Magnitude <= radius
			end
			if ok then
				table.insert(found, player)
			end
		end
	end
	return found
end

local function wanted(entry, move, position: Vector3, targetPosition: Vector3?): boolean
	if move.where == "behind" then
		return #inShape(entry, "behind", move.range) > 0
	end
	if not targetPosition then
		return false
	end
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude
	return distance <= move.range
end

function Beast.trait(spec)
	local Trait = { Tuning = spec }

	function Trait.start(entry)
		entry.model:SetAttribute("Rig", spec.rig)
		entry.nextMoveAt = {}
		CreatureKit.pose(entry, "walk")
	end

	function Trait.guard(entry, _amount, dealer)
		local herd = spec.herd
		if herd and typeof(dealer) == "Instance" and dealer:IsA("Player") and not (entry.called and entry.called[dealer]) then
			entry.called = entry.called or {}
			entry.called[dealer] = true
			entry.wantsCall = true
			local Service = CreatureKit.service()
			Service.forEachNear(entry.model:GetPivot().Position, herd.radius, function(model)
				if Service.describe(model) == entry.name then
					Service.provoke(model, dealer)
				end
			end)
		end
		return 1
	end

	function Trait.step(entry, target, targetPosition, position, dt, now)
		if entry.state ~= "Grounded" then
			entry.move = nil
			return false
		end

		local move = entry.move
		if move then
			local m = move.spec
			-- A lean of the whole body (rearing up) through the wind-up,
			-- dropped as the blow lands.
			if m.lean then
				local k = if now < move.hitAt then 1 - (move.hitAt - now) / m.windup else 0
				CreatureKit.place(entry, CreatureKit.feet(entry), nil, CFrame.Angles(m.lean * math.clamp(k, 0, 1), 0, 0))
			end
			if not move.hit and now >= move.hitAt and m.hit then
				move.hit = true
				local h = m.hit
				for _, player in ipairs(inShape(entry, h.shape, h.radius)) do
					CreatureKit.hurt(entry, player, h.damage)
					if h.slow then
						CreatureKit.slow(player, h.slow[1], h.slow[2])
					end
				end
				if h.fx == "slam" then
					CreatureKit.fx("slam", CreatureKit.feet(entry) + look(entry) * 1.5, h.radius)
				elseif h.fx == "cut" then
					CreatureKit.fx("cut", entry.model)
				end
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
			end
			return true
		end

		if entry.wantsCall and spec.herd then
			entry.wantsCall = false
			entry.move = { spec = { hit = nil }, untilAt = now + spec.herd.seconds }
			CreatureKit.pose(entry, spec.herd.pose)
			CreatureKit.fx("roar", entry.model, spec.herd.seconds)
			return true
		end

		if not (target and targetPosition) then
			CreatureKit.pose(entry, "walk")
			return false
		end

		local toward = CreatureKit.flat(targetPosition - position)
		local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

		for index, m in ipairs(spec.moves) do
			if now >= (entry.nextMoveAt[index] or 0) and wanted(entry, m, position, targetPosition) then
				entry.nextMoveAt[index] = now + m.cooldown
				entry.move = { spec = m, hitAt = now + m.windup, untilAt = now + m.seconds }
				if m.where ~= "behind" then
					CreatureKit.place(entry, CreatureKit.feet(entry), toward)
				end
				CreatureKit.pose(entry, m.pose)
				return true
			end
		end

		CreatureKit.pose(entry, "walk")
		if distance <= (spec.closeEnough or 2) then
			CreatureKit.place(entry, CreatureKit.feet(entry), toward)
			return true
		end
		if not CreatureKit.slide(entry, toward * spec.walkSpeed * dt, toward, nil, spec.slideStep or 2) then
			return false
		end
		return true
	end

	return Trait
end

return Beast
