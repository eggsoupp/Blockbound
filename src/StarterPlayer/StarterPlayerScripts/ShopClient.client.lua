--[[
	ShopClient

	The Aspect Shop: a coin button in the top bar, and the Starfall
	Merchant's prompt at spawn, open one window: a scrolling list with one
	row per aspect - its icon, name, tier and three abilities - and that
	row's button:

	  R$ 499        not bought yet: prompts its Game Pass. The purchase lands in
	                the inventory as a permanent PASS (ServerScriptService.AspectShop)
	  REDEEM        a pass is in the inventory: redeeming makes the aspect
	                permanent; left unredeemed it can be traded
	  TRADED        the pass was bought and traded; Roblox sells it only once
	  EQUIP         owned permanently: makes it the aspect in use
	  EQUIPPED      already in use
	  SOON          its Game Pass id in AspectShopConfig is still 0

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
-- The window: a scrolling list, one row per aspect
-- ---------------------------------------------------------------------------

local WIDTH, HEIGHT = 500, 470
local LIST_X, LIST_Y = 22, 46
local LIST_W, LIST_H = WIDTH - 44, 352
local ROW_H = 88
local ROW_GAP = 6
local ROW_ICON = 52
local BUTTON_W, BUTTON_H = 124, 46

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

local listPanel = PixelUI.image(window, "inset_parchment")
listPanel.Name = "Aspects"
listPanel.Position = UDim2.fromOffset(LIST_X, LIST_Y)
listPanel.Size = UDim2.fromOffset(LIST_W, LIST_H)
listPanel.ZIndex = 3

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(8, 8)
list.Size = UDim2.new(1, -16, 1, -16)
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
list.ZIndex = 4
list.Parent = listPanel
PixelUI.styleScrollBar(list)
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, ROW_GAP)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list
local listPad = Instance.new("UIPadding")
listPad.PaddingRight = UDim.new(0, 6)
listPad.Parent = list

-- What "permanent" means, said once, under the list.
local note = text(window, { font = Theme.Fonts.Body, size = Theme.TextSize.Small, color = P.OnWood, wrap = true,
	align = Enum.TextXAlignment.Center,
	text = "Everything here is permanent: yours for good, never lost when swapped.",
	at = UDim2.fromOffset(LIST_X, LIST_Y + LIST_H + 6), box = UDim2.fromOffset(LIST_W, 34) })
note.TextStrokeColor3 = P.Outline
note.TextStrokeTransparency = 0.4

local status = text(window, { size = Theme.TextSize.Small, color = P.BadLight, align = Enum.TextXAlignment.Center,
	at = UDim2.fromOffset(LIST_X, LIST_Y + LIST_H + 40), box = UDim2.fromOffset(LIST_W, 18) })

-- ---------------------------------------------------------------------------
-- State and drawing
-- ---------------------------------------------------------------------------

local rows = {}

-- passId -> "R$ 499" once Roblox has said, "" while asking.
local prices: { [number]: string } = {}
local refresh -- below
local perform -- below

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

-- What an aspect's button does right now.
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

local function rowFor(aspectName: string)
	local row = rows[aspectName]
	if row then
		return row
	end
	local definition = AspectConfig.get(aspectName)

	local frame = PixelUI.image(list, "slot")
	frame.Name = aspectName
	frame.LayoutOrder = definition.order or 0
	frame.Size = UDim2.new(1, 0, 0, ROW_H)
	frame.ZIndex = 4

	local icon = AbilityStorage.icon(frame, aspectName, ROW_ICON)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0, ROW_H / 2)
	icon.ZIndex = 5

	local textX = 12 + ROW_ICON + 12
	local textW = -(textX + BUTTON_W + 18)
	text(frame, { text = string.upper(definition.displayName or aspectName), font = Theme.Fonts.Heading,
		size = Theme.TextSize.Subheading, color = Theme.rarityInk(definition.rarity),
		at = UDim2.fromOffset(textX, 8), box = UDim2.new(1, textW, 0, 22), z = 5 })
	local tier = text(frame, { font = Theme.Fonts.Heading, size = 12, color = P.Heading,
		at = UDim2.fromOffset(textX, 30), box = UDim2.new(1, textW, 0, 16), z = 5 })
	-- The three abilities, by name.
	local names = {}
	for _, abilityName in ipairs(AspectConfig.abilitiesOf(aspectName)) do
		local ability = AbilityConfig.get(abilityName)
		table.insert(names, ability and ability.displayName or abilityName)
	end
	-- Wraps onto a second line rather than cutting the last name off.
	local abilities = text(frame, { text = table.concat(names, " · "), font = Theme.Fonts.Body, size = 13, wrap = true,
		at = UDim2.fromOffset(textX, 47), box = UDim2.new(1, textW, 0, 34), z = 5 })
	abilities.TextYAlignment = Enum.TextYAlignment.Top

	local action = PixelUI.button(frame, {
		text = "",
		color = "green",
		size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
		onClick = function()
			perform(aspectName)
		end,
	})
	action.button.AnchorPoint = Vector2.new(1, 0.5)
	action.button.Position = UDim2.new(1, -12, 0, ROW_H / 2)
	action.button.ZIndex = 5
	action.label.TextSize = Theme.TextSize.Body

	-- Clicking the row (anywhere but its button) opens it to list the aspect's
	-- abilities with their rarity, mana and cooldown; clicking again closes it.
	local toggle = text(frame, { text = "+", font = Theme.Fonts.Heading, size = Theme.TextSize.Heading, color = P.InkSoft,
		align = Enum.TextXAlignment.Right, at = UDim2.new(1, -(BUTTON_W + 40), 0, 6), box = UDim2.fromOffset(20, 24), z = 5 })

	local abilityNames = AspectConfig.abilitiesOf(aspectName)
	local LINE_H = 26
	local details = Instance.new("Frame")
	details.Name = "Abilities"
	details.BackgroundTransparency = 1
	details.Position = UDim2.fromOffset(12, ROW_H - 2)
	details.Size = UDim2.new(1, -24, 0, 10 + #abilityNames * LINE_H)
	details.Visible = false
	details.ZIndex = 5
	details.Parent = frame
	local divider = PixelUI.divider(details)
	divider.Size = UDim2.new(1, 0, 0, 4)
	divider.ZIndex = 5
	for i, abilityName in ipairs(abilityNames) do
		local ability = AbilityConfig.get(abilityName)
		local y = 8 + (i - 1) * LINE_H
		text(details, { text = ability and ability.displayName or abilityName, font = Theme.Fonts.Heading,
			size = Theme.TextSize.Body, color = Theme.rarityInk(ability and ability.rarity),
			at = UDim2.fromOffset(6, y), box = UDim2.new(0.42, 0, 0, LINE_H), z = 5 })
		local stats = {}
		if ability and ability.rarity then
			table.insert(stats, string.upper(ability.rarity))
		end
		if ability and ability.manaCost then
			table.insert(stats, string.format("%d MANA", ability.manaCost))
		end
		if ability and ability.cooldown then
			table.insert(stats, string.format("%gs CD", ability.cooldown))
		end
		text(details, { text = table.concat(stats, "  ·  "), font = Theme.Fonts.Number, size = 12, color = P.InkSoft,
			align = Enum.TextXAlignment.Right, at = UDim2.new(0.42, 0, 0, y), box = UDim2.new(0.58, -6, 0, LINE_H), z = 5 })
	end

	local open = false
	local hit = Instance.new("TextButton")
	hit.Name = "Toggle"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.new(1, -(BUTTON_W + 24), 0, ROW_H)
	hit.ZIndex = 6
	hit.Parent = frame
	hit.MouseButton1Click:Connect(function()
		open = not open
		Sounds.play("ui.click")
		details.Visible = open
		toggle.Text = if open then "-" else "+"
		frame.Size = UDim2.new(1, 0, 0, if open then ROW_H + details.Size.Y.Offset else ROW_H)
	end)
	hit.MouseEnter:Connect(function()
		Sounds.play("ui.hover")
	end)

	row = { frame = frame, tier = tier, action = action, definition = definition }
	rows[aspectName] = row
	return row
end

function refresh()
	for _, aspectName in ipairs(AspectConfig.names()) do
		local row = rowFor(aspectName)
		local mode = actionFor(aspectName)
		local rarity = string.upper(row.definition.rarity or "")
		row.tier.Text = if AbilityStorage.isPermanent(aspectName) then rarity .. " · PERMANENT" else rarity .. " ASPECT"
		local action = row.action
		if mode == "buy" then
			local price = priceOf(aspectName)
			action.label.Text = if price and price ~= "" then price else "BUY"
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
			action.label.Text = "REDEEM"
			action.setColor("green")
			action.setEnabled(true)
		elseif mode == "traded" then
			action.label.Text = "TRADED"
			action.setEnabled(false)
		else
			action.label.Text = "SOON"
			action.setEnabled(false)
		end
	end
end

function perform(aspectName)
	local mode = actionFor(aspectName)
	if mode == "buy" then
		status.Text = ""
		BuyRemote:FireServer(aspectName)
	elseif mode == "redeem" then
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
		local current = currentAspect()
		if current and not AbilityStorage.isPermanent(current) then
			-- A permanent aspect in use is kept; anything else in use is lost.
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
	end
end

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

game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player or prompt.Name ~= "StarfallShop" then return end
	local hub = workspace:FindFirstChild("StarfallHub")
	if not hub or not prompt:IsDescendantOf(hub.StarfallMerchant) then return end
	window.Visible = true
	status.Text = ""
	refresh()
end)
