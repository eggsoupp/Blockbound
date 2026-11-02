--[[
	AbilityStorage

	The storage column of the Tab menu: the abilities a player has bought room
	to keep, drawn as the same rows as the loadout beside it in a panel of the
	menu's own colours, and the button that buys more.

		local column = AbilityStorage.create(root, {
			x, listTop, width,       where it sits in the panel's root
			pitch, cardHeight, cardGap, visibleRows,
			newCard = fn(parent) -> card,   AbilityPanel's card builder
			onPress = fn(index, input),     a press on a stored ability
			onRefresh = fn(state),          after every redraw
		})

	THE SAME CARDS AS THE LOADOUT

	A stored ability is bought, so it must not look like a lesser thing than one
	in use. The cards come from AbilityPanel's own builder - the slot line, the
	name, the tier in its colour - so the two columns cannot drift apart; this
	file only adds the touches of gold that say these slots were paid for: the
	PREMIUM tag and the buy button.

	DRAGGING BELONGS TO AbilityPanel

	Cards travel between the two columns, so one place has to own a drag from
	start to finish and know both sides' geometry. That is the panel. This file
	tells it where its rows are (rowAt, rowTop), shows where a drop would land
	(setTarget), and sends what the drop meant to the server (store, swap,
	retrieve, move).

	THE SERVER OWNS EVERYTHING REAL. Nothing here decides how many slots a
	player has bought, whether one is free, or what ends up stored; it asks, and
	redraws when AbilityLoadout pushes back. See the storage section there.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Theme = require(script.Parent.Theme)
local MenuWindow = require(script.Parent.MenuWindow)
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local Config = require(Shared.Abilities.AbilityConfig)
local StorageConfig = require(Shared.Abilities.StorageConfig)
local Remotes = require(Shared.Net.Remotes)

local Request = Remotes.wait("AbilityStorageRequest")
local Changed = Remotes.wait("AbilityStorageChanged")

-- The premium accent: the hotbar's selection gold, kept to the touches that
-- say "paid for" - the tag by the heading and the button that buys more.
local GOLD = Theme.PixelColor.Selection

-- The menu's own greens (Shared.UI.MenuWindow), so the drawer belongs with
-- the loadout and the other pages rather than sitting beside them.
local PALETTE = MenuWindow.Palette

local HEADER_HEIGHT = 22
local FOOTER_GAP = 10
local BUY_HEIGHT = 36

-- Rows as the loadout draws them (AbilityPanel's CARD_ and STROKE_ values).
local CARD_REST = 0.3
local CARD_HOVER = 0.05
local STROKE_REST = 1
local STROKE_HOVER = 0.5

local LOCKED_ROWS = 3

-- The last thing the server said. One copy for every column on screen,
-- because there is only ever one player.
local state = {
	slots = {},
	capacity = 0,
	maxSlots = StorageConfig.MaxSlots,
	perPurchase = StorageConfig.SlotsPerPurchase,
	productId = StorageConfig.AbilityStorageProductId,
	canBuy = false,
}
local views = {}

-- productId -> "R$ 300", once Roblox has said.
local prices: { [number]: string } = {}

local function fetchPrice(productId: number?)
	if type(productId) ~= "number" or productId <= 0 or prices[productId] then
		return
	end
	prices[productId] = ""
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
		if ok and info and info.PriceInRobux then
			prices[productId] = "R$ " .. tostring(info.PriceInRobux)
			for view in pairs(views) do
				view.refresh()
			end
		end
	end)
end

local AbilityStorage = {}

-- What the panel needs to know about the store, for drops.
function AbilityStorage.state()
	return state
end

function AbilityStorage.create(root: Instance, opts)
	local pitch, cardHeight = opts.pitch, opts.cardHeight
	local listHeight = opts.visibleRows * pitch - opts.cardGap

	local column = Instance.new("Frame")
	column.Name = "Storage"
	column.BackgroundTransparency = 1
	column.Position = UDim2.fromOffset(opts.x, 0)
	column.Size = UDim2.fromOffset(opts.width, opts.listTop + listHeight + FOOTER_GAP + BUY_HEIGHT)
	column.Parent = root

	-- Its own panel, in the menu's colours: the same dark green and thin
	-- outline as the quest and bestiary pages.
	local pad = opts.pad or 0
	local headerTop = opts.headerTop or 0
	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.Position = UDim2.fromOffset(-pad, headerTop - pad)
	frame.Size = UDim2.fromOffset(opts.width + pad * 2, opts.listTop + listHeight + FOOTER_GAP + BUY_HEIGHT + pad * 2 - headerTop)
	frame.BackgroundColor3 = PALETTE.Base
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	frame.ZIndex = 0
	frame.Parent = column

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 6)
	frameCorner.Parent = frame

	local frameStroke = Instance.new("UIStroke")
	frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	frameStroke.Color = PALETTE.Line
	frameStroke.Thickness = 1.5
	frameStroke.Parent = frame

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.Position = UDim2.fromOffset(0, headerTop + HEADER_HEIGHT + 2)
	rule.Size = UDim2.fromOffset(opts.width, 1)
	rule.BackgroundColor3 = PALETTE.Line
	rule.BorderSizePixel = 0
	rule.Parent = column

	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.BackgroundTransparency = 1
	heading.Position = UDim2.fromOffset(0, headerTop)
	heading.Size = UDim2.new(1, -80, 0, HEADER_HEIGHT)
	heading.FontFace = Theme.Fonts.Heading
	heading.TextSize = Theme.TextSize.Small
	heading.TextColor3 = Theme.Color.Text
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = "STORAGE"
	heading.Parent = column

	-- A small gold tag after the heading: what makes these slots different.
	local tag = Instance.new("TextLabel")
	tag.Name = "Premium"
	tag.BackgroundTransparency = 1
	tag.Size = UDim2.fromOffset(80, HEADER_HEIGHT)
	tag.FontFace = Theme.Fonts.BodyBold
	tag.TextSize = Theme.TextSize.Small
	tag.TextColor3 = GOLD
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.Text = "PREMIUM"
	tag.Parent = column
	local function placeTag()
		tag.Position = UDim2.fromOffset(heading.TextBounds.X + 10, headerTop)
	end
	heading:GetPropertyChangedSignal("TextBounds"):Connect(placeTag)
	placeTag()

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, 0, 0, headerTop)
	count.BackgroundTransparency = 1
	count.Size = UDim2.fromOffset(80, HEADER_HEIGHT)
	count.FontFace = Theme.Fonts.BodyBold
	count.TextSize = Theme.TextSize.Small
	count.TextColor3 = Theme.Color.TextDim
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Parent = column

	local list = Instance.new("ScrollingFrame")
	list.Name = "Slots"
	list.Position = UDim2.fromOffset(0, opts.listTop)
	list.Size = UDim2.fromOffset(opts.width, listHeight)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 3
	list.ScrollBarImageColor3 = PALETTE.Line
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.fromOffset(0, listHeight)
	list.Parent = column

	-- The button that buys more: dark, outlined in gold, with what it buys on
	-- the left and the price on the right. Warms toward gold when pointed at.
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.Position = UDim2.fromOffset(0, opts.listTop + listHeight + FOOTER_GAP)
	buy.Size = UDim2.fromOffset(opts.width, BUY_HEIGHT)
	buy.AutoButtonColor = false
	buy.BorderSizePixel = 0
	buy.BackgroundColor3 = PALETTE.Raised
	buy.Text = ""
	buy.Parent = column

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 6)
	buyCorner.Parent = buy

	local buyStroke = Instance.new("UIStroke")
	buyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	buyStroke.Thickness = 1.5
	buyStroke.Parent = buy

	local buyLabel = Instance.new("TextLabel")
	buyLabel.Name = "Label"
	buyLabel.BackgroundTransparency = 1
	buyLabel.Position = UDim2.fromOffset(14, 0)
	buyLabel.Size = UDim2.new(1, -28, 1, 0)
	buyLabel.FontFace = Theme.Fonts.Heading
	buyLabel.TextSize = Theme.TextSize.Small
	buyLabel.TextXAlignment = Enum.TextXAlignment.Left
	buyLabel.Parent = buy

	local buyPrice = Instance.new("TextLabel")
	buyPrice.Name = "Price"
	buyPrice.BackgroundTransparency = 1
	buyPrice.Position = UDim2.fromOffset(14, 0)
	buyPrice.Size = UDim2.new(1, -28, 1, 0)
	buyPrice.FontFace = Theme.Fonts.BodyBold
	buyPrice.TextSize = Theme.TextSize.Body
	buyPrice.TextColor3 = Theme.Color.Text
	buyPrice.TextXAlignment = Enum.TextXAlignment.Right
	buyPrice.Parent = buy

	local rows = {}
	local target: number? = nil
	local lifted: number? = nil
	local hovered: number? = nil

	local function paintRow(index: number)
		local row = rows[index]
		local raised = index == target or index == hovered
		row.button.BackgroundTransparency = if index == lifted then 0.95 elseif raised then CARD_HOVER else CARD_REST
		row.stroke.Transparency = if index == target then 0 elseif index == lifted then 1 elseif raised then STROKE_HOVER else STROKE_REST
		row.stroke.Color = if index == target then Theme.Color.Good else Theme.Color.Text
		row.badgeStroke.Color = if index == target then Theme.Color.Good else PALETTE.Line
		row.name.TextTransparency = if index == lifted then 0.6 else 0
	end

	local function rowFor(index: number)
		local row = rows[index]
		if row then
			return row
		end

		row = opts.newCard(list)
		row.button.Name = "Stored" .. index
		row.button.Position = UDim2.fromOffset(0, (index - 1) * pitch)
		row.badge.BackgroundColor3 = PALETTE.Deep
		rows[index] = row

		row.button.MouseEnter:Connect(function()
			hovered = index
			paintRow(index)
			if state.slots[index] then
				Sounds.play("ui.hover")
			end
		end)
		row.button.MouseLeave:Connect(function()
			if hovered == index then
				hovered = nil
			end
			paintRow(index)
		end)
		row.button.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and state.slots[index] then
				opts.onPress(index, input)
			end
		end)

		return row
	end

	local function refresh()
		local capacity = state.capacity or 0
		local slots = state.slots or {}
		local locked = capacity == 0 and #slots == 0

		-- Past what was bought only if something is still stored there, so it
		-- can always be taken back out.
		local shown = if locked then LOCKED_ROWS else math.max(capacity, #slots)
		count.Text = if capacity == 0 then "" else string.format("%d / %d", #slots, capacity)

		for index = 1, math.max(shown, #rows) do
			local row = rowFor(index)
			row.button.Visible = index <= shown

			local name = slots[index]
			local def = name and Config.get(name)
			row.badge.Text = if locked then "-" else tostring(index)
			row.badge.TextColor3 = if def then Theme.Color.Text else Theme.Color.TextFaint
			row.accent.BackgroundColor3 = if def then Theme.rarityColor(def.rarity) else PALETTE.Line
			row.accent.BackgroundTransparency = if def or not locked then 0 else 0.5

			if def then
				row.name.Text = def.displayName or name
				row.name.TextColor3 = Theme.Color.Text
				row.rarity.Text = if def.rarity then string.upper(def.rarity) else ""
				row.rarity.TextColor3 = Theme.rarityColor(def.rarity)
				row.stats.Text = Config.statsText(def)
			elseif locked then
				row.stats.Text = ""
				row.name.Text = "Locked"
				row.name.TextColor3 = Theme.Color.TextFaint
				row.rarity.Text = "BUY SLOTS TO UNLOCK"
				row.rarity.TextColor3 = Theme.Color.TextFaint
			else
				row.stats.Text = ""
				row.name.Text = "Empty"
				row.name.TextColor3 = Theme.Color.TextFaint
				row.rarity.Text = "DRAG AN ABILITY HERE"
				row.rarity.TextColor3 = Theme.Color.TextFaint
			end
			paintRow(index)
		end

		list.CanvasSize = UDim2.fromOffset(0, math.max(listHeight, shown * pitch - opts.cardGap))

		if state.canBuy then
			fetchPrice(state.productId)
			local price = prices[state.productId]
			buyLabel.Text = string.format("+%d SLOTS", state.perPurchase)
			buyLabel.TextColor3 = GOLD
			buyLabel.TextXAlignment = Enum.TextXAlignment.Left
			buyPrice.Text = if price and price ~= "" then price else ""
			buyStroke.Color = GOLD
			buyStroke.Transparency = 0.3
			buy.Active = true
		else
			buyLabel.Text = if capacity >= (state.maxSlots or 0) and capacity > 0
				then "STORAGE IS FULL"
				else "NOT ON SALE YET"
			buyLabel.TextColor3 = Theme.Color.TextFaint
			buyLabel.TextXAlignment = Enum.TextXAlignment.Center
			buyPrice.Text = ""
			buyStroke.Color = PALETTE.Line
			buyStroke.Transparency = 0
			buy.Active = false
		end
		buy.BackgroundColor3 = PALETTE.Raised

		if opts.onRefresh then
			opts.onRefresh(state)
		end
	end

	buy.MouseEnter:Connect(function()
		if buy.Active then
			buy.BackgroundColor3 = PALETTE.Raised:Lerp(GOLD, 0.18)
			buyStroke.Transparency = 0
			Sounds.play("ui.hover")
		end
	end)
	buy.MouseLeave:Connect(function()
		buy.BackgroundColor3 = PALETTE.Raised
		buyStroke.Transparency = if buy.Active then 0.3 else 0
	end)
	buy.Activated:Connect(function()
		if state.canBuy then
			Sounds.play("ui.click")
			Request:FireServer("buy")
		end
	end)

	local view = { refresh = refresh, column = column }

	-- The top of row `index` in the panel's root, with the list's scroll.
	function view.rowTop(index: number): number
		return opts.listTop + (index - 1) * pitch - list.CanvasPosition.Y
	end

	--[[
		Which row a card whose middle is at `y` (root pixels) would land on:
		any slot that was bought, or the one after the last stored ability.
		nil when there is nowhere to put it.
	]]
	function view.rowAt(y: number): number?
		local shown = math.max(state.capacity or 0, #(state.slots or {}))
		if shown == 0 then
			return nil
		end
		local index = math.floor((y - opts.listTop + list.CanvasPosition.Y) / pitch) + 1
		return math.clamp(index, 1, shown)
	end

	-- Whether `y` is over the visible list rather than the header or the button.
	function view.covers(y: number): boolean
		return y >= opts.listTop - pitch * 0.5 and y <= opts.listTop + listHeight + pitch * 0.25
	end

	-- Shows where a drop would land (green), or nothing.
	function view.setTarget(index: number?)
		local old = target
		target = index
		if old and rows[old] then
			paintRow(old)
		end
		if index and rows[index] then
			paintRow(index)
		end
	end

	-- Dims the row a card was picked up from while it is in the air.
	function view.setLifted(index: number?)
		local old = lifted
		lifted = index
		if old and rows[old] then
			paintRow(old)
		end
		if index and rows[index] then
			paintRow(index)
		end
	end

	-- Scrolls a row into view when a drag hangs over the list's ends.
	function view.nudge(y: number)
		local max = math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y)
		if y < opts.listTop + 12 then
			list.CanvasPosition = Vector2.new(0, math.max(0, list.CanvasPosition.Y - 6))
		elseif y > opts.listTop + listHeight - 12 and max > 0 then
			list.CanvasPosition = Vector2.new(0, math.min(max, list.CanvasPosition.Y + 6))
		end
	end

	function view.height(): number
		return opts.listTop + listHeight + FOOTER_GAP + BUY_HEIGHT + pad
	end

	-- Requests, each answered by a push that redraws every column.
	function view.store(name: string)
		Request:FireServer("store", name)
	end
	function view.swap(stored: string, active: string)
		Request:FireServer("swap", stored, active)
	end
	function view.retrieve(name: string)
		Request:FireServer("retrieve", name)
	end
	function view.move(from: number, to: number)
		Request:FireServer("move", from, to)
	end

	-- The screen closing mid-drag leaves nothing picked out.
	function view.dismiss()
		view.setTarget(nil)
		view.setLifted(nil)
	end

	views[view] = true
	root.Destroying:Connect(function()
		views[view] = nil
	end)

	refresh()
	return view
end

Changed.OnClientEvent:Connect(function(value)
	if type(value) ~= "table" or type(value.slots) ~= "table" then
		return
	end

	state = value
	for view in pairs(views) do
		view.refresh()
	end
end)

task.defer(function()
	Request:FireServer("sync")
end)

return AbilityStorage
