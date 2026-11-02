--[[
	MenuWindow

	The frame the Tab menu's other pages are drawn in (QuestWindow,
	BestiaryWindow): a dark panel in the middle of the menu with a title, a
	line under it, and a BACK button that returns to the loadout.

		local window = MenuWindow.new(parent, "GUIDE", width, height, onBack)
		window.body          where the page builds its contents
		window.subtitle      the line beside the title, for a count
		window:setVisible(bool)
		window:place(top, bottom, width)   fit into that room, like PauseMenu
		                                   fits the loadout

	Fades on one CanvasGroup, as AbilityPanel does, and is only Visible while
	shown so a hidden page takes no clicks.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Sounds = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("Sounds")
)

local HEADER_HEIGHT = 44
local PAD = 16

local MenuWindow = {}
MenuWindow.__index = MenuWindow

MenuWindow.Pad = PAD
MenuWindow.HeaderHeight = HEADER_HEIGHT

-- Deep greens off the menu's own backdrop, rather than the grey of the
-- in-game panels: these pages sit on the star field and should belong to it.
MenuWindow.Palette = {
	Base = Color3.fromRGB(14, 27, 24),
	Raised = Color3.fromRGB(22, 40, 36),
	Deep = Color3.fromRGB(8, 17, 15),
	Line = Color3.fromRGB(48, 78, 70),
}
local PALETTE = MenuWindow.Palette

function MenuWindow.new(parent: Instance, title: string, width: number, height: number, onBack: () -> ())
	local self = setmetatable({}, MenuWindow)

	local root = Instance.new("CanvasGroup")
	root.Name = title:gsub("%s", "") .. "Window"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.fromScale(0.5, 0.1)
	root.Size = UDim2.fromOffset(width, height)
	root.BackgroundColor3 = PALETTE.Base
	root.BackgroundTransparency = 0
	root.GroupTransparency = 1
	root.Visible = false
	root.ZIndex = 6
	root.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = root

	local scale = Instance.new("UIScale")
	scale.Name = "FitScale"
	scale.Parent = root

	local heading = Instance.new("TextLabel")
	heading.Name = "Title"
	heading.BackgroundTransparency = 1
	heading.Position = UDim2.fromOffset(PAD, 0)
	heading.Size = UDim2.new(1, -PAD * 2, 0, HEADER_HEIGHT)
	heading.FontFace = Theme.Fonts.Heading
	heading.TextSize = Theme.TextSize.Heading
	heading.TextColor3 = Theme.Color.Text
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = title
	heading.Parent = root

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(PAD + heading.TextBounds.X + 14, 0)
	subtitle.Size = UDim2.new(1, -PAD * 2 - 220, 0, HEADER_HEIGHT)
	subtitle.FontFace = Theme.Fonts.BodyBold
	subtitle.TextSize = Theme.TextSize.Small
	subtitle.TextColor3 = Theme.Color.TextDim
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = ""
	subtitle.Parent = root

	-- Placed off the title's measured width once it has one.
	heading:GetPropertyChangedSignal("TextBounds"):Connect(function()
		subtitle.Position = UDim2.fromOffset(PAD + heading.TextBounds.X + 14, 0)
	end)

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.Position = UDim2.fromOffset(PAD, HEADER_HEIGHT)
	rule.Size = UDim2.new(1, -PAD * 2, 0, 1)
	rule.BackgroundColor3 = PALETTE.Line
	rule.BorderSizePixel = 0
	rule.Parent = root

	local back = Instance.new("TextButton")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(1, 0.5)
	back.Position = UDim2.new(1, -PAD, 0, HEADER_HEIGHT / 2)
	back.Size = UDim2.fromOffset(84, 28)
	back.AutoButtonColor = false
	back.BackgroundColor3 = PALETTE.Raised
	back.BorderSizePixel = 0
	back.FontFace = Theme.Fonts.Heading
	back.TextSize = Theme.TextSize.Small
	back.TextColor3 = Theme.Color.TextDim
	back.Text = "< BACK"
	back.Parent = root

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 4)
	backCorner.Parent = back

	local backStroke = Instance.new("UIStroke")
	backStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	backStroke.Color = PALETTE.Line
	backStroke.Parent = back

	back.MouseEnter:Connect(function()
		back.TextColor3 = Theme.Color.Text
		backStroke.Color = Theme.Color.Text
		Sounds.play("ui.hover")
	end)
	back.MouseLeave:Connect(function()
		back.TextColor3 = Theme.Color.TextDim
		backStroke.Color = PALETTE.Line
	end)
	back.Activated:Connect(function()
		Sounds.play("ui.click")
		onBack()
	end)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(PAD, HEADER_HEIGHT + 12)
	body.Size = UDim2.new(1, -PAD * 2, 1, -(HEADER_HEIGHT + 12 + PAD))
	body.Parent = root

	self.root = root
	self.body = body
	self.subtitle = subtitle
	self.scale = scale
	self.visible = false
	self.fade = nil
	return self
end

function MenuWindow:setVisible(visible: boolean)
	if visible == self.visible then
		return
	end
	self.visible = visible
	if self.fade then
		self.fade:Cancel()
	end

	if visible then
		self.root.Visible = true
	end
	local fade = TweenService:Create(self.root, Theme.Tween.Fade, { GroupTransparency = if visible then 0 else 1 })
	self.fade = fade
	fade.Completed:Connect(function(state)
		if not self.visible and state == Enum.PlaybackState.Completed then
			self.root.Visible = false
		end
	end)
	fade:Play()
end

-- Centred in the room between `top` and `bottom`, shrunk only if it must be.
function MenuWindow:place(top: number, bottom: number, width: number)
	local size = self.root.Size
	local fit = math.min((bottom - top) / size.Y.Offset, (width - 16) / size.X.Offset)
	self.scale.Scale = math.clamp(fit, 0.5, 1)
	local height = size.Y.Offset * self.scale.Scale
	self.root.Position = UDim2.new(0.5, 0, 0, math.max(top, (top + bottom - height) / 2))
end

return MenuWindow
