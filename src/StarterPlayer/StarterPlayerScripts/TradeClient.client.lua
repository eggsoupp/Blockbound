--[[
	TradeClient

	Trading, from the player's side:

	  * a button in the top bar that lists everyone else here, each with a
	    TRADE button that sends them a request;
	  * the prompt a request arrives as - ACCEPT or DECLINE, gone on its own
	    when the request runs out;
	  * the trade window itself (Shared.UI.TradeWindow), shown whenever the
	    server says a trade is on.

	Nothing here decides anything. Every button sends a request over the
	"Trade" remote and the server (ServerScriptService.Trade) answers with the
	trade as it now stands; that answer is all that is ever drawn. What the
	server has to say in words arrives as an ordinary CommandFeedback line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelUI = require(UI:WaitForChild("PixelUI"))
local TopbarButtons = require(UI:WaitForChild("TopbarButtons"))
local TradeWindow = require(UI:WaitForChild("TradeWindow"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local Remote = Remotes.wait("Trade")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local P = Theme.PixelColor

-- Two arrows passing each other, a texel to a character.
local ICON_SPRITE = {
	"............",
	".......##...",
	".......###..",
	".##########.",
	".......###..",
	".......##...",
	"...##.......",
	"..###.......",
	".##########.",
	"..###.......",
	"...##.......",
	"............",
}
local ICON_SCALE = 0.62
local RING_OUTSET = 3

local screen = Instance.new("ScreenGui")
screen.Name = "Trade"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 21
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = props.font or Theme.Fonts.BodyBold
	l.TextSize = props.size or Theme.TextSize.Body
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

-- ---------------------------------------------------------------------------
-- The trade itself
-- ---------------------------------------------------------------------------

local tradeWindow = TradeWindow.create(screen, {
	setOffer = function(kind, name, count)
		Remote:FireServer("offer", kind, name, count)
	end,
	confirm = function(rev)
		Remote:FireServer("confirm", rev)
	end,
	unconfirm = function()
		Remote:FireServer("unconfirm")
	end,
	cancel = function()
		Remote:FireServer("cancel")
	end,
})

-- ---------------------------------------------------------------------------
-- The top-bar button
-- ---------------------------------------------------------------------------

local button = Instance.new("ImageButton")
button.Name = "Trade"
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
ring.ImageColor3 = P.Selection
ring.ZIndex = 5
ring.Visible = false

do
	local field = Instance.new("Frame")
	field.AnchorPoint = Vector2.new(0.5, 0.5)
	field.Position = UDim2.fromScale(0.5, 0.5)
	field.Size = UDim2.fromScale(ICON_SCALE, ICON_SCALE)
	field.BackgroundTransparency = 1
	field.Parent = face

	local rows, columns = #ICON_SPRITE, #ICON_SPRITE[1]
	for row, line in ipairs(ICON_SPRITE) do
		for column = 1, columns do
			if string.sub(line, column, column) == "#" then
				local pixel = Instance.new("Frame")
				pixel.BackgroundColor3 = P.Heading
				pixel.BorderSizePixel = 0
				pixel.Position = UDim2.fromScale((column - 1) / columns, (row - 1) / rows)
				pixel.Size = UDim2.fromScale(1 / columns, 1 / rows)
				pixel.Parent = field
			end
		end
	end
end

TopbarButtons.add(button, 5, function()
	return "Trade - swap items and aspects with another player"
end)

-- ---------------------------------------------------------------------------
-- Who to trade with
-- ---------------------------------------------------------------------------

local LIST_W = 340
local ROW_H = 44
local LIST_MAX_ROWS = 7

local list = PixelUI.image(screen, "frame_wood")
list.Name = "Players"
list.AnchorPoint = Vector2.new(0.5, 0.5)
list.Position = UDim2.fromScale(0.5, 0.5)
list.Visible = false
list.Active = true
list.ZIndex = 2

local listHeader = PixelUI.header(list, "TRADE WITH")
listHeader.Position = UDim2.new(0.5, 0, 0, 0)
listHeader.ZIndex = 4
for _, child in ipairs(listHeader:GetDescendants()) do
	if child:IsA("GuiObject") then
		child.ZIndex = 5
	end
end

local listClose = PixelUI.closeButton(list, function()
	list.Visible = false
end)
listClose.Position = UDim2.new(1, -10, 0, 10)
listClose.ZIndex = 6

local listPanel = PixelUI.image(list, "inset_parchment")
listPanel.Position = UDim2.fromOffset(20, 40)
listPanel.ZIndex = 3

local listScroll = Instance.new("ScrollingFrame")
listScroll.BackgroundTransparency = 1
listScroll.BorderSizePixel = 0
listScroll.Position = UDim2.fromOffset(8, 8)
listScroll.Size = UDim2.new(1, -14, 1, -16)
listScroll.CanvasSize = UDim2.new()
listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
listScroll.ScrollBarThickness = 6
listScroll.ZIndex = 3
listScroll.Parent = listPanel
PixelUI.styleScrollBar(listScroll)

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listScroll

local listEmpty = text(listPanel, { text = "Nobody else is here yet.", font = Theme.Fonts.Body, color = P.InkSoft,
	align = Enum.TextXAlignment.Center })

local function drawList()
	for _, child in ipairs(listScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local others = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b)
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)

	for order, other in ipairs(others) do
		local row = Instance.new("Frame")
		row.Name = other.Name
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -8, 0, ROW_H)
		row.LayoutOrder = order
		row.ZIndex = 3
		row.Parent = listScroll

		text(row, { text = other.DisplayName, at = UDim2.fromOffset(6, 0), box = UDim2.new(1, -118, 1, 0) })

		local ask = PixelUI.button(row, {
			text = "TRADE",
			color = "green",
			size = UDim2.fromOffset(100, 36),
			textSize = Theme.TextSize.Body,
			onClick = function()
				Remote:FireServer("request", other.UserId)
				list.Visible = false
			end,
		})
		ask.button.AnchorPoint = Vector2.new(1, 0.5)
		ask.button.Position = UDim2.new(1, -2, 0.5, 0)
		ask.button.ZIndex = 4
		ask.label.ZIndex = 5
	end

	local rows = math.clamp(#others, 2, LIST_MAX_ROWS)
	local panelHeight = rows * ROW_H + 16
	listPanel.Size = UDim2.fromOffset(LIST_W - 40, panelHeight)
	list.Size = UDim2.fromOffset(LIST_W, panelHeight + 62)
	listEmpty.Visible = #others == 0
end

Players.PlayerAdded:Connect(function()
	if list.Visible then
		drawList()
	end
end)
Players.PlayerRemoving:Connect(function()
	if list.Visible then
		task.defer(drawList)
	end
end)

button.MouseButton1Click:Connect(function()
	-- In a trade the button has nothing to add: the window is already up.
	if tradeWindow.isOpen() then
		Sounds.play("ui.denied")
		return
	end
	list.Visible = not list.Visible
	Sounds.play(if list.Visible then "ui.open" else "ui.close")
	if list.Visible then
		drawList()
	end
end)

-- ---------------------------------------------------------------------------
-- Someone is asking
-- ---------------------------------------------------------------------------

local PROMPT_W, PROMPT_H = 360, 124

-- Requests waiting, oldest first: { userId, name, expiresAt }.
local waiting = {}

local prompt = PixelUI.image(screen, "frame_wood")
prompt.Name = "Request"
prompt.AnchorPoint = Vector2.new(0.5, 0)
prompt.Position = UDim2.new(0.5, 0, 0, 70)
prompt.Size = UDim2.fromOffset(PROMPT_W, PROMPT_H)
prompt.Visible = false
prompt.Active = true
prompt.ZIndex = 8

local promptText = text(prompt, { color = P.OnWood, align = Enum.TextXAlignment.Center, size = Theme.TextSize.Subheading,
	at = UDim2.fromOffset(16, 16), box = UDim2.new(1, -32, 0, 24), z = 9 })
local promptTime = text(prompt, { color = P.OnWoodDim, align = Enum.TextXAlignment.Center, size = Theme.TextSize.Small,
	font = Theme.Fonts.Body, at = UDim2.fromOffset(16, 40), box = UDim2.new(1, -32, 0, 18), z = 9 })

local function drawPrompt()
	local now = os.clock()
	while waiting[1] and waiting[1].expiresAt <= now do
		table.remove(waiting, 1)
	end
	local first = waiting[1]
	-- Not over a trade already under way; the server would refuse it anyway.
	prompt.Visible = first ~= nil and not tradeWindow.isOpen()
	if first then
		promptText.Text = first.name .. " wants to trade"
		local more = #waiting - 1
		promptTime.Text = string.format(
			"%d s%s", math.ceil(first.expiresAt - now), if more > 0 then string.format("   (+%d more)", more) else ""
		)
	end
end

local function answer(accept: boolean)
	local first = table.remove(waiting, 1)
	if first then
		Remote:FireServer("respond", first.userId, accept)
	end
	drawPrompt()
end

local accept = PixelUI.button(prompt, { text = "ACCEPT", color = "green", size = UDim2.fromOffset(150, 44), onClick = function()
	answer(true)
end })
accept.button.Position = UDim2.fromOffset(22, 66)
accept.button.ZIndex = 9
accept.label.ZIndex = 10

local decline = PixelUI.button(prompt, { text = "DECLINE", color = "red", size = UDim2.fromOffset(150, 44), onClick = function()
	answer(false)
end })
decline.button.Position = UDim2.fromOffset(PROMPT_W - 22 - 150, 66)
decline.button.ZIndex = 9
decline.label.ZIndex = 10

-- ---------------------------------------------------------------------------
-- The server
-- ---------------------------------------------------------------------------

Remote.OnClientEvent:Connect(function(action, a, b, c)
	if action == "state" and type(a) == "table" then
		list.Visible = false
		tradeWindow.show(a)
		drawPrompt()
	elseif action == "closed" then
		tradeWindow.hide()
		drawPrompt()
	elseif action == "request" and type(a) == "number" and type(b) == "string" then
		for index = #waiting, 1, -1 do
			if waiting[index].userId == a then
				table.remove(waiting, index)
			end
		end
		table.insert(waiting, { userId = a, name = b, expiresAt = os.clock() + (tonumber(c) or 30) })
		Sounds.play("ui.open")
		drawPrompt()
	elseif action == "requestGone" then
		for index = #waiting, 1, -1 do
			if waiting[index].userId == a then
				table.remove(waiting, index)
			end
		end
		drawPrompt()
	end
end)

local lastSecond = -1
RunService.Heartbeat:Connect(function()
	ring.Visible = list.Visible or tradeWindow.isOpen()
	if #waiting > 0 then
		local second = math.floor(os.clock())
		if second ~= lastSecond then
			lastSecond = second
			drawPrompt()
		end
	end
end)
