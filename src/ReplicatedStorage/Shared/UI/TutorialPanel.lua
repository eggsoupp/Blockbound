--[[
	TutorialPanel

	The tutorial guide on the gameplay HUD: one dark pixel-kit card in the top
	right corner. The Tab menu's wireframe solid - the Worldkeeper - sits in
	its header beside the speaker's name and the step pips, and under that
	are the step's title, one or two lines of instruction, the goals as tick
	boxes, and a button when the step has one.

		local panel = TutorialPanel.new(playerGui)
		panel:show(view)            -- enters if hidden; a new id turns the page
		panel:complete()            -- every goal ticks, the solid bursts
		panel:setSuppressed(true)   -- a menu is up: fade out, and back with false
		panel:hide()                -- gone, nothing animating
		panel:destroy()

		panel.onAction = function() end   -- the step's button was pressed

	A view is a step with everything already filled in:

		{
			id = "table", index = 2, count = 5,
			speaker = "THE WORLDKEEPER",
			title = "MAKE A CRAFTING TABLE",
			body = "Press [B] to craft ...",      -- [x] is drawn as a key
			goals = { { text = "Craft Wood Planks", done = true }, ... },
			message = nil,                        -- a red line under the goals
			action = "GO TO MY ISLAND",           -- optional
			actionEnabled = true,
		}

	It draws. It does not decide: which step shows and what finishes it is
	StarterPlayerScripts.TutorialClient's and the server's, and the words are
	Shared.UI.TutorialSteps'.

	WHERE IT SITS

	Top right, under Roblox's top bar - the ScreenGui respects the inset.
	The hotbar and the gear are top LEFT, the vitals and abilities bottom
	left, the boss bar bottom centre. Above the crafting window on purpose: the
	table is made with that window open, and the guide is what says which
	recipe comes next. Designed in 1080p pixels and fitted with one UIScale.

	MOTION

	Arriving, the card slides in and fades up, the solid pops and bursts, and
	the instruction types on - quickly; it is read while playing. A finished
	step ticks its boxes and bursts the solid; the next one turns the page:
	the words fade out and the new ones type in, the card stays put. One fade
	value per layer (the card, and the words on it) drives every transparency,
	so nothing is ever left half faded by two tweens disagreeing.
]]

local TweenService = game:GetService("TweenService")
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
	width = 360,

	-- Inside the card, past the sprite's own border.
	pad = 8,
	gap = 8,

	-- The header: the solid's square, and the words beside it.
	solid = 64,
	solidGap = 10,
	speakerHeight = 16,
	titleTop = 22,
	titleHeight = 30,

	pip = 8,
	pipGap = 4,

	goalHeight = 24,
	goalGap = 4,
	-- The kit's tick boxes, at this many pixels a texel.
	checkScale = 2,

	buttonHeight = 14 * Theme.Pixel.Scale,
}

local DESIGN_HEIGHT = 1080
local MIN_SCALE = 0.72
local MAX_SCALE = 1.1

-- The card is never wider than this share of the screen.
local MAX_WIDTH_SHARE = 0.34

local CARD_SPRITE = "tooltip"

local BODY_SIZE = 17
local TITLE_SIZE = 20

-- Keys in the instruction, in the kit's selection gold.
local KEY_HEX = "#" .. Theme.PixelColor.Selection:ToHex()

local ENTER_SLIDE = 40
local ENTER_SCALE = 0.6
local ENTER_BURST_AT = 0.2
local ENTER_WORDS_AT = 0.3

-- Type-on: seconds per character, within a floor and a ceiling.
local TYPE_PER_CHAR = 0.012
local TYPE_MIN = 0.25
local TYPE_MAX = 0.9

local ENTER_SOUND = "ui.open"
local ENTER_SOUND_VOLUME = 0.45
local COMPLETE_SOUND = "craft.success"
local COMPLETE_SOUND_VOLUME = 0.5

local FADE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PAGE_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PAGE_IN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_IN = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP_IN = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- The pips: done, current, still to come.
local PIP_DONE = Theme.Color.MenuWire
local PIP_NOW = Theme.PixelColor.Selection
local PIP_LATER = Theme.PixelColor.OnWoodDim
local PIP_LATER_ALPHA = 0.65

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

-- [B] becomes a gold key. Our own words only, so nothing here needs escaping.
local function richKeys(text: string): string
	return (string.gsub(text, "%[([^%]]+)%]", '<font color="' .. KEY_HEX .. '"><b>[%1]</b></font>'))
end

local function visibleLength(richText: string): number
	local plain = string.gsub(richText, "<[^>]->", "")
	return utf8.len(plain) or #plain
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

function TutorialPanel.new(playerGui: Instance)
	local self = setmetatable({}, TutorialPanel)

	local screen = Instance.new("ScreenGui")
	screen.Name = "TutorialGuide"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	-- Over the crafting window (10); every other menu suppresses the guide.
	screen.DisplayOrder = 11
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false
	screen.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -L.edge, 0, L.top)
	root.Size = UDim2.fromOffset(L.width, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundTransparency = 1
	root.Parent = screen

	local scale = Instance.new("UIScale")
	scale.Parent = root

	-- A button so a click on the card is processed input: mining and
	-- placement leave a click on the guide alone.
	local card = Instance.new("ImageButton")
	card.Name = "Card"
	card.AutoButtonColor = false
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Parent = root
	PixelUI.apply(card, CARD_SPRITE)
	PixelUI.padTo(card, CARD_SPRITE, L.pad)

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, L.gap)
	list.Parent = card

	-- The header: the solid on the left, the speaker and the pips across the
	-- top of the rest, the title under them.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, L.solid)
	header.LayoutOrder = 1
	header.Parent = card

	local host = Instance.new("Frame")
	host.Name = "Worldkeeper"
	host.AnchorPoint = Vector2.new(0.5, 0.5)
	host.Position = UDim2.fromOffset(L.solid / 2, L.solid / 2)
	host.Size = UDim2.fromOffset(L.solid, L.solid)
	host.BackgroundTransparency = 1
	host.Parent = header

	-- Named for Motion.pulse, which reuses a UIScale of this name.
	local hostScale = Instance.new("UIScale")
	hostScale.Name = "MotionPulse"
	hostScale.Parent = host

	local art = MenuBackdrop.new(host, { look = "guide" })

	local textLeft = L.solid + L.solidGap

	local speaker = label(header, "Speaker", Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.PixelColor.OnWoodDim)
	speaker.AutomaticSize = Enum.AutomaticSize.None
	speaker.Position = UDim2.fromOffset(textLeft, 2)
	speaker.Size = UDim2.new(1, -textLeft, 0, L.speakerHeight)
	speaker.TextWrapped = false

	local pips = Instance.new("Frame")
	pips.Name = "Pips"
	pips.AnchorPoint = Vector2.new(1, 0)
	pips.Position = UDim2.new(1, 0, 0, 6)
	pips.Size = UDim2.fromOffset(0, L.pip)
	pips.AutomaticSize = Enum.AutomaticSize.X
	pips.BackgroundTransparency = 1
	pips.Parent = header

	local pipList = Instance.new("UIListLayout")
	pipList.FillDirection = Enum.FillDirection.Horizontal
	pipList.SortOrder = Enum.SortOrder.LayoutOrder
	pipList.Padding = UDim.new(0, L.pipGap)
	pipList.Parent = pips

	-- One line whatever the font: scaled down rather than wrapped.
	local title = label(header, "Title", Theme.Fonts.Heading, TITLE_SIZE, Theme.Color.MenuWire)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(textLeft, L.titleTop)
	title.Size = UDim2.new(1, -textLeft, 0, L.titleHeight)
	title.TextWrapped = false
	title.TextScaled = true
	title.TextYAlignment = Enum.TextYAlignment.Center

	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MaxTextSize = TITLE_SIZE
	titleLimit.MinTextSize = 12
	titleLimit.Parent = title

	local divider = PixelUI.divider(card)
	divider.LayoutOrder = 2

	local body = label(card, "Body", Theme.Fonts.Body, BODY_SIZE, Theme.PixelColor.OnWood)
	body.RichText = true
	body.LayoutOrder = 3
	body.LineHeight = 1.1

	local goals = Instance.new("Frame")
	goals.Name = "Goals"
	goals.BackgroundTransparency = 1
	goals.Size = UDim2.new(1, 0, 0, 0)
	goals.AutomaticSize = Enum.AutomaticSize.Y
	goals.LayoutOrder = 4
	goals.Parent = card

	local goalList = Instance.new("UIListLayout")
	goalList.SortOrder = Enum.SortOrder.LayoutOrder
	goalList.Padding = UDim.new(0, L.goalGap)
	goalList.Parent = goals

	local message = label(card, "Message", Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.PixelColor.BadLight)
	message.LayoutOrder = 5
	message.Visible = false

	local action = PixelUI.button(card, {
		name = "Action",
		color = "green",
		size = UDim2.new(1, 0, 0, L.buttonHeight),
		onClick = function()
			if self.onAction then
				task.spawn(self.onAction)
			end
		end,
	})
	action.button.LayoutOrder = 6
	action.button.Visible = false

	self.screen = screen
	self.root = root
	self.scale = scale
	self.card = card
	self.host = host
	self.hostScale = hostScale
	self.art = art
	self.speaker = speaker
	self.pips = pips
	self.title = title
	self.divider = divider
	self.body = body
	self.goals = goals
	self.message = message
	self.action = action

	self.pipFrames = {}
	self.goalRows = {}
	self.view = nil

	-- 1 is fully shown. `card` is the card and its frame; `words` is what is
	-- written on it, and is multiplied by `card`.
	self.cardFade = Instance.new("NumberValue")
	self.wordsFade = Instance.new("NumberValue")
	self.wordsFade.Value = 1

	self.shown = false
	self.entered = false
	self.suppressed = false
	self.destroyed = false
	self.token = 0

	self.onAction = nil
	self.connections = {}

	table.insert(self.connections, self.cardFade.Changed:Connect(function()
		self:_paint()
	end))
	table.insert(self.connections, self.wordsFade.Changed:Connect(function()
		self:_paint()
	end))
	table.insert(self.connections, screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_fit()
	end))

	self:_fit()
	self:_paint()

	return self
end

-- ---------------------------------------------------------------------------
-- Layout and paint
-- ---------------------------------------------------------------------------

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

-- Every transparency on the card, from the two fades. Nothing else writes them.
function TutorialPanel:_paint()
	local card = self.cardFade.Value
	local words = card * self.wordsFade.Value

	local function alpha(base: number, shown: number): number
		return 1 - (1 - base) * shown
	end

	self.card.ImageTransparency = alpha(0, card)
	self.divider.ImageTransparency = alpha(0, card)
	self.speaker.TextTransparency = alpha(0, card)

	for _, pip in ipairs(self.pipFrames) do
		local base = if pip:GetAttribute("Later") then PIP_LATER_ALPHA else 0
		pip.BackgroundTransparency = alpha(base, card)
	end

	self.title.TextTransparency = alpha(0, words)
	self.body.TextTransparency = alpha(0, words)
	self.message.TextTransparency = alpha(0, words)

	for _, row in ipairs(self.goalRows) do
		row.check.ImageTransparency = alpha(0, words)
		row.text.TextTransparency = alpha(0, words)
	end

	self.action.button.ImageTransparency = alpha(0, words)
	self.action.label.TextTransparency = alpha(0, words)
end

function TutorialPanel:_setPips(index: number, count: number)
	for i = #self.pipFrames + 1, count do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.LayoutOrder = i
		pip.Size = UDim2.fromOffset(L.pip, L.pip)
		pip.BorderSizePixel = 0
		pip.Parent = self.pips
		self.pipFrames[i] = pip
	end
	for i = #self.pipFrames, count + 1, -1 do
		self.pipFrames[i]:Destroy()
		self.pipFrames[i] = nil
	end

	for i, pip in ipairs(self.pipFrames) do
		local later = i > index
		pip:SetAttribute("Later", later)
		pip.BackgroundColor3 = if i < index then PIP_DONE elseif i == index then PIP_NOW else PIP_LATER
	end
end

function TutorialPanel:_paintGoal(row, done: boolean)
	row.done = done
	PixelUI.apply(row.check, if done then "checkbox_on" else "checkbox_off", L.checkScale)
	row.text.TextColor3 = if done then Theme.PixelColor.GoodLight else Theme.PixelColor.OnWood
end

function TutorialPanel:_buildGoals(goals)
	for _, row in ipairs(self.goalRows) do
		row.frame:Destroy()
	end
	table.clear(self.goalRows)

	-- No empty row of padding under a step with nothing to tick.
	self.goals.Visible = goals ~= nil and #goals > 0

	for index, goal in ipairs(goals or {}) do
		local frame = Instance.new("Frame")
		frame.Name = "Goal" .. index
		frame.LayoutOrder = index
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(1, 0, 0, L.goalHeight)
		frame.Parent = self.goals

		local check = PixelUI.image(frame, "checkbox_off", L.checkScale)
		check.Name = "Check"
		check.AnchorPoint = Vector2.new(0, 0.5)
		check.Position = UDim2.new(0, 0, 0.5, 0)

		local checkSize = PixelUI.get("checkbox_off").size.X * L.checkScale
		local text = label(frame, "Text", Theme.Fonts.BodyBold, Theme.TextSize.Body, Theme.PixelColor.OnWood)
		text.AutomaticSize = Enum.AutomaticSize.None
		text.Position = UDim2.fromOffset(checkSize + 8, 0)
		text.Size = UDim2.new(1, -(checkSize + 8), 1, 0)
		text.TextYAlignment = Enum.TextYAlignment.Center
		text.TextWrapped = false
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.Text = goal.text

		local row = { frame = frame, check = check, text = text, done = false }
		self:_paintGoal(row, goal.done == true)
		self.goalRows[index] = row
	end
end

-- Ticks what has changed since the last view, with a little pop on each.
function TutorialPanel:_updateGoals(goals)
	if #goals ~= #self.goalRows then
		self:_buildGoals(goals)
		return
	end

	for index, goal in ipairs(goals) do
		local row = self.goalRows[index]
		row.text.Text = goal.text
		local done = goal.done == true
		if done ~= row.done then
			self:_paintGoal(row, done)
			if done then
				Motion.pulse(row.check, 1.35)
			end
		end
	end
end

function TutorialPanel:_setMessage(text: string?)
	local has = type(text) == "string" and text ~= ""
	self.message.Visible = has
	self.message.Text = if has then text else ""
end

function TutorialPanel:_setAction(view)
	local has = type(view.action) == "string" and view.action ~= ""
	self.action.button.Visible = has
	if has then
		self.action.label.Text = view.action
		self.action.setEnabled(view.actionEnabled ~= false)
	end
end

-- Everything a view says, written at once. The body is left typed out.
function TutorialPanel:_write(view)
	self.speaker.Text = view.speaker or ""
	self.title.Text = view.title or ""
	self.body.Text = richKeys(view.body or "")
	self.body.MaxVisibleGraphemes = -1
	self:_setPips(view.index or 1, view.count or 1)
	self:_buildGoals(view.goals)
	self:_setMessage(view.message)
	self:_setAction(view)
	self:_paint()
end

function TutorialPanel:_typeBody()
	local body = self.body
	local count = visibleLength(body.Text)
	local duration = math.clamp(count * TYPE_PER_CHAR, TYPE_MIN, TYPE_MAX)
	body.MaxVisibleGraphemes = 0
	tween(body, TweenInfo.new(duration, Enum.EasingStyle.Linear), { MaxVisibleGraphemes = count })
end

-- ---------------------------------------------------------------------------
-- Sequences
-- ---------------------------------------------------------------------------

function TutorialPanel:_enter(token: number)
	self.entered = true
	self.screen.Enabled = true

	self.root.Position = UDim2.new(1, -L.edge + ENTER_SLIDE, 0, L.top)
	self.hostScale.Scale = ENTER_SCALE
	self.cardFade.Value = 0
	self.wordsFade.Value = 0

	self.art:setVisible(true)
	tween(self.root, SLIDE_IN, { Position = UDim2.new(1, -L.edge, 0, L.top) })
	tween(self.cardFade, FADE_IN, { Value = 1 })
	tween(self.hostScale, POP_IN, { Scale = 1 })

	self:_later(ENTER_BURST_AT, token, function()
		self.art:burst(nil, 1)
		Sounds.play(ENTER_SOUND, ENTER_SOUND_VOLUME)
	end)

	self:_later(ENTER_WORDS_AT, token, function()
		tween(self.wordsFade, PAGE_IN, { Value = 1 })
		self:_typeBody()
	end)
end

-- The words fade out, change, and the new ones type in. The card stays.
function TutorialPanel:_turnPage(view, token: number)
	tween(self.wordsFade, PAGE_OUT, { Value = 0 })

	self:_later(PAGE_OUT.Time, token, function()
		self:_write(view)
		self.art:burst(nil, 0.7)
		tween(self.wordsFade, PAGE_IN, { Value = 1 })
		self:_typeBody()
	end)
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function TutorialPanel:show(view)
	assert(type(view) == "table" and view.id, "[TutorialPanel] show wants a view with an id")

	local previous = self.view
	self.view = view

	if not self.shown then
		self.shown = true
		self.token += 1
		self:_write(view)
		if not self.suppressed then
			self:_enter(self.token)
		end
		return
	end

	-- Suppressed or not yet seen: written now, shown when the menu closes.
	if self.suppressed or not self.entered then
		self.token += 1
		self:_write(view)
		return
	end

	if not previous or previous.id ~= view.id then
		self.token += 1
		self:_turnPage(view, self.token)
		return
	end

	-- The same step with something changed: written in place, no page turn.
	self.speaker.Text = view.speaker or ""
	self.title.Text = view.title or ""
	self:_setPips(view.index or 1, view.count or 1)
	self:_updateGoals(view.goals or {})
	self:_setMessage(view.message)
	self:_setAction(view)

	local body = richKeys(view.body or "")
	if body ~= self.body.Text then
		self.body.Text = body
		self.body.MaxVisibleGraphemes = -1
		Motion.fadeInText(self.body)
	end

	self:_paint()
end

-- The current step is finished: every box ticks and the solid bursts.
function TutorialPanel:complete()
	if not self.shown then
		return
	end

	for _, row in ipairs(self.goalRows) do
		if not row.done then
			self:_paintGoal(row, true)
			Motion.pulse(row.check, 1.35)
		end
	end
	self:_setAction({})

	if not self.suppressed then
		self.art:burst(nil, 1)
		Motion.pulse(self.host, 1.15)
		Sounds.play(COMPLETE_SOUND, COMPLETE_SOUND_VOLUME)
	end
end

--[[
	A menu is up, or has just closed. Out: everything fades and the ScreenGui
	is disabled, so nothing here is drawn or clickable under the menu. Back:
	the card fades up as it was, or makes its whole entrance if it never had
	the chance to.
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
		self.art:setVisible(false)
		tween(self.cardFade, FADE_OUT, { Value = 0 })
		self:_later(FADE_OUT.Time, token, function()
			self.screen.Enabled = false
		end)
		return
	end

	if not self.entered then
		self:_enter(token)
		return
	end

	-- Written again: a page turn the menu interrupted never got to write the
	-- new words, and writing the same ones twice changes nothing.
	if self.view then
		self:_write(self.view)
	end

	self.screen.Enabled = true
	self.root.Position = UDim2.new(1, -L.edge, 0, L.top)
	self.wordsFade.Value = 1
	self.art:setVisible(true)
	tween(self.cardFade, FADE_IN, { Value = 1 })
end

function TutorialPanel:hide()
	if not self.shown then
		return
	end
	self.shown = false
	self.entered = false
	self.view = nil

	self.token += 1
	local token = self.token

	if self.suppressed or not self.screen.Enabled then
		self.screen.Enabled = false
		return
	end

	self.art:setVisible(false)
	tween(self.root, FADE_OUT, { Position = UDim2.new(1, -L.edge + ENTER_SLIDE, 0, L.top) })
	tween(self.cardFade, FADE_OUT, { Value = 0 })
	self:_later(FADE_OUT.Time, token, function()
		self.screen.Enabled = false
	end)
end

function TutorialPanel:isShown(): boolean
	return self.shown
end

function TutorialPanel:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.token += 1

	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)

	self.art:destroy()
	self.cardFade:Destroy()
	self.wordsFade:Destroy()
	self.screen:Destroy()
end

return TutorialPanel
