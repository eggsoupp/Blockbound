--[[
	NoticeBoardClient

	The village notice board's window: Updates, Patch Notes and Upcoming,
	each a scrolling list of entries from Shared.UI.Notices. It opens from
	the board's "Read" prompt (VillageNotices, built by SpawnHub) and closes
	when you walk away.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelUI = require(UI:WaitForChild("PixelUI"))
local Notices = require(UI:WaitForChild("Notices"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local P = Theme.PixelColor

local WIDTH, HEIGHT = 520, 470
local WALK_AWAY = 20
local TABS = {
	{ key = "Updates", label = "UPDATES" },
	{ key = "PatchNotes", label = "PATCH NOTES" },
	{ key = "Upcoming", label = "UPCOMING" },
}

local screen = Instance.new("ScreenGui")
screen.Name = "NoticeBoard"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 20
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

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

local header = PixelUI.header(window, "NOTICE BOARD")
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
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Text = props.text or ""
	l.LayoutOrder = props.order or 0
	l.ZIndex = 5
	l.Parent = parent
	return l
end

-- The tabs.
local tabButtons = {}
local tabWidth = (WIDTH - 44 - 2 * 8) / #TABS
for i, tab in ipairs(TABS) do
	local handle = PixelUI.button(window, {
		text = tab.label,
		color = "tan",
		size = UDim2.fromOffset(tabWidth, 40),
		textSize = Theme.TextSize.Body,
	})
	handle.button.Position = UDim2.fromOffset(22 + (i - 1) * (tabWidth + 8), 44)
	handle.button.ZIndex = 4
	tabButtons[tab.key] = handle
end

-- The list.
local panel = PixelUI.image(window, "inset_parchment")
panel.Position = UDim2.fromOffset(22, 92)
panel.Size = UDim2.fromOffset(WIDTH - 44, HEIGHT - 92 - 22)
panel.ZIndex = 3

local list = Instance.new("ScrollingFrame")
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(10, 8)
list.Size = UDim2.new(1, -18, 1, -16)
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
list.ZIndex = 4
list.Parent = panel
PixelUI.styleScrollBar(list)
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 14)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list
local pad = Instance.new("UIPadding")
pad.PaddingRight = UDim.new(0, 8)
pad.PaddingTop = UDim.new(0, 4)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = list

local current = nil

local function show(key)
	current = key
	for k, handle in pairs(tabButtons) do
		handle.setColor(if k == key then "green" else "tan")
	end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local entries = Notices[key] or {}
	if #entries == 0 then
		text(list, { text = "Nothing here yet.", font = Theme.Fonts.Body, color = P.InkSoft })
	end
	for order, entry in ipairs(entries) do
		local block = Instance.new("Frame")
		block.Name = "Entry"
		block.BackgroundTransparency = 1
		block.Size = UDim2.new(1, 0, 0, 0)
		block.AutomaticSize = Enum.AutomaticSize.Y
		block.LayoutOrder = order
		block.ZIndex = 4
		block.Parent = list
		local blockLayout = Instance.new("UIListLayout")
		blockLayout.Padding = UDim.new(0, 3)
		blockLayout.SortOrder = Enum.SortOrder.LayoutOrder
		blockLayout.Parent = block
		text(block, { text = string.upper(entry.title or ""), font = Theme.Fonts.Heading, size = Theme.TextSize.Subheading,
			color = P.Heading, order = 1 })
		if entry.date then
			text(block, { text = entry.date, font = Theme.Fonts.Number, size = 12, color = P.InkSoft, order = 2 })
		end
		for i, line in ipairs(entry.lines or {}) do
			text(block, { text = "•  " .. line, font = Theme.Fonts.Body, size = Theme.TextSize.Small, order = 2 + i })
		end
	end
	list.CanvasPosition = Vector2.zero
end

for _, tab in ipairs(TABS) do
	tabButtons[tab.key].button.MouseButton1Click:Connect(function()
		if current ~= tab.key then
			show(tab.key)
		end
	end)
end

-- Opening at the board ---------------------------------------------------------

local openedAt = nil

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player or prompt.Name ~= "VillageNotices" then
		return
	end
	openedAt = prompt.Parent
	show(current or "Updates")
	window.Visible = true
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
