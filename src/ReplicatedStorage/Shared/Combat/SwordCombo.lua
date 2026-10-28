--[[
	SwordCombo

	Swinging a weapon: the four-swing combo, when each swing lets the next one
	start, and when and how wide each one hits.

		local combo = SwordCombo.new(stats, function(index, step) ... end)
		combo:press()     -- Tool.Activated
		combo:release()   -- Tool.Deactivated
		combo:cancel()    -- put away, or died

	ONE RULEBOOK, RUN TWICE

	The client and the server both run this, from the same clicks: Tool.
	Activated and Deactivated fire on both. The client runs it to animate
	(WeaponClient), the server to hurt (WeaponServer). Neither tells the other
	which swing it is on; they agree because they apply these rules to the
	same presses, so the swing the player sees is the swing the server lands.
	At worst a click right on the edge of ComboWindow starts the combo over on
	one side and not the other, and that blow lands as a different step.

	THE RHYTHM

	A click swings. A click during a swing queues the next one, and holding the
	button keeps swinging, so 1-2-3-4 runs as fast as `recover` allows. Wait
	longer than ComboWindow after a swing and it starts again from 1; after 4
	it starts from 1 anyway.

	THE HIT

	Each swing lands at its animation's `hit` time (Shared.Tools.
	SwingAnimations), not on the click. The hitbox is deliberately forgiving:
	reach is measured to the near side of an enemy rather than its middle, the
	arc is wider than a half-circle, anything close enough to touch is hit
	whichever way you face, and the finisher spins, so it hits all round.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponConfig"))
local SwingAnimations = require(Shared:WaitForChild("Tools"):WaitForChild("SwingAnimations"))

local SwordCombo = {}

--[[
	The steps, in order. `recover` is how long after a swing starts the next
	may (so it is the rate of fire, before attack speed); `damage` multiplies
	the weapon's own; `arc` overrides the weapon's arc and `maxTargets` its
	target count, for the finisher only.

	At the default cooldown that is 4.5 blows' worth in 1.9s, about 30% more
	damage per second than the single swing every 0.55s it replaced - the
	reward for keeping the rhythm going.
]]
SwordCombo.Steps = {
	{ swing = "SwordSlash1", recover = 0.4, damage = 1 },
	{ swing = "SwordSlash2", recover = 0.4, damage = 1 },
	{ swing = "SwordSlash3", recover = 0.45, damage = 1 },
	{ swing = "SwordSlash4", recover = 0.65, damage = 1.5, arc = 360, maxTargets = 4 },
}

-- Seconds after a swing's `recover` in which a click carries the combo on.
SwordCombo.ComboWindow = 0.8

-- An enemy whose near side is this close to the wielder's middle is hit
-- whichever way they are facing: anything touching you is in reach.
SwordCombo.CloseRange = 4

-- How much of an enemy's own half-width counts toward reach, at most. Capped
-- so a boss's bounding box does not turn the sword into a polearm.
SwordCombo.BodyAllowance = 5

-- Weapon classes that play the combo's animations. A lance's reach is a
-- thrust, not a slash; it still swings on this rhythm, unanimated, until it
-- has moves of its own.
SwordCombo.AnimatedClasses = { Sword = true, HeavySword = true }

function SwordCombo.animates(definition)
	local class = definition and definition.weaponClass
	return class == nil or SwordCombo.AnimatedClasses[class] == true
end

-- How much faster than the default this weapon swings. Everything in a step
-- is divided by it, and the animation plays at it.
function SwordCombo.speedFor(stats)
	return WeaponConfig.DefaultCooldown / math.max(0.05, stats.cooldown)
end

-- Seconds from the start of a swing to its blow landing.
function SwordCombo.hitDelay(step, speed)
	local swing = SwingAnimations.Swings[step.swing]
	return (swing and swing.hit or 0) / speed
end

-- ---------------------------------------------------------------------------
-- The combo
-- ---------------------------------------------------------------------------

local Combo = {}
Combo.__index = Combo

function SwordCombo.new(stats, onSwing)
	return setmetatable({
		speed = SwordCombo.speedFor(stats),
		onSwing = onSwing,
		index = 0,
		-- When the last swing let the next one start.
		freeAt = -math.huge,
		held = false,
		queued = false,
		busy = false,
		-- Bumped by cancel(), so a swing scheduled before it never happens.
		token = 0,
	}, Combo)
end

function Combo:press()
	self.held = true
	if self.busy then
		self.queued = true
	else
		self:swing()
	end
end

function Combo:release()
	self.held = false
end

function Combo:cancel()
	self.token += 1
	self.held, self.queued, self.busy = false, false, false
	self.index = 0
end

function Combo:swing()
	local now = os.clock()
	local steps = SwordCombo.Steps
	local continuing = self.index < #steps and now - self.freeAt <= SwordCombo.ComboWindow
	self.index = if continuing then self.index + 1 else 1

	local step = steps[self.index]
	local recover = step.recover / self.speed
	self.busy, self.queued = true, false
	self.freeAt = now + recover

	-- Spawned, so a mistake in what a swing does cannot stop the rhythm.
	task.spawn(self.onSwing, self.index, step)

	local token = self.token
	task.delay(recover, function()
		if self.token ~= token then
			return
		end
		self.busy = false
		if self.held or self.queued then
			self:swing()
		end
	end)
end

return SwordCombo
