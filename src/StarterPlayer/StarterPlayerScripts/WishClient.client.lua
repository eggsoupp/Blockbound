--[[
	WishClient

	The Starfall banner window - Wish Stars, pity, the odds, Wish x1 and
	Wish x10, and the Robux buttons when products are set. It has no top-bar
	button: it opens at the Starfall Shrine in the spawn village, from the
	shrine's "Make a Wish" prompt (StarfallWish, built by SpawnHub), and
	closes when the player walks away. The merchant beside it sells the
	permanent aspects (ShopClient).

	A wish asks WishService (the server rolls and grants), then
	Shared.Wish.WishCinematic plays what came back. The window is still there
	afterwards, like returning to a banner screen.

	Restored from before the Aspect Shop replaced it (commit c222fdb), with
	the top-bar button taken out.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelUI = require(UI:WaitForChild("PixelUI"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local WishConfig = require(Shared:WaitForChild("Wish"):WaitForChild("WishConfig"))
local Cinematic = require(Shared.Wish:WaitForChild("WishCinematic"))

local PullRemote = Remotes.wait("WishPull")
local StateRemote = Remotes.wait("WishState")
local BuyRemote = Remotes.wait("WishBuy")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local P = Theme.PixelColor

local state = nil

-- How far from the shrine's prompt the window stays open.
local WALK_AWAY = 22

local screen = Instance.new("ScreenGui")
screen.Name = "WishBanner"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 20
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui


-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local WIDTH, HEIGHT = 640, 268

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

local header = PixelUI.header(window, string.upper(WishConfig.BannerName))
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
	l.RichText = props.rich or false
	l.Position = props.at
	l.Size = props.box
	l.Text = props.text or ""
	l.ZIndex = 4
	l.Parent = parent
	return l
end

-- Left: the odds, on parchment.
local odds = PixelUI.image(window, "inset_parchment")
odds.Name = "Odds"
odds.Position = UDim2.fromOffset(26, 44)
odds.Size = UDim2.fromOffset(250, 200)
odds.ZIndex = 3

text(odds, { text = "THE ODDS", font = Theme.Fonts.Heading, size = Theme.TextSize.Subheading, color = P.Heading,
	at = UDim2.fromOffset(16, 10), box = UDim2.new(1, -32, 0, 24) })

local rows = {
	{ "Legendary", WishConfig.Rates.Legendary },
	{ "Epic", WishConfig.Rates.Epic },
	{ "Rare", WishConfig.Rates.Rare },
	{ "Uncommon", WishConfig.Rates.Uncommon },
	{ "Common", 1 - WishConfig.Rates.Legendary - WishConfig.Rates.Epic - WishConfig.Rates.Rare - WishConfig.Rates.Uncommon },
}
for i, row in ipairs(rows) do
	local y = 38 + (i - 1) * 28
	local stars = WishConfig.Stars[row[1]]
	for s = 1, stars do
		local star = PixelUI.image(odds, "icon_star")
		star.Position = UDim2.fromOffset(16 + (s - 1) * 13, y + 6)
		star.Size = UDim2.fromOffset(12, 12)
		star.ImageColor3 = Theme.rarityColor(row[1])
		star.ZIndex = 4
	end
	text(odds, { text = row[1], size = Theme.TextSize.Small, color = Theme.rarityInk(row[1]), at = UDim2.fromOffset(84, y), box = UDim2.fromOffset(96, 24) })
	text(odds, { text = string.format("%.1f%%", row[2] * 100), size = Theme.TextSize.Small, align = Enum.TextXAlignment.Right,
		at = UDim2.fromOffset(170, y), box = UDim2.fromOffset(64, 24) })
end

-- Right: the stars, the pity, the buttons.
local right = Instance.new("Frame")
right.Name = "Wish"
right.BackgroundTransparency = 1
right.Position = UDim2.fromOffset(292, 44)
right.Size = UDim2.fromOffset(322, 200)
right.ZIndex = 3
right.Parent = window

local purse = PixelUI.image(right, "inset_wood")
purse.Position = UDim2.fromOffset(0, 0)
purse.Size = UDim2.new(1, 0, 0, 58)
purse.ZIndex = 3
local purseStar = PixelUI.image(purse, "icon_star")
purseStar.AnchorPoint = Vector2.new(0, 0.5)
purseStar.Position = UDim2.new(0, 16, 0.5, 0)
purseStar.Size = UDim2.fromOffset(30, 30)
purseStar.ImageColor3 = Color3.fromRGB(255, 214, 72)
purseStar.ZIndex = 4
local starsText = text(purse, { text = "-", font = Theme.Fonts.Number, size = 30, color = P.OnWood,
	at = UDim2.fromOffset(56, 0), box = UDim2.new(1, -70, 1, 0) })
starsText.TextStrokeColor3 = P.Outline
starsText.TextStrokeTransparency = 0
-- Shrinks for big counts rather than running off the panel.
starsText.TextScaled = true
local starsFit = Instance.new("UITextSizeConstraint")
starsFit.MaxTextSize = 30
starsFit.Parent = starsText

-- The pity as a bar: how far towards the guaranteed Legendary, with a ? at
-- its end whose tooltip has the details.
local BAR_Y = 70
local HELP = 28
local track = PixelUI.image(right, "bar_frame")
track.Position = UDim2.fromOffset(0, BAR_Y)
track.Size = UDim2.new(1, -(HELP + 8), 0, 24)
track.ZIndex = 3
local gl, gt, gr, gb = PixelUI.groove("bar_frame")
local groove = Instance.new("Frame")
groove.BackgroundTransparency = 1
groove.ClipsDescendants = true
groove.Position = UDim2.fromOffset(gl, BAR_Y + gt)
groove.Size = UDim2.new(1, -(HELP + 8 + gl + gr), 0, 24 - gt - gb)
groove.ZIndex = 4
groove.Parent = right
local fill = PixelUI.image(groove, "bar_fill")
fill.Size = UDim2.fromScale(0, 1)
fill.ImageColor3 = Theme.rarityColor("Legendary")
fill.ZIndex = 4

-- What the bar means, written on it: "PITY 10 / 30".
local pityCount = text(right, { text = "", font = Theme.Fonts.Number, size = Theme.TextSize.Small, color = P.OnWood,
	align = Enum.TextXAlignment.Center, at = UDim2.fromOffset(0, BAR_Y), box = UDim2.new(1, -(HELP + 8), 0, 22) })
pityCount.TextStrokeColor3 = P.Outline
pityCount.TextStrokeTransparency = 0
pityCount.ZIndex = 6

local help = PixelUI.button(right, { text = "?", color = "tan", size = UDim2.fromOffset(HELP, HELP + 2) })
help.button.Name = "Help"
help.button.AnchorPoint = Vector2.new(1, 0)
help.button.Position = UDim2.new(1, 0, 0, BAR_Y - 3)
help.button.ZIndex = 5
help.label.TextSize = Theme.TextSize.Subheading

-- The details, shown while the ? is hovered (or after a tap on a phone).
local tip = PixelUI.image(window, "tooltip")
tip.Name = "PityDetails"
tip.AnchorPoint = Vector2.new(1, 0)
tip.Position = UDim2.new(1, -26, 0, 44 + BAR_Y + 32)
tip.Size = UDim2.fromOffset(300, 0)
tip.AutomaticSize = Enum.AutomaticSize.Y
tip.ZIndex = 20
tip.Visible = false
local tipPad = Instance.new("UIPadding")
tipPad.PaddingLeft, tipPad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
tipPad.PaddingTop, tipPad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
tipPad.Parent = tip
local tipText = text(tip, { text = "", color = P.OnWood, size = Theme.TextSize.Small, wrap = true, rich = true,
	at = UDim2.new(), box = UDim2.new(1, 0, 0, 0) })
tipText.AutomaticSize = Enum.AutomaticSize.Y
tipText.TextYAlignment = Enum.TextYAlignment.Top
tipText.LineHeight = 1.15
tipText.ZIndex = 21

local function detailsText()
	if not state then
		return "Loading your wishes..."
	end
	local left = WishConfig.LegendaryPity - state.sinceLegendary
	local epicLeft = WishConfig.EpicPity - state.sinceEpic
	return string.format(
		"Legendary guaranteed within <b>%d</b> %s.\nThe chance rises every wish from wish %d.\n\nEpic or better within <b>%d</b> %s.\n\nWishes made: %d\nEach wish is an aspect. With one in use, it goes to aspect storage.",
		left, if left == 1 then "wish" else "wishes", WishConfig.SoftPityFrom,
		epicLeft, if epicLeft == 1 then "wish" else "wishes", state.wishes
	)
end
local function showTip(on)
	tip.Visible = on
	if on then
		tipText.Text = detailsText()
	end
end
help.button.MouseEnter:Connect(function() showTip(true) end)
help.button.MouseLeave:Connect(function() showTip(false) end)
help.button.MouseButton1Click:Connect(function() showTip(not tip.Visible) end)

local status = text(right, { text = "", color = P.BadLight, size = Theme.TextSize.Small, align = Enum.TextXAlignment.Center,
	at = UDim2.fromOffset(0, BAR_Y + 28), box = UDim2.new(1, 0, 0, 20) })

local busy = false
local wishButtons = {}
local refresh -- below: redraws everything from `state`

local function doWish(count)
	if busy or Cinematic.isPlaying() then
		return
	end
	busy = true
	status.Text = ""
	for _, handle in pairs(wishButtons) do
		handle.setEnabled(false)
	end
	local ok, reply = pcall(PullRemote.InvokeServer, PullRemote, count)
	if ok and type(reply) == "table" and reply.ok then
		if reply.state then
			state = reply.state
		end
		Cinematic.play(reply.results)
		StateRemote:FireServer("done")
	else
		status.Text = if ok and type(reply) == "table" and reply.message then reply.message else "The banner is unavailable."
	end
	busy = false
	refresh()
end

for i, count in ipairs(WishConfig.Batches) do
	local handle = PixelUI.button(right, {
		text = string.format("Wish x%d", count),
		color = "green",
		size = UDim2.new(0.5, -6, 0, 56),
		onClick = function()
			doWish(count)
		end,
	})
	handle.button.Position = UDim2.fromOffset((i - 1) * 167, BAR_Y + 52)
	handle.button.ZIndex = 4
	handle.label.TextSize = Theme.TextSize.Heading
	handle.label.Size = UDim2.new(1, 0, 0.62, 0)
	local cost = text(handle.content, {
		text = string.format("%d %s", count * WishConfig.Cost, if count * WishConfig.Cost == 1 then "Wish Star" else WishConfig.CurrencyName),
		font = Theme.Fonts.Body, size = Theme.TextSize.Small, align = Enum.TextXAlignment.Center,
		at = UDim2.new(0, 0, 0.55, 0), box = UDim2.new(1, 0, 0.4, 0),
	})
	handle.onPaint(function(set)
		cost.TextColor3 = set.text
	end)
	wishButtons[count] = handle
end

-- The Robux buttons, one per product the server says is on sale.
local shop = Instance.new("Frame")
shop.BackgroundTransparency = 1
shop.Position = UDim2.fromOffset(0, BAR_Y + 118)
shop.Size = UDim2.new(1, 0, 0, 36)
shop.ZIndex = 4
shop.Parent = right

local shopFor = nil
local function buildShop(products)
	local key = ""
	for _, product in ipairs(products) do
		key ..= product.id .. ","
	end
	if key == shopFor then
		return
	end
	shopFor = key
	shop:ClearAllChildren()
	-- Room for the Robux row only when there is one.
	local extra = if #products > 0 then 46 else 0
	window.Size = UDim2.fromOffset(WIDTH, HEIGHT + extra)
	odds.Size = UDim2.fromOffset(250, 200 + extra)
	for i, product in ipairs(products) do
		local handle = PixelUI.button(shop, {
			text = string.format("Buy %s", product.label),
			color = "tan",
			size = UDim2.new(1 / #products, -6, 1, 0),
			onClick = function()
				BuyRemote:FireServer(product.id)
			end,
		})
		handle.button.Position = UDim2.new((i - 1) / #products, (i - 1) * 6 / #products, 0, 0)
		handle.button.ZIndex = 4
		local star = PixelUI.image(handle.content, "icon_star")
		star.AnchorPoint = Vector2.new(0, 0.5)
		star.Position = UDim2.new(0.5, 26, 0.5, 0)
		star.Size = UDim2.fromOffset(16, 16)
		star.ImageColor3 = Color3.fromRGB(255, 214, 72)
		star.ZIndex = 5
	end
end

function refresh()
	local stars = state and state.stars or 0
	starsText.Text = string.format("%d %s", stars, if stars == 1 then "Wish Star" else WishConfig.CurrencyName)
	if not state then
		fill.Size = UDim2.fromScale(0, 1)
		pityCount.Text = ""
	else
		fill.Size = UDim2.fromScale(state.sinceLegendary / WishConfig.LegendaryPity, 1)
		pityCount.Text = string.format("PITY %d / %d", state.sinceLegendary, WishConfig.LegendaryPity)
		buildShop(state.products or {})
		if tip.Visible then
			tipText.Text = detailsText()
		end
	end
	for count, handle in pairs(wishButtons) do
		handle.setEnabled(not busy and state ~= nil and stars >= count * WishConfig.Cost)
	end
end

refresh()

StateRemote.OnClientEvent:Connect(function(newState)
	state = newState
	refresh()
end)
StateRemote:FireServer()

-- ---------------------------------------------------------------------------
-- Opening at the shrine
-- ---------------------------------------------------------------------------

local openedAt = nil -- the prompt's part while the window is open from it

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player or prompt.Name ~= "StarfallWish" then
		return
	end
	local hub = workspace:FindFirstChild("StarfallHub")
	if not hub or not prompt:IsDescendantOf(hub) then
		return
	end
	openedAt = prompt.Parent
	window.Visible = true
	status.Text = ""
	Cinematic.preload()
	StateRemote:FireServer()
end)

RunService.Heartbeat:Connect(function()
	if not window.Visible or not openedAt then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not openedAt.Parent or (root and (root.Position - openedAt.Position).Magnitude > WALK_AWAY) then
		window.Visible = false
		openedAt = nil
	end
end)
