--[[
	AbilityPanel

	The middle of the Tab menu, over its wireframe solid (whose colour is the
	aspect's tier - see MenuBackdrop.setRestTint): the QUEST line, the ASPECT
	in use on one card, and the INVENTORY and BESTIARY buttons under it.

		local panel = AbilityPanel.new(someFrame)
		panel.onGuide, panel.onBestiary, panel.onInventory   set by PauseMenu
		panel:setVisible(true)
		panel:destroy()

		AbilityPanel.setAspect(info)    the aspect in use, worded; nil for none
		AbilityPanel.setHeldBack(bool)  step aside (the tutorial's choice)

	Only the aspect. Its abilities are on the HUD by their keys; the aspects
	the player keeps are on their own page (Shared.UI.AspectInventoryWindow),
	which is where one is swapped in.

	IT KNOWS NOTHING ABOUT ABILITIES: StarterPlayerScripts.AbilityClient words
	what the card shows and hands it over.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Sounds = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("Sounds")
)
local AbilityStorage = require(script.Parent:WaitForChild("AbilityStorage"))
local QuestState = require(script.Parent:WaitForChild("QuestState"))
local BestiaryState = require(script.Parent:WaitForChild("BestiaryState"))

local AbilityPanel = {}
AbilityPanel.__index = AbilityPanel

-- The one that exists, and the aspect it shows. Module level so the order in
-- which PauseMenu and AbilityClient start does not decide what is drawn.
local live = nil
local aspectInfo: { [string]: any }? = nil

-- Whether something has asked the panel to step aside; see setHeldBack.
local heldBack = false

-- ---------------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------------

local WIDTH = 340
local EDGE = 3

local GUIDE_HEIGHT = 36
local GAP = 8

--[[
	The aspect card: one row, drawn the way an ability slot used to be - a bar
	in the tier's colour down the left edge, the aspect's picture where the
	keycap was, then its name over its tier. The row is darkest at the picture
	and fades out to the right.
]]
local CARD_HEIGHT = 56
local ACCENT_WIDTH = 3
local BADGE = 36
local BADGE_LEFT = 14
local ICON = 28
local TEXT_LEFT = BADGE_LEFT + BADGE + 14

local PILL_HEIGHT = 34
local PILL_GAP = 12
local PILL_WIDTH = (WIDTH - PILL_GAP) // 2

local CARD_TOP = EDGE + GUIDE_HEIGHT + GAP
local PILLS_TOP = CARD_TOP + CARD_HEIGHT + GAP
local HEIGHT = PILLS_TOP + PILL_HEIGHT + EDGE

local function newText(parent: Instance, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	label.Text = ""
	label.Parent = parent
	return label
end

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function outline(parent: Instance, color: Color3, transparency: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = 1.5
	stroke.Transparency = transparency
	stroke.Parent = parent
	return stroke
end

-- A dark rounded button with an outline that lights up when pointed at.
local function button(parent: Instance, name: string, width: number, height: number, accent: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.Size = UDim2.fromOffset(width, height)
	b.BackgroundColor3 = Theme.Color.Panel
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.Parent = parent
	round(b, 6)
	local stroke = outline(b, accent, 0.45)
	b.MouseEnter:Connect(function()
		stroke.Transparency = 0
		Sounds.play("ui.hover")
	end)
	b.MouseLeave:Connect(function()
		stroke.Transparency = 0.45
	end)
	return b
end

-- ---------------------------------------------------------------------------
-- Instance
-- ---------------------------------------------------------------------------

function AbilityPanel.new(parent: Instance)
	local self = setmetatable({}, AbilityPanel)

	-- A CanvasGroup, so the whole panel fades on one property.
	local root = Instance.new("CanvasGroup")
	root.Name = "AbilityPanel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(WIDTH + EDGE * 2, HEIGHT)
	root.BackgroundTransparency = 1
	root.GroupTransparency = 1
	root.Visible = false
	-- Over MenuBackdrop's art, which tops out at 4 and is a sibling of this.
	root.ZIndex = 6
	root.Parent = parent

	-- THE QUEST LINE: the first quest that can be worked on; opens the guide.
	local guide = button(root, "GuideButton", WIDTH, GUIDE_HEIGHT, Theme.Color.Text)
	guide.Position = UDim2.fromOffset(EDGE, EDGE)
	local guideTag = newText(guide, Theme.Fonts.Heading, Theme.TextSize.Small, Theme.PixelColor.Selection)
	guideTag.Position = UDim2.fromOffset(12, 0)
	guideTag.Size = UDim2.fromOffset(60, GUIDE_HEIGHT)
	guideTag.TextXAlignment = Enum.TextXAlignment.Left
	guideTag.Text = "QUEST"
	local guideText = newText(guide, Theme.Fonts.BodyBold, Theme.TextSize.Body, Theme.Color.Text)
	guideText.Position = UDim2.fromOffset(74, 0)
	guideText.Size = UDim2.new(1, -108, 0, GUIDE_HEIGHT)
	guideText.TextXAlignment = Enum.TextXAlignment.Left
	guideText.TextTruncate = Enum.TextTruncate.AtEnd
	local guideArrow = newText(guide, Theme.Fonts.Heading, Theme.TextSize.Body, Theme.Color.TextDim)
	guideArrow.Position = UDim2.new(1, -28, 0, 0)
	guideArrow.Size = UDim2.fromOffset(20, GUIDE_HEIGHT)
	guideArrow.Text = ">"
	guide.Activated:Connect(function()
		Sounds.play("ui.click")
		if self.onGuide then
			self.onGuide()
		end
	end)

	--[[
		THE ASPECT CARD: one row, like a single ability slot. The tier's colour
		down the left edge, the aspect's picture in the keycap square, its name
		over "LEGENDARY ASPECT", and how many abilities it holds on the right.
	]]
	local card = Instance.new("Frame")
	card.Name = "Aspect"
	card.Position = UDim2.fromOffset(EDGE, CARD_TOP)
	card.Size = UDim2.fromOffset(WIDTH, CARD_HEIGHT)
	card.BackgroundColor3 = Theme.Color.Panel
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel = 0
	card.Parent = root

	-- Darkest behind the picture, gone by the right-hand end.
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = card

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, ACCENT_WIDTH, 1, 0)
	accent.BackgroundColor3 = Theme.Color.TextFaint
	accent.BorderSizePixel = 0
	accent.Parent = card

	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Position = UDim2.fromOffset(BADGE_LEFT, (CARD_HEIGHT - BADGE) // 2)
	badge.Size = UDim2.fromOffset(BADGE, BADGE)
	badge.BackgroundColor3 = Theme.Color.Panel
	badge.BackgroundTransparency = 0.15
	badge.BorderSizePixel = 0
	badge.Parent = card
	round(badge, 4)
	local badgeStroke = outline(badge, Theme.Color.Stroke, 0.3)
	badgeStroke.Thickness = 1

	local icon = AbilityStorage.icon(badge, nil, ICON)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)

	local name = newText(card, Theme.Fonts.Heading, Theme.TextSize.Heading, Theme.Color.Text)
	name.Position = UDim2.fromOffset(TEXT_LEFT, 7)
	name.Size = UDim2.new(1, -TEXT_LEFT - 10, 0, 26)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local tier = newText(card, Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.TextDim)
	tier.Position = UDim2.fromOffset(TEXT_LEFT, 33)
	tier.Size = UDim2.new(1, -TEXT_LEFT - 10, 0, 16)
	tier.TextXAlignment = Enum.TextXAlignment.Left

	-- How many abilities, on the tier's line at the right.
	local count = newText(card, Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.TextDim)
	count.Position = UDim2.fromOffset(0, 33)
	count.Size = UDim2.new(1, -14, 0, 16)
	count.TextXAlignment = Enum.TextXAlignment.Right

	self.aspect = {
		accent = accent, badgeStroke = badgeStroke, icon = icon,
		tier = tier, name = name, count = count,
	}

	-- INVENTORY: the aspects kept but not in use, on their own page.
	local inventory = button(root, "InventoryButton", PILL_WIDTH, PILL_HEIGHT, Theme.PixelColor.Selection)
	inventory.Position = UDim2.fromOffset(EDGE, PILLS_TOP)
	local inventoryLabel = newText(inventory, Theme.Fonts.Heading, Theme.TextSize.Small, Theme.PixelColor.Selection)
	inventoryLabel.Position = UDim2.fromOffset(12, 0)
	inventoryLabel.Size = UDim2.new(1, -24, 1, 0)
	inventoryLabel.TextXAlignment = Enum.TextXAlignment.Left
	inventoryLabel.Text = "INVENTORY"
	local inventoryCount = newText(inventory, Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.TextDim)
	inventoryCount.Size = UDim2.new(1, -12, 1, 0)
	inventoryCount.TextXAlignment = Enum.TextXAlignment.Right
	inventory.Activated:Connect(function()
		Sounds.play("ui.click")
		if self.onInventory then
			self.onInventory()
		end
	end)

	local bestiary = button(root, "BestiaryButton", PILL_WIDTH, PILL_HEIGHT, Theme.Color.Text)
	bestiary.Position = UDim2.fromOffset(EDGE + WIDTH - PILL_WIDTH, PILLS_TOP)
	local bestiaryLabel = newText(bestiary, Theme.Fonts.Heading, Theme.TextSize.Small, Theme.Color.Text)
	bestiaryLabel.Position = UDim2.fromOffset(12, 0)
	bestiaryLabel.Size = UDim2.new(1, -24, 1, 0)
	bestiaryLabel.TextXAlignment = Enum.TextXAlignment.Left
	bestiaryLabel.Text = "BESTIARY"
	local bestiaryCount = newText(bestiary, Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.TextDim)
	bestiaryCount.Size = UDim2.new(1, -12, 1, 0)
	bestiaryCount.TextXAlignment = Enum.TextXAlignment.Right
	bestiary.Activated:Connect(function()
		Sounds.play("ui.click")
		if self.onBestiary then
			self.onBestiary()
		end
	end)

	local function refreshNav()
		local quest = QuestState.focus()
		guideText.Text = if quest then quest.title else "Every quest complete"
		local met, all = BestiaryState.counts()
		bestiaryCount.Text = string.format("%d/%d", met, all)
		local stored = #(AbilityStorage.state().slots or {})
		inventoryCount.Text = if stored > 0 then tostring(stored) else ""
	end
	QuestState.Changed:Connect(refreshNav)
	BestiaryState.Changed:Connect(refreshNav)
	AbilityStorage.Changed:Connect(refreshNav)
	refreshNav()

	self.root = root
	self.guide = guide
	self.inventory = inventory
	self.bestiary = bestiary
	self.visible = false
	self.wanted = false
	self.fade = nil

	live = self
	self:_refreshAspect()
	return self
end

-- Draws the aspect in use, or says there is none and how to get one.
function AbilityPanel:_refreshAspect()
	local view = self.aspect
	local info = aspectInfo
	local color = if info then Theme.rarityColor(info.rarity) else Theme.Color.TextFaint

	view.accent.BackgroundColor3 = color
	view.accent.BackgroundTransparency = if info then 0 else 0.6
	view.badgeStroke.Color = if info then color else Theme.Color.Stroke
	AbilityStorage.setIcon(view.icon, info and info.name)

	if info then
		view.name.Text = info.displayName or info.name
		view.name.TextColor3 = Theme.Color.Text
		view.tier.Text = string.upper(info.rarity or "") .. " ASPECT"
		view.tier.TextColor3 = color
		-- A permanent aspect (bought in the shop) says so in gold; any other
		-- says how many abilities it holds.
		local abilities = info.abilityCount or 0
		view.count.Text = if info.permanent
			then "PERMANENT"
			else string.format("%d %s", abilities, if abilities == 1 then "ability" else "abilities")
		view.count.TextColor3 = if info.permanent then Theme.PixelColor.Selection else Theme.Color.TextDim
	else
		view.name.Text = "No aspect"
		view.name.TextColor3 = Theme.Color.TextFaint
		view.tier.Text = "WISH, OR FIND A SCROLL"
		view.tier.TextColor3 = Theme.Color.TextFaint
		view.count.Text = ""
	end
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------

-- What the menu asked for. Shown only if nothing is holding the panel back.
function AbilityPanel:setVisible(visible: boolean)
	self.wanted = visible == true
	self:_show(self.wanted and not heldBack)
end

function AbilityPanel:_show(visible: boolean)
	visible = visible == true
	if visible == self.visible then
		return
	end
	self.visible = visible

	if self.fade then
		self.fade:Cancel()
		self.fade = nil
	end

	if visible then
		self.root.Visible = true
	end
	local fade = TweenService:Create(
		self.root,
		if visible then Theme.Tween.Fade else Theme.Tween.Close,
		{ GroupTransparency = if visible then 0 else 1 }
	)
	self.fade = fade
	-- A CanvasGroup at full transparency still takes clicks; only Visible stops
	-- that, and it cannot be set until the fade has finished.
	fade.Completed:Connect(function(state)
		if not self.visible and state == Enum.PlaybackState.Completed then
			self.root.Visible = false
		end
	end)
	fade:Play()
end

function AbilityPanel:destroy()
	self.root:Destroy()
	if live == self then
		live = nil
	end
end

-- ---------------------------------------------------------------------------
-- The way in from outside
-- ---------------------------------------------------------------------------

--[[
	The aspect in use:

	  name         the AspectConfig name (picks the picture)
	  displayName  "Ember"
	  rarity        its tier name, which colours the card
	  abilityCount  how many abilities it holds
	  permanent     bought in the shop (shown in gold instead of the count)

	nil for no aspect. Kept until there is a panel to show it.
]]
function AbilityPanel.setAspect(info: { [string]: any }?)
	aspectInfo = info
	if live then
		live:_refreshAspect()
	end
end

--[[
	Steps the panel out of the way while something else needs the middle of
	the Tab menu - today, the tutorial's ability choice (Shared.UI.
	TutorialChoice) - and back when it is done.
]]
function AbilityPanel.setHeldBack(held: boolean)
	heldBack = held == true
	if live then
		live:_show(live.wanted and not heldBack)
	end
end

return AbilityPanel
