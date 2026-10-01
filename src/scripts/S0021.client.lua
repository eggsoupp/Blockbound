--[[
	BossBar

	The boss's health, across the top of the screen.

	Up whenever ServerScriptService.BossService says there is one and down when
	it says there is not. Everyone in the server sees it, including somebody who
	joined halfway through - see the note there about why it is not limited to
	whoever is swinging.

	WHY IT IS NOT THE HEALTH BAR AGAIN

	The player's own bar is in the corner, small and always there, and it is
	read in peripheral vision. This is the opposite: it is the thing the fight
	is ABOUT, it is only up during one, and it wants to be looked at directly.
	So it goes where a player's eyes already are - across the top, under the
	name - rather than becoming a third row in the bottom-left column.

	IT IS BUILT OUT OF FOUR LAYERS, AND EACH ANSWERS A DIFFERENT QUESTION

	  the FILL     how much is left. Chases the real value quickly, so a swing
	               feels connected to the bar.
	  the GHOST    what the last few seconds did. Catches up slowly, so the gap
	               between it and the fill is the size of the damage - which on
	               a boss with two thousand health is the only way to see that a
	               swing did anything at all.
	  the EDGE     a bright line at the head of the fill, so the eye has
	               something to track. A long bar with a flat end reads as a
	               static rectangle.
	  the PHASES   where the fight changes, marked before it happens.

	And under it, the name of whatever he is DOING. That is the part that makes
	the moves learnable: a player who reads "BODY COLLAPSE" the first three
	times knows what the rear-up means the fourth.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local BossState = Remotes.wait("BossState")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local L = {
	width = 660,
	height = 26,
	top = 58,
	nameHeight = 30,
	moveHeight = 18,
	gap = 6,
}

-- How fast the fill and its ghost chase the real value. The fill is quick
-- enough to feel connected to the swing; the ghost is slow enough that the gap
-- between them IS the hit.
local FILL_SPEED = 12
local GHOST_SPEED = 2.2

local FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- How long the bar stays after the kill. The bar hitting zero is the payoff
-- for a two minute fight, and taking it away on the same frame he dies means
-- nobody ever sees it land there.
local LINGER = 1.4

local screen = Instance.new("ScreenGui")
screen.Name = "BossUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true

-- Above the world HUD, below the settings menu and any confirmation.
screen.DisplayOrder = 8
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Enabled = false
screen.Parent = playerGui

--[[
	A CanvasGroup, so the whole thing fades in and out on ONE property.

	The alternative is tweening a name, a bar, a ghost, an edge, two phase marks
	and two labels, and keeping them in step. Here the entrance is one tween and
	nothing inside it has to know the bar is arriving.
]]
local root = Instance.new("CanvasGroup")
root.Name = "Boss"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0, L.top)
root.Size = UDim2.fromOffset(
	L.width, L.nameHeight + L.gap + L.height + L.gap + L.moveHeight
)
root.BackgroundTransparency = 1
root.GroupTransparency = 1
root.Parent = screen

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, L.nameHeight)
title.BackgroundTransparency = 1
title.FontFace = Theme.Fonts.Heading
title.TextSize = Theme.TextSize.Heading
title.TextColor3 = Theme.Color.Text
title.TextStrokeTransparency = 0.35
title.Text = ""
title.Parent = root

local track = Instance.new("Frame")
track.Name = "Track"
track.Position = UDim2.fromOffset(0, L.nameHeight + L.gap)
track.Size = UDim2.fromOffset(L.width, L.height)
track.BackgroundColor3 = Theme.Color.Backdrop
track.BackgroundTransparency = 0.25
track.BorderSizePixel = 0
track.ClipsDescendants = true
track.Parent = root

local trackStroke = Instance.new("UIStroke")
trackStroke.Color = Theme.Color.Stroke
trackStroke.Thickness = 2
trackStroke.Parent = track

local ghost = Instance.new("Frame")
ghost.Name = "Ghost"
ghost.Size = UDim2.fromScale(1, 1)
ghost.BackgroundColor3 = Theme.Color.Text
ghost.BackgroundTransparency = 0.7
ghost.BorderSizePixel = 0
ghost.ZIndex = 2
ghost.Parent = track

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Theme.Color.Bad
fill.BorderSizePixel = 0
fill.ZIndex = 3
fill.Parent = track

-- Darker at the bottom, so the bar has a body rather than being a flat block
-- of colour. The same trick the inventory's slot art uses.
local fillShade = Instance.new("UIGradient")
fillShade.Rotation = 90
fillShade.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)),
})
fillShade.Parent = fill

--[[
	The bright edge at the head of the fill.

	Anchored to the fill's right edge rather than positioned by fraction, so it
	tracks whatever the fill is doing without a second calculation that could
	disagree with it.
]]
local edge = Instance.new("Frame")
edge.Name = "Edge"
edge.AnchorPoint = Vector2.new(1, 0)
edge.Position = UDim2.fromScale(1, 0)
edge.Size = UDim2.new(0, 3, 1, 0)
edge.BackgroundColor3 = Theme.Color.Text
edge.BorderSizePixel = 0
edge.ZIndex = 4
edge.Parent = fill

--[[
	The phase markers.

	Thin lines at the health fractions the fight changes at, so a player can see
	the next change coming rather than being surprised by it. They are the same
	numbers the behaviour module splits its deck on; if those move, these move.
]]
local PHASE_MARKS = { 0.65, 0.3 }

for _, fraction in ipairs(PHASE_MARKS) do
	local mark = Instance.new("Frame")
	mark.Name = "Phase"
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Position = UDim2.fromScale(fraction, 0)
	mark.Size = UDim2.new(0, 2, 1, 0)
	mark.BackgroundColor3 = Theme.Color.Backdrop
	mark.BackgroundTransparency = 0.2
	mark.BorderSizePixel = 0
	mark.ZIndex = 5
	mark.Parent = track
end

local amount = Instance.new("TextLabel")
amount.Name = "Amount"
amount.Size = UDim2.fromScale(1, 1)
amount.BackgroundTransparency = 1
amount.FontFace = Theme.Fonts.Number
amount.TextSize = Theme.TextSize.Small
amount.TextColor3 = Theme.Color.Text
amount.TextStrokeTransparency = 0.5
amount.Text = ""
amount.ZIndex = 6
amount.Parent = track

--[[
	What he is doing, right now, named.

	Blank between attacks, which is most of the time. A label that held the last
	move's name during the gaps would be reporting the past as if it were the
	present, and the gaps are exactly when a player is deciding what to do next.
]]
local move = Instance.new("TextLabel")
move.Name = "Move"
move.Position = UDim2.fromOffset(0, L.nameHeight + L.gap + L.height + L.gap)
move.Size = UDim2.new(1, 0, 0, L.moveHeight)
move.BackgroundTransparency = 1
move.FontFace = Theme.Fonts.BodyBold
move.TextSize = Theme.TextSize.Small
move.TextColor3 = Theme.Color.Accent
move.TextStrokeTransparency = 0.4
move.Text = ""
move.Parent = root

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local shownFraction = 1
local ghostFraction = 1

local health = 0
local maxHealth = 0
local visible = false
local fade = nil

local function setVisible(next: boolean)
	if next == visible then
		return
	end
	visible = next

	if fade then
		fade:Cancel()
	end

	if next then
		screen.Enabled = true
		fade = TweenService:Create(root, FADE, { GroupTransparency = 0 })
		fade:Play()
		return
	end

	task.delay(LINGER, function()
		if visible then
			return
		end

		fade = TweenService:Create(root, FADE, { GroupTransparency = 1 })
		fade.Completed:Connect(function(state)
			if not visible and state == Enum.PlaybackState.Completed then
				screen.Enabled = false
			end
		end)
		fade:Play()
	end)
end

BossState.OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then
		setVisible(false)
		return
	end

	health = math.max(0, tonumber(state.health) or 0)
	maxHealth = math.max(1, tonumber(state.maxHealth) or 1)

	title.Text = string.upper(tostring(state.name or ""))
	move.Text = if type(state.phase) == "string" then string.upper(state.phase) else ""

	if not visible then
		-- A fresh fight starts where he actually is rather than sweeping up
		-- from wherever the last one ended.
		shownFraction = health / maxHealth
		ghostFraction = shownFraction
	end

	setVisible(true)
end)

RunService.Heartbeat:Connect(function(deltaTime)
	if not screen.Enabled then
		return
	end

	local target = if maxHealth > 0 then health / maxHealth else 0

	shownFraction += (target - shownFraction) * math.min(deltaTime * FILL_SPEED, 1)

	-- The ghost only ever catches DOWN. Healing pushes the fill up past it, and
	-- a ghost that trailed upward would read as damage - which matters here,
	-- because this boss really does heal when he reabsorbs a slime.
	if ghostFraction > shownFraction then
		ghostFraction += (shownFraction - ghostFraction) * math.min(deltaTime * GHOST_SPEED, 1)
	else
		ghostFraction = shownFraction
	end

	fill.Size = UDim2.fromScale(math.max(0, shownFraction), 1)
	ghost.Size = UDim2.fromScale(math.max(0, ghostFraction), 1)

	-- Hidden at the very ends, where a bright line on the edge of the track
	-- reads as part of the border rather than as the head of the bar.
	edge.Visible = shownFraction > 0.005 and shownFraction < 0.995

	amount.Text = string.format("%d / %d", math.floor(health + 0.5), math.floor(maxHealth))
end)
