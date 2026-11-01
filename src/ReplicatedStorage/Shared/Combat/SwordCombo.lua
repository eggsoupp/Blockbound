-- Server-owned five-hit combos. All times come from the authored clip markers.
local WeaponConfig = require(script.Parent.WeaponConfig)
local WeaponAnimations = require(script.Parent.WeaponAnimations)
local SwordCombo = {}
SwordCombo.ComboWindow = 0.8
SwordCombo.CloseRange = 4
SwordCombo.BodyAllowance = 5
SwordCombo.SampleInterval = 1 / 30
function SwordCombo.speedFor(stats)
	return WeaponConfig.DefaultCooldown / math.max(0.05, stats.cooldown)
end
function SwordCombo.hitDelay(step, speed)
	return step.hit / speed
end
local Combo = {}
Combo.__index = Combo
function SwordCombo.new(stats, onSwing)
	return setmetatable({
		speed = SwordCombo.speedFor(stats),
		steps = WeaponAnimations.forClass(stats.weaponClass).steps,
		onSwing = onSwing, index = 0, freeAt = -math.huge,
		held = false, queued = false, busy = false, token = 0,
	}, Combo)
end
function Combo:press()
	if self.held then return end
	self.held = true
	if self.busy then self.queued = true else self:swing() end
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
	local continuing = self.index < #self.steps and now - self.freeAt <= SwordCombo.ComboWindow
	self.index = if continuing then self.index + 1 else 1
	local step = self.steps[self.index]
	local recover = step.recover / self.speed
	self.busy, self.queued = true, false
	self.freeAt = now + recover
	local token = self.token
	task.spawn(self.onSwing, self.index, step, token)
	task.delay(recover, function()
		if self.token ~= token then return end
		self.busy = false
		if self.held or self.queued then self:swing() end
	end)
end
return SwordCombo
