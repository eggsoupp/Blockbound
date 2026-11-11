--[[
	EnemyFeedback

	What a hit on an enemy looks like to everyone nearby: the name plate and
	its health bar, the hit flash, the floating damage number, and the burst of
	cubes when it dies. Built on the server so every player sees the same
	thing; EnemyService decides WHEN, this module decides how it looks.

	  EnemyFeedback.buildNamePlate(model, def, height) -> billboard, fill
	  EnemyFeedback.refreshNamePlate(entry)
	  EnemyFeedback.flashHit(entry)
	  EnemyFeedback.damageNumber(position, amount, height, killing)
	  EnemyFeedback.burst(position, color, height)
	  EnemyFeedback.dominantColor(model) -> Color3
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))

local EnemyFeedback = {}

--[[
	The floating damage number.

	`life` is short on purpose. It is a receipt, not a label - it has to be
	readable and then out of the way before the next swing lands, and Sacred
	Rain lands fifteen of them.
]]
local DAMAGE_TEXT = {
	width = 90,
	height = 28,
	size = 24,
	killSize = 28,
	rise = 3.4,
	spread = 2.2,
	life = 0.85,
	maxDistance = 110,
}

-- Name plate geometry. Offset pixels, so it stays the same size on screen at
-- any distance rather than growing as you approach.
local PLATE = {
	width = 140,
	height = 18,
	barHeight = 6,
	gap = 2,
	rise = 2.2, -- studs above the model's own top
	maxDistance = 120,
}

--[[
	The name plate: what it is called, and how much life it has left.

	A BillboardGui built here on the server rather than by each client. It is a
	handful of frames that only change when something takes a hit, so the
	replication is negligible - and building it here means it exists for anything
	that spawns an enemy, including a future spawner, with no client to keep in
	step.

	Sized in offset rather than scale so it stays legible at distance instead of
	swelling as you walk up to it, and studs-offset above the model's own height
	so it clears a tall enemy as readily as a short one.
]]
local function buildNamePlate(model, def, height)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NamePlate"
	billboard.Size = UDim2.fromOffset(PLATE.width, PLATE.height + PLATE.gap + PLATE.barHeight)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height * 0.5 + PLATE.rise, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = PLATE.maxDistance
	billboard.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.new(1, 0, 0, PLATE.height)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.BodyBold
	label.TextSize = Theme.TextSize.Small
	label.TextColor3 = Theme.Color.Text
	label.TextStrokeTransparency = 0.4
	-- displayName, not the asset name: "Blue Slime" rather than "BlueSlime".
	label.Text = def.displayName or model.Name
	label.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, 0)
	track.Size = UDim2.fromOffset(PLATE.width - 16, PLATE.barHeight)
	track.BackgroundColor3 = Theme.Color.Panel
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Stroke
	stroke.Thickness = 1
	stroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Theme.Color.Good
	fill.BorderSizePixel = 0
	fill.Parent = track

	billboard.Parent = model
	return billboard, fill
end

-- ---------------------------------------------------------------------------
-- Hit feedback
-- ---------------------------------------------------------------------------

local HIT_FLASH_SECONDS = 0.09
local HIT_FLASH_COLOR = Color3.fromRGB(255, 236, 236)

--[[
	The Highlight flash, for an enemy whose definition says `hitFlash =
	"Highlight"`.

	Tinting Color does nothing visible on a textured MeshPart - Signus is five
	of them - so such an enemy is flashed with one Highlight instead: a fill
	that fades back out over the flash. One Highlight per enemy, reused, so a
	flurry of hits never stacks instances (Roblox draws at most 31 at once).
	`hitFlashColor` on the definition picks the fill; the outline stays off so
	the flash reads as light on the body rather than a selection box.
]]
local HIGHLIGHT_FLASH_SECONDS = 0.16
local HIGHLIGHT_FILL = 0.25

local function flashHighlight(entry)
	local model = entry.model
	local highlight = entry.hitHighlight
	if not (highlight and highlight.Parent) then
		highlight = Instance.new("Highlight")
		highlight.Name = "HitFlash"
		highlight.FillColor = entry.def.hitFlashColor or HIT_FLASH_COLOR
		highlight.OutlineTransparency = 1
		highlight.FillTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = model
		entry.hitHighlight = highlight
	end

	-- Snapped to full and faded, rather than tweened both ways: the fade is
	-- what reads, and a second hit mid-fade simply snaps it back up.
	highlight.FillTransparency = HIGHLIGHT_FILL
	TweenService:Create(
		highlight,
		TweenInfo.new(HIGHLIGHT_FLASH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ FillTransparency = 1 }
	):Play()
end

--[[
	Whitens an enemy for a moment, then puts its colours back.

	The resting colours are captured on the FIRST hit and reused after that, so
	a second hit landing mid-flash restores the real colour rather than the
	flash colour. `flashUntil` means a rapid series of hits extends one flash
	instead of racing several restores against each other.
]]
local function flashHit(entry)
	local model = entry.model
	if not model.Parent then
		return
	end

	if entry.def.hitFlash == "Highlight" then
		flashHighlight(entry)
		return
	end

	if not entry.baseColors then
		local colors = {}
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				colors[part] = part.Color
			end
		end
		entry.baseColors = colors
	end

	for part in pairs(entry.baseColors) do
		if part.Parent then
			part.Color = HIT_FLASH_COLOR
		end
	end

	local until_ = os.clock() + HIT_FLASH_SECONDS
	entry.flashUntil = until_

	task.delay(HIT_FLASH_SECONDS, function()
		if entry.flashUntil ~= until_ or not model.Parent then
			return
		end

		for part, color in pairs(entry.baseColors) do
			if part.Parent then
				part.Color = color
			end
		end
	end)
end

-- The colour of the biggest part in a model: near enough "what colour is this
-- thing" for a shower of debris, without averaging anything.
local function dominantColor(model)
	local best, bestVolume = Color3.fromRGB(180, 180, 180), -1

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local size = part.Size
			local volume = size.X * size.Y * size.Z
			if volume > bestVolume then
				best, bestVolume = part.Color, volume
			end
		end
	end

	return best
end

--[[
	The number that floats off a hit.

	MADE HERE, LIKE THE FLASH AND THE BURST, for the same reason those are:
	everyone standing nearby sees the same figure come off the same hit. A
	client drawing its own would show one number to the player who swung and
	nothing to the player next to them, and two players hitting the same slime
	would each be watching a private fight.

	It is the RAW damage, not the health actually removed. Hitting a slime with
	four life left for seventy-five says seventy-five, because the question the
	number answers is "what does my weapon do", and an answer that shrinks as
	things die would be useless for exactly the comparison it exists to serve.

	One part, one label, gone in under a second. The rise is a tween on the part
	rather than on StudsOffset so the text drifts in world space and hits from
	two directions do not stack into an unreadable pile.

	The killing blow's number is a size up and in the accent colour: the one
	hit worth telling apart from the rest, without adding anything to the pile.
]]
local function damageNumber(position, amount, height, killing)
	local anchor = Instance.new("Part")
	anchor.Name = "DamageNumber"
	anchor.Size = Vector3.one * 0.2
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true

	-- Jittered sideways, so a flurry of hits reads as several numbers rather
	-- than one number flickering.
	local spread = DAMAGE_TEXT.spread
	anchor.CFrame = CFrame.new(position + Vector3.new(
		(math.random() - 0.5) * spread,
		(height or 4) * 0.5,
		(math.random() - 0.5) * spread
	))
	anchor.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(DAMAGE_TEXT.width, DAMAGE_TEXT.height)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = DAMAGE_TEXT.maxDistance
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Number
	label.TextSize = if killing then DAMAGE_TEXT.killSize else DAMAGE_TEXT.size
	label.TextColor3 = if killing then Theme.Color.Accent else Theme.Color.Text
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Text = tostring(math.max(1, math.floor(amount + 0.5)))
	label.Parent = billboard

	local rise = TweenInfo.new(DAMAGE_TEXT.life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(anchor, rise, {
		CFrame = anchor.CFrame + Vector3.new(0, DAMAGE_TEXT.rise, 0),
	}):Play()

	-- Held at full for the first part of the life and then faded, so the number
	-- is READ before it starts disappearing.
	TweenService:Create(label, TweenInfo.new(
		DAMAGE_TEXT.life * 0.45,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		0,
		false,
		DAMAGE_TEXT.life * 0.55
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	Debris:AddItem(anchor, DAMAGE_TEXT.life + 0.1)
end

--[[
	A short shower of cubes where something died.

	Blocky rather than a ParticleEmitter, matching the mining and chopping
	debris, and for the same reasons: it suits the game and needs no texture.
	Massless and non-colliding, so it cannot shove anybody around.
]]
local function burst(position, color, height)
	local spread = math.max(1, height or 4) * 0.5

	for _ = 1, 10 do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.one * (0.4 + math.random() * 0.3)
		chunk.Color = color
		chunk.Material = Enum.Material.SmoothPlastic
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.Massless = true
		chunk.CFrame = CFrame.new(position + Vector3.new(
			(math.random() - 0.5) * spread,
			(math.random() - 0.5) * spread,
			(math.random() - 0.5) * spread
		)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Parent = workspace

		-- After parenting: an unparented part has no assembly for the physics
		-- engine to apply a velocity to, so setting it first does nothing.
		chunk.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 18,
			math.random() * 12 + 4,
			(math.random() - 0.5) * 18
		)

		Debris:AddItem(chunk, 1.3)
	end
end

--[[
	Redraws one enemy's bar. Colour shifts as it drops, so how hurt something is
	is readable without reading the bar's length.
]]
local function refreshNamePlate(entry)
	local fill = entry.healthFill
	if not fill or not fill.Parent then
		return
	end

	local fraction = math.clamp(entry.health / math.max(1, entry.def.health), 0, 1)
	fill.Size = UDim2.fromScale(fraction, 1)

	fill.BackgroundColor3 = if fraction > 0.5
		then Theme.Color.Good
		else Theme.Color.Good:Lerp(Theme.Color.Bad, 1 - fraction * 2)
end

EnemyFeedback.buildNamePlate = buildNamePlate
EnemyFeedback.refreshNamePlate = refreshNamePlate
EnemyFeedback.flashHit = flashHit
EnemyFeedback.damageNumber = damageNumber
EnemyFeedback.burst = burst
EnemyFeedback.dominantColor = dominantColor

return EnemyFeedback
