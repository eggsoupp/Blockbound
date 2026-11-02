--[[
	IslandPickerClient

	The wide button in the top bar beside the travel tile: it shows the name of
	the current island, and opens a list of the player's
	islands - pick one to travel there immediately, or press the pencil to
	rename it.

	The server owns all of it (ServerScriptService.IslandSlots): this sends
	"select" or "rename" over the IslandMenu remote and redraws from the
	attributes the server keeps on the player - IslandCount, ActiveIsland,
	IslandName1, IslandName2. An island not yet bought is listed too, locked,
	and choosing it offers the pass.

	Only shown in the Island place; both places use this same script.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))

if not PlaceConfig.isIsland() then
	return
end

local UI = Shared:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelUI = require(UI:WaitForChild("PixelUI"))
local TopbarButtons = require(UI:WaitForChild("TopbarButtons"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local IslandConfig = require(Shared:WaitForChild("IslandSlots"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local Menu = Remotes.wait("IslandMenu")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local P = Theme.PixelColor

-- The button's width in multiples of the bar's buttons, and the list's rows.
local WIDTH_SCALE = 3.4
local ROW_HEIGHT = 40
local LIST_WIDTH = 260
local LIST_PAD = 14
local NAME_LENGTH = 20
local RING_OUTSET = 3

-- A pencil, a texel to a character.
local PENCIL_SPRITE = {
	"......##",
	".....#.#",
	"....#.#.",
	"...#.#..",
	"..#.#...",
	".#.#....",
	"##.#....",
	"###.....",
}

local function drawSprite(parent: Instance, sprite: { string }, color: Color3)
	local rows, columns = #sprite, #sprite[1]
	for row, line in ipairs(sprite) do
		for column = 1, columns do
			if string.sub(line, column, column) == "#" then
				local pixel = Instance.new("Frame")
				pixel.BackgroundColor3 = color
				pixel.BorderSizePixel = 0
				pixel.Position = UDim2.fromScale((column - 1) / columns, (row - 1) / rows)
				pixel.Size = UDim2.fromScale(1 / columns, 1 / rows)
				pixel.Parent = parent
			end
		end
	end
end

local function islandName(slot: number): string
	return player:GetAttribute("IslandName" .. slot) or ("Island " .. slot)
end

local function activeSlot(): number
	if workspace:GetAttribute("IslandOwnerId") == player.UserId then
		return workspace:GetAttribute("IslandSlot") or 1
	end
	return player:GetAttribute("ActiveIsland") or 1
end

-- ---------------------------------------------------------------------------
-- The button
-- ---------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "IslandPicker"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 20
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local button = Instance.new("ImageButton")
button.Name = "Picker"
button.AutoButtonColor = false
button.BackgroundTransparency = 1
button.Parent = screen

local face = Instance.new("Frame")
face.Name = "Content"
face.BackgroundTransparency = 1
face.Size = UDim2.fromScale(1, 1)
face.Parent = button

PixelUI.bindButton(button, { idle = "slot", hover = "slot", pressed = "slot_dark", text = P.Ink }, face)

local ring = PixelUI.image(button, "slot_highlight")
ring.Name = "Selection"
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.new(1, RING_OUTSET * 2, 1, RING_OUTSET * 2)
ring.ImageColor3 = P.Selection
ring.ZIndex = 5
ring.Visible = false

local current = Instance.new("TextLabel")
current.Name = "Name"
current.BackgroundTransparency = 1
current.AnchorPoint = Vector2.new(0.5, 0.5)
current.Position = UDim2.fromScale(0.5, 0.5)
current.Size = UDim2.new(1, -16, 0.6, 0)
current.FontFace = Theme.Fonts.Heading
current.TextScaled = true
current.TextColor3 = P.Ink
current.TextTruncate = Enum.TextTruncate.AtEnd
current.Parent = face

local fit = Instance.new("UITextSizeConstraint")
fit.MaxTextSize = Theme.TextSize.Body
fit.Parent = current

local tip = TopbarButtons.add(button, 3, function()
	return "Your islands - select an island to switch to it, or rename one"
end, WIDTH_SCALE)

-- ---------------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------------

local list = PixelUI.image(screen, "frame_wood")
list.Name = "Islands"
list.AnchorPoint = Vector2.new(1, 0)
list.Visible = false
list.ZIndex = 20

local rowsHolder = Instance.new("Frame")
rowsHolder.Name = "Rows"
rowsHolder.BackgroundTransparency = 1
rowsHolder.Position = UDim2.fromOffset(LIST_PAD, LIST_PAD)
rowsHolder.Size = UDim2.new(1, -LIST_PAD * 2, 1, -LIST_PAD * 2)
rowsHolder.ZIndex = 21
rowsHolder.Parent = list

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = rowsHolder

local rows = {}

local function buildRow(slot: number)
	local row = Instance.new("ImageButton")
	row.Name = "Island" .. slot
	row.LayoutOrder = slot
	row.AutoButtonColor = false
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.ZIndex = 22
	row.Parent = rowsHolder
	PixelUI.apply(row, "row")

	-- The gold marker on the island currently loaded.
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.BackgroundColor3 = P.Selection
	marker.BorderSizePixel = 0
	marker.Position = UDim2.fromOffset(8, 10)
	marker.Size = UDim2.new(0, 6, 1, -20)
	marker.ZIndex = 23
	marker.Parent = row

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(22, 0)
	name.Size = UDim2.new(1, -66, 1, 0)
	name.FontFace = Theme.Fonts.Heading
	name.TextSize = Theme.TextSize.Body
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextColor3 = P.Ink
	name.ZIndex = 23
	name.Parent = row

	local edit = Instance.new("TextBox")
	edit.Name = "Edit"
	edit.Visible = false
	edit.ClearTextOnFocus = false
	edit.BackgroundColor3 = Color3.fromRGB(251, 241, 214)
	edit.BorderSizePixel = 0
	edit.Position = UDim2.new(0, 20, 0.5, -13)
	edit.Size = UDim2.new(1, -64, 0, 26)
	edit.FontFace = Theme.Fonts.Heading
	edit.TextSize = Theme.TextSize.Body
	edit.TextXAlignment = Enum.TextXAlignment.Left
	edit.TextColor3 = P.Ink
	edit.ZIndex = 24
	edit.Parent = row

	local pencil = Instance.new("TextButton")
	pencil.Name = "Rename"
	pencil.Text = ""
	pencil.AutoButtonColor = false
	pencil.BackgroundTransparency = 1
	pencil.AnchorPoint = Vector2.new(1, 0.5)
	pencil.Position = UDim2.new(1, -8, 0.5, 0)
	pencil.Size = UDim2.fromOffset(30, 30)
	pencil.ZIndex = 24
	pencil.Parent = row

	local pencilIcon = Instance.new("Frame")
	pencilIcon.BackgroundTransparency = 1
	pencilIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	pencilIcon.Position = UDim2.fromScale(0.5, 0.5)
	pencilIcon.Size = UDim2.fromOffset(18, 18)
	pencilIcon.ZIndex = 24
	pencilIcon.Parent = pencil
	drawSprite(pencilIcon, PENCIL_SPRITE, P.Ink)
	for _, pixel in ipairs(pencilIcon:GetChildren()) do
		pixel.ZIndex = 25
	end

	-- Where the pencil goes, on an island not bought yet.
	local locked = Instance.new("TextLabel")
	locked.Name = "Locked"
	locked.BackgroundTransparency = 1
	locked.AnchorPoint = Vector2.new(1, 0.5)
	locked.Position = UDim2.new(1, -10, 0.5, 0)
	locked.Size = UDim2.fromOffset(70, 20)
	locked.FontFace = Theme.Fonts.BodyBold
	locked.TextSize = Theme.TextSize.Small
	locked.TextXAlignment = Enum.TextXAlignment.Right
	locked.TextColor3 = P.InkSoft
	locked.Text = "LOCKED"
	locked.ZIndex = 24
	locked.Parent = row

	local entry = { row = row, marker = marker, name = name, edit = edit, pencil = pencil, locked = locked }

	row.MouseEnter:Connect(function()
		PixelUI.apply(row, "row_hover")
		Sounds.play("ui.hover")
	end)
	row.MouseLeave:Connect(function()
		PixelUI.apply(row, if slot == activeSlot() then "row_selected" else "row")
	end)
	row.Activated:Connect(function()
		if edit.Visible then
			return
		end
		Sounds.play("ui.click")
		Menu:FireServer("select", slot)
		if slot <= (player:GetAttribute("IslandCount") or 1) then
			list.Visible = false
		end
	end)

	pencil.Activated:Connect(function()
		if slot > (player:GetAttribute("IslandCount") or 1) then
			return
		end
		Sounds.play("ui.click")
		edit.Text = islandName(slot)
		edit.Visible = true
		name.Visible = false
		edit:CaptureFocus()
	end)

	edit:GetPropertyChangedSignal("Text"):Connect(function()
		if #edit.Text > NAME_LENGTH then
			edit.Text = string.sub(edit.Text, 1, NAME_LENGTH)
		end
	end)

	edit.FocusLost:Connect(function(enterPressed)
		edit.Visible = false
		name.Visible = true
		if enterPressed and edit.Text ~= islandName(slot) then
			Menu:FireServer("rename", slot, edit.Text)
		end
	end)

	rows[slot] = entry
	return entry
end

for slot = 1, IslandConfig.MaxIslands do
	buildRow(slot)
end

local function refresh()
	local count = player:GetAttribute("IslandCount") or 1
	local active = activeSlot()
	current.Text = islandName(active)

	for slot, entry in pairs(rows) do
		local owned = slot <= count
		entry.name.Text = islandName(slot)
		entry.locked.Visible = not owned
		entry.name.TextColor3 = if owned then P.Ink else P.InkSoft
		entry.marker.Visible = slot == active
		entry.pencil.Visible = owned
		PixelUI.apply(entry.row, if slot == active then "row_selected" else "row")
	end

	list.Size = UDim2.fromOffset(LIST_WIDTH, LIST_PAD * 2 + IslandConfig.MaxIslands * (ROW_HEIGHT + 6) - 6)
end

local function placeList()
	local position = button.AbsolutePosition - screen.AbsolutePosition
	list.Position = UDim2.fromOffset(position.X + button.AbsoluteSize.X, position.Y + button.AbsoluteSize.Y + 8)
end

refresh()
for _, attribute in ipairs({ "IslandCount", "ActiveIsland", "IslandName1", "IslandName2" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refresh)
end
workspace:GetAttributeChangedSignal("IslandOwnerId"):Connect(refresh)
workspace:GetAttributeChangedSignal("IslandSlot"):Connect(refresh)

button.MouseButton1Click:Connect(function()
	Sounds.play(if list.Visible then "ui.close" else "ui.open")
	list.Visible = not list.Visible
	tip.Visible = false
	if list.Visible then
		placeList()
	end
end)

button.MouseEnter:Connect(function()
	ring.Visible = true
	Sounds.play("ui.hover")
end)
button.MouseLeave:Connect(function()
	ring.Visible = list.Visible
end)

list:GetPropertyChangedSignal("Visible"):Connect(function()
	ring.Visible = list.Visible
	-- The hover summary would sit under the open list.
	if list.Visible then
		tip.Visible = false
	end
end)
button:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeList)
