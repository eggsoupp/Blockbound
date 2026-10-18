--[[
	PixelUI

	Puts the wood-and-parchment pixel-art kit (assets/pixel-ui) on the game's
	windows, and builds the pieces every window shares out of it.

		PixelUI.apply(imageLabel, "frame_parchment")    -- any ImageLabel / ImageButton
		PixelUI.image(parent, "icon_star")               -- a new ImageLabel at its own size
		PixelUI.button(parent, { color = "green", text = "CRAFT", onClick = fn })
		PixelUI.bindButton(imageButton, "tan", content)  -- the same states on your own button
		PixelUI.closeButton(parent, onClick)
		PixelUI.header(parent, "CRAFTING")
		PixelUI.divider(parent)
		PixelUI.padTo(frame, "inset_parchment", 6)       -- UIPadding clear of the border

	Sprite names are the file names in assets/pixel-ui/sprites. Where each one
	is and how it slices comes from Shared.UI.PixelSprites, which the art's
	generator writes; the asset ids are Theme.Pixel's.

	ONE TEXEL IS Theme.Pixel.Scale PIXELS

	The art is drawn at 1x and shown Pixelated at 3x on a 1080p screen, the same
	as the preview page. Sliced sprites take that as their SliceScale, so a
	frame's border is the same thickness on a window and on a button; anything
	unsliced is sized to exactly three times its art. Windows that scale to the
	screen with a UIScale scale the art with them.

	IF THE ART WILL NOT LOAD

	It is an upload, and uploads go missing - that is how the inventory once lost
	its frames, and an ImageLabel pointed at an image that will not load draws
	nothing at all, silently. So each asset is checked once per session, and
	anything drawn from one that fails (or from an id nobody has filled in yet)
	gets a plain frame in the sprite's own colours instead, with one line in
	Output saying why. The stand-in follows ImageColor3, so hover and drop-target
	tints still show on it.
]]

local ContentProvider = game:GetService("ContentProvider")

local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelSprites = require(script.Parent:WaitForChild("PixelSprites"))
local Sounds = require(script.Parent.Parent:WaitForChild("Audio"):WaitForChild("Sounds"))

local PixelUI = {}

PixelUI.Sprites = PixelSprites.Sprites
PixelUI.Scale = Theme.Pixel.Scale
PixelUI.Color = Theme.PixelColor

local SCALE = Theme.Pixel.Scale

-- A button's face sits on a lip two texels deep, and pressing it drops the
-- face onto the lip: its contents move down by the same amount.
local LIP = 2 * SCALE

-- ---------------------------------------------------------------------------
-- Where the art comes from
-- ---------------------------------------------------------------------------

-- A sprite's own upload if it has one, otherwise its place on the atlas.
local function sourceFor(name: string): (string, boolean)
	local own = Theme.Pixel.Images[name]
	if type(own) == "string" and own ~= "" then
		return own, false
	end
	return Theme.Pixel.Atlas or "", true
end

-- asset id -> "checking" | "loaded" | "failed", for the rest of the session.
local assetState: { [string]: string } = {}

-- asset id -> the guis drawn from it while it is being checked. Weak, so a gui
-- destroyed before the answer arrives is not kept alive for it.
local waiting: { [string]: { [GuiObject]: boolean } } = {}

local warnedEmpty = false

-- ---------------------------------------------------------------------------
-- The stand-in
-- ---------------------------------------------------------------------------

local STAND_IN = "PixelStandIn"
local STAND_IN_CORNER = UDim.new(0, 4)
local STAND_IN_STROKE = 2

local function multiply(color: Color3, tint: Color3): Color3
	return Color3.new(color.R * tint.R, color.G * tint.G, color.B * tint.B)
end

local function drawStandIn(gui: GuiObject)
	local sprite = PixelUI.Sprites[gui:GetAttribute("PixelSprite")]
	if not sprite then
		return
	end

	local box = gui:FindFirstChild(STAND_IN)
	if not box then
		box = Instance.new("Frame")
		box.Name = STAND_IN
		box.BorderSizePixel = 0
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		-- Under every sibling the gui's own contents are made of.
		box.ZIndex = 0

		local corner = Instance.new("UICorner")
		corner.CornerRadius = STAND_IN_CORNER
		corner.Parent = box

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = STAND_IN_STROKE
		stroke.Parent = box

		box.Parent = gui

		local function follow()
			if gui:FindFirstChild(STAND_IN) then
				drawStandIn(gui)
			end
		end
		gui:GetPropertyChangedSignal("ImageColor3"):Connect(follow)
		gui:GetPropertyChangedSignal("ImageTransparency"):Connect(follow)
	end

	local tint = gui.ImageColor3
	local transparency = gui.ImageTransparency
	local stroke = box:FindFirstChildOfClass("UIStroke")

	-- An icon is a picture, not a panel: a smaller filled square stands in.
	box.Size = if sprite.icon then UDim2.fromScale(0.7, 0.7) else UDim2.fromScale(1, 1)
	box.BackgroundColor3 = multiply(sprite.fill or sprite.edge or Color3.new(), tint)
	box.BackgroundTransparency = if sprite.fill or sprite.icon then transparency else 1
	stroke.Color = multiply(sprite.edge or Color3.new(), tint)
	stroke.Transparency = if sprite.edge and not sprite.icon then transparency else 1
end

local function clearStandIn(gui: GuiObject)
	local box = gui:FindFirstChild(STAND_IN)
	if box then
		box:Destroy()
	end
end

local function check(id: string)
	assetState[id] = "checking"

	task.spawn(function()
		local loaded = false
		local probe = Instance.new("ImageLabel")
		probe.Image = id
		pcall(function()
			ContentProvider:PreloadAsync({ probe }, function(_, status)
				loaded = status == Enum.AssetFetchStatus.Success
			end)
		end)
		probe:Destroy()

		assetState[id] = if loaded then "loaded" else "failed"

		local list = waiting[id]
		waiting[id] = nil

		if loaded then
			return
		end

		warn(string.format(
			"[PixelUI] %q did not load, so what is drawn from it is shown as plain frames. "
				.. "If it was uploaded as a Decal, its ID is not the image's: paste it into any "
				.. "ImageLabel's Image property in Studio, which swaps it for the image ID, and "
				.. "put that in Theme.Pixel.",
			id
		))

		-- pcall because a gui may have been destroyed while it waited, and one
		-- dead gui should not leave the rest without a frame.
		for gui in pairs(list or {}) do
			if gui:GetAttribute("PixelSource") == id then
				pcall(function()
					gui.Image = ""
					drawStandIn(gui)
				end)
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Putting a sprite on
-- ---------------------------------------------------------------------------

function PixelUI.get(name: string)
	local sprite = PixelUI.Sprites[name]
	assert(sprite, string.format("[PixelUI] there is no sprite called %q", tostring(name)))
	return sprite
end

--[[
	Draws sprite `name` on an ImageLabel or ImageButton. Safe to call again to
	swap sprites - a button's hover state is exactly that.

	`scale` is texels to pixels for a sliced sprite's border, Theme.Pixel.Scale
	unless given. The gui's Size is left alone: windows and buttons are whatever
	size they need to be, and the slicing keeps their borders crisp.
]]
function PixelUI.apply(gui: GuiObject, name: string, scale: number?)
	local sprite = PixelUI.get(name)
	local id, fromAtlas = sourceFor(name)

	gui:SetAttribute("PixelSprite", name)
	gui:SetAttribute("PixelSource", id)
	gui.ResampleMode = Enum.ResamplerMode.Pixelated

	if fromAtlas then
		gui.ImageRectOffset = sprite.offset
		gui.ImageRectSize = sprite.size
	else
		gui.ImageRectOffset = Vector2.zero
		gui.ImageRectSize = Vector2.zero
	end

	if sprite.slice then
		gui.ScaleType = Enum.ScaleType.Slice
		gui.SliceCenter = sprite.slice
		gui.SliceScale = scale or SCALE
	else
		gui.ScaleType = Enum.ScaleType.Stretch
	end

	if id == "" then
		if not warnedEmpty then
			warnedEmpty = true
			warn("[PixelUI] Theme.Pixel has no asset ids yet, so the windows are drawn as plain "
				.. "frames. Upload assets/pixel-ui/atlas/pixel_ui_atlas.png and put its image ID in "
				.. "Theme.Pixel.Atlas.")
		end
		gui.Image = ""
		drawStandIn(gui)
		return gui
	end

	local state = assetState[id]
	if state == "failed" then
		gui.Image = ""
		drawStandIn(gui)
		return gui
	end

	gui.Image = id
	clearStandIn(gui)

	if state ~= "loaded" then
		local list = waiting[id]
		if not list then
			list = setmetatable({}, { __mode = "k" })
			waiting[id] = list
		end
		list[gui] = true
		if state == nil then
			check(id)
		end
	end

	return gui
end

-- A sprite's own size on screen, at `scale` pixels a texel.
function PixelUI.size(name: string, scale: number?): UDim2
	local size = PixelUI.get(name).size * (scale or SCALE)
	return UDim2.fromOffset(size.X, size.Y)
end

--[[
	How thick a sliced sprite's border is on screen, side by side: what to keep
	the contents clear of. Returns left, top, right, bottom.
]]
function PixelUI.border(name: string, scale: number?): (number, number, number, number)
	local sprite = PixelUI.get(name)
	local slice = sprite.slice
	if not slice then
		return 0, 0, 0, 0
	end
	scale = scale or SCALE
	return slice.Min.X * scale,
		slice.Min.Y * scale,
		(sprite.size.X - slice.Max.X) * scale,
		(sprite.size.Y - slice.Max.Y) * scale
end

-- A UIPadding that keeps `frame`'s children inside the border of `name`, plus
-- `extra` pixels all round.
function PixelUI.padTo(frame: GuiObject, name: string, extra: number?): UIPadding
	local left, top, right, bottom = PixelUI.border(name)
	extra = extra or 0

	local padding = frame:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left + extra)
	padding.PaddingTop = UDim.new(0, top + extra)
	padding.PaddingRight = UDim.new(0, right + extra)
	padding.PaddingBottom = UDim.new(0, bottom + extra)
	padding.Parent = frame
	return padding
end

-- A new ImageLabel showing `name`, at its own size unless the caller resizes it.
function PixelUI.image(parent: Instance?, name: string, scale: number?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Size = PixelUI.size(name, scale)
	PixelUI.apply(image, name, scale)
	image.Parent = parent
	return image
end

-- An engraved line across a parchment panel, full width.
function PixelUI.divider(parent: Instance?): ImageLabel
	local line = PixelUI.image(parent, "divider")
	line.Name = "Divider"
	line.Size = UDim2.new(1, 0, 0, PixelUI.get("divider").size.Y * SCALE)
	return line
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------

-- The sprite for each state, and the label colour that reads on it.
PixelUI.ButtonStyles = {
	green = {
		idle = "button_green", hover = "button_green_hover", pressed = "button_green_pressed",
		text = Theme.PixelColor.OnGreen,
	},
	red = {
		idle = "button_red", hover = "button_red_hover", pressed = "button_red_pressed",
		text = Color3.fromRGB(43, 15, 12),
	},
	tan = {
		idle = "button_tan", hover = "button_tan_hover", pressed = "button_tan_pressed",
		text = Theme.PixelColor.Ink,
	},
	disabled = {
		idle = "button_disabled", hover = "button_disabled", pressed = "button_disabled",
		text = Color3.fromRGB(94, 90, 84),
		inert = true,
	},
	close = {
		idle = "close", hover = "close_hover", pressed = "close_pressed",
		text = Theme.PixelColor.Ink,
	},
}

--[[
	Hover and press on an ImageButton the caller built: the sprite follows the
	cursor, and `content` (a Frame holding the label, or anything else drawn on
	the face) drops with the face when it is pressed.

	Pixel art is not scaled on hover - a stretched texel looks like a mistake -
	so the art changing is the whole acknowledgement. Clicks are the caller's.

	Returns a handle:
	  handle.setStyle(name)   "green", "red", "tan", "disabled", or a table like
	                          PixelUI.ButtonStyles' entries
	  handle.getStyle()       the name it was last given
	  handle.onPaint(fn)      fn(style) after every repaint, to recolour labels
]]
function PixelUI.bindButton(button: GuiButton, style: string | {}, content: GuiObject?)
	local current = style
	local hovered, pressed = false, false
	local painters = {}

	local function resolve()
		return if type(current) == "table" then current else PixelUI.ButtonStyles[current]
	end

	local function paint()
		local set = resolve()
		local down = pressed and not set.inert
		PixelUI.apply(button, if down then set.pressed elseif hovered then set.hover else set.idle)
		if content then
			content.Position = UDim2.fromOffset(0, if down then LIP else 0)
		end
		for _, painter in ipairs(painters) do
			painter(set)
		end
	end

	button.MouseEnter:Connect(function()
		hovered = true
		paint()
	end)
	button.MouseLeave:Connect(function()
		hovered, pressed = false, false
		paint()
	end)
	button.MouseButton1Down:Connect(function()
		pressed = true
		paint()
	end)
	button.MouseButton1Up:Connect(function()
		pressed = false
		paint()
	end)

	local handle = {}

	function handle.setStyle(newStyle)
		if newStyle ~= current then
			current = newStyle
			paint()
		end
	end

	function handle.getStyle()
		return current
	end

	function handle.onPaint(painter)
		table.insert(painters, painter)
		painter(resolve())
	end

	paint()
	return handle
end

--[[
	A text button: the sprite, a Content frame over its face, a label in it.

	  color       "green" (the action), "tan" (everything else), "red" (cannot
	              be undone). Default "tan".
	  text, textSize, font
	  size        UDim2; default a 14-texel-tall button 160 wide
	  onClick     called on click, with the sound played first
	  enabled     predicate: false plays "ui.denied" and calls onDenied instead
	  sound       the click's sound key, "ui.click" unless given

	Returns the bindButton handle with .button, .content and .label on it, and
	setEnabled(bool), which shows the grey sprite and refuses clicks.
]]
function PixelUI.button(parent: Instance?, options)
	options = options or {}

	local button = Instance.new("ImageButton")
	button.Name = options.name or "Button"
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Size = options.size or UDim2.fromOffset(160, 14 * SCALE)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 1, -LIP)
	content.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = options.font or Theme.Fonts.Heading
	label.TextSize = options.textSize or Theme.TextSize.Subheading
	label.Text = options.text or ""
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = content

	local baseStyle = options.color or "tan"
	local handle = PixelUI.bindButton(button, baseStyle, content)
	handle.button, handle.content, handle.label = button, content, label

	handle.onPaint(function(set)
		label.TextColor3 = set.text
	end)

	function handle.setEnabled(on: boolean)
		handle.setStyle(if on then baseStyle else "disabled")
	end

	function handle.setColor(color: string)
		local wasEnabled = handle.getStyle() ~= "disabled"
		baseStyle = color
		if wasEnabled then
			handle.setStyle(color)
		end
	end

	button.MouseEnter:Connect(function()
		Sounds.play(options.hoverSound or "ui.hover")
	end)

	if options.onClick then
		button.MouseButton1Click:Connect(function()
			if handle.getStyle() == "disabled" or (options.enabled and not options.enabled()) then
				Sounds.play("ui.denied")
				if options.onDenied then
					options.onDenied()
				end
				return
			end
			Sounds.play(options.sound or "ui.click")
			options.onClick()
		end)
	end

	button.Parent = parent
	return handle
end

--[[
	The ✖ that sits over a window's top-right corner. Anchored at its centre, so
	placing it on the corner is UDim2.new(1, -inset, 0, inset).
]]
function PixelUI.closeButton(parent: Instance?, onClick: (() -> ())?): ImageButton
	local button = Instance.new("ImageButton")
	button.Name = "Close"
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = PixelUI.size("close")
	PixelUI.bindButton(button, "close")

	button.MouseEnter:Connect(function()
		Sounds.play("ui.hover")
	end)
	if onClick then
		button.MouseButton1Click:Connect(function()
			Sounds.play("ui.click")
			onClick()
		end)
	end

	button.Parent = parent
	return button
end

-- ---------------------------------------------------------------------------
-- Headers
-- ---------------------------------------------------------------------------

--[[
	The title banner, as wide as its text: green unless `sprite` names another
	("header_red" is the boss's). Anchored at its centre: laid across a window's
	top edge it is UDim2.new(0.5, 0, 0, 0) on the window. Returns the banner and
	its label, so the title can change.
]]
function PixelUI.header(parent: Instance?, text: string, sprite: string?): (ImageLabel, TextLabel)
	sprite = sprite or "header"

	local banner = PixelUI.image(nil, sprite)
	banner.Name = "Header"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Size = UDim2.fromOffset(0, PixelUI.get(sprite).size.Y * SCALE)
	banner.AutomaticSize = Enum.AutomaticSize.X

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 7 * SCALE)
	padding.PaddingRight = UDim.new(0, 7 * SCALE)
	padding.PaddingBottom = UDim.new(0, SCALE)
	padding.Parent = banner

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.FontFace = Theme.Fonts.Heading
	label.TextSize = Theme.TextSize.Heading
	label.TextColor3 = Theme.PixelColor.OnGreen
	label.Text = text
	label.Parent = banner

	banner.Parent = parent
	return banner, label
end

-- ---------------------------------------------------------------------------
-- Bars
-- ---------------------------------------------------------------------------

--[[
	Where the dark groove sits inside each bar frame, in texels from its edges:
	where a fill laid over the frame belongs. These follow the art in
	assets/pixel-ui/source/build_sprites.cs; change one, change the other.
]]
PixelUI.Grooves = {
	bar_frame = { left = 4, top = 4, right = 4, bottom = 3 },
	boss_frame = { left = 6, top = 4, right = 6, bottom = 4 },
}

-- A frame's groove inset on screen, side by side: left, top, right, bottom.
function PixelUI.groove(name: string): (number, number, number, number)
	local groove = PixelUI.Grooves[name]
	assert(groove, string.format("[PixelUI] %q is not a bar frame", tostring(name)))
	return groove.left * SCALE, groove.top * SCALE, groove.right * SCALE, groove.bottom * SCALE
end

-- ---------------------------------------------------------------------------
-- Scroll bars
-- ---------------------------------------------------------------------------

--[[
	A ScrollingFrame's bar in the kit's green, where it can be.

	Its Top/Mid/BottomImage take a whole image and cannot be pointed at a piece
	of the atlas, so the drawn bar only appears once scroll_top, scroll_mid and
	scroll_bottom have their own ids in Theme.Pixel.Images. Until then it is
	Roblox's bar in the dark wood colour, which reads fine on parchment.
]]
function PixelUI.styleScrollBar(scroller: ScrollingFrame)
	local images = Theme.Pixel.Images
	local top, mid, bottom = images.scroll_top, images.scroll_mid, images.scroll_bottom

	if top and mid and bottom and top ~= "" and mid ~= "" and bottom ~= "" then
		scroller.TopImage = top
		scroller.MidImage = mid
		scroller.BottomImage = bottom
		scroller.ScrollBarImageColor3 = Color3.new(1, 1, 1)
		scroller.ScrollBarImageTransparency = 0
		scroller.ScrollBarThickness = PixelUI.get("scroll_mid").size.X * SCALE
	else
		scroller.ScrollBarImageColor3 = Color3.fromRGB(90, 53, 32)
		scroller.ScrollBarImageTransparency = 0.1
		scroller.ScrollBarThickness = 2 * SCALE
	end
end

return PixelUI
