--[[
	ItemPreview

	3D item renders for the inventory: one hover tooltip, plus small live views
	inside the slots themselves.

		ItemPreview.mount(inventoryGui)
		ItemPreview.show("GoldPickaxe", slotFrame)
		ItemPreview.hide()
		ItemPreview.fillSlot(icon, "GoldPickaxe")

	A ViewportFrame is a second render pass per frame, so the tooltip is a
	single one that exists only while the cursor is on a filled slot, and slot
	views are capped by LiveSlotLimit and released the moment a slot is hidden.
	Nothing animates - the camera is placed once per show and then left alone.

	Prepared models are cached because hovering along a row would otherwise
	re-clone and re-pose per slot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local ItemModels = require(script.Parent:WaitForChild("ItemModels"))
local WeaponClasses = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponClasses"))

local ItemPreview = {}

-- No height: the description wraps to whatever it is and AutomaticSize grows
-- the panel. `estimate` is only used on the first frame of the first hover,
-- before there is a measured height to place against.
local PANEL = {
	width = 224,
	viewHeight = 104,
	nameHeight = 20,
	gap = 10,
	edge = 10,
	estimate = 200,
}

-- Sized to a full bag of distinct items: a smaller cache would evict models
-- the same inventory open is about to clone again.
local CACHE_LIMIT = 48

-- Slack on the camera distance once the silhouette is measured. 1 puts the
-- item's edges exactly on the frame's.
local PANEL_MARGIN = 1.1
local SLOT_MARGIN = 0.97

-- Used only before a viewport has been laid out and can report its own shape.
local PANEL_ASPECT = 2
local SLOT_ASPECT = 1

local panel: Frame? = nil
local viewport: ViewportFrame? = nil
local camera: Camera? = nil
local nameLabel: TextLabel? = nil
local descriptionLabel: TextLabel? = nil

-- itemName -> prepared Model, unparented while not shown.
local prepared: { [string]: Model } = {}
local order: { string } = {}

local shownItem: string? = nil

-- ---------------------------------------------------------------------------
-- Building the panel
-- ---------------------------------------------------------------------------

-- Safe to call more than once. Everything below quietly does nothing until it
-- has run, so a UI that never mounts a preview simply never gets one.
function ItemPreview.mount(parent: Instance)
	if panel then
		return
	end

	local frame = Instance.new("Frame")
	frame.Name = "ItemPreview"
	frame.Size = UDim2.fromOffset(PANEL.width, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.Color.Panel
	frame.BackgroundTransparency = Theme.Transparency.Panel
	frame.BorderSizePixel = 0
	frame.Visible = false
	-- Above the slots, below the drag icon at 101.
	frame.ZIndex = 60
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Stroke
	stroke.Thickness = 1
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PANEL.edge)
	padding.PaddingBottom = UDim.new(0, PANEL.edge)
	padding.PaddingLeft = UDim.new(0, PANEL.edge)
	padding.PaddingRight = UDim.new(0, PANEL.edge)
	padding.Parent = frame

	-- Stacked, not positioned: the description's height is its text's, so
	-- everything under it moves when the text does.
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	local view = Instance.new("ViewportFrame")
	view.Name = "View"
	view.LayoutOrder = 1
	view.Size = UDim2.new(1, 0, 0, PANEL.viewHeight)
	view.BackgroundColor3 = Theme.Color.Backdrop
	view.BackgroundTransparency = 0.35
	view.BorderSizePixel = 0
	view.ZIndex = frame.ZIndex + 1

	-- A catalogue photograph, not a scene: high ambient and a soft key, so no
	-- part of an item is in shadow while somebody is identifying it.
	view.Ambient = Color3.fromRGB(150, 150, 150)
	view.LightColor = Color3.fromRGB(255, 255, 255)
	view.LightDirection = Vector3.new(-0.6, -1, -0.4)
	view.Parent = frame

	local cam = Instance.new("Camera")
	cam.FieldOfView = 45
	cam.Parent = view
	view.CurrentCamera = cam

	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.LayoutOrder = 2
	label.Size = UDim2.new(1, 0, 0, PANEL.nameHeight)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.BodyBold
	label.TextSize = Theme.TextSize.Body
	label.TextColor3 = Theme.Color.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.ZIndex = frame.ZIndex + 1
	label.Parent = frame

	-- Hidden when an item has no description: UIListLayout skips invisible
	-- children, so the panel closes up instead of leaving a gap.
	local description = Instance.new("TextLabel")
	description.Name = "Description"
	description.LayoutOrder = 3
	description.Size = UDim2.new(1, 0, 0, 0)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.BackgroundTransparency = 1
	description.FontFace = Theme.Fonts.Body
	description.TextSize = Theme.TextSize.Small
	description.TextColor3 = Theme.Color.TextDim
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextWrapped = true
	description.Text = ""
	description.Visible = false
	description.ZIndex = frame.ZIndex + 1
	description.Parent = frame

	panel = frame
	viewport = view
	camera = cam
	nameLabel = label
	descriptionLabel = description
end

-- ---------------------------------------------------------------------------
-- Preparing a model
-- ---------------------------------------------------------------------------

local function remember(itemName: string, model: Model)
	prepared[itemName] = model
	table.insert(order, itemName)

	while #order > CACHE_LIMIT do
		local oldest = table.remove(order, 1)

		-- Never evict what is on screen; the panel is holding that model.
		if oldest == shownItem then
			table.insert(order, oldest)
			break
		end

		if oldest and oldest ~= itemName then
			local stale = prepared[oldest]
			prepared[oldest] = nil
			if stale then
				stale:Destroy()
			end
		end
	end
end

-- The world-aligned box around a set of parts. GetBoundingBox is oriented to
-- the pivot and GetExtentsSize gives no centre; framing needs both, in the
-- camera's axes.
local function worldBounds(parts: { BasePart }): (Vector3, Vector3)
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = -min

	for _, part in ipairs(parts) do
		local half = part.Size * 0.5
		local cf = part.CFrame

		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					local corner = cf * Vector3.new(half.X * x, half.Y * y, half.Z * z)
					min = min:Min(corner)
					max = max:Max(corner)
				end
			end
		end
	end

	return (min + max) * 0.5, max - min
end

--[[
	Presentation, chosen by shape so nobody has to classify the catalogue by
	hand: an item whose longest side is under BLOCK_RATIO times its shortest is
	a "block" (three-quarter cube view), the rest are "tools" (laid along the
	diagonal, head up and right, broad side to camera - a blade seen edge-on is
	a line, and a line is not identifiable). Overridable per item with
	`iconPose`, and nudged with `iconAngle`.
]]
local BLOCK_RATIO = 1.5
local BLOCK_YAW = 35
local BLOCK_PITCH = 24

-- Where a tool's long axis points on screen, and which way its broad side
-- faces. The slight Z on the long target stops it reading as a flat sticker.
local TOOL_LONG = Vector3.new(0.58, 0.78, 0.24)
local TOOL_FACE = Vector3.zAxis

-- Orthonormal frame from a primary axis and a hint for a second, with the hint
-- squared up rather than trusted. Returned as X, Y, Z for CFrame.fromMatrix,
-- where Z is the BACK vector.
local function basis(primary: Vector3, faceHint: Vector3): (Vector3, Vector3, Vector3)
	local up = primary.Unit

	local face = faceHint - up * up:Dot(faceHint)
	if face.Magnitude < 1e-3 then
		-- The hint was parallel to the primary and says nothing; any
		-- perpendicular will do.
		face = if math.abs(up.Y) < 0.9 then up:Cross(Vector3.yAxis) else up:Cross(Vector3.xAxis)
	end

	face = face.Unit
	return up:Cross(face), up, face
end

-- Baked into the model rather than applied as a camera angle, so the tooltip
-- and the slot show an identical pose.
local function poseModel(model: Model, parts: { BasePart }, itemName: string, handle: BasePart?)
	local centre, size = worldBounds(parts)

	local definition = ItemDefinitions[itemName]
	local axes = { { Vector3.xAxis, size.X }, { Vector3.yAxis, size.Y }, { Vector3.zAxis, size.Z } }
	table.sort(axes, function(a, b)
		return a[2] > b[2]
	end)

	local longest, shortest = axes[1], axes[3]
	local ratio = if shortest[2] > 1e-3 then longest[2] / shortest[2] else math.huge

	local kind = definition and definition.iconPose
	if kind ~= "tool" and kind ~= "block" then
		kind = if ratio < BLOCK_RATIO then "block" else "tool"
	end

	local rotation

	if kind == "block" then
		rotation = CFrame.Angles(math.rad(BLOCK_PITCH), math.rad(BLOCK_YAW), 0)
	else
		local along = longest[1]

		-- The handle is the end you hold, so the axis points away from it -
		-- that is what puts the business end up and to the right. Without one,
		-- the model's own +axis is the guess `iconAngle` exists to correct.
		if handle then
			local offset = handle.Position - centre
			if offset:Dot(along) > 0 then
				along = -along
			end
		end

		local modelX, modelY, modelZ = basis(along, shortest[1])
		local targetX, targetY, targetZ = basis(TOOL_LONG, TOOL_FACE)

		local from = CFrame.fromMatrix(Vector3.zero, modelX, modelY, modelZ)
		local to = CFrame.fromMatrix(Vector3.zero, targetX, targetY, targetZ)

		rotation = to * from:Inverse()
	end

	-- Per-item correction in degrees, applied after the rule so it reads as a
	-- nudge rather than a replacement.
	local nudge = definition and definition.iconAngle
	if typeof(nudge) == "Vector3" then
		rotation = rotation * CFrame.Angles(math.rad(nudge.X), math.rad(nudge.Y), math.rad(nudge.Z))
	end

	model:PivotTo(CFrame.new(centre) * rotation)
end

--[[
	A display copy of an item's model: shape and colour only, anchored, posed.
	Scripts would run inside the viewport and sounds would play from a menu, so
	those go.

	nil for the items with no model at all - most of the catalogue.
]]
local function prepare(itemName: string): Model?
	local cached = prepared[itemName]
	if cached then
		return cached
	end

	local source = ItemModels.find(itemName)
	if not source then
		return nil
	end

	local clone = source:Clone()

	for _, descendant in ipairs(clone:GetDescendants()) do
		if
			descendant:IsA("BaseScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("Sound")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
		then
			descendant:Destroy()
		end
	end

	-- Rebuilt as a plain Model of anchored parts: the source may be a Tool, a
	-- Model or a bare BasePart, and the caller should not have to care.
	local model = Instance.new("Model")
	model.Name = itemName

	local parts: { BasePart } = {}
	local handle: BasePart? = nil

	if clone:IsA("BasePart") then
		parts[1] = clone
	else
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)

				-- Decides which way up a tool is presented. Named by convention
				-- here and by requirement in ToolFactory.
				if descendant.Name == "Handle" then
					handle = descendant
				end
			end
		end
	end

	if #parts == 0 then
		model:Destroy()
		clone:Destroy()
		return nil
	end

	for _, part in ipairs(parts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Parent = model
	end

	-- An invisible anchor at the centre, made the pivot, so PivotTo is a clean
	-- rotation in place rather than a swing around whichever part came first.
	local centre = worldBounds(parts)

	local anchor = Instance.new("Part")
	anchor.Name = "Pivot"
	anchor.Size = Vector3.new(0.05, 0.05, 0.05)
	anchor.CFrame = CFrame.new(centre)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = model

	model.PrimaryPart = anchor

	-- A bare BasePart source IS parts[1] and has just been reparented into the
	-- model; destroying it here would destroy the preview.
	if clone ~= parts[1] then
		clone:Destroy()
	end

	poseModel(model, parts, itemName, handle)

	remember(itemName, model)
	return model
end

-- ---------------------------------------------------------------------------
-- Showing it
-- ---------------------------------------------------------------------------

--[[
	Framed to the item's actual silhouette rather than a bounding sphere - the
	model is already turned to face the camera, so the box's width and height
	are what will be on screen. FieldOfView is the VERTICAL angle, so the
	horizontal one is derived through the aspect ratio or a wide viewport crops
	a long item.
]]
local function frameCamera(cam: Camera, model: Model, aspect: number, margin: number)
	local parts = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "Pivot" then
			table.insert(parts, descendant)
		end
	end

	if #parts == 0 then
		return
	end

	local centre, size = worldBounds(parts)

	local vertical = math.rad(cam.FieldOfView) * 0.5
	local horizontal = math.atan(math.tan(vertical) * math.max(aspect, 0.01))

	local distance = math.max(
		(size.Y * 0.5) / math.tan(vertical),
		(size.X * 0.5) / math.tan(horizontal)
	) * margin

	-- Half the depth on top, or a thick model pokes through the near plane.
	distance += size.Z * 0.5

	cam.CFrame = CFrame.lookAt(centre + Vector3.zAxis * distance, centre)
end

local function frameModel(model: Model)
	if camera and viewport then
		local size = viewport.AbsoluteSize
		local aspect = if size.Y > 0 then size.X / size.Y else PANEL_ASPECT

		frameCamera(camera, model, aspect, PANEL_MARGIN)
	end
end

-- Under the slot by preference - the eye is already there and reads downward -
-- flipping above when there is no room, since the hotbar is at the bottom.
local function positionNear(slot: GuiObject)
	local frame = panel
	local host = frame and frame.Parent

	if not (frame and host and host:IsA("GuiBase2d")) then
		return
	end

	local hostPosition = host.AbsolutePosition
	local hostSize = host.AbsoluteSize

	local slotPosition = slot.AbsolutePosition - hostPosition
	local slotSize = slot.AbsoluteSize

	local height = frame.AbsoluteSize.Y
	if height <= 0 then
		height = PANEL.estimate
	end

	local x = slotPosition.X + slotSize.X * 0.5 - PANEL.width * 0.5
	local below = slotPosition.Y + slotSize.Y + PANEL.gap

	local y = below
	if below + height > hostSize.Y - PANEL.gap then
		y = slotPosition.Y - height - PANEL.gap
	end

	x = math.clamp(x, PANEL.gap, math.max(PANEL.gap, hostSize.X - PANEL.width - PANEL.gap))
	y = math.clamp(y, PANEL.gap, math.max(PANEL.gap, hostSize.Y - height - PANEL.gap))

	frame.Position = UDim2.fromOffset(x, y)
end

-- Returns false for an item with no model, which is not a failure: a preview
-- panel containing an empty box is worse than no panel.
function ItemPreview.show(itemName: string?, slot: GuiObject?): boolean
	if not (panel and viewport and nameLabel and descriptionLabel) then
		return false
	end

	if type(itemName) ~= "string" or not slot then
		return false
	end

	if shownItem ~= itemName then
		local model = prepare(itemName)
		if not model then
			ItemPreview.hide()
			return false
		end

		-- The outgoing model goes back to the cache; unparenting is what stops
		-- it rendering.
		local previous = if shownItem then prepared[shownItem] else nil
		if previous and previous.Parent == viewport then
			previous.Parent = nil
		end

		model.Parent = viewport
		frameModel(model)

		local definition = ItemDefinitions[itemName]
		nameLabel.Text = itemName
		nameLabel.TextColor3 = Theme.rarityColor(definition and definition.rarity or "Common")

		-- A weapon's class line ("Sword -> Katana") heads its description.
		descriptionLabel.Text = WeaponClasses.description(definition)
		descriptionLabel.Visible = descriptionLabel.Text ~= ""

		shownItem = itemName
	end

	positionNear(slot)
	panel.Visible = true

	-- Placed again after the layout resolves: the first call used the previous
	-- item's height, and only doing the second would make the panel jump.
	local target = itemName
	task.defer(function()
		if shownItem == target and panel and panel.Visible and slot.Parent then
			positionNear(slot)
		end
	end)

	return true
end

-- Both halves matter: a hidden ViewportFrame with a model still in it is not
-- guaranteed to cost nothing.
function ItemPreview.hide()
	if not panel then
		return
	end

	panel.Visible = false

	local model = if shownItem then prepared[shownItem] else nil
	if model and model.Parent == viewport then
		model.Parent = nil
	end

	shownItem = nil
end

function ItemPreview.canShow(itemName: string?): boolean
	return ItemModels.find(itemName) ~= nil
end

-- ---------------------------------------------------------------------------
-- Live slots
-- ---------------------------------------------------------------------------

--[[
	The inventory's first choice for a slot holding an item with a model: a
	small ViewportFrame posed exactly like the hover panel. It is first because
	it is the only render whose camera this project controls - Roblox will
	render a published model's thumbnail for free, but at an angle that cannot
	be edited and that leaves these tools unidentifiable. ItemThumbnails is the
	fallback for items with no model at all.

	It is not free: each view is a render pass per frame. Two things bound it -
	the caller releases the slots it hides (a closed inventory costs the hotbar
	and nothing else), and this cap. 9 gives live views to the hotbar only; 0
	turns them off, leaving the on-demand hover preview.
]]
ItemPreview.LiveSlotLimit = 42

-- icon (ImageLabel) -> { view = ViewportFrame, item = string, dying = RBXScriptConnection }
local liveSlots: { [Instance]: any } = {}
local liveCount = 0

local function releaseSlotInternal(icon: Instance)
	local entry = liveSlots[icon]
	if not entry then
		return
	end

	liveSlots[icon] = nil
	liveCount -= 1

	entry.dying:Disconnect()

	-- A slot's model is its own copy, so the viewport takes it with it.
	entry.view:Destroy()
end

--[[
	Puts a live view of `itemName` inside `icon`, if there is room. False means
	the caller should fall back to a flat image - no model, or the cap is full.

	Re-calling for the same icon and item leaves the existing view alone, so a
	redraw of an unchanged slot costs nothing.
]]
function ItemPreview.fillSlot(icon: Instance?, itemName: string?): boolean
	if typeof(icon) ~= "Instance" or not icon:IsA("GuiObject") then
		return false
	end

	local existing = liveSlots[icon]
	if existing and existing.item == itemName then
		return true
	end

	releaseSlotInternal(icon)

	if type(itemName) ~= "string" or itemName == "" then
		return false
	end

	if liveCount >= ItemPreview.LiveSlotLimit then
		return false
	end

	local model = prepare(itemName)
	if not model then
		return false
	end

	local view = Instance.new("ViewportFrame")
	view.Name = "LiveIcon"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.BorderSizePixel = 0
	view.ZIndex = icon.ZIndex + 1
	view.Ambient = Color3.fromRGB(150, 150, 150)
	view.LightColor = Color3.fromRGB(255, 255, 255)
	view.LightDirection = Vector3.new(-0.6, -1, -0.4)

	local cam = Instance.new("Camera")
	cam.FieldOfView = 45
	cam.Parent = view
	view.CurrentCamera = cam

	-- Its own copy: the shared prepared model can only be parented once, and
	-- the hover panel wants it too.
	local copy = model:Clone()
	copy.Parent = view

	-- The icon has been laid out by now, so its aspect is real rather than
	-- assumed, which matters for tiles that are not square.
	local shape = icon.AbsoluteSize
	local aspect = if shape.Y > 0 then shape.X / shape.Y else SLOT_ASPECT

	frameCamera(cam, copy, aspect, SLOT_MARGIN)

	view.Parent = icon

	-- A slot destroyed without a release would otherwise hold its share of the
	-- cap for the rest of the session.
	local dying
	dying = icon.Destroying:Connect(function()
		releaseSlotInternal(icon)
	end)

	liveSlots[icon] = { view = view, item = itemName, dying = dying }
	liveCount += 1
	return true
end

-- Safe on a slot that never had one, which is nearly all of them.
function ItemPreview.releaseSlot(icon: Instance?)
	if typeof(icon) == "Instance" then
		releaseSlotInternal(icon)
	end
end

return ItemPreview
