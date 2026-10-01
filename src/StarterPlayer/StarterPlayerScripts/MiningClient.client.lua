--[[
	MiningClient

	Sends mining requests and provides all the feedback for them.

	The server decides everything that matters - whether the block breaks, how
	long it takes, what it drops. This is what makes the wait feel like work
	rather than like lag:

	  * the targeted block is outlined, and whitens as progress climbs
	  * a chip and a puff of debris on each tick, pitched to the material
	  * a heavier break and a burst of block-coloured chunks when it goes
	  * a progress bar that only appears while something is happening
	  * holding the button carries straight on into the next block

	The material comes from the target part's Name, which TerrainManager sets to
	the block name when it renders it, so none of this costs a remote.

	Input is read through UserInputService rather than Mouse.Button1Down so the
	`gameProcessed` flag can be honoured - without it, clicking a button in the
	crafting window also swung your pickaxe at whatever was behind it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local MenuState = require(Shared.UI:WaitForChild("MenuState"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local STUD_SIZE = TerrainConfig.StudSize

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local RequestMine = Remotes.wait("RequestMineBlock")
local MiningStarted = Remotes.wait("MiningStarted")
local MiningResult = Remotes.wait("MiningResult")
local CancelMine = Remotes.wait("CancelMine")

local isMining = false
local targetPart = nil
local targetName = nil

-- Forward declared: the MiningResult handler below chains into it, and it is
-- defined further down with the rest of the input handling.
local beginMining

-- Whether the button is still down. A mining game is mostly one block after
-- another, so holding continues into the next one rather than asking for a
-- click per block. Each block is still a fresh request the server validates
-- from scratch.
local mouseHeld = false

-- The centre of the single block being mined, in world studs. Not the same as
-- targetPart.Position any more: the renderer merges runs of identical blocks
-- into one long Part, so a Part's centre is the middle of the run rather than
-- the block the player is pointing at.
local targetCentre = nil

-- Bumped whenever a swing ends or a new one starts. The progress animation
-- checks it every frame and stops as soon as it no longer matches, which is how
-- a cancelled swing cannot leave a bar creeping along behind the next one.
local progressToken = 0

-- ---------------------------------------------------------------------------
-- Progress bar
-- ---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "MiningGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local back = Instance.new("Frame")
back.Name = "Back"
back.AnchorPoint = Vector2.new(0.5, 1)
back.Position = UDim2.fromScale(0.5, 0.9)
back.Size = UDim2.fromOffset(180, 8)
back.BackgroundColor3 = Theme.Color.Panel
back.BackgroundTransparency = 0.2
back.BorderSizePixel = 0
back.Parent = gui

local backStroke = Instance.new("UIStroke")
backStroke.Color = Theme.Color.Stroke
backStroke.Thickness = 1
backStroke.Parent = back

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Theme.Color.Accent
fill.BorderSizePixel = 0
fill.Parent = back

--[[
	The outline on whatever is being mined. One Highlight, re-adorned rather than
	recreated - Highlight instances are a limited resource per client.
]]
local highlight = Instance.new("Highlight")
highlight.Name = "MiningHighlight"
highlight.FillColor = Color3.new(1, 1, 1)
highlight.FillTransparency = 1
highlight.OutlineColor = Theme.Color.Accent
highlight.OutlineTransparency = 0.15
highlight.DepthMode = Enum.HighlightDepthMode.Occluded
highlight.Enabled = false
-- Parented to PlayerGui rather than to the progress ScreenGui above: that gui
-- is enabled and disabled constantly, and a Highlight has no business inheriting
-- the visibility of a progress bar.
highlight.Parent = player.PlayerGui

--[[
	A one-block stand-in for the Highlight to outline.

	A Highlight outlines its whole Adornee, and since the renderer started
	merging runs of identical blocks into single stretched Parts, adorning the
	real Part lights up the entire run - forty studs of ground for a four-stud
	block. Rather than lose the outline, the highlight follows this invisible
	cube, which is moved onto whichever block the player is actually aiming at.

	CanQuery is false so it can never be picked up by the mouse raycast that
	decides what is being aimed at, which would otherwise make it shadow the
	terrain behind it the moment it appeared.
]]
local targetProxy = Instance.new("Part")
targetProxy.Name = "MiningTargetProxy"
targetProxy.Size = Vector3.new(STUD_SIZE, STUD_SIZE, STUD_SIZE)
targetProxy.Anchored = true
targetProxy.CanCollide = false
targetProxy.CanQuery = false
targetProxy.CanTouch = false
targetProxy.Transparency = 1
targetProxy.CastShadow = false
targetProxy.Locked = true
targetProxy.Parent = workspace

--[[
	Which block is the player pointing at?

	The hit point sits exactly ON a face, so flooring it directly is ambiguous -
	a click on the top of a block floors to the block above. Stepping a fraction
	along the aim direction first lands the point inside the block that was
	actually hit, which is the same block the server resolves from the same
	position.
]]
local function blockCentreAt(hitPos, direction)
	if not hitPos then
		return nil
	end

	local inside = hitPos
	if direction then
		inside = hitPos + direction.Unit * 0.1
	end

	return Vector3.new(
		math.floor(inside.X / STUD_SIZE) * STUD_SIZE + STUD_SIZE * 0.5,
		math.floor(inside.Y / STUD_SIZE) * STUD_SIZE + STUD_SIZE * 0.5,
		math.floor(inside.Z / STUD_SIZE) * STUD_SIZE + STUD_SIZE * 0.5
	)
end

--[[
	Draws the bar at `percent`.

	`immediate` sets the width directly instead of tweening to it. The tween is
	right for the occasional jump - starting a swing, snapping back to zero -
	but the swing itself is now animated locally at frame rate, and building a
	Tween every frame would cost more than the ten-a-second remote this replaced.
]]
local function setProgress(percent, immediate)
	local clamped = math.clamp(percent / 100, 0, 1)

	gui.Enabled = percent > 0 and percent < 100

	if immediate then
		fill.Size = UDim2.fromScale(clamped, 1)
	else
		TweenService:Create(fill, Theme.Tween.Hover, { Size = UDim2.fromScale(clamped, 1) }):Play()
	end

	-- The block whitens as it gives way, so the world tells you how far along you
	-- are without you having to look at the bar.
	if highlight.Enabled then
		highlight.FillTransparency = 1 - clamped * 0.55
	end
end

--[[
	Ends whatever swing is being animated. Cheap enough to call unconditionally.
]]
local function stopProgressAnimation()
	progressToken += 1
end

local function clearTarget()
	highlight.Enabled = false
	highlight.Adornee = nil
	highlight.FillTransparency = 1
	targetPart = nil
	targetName = nil
	targetCentre = nil
end

-- ---------------------------------------------------------------------------
-- Debris
-- ---------------------------------------------------------------------------

--[[
	A short-lived shower of small cubes in the block's own colour.

	Deliberately real parts rather than a ParticleEmitter: the game is blocky, so
	blocky debris reads correctly, and it needs no particle texture asset. They
	are unanchored but massless and non-colliding, so they cost almost nothing
	and cannot shove the player around.
]]
local function spawnDebris(position, color, count, spread, size)
	for _ = 1, count do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(size, size, size)
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

		-- Velocity has to be set AFTER parenting: an unparented part has no
		-- assembly for the physics engine to apply it to, so setting it first
		-- silently does nothing and the debris just drops straight down.
		chunk.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 14,
			math.random() * 10 + 3,
			(math.random() - 0.5) * 14
		)

		Debris:AddItem(chunk, 1.1)
	end
end

local function targetColor()
	if targetPart and targetPart:IsA("BasePart") then
		return targetPart.Color
	end
	return Color3.fromRGB(150, 150, 150)
end

--[[
	Where the chips and the break sound come from.

	The block's own centre, not the Part's - on a merged run those are different
	places, and debris spraying out of the middle of a forty-stud slab while the
	player mines its far end reads as a bug.
]]
local function targetPosition()
	if targetCentre then
		return targetCentre
	end
	if targetPart and targetPart:IsA("BasePart") then
		return targetPart.Position
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Server events
-- ---------------------------------------------------------------------------

--[[
	The server has decided how long this block takes and started its clock. It
	sends that once; everything the player sees for the rest of the swing is
	animated here against the local clock.

	This is presentation only. The server still runs its own timer, still
	re-checks reach and tool for the whole duration, and still decides whether
	the block breaks - a client that lied about this would get a bar that
	finished early and a block that did not.
]]
MiningStarted.OnClientEvent:Connect(function(duration, blockName)
	duration = tonumber(duration)
	if not duration or duration <= 0 then
		return
	end

	if type(blockName) == "string" and blockName ~= "" then
		targetName = blockName
	end

	progressToken += 1
	local token = progressToken
	local startedAt = os.clock()

	-- One chip per ~15% of the way through, so a fast block gets a couple of
	-- taps and a slow one gets a rhythm, instead of both getting a machine gun.
	local nextChipAt = 15

	task.spawn(function()
		while progressToken == token do
			local fraction = (os.clock() - startedAt) / duration
			if fraction > 1 then
				fraction = 1
			end

			local percent = math.floor(fraction * 100)
			setProgress(percent, true)

			if percent >= nextChipAt and percent < 100 then
				nextChipAt += 15

				local position = targetPosition()
				if position then
					Sounds.playBlock("mine.hit", targetName, position)
					spawnDebris(position, targetColor(), 2, 3.2, 0.35)
				end
			end

			if fraction >= 1 then
				break
			end

			RunService.Heartbeat:Wait()
		end
	end)
end)

MiningResult.OnClientEvent:Connect(function(success, itemName)
	local position = targetPosition()
	local color = targetColor()

	if success and position then
		Sounds.playBlock("mine.break", targetName, position)
		spawnDebris(position, color, 8, 3.6, 0.55)

		-- Ore is worth noticing, so it gets a second, brighter burst.
		local def = itemName and ItemDefinitions[itemName]
		if def and (def.rarity == "Rare" or def.rarity == "Epic" or def.rarity == "Legendary") then
			spawnDebris(position, Theme.rarityColor(def.rarity), 6, 3.0, 0.4)
		end
	end

	isMining = false
	stopProgressAnimation()
	setProgress(0)
	clearTarget()

	-- Still holding, and that one came off cleanly: go straight into the next
	-- block. Briefly delayed so terrain replication can settle, and
	-- only on success - a refusal keeps its reason on screen instead of being
	-- retried into a loop.
	if success and mouseHeld then
		task.delay(0.12, function()
			if mouseHeld then beginMining() end
		end)
	end
end)

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

--[[
	Is the player holding a pickaxe?

	Only a hint: this decides whether to bother asking the server, nothing more.
	The server checks the same thing again before it starts a break, so a client
	that lies here gains nothing.
]]
local function hasPickaxeEquipped()
	local character = player.Character
	if not character then
		return false
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return false
	end

	local attribute = tool:GetAttribute("itemName") or tool:GetAttribute("ItemName")
	local value = tool:FindFirstChild("ItemName") or tool:FindFirstChild("itemName")
	local fromValue = value and value:IsA("StringValue") and value.Value or nil

	for _, itemName in ipairs({ attribute, fromValue, tool.Name }) do
		local def = itemName and ItemDefinitions[itemName]
		if def and def.classification == "Pickaxe" then
			return true
		end
	end

	return false
end

function beginMining()
	if isMining or MenuState.isAnyOpen() or not hasPickaxeEquipped() then
		return
	end

	-- Refresh the ray for every swing; Mouse.Target can still refer to the
	-- part removed by the previous break until the next rendered frame.
	local ray = mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = { targetProxy }
	if player.Character then table.insert(excluded, player.Character) end
	params.FilterDescendantsInstances = excluded
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 512, params)
	if not hit then return end
	local target = hit.Instance
	local hitPos = hit.Position - hit.Normal * 0.05
	local aimDirection = ray.Direction

	isMining = true
	-- Anything still animating belongs to the previous swing.
	stopProgressAnimation()

	if target and target:IsA("BasePart") then
		targetPart = target
		-- TerrainManager names every rendered part after its block, so the
		-- material is already here without asking the server for it.
		targetName = target.Name

		-- Outline the block, not the run it belongs to. The proxy is moved onto
		-- the aimed-at block and the Highlight follows it, so a merged Part
		-- forty studs long still lights up exactly one four-stud cube.
		targetCentre = blockCentreAt(hitPos, aimDirection)

		if targetCentre then
			targetProxy.CFrame = CFrame.new(targetCentre)
			highlight.Adornee = targetProxy
		else
			highlight.Adornee = target
		end

		highlight.FillTransparency = 1
		highlight.Enabled = true
	end

	setProgress(1)
	local requestToken = progressToken
	RequestMine:FireServer(target, hitPos)
	task.delay(10, function()
		if isMining and progressToken == requestToken then
			CancelMine:FireServer()
			isMining = false
			stopProgressAnimation()
			setProgress(0)
			clearTarget()
			warn("[MiningClient] Server did not start the mining request; swing reset")
		end
	end)
end

local function endMining()
	if not isMining then
		return
	end
	CancelMine:FireServer()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	mouseHeld = true
	beginMining()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = false
		endMining()
	end
end)

-- Opening a menu mid-swing should stop the swing, not leave a highlighted block
-- and a stuck progress bar behind it. The held flag is dropped too, or the
-- chain would start the next block behind the menu.
MenuState.Changed:Connect(function(_, _, anyOpen)
	if anyOpen then
		mouseHeld = false
		if isMining then
			endMining()
		end
	end
end)
