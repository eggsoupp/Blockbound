--[[
	Confirm

	"Are you sure?" - one modal, borrowed by anything that is about to do
	something a player cannot undo.

		Confirm.ask({
			title = "Drop Eclipse?",
			body = "It leaves your loadout. Getting it back means another scroll.",
			accept = "Drop",
			tone = "bad",
		}, function(accepted)
			...
		end)

	  title    the question, in the panel's heading
	  body     what actually happens if they say yes. Optional, and worth
	           writing: the title is the decision, this is the consequence.
	  accept   wording on the yes button. "Drop", not "OK" - a button that
	           names its action is one you can read without the title.
	  tone     "bad" colours the accept button as a destructive act; anything
	           else leaves it neutral.

	THE CALLBACK ALWAYS RUNS, EXACTLY ONCE

	With true or with false. Cancelling, clicking the dim, and asking while
	another question is already up all come back as false, so a caller never has
	to handle "and sometimes nothing happens" - which is the state that leaves a
	dragged card floating and a scroll half-used.

	IT IS A MENU, AND SAYS SO

	Registered with MenuState while it is up, so the player stops moving and the
	cursor comes free. A scroll is read out in the world with the mouse locked
	to the camera, and a dialog nobody can click is worse than no dialog.

	ONE AT A TIME. A second question refuses rather than stacking: the dim
	swallows input, so the only way to reach one is a signal that does not need
	the mouse - a tool firing twice - and the right answer to that is "no".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Theme = require(script.Parent:WaitForChild("Theme"))
local MenuState = require(script.Parent:WaitForChild("MenuState"))
local Sounds = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("Sounds")
)

local Confirm = {}

local MENU_NAME = "Confirm"

local CARD_WIDTH = 360
local EDGE = 18
local TITLE_HEIGHT = 26
local BODY_HEIGHT = 40
local BUTTON_HEIGHT = 34
local BUTTON_GAP = 10

-- Over every other menu in the game, because it is asked ON TOP of one: the
-- bin lives inside the Tab menu's own backdrop.
local DISPLAY_ORDER = 30

local gui = nil
local card = nil
local titleLabel, bodyLabel, acceptButton, cancelButton = nil, nil, nil, nil

local pending = nil

--[[
	Built once, on the first question, and kept.

	A dialog nobody has opened yet should not be five instances sitting in the
	PlayerGui, and one that has been opened once is very likely to be opened
	again.
]]
local function build()
	if gui then
		return
	end

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	gui = Instance.new("ScreenGui")
	gui.Name = "Confirm"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui

	--[[
		The dim, and the reason it is a BUTTON.

		A Frame with Active would sink the click, which is most of the job, but
		a button also gives the "click outside to cancel" behaviour its own
		handler rather than a global input listener that has to work out whether
		the click was inside the card.
	]]
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Theme.Color.Backdrop
	dim.BackgroundTransparency = 0.4
	dim.BorderSizePixel = 0
	dim.Parent = gui

	card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(CARD_WIDTH, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Theme.Color.Panel
	card.BackgroundTransparency = Theme.Transparency.Panel
	card.BorderSizePixel = 0
	card.ZIndex = 2
	card.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Stroke
	stroke.Thickness = 1
	stroke.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, EDGE)
	padding.PaddingBottom = UDim.new(0, EDGE)
	padding.PaddingLeft = UDim.new(0, EDGE)
	padding.PaddingRight = UDim.new(0, EDGE)
	padding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = card

	titleLabel = Instance.new("TextLabel")
	titleLabel.LayoutOrder = 1
	titleLabel.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = Theme.Fonts.Heading
	titleLabel.TextSize = Theme.TextSize.Subheading
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Theme.Color.Text
	titleLabel.Text = ""
	titleLabel.ZIndex = 2
	titleLabel.Parent = card

	bodyLabel = Instance.new("TextLabel")
	bodyLabel.LayoutOrder = 2
	bodyLabel.Size = UDim2.new(1, 0, 0, BODY_HEIGHT)
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.FontFace = Theme.Fonts.Body
	bodyLabel.TextSize = Theme.TextSize.Body
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.TextWrapped = true
	bodyLabel.TextColor3 = Theme.Color.TextDim
	bodyLabel.Text = ""
	bodyLabel.ZIndex = 2
	bodyLabel.Parent = card

	local buttons = Instance.new("Frame")
	buttons.LayoutOrder = 3
	buttons.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	buttons.BackgroundTransparency = 1
	buttons.ZIndex = 2
	buttons.Parent = card

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Padding = UDim.new(0, BUTTON_GAP)
	buttonLayout.Parent = buttons

	local function newButton(order: number, name: string): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.LayoutOrder = order
		button.AutoButtonColor = false
		button.Size = UDim2.fromOffset(110, BUTTON_HEIGHT)
		button.BackgroundColor3 = Theme.Color.PanelRaised
		button.BorderSizePixel = 0
		button.FontFace = Theme.Fonts.BodyBold
		button.TextSize = Theme.TextSize.Body
		button.TextColor3 = Theme.Color.Text
		button.Text = ""
		button.ZIndex = 3
		button.Parent = buttons

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 6)
		buttonCorner.Parent = button

		return button
	end

	--[[
		Cancel FIRST and accept second, reading left to right.

		The destructive one is the far one from where the cursor already is:
		this is opened by a drag that ended on the right of the screen, or by a
		click, and putting "yes, destroy it" under the pointer is how a dialog
		gets dismissed without being read.
	]]
	cancelButton = newButton(1, "Cancel")
	acceptButton = newButton(2, "Accept")

	local function answer(accepted: boolean)
		Confirm.close(accepted)
	end

	dim.MouseButton1Click:Connect(function()
		answer(false)
	end)
	cancelButton.MouseButton1Click:Connect(function()
		answer(false)
	end)
	acceptButton.MouseButton1Click:Connect(function()
		answer(true)
	end)
end

--[[
	Answers whatever question is up, if any.

	Public because the caller may need to take the question away itself - a
	respawn, or the menu it was asked over closing - and because everything
	inside here funnels through it too.
]]
function Confirm.close(accepted: boolean)
	local done = pending
	if not done then
		return
	end
	pending = nil

	gui.Enabled = false
	MenuState.setOpen(MENU_NAME, false)

	Sounds.play(if accepted then "ui.click" else "ui.close")

	-- Cleared before the callback runs, so a handler that asks another question
	-- straight away is not refused by the one it is answering.
	done(accepted)
end

function Confirm.ask(options: { [string]: any }, done: (boolean) -> ())
	if type(done) ~= "function" then
		return
	end

	if pending then
		-- Already asking something. See the note at the top about why the
		-- answer to a second question is no rather than a queue.
		done(false)
		return
	end

	build()

	titleLabel.Text = tostring(options.title or "Are you sure?")

	local body = options.body
	bodyLabel.Text = if type(body) == "string" then body else ""
	bodyLabel.Visible = bodyLabel.Text ~= ""

	acceptButton.Text = tostring(options.accept or "Confirm")
	acceptButton.BackgroundColor3 = if options.tone == "bad"
		then Theme.Color.Bad
		else Theme.Color.PanelRaised

	cancelButton.Text = tostring(options.cancel or "Cancel")

	pending = done
	gui.Enabled = true

	MenuState.setOpen(MENU_NAME, true)
	Sounds.play("ui.open")
end

function Confirm.isOpen(): boolean
	return pending ~= nil
end

--[[
	A question that outlives the character that asked it has nothing left to
	confirm - and it would be holding the movement lock on the new one.

	Guarded, because this module lives in Shared and LocalPlayer is nil on the
	server. Nothing requires it there today; the guard is so that a module which
	one day does is not broken by a line it never reaches.
]]
local localPlayer = Players.LocalPlayer

if localPlayer then
	localPlayer.CharacterRemoving:Connect(function()
		Confirm.close(false)
	end)
end

return Confirm
