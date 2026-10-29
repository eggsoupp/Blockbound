--[[
	Vampire Duck - a black duck of the Crimson with a long red bill that
	drinks. Head and legs are jointed (Shared.Enemies.CreatureRigs.VampireDuck).

	LATCH (within `latchRange`). It draws its bill back and stabs; if it
	connects it hangs on at your side for up to `latchSeconds`, draining
	`drainDamage` every `drainInterval` and healing itself by as much, and
	you drag it along at `latchSlow` of your speed. Any blow knocks it off.

	FLEE. Knocked off or drunk its fill, it scuttles away for `fleeSeconds`
	before coming back for more.
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	walkSpeed = 6.5,
	slideStep = 2,

	latchRange = 2.8,
	latchReach = 2,
	peckWindup = 0.25,
	peckSeconds = 0.45,
	latchSeconds = 2.2,
	drainInterval = 0.3,
	drainDamage = 2,
	latchSlow = 0.65,
	latchCooldown = 3.5,

	fleeSeconds = 1.3,
	fleeSpeed = 9,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "VampireDuck")
	CreatureKit.pose(entry, "walk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

local function flee(entry, now: number)
	entry.move = { kind = "flee", untilAt = now + Tuning.fleeSeconds }
	entry.nextLatchAt = now + Tuning.latchCooldown
	CreatureKit.pose(entry, "flee")
end

-- A blow knocks it off whoever it is hanging on to; it takes the blow.
function Trait.guard(entry)
	if entry.move and entry.move.kind == "latch" then
		CreatureKit.slow(entry.move.player, 1, 0.05)
		flee(entry, os.clock())
		CreatureKit.fx("splash", "duck", CreatureKit.feet(entry) + Vector3.new(0, 1, 0), "ichor")
	end
	return 1
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	local move = entry.move
	if move and move.kind == "latch" then
		-- Hanging on: carried at the victim's side, wherever they go.
		local player = move.player
		local hrp = player.Parent and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local humanoid = hrp and player.Character:FindFirstChildOfClass("Humanoid")
		if not (hrp and humanoid and humanoid.Health > 0) or now >= move.untilAt then
			CreatureKit.slow(player, 1, 0.05)
			flee(entry, now)
			return true
		end
		local side = hrp.CFrame * CFrame.new(move.side * 1.4, 0, -0.4)
		local ground = CreatureKit.service().groundAt(side.Position.X, side.Position.Z, hrp.Position.Y)
		local feet = Vector3.new(side.Position.X, ground, side.Position.Z)
		CreatureKit.place(entry, feet, CreatureKit.flat(hrp.Position - feet))
		if now >= move.nextDrainAt then
			move.nextDrainAt = now + Tuning.drainInterval
			CreatureKit.hurt(entry, player, Tuning.drainDamage)
			CreatureKit.service().heal(entry.model, Tuning.drainDamage)
			CreatureKit.slow(player, Tuning.latchSlow, Tuning.drainInterval + 0.2)
			CreatureKit.fx("drain", entry.model, player.Character)
		end
		return true
	end

	if entry.state ~= "Grounded" then
		if not (move and move.kind == "flee") then
			entry.move = nil
		end
		return false
	end

	if move then
		if move.kind == "peck" then
			if now >= move.at then
				local reach = CreatureKit.feet(entry) + look(entry) * Tuning.latchReach + Vector3.new(0, 1, 0)
				local caught
				for _, player in ipairs(Players:GetPlayers()) do
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp and (hrp.Position - reach).Magnitude <= 3 then
						caught = player
						break
					end
				end
				if caught then
					entry.move = {
						kind = "latch", player = caught, untilAt = now + Tuning.latchSeconds,
						nextDrainAt = now, side = if math.random() < 0.5 then 1 else -1,
					}
					CreatureKit.pose(entry, "latch")
				elseif now >= move.untilAt then
					entry.move = nil
					entry.nextLatchAt = now + 1
					CreatureKit.pose(entry, "walk")
				else
					return true
				end
			end
			return true
		elseif move.kind == "flee" then
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "walk")
				return true
			end
			if targetPosition then
				local away = CreatureKit.flat(position - targetPosition)
				if not CreatureKit.slide(entry, away * Tuning.fleeSpeed * dt, away, nil, Tuning.slideStep) then
					entry.move = nil
					return false
				end
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

	if distance <= Tuning.latchRange and now >= (entry.nextLatchAt or 0) then
		entry.move = { kind = "peck", at = now + Tuning.peckWindup, untilAt = now + Tuning.peckSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "peck")
		return true
	end

	CreatureKit.pose(entry, "walk")
	if distance <= Tuning.latchRange * 0.7 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.walkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

function Trait.finish(entry)
	local move = entry.move
	if move and move.kind == "latch" then
		CreatureKit.slow(move.player, 1, 0.05)
	end
end

return Trait
