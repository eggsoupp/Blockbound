--[[
	AspectInventoryWindow

	The Tab menu's INVENTORY page: every aspect the player keeps but is not
	using, as a grid of tiles (one per aspect, "3x" when they hold copies), and
	beside it the selected aspect - its picture, tier, abilities - with the
	button that makes it the aspect in use.

		local inventory = AspectInventoryWindow.new(parent, onBack)   a MenuWindow

	USING ONE REPLACES THE ASPECT IN USE, AND THAT ONE IS GONE. The panel says
	which one before the button is pressed, and Shared.UI.Confirm asks once
	more. After a use the page closes back to the main menu, where the new
	aspect lands with its flourish.

	What is stored is the server's (AbilityLoadout), read through
	Shared.UI.AbilityStorage. The aspect in use is the LocalPlayer's "Aspect"
	attribute, which AbilityClient keeps.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Theme = require(script.Parent:WaitForChild("Theme"))
local MenuWindow = require(script.Parent:WaitForChild("MenuWindow"))
local Confirm = require(script.Parent:WaitForChild("Confirm"))
local AbilityStorage = require(script.Parent:WaitForChild("AbilityStorage"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local AspectConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AspectConfig"))
local AbilityConfig = require(Shared.Abilities:WaitForChild("AbilityConfig"))

local LocalPlayer = Players.LocalPlayer

local GOLD = Theme.PixelColor.Selection
local PALETTE = MenuWindow.Palette

local WIDTH, HEIGHT = 720, 470
local TILE_W, TILE_H = 120, 132
local TILE_GAP = 8
local COLUMNS = 3
local GRID_PAD = 2
local GRID_WIDTH = COLUMNS * TILE_W + (COLUMNS - 1) * TILE_GAP + GRID_PAD * 2 + 8
local BUY_HEIGHT = 36
local TILE_ICON = 56
local DETAIL_ICON = 72
local ROW_HEIGHT = 22
local USE_HEIGHT = 38

local AspectInventoryWindow = {}

local function text(parent: Instance, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function outline(parent: Instance, color: Color3, transparency: number, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness or 1.5
	stroke.Parent = parent
	return stroke
end

local function currentAspect(): string?
	local value = LocalPlayer:GetAttribute("Aspect")
	return if type(value) == "string" and value ~= "" then value else nil
end

function AspectInventoryWindow.new(parent: Instance, onBack: () -> ())
	local window = MenuWindow.new(parent, "INVENTORY", WIDTH, HEIGHT, onBack)
	local body = window.body

	-- ---------------------------------------------------------------------
	-- The grid
	-- ---------------------------------------------------------------------

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(0, GRID_WIDTH, 1, -(BUY_HEIGHT + 10))
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 3
	grid.ScrollBarImageColor3 = PALETTE.Line
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = body

	-- Room for the tiles' outlines, which a ScrollingFrame would cut.
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, GRID_PAD)
	padding.PaddingTop = UDim.new(0, GRID_PAD)
	padding.PaddingBottom = UDim.new(0, GRID_PAD)
	padding.Parent = grid

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	layout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local empty = text(body, Theme.Fonts.Body, Theme.TextSize.Body, Theme.Color.TextDim)
	empty.Size = UDim2.new(0, GRID_WIDTH, 0, 80)
	empty.TextWrapped = true
	empty.TextXAlignment = Enum.TextXAlignment.Center
	empty.Text = "Nothing stored yet.\nWishes and scrolls land here while you already have an aspect."

	-- The extra-slots product, under the grid.
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(0, 1)
	buy.Position = UDim2.fromScale(0, 1)
	buy.Size = UDim2.fromOffset(GRID_WIDTH - 8, BUY_HEIGHT)
	buy.AutoButtonColor = false
	buy.BackgroundColor3 = PALETTE.Raised
	buy.BorderSizePixel = 0
	buy.Text = ""
	buy.Parent = body
	round(buy, 6)
	local buyStroke = outline(buy, GOLD, 0.3)
	local buyLabel = text(buy, Theme.Fonts.Heading, Theme.TextSize.Small, GOLD)
	buyLabel.Position = UDim2.fromOffset(14, 0)
	buyLabel.Size = UDim2.new(1, -28, 1, 0)
	local buyPrice = text(buy, Theme.Fonts.BodyBold, Theme.TextSize.Body, Theme.Color.Text)
	buyPrice.Position = UDim2.fromOffset(14, 0)
	buyPrice.Size = UDim2.new(1, -28, 1, 0)
	buyPrice.TextXAlignment = Enum.TextXAlignment.Right
	buy.MouseEnter:Connect(function()
		if AbilityStorage.state().canBuy then
			buy.BackgroundColor3 = PALETTE.Raised:Lerp(GOLD, 0.18)
			Sounds.play("ui.hover")
		end
	end)
	buy.MouseLeave:Connect(function()
		buy.BackgroundColor3 = PALETTE.Raised
	end)
	buy.Activated:Connect(function()
		if AbilityStorage.state().canBuy then
			Sounds.play("ui.click")
			AbilityStorage.buy()
		end
	end)

	-- ---------------------------------------------------------------------
	-- The selected aspect
	-- ---------------------------------------------------------------------

	local info = Instance.new("Frame")
	info.Name = "Details"
	info.AnchorPoint = Vector2.new(1, 0)
	info.Position = UDim2.fromScale(1, 0)
	info.Size = UDim2.new(1, -(GRID_WIDTH + 16), 1, 0)
	info.BackgroundColor3 = PALETTE.Raised
	info.BorderSizePixel = 0
	info.Parent = body
	round(info, 6)
	local infoStroke = outline(info, PALETTE.Line, 0, 2)

	local infoBadge = Instance.new("Frame")
	infoBadge.AnchorPoint = Vector2.new(0.5, 0)
	infoBadge.Position = UDim2.new(0.5, 0, 0, 14)
	infoBadge.Size = UDim2.fromOffset(DETAIL_ICON + 12, DETAIL_ICON + 12)
	infoBadge.BackgroundColor3 = PALETTE.Deep
	infoBadge.BorderSizePixel = 0
	infoBadge.Parent = info
	round(infoBadge, 6)
	local infoBadgeStroke = outline(infoBadge, PALETTE.Line, 0.2, 1)
	local infoIcon = AbilityStorage.icon(infoBadge, nil, DETAIL_ICON)
	infoIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	infoIcon.Position = UDim2.fromScale(0.5, 0.5)

	local top = 14 + DETAIL_ICON + 12 + 8
	local infoTier = text(info, Theme.Fonts.Heading, Theme.TextSize.Small, Theme.Color.TextDim)
	infoTier.Position = UDim2.fromOffset(0, top)
	infoTier.Size = UDim2.new(1, 0, 0, 16)
	infoTier.TextXAlignment = Enum.TextXAlignment.Center
	local infoName = text(info, Theme.Fonts.Heading, 26, Theme.Color.Text)
	infoName.Position = UDim2.fromOffset(0, top + 18)
	infoName.Size = UDim2.new(1, 0, 0, 28)
	infoName.TextXAlignment = Enum.TextXAlignment.Center
	local infoBlurb = text(info, Theme.Fonts.Body, Theme.TextSize.Small, Theme.Color.TextDim)
	infoBlurb.Position = UDim2.fromOffset(14, top + 48)
	infoBlurb.Size = UDim2.new(1, -28, 0, 16)
	infoBlurb.TextXAlignment = Enum.TextXAlignment.Center
	infoBlurb.TextTruncate = Enum.TextTruncate.AtEnd

	local listTop = top + 76
	local listHeading = text(info, Theme.Fonts.Heading, Theme.TextSize.Small, Theme.Color.TextDim)
	listHeading.Position = UDim2.fromOffset(14, listTop)
	listHeading.Size = UDim2.new(1, -28, 0, 16)
	listHeading.Text = "ABILITIES"
	local rule = Instance.new("Frame")
	rule.Position = UDim2.fromOffset(14, listTop + 18)
	rule.Size = UDim2.new(1, -28, 0, 1)
	rule.BackgroundColor3 = PALETTE.Line
	rule.BorderSizePixel = 0
	rule.Parent = info

	local abilityRows = {}
	local function abilityRow(index: number)
		local row = abilityRows[index]
		if row then
			return row
		end
		local y = listTop + 24 + (index - 1) * ROW_HEIGHT
		local name = text(info, Theme.Fonts.BodyBold, Theme.TextSize.Body, Theme.Color.Text)
		name.Position = UDim2.fromOffset(14, y)
		name.Size = UDim2.new(1, -28, 0, ROW_HEIGHT)
		local cost = text(info, Theme.Fonts.Body, Theme.TextSize.Small, Theme.Color.TextDim)
		cost.Position = UDim2.fromOffset(14, y)
		cost.Size = UDim2.new(1, -28, 0, ROW_HEIGHT)
		cost.TextXAlignment = Enum.TextXAlignment.Right
		row = { name = name, cost = cost }
		abilityRows[index] = row
		return row
	end

	local warning = text(info, Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.Bad)
	warning.AnchorPoint = Vector2.new(0, 1)
	warning.Position = UDim2.new(0, 14, 1, -(USE_HEIGHT + 20))
	warning.Size = UDim2.new(1, -28, 0, 16)
	warning.TextXAlignment = Enum.TextXAlignment.Center
	warning.TextTruncate = Enum.TextTruncate.AtEnd

	local use = Instance.new("TextButton")
	use.Name = "Use"
	use.AnchorPoint = Vector2.new(0.5, 1)
	use.Position = UDim2.new(0.5, 0, 1, -12)
	use.Size = UDim2.new(1, -28, 0, USE_HEIGHT)
	use.AutoButtonColor = false
	use.BorderSizePixel = 0
	use.FontFace = Theme.Fonts.Heading
	use.TextSize = Theme.TextSize.Body
	use.Parent = info
	round(use, 6)
	local useStroke = outline(use, GOLD, 0)

	-- ---------------------------------------------------------------------
	-- Drawing
	-- ---------------------------------------------------------------------

	local tiles = {}
	local groups = {}
	local selected: string? = nil

	local function paintTile(tile)
		local isSelected = tile.name == selected
		tile.stroke.Color = if isSelected then GOLD else tile.color
		tile.stroke.Transparency = if isSelected then 0 elseif tile.hovered then 0.2 else 0.6
		tile.stroke.Thickness = if isSelected then 2.5 else 1.5
		tile.button.BackgroundColor3 = if isSelected or tile.hovered then PALETTE.Raised else PALETTE.Deep
	end

	local function canUse(): boolean
		return selected ~= nil and selected ~= currentAspect()
	end

	local function drawDetails()
		local definition = AspectConfig.get(selected)
		info.Visible = definition ~= nil
		if not definition then
			return
		end

		local color = Theme.rarityColor(definition.rarity)
		infoStroke.Color = color
		infoBadgeStroke.Color = color
		AbilityStorage.setIcon(infoIcon, selected)
		infoTier.Text = string.upper(definition.rarity or "") .. " ASPECT"
		infoTier.TextColor3 = color
		infoName.Text = string.upper(definition.displayName or selected)
		infoBlurb.Text = definition.blurb or ""

		local abilities = AspectConfig.abilitiesOf(selected)
		for index = 1, math.max(#abilities, #abilityRows) do
			local row = abilityRow(index)
			local abilityName = abilities[index]
			local ability = abilityName and AbilityConfig.get(abilityName)
			row.name.Visible = ability ~= nil
			row.cost.Visible = ability ~= nil
			if ability then
				row.name.Text = ability.displayName or abilityName
				row.cost.Text = AbilityConfig.statsText(ability)
			end
		end

		local current = currentAspect()
		if selected == current then
			warning.Text = ""
			use.Text = "ALREADY IN USE"
		elseif current then
			-- Short: the panel is narrow and this must be read whole.
			warning.Text = string.format("Replaces %s for good", AspectConfig.displayName(current))
			use.Text = "USE " .. string.upper(definition.displayName or selected)
		else
			warning.Text = ""
			use.Text = "USE " .. string.upper(definition.displayName or selected)
		end
		local active = canUse()
		use.Active = active
		use.BackgroundColor3 = if active then (if current then Theme.Color.Bad else Theme.Color.Good) else PALETTE.Deep
		use.TextColor3 = if active then Color3.new(1, 1, 1) else Theme.Color.TextFaint
		useStroke.Transparency = if active then 1 else 0
		useStroke.Color = PALETTE.Line
	end

	local function choose(name: string?)
		selected = name
		for _, tile in pairs(tiles) do
			paintTile(tile)
		end
		drawDetails()
	end

	local function tileFor(name: string)
		local tile = tiles[name]
		if tile then
			return tile
		end
		local definition = AspectConfig.get(name)

		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = ""
		b.AutoButtonColor = false
		b.BackgroundColor3 = PALETTE.Deep
		b.BorderSizePixel = 0
		b.LayoutOrder = definition and definition.order or 0
		b.Parent = grid
		round(b, 6)

		local icon = AbilityStorage.icon(b, name, TILE_ICON)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 14)

		local label = text(b, Theme.Fonts.Heading, Theme.TextSize.Body, Theme.Color.Text)
		label.Position = UDim2.fromOffset(4, 14 + TILE_ICON + 10)
		label.Size = UDim2.new(1, -8, 0, 20)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = string.upper(definition and definition.displayName or name)

		local color = Theme.rarityColor(definition and definition.rarity)
		local tierLabel = text(b, Theme.Fonts.BodyBold, Theme.TextSize.Small, color)
		tierLabel.Position = UDim2.fromOffset(4, 14 + TILE_ICON + 30)
		tierLabel.Size = UDim2.new(1, -8, 0, 16)
		tierLabel.TextXAlignment = Enum.TextXAlignment.Center
		tierLabel.Text = string.upper(definition and definition.rarity or "")

		-- "3x" in the corner when there are copies.
		local copies = text(b, Theme.Fonts.Heading, Theme.TextSize.Body, GOLD)
		copies.AnchorPoint = Vector2.new(1, 0)
		copies.Position = UDim2.new(1, -8, 0, 6)
		copies.Size = UDim2.fromOffset(40, 18)
		copies.TextXAlignment = Enum.TextXAlignment.Right

		tile = {
			name = name, button = b, copies = copies, color = color, hovered = false,
			stroke = outline(b, color, 0.6),
		}
		tiles[name] = tile

		b.MouseEnter:Connect(function()
			tile.hovered = true
			paintTile(tile)
			Sounds.play("ui.hover")
		end)
		b.MouseLeave:Connect(function()
			tile.hovered = false
			paintTile(tile)
		end)
		b.Activated:Connect(function()
			if selected ~= name then
				Sounds.play("ui.click")
				choose(name)
			end
		end)

		paintTile(tile)
		return tile
	end

	local function refresh()
		local state = AbilityStorage.state()
		groups = AbilityStorage.groups()

		local present = {}
		for _, group in ipairs(groups) do
			present[group.name] = true
			local tile = tileFor(group.name)
			tile.button.Visible = true
			tile.copies.Text = if group.count > 1 then string.format("%dx", group.count) else ""
		end
		for name, tile in pairs(tiles) do
			if not present[name] then
				tile.button.Visible = false
			end
		end
		empty.Visible = #groups == 0

		local capacity = state.capacity or 0
		window.subtitle.Text = if capacity > 0
			then string.format("%d stored  -  %d / %d extra copies", #(state.slots or {}), state.extras or 0, capacity)
			else string.format("%d stored  -  one of each is free", #(state.slots or {}))

		if state.canBuy then
			buyLabel.Text = string.format("+%d SLOTS FOR EXTRA COPIES", state.perPurchase or 3)
			buyLabel.TextColor3 = GOLD
			buyPrice.Text = AbilityStorage.price()
			buyStroke.Color = GOLD
			buy.Active = true
		else
			buyLabel.Text = if capacity > 0 and capacity >= (state.maxSlots or 0) then "STORAGE IS FULL" else "EXTRA SLOTS NOT ON SALE"
			buyLabel.TextColor3 = Theme.Color.TextFaint
			buyPrice.Text = ""
			buyStroke.Color = PALETTE.Line
			buy.Active = false
		end

		-- Keep the selection while it is still stored; otherwise the first one.
		if not (selected and present[selected]) then
			selected = groups[1] and groups[1].name or nil
		end
		choose(selected)
	end

	use.MouseEnter:Connect(function()
		if use.Active then
			Sounds.play("ui.hover")
		end
	end)
	use.Activated:Connect(function()
		if not canUse() then
			return
		end
		local name = selected
		local label = AspectConfig.displayName(name)
		local current = currentAspect()
		Sounds.play("ui.click")
		Confirm.ask({
			title = string.format("Use %s?", label),
			-- Two lines at most: the dialog does not grow to fit.
			body = if current
				then string.format("%s replaces %s, and %s is gone for good.", label, AspectConfig.displayName(current), AspectConfig.displayName(current))
				else string.format("%s becomes your aspect.", label),
			accept = "Use",
			tone = if current then "bad" else nil,
		}, function(accepted)
			if accepted and name then
				AbilityStorage.use(name)
				-- Back to the menu, where the new aspect lands.
				onBack()
			end
		end)
	end)

	AbilityStorage.Changed:Connect(refresh)
	LocalPlayer:GetAttributeChangedSignal("Aspect"):Connect(drawDetails)
	refresh()

	return window
end

return AspectInventoryWindow
