--[[
	TutorialPanel

	The tutorial guide on the gameplay HUD: a small copy of the Tab menu's
	wireframe solid in the top right corner, with a dark pixel-kit panel under
	it that carries the current step's title and body.

		local panel = TutorialPanel.new(playerGui)
		panel:showStep(step)          -- a TutorialSteps entry; enters if hidden
		panel:collapse()              -- polygon only
		panel:expand()                -- polygon and text
		panel:setSuppressed(true)     -- a menu is up: fade out, remember state
		panel:setSuppressed(false)    -- and back, as it was
		panel:hide()                  -- gone, nothing animating
		panel:destroy()

		panel.onInteract = function() end   -- the player clicked or tapped it

	It draws. It does not decide: which step shows, when, and what finishes it
	is StarterPlayerScripts.TutorialClient's, and the words are
	Shared.UI.TutorialSteps'. This file would be the same if there were forty
	steps instead of one.

	THE SOLID IS THE MENU'S OWN

	Shared.UI.MenuBackdrop, built with its "guide" look: the same geometry,
	drift and burst at a size that fits a corner of the HUD. That is the point
	of it - the shape the player has been looking at behind the Tab menu is the
	one that turns to them and speaks. It animates only while it is on screen;
	hidden or suppressed, its render connection is dropped, and this file has
	no per-frame work of its own at all. Everything here is tweens and a
	handful of delayed steps.

	WHERE IT SITS

	Top right, under Roblox's top bar - the ScreenGui respects the inset, so
	the bar is clear by construction. Everything the game already draws is
	elsewhere: the hotbar and the gear top LEFT, health, mana, abilities and
	the feedback lines bottom left, the boss bar bottom centre. On a phone the
	jump button is bottom right. Designed in 1080p pixels and fitted with one
	UIScale: smaller on a smaller screen, and never wider than a modest share
	of it, so it stays readable without sitting on the game.

	THE FIRST MINUTE

	The entrance is meant to be seen once and then stop asking: the solid pops
	in and bursts - the same flourish an equipped ability gets, so it is
	briefly brighter and faster than it will rest - the panel unfolds beneath,
	the title fades up and the body types on. One sound, quietly. If nothing
	is clicked for a while, one more nod: a half-strength burst and a small
	scale bump on the panel, and that is all. No loop, no second sound. Any
	click or tap on the guide ends even that.

	STATES

	hidden ...... nothing visible, nothing running
	shown ....... the solid is up; `expanded` says whether the panel is too
	suppressed .. a menu is open; faded out, and `expanded` is kept so closing
	              the menu brings it back exactly as it was

	Every sequence checks a token before each of its delayed steps, so a
	collapse or a menu opening mid-entrance simply ends the entrance rather
	than racing it.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelUI = require(script.Parent:WaitForChild("PixelUI"))
local Motion = require(script.Parent:WaitForChild("Motion"))
local MenuBackdrop = require(script.Parent:WaitForChild("MenuBackdrop"))
local Sounds = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("Sounds")
)

local TutorialPanel = {}
TutorialPanel.__index = TutorialPanel

-- ---------------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------------

-- In pixels on a 1080p screen; a UIScale fits them to the real one.
local L = {
	-- From the screen's right edge and from the top of the usable area.
	edge = 18,
	top = 14,

	-- The square the solid is drawn in. Its hit area is this square.
	host = 120,

	-- Between the solid and the panel, and the panel's width.
	gap = 8,
	width = 300,

	-- Inside the panel, past the sprite's own border.
	pad = 8,
	titleGap = 6,
	hintGap = 10,
}

local DESIGN_HEIGHT = 1080
local MIN_SCALE = 0.75
local MAX_SCALE = 1.1

-- The panel is never wider than this share of the screen.
local MAX_WIDTH_SHARE = 0.42

-- The panel's sprite: the kit's dark wood, which the pale wireframe sits well
-- over and which reads over a bright daytime world.
local PANEL_SPRITE = "tooltip"

-- How far the whole thing slides in from, and how small the solid starts.
local ENTER_SLIDE = 48
local ENTER_SCALE = 0.6

-- Seconds. The entrance is staged, not simultaneous: the solid first, the
-- burst and the sound once it is there, then the panel, then the words.
local ENTER_BURST_AT = 0.3
local ENTER_PANEL_AT = 0.45
local ENTER_TITLE_AT = 0.65
local ENTER_BODY_AT = 0.9
local ENTER_HINT_AFTER = 0.3

-- Type-on: seconds per character, within a floor and a ceiling so a short
-- line is not over in a blink and a long one does not drag.
local TYPE_PER_CHAR = 0.022
local TYPE_MIN = 0.5
local TYPE_MAX = 1.6

-- The one sound, and how quietly.
local ENTER_SOUND = "ui.open"
local ENTER_SOUND_VOLUME = 0.45

-- The entrance burst and the later nod, as MenuBackdrop:burst strengths.
local ENTER_BURST = 1
local ATTENTION_BURST = 0.5
local ATTENTION_PULSE = 1.05

-- How long after the entrance has finished the nod comes, if nothing has
-- been clicked, and how many nods there are at most. One: the brief is to be
-- hard to miss, not to keep asking.
local ATTENTION_DELAY = 13
local ATTENTION_COUNT = 1

local SLIDE_IN = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP_IN = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local UNFOLD = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE = Theme.Tween.Fade
local FADE_OUT = Theme.Tween.Close

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function tween(instance: Instance, info: TweenInfo, goal: {})
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

local function label(parent: Instance, name: string, font: Font, size: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 0, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Text = ""
	text.Parent = parent
	return text
end

local function hintText(): string
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	return if touch then "Tap the guide to hide or show this" else "Click the guide to hide or show this"
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

function TutorialPanel.new(playerGui: Instance)
	local self = setmetatable({}, TutorialPanel)

	local screen = Instance.new("ScreenGui")
	screen.Name = "TutorialGuide"
	screen.ResetOnSpawn = false
	-- Respecting the inset is what keeps this under the top bar on every
	-- device without measuring it.
	screen.IgnoreGuiInset = false
	-- With the rest of the HUD; under the settings window and any real menu.
	screen.DisplayOrder = 5
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false
	screen.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -L.edge, 0, L.top)
	root.Size = UDim2.fromOffset(L.width, L.host)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundTransparency = 1
	root.Parent = screen

	local scale = Instance.new("UIScale")
	scale.Parent = root

	-- The solid's host, and its hit area. A button so a click lands here and
	-- is marked processed - mining and placement check that flag and leave a
	-- click on the guide alone.
	local host = Instance.new("TextButton")
	host.Name = "Guide"
	host.Text = ""
	host.AutoButtonColor = false
	-- Anchored at its centre so the UIScale below grows it about the middle
	-- of the solid rather than from a corner.
	host.AnchorPoint = Vector2.new(0.5, 0.5)
	host.Position = UDim2.new(1, -L.host / 2, 0, L.host / 2)
	host.Size = UDim2.fromOffset(L.host, L.host)
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.ZIndex = 2
	host.Parent = root

	-- Named for Motion.pulse, which reuses a UIScale of this name rather than
	-- adding a second one: two UIScales on one object do not compose.
	local hostScale = Instance.new("UIScale")
	hostScale.Name = "MotionPulse"
	hostScale.Parent = host

	local art = MenuBackdrop.new(host, { look = "guide" })

	-- The text panel, under the solid. Also a button: a click on it collapses
	-- the guide, and is processed input like the host's.
	local panel = Instance.new("ImageButton")
	panel.Name = "Panel"
	panel.AutoButtonColor = false
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, 0, 0, L.host + L.gap)
	panel.Size = UDim2.new(1, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ImageTransparency = 1
	panel.Visible = false
	panel.ZIndex = 1
	panel.Parent = root
	PixelUI.apply(panel, PANEL_SPRITE)
	PixelUI.padTo(panel, PANEL_SPRITE, L.pad)

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, L.titleGap)
	list.Parent = panel

	-- The title in the wireframe's own pale green, so the words are visibly
	-- the solid's; the body in the cream the kit puts on dark wood.
	local title = label(panel, "Title", Theme.Fonts.Heading, Theme.TextSize.Subheading, Theme.Color.MenuWire)
	title.LayoutOrder = 1

	local body = label(panel, "Body", Theme.Fonts.Body, Theme.TextSize.Body, Theme.PixelColor.OnWood)
	body.LayoutOrder = 2

	local hint = label(panel, "Hint", Theme.Fonts.Body, Theme.TextSize.Small - 1, Theme.PixelColor.OnWoodDim)
	hint.LayoutOrder = 3
	hint.Text = hintText()

	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingTop = UDim.new(0, L.hintGap - L.titleGap)
	hintPad.Parent = hint

	self.screen = screen
	self.root = root
	self.scale = scale
	self.host = host
	self.hostScale = hostScale
	self.art = art
	self.panel = panel
	self.title = title
	self.body = body
	self.hint = hint

	self.step = nil
	self.shown = false
	-- Whether the arrival has actually played: a step shown while a menu is
	-- up waits, and gets its entrance when the menu closes.
	self.entered = false
	self.expanded = true
	self.suppressed = false
	self.interacted = false
	self.destroyed = false
	self.heldAttention = nil

	-- Bumped by anything that starts a sequence; a delayed step that finds a
	-- newer token does nothing. The attention nod has its own, so collapsing
	-- the panel does not cancel it but a menu opening can.
	self.token = 0
	self.attentionToken = 0
	self.attentionDue = nil
	self.attentionLeft = ATTENTION_COUNT

	self.onInteract = nil
	self.connections = {}

	table.insert(self.connections, host.Activated:Connect(function()
		self:_interact()
		self:toggle()
	end))

	table.insert(self.connections, panel.Activated:Connect(function()
		self:_interact()
		self:collapse()
	end))

	table.insert(self.connections, screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_fit()
	end))

	self:_fit()
	self:_setTextAlpha(1)

	return self
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

-- Shrinks with the screen, grows a little on a tall one, and never takes more
-- than its share of the width.
function TutorialPanel:_fit()
	local size = self.screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local byHeight = math.clamp(size.Y / DESIGN_HEIGHT, MIN_SCALE, MAX_SCALE)
	local byWidth = size.X * MAX_WIDTH_SHARE / L.width
	self.scale.Scale = math.min(byHeight, byWidth)
end

function TutorialPanel:_later(delay: number, token: number, fn: () -> ())
	task.delay(delay, function()
		if self.destroyed or self.token ~= token then
			return
		end
		fn()
	end)
end

-- The title, the body and the hint at one transparency. 1 is invisible.
function TutorialPanel:_setTextAlpha(transparency: number)
	self.title.TextTransparency = transparency
	self.body.TextTransparency = transparency
	self.hint.TextTransparency = transparency
end

function TutorialPanel:_setWords(step)
	self.title.Text = step.title or ""
	self.body.Text = step.body or ""
	self.body.MaxVisibleGraphemes = -1
end

-- ---------------------------------------------------------------------------
-- Sequences
-- ---------------------------------------------------------------------------

--[[
	The panel unfolding under the solid and its words arriving, from nothing.
	Used by the entrance and by expand(); the entrance adds the solid's own
	arrival in front of it. `typed` is whether the body types on - it does the
	first time a step is seen, and not when the player is merely reopening it.
]]
function TutorialPanel:_unfoldPanel(token: number, typed: boolean)
	local panel = self.panel

	panel.Visible = true
	panel.ImageTransparency = 1
	panel.Position = UDim2.new(1, 0, 0, L.host + L.gap - 12)
	self:_setTextAlpha(1)

	tween(panel, UNFOLD, {
		ImageTransparency = 0,
		Position = UDim2.new(1, 0, 0, L.host + L.gap),
	})

	local titleAt = ENTER_TITLE_AT - ENTER_PANEL_AT
	local bodyAt = ENTER_BODY_AT - ENTER_PANEL_AT

	self:_later(titleAt, token, function()
		tween(self.title, FADE, { TextTransparency = 0 })
	end)

	self:_later(bodyAt, token, function()
		local body = self.body
		body.TextTransparency = 0

		local hintAt = ENTER_HINT_AFTER
		if typed then
			local count = utf8.len(body.Text) or #body.Text
			local duration = math.clamp(count * TYPE_PER_CHAR, TYPE_MIN, TYPE_MAX)
			body.MaxVisibleGraphemes = 0
			tween(body, TweenInfo.new(duration, Enum.EasingStyle.Linear), { MaxVisibleGraphemes = count })
			hintAt += duration
		else
			body.MaxVisibleGraphemes = -1
		end

		self:_later(hintAt, token, function()
			tween(self.hint, FADE, { TextTransparency = 0 })
		end)
	end)
end

function TutorialPanel:_foldPanel(token: number, onDone: (() -> ())?)
	local panel = self.panel

	tween(panel, FADE_OUT, {
		ImageTransparency = 1,
		Position = UDim2.new(1, 0, 0, L.host + L.gap - 8),
	})
	tween(self.title, FADE_OUT, { TextTransparency = 1 })
	tween(self.body, FADE_OUT, { TextTransparency = 1 })
	tween(self.hint, FADE_OUT, { TextTransparency = 1 })

	self:_later(FADE_OUT.Time, token, function()
		panel.Visible = false
		if onDone then
			onDone()
		end
	end)
end

--[[
	The whole arrival. The solid slides and pops in, bursts once it is there -
	the burst is what makes it briefly brighter and faster than it will rest -
	and the sound plays under that; then the panel and its words.
]]
function TutorialPanel:_enter(token: number)
	local root = self.root

	self.entered = true
	self.screen.Enabled = true
	root.Visible = true
	root.Position = UDim2.new(1, -L.edge + ENTER_SLIDE, 0, L.top)
	self.hostScale.Scale = ENTER_SCALE
	self.panel.Visible = false

	self.art:setVisible(true)
	tween(root, SLIDE_IN, { Position = UDim2.new(1, -L.edge, 0, L.top) })
	tween(self.hostScale, POP_IN, { Scale = 1 })

	self:_later(ENTER_BURST_AT, token, function()
		self.art:burst(nil, ENTER_BURST)
		Sounds.play(ENTER_SOUND, ENTER_SOUND_VOLUME)
	end)

	self:_later(ENTER_PANEL_AT, token, function()
		if self.expanded then
			self:_unfoldPanel(token, true)
		end
	end)

	-- The nod is counted from when the words have finished arriving.
	local settled = ENTER_BODY_AT + TYPE_MAX + ENTER_HINT_AFTER
	self:_armAttention(settled + ATTENTION_DELAY)
end

-- ---------------------------------------------------------------------------
-- Attention
-- ---------------------------------------------------------------------------

function TutorialPanel:_armAttention(delay: number)
	if self.interacted or self.attentionLeft <= 0 then
		return
	end

	self.attentionToken += 1
	local token = self.attentionToken
	self.attentionDue = os.clock() + delay

	task.delay(delay, function()
		if self.destroyed or self.attentionToken ~= token then
			return
		end
		self.attentionDue = nil

		if self.interacted or not self.shown or self.suppressed then
			return
		end

		self.attentionLeft -= 1
		self.art:burst(nil, ATTENTION_BURST)
		Motion.pulse(if self.expanded then self.panel else self.host, ATTENTION_PULSE)

		if self.attentionLeft > 0 then
			self:_armAttention(ATTENTION_DELAY)
		end
	end)
end

-- Cancels a pending nod, remembering how long it had left so a menu closing
-- can re-arm it rather than restart it.
function TutorialPanel:_holdAttention(): number?
	self.attentionToken += 1
	local due = self.attentionDue
	self.attentionDue = nil
	if due then
		return math.max(due - os.clock(), 2)
	end
	return nil
end

function TutorialPanel:_interact()
	if self.interacted then
		return
	end
	self.interacted = true
	self:_holdAttention()

	if self.onInteract then
		task.spawn(self.onInteract)
	end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

--[[
	Shows a step. Hidden, the guide enters with it; already up, the words
	change in place with a short fold and unfold and the solid bursts, so a new
	step is noticed without the whole arrival playing again.
]]
function TutorialPanel:showStep(step)
	assert(type(step) == "table" and step.title, "[TutorialPanel] showStep wants a TutorialSteps entry")

	self.step = step
	self.token += 1
	local token = self.token

	if not self.shown then
		self.shown = true
		self.expanded = true
		self:_setWords(step)

		if not self.suppressed then
			self:_enter(token)
		end
		return
	end

	-- A new step is new information: it opens the panel even if the player
	-- had collapsed the last one.
	self.expanded = true

	if self.suppressed then
		self:_setWords(step)
		return
	end

	self.art:burst(nil, ENTER_BURST)

	if self.panel.Visible then
		self:_foldPanel(token, function()
			self:_setWords(step)
			self:_unfoldPanel(token, true)
		end)
	else
		self:_setWords(step)
		self:_unfoldPanel(token, true)
	end
end

function TutorialPanel:expand()
	if self.expanded then
		return
	end
	self.expanded = true

	if not self.shown or self.suppressed then
		return
	end

	self.token += 1
	self:_unfoldPanel(self.token, false)
end

function TutorialPanel:collapse()
	if not self.expanded then
		return
	end
	self.expanded = false

	if not self.shown or self.suppressed then
		return
	end

	self.token += 1
	self:_foldPanel(self.token)
end

function TutorialPanel:toggle()
	if self.expanded then
		self:collapse()
	else
		self:expand()
	end
end

--[[
	A menu is up, or has just closed. Out: everything fades and the ScreenGui
	is disabled, so nothing here is drawn, clickable or animating under the
	menu. Back: the solid pops in again and the panel returns only if it was
	open before - the collapsed state survives the trip.
]]
function TutorialPanel:setSuppressed(suppressed: boolean)
	suppressed = suppressed == true
	if suppressed == self.suppressed then
		return
	end
	self.suppressed = suppressed

	if not self.shown then
		return
	end

	self.token += 1
	local token = self.token

	if suppressed then
		self.heldAttention = self:_holdAttention()
		self.art:setVisible(false)
		tween(self.hostScale, FADE_OUT, { Scale = ENTER_SCALE })
		self:_foldPanel(token, function()
			self.screen.Enabled = false
		end)
		return
	end

	-- Never seen yet: the whole arrival, now that there is a screen to see it.
	if not self.entered then
		self:_enter(token)
		return
	end

	self.screen.Enabled = true
	self.root.Position = UDim2.new(1, -L.edge, 0, L.top)
	self.art:setVisible(true)
	tween(self.hostScale, POP_IN, { Scale = 1 })

	if self.expanded then
		self:_unfoldPanel(token, false)
	end

	if self.heldAttention then
		self:_armAttention(self.heldAttention)
		self.heldAttention = nil
	end
end

-- Gone, with nothing left running. showStep brings it back with a full
-- entrance, which is what a later step arriving after a long gap wants.
function TutorialPanel:hide()
	if not self.shown then
		return
	end
	self.shown = false
	self.entered = false
	self.step = nil

	self.token += 1
	local token = self.token
	self:_holdAttention()
	self.heldAttention = nil

	if self.suppressed or not self.screen.Enabled then
		self.panel.Visible = false
		self.screen.Enabled = false
		return
	end

	self.art:setVisible(false)
	tween(self.hostScale, FADE_OUT, { Scale = ENTER_SCALE })
	self:_foldPanel(token, function()
		self.screen.Enabled = false
	end)
end

function TutorialPanel:isShown(): boolean
	return self.shown
end

function TutorialPanel:isExpanded(): boolean
	return self.expanded
end

function TutorialPanel:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.token += 1
	self.attentionToken += 1

	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)

	self.art:destroy()
	self.screen:Destroy()
end

return TutorialPanel
