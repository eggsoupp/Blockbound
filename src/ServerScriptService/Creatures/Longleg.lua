--[[
	Longleg - a hunched thing of the Corruption on four stilts, with its head
	slung low on a long neck. It does not like to be seen moving. Head and legs
	are jointed (Shared.Enemies.CreatureRigs.Longleg).

	WATCHED. While you face it - your character turned within `watchAngle` of
	it, inside `watchRange`, with nothing in between - it stops dead and only
	twitches. Look away, or run (a running character faces where it runs), and
	it lopes after you at `stalkSpeed`, far faster than it looks.

	STARED DOWN. Watching only holds it for `stareLimit` seconds in all. Then it
	shrieks for `shriekSeconds` and dashes straight at you at `dashSpeed`,
	watched or not.

	STRIKE (within `strikeRange`). Watched or not, close enough is close enough:
	it rears its head and lashes it down in front of it.
]]

local Players = game:GetService("Players")

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	stalkSpeed = 13,
	slideStep = 2,

	watchRange = 45,
	watchAngle = 50,
	stareLimit = 3.5,
	-- Unwatched, the stare drains back at this many seconds a second.
	stareDrain = 0.5,

	shriekSeconds = 0.7,
	dashSpeed = 30,
	dashSeconds = 0.8,
	dashDamage = 12,

	strikeRange = 5.5,
	strikeReach = 4.5,
	strikeWindup = 0.45,
	strikeSeconds = 0.7,
	strikeDamage = 14,
	strikeCooldown = 2.2,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "Longleg")
	entry.stare = 0
	CreatureKit.pose(entry, "stalk")
end

local function look(entry): Vector3
	return CreatureKit.flat(entry.facing or Vector3.new(0, 0, -1))
end

-- Is anyone looking at it? Any player, not just its target: a friend
-- watching your back is the point.
local function watched(entry, position: Vector3): boolean
	local eye = position + Vector3.new(0, entry.height * 0.3, 0)
	local cosine = math.cos(math.rad(Tuning.watchAngle))
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local offset = eye - hrp.Position
			if offset.Magnitude <= Tuning.watchRange
				and CreatureKit.flat(hrp.CFrame.LookVector):Dot(CreatureKit.flat(offset)) >= cosine
				and not CreatureKit.firstBlock(hrp.Position + Vector3.new(0, 1.5, 0), eye, 1) then
				return true
			end
		end
	end
	return false
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		entry.move = nil
		return false
	end

	local move = entry.move
	if move then
		if move.kind == "shriek" then
			if now >= move.untilAt then
				local aim = targetPosition or move.aim
				entry.move = { kind = "dash", untilAt = now + Tuning.dashSeconds, heading = CreatureKit.flat(aim - position) }
				CreatureKit.pose(entry, "dash")
			end
			return true
		elseif move.kind == "dash" then
			local reached = targetPosition
				and Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude <= 3.5
			if not move.hit then
				local center = position + Vector3.new(0, entry.height * 0.2, 0)
				for _, player in ipairs(CreatureKit.playersAlong(center, center + move.heading * 3, 2.5)) do
					CreatureKit.hurt(entry, player, Tuning.dashDamage)
					move.hit = true
				end
			end
			if now >= move.untilAt or reached or move.hit then
				entry.move = nil
				entry.stare = 0
				CreatureKit.pose(entry, "stalk")
			elseif not CreatureKit.slide(entry, move.heading * Tuning.dashSpeed * dt, move.heading, nil, Tuning.slideStep) then
				-- A step or a drop in the way: the rest of the dash is a leap,
				-- the ordinary hop's lunge, straight away.
				entry.move = nil
				entry.stare = 0
				entry.state = "Windup"
				entry.pendingLunge = true
				entry.stateUntil = now
				CreatureKit.pose(entry, "dash")
				return false
			end
			return true
		elseif move.kind == "strike" then
			if not move.hit and now >= move.hitAt then
				move.hit = true
				local reach = CreatureKit.feet(entry) + look(entry) * Tuning.strikeReach + Vector3.new(0, 1.5, 0)
				CreatureKit.service().touch(entry, reach, Tuning.strikeDamage)
				CreatureKit.fx("lash", entry.model)
			end
			if now >= move.untilAt then
				entry.move = nil
				CreatureKit.pose(entry, "stalk")
			end
			return true
		end
	end

	if not (target and targetPosition) then
		entry.stare = math.max(0, entry.stare - Tuning.stareDrain * dt)
		CreatureKit.pose(entry, "stalk")
		return false
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

	if distance <= Tuning.strikeRange and now >= (entry.nextStrikeAt or 0) then
		entry.nextStrikeAt = now + Tuning.strikeCooldown
		entry.move = { kind = "strike", hitAt = now + Tuning.strikeWindup, untilAt = now + Tuning.strikeSeconds }
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		CreatureKit.pose(entry, "strike")
		return true
	end

	if watched(entry, position) then
		entry.stare += dt
		if entry.stare >= Tuning.stareLimit then
			entry.move = { kind = "shriek", untilAt = now + Tuning.shriekSeconds, aim = targetPosition }
			CreatureKit.place(entry, CreatureKit.feet(entry), toward)
			CreatureKit.pose(entry, "shriek")
			CreatureKit.fx("shriek", entry.model)
			return true
		end
		-- Dead still: not even turning.
		CreatureKit.pose(entry, "frozen")
		return true
	end

	entry.stare = math.max(0, entry.stare - Tuning.stareDrain * dt)
	CreatureKit.pose(entry, "stalk")
	if distance <= Tuning.strikeRange * 0.8 then
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		return true
	end
	if not CreatureKit.slide(entry, toward * Tuning.stalkSpeed * dt, toward, nil, Tuning.slideStep) then
		return false
	end
	return true
end

return Trait
