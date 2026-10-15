--[[
	CraftingClient

	The crafting window.

	Drawn entirely from Shared.UI.Theme, so it uses the inventory's own slot
	tile, pitch, fonts, rarity colours and selection yellow.

	It reads the shared RecipeBook - the same module the server reads - so the
	list can never contain a recipe the server has not heard of. Greying out
	what the player cannot afford is a courtesy, not a rule: the server
	re-checks materials, station and range on every craft, and the only thing
	this sends is a recipe id.

	Opened with B for hand recipes, or by using a placed station's prompt. Both
	the tab strip and the grid are built at run time from CraftingRecipes and
	StationConfig, so adding a recipe changes nothing here.
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
-- Layout
-- ---------------------------------------------------------------------------

local L = {
	windowWidth = 720,
	windowHeight = 470,

	pad = 14,
	headerHeight = 32,
	bodyTop = 64,
	bodyHeight = 332,

	tabWidth = 132,
	tabHeight = 28,

	closeSize = 26,
	searchX = 150,
	searchWidth = 250,

	gridX = 166,
	gridWidth = 340,

	detailX = 532,
	detailWidth = 174,

	statusY = 426,
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local isOpen = false
local activeStation = nil -- nil means hand crafting
local selectedRecipe = nil
local heldCounts = {} -- itemName -> count, from the last server snapshot
local searchQuery = "" -- lowercased contents of the search box; "" means no filter
local recipeTiles = {} -- recipeId -> { tile, icon, count }
local ingredientRows = {}
local tabButtons = {}
local statusClearAt = 0

-- ---------------------------------------------------------------------------
-- Widget helpers
-- ---------------------------------------------------------------------------

local function rarityColor(itemName)
	local def = ItemDefinitions[itemName]
	return Theme.rarityColor(def and def.rarity)
end

local function newText(parent, size, font, textSize, color)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.FontFace = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = ""
	label.Parent = parent
	return label
end

local function newDivider(parent, position, size)
	local line = Instance.new("Frame")
	line.BackgroundColor3 = Theme.Color.Divider
	line.BorderSizePixel = 0
	line.Position = position
	line.Size = size
	line.Parent = parent
	return line
end

--[[
	One inventory-style tile: the slot image, an icon centred inside it at the
	same 48/64 ratio the inventory uses, and a count in the bottom-right corner.
]]
local function newSlotTile(parent, pixels, interactive)
	local tile = Instance.new(if interactive then "ImageButton" else "ImageLabel")
	tile.BackgroundTransparency = 1
	tile.BorderSizePixel = 0
	tile.Image = Theme.SlotImage
	tile.Size = UDim2.fromOffset(pixels, pixels)

	-- AutoButtonColor exists on ImageButton but NOT on ImageLabel, and assigning
	-- a property a class does not have is a hard error, not a no-op.
	if interactive then
		tile.AutoButtonColor = false
	end

	tile.Parent = parent

	local icon = Instance.new("ImageLabel")
	icon.Name = "icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0.75, 0.75)
	icon.Position = UDim2.fromScale(0.125, 0.125)
	icon.ZIndex = tile.ZIndex + 2
	icon.Parent = tile

	local count = Instance.new("TextLabel")
	count.Name = "num"
	count.BackgroundTransparency = 1
	count.Size = UDim2.fromScale(0.92, 0.3)
	count.Position = UDim2.fromScale(0, 0.66)
	count.FontFace = Theme.Fonts.Number
	count.TextSize = Theme.TextSize.Count
	count.TextColor3 = Color3.new(1, 1, 1)
	count.TextStrokeTransparency = 0.4
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextYAlignment = Enum.TextYAlignment.Center
	count.ZIndex = tile.ZIndex + 3
	count.Text = ""
	count.Parent = tile

	return tile, icon, count
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

-- Modal dim, so the window reads as a mode rather than a floating rectangle.
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Theme.Color.Backdrop
backdrop.BackgroundTransparency = 1
backdrop.BorderSizePixel = 0
-- Active so it reliably receives and sinks the click that closes the window.
-- A transparent Frame still gets InputBegan, but an inactive one lets the click
-- fall through to the world behind it - which would swing the pickaxe.
backdrop.Active = true
backdrop.Parent = screen

local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(L.windowWidth, L.windowHeight)
window.BackgroundColor3 = Theme.Color.Panel
window.BackgroundTransparency = Theme.Transparency.Panel
window.BorderSizePixel = 0
window.Parent = screen

-- A framed edge, matching the framed look of the slot tiles.
local windowStroke = Instance.new("UIStroke")
windowStroke.Color = Theme.Color.Stroke
windowStroke.Thickness = 2
windowStroke.Parent = window

-- === Header ===============================================================

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundColor3 = Theme.Color.PanelRaised
header.BackgroundTransparency = 0.35
header.BorderSizePixel = 0
header.Position = UDim2.fromOffset(0, 0)
header.Size = UDim2.new(1, 0, 0, L.pad + L.headerHeight)
header.Parent = window

local title = newText(
	header,
	UDim2.new(0.6, 0, 0, L.headerHeight),
	Theme.Fonts.Heading,
	Theme.TextSize.Heading,
	Theme.Color.Text
)
title.Position = UDim2.fromOffset(L.pad, L.pad * 0.5)
title.Text = "Crafting"

--[[
	Close button.

	The keyboard hint stays, because a player who has learned B should not have
	to reach for the mouse - but a modal with no visible way out is a modal a
	player can feel trapped in, and "press the key you used to open it" is not
	discoverable from inside the window.
]]
local closeButton = Instance.new("ImageButton")
closeButton.Name = "Close"
closeButton.BackgroundTransparency = 1
closeButton.BorderSizePixel = 0
closeButton.Image = Theme.SlotImage
closeButton.ScaleType = Enum.ScaleType.Slice
closeButton.SliceCenter = Theme.SlotSlice
closeButton.Size = UDim2.fromOffset(L.closeSize, L.closeSize)
closeButton.Position = UDim2.new(1, -(L.pad + L.closeSize), 0, L.pad * 0.5 + 2)
closeButton.AutoButtonColor = false
closeButton.Parent = header

local closeGlyph = newText(
	closeButton,
	UDim2.fromScale(1, 1),
	Theme.Fonts.Heading,
	Theme.TextSize.Subheading,
	Theme.Color.TextDim
)
closeGlyph.TextXAlignment = Enum.TextXAlignment.Center
closeGlyph.Text = "\u{00D7}"
closeGlyph.ZIndex = 2

local closeHint = newText(
	header,
	UDim2.new(0, 110, 0, L.headerHeight),
	Theme.Fonts.Body,
	Theme.TextSize.Small,
	Theme.Color.TextFaint
)
closeHint.Position = UDim2.new(1, -(L.pad + L.closeSize + 8 + 110), 0, L.pad * 0.5)
closeHint.TextXAlignment = Enum.TextXAlignment.Right
closeHint.Text = "B or Esc"

--[[
	Recipe search.

	Thirty-five recipes across seven stations is past the point where scanning a
	grid of icons is the fastest way to find one. Filters on the output item's
	name, live, across the active station's list.

	Typing sets `processed` on the global input handler, so the B key that opens
	this window does not close it mid-word.
]]
local searchBox = Instance.new("TextBox")
searchBox.Name = "Search"
searchBox.BackgroundColor3 = Theme.Color.Panel
searchBox.BackgroundTransparency = 0.25
searchBox.BorderSizePixel = 0
searchBox.Position = UDim2.fromOffset(L.searchX, L.pad * 0.5 + 3)
searchBox.Size = UDim2.fromOffset(L.searchWidth, L.headerHeight - 6)
searchBox.FontFace = Theme.Fonts.Body
searchBox.TextSize = Theme.TextSize.Small
searchBox.TextColor3 = Theme.Color.Text
searchBox.PlaceholderText = "Search recipes..."
searchBox.PlaceholderColor3 = Theme.Color.TextFaint
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.Text = ""
searchBox.Parent = header

local searchPadding = Instance.new("UIPadding")
searchPadding.PaddingLeft = UDim.new(0, 8)
searchPadding.PaddingRight = UDim.new(0, 8)
searchPadding.Parent = searchBox

local searchStroke = Instance.new("UIStroke")
searchStroke.Color = Theme.Color.Stroke
searchStroke.Thickness = 1
searchStroke.Transparency = 0.4
searchStroke.Parent = searchBox

newDivider(window, UDim2.fromOffset(0, L.pad + L.headerHeight), UDim2.new(1, 0, 0, 1))

-- === Tabs =================================================================

local tabColumn = Instance.new("Frame")
tabColumn.Name = "Tabs"
tabColumn.BackgroundTransparency = 1
tabColumn.Position = UDim2.fromOffset(L.pad, L.bodyTop)
tabColumn.Size = UDim2.fromOffset(L.tabWidth, L.bodyHeight)
tabColumn.Parent = window

local tabLayout = Instance.new("UIListLayout")
tabLayout.Padding = UDim.new(0, 4)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabColumn

newDivider(window, UDim2.fromOffset(L.pad + L.tabWidth + 8, L.bodyTop), UDim2.fromOffset(1, L.bodyHeight))

-- === Recipe grid ==========================================================

local grid = Instance.new("ScrollingFrame")
grid.Name = "Recipes"
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.Position = UDim2.fromOffset(L.gridX, L.bodyTop)
grid.Size = UDim2.fromOffset(L.gridWidth, L.bodyHeight)
grid.CanvasSize = UDim2.new()
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.ScrollBarThickness = 4
grid.ScrollBarImageColor3 = Theme.Color.Stroke
grid.ScrollingDirection = Enum.ScrollingDirection.Y
grid.Parent = window

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(Theme.SlotSize, Theme.SlotSize)
gridLayout.CellPadding = UDim2.fromOffset(
	Theme.SlotPitch - Theme.SlotSize,
	Theme.SlotPitch - Theme.SlotSize
)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

--[[
	The "nothing here" note.

	Parented to the WINDOW, not to the grid: UIGridLayout lays out every child of
	its parent, so anything living inside the scroller that is not a recipe would
	be dropped into a cell of its own.
]]
local emptyNote = newText(
	window,
	UDim2.fromOffset(L.gridWidth - 8, 40),
	Theme.Fonts.Body,
	Theme.TextSize.Body,
	Theme.Color.TextFaint
)
emptyNote.Position = UDim2.fromOffset(L.gridX + 4, L.bodyTop + 8)
emptyNote.TextWrapped = true
emptyNote.TextYAlignment = Enum.TextYAlignment.Top
emptyNote.Visible = false

--[[
	Names the tile under the cursor.

	With the grid now several rows deep, icons alone are not enough to tell
	recipes apart at a glance - and clicking each one to find out is exactly the
	kind of friction that makes a menu feel unfinished. Sits under the grid so it
	never covers a tile.
]]
local hoverName = newText(
	window,
	UDim2.fromOffset(L.gridWidth, 20),
	Theme.Fonts.Body,
	Theme.TextSize.Small,
	Theme.Color.TextDim
)
hoverName.Position = UDim2.fromOffset(L.gridX, L.bodyTop + L.bodyHeight + 4)
hoverName.TextTruncate = Enum.TextTruncate.AtEnd

newDivider(window, UDim2.fromOffset(L.detailX - 14, L.bodyTop), UDim2.fromOffset(1, L.bodyHeight))

-- === Detail panel =========================================================

local detail = Instance.new("Frame")
detail.Name = "Detail"
detail.BackgroundTransparency = 1
detail.Position = UDim2.fromOffset(L.detailX, L.bodyTop)
detail.Size = UDim2.fromOffset(L.detailWidth, L.bodyHeight)
detail.Parent = window

local detailTile, detailIcon, detailCount = newSlotTile(detail, Theme.SlotSize, false)
detailTile.Position = UDim2.fromOffset(0, 0)

local detailName = newText(
	detail,
	UDim2.new(1, -(Theme.SlotSize + 10), 0, 22),
	Theme.Fonts.BodyBold,
	Theme.TextSize.Subheading,
	Theme.Color.Text
)
detailName.Position = UDim2.fromOffset(Theme.SlotSize + 10, 8)
detailName.TextTruncate = Enum.TextTruncate.AtEnd

local detailStation = newText(
	detail,
	UDim2.new(1, -(Theme.SlotSize + 10), 0, 18),
	Theme.Fonts.Body,
	Theme.TextSize.Small,
	Theme.Color.TextDim
)
detailStation.Position = UDim2.fromOffset(Theme.SlotSize + 10, 32)

local detailDescription = newText(
	detail,
	UDim2.new(1, 0, 0, 56),
	Theme.Fonts.Body,
	Theme.TextSize.Small,
	Theme.Color.TextFaint
)
detailDescription.Position = UDim2.fromOffset(0, Theme.SlotSize + 12)
detailDescription.TextWrapped = true
detailDescription.TextYAlignment = Enum.TextYAlignment.Top

local requiresLabel = newText(
	detail,
	UDim2.new(1, 0, 0, 18),
	Theme.Fonts.BodyBold,
	Theme.TextSize.Small,
	Theme.Color.TextDim
)
requiresLabel.Position = UDim2.fromOffset(0, 142)
requiresLabel.Text = "REQUIRES"

newDivider(detail, UDim2.fromOffset(0, 162), UDim2.new(1, 0, 0, 1))

local ingredientList = Instance.new("Frame")
ingredientList.Name = "Ingredients"
ingredientList.BackgroundTransparency = 1
ingredientList.Position = UDim2.fromOffset(0, 170)
ingredientList.Size = UDim2.new(1, 0, 0, 116)
ingredientList.Parent = detail

local ingredientLayout = Instance.new("UIListLayout")
ingredientLayout.Padding = UDim.new(0, 4)
ingredientLayout.SortOrder = Enum.SortOrder.LayoutOrder
ingredientLayout.Parent = ingredientList

local craftButton = Instance.new("ImageButton")
craftButton.Name = "Craft"
craftButton.BackgroundTransparency = 1
craftButton.BorderSizePixel = 0
craftButton.Image = Theme.SlotImage
craftButton.ScaleType = Enum.ScaleType.Slice
craftButton.SliceCenter = Theme.SlotSlice
craftButton.Position = UDim2.fromOffset(0, L.bodyHeight - 38)
craftButton.Size = UDim2.fromOffset(L.detailWidth, 38)
craftButton.AutoButtonColor = false
craftButton.Parent = detail

local craftLabel = newText(
	craftButton,
	UDim2.fromScale(1, 1),
	Theme.Fonts.Heading,
	Theme.TextSize.Subheading,
	Theme.Color.Text
)
craftLabel.TextXAlignment = Enum.TextXAlignment.Center
craftLabel.Text = "CRAFT"
craftLabel.ZIndex = 2

-- Sits above the button rather than inside it: how many you COULD make is a
-- different question from whether this click will work, and cramming both into
-- one line makes the button read as a sentence instead of a control.
local craftableLabel = newText(
	detail,
	UDim2.new(1, 0, 0, 16),
	Theme.Fonts.Body,
	Theme.TextSize.Small,
	Theme.Color.TextFaint
)
craftableLabel.Position = UDim2.fromOffset(0, L.bodyHeight - 56)
craftableLabel.TextXAlignment = Enum.TextXAlignment.Center

-- === Status ===============================================================

local status = newText(
	window,
	UDim2.new(1, -L.pad * 2, 0, 20),
	Theme.Fonts.Body,
	Theme.TextSize.Small,
	Theme.Color.TextDim
)
status.Position = UDim2.fromOffset(L.pad, L.statusY)

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

local function held(itemName)
	return heldCounts[itemName] or 0
end

local function canAfford(recipe)
	for _, ingredient in ipairs(recipe.ingredients) do
		if held(ingredient.item) < ingredient.count then
			return false
		end
	end
	return true
end

local function setStatus(message, tone)
	status.Text = message or ""

	if tone == "bad" then
		status.TextColor3 = Theme.Color.Bad
	elseif tone == "good" then
		status.TextColor3 = Theme.Color.Good
	else
		status.TextColor3 = Theme.Color.TextDim
	end

	if message then
		Motion.fadeInText(status)
		statusClearAt = os.clock() + 4
	else
		statusClearAt = 0
	end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local refreshDetail
local selectRecipe

--[[
	Marks one tile as chosen.

	Each tile carries its own highlight child rather than there being a single
	marker that slides around: the grid layout owns tile positions, so a floating
	marker would have to chase numbers the layout is free to change. The colour
	and transparency are the inventory hotbar highlight's, so "this one is
	selected" looks the same in both screens.
]]
local function setSelected(recipeId)
	for id, entry in pairs(recipeTiles) do
		entry.highlight.Visible = (id == recipeId)
	end
end

local function refreshGridAffordability()
	for recipeId, entry in pairs(recipeTiles) do
		local recipe = RecipeBook.get(recipeId)
		local affordable = recipe ~= nil and canAfford(recipe)

		entry.tile.ImageColor3 = if affordable then Color3.new(1, 1, 1) else Theme.Color.Disabled
		entry.icon.ImageTransparency = if affordable then 0 else 0.5
		entry.count.TextTransparency = if affordable then 0 else 0.4
	end
end

--[[
	How many times over the player could make this recipe right now.

	Shown next to the craft button, because "can I afford it" is only half the
	question a player is actually asking when they are stockpiling.
]]
local function craftableCount(recipe)
	if not recipe then
		return 0
	end

	local possible = math.huge
	for _, ingredient in ipairs(recipe.ingredients) do
		local need = ingredient.count or 1
		if need > 0 then
			local runs = math.floor(held(ingredient.item) / need)
			if runs < possible then
				possible = runs
			end
		end
	end

	return if possible == math.huge then 0 else possible
end

local function matchesSearch(recipe)
	if searchQuery == "" then
		return true
	end
	return string.find(string.lower(recipe.output.item), searchQuery, 1, true) ~= nil
end

local function buildGrid()
	hoverName.Text = ""

	for _, entry in pairs(recipeTiles) do
		entry.tile:Destroy()
	end
	table.clear(recipeTiles)

	local all = RecipeBook.getForStation(activeStation)

	-- Filtered into a separate list rather than hiding tiles in place, because
	-- UIGridLayout still reserves a cell for an invisible child and the grid
	-- would fill with holes.
	local recipes = {}
	for _, recipe in ipairs(all) do
		if matchesSearch(recipe) then
			table.insert(recipes, recipe)
		end
	end

	for order, recipe in ipairs(recipes) do
		local tile, icon, count = newSlotTile(grid, Theme.SlotSize, true)
		tile.Name = recipe.id
		tile.LayoutOrder = order
		tile.ZIndex = 1

		local highlight = Instance.new("Frame")
		highlight.Name = "Selected"
		highlight.BackgroundColor3 = Theme.Color.Accent
		highlight.BackgroundTransparency = Theme.Transparency.Selection
		highlight.BorderSizePixel = 0
		highlight.Size = UDim2.fromScale(1, 1)
		highlight.ZIndex = tile.ZIndex + 1
		highlight.Visible = false
		highlight.Parent = tile

		ItemThumbnails.bind(icon, recipe.output.item)
		count.Text = if recipe.output.count > 1 then tostring(recipe.output.count) else ""

		Motion.attachSlot(tile, icon, {
			onClick = function()
				selectRecipe(recipe)
			end,
		})

		local label = if recipe.output.count > 1
			then string.format("%s  x%d", recipe.output.item, recipe.output.count)
			else recipe.output.item

		tile.MouseEnter:Connect(function()
			hoverName.Text = label
			hoverName.TextColor3 = if canAfford(recipe) then Theme.Color.Text else Theme.Color.TextFaint
		end)

		tile.MouseLeave:Connect(function()
			if hoverName.Text == label then
				hoverName.Text = ""
			end
		end)

		recipeTiles[recipe.id] = { tile = tile, icon = icon, count = count, highlight = highlight }
	end

	refreshGridAffordability()

	emptyNote.Visible = #recipes == 0
	if #recipes == 0 then
		emptyNote.Text = if searchQuery ~= ""
			then string.format("Nothing here matches \"%s\".", searchBox.Text)
			else string.format(
				"No recipes at the %s yet.", StationConfig.getDisplayName(activeStation)
			)
		selectRecipe(nil)
	else
		-- Keep the current selection if the filter did not remove it, so typing
		-- does not yank the detail panel away mid-read.
		local keep = nil
		if selectedRecipe then
			for _, recipe in ipairs(recipes) do
				if recipe.id == selectedRecipe.id then
					keep = recipe
					break
				end
			end
		end

		selectRecipe(keep or recipes[1])
	end
end

local function refreshIngredients(recipe)
	for _, row in ipairs(ingredientRows) do
		row:Destroy()
	end
	table.clear(ingredientRows)

	if not recipe then
		return
	end

	for order, ingredient in ipairs(recipe.ingredients) do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 34)
		row.LayoutOrder = order
		row.Parent = ingredientList

		local tile, icon = newSlotTile(row, 30, false)
		tile.Position = UDim2.fromOffset(0, 2)

		ItemThumbnails.bind(icon, ingredient.item)

		local have = held(ingredient.item)
		local enough = have >= ingredient.count

		local name = newText(
			row,
			UDim2.new(1, -80, 1, 0),
			Theme.Fonts.Body,
			Theme.TextSize.Small,
			if enough then Theme.Color.Text else Theme.Color.TextDim
		)
		name.Position = UDim2.fromOffset(38, 0)
		name.Text = ingredient.item
		name.TextTruncate = Enum.TextTruncate.AtEnd

		-- The count is the thing being scanned for, so it gets the number font
		-- and its own column rather than being buried in a sentence.
		local tally = newText(
			row,
			UDim2.fromOffset(40, 34),
			Theme.Fonts.Number,
			Theme.TextSize.Count,
			if enough then Theme.Color.Good else Theme.Color.Bad
		)
		tally.Position = UDim2.new(1, -40, 0, 0)
		tally.TextXAlignment = Enum.TextXAlignment.Right
		tally.Text = string.format("%d/%d", math.min(have, 999), ingredient.count)

		table.insert(ingredientRows, row)
	end
end

function refreshDetail()
	local recipe = selectedRecipe

	if not recipe then
		detailIcon.Image = ""
		detailCount.Text = ""
		detailName.Text = ""
		detailStation.Text = ""
		detailDescription.Text = ""
		requiresLabel.Visible = false
		craftButton.Visible = false
		craftableLabel.Text = ""
		setSelected(nil)
		refreshIngredients(nil)
		return
	end

	local def = ItemDefinitions[recipe.output.item]

	ItemThumbnails.bind(detailIcon, recipe.output.item)
	detailCount.Text = if recipe.output.count > 1 then tostring(recipe.output.count) else ""
	detailName.Text = recipe.output.item
	detailName.TextColor3 = rarityColor(recipe.output.item)
	detailStation.Text = StationConfig.getDisplayName(recipe.station)
	-- A weapon's class line ("Sword -> Longsword") heads its description.
	detailDescription.Text = WeaponClasses.description(def)
	requiresLabel.Visible = true

	refreshIngredients(recipe)

	local affordable = canAfford(recipe)
	craftButton.Visible = true
	craftButton.ImageColor3 = if affordable then Color3.new(1, 1, 1) else Theme.Color.Disabled
	craftLabel.TextColor3 = if affordable then Theme.Color.Text else Theme.Color.TextFaint

	-- The button says why it will not work, rather than just going grey and
	-- leaving the player to compare numbers in the ingredient list themselves.
	craftLabel.Text = if affordable then "CRAFT" else "NEED MATERIALS"

	local possible = craftableCount(recipe)
	craftableLabel.Text = if possible > 1 then string.format("enough for %d", possible) else ""

	setSelected(recipe.id)
end

function selectRecipe(recipe)
	selectedRecipe = recipe
	refreshDetail()
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------

local setStation

local function buildTabs()
	local entries = { StationConfig.HandStation }
	for _, id in ipairs(StationConfig.Order) do
		table.insert(entries, id)
	end

	for order, id in ipairs(entries) do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, L.tabHeight)
		row.LayoutOrder = order
		row.Parent = tabColumn

		-- The active tab gets an accent bar rather than only a colour change:
		-- colour alone is easy to miss against a busy grid.
		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.BackgroundColor3 = Theme.Color.Accent
		accent.BorderSizePixel = 0
		accent.Position = UDim2.fromOffset(0, 4)
		accent.Size = UDim2.fromOffset(3, L.tabHeight - 8)
		accent.Visible = false
		accent.Parent = row

		local button = Instance.new("TextButton")
		button.BackgroundColor3 = Theme.Color.PanelRaised
		button.BackgroundTransparency = 1
		button.BorderSizePixel = 0
		button.Position = UDim2.fromOffset(9, 0)
		button.Size = UDim2.new(1, -9, 1, 0)
		button.FontFace = Theme.Fonts.Body
		button.TextSize = Theme.TextSize.Body
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.TextColor3 = Theme.Color.TextDim
		button.Text = StationConfig.getDisplayName(
			if id == StationConfig.HandStation then nil else id
		)
		button.AutoButtonColor = false
		button.Parent = row

		local stationId = if id == StationConfig.HandStation then nil else id

		button.MouseEnter:Connect(function()
			if not tabButtons[id].active then
				TweenService:Create(button, Theme.Tween.Hover, { BackgroundTransparency = 0.6 }):Play()
			end
			Sounds.play("ui.hover")
		end)

		button.MouseLeave:Connect(function()
			TweenService:Create(button, Theme.Tween.Hover, { BackgroundTransparency = 1 }):Play()
		end)

		button.MouseButton1Click:Connect(function()
			Sounds.play("ui.tab")
			setStation(stationId)
		end)

		tabButtons[id] = { button = button, accent = accent, active = false }
	end
end

function setStation(stationId)
	activeStation = stationId

	for id, entry in pairs(tabButtons) do
		local active = (id == (stationId or StationConfig.HandStation))
		entry.active = active
		entry.accent.Visible = active
		entry.button.TextColor3 = if active then Theme.Color.Text else Theme.Color.TextDim
		entry.button.BackgroundTransparency = if active then 0.45 else 1
		entry.button.FontFace = if active then Theme.Fonts.BodyBold else Theme.Fonts.Body
	end

	title.Text = string.format("Crafting  -  %s", StationConfig.getDisplayName(stationId))
	buildGrid()
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------

local function open(stationId)
	log("open", stationId or "Hand")

	local wasOpen = isOpen
	isOpen = true
	screen.Enabled = true

	setStatus(nil)
	setStation(stationId)

	if not wasOpen then
		Sounds.play("ui.open")
		Motion.openPanel(window, Theme.Transparency.Panel)
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

	-- Reopening on a filter the player set a session ago, with no memory of
	-- having set it, reads as half the recipes having disappeared.
	if searchBox.Text ~= "" then
		searchBox.Text = ""
	end
	searchBox:ReleaseFocus()

	Sounds.play("ui.close")
	TweenService:Create(backdrop, Theme.Tween.Close, { BackgroundTransparency = 1 }):Play()
	Motion.closePanel(window, function()
		if not isOpen then
			screen.Enabled = false
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

--[[
	One place that asks the server to craft, so the button and the Enter key
	cannot drift into behaving differently.
]]
local function requestCraft()
	if not selectedRecipe then
		return
	end

	if not canAfford(selectedRecipe) then
		Motion.shake(window, 8)
		setStatus("Not enough materials", "bad")
		return
	end

	log("craft request", selectedRecipe.id)
	RequestCraft:FireServer(selectedRecipe.id)
end

Motion.attachButton(craftButton, {
	hoverScale = 1.03,
	pressScale = 0.97,
	sound = "ui.click",
	enabled = function()
		return selectedRecipe ~= nil and canAfford(selectedRecipe)
	end,
	onDenied = function()
		Motion.shake(window, 8)
		setStatus("Not enough materials", "bad")
	end,
	onClick = requestCraft,
})

Motion.attachButton(closeButton, {
	hoverScale = 1.08,
	pressScale = 0.94,
	sound = "ui.click",
	onClick = close,
})

closeButton.MouseEnter:Connect(function()
	closeGlyph.TextColor3 = Theme.Color.Text
end)
closeButton.MouseLeave:Connect(function()
	closeGlyph.TextColor3 = Theme.Color.TextDim
end)

-- Clicking the dimmed area outside the window closes it, which is what every
-- modal a player has ever used does. The window is a later sibling of the
-- backdrop, so clicks on the panel itself never reach here.
backdrop.InputBegan:Connect(function(input)
	if isOpen and input.UserInputType == Enum.UserInputType.MouseButton1 then
		close()
	end
end)

--[[
	Live filtering.

	Rebuilt on every keystroke rather than debounced: the grid is at most a few
	dozen tiles and rebuilding it is what already happens on a tab change, so
	the cost is one that has been paid on every station switch all along.
]]
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	local query = string.lower(searchBox.Text)
	if query == searchQuery then
		return
	end

	searchQuery = query
	buildGrid()
end)

-- Enter in the search box crafts the selection, so a player can type a name
-- and make it without reaching for the mouse.
searchBox.FocusLost:Connect(function(enterPressed)
	if enterPressed and selectedRecipe then
		requestCraft()
	end
end)

CraftingResult.OnClientEvent:Connect(function(ok, _recipeId, message)
	log("craft result", ok, message)

	if ok then
		setStatus(message, "good")
		Sounds.play("craft.success")
		-- Flash the thing you just made, so the eye is drawn to the result
		-- rather than to a line of text at the bottom of the panel.
		Motion.flash(detailTile, Theme.Color.Good)
		Motion.flash(detailIcon, Theme.Color.Good)
		Motion.pulse(detailTile, 1.12)
	else
		setStatus(message, "bad")
		Sounds.play("craft.fail")
		Motion.shake(window, 8)
	end
end)

-- Through the mirror rather than the remote: the wire now carries only the
-- slots that moved, and the mirror is what reassembles them into the whole bag
-- these totals are counted from.
InventoryMirror.onChanged(function(snapshot)
	table.clear(heldCounts)
	for _, slot in pairs(snapshot or {}) do
		if type(slot) == "table" and slot.name then
			heldCounts[slot.name] = (heldCounts[slot.name] or 0) + (slot.count or 0)
		end
	end

	if isOpen then
		refreshGridAffordability()
		refreshDetail()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.B then
		toggle(nil)
	elseif input.KeyCode == Enum.KeyCode.Escape and isOpen then
		close()
	elseif isOpen and (input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter) then
		-- Only reached when the search box does not have focus; typing sets
		-- `processed` and the box handles its own Enter.
		requestCraft()
	end
end)

--[[
	Walking up to a placed station and using its prompt opens the window on that
	station's tab. The prompt carries the station id as an attribute, which is
	what keeps this generic: a new station type needs no case here.
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

-- Two full-screen menus at once is never what anyone wants; the settings view
-- wins because it is the one with the escape hatch.
MenuState.Changed:Connect(function(name, opened)
	if name == "PauseMenu" and opened and isOpen then
		close()
	end
end)

-- Status messages clear themselves. Polled at 1Hz rather than run off a
-- per-frame connection, because that is all the precision this needs.
task.spawn(function()
	while true do
		task.wait(1)
		if statusClearAt > 0 and os.clock() >= statusClearAt then
			setStatus(nil)
		end
	end
end)

buildTabs()
setStation(nil)
RequestFullInventory:FireServer()
