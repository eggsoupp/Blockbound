--[[
	SettingsButton

	The gear in the topbar, next to Roblox's own chat button, and the settings
	window it opens: audio, view distance and the combat feedback options.

	WHY IT IS NOT IN THE TAB MENU

	Because these are the settings a player changes WHILE PLAYING - sound
	because somebody walked into the room, view distance because the frame rate
	dropped - and both of those are worse moments to be dropped into a menu that
	stops you moving and swings the camera. The Tab menu is where you go to look
	at your abilities; this is where you go to turn the music off. So the
	window does not lock movement, and closes on Esc, on its cross, on the gear,
	or on a click outside it.

	THE BUTTON LOOKS LIKE ROBLOX'S OWN; THE WINDOW LOOKS LIKE THE GAME'S

	The gear is chrome in Roblox's topbar, so it matches the core buttons beside
	it: same size and spacing, the same translucent black rounded square, the
	same white glyph, drawn from Frames rather than being an image. The window
	it opens is the game's, so it is drawn from the pixel-art kit like every
	other window (Shared.UI.PixelUI): a wooden frame and its green title banner,
	and on parchment inside it, a row per setting - a gold marker, its name, a
	line on what it does, and its control on the right with its default under
	it.

	WHERE IT SITS IS ASKED FOR, NOT GUESSED

	GuiService.TopbarInset is the region Roblox leaves free for developer UI:
	its left edge is exactly where the core buttons stop. Hard-coding an offset
	would be a number that is wrong the next time Roblox changes its topbar,
	and it changes. The inset is also watched, because it moves when the chat
	button appears and disappears.

	THE VALUES LIVE IN Shared.UI.PlayerSettings

	This file only draws them and changes them through PlayerSettings, which
	applies each one and saves it with the player. The window follows
	PlayerSettings.Changed rather than its own last click, so it is right when
	the saved values arrive after it was drawn.

	VIEW DISTANCE IS THE SERVER'S ANSWER, NOT THE CLICK

	The number displayed is always the one the SERVER confirmed, never the one
	the player just clicked - it decides how much terrain the server generates
	and holds on this player's behalf. Pressing an arrow shows nothing until the
	reply lands, which is correct: it means the readout can never claim a
	distance that is not actually loaded. The server saves it too.
]]

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local PixelUI = require(Shared.UI:WaitForChild("PixelUI"))
local Motion = require(Shared.UI:WaitForChild("Motion"))
local MenuState = require(Shared.UI:WaitForChild("MenuState"))
local PlayerSettings = require(Shared.UI:WaitForChild("PlayerSettings"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))

local RequestViewDistance = Remotes.wait("RequestViewDistance")
local ViewDistanceChanged = Remotes.wait("ViewDistanceChanged")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local P = Theme.PixelColor
local MENU_NAME = "Settings"

-- ---------------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------------

--[[
	Roblox's topbar numbers, matched rather than invented: a 32px square inside
	the 36px bar, 8px from whatever is to its left, with a 8px corner radius and
	a black background at 0.5.
]]
local BUTTON_SIZE = 32
local BUTTON_GAP = 8
local BUTTON_CORNER = 8
local BUTTON_TRANSPARENCY = 0.5
local BUTTON_HOVER_TRANSPARENCY = 0.3

-- The window, in pixels on a 1080p screen. A UIScale fits it to the real one.
local L = {
	width = 780,
	height = 700,
	-- Clear of the frame art's border, and the header row under the banner.
	pad = 30,
	headerHeight = 66,

	sectionHeight = 40,
	rowHeight = 80,
	accentWidth = 6,
	controlsWidth = 336,

	button = 36,
	sliderWidth = 168,
	valueWidth = 64,
	stepperBox = 96,
}

local DESIGN_HEIGHT = 1080
local MIN_SCALE = 0.5

-- One press of a volume button, and how finely a drag settles.
local VOLUME_STEP = 0.05
local VOLUME_DRAG_STEP = 0.01

-- One press of a view distance arrow. The server owns the bounds and sends
-- them, so this is only the size of one press.
local DISTANCE_STEP = 1

-- The volume fill is a sliced sprite, never drawn narrower than its two ends.
local FILL_MIN = 6 * PixelUI.Scale

-- The rule behind a section's name, and the parchment the name is printed
-- on, which masks the rule where the name crosses it.
local RULE_COLOR = Color3.fromRGB(168, 124, 76)
local PARCHMENT = Color3.fromRGB(239, 220, 174)
local ACCENT = Color3.fromRGB(214, 160, 52)

-- An arrow with nowhere left to go.
local ARROW_SPENT_TRANSPARENCY = 0.6

local screen = Instance.new("ScreenGui")
screen.Name = "SettingsButton"
screen.ResetOnSpawn = false

-- The topbar is above the inset by definition, so this cannot respect it.
screen.IgnoreGuiInset = true

-- Over the game's own HUD, under nothing: this is chrome, and a menu that
-- opened behind the health bar would be a bug nobody could click their way out
-- of.
screen.DisplayOrder = 20
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- ---------------------------------------------------------------------------
-- The button
-- ---------------------------------------------------------------------------

local button = Instance.new("TextButton")
button.Name = "Gear"
button.Text = ""
button.AutoButtonColor = false
button.AnchorPoint = Vector2.new(0, 0.5)
button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
button.BackgroundColor3 = Color3.new(0, 0, 0)
button.BackgroundTransparency = BUTTON_TRANSPARENCY
button.BorderSizePixel = 0
-- Over the window's dimmed backdrop, so it can close what it opened.
button.ZIndex = 3
button.Parent = screen

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, BUTTON_CORNER)
buttonCorner.Parent = button

--[[
	The gear, drawn rather than uploaded.

	A ring made from a circle with a smaller circle punched out of it - punched
	by drawing the hole in the button's own colour would not work over a
	translucent background, so the "hole" is a real gap: the ring is a circle
	with a UIStroke and no fill. Eight teeth are then laid round it as small
	rotated squares.
]]
local function buildGear(parent: Instance)
	local field = Instance.new("Frame")
	field.Name = "Icon"
	field.AnchorPoint = Vector2.new(0.5, 0.5)
	field.Position = UDim2.fromScale(0.5, 0.5)
	field.Size = UDim2.fromOffset(18, 18)
	field.BackgroundTransparency = 1
	field.Parent = parent

	for index = 1, 8 do
		local angle = (index - 1) * (math.pi * 2 / 8)

		local tooth = Instance.new("Frame")
		tooth.AnchorPoint = Vector2.new(0.5, 0.5)
		tooth.Position = UDim2.fromScale(
			0.5 + math.cos(angle) * 0.42,
			0.5 + math.sin(angle) * 0.42
		)
		tooth.Size = UDim2.fromOffset(6, 6)
		tooth.Rotation = math.deg(angle)
		tooth.BackgroundColor3 = Color3.new(1, 1, 1)
		tooth.BorderSizePixel = 0
		tooth.Parent = field
	end

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(13, 13)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Parent = field

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.new(1, 1, 1)
	ringStroke.Thickness = 3
	ringStroke.Parent = ring

	return field
end

buildGear(button)

--[[
	The bar's height, with a floor under it.

	Read rather than assumed, because it is taller on a phone and that is what
	keeps this lined up with the chat button there. The floor is for a client
	that has not finished setting its topbar up and reports an empty inset: a
	height of zero would centre the button on the very top edge of the screen
	with half of it off it, and 36 - Roblox's own desktop bar - is the right
	thing to be wrong with.
]]
local function barHeight(inset: Rect): number
	return math.max(inset.Height, 36)
end

--[[
	Just right of whatever Roblox is drawing on the left of the topbar.

	TopbarInset is in the same space as this ScreenGui, which ignores the inset,
	so its numbers can be used directly.
]]
local function place()
	local inset = GuiService.TopbarInset

	button.Position = UDim2.fromOffset(
		inset.Min.X + BUTTON_GAP,
		inset.Min.Y + barHeight(inset) * 0.5
	)
end

place()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

-- A light dim behind the window. A click on it closes the window; a click on
-- the window never reaches it.
local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Theme.Color.Backdrop
backdrop.BackgroundTransparency = 1
backdrop.BorderSizePixel = 0
backdrop.Visible = false
backdrop.ZIndex = 1
backdrop.Parent = screen

local BACKDROP_TRANSPARENCY = 0.65

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromOffset(L.width, L.height)
root.BackgroundTransparency = 1
root.Visible = false
root.ZIndex = 2
root.Parent = screen

local rootScale = Instance.new("UIScale")
rootScale.Parent = root

local window = PixelUI.image(root, "frame_wood")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromScale(1, 1)

local banner = PixelUI.header(window, "SETTINGS")
banner.Position = UDim2.new(0.5, 0, 0, 0)
banner.ZIndex = 3

local closeButton = PixelUI.closeButton(window)
closeButton.Position = UDim2.new(1, -14, 0, 14)
closeButton.ZIndex = 3

local hint = Instance.new("TextLabel")
hint.Name = "KeyHint"
hint.BackgroundTransparency = 1
hint.AnchorPoint = Vector2.new(1, 0.5)
hint.Position = UDim2.new(1, -L.pad, 0, 24 + (L.headerHeight - 24) / 2)
hint.Size = UDim2.fromOffset(200, 18)
hint.FontFace = Theme.Fonts.Body
hint.TextSize = Theme.TextSize.Small
hint.TextColor3 = P.OnWoodDim
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.Text = "Esc to close"
hint.Parent = window

local panel = PixelUI.image(window, "inset_parchment")
panel.Name = "Panel"
panel.Position = UDim2.fromOffset(L.pad, L.headerHeight)
panel.Size = UDim2.new(1, -L.pad * 2, 1, -(L.headerHeight + L.pad))

local insetLeft, insetTop, insetRight, insetBottom = PixelUI.border("inset_parchment")

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(insetLeft, insetTop)
list.Size = UDim2.new(1, -(insetLeft + insetRight), 1, -(insetTop + insetBottom))
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Parent = panel
PixelUI.styleScrollBar(list)

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local listPadding = Instance.new("UIPadding")
listPadding.PaddingLeft = UDim.new(0, 12)
listPadding.PaddingRight = UDim.new(0, 18)
listPadding.PaddingTop = UDim.new(0, 4)
listPadding.PaddingBottom = UDim.new(0, 10)
listPadding.Parent = list

local layoutOrder = 0
local function nextOrder(): number
	layoutOrder += 1
	return layoutOrder
end

local function text(parent: Instance, name: string, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

local function percent(value: number): string
	return string.format("%d%%", math.floor(value * 100 + 0.5))
end

-- A section's name over a rule running the width of the list.
local function section(title: string)
	local holder = Instance.new("Frame")
	holder.Name = title
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, L.sectionHeight)
	holder.LayoutOrder = nextOrder()
	holder.Parent = list

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0, 0.5)
	rule.Position = UDim2.new(0, 0, 0.5, 4)
	rule.Size = UDim2.new(1, 0, 0, PixelUI.Scale)
	rule.BackgroundColor3 = RULE_COLOR
	rule.BackgroundTransparency = 0.45
	rule.BorderSizePixel = 0
	rule.Parent = holder

	local label = text(holder, "Title", Theme.Fonts.Heading, Theme.TextSize.Small, P.Heading)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 0, 0.5, 4)
	label.Size = UDim2.fromOffset(0, 20)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundColor3 = PARCHMENT
	label.BackgroundTransparency = 0
	label.Text = string.upper(title)
	label.ZIndex = 2

	local labelPadding = Instance.new("UIPadding")
	labelPadding.PaddingRight = UDim.new(0, 10)
	labelPadding.Parent = label
end

-- An engraved line between two rows of the same section.
local function divider()
	local line = PixelUI.divider(list)
	line.LayoutOrder = nextOrder()
end

--[[
	A row: the gold marker, the name, a line on what it does, and a frame on
	the right for its control. The control's builder puts "DEFAULT ..." under
	itself with `caption`.
]]
local function row(title: string, description: string): Frame
	local holder = Instance.new("Frame")
	holder.Name = title
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, L.rowHeight)
	holder.LayoutOrder = nextOrder()
	holder.Parent = list

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(0, 10)
	accent.Size = UDim2.new(0, L.accentWidth, 1, -20)
	accent.BackgroundColor3 = ACCENT
	accent.BorderSizePixel = 0
	accent.Parent = holder

	local textWidth = -(20 + L.controlsWidth + 16)

	local name = text(holder, "Name", Theme.Fonts.Heading, Theme.TextSize.Body, P.Ink)
	name.Position = UDim2.fromOffset(20, 12)
	name.Size = UDim2.new(1, textWidth, 0, 20)
	name.Text = string.upper(title)

	local about = text(holder, "Description", Theme.Fonts.Body, Theme.TextSize.Small, P.InkSoft)
	about.Position = UDim2.fromOffset(20, 36)
	about.Size = UDim2.new(1, textWidth, 0, 36)
	about.TextWrapped = true
	about.TextYAlignment = Enum.TextYAlignment.Top
	about.Text = description

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.BackgroundTransparency = 1
	controls.AnchorPoint = Vector2.new(1, 0)
	controls.Position = UDim2.new(1, 0, 0, 12)
	controls.Size = UDim2.new(0, L.controlsWidth, 1, -12)
	controls.Parent = holder

	return controls
end

-- The small print under a control: its default, or its range.
local function caption(controls: Instance): TextLabel
	local label = text(controls, "Default", Theme.Fonts.Number, 13, P.InkFaint)
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, 0, 0, L.button + 6)
	label.Size = UDim2.new(1, 0, 0, 16)
	label.TextXAlignment = Enum.TextXAlignment.Right
	return label
end

local function smallButton(parent: Instance, label: string, x: number, onClick: () -> ())
	local handle = PixelUI.button(parent, {
		text = label,
		textSize = Theme.TextSize.Body,
		size = UDim2.fromOffset(L.button, L.button),
		onClick = onClick,
	})
	handle.button.Position = UDim2.fromOffset(x, 0)
	return handle
end

-- ---------------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------------

-- The slider being dragged, if any: { track, set }.
local dragging = nil

local function sliderValueAt(track: GuiObject, x: number): number
	local width = track.AbsoluteSize.X
	if width <= 0 then
		return 0
	end
	return math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
end

--[[
	[-] slider [+] and the value, for a 0..1 setting shown as a percentage.

	`x` from an InputObject's Position, which is in the same space as
	AbsolutePosition. UserInputService:GetMouseLocation() is NOT, even in a
	ScreenGui that ignores the GUI inset: it counts from the window's corner,
	inset included - the same trap that put the inventory's drop targets a top
	bar too high.
]]
local function volumeControl(controls: Frame, key: string)
	local function step(direction: number)
		local value = PlayerSettings.get(key) + direction * VOLUME_STEP
		PlayerSettings.set(key, math.round(value / VOLUME_STEP) * VOLUME_STEP)
	end

	smallButton(controls, "-", 0, function()
		step(-1)
	end)

	local trackX = L.button + 8
	local track = PixelUI.image(controls, "slider_track")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(trackX, (L.button - 24) / 2)
	track.Size = UDim2.fromOffset(L.sliderWidth, 24)

	local fill = PixelUI.image(track, "slider_fill")
	fill.Name = "Fill"

	local knob = PixelUI.image(track, "slider_knob")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.ZIndex = 2

	smallButton(controls, "+", trackX + L.sliderWidth + 8, function()
		step(1)
	end)

	local value = text(controls, "Value", Theme.Fonts.Number, Theme.TextSize.Body, P.Ink)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, 0, 0, 0)
	value.Size = UDim2.fromOffset(L.valueWidth, L.button)
	value.TextXAlignment = Enum.TextXAlignment.Right

	caption(controls).Text = "DEFAULT " .. percent(PlayerSettings.getDefault(key))

	local function draw(level: number)
		fill.Size = UDim2.new(level, (1 - level) * FILL_MIN, 1, 0)
		knob.Position = UDim2.new(level, 0, 0.5, 0)
		value.Text = percent(level)
	end

	local function setFrom(x: number)
		local level = sliderValueAt(track, x)
		PlayerSettings.set(key, math.round(level / VOLUME_DRAG_STEP) * VOLUME_DRAG_STEP)
	end

	-- The grab area is wider than the track, so the knob is easy to catch at
	-- either end.
	local grab = Instance.new("TextButton")
	grab.Name = "Grab"
	grab.Text = ""
	grab.AutoButtonColor = false
	grab.BackgroundTransparency = 1
	grab.Position = UDim2.fromOffset(trackX - 8, 0)
	grab.Size = UDim2.fromOffset(L.sliderWidth + 16, L.button)
	grab.ZIndex = 3
	grab.Parent = controls

	grab.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = { set = setFrom }
			setFrom(input.Position.X)
		end
	end)

	draw(PlayerSettings.get(key))
	PlayerSettings.Changed.Event:Connect(function(changed, level)
		if changed == key then
			draw(level)
		end
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if
		dragging
		and (
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		)
	then
		dragging.set(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if
		input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		dragging = nil
	end
end)

--[[
	OFF | ON, for a true/false setting. The side that is chosen is lit: ON in
	green, OFF in red. The other side is plain tan.
]]
local function toggleControl(controls: Frame, key: string)
	local width = 72

	local off = PixelUI.button(controls, {
		text = "OFF",
		textSize = Theme.TextSize.Small,
		size = UDim2.fromOffset(width, L.button),
		onClick = function()
			PlayerSettings.set(key, false)
		end,
	})
	off.button.AnchorPoint = Vector2.new(1, 0)
	off.button.Position = UDim2.new(1, -(width + 4), 0, 0)

	local on = PixelUI.button(controls, {
		text = "ON",
		textSize = Theme.TextSize.Small,
		size = UDim2.fromOffset(width, L.button),
		onClick = function()
			PlayerSettings.set(key, true)
		end,
	})
	on.button.AnchorPoint = Vector2.new(1, 0)
	on.button.Position = UDim2.new(1, 0, 0, 0)

	caption(controls).Text = "DEFAULT " .. (if PlayerSettings.getDefault(key) then "ON" else "OFF")

	local function draw(enabled: boolean)
		on.setColor(if enabled then "green" else "tan")
		off.setColor(if enabled then "tan" else "red")
	end

	draw(PlayerSettings.get(key))
	PlayerSettings.Changed.Event:Connect(function(changed, enabled)
		if changed == key then
			draw(enabled)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- The rows
-- ---------------------------------------------------------------------------

section("Audio")
volumeControl(
	row("Music volume", "How loud the music is. Sound effects are separate."),
	"musicVolume"
)
divider()
volumeControl(
	row("Sound effects", "Mining, combat, abilities, menus - everything that is not music."),
	"sfxVolume"
)

section("World")
local distanceRow = row(
	"View distance",
	"How far the world loads around you, in chunks. Lower it if the game runs slowly."
)

section("Combat")
toggleControl(
	row("Damage numbers", "Shows how much each hit took, beside your health bar."),
	"damageNumbers"
)
divider()
toggleControl(
	row("Hit flash", "Flashes the edges of the screen red when you are hurt."),
	"hitFlash"
)

-- Reset, in the header row: audio and combat back to their defaults. View
-- distance is the server's, and is left where it is.
local reset = PixelUI.button(window, {
	name = "Reset",
	text = "RESET TO DEFAULTS",
	textSize = Theme.TextSize.Small,
	size = UDim2.fromOffset(210, L.button),
	onClick = function()
		PlayerSettings.reset()
	end,
})
reset.button.AnchorPoint = Vector2.new(0, 0.5)
reset.button.Position = UDim2.new(0, L.pad, 0, 24 + (L.headerHeight - 24) / 2)

-- ---------------------------------------------------------------------------
-- View distance
-- ---------------------------------------------------------------------------

local distance, distanceMin, distanceMax, distanceDefault = nil, nil, nil, nil

local arrowWidth = PixelUI.get("icon_arrow_right").size.X * PixelUI.Scale
local stepperWidth = arrowWidth * 2 + L.stepperBox + 16

local function arrow(sprite: string, x: number): ImageButton
	local step = Instance.new("ImageButton")
	step.Name = sprite
	step.AutoButtonColor = false
	step.BackgroundTransparency = 1
	step.BorderSizePixel = 0
	step.Size = PixelUI.size(sprite)
	step.Position = UDim2.new(1, x, 0, (L.button - step.Size.Y.Offset) / 2)
	step.Parent = distanceRow
	PixelUI.apply(step, sprite)
	step.MouseEnter:Connect(function()
		Sounds.play("ui.hover")
	end)
	return step
end

local minus = arrow("icon_arrow_left", -stepperWidth)
local plus = arrow("icon_arrow_right", -arrowWidth)

local distanceBox = PixelUI.image(distanceRow, "input")
distanceBox.Name = "Distance"
distanceBox.Position = UDim2.new(1, -(arrowWidth + 8 + L.stepperBox), 0, 0)
distanceBox.Size = UDim2.fromOffset(L.stepperBox, L.button)

local distanceValue = text(distanceBox, "Value", Theme.Fonts.Number, Theme.TextSize.Body, P.InkSoft)
distanceValue.Size = UDim2.fromScale(1, 1)
distanceValue.TextXAlignment = Enum.TextXAlignment.Center
distanceValue.Text = "..."

local distanceCaption = caption(distanceRow)

local function drawDistance()
	if not distance then
		distanceValue.Text = "..."
		distanceCaption.Text = ""
		return
	end

	distanceValue.Text = tostring(distance)
	distanceValue.TextColor3 = P.Ink

	local parts = {}
	if distanceDefault then
		table.insert(parts, "DEFAULT " .. tostring(distanceDefault))
	end
	if distanceMin and distanceMax then
		table.insert(parts, string.format("%d TO %d", distanceMin, distanceMax))
	end
	distanceCaption.Text = table.concat(parts, "  ·  ")

	-- Faded at the ends rather than hidden, so the range is visible without
	-- the row changing shape.
	minus.ImageTransparency = if distanceMin and distance <= distanceMin then ARROW_SPENT_TRANSPARENCY else 0
	plus.ImageTransparency = if distanceMax and distance >= distanceMax then ARROW_SPENT_TRANSPARENCY else 0
end

local function requestDistance(delta: number)
	if not distance then
		return
	end

	local wanted = distance + delta
	if distanceMin then
		wanted = math.max(distanceMin, wanted)
	end
	if distanceMax then
		wanted = math.min(distanceMax, wanted)
	end

	if wanted == distance then
		Sounds.play("ui.denied")
		return
	end

	Sounds.play("ui.click")
	RequestViewDistance:FireServer(wanted)
end

minus.MouseButton1Click:Connect(function()
	requestDistance(-DISTANCE_STEP)
end)

plus.MouseButton1Click:Connect(function()
	requestDistance(DISTANCE_STEP)
end)

ViewDistanceChanged.OnClientEvent:Connect(function(applied, low, high, default)
	if type(applied) ~= "number" then
		return
	end

	distance = applied
	distanceMin = if type(low) == "number" then low else distanceMin
	distanceMax = if type(high) == "number" then high else distanceMax
	distanceDefault = if type(default) == "number" then default else distanceDefault

	drawDistance()
end)

drawDistance()

-- ---------------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------------

-- Never smaller than designed on an ordinary screen, bigger on a tall one, and
-- shrunk only when the window would not otherwise fit.
local function fit()
	local size = screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local scale = math.min(
		math.max(1, size.Y / DESIGN_HEIGHT),
		size.Y * 0.9 / L.height,
		size.X * 0.94 / L.width
	)
	rootScale.Scale = math.max(scale, MIN_SCALE)
end

screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

local open = false

local function setOpen(shouldOpen: boolean)
	if shouldOpen == open then
		return
	end
	open = shouldOpen
	dragging = nil

	if shouldOpen then
		fit()
		root.Visible = true
		backdrop.Visible = true
		Motion.openPanel(window, 1)
		TweenService:Create(backdrop, Theme.Tween.Open, { BackgroundTransparency = BACKDROP_TRANSPARENCY }):Play()

		-- What the server holds now: something else (/bbvd, the benchmark) may
		-- have moved it since the last reply.
		RequestViewDistance:FireServer()
	else
		TweenService:Create(backdrop, Theme.Tween.Close, { BackgroundTransparency = 1 }):Play()
		Motion.closePanel(window, function()
			if not open then
				root.Visible = false
				backdrop.Visible = false
			end
		end)
	end

	-- These settings are changed while playing, so the window does not stop
	-- the player moving.
	MenuState.setOpen(MENU_NAME, shouldOpen, false)

	button.BackgroundTransparency = if shouldOpen then BUTTON_HOVER_TRANSPARENCY else BUTTON_TRANSPARENCY
	Sounds.play(if shouldOpen then "ui.open" else "ui.close")
end

button.MouseButton1Click:Connect(function()
	setOpen(not open)
end)

button.MouseEnter:Connect(function()
	if not open then
		button.BackgroundTransparency = BUTTON_HOVER_TRANSPARENCY
	end
end)

button.MouseLeave:Connect(function()
	if not open then
		button.BackgroundTransparency = BUTTON_TRANSPARENCY
	end
end)

closeButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)

backdrop.MouseButton1Click:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if open and input.KeyCode == Enum.KeyCode.Escape and not processed then
		setOpen(false)
	end
end)

-- Two full-screen menus at once is never what anyone wants; the pause menu
-- wins because it is the one with the escape hatch.
MenuState.Changed:Connect(function(name, opened)
	if name == "PauseMenu" and opened and open then
		setOpen(false)
	end
end)
