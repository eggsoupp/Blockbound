--[[
	TopbarButtons

	The game's own buttons in Roblox's top bar - settings and the island
	recall - lined up at its RIGHT end, the same size as Roblox's buttons, each
	with a short summary under it on hover. Client only.

		local tip = TopbarButtons.add(button, order, function()
			return "Settings - sound, world and combat options"
		end)

	`order` counts from the right: 1 is the last button on the bar, 2 sits
	left of it, and so on. An optional fourth argument makes a button wider
	than it is tall, in multiples of its height (the island picker's name).
 The button must be in a ScreenGui that ignores the
	GUI inset (TopbarInset is measured from the window's corner). The summary
	is asked for again every frame it is showing, so it can change while the
	pointer rests on the button (the recall's "Cancel teleport").

		TopbarButtons.leftEdge()   where the leftmost of them starts, for
		                           windows that must stop short of them
		                           (Responsive.fitWindow)

	One place for the arithmetic, so two scripts' buttons cannot drift apart.
]]

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelUI = require(script.Parent:WaitForChild("PixelUI"))

local TopbarButtons = {}

-- Roblox draws its own buttons BAR_MARGIN short of the bar's height; these
-- match, between MIN_SIZE and MAX_SIZE, GAP apart and GAP from the edge.
local GAP = 8
local BAR_MARGIN = 8
local MIN_SIZE = 32
local MAX_SIZE = 48

-- Between the bottom of a button and the top of its summary.
local TIP_GAP = 6

local entries = {}
local highest = 0

-- The bar's height, with Roblox's desktop 36 as the floor for a client that
-- has not set its top bar up yet and reports nothing.
local function barHeight(inset: Rect): number
	return math.max(inset.Height, 36)
end

function TopbarButtons.size(): number
	return math.clamp(barHeight(GuiService.TopbarInset) - BAR_MARGIN * 2, MIN_SIZE, MAX_SIZE)
end

-- How wide the button at `order` is, and the x of its right edge.
local function widthOf(order: number, size: number): number
	for _, entry in ipairs(entries) do
		if entry.order == order then
			return size * entry.widthScale
		end
	end
	return size
end

local function rightEdgeOf(order: number, size: number): number
	local right = GuiService.TopbarInset.Max.X - GAP
	for below = 1, order - 1 do
		right -= widthOf(below, size) + GAP
	end
	return right
end

-- The x of the left edge of the button furthest from the right.
function TopbarButtons.leftEdge(): number
	local size = TopbarButtons.size()
	return rightEdgeOf(highest, size) - widthOf(highest, size)
end

local function place(entry)
	local inset = GuiService.TopbarInset
	local size = TopbarButtons.size()
	local right = rightEdgeOf(entry.order, size)
	local middle = inset.Min.Y + barHeight(inset) * 0.5

	entry.button.AnchorPoint = Vector2.new(1, 0.5)
	entry.button.Size = UDim2.fromOffset(size * entry.widthScale, size)
	entry.button.Position = UDim2.fromOffset(right, middle)

	-- Under the button, its right edge on the button's, so it never runs off
	-- the right of the screen.
	entry.tip.Position = UDim2.fromOffset(right, middle + size * 0.5 + TIP_GAP)
end

GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
	for _, entry in ipairs(entries) do
		place(entry)
	end
end)

function TopbarButtons.add(button: GuiButton, order: number, summary: () -> string, widthScale: number?): Frame
	local tip = PixelUI.image(button.Parent, "badge")
	tip.Name = button.Name .. "Tip"
	tip.AnchorPoint = Vector2.new(1, 0)
	tip.Size = UDim2.fromOffset(0, PixelUI.get("badge").size.Y * PixelUI.Scale)
	tip.AutomaticSize = Enum.AutomaticSize.X
	tip.ZIndex = 10
	tip.Visible = false

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = tip

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.FontFace = Theme.Fonts.BodyBold
	label.TextSize = Theme.TextSize.Small
	label.TextColor3 = Theme.PixelColor.OnWood
	label.ZIndex = 11
	label.Parent = tip

	local entry = { button = button, order = order, tip = tip, widthScale = widthScale or 1 }
	table.insert(entries, entry)
	highest = math.max(highest, order)
	-- A wider button moves everything left of it, so all are placed again.
	for _, other in ipairs(entries) do
		place(other)
	end

	local watching: RBXScriptConnection? = nil
	button.MouseEnter:Connect(function()
		label.Text = summary()
		tip.Visible = true
		if not watching then
			watching = RunService.RenderStepped:Connect(function()
				label.Text = summary()
			end)
		end
	end)
	button.MouseLeave:Connect(function()
		tip.Visible = false
		if watching then
			watching:Disconnect()
			watching = nil
		end
	end)

	return tip
end

return TopbarButtons
