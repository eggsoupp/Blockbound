--[[
	TradeWindow

	The window two players trade in. Client only; drawing and clicks, no rules.

		local window = TradeWindow.create(screen, {
			setOffer = function(kind, name, count) end,   -- "item" | "aspect" | "permanent"
			confirm = function(rev) end,
			unconfirm = function() end,
			cancel = function() end,
		})
		window.show(view)   -- the server's "state" (ServerScriptService.Trade)
		window.hide()
		window.isOpen()

	Three panels: YOUR BAG (everything that may be traded, with what is left
	after your offer), YOUR OFFER and THEIR OFFER.

	  click a bag tile          offer one more        right-click: all of it
	  click a tile you offered  take one back         right-click: all of it

	The server answers every click with the whole trade, and that answer is
	what is drawn. Clicks faster than the answer are counted locally so each
	one still asks for one more, not for the same number twice.

	CONFIRM is greyed out for TradeConfig.ConfirmDelay after anything changes,
	on either side - long enough to see what changed before agreeing to it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelUI = require(script.Parent:WaitForChild("PixelUI"))
local AbilityStorage = require(script.Parent:WaitForChild("AbilityStorage"))
local ItemPreview = require(script.Parent:WaitForChild("ItemPreview"))
local ItemThumbnails = require(script.Parent:WaitForChild("ItemThumbnails"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local InventoryMirror = require(Shared:WaitForChild("Inventory"):WaitForChild("InventoryMirror"))
local AspectConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AspectConfig"))
local TradeConfig = require(Shared:WaitForChild("Trade"):WaitForChild("TradeConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local P = Theme.PixelColor

local TradeWindow = {}

local WIDTH, HEIGHT = 780, 470
local TOP = 44
local BAG_X, BAG_W, BAG_H = 22, 250, 404
local OFFER_W, OFFER_H = 228, 300
local MINE_X = BAG_X + BAG_W + 12
local THEIRS_X = MINE_X + OFFER_W + 12
local TILE, GAP = 50, 6
local ICON = 36

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = props.font or Theme.Fonts.BodyBold
	l.TextSize = props.size or Theme.TextSize.Small
	l.TextColor3 = props.color or P.Ink
	l.TextXAlignment = props.align or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Position = props.at or UDim2.new()
	l.Size = props.box or UDim2.fromScale(1, 1)
	l.Text = props.text or ""
	l.ZIndex = props.z or 4
	l.Parent = parent
	return l
end

local function itemLabel(name: string): string
	local definition = ItemDefinitions[name]
	local text = (definition and definition.displayName) or name
	return (string.gsub(text, "(%l)(%u)", "%1 %2"))
end

local function entryLabel(kind: string, name: string): string
	if kind == "permanent" then
		return "Permanent " .. AspectConfig.displayName(name) .. " pass (unredeemed)"
	end
	return if kind == "aspect" then AspectConfig.displayName(name) .. " aspect" else itemLabel(name)
end

--[[
	A grid of tiles that keeps its tiles between redraws, one per "kind:name",
	so a live item preview is not torn down and rebuilt on every click.

	grid.set({ { kind, n, c, dim? }, ... }) draws exactly that list, in order.
]]
local function newGrid(parent: GuiObject, onClick, onHover)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(TILE, TILE)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent

	local tiles = {}
	local grid = {}

	local function build(kind: string, name: string)
		local button = Instance.new("ImageButton")
		button.Name = kind .. "_" .. name
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.ZIndex = 4
		local face = Instance.new("Frame")
		face.BackgroundTransparency = 1
		face.Size = UDim2.fromScale(1, 1)
		face.ZIndex = 4
		face.Parent = button
		PixelUI.bindButton(button, { idle = "slot", hover = "slot", pressed = "slot_dark", text = P.Ink }, face)

		local icon
		local fallback = label(face, { align = Enum.TextXAlignment.Center, z = 6 })
		fallback.TextWrapped = true
		fallback.TextTruncate = Enum.TextTruncate.None
		fallback.TextSize = 11
		fallback.Visible = false

		if kind == "permanent" then
			icon = AbilityStorage.icon(face, name, ICON)
			-- The gold ribbon permanent aspects wear in the shop and inventory.
			local ribbon = Instance.new("Frame")
			ribbon.BorderSizePixel = 0
			ribbon.BackgroundColor3 = P.Selection
			ribbon.Position = UDim2.fromOffset(4, 4)
			ribbon.Size = UDim2.new(1, -8, 0, 11)
			ribbon.ZIndex = 6
			ribbon.Parent = face
			local word = label(ribbon, { text = "PASS", font = Theme.Fonts.Heading, color = P.Outline,
				align = Enum.TextXAlignment.Center, z = 7 })
			word.TextSize = 9
		elseif kind == "aspect" then
			icon = AbilityStorage.icon(face, name, ICON)
			-- A rule in the aspect's tier colour: aspects and items share a grid.
			local tier = Instance.new("Frame")
			tier.BorderSizePixel = 0
			tier.BackgroundColor3 = Theme.rarityColor((AspectConfig.get(name) or {}).rarity)
			tier.Position = UDim2.fromOffset(5, 5)
			tier.Size = UDim2.new(1, -10, 0, 3)
			tier.ZIndex = 6
			tier.Parent = face
		else
			icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.fromOffset(ICON, ICON)
			icon.Parent = face
			-- A live view, then a picture, then the name: the bag's own order.
			local definition = ItemDefinitions[name]
			local wantsImage = definition and type(definition.thumbnail) == "string" and definition.thumbnail ~= ""
			if wantsImage or not ItemPreview.fillSlot(icon, name) then
				ItemThumbnails.bind(icon, name, function(image)
					if image == "" and icon.Parent and not ItemPreview.fillSlot(icon, name) then
						fallback.Text = itemLabel(name)
						fallback.Visible = true
					end
				end)
			end
		end
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 5

		local count = label(face, { font = Theme.Fonts.Number, size = Theme.TextSize.Count, color = Color3.new(1, 1, 1),
			align = Enum.TextXAlignment.Right, at = UDim2.new(0, 0, 1, -22), box = UDim2.new(1, -5, 0, 20), z = 7 })
		count.TextStrokeTransparency = 0.4

		local tile = { button = button, icon = icon, count = count, kind = kind, name = name, amount = 0 }

		button.MouseEnter:Connect(function()
			onHover(tile)
		end)
		button.MouseLeave:Connect(function()
			onHover(nil)
		end)
		button.MouseButton1Click:Connect(function()
			onClick(tile, false)
		end)
		button.MouseButton2Click:Connect(function()
			onClick(tile, true)
		end)

		button.Parent = parent
		return tile
	end

	function grid.set(entries)
		local wanted = {}
		for order, entry in ipairs(entries) do
			local key = entry.kind .. ":" .. entry.n
			wanted[key] = true
			local tile = tiles[key]
			if not tile then
				tile = build(entry.kind, entry.n)
				tiles[key] = tile
			end
			tile.amount = entry.c
			tile.button.LayoutOrder = order
			tile.count.Text = if entry.c > 1 then tostring(entry.c) elseif entry.c <= 0 then "0" else ""
			tile.icon.ImageTransparency = if entry.dim then 0.6 else 0
			tile.button.ImageTransparency = if entry.dim then 0.4 else 0
		end
		for key, tile in pairs(tiles) do
			if not wanted[key] then
				if tile.kind == "item" then
					ItemPreview.releaseSlot(tile.icon)
					ItemThumbnails.bind(tile.icon, nil)
				end
				tile.button:Destroy()
				tiles[key] = nil
			end
		end
	end

	return grid
end

function TradeWindow.create(screen: ScreenGui, callbacks)
	local window = PixelUI.image(screen, "frame_wood")
	window.Name = "TradeWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	window.Visible = false
	window.ZIndex = 2
	-- Clicks on the wood must not reach the world behind it.
	window.Active = true

	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function rescale()
		local view = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min((view.X - 24) / WIDTH, (view.Y - 90) / HEIGHT, 1.15), 0.4, 1.15)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local header = PixelUI.header(window, "TRADE")
	header.Position = UDim2.new(0.5, 0, 0, 0)
	header.ZIndex = 4
	for _, child in ipairs(header:GetDescendants()) do
		if child:IsA("GuiObject") then
			child.ZIndex = 5
		end
	end

	local close = PixelUI.closeButton(window, function()
		callbacks.cancel()
	end)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.ZIndex = 6

	local function panel(name: string, x: number, width: number, height: number)
		local frame = PixelUI.image(window, "inset_parchment")
		frame.Name = name
		frame.Position = UDim2.fromOffset(x, TOP)
		frame.Size = UDim2.fromOffset(width, height)
		frame.ZIndex = 3
		local title = label(frame, { font = Theme.Fonts.Heading, color = P.Heading,
			at = UDim2.fromOffset(12, 8), box = UDim2.new(1, -24, 0, 18) })
		return frame, title
	end

	-- State the handlers below read.
	local view = nil
	-- What I have asked for but not yet heard back about: [kind][name] = count.
	local asked = { item = {}, aspect = {}, permanent = {} }

	local function clearAsked()
		table.clear(asked.item)
		table.clear(asked.aspect)
		table.clear(asked.permanent)
	end

	-- One side's entries of one kind, as the server sent them.
	local function listed(side, kind: string)
		local list = if kind == "item" then side.items elseif kind == "aspect" then side.aspects else side.permanent
		return list or {}
	end
	local confirmAt = 0
	local hoverText = ""
	local refresh

	local function offered(kind: string, name: string): number
		local local_ = asked[kind][name]
		if local_ ~= nil then
			return local_
		end
		if view then
			for _, entry in ipairs(listed(view.mine, kind)) do
				if entry.n == name then
					return entry.c
				end
			end
		end
		return 0
	end

	-- How many of something I hold that could be traded at all.
	local function held(kind: string, name: string): number
		local total = 0
		if kind == "permanent" then
			total = AbilityStorage.passCount(name)
		elseif kind == "aspect" then
			for _, stored in ipairs(AbilityStorage.state().slots or {}) do
				if stored == name then
					total += 1
				end
			end
		else
			for _, slot in pairs(InventoryMirror.get()) do
				if slot.name == name then
					total += slot.count or 0
				end
			end
		end
		return total
	end

	local function open(): boolean
		return view ~= nil and view.phase == "open"
	end

	local function setOffer(kind: string, name: string, count: number)
		count = math.clamp(count, 0, held(kind, name))
		if count == offered(kind, name) then
			Sounds.play("ui.denied")
			return
		end
		Sounds.play("ui.click")
		asked[kind][name] = count
		callbacks.setOffer(kind, name, count)
		refresh()
	end

	local function hover(tile)
		hoverText = if tile then entryLabel(tile.kind, tile.name) else ""
		refresh()
	end

	-- YOUR BAG
	local bagPanel, bagTitle = panel("Bag", BAG_X, BAG_W, BAG_H)
	bagTitle.Text = "YOUR BAG"
	local bagScroll = Instance.new("ScrollingFrame")
	bagScroll.BackgroundTransparency = 1
	bagScroll.BorderSizePixel = 0
	bagScroll.Position = UDim2.fromOffset(10, 32)
	bagScroll.Size = UDim2.new(1, -16, 1, -62)
	bagScroll.CanvasSize = UDim2.new()
	bagScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bagScroll.ScrollBarThickness = 6
	bagScroll.ZIndex = 3
	bagScroll.Parent = bagPanel
	PixelUI.styleScrollBar(bagScroll)
	label(bagPanel, { text = "Click: one    Right-click: all", font = Theme.Fonts.Body, color = P.InkSoft,
		align = Enum.TextXAlignment.Center, at = UDim2.new(0, 8, 1, -26), box = UDim2.new(1, -16, 0, 18) })

	local bagGrid = newGrid(bagScroll, function(tile, all)
		if open() then
			local now = offered(tile.kind, tile.name)
			setOffer(tile.kind, tile.name, if all then math.huge else now + 1)
		end
	end, hover)

	-- The two offers
	local function offerPanel(name: string, x: number, mine: boolean)
		local frame, title = panel(name, x, OFFER_W, OFFER_H)
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.fromOffset(9, 34)
		holder.Size = UDim2.new(1, -18, 1, -70)
		holder.ZIndex = 3
		holder.Parent = frame

		local grid = newGrid(holder, function(tile, all)
			if mine and open() then
				setOffer(tile.kind, tile.name, if all then 0 else offered(tile.kind, tile.name) - 1)
			end
		end, hover)

		local ready = Instance.new("Frame")
		ready.BorderSizePixel = 0
		ready.Position = UDim2.new(0, 8, 1, -30)
		ready.Size = UDim2.new(1, -16, 0, 22)
		ready.ZIndex = 4
		ready.Parent = frame
		local readyText = label(ready, { font = Theme.Fonts.Heading, align = Enum.TextXAlignment.Center, z = 5 })

		return { title = title, grid = grid, ready = ready, readyText = readyText }
	end

	local minePanel = offerPanel("Mine", MINE_X, true)
	local theirsPanel = offerPanel("Theirs", THEIRS_X, false)
	minePanel.title.Text = "YOUR OFFER"

	local status = label(window, { align = Enum.TextXAlignment.Center, color = P.OnWood,
		at = UDim2.fromOffset(MINE_X, TOP + OFFER_H + 8), box = UDim2.fromOffset(OFFER_W * 2 + 12, 22) })

	local confirm = PixelUI.button(window, { text = "CONFIRM", color = "green", size = UDim2.fromOffset(OFFER_W, 52) })
	confirm.button.Position = UDim2.fromOffset(MINE_X, TOP + OFFER_H + 40)
	confirm.button.ZIndex = 4

	local cancel = PixelUI.button(window, { text = "CANCEL", color = "red", size = UDim2.fromOffset(OFFER_W, 52) })
	cancel.button.Position = UDim2.fromOffset(THEIRS_X, TOP + OFFER_H + 40)
	cancel.button.ZIndex = 4

	local function drawReady(target, confirmed: boolean)
		target.ready.BackgroundColor3 = if confirmed then P.Good else P.InkFaint
		target.readyText.Text = if confirmed then "READY" else "NOT READY"
		target.readyText.TextColor3 = if confirmed then P.OnGreen else P.OnWood
	end

	local function offerEntries(side)
		local entries = {}
		for _, entry in ipairs(listed(side, "permanent")) do
			table.insert(entries, { kind = "permanent", n = entry.n, c = entry.c })
		end
		for _, entry in ipairs(side.aspects) do
			table.insert(entries, { kind = "aspect", n = entry.n, c = entry.c })
		end
		for _, entry in ipairs(side.items) do
			table.insert(entries, { kind = "item", n = entry.n, c = entry.c })
		end
		return entries
	end

	-- Everything I hold that may be traded, showing what is left after my offer.
	local function bagEntries()
		local entries = {}
		for _, group in ipairs(AbilityStorage.groups()) do
			-- Unredeemed permanent passes. A redeemed aspect is not listed.
			if group.passes > 0 and TradeConfig.permanentTradable(group.name) then
				local left = group.passes - offered("permanent", group.name)
				table.insert(entries, { kind = "permanent", n = group.name, c = left, dim = left <= 0 })
			end
		end
		for _, group in ipairs(AbilityStorage.groups()) do
			if group.count > 0 and TradeConfig.aspectTradable(group.name) then
				local left = group.count - offered("aspect", group.name)
				table.insert(entries, { kind = "aspect", n = group.name, c = left, dim = left <= 0 })
			end
		end

		local totals, names = {}, {}
		for _, slot in pairs(InventoryMirror.get()) do
			if slot.name and (slot.count or 0) > 0 and TradeConfig.itemTradable(slot.name) then
				if not totals[slot.name] then
					totals[slot.name] = 0
					table.insert(names, slot.name)
				end
				totals[slot.name] += slot.count
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			local left = totals[name] - offered("item", name)
			table.insert(entries, { kind = "item", n = name, c = left, dim = left <= 0 })
		end
		return entries
	end

	function refresh()
		if not view then
			return
		end

		local settling = view.phase ~= "open"
		local waitLeft = math.max(0, confirmAt - os.clock())
		local empty = #view.mine.items + #view.mine.aspects + #listed(view.mine, "permanent")
			+ #view.theirs.items + #view.theirs.aspects + #listed(view.theirs, "permanent") == 0

		theirsPanel.title.Text = string.upper(view.partner.name) .. "'S OFFER"
		bagGrid.set(bagEntries())
		minePanel.grid.set(offerEntries(view.mine))
		theirsPanel.grid.set(offerEntries(view.theirs))
		drawReady(minePanel, view.mine.confirmed)
		drawReady(theirsPanel, view.theirs.confirmed)

		if settling then
			confirm.label.Text = "COMPLETING..."
			confirm.setEnabled(false)
		elseif view.mine.confirmed then
			confirm.label.Text = "UNDO CONFIRM"
			confirm.setColor("tan")
			confirm.setEnabled(true)
		else
			confirm.label.Text = if waitLeft > 0 then string.format("CONFIRM  %d", math.ceil(waitLeft)) else "CONFIRM"
			confirm.setColor("green")
			confirm.setEnabled(waitLeft <= 0 and not empty)
		end
		cancel.setEnabled(not settling)

		if hoverText ~= "" then
			status.Text = hoverText
		elseif settling then
			status.Text = "Completing the trade - do not leave"
		elseif view.mine.confirmed and not view.theirs.confirmed then
			status.Text = "Waiting for " .. view.partner.name
		elseif view.theirs.confirmed then
			status.Text = view.partner.name .. " is ready"
		elseif empty then
			status.Text = "Click something in your bag to offer it"
		else
			status.Text = "Any change resets both confirmations"
		end
	end

	confirm.button.MouseButton1Click:Connect(function()
		if not open() or confirm.getStyle() == "disabled" then
			Sounds.play("ui.denied")
			return
		end
		Sounds.play("ui.click")
		if view.mine.confirmed then
			callbacks.unconfirm()
		else
			callbacks.confirm(view.rev)
		end
	end)

	cancel.button.MouseButton1Click:Connect(function()
		if not open() then
			Sounds.play("ui.denied")
			return
		end
		Sounds.play("ui.click")
		callbacks.cancel()
	end)

	-- The countdown on CONFIRM, and the bag changing under an open trade.
	local lastWhole = -1
	RunService.Heartbeat:Connect(function()
		if view and window.Visible then
			local whole = math.ceil(math.max(0, confirmAt - os.clock()))
			if whole ~= lastWhole then
				lastWhole = whole
				refresh()
			end
		end
	end)
	InventoryMirror.onChanged(function()
		if view and window.Visible then
			refresh()
		end
	end)
	AbilityStorage.Changed:Connect(function()
		if view and window.Visible then
			refresh()
		end
	end)

	local handle = {}

	function handle.show(newView)
		local wasOpen = window.Visible
		view = newView
		-- The server has spoken: its counts replace anything asked for locally.
		clearAsked()
		confirmAt = os.clock() + (tonumber(newView.confirmIn) or 0)
		window.Visible = true
		if not wasOpen then
			Sounds.play("ui.open")
		end
		refresh()
	end

	function handle.hide()
		if window.Visible then
			Sounds.play("ui.close")
		end
		window.Visible = false
		view = nil
		hoverText = ""
		clearAsked()
		bagGrid.set({})
		minePanel.grid.set({})
		theirsPanel.grid.set({})
	end

	function handle.isOpen(): boolean
		return window.Visible
	end

	return handle
end

return TradeWindow
