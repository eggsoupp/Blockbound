--[[
	MiningClient

	Sends mining requests and provides all the feedback for them.

	The server decides everything that matters - whether the block breaks, how
	long it takes, what it drops. This is what makes the wait feel like work
	rather than like lag:

	  * the block under the cursor is outlined while it is in reach, so the
	    player knows which block a click will take before clicking - in faint
	    red when the pickaxe in hand is too weak for it (miningPower)
	  * the outline brightens while the block is being worked on
	  * cracks spread across the block itself, Minecraft-style, as it gives way
	    (Shared.Blocks.BreakOverlay) - there is no progress bar
	  * the pickaxe's mining swing loops while the button is held, faster for a
	    faster pickaxe (miningSpeed)
	  * a chip and a puff of debris on each tick, pitched to the material
	  * a heavier break and a burst of block-coloured chunks when it goes,
	    and the block's item lands on the ground (GroundDrops) to be picked up
	  * a red flash on the block when the server refuses the swing
	  * holding the button carries straight on into the next block, and follows
	    the cursor: moving onto a different block drops the one in progress
	    and starts on the new one, as in Minecraft

	The outline is Shared.UI.WorldFeedback's focus, claimed as "mine", so it
	never competes with the chopping, combat or building outlines.

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
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local MenuState = require(Shared.UI:WaitForChild("MenuState"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local Feedback = require(Shared.UI:WaitForChild("Feedback"))
local WorldFeedback = require(Shared.UI:WaitForChild("WorldFeedback"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local OreConfig = require(Shared.Terrain:WaitForChild("OreConfig"))
local BlockConfig = require(Shared:WaitForChild("Blocks"):WaitForChild("BlockConfig"))
local BreakOverlay = require(Shared.Blocks:WaitForChild("BreakOverlay"))
local ToolConfig = require(Shared:WaitForChild("Tools"):WaitForChild("ToolConfig"))
local ToolAnimation = require(Shared.Tools:WaitForChild("ToolAnimation"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local STUD_SIZE = TerrainConfig.StudSize

--[[
	What each ore asks of a pickaxe, told to this side's BlockConfig.

	On the server OreRegistry registers this along with the rest of each ore's
	facts; nothing runs OreRegistry here, so without this the client would
	think every ore takes power 1. Only `power`, and only to colour the hover
	outline - MiningServer decides for real with its own copy.
]]
for _, ore in pairs(OreConfig.Definitions) do
	BlockConfig.registerBlock(ore.block, { power = ore.power })
end

-- MiningServer's MAX_MINE_DISTANCE, measured the same way: root to hit point.
-- Only decides whether the hover outline is drawn; the server measures again
-- for every swing, so a stale copy here costs an outline, never a block.
local MINE_REACH = 34

-- How often the hover outline re-aims. A raycast at 20Hz, not per frame.
local HOVER_INTERVAL = 1 / 20

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

--[[
	Following the cursor while the button is held, as Minecraft does: moving
	off the block being mined abandons it, and the hold carries on into
	whatever block the cursor is at now. See the hover loop at the bottom.

	`retargeting` is set between asking the server to drop the old block and
	its "cancelled" arriving - only then is it free to start the new one.
	`refusedCentre` is the block the server last refused, so a held button on
	it does not ask again every tick; it clears once the cursor moves off.
	`resumeAfter` holds automatic starts back for a moment after a result, so
	the terrain has replicated the last break before the next ray is cast.
]]
local retargeting = false
local refusedCentre = nil
local resumeAfter = 0
local RESUME_DELAY = 0.12

-- The centre of the single block being mined, in world studs. Not the same as
-- targetPart.Position any more: the renderer merges runs of identical blocks
-- into one long Part, so a Part's centre is the middle of the run rather than
-- the block the player is pointing at.
local targetCentre = nil

-- Bumped whenever a swing ends or a new one starts. The progress animation
-- checks it every frame and stops as soon as it no longer matches, which is how
-- a cancelled swing cannot leave a bar creeping along behind the next one.
local progressToken = 0

--[[
	The outline on whatever is being mined is WorldFeedback's focus, claimed as
	"mine" and pointed at the proxy below. One Highlight for the whole game's
	targeting, re-adorned rather than recreated.

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
	Ends whatever swing is being animated. Cheap enough to call unconditionally.
]]
local function stopProgressAnimation()
	progressToken += 1
end

-- After a refusal the outline holds still on the refused block long enough for
-- its red flash to be seen, instead of the hover loop fading it straight away.
local hoverHoldUntil = 0

--[[
	Forgets the swing. `broken` is true when the block is gone, which drops the
	outline at once; otherwise the hover loop decides what it shows next.
]]
local function clearTarget(broken)
	if broken then
		WorldFeedback.release("mine", true)
	end
	targetPart = nil
	targetName = nil
	targetCentre = nil
end

-- A refused or abandoned swing: the block it was aimed at flashes red.
local function flashRefused()
	WorldFeedback.flash(targetProxy, "Invalid")
	hoverHoldUntil = os.clock() + WorldFeedback.FlashSeconds
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
	the block breaks - a client that lied about this would get cracks that
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

	--[[
		The cracks go on the one block being mined, not the merged run it was
		drawn as - the same reason the outline follows a proxy. There is no
		progress bar: the cracks are the progress (Shared.Blocks.BreakOverlay).

		Only the END of a swing hides them (the result, a cancel, a timeout).
		The loop below only moves the stage - it used to hide the overlay on its
		first frame, where the fraction is still zero, which is why no cracks
		were ever seen. At 100% the last stage holds until the server's verdict,
		so the cracks never vanish before the block does.
	]]
	if targetCentre then
		BreakOverlay.show(targetCentre, STUD_SIZE)
	end

	-- One chip per ~15% of the way through, so a fast block gets a couple of
	-- taps and a slow one gets a rhythm, instead of both getting a machine gun.
	local nextChipAt = 15

	task.spawn(function()
		while progressToken == token do
			local fraction = (os.clock() - startedAt) / duration
			if fraction > 1 then
				fraction = 1
			end

			BreakOverlay.setProgress(fraction)

			local percent = math.floor(fraction * 100)

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

--[[
	What to tell the player when the server says no.

	Every refusal used to be silent: the bar flickered and nothing happened,
	which looks exactly like a bug in the terrain. A refusal is the server
	working as designed, so the reason goes on screen. "cancelled" and
	"already_mining" are left out - the player caused both on purpose.
]]
local REFUSALS = {
	inventory_full = "Inventory full",
	too_far = "Too far away to mine that",
	moved_too_far = "Moved out of reach",
	no_pickaxe = "Hold a pickaxe to mine",
	unbreakable = "That can't be broken",
	too_weak = "Your pickaxe isn't strong enough for that",
	no_block = "Nothing to mine there",
	bad_target = "Nothing to mine there",
	target_lost = "That block changed before you finished",
	break_failed = "That block wouldn't break",
	terrain_error = "Mining failed (see the Output window)",
	no_character = "No character to mine with",
}

-- Holding the button into a wall of refusals should not fill the feed with
-- the same line.
local REFUSAL_REPEAT_SECONDS = 2
local lastRefusal, lastRefusalAt = nil, 0

local function reportRefusal(reason, itemName)
	local text = REFUSALS[reason]
	if not text then
		return
	end

	if reason == "inventory_full" and type(itemName) == "string" then
		local def = ItemDefinitions[itemName]
		text = string.format("Inventory full: no room for %s", def and def.displayName or itemName)
	end

	local now = os.clock()
	if text == lastRefusal and now - lastRefusalAt < REFUSAL_REPEAT_SECONDS then
		return
	end
	lastRefusal, lastRefusalAt = text, now

	Feedback.show(text, "bad")
end

MiningResult.OnClientEvent:Connect(function(success, itemName, reason)
	if not success then
		reportRefusal(reason, itemName)

		-- Only the refusals worth a line are worth a flash; a swing the player
		-- let go of on purpose ("cancelled") is not a mistake.
		if REFUSALS[reason] and targetCentre then
			flashRefused()
			refusedCentre = targetCentre
		end
	end

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
	BreakOverlay.hide()
	clearTarget(success)

	local wasRetargeting = retargeting
	retargeting = false
	resumeAfter = os.clock() + RESUME_DELAY

	if success and mouseHeld then
		-- Still holding, and that one came off cleanly: go straight into the
		-- next block. Briefly delayed so terrain replication can settle.
		task.delay(RESUME_DELAY, function()
			if mouseHeld then beginMining() end
		end)
	elseif wasRetargeting and mouseHeld then
		-- The old block was dropped because the cursor moved; the server has
		-- let go of it, so start on the block the cursor is at now. Nothing
		-- broke, so there is no terrain to wait for.
		beginMining()
	end
	-- Any other refusal keeps its reason on screen instead of being retried
	-- into a loop; refusedCentre stops the hover loop asking again too.
end)

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

local function pickaxeDefinitionNamed(itemName)
	local def = type(itemName) == "string" and ItemDefinitions[itemName]
	if def and def.classification == "Pickaxe" then
		return def
	end
	return nil
end

--[[
	The pickaxe the player is holding, as its ItemDefinitions entry, or nil.

	Only a hint: this decides whether to bother asking the server, how fast to
	swing and how to colour the outline, nothing more. The server reads the
	same things again before it starts a break, so a client that lies here
	gains nothing.
]]
local function heldPickaxeDefinition()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end

	local value = tool:FindFirstChild("ItemName") or tool:FindFirstChild("itemName")

	return pickaxeDefinitionNamed(tool:GetAttribute("itemName") or tool:GetAttribute("ItemName"))
		or pickaxeDefinitionNamed(value and value:IsA("StringValue") and value.Value or nil)
		or pickaxeDefinitionNamed(tool.Name)
end

-- heldPickaxeDefinition walks a tool's names; remembered per tool so the hover
-- loop asks it once per equip rather than twenty times a second.
local cachedTool, cachedPickaxe = nil, nil

local function holdingPickaxe()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool ~= cachedTool then
		cachedTool = tool
		cachedPickaxe = if tool then heldPickaxeDefinition() else nil
	end
	return cachedPickaxe
end

-- ---------------------------------------------------------------------------
-- The swing
-- ---------------------------------------------------------------------------
--[[
	The pickaxe's mining animation (ToolConfig.Animations.Pickaxe), LOOPED for
	as long as the button is held with a pickaxe out - whether or not anything
	breaks, the way an arm keeps swinging in Minecraft. Faster pickaxes swing
	faster: the rate is ToolConfig.miningAnimationRate of the pickaxe's
	miningSpeed.

	Played on this character's own Animator, so everybody else sees it too.
	ToolFeedback leaves pickaxes alone so the two never fight over the track.
]]
local swingTrack = nil

local function stopSwing()
	if swingTrack then
		swingTrack:Stop(0.15)
		swingTrack = nil
	end
end

local function startSwing()
	local pickaxe = holdingPickaxe()
	local character = player.Character
	if not (pickaxe and character) or MenuState.isAnyOpen() then
		return
	end

	local id = ToolConfig.animationFor(pickaxe.classification, pickaxe)
	local track = id and ToolAnimation.track(character, id)
	if not track then
		return
	end

	local rate = ToolConfig.miningAnimationRate(pickaxe.miningSpeed)
	track.Looped = true

	if track.IsPlaying then
		track:AdjustSpeed(rate)
	else
		track:Play(0.1, 1, rate)
	end
	swingTrack = track
end

player.CharacterAdded:Connect(function()
	-- The old track belonged to the old body.
	swingTrack = nil
end)

function beginMining()
	if isMining or MenuState.isAnyOpen() or not heldPickaxeDefinition() then
		return
	end

	-- Refresh the ray for every swing; Mouse.Target can still refer to the
	-- part removed by the previous break until the next rendered frame.
	local ray = mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Aim through water at the block behind it: water is Terrain now, and a
	-- ray stops at Terrain water unless told not to.
	params.IgnoreWater = true
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

		-- Brighter while it is being worked on than while it is only aimed at.
		if targetCentre then
			targetProxy.CFrame = CFrame.new(targetCentre)
			WorldFeedback.focus("mine", targetProxy, "MineActive")
		else
			WorldFeedback.focus("mine", target, "MineActive")
		end
	end

	local requestToken = progressToken
	RequestMine:FireServer(target, hitPos)
	task.delay(10, function()
		if isMining and progressToken == requestToken then
			CancelMine:FireServer()
			isMining = false
			retargeting = false
			stopProgressAnimation()
			BreakOverlay.hide()
			flashRefused()
			clearTarget(false)
			warn("[MiningClient] Server did not start the mining request; swing reset")
			Feedback.show("The server didn't answer that swing", "bad")
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
	startSwing()
	beginMining()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = false
		stopSwing()
		endMining()
	end
end)

-- Opening a menu mid-swing should stop the swing, not leave a highlighted block
-- and stuck cracks behind it. The held flag is dropped too, or the chain would
-- start the next block behind the menu.
MenuState.Changed:Connect(function(_, _, anyOpen)
	if anyOpen then
		mouseHeld = false
		stopSwing()
		if isMining then
			endMining()
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Hover outline
-- ---------------------------------------------------------------------------
--[[
	Outlines the block a click would mine, before the click.

	The same ray beginMining casts, at 20Hz, with its params built once. It
	asks only what the outline needs - is this a block, can it break, is it in
	reach - and leaves every real decision to the server. While a swing is
	running it stands aside: the outline belongs to the block being mined.
]]

local hoverParams = RaycastParams.new()
hoverParams.FilterType = Enum.RaycastFilterType.Exclude
hoverParams.IgnoreWater = true
local hoverExcluded = { targetProxy }

local function refreshHoverFilter()
	hoverExcluded[2] = player.Character
	hoverParams.FilterDescendantsInstances = hoverExcluded
end

refreshHoverFilter()
player.CharacterAdded:Connect(function()
	task.defer(refreshHoverFilter)
end)

local function isMineable(part)
	if CollectionService:HasTag(part, "CraftingStation") then
		return true
	end
	return CollectionService:HasTag(part, "TerrainBlock") and not BlockConfig.isUnbreakable(part.Name)
end

--[[
	"Mine" for a block this pickaxe can take, "MineBlocked" - a faint red edge -
	for one it is too weak for, so the player learns what their tier reaches
	before swinging at it. Stations come up whole with any pickaxe.
]]
local function hoverStyle(part, pickaxe)
	if CollectionService:HasTag(part, "CraftingStation") or BlockConfig.canMine(part.Name, pickaxe) then
		return "Mine"
	end
	return "MineBlocked"
end

local function updateHover()
	-- Put away mid-hold: the arm stops with the pickaxe.
	if swingTrack and not holdingPickaxe() then
		stopSwing()
	end

	-- Waiting out a refusal's flash, or for the server to let go of a block the
	-- cursor moved off: nothing to decide until that settles.
	if os.clock() < hoverHoldUntil or retargeting then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local pickaxe = holdingPickaxe()
	if not root or MenuState.isAnyOpen() or not pickaxe then
		if not isMining then
			WorldFeedback.release("mine")
		end
		return
	end

	local ray = mouse.UnitRay
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 512, hoverParams)
	local part = hit and hit.Instance

	-- The block under the cursor that a swing could take, or nil.
	local centre = nil
	if part and isMineable(part) and (hit.Position - root.Position).Magnitude <= MINE_REACH then
		centre = blockCentreAt(hit.Position - hit.Normal * 0.05, ray.Direction)
	end

	if isMining then
		--[[
			Still holding, but the cursor has left the block being mined - onto
			another block, or onto nothing. Drop it, the way Minecraft resets a
			break you look away from; the result handler starts the next one
			once the server confirms it has let go. The server would otherwise
			carry on with the old block for as long as it stayed in reach.
		]]
		if mouseHeld and targetCentre and centre ~= targetCentre then
			retargeting = true
			CancelMine:FireServer()
		end
		return
	end

	-- A refused block is not asked about again until the cursor moves off it.
	if refusedCentre and centre ~= refusedCentre then
		refusedCentre = nil
	end

	if not centre then
		WorldFeedback.release("mine")
		return
	end

	if targetProxy.Position ~= centre then
		targetProxy.CFrame = CFrame.new(centre)
	end

	local style = hoverStyle(part, pickaxe)
	WorldFeedback.focus("mine", targetProxy, style)

	--[[
		Held down, not mining, cursor on a block this pickaxe can take: start on
		it. This is what carries a hold onto a block after the cursor was over
		nothing, or after a refusal elsewhere. A block too hard for the pickaxe
		is left to an actual click, which gets the server's reason on screen.
	]]
	if mouseHeld and style == "Mine" and centre ~= refusedCentre and os.clock() >= resumeAfter then
		beginMining()
	end
end

local hoverAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	hoverAccumulator += dt
	if hoverAccumulator < HOVER_INTERVAL then
		return
	end
	hoverAccumulator = 0
	updateHover()
end)
