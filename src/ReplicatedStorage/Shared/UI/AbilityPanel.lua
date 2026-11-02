--[[
	AbilityPanel

	The loadout, listed over the Tab menu's wireframe solid, and draggable: a
	card per slot, dragged up or down to change which key casts what, right onto
	the bin to throw it away, or left into the storage column beside it
	(Shared.UI.AbilityStorage) to keep it. Stored cards drag back the other way.

		local panel = AbilityPanel.new(someFrame)
		panel:setVisible(true)
		panel:destroy()

		AbilityPanel.setSlots(entries)                    -- what to list
		AbilityPanel.setHandlers({ reorder = , drop = })  -- where a drop goes

	THE LAYOUT IS THE REFERENCE'S

	A small line in capitals naming the slot and its key, the ability's name
	under it, and its tier under that, in the tier's own colour. No box until
	you point at one - the art behind it is a handful of pale hairlines, and a
	panel drawn over that stops being a readout and starts being a window.

	Shared.UI.MenuBackdrop used to draw this list itself, for a few seconds,
	when an ability was equipped. Now that the list is permanent it does the
	REACTION instead - it throws the solid outward in the new ability's colour -
	and the two halves no longer print the same three names in the same place.

	IT KNOWS NOTHING ABOUT ABILITIES

	Entries arrive already worded: { label, name, rarity, gained }, with name
	nil for an empty slot. So this file never reads AbilityConfig, never names
	an ability and never touches a remote - it draws what it is handed and
	reports which slot was dragged onto which. StarterPlayerScripts.AbilityClient
	owns all three of those and wires them together.

	DRAGGING IS OPTIMISTIC, AND THE SERVER IS STILL THE AUTHORITY

	A dropped card stays where it was dropped rather than snapping home to wait
	for a round trip. That is a guess, and it is corrected: AbilityLoadout
	answers EVERY reorder request with a push of the real order, including one
	it refused, so a wrong guess is overwritten a moment later rather than left
	on screen. The alternative - snap back, then jump forward 80ms later - looks
	broken every single time, including when it worked.

	Only the filled slots take part. The loadout is a dense array on the server
	(see AbilityLoadout), so there is no such thing as an ability on V with
	nothing on X, and a drop below the last filled card lands on that card
	rather than opening a hole the server would refuse to keep.

	THE BIN IS THE OTHER HALF OF THE THREE-SLOT LIMIT

	With every slot full, a scroll cannot be read: AbilityLoadout.add refuses
	and says so. The bin is what a player does about that, and it is why it is
	here rather than being another chat command - the moment you find out you
	are full is the moment a scroll is in your hand, and the fix should not be
	a thing you have to know the name of.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Confirm = require(script.Parent:WaitForChild("Confirm"))
local Sounds = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("Sounds")
)

local StorageUI = require(script.Parent.AbilityStorage)
local QuestState = require(script.Parent:WaitForChild("QuestState"))
local BestiaryState = require(script.Parent:WaitForChild("BestiaryState"))
local StorageAbilityConfig = require(ReplicatedStorage.Shared.Abilities.AbilityConfig)
local AbilityConfigSlotCount = StorageAbilityConfig.SlotCount
local AbilityPanel = {}
AbilityPanel.__index = AbilityPanel

--[[
	The one that exists, what it is showing, and who to tell about a drag.

	Module level for the same reason MenuBackdrop's is: PauseMenu owns the
	instance and AbilityClient owns the data, and neither has any business
	holding a reference to the other. Keeping the slot list here as well is what
	makes the order of those two not matter - a push that arrives before the
	panel is built is applied when it is built, rather than dropped.
]]
local live = nil
local slots: { any } = {}

--[[
	What to do when a card is dropped somewhere: { reorder, drop }.

	One table rather than a setter each, because they are set together, by the
	same script, at the same moment - and a second setter is a second thing to
	forget.
]]
local handlers: { [string]: ((...any) -> ())? } = {}

-- Whether something has asked the list to step aside; see setHeldBack.
local heldBack = false

-- ---------------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------------

-- Pixels. Fixed rather than proportional, like every other panel in the game:
-- text that scales with the window is text that is the wrong size twice.
local CARD_WIDTH = 340
local CARD_HEIGHT = 56
local CARD_GAP = 8
local PITCH = CARD_HEIGHT + CARD_GAP

-- Row offsets inside a card: the name over its tier. (The capitals line is
-- kept for the code that writes it, but no longer shown: the keycap says it.)
local LABEL_Y, LABEL_HEIGHT = 3, 15
local NAME_Y, NAME_HEIGHT = 7, 26
local RARITY_Y, RARITY_HEIGHT = 33, 16

-- A card is a row: a thin bar in the tier's colour down its left edge, the
-- slot's keycap, then the name. The row is darkest at the keycap and fades
-- out to the right, so the three read as a list rather than as three boxes.
local ACCENT_WIDTH = 3
local BADGE_SIZE = 36
local BADGE_LEFT = 14
local BADGE_INSET = (CARD_HEIGHT - BADGE_SIZE) // 2
local TEXT_LEFT = BADGE_LEFT + BADGE_SIZE + 14

-- Each column sits in its own framed panel, this far in from the frame.
local PANEL_PAD = 14

-- Room round the frames inside the root: a CanvasGroup cuts at its edge, and
-- a frame's stroke is drawn just outside it.
local EDGE = 3

local HINT_GAP = 10
local HINT_HEIGHT = 16

--[[
	THE BIN, drawn a pixel at a time.

	Each '#' is one square Frame BIN_PIXEL across, so the thing is a sprite
	without being an image: no asset to upload, no id to go stale, and it is
	crisp at any size because it is made of rectangles rather than resampled
	from one. The two walls and the two slots in the body are what make it read
	as a bin rather than as a bucket at this size.

	Change the picture by editing the picture. Width and height are measured off
	it, so a wider or taller drawing needs nothing else changed.
]]
local BIN_SPRITE = {
	"....###....",
	".#########.",
	".#########.",
	"...........",
	"..#######..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#######..",
}

local BIN_PIXEL = 6
local BIN_GAP = 30
local BIN_WIDTH = #BIN_SPRITE[1] * BIN_PIXEL
local BIN_HEIGHT = #BIN_SPRITE * BIN_PIXEL

--[[
	The LOADOUT is the panel, in the middle, with the bin on its right.
	Storage (Shared.UI.AbilityStorage) is a drawer that opens to the loadout's
	left from the gold tab under it, shut unless the player opens it. Both
	columns put their cards on the same rows, under the room storage needs for
	its heading, so a card carried across lands level with where it left.

	The root is as wide on the right of the loadout as on its left, so the
	loadout is in the middle of the screen with the drawer open or shut. That
	makes the left-to-right positions depend on the drawer: layoutFor sets them.
]]
local BIN_SIDE = BIN_WIDTH + BIN_GAP
local TAB_GAP_X = 12
local PILL_LENGTH = (CARD_WIDTH - TAB_GAP_X) // 2
local TAB_LENGTH = PILL_LENGTH
local TAB_HEIGHT = 30
local TAB_GAP = 12
local COLUMN_GAP = 40
local HEADER_HEIGHT = 22
local HEADER_TOP = EDGE + PANEL_PAD
local LIST_TOP = HEADER_TOP + HEADER_HEIGHT + 8
-- The NEXT line fills the room over the cards that storage keeps for its heading.
local GUIDE_HEIGHT = LIST_TOP - EDGE - 8

local OPEN_SIDE = EDGE + PANEL_PAD * 2 + CARD_WIDTH + COLUMN_GAP
local SHUT_SIDE = BIN_SIDE

local STORE_X, CARDS_X, BIN_X, ROOT_WIDTH, STORE_REACH = 0, 0, 0, 0, 0

local function layoutFor(open: boolean)
	local side = if open then OPEN_SIDE else SHUT_SIDE
	CARDS_X = side
	STORE_X = side - OPEN_SIDE + EDGE + PANEL_PAD
	BIN_X = CARDS_X + CARD_WIDTH + BIN_GAP
	ROOT_WIDTH = side * 2 + CARD_WIDTH
	-- How far left a loadout card is carried before storage takes it: half way.
	STORE_REACH = (CARDS_X - STORE_X) * 0.5
end

-- Shut until opened, and remembered for as long as the client runs.
local storageOpen = false
layoutFor(storageOpen)

-- Where loadout card `index` rests, `dx` to the side of its column.
local function slotPosition(index: number, dx: number?): UDim2
	return UDim2.fromOffset(CARDS_X + (dx or 0), LIST_TOP + (index - 1) * PITCH)
end

--[[
	How far right a card has to be dragged before the bin takes it: half the
	distance to it.

	Measured as a DISTANCE DRAGGED rather than by testing the cursor against the
	bin's rectangle on screen, because a delta needs no agreement about which of
	Roblox's coordinate spaces anything is in - the same reason pointerAt works
	the way it does. The card slides visibly toward the bin the whole time, so
	there is nothing hidden about where the threshold is.
]]
local BIN_REACH = BIN_SIDE * 0.5

local BIN_IDLE_TRANSPARENCY = 0.55
local BIN_ARMED_TRANSPARENCY = 0

--[[
	The card's own box: always there, so the three slots read as three slots,
	and brighter when pointed at.

	LIFTED is the one being dragged. It is the most opaque of the three on
	purpose: while it is in the air it has to read as a thing that came off the
	stack rather than as another row of it.
]]
local CARD_REST = 0.3
local CARD_HOVER = 0.05
local CARD_LIFTED = 0

local STROKE_REST = 1
local STROKE_HOVER = 0.5
local STROKE_LIFTED = 0.2

-- How far the pointer travels before a press stops being a click and becomes a
-- drag. Without it every click nudges the stack by a pixel and back.
local DRAG_THRESHOLD = 4

-- How long a newly equipped ability stays picked out in its card.
local GAIN_HOLD = 4

local EMPTY_TEXT = "Empty"
local DRAG_HINT = "drag to reorder, left into storage to keep, or to the bin to drop"
local DRAG_HINT_ONE = "drag left into storage to keep, or to the bin to drop"
local SHUT_HINT = "drag to reorder, or to the bin to drop"
local SHUT_HINT_ONE = "drag to the bin to drop"

local function hintFor(filled: number): string
	if storageOpen then
		return if filled > 1 then DRAG_HINT else DRAG_HINT_ONE
	end
	return if filled > 1 then SHUT_HINT else SHUT_HINT_ONE
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

local function newText(
	parent: Instance,
	y: number,
	height: number,
	size: number,
	font: Font,
	color: Color3
): TextLabel
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	label.Text = ""
	label.Parent = parent
	return label
end

--[[
	Where the pointer is.

	Only ever used as a DIFFERENCE from where the drag started, so which of
	Roblox's several screen spaces this is measured in does not matter - only
	that the same one is used for the whole of one drag. That is also why the
	GUI inset never has to be corrected for here, which is the usual way a drag
	ends up sitting a topbar's height away from the cursor, and why the bin
	tests how far a card has been dragged rather than where the cursor is.
]]
local function pointerAt(input: InputObject): (number?, number?)
	local kind = input.UserInputType

	if kind == Enum.UserInputType.Touch then
		return input.Position.X, input.Position.Y
	end

	if
		kind == Enum.UserInputType.MouseMovement
		or kind == Enum.UserInputType.MouseButton1
	then
		local location = UserInputService:GetMouseLocation()
		return location.X, location.Y
	end

	return nil, nil
end

--[[
	The pointer in the panel's own pixels. The panel may be drawn smaller than
	designed - PauseMenu shrinks it with a UIScale named FitScale to fit a phone - and a drag
	moves cards by the distance the pointer travelled, so that distance is
	divided by the scale or the card would run ahead of the finger.
]]
function AbilityPanel:_pointerAt(input: InputObject): (number?, number?)
	local x, y = pointerAt(input)
	local scale = self.root and self.root:FindFirstChild("FitScale")
	if x and y and scale and scale.Scale > 0 then
		return x / scale.Scale, y / scale.Scale
	end
	return x, y
end

--[[
	Builds one of the drag targets out of its sprite, one Frame per '#'.

	Returns the container and the pixels, because the pixels are what get
	recoloured when a card is dragged over it - the container is only there to
	move and size them as one.

	Both the bin and the storage box come through here, which is the point: they
	are the same control in two flavours, so they are drawn by the same code at
	the same pixel size off two equally-sized grids. Give one of them its own
	builder and they drift apart on the first edit to either.

	A TextButton rather than a Frame so the box can also be CLICKED, which is
	how the storage panel opens. The bin has nothing to open, and a button
	nobody connects is inert.
]]
local function buildSprite(
	parent: Instance,
	sprite: { string },
	name: string,
	top: number
): (TextButton, { Frame })
	local field = Instance.new("TextButton")
	field.Name = name
	field.Text = ""
	field.AutoButtonColor = false
	field.Position = UDim2.fromOffset(BIN_X, top)
	field.Size = UDim2.fromOffset(#sprite[1] * BIN_PIXEL, #sprite * BIN_PIXEL)
	field.BackgroundTransparency = 1
	field.Parent = parent

	local pixels = {}

	for row, line in ipairs(sprite) do
		for column = 1, #line do
			if string.sub(line, column, column) == "#" then
				local pixel = Instance.new("Frame")
				pixel.Position = UDim2.fromOffset((column - 1) * BIN_PIXEL, (row - 1) * BIN_PIXEL)
				pixel.Size = UDim2.fromOffset(BIN_PIXEL, BIN_PIXEL)
				pixel.BackgroundColor3 = Theme.Color.TextDim
				pixel.BackgroundTransparency = BIN_IDLE_TRANSPARENCY
				pixel.BorderSizePixel = 0
				pixel.Parent = field
				table.insert(pixels, pixel)
			end
		end
	end

	return field, pixels
end

-- Lights one of them up while a card is over it. Armed is the accent colour at
-- full opacity, idle is dim and half faded - the same two states for both, so
-- "this is where it would land" reads the same wherever the card is going.
local function setSpriteArmed(pixels: { Frame }, armed: boolean, accent: Color3)
	local color = if armed then accent else Theme.Color.TextDim
	local transparency = if armed then BIN_ARMED_TRANSPARENCY else BIN_IDLE_TRANSPARENCY

	for _, pixel in ipairs(pixels) do
		pixel.BackgroundColor3 = color
		pixel.BackgroundTransparency = transparency
	end
end

local function isPressInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

--[[
	One card: the box, the capitals line, the name and the tier. Shared with the
	storage column (Shared.UI.AbilityStorage) and with the ghost a stored card
	is carried as, so all three are the same card and cannot drift apart.
]]
local function newCard(parent: Instance)
	local button = Instance.new("TextButton")
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	button.BackgroundColor3 = Theme.Color.Panel
	button.BackgroundTransparency = CARD_REST
	button.BorderSizePixel = 0
	button.Parent = parent

	-- Darkest behind the keycap, gone by the right-hand end. Also fades the
	-- outline a hover draws, so a raised row has no hard right edge either.
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = button

	-- The tier's colour down the left edge.
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, ACCENT_WIDTH, 1, 0)
	accent.BackgroundColor3 = Theme.Color.TextFaint
	accent.BorderSizePixel = 0
	accent.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Color.Stroke
	stroke.Thickness = 1.5
	stroke.Transparency = STROKE_REST
	stroke.Parent = button

	-- The slot's keycap: the key that casts it, or its number where there is
	-- no key to name.
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Position = UDim2.fromOffset(BADGE_LEFT, BADGE_INSET)
	badge.Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE)
	badge.BackgroundColor3 = Theme.Color.Panel
	badge.BackgroundTransparency = 0.15
	badge.BorderSizePixel = 0
	badge.FontFace = Theme.Fonts.Heading
	badge.TextSize = Theme.TextSize.Heading
	badge.TextColor3 = Theme.Color.Text
	badge.TextStrokeTransparency = 1
	badge.Text = ""
	badge.Parent = button

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 4)
	badgeCorner.Parent = badge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badgeStroke.Color = Theme.Color.Stroke
	badgeStroke.Thickness = 1
	badgeStroke.Transparency = 0.3
	badgeStroke.Parent = badge

	local card = {
		button = button,
		stroke = stroke,
		badge = badge,
		badgeStroke = badgeStroke,
		accent = accent,
		label = newText(
			button, LABEL_Y, LABEL_HEIGHT,
			Theme.TextSize.Small, Theme.Fonts.BodyBold, Theme.Color.TextDim
		),
		name = newText(
			button, NAME_Y, NAME_HEIGHT,
			Theme.TextSize.Heading, Theme.Fonts.Heading, Theme.Color.Text
		),
		rarity = newText(
			button, RARITY_Y, RARITY_HEIGHT,
			Theme.TextSize.Small, Theme.Fonts.BodyBold, Theme.Color.TextDim
		),
	}

	card.label.Visible = false

	-- Cooldown and mana, on the tier's line at the right.
	card.stats = newText(button, RARITY_Y, RARITY_HEIGHT, Theme.TextSize.Small, Theme.Fonts.BodyBold, Theme.Color.TextDim)
	card.stats.Name = "Stats"
	card.stats.Size = UDim2.new(1, -14, 0, RARITY_HEIGHT)
	card.stats.TextXAlignment = Enum.TextXAlignment.Right

	-- Beside the badge rather than centred across the whole card.
	for _, text in ipairs({ card.label, card.name, card.rarity }) do
		text.Position = UDim2.fromOffset(TEXT_LEFT, text.Position.Y.Offset)
		text.Size = UDim2.new(1, -TEXT_LEFT - 10, 0, text.Size.Y.Offset)
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
	end

	return card
end

-- ---------------------------------------------------------------------------
-- Instance
-- ---------------------------------------------------------------------------

function AbilityPanel.new(parent: Instance)
	local self = setmetatable({}, AbilityPanel)

	--[[
		A CanvasGroup, so the whole panel fades on ONE property.

		The alternative is tweening a background, a stroke and three labels per
		card and hoping none of them is mid-hover when the menu closes. Here the
		fade and the hover write different properties and cannot fight.
	]]
	local root = Instance.new("CanvasGroup")
	root.Name = "AbilityPanel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(ROOT_WIDTH, PITCH)
	root.BackgroundTransparency = 1
	root.GroupTransparency = 1
	root.Visible = false

	-- Over MenuBackdrop's art, which tops out at 4 and is a sibling of this.
	root.ZIndex = 6
	root.Parent = parent

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, 0)
	hint.Size = UDim2.new(1, 0, 0, HINT_HEIGHT)
	hint.BackgroundTransparency = 1
	hint.FontFace = Theme.Fonts.Body
	hint.TextSize = Theme.TextSize.Small
	hint.TextColor3 = Theme.Color.TextFaint
	hint.TextStrokeTransparency = 1
	hint.Text = DRAG_HINT
	hint.Visible = false
	hint.Parent = root

	local bin, binPixels = buildSprite(root, BIN_SPRITE, "Bin", 0)

	-- The storage drawer's handle: a gold tab under the loadout, with the way
	-- the drawer opens on its left, STORAGE in the middle and the count on its
	-- right.
	local tab = Instance.new("TextButton")
	tab.Name = "StorageTab"
	tab.Text = ""
	tab.AutoButtonColor = false
	tab.Size = UDim2.fromOffset(TAB_LENGTH, TAB_HEIGHT)
	tab.BackgroundColor3 = Theme.Color.Panel
	tab.BackgroundTransparency = 0.1
	tab.BorderSizePixel = 0
	tab.Parent = root

	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(0, 6)
	tabCorner.Parent = tab

	local tabStroke = Instance.new("UIStroke")
	tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tabStroke.Color = Theme.PixelColor.Selection
	tabStroke.Thickness = 1.5
	tabStroke.Transparency = 0.35
	tabStroke.Parent = tab

	local tabArrow = newText(tab, 0, TAB_HEIGHT, Theme.TextSize.Body, Theme.Fonts.Heading, Theme.PixelColor.Selection)
	tabArrow.Name = "Arrow"
	tabArrow.Position = UDim2.fromOffset(8, 0)
	tabArrow.Size = UDim2.fromOffset(20, TAB_HEIGHT)

	local tabLabel = newText(tab, 0, TAB_HEIGHT, Theme.TextSize.Small, Theme.Fonts.Heading, Theme.PixelColor.Selection)
	tabLabel.Name = "Label"
	tabLabel.Text = "STORAGE"

	local tabCount = newText(tab, 0, TAB_HEIGHT, Theme.TextSize.Small, Theme.Fonts.BodyBold, Theme.Color.TextDim)
	tabCount.Name = "Count"
	tabCount.Position = UDim2.fromOffset(0, 0)
	tabCount.Size = UDim2.new(1, -10, 0, TAB_HEIGHT)
	tabCount.TextXAlignment = Enum.TextXAlignment.Right

	tab.MouseEnter:Connect(function()
		tabStroke.Transparency = 0
		Sounds.play("ui.hover")
	end)
	tab.MouseLeave:Connect(function()
		tabStroke.Transparency = 0.35
	end)
	tab.Activated:Connect(function()
		Sounds.play("ui.click")
		self:_setStorageOpen(not storageOpen)
	end)

	self.tab = tab
	self.tabArrow = tabArrow
	self.tabCount = tabCount

	--[[
		The two other pages of the menu, opened through callbacks PauseMenu
		sets (onGuide, onBestiary): the QUEST line over the cards, naming the
		first quest that can be worked on, and the BESTIARY pill beside storage.
	]]
	local function navButton(name: string, width: number, height: number, accent: Color3)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Text = ""
		button.AutoButtonColor = false
		button.Size = UDim2.fromOffset(width, height)
		button.BackgroundColor3 = Theme.Color.Panel
		button.BackgroundTransparency = 0.1
		button.BorderSizePixel = 0
		button.Parent = root

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 6)
		buttonCorner.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = accent
		stroke.Thickness = 1.5
		stroke.Transparency = 0.5
		stroke.Parent = button

		button.MouseEnter:Connect(function()
			stroke.Transparency = 0
			Sounds.play("ui.hover")
		end)
		button.MouseLeave:Connect(function()
			stroke.Transparency = 0.5
		end)
		return button
	end

	local guide = navButton("GuideButton", CARD_WIDTH, GUIDE_HEIGHT, Theme.Color.Text)
	local guideTag = newText(guide, 0, GUIDE_HEIGHT, Theme.TextSize.Small, Theme.Fonts.Heading, Theme.PixelColor.Selection)
	guideTag.Position = UDim2.fromOffset(12, 0)
	guideTag.Size = UDim2.fromOffset(60, GUIDE_HEIGHT)
	guideTag.TextXAlignment = Enum.TextXAlignment.Left
	guideTag.Text = "QUEST"
	local guideText = newText(guide, 0, GUIDE_HEIGHT, Theme.TextSize.Body, Theme.Fonts.BodyBold, Theme.Color.Text)
	guideText.Position = UDim2.fromOffset(74, 0)
	guideText.Size = UDim2.new(1, -108, 0, GUIDE_HEIGHT)
	guideText.TextXAlignment = Enum.TextXAlignment.Left
	guideText.TextTruncate = Enum.TextTruncate.AtEnd
	local guideArrow = newText(guide, 0, GUIDE_HEIGHT, Theme.TextSize.Body, Theme.Fonts.Heading, Theme.Color.TextDim)
	guideArrow.Position = UDim2.new(1, -28, 0, 0)
	guideArrow.Size = UDim2.fromOffset(20, GUIDE_HEIGHT)
	guideArrow.Text = ">"
	guide.Activated:Connect(function()
		Sounds.play("ui.click")
		if self.onGuide then
			self.onGuide()
		end
	end)

	local bestiary = navButton("BestiaryButton", PILL_LENGTH, TAB_HEIGHT, Theme.Color.Text)
	local bestiaryLabel = newText(bestiary, 0, TAB_HEIGHT, Theme.TextSize.Small, Theme.Fonts.Heading, Theme.Color.Text)
	bestiaryLabel.Position = UDim2.fromOffset(12, 0)
	bestiaryLabel.Size = UDim2.new(1, -24, 0, TAB_HEIGHT)
	bestiaryLabel.TextXAlignment = Enum.TextXAlignment.Left
	bestiaryLabel.Text = "BESTIARY"
	local bestiaryCount = newText(bestiary, 0, TAB_HEIGHT, Theme.TextSize.Small, Theme.Fonts.BodyBold, Theme.Color.TextDim)
	bestiaryCount.Size = UDim2.new(1, -12, 0, TAB_HEIGHT)
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
	end
	QuestState.Changed:Connect(refreshNav)
	BestiaryState.Changed:Connect(refreshNav)
	refreshNav()

	self.guide = guide
	self.bestiary = bestiary

	self.root = root
	self.hint = hint
	self.bin = bin
	self.binPixels = binPixels

	-- The storage column, from the same cards. A press on a stored ability
	-- starts a drag here, since a card can be carried into the loadout.
	self.storage = StorageUI.create(root, {
		x = STORE_X,
		listTop = LIST_TOP,
		headerTop = HEADER_TOP,
		pad = PANEL_PAD,
		width = CARD_WIDTH,
		pitch = PITCH,
		cardHeight = CARD_HEIGHT,
		cardGap = CARD_GAP,
		visibleRows = AbilityConfigSlotCount,
		newCard = newCard,
		onPress = function(index, input)
			self:_beginStoredDrag(index, self:_pointerAt(input))
		end,
		onRefresh = function(state)
			self:_refreshTab(state)
		end,
	})
	self.cards = {}
	self.filled = 0
	self.visible = false
	self.wanted = false
	self.fade = nil
	self.drag = nil

	live = self

	-- Whatever was pushed before this existed is what it opens showing.
	self:_rebuild()

	return self
end

function AbilityPanel:_buildCard(index: number)
	local card = newCard(self.root)
	local button = card.button
	button.Name = "Slot" .. index
	button.Position = slotPosition(index)

	card.slot = index
	card.filled = false
	card.hovered = false
	card.gained = false
	-- Picked out as where a stored card would land, during a drag from storage.
	card.armed = false
	card.rarityColor = nil
	card.gainToken = 0
	-- The tween carrying this card into the slot it was dropped on, while one
	-- is running (card.settle). See _rebuild for why it is worth holding on to.

	button.MouseEnter:Connect(function()
		card.hovered = true
		self:_refreshCard(card)

		-- Silent on an empty slot and mid-drag: the first is not a thing you
		-- can pick up, and the second already has the cursor making noise.
		if card.filled and not self.drag then
			Sounds.play("ui.hover")
		end
	end)

	button.MouseLeave:Connect(function()
		card.hovered = false
		self:_refreshCard(card)
	end)

	button.InputBegan:Connect(function(input)
		if isPressInput(input) then
			self:_beginDrag(card, self:_pointerAt(input))
		end
	end)

	return card
end

--[[
	Colours a card from its own state.

	One function rather than a write at each of the places state changes: hover,
	drag and "just equipped" all want a say in the same two transparencies, and
	three handlers each writing what they think the answer is, is how a card
	ends up stuck looking hovered.
]]
function AbilityPanel:_refreshCard(card)
	local lifted = self.drag ~= nil and self.drag.card == card
	local raised = lifted or card.armed or (card.filled and (card.hovered or card.gained))

	if lifted then
		card.button.BackgroundTransparency = CARD_LIFTED
		card.stroke.Transparency = STROKE_LIFTED
	elseif raised then
		card.button.BackgroundTransparency = CARD_HOVER
		card.stroke.Transparency = STROKE_HOVER
	else
		card.button.BackgroundTransparency = CARD_REST
		card.stroke.Transparency = STROKE_REST
	end

	if card.armed then
		card.stroke.Color = Theme.Color.Good
	elseif card.gained and card.rarityColor then
		card.stroke.Color = card.rarityColor
	elseif lifted then
		card.stroke.Color = Theme.Color.Accent
	else
		card.stroke.Color = Theme.Color.Stroke
	end

	card.label.TextColor3 = if card.gained then Theme.Color.Good else Theme.Color.TextDim
	card.badge.TextColor3 = if card.filled then Theme.Color.Text else Theme.Color.TextFaint
	card.badgeStroke.Color = card.stroke.Color
end

--[[
	Redraws the whole list from whatever was last pushed.

	The cards themselves are kept and refilled rather than destroyed and rebuilt.
	The list is SlotCount long and only changes length if SlotKeys does, so a
	rebuild is a fill - which also means a hover survives one, instead of the
	card under the cursor going flat every time the server pushes.
]]
function AbilityPanel:_rebuild()
	self:_cancelDrag()

	local count = #slots

	for index = #self.cards + 1, count do
		self.cards[index] = self:_buildCard(index)
	end

	for index = #self.cards, count + 1, -1 do
		self.cards[index].button:Destroy()
		self.cards[index] = nil
	end

	local filled = 0

	for index, entry in ipairs(slots) do
		local card = self.cards[index]
		local abilityName = if type(entry.name) == "string" then entry.name else ""
		local has = abilityName ~= ""

		if has then
			filled += 1
		end

		card.slot = index
		card.filled = has
		card.gained = has and entry.gained == true
		card.rarityColor = if entry.rarity then Theme.rarityColor(entry.rarity) else nil

		card.label.Text = string.upper(tostring(entry.label or ""))
		card.badge.Text = if type(entry.key) == "string" and entry.key ~= "" then entry.key else tostring(index)
		card.accent.BackgroundColor3 = if has then card.rarityColor or Theme.Color.Text else Theme.Color.TextFaint
		card.accent.BackgroundTransparency = if has then 0 else 0.6

		card.stats.Text = if has and type(entry.stats) == "string" then entry.stats else ""

		if has then
			card.name.Text = abilityName
			card.name.TextColor3 = Theme.Color.Text
			card.rarity.Text = if entry.rarity then string.upper(entry.rarity) else ""
			card.rarity.TextColor3 = card.rarityColor or Theme.Color.TextDim
		else
			card.name.Text = EMPTY_TEXT
			card.name.TextColor3 = Theme.Color.TextFaint
			card.rarity.Text = ""
		end

		--[[
			Cancelled before the position is written, not after.

			A card dropped a moment ago is still tweening into the slot the
			CLIENT guessed at. This is the server's answer arriving, and a tween
			left running would finish after it and quietly put the card back on
			the guess.
		]]
		if card.settle then
			card.settle:Cancel()
			card.settle = nil
		end

		card.button.Position = slotPosition(index)
		card.button.ZIndex = 1

		-- Bumped per fill, so an earlier card's hold cannot clear the pick-out
		-- on a later ability that has only just landed in the same card.
		card.gainToken += 1

		if card.gained then
			local token = card.gainToken
			task.delay(GAIN_HOLD, function()
				if card.gainToken == token and card.gained then
					card.gained = false
					self:_refreshCard(card)
				end
			end)
		end

		self:_refreshCard(card)
	end

	self.filled = filled

	-- Worth saying as soon as there is anything to drag, but only worth
	-- mentioning REORDERING once there are two things to put in an order.
	self.hint.Visible = filled > 0
	self.hint.Text = hintFor(filled)

	local stack = math.max(PITCH, count * PITCH - CARD_GAP)

	--[[
		The bin, centred against the stack. Never above the top of the list: a
		CanvasGroup does not overflow, it cuts, and the panel rebuilds itself
		once in the constructor with no slots at all.
	]]
	local binTop = LIST_TOP + math.max(0, math.floor((stack - BIN_HEIGHT) * 0.5))
	self.bin.Position = UDim2.fromOffset(BIN_X, binTop)

	-- Nothing to throw away with an empty loadout, and a bin with nothing that
	-- can reach it is a control that does not work.
	self.bin.Visible = filled > 0

	-- Everything left-to-right moves with the drawer; see layoutFor.
	local tabTop = LIST_TOP + stack + TAB_GAP
	self.tab.Position = UDim2.fromOffset(CARDS_X, tabTop)
	self.bestiary.Position = UDim2.fromOffset(CARDS_X + CARD_WIDTH - PILL_LENGTH, tabTop)
	self.guide.Position = UDim2.fromOffset(CARDS_X, LIST_TOP - GUIDE_HEIGHT - 8)
	self.tabArrow.Text = if storageOpen then ">" else "<"
	self.storage.column.Position = UDim2.fromOffset(STORE_X, 0)
	self.storage.column.Visible = storageOpen

	self:_setBinArmed(false)

	-- As tall as the taller column: an open drawer ends in its buy button.
	self.root.Size = UDim2.fromOffset(
		ROOT_WIDTH,
		math.max(tabTop + TAB_HEIGHT, if storageOpen then self.storage.height() else 0) + EDGE + HINT_GAP + HINT_HEIGHT
	)
end

--[[
	Opens or shuts the storage drawer. The root changes width round the
	loadout, so PauseMenu re-centres it and the loadout does not move.
]]
function AbilityPanel:_setStorageOpen(open: boolean)
	if open == storageOpen then
		return
	end
	storageOpen = open
	layoutFor(open)
	self.storage.dismiss()
	self:_rebuild()

	if open then
		-- Slides out from behind the tab.
		local column = self.storage.column
		column.Position = UDim2.fromOffset(STORE_X + 40, 0)
		TweenService:Create(
			column,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(STORE_X, 0) }
		):Play()
	end
end

-- The tab's line: what is in storage, or that there is none yet.
function AbilityPanel:_refreshTab(state)
	if not self.tabCount then
		return
	end
	local capacity = state.capacity or 0
	local stored = #(state.slots or {})
	self.tabCount.Text = if capacity == 0 and stored == 0 then "+" else string.format("%d/%d", stored, capacity)
end

-- ---------------------------------------------------------------------------
-- Dragging
-- ---------------------------------------------------------------------------

--[[
	Lays every card except the dragged one out for the order the drop would
	make, so the stack opens a gap under the card in the air.

	The permutation is a MOVE, not a swap: pulling slot 3 up to slot 1 pushes 1
	and 2 down rather than sending 1 to the bottom. That is what the server does
	with the same two numbers, so what the stack shows while the card is in the
	air is what will be there when it lands.
]]
function AbilityPanel:_layoutAround(from: number, to: number)
	local order = {}
	for slot = 1, self.filled do
		order[slot] = slot
	end

	table.remove(order, from)
	table.insert(order, to, from)

	for position, slot in ipairs(order) do
		if slot ~= from then
			local card = self.cards[slot]
			if card then
				TweenService:Create(card.button, Theme.Tween.Open, {
					Position = slotPosition(position),
				}):Play()
			end
		end
	end
end

function AbilityPanel:_beginDrag(card, startX: number?, startY: number?)
	if self.drag or not (startX and startY) then
		return
	end

	--[[
		Nothing to pick up in an empty slot.

		ONE filled slot is enough, though. There is nowhere to reorder it to and
		the vertical clamp below works that out for itself - `reach` comes to
		zero, so the card cannot move up or down at all - but it can still be
		carried sideways into the bin, which is the only way to make room for a
		scroll when the one ability you have is not the one you want.
	]]
	if not card.filled or self.filled < 1 or not self.visible or self.storedDrag then
		return
	end

	local drag = {
		card = card,
		from = card.slot,
		target = card.slot,
		startX = startX,
		startY = startY,
		moved = false,

		-- Whether the card is far enough right that letting go would bin it.
		-- While it is, the stack stops reordering: a card on its way out is not
		-- also being put somewhere.
		binned = false,

		-- Whether it is far enough left that letting go would store it, and on
		-- which stored card.
		storing = false,
		storeTarget = nil,
	}
	self.drag = drag

	--[[
		Listened for globally rather than on the card.

		A pointer moving faster than the card follows it leaves the button
		behind, and a button that only hears its own input loses the drag the
		instant that happens - the classic "it drops when I move quickly".
	]]
	drag.changed = UserInputService.InputChanged:Connect(function(input)
		local x, y = self:_pointerAt(input)
		if x and y then
			self:_dragTo(x, y)
		end
	end)

	drag.ended = UserInputService.InputEnded:Connect(function(input)
		if isPressInput(input) then
			self:_endDrag()
		end
	end)
end

function AbilityPanel:_dragTo(x: number, y: number)
	local drag = self.drag
	if not drag then
		return
	end

	local sideways = x - drag.startX
	local delta = y - drag.startY

	if not drag.moved then
		-- Either axis starts the drag. Reaching for the bin is a sideways
		-- movement, and requiring vertical travel first would make the card
		-- jump the moment it finally began.
		if math.max(math.abs(delta), math.abs(sideways)) < DRAG_THRESHOLD then
			return
		end

		drag.moved = true
		drag.card.button.ZIndex = 10
		self:_refreshCard(drag.card)
		Sounds.play("ui.click")
	end

	--[[
		Sideways travel: right toward the bin, left across into the storage
		column. Clamped to the two, since past either there is nothing to drop
		onto and the CanvasGroup would cut the card in half on the way out.
	]]
	local lift = math.clamp(sideways, if storageOpen then STORE_X - CARDS_X else 0, BIN_SIDE)

	--[[
		Which target the card is over, measured as TRAVEL from where the drag
		began, added to where the card started in the root - never against a
		control's AbsolutePosition, which is in a different screen space than
		the pointer and would put the boundary a topbar's height out. See
		pointerAt.
	]]
	local storing = lift <= -STORE_REACH
	local binned = lift >= BIN_REACH

	if storing ~= drag.storing then
		drag.storing = storing
		Sounds.play(if storing then "ui.hover" else "ui.close")
		self:_layoutAround(drag.from, if storing then drag.from else drag.target)
	end

	if binned ~= drag.binned then
		drag.binned = binned
		Sounds.play(if binned then "ui.hover" else "ui.close")
		self:_setBinArmed(binned)

		-- Coming back off the bin puts the stack back the way the current
		-- target left it; going onto it closes the gap up again.
		self:_layoutAround(drag.from, if binned then drag.from else drag.target)
	end

	--[[
		Held inside the stack - or, over the storage column, inside that
		column's rows - rather than allowed to follow the cursor anywhere. A
		CanvasGroup renders its descendants into a buffer its own size, so a
		card carried past its edge is cut in half, and a card lifted somewhere
		it cannot be dropped lies about what letting go will do.
	]]
	local reach = math.max(0, if storing then AbilityConfigSlotCount - 1 else self.filled - 1) * PITCH
	local carried = math.clamp((drag.from - 1) * PITCH + delta, 0, reach)
	drag.card.button.Position = UDim2.fromOffset(CARDS_X + lift, LIST_TOP + carried)

	if storing then
		-- Which stored card it would swap with, or the next free slot.
		local middle = LIST_TOP + carried + CARD_HEIGHT * 0.5
		self.storage.nudge(middle)
		drag.storeTarget = self.storage.rowAt(middle)
		self.storage.setTarget(drag.storeTarget)
		return
	end
	if drag.storeTarget then
		drag.storeTarget = nil
		self.storage.setTarget(nil)
	end

	-- On its way to the bin it is not also choosing a slot. Leaving the target
	-- where it was means dragging back off the bin returns to the arrangement
	-- that was on screen before, rather than to wherever the pointer's height
	-- happens to be by then.
	if binned then
		return
	end

	-- Which slot it would land in: whichever row its own top edge is nearest.
	-- Already inside the filled range, because `carried` is.
	local target = math.clamp(math.floor(carried / PITCH + 0.5) + 1, 1, self.filled)

	if target ~= drag.target then
		drag.target = target
		Sounds.play("ui.hover")
		self:_layoutAround(drag.from, target)
	end
end

-- Lights the bin up while a card is over it. Colour and opacity together,
-- because at its resting grey it has to be quiet enough to ignore.
-- Red, because binning is the one that cannot be undone.
function AbilityPanel:_setBinArmed(armed: boolean)
	if not self.drag then
		self.storage.setTarget(nil)
	end

	setSpriteArmed(self.binPixels, armed, Theme.Color.Bad)
end

function AbilityPanel:_endDrag()
	local drag = self.drag
	if not drag then
		return
	end

	self:_disconnectDrag()
	self.drag = nil
	self:_setBinArmed(false)

	local card = drag.card
	self:_refreshCard(card)

	if not drag.moved then
		-- A click on a card, which this panel has nothing to do with. Left
		-- exactly where it was rather than treated as a drop onto itself.
		card.button.ZIndex = 1
		card.button.Position = slotPosition(drag.from)
		return
	end

	--[[
		Into the bin - asked about first.

		The card goes straight back into the stack while the question is up, so
		the panel is never showing a state nobody has agreed to. Only the answer
		moves anything.

		The slot is looked up AGAIN when the answer comes rather than being read
		from `drag`, because a server push can rebuild the whole panel while the
		dialog is open. What was slot 2 when the drag started may be a different
		ability by the time the player says yes, and dropping that one would be
		this feature doing the exact thing it exists to prevent.
	]]
	--[[
		Into storage: onto a stored ability, a swap when storage has no room
		left; anywhere else in the column, stored in the next free slot. The
		stack goes back as it was until the server's push says what happened.
	]]
	if drag.storing then
		local ability = StorageAbilityConfig.resolve(card.name.Text)
		local store = StorageUI.state()
		local over = drag.storeTarget and store.slots[drag.storeTarget]
		self:_rebuild()
		if not ability then
			return
		end
		if over and #store.slots >= (store.capacity or 0) then
			self.storage.swap(over, ability)
		else
			self.storage.store(ability)
		end
		Sounds.play("ui.click")
		return
	end

	if drag.binned then
		card.button.ZIndex = 1
		card.button.Position = slotPosition(drag.from)

		local name = card.name.Text

		Confirm.ask({
			title = string.format("Drop %s?", name),
			body = "It leaves your loadout. Getting it back means another scroll.",
			accept = "Drop",
			tone = "bad",
		}, function(accepted)
			if not accepted then
				return
			end

			local slot = table.find(self.cards, card)
			if not slot then
				return
			end

			self:_applyDrop(slot)

			if handlers.drop then
				handlers.drop(slot)
			end
		end)

		return
	end

	-- Settles into the gap the rest of the stack has already opened for it.
	local settle = TweenService:Create(card.button, Theme.Tween.Open, {
		Position = slotPosition(drag.target),
	})
	card.settle = settle

	--[[
		Still on top until it has actually landed.

		Dropped to ZIndex 1 here, it would slide UNDER every card it passes for
		the length of the settle - which is the one sixth of a second the player
		is watching most closely, because it is the answer to what their drag
		just did.
	]]
	settle.Completed:Connect(function()
		card.button.ZIndex = 1
		if card.settle == settle then
			card.settle = nil
		end
	end)

	settle:Play()

	if drag.target == drag.from then
		Sounds.play("ui.close")
		return
	end

	Sounds.play("ui.click")

	-- Before the request goes out, not after it comes back.
	self:_applyMove(drag.from, drag.target)

	if handlers.reorder then
		handlers.reorder(drag.from, drag.target)
	end
end

--[[
	Applies a move to the cards themselves, not only to where they are drawn.

	THIS IS WHAT STOPS TWO ABILITIES ENDING UP ON TOP OF EACH OTHER

	A drop moves a card optimistically and waits for the server to confirm it.
	Without this, `card.slot` still says where the card USED to be for the whole
	of that round trip, while the card is sitting somewhere else - and every
	part of the drag reads `card.slot`.

	Start a second drag inside that window and `_beginDrag` takes its origin
	from the stale slot, so the card teleports onto its neighbour the moment the
	threshold is crossed. Worse, merely CLICK inside it: the not-moved branch
	puts the card back at the stale slot, on top of the other one, and sends
	nothing - so no push comes back, no rebuild happens, and the two stay drawn
	over each other until something else changes the loadout. Closing and
	reopening the menu does not help, because showing the panel does not rebuild
	it.

	Permuting the array here keeps the one invariant everything else assumes:
	self.cards[i] is the card sitting at position i. The server still has the
	last word - its push rebuilds from scratch and overwrites this if it
	disagreed.
]]
--[[
	Takes a card out, for the same reasons and with the same caveat as
	_applyMove: the display must not disagree with `card.slot` for the length of
	a round trip, and the server still has the last word.

	The card is DESTROYED rather than hidden. _rebuild makes whatever cards it
	is short of, so if the server refuses the drop its push simply builds a new
	one - which is less state than keeping a dead card around and remembering
	that it is dead.
]]
function AbilityPanel:_applyDrop(slot: number)
	local card = table.remove(self.cards, slot)
	if not card then
		return
	end

	if card.settle then
		card.settle:Cancel()
		card.settle = nil
	end

	card.button:Destroy()

	for index, entry in ipairs(self.cards) do
		entry.slot = index
		entry.button.Position = slotPosition(index)
	end

	self.filled = math.max(0, self.filled - 1)
	self.hint.Visible = self.filled > 0
	self.hint.Text = hintFor(self.filled)
	self.bin.Visible = self.filled > 0
end

function AbilityPanel:_applyMove(from: number, to: number)
	local card = table.remove(self.cards, from)
	if not card then
		return
	end

	table.insert(self.cards, to, card)

	for slot, entry in ipairs(self.cards) do
		entry.slot = slot
	end
end

function AbilityPanel:_disconnectDrag()
	local drag = self.drag
	if not drag then
		return
	end

	if drag.changed then
		drag.changed:Disconnect()
	end
	if drag.ended then
		drag.ended:Disconnect()
	end
end

--[[
	Drops a drag on the floor: the menu closed under it, or the server pushed a
	new loadout while a card was in the air.

	Every card is put back rather than only the one being carried, because the
	rest of the stack has been shuffled around to make room for it.
]]
function AbilityPanel:_cancelDrag()
	local drag = self.drag
	if not drag then
		return
	end

	self:_disconnectDrag()
	self.drag = nil
	self:_setBinArmed(false)

	drag.card.button.ZIndex = 1

	for slot, card in ipairs(self.cards) do
		-- Including any card still settling from an earlier drop, or "put back"
		-- would last exactly as long as it took that tween to finish.
		if card.settle then
			card.settle:Cancel()
			card.settle = nil
		end

		card.button.ZIndex = 1
		card.button.Position = slotPosition(slot)
		self:_refreshCard(card)
	end
end

-- ---------------------------------------------------------------------------
-- Dragging out of storage
-- ---------------------------------------------------------------------------

--[[
	A stored card is carried as a GHOST: a copy of the card made from the same
	builder, on top of the whole panel. The real row stays in the storage list,
	dimmed, because that list scrolls - and anything inside a ScrollingFrame is
	cut off at its edge the moment it leaves.

	Dropped on the loadout column it is taken out, into the next free slot, or
	- with every slot full - swapped with the card it was dropped on. Dropped
	back in the storage column it moves to that row. Anywhere else it goes back.
	The same distances-travelled rule as the loadout drag decides all of it;
	see pointerAt.
]]
function AbilityPanel:_beginStoredDrag(index: number, startX: number?, startY: number?)
	if self.drag or self.storedDrag or not (startX and startY) or not self.visible then
		return
	end

	local name = StorageUI.state().slots[index]
	if not name then
		return
	end

	local drag = {
		index = index,
		name = name,
		startX = startX,
		startY = startY,
		top = self.storage.rowTop(index),
		moved = false,
	}
	self.storedDrag = drag

	drag.changed = UserInputService.InputChanged:Connect(function(input)
		local x, y = self:_pointerAt(input)
		if x and y then
			self:_storedDragTo(x, y)
		end
	end)

	drag.ended = UserInputService.InputEnded:Connect(function(input)
		if isPressInput(input) then
			self:_endStoredDrag(true)
		end
	end)
end

-- Picks out the loadout card a stored card would land on, or none.
function AbilityPanel:_armLoadout(slot: number?)
	for index, card in ipairs(self.cards) do
		local armed = index == slot
		if card.armed ~= armed then
			card.armed = armed
			self:_refreshCard(card)
		end
	end
end

function AbilityPanel:_storedDragTo(x: number, y: number)
	local drag = self.storedDrag
	if not drag then
		return
	end

	local dx, dy = x - drag.startX, y - drag.startY

	if not drag.moved then
		if math.max(math.abs(dx), math.abs(dy)) < DRAG_THRESHOLD then
			return
		end
		drag.moved = true

		local definition = StorageAbilityConfig.get(drag.name)
		local ghost = newCard(self.root)
		ghost.button.Name = "CarriedStored"
		ghost.button.ZIndex = 20
		ghost.button.BackgroundTransparency = CARD_LIFTED
		ghost.stroke.Transparency = STROKE_LIFTED
		ghost.stroke.Color = Theme.PixelColor.Selection
		ghost.label.Text = "STORED"
		ghost.label.TextColor3 = Theme.PixelColor.Selection
		ghost.name.Text = definition and definition.displayName or drag.name
		ghost.rarity.Text = if definition and definition.rarity then string.upper(definition.rarity) else ""
		ghost.rarity.TextColor3 = Theme.rarityColor(definition and definition.rarity)
		ghost.badge.Text = tostring(drag.index)
		ghost.badge.TextColor3 = Theme.PixelColor.Selection
		ghost.badgeStroke.Color = Theme.PixelColor.Selection
		for _, text in ipairs({ ghost.label, ghost.name, ghost.rarity, ghost.badge }) do
			text.ZIndex = 21
		end
		drag.ghost = ghost

		self.storage.setLifted(drag.index)
		Sounds.play("ui.click")
	end

	-- Between the two columns, and level with their rows.
	local left = math.clamp(STORE_X + dx, STORE_X, CARDS_X)
	local top = math.clamp(drag.top + dy, LIST_TOP, LIST_TOP + (AbilityConfigSlotCount - 1) * PITCH)
	drag.ghost.button.Position = UDim2.fromOffset(left, top)

	local middle = top + CARD_HEIGHT * 0.5

	if left >= (STORE_X + CARDS_X) * 0.5 then
		-- Over the loadout: the card it would replace when every slot is full,
		-- otherwise the empty slot it would fill.
		local full = self.filled >= #self.cards
		local slot = if full
			then math.clamp(math.floor((middle - LIST_TOP) / PITCH) + 1, 1, #self.cards)
			else self.filled + 1

		if drag.storeTarget then
			drag.storeTarget = nil
			self.storage.setTarget(nil)
		end
		if slot ~= drag.loadoutTarget then
			drag.loadoutTarget = slot
			self:_armLoadout(slot)
			Sounds.play("ui.hover")
		end
		return
	end

	if drag.loadoutTarget then
		drag.loadoutTarget = nil
		self:_armLoadout(nil)
	end

	self.storage.nudge(middle)
	local row = self.storage.rowAt(middle)
	row = if row and row ~= drag.index then row else nil
	if row ~= drag.storeTarget then
		drag.storeTarget = row
		self.storage.setTarget(row)
		if row then
			Sounds.play("ui.hover")
		end
	end
end

-- Lets go: `commit` false only when the screen closed under the drag.
function AbilityPanel:_endStoredDrag(commit: boolean)
	local drag = self.storedDrag
	if not drag then
		return
	end
	self.storedDrag = nil

	drag.changed:Disconnect()
	drag.ended:Disconnect()
	if drag.ghost then
		drag.ghost.button:Destroy()
	end
	self.storage.setLifted(nil)
	self.storage.setTarget(nil)
	self:_armLoadout(nil)

	if not commit then
		return
	end

	local full = self.filled >= #self.cards

	if not drag.moved then
		-- A click: take it out when there is room, the way the old list did.
		if not full then
			self.storage.retrieve(drag.name)
			Sounds.play("ui.click")
		end
		return
	end

	if drag.loadoutTarget then
		if not full then
			self.storage.retrieve(drag.name)
		else
			local card = self.cards[drag.loadoutTarget]
			local active = card and StorageAbilityConfig.resolve(card.name.Text)
			if active then
				self.storage.swap(drag.name, active)
			end
		end
		Sounds.play("ui.click")
	elseif drag.storeTarget then
		local count = #StorageUI.state().slots
		self.storage.move(drag.index, math.min(drag.storeTarget, count))
		Sounds.play("ui.click")
	else
		Sounds.play("ui.close")
	end
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------

-- What the menu asked for. Shown only if nothing is holding the list back too.
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
		self.fade = TweenService:Create(self.root, Theme.Tween.Fade, { GroupTransparency = 0 })
		self.fade:Play()
		return
	end

	self:_cancelDrag()
	self:_endStoredDrag(false)

	-- Storage closes with the screen it lives on. Left open it is still open
	-- the next time the screen appears, which is a panel nobody asked for over
	-- the cards they did.
	self.storage.dismiss()

	local fade = TweenService:Create(self.root, Theme.Tween.Close, { GroupTransparency = 1 })
	self.fade = fade

	-- A CanvasGroup at full transparency still takes clicks; only Visible stops
	-- that, and it cannot be set until the fade has actually finished.
	fade.Completed:Connect(function(state)
		if not self.visible and state == Enum.PlaybackState.Completed then
			self.root.Visible = false
		end
	end)

	fade:Play()
end

function AbilityPanel:destroy()
	self:_cancelDrag()
	self.root:Destroy()

	if live == self then
		live = nil
	end
end

-- ---------------------------------------------------------------------------
-- The way in from outside
-- ---------------------------------------------------------------------------

--[[
	What to list. One entry per slot, in slot order:

	  label    the capitals line, already worded ("slot 1  ~  Z")
	  name     the ability's display name, or nil for an empty slot
	  rarity   its tier name, or nil
	  gained   true for the one that was just equipped

	Kept even when there is no panel to put it in, so the order in which
	PauseMenu and AbilityClient start does not decide whether the first loadout
	is drawn.
]]
function AbilityPanel.setSlots(entries: { any }?)
	slots = entries or {}

	if live then
		live:_rebuild()
	end
end

--[[
	Where a drop goes.

	  reorder(fromSlot, toSlot)   a card dropped on another slot
	  drop(slot)                  a card dropped on the bin

	Set once, at startup, by whoever owns the remotes. The panel does not care
	whether either request succeeds - see the note at the top about the push
	that follows every one of them either way.
]]
function AbilityPanel.setHandlers(next: { [string]: ((...any) -> ())? }?)
	handlers = next or {}
end

--[[
	Steps the list out of the way while something else needs the middle of
	the Tab menu - today, the tutorial's ability choice (Shared.UI.
	TutorialChoice) - and back when it is done. The menu still opens and
	closes it as usual; held back, it just stays faded out until released.
]]
function AbilityPanel.setHeldBack(held: boolean)
	heldBack = held == true

	if live then
		live:_show(live.wanted and not heldBack)
	end
end

return AbilityPanel
