--[[
	ShopClient

	The Aspect Shop: a coin button in the top bar (where the wish star was)
	and the window it opens. Every aspect is on a tile; the panel beside the
	grid shows the selected one - its tier, abilities and price - with one
	button:

	  BUY R$ 499    not bought yet: prompts its Game Pass. The purchase lands in
	                the inventory as a permanent PASS (ServerScriptService.AspectShop)
	  REDEEM PASS   a pass is in the inventory: redeeming makes the aspect
	                permanent; left unredeemed it can be traded
	  TRADED AWAY   the pass was bought and traded; Roblox sells it only once
	  EQUIP         owned permanently: makes it the aspect in use
	  EQUIPPED      already in use
	  NOT ON SALE   its Game Pass id in AspectShopConfig is still 0

	Everything sold here is PERMANENT: owned for good, equipped any time, and
	never destroyed when swapped out. The aspect in use is only lost when it
	is NOT permanent, so that is the one case that asks first.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelUI = require(UI:WaitForChild("PixelUI"))
local TopbarButtons = require(UI:WaitForChild("TopbarButtons"))
local Confirm = require(UI:WaitForChild("Confirm"))
local AbilityStorage = require(UI:WaitForChild("AbilityStorage"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AspectConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AspectConfig"))
local AbilityConfig = require(Shared.Abilities:WaitForChild("AbilityConfig"))
local ShopConfig = require(Shared.Abilities:WaitForChild("AspectShopConfig"))

local BuyRemote = Remotes.wait("AspectShopBuy")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local P = Theme.PixelColor
local GOLD = P.Selection

-- A coin, a texel to a character.
local COIN_SPRITE = {
	"....####....",
	"..########..",
	".###....###.",
	".##.####.##.",
	"##.##..##.##",
	"##.##.....##",
	"##..####..##",
	"##.....##.##",
	"##.##..##.##",
	".##.####.##.",
	".###....###.",
	"..########..",
}
local ICON_SCALE = 0.62
local RING_OUTSET = 3

local screen = Instance.new("ScreenGui")
screen.Name = "AspectShop"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 20
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- ---------------------------------------------------------------------------
-- The top-bar button
-- ---------------------------------------------------------------------------

local button = Instance.new("ImageButton")
button.Name = "Shop"
button.AutoButtonColor = false
button.AnchorPoint = Vector2.new(0, 0.5)
button.BackgroundTransparency = 1
button.Parent = screen

local face = Instance.new("Frame")
face.Name = "Content"
face.BackgroundTransparency = 1
face.Size = UDim2.fromScale(1, 1)
face.Parent = button
PixelUI.bindButton(button, { idle = "slot", hover = "slot", pressed = "slot_dark", text = P.Ink }, face)

local ring = PixelUI.image(button, "slot_highlight")
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.new(1, RING_OUTSET * 2, 1, RING_OUTSET * 2)
ring.ImageColor3 = GOLD
ring.ZIndex = 5
ring.Visible = false

local iconField = Instance.new("Frame")
iconField.AnchorPoint = Vector2.new(0.5, 0.5)
iconField.Position = UDim2.fromScale(0.5, 0.5)
iconField.Size = UDim2.fromScale(ICON_SCALE, ICON_SCALE)
iconField.BackgroundTransparency = 1
iconField.Parent = face
do
	local rows, columns = #COIN_SPRITE, #COIN_SPRITE[1]
	for row, line in ipairs(COIN_SPRITE) do
		for column = 1, columns do
			if string.sub(line, column, column) == "#" then
				local pixel = Instance.new("Frame")
				pixel.BackgroundColor3 = Color3.fromRGB(196, 132, 18)
				pixel.BorderSizePixel = 0
				pixel.Position = UDim2.fromScale((column - 1) / columns, (row - 1) / rows)
				pixel.Size = UDim2.fromScale(1 / columns, 1 / rows)
				pixel.Parent = iconField
			end
		end
	end
end

TopbarButtons.add(button, 4, function()
	return "Aspect Shop - permanent aspects"
end)

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local WIDTH, HEIGHT = 700, 440
local GRID_W, GRID_H = 392, 370
local TILE_W, TILE_H = 86, 112
local TILE_GAP = 6
local TILE_ICON = 44
local DETAIL_X = 26 + GRID_W + 12
local DETAIL_W = WIDTH - DETAIL_X - 26

local window = PixelUI.image(screen, "frame_wood")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(WIDTH, HEIGHT)
window.Visible = false
window.ZIndex = 2

local windowScale = Instance.new("UIScale")
windowScale.Parent = window
local function rescale()
	local view = workspace.CurrentCamera.ViewportSize
	windowScale.Scale = math.clamp(math.min((view.X - 24) / WIDTH, (view.Y - 90) / HEIGHT, 1.15), 0.45, 1.15)
end
rescale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

local header = PixelUI.header(window, "ASPECT SHOP")
header.Position = UDim2.new(0.5, 0, 0, 0)
header.ZIndex = 4
for _, child in ipairs(header:GetDescendants()) do
	if child:IsA("GuiObject") then
		child.ZIndex = 5
	end
end

local close = PixelUI.closeButton(window, function()
	window.Visible = false
end)
close.Position = UDim2.new(1, -10, 0, 10)
close.ZIndex = 6

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = props.font or Theme.Fonts.BodyBold
	l.TextSize = props.size or Theme.TextSize.Body
	l.TextColor3 = props.color or P.Ink
	l.TextXAlignment = props.align or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextWrapped = props.wrap or false
	l.TextTruncate = if props.wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
	l.Position = props.at or UDim2.new()
	l.Size = props.box or UDim2.fromScale(1, 1)
	l.Text = props.text or ""
	l.ZIndex = props.z or 4
	l.Parent = parent
	return l
end

-- Left: every aspect, on parchment.
local gridPanel = PixelUI.image(window, "inset_parchment")
gridPanel.Name = "Aspects"
gridPanel.Position = UDim2.fromOffset(26, 44)
gridPanel.Size = UDim2.fromOffset(GRID_W, GRID_H)
gridPanel.ZIndex = 3

local grid = Instance.new("Frame")
grid.Name = "Grid"
grid.BackgroundTransparency = 1
grid.Size = UDim2.fromScale(1, 1)
grid.ZIndex = 3
grid.Parent = gridPanel
local gridPad = Instance.new("UIPadding")
gridPad.PaddingLeft = UDim.new(0, 12)
gridPad.PaddingTop = UDim.new(0, 10)
gridPad.Parent = grid
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
layout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = grid

-- Right: the selected aspect.
local detail = PixelUI.image(window, "inset_parchment")
detail.Name = "Detail"
detail.Position = UDim2.fromOffset(DETAIL_X, 44)
detail.Size = UDim2.fromOffset(DETAIL_W, GRID_H)
detail.ZIndex = 3

local detailBadge = PixelUI.image(detail, "slot")
detailBadge.AnchorPoint = Vector2.new(0.5, 0)
detailBadge.Position = UDim2.new(0.5, 0, 0, 12)
detailBadge.Size = UDim2.fromOffset(76, 76)
detailBadge.ZIndex = 4
local detailIcon = AbilityStorage.icon(detailBadge, nil, 60)
detailIcon.AnchorPoint = Vector2.new(0.5, 0.5)
detailIcon.Position = UDim2.fromScale(0.5, 0.5)
detailIcon.ZIndex = 5

local detailTier = text(detail, { font = Theme.Fonts.Heading, size = Theme.TextSize.Small, align = Enum.TextXAlignment.Center,
	at = UDim2.fromOffset(0, 94), box = UDim2.new(1, 0, 0, 16) })
local detailName = text(detail, { font = Theme.Fonts.Heading, size = Theme.TextSize.Heading, color = P.Heading,
	align = Enum.TextXAlignment.Center, at = UDim2.fromOffset(0, 110), box = UDim2.new(1, 0, 0, 26) })
local detailBlurb = text(detail, { font = Theme.Fonts.Body, size = Theme.TextSize.Small, align = Enum.TextXAlignment.Center,
	at = UDim2.fromOffset(10, 136), box = UDim2.new(1, -20, 0, 16) })

local listTop = 160
text(detail, { text = "ABILITIES", font = Theme.Fonts.Heading, size = Theme.TextSize.Small, color = P.Heading,
	at = UDim2.fromOffset(14, listTop), box = UDim2.new(1, -28, 0, 16) })
local abilityRows = {}
local function abilityRow(index)
	local row = abilityRows[index]
	if not row then
		local y = listTop + 18 + (index - 1) * 20
		row = {
			-- Leaves room for the cost on the right: the panel is narrow.
			name = text(detail, { size = Theme.TextSize.Small, at = UDim2.fromOffset(14, y), box = UDim2.new(1, -96, 0, 20) }),
			cost = text(detail, { font = Theme.Fonts.Body, size = Theme.TextSize.Small, align = Enum.TextXAlignment.Right,
				at = UDim2.fromOffset(14, y), box = UDim2.new(1, -28, 0, 20) }),
		}
		abilityRows[index] = row
	end
	return row
end

-- What "permanent" means, said once where the decision is made.
local note = text(detail, { font = Theme.Fonts.Body, size = Theme.TextSize.Small, wrap = true, align = Enum.TextXAlignment.Center,
	-- Two lines at most at this width.
	text = "Permanent: yours for good, never lost when swapped.",
	at = UDim2.new(0, 12, 1, -112), box = UDim2.new(1, -24, 0, 36) })

local status = text(detail, { size = Theme.TextSize.Small, color = P.BadLight, align = Enum.TextXAlignment.Center,
	at = UDim2.new(0, 10, 1, -74), box = UDim2.new(1, -20, 0, 18) })

local action = PixelUI.button(detail, { text = "", color = "green", size = UDim2.new(1, -28, 0, 48) })
action.button.AnchorPoint = Vector2.new(0.5, 1)
action.button.Position = UDim2.new(0.5, 0, 1, -12)
action.button.ZIndex = 4
action.label.TextSize = Theme.TextSize.Subheading

-- ---------------------------------------------------------------------------
-- State and drawing
-- ---------------------------------------------------------------------------

local selected = AspectConfig.names()[1]
local tiles = {}

-- passId -> "R$ 499" once Roblox has said, "" while asking.
local prices: { [number]: string } = {}
local refresh -- below

local function priceOf(aspectName: string): string?
	local passId = ShopConfig.passFor(aspectName)
	if passId <= 0 then
		return nil
	end
	if prices[passId] == nil then
		prices[passId] = ""
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, passId, Enum.InfoType.GamePass)
			prices[passId] = if ok and info and info.PriceInRobux then "R$ " .. tostring(info.PriceInRobux) else "R$ ?"
			refresh()
		end)
	end
	return prices[passId]
end

local function currentAspect(): string?
	local value = player:GetAttribute("Aspect")
	return if type(value) == "string" and value ~= "" then value else nil
end

-- What the selected aspect's button does right now.
local function actionFor(aspectName: string): string
	if AbilityStorage.isPermanent(aspectName) then
		return if currentAspect() == aspectName then "equipped" else "equip"
	end
	-- An unredeemed permanent pass is in the inventory: redeem it here, or
	-- leave it there to trade.
	if AbilityStorage.passCount(aspectName) > 0 then
		return "redeem"
	end
	-- Bought once and traded away. Roblox still counts the Game Pass as owned
	-- and will not sell it again, so there is nothing to offer but the reason.
	if AbilityStorage.isClaimed(aspectName) then
		return "traded"
	end
	return if ShopConfig.passFor(aspectName) > 0 then "buy" else "soon"
end

local function tileFor(aspectName: string)
	local tile = tiles[aspectName]
	if tile then
		return tile
	end
	local definition = AspectConfig.get(aspectName)

	local b = Instance.new("ImageButton")
	b.Name = aspectName
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.LayoutOrder = definition.order or 0
	b.ZIndex = 4
	b.Parent = grid
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 4
	content.Parent = b
	PixelUI.bindButton(b, { idle = "slot", hover = "slot", pressed = "slot_dark", text = P.Ink }, content)

	local highlight = PixelUI.image(b, "slot_highlight")
	highlight.AnchorPoint = Vector2.new(0.5, 0.5)
	highlight.Position = UDim2.fromScale(0.5, 0.5)
	highlight.Size = UDim2.new(1, RING_OUTSET * 2, 1, RING_OUTSET * 2)
	highlight.ImageColor3 = GOLD
	highlight.ZIndex = 7
	highlight.Visible = false

	local icon = AbilityStorage.icon(content, aspectName, TILE_ICON)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 12)
	icon.ZIndex = 5

	local name = text(content, { text = string.upper(definition.displayName or aspectName), font = Theme.Fonts.Heading,
		size = Theme.TextSize.Small, color = Theme.rarityInk(definition.rarity), align = Enum.TextXAlignment.Center,
		at = UDim2.fromOffset(2, 60), box = UDim2.new(1, -4, 0, 16), z = 5 })
	name.Name = "AspectName"
	local line = text(content, { font = Theme.Fonts.Number, size = Theme.TextSize.Small, align = Enum.TextXAlignment.Center,
		at = UDim2.fromOffset(2, 80), box = UDim2.new(1, -4, 0, 16), z = 5 })

	-- Owned: a gold ribbon across the top, as in the inventory.
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Owned"
	ribbon.Position = UDim2.fromOffset(4, 3)
	ribbon.Size = UDim2.new(1, -8, 0, 13)
	ribbon.BackgroundColor3 = GOLD
	ribbon.BorderSizePixel = 0
	ribbon.ZIndex = 6
	ribbon.Visible = false
	ribbon.Parent = content
	text(ribbon, { text = "PERMANENT", font = Theme.Fonts.Heading, size = 10, color = P.Outline,
		align = Enum.TextXAlignment.Center, z = 6 })

	tile = { button = b, highlight = highlight, line = line, ribbon = ribbon }
	tiles[aspectName] = tile

	b.MouseEnter:Connect(function()
		Sounds.play("ui.hover")
	end)
	b.MouseButton1Click:Connect(function()
		if selected ~= aspectName then
			Sounds.play("ui.click")
			selected = aspectName
			status.Text = ""
			refresh()
		end
	end)
	return tile
end

function refresh()
	local current = currentAspect()

	for _, aspectName in ipairs(AspectConfig.names()) do
		local tile = tileFor(aspectName)
		local mode = actionFor(aspectName)
		tile.highlight.Visible = aspectName == selected
		tile.ribbon.Visible = AbilityStorage.isPermanent(aspectName)
		if mode == "equipped" then
			tile.line.Text = "EQUIPPED"
			tile.line.TextColor3 = P.Heading
		elseif mode == "equip" then
			tile.line.Text = "OWNED"
			tile.line.TextColor3 = P.Heading
		elseif mode == "buy" then
			local price = priceOf(aspectName)
			tile.line.Text = if price and price ~= "" then price else "..."
			tile.line.TextColor3 = P.Ink
		elseif mode == "redeem" then
			-- Short: the tile truncates anything longer.
			tile.line.Text = "REDEEM"
			tile.line.TextColor3 = P.Heading
		elseif mode == "traded" then
			tile.line.Text = "TRADED"
			tile.line.TextColor3 = Color3.fromRGB(120, 108, 92)
		else
			tile.line.Text = "SOON"
			tile.line.TextColor3 = Color3.fromRGB(120, 108, 92)
		end
	end

	local definition = AspectConfig.get(selected)
	if not definition then
		return
	end
	AbilityStorage.setIcon(detailIcon, selected)
	detailTier.Text = string.upper(definition.rarity or "") .. " ASPECT"
	detailTier.TextColor3 = Theme.rarityInk(definition.rarity)
	detailName.Text = string.upper(definition.displayName or selected)
	detailBlurb.Text = definition.blurb or ""

	local abilities = AspectConfig.abilitiesOf(selected)
	for index = 1, math.max(#abilities, #abilityRows) do
		local row = abilityRow(index)
		local ability = abilities[index] and AbilityConfig.get(abilities[index])
		row.name.Visible = ability ~= nil
		row.cost.Visible = ability ~= nil
		if ability then
			row.name.Text = ability.displayName or abilities[index]
			-- Mana only: with the cooldown too it runs into the name.
			row.cost.Text = string.format("%d mana", ability.manaCost or 0)
		end
	end

	local mode = actionFor(selected)
	if mode == "buy" then
		local price = priceOf(selected)
		action.label.Text = if price and price ~= "" then "BUY  " .. price else "BUY"
		action.setColor("green")
		action.setEnabled(true)
	elseif mode == "equip" then
		action.label.Text = "EQUIP"
		action.setColor("tan")
		action.setEnabled(true)
	elseif mode == "equipped" then
		action.label.Text = "EQUIPPED"
		action.setEnabled(false)
	elseif mode == "redeem" then
		action.label.Text = "REDEEM PASS"
		action.setColor("green")
		action.setEnabled(true)
	elseif mode == "traded" then
		action.label.Text = "TRADED AWAY"
		action.setEnabled(false)
	else
		action.label.Text = "NOT ON SALE"
		action.setEnabled(false)
	end
	note.Visible = mode ~= "soon"
	note.Text = if mode == "traded" then "You traded this pass away. Another can only come from a trade."
		elseif mode == "redeem" then "Redeem to keep it for good, or trade the pass instead."
		elseif mode == "buy" then "Buys a pass: redeem it to keep, or trade it unredeemed."
		else "Permanent: yours for good, never lost when swapped."
	-- A permanent aspect in use is kept; anything else in use would be lost.
	if mode == "equip" and current and not AbilityStorage.isPermanent(current) and status.Text == "" then
		status.Text = string.format("Equipping replaces %s for good", AspectConfig.displayName(current))
	elseif mode ~= "equip" and string.find(status.Text, "^Equipping") then
		status.Text = ""
	end
end

action.button.MouseButton1Click:Connect(function()
	local aspectName = selected
	local mode = actionFor(aspectName)
	if mode == "buy" then
		Sounds.play("ui.click")
		status.Text = ""
		BuyRemote:FireServer(aspectName)
	elseif mode == "redeem" then
		Sounds.play("ui.click")
		local label = AspectConfig.displayName(aspectName)
		Confirm.ask({
			title = string.format("Redeem the %s pass?", label),
			-- Two lines at most: the dialog does not grow to fit.
			body = string.format("%s becomes permanently yours. A redeemed pass can no longer be traded.", label),
			accept = "Redeem",
		}, function(accepted)
			if accepted then
				AbilityStorage.redeem(aspectName)
			end
		end)
	elseif mode == "equip" then
		Sounds.play("ui.click")
		local current = currentAspect()
		if current and not AbilityStorage.isPermanent(current) then
			local label, currentLabel = AspectConfig.displayName(aspectName), AspectConfig.displayName(current)
			Confirm.ask({
				title = string.format("Equip %s?", label),
				-- Two lines at most: the dialog does not grow to fit.
				body = string.format("%s replaces %s, and %s is gone for good.", label, currentLabel, currentLabel),
				accept = "Equip",
				tone = "bad",
			}, function(accepted)
				if accepted then
					AbilityStorage.use(aspectName)
				end
			end)
		else
			AbilityStorage.use(aspectName)
		end
	else
		Sounds.play("ui.denied")
	end
end)

AbilityStorage.Changed:Connect(refresh)
player:GetAttributeChangedSignal("Aspect"):Connect(function()
	status.Text = ""
	refresh()
end)
refresh()

button.MouseButton1Click:Connect(function()
	window.Visible = not window.Visible
	if window.Visible then
		status.Text = ""
		refresh()
	end
end)

RunService.RenderStepped:Connect(function()
	ring.Visible = window.Visible
end)
