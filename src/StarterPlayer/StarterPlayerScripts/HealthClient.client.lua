--[[
	HealthClient

	The health bar, and the defense readout beside it.

	Roblox's own health GUI is switched off in Initialisation, so this is the
	only thing telling a player they are being hurt. It is drawn from the
	pixel-art kit (Shared.UI.PixelUI) - a wooden bar with a heart on its end -
	so it reads as part of the same interface as the inventory and the crafting
	window rather than as a widget bolted onto them.

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
local PixelUI = require(Shared.UI:WaitForChild("PixelUI"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local CombatStats = Remotes.wait("CombatStats", 30)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local P = Theme.PixelColor

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local L = {
	width = 260,
	-- The frame's art: a 6-texel groove in a 13-texel bar, at 3px a texel.
	height = 39,
	pad = 16,
	-- The bottom of the HUD column; ManaClient stacks on top of this. Low, so
	-- the ability rows above the mana bar have room to be seen.
	bottom = 40,
	-- The frame starts this far in, so the heart can sit over its left end, and
	-- the fill starts this much further in again, clear of the heart.
	iconInset = 15,
	iconClear = 10,
	-- Between the bar and the defense readout beside it.
	defenceGap = 8,
}

-- Below this fraction the bar turns; it is the point where the player should
-- stop mining and start paying attention.
local LOW_FRACTION = 0.3

-- How see-through the streak a hit leaves behind the fill is.
local GHOST_TRANSPARENCY = 0.3

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
root.Size = UDim2.fromOffset(L.width, L.height)
root.BackgroundTransparency = 1
root.Parent = screen

local heart = PixelUI.image(root, "icon_heart")
heart.Name = "Icon"
heart.AnchorPoint = Vector2.new(0, 0.5)
heart.Position = UDim2.fromScale(0, 0.5)
heart.ZIndex = 5

-- The wooden bar. Its groove is dark, so an almost-empty bar still reads as a
-- bar rather than as nothing at all.
local track = PixelUI.image(root, "bar_frame")
track.Name = "Track"
track.Position = UDim2.fromOffset(L.iconInset, 0)
track.Size = UDim2.new(1, -L.iconInset, 1, 0)

-- The fill runs in the groove, and is clipped to it.
local grooveLeft, grooveTop, grooveRight, grooveBottom = PixelUI.groove("bar_frame")
local fillLeft = L.iconInset + grooveLeft + L.iconClear

local groove = Instance.new("Frame")
groove.Name = "Groove"
groove.BackgroundTransparency = 1
groove.ClipsDescendants = true
groove.Position = UDim2.fromOffset(fillLeft, grooveTop)
groove.Size = UDim2.new(1, -(fillLeft + grooveRight), 1, -(grooveTop + grooveBottom))
groove.ZIndex = 2
groove.Parent = root

--[[
	The trailing bar.

	Sits behind the fill and catches up slowly, so a hit leaves a pale streak
	showing how much was just lost. It is the cheapest way to make damage
	legible: the size of the gap IS the size of the hit, with no numbers to
	read.
]]
local ghost = PixelUI.image(groove, "bar_fill")
ghost.Name = "Ghost"
ghost.Size = UDim2.fromScale(1, 1)
ghost.ImageColor3 = P.BarGhost
ghost.ImageTransparency = GHOST_TRANSPARENCY
ghost.ZIndex = 1

local fill = PixelUI.image(groove, "bar_fill")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.ImageColor3 = P.HealthFill
fill.ZIndex = 2

local amount = Instance.new("TextLabel")
amount.Name = "Amount"
amount.BackgroundTransparency = 1
amount.Position = groove.Position
amount.Size = groove.Size
amount.FontFace = Theme.Fonts.Number
amount.TextSize = Theme.TextSize.Body
amount.TextColor3 = P.OnWood
amount.TextStrokeColor3 = P.Outline
amount.TextStrokeTransparency = 0
amount.Text = ""
amount.ZIndex = 4
amount.Parent = root

--[[
	Defense, beside the bar: a shield on the end of one of the kit's dark pills.
	Hidden while it is zero, because it only matters when it is not.
]]
local defence = Instance.new("Frame")
defence.Name = "Defence"
defence.BackgroundTransparency = 1
defence.AnchorPoint = Vector2.new(0, 0.5)
defence.Position = UDim2.new(0, L.pad + L.width + L.defenceGap, 1, -(L.bottom + L.height / 2))
defence.Size = PixelUI.size("icon_shield")
defence.Visible = false
defence.Parent = screen

local shield = PixelUI.image(defence, "icon_shield")
shield.Name = "Icon"
shield.ZIndex = 2

local pill = PixelUI.image(defence, "badge")
pill.Name = "Pill"
pill.AnchorPoint = Vector2.new(0, 0.5)
-- Tucked under the shield's right edge, like the heart over the bar.
pill.Position = UDim2.new(0, shield.Size.X.Offset - 12, 0.5, 0)
pill.Size = UDim2.fromOffset(0, PixelUI.get("badge").size.Y * PixelUI.Scale)
pill.AutomaticSize = Enum.AutomaticSize.X

local pillPadding = Instance.new("UIPadding")
pillPadding.PaddingLeft = UDim.new(0, 18)
pillPadding.PaddingRight = UDim.new(0, 12)
pillPadding.Parent = pill

local defenceLabel = Instance.new("TextLabel")
defenceLabel.Name = "Label"
defenceLabel.BackgroundTransparency = 1
defenceLabel.Size = UDim2.fromScale(0, 1)
defenceLabel.AutomaticSize = Enum.AutomaticSize.X
defenceLabel.FontFace = Theme.Fonts.Number
defenceLabel.TextSize = Theme.TextSize.Small
defenceLabel.TextColor3 = P.OnWood
defenceLabel.Text = ""
defenceLabel.Parent = pill

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

local DAMAGE_HEIGHT = 24
local DAMAGE_RISE = 34

--[[
	The number that was just taken, thrown up beside the bar - past the defense
	readout when that is showing.

	Deliberately not centred on the screen: the damage number and the bar it
	came out of belong together, and a number in the middle of the view is one
	more thing covering the world.
]]
local function popDamageNumber(damage)
	local x = L.pad + L.width + 10
	if defence.Visible then
		x = pill.AbsolutePosition.X + pill.AbsoluteSize.X - screen.AbsolutePosition.X + 10
	end
	local bottom = L.bottom + (L.height - DAMAGE_HEIGHT) / 2

	local label = Instance.new("TextLabel")
	label.Name = "Damage"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, x, 1, -bottom)
	label.Size = UDim2.fromOffset(80, DAMAGE_HEIGHT)
	label.FontFace = Theme.Fonts.Number
	label.TextSize = Theme.TextSize.Heading
	label.TextColor3 = P.HealthLow
	label.TextStrokeColor3 = P.Outline
	label.TextStrokeTransparency = 0
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = string.format("-%d", damage)
	label.Parent = screen

	local rise = TweenService:Create(
		label,
		TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.new(0, x, 1, -bottom - DAMAGE_RISE),
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
		defence.Visible = false
		defenceLabel.Text = ""
		return
	end

	defenceLabel.Text = string.format("DEF %d  -%d%%", defense, math.floor((reduction or 0) * 100 + 0.5))
	defence.Visible = true
end

local function render(health, maxHealth, hit)
	maxHealth = math.max(1, maxHealth or 1)
	health = math.clamp(health or 0, 0, maxHealth)

	local fraction = health / maxHealth
	local dropped = fraction < currentFraction
	currentFraction = fraction

	amount.Text = string.format("%d / %d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))

	fill.ImageColor3 = if fraction <= LOW_FRACTION then P.HealthLow else P.HealthFill

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
		-- The wooden frame flushes red and fades back, so the hit reads at the
		-- edge of vision without hiding the number.
		track.ImageColor3 = P.HitFlash
		TweenService:Create(track, Theme.Tween.Fade, {
			ImageColor3 = Color3.new(1, 1, 1),
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
