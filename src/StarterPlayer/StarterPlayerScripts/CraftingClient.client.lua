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

	Drawn from Shared.UI.Theme, so it shares the inventory's slot art, fonts,
	rarity colours and selection yellow.
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
	width = 920,
	height = 620,
	pad = 18,
	gutter = 16,
	radius = 12,

	headerHeight = 66,

	sidebarWidth = 200,
	tabHeight = 50,

	searchHeight = 38,
	filterWidth = 112,
	rowHeight = 62,
	rowGap = 6,

	detailWidth = 300,
	detailPad = 14,
	heroHeight = 120,
	ingredientHeight = 38,
	stepperHeight = 32,
	buttonHeight = 48,
}

L.bodyTop = L.headerHeight + 14
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

local C = {
	card = Theme.Color.PanelRaised,
	cardHover = Theme.Color.PanelRaised:Lerp(Color3.new(1, 1, 1), 0.07),
	sunken = Theme.Color.Panel:Lerp(Color3.new(0, 0, 0), 0.3),
	-- Dark text that stays readable on the selection yellow.
	onAccent = Color3.fromRGB(34, 31, 8),
}

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

local window = frame(root, "Window", Theme.Color.Panel, Theme.Transparency.Panel)
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromScale(1, 1)
-- Above the shadow layers, which are its earlier siblings.
window.ZIndex = 2
corner(window, L.radius)
stroke(window, Theme.Color.Stroke, 1.5, 0.35)

-- Lit from above: the top of the panel a touch lighter than the bottom.
local windowShade = Instance.new("UIGradient")
windowShade.Rotation = 90
windowShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 206))
windowShade.Parent = window

-- === Header =================================================================

local header = frame(window, "Header")
header.Size = UDim2.new(1, 0, 0, L.headerHeight)

local stationBadge = frame(header, "StationBadge", Theme.Color.TextDim)
stationBadge.Position = UDim2.fromOffset(L.pad, (L.headerHeight - 42) / 2)
stationBadge.Size = UDim2.fromOffset(42, 42)
corner(stationBadge, 10)
stroke(stationBadge, Color3.new(1, 1, 1), 1, 0.75)

local badgeShade = Instance.new("UIGradient")
badgeShade.Rotation = 90
badgeShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
badgeShade.Parent = stationBadge

local badgeLetter = text(stationBadge, "Letter", Theme.Fonts.Heading, 22, Color3.new(1, 1, 1))
badgeLetter.Size = UDim2.fromScale(1, 1)
badgeLetter.TextXAlignment = Enum.TextXAlignment.Center
badgeLetter.TextStrokeTransparency = 0.6

local title = text(header, "Title", Theme.Fonts.Heading, Theme.TextSize.Heading, Theme.Color.Text)
title.Position = UDim2.fromOffset(L.pad + 56, 13)
title.Size = UDim2.fromOffset(360, 24)
title.Text = "Crafting"

local subtitle = text(header, "Subtitle", Theme.Fonts.Body, Theme.TextSize.Small, Theme.Color.TextDim)
subtitle.Position = UDim2.fromOffset(L.pad + 56, 37)
subtitle.Size = UDim2.fromOffset(360, 18)

-- Close: a round button with a cross, red under the cursor, and the keys that
-- do the same beside it - a modal with no visible way out feels like a trap.
local closeButton = button(header, "Close")
closeButton.AnchorPoint = Vector2.new(0, 0.5)
closeButton.Position = UDim2.new(1, -(L.pad + 34), 0.5, 0)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.BackgroundColor3 = C.card
corner(closeButton, UDim.new(1, 0))
local closeStroke = stroke(closeButton, Theme.Color.Stroke, 1, 0.4)

local closeGlyph = text(closeButton, "Glyph", Theme.Fonts.Heading, Theme.TextSize.Subheading, Theme.Color.TextDim)
closeGlyph.Size = UDim2.fromScale(1, 1)
closeGlyph.TextXAlignment = Enum.TextXAlignment.Center
closeGlyph.Text = "\u{00D7}"

local closeHint = text(header, "KeyHint", Theme.Fonts.Body, Theme.TextSize.Small, Theme.Color.TextFaint)
closeHint.AnchorPoint = Vector2.new(1, 0.5)
closeHint.Position = UDim2.new(1, -(L.pad + 34 + 10), 0.5, 0)
closeHint.Size = UDim2.fromOffset(120, 18)
closeHint.TextXAlignment = Enum.TextXAlignment.Right
closeHint.Text = "B or Esc to close"

local headerRule = frame(window, "HeaderRule", Theme.Color.Divider, 0.2)
headerRule.Position = UDim2.fromOffset(L.pad, L.headerHeight)
headerRule.Size = UDim2.new(1, -L.pad * 2, 0, 1)

-- === Stations ===============================================================

local sidebar = frame(window, "Stations")
sidebar.Position = UDim2.fromOffset(L.pad, L.bodyTop)
sidebar.Size = UDim2.fromOffset(L.sidebarWidth, L.bodyHeight)

local sidebarCaption = text(sidebar, "Caption", Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.TextFaint)
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

local listColumn = frame(window, "Recipes")
listColumn.Position = UDim2.fromOffset(L.listX, L.bodyTop)
listColumn.Size = UDim2.fromOffset(L.listWidth, L.bodyHeight)

local searchField = frame(listColumn, "Search", C.sunken, 0.1)
searchField.Size = UDim2.new(1, -(L.filterWidth + 8), 0, L.searchHeight)
corner(searchField, 8)
local searchStroke = stroke(searchField, Theme.Color.Stroke, 1, 0.5)

-- A magnifier drawn from two frames, so it needs no image asset.
local lensRing = frame(searchField, "Lens")
lensRing.Position = UDim2.fromOffset(12, 11)
lensRing.Size = UDim2.fromOffset(12, 12)
corner(lensRing, UDim.new(1, 0))
stroke(lensRing, Theme.Color.TextDim, 2, 0)

local lensHandle = frame(searchField, "Handle", Theme.Color.TextDim)
lensHandle.AnchorPoint = Vector2.new(0.5, 0.5)
lensHandle.Position = UDim2.fromOffset(26, 26)
lensHandle.Size = UDim2.fromOffset(6, 2)
lensHandle.Rotation = 45

local searchBox = Instance.new("TextBox")
searchBox.Name = "Box"
searchBox.BackgroundTransparency = 1
searchBox.Position = UDim2.fromOffset(36, 0)
searchBox.Size = UDim2.new(1, -36 - 30, 1, 0)
searchBox.FontFace = Theme.Fonts.Body
searchBox.TextSize = Theme.TextSize.Body
searchBox.TextColor3 = Theme.Color.Text
searchBox.PlaceholderText = "Search recipes"
searchBox.PlaceholderColor3 = Theme.Color.TextFaint
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.Text = ""
searchBox.Parent = searchField

local clearSearch = button(searchField, "Clear")
clearSearch.AnchorPoint = Vector2.new(1, 0.5)
clearSearch.Position = UDim2.new(1, -8, 0.5, 0)
clearSearch.Size = UDim2.fromOffset(22, 22)
clearSearch.BackgroundColor3 = C.card
clearSearch.Visible = false
corner(clearSearch, UDim.new(1, 0))

local clearGlyph = text(clearSearch, "Glyph", Theme.Fonts.Heading, Theme.TextSize.Small, Theme.Color.TextDim)
clearGlyph.Size = UDim2.fromScale(1, 1)
clearGlyph.TextXAlignment = Enum.TextXAlignment.Center
clearGlyph.Text = "\u{00D7}"

-- "Craftable": a toggle that hides everything you cannot make right now.
local filterChip = button(listColumn, "CraftableOnly")
filterChip.AnchorPoint = Vector2.new(1, 0)
filterChip.Position = UDim2.new(1, 0, 0, 0)
filterChip.Size = UDim2.fromOffset(L.filterWidth, L.searchHeight)
filterChip.BackgroundColor3 = C.sunken
filterChip.BackgroundTransparency = 0.1
corner(filterChip, 8)
local filterStroke = stroke(filterChip, Theme.Color.Stroke, 1, 0.5)

local filterBox = frame(filterChip, "Box")
filterBox.Position = UDim2.fromOffset(12, (L.searchHeight - 16) / 2)
filterBox.Size = UDim2.fromOffset(16, 16)
filterBox.BackgroundColor3 = Theme.Color.Accent
corner(filterBox, 4)
local filterBoxStroke = stroke(filterBox, Theme.Color.TextDim, 1.5, 0)

-- A dark dot in the filled box, drawn rather than typed: a tick glyph is not
-- something every font has.
local filterTick = frame(filterBox, "Tick", C.onAccent)
filterTick.AnchorPoint = Vector2.new(0.5, 0.5)
filterTick.Position = UDim2.fromScale(0.5, 0.5)
filterTick.Size = UDim2.fromOffset(6, 6)
corner(filterTick, 2)

local filterLabel = text(filterChip, "Label", Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.TextDim)
filterLabel.Position = UDim2.fromOffset(36, 0)
filterLabel.Size = UDim2.new(1, -40, 1, 0)
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
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = Theme.Color.Stroke
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Parent = listColumn

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, L.rowGap)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

-- Room for the selected row's border, and for the scroll bar.
local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 2)
listPadding.PaddingLeft = UDim.new(0, 2)
listPadding.PaddingRight = UDim.new(0, 10)
listPadding.PaddingBottom = UDim.new(0, 2)
listPadding.Parent = list

-- The "nothing here" note. On the column, not in the list, which would lay it
-- out as a row.
local emptyNote = frame(listColumn, "Empty")
emptyNote.AnchorPoint = Vector2.new(0.5, 0)
emptyNote.Position = UDim2.new(0.5, 0, 0, L.searchHeight + 60)
emptyNote.Size = UDim2.new(1, -40, 0, 70)
emptyNote.Visible = false

local emptyTitle = text(emptyNote, "Title", Theme.Fonts.BodyBold, Theme.TextSize.Subheading, Theme.Color.TextDim)
emptyTitle.Size = UDim2.new(1, 0, 0, 24)
emptyTitle.TextXAlignment = Enum.TextXAlignment.Center

local emptyHint = text(emptyNote, "Hint", Theme.Fonts.Body, Theme.TextSize.Small, Theme.Color.TextFaint)
emptyHint.Position = UDim2.fromOffset(0, 28)
emptyHint.Size = UDim2.new(1, 0, 0, 40)
emptyHint.TextXAlignment = Enum.TextXAlignment.Center
emptyHint.TextYAlignment = Enum.TextYAlignment.Top
emptyHint.TextWrapped = true

-- === Detail =================================================================

local detail = frame(window, "Detail", C.card, 0.25)
detail.Position = UDim2.fromOffset(L.detailX, L.bodyTop)
detail.Size = UDim2.fromOffset(L.detailWidth, L.bodyHeight)
corner(detail, 10)
stroke(detail, Theme.Color.Stroke, 1, 0.6)

local detailBody = frame(detail, "Body")
detailBody.Position = UDim2.fromOffset(L.detailPad, L.detailPad)
detailBody.Size = UDim2.new(1, -L.detailPad * 2, 1, -L.detailPad * 2)

-- The hero: what the recipe makes, large, on a glow in its rarity's colour.
local hero = frame(detailBody, "Hero", C.sunken, 0)
hero.Size = UDim2.new(1, 0, 0, L.heroHeight)
corner(hero, 8)

local heroGlow = frame(hero, "Glow", Theme.Color.TextDim, 0)
heroGlow.Size = UDim2.fromScale(1, 1)
corner(heroGlow, 8)

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

local nameLabel = text(detailBody, "Name", Theme.Fonts.Heading, Theme.TextSize.Heading, Theme.Color.Text)
nameLabel.Position = UDim2.fromOffset(0, L.heroHeight + 10)
nameLabel.Size = UDim2.new(1, 0, 0, 26)
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- Two small pills: rarity, and where it is made.
local chips = frame(detailBody, "Chips")
chips.Position = UDim2.fromOffset(0, L.heroHeight + 40)
chips.Size = UDim2.new(1, 0, 0, 22)

local chipLayout = Instance.new("UIListLayout")
chipLayout.FillDirection = Enum.FillDirection.Horizontal
chipLayout.Padding = UDim.new(0, 6)
chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
chipLayout.Parent = chips

local function newChip(name, order)
	local chip = frame(chips, name, Theme.Color.TextDim, 0.82)
	chip.Size = UDim2.fromOffset(0, 22)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.LayoutOrder = order
	corner(chip, UDim.new(1, 0))

	local chipPadding = Instance.new("UIPadding")
	chipPadding.PaddingLeft = UDim.new(0, 10)
	chipPadding.PaddingRight = UDim.new(0, 10)
	chipPadding.Parent = chip

	local label = text(chip, "Label", Theme.Fonts.BodyBold, 13, Theme.Color.Text)
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X

	return chip, label
end

local rarityChip, rarityLabel = newChip("Rarity", 1)
local stationChip, stationLabel = newChip("Station", 2)

local description = text(detailBody, "Description", Theme.Fonts.Body, Theme.TextSize.Small, Theme.Color.TextDim)
description.Position = UDim2.fromOffset(0, L.heroHeight + 70)
description.Size = UDim2.new(1, 0, 0, 36)
description.TextWrapped = true
description.TextYAlignment = Enum.TextYAlignment.Top
description.TextTruncate = Enum.TextTruncate.AtEnd

local requiresCaption = text(detailBody, "RequiresCaption", Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.TextFaint)
requiresCaption.Position = UDim2.fromOffset(0, L.heroHeight + 112)
requiresCaption.Size = UDim2.new(1, 0, 0, 16)
requiresCaption.Text = "REQUIRES"

local footerHeight = L.stepperHeight + 10 + L.buttonHeight
local ingredientsTop = L.heroHeight + 132

local ingredients = Instance.new("ScrollingFrame")
ingredients.Name = "Ingredients"
ingredients.BackgroundTransparency = 1
ingredients.BorderSizePixel = 0
ingredients.Position = UDim2.fromOffset(0, ingredientsTop)
ingredients.Size = UDim2.new(1, 0, 1, -(ingredientsTop + footerHeight + 10))
ingredients.CanvasSize = UDim2.new()
ingredients.AutomaticCanvasSize = Enum.AutomaticSize.Y
ingredients.ScrollBarThickness = 3
ingredients.ScrollBarImageColor3 = Theme.Color.Stroke
ingredients.ScrollingDirection = Enum.ScrollingDirection.Y
ingredients.Parent = detailBody

local ingredientLayout = Instance.new("UIListLayout")
ingredientLayout.Padding = UDim.new(0, 4)
ingredientLayout.SortOrder = Enum.SortOrder.LayoutOrder
ingredientLayout.Parent = ingredients

-- Quantity: - [n] + MAX, and how many could be made.
local stepper = frame(detailBody, "Quantity")
stepper.AnchorPoint = Vector2.new(0, 1)
stepper.Position = UDim2.new(0, 0, 1, -(L.buttonHeight + 10))
stepper.Size = UDim2.new(1, 0, 0, L.stepperHeight)

local function stepButton(name, label, x, width)
	local b = button(stepper, name)
	b.Position = UDim2.fromOffset(x, 0)
	b.Size = UDim2.fromOffset(width, L.stepperHeight)
	b.BackgroundColor3 = C.sunken
	corner(b, 6)
	stroke(b, Theme.Color.Stroke, 1, 0.5)

	local glyph = text(b, "Glyph", Theme.Fonts.Heading, Theme.TextSize.Body, Theme.Color.Text)
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	glyph.Text = label
	return b, glyph
end

local minusButton = stepButton("Less", "-", 0, L.stepperHeight)
local quantityLabel = text(stepper, "Value", Theme.Fonts.Number, Theme.TextSize.Subheading, Theme.Color.Text)
quantityLabel.Position = UDim2.fromOffset(L.stepperHeight, 0)
quantityLabel.Size = UDim2.fromOffset(48, L.stepperHeight)
quantityLabel.TextXAlignment = Enum.TextXAlignment.Center
local plusButton = stepButton("More", "+", L.stepperHeight + 48, L.stepperHeight)
local maxButton, maxGlyph = stepButton("Max", "MAX", L.stepperHeight * 2 + 56, 52)
maxGlyph.TextSize = Theme.TextSize.Small

local canMakeLabel = text(stepper, "CanMake", Theme.Fonts.Body, Theme.TextSize.Small, Theme.Color.TextFaint)
canMakeLabel.AnchorPoint = Vector2.new(1, 0)
canMakeLabel.Position = UDim2.new(1, 0, 0, 0)
canMakeLabel.Size = UDim2.fromOffset(90, L.stepperHeight)
canMakeLabel.TextXAlignment = Enum.TextXAlignment.Right

-- The craft button. Yellow when it will work; when it will not, it says why.
local craftButton = button(detailBody, "Craft")
craftButton.Position = UDim2.new(0, 0, 1, -L.buttonHeight)
craftButton.Size = UDim2.new(1, 0, 0, L.buttonHeight)
craftButton.BackgroundColor3 = Theme.Color.Accent
corner(craftButton, 8)
local craftStroke = stroke(craftButton, Color3.new(1, 1, 1), 1, 0.7)

local craftShade = Instance.new("UIGradient")
craftShade.Rotation = 90
craftShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215))
craftShade.Parent = craftButton

-- Fills left to right while a batch is being made.
local craftProgress = frame(craftButton, "Progress", Color3.new(1, 1, 1), 0.7)
craftProgress.Size = UDim2.fromScale(0, 1)
corner(craftProgress, 8)

local craftLabel = text(craftButton, "Label", Theme.Fonts.Heading, Theme.TextSize.Subheading, C.onAccent)
craftLabel.Size = UDim2.fromScale(1, 1)
craftLabel.TextXAlignment = Enum.TextXAlignment.Center
craftLabel.ZIndex = 2

-- The detail panel's empty state.
local noSelection = text(detail, "NoSelection", Theme.Fonts.Body, Theme.TextSize.Body, Theme.Color.TextFaint)
noSelection.Size = UDim2.fromScale(1, 1)
noSelection.TextXAlignment = Enum.TextXAlignment.Center
noSelection.Text = "Pick a recipe"
noSelection.Visible = false

-- === Toast ==================================================================

-- Results appear as a pill just under the window, where they do not cover the
-- thing being crafted.
local toast = frame(root, "Toast", C.card, 1)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 1, 14)
toast.Size = UDim2.fromOffset(0, 34)
toast.AutomaticSize = Enum.AutomaticSize.X
corner(toast, UDim.new(1, 0))
local toastStroke = stroke(toast, Theme.Color.Stroke, 1, 1)

local toastPadding = Instance.new("UIPadding")
toastPadding.PaddingLeft = UDim.new(0, 16)
toastPadding.PaddingRight = UDim.new(0, 16)
toastPadding.Parent = toast

local toastLabel = text(toast, "Label", Theme.Fonts.BodyBold, Theme.TextSize.Body, Theme.Color.Text)
toastLabel.Size = UDim2.fromScale(0, 1)
toastLabel.AutomaticSize = Enum.AutomaticSize.X
toastLabel.TextTransparency = 1

local toastToken = 0

local function showToast(message, tone)
	toastToken += 1
	local token = toastToken

	local color = if tone == "bad" then Theme.Color.Bad elseif tone == "good" then Theme.Color.Good else Theme.Color.Text
	toastLabel.Text = message
	toastLabel.TextColor3 = color
	toastStroke.Color = color

	TweenService:Create(toast, Theme.Tween.Fade, { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(toastLabel, Theme.Tween.Fade, { TextTransparency = 0 }):Play()
	TweenService:Create(toastStroke, Theme.Tween.Fade, { Transparency = 0.3 }):Play()

	task.delay(TOAST_SECONDS, function()
		if token ~= toastToken then
			return
		end
		TweenService:Create(toast, Theme.Tween.Fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(toastLabel, Theme.Tween.Fade, { TextTransparency = 1 }):Play()
		TweenService:Create(toastStroke, Theme.Tween.Fade, { Transparency = 1 }):Play()
	end)
end

local function hideToast()
	toastToken += 1
	toast.BackgroundTransparency = 1
	toastLabel.TextTransparency = 1
	toastStroke.Transparency = 1
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
	filterTick.Visible = craftableOnly
	filterBox.BackgroundTransparency = if craftableOnly then 0 else 1
	filterBoxStroke.Color = if craftableOnly then Theme.Color.Accent else Theme.Color.TextDim
	filterStroke.Color = if craftableOnly then Theme.Color.Accent else Theme.Color.Stroke
	filterStroke.Transparency = if craftableOnly then 0.2 else 0.5
	filterLabel.TextColor3 = if craftableOnly then Theme.Color.Text else Theme.Color.TextDim
end

-- What a row looks like for its state: chosen, under the cursor, affordable.
local function paintRow(entry)
	local selected = selectedRecipe ~= nil and selectedRecipe.id == entry.recipe.id
	local affordable = canAfford(entry.recipe)

	entry.button.BackgroundColor3 = if entry.hovered or selected then C.cardHover else C.card
	entry.button.BackgroundTransparency = if selected then 0.05 elseif entry.hovered then 0.2 else 0.5
	entry.border.Color = if selected then Theme.Color.Accent else Theme.Color.Stroke
	entry.border.Transparency = if selected then 0 else 0.8
	entry.border.Thickness = if selected then 2 else 1

	entry.tile.ImageColor3 = if affordable then Color3.new(1, 1, 1) else Theme.Color.Disabled
	entry.icon.ImageTransparency = if affordable then 0 else 0.45
	entry.name.TextColor3 = if affordable then Theme.Color.Text else Theme.Color.TextDim

	local possible = craftableCount(entry.recipe)
	if possible > 0 then
		entry.badge.Text = "\u{00D7}" .. tostring(math.min(possible, 999))
		entry.badge.TextColor3 = Theme.Color.Good
		entry.badgeFrame.BackgroundColor3 = Theme.Color.Good
	else
		entry.badge.Text = "Need"
		entry.badge.TextColor3 = Theme.Color.TextFaint
		entry.badgeFrame.BackgroundColor3 = Theme.Color.TextFaint
	end

	for _, chip in ipairs(entry.costs) do
		chip.label.TextColor3 = if held(chip.item) >= chip.count then Theme.Color.TextDim else Theme.Color.Bad
	end
end

local function paintRows()
	for _, entry in pairs(rows) do
		paintRow(entry)
	end
end

local function newRow(recipe, order)
	local entry = { recipe = recipe, hovered = false, costs = {} }

	local row = button(list, recipe.id)
	row.Size = UDim2.new(1, 0, 0, L.rowHeight)
	row.LayoutOrder = order
	corner(row, 8)
	entry.button = row
	entry.border = stroke(row, Theme.Color.Stroke, 1, 0.8)

	local tile, icon, count = newSlotTile(row, 48)
	tile.Position = UDim2.fromOffset(7, (L.rowHeight - 48) / 2)
	showItem(icon, recipe.output.item)
	count.Text = if recipe.output.count > 1 then tostring(recipe.output.count) else ""
	entry.tile, entry.icon = tile, icon

	local name = text(row, "Name", Theme.Fonts.BodyBold, Theme.TextSize.Body, Theme.Color.Text)
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
			local more = text(costs, "More", Theme.Fonts.Body, 13, Theme.Color.TextFaint)
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

		local amount = text(cost, "Count", Theme.Fonts.Number, 13, Theme.Color.TextDim)
		amount.Position = UDim2.fromOffset(20, 0)
		amount.Size = UDim2.fromOffset(0, 18)
		amount.AutomaticSize = Enum.AutomaticSize.X
		amount.Text = tostring(ingredient.count)

		table.insert(entry.costs, { item = ingredient.item, count = ingredient.count, label = amount })
	end

	-- How many you could make, on the right.
	local badgeFrame = frame(row, "Badge", Theme.Color.Good, 0.85)
	badgeFrame.AnchorPoint = Vector2.new(1, 0.5)
	badgeFrame.Position = UDim2.new(1, -12, 0.5, 0)
	badgeFrame.Size = UDim2.fromOffset(48, 24)
	corner(badgeFrame, UDim.new(1, 0))
	entry.badgeFrame = badgeFrame

	local badge = text(badgeFrame, "Label", Theme.Fonts.Number, 13, Theme.Color.Good)
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
	local row = frame(ingredients, ingredient.item, C.sunken, 0.35)
	row.Size = UDim2.new(1, -4, 0, L.ingredientHeight)
	row.LayoutOrder = order
	corner(row, 6)

	local tile, icon = newSlotTile(row, 32)
	tile.Position = UDim2.fromOffset(4, (L.ingredientHeight - 32) / 2)
	ItemThumbnails.bind(icon, ingredient.item, function(image)
		if image == "" then
			ItemPreview.fillSlot(icon, ingredient.item)
		end
	end)

	local have = held(ingredient.item)
	local enough = have >= ingredient.count

	local name = text(row, "Name", Theme.Fonts.Body, Theme.TextSize.Small, if enough then Theme.Color.Text else Theme.Color.TextDim)
	name.Position = UDim2.fromOffset(44, 5)
	name.Size = UDim2.new(1, -44 - 70, 0, 18)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = displayName(ingredient.item)

	local tally = text(row, "Tally", Theme.Fonts.Number, Theme.TextSize.Count, if enough then Theme.Color.Good else Theme.Color.Bad)
	tally.AnchorPoint = Vector2.new(1, 0)
	tally.Position = UDim2.new(1, -10, 0, 4)
	tally.Size = UDim2.fromOffset(70, 18)
	tally.TextXAlignment = Enum.TextXAlignment.Right
	tally.Text = string.format("%d / %d", math.min(have, 9999), ingredient.count)

	-- How far along you are, under the name.
	local track = frame(row, "Track", Theme.Color.Divider, 0)
	track.Position = UDim2.new(0, 44, 0, 27)
	track.Size = UDim2.new(1, -54, 0, 4)
	corner(track, UDim.new(1, 0))

	local fill = frame(track, "Fill", if enough then Theme.Color.Good else Theme.Color.Bad, 0)
	fill.Size = UDim2.fromScale(math.clamp(have / math.max(ingredient.count, 1), 0, 1), 1)
	corner(fill, UDim.new(1, 0))
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
	craftButton.BackgroundColor3 = if lit or batch then Theme.Color.Accent else C.sunken
	craftLabel.TextColor3 = if lit or batch then C.onAccent else Theme.Color.TextFaint
	craftStroke.Color = if lit or batch then Color3.new(1, 1, 1) else Theme.Color.Stroke
	craftStroke.Transparency = if lit or batch then 0.7 else 0.5
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
	nameLabel.TextColor3 = if Theme.rarityRank(rarity) > 1 then rarityColor else Theme.Color.Text

	rarityChip.BackgroundColor3 = rarityColor
	rarityLabel.Text = string.upper(rarity)
	rarityLabel.TextColor3 = rarityColor:Lerp(Color3.new(1, 1, 1), 0.35)

	stationChip.BackgroundColor3 = stationColor(recipe.station)
	stationLabel.Text = if recipe.station then StationConfig.getDisplayName(recipe.station) else "By hand"
	stationLabel.TextColor3 = if inRange(recipe.station) then Theme.Color.Text else Theme.Color.TextDim

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

		local b = button(tabList, id)
		b.Size = UDim2.new(1, 0, 0, L.tabHeight)
		b.LayoutOrder = order
		b.BackgroundColor3 = C.card
		b.BackgroundTransparency = 1
		corner(b, 8)
		tab.button = b
		tab.border = stroke(b, Theme.Color.Stroke, 1, 1)

		-- The active tab gets an accent bar as well as a fill: colour alone is
		-- easy to miss beside a busy list.
		local bar = frame(b, "Accent", Theme.Color.Accent)
		bar.AnchorPoint = Vector2.new(0, 0.5)
		bar.Position = UDim2.new(0, 0, 0.5, 0)
		bar.Size = UDim2.fromOffset(4, L.tabHeight - 18)
		bar.Visible = false
		corner(bar, 2)
		tab.bar = bar

		local dot = frame(b, "Swatch", stationColor(stationId))
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 14, 0.5, 0)
		dot.Size = UDim2.fromOffset(14, 14)
		corner(dot, 4)
		stroke(dot, Color3.new(1, 1, 1), 1, 0.7)

		local name = text(b, "Name", Theme.Fonts.Body, Theme.TextSize.Body, Theme.Color.TextDim)
		name.Position = UDim2.fromOffset(38, 7)
		name.Size = UDim2.new(1, -38 - 44, 0, 20)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = if stationId then StationConfig.getDisplayName(stationId) else "By Hand"
		tab.name = name

		local state = text(b, "State", Theme.Fonts.Body, 13, Theme.Color.TextFaint)
		state.Position = UDim2.fromOffset(38, 27)
		state.Size = UDim2.new(1, -38 - 44, 0, 16)
		tab.state = state

		-- How many of its recipes you can make right now, of how many.
		local count = text(b, "Count", Theme.Fonts.Number, 13, Theme.Color.TextFaint)
		count.AnchorPoint = Vector2.new(1, 0.5)
		count.Position = UDim2.new(1, -10, 0.5, 0)
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

		tab.button.BackgroundTransparency = if tab.active then 0.1 elseif tab.hovered then 0.45 else 1
		tab.border.Transparency = if tab.active then 0.5 else 1
		tab.bar.Visible = tab.active
		tab.name.FontFace = if tab.active then Theme.Fonts.BodyBold else Theme.Fonts.Body
		tab.name.TextColor3 = if tab.active or tab.hovered then Theme.Color.Text else Theme.Color.TextDim

		if stationId == nil then
			tab.state.Text = "Anywhere"
			tab.state.TextColor3 = Theme.Color.TextFaint
		elseif nearby[stationId] then
			tab.state.Text = "In range"
			tab.state.TextColor3 = Theme.Color.Good
		else
			tab.state.Text = "Not nearby"
			tab.state.TextColor3 = Theme.Color.TextFaint
		end

		local recipes = RecipeBook.getForStation(stationId)
		local ready = 0
		for _, recipe in ipairs(recipes) do
			if canAfford(recipe) then
				ready += 1
			end
		end
		tab.count.Text = string.format("%d/%d", ready, #recipes)
		tab.count.TextColor3 = if ready > 0 then Theme.Color.Good else Theme.Color.TextFaint
	end
end

local function refreshHeader()
	local color = stationColor(activeStation)
	stationBadge.BackgroundColor3 = color

	local name = if activeStation then StationConfig.getDisplayName(activeStation) else "By Hand"
	badgeLetter.Text = if activeStation then string.upper(string.sub(name, 1, 1)) else "H"
	title.Text = if activeStation then name else "Crafting"

	if activeStation == nil then
		subtitle.Text = "Hand recipes - craft these anywhere"
		subtitle.TextColor3 = Theme.Color.TextDim
	elseif nearby[activeStation] then
		subtitle.Text = string.format("At a %s", name)
		subtitle.TextColor3 = Theme.Color.Good
	else
		subtitle.Text = string.format("Stand near a %s to craft these", name)
		subtitle.TextColor3 = Theme.Color.TextDim
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
		Motion.openPanel(window, Theme.Transparency.Panel)
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

Motion.attachButton(craftButton, {
	hoverScale = 1.02,
	pressScale = 0.97,
	sound = "ui.click",
	enabled = function()
		return selectedRecipe ~= nil and canAfford(selectedRecipe) and batch == nil
	end,
	onDenied = function()
		if not batch then
			Motion.shake(detail, 6)
			showToast("Not enough materials", "bad")
		end
	end,
	onClick = requestCraft,
})

Motion.attachButton(closeButton, {
	hoverScale = 1.08,
	pressScale = 0.92,
	sound = "ui.click",
	onClick = close,
})

closeButton.MouseEnter:Connect(function()
	TweenService:Create(closeButton, Theme.Tween.Hover, { BackgroundColor3 = Theme.Color.Bad }):Play()
	closeGlyph.TextColor3 = Color3.new(1, 1, 1)
	closeStroke.Transparency = 1
end)
closeButton.MouseLeave:Connect(function()
	TweenService:Create(closeButton, Theme.Tween.Hover, { BackgroundColor3 = C.card }):Play()
	closeGlyph.TextColor3 = Theme.Color.TextDim
	closeStroke.Transparency = 0.4
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

Motion.attachButton(minusButton, { onClick = function() stepQuantity(-1) end, sound = "ui.click" })
Motion.attachButton(plusButton, { onClick = function() stepQuantity(1) end, sound = "ui.click" })
Motion.attachButton(maxButton, {
	sound = "ui.click",
	onClick = function()
		quantity = quantityLimit()
		refreshCraftButton()
	end,
})

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
	searchStroke.Color = Theme.Color.Accent
	searchStroke.Transparency = 0.2
end)

-- Enter in the search box crafts the selection, so a player can type a name
-- and make it without reaching for the mouse.
searchBox.FocusLost:Connect(function(enterPressed)
	searchStroke.Color = Theme.Color.Stroke
	searchStroke.Transparency = 0.5
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
