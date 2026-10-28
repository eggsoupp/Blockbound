--[[
	TutorialChoice

	The tutorial's ability choice, drawn in the Tab menu. Two parts, never on
	screen together:

	  the picker    three cards across the middle of the menu, one per common
	                attack. The loadout list steps aside for it (AbilityPanel.
	                setHeldBack), so the cards have the menu to themselves.
	  the word      once one is picked: the loadout comes back with the new
	                ability in it, and a short line low on the screen says how
	                to cast it, with a button to carry on.

		local choice = TutorialChoice.new(playerGui, TutorialSteps.Choices)
		choice:showChoices(title, subtitle)          -- the picker
		choice:showChosen(name, title, subtitle)     -- the word
		choice:setMessage(text)                      -- a refusal from the server, or nil
		choice:release()                             -- let go of an unanswered pick
		choice:hide()

		choice.onChoose = function(name) end
		choice.onContinue = function() end  -- the word's button

	THE TAB MENU'S LOOK, NOT THE PIXEL KIT'S

	It is drawn inside the Tab menu, which keeps its own art: pale hairlines
	over the wireframe, no windows. So the cards are built like the loadout's
	cards - a thin edge, a dark fill that firms up when pointed at - with the
	edge in the element's colour and a small glyph drawn a pixel at a time, the
	way AbilityPanel draws its bin. Nothing to upload, crisp at any size.

	It knows nothing about the tutorial's state. TutorialClient says when to
	show which, and sends the pick to the server.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local AbilityPanel = require(script.Parent:WaitForChild("AbilityPanel"))
local AbilityConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Abilities"):WaitForChild("AbilityConfig")
)
local Sounds = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("Sounds")
)

local TutorialChoice = {}
TutorialChoice.__index = TutorialChoice

-- ---------------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------------

-- 1080p pixels, fitted with a UIScale.
local P = {
	cardWidth = 250,
	cardHeight = 256,
	cardGap = 36,

	titleSize = 30,
	titleHeight = 36,
	subtitleTop = 44,
	subtitleHeight = 46,
	cardsTop = 108,

	-- Inside a card, from its top.
	glyphTop = 26,
	nameTop = 100,
	tierTop = 130,
	blurbTop = 158,
	blurbHeight = 56,
	tagsFromBottom = 30,
	cardPad = 20,
}
P.width = P.cardWidth * 3 + P.cardGap * 2
P.height = P.cardsTop + P.cardHeight

-- The word, low on the screen and clear of the loadout and "Tab to resume".
local W = {
	width = 640,
	titleSize = 26,
	titleHeight = 32,
	subtitleTop = 38,
	subtitleHeight = 24,
	buttonTop = 78,
	buttonWidth = 220,
	buttonHeight = 38,
	bottom = 74,
}
W.height = W.buttonTop + W.buttonHeight

-- Room round each group: a card grows on hover, and a CanvasGroup cuts
-- whatever reaches past its edge.
local MARGIN = 16

local DESIGN_HEIGHT = 1080
local MIN_SCALE = 0.6
local MAX_SCALE = 1.1

local GLYPH_PIXEL = 5

-- Nearly solid: the Tab menu's wireframe drifts behind the cards, and through
-- a see-through card its lines cut across every word on it.
local CARD_REST = 0.1
local CARD_HOVER = 0.02
local STROKE_REST = 0.5
local STROKE_HOVER = 0
local DIMMED = 0.5

local KEY_HEX = "#" .. Theme.Color.Accent:ToHex()

--[[
	The glyphs, a pixel at a time: '#' in the element's colour, '+' in its
	light. Change one by editing the picture; width and height are measured
	off it.
]]
local GLYPHS = {
	fire = {
		".....#.....",
		"....##.....",
		"....###....",
		"...####..#.",
		"..#####.##.",
		"..########.",
		".####+####.",
		".###+++###.",
		".###+++###.",
		"..##+++##..",
		"...#####...",
		"....###....",
	},
	wind = {
		"......###..",
		".........#.",
		".........#.",
		"########+#.",
		"...........",
		"...........",
		"##########.",
		"...........",
		"...........",
		"#######+#..",
		"........#..",
		".....###...",
	},
	water = {
		".....#.....",
		".....#.....",
		"....###....",
		"....###....",
		"...#####...",
		"..###+###..",
		"..##+####..",
		".###+#####.",
		".####+####.",
		".#########.",
		"..#######..",
		"...#####...",
	},
}

local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE = Theme.Tween.Fade
local POP = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- How far a group rises as it fades in.
local RISE = 18

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function tween(instance: Instance, info: TweenInfo, goal: {})
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

local function text(parent: Instance, y: number, height: number, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.Text = ""
	label.Parent = parent
	return label
end

local function richKeys(value: string): string
	return (string.gsub(value, "%[([^%]]+)%]", '<font color="' .. KEY_HEX .. '"><b>[%1]</b></font>'))
end

local function drawGlyph(parent: Instance, picture: { string }, color: Color3, light: Color3): Frame
	local field = Instance.new("Frame")
	field.Name = "Glyph"
	field.BackgroundTransparency = 1
	field.AnchorPoint = Vector2.new(0.5, 0)
	field.Size = UDim2.fromOffset(#picture[1] * GLYPH_PIXEL, #picture * GLYPH_PIXEL)
	field.Parent = parent

	for row, line in ipairs(picture) do
		for column = 1, #line do
			local mark = string.sub(line, column, column)
			if mark == "#" or mark == "+" then
				local pixel = Instance.new("Frame")
				pixel.Position = UDim2.fromOffset((column - 1) * GLYPH_PIXEL, (row - 1) * GLYPH_PIXEL)
				pixel.Size = UDim2.fromOffset(GLYPH_PIXEL, GLYPH_PIXEL)
				pixel.BackgroundColor3 = if mark == "+" then light else color
				pixel.BorderSizePixel = 0
				pixel.Parent = field
			end
		end
	end

	return field
end

-- A CanvasGroup holding one part, so the part fades on one property, with
-- the frame inside it that the part is laid out in.
local function group(screen: Instance, name: string, width: number, height: number, anchor: Vector2, position: UDim2)
	local root = Instance.new("CanvasGroup")
	root.Name = name
	root.AnchorPoint = anchor
	root.Position = position
	root.Size = UDim2.fromOffset(width + MARGIN * 2, height + MARGIN * 2)
	root.BackgroundTransparency = 1
	root.GroupTransparency = 1
	root.Visible = false
	root.Parent = screen

	local scale = Instance.new("UIScale")
	scale.Parent = root

	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.Position = UDim2.fromOffset(MARGIN, MARGIN)
	inner.Size = UDim2.fromOffset(width, height)
	inner.BackgroundTransparency = 1
	inner.Parent = root

	return { root = root, scale = scale, inner = inner, position = position, shown = false, width = width }
end

-- A plain hairline button in the Tab menu's style.
local function hairlineButton(parent: Instance, label: string, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BackgroundColor3 = Theme.Color.Panel
	button.BackgroundTransparency = CARD_REST
	button.BorderSizePixel = 0
	button.FontFace = Theme.Fonts.Heading
	button.TextSize = Theme.TextSize.Subheading
	button.TextColor3 = Theme.Color.Text
	button.Text = label
	button.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Color.MenuWire
	stroke.Transparency = STROKE_REST
	stroke.Parent = button

	button.MouseEnter:Connect(function()
		tween(button, HOVER, { BackgroundTransparency = CARD_HOVER })
		tween(stroke, HOVER, { Transparency = STROKE_HOVER })
		Sounds.play("ui.hover")
	end)
	button.MouseLeave:Connect(function()
		tween(button, HOVER, { BackgroundTransparency = CARD_REST })
		tween(stroke, HOVER, { Transparency = STROKE_REST })
	end)
	button.Activated:Connect(function()
		Sounds.play("ui.click")
		onClick()
	end)

	return button
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

function TutorialChoice.new(playerGui: Instance, choices)
	local self = setmetatable({}, TutorialChoice)

	local screen = Instance.new("ScreenGui")
	screen.Name = "TutorialChoice"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- Over the Tab menu's backdrop (-1), under every real window.
	screen.DisplayOrder = 1
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false
	screen.Parent = playerGui

	-- The picker, a little below the middle so the title sits about where the
	-- loadout's first card would.
	local picker = group(
		screen, "Picker", P.width, P.height,
		Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 30)
	)

	local title = text(picker.inner, 0, P.titleHeight, Theme.Fonts.Heading, P.titleSize, Theme.Color.MenuWire)
	title.Name = "Title"

	local subtitle = text(
		picker.inner, P.subtitleTop, P.subtitleHeight,
		Theme.Fonts.Body, Theme.TextSize.Subheading, Theme.Color.TextDim
	)
	subtitle.Name = "Subtitle"
	subtitle.RichText = true
	subtitle.TextYAlignment = Enum.TextYAlignment.Top

	-- The word, anchored to the bottom.
	local word = group(
		screen, "Word", W.width, W.height,
		Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -W.bottom)
	)

	local wordTitle = text(word.inner, 0, W.titleHeight, Theme.Fonts.Heading, W.titleSize, Theme.Color.MenuWire)
	wordTitle.Name = "Title"

	local wordSubtitle = text(
		word.inner, W.subtitleTop, W.subtitleHeight,
		Theme.Fonts.Body, Theme.TextSize.Subheading, Theme.Color.TextDim
	)
	wordSubtitle.Name = "Subtitle"
	wordSubtitle.RichText = true

	-- Closes the menu, for anyone without a Tab key to press.
	local battle = hairlineButton(word.inner, "TO BATTLE", function()
		if self.onContinue then
			task.spawn(self.onContinue)
		end
	end)
	battle.Name = "Continue"
	battle.AnchorPoint = Vector2.new(0.5, 0)
	battle.Position = UDim2.new(0.5, 0, 0, W.buttonTop)
	battle.Size = UDim2.fromOffset(W.buttonWidth, W.buttonHeight)

	self.screen = screen
	self.picker = picker
	self.word = word
	self.title = title
	self.subtitle = subtitle
	self.wordTitle = wordTitle
	self.wordSubtitle = wordSubtitle
	self.choices = choices

	self.mode = nil -- nil (hidden), "choices", "chosen"
	self.chosen = nil
	self.pending = nil
	self.message = nil
	self.subtitleText = ""
	self.onChoose = nil
	self.onContinue = nil

	self.cards = {}
	for index, choice in ipairs(choices) do
		self.cards[index] = self:_buildCard(picker.inner, index, choice)
	end

	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_fit()
	end)
	self:_fit()

	return self
end

function TutorialChoice:_buildCard(parent: Instance, index: number, choice)
	local definition = AbilityConfig.get(choice.name)
	local rarity = definition and definition.rarity or "Common"

	local button = Instance.new("TextButton")
	button.Name = choice.name
	button.Text = ""
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromOffset(
		(index - 1) * (P.cardWidth + P.cardGap) + P.cardWidth / 2,
		P.cardsTop + P.cardHeight / 2
	)
	button.Size = UDim2.fromOffset(P.cardWidth, P.cardHeight)
	button.BackgroundColor3 = Theme.Color.Panel
	button.BackgroundTransparency = CARD_REST
	button.BorderSizePixel = 0
	button.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = choice.color
	stroke.Thickness = 1
	stroke.Transparency = STROKE_REST
	stroke.Parent = button

	local grow = Instance.new("UIScale")
	grow.Parent = button

	local glyph = drawGlyph(button, GLYPHS[choice.glyph] or GLYPHS.fire, choice.color, choice.light)
	glyph.Position = UDim2.new(0.5, 0, 0, P.glyphTop)

	local name = text(button, P.nameTop, 28, Theme.Fonts.Heading, 24, Theme.Color.Text)
	name.Text = string.upper(definition and definition.displayName or choice.name)

	local tier = text(button, P.tierTop, 18, Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.rarityColor(rarity))
	tier.Text = string.upper(rarity)

	local blurb = text(button, P.blurbTop, P.blurbHeight, Theme.Fonts.Body, Theme.TextSize.Body, Theme.Color.TextDim)
	blurb.Position = UDim2.fromOffset(P.cardPad, P.blurbTop)
	blurb.Size = UDim2.new(1, -P.cardPad * 2, 0, P.blurbHeight)
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	blurb.LineHeight = 1.1
	blurb.Text = choice.blurb

	local tags = text(
		button, P.cardHeight - P.tagsFromBottom, 18,
		Theme.Fonts.BodyBold, Theme.TextSize.Small - 1, choice.color
	)
	tags.Text = choice.tags

	-- Laid over the card to push it back when another one is picked.
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Theme.Color.Backdrop
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = 5
	dim.Parent = button

	local card = {
		name = choice.name,
		choice = choice,
		button = button,
		stroke = stroke,
		grow = grow,
		glyph = glyph,
		dim = dim,
		hovered = false,
	}

	button.MouseEnter:Connect(function()
		card.hovered = true
		if self.mode == "choices" and not self.pending then
			Sounds.play("ui.hover")
		end
		self:_paintCard(card)
	end)
	button.MouseLeave:Connect(function()
		card.hovered = false
		self:_paintCard(card)
	end)
	button.Activated:Connect(function()
		if self.mode ~= "choices" or self.pending then
			return
		end
		self.pending = card.name
		Sounds.play("ui.click")
		self:_paintAll()
		if self.onChoose then
			task.spawn(self.onChoose, card.name)
		end
	end)

	return card
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

function TutorialChoice:_fit()
	local size = self.screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local byHeight = math.clamp(size.Y / DESIGN_HEIGHT, MIN_SCALE, MAX_SCALE)
	for _, part in ipairs({ self.picker, self.word }) do
		local byWidth = (size.X - 32) / (part.width + MARGIN * 2)
		part.scale.Scale = math.min(byHeight, byWidth)
	end
end

-- One card from its own state: hovered, picked, or pushed back by a pick.
function TutorialChoice:_paintCard(card)
	local picked = self.pending == card.name
	local other = self.pending ~= nil and not picked
	local lifted = picked or (card.hovered and self.mode == "choices" and not self.pending)

	tween(card.button, HOVER, { BackgroundTransparency = if lifted then CARD_HOVER else CARD_REST })
	tween(card.stroke, HOVER, { Transparency = if lifted then STROKE_HOVER else STROKE_REST })
	card.stroke.Thickness = if picked then 2 else 1
	tween(card.grow, HOVER, { Scale = if picked then 1.05 elseif lifted then 1.03 else 1 })
	tween(card.glyph, HOVER, { Position = UDim2.new(0.5, 0, 0, if lifted then P.glyphTop - 5 else P.glyphTop) })
	tween(card.dim, FADE, { BackgroundTransparency = if other then DIMMED else 1 })
end

function TutorialChoice:_paintAll()
	for _, card in ipairs(self.cards) do
		self:_paintCard(card)
	end
end

function TutorialChoice:_paintSubtitle()
	if self.message then
		self.subtitle.Text = self.message
		self.subtitle.TextColor3 = Theme.Color.Bad
	else
		self.subtitle.Text = richKeys(self.subtitleText)
		self.subtitle.TextColor3 = Theme.Color.TextDim
	end
end

-- Fades a part in, rising a little; `after` runs once it has started.
function TutorialChoice:_reveal(part, after: (() -> ())?)
	self.screen.Enabled = true
	if part.shown then
		return
	end
	part.shown = true

	local root = part.root
	root.Visible = true
	root.GroupTransparency = 1
	root.Position = part.position + UDim2.fromOffset(0, RISE)
	tween(root, FADE, { GroupTransparency = 0, Position = part.position })

	if after then
		after()
	end
end

function TutorialChoice:_conceal(part)
	if not part.shown then
		return
	end
	part.shown = false

	local fade = tween(part.root, FADE, { GroupTransparency = 1 })
	fade.Completed:Connect(function()
		if not part.shown then
			part.root.Visible = false
			if not self.picker.shown and not self.word.shown then
				self.screen.Enabled = false
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function TutorialChoice:showChoices(title: string, subtitle: string)
	if self.mode ~= "choices" then
		self.pending = nil
	end
	self.mode = "choices"
	self.chosen = nil
	self.title.Text = title
	self.subtitleText = subtitle
	self:_paintSubtitle()

	AbilityPanel.setHeldBack(true)
	self:_conceal(self.word)
	self:_reveal(self.picker, function()
		-- The cards arrive one after another rather than as a block.
		for index, card in ipairs(self.cards) do
			card.grow.Scale = 0.85
			task.delay(0.06 * index, function()
				tween(card.grow, POP, { Scale = 1 })
			end)
		end
	end)
	self:_paintAll()
end

function TutorialChoice:showChosen(name: string, title: string, subtitle: string)
	self.mode = "chosen"
	self.chosen = name
	self.pending = nil
	self.message = nil

	local choice = nil
	for _, entry in ipairs(self.choices) do
		if entry.name == name then
			choice = entry
		end
	end

	self.wordTitle.Text = title
	self.wordTitle.TextColor3 = if choice then choice.light else Theme.Color.MenuWire
	self.wordSubtitle.Text = richKeys(subtitle)

	-- The loadout comes back, with the new ability already in it.
	AbilityPanel.setHeldBack(false)
	self:_conceal(self.picker)
	self:_reveal(self.word)
end

-- A refusal from the server: shown in place of the subtitle, and the pick is
-- released so another can be tried.
function TutorialChoice:setMessage(message: string?)
	self.message = if type(message) == "string" and message ~= "" then message else nil
	if self.message then
		self.pending = nil
		self:_paintAll()
	end
	self:_paintSubtitle()
end

-- Lets go of a pick the server never answered, so the cards work again.
function TutorialChoice:release()
	if self.pending then
		self.pending = nil
		self:_paintAll()
	end
end

function TutorialChoice:pendingName(): string?
	return self.pending
end

function TutorialChoice:hide()
	if not self.mode then
		return
	end
	self.mode = nil
	self.pending = nil

	AbilityPanel.setHeldBack(false)
	self:_conceal(self.picker)
	self:_conceal(self.word)
end

function TutorialChoice:isShowing(): boolean
	return self.mode ~= nil
end

return TutorialChoice
