--[[
	ManaClient

	The mana bar, directly above the health bar.

	Built in code rather than authored in Studio, like the health bar and the
	ability panel, so the whole widget is this one file.

	IT DRAWS THE RAMP, THE SERVER DOES NOT SEND IT

	ServerScriptService.ManaService pushes three numbers - the value, the
	maximum and the REGEN RATE - and only when something happens: a cast, a
	refused cast, a respawn. Between those, this fills the bar in itself from
	the rate it was given. So an idle player costs no network at all and the bar
	is still smooth at any frame rate, which a value streamed ten times a second
	would not be at either end of a bad connection.

	The consequence is that the number on screen is a PREDICTION, and it is
	allowed to be slightly ahead of the server's. It cannot drift, because every
	push snaps it back - including the push that answers a cast the server
	refused, which is exactly the case where a client thought it could afford
	something and could not.

	THE FLASH IS THE REFUSAL

	A cast that the server turns down for mana arrives here as a push that does
	not lower the bar. There is nothing to see in that, so the bar is told to
	flash instead: it is the only feedback the player gets that the button did
	nothing for a reason, and without it a too-expensive ability is
	indistinguishable from a broken one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local ManaChanged = Remotes.wait("ManaChanged")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

--[[
	Directly above the health bar and the same width as it, so the two read as
	one meter with two rows rather than as two widgets that happen to be near
	each other. Shorter, because mana is the lesser of the two: running out of
	it costs you a cast, running out of health costs you everything.

	The bottom-left column, top to bottom, and every one of these knows where
	the one below it ends:

	    the feedback column 270   (Shared.UI.Feedback owns it)
	    ability cooldowns 176   (AbilityClient HUD.bottom)
	    THIS              148
	    health             96   (HealthClient L.bottom)
	    hotbar                  (authored in the place file)

	Inserting this pushed the two above it up by 26. If it moves again, they
	move with it.
]]
local L = {
	width = 232,
	height = 20,
	pad = 16,
	bottom = 148,
}

-- Below this fraction the bar turns, the same way the health bar does: it is
-- the point at which the next ability is no longer a given.
local LOW_FRACTION = 0.3

-- How fast the drawn value chases the predicted one. The prediction is exact,
-- so this is only here to turn the STEP a cast makes into a slide.
local DRAIN_SPEED = 9

-- The refusal flash: how bright, and how fast it decays.
local DENIED_FLASH = 0.75
local DENIED_DECAY = 3.5

local screen = Instance.new("ScreenGui")
screen.Name = "ManaUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 5
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Mana"
root.AnchorPoint = Vector2.new(0, 1)
root.Position = UDim2.new(0, L.pad, 1, -L.bottom)
root.Size = UDim2.fromOffset(L.width, L.height)
root.BackgroundTransparency = 1
root.Parent = screen

-- The track, matched to the health bar's so the two line up exactly.
local track = Instance.new("Frame")
track.Name = "Track"
track.Size = UDim2.fromScale(1, 1)
track.BackgroundColor3 = Theme.Color.Panel
track.BackgroundTransparency = 0.15
track.BorderSizePixel = 0
track.Parent = root

local trackStroke = Instance.new("UIStroke")
trackStroke.Color = Theme.Color.Stroke
trackStroke.Thickness = 2
trackStroke.Parent = track

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Theme.Color.Mana
fill.BorderSizePixel = 0
fill.ZIndex = 2
fill.Parent = track

--[[
	The refusal flash, over the fill and across the whole track.

	Its own frame rather than a colour written onto the fill, because a fill
	that is nearly empty is nearly invisible - and the one moment this has to be
	seen is when there is not enough mana, which is exactly then.
]]
local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Theme.Color.Bad
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 3
flash.Parent = track

local amount = Instance.new("TextLabel")
amount.Name = "Amount"
amount.Size = UDim2.fromScale(1, 1)
amount.BackgroundTransparency = 1
amount.FontFace = Theme.Fonts.Number
amount.TextSize = Theme.TextSize.Small
amount.TextColor3 = Theme.Color.Text
amount.TextStrokeTransparency = 0.5
amount.Text = ""
amount.ZIndex = 4
amount.Parent = track

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--[[
	What the server last said, when it said it, and what is actually drawn.

	`predicted` is worked out from the first three every frame; `shown` chases
	it. Keeping them apart is what lets a cast slide the bar down over a few
	frames while the prediction underneath stays exact.
]]
local known = 0
local maximum = 0
local regen = 0
local knownAt = os.clock()

local shown = 0
local denied = 0

local function predict(): number
	if maximum <= 0 then
		return 0
	end
	return math.clamp(known + (os.clock() - knownAt) * regen, 0, maximum)
end

ManaChanged.OnClientEvent:Connect(function(value, max, rate)
	if type(value) ~= "number" or type(max) ~= "number" or max <= 0 then
		return
	end

	local before = predict()

	known = math.clamp(value, 0, max)
	maximum = max
	regen = if type(rate) == "number" then rate else 0
	knownAt = os.clock()

	--[[
		A push that did not lower the pool, while the bar was already too low to
		pay for much, is the server having refused a cast - there is no other
		reason it would speak up without taking anything.

		Deliberately a guess rather than a flag on the message. The alternative
		is ManaService reporting WHY it pushed, which makes the wire format
		carry a reason that only this one animation reads.
	]]
	if maximum > 0 and known >= before - 0.01 and known < maximum then
		denied = 1
	end
end)

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

RunService.Heartbeat:Connect(function(deltaTime)
	if maximum <= 0 then
		return
	end

	local godMode = Players.LocalPlayer:GetAttribute("GodMode") == true
	local target = if godMode then maximum else predict()
	if godMode then shown = maximum; denied = 0 end
	shown += (target - shown) * math.min(deltaTime * DRAIN_SPEED, 1)

	if denied > 0 then
		denied -= denied * math.min(deltaTime * DENIED_DECAY, 1)
		if denied < 0.01 then
			denied = 0
		end
	end

	local fraction = shown / maximum

	fill.Size = UDim2.fromScale(fraction, 1)
	fill.BackgroundColor3 = if fraction <= LOW_FRACTION
		then Theme.Color.ManaLow
		else Theme.Color.Mana

	flash.BackgroundTransparency = 1 - DENIED_FLASH * denied

	-- Rounded down, so a bar that says 30 can always pay for something costing
	-- 30. Rounding to nearest would let it claim mana the server does not have.
	amount.Text = if godMode then "Unlimited" else string.format("%d / %d", math.floor(shown), math.floor(maximum))
end)
