--[[
	InventoryLayout

	Builds the inventory's screen: the hotbar, the bag, the bin and the gear
	column. Layout only - what a slot holds, dragging and equipping all belong
	to StarterPlayerScripts.InventoryClient, which is the one caller.

		local layout = InventoryLayout.build(playerGui)

		layout.gui         the ScreenGui, "InventoryUI"
		layout.slots       the tile for each slot index, 1 .. SlotCount
		layout.itemLabel   the name of the item in hand
		layout.openPanels  what is only on screen while the inventory is open
		layout.onMoved(fn) calls fn whenever the tiles move on screen

	It used to be hand-placed in StarterGui, and was lost with the place file's
	other assets. Built here it cannot be lost, and it is made of the same Theme
	measurements as every other piece of UI.

	WHERE THINGS GO

	  Hotbar      top left, just under Roblox's top bar. Always on screen.
	  Bag         the rows under the hotbar, and the bin under their first column.
	  Item label  to the right of the hotbar.
	  Gear        bottom right: armor, then the accessories. Kept apart from the
	              grid so what you are wearing reads as a separate thing from
	              what you are carrying.

	SIZES ARE THEME PIXELS ON A 1080p SCREEN

	Everything is laid out in Theme's slot measurements, which are what a slot
	should be on a 1080p screen, and a UIScale on each group fits that to the
	real one: bigger at 1440p, never smaller than that on a shorter screen, and
	only shrunk when a window is too narrow to fit it. The tiles keep their pixel sizes
	underneath the scale, so code that measures a tile in Offset - the drag
	code does - still gets the numbers it expects.

	SLOT INDICES, and the names the hand-built UI gave them

	  1-9    Row1 (hotbar)
	  10-36  Row2-Row4
	  37-41  Row5 (accessories)
	  42     Row6 (armor)
	  43     Row7 (the bin)

	Kept, so the Explorer reads the same as it always did.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local InventoryConstants = require(ReplicatedStorage:WaitForChild("InventoryConstants"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SlotArt = require(script.Parent:WaitForChild("SlotArt"))

local InventoryLayout = {}

-- ---------------------------------------------------------------------------
-- Measurements, in 1080p pixels
-- ---------------------------------------------------------------------------

local SLOT = Theme.SlotSize
local PITCH = Theme.SlotPitch
local GAP = PITCH - SLOT

-- The item picture inside the frame art: the 48-in-64 the tiles always had.
local ICON = math.round(SLOT * 0.75)
local ICON_INSET = (SLOT - ICON) / 2

local COUNT_HEIGHT = 20
local COUNT_INSET = 5

local COLUMNS = InventoryConstants.HotbarSlots
local HOTBAR_SLOTS = InventoryConstants.HotbarSlots
local ACCESSORIES = InventoryConstants.AccessoryRange
local ARMOR = InventoryConstants.ArmorRange
local BIN_SLOT = InventoryConstants.BinSlot

-- Every slot between the hotbar and the gear is bag.
local BAG_ROWS = (ACCESSORIES.first - 1 - HOTBAR_SLOTS) // COLUMNS

local GRID_WIDTH = COLUMNS * PITCH - GAP

-- The hotbar stands slightly apart from the bag, so the row that is always
-- there reads as its own thing when the rest opens under it.
local BAG_TOP = SLOT + Theme.Spacing.Gap
local BIN_TOP = BAG_TOP + BAG_ROWS * PITCH + Theme.Spacing.Gap
local BAG_HEIGHT = BIN_TOP + SLOT

local ITEM_LABEL_WIDTH = 280
local ITEM_LABEL_HEIGHT = 28

local TITLE_HEIGHT = Theme.TextSize.Small + 6

-- The height Roblox's top bar is assumed to have when it reports none, the
-- same floor SettingsButton uses for the button it puts in that bar.
local MIN_TOPBAR_HEIGHT = 36

-- ---------------------------------------------------------------------------
-- Fitting to the screen
-- ---------------------------------------------------------------------------

--[[
	Never smaller than the hand-built inventory was. That one was a fixed 64
	pixels a slot on every screen, and the first version of this scaled it by
	height from 1080p - which shrank it to two-thirds in a Studio window and on
	any laptop, and read as the inventory having got smaller. So the Theme
	size is the floor: a taller screen grows it, a shorter one keeps it.

	The one exception is width. A window too narrow for a 64-pixel grid gets a
	smaller one rather than a grid that runs off the side, down to MIN_SCALE.
]]
local DESIGN_HEIGHT = 1080

-- THE SIZE DIAL. Multiplies everything above: 1 is the hand-built UI's size,
-- 0.9 is a tenth smaller, 1.1 a tenth bigger.
local INVENTORY_SIZE = 0.9

-- 0.55 keeps a 64-pixel slot above 35 on a phone; 2 stops a 4K screen growing
-- it past where it helps.
local MIN_SCALE = 0.55
local MAX_SCALE = 2

-- The grid may take at most this share of the screen's width.
local MAX_WIDTH_SHARE = 0.6

local function scaleFor(screenSize: Vector2): number
	local scale = math.min(
		math.max(1, screenSize.Y / DESIGN_HEIGHT),
		screenSize.X * MAX_WIDTH_SHARE / GRID_WIDTH
	)
	return math.clamp(scale * INVENTORY_SIZE, MIN_SCALE, MAX_SCALE)
end

-- ---------------------------------------------------------------------------
-- The bin's picture
-- ---------------------------------------------------------------------------

-- The same drawing as the ability screen's bin, so the two mean the same thing
-- in both places. Shared.UI.AbilityPanel owns the original.
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

local BIN_ICON_SCALE = 0.62
local BIN_ICON_TRANSPARENCY = 0.55

--[[
	Drawn BEHIND the slot's icon and count rather than instead of them: an
	empty bin shows what it is, and a bin holding something shows the item over
	the picture - so the thing about to be destroyed is never hidden by the
	label saying it is about to be destroyed.
]]
local function drawBinIcon(tile: GuiObject)
	local art = Instance.new("Frame")
	art.Name = "BinIcon"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(BIN_ICON_SCALE, BIN_ICON_SCALE)
	art.BackgroundTransparency = 1
	art.ZIndex = 1
	art.Parent = tile

	local rows = #BIN_SPRITE
	local columns = #BIN_SPRITE[1]

	for row, line in ipairs(BIN_SPRITE) do
		for column = 1, columns do
			if string.sub(line, column, column) == "#" then
				local pixel = Instance.new("Frame")
				pixel.BackgroundColor3 = Theme.Color.TextDim
				pixel.BackgroundTransparency = BIN_ICON_TRANSPARENCY
				pixel.BorderSizePixel = 0
				pixel.ZIndex = 1
				pixel.Position = UDim2.fromScale((column - 1) / columns, (row - 1) / rows)
				pixel.Size = UDim2.fromScale(1 / columns, 1 / rows)
				pixel.Parent = art
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------------

--[[
	One slot: the frame art, the item's picture, and its count in the bottom
	right corner - the same tile CraftingClient draws, so a stack looks the
	same in the bag as it does in a recipe.

	The icon is a BUTTON because a drag starts from it; the tile is one so it
	sinks clicks that would otherwise go through to the world and swing
	whatever is in hand.
]]
local function newTile(parent: Instance, name: string, position: UDim2): ImageButton
	local tile = Instance.new("ImageButton")
	tile.Name = name
	tile.AutoButtonColor = false
	tile.BackgroundTransparency = 1
	tile.BorderSizePixel = 0
	tile.Size = UDim2.fromOffset(SLOT, SLOT)
	tile.Position = position
	tile.ZIndex = 1
	tile.Parent = parent
	SlotArt.apply(tile)

	local icon = Instance.new("ImageButton")
	icon.Name = "icon"
	icon.AutoButtonColor = false
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.Size = UDim2.fromOffset(ICON, ICON)
	icon.Position = UDim2.fromOffset(ICON_INSET, ICON_INSET)
	icon.Visible = false
	icon.ZIndex = 2
	icon.Parent = tile

	local count = Instance.new("TextLabel")
	count.Name = "num"
	count.BackgroundTransparency = 1
	count.Size = UDim2.fromOffset(SLOT - COUNT_INSET, COUNT_HEIGHT)
	count.Position = UDim2.fromOffset(0, SLOT - COUNT_HEIGHT - COUNT_INSET + 2)
	count.FontFace = Theme.Fonts.Number
	count.TextSize = Theme.TextSize.Count
	count.TextColor3 = Color3.new(1, 1, 1)
	count.TextStrokeTransparency = 0.4
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextYAlignment = Enum.TextYAlignment.Center
	count.Text = ""
	count.ZIndex = 3
	count.Parent = tile

	return tile
end

local function newGroup(parent: Instance, name: string, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = size
	frame.Parent = parent
	return frame
end

-- A row of tiles running across, Slot1 on the left.
local function newRow(parent: Instance, name: string, top: number, count: number): Frame
	local row = newGroup(parent, name, UDim2.fromOffset(count * PITCH - GAP, SLOT))
	row.Position = UDim2.fromOffset(0, top)
	for index = 1, count do
		newTile(row, "Slot" .. index, UDim2.fromOffset((index - 1) * PITCH, 0))
	end
	return row
end

-- The same running down, Slot1 at the top.
local function newColumn(parent: Instance, name: string, top: number, count: number): Frame
	local column = newGroup(parent, name, UDim2.fromOffset(SLOT, count * PITCH - GAP))
	column.Position = UDim2.fromOffset(0, top)
	for index = 1, count do
		newTile(column, "Slot" .. index, UDim2.fromOffset(0, (index - 1) * PITCH))
	end
	return column
end

local function newTitle(parent: Instance, text: string, top: number): TextLabel
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	-- Wider than the column and centred on it, so the word is never clipped by
	-- a slot-wide box.
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, top)
	title.Size = UDim2.fromOffset(SLOT * 2.5, TITLE_HEIGHT)
	title.FontFace = Theme.Fonts.Heading
	title.TextSize = Theme.TextSize.Small
	title.TextColor3 = Theme.Color.Text
	title.TextStrokeTransparency = 0.4
	title.Text = text
	title.Parent = parent
	return title
end

-- ---------------------------------------------------------------------------
-- The hotbar's selection marker
-- ---------------------------------------------------------------------------

--[[
	An accent frame AROUND the selected tile, with a soft glow outside it and a
	small tab under it pointing up at the item.

	It used to be a translucent yellow rectangle laid over the tile, which
	tinted the very item it was pointing at, and was placed from the tile's
	on-screen position - so a tile caught mid-hover or mid-pulse put it a few
	pixels out. This one lives in the hotbar row itself and is placed from the
	tiles' RESTING offsets, so it lines up exactly at any screen size and never
	covers what is in the slot: only its border is drawn.
]]
local MARKER_OUTSET = 4
local MARKER_STROKE = 3
local MARKER_GLOW = 7
local MARKER_GLOW_TRANSPARENCY = 0.78
local MARKER_TAB = 8
local MARKER_SLIDE = TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local MARKER_POP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function newSelectionMarker(row: Instance)
	local marker = Instance.new("Frame")
	marker.Name = "Selection"
	marker.BackgroundTransparency = 1
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.fromOffset(SLOT + MARKER_OUTSET * 2, SLOT + MARKER_OUTSET * 2)
	-- Above the tiles, swollen ones included (they step up to ZIndex 2), so
	-- the border is never hidden under a neighbour.
	marker.ZIndex = 5
	marker.Visible = false
	marker.Parent = row

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = marker

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Border"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Color.Accent
	stroke.Thickness = MARKER_STROKE
	stroke.Parent = marker

	-- A lighter edge across the top, so the frame reads as lit rather than as a
	-- flat outline.
	local sheen = Instance.new("UIGradient")
	sheen.Rotation = 90
	sheen.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
	sheen.Parent = stroke

	-- The glow: a wider, faint stroke on a slightly larger frame behind it.
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, MARKER_GLOW, 1, MARKER_GLOW)
	glow.ZIndex = 5
	glow.Parent = marker

	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0, 11)
	glowCorner.Parent = glow

	local glowStroke = Instance.new("UIStroke")
	glowStroke.Color = Theme.Color.Accent
	glowStroke.Thickness = MARKER_GLOW
	glowStroke.Transparency = MARKER_GLOW_TRANSPARENCY
	glowStroke.Parent = glow

	-- The tab: a small diamond half-tucked under the bottom edge, short enough
	-- to clear the bag row that opens beneath the hotbar.
	local tab = Instance.new("Frame")
	tab.Name = "Tab"
	tab.AnchorPoint = Vector2.new(0.5, 0.5)
	tab.Position = UDim2.new(0.5, 0, 1, -1)
	tab.Size = UDim2.fromOffset(MARKER_TAB, MARKER_TAB)
	tab.Rotation = 45
	tab.BackgroundColor3 = Theme.Color.Accent
	tab.BorderSizePixel = 0
	tab.ZIndex = 6
	tab.Parent = marker

	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(0, 2)
	tabCorner.Parent = tab

	local pop = Instance.new("UIScale")
	pop.Parent = marker

	local current: number? = nil

	-- Where tile `index` rests, as the marker's centre.
	local function centreOf(index: number): UDim2
		return UDim2.fromOffset((index - 1) * PITCH + SLOT / 2, SLOT / 2)
	end

	return function(index: number?)
		if index == current then
			return
		end

		if index == nil then
			current = nil
			marker.Visible = false
			return
		end

		local target = centreOf(index)

		if current == nil then
			-- Appearing from nothing: no slot to slide from, so it pops in place.
			marker.Position = target
			marker.Visible = true
			pop.Scale = 1.18
			TweenService:Create(pop, MARKER_POP, { Scale = 1 }):Play()
		else
			TweenService:Create(marker, MARKER_SLIDE, { Position = target }):Play()
		end

		current = index
	end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

function InventoryLayout.build(playerGui: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- The hotbar, the bag and the bin: one group, so they scale together about
	-- the top-left corner they hang from.
	local bag = newGroup(gui, "Bag", UDim2.fromOffset(GRID_WIDTH, BAG_HEIGHT))
	local bagScale = Instance.new("UIScale")
	bagScale.Parent = bag

	local hotbar = newRow(bag, "Row1", 0, HOTBAR_SLOTS)
	local selectHotbar = newSelectionMarker(hotbar)

	local bagRows = {}
	for index = 1, BAG_ROWS do
		bagRows[index] = newRow(bag, "Row" .. (index + 1), BAG_TOP + (index - 1) * PITCH, COLUMNS)
	end

	local binRow = newRow(bag, "Row7", BIN_TOP, 1)
	drawBinIcon(binRow.Slot1)

	local itemLabel = Instance.new("TextLabel")
	itemLabel.Name = "ItemLabel"
	itemLabel.BackgroundTransparency = 1
	itemLabel.AnchorPoint = Vector2.new(0, 0.5)
	itemLabel.Position = UDim2.fromOffset(GRID_WIDTH + Theme.Spacing.Section, SLOT / 2)
	itemLabel.Size = UDim2.fromOffset(ITEM_LABEL_WIDTH, ITEM_LABEL_HEIGHT)
	itemLabel.FontFace = Theme.Fonts.Heading
	itemLabel.TextSize = Theme.TextSize.Heading
	itemLabel.TextColor3 = Theme.Color.Text
	itemLabel.TextStrokeTransparency = 0.4
	itemLabel.TextXAlignment = Enum.TextXAlignment.Left
	itemLabel.Text = ""
	itemLabel.Parent = bag

	-- Armor over accessories, scaled about the bottom-right corner it sits in.
	local armorCount = ARMOR.last - ARMOR.first + 1
	local accessoryCount = ACCESSORIES.last - ACCESSORIES.first + 1
	local accessoryTitleTop = TITLE_HEIGHT + armorCount * PITCH - GAP + Theme.Spacing.Section
	local gearHeight = accessoryTitleTop + TITLE_HEIGHT + accessoryCount * PITCH - GAP

	local gear = newGroup(gui, "Gear", UDim2.fromOffset(SLOT, gearHeight))
	gear.AnchorPoint = Vector2.new(1, 1)
	gear.Position = UDim2.new(1, -Theme.Spacing.Edge, 1, -Theme.Spacing.Edge)
	local gearScale = Instance.new("UIScale")
	gearScale.Parent = gear

	newTitle(gear, "ARMOR", 0)
	local armorColumn = newColumn(gear, "Row6", TITLE_HEIGHT, armorCount)
	newTitle(gear, "ACCESSORIES", accessoryTitleTop)
	local accessoryColumn = newColumn(gear, "Row5", accessoryTitleTop + TITLE_HEIGHT, accessoryCount)

	-- Slot indices, in the order the server numbers them.
	local slots = {}
	local function take(group: Instance, count: number)
		for index = 1, count do
			table.insert(slots, group:FindFirstChild("Slot" .. index))
		end
	end
	take(hotbar, HOTBAR_SLOTS)
	for _, row in ipairs(bagRows) do
		take(row, COLUMNS)
	end
	take(accessoryColumn, accessoryCount)
	take(armorColumn, armorCount)
	take(binRow, 1)

	assert(
		#slots == InventoryConstants.SlotCount and slots[BIN_SLOT] == binRow.Slot1,
		"[InventoryLayout] the layout no longer matches InventoryConstants' slot numbering"
	)

	-- Everything but the hotbar waits for the inventory to open.
	local openPanels = { binRow, gear }
	for _, row in ipairs(bagRows) do
		table.insert(openPanels, row)
	end
	for _, panel in ipairs(openPanels) do
		panel.Visible = false
	end

	-- Under Roblox's top bar, which changes height between devices and when
	-- Roblox redraws it, and scaled to the screen.
	local function fit()
		local inset = GuiService.TopbarInset
		local top = inset.Min.Y + math.max(inset.Height, MIN_TOPBAR_HEIGHT)
		bag.Position = UDim2.fromOffset(Theme.Spacing.Edge, top + Theme.Spacing.Gap)

		local screenSize = gui.AbsoluteSize
		if screenSize.X > 0 and screenSize.Y > 0 then
			local scale = scaleFor(screenSize)
			bagScale.Scale = scale
			gearScale.Scale = scale
		end
	end

	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fit)

	local layout = {
		gui = gui,
		slots = slots,
		itemLabel = itemLabel,
		openPanels = openPanels,

		-- Puts the marker on hotbar slot 1-9, sliding from wherever it was, or
		-- hides it for nil.
		selectHotbar = selectHotbar,
	}

	--[[
		Anything measured in screen pixels - drop hit boxes, the hotbar marker -
		is stale once the groups move or rescale, so whoever measured it is told.
		Tiles swelling on hover do not count; only the groups are watched.
	]]
	function layout.onMoved(callback: () -> ())
		for _, group in ipairs({ bag, gear }) do
			group:GetPropertyChangedSignal("AbsolutePosition"):Connect(callback)
			group:GetPropertyChangedSignal("AbsoluteSize"):Connect(callback)
		end
	end

	return layout
end

return InventoryLayout
