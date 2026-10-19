--[[
	CraftingClient

	The crafting window. Stations down the left, that station's recipes in the
	middle, and the chosen recipe on the right: a live look at what it makes,
	what it costs against what you are carrying, and a button that makes it
	once or as many times as you ask.

	Opened with B for hand recipes, or by using a placed station's prompt, which
	opens on that station. Every tab, row and count is built at run time from
	CraftingRecipes and StationConfig, so adding a recipe or a station changes
	nothing here.

	WHAT THE CLIENT DECIDES, AND WHAT IT DOES NOT

	It reads the shared RecipeBook - the same module the server reads - so the
	list can never offer a recipe the server has not heard of. Everything it
	shows about affordability and range is a courtesy: the server re-checks
	materials, station and range on every craft, and all this ever sends is a
	recipe id. Crafting several is several requests, one after another, each
	waiting for the last one's answer.

	Drawn from the pixel-art kit (Shared.UI.PixelUI) on Shared.UI.Theme's fonts
	and rarity colours, so it shares the inventory's slots and frames: a wooden
	window, parchment insets for the list and the recipe, and the kit's buttons.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local RecipeBook = require(Shared:WaitForChild("Crafting"):WaitForChild("RecipeBook"))
local StationConfig = require(Shared.Crafting:WaitForChild("StationConfig"))
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local Motion = require(Shared.UI:WaitForChild("Motion"))
local SlotArt = require(Shared.UI:WaitForChild("SlotArt"))
local PixelUI = require(Shared.UI:WaitForChild("PixelUI"))
local ItemPreview = require(Shared.UI:WaitForChild("ItemPreview"))
local InventoryMirror =
	require(Shared:WaitForChild("Inventory"):WaitForChild("InventoryMirror"))
local MenuState = require(Shared.UI:WaitForChild("MenuState"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local WeaponClasses = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponClasses"))

-- The same resolver the inventory slots use, so an item is drawn the same way
-- on both screens. See Shared.UI.ItemThumbnails.
local ItemThumbnails = require(Shared.UI:WaitForChild("ItemThumbnails"))

--[[
	Set true to trace opening, closing and craft requests.

	Worth knowing when something here goes quiet: the remotes below are created
	by CraftingServer, so if that script is stuck or erroring, these waits never
	return and this whole file stops before it connects any input. An "Infinite
	yield possible on Remotes:WaitForChild" warning naming one of them means the
	problem is on the server, not here.
]]
local DEBUG = false
local function log(...)
	if DEBUG then
		print("[CraftingClient]", ...)
	end
end

log("waiting for crafting remotes")

local RequestCraft = Remotes.wait("RequestCraft")
local CraftingResult = Remotes.wait("CraftingResult")
local RequestFullInventory = Remotes.wait("RequestFullInventory")

log("remotes ready")

local MENU_NAME = "Crafting"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- Layout, in pixels on a 1080p screen. A UIScale fits it to the real one.
-- ---------------------------------------------------------------------------

local L = {
	width = 960,
	height = 650,
	-- Clear of the window frame's border (24) with a little to spare.
	pad = 30,
	gutter = 16,
	radius = 8,

	-- The frame's top border and the header row under the title banner.
	headerHeight = 84,
	headerRowTop = 24,

	sidebarWidth = 200,
	tabHeight = 54,

	searchHeight = 42,
	filterWidth = 150,
	rowHeight = 62,
	rowGap = 6,

	detailWidth = 300,
	-- Clear of an inset's border (12).
	detailPad = 18,
	heroHeight = 120,
	ingredientHeight = 46,
	stepperHeight = 36,
	buttonHeight = 50,
}

L.bodyTop = L.headerHeight + 6
L.bodyHeight = L.height - L.bodyTop - L.pad
L.listX = L.pad + L.sidebarWidth + L.gutter
L.detailX = L.width - L.pad - L.detailWidth
L.listWidth = L.detailX - L.gutter - L.listX

-- Never smaller than designed on an ordinary screen, bigger on a tall one, and
-- shrunk only when the window would not otherwise fit.
local DESIGN_HEIGHT = 1080
local MIN_SCALE = 0.5

-- Crafting several: the gap between requests (the server refuses anything
-- under 0.12s), how long to wait for an answer before giving up on a batch,
-- and the most one batch will make.
local CRAFT_GAP = 0.15
local CRAFT_TIMEOUT = 3
local MAX_BATCH = 99

-- How often, while the window is open, to look for stations in range.
local PROXIMITY_INTERVAL = 0.5

-- How long a result message stays up.
local TOAST_SECONDS = 3

-- Text colours: dark ink on parchment, cream on wood.
local P = Theme.PixelColor

-- The thin bars under each ingredient: a groove of dark wood.
local GROOVE = Color3.fromRGB(90, 53, 32)

-- The search box is drawn a touch dim, and lights up while it is typed in.
local SEARCH_IDLE = Color3.fromRGB(238, 238, 238)
local SEARCH_FOCUSED = Color3.new(1, 1, 1)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local isOpen = false
local activeStation = nil -- nil means hand crafting
local selectedRecipe = nil
local heldCounts = {} -- itemName -> count, from the last inventory snapshot
local searchQuery = "" -- lowercased search text; "" means no filter
local craftableOnly = false
local quantity = 1
local nearby = {} -- stationId -> true while one is in range

local rows = {} -- recipeId -> row parts
local visibleRecipes = {} -- the list as drawn, top to bottom
local tabs = {} -- tab id -> tab parts

-- The batch being crafted, if any: { recipe, total, done, sentAt }.
local batch = nil

-- ---------------------------------------------------------------------------
-- Small builders
-- ---------------------------------------------------------------------------

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

local function frame(parent, name, color, transparency)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or Color3.new()
	f.BackgroundTransparency = if color then (transparency or 0) else 1
	f.Parent = parent
	return f
end

local function text(parent, name, font, size, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = ""
	label.Parent = parent
	return label
end

local function button(parent, name)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Text = ""
	b.Parent = parent
	return b
end

--[[
	One inventory-style tile: the slot art, the item centred inside it at the
	inventory's 48/64, and a count in the bottom-right corner.
]]
local function newSlotTile(parent, pixels)
	local tile = Instance.new("ImageLabel")
	tile.Name = "Tile"
	tile.BackgroundTransparency = 1
	tile.BorderSizePixel = 0
	tile.Size = UDim2.fromOffset(pixels, pixels)
	tile.Parent = parent
	SlotArt.apply(tile)

	local icon = Instance.new("ImageLabel")
	icon.Name = "icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0.75, 0.75)
	icon.Position = UDim2.fromScale(0.125, 0.125)
	icon.ZIndex = tile.ZIndex + 1
	icon.Parent = tile

	local count = text(tile, "num", Theme.Fonts.Number, Theme.TextSize.Count, Color3.new(1, 1, 1))
	count.Size = UDim2.fromScale(0.92, 0.32)
	count.Position = UDim2.fromScale(0, 0.66)
	count.TextStrokeTransparency = 0.4
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.ZIndex = tile.ZIndex + 2

	return tile, icon, count
end

--[[
	Draws an item into an icon: a live 3D view where the item has a model and
	there is room under ItemPreview's cap, a flat image otherwise - the same
	order the inventory uses, so a pickaxe looks like the same pickaxe here.
]]
local function showItem(icon, itemName)
	if itemName and ItemPreview.fillSlot(icon, itemName) then
		ItemThumbnails.bind(icon, nil)
		return
	end

	ItemPreview.releaseSlot(icon)
	ItemThumbnails.bind(icon, itemName, function(image)
		if image == "" and itemName then
			ItemPreview.fillSlot(icon, itemName)
		end
	end)
end

local function displayName(itemName)
	local def = ItemDefinitions[itemName]
	if def and type(def.displayName) == "string" and def.displayName ~= "" then
		return def.displayName
	end
	-- "CopperPickaxe" -> "Copper Pickaxe"
	return (string.gsub(tostring(itemName), "(%l)(%u)", "%1 %2"))
end

local function rarityOf(itemName)
	local def = ItemDefinitions[itemName]
	return (def and def.rarity) or "Common"
end

local function stationColor(stationId)
	local def = StationConfig.get(stationId)
	local look = def and def.appearance
	return (look and (look.topColor or look.color)) or Theme.Color.TextDim
end

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------

local function held(itemName)
	return heldCounts[itemName] or 0
end

-- How many times over the player could make this right now.
local function craftableCount(recipe)
	if not recipe then
		return 0
	end

	local possible = math.huge
	for _, ingredient in ipairs(recipe.ingredients) do
		local need = ingredient.count or 1
		if need > 0 then
			possible = math.min(possible, math.floor(held(ingredient.item) / need))
		end
	end

	return if possible == math.huge then 0 else possible
end

local function canAfford(recipe)
	return craftableCount(recipe) > 0
end

-- Hand recipes are always in range; a station's only near a placed one.
local function inRange(stationId)
	return stationId == nil or nearby[stationId] == true
end

local function matchesSearch(recipe)
	if searchQuery == "" then
		return true
	end
	local item = recipe.output.item
	return string.find(string.lower(item), searchQuery, 1, true) ~= nil
		or string.find(string.lower(displayName(item)), searchQuery, 1, true) ~= nil
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "CraftingUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 10
screen.Enabled = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- Modal dim. Active so it sinks the click that closes the window instead of
-- letting it fall through to the world, where it would swing the pickaxe.
local backdrop = frame(screen, "Backdrop", Theme.Color.Backdrop, 1)
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.Active = true

-- Holds the window and its shadow, and carries the screen-fit scale.
local root = frame(screen, "Root")
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromOffset(L.width, L.height)

local rootScale = Instance.new("UIScale")
rootScale.Parent = root

-- A soft shadow: three dark layers, each a little wider and fainter.
local SHADOW_LAYERS = {
	{ grow = 6, transparency = 0.78 },
	{ grow = 14, transparency = 0.87 },
	{ grow = 24, transparency = 0.93 },
}
local shadows = {}
for index, layer in ipairs(SHADOW_LAYERS) do
	local shade = frame(root, "Shadow" .. index, Color3.new(0, 0, 0), 1)
	shade.AnchorPoint = Vector2.new(0.5, 0.5)
	shade.Position = UDim2.new(0.5, 0, 0.5, 8)
	shade.Size = UDim2.new(1, layer.grow, 1, layer.grow)
	corner(shade, L.radius + layer.grow / 2)
	shadows[index] = { frame = shade, transparency = layer.transparency }
end

-- The wooden window. Its background stays transparent: the art is the panel.
local window = PixelUI.image(root, "frame_wood")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromScale(1, 1)
-- Above the shadow layers, which are its earlier siblings.
window.ZIndex = 2

-- === Header =================================================================

local header = frame(window, "Header")
header.Size = UDim2.new(1, 0, 0, L.headerHeight)

-- The title is the green banner across the frame's top edge.
local banner, title = PixelUI.header(window, "Crafting")
banner.Position = UDim2.new(0.5, 0, 0, 0)
banner.ZIndex = 3

local headerRowHeight = L.headerHeight - L.headerRowTop

-- A small slot tinted with the station's colour, its initial on it.
local stationBadge = Instance.new("ImageLabel")
stationBadge.Name = "StationBadge"
stationBadge.BackgroundTransparency = 1
stationBadge.Position = UDim2.fromOffset(L.pad, L.headerRowTop + (headerRowHeight - 42) / 2)
stationBadge.Size = UDim2.fromOffset(42, 42)
stationBadge.Parent = header
SlotArt.apply(stationBadge)

local badgeLetter = text(stationBadge, "Letter", Theme.Fonts.Heading, 22, Color3.new(1, 1, 1))
badgeLetter.Size = UDim2.fromScale(1, 1)
badgeLetter.TextXAlignment = Enum.TextXAlignment.Center
badgeLetter.TextStrokeColor3 = Color3.fromRGB(43, 24, 16)
badgeLetter.TextStrokeTransparency = 0.2

local subtitle = text(header, "Subtitle", Theme.Fonts.Body, Theme.TextSize.Body, P.OnWoodDim)
subtitle.AnchorPoint = Vector2.new(0, 0.5)
subtitle.Position = UDim2.fromOffset(L.pad + 56, L.headerRowTop + headerRowHeight / 2)
subtitle.Size = UDim2.fromOffset(420, 22)

-- Close: the kit's cross over the frame's top-right corner, and the keys that
-- do the same beside it - a modal with no visible way out feels like a trap.
-- Wired further down, once close() exists.
local closeButton = PixelUI.closeButton(window)
closeButton.Position = UDim2.new(1, -14, 0, 14)
closeButton.ZIndex = 3

local closeHint = text(header, "KeyHint", Theme.Fonts.Body, Theme.TextSize.Small, P.OnWoodDim)
closeHint.AnchorPoint = Vector2.new(1, 0.5)
closeHint.Position = UDim2.new(1, -L.pad, 0, L.headerRowTop + headerRowHeight / 2)
closeHint.Size = UDim2.fromOffset(160, 18)
closeHint.TextXAlignment = Enum.TextXAlignment.Right
closeHint.Text = "B or Esc to close"

-- === Stations ===============================================================

local sidebar = frame(window, "Stations")
sidebar.Position = UDim2.fromOffset(L.pad, L.bodyTop)
sidebar.Size = UDim2.fromOffset(L.sidebarWidth, L.bodyHeight)

local sidebarCaption = text(sidebar, "Caption", Theme.Fonts.BodyBold, Theme.TextSize.Small, P.OnWoodDim)
sidebarCaption.Size = UDim2.new(1, 0, 0, 18)
sidebarCaption.Text = "STATIONS"

local tabList = frame(sidebar, "List")
tabList.Position = UDim2.fromOffset(0, 26)
tabList.Size = UDim2.new(1, 0, 1, -26)

local tabLayout = Instance.new("UIListLayout")
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabList

-- === Search and filter ======================================================

-- The middle column is a parchment inset; its padding keeps everything in it
-- clear of the inset's border.
local listColumn = PixelUI.image(window, "inset_parchment")
listColumn.Name = "Recipes"
listColumn.Position = UDim2.fromOffset(L.listX, L.bodyTop)
listColumn.Size = UDim2.fromOffset(L.listWidth, L.bodyHeight)
PixelUI.padTo(listColumn, "inset_parchment", 4)

local searchField = PixelUI.image(listColumn, "input")
searchField.Name = "Search"
searchField.Size = UDim2.new(1, -(L.filterWidth + 8), 0, L.searchHeight)
searchField.ImageColor3 = SEARCH_IDLE

-- The kit's magnifier, at two texels a pixel so it fits the box.
local lens = PixelUI.image(searchField, "icon_search", 2)
lens.Name = "Lens"
lens.AnchorPoint = Vector2.new(0, 0.5)
lens.Position = UDim2.new(0, 10, 0.5, 0)

local searchBox = Instance.new("TextBox")
searchBox.Name = "Box"
searchBox.BackgroundTransparency = 1
searchBox.Position = UDim2.fromOffset(38, 0)
searchBox.Size = UDim2.new(1, -38 - 30, 1, 0)
searchBox.FontFace = Theme.Fonts.Body
searchBox.TextSize = Theme.TextSize.Body
searchBox.TextColor3 = P.Ink
searchBox.PlaceholderText = "Search recipes"
searchBox.PlaceholderColor3 = P.InkFaint
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.Text = ""
searchBox.Parent = searchField

local clearSearch = button(searchField, "Clear")
clearSearch.AnchorPoint = Vector2.new(1, 0.5)
clearSearch.Position = UDim2.new(1, -8, 0.5, 0)
clearSearch.Size = UDim2.fromOffset(22, 22)
clearSearch.BackgroundTransparency = 1
clearSearch.Visible = false

local clearGlyph = text(clearSearch, "Glyph", Theme.Fonts.Heading, Theme.TextSize.Subheading, P.InkSoft)
clearGlyph.Size = UDim2.fromScale(1, 1)
clearGlyph.TextXAlignment = Enum.TextXAlignment.Center
clearGlyph.Text = "\u{00D7}"

-- "Craftable": a checkbox that hides everything you cannot make right now.
local filterChip = button(listColumn, "CraftableOnly")
filterChip.AnchorPoint = Vector2.new(1, 0)
filterChip.Position = UDim2.new(1, 0, 0, 0)
filterChip.Size = UDim2.fromOffset(L.filterWidth, L.searchHeight)
filterChip.BackgroundTransparency = 1

local filterBox = PixelUI.image(filterChip, "checkbox_off")
filterBox.Name = "Box"
filterBox.AnchorPoint = Vector2.new(0, 0.5)
filterBox.Position = UDim2.new(0, 4, 0.5, 0)

local filterLabel = text(filterChip, "Label", Theme.Fonts.BodyBold, Theme.TextSize.Small, P.InkSoft)
filterLabel.Position = UDim2.fromOffset(46, 0)
filterLabel.Size = UDim2.new(1, -46, 1, 0)
filterLabel.Text = "Craftable"

-- === Recipe list ============================================================

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(0, L.searchHeight + 10)
list.Size = UDim2.new(1, 0, 1, -(L.searchHeight + 10))
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Parent = listColumn
PixelUI.styleScrollBar(list)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, L.rowGap)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

-- Room for the selected row's border, and for the scroll bar.
local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 2)
listPadding.PaddingLeft = UDim.new(0, 2)
listPadding.PaddingRight = UDim.new(0, 12)
listPadding.PaddingBottom = UDim.new(0, 2)
listPadding.Parent = list

-- The "nothing here" note. On the column, not in the list, which would lay it
-- out as a row.
local emptyNote = frame(listColumn, "Empty")
emptyNote.AnchorPoint = Vector2.new(0.5, 0)
emptyNote.Position = UDim2.new(0.5, 0, 0, L.searchHeight + 60)
emptyNote.Size = UDim2.new(1, -40, 0, 70)
emptyNote.Visible = false

local emptyTitle = text(emptyNote, "Title", Theme.Fonts.BodyBold, Theme.TextSize.Subheading, P.InkSoft)
emptyTitle.Size = UDim2.new(1, 0, 0, 24)
emptyTitle.TextXAlignment = Enum.TextXAlignment.Center

local emptyHint = text(emptyNote, "Hint", Theme.Fonts.Body, Theme.TextSize.Small, P.InkFaint)
emptyHint.Position = UDim2.fromOffset(0, 28)
emptyHint.Size = UDim2.new(1, 0, 0, 40)
emptyHint.TextXAlignment = Enum.TextXAlignment.Center
emptyHint.TextYAlignment = Enum.TextYAlignment.Top
emptyHint.TextWrapped = true

-- === Detail =================================================================

local detail = PixelUI.image(window, "inset_parchment")
detail.Name = "Detail"
detail.Position = UDim2.fromOffset(L.detailX, L.bodyTop)
detail.Size = UDim2.fromOffset(L.detailWidth, L.bodyHeight)

local detailBody = frame(detail, "Body")
detailBody.Position = UDim2.fromOffset(L.detailPad, L.detailPad)
detailBody.Size = UDim2.new(1, -L.detailPad * 2, 1, -L.detailPad * 2)

-- The hero: what the recipe makes, large, in a wooden well that glows in its
-- rarity's colour.
local hero = PixelUI.image(detailBody, "inset_wood")
hero.Name = "Hero"
hero.Size = UDim2.new(1, 0, 0, L.heroHeight)

-- Inside the well's border, so the glow never paints over the frame art.
local heroInset = (PixelUI.border("inset_wood"))
local heroGlow = frame(hero, "Glow", Theme.Color.TextDim, 0)
heroGlow.Position = UDim2.fromOffset(heroInset, heroInset)
heroGlow.Size = UDim2.new(1, -heroInset * 2, 1, -heroInset * 2)

local heroGlowFade = Instance.new("UIGradient")
heroGlowFade.Rotation = 90
heroGlowFade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.55, 0.82),
	NumberSequenceKeypoint.new(1, 0.55),
})
heroGlowFade.Parent = heroGlow

local heroIcon = Instance.new("ImageLabel")
heroIcon.Name = "Icon"
heroIcon.BackgroundTransparency = 1
heroIcon.AnchorPoint = Vector2.new(0.5, 0.5)
heroIcon.Position = UDim2.fromScale(0.5, 0.5)
heroIcon.Size = UDim2.fromOffset(96, 96)
heroIcon.ZIndex = 2
heroIcon.Parent = hero

local heroCount = text(hero, "Count", Theme.Fonts.Number, Theme.TextSize.Subheading, Color3.new(1, 1, 1))
heroCount.AnchorPoint = Vector2.new(1, 1)
heroCount.Position = UDim2.new(1, -10, 1, -6)
heroCount.Size = UDim2.fromOffset(80, 24)
heroCount.TextXAlignment = Enum.TextXAlignment.Right
heroCount.TextStrokeTransparency = 0.4
heroCount.ZIndex = 3

local nameLabel = text(detailBody, "Name", Theme.Fonts.Heading, Theme.TextSize.Heading, P.Ink)
nameLabel.Position = UDim2.fromOffset(0, L.heroHeight + 10)
nameLabel.Size = UDim2.new(1, 0, 0, 26)
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- Two small pills: rarity, and where it is made. The kit's dark badge, as
-- tall as its art.
local CHIP_HEIGHT = PixelUI.get("badge").size.Y * PixelUI.Scale

local chips = frame(detailBody, "Chips")
chips.Position = UDim2.fromOffset(0, L.heroHeight + 40)
chips.Size = UDim2.new(1, 0, 0, CHIP_HEIGHT)

local chipLayout = Instance.new("UIListLayout")
chipLayout.FillDirection = Enum.FillDirection.Horizontal
chipLayout.Padding = UDim.new(0, 6)
chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
chipLayout.Parent = chips

local function newChip(name, order)
	local chip = PixelUI.image(chips, "badge")
	chip.Name = name
	chip.Size = UDim2.fromOffset(0, CHIP_HEIGHT)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.LayoutOrder = order

	local chipPadding = Instance.new("UIPadding")
	chipPadding.PaddingLeft = UDim.new(0, 12)
	chipPadding.PaddingRight = UDim.new(0, 12)
	chipPadding.Parent = chip

	local label = text(chip, "Label", Theme.Fonts.BodyBold, 13, P.OnWood)
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X

	return chip, label
end

local rarityChip, rarityLabel = newChip("Rarity", 1)
local stationChip, stationLabel = newChip("Station", 2)

local description = text(detailBody, "Description", Theme.Fonts.Body, Theme.TextSize.Small, P.InkSoft)
description.Position = UDim2.fromOffset(0, L.heroHeight + 74)
description.Size = UDim2.new(1, 0, 0, 36)
description.TextWrapped = true
description.TextYAlignment = Enum.TextYAlignment.Top
description.TextTruncate = Enum.TextTruncate.AtEnd

local requiresCaption = text(detailBody, "RequiresCaption", Theme.Fonts.BodyBold, Theme.TextSize.Small, P.Heading)
requiresCaption.Position = UDim2.fromOffset(0, L.heroHeight + 116)
requiresCaption.Size = UDim2.new(1, 0, 0, 16)
requiresCaption.Text = "REQUIRES"

local footerHeight = L.stepperHeight + 10 + L.buttonHeight
local ingredientsTop = L.heroHeight + 136

local ingredients = Instance.new("ScrollingFrame")
ingredients.Name = "Ingredients"
ingredients.BackgroundTransparency = 1
ingredients.BorderSizePixel = 0
ingredients.Position = UDim2.fromOffset(0, ingredientsTop)
ingredients.Size = UDim2.new(1, 0, 1, -(ingredientsTop + footerHeight + 10))
ingredients.CanvasSize = UDim2.new()
ingredients.AutomaticCanvasSize = Enum.AutomaticSize.Y
ingredients.ScrollingDirection = Enum.ScrollingDirection.Y
ingredients.Parent = detailBody
PixelUI.styleScrollBar(ingredients)

local ingredientLayout = Instance.new("UIListLayout")
ingredientLayout.Padding = UDim.new(0, 4)
ingredientLayout.SortOrder = Enum.SortOrder.LayoutOrder
ingredientLayout.Parent = ingredients

-- Quantity: - [n] + MAX, and how many could be made.
local stepper = frame(detailBody, "Quantity")
stepper.AnchorPoint = Vector2.new(0, 1)
stepper.Position = UDim2.new(0, 0, 1, -(L.buttonHeight + 10))
stepper.Size = UDim2.new(1, 0, 0, L.stepperHeight)

-- Small tan buttons; their clicks are wired further down, with the rest.
local function stepButton(name, label, x, width)
	local handle = PixelUI.button(stepper, {
		name = name,
		text = label,
		textSize = Theme.TextSize.Body,
		size = UDim2.fromOffset(width, L.stepperHeight),
	})
	handle.button.Position = UDim2.fromOffset(x, 0)
	return handle.button, handle.label
end

local minusButton = stepButton("Less", "-", 0, L.stepperHeight)
local quantityLabel = text(stepper, "Value", Theme.Fonts.Number, Theme.TextSize.Subheading, P.Ink)
quantityLabel.Position = UDim2.fromOffset(L.stepperHeight, 0)
quantityLabel.Size = UDim2.fromOffset(44, L.stepperHeight)
quantityLabel.TextXAlignment = Enum.TextXAlignment.Center
local plusButton = stepButton("More", "+", L.stepperHeight + 44, L.stepperHeight)
local maxButton, maxGlyph = stepButton("Max", "MAX", L.stepperHeight * 2 + 52, 58)
maxGlyph.TextSize = Theme.TextSize.Small

local canMakeLabel = text(stepper, "CanMake", Theme.Fonts.Body, Theme.TextSize.Small, P.InkSoft)
canMakeLabel.AnchorPoint = Vector2.new(1, 0)
canMakeLabel.Position = UDim2.new(1, 0, 0, 0)
canMakeLabel.Size = UDim2.fromOffset(90, L.stepperHeight)
canMakeLabel.TextXAlignment = Enum.TextXAlignment.Right

-- The craft button. Green when it will work; grey when it will not, saying why.
local craft = PixelUI.button(detailBody, {
	name = "Craft",
	color = "green",
	textSize = Theme.TextSize.Subheading,
	size = UDim2.new(1, 0, 0, L.buttonHeight),
})
local craftButton = craft.button
local craftLabel = craft.label
craftButton.Position = UDim2.new(0, 0, 1, -L.buttonHeight)
craftLabel.ZIndex = 2

-- Fills left to right while a batch is being made: a pale wash over the face,
-- under the label.
-- Inside the outline, so the wash never paints over the button's edge.
local craftTrack = frame(craft.content, "Track")
craftTrack.Position = UDim2.fromOffset(PixelUI.Scale, PixelUI.Scale)
craftTrack.Size = UDim2.new(1, -PixelUI.Scale * 2, 1, -PixelUI.Scale * 2)

local craftProgress = frame(craftTrack, "Progress", Color3.new(1, 1, 1), 0.72)
craftProgress.Size = UDim2.fromScale(0, 1)

-- The detail panel's empty state.
local noSelection = text(detail, "NoSelection", Theme.Fonts.Body, Theme.TextSize.Body, P.InkFaint)
noSelection.Size = UDim2.fromScale(1, 1)
noSelection.TextXAlignment = Enum.TextXAlignment.Center
noSelection.Text = "Pick a recipe"
noSelection.Visible = false

-- === Toast ==================================================================

-- Results appear as a pill just under the window, where they do not cover the
-- thing being crafted.
local toast = PixelUI.image(root, "tooltip")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 1, 14)
toast.Size = UDim2.fromOffset(0, 40)
toast.AutomaticSize = Enum.AutomaticSize.X
toast.ImageTransparency = 1

local toastPadding = Instance.new("UIPadding")
toastPadding.PaddingLeft = UDim.new(0, 20)
toastPadding.PaddingRight = UDim.new(0, 20)
toastPadding.Parent = toast

local toastLabel = text(toast, "Label", Theme.Fonts.BodyBold, Theme.TextSize.Body, P.OnWood)
toastLabel.Size = UDim2.fromScale(0, 1)
toastLabel.AutomaticSize = Enum.AutomaticSize.X
toastLabel.TextTransparency = 1

local toastToken = 0

local function showToast(message, tone)
	toastToken += 1
	local token = toastToken

	toastLabel.Text = message
	toastLabel.TextColor3 = if tone == "bad" then P.BadLight elseif tone == "good" then P.GoodLight else P.OnWood

	TweenService:Create(toast, Theme.Tween.Fade, { ImageTransparency = 0 }):Play()
	TweenService:Create(toastLabel, Theme.Tween.Fade, { TextTransparency = 0 }):Play()

	task.delay(TOAST_SECONDS, function()
		if token ~= toastToken then
			return
		end
		TweenService:Create(toast, Theme.Tween.Fade, { ImageTransparency = 1 }):Play()
		TweenService:Create(toastLabel, Theme.Tween.Fade, { TextTransparency = 1 }):Play()
	end)
end

local function hideToast()
	toastToken += 1
	toast.ImageTransparency = 1
	toastLabel.TextTransparency = 1
end

-- ---------------------------------------------------------------------------
-- Fitting to the screen
-- ---------------------------------------------------------------------------

local function fit()
	local size = screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local scale = math.min(
		math.max(1, size.Y / DESIGN_HEIGHT),
		size.Y * 0.88 / L.height,
		size.X * 0.94 / L.width
	)
	rootScale.Scale = math.max(scale, MIN_SCALE)
end

screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local refreshDetail
local selectRecipe
local refreshTabs

local function refreshFilterChip()
	PixelUI.apply(filterBox, if craftableOnly then "checkbox_on" else "checkbox_off")
	filterLabel.TextColor3 = if craftableOnly then P.Ink else P.InkSoft
end

-- What a row looks like for its state: chosen, under the cursor, affordable.
local function paintRow(entry)
	local selected = selectedRecipe ~= nil and selectedRecipe.id == entry.recipe.id
	local affordable = canAfford(entry.recipe)

	PixelUI.apply(entry.button, if selected then "row_selected" elseif entry.hovered then "row_hover" else "row")

	entry.tile.ImageColor3 = if affordable then Color3.new(1, 1, 1) else P.Disabled
	entry.icon.ImageTransparency = if affordable then 0 else 0.45
	entry.name.TextColor3 = if affordable then P.Ink else P.InkSoft

	local possible = craftableCount(entry.recipe)
	if possible > 0 then
		entry.badge.Text = "\u{00D7}" .. tostring(math.min(possible, 999))
		entry.badge.TextColor3 = P.GoodLight
	else
		entry.badge.Text = "Need"
		entry.badge.TextColor3 = P.OnWoodDim
	end

	for _, chip in ipairs(entry.costs) do
		chip.label.TextColor3 = if held(chip.item) >= chip.count then P.InkSoft else P.Bad
	end
end

local function paintRows()
	for _, entry in pairs(rows) do
		paintRow(entry)
	end
end

local function newRow(recipe, order)
	local entry = { recipe = recipe, hovered = false, costs = {} }

	local row = Instance.new("ImageButton")
	row.Name = recipe.id
	row.AutoButtonColor = false
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, L.rowHeight)
	row.LayoutOrder = order
	row.Parent = list
	PixelUI.apply(row, "row")
	entry.button = row

	local tile, icon, count = newSlotTile(row, 48)
	tile.Position = UDim2.fromOffset(7, (L.rowHeight - 48) / 2)
	showItem(icon, recipe.output.item)
	count.Text = if recipe.output.count > 1 then tostring(recipe.output.count) else ""
	entry.tile, entry.icon = tile, icon

	local name = text(row, "Name", Theme.Fonts.BodyBold, Theme.TextSize.Body, P.Ink)
	name.Position = UDim2.fromOffset(66, 9)
	name.Size = UDim2.new(1, -66 - 64, 0, 20)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = displayName(recipe.output.item)
	entry.name = name

	-- What it costs, as a strip of small icons with counts.
	local costs = frame(row, "Costs")
	costs.Position = UDim2.fromOffset(66, 33)
	costs.Size = UDim2.new(1, -66 - 64, 0, 18)

	local costLayout = Instance.new("UIListLayout")
	costLayout.FillDirection = Enum.FillDirection.Horizontal
	costLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	costLayout.Padding = UDim.new(0, 8)
	costLayout.SortOrder = Enum.SortOrder.LayoutOrder
	costLayout.Parent = costs

	for index, ingredient in ipairs(recipe.ingredients) do
		if index > 4 then
			local more = text(costs, "More", Theme.Fonts.Body, 13, P.InkFaint)
			more.Size = UDim2.fromOffset(28, 18)
			more.LayoutOrder = index
			more.Text = string.format("+%d", #recipe.ingredients - 4)
			break
		end

		local cost = frame(costs, ingredient.item)
		cost.Size = UDim2.fromOffset(0, 18)
		cost.AutomaticSize = Enum.AutomaticSize.X
		cost.LayoutOrder = index

		local mini = Instance.new("ImageLabel")
		mini.Name = "Icon"
		mini.BackgroundTransparency = 1
		mini.Size = UDim2.fromOffset(18, 18)
		mini.Parent = cost
		ItemThumbnails.bind(mini, ingredient.item)

		local amount = text(cost, "Count", Theme.Fonts.Number, 13, P.InkSoft)
		amount.Position = UDim2.fromOffset(20, 0)
		amount.Size = UDim2.fromOffset(0, 18)
		amount.AutomaticSize = Enum.AutomaticSize.X
		amount.Text = tostring(ingredient.count)

		table.insert(entry.costs, { item = ingredient.item, count = ingredient.count, label = amount })
	end

	-- How many you could make, on the right, on the kit's dark pill.
	local badgeFrame = PixelUI.image(row, "badge")
	badgeFrame.Name = "Badge"
	badgeFrame.AnchorPoint = Vector2.new(1, 0.5)
	badgeFrame.Position = UDim2.new(1, -14, 0.5, 0)
	badgeFrame.Size = UDim2.fromOffset(54, CHIP_HEIGHT)
	entry.badgeFrame = badgeFrame

	local badge = text(badgeFrame, "Label", Theme.Fonts.Number, 13, P.GoodLight)
	badge.Size = UDim2.fromScale(1, 1)
	badge.TextXAlignment = Enum.TextXAlignment.Center
	entry.badge = badge

	row.MouseEnter:Connect(function()
		entry.hovered = true
		paintRow(entry)
		Sounds.play("ui.hover")
	end)
	row.MouseLeave:Connect(function()
		entry.hovered = false
		paintRow(entry)
	end)
	row.MouseButton1Click:Connect(function()
		if not (selectedRecipe and selectedRecipe.id == recipe.id) then
			Sounds.play("ui.click")
			selectRecipe(recipe)
		end
	end)

	rows[recipe.id] = entry
	return entry
end

local function clearList()
	for _, entry in pairs(rows) do
		-- Destroying releases each row's live view back to ItemPreview's cap.
		entry.button:Destroy()
	end
	table.clear(rows)
	table.clear(visibleRecipes)
end

--[[
	Rebuilds the list for the active station, search and filter.

	Recipes you can make right now come first, in book order, then the rest.
	Sorted here only, never on an inventory change: a list that reshuffles
	itself while you are crafting from it moves the row out from under the
	cursor.
]]
local function buildList()
	clearList()

	local all = RecipeBook.getForStation(activeStation)
	local ready, rest = {}, {}
	for _, recipe in ipairs(all) do
		if matchesSearch(recipe) then
			if canAfford(recipe) then
				table.insert(ready, recipe)
			elseif not craftableOnly then
				table.insert(rest, recipe)
			end
		end
	end

	for _, recipe in ipairs(ready) do
		table.insert(visibleRecipes, recipe)
	end
	for _, recipe in ipairs(rest) do
		table.insert(visibleRecipes, recipe)
	end

	for order, recipe in ipairs(visibleRecipes) do
		newRow(recipe, order)
	end

	list.CanvasPosition = Vector2.zero

	local empty = #visibleRecipes == 0
	emptyNote.Visible = empty
	if empty then
		if searchQuery ~= "" then
			emptyTitle.Text = "No matches"
			emptyHint.Text = string.format("Nothing here is called \"%s\".", searchBox.Text)
		elseif craftableOnly and #all > 0 then
			emptyTitle.Text = "Nothing you can make yet"
			emptyHint.Text = "Turn off Craftable to see every recipe here and what each one needs."
		else
			emptyTitle.Text = "No recipes"
			emptyHint.Text = if activeStation
				then string.format("Nothing is made at the %s yet.", StationConfig.getDisplayName(activeStation))
				else "There are no hand recipes yet."
		end
		selectRecipe(nil)
		return
	end

	-- Keep the current choice if it survived the filter, so typing does not
	-- yank the detail panel away mid-read.
	local keep = nil
	if selectedRecipe then
		for _, recipe in ipairs(visibleRecipes) do
			if recipe.id == selectedRecipe.id then
				keep = recipe
				break
			end
		end
	end

	selectRecipe(keep or visibleRecipes[1])
end

local function newIngredientRow(ingredient, order)
	local row = PixelUI.image(ingredients, "row")
	row.Name = ingredient.item
	row.Size = UDim2.new(1, -4, 0, L.ingredientHeight)
	row.LayoutOrder = order

	-- The wooden slot, so the cost reads apart from the recipe's own tiles.
	local tile, icon = newSlotTile(row, 34)
	SlotArt.apply(tile, "dark")
	tile.Position = UDim2.fromOffset(6, (L.ingredientHeight - 34) / 2)
	ItemThumbnails.bind(icon, ingredient.item, function(image)
		if image == "" then
			ItemPreview.fillSlot(icon, ingredient.item)
		end
	end)

	local have = held(ingredient.item)
	local enough = have >= ingredient.count

	local name = text(row, "Name", Theme.Fonts.Body, Theme.TextSize.Small, if enough then P.Ink else P.InkSoft)
	name.Position = UDim2.fromOffset(48, 8)
	name.Size = UDim2.new(1, -48 - 76, 0, 18)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = displayName(ingredient.item)

	local tally = text(row, "Tally", Theme.Fonts.Number, Theme.TextSize.Count, if enough then P.Good else P.Bad)
	tally.AnchorPoint = Vector2.new(1, 0)
	tally.Position = UDim2.new(1, -12, 0, 7)
	tally.Size = UDim2.fromOffset(70, 18)
	tally.TextXAlignment = Enum.TextXAlignment.Right
	tally.Text = string.format("%d / %d", math.min(have, 9999), ingredient.count)

	-- How far along you are, under the name: a groove that fills. Square ends,
	-- like everything else drawn in texels.
	local track = frame(row, "Track", GROOVE, 0.35)
	track.Position = UDim2.new(0, 48, 0, 30)
	track.Size = UDim2.new(1, -60, 0, PixelUI.Scale * 2)

	local fill = frame(track, "Fill", if enough then P.Good else P.Bad, 0)
	fill.Size = UDim2.fromScale(math.clamp(have / math.max(ingredient.count, 1), 0, 1), 1)
end

local function refreshIngredients(recipe)
	for _, child in ipairs(ingredients:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if recipe then
		for order, ingredient in ipairs(recipe.ingredients) do
			newIngredientRow(ingredient, order)
		end
	end
end

-- The most the stepper will go to: what can be afforded, within one batch.
local function quantityLimit()
	return math.clamp(craftableCount(selectedRecipe), 1, MAX_BATCH)
end

local function refreshCraftButton()
	local recipe = selectedRecipe
	if not recipe then
		return
	end

	local affordable = canAfford(recipe)
	local reachable = inRange(recipe.station)
	quantity = math.clamp(quantity, 1, quantityLimit())

	quantityLabel.Text = tostring(quantity)
	local possible = craftableCount(recipe)
	canMakeLabel.Text = if possible > 0 then string.format("Can make %d", math.min(possible, 999)) else ""

	local ready = affordable and batch == nil

	if batch then
		craftLabel.Text = string.format("CRAFTING %d / %d", batch.done, batch.total)
	elseif not affordable then
		craftLabel.Text = "NEED MATERIALS"
	elseif not reachable then
		-- Still clickable: this is the client's guess at range, and the server
		-- has the final word. It just warns before the attempt.
		craftLabel.Text = string.format("GO TO A %s", string.upper(StationConfig.getDisplayName(recipe.station)))
	elseif quantity > 1 then
		craftLabel.Text = string.format("CRAFT \u{00D7}%d", quantity)
	else
		craftLabel.Text = "CRAFT"
	end

	local lit = ready and reachable
	craft.setStyle(if lit or batch then "green" else "disabled")
	craftProgress.Size = UDim2.fromScale(if batch then batch.done / batch.total else 0, 1)

	minusButton.Visible = affordable
	plusButton.Visible = affordable
	maxButton.Visible = affordable
	quantityLabel.Visible = affordable
end

function refreshDetail()
	local recipe = selectedRecipe

	detailBody.Visible = recipe ~= nil
	noSelection.Visible = recipe == nil

	if not recipe then
		ItemPreview.releaseSlot(heroIcon)
		ItemThumbnails.bind(heroIcon, nil)
		refreshIngredients(nil)
		paintRows()
		return
	end

	local item = recipe.output.item
	local def = ItemDefinitions[item]
	local rarity = rarityOf(item)
	local rarityColor = Theme.rarityColor(rarity)

	showItem(heroIcon, item)
	heroGlow.BackgroundColor3 = rarityColor
	heroCount.Text = if recipe.output.count > 1 then "\u{00D7}" .. tostring(recipe.output.count) else ""

	nameLabel.Text = displayName(item)
	nameLabel.TextColor3 = if Theme.rarityRank(rarity) > 1 then Theme.rarityInk(rarity) else P.Ink

	-- On the dark pills, so the rarity's own colour, lifted a little.
	rarityLabel.Text = string.upper(rarity)
	rarityLabel.TextColor3 = rarityColor:Lerp(Color3.new(1, 1, 1), 0.35)

	stationLabel.Text = if recipe.station then StationConfig.getDisplayName(recipe.station) else "By hand"
	stationLabel.TextColor3 = if inRange(recipe.station) then P.OnWood else P.OnWoodDim

	-- A weapon's class line ("Sword -> Longsword") heads its description.
	description.Text = WeaponClasses.description(def)

	refreshIngredients(recipe)
	refreshCraftButton()
	paintRows()
end

function selectRecipe(recipe)
	if not (selectedRecipe and recipe and selectedRecipe.id == recipe.id) then
		quantity = 1
	end
	selectedRecipe = recipe
	refreshDetail()
end

-- ---------------------------------------------------------------------------
-- Stations
-- ---------------------------------------------------------------------------

local setStation

local function stationIds()
	local ids = { StationConfig.HandStation }
	for _, id in ipairs(StationConfig.Order) do
		table.insert(ids, id)
	end
	return ids
end

local function buildTabs()
	for order, id in ipairs(stationIds()) do
		local stationId = if id == StationConfig.HandStation then nil else id
		local tab = { stationId = stationId, active = false, hovered = false }

		-- A kit button: tan, and green while it is the station shown. What is
		-- drawn on its face sits in `content`, which drops with the face when
		-- it is pressed.
		local b = Instance.new("ImageButton")
		b.Name = id
		b.AutoButtonColor = false
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		b.Size = UDim2.new(1, 0, 0, L.tabHeight)
		b.LayoutOrder = order
		b.Parent = tabList
		tab.button = b

		local content = frame(b, "Content")
		content.Size = UDim2.new(1, 0, 1, -PixelUI.Scale * 2)
		tab.look = PixelUI.bindButton(b, "tan", content)

		-- Square, outlined in the frame art's dark brown: a texel swatch.
		local dot = frame(content, "Swatch", stationColor(stationId))
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 14, 0.5, 0)
		dot.Size = UDim2.fromOffset(12, 12)
		stroke(dot, Color3.fromRGB(43, 24, 16), 2, 0)

		local name = text(content, "Name", Theme.Fonts.Body, Theme.TextSize.Body, P.Ink)
		name.Position = UDim2.fromOffset(36, 6)
		name.Size = UDim2.new(1, -36 - 50, 0, 20)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = if stationId then StationConfig.getDisplayName(stationId) else "By Hand"
		tab.name = name

		local state = text(content, "State", Theme.Fonts.Body, 13, P.InkSoft)
		state.Position = UDim2.fromOffset(36, 26)
		state.Size = UDim2.new(1, -36 - 50, 0, 16)
		tab.state = state

		-- How many of its recipes you can make right now, of how many.
		local count = text(content, "Count", Theme.Fonts.Number, 13, P.InkSoft)
		count.AnchorPoint = Vector2.new(1, 0.5)
		count.Position = UDim2.new(1, -14, 0.5, 0)
		count.Size = UDim2.fromOffset(40, 18)
		count.TextXAlignment = Enum.TextXAlignment.Right
		tab.count = count

		b.MouseEnter:Connect(function()
			tab.hovered = true
			refreshTabs()
			Sounds.play("ui.hover")
		end)
		b.MouseLeave:Connect(function()
			tab.hovered = false
			refreshTabs()
		end)
		b.MouseButton1Click:Connect(function()
			if not tab.active then
				Sounds.play("ui.tab")
				setStation(stationId)
			end
		end)

		tabs[id] = tab
	end
end

function refreshTabs()
	for _, tab in pairs(tabs) do
		local stationId = tab.stationId

		-- Green is the station shown; its text is the dark green that reads on
		-- it, and every other tab is ink on tan.
		tab.look.setStyle(if tab.active then "green" else "tan")
		tab.name.FontFace = if tab.active then Theme.Fonts.BodyBold else Theme.Fonts.Body
		tab.name.TextColor3 = if tab.active then P.OnGreen else P.Ink

		if stationId == nil then
			tab.state.Text = "Anywhere"
			tab.state.TextColor3 = if tab.active then P.OnGreen else P.InkSoft
		elseif nearby[stationId] then
			tab.state.Text = "In range"
			tab.state.TextColor3 = if tab.active then P.OnGreen else P.Good
		else
			tab.state.Text = "Not nearby"
			tab.state.TextColor3 = if tab.active then P.OnGreen else P.InkSoft
		end

		local recipes = RecipeBook.getForStation(stationId)
		local ready = 0
		for _, recipe in ipairs(recipes) do
			if canAfford(recipe) then
				ready += 1
			end
		end
		tab.count.Text = string.format("%d/%d", ready, #recipes)
		tab.count.TextColor3 = if tab.active then P.OnGreen elseif ready > 0 then P.Good else P.InkSoft
	end
end

local function refreshHeader()
	-- Tinted toward the station's colour, but kept light: a full-strength
	-- multiply would sink the parchment slot to near black.
	stationBadge.ImageColor3 = stationColor(activeStation):Lerp(Color3.new(1, 1, 1), 0.3)

	local name = if activeStation then StationConfig.getDisplayName(activeStation) else "By Hand"
	badgeLetter.Text = if activeStation then string.upper(string.sub(name, 1, 1)) else "H"
	title.Text = if activeStation then name else "Crafting"

	if activeStation == nil then
		subtitle.Text = "Hand recipes - craft these anywhere"
		subtitle.TextColor3 = P.OnWoodDim
	elseif nearby[activeStation] then
		subtitle.Text = string.format("At a %s", name)
		subtitle.TextColor3 = P.GoodLight
	else
		subtitle.Text = string.format("Stand near a %s to craft these", name)
		subtitle.TextColor3 = P.OnWoodDim
	end
end

function setStation(stationId)
	activeStation = stationId

	for _, tab in pairs(tabs) do
		tab.active = tab.stationId == stationId
	end

	refreshTabs()
	refreshHeader()
	buildList()
end

-- ---------------------------------------------------------------------------
-- Stations in range
-- ---------------------------------------------------------------------------

--[[
	Which placed stations are within their use range of the player. The same
	test the server makes - distance from the station's centre to the root
	part, against StationConfig.useRange - from the stations StationService
	puts in the world with a StationId attribute. A guess the server confirms;
	the window only uses it to say where you are.
]]
local function scanNearby(): boolean
	local found = {}

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local folder = workspace:FindFirstChild(StationConfig.WorldFolderName or "CraftingStations")

	if root and folder then
		local position = root.Position
		for _, station in ipairs(folder:GetChildren()) do
			local id = station:GetAttribute("StationId")
			local def = type(id) == "string" and StationConfig.get(id)
			if def and not found[id] then
				local centre = if station:IsA("Model")
					then station:GetPivot().Position
					elseif station:IsA("BasePart") then station.Position
					else nil
				if centre and (centre - position).Magnitude <= def.useRange then
					found[id] = true
				end
			end
		end
	end

	local changed = false
	for id in pairs(found) do
		if not nearby[id] then
			changed = true
		end
	end
	for id in pairs(nearby) do
		if not found[id] then
			changed = true
		end
	end

	nearby = found
	return changed
end

-- ---------------------------------------------------------------------------
-- Crafting
-- ---------------------------------------------------------------------------

local function finishBatch(message, tone)
	batch = nil
	if message then
		showToast(message, tone)
	end
	refreshCraftButton()
end

local function sendNext()
	if not batch then
		return
	end
	batch.sentAt = os.clock()
	log("craft request", batch.recipe.id, batch.done + 1, "/", batch.total)
	RequestCraft:FireServer(batch.recipe.id)
end

-- One place that starts a craft, so the button and the Enter key cannot
-- drift into behaving differently.
local function requestCraft()
	local recipe = selectedRecipe
	if not recipe or batch then
		return
	end

	if not canAfford(recipe) then
		Sounds.play("ui.denied")
		Motion.shake(detail, 6)
		showToast("Not enough materials", "bad")
		return
	end

	batch = {
		recipe = recipe,
		total = math.clamp(quantity, 1, quantityLimit()),
		done = 0,
		sentAt = os.clock(),
	}
	refreshCraftButton()
	sendNext()
end

CraftingResult.OnClientEvent:Connect(function(ok, recipeId, message)
	log("craft result", ok, recipeId, message)

	-- A result for something other than the running batch - a stale reply
	-- after a cancel - only gets reported.
	if not batch or recipeId ~= batch.recipe.id then
		if not ok and message then
			showToast(message, "bad")
		end
		return
	end

	if not ok then
		Sounds.play("craft.fail")
		Motion.shake(detail, 6)
		local made = batch.done
		finishBatch(
			if made > 0 then string.format("Made %d, then: %s", made, tostring(message)) else tostring(message),
			"bad"
		)
		return
	end

	batch.done += 1
	Sounds.play("craft.success")
	Motion.pulse(hero, 1.06)
	refreshCraftButton()

	if batch.done >= batch.total then
		local recipe = batch.recipe
		local made = batch.done * recipe.output.count
		finishBatch(
			if made > 1
				then string.format("Crafted %d \u{00D7} %s", made, displayName(recipe.output.item))
				else string.format("Crafted %s", displayName(recipe.output.item)),
			"good"
		)
		return
	end

	task.delay(CRAFT_GAP, sendNext)
end)

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------

local function fadeShadows(visible, info)
	for _, layer in ipairs(shadows) do
		TweenService:Create(layer.frame, info, {
			BackgroundTransparency = if visible then layer.transparency else 1,
		}):Play()
	end
end

local function open(stationId)
	log("open", stationId or "Hand")

	local wasOpen = isOpen
	isOpen = true
	screen.Enabled = true
	fit()

	scanNearby()
	hideToast()
	setStation(stationId)

	if not wasOpen then
		Sounds.play("ui.open")
		-- Transparent to the end: the frame art is the panel, not a background.
		Motion.openPanel(window, 1)
		fadeShadows(true, Theme.Tween.Open)
		TweenService:Create(backdrop, Theme.Tween.Open, {
			BackgroundTransparency = Theme.Transparency.Backdrop,
		}):Play()
		MenuState.setOpen(MENU_NAME, true)
	end
end

local function close()
	if not isOpen then
		return
	end

	log("close")
	isOpen = false

	-- Reopening on a filter set a session ago, with no memory of having set
	-- it, reads as half the recipes having disappeared.
	if searchBox.Text ~= "" then
		searchBox.Text = ""
	end
	searchBox:ReleaseFocus()

	Sounds.play("ui.close")
	TweenService:Create(backdrop, Theme.Tween.Close, { BackgroundTransparency = 1 }):Play()
	fadeShadows(false, Theme.Tween.Close)
	hideToast()

	Motion.closePanel(window, function()
		if not isOpen then
			screen.Enabled = false
			-- Hand back the live views; the inventory wants them more.
			clearList()
			ItemPreview.releaseSlot(heroIcon)
		end
	end)

	MenuState.setOpen(MENU_NAME, false)
end

local function toggle(stationId)
	if isOpen and stationId == activeStation then
		close()
	else
		open(stationId)
	end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

-- The kit's buttons show hover and press themselves, and are never scaled -
-- a stretched texel looks like a mistake - so these only decide what a click
-- does.
craftButton.MouseButton1Click:Connect(function()
	if not (selectedRecipe ~= nil and canAfford(selectedRecipe) and batch == nil) then
		Sounds.play("ui.denied")
		if not batch then
			Motion.shake(detail, 6)
			showToast("Not enough materials", "bad")
		end
		return
	end
	Sounds.play("ui.click")
	requestCraft()
end)

closeButton.MouseButton1Click:Connect(function()
	Sounds.play("ui.click")
	close()
end)

local function stepQuantity(delta)
	local limit = quantityLimit()
	local nextValue = math.clamp(quantity + delta, 1, limit)
	if nextValue == quantity then
		Sounds.play("ui.denied")
		return
	end
	quantity = nextValue
	refreshCraftButton()
end

minusButton.MouseButton1Click:Connect(function()
	Sounds.play("ui.click")
	stepQuantity(-1)
end)
plusButton.MouseButton1Click:Connect(function()
	Sounds.play("ui.click")
	stepQuantity(1)
end)
maxButton.MouseButton1Click:Connect(function()
	Sounds.play("ui.click")
	quantity = quantityLimit()
	refreshCraftButton()
end)

filterChip.MouseButton1Click:Connect(function()
	craftableOnly = not craftableOnly
	Sounds.play("ui.tab")
	refreshFilterChip()
	buildList()
end)

clearSearch.MouseButton1Click:Connect(function()
	Sounds.play("ui.click")
	searchBox.Text = ""
end)

searchBox.Focused:Connect(function()
	searchField.ImageColor3 = SEARCH_FOCUSED
end)

-- Enter in the search box crafts the selection, so a player can type a name
-- and make it without reaching for the mouse.
searchBox.FocusLost:Connect(function(enterPressed)
	searchField.ImageColor3 = SEARCH_IDLE
	if enterPressed and selectedRecipe then
		requestCraft()
	end
end)

-- Rebuilt on every keystroke: a station's list is a few dozen rows at most,
-- the same work a tab change already does.
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	clearSearch.Visible = searchBox.Text ~= ""

	local query = string.lower(searchBox.Text)
	if query == searchQuery then
		return
	end
	searchQuery = query
	buildList()
end)

-- Clicking the dimmed area outside the window closes it. The window is drawn
-- over the backdrop, so clicks on the panel never reach here.
backdrop.InputBegan:Connect(function(input)
	if isOpen and input.UserInputType == Enum.UserInputType.MouseButton1 then
		close()
	end
end)

-- Through the mirror rather than the remote: the wire carries only the slots
-- that moved, and the mirror reassembles the whole bag these totals need.
InventoryMirror.onChanged(function(snapshot)
	table.clear(heldCounts)
	for _, slot in pairs(snapshot or {}) do
		if type(slot) == "table" and slot.name then
			heldCounts[slot.name] = (heldCounts[slot.name] or 0) + (slot.count or 0)
		end
	end

	if isOpen then
		refreshTabs()
		refreshDetail()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	local key = input.KeyCode
	if key == Enum.KeyCode.B then
		toggle(nil)
	elseif not isOpen then
		return
	elseif key == Enum.KeyCode.Escape then
		close()
	elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
		-- Only reached when the search box does not have focus; typing sets
		-- `processed` and the box handles its own Enter.
		requestCraft()
	end
end)

--[[
	Using a placed station's prompt opens the window on that station. The
	prompt carries the station id as an attribute, which keeps this generic: a
	new station type needs no case here.
]]
ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then
		return
	end

	local stationId = prompt:GetAttribute("StationId")
	log("prompt triggered, station =", tostring(stationId))

	if type(stationId) == "string" then
		open(stationId)
	end
end)

-- Two full-screen menus at once is never what anyone wants; the pause menu
-- wins because it is the one with the escape hatch.
MenuState.Changed:Connect(function(name, opened)
	if name == "PauseMenu" and opened and isOpen then
		close()
	end
end)

-- While open: which stations are in range, and a batch that stopped hearing
-- back from the server.
task.spawn(function()
	while true do
		task.wait(PROXIMITY_INTERVAL)

		if isOpen then
			if scanNearby() then
				refreshTabs()
				refreshHeader()
				refreshDetail()
			end

			if batch and os.clock() - batch.sentAt > CRAFT_TIMEOUT then
				finishBatch("Crafting stopped - no answer from the server", "bad")
			end
		end
	end
end)

-- The list itself is built when the window opens, not here: rows take live
-- item views from ItemPreview's shared cap, and a closed window holding them
-- would starve the inventory.
buildTabs()
refreshFilterChip()
RequestFullInventory:FireServer()
