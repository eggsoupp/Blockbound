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

	IT IS DRAWN FROM THE PIXEL-ART KIT

	Shared.UI.PixelUI: his name on the red banner, the bar in a wooden frame
	with gold caps and a skull on its end, gold-tipped phase markers, and the
	move named on one of the kit's dark pills.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local PixelUI = require(Shared.UI:WaitForChild("PixelUI"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local BossState = Remotes.wait("BossState")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local P = Theme.PixelColor

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

--[[
	640 wide rather than wider: the hotbar shares this band at the top left, and
	any wider and the skull on the bar's end runs into its last slot.

	The name banner sits on the frame's top rim, overlapping it by 6px, and the
	move's pill hangs under the frame.
]]
local L = {
	width = 640,
	top = 58,
	frameTop = 36,
	-- The frame's art with an 8-texel groove, at 3px a texel.
	frameHeight = 48,
	moveGap = 6,
	-- The skull hangs this far past the frame's left end, and the CanvasGroup
	-- that fades everything is that much wider each side so it is not clipped.
	side = 16,
	-- The fill starts this much further in than the groove, clear of the skull.
	skullClear = 12,
}

local MOVE_HEIGHT = PixelUI.get("badge").size.Y * PixelUI.Scale
local MARKER_WIDTH = PixelUI.get("bar_marker").size.X * PixelUI.Scale

-- How fast the fill and its ghost chase the real value. The fill is quick
-- enough to feel connected to the swing; the ghost is slow enough that the gap
-- between them IS the hit.
local FILL_SPEED = 12
local GHOST_SPEED = 2.2

local GHOST_TRANSPARENCY = 0.3

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

	A CanvasGroup clips what it draws to its own box, which is why it is wider
	than the frame by L.side: the skull hangs off the frame's end.
]]
local root = Instance.new("CanvasGroup")
root.Name = "Boss"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0, L.top)
root.Size = UDim2.fromOffset(
	L.width + L.side * 2, L.frameTop + L.frameHeight + L.moveGap + MOVE_HEIGHT
)
root.BackgroundTransparency = 1
root.GroupTransparency = 1
root.Parent = screen

local banner, title = PixelUI.header(root, "", "header_red")
banner.Name = "Title"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.fromScale(0.5, 0)
banner.ZIndex = 6
-- Cream on the red banner, outlined so it reads at a glance.
title.TextColor3 = P.OnWood
title.TextStrokeColor3 = P.Outline
title.TextStrokeTransparency = 0

local track = PixelUI.image(root, "boss_frame")
track.Name = "Track"
track.Position = UDim2.fromOffset(L.side, L.frameTop)
track.Size = UDim2.fromOffset(L.width, L.frameHeight)

local skull = PixelUI.image(root, "icon_skull")
skull.Name = "Emblem"
skull.AnchorPoint = Vector2.new(0, 0.5)
skull.Position = UDim2.fromOffset(L.side - 15, L.frameTop + L.frameHeight / 2)
skull.ZIndex = 6

-- The fill runs in the frame's groove, and is clipped to it.
local grooveLeft, grooveTop, grooveRight, grooveBottom = PixelUI.groove("boss_frame")
local fillLeft = L.side + grooveLeft + L.skullClear
local fillWidth = L.width - grooveLeft - L.skullClear - grooveRight

local groove = Instance.new("Frame")
groove.Name = "Groove"
groove.BackgroundTransparency = 1
groove.ClipsDescendants = true
groove.Position = UDim2.fromOffset(fillLeft, L.frameTop + grooveTop)
groove.Size = UDim2.fromOffset(fillWidth, L.frameHeight - grooveTop - grooveBottom)
groove.ZIndex = 2
groove.Parent = root

local ghost = PixelUI.image(groove, "bar_fill")
ghost.Name = "Ghost"
ghost.Size = UDim2.fromScale(1, 1)
ghost.ImageColor3 = P.BarGhost
ghost.ImageTransparency = GHOST_TRANSPARENCY
ghost.ZIndex = 1

local fill = PixelUI.image(groove, "bar_fill")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.ImageColor3 = P.BossFill
fill.ZIndex = 2

--[[
	The bright edge at the head of the fill.

	Anchored to the fill's right edge rather than positioned by fraction, so it
	tracks whatever the fill is doing without a second calculation that could
	disagree with it. One texel wide, so it is a line of the art and not a
	smoother thing laid over it.
]]
local edge = Instance.new("Frame")
edge.Name = "Edge"
edge.AnchorPoint = Vector2.new(1, 0)
edge.Position = UDim2.fromScale(1, 0)
edge.Size = UDim2.new(0, PixelUI.Scale, 1, 0)
edge.BackgroundColor3 = Color3.fromRGB(255, 246, 224)
edge.BorderSizePixel = 0
edge.ZIndex = 4
edge.Parent = fill

--[[
	The phase markers.

	Gold-tipped lines across the bar at the health fractions the fight changes
	at, so a player can see the next change coming rather than being surprised
	by it. They are the same numbers the behaviour module splits its deck on; if
	those move, these move.
]]
local PHASE_MARKS = { 0.65, 0.3 }

for _, fraction in ipairs(PHASE_MARKS) do
	local mark = PixelUI.image(root, "bar_marker")
	mark.Name = "Phase"
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Position = UDim2.fromOffset(fillLeft + fraction * fillWidth, L.frameTop)
	mark.Size = UDim2.fromOffset(MARKER_WIDTH, L.frameHeight)
	mark.ZIndex = 5
end

local amount = Instance.new("TextLabel")
amount.Name = "Amount"
amount.Position = groove.Position
amount.Size = groove.Size
amount.BackgroundTransparency = 1
amount.FontFace = Theme.Fonts.Number
amount.TextSize = Theme.TextSize.Small
amount.TextColor3 = P.OnWood
amount.TextStrokeColor3 = P.Outline
amount.TextStrokeTransparency = 0
amount.Text = ""
amount.ZIndex = 6
amount.Parent = root

--[[
	What he is doing, right now, named, on a dark pill under the bar.

	Blank between attacks, which is most of the time, and the pill goes with
	it. A label that held the last move's name during the gaps would be
	reporting the past as if it were the present, and the gaps are exactly when
	a player is deciding what to do next.
]]
local movePill = PixelUI.image(root, "badge")
movePill.Name = "MovePill"
movePill.AnchorPoint = Vector2.new(0.5, 0)
movePill.Position = UDim2.new(0.5, 0, 0, L.frameTop + L.frameHeight + L.moveGap)
movePill.Size = UDim2.fromOffset(0, MOVE_HEIGHT)
movePill.AutomaticSize = Enum.AutomaticSize.X
movePill.Visible = false

local movePadding = Instance.new("UIPadding")
movePadding.PaddingLeft = UDim.new(0, 14)
movePadding.PaddingRight = UDim.new(0, 14)
movePadding.Parent = movePill

local move = Instance.new("TextLabel")
move.Name = "Move"
move.Size = UDim2.fromScale(0, 1)
move.AutomaticSize = Enum.AutomaticSize.X
move.BackgroundTransparency = 1
move.FontFace = Theme.Fonts.BodyBold
move.TextSize = Theme.TextSize.Small
move.TextColor3 = P.Selection
move.Text = ""
move.Parent = movePill

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
	movePill.Visible = move.Text ~= ""

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

	-- Hidden at the very ends, where a bright line on the edge of the groove
	-- reads as part of the border rather than as the head of the bar.
	edge.Visible = shownFraction > 0.005 and shownFraction < 0.995

	amount.Text = string.format("%d / %d", math.floor(health + 0.5), math.floor(maxHealth))
end)
