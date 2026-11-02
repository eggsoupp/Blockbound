--[[
	IslandRecallClient

	The island button in the top bar, the countdown while it channels, and the
	teleport aura - on everyone who is channelling, not only on this player.

	THE BUTTON

	A hotbar tile left of the settings gear, at the right of the top bar, with a
	pixel house-on-an-island in it, and a line on what it does on hover: always
	on screen, on a computer and on a phone, and never inside a menu. From
	your own island it takes you back to the world instead, and says so.
	Pressing it again while it channels cancels.

	THE SERVER DECIDES

	Pressing asks IslandRecall to start; the countdown here is drawn from what
	the server answers, and a hit, dying or the server refusing all come back
	as a message rather than being guessed at. See IslandRecall.

	THE AURA

	ReplicatedStorage.RecallAura is a complete aura from the SoulShroud pack,
	authored on an R6 dummy. Its effects are lifted off the dummy onto the
	matching body parts of whoever is channelling (R6 or R15), and anything it
	keeps in its own holder parts is welded at the same offset from the root.
	It is drawn for every character carrying RecallUntil, so other players see
	someone leaving.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelUI = require(UI:WaitForChild("PixelUI"))
local TopbarButtons = require(UI:WaitForChild("TopbarButtons"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local Recall = Remotes.wait("IslandRecall")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local P = Theme.PixelColor

-- The hotbar marker's ring round the tile, as on the settings gear.
local RING_OUTSET = 3

-- A house on a floating island - home - a texel to a character.
local ISLAND_SPRITE = {
	".....##.....",
	"....####....",
	"...######...",
	"..########..",
	"...#....#...",
	"...#.##.#...",
	".##########.",
	"############",
	".##########.",
	"...######...",
	".....##.....",
}

-- A globe - the main world - shown when the button leads there instead.
local WORLD_SPRITE = {
	"....####....",
	"..##.##.##..",
	".#..#..#..#.",
	".#..#..#..#.",
	"############",
	"#...#..#...#",
	"#...#..#...#",
	"############",
	".#..#..#..#.",
	".#..#..#..#.",
	"..##.##.##..",
	"....####....",
}
local ICON_SCALE = 0.62

-- ---------------------------------------------------------------------------
-- The button
-- ---------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "IslandRecall"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
-- With the settings gear: chrome, over the game's own HUD.
screen.DisplayOrder = 20
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local button = Instance.new("ImageButton")
button.Name = "Island"
button.AutoButtonColor = false
button.AnchorPoint = Vector2.new(0, 0.5)
button.BackgroundTransparency = 1
button.Parent = screen

local face = Instance.new("Frame")
face.Name = "Content"
face.BackgroundTransparency = 1
face.Size = UDim2.fromScale(1, 1)
face.Parent = button

PixelUI.bindButton(button, { idle = "slot", hover = "slot", pressed = "slot_dark", text = P.Ink }, face)

local ring = PixelUI.image(button, "slot_highlight")
ring.Name = "Selection"
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.new(1, RING_OUTSET * 2, 1, RING_OUTSET * 2)
ring.ImageColor3 = P.Selection
ring.ZIndex = 5
ring.Visible = false

local iconField = Instance.new("Frame")
iconField.Name = "Icon"
iconField.AnchorPoint = Vector2.new(0.5, 0.5)
iconField.Position = UDim2.fromScale(0.5, 0.5)
iconField.Size = UDim2.fromScale(ICON_SCALE, ICON_SCALE)
iconField.BackgroundTransparency = 1
iconField.Parent = face

local drawnSprite = nil

-- Draws one of the sprites into the tile, a texel per Frame.
local function drawIcon(sprite)
	if sprite == drawnSprite then
		return
	end
	drawnSprite = sprite
	iconField:ClearAllChildren()
	local field = iconField
	local rows, columns = #sprite, #sprite[1]
	for row, line in ipairs(sprite) do
		for column = 1, columns do
			if string.sub(line, column, column) == "#" then
				local pixel = Instance.new("Frame")
				pixel.BackgroundColor3 = P.Ink
				pixel.BorderSizePixel = 0
				pixel.Position = UDim2.fromScale((column - 1) / columns, (row - 1) / rows)
				pixel.Size = UDim2.fromScale(1 / columns, 1 / rows)
				pixel.Parent = field
			end
		end
	end
end

-- What the button does from here, worded for the tooltip and the countdown.
-- Home is the island chosen with /switchisland (ActiveIsland); standing on it,
-- the button leads back to the world instead.
local function goingHome(): boolean
	return not (
		PlaceConfig.isIsland()
		and workspace:GetAttribute("IslandOwnerId") == player.UserId
		and (workspace:GetAttribute("IslandSlot") or 1) == (player:GetAttribute("ActiveIsland") or 1)
	)
end

local function destinationText(destination: string?): string
	if (destination or (if goingHome() then "island" else "world")) == "world" then
		return "THE WORLD"
	end
	if (player:GetAttribute("IslandCount") or 1) > 1 then
		return "ISLAND " .. (player:GetAttribute("ActiveIsland") or 1)
	end
	return "YOUR ISLAND"
end

-- The globe when the button leads to the world, the island otherwise.
local function refreshIcon()
	drawIcon(if goingHome() then ISLAND_SPRITE else WORLD_SPRITE)
end
refreshIcon()
workspace:GetAttributeChangedSignal("IslandOwnerId"):Connect(refreshIcon)
workspace:GetAttributeChangedSignal("IslandSlot"):Connect(refreshIcon)
player:GetAttributeChangedSignal("ActiveIsland"):Connect(refreshIcon)


-- ---------------------------------------------------------------------------
-- The countdown
-- ---------------------------------------------------------------------------

local panel = PixelUI.image(screen, "frame_wood")
panel.Name = "Countdown"
panel.AnchorPoint = Vector2.new(0.5, 0)
-- Low enough to leave the character, and the aura round it, in view.
panel.Position = UDim2.new(0.5, 0, 0.74, 0)
panel.Size = UDim2.fromOffset(340, 104)
panel.Visible = false

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(0, 14)
title.Size = UDim2.new(1, 0, 0, 22)
title.FontFace = Theme.Fonts.Heading
title.TextSize = Theme.TextSize.Subheading
title.TextColor3 = P.OnWood
title.TextStrokeColor3 = P.Outline
title.TextStrokeTransparency = 0
title.Parent = panel

local track = PixelUI.image(panel, "bar_frame")
track.Name = "Track"
track.Position = UDim2.fromOffset(22, 44)
track.Size = UDim2.new(1, -44, 0, 27)

local grooveLeft, grooveTop, grooveRight, grooveBottom = PixelUI.groove("bar_frame")
local groove = Instance.new("Frame")
groove.Name = "Groove"
groove.BackgroundTransparency = 1
groove.ClipsDescendants = true
groove.Position = UDim2.fromOffset(22 + grooveLeft, 44 + grooveTop)
groove.Size = UDim2.new(1, -(44 + grooveLeft + grooveRight), 0, 27 - grooveTop - grooveBottom)
groove.ZIndex = 2
groove.Parent = panel

local fill = PixelUI.image(groove, "bar_fill")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.ImageColor3 = P.ManaFill

local seconds = Instance.new("TextLabel")
seconds.Name = "Seconds"
seconds.BackgroundTransparency = 1
seconds.Position = groove.Position
seconds.Size = groove.Size
seconds.FontFace = Theme.Fonts.Number
seconds.TextSize = Theme.TextSize.Body
seconds.TextColor3 = P.OnWood
seconds.TextStrokeColor3 = P.Outline
seconds.TextStrokeTransparency = 0
seconds.ZIndex = 3
seconds.Parent = panel

local note = Instance.new("TextLabel")
note.Name = "Note"
note.BackgroundTransparency = 1
note.Position = UDim2.fromOffset(0, 76)
note.Size = UDim2.new(1, 0, 0, 16)
note.FontFace = Theme.Fonts.Body
note.TextSize = Theme.TextSize.Small
note.TextColor3 = P.OnWoodDim
note.Parent = panel

-- The channel this client was told about: when it ends, by the server's clock.
local channel: { endsAt: number, seconds: number, destination: string }? = nil
local hideToken = 0

local function showPanel()
	hideToken += 1
	panel.Visible = true
end

local function hidePanelSoon(delay: number)
	hideToken += 1
	local token = hideToken
	task.delay(delay, function()
		if token == hideToken then
			panel.Visible = false
		end
	end)
end

-- Left of the settings gear at the right of the top bar, with a line on what
-- it does under it on hover. See Shared.UI.TopbarButtons.
local tip = TopbarButtons.add(button, 2, function()
	return if channel then "Cancel teleport" else "Teleport to " .. string.lower(destinationText(nil))
end)

RunService.RenderStepped:Connect(function()
	ring.Visible = channel ~= nil or tip.Visible
	if not channel then
		return
	end
	local left = math.max(0, channel.endsAt - workspace:GetServerTimeNow())
	fill.Size = UDim2.fromScale(1 - left / channel.seconds, 1)
	seconds.Text = string.format("%.1f", left)
end)

local CANCEL_TEXT = {
	damage = "Cancelled - you took damage",
	moved = "Cancelled - you moved",
	input = "Cancelled - stand still to teleport",
	died = "Cancelled",
	player = "Cancelled",
}

Recall.OnClientEvent:Connect(function(event, a, b)
	if event == "started" then
		channel = { endsAt = workspace:GetServerTimeNow() + a, seconds = a, destination = b }
		title.Text = "TELEPORTING TO " .. destinationText(b)
		title.TextColor3 = P.OnWood
		note.Text = "Moving, acting or taking damage cancels it"
		fill.ImageColor3 = P.ManaFill
		showPanel()
		Sounds.play("ui.open")
	elseif event == "cancelled" then
		channel = nil
		title.Text = "TELEPORT CANCELLED"
		title.TextColor3 = Theme.Color.Bad
		note.Text = CANCEL_TEXT[a] or "Cancelled"
		seconds.Text = ""
		fill.ImageColor3 = P.HealthLow
		showPanel()
		hidePanelSoon(2)
		Sounds.play(if a == "damage" then "ui.denied" else "ui.close")
	elseif event == "arrived" then
		channel = nil
		title.Text = "TELEPORTING..."
		note.Text = ""
		seconds.Text = ""
		fill.Size = UDim2.fromScale(1, 1)
		hidePanelSoon(8)
	elseif event == "failed" then
		channel = nil
		hidePanelSoon(0)
	end
end)

--[[
	Any input but looking around cancels: a key, a left click on the world, a
	gamepad button. Moving the mouse, right-click (the camera) and the wheel
	do not. Input a GUI took - typing in chat, clicking this button - is left
	alone. The server cancels on what it can see itself (moving, jumping,
	tools, any action request); this is for what only the client knows about.
]]
local CANCEL_INPUTS = {
	[Enum.UserInputType.Keyboard] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Gamepad1] = true,
}

UserInputService.InputBegan:Connect(function(input, processed)
	if channel and not processed and CANCEL_INPUTS[input.UserInputType] then
		Recall:FireServer("cancel", "input")
	end
end)

button.MouseButton1Click:Connect(function()
	Sounds.play("ui.click")
	Recall:FireServer(if channel then "cancel" else "start")
end)

button.MouseEnter:Connect(function()
	Sounds.play("ui.hover")
end)

-- ---------------------------------------------------------------------------
-- The aura
-- ---------------------------------------------------------------------------

local AURA = ReplicatedStorage:WaitForChild("RecallAura", 30)

-- The dummy's R6 parts, and where each one's effects go on an R15 body. The
-- torso's go on the root, which sits where an R6 torso does - the same height
-- over the feet on both rigs - so a ring drawn at the feet stays on the ground.
local R15_PART = {
	Torso = "HumanoidRootPart",
	Head = "Head",
	["Left Arm"] = "LeftUpperArm",
	["Right Arm"] = "RightUpperArm",
	["Left Leg"] = "LeftUpperLeg",
	["Right Leg"] = "RightUpperLeg",
}

local EFFECT_CLASSES = { "Attachment", "ParticleEmitter", "Beam", "Trail", "PointLight" }

local function isEffect(instance: Instance): boolean
	for _, class in ipairs(EFFECT_CLASSES) do
		if instance:IsA(class) then
			return true
		end
	end
	return false
end

-- character -> { effects = {Instance}, holders = {BasePart} }
local mounted = {}

local function mount(character: Model)
	if mounted[character] or not AURA then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local copy = AURA:Clone()
	local dummyRoot = copy:FindFirstChild("HumanoidRootPart")
	local entry = { effects = {}, holders = {} }
	mounted[character] = entry

	for _, part in ipairs(copy:GetChildren()) do
		if part:IsA("BasePart") and part ~= dummyRoot then
			local target = character:FindFirstChild(part.Name) or character:FindFirstChild(R15_PART[part.Name] or "")
			if target and target:IsA("BasePart") then
				for _, child in ipairs(part:GetChildren()) do
					if isEffect(child) then
						child.Parent = target
						table.insert(entry.effects, child)
					end
				end
			end
		end
	end

	-- Holder parts the pack keeps beside the body: welded where they were,
	-- relative to the dummy's root.
	for _, holder in ipairs(copy:GetDescendants()) do
		if holder:IsA("BasePart") and holder.Parent ~= copy and dummyRoot then
			local offset = dummyRoot.CFrame:ToObjectSpace(holder.CFrame)
			holder.Anchored = false
			holder.CanCollide = false
			holder.CanQuery = false
			holder.CanTouch = false
			holder.Massless = true
			holder.CFrame = root.CFrame * offset
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = holder
			weld.Parent = holder
			holder.Parent = character
			table.insert(entry.holders, holder)
		end
	end

	copy:Destroy()
end

local function unmount(character: Model)
	local entry = mounted[character]
	if not entry then
		return
	end
	mounted[character] = nil

	-- Stop emitting and let what is in the air finish, rather than cutting it.
	for _, list in ipairs({ entry.effects, entry.holders }) do
		for _, instance in ipairs(list) do
			for _, effect in ipairs(instance:GetDescendants()) do
				if effect:IsA("ParticleEmitter") or effect:IsA("Beam") then
					effect.Enabled = false
				end
			end
			if instance:IsA("ParticleEmitter") or instance:IsA("Beam") then
				instance.Enabled = false
			end
		end
	end
	task.delay(2, function()
		for _, list in ipairs({ entry.effects, entry.holders }) do
			for _, instance in ipairs(list) do
				instance:Destroy()
			end
		end
	end)
end

local function watchCharacter(character: Model)
	local function update()
		local untilTime = character:GetAttribute("RecallUntil")
		if type(untilTime) == "number" and untilTime > workspace:GetServerTimeNow() then
			mount(character)
		else
			unmount(character)
		end
	end
	character:GetAttributeChangedSignal("RecallUntil"):Connect(update)
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			unmount(character)
		end
	end)
	update()
end

local function watchPlayer(other: Player)
	other.CharacterAdded:Connect(watchCharacter)
	if other.Character then
		watchCharacter(other.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
