--[[
	HealthClient

	The health bar, and the defense readout beside it.

	Roblox's own health GUI is switched off in Initialisation, so this is the
	only thing telling a player they are being hurt. It is drawn from
	Shared.UI.Theme, so it reads as part of the same interface as the inventory
	and the crafting window rather than as a widget bolted onto them.

	IT DISPLAYS, IT DOES NOT DECIDE

	Everything here is presentation. CombatService works out what a hit costs,
	applies it, and sends the result; this draws that result. It never computes
	damage, never reads armour, and could not lie about either if it wanted to -
	which is the point, because a client that owns its own health owns its own
	immortality.

	The Humanoid is still listened to as well as the remote. Health can change
	from things that are not combat - a heal, a respawn, anything future - and
	a bar that only updates when something hurts you is a bar that is wrong the
	rest of the time.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local CombatStats = Remotes.wait("CombatStats", 30)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local L = {
	width = 232,
	height = 26,
	pad = 16,
	bottom = 96, -- clear of the hotbar
	labelHeight = 16,
}

-- Below this fraction the bar turns; it is the point where the player should
-- stop mining and start paying attention.
local LOW_FRACTION = 0.3

local screen = Instance.new("ScreenGui")
screen.Name = "HealthUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 5
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Health"
root.AnchorPoint = Vector2.new(0, 1)
root.Position = UDim2.new(0, L.pad, 1, -L.bottom)
root.Size = UDim2.fromOffset(L.width, L.height + L.labelHeight + 4)
root.BackgroundTransparency = 1
root.Parent = screen

-- The track. Dark, so an almost-empty bar still reads as a bar rather than as
-- nothing at all.
local track = Instance.new("Frame")
track.Name = "Track"
track.Position = UDim2.fromOffset(0, L.labelHeight + 4)
track.Size = UDim2.fromOffset(L.width, L.height)
track.BackgroundColor3 = Theme.Color.Panel
track.BackgroundTransparency = 0.15
track.BorderSizePixel = 0
track.Parent = root

local trackStroke = Instance.new("UIStroke")
trackStroke.Color = Theme.Color.Stroke
trackStroke.Thickness = 2
trackStroke.Parent = track

--[[
	The trailing bar.

	Sits behind the fill and catches up slowly, so a hit leaves a pale streak
	showing how much was just lost. It is the cheapest way to make damage
	legible: the size of the gap IS the size of the hit, with no numbers to
	read.
]]
local ghost = Instance.new("Frame")
ghost.Name = "Ghost"
ghost.Size = UDim2.fromScale(1, 1)
ghost.BackgroundColor3 = Theme.Color.Bad
ghost.BackgroundTransparency = 0.55
ghost.BorderSizePixel = 0
ghost.ZIndex = 2
ghost.Parent = track

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Theme.Color.Good
fill.BorderSizePixel = 0
fill.ZIndex = 3
fill.Parent = track

local amount = Instance.new("TextLabel")
amount.Name = "Amount"
amount.BackgroundTransparency = 1
amount.Size = UDim2.fromScale(1, 1)
amount.FontFace = Theme.Fonts.Number
amount.TextSize = Theme.TextSize.Body
amount.TextColor3 = Theme.Color.Text
amount.TextStrokeTransparency = 0.5
amount.Text = ""
amount.ZIndex = 4
amount.Parent = track

local caption = Instance.new("TextLabel")
caption.Name = "Caption"
caption.BackgroundTransparency = 1
caption.Size = UDim2.fromOffset(L.width, L.labelHeight)
caption.FontFace = Theme.Fonts.Body
caption.TextSize = Theme.TextSize.Small
caption.TextColor3 = Theme.Color.TextDim
caption.TextXAlignment = Enum.TextXAlignment.Left
caption.Text = "HEALTH"
caption.Parent = root

-- Defense, right-aligned on the same line as the caption. Quiet by default,
-- because it only matters when it is not zero.
local defenceLabel = Instance.new("TextLabel")
defenceLabel.Name = "Defence"
defenceLabel.BackgroundTransparency = 1
defenceLabel.Size = UDim2.fromOffset(L.width, L.labelHeight)
defenceLabel.FontFace = Theme.Fonts.Body
defenceLabel.TextSize = Theme.TextSize.Small
defenceLabel.TextColor3 = Theme.Color.TextFaint
defenceLabel.TextXAlignment = Enum.TextXAlignment.Right
defenceLabel.Text = ""
defenceLabel.Parent = root

-- ---------------------------------------------------------------------------
-- Hit feedback
-- ---------------------------------------------------------------------------

--[[
	A red vignette around the edge of the screen, and the number that caused it.

	Built from four gradient strips rather than one full-screen wash. A wash
	over the middle of the screen covers the thing the player is trying to look
	at at the exact moment they most need to look at it; darkening only the
	edges reads as being hurt without taking the game away.

	Four Frames with linear gradients also means no image asset, which matters
	because an asset that fails to load leaves no feedback at all.
]]
local vignette = Instance.new("Frame")
vignette.Name = "HitVignette"
vignette.BackgroundTransparency = 1
vignette.Size = UDim2.fromScale(1, 1)
vignette.ZIndex = 0
vignette.Parent = screen

local EDGE = 0.22 -- fraction of the screen each strip covers

local function makeEdge(size, position, rotation)
	local strip = Instance.new("Frame")
	strip.BackgroundColor3 = Theme.Color.Bad
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Size = size
	strip.Position = position
	strip.Parent = vignette

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	-- Opaque at the screen edge, gone by the inner edge of the strip.
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = strip

	return strip
end

local edges = {
	makeEdge(UDim2.fromScale(1, EDGE), UDim2.fromScale(0, 0), 90),
	makeEdge(UDim2.fromScale(1, EDGE), UDim2.fromScale(0, 1 - EDGE), 270),
	makeEdge(UDim2.fromScale(EDGE, 1), UDim2.fromScale(0, 0), 180),
	makeEdge(UDim2.fromScale(EDGE, 1), UDim2.fromScale(1 - EDGE, 0), 0),
}

--[[
	The number that was just taken, thrown up beside the bar.

	Deliberately not centred on the screen: the damage number and the bar it
	came out of belong together, and a number in the middle of the view is one
	more thing covering the world.
]]
local function popDamageNumber(damage)
	local label = Instance.new("TextLabel")
	label.Name = "Damage"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, L.pad + L.width + 10, 1, -L.bottom)
	label.Size = UDim2.fromOffset(80, 24)
	label.FontFace = Theme.Fonts.Number
	label.TextSize = Theme.TextSize.Heading
	label.TextColor3 = Theme.Color.Bad
	label.TextStrokeTransparency = 0.4
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = string.format("-%d", damage)
	label.Parent = screen

	local rise = TweenService:Create(
		label,
		TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.new(0, L.pad + L.width + 10, 1, -L.bottom - 34),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)

	rise.Completed:Connect(function()
		label:Destroy()
	end)
	rise:Play()
end

--[[
	Flashes the vignette, harder for a harder hit.

	Scaled against a full quarter of the player's health so that a slime's bump
	and a slime's lunge do not look the same. A hit that takes a quarter of you
	should be alarming; one that takes two points should be a flicker.
]]
local function flashDamage(damage, maxHealth)
	local severity = math.clamp(damage / math.max(1, (maxHealth or 100) * 0.25), 0.15, 1)
	local peak = 1 - severity * 0.55

	for _, strip in ipairs(edges) do
		strip.BackgroundTransparency = peak
		TweenService:Create(
			strip,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end

	popDamageNumber(damage)
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local currentFraction = 1
local ghostTween = nil

local function setDefence(defense, reduction)
	if not defense or defense <= 0 then
		defenceLabel.Text = ""
		return
	end

	defenceLabel.Text = string.format("DEF %d  -%d%%", defense, math.floor((reduction or 0) * 100 + 0.5))
end

local function render(health, maxHealth, hit)
	maxHealth = math.max(1, maxHealth or 1)
	health = math.clamp(health or 0, 0, maxHealth)

	local fraction = health / maxHealth
	local dropped = fraction < currentFraction
	currentFraction = fraction

	amount.Text = string.format("%d / %d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))

	fill.BackgroundColor3 = if fraction <= LOW_FRACTION then Theme.Color.Bad else Theme.Color.Good

	TweenService:Create(fill, Theme.Tween.Hover, {
		Size = UDim2.fromScale(fraction, 1),
	}):Play()

	if ghostTween then
		ghostTween:Cancel()
		ghostTween = nil
	end

	if dropped then
		-- Hold the streak for a beat before it closes, so a hit registers even
		-- if the player was looking somewhere else at the time.
		ghostTween = TweenService:Create(
			ghost,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.15),
			{ Size = UDim2.fromScale(fraction, 1) }
		)
		ghostTween:Play()
	else
		-- Healing: the streak has nothing to show, so it keeps up with the fill.
		ghost.Size = UDim2.fromScale(fraction, 1)
	end

	if hit and hit > 0 then
		-- A flash on the frame rather than on the bar, so it reads at the edge
		-- of vision without hiding the number.
		trackStroke.Color = Theme.Color.Bad
		TweenService:Create(trackStroke, Theme.Tween.Fade, {
			Color = Theme.Color.Stroke,
		}):Play()
	end
end

-- ---------------------------------------------------------------------------
-- Sources
-- ---------------------------------------------------------------------------

if CombatStats then
	CombatStats.OnClientEvent:Connect(function(stats)
		if type(stats) ~= "table" then
			return
		end

		setDefence(stats.defense, stats.reduction)
		render(stats.health, stats.maxHealth, stats.hit)

		-- `hit` is present only on a message caused by damage, which is what
		-- separates "you were hurt" from "here are your numbers again".
		if stats.hit and stats.hit > 0 then
			flashDamage(stats.hit, stats.maxHealth)
		end
	end)
else
	warn("[HealthClient] no CombatStats remote; the defence readout will stay empty.")
end

--[[
	Also bound straight to the Humanoid.

	The remote covers combat, but health moves for other reasons - respawning
	most obviously - and those must not leave a stale bar on screen.
]]
local function bindCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	currentFraction = 1
	ghost.Size = UDim2.fromScale(1, 1)
	render(humanoid.Health, humanoid.MaxHealth, nil)

	humanoid.HealthChanged:Connect(function(health)
		render(health, humanoid.MaxHealth, nil)
	end)

	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		render(humanoid.Health, humanoid.MaxHealth, nil)
	end)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end
