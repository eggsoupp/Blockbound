--[[
	Motion

	The small set of movements the UI uses: hover, press, open, close, shake,
	pulse and flash. Written once so every button acknowledges a cursor the same
	way. Everything is 60-200ms - the point is to feel responsive, not to
	animate at you.

		Motion.attachButton(button, { onClick = fn })
		Motion.openPanel(frame)
		Motion.shake(frame)
		Motion.pulse(icon)
		Motion.flash(imageLabel, Theme.Color.Good)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Sounds = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("Sounds")
)

local Motion = {}

-- Sounds no-ops on the server, so this needs no guard of its own.
local function play(key)
	if key then
		Sounds.play(key)
	end
end

local function tween(instance, info, goal)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------

--[[
	Hover and press feedback for a GuiButton, and optionally its click.

	  hoverScale / pressScale  size multipliers (1.06 / 0.94)
	  onClick                  called on MouseButton1Click
	  sound / hoverSound       sound keys ("ui.click" / "ui.hover")
	  enabled                  predicate; a disabled button still hovers but
	                           plays "ui.denied" and calls onDenied instead

	Only the offset half of UDim2 is scaled, so a button sized in scale units is
	left alone rather than mangled. Returns a function that re-captures the
	resting size and position - call it after moving the button by layout.
]]
function Motion.attachButton(button, options)
	options = options or {}

	local hoverScale = options.hoverScale or 1.06
	local pressScale = options.pressScale or 0.94
	local baseSize = button.Size
	local basePosition = button.Position
	local hovering = false

	local function scaleTo(multiplier, info)
		-- Grow from the centre: the offset grows and the position shifts back
		-- by half of it, so the button does not crawl to the right.
		local dx = baseSize.X.Offset * (multiplier - 1)
		local dy = baseSize.Y.Offset * (multiplier - 1)

		tween(button, info, {
			Size = UDim2.new(
				baseSize.X.Scale, baseSize.X.Offset + dx,
				baseSize.Y.Scale, baseSize.Y.Offset + dy
			),
			Position = UDim2.new(
				basePosition.X.Scale, basePosition.X.Offset - dx * 0.5,
				basePosition.Y.Scale, basePosition.Y.Offset - dy * 0.5
			),
		})
	end

	button.MouseEnter:Connect(function()
		hovering = true
		scaleTo(hoverScale, Theme.Tween.Hover)
		play(options.hoverSound or "ui.hover")
	end)

	button.MouseLeave:Connect(function()
		hovering = false
		scaleTo(1, Theme.Tween.Hover)
	end)

	button.MouseButton1Down:Connect(function()
		scaleTo(pressScale, Theme.Tween.Press)
	end)

	-- Releasing after the cursor has left must not leave the button enlarged.
	button.MouseButton1Up:Connect(function()
		scaleTo(if hovering then hoverScale else 1, Theme.Tween.Press)
	end)

	if options.onClick then
		button.MouseButton1Click:Connect(function()
			if options.enabled and not options.enabled() then
				play("ui.denied")
				if options.onDenied then
					options.onDenied()
				end
				return
			end

			play(options.sound or "ui.click")
			options.onClick()
		end)
	end

	return function()
		baseSize = button.Size
		basePosition = button.Position
	end
end

--[[
	The same for a slot tile inside a UIListLayout or UIGridLayout.

	Those layouts own their children's Position and Size, so attachButton's
	scaling would be fought and overwritten. This scales the tile's ICON
	instead, which the layout does not touch, being a grandchild.
]]
function Motion.attachSlot(tile, icon, options)
	options = options or {}

	local hoverScale = options.hoverScale or 1.15
	local baseSize = icon.Size
	local basePosition = icon.Position
	local hovering = false

	local function scaleIcon(multiplier, info)
		-- The icon is sized in scale units inside the tile, so grow it about
		-- its own centre by pulling the position back half the growth.
		local grow = multiplier - 1
		tween(icon, info, {
			Size = UDim2.fromScale(baseSize.X.Scale * multiplier, baseSize.Y.Scale * multiplier),
			Position = UDim2.fromScale(
				basePosition.X.Scale - baseSize.X.Scale * grow * 0.5,
				basePosition.Y.Scale - baseSize.Y.Scale * grow * 0.5
			),
		})
	end

	tile.MouseEnter:Connect(function()
		hovering = true
		scaleIcon(hoverScale, Theme.Tween.Hover)
		play(options.hoverSound or "ui.hover")
	end)

	tile.MouseLeave:Connect(function()
		hovering = false
		scaleIcon(1, Theme.Tween.Hover)
	end)

	tile.MouseButton1Down:Connect(function()
		scaleIcon(0.92, Theme.Tween.Press)
	end)

	tile.MouseButton1Up:Connect(function()
		scaleIcon(if hovering then hoverScale else 1, Theme.Tween.Press)
	end)

	if options.onClick then
		tile.MouseButton1Click:Connect(function()
			if options.enabled and not options.enabled() then
				play("ui.denied")
				if options.onDenied then
					options.onDenied()
				end
				return
			end

			play(options.sound or "ui.click")
			options.onClick()
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Panels
-- ---------------------------------------------------------------------------

-- Expects an AnchorPoint of (0.5, 0.5); grows from 96% to full size.
function Motion.openPanel(frame, finalTransparency)
	local target = finalTransparency or frame.BackgroundTransparency
	local size = frame.Size

	frame.Size = UDim2.new(
		size.X.Scale * 0.96, size.X.Offset * 0.96,
		size.Y.Scale * 0.96, size.Y.Offset * 0.96
	)
	frame.BackgroundTransparency = 1

	tween(frame, Theme.Tween.Open, { Size = size, BackgroundTransparency = target })
end

-- `onDone` runs once the panel has finished shrinking, so the caller can hide
-- the ScreenGui only after the animation has played.
function Motion.closePanel(frame, onDone)
	local size = frame.Size

	local t = tween(frame, Theme.Tween.Close, {
		Size = UDim2.new(
			size.X.Scale * 0.96, size.X.Offset * 0.96,
			size.Y.Scale * 0.96, size.Y.Offset * 0.96
		),
		BackgroundTransparency = 1,
	})

	t.Completed:Connect(function()
		frame.Size = size
		if onDone then
			onDone()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Emphasis
-- ---------------------------------------------------------------------------

-- A short horizontal wobble: "that did not work", without a colour or a word.
function Motion.shake(element, magnitude)
	magnitude = magnitude or 6

	local base = element.Position
	local steps = { magnitude, -magnitude * 0.7, magnitude * 0.4, 0 }
	local info = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	task.spawn(function()
		for _, offset in ipairs(steps) do
			tween(element, info, {
				Position = UDim2.new(
					base.X.Scale, base.X.Offset + offset,
					base.Y.Scale, base.Y.Offset
				),
			})
			task.wait(0.05)
		end
		element.Position = base
	end)
end

--[[
	A one-shot scale bump about the element's own centre: "this just changed".
	Used for a stack that grew, a hotbar slot being selected, a craft landing.

	Driven through a UIScale rather than Size, so it composes with a layout that
	owns the element's size and with Motion's own hover scaling.
]]
function Motion.pulse(element, magnitude)
	magnitude = magnitude or 1.18

	local scale = element:FindFirstChild("MotionPulse")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "MotionPulse"
		scale.Parent = element
	end

	scale.Scale = magnitude
	tween(scale, Theme.Tween.Pop, { Scale = 1 })
end

-- Briefly tints an element, then fades back. Confirms a craft or a placement.
-- The resting colour is remembered per element, so flashing twice in quick
-- succession fades back to the real colour rather than to a mid-tween one.
local flashBase = setmetatable({}, { __mode = "k" })

function Motion.flash(element, color, property)
	property = property or "ImageColor3"

	local remembered = flashBase[element]
	if not remembered then
		remembered = {}
		flashBase[element] = remembered
	end

	if remembered[property] == nil then
		remembered[property] = element[property]
	end

	element[property] = color
	tween(element, Theme.Tween.Fade, { [property] = remembered[property] })
end

-- For status lines that change often enough that a hard swap looks like a bug.
function Motion.fadeInText(label)
	label.TextTransparency = 1
	tween(label, Theme.Tween.Hover, { TextTransparency = 0 })
end

return Motion
