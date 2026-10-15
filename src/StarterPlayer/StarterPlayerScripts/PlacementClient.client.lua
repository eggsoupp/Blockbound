--[[
	PlacementClient

	Shows where a block would go and asks the server to put it there.

	The preview follows the cursor on a 30Hz raycast and turns red where the
	cell is blocked - by geometry, or by the player themselves. On a confirmed
	placement the block pops in with a short scale and a thump, so building has
	some weight to it.

	The ghost also carries Shared.UI.WorldFeedback's focus outline, claimed as
	"place": green where the cell is free, red where it is not, blended rather
	than blinked between the two. A refused click flashes it, and a refusal
	from the server says why in the feedback column.

	Input is read through UserInputService rather than Mouse.Button1Down so the
	`gameProcessed` flag can be honoured; without it, clicking a button in the
	crafting window also tried to place a block behind it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MenuState = require(Shared:WaitForChild("UI"):WaitForChild("MenuState"))
local WorldFeedback = require(Shared.UI:WaitForChild("WorldFeedback"))
local Feedback = require(Shared.UI:WaitForChild("Feedback"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local InventoryMirror =
	require(Shared:WaitForChild("Inventory"):WaitForChild("InventoryMirror"))

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

local DEFAULT_GRID = 4
local Grid = DEFAULT_GRID
local GRID_ORIGIN = Vector3.new(Grid * 0.5, Grid * 0.5, Grid * 0.5)
local HIDDEN_CFRAME = CFrame.new(0, -10000, 0)
local RAYCAST_INTERVAL = 1 / 30
local MAX_RAY_DISTANCE = 900

local TerrainAssets = ReplicatedStorage:FindFirstChild("TerrainAssets")
local BlocksFolder = TerrainAssets and TerrainAssets:FindFirstChild("Blocks")
if BlocksFolder then
	for _, inst in ipairs(BlocksFolder:GetDescendants()) do
		if inst:IsA("BasePart") then
			Grid = math.max(1, math.floor(inst.Size.X + 0.5))
			GRID_ORIGIN = Vector3.new(Grid * 0.5, Grid * 0.5, Grid * 0.5)
			break
		end
	end
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local RequestPlaceBlock = remotesFolder:WaitForChild("RequestPlaceBlock")
local RequestFullInv = remotesFolder:FindFirstChild("RequestFullInventory")
local PlacementResult = remotesFolder:FindFirstChild("PlacementResult")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local equippedSlot = nil
local localInventory = {}
--[[
	How see-through the placement preview is.

	High enough to read as a ghost of a block rather than a block: you have to
	be able to see the terrain you are about to build on THROUGH it, or the
	preview hides the thing it is helping you aim at.
]]
local PREVIEW_TRANSPARENCY = 0.55

local preview = nil
local previewItemName = nil
local lastCellX = nil
local lastCellY = nil
local lastCellZ = nil
local lastCanPlace = false
-- Whether the cached cell was blocked by geometry; the character test is
-- re-run every update on top of it. See updatePreview.
local lastCellBlocked = true
local raycastAccumulator = 0
local resultFlashUntil = 0
local resultFlashSuccess = true

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
-- Aim through water: water is Terrain, and placing a block INTO a lake means
-- pointing at the bed through the surface.
raycastParams.IgnoreWater = true

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function round(n)
	return math.floor(n + 0.5)
end

local function worldPosToCellIndices(pos)
	return round((pos.X - GRID_ORIGIN.X) / Grid),
	round((pos.Y - GRID_ORIGIN.Y) / Grid),
	round((pos.Z - GRID_ORIGIN.Z) / Grid)
end

local function cellIndicesToWorldPos(ix, iy, iz)
	return Vector3.new(
		GRID_ORIGIN.X + ix * Grid,
		GRID_ORIGIN.Y + iy * Grid,
		GRID_ORIGIN.Z + iz * Grid
	)
end

local function updateFilters()
	local ignore = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	if preview then
		table.insert(ignore, preview)
	end

	raycastParams.FilterDescendantsInstances = ignore
	overlapParams.FilterDescendantsInstances = ignore
end

-- Both of these end up in the world as a one-cell object, so both get a preview.
-- The server decides which system actually builds it.
local placeableClasses = {
	Block = true,
	Workbench = true,
}

local function getEquippedSlotData()
	if type(equippedSlot) ~= "number" then return nil end
	local slotData = localInventory[equippedSlot]
	if not slotData or (slotData.count or 0) <= 0 then return nil end

	local def = ItemDefinitions[slotData.name]
	if not def or not placeableClasses[def.classification] then return nil end

	return slotData
end

local function clonePreviewTemplate(itemName)
	local template = BlocksFolder and (BlocksFolder:FindFirstChild(itemName) or BlocksFolder:FindFirstChild(itemName, true))
	if template and template:IsA("BasePart") then
		return template:Clone()
	end
	if template and template:IsA("Model") then
		local part = template.PrimaryPart or template:FindFirstChildWhichIsA("BasePart")
		if part then
			return part:Clone()
		end
	end

	local fallback = ReplicatedStorage:FindFirstChild("Part")
	if fallback and fallback:IsA("BasePart") then
		return fallback:Clone()
	end

	local part = Instance.new("Part")
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(120, 190, 255)
	return part
end

--[[
	Makes a cloned block see-through, INCLUDING ITS FACES.

	A part's Transparency does not touch its Decals or Textures - they carry
	their own, and they default to opaque. So a textured block cloned for the
	preview came out looking completely solid however transparent the part
	underneath it was, which is why the preview read as a real block sitting in
	the world rather than as a suggestion.

	It is also what was hiding the red/green placement tint: `Color` only shows
	where the faces are not.
]]
local function setPreviewTransparency(part, alpha)
	part.Transparency = alpha

	for _, child in ipairs(part:GetDescendants()) do
		if child:IsA("Decal") or child:IsA("Texture") then
			child.Transparency = alpha
		end
	end
end

local function destroyPreview()
	WorldFeedback.release("place", true)
	if preview then
		preview:Destroy()
		preview = nil
	end
	previewItemName = nil
	lastCellX, lastCellY, lastCellZ = nil, nil, nil
	lastCanPlace = false
	lastCellBlocked = true
end

local function ensurePreview(itemName)
	if preview and previewItemName == itemName then
		return preview
	end

	destroyPreview()

	preview = clonePreviewTemplate(itemName)
	previewItemName = itemName
	preview.Name = "PlacementPreview"
	preview.Size = Vector3.new(Grid, Grid, Grid)
	preview.Anchored = true
	preview.CanCollide = false
	preview.CanQuery = false
	preview.CanTouch = false
	preview.CastShadow = false

	-- Faces included; see setPreviewTransparency.
	setPreviewTransparency(preview, PREVIEW_TRANSPARENCY)
	preview.Parent = Workspace
	preview.CFrame = HIDDEN_CFRAME

	updateFilters()
	return preview
end

local function setPreviewState(canPlace)
	if not preview then return end

	local flashActive = os.clock() < resultFlashUntil
	if flashActive then
		canPlace = resultFlashSuccess
	end

	if canPlace then
		preview.Color = Color3.fromRGB(90, 220, 120)
	else
		preview.Color = Color3.fromRGB(255, 95, 95)
	end

	-- A repeat of the same verdict returns at once inside WorldFeedback, so
	-- this costs nothing at thirty calls a second.
	WorldFeedback.focus("place", preview, if canPlace then "PlaceValid" else "PlaceInvalid")
end

-- The character is deliberately filtered out of the overlap query, so it is
-- tested separately - and NOT cached with the cell, because the player can
-- walk into or out of it without moving the cursor. The server refuses a block
-- that would seal them in, so the preview should say so first.
local function overlapsCharacter(worldCenter)
	local character = player.Character
	if not character then
		return false
	end

	local cf, size = character:GetBoundingBox()
	local gap = cf.Position - worldCenter

	return math.abs(gap.X) < size.X * 0.5 + Grid * 0.5
		and math.abs(gap.Y) < size.Y * 0.5 + Grid * 0.5
		and math.abs(gap.Z) < size.Z * 0.5 + Grid * 0.5
end

local function isCellBlocked(worldCenter)
	local parts = Workspace:GetPartBoundsInBox(
		CFrame.new(worldCenter),
		Vector3.new(Grid - 0.1, Grid - 0.1, Grid - 0.1),
		overlapParams
	)

	for _, part in ipairs(parts) do
		if part:IsA("BasePart") and part.CanCollide then
			return true
		end
	end

	return false
end

local function hidePreview()
	-- At once: a hidden ghost is parked far below the world, and an outline
	-- fading on the way there would streak across the screen.
	WorldFeedback.release("place", true)
	if preview then
		preview.CFrame = HIDDEN_CFRAME
	end
	lastCellX, lastCellY, lastCellZ = nil, nil, nil
	lastCanPlace = false
	lastCellBlocked = true
end

local function updatePreview()
	camera = Workspace.CurrentCamera
	if not camera then
		hidePreview()
		return
	end

	-- A build ghost floating under an open menu looks like a bug.
	if MenuState.isAnyOpen() then
		hidePreview()
		return
	end

	local slotData = getEquippedSlotData()
	if not slotData then
		hidePreview()
		return
	end

	local part = ensurePreview(slotData.name)

	local mx, my = mouse.X, mouse.Y
	if not mx or not my or (mx == 0 and my == 0) then
		local size = camera.ViewportSize
		mx, my = size.X * 0.5, size.Y * 0.5
	end

	local ray = camera:ScreenPointToRay(mx, my)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * MAX_RAY_DISTANCE, raycastParams)
	if not result then
		hidePreview()
		return
	end

	local anchoredPos = result.Position + result.Normal.Unit * (Grid * 0.5 + 0.001)
	local ix, iy, iz = worldPosToCellIndices(anchoredPos)

	local worldCenter = cellIndicesToWorldPos(ix, iy, iz)

	-- The overlap query is the expensive half of this function, and the cell
	-- only changes when the player aims somewhere new - a small fraction of
	-- thirty checks a second. The character test is not cached with it: the
	-- player can walk into or out of the cell without moving the cursor.
	if ix ~= lastCellX or iy ~= lastCellY or iz ~= lastCellZ then
		lastCellX, lastCellY, lastCellZ = ix, iy, iz
		lastCellBlocked = isCellBlocked(worldCenter)
		part.CFrame = CFrame.new(worldCenter)
	end

	lastCanPlace = not lastCellBlocked and not overlapsCharacter(worldCenter)
	setPreviewState(lastCanPlace)
end

-- InventoryClient publishes the selected hotbar slot here. Read rather than
-- pushed, so this script does not have to exist before that one runs.
local EQUIPPED_SLOT_ATTRIBUTE = "EquippedSlot"

local function readEquippedSlot()
	local slot = player:GetAttribute(EQUIPPED_SLOT_ATTRIBUTE)
	equippedSlot = if type(slot) == "number" then slot else nil
	destroyPreview()
end

readEquippedSlot()
player:GetAttributeChangedSignal(EQUIPPED_SLOT_ATTRIBUTE):Connect(readEquippedSlot)

player.CharacterAdded:Connect(function()
	task.defer(updateFilters)
end)

if RequestFullInv and RequestFullInv:IsA("RemoteEvent") then
	RequestFullInv:FireServer()
end

-- The mirror hands back the same table every time and updates it in place, so
-- holding the reference keeps this current without copying the bag on every
-- change.
localInventory = InventoryMirror.get()

InventoryMirror.onChanged(function(snapshot)
	localInventory = snapshot
	if not getEquippedSlotData() then
		hidePreview()
	end
end)

--[[
	A block dropping into place: a ghost of the block that starts slightly large
	and settles to size. The real block is a server part that simply appears, so
	this is what gives placement its sense of impact.
]]
local function playPlacementEffect(itemName, worldCenter)
	local ghost = clonePreviewTemplate(itemName)
	ghost.Name = "PlacementPop"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.CastShadow = false
	ghost.Size = Vector3.new(Grid, Grid, Grid) * 1.22
	ghost.CFrame = CFrame.new(worldCenter)
	ghost.Parent = Workspace

	setPreviewTransparency(ghost, 0.35)

	local info = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	TweenService:Create(ghost, info, {
		Size = Vector3.new(Grid, Grid, Grid),
		Transparency = 1,
	}):Play()

	-- The faces have to fade with it, or the pop leaves a fully textured cube
	-- hanging in the air for a sixth of a second after the part has gone.
	for _, child in ipairs(ghost:GetDescendants()) do
		if child:IsA("Decal") or child:IsA("Texture") then
			TweenService:Create(child, info, { Transparency = 1 }):Play()
		end
	end

	Debris:AddItem(ghost, 0.4)

	-- A green edge on the settling ghost: "that one is yours now".
	WorldFeedback.flash(ghost, "Confirm", 0.3)

	-- Workbenches are furniture, not masonry, so they get their own thunk;
	-- everything else uses its material group.
	local def = ItemDefinitions[itemName]
	if def and def.classification == "Workbench" then
		Sounds.playAt("place.station", worldCenter)
	else
		Sounds.playBlock("place", itemName, worldCenter)
	end
end

-- The cell the last request was fired at, so the confirmation can be played
-- where the block actually landed rather than wherever the cursor has drifted to.
local pendingItemName = nil
local pendingCenter = nil

-- A held click into a wall of refusals should not fill the feed with one line.
local REFUSAL_REPEAT_SECONDS = 2
local lastRefusal, lastRefusalAt = nil, 0

local function reportRefusal(message)
	if type(message) ~= "string" or message == "" then
		return
	end

	local now = os.clock()
	if message == lastRefusal and now - lastRefusalAt < REFUSAL_REPEAT_SECONDS then
		return
	end
	lastRefusal, lastRefusalAt = message, now

	Feedback.show(message, "bad")
end

if PlacementResult and PlacementResult:IsA("RemoteEvent") then
	PlacementResult.OnClientEvent:Connect(function(success, message)
		resultFlashSuccess = success == true
		resultFlashUntil = os.clock() + 0.18
		setPreviewState(resultFlashSuccess)

		if success and pendingItemName and pendingCenter then
			playPlacementEffect(pendingItemName, pendingCenter)
		elseif not success then
			Sounds.play("ui.denied")
			-- The reason was always sent and never shown; a build limit that
			-- only says "no" looks exactly like a broken preview.
			reportRefusal(message)
			WorldFeedback.flash(preview, "Invalid")
		end

		pendingItemName, pendingCenter = nil, nil
	end)
end

RunService.RenderStepped:Connect(function(dt)
	raycastAccumulator += dt
	if raycastAccumulator < RAYCAST_INTERVAL then
		return
	end
	raycastAccumulator = 0

	updatePreview()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if MenuState.isAnyOpen() then
		return
	end

	local slotData = getEquippedSlotData()
	if not lastCellX or not slotData then
		return
	end

	if not lastCanPlace then
		-- Say no out loud rather than silently ignoring the click.
		Sounds.play("ui.denied")
		WorldFeedback.flash(preview, "Invalid")
		return
	end

	pendingItemName = slotData.name
	pendingCenter = cellIndicesToWorldPos(lastCellX, lastCellY, lastCellZ)

	RequestPlaceBlock:FireServer(equippedSlot, lastCellX, lastCellY, lastCellZ)
end)
