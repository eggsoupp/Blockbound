--[[
	SettingsButton

	The gear in the topbar, next to Roblox's own chat button, and the small menu
	it opens: sound on or off, and view distance.

	WHY IT IS NOT IN THE TAB MENU

	Because those two are the settings a player changes WHILE PLAYING - sound
	because somebody walked into the room, view distance because the frame rate
	dropped - and both of those are worse moments to be dropped into a modal
	menu that stops you moving and swings the camera. The Tab menu is where you
	go to look at your abilities; this is where you go to turn the music off.

	THE BUTTON LOOKS LIKE ROBLOX'S OWN; THE PANEL LOOKS LIKE THE GAME'S

	The gear is chrome in Roblox's topbar, so it matches the core buttons beside
	it: same size and spacing, the same translucent black rounded square, the
	same white glyph, drawn from Frames rather than being an image. The panel
	it opens is the game's, so it is drawn from the pixel-art kit like every
	other window: parchment in a wooden frame, the kit's toggle, slider and
	arrows (Shared.UI.PixelUI).

	WHERE IT SITS IS ASKED FOR, NOT GUESSED

	GuiService.TopbarInset is the region Roblox leaves free for developer UI:
	its left edge is exactly where the core buttons stop. Hard-coding an offset
	would be a number that is wrong the next time Roblox changes its topbar,
	and it changes. The inset is also watched, because it moves when the chat
	button appears and disappears.

	VIEW DISTANCE IS THE SERVER'S ANSWER, NOT THE CLICK

	The number displayed is always the one the SERVER confirmed, never the one
	the player just clicked - it decides how much terrain the server generates
	and holds on this player's behalf. Pressing + shows nothing until the reply
	lands, which is correct: it means the readout can never claim a distance
	that is not actually loaded.
]]

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local PixelUI = require(Shared.UI:WaitForChild("PixelUI"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local Music = require(Shared.Audio:WaitForChild("Music"))

local RequestViewDistance = Remotes.wait("RequestViewDistance")
local ViewDistanceChanged = Remotes.wait("ViewDistanceChanged")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

local PANEL_WIDTH = 340
local PANEL_TOP_GAP = 6
-- Inside the frame art's border.
local PANEL_PAD = 6
local PANEL_ROW_HEIGHT = 46

local VOLUME_WIDTH = 140

-- The volume fill is a sliced sprite, and never drawn narrower than its two
-- rounded ends.
local VOLUME_FILL_MIN = 6 * PixelUI.Scale

local DISTANCE_BOX_WIDTH = 58

-- Fractions of a view-distance step. The server owns the real bounds and sends
-- them, so this is only the size of one press.
local DISTANCE_STEP = 1

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

	local teeth = {}
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

		table.insert(teeth, tooth)
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

-- ---------------------------------------------------------------------------
-- Where it sits
-- ---------------------------------------------------------------------------

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
-- The panel
-- ---------------------------------------------------------------------------

-- Parchment in a wooden frame, as tall as its rows.
local panel = PixelUI.image(screen, "frame_parchment")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.Visible = false
PixelUI.padTo(panel, "frame_parchment", PANEL_PAD)

local panelLayout = Instance.new("UIListLayout")
panelLayout.FillDirection = Enum.FillDirection.Vertical
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Parent = panel

local rowCount = 0

--[[
	A labelled row, and the space on its right for whatever controls it.

	Adding a setting is a call to this and then whatever control it needs built
	into the row it hands back. The panel sizes itself to its contents.
]]
local function addRow(text: string): Frame
	rowCount += 1

	if rowCount > 1 then
		local divider = PixelUI.divider(panel)
		divider.LayoutOrder = rowCount * 10 - 1
	end

	local row = Instance.new("Frame")
	row.Name = text
	row.LayoutOrder = rowCount * 10
	row.Size = UDim2.new(1, 0, 0, PANEL_ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.Parent = panel

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(0, 0.5)
	label.Size = UDim2.new(0.5, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Body
	label.TextSize = Theme.TextSize.Body
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Theme.PixelColor.Ink
	label.Text = text
	label.Parent = row

	return row
end

-- ---------------------------------------------------------------------------
-- Sound
-- ---------------------------------------------------------------------------

--[[
	One switch for everything audible.

	Muting is done by remembering the music volume and setting it to zero rather
	than by a flag every play site would have to check - so nothing else in the
	game needs to know this switch exists, and unmuting puts the volume back
	exactly where the player had left the slider.

	Sounds.MasterVolume covers the effects, which are read per play, so it takes
	effect on the next sound rather than cutting one already in the air. That is
	the right behaviour for a mute: it stops the noise, it does not clip it.
]]
local soundOn = true
local mutedMusicVolume = nil

local soundRow = addRow("Sound")

-- The kit's switch: two drawings, knob left on wood and knob right on green.
local toggle = Instance.new("ImageButton")
toggle.Name = "Toggle"
toggle.AutoButtonColor = false
toggle.AnchorPoint = Vector2.new(1, 0.5)
toggle.Position = UDim2.fromScale(1, 0.5)
toggle.Size = PixelUI.size("toggle_on")
toggle.BackgroundTransparency = 1
toggle.BorderSizePixel = 0
toggle.Parent = soundRow

-- Pixel art does not slide between texels, so the switch flips rather than
-- tweening; the click sound is what confirms it.
local function drawToggle(_animate: boolean)
	PixelUI.apply(toggle, if soundOn then "toggle_on" else "toggle_off")
end

local function setSound(on: boolean)
	if on == soundOn then
		return
	end
	soundOn = on

	if on then
		Sounds.MasterVolume = 1
		if mutedMusicVolume then
			Music.setVolume(mutedMusicVolume)
			mutedMusicVolume = nil
		end
	else
		-- Read before it is zeroed, so unmuting restores what the slider says
		-- rather than a number this file made up.
		mutedMusicVolume = Music.getVolume()
		Music.setVolume(0)
		Sounds.MasterVolume = 0
	end

	drawToggle(true)

	-- After the volume is back up, so turning sound ON is audible and turning
	-- it off is not. The click is the confirmation either way.
	Sounds.play("ui.click")
end

toggle.MouseButton1Click:Connect(function()
	setSound(not soundOn)
end)

drawToggle(false)

-- ---------------------------------------------------------------------------
-- Volume
-- ---------------------------------------------------------------------------

--[[
	The music volume, as a slider.

	It exists because this panel REPLACED the one in the Tab menu, and that one
	was granular. A toggle alone would have been a quieter way of deleting a
	control: "sound is redundant now" is only true if everything it could do can
	still be done.

	Music owns Sound.Volume - writing it anywhere else fought the track fade,
	and the next track change threw the choice away - so this goes through
	setVolume and follows Music.Changed rather than its own last write. That is
	also what keeps the knob honest while the mute toggle is moving the same
	number underneath it.
]]
local volumeRow = addRow("Volume")

-- The kit's slider: a wooden groove, a green fill in it, and a tan knob. The
-- knob hangs half its width past the end at full volume, so the track stops
-- that far short of the row's edge.
local volumeKnobWidth = PixelUI.get("slider_knob").size.X * PixelUI.Scale

local volumeTrack = PixelUI.image(volumeRow, "slider_track")
volumeTrack.Name = "Track"
volumeTrack.AnchorPoint = Vector2.new(1, 0.5)
volumeTrack.Position = UDim2.new(1, -volumeKnobWidth / 2, 0.5, 0)
volumeTrack.Size = UDim2.fromOffset(VOLUME_WIDTH, PixelUI.get("slider_track").size.Y * PixelUI.Scale)

local volumeFill = PixelUI.image(volumeTrack, "slider_fill")
volumeFill.Name = "Fill"
volumeFill.Size = UDim2.fromScale(1, 1)

local volumeKnob = PixelUI.image(volumeTrack, "slider_knob")
volumeKnob.Name = "Knob"
volumeKnob.AnchorPoint = Vector2.new(0.5, 0.5)
volumeKnob.ZIndex = 2

--[[
	The grab area, over the whole row rather than only the knob.

	A knob is a small thing to hit and an unforgiving one to miss, and the row
	is otherwise doing nothing with the space.
]]
local volumeGrab = Instance.new("TextButton")
volumeGrab.Name = "Grab"
volumeGrab.Text = ""
volumeGrab.AutoButtonColor = false
volumeGrab.AnchorPoint = Vector2.new(1, 0.5)
volumeGrab.Position = UDim2.fromScale(1, 0.5)
volumeGrab.Size = UDim2.fromOffset(VOLUME_WIDTH + volumeKnobWidth, PANEL_ROW_HEIGHT)
volumeGrab.BackgroundTransparency = 1
volumeGrab.ZIndex = 3
volumeGrab.Parent = volumeRow

local function drawVolume(value: number)
	-- Never narrower than the fill's two ends; the knob covers the difference.
	volumeFill.Size = UDim2.new(value, (1 - value) * VOLUME_FILL_MIN, 1, 0)
	volumeKnob.Position = UDim2.new(value, 0, 0.5, 0)
end

--[[
	Where along the track a pointer is, as 0..1.

	`x` is an InputObject's Position, which is in the same space as
	AbsolutePosition. UserInputService:GetMouseLocation() is NOT, even in a
	ScreenGui that ignores the GUI inset: it counts from the window's corner,
	inset included - the same trap that put the inventory's drop targets a top
	bar too high. Here only the left inset matters, which is zero on a PC and
	not on a phone with a notch. The panel's card drag gets away with pure
	deltas - a slider cannot, because clicking the track has to jump to where
	the click was.
]]
local function volumeAt(x: number): number
	local left = volumeTrack.AbsolutePosition.X
	local width = volumeTrack.AbsoluteSize.X
	if width <= 0 then
		return 0
	end
	return math.clamp((x - left) / width, 0, 1)
end

local draggingVolume = false

local function applyVolume(x: number)
	local value = volumeAt(x)
	drawVolume(value)

	-- Straight to Music, which is what actually owns the number. Muting is a
	-- separate switch and is left alone: dragging the slider while muted sets
	-- what unmuting will restore, which is the least surprising reading of it.
	if soundOn then
		Music.setVolume(value)
	else
		mutedMusicVolume = value
	end
end

volumeGrab.InputBegan:Connect(function(input)
	if
		input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		draggingVolume = true
		applyVolume(input.Position.X)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not draggingVolume then
		return
	end

	if
		input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
	then
		applyVolume(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if
		input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		draggingVolume = false
	end
end)

-- Followed rather than assumed, so the knob is right whoever moved the volume -
-- including the mute switch above, which sets it to zero and back.
Music.Changed.Event:Connect(function(value)
	if not draggingVolume and soundOn then
		drawVolume(math.clamp(value, 0, 1))
	end
end)

drawVolume(math.clamp(Music.getVolume(), 0, 1))

-- ---------------------------------------------------------------------------
-- View distance
-- ---------------------------------------------------------------------------

local distanceRow = addRow("View distance")

local distance, distanceMin, distanceMax = nil, nil, nil

-- The kit's green arrows either side of the number, which sits in a text box.
local arrowWidth = PixelUI.get("icon_arrow_right").size.X * PixelUI.Scale

local distanceBox = PixelUI.image(distanceRow, "input")
distanceBox.Name = "Distance"
distanceBox.AnchorPoint = Vector2.new(1, 0.5)
distanceBox.Position = UDim2.new(1, -(arrowWidth + 6), 0.5, 0)
distanceBox.Size = UDim2.fromOffset(DISTANCE_BOX_WIDTH, 36)

local distanceValue = Instance.new("TextLabel")
distanceValue.Size = UDim2.fromScale(1, 1)
distanceValue.BackgroundTransparency = 1
distanceValue.FontFace = Theme.Fonts.Number
distanceValue.TextSize = Theme.TextSize.Body
distanceValue.TextColor3 = Theme.PixelColor.InkSoft
distanceValue.Text = "..."
distanceValue.Parent = distanceBox

local function stepButton(sprite: string, offsetFromRight: number): ImageButton
	local step = Instance.new("ImageButton")
	step.Name = sprite
	step.AutoButtonColor = false
	step.AnchorPoint = Vector2.new(1, 0.5)
	step.Position = UDim2.new(1, -offsetFromRight, 0.5, 0)
	step.Size = PixelUI.size(sprite)
	step.BackgroundTransparency = 1
	step.BorderSizePixel = 0
	step.Parent = distanceRow
	PixelUI.apply(step, sprite)
	return step
end

local minus = stepButton("icon_arrow_left", arrowWidth + 6 + DISTANCE_BOX_WIDTH + 6)
local plus = stepButton("icon_arrow_right", 0)

-- How an arrow looks with nowhere left to go.
local ARROW_SPENT_TRANSPARENCY = 0.6

local function drawDistance()
	if not distance then
		distanceValue.Text = "..."
		return
	end

	distanceValue.Text = tostring(distance)
	distanceValue.TextColor3 = Theme.PixelColor.Ink

	-- Faded at the ends rather than hidden, so the range is visible without
	-- the row changing shape.
	minus.ImageTransparency = if distanceMin and distance <= distanceMin
		then ARROW_SPENT_TRANSPARENCY
		else 0
	plus.ImageTransparency = if distanceMax and distance >= distanceMax
		then ARROW_SPENT_TRANSPARENCY
		else 0
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

ViewDistanceChanged.OnClientEvent:Connect(function(applied, low, high)
	if type(applied) ~= "number" then
		return
	end

	distance = applied
	distanceMin = if type(low) == "number" then low else distanceMin
	distanceMax = if type(high) == "number" then high else distanceMax

	drawDistance()
end)

drawDistance()

-- ---------------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------------

local open = false

local function placePanel()
	local inset = GuiService.TopbarInset
	panel.Position = UDim2.fromOffset(
		inset.Min.X + BUTTON_GAP,
		inset.Min.Y + barHeight(inset) + PANEL_TOP_GAP
	)
end

local function setOpen(shouldOpen: boolean)
	if shouldOpen == open then
		return
	end
	open = shouldOpen

	if shouldOpen then
		placePanel()
	end

	panel.Visible = shouldOpen
	button.BackgroundTransparency = if shouldOpen
		then BUTTON_HOVER_TRANSPARENCY
		else BUTTON_TRANSPARENCY

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

--[[
	A click anywhere else closes it.

	Watched globally rather than with a full-screen invisible button behind the
	panel, because that button would also swallow the click - so dismissing the
	menu and pressing the thing you actually wanted would take two clicks.

	`processed` is true when the click landed on some GUI, which includes the
	panel and the gear; both of those have their own handlers and neither wants
	this one as well.
]]
UserInputService.InputBegan:Connect(function(input, processed)
	if not open or processed then
		return
	end

	if
		input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		setOpen(false)
	end
end)
