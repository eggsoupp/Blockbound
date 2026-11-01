--[[
	AbilityStorage

	The panel behind the storage box in the ability screen: slots an ability
	can be parked in instead of thrown away, the swap that gets one back out
	when the loadout is already full, and the button that buys more of them.

	WHAT LIVES WHERE

	The BOX ITSELF is built by AbilityPanel, which also positions it, sizes it
	and lights it up while a card is over it. That is deliberate: the box and
	the bin are the two things a card can be dragged onto, they sit one above
	the other, and they have to be the same control in two flavours. Drawn from
	here they were half the bin's size and signalled "armed" a different way,
	which read as one control and one decoration.

	So this file owns the BEHAVIOUR - what opens, what the slots say, and which
	request goes to the server - and takes the finished button as an argument.

	THE SERVER OWNS EVERYTHING REAL. Nothing here decides how many slots a
	player has bought, whether one is free, or what ends up stored; it asks, and
	redraws when AbilityLoadout pushes back. See the storage section there.

	BUYING MORE

	Storage is sold StorageConfig.SlotsPerPurchase slots at a time, as often as
	a player likes up to MaxSlots, so the list scrolls and the button at the
	bottom is always "+3 more" until there is no more to buy. The price is
	Roblox's, read once per product and shown on the button.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Theme = require(script.Parent.Theme)
local Config = require(Shared.Abilities.AbilityConfig)
local StorageConfig = require(Shared.Abilities.StorageConfig)
local Remotes = require(Shared.Net.Remotes)

local Request = Remotes.wait("AbilityStorageRequest")
local Changed = Remotes.wait("AbilityStorageChanged")

-- Measured to stay inside the ability screen's panel, which clips: three rows
-- show at once and the rest scroll.
local HEADING_HEIGHT = 32
local ROW_HEIGHT = 40
local ROW_GAP = 4
local VISIBLE_ROWS = 3
local FOOTER_HEIGHT = 46
local INSET = 8
local LIST_HEIGHT = VISIBLE_ROWS * (ROW_HEIGHT + ROW_GAP)
local PANEL_HEIGHT = HEADING_HEIGHT + LIST_HEIGHT + FOOTER_HEIGHT

local BUY_COLOR = Theme.Color.Good
local BUY_TEXT = Color3.new(1, 1, 1)

-- The last thing the server said. One copy for every panel on screen, because
-- there is only ever one player.
local state = {
	slots = {},
	capacity = 0,
	maxSlots = StorageConfig.MaxSlots,
	perPurchase = StorageConfig.SlotsPerPurchase,
	productId = StorageConfig.AbilityStorageProductId,
	canBuy = false,
}
local views = {}

-- productId -> "R$ 49", once Roblox has said.
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

local function newLabel(parent: Instance, text: string, size: number, color: Color3)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.BodyBold
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.ZIndex = 31
	label.Parent = parent
	return label
end

--[[
	button      the box, already built and placed by AbilityPanel
	panelX      where the drop-down sits, which is over the cards
	panelWidth  and how wide, which is a card
	getActive   the loadout as it is on screen right now, for the swap list
]]
function AbilityStorage.create(parent, button, panelX, panelWidth, getActive)
	local panel = Instance.new("Frame")
	panel.Name = "StoredAbilities"
	panel.Position = UDim2.fromOffset(panelX, 0)
	panel.Size = UDim2.fromOffset(panelWidth, PANEL_HEIGHT)
	panel.BackgroundColor3 = Theme.Color.Panel
	panel.BorderSizePixel = 0
	panel.ZIndex = 30
	panel.Visible = false
	panel.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Stroke
	stroke.Parent = panel

	local heading = newLabel(panel, "", 14, Theme.Color.Text)
	heading.Position = UDim2.fromOffset(INSET + 2, 0)
	heading.Size = UDim2.new(1, -(INSET + 2), 0, HEADING_HEIGHT)
	heading.TextXAlignment = Enum.TextXAlignment.Left

	-- How many are used of how many bought, beside the close button.
	local count = newLabel(panel, "", 14, Theme.Color.TextDim)
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -36, 0, 0)
	count.Size = UDim2.fromOffset(70, HEADING_HEIGHT)
	count.TextXAlignment = Enum.TextXAlignment.Right

	local close = Instance.new("TextButton")
	close.Text = "×"
	close.Size = UDim2.fromOffset(32, 32)
	close.Position = UDim2.new(1, -34, 0, 0)
	close.BackgroundTransparency = 1
	close.TextColor3 = Theme.Color.Text
	close.TextSize = 22
	close.ZIndex = 31
	close.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Name = "Slots"
	list.Position = UDim2.fromOffset(INSET, HEADING_HEIGHT)
	list.Size = UDim2.new(1, -INSET, 0, LIST_HEIGHT)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = Theme.Color.TextDim
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = 31
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- Said instead of rows while there are none: what storage is, before
	-- anyone has bought it.
	local empty = newLabel(list, "", 13, Theme.Color.TextDim)
	empty.FontFace = Theme.Fonts.Body
	empty.Size = UDim2.new(1, -INSET, 0, LIST_HEIGHT - ROW_GAP)
	empty.TextWrapped = true
	empty.Text = string.format(
		"Keep abilities you are not using here instead of dropping them. Each purchase adds %d slots.",
		state.perPurchase
	)

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(0, 1)
	buy.Position = UDim2.new(0, INSET, 1, -INSET)
	buy.Size = UDim2.new(1, -INSET * 2, 0, FOOTER_HEIGHT - INSET * 2 + 4)
	buy.AutoButtonColor = true
	buy.BorderSizePixel = 0
	buy.FontFace = Theme.Fonts.BodyBold
	buy.TextSize = 14
	buy.ZIndex = 31
	buy.Parent = panel

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 4)
	buyCorner.Parent = buy

	-- Set while a stored ability is waiting to be traded for an active one, so
	-- the rows list the LOADOUT instead of the store.
	local swapName = nil
	local rows = {}

	local function rowAt(index: number): TextButton
		local row = rows[index]
		if row then
			return row
		end

		row = Instance.new("TextButton")
		row.Name = "Slot" .. index
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -INSET, 0, ROW_HEIGHT)
		row.BackgroundColor3 = Theme.Color.PanelRaised
		row.BorderSizePixel = 0
		row.FontFace = Theme.Fonts.Body
		row.TextSize = 14
		row.ZIndex = 31
		row.Parent = list

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = row

		row.Activated:Connect(function()
			if swapName then
				-- Second half of a swap: this row is an ACTIVE ability now.
				local active = getActive()[index]
				if active then
					Request:FireServer("swap", swapName, active)
					swapName = nil
					for view in pairs(views) do
						view.refresh()
					end
				end
				return
			end

			local name = state.slots[index]
			if not name then
				return
			end

			-- A full loadout has nowhere to put this, so the click becomes the
			-- first half of a swap rather than a refusal.
			-- Config.SlotCount, not a 3: the server checks the same number, and
			-- two copies of it is how they come to disagree.
			if #getActive() >= Config.SlotCount then
				swapName = name
				for view in pairs(views) do
					view.refresh()
				end
			else
				Request:FireServer("retrieve", name)
			end
		end)

		rows[index] = row
		return row
	end

	local function refresh()
		local capacity = state.capacity or 0
		local slots = state.slots or {}
		local listed = if swapName then getActive() else slots

		heading.Text = if swapName then "SWAP WITH ACTIVE ABILITY" else "ABILITY STORAGE"
		count.Text = if swapName or capacity == 0 then "" else string.format("%d / %d", #slots, capacity)

		-- Past what was bought only if something is still stored there, so
		-- it can always be taken back out.
		local shown = if swapName then #listed else math.max(capacity, #slots)
		empty.Visible = shown == 0

		for index = 1, math.max(shown, #rows) do
			local row = rowAt(index)
			row.Visible = index <= shown

			local name = listed[index]
			local def = name and Config.get(name)
			row.Text = if def
				then (def.displayName or name) .. (if swapName then "" else "  ·  take out")
				else "Empty slot"
			row.TextColor3 = if def then Theme.rarityColor(def.rarity) else Theme.Color.TextDim
		end

		if swapName then
			buy.Text = "CANCEL"
			buy.BackgroundColor3 = Theme.Color.PanelRaised
			buy.TextColor3 = Theme.Color.Text
			buy.Active = true
		elseif state.canBuy then
			fetchPrice(state.productId)
			local price = prices[state.productId]
			buy.Text = string.format("+%d SLOTS", state.perPurchase)
				.. (if price and price ~= "" then "  ·  " .. price else "")
			buy.BackgroundColor3 = BUY_COLOR
			buy.TextColor3 = BUY_TEXT
			buy.Active = true
		else
			buy.Text = if capacity >= (state.maxSlots or 0) and capacity > 0
				then string.format("MAXIMUM STORAGE  ·  %d SLOTS", capacity)
				else "MORE STORAGE IS NOT ON SALE YET"
			buy.BackgroundColor3 = Theme.Color.PanelRaised
			buy.TextColor3 = Theme.Color.TextDim
			buy.Active = false
		end
		buy.AutoButtonColor = buy.Active
	end

	buy.Activated:Connect(function()
		if swapName then
			swapName = nil
			refresh()
		elseif state.canBuy then
			Request:FireServer("buy")
		end
	end)

	close.Activated:Connect(function()
		panel.Visible = false
		swapName = nil
	end)

	button.Activated:Connect(function()
		swapName = nil
		refresh()
		panel.Visible = not panel.Visible
		Request:FireServer("sync")
	end)

	local view = { button = button, panel = panel, refresh = refresh }

	-- Called when the ability screen closes, so storage is not still hanging
	-- open the next time it is opened.
	function view.dismiss()
		panel.Visible = false
		swapName = nil
	end

	function view.store(name)
		if name then
			Request:FireServer("store", name)
		end
	end

	views[view] = true
	parent.Destroying:Connect(function()
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
