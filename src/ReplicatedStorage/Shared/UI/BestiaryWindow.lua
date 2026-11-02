--[[
	BestiaryWindow

	The Tab menu's BESTIARY page: every creature in the game as a tile with its
	own model in a viewport, black until the player has met one. Hovering a
	tile plays the creature's own walk (Shared.Enemies.CreatureRigs, the same
	procedural animation CreatureFX runs in the world) or, for the creatures
	without a jointed rig, a hop; the panel on the right says what it is, where
	it lives and how many the player has killed.

		local bestiary = BestiaryWindow.new(parent, onBack)   a MenuWindow

	What has been met is ServerScriptService.Bestiary's, read through
	Shared.UI.BestiaryState.

	THE MODELS ARE BUILT ON FIRST OPEN, a few a frame, not when the menu is
	made: there are about fifty and some are big, and most sessions never open
	this page. Only the hovered tile animates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Theme = require(script.Parent:WaitForChild("Theme"))
local MenuWindow = require(script.Parent:WaitForChild("MenuWindow"))
local BestiaryState = require(script.Parent:WaitForChild("BestiaryState"))
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local CreatureRigs = require(Shared.Enemies:WaitForChild("CreatureRigs"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))

local GOLD = Theme.PixelColor.Selection
local PALETTE = MenuWindow.Palette

-- Each creature's tile is washed in its home biome's colour once it has
-- been met; bosses in gold. A creature from no biome gets a colour of its own
-- from its name, so it is at least always the same one.
local BIOME_TINT = {
	Plains = Color3.fromRGB(96, 170, 84),
	Desert = Color3.fromRGB(214, 172, 96),
	Swamp = Color3.fromRGB(110, 140, 64),
	Snow = Color3.fromRGB(150, 196, 230),
	Corruption = Color3.fromRGB(140, 84, 200),
	Crimson = Color3.fromRGB(206, 64, 72),
	Hallow = Color3.fromRGB(236, 140, 214),
}

local function tintFor(name: string, def): Color3
	if def.boss then
		return GOLD
	end
	local biome = type(def.spawnBiomes) == "table" and def.spawnBiomes[1]
	if biome and BIOME_TINT[biome] then
		return BIOME_TINT[biome]
	end
	local hash = 0
	for index = 1, #name do
		hash = (hash * 31 + string.byte(name, index)) % 360
	end
	return Color3.fromHSV(hash / 360, 0.55, 0.85)
end

local WIDTH, HEIGHT = 800, 560
local TILE_W, TILE_H = 116, 136
local TILE_GAP = 8
local COLUMNS = 4
local GRID_PAD = 2
local GRID_WIDTH = COLUMNS * TILE_W + (COLUMNS - 1) * TILE_GAP + GRID_PAD * 2 + 8
local VIEW_HEIGHT = 100
local FOV = 30
local BUILD_PER_FRAME = 3

local BestiaryWindow = {}

local function text(parent, font, size, color): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = ""
	label.Parent = parent
	return label
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- The creature's model, ready for a viewport: no scripts or sounds, the body
-- anchored and the limbs free to be posed by their joints.
local function cloneModel(def): Model?
	local folder = ReplicatedStorage:FindFirstChild(EnemyConfig.AssetsFolder)
	local source = folder and EnemyConfig.findAsset(folder, def.asset or "")
	if not source then
		return nil
	end

	local copy = source:Clone()
	local model: Model
	if copy:IsA("Model") then
		model = copy
	elseif copy:IsA("BasePart") then
		model = Instance.new("Model")
		copy.Parent = model
		model.PrimaryPart = copy
	else
		copy:Destroy()
		return nil
	end

	local biggest, volume = nil, -1
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BaseScript") or item:IsA("Sound") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = false
			local size = item.Size.X * item.Size.Y * item.Size.Z
			if size > volume then
				biggest, volume = item, size
			end
		end
	end
	model.PrimaryPart = model.PrimaryPart or biggest
	if not model.PrimaryPart then
		model:Destroy()
		return nil
	end
	model.PrimaryPart.Anchored = true
	model:PivotTo(CFrame.new())
	return model
end

-- A camera on the creature's front, a little to one side and above.
local function frame(camera: Camera, model: Model)
	local box, size = model:GetBoundingBox()
	local radius = size.Magnitude * 0.5
	local distance = radius / math.tan(math.rad(FOV * 0.5)) * 1.02
	local look = model:GetPivot().LookVector
	local side = CFrame.Angles(0, math.rad(32), 0):VectorToWorldSpace(Vector3.new(look.X, 0, look.Z).Unit)
	local eye = box.Position + side * distance + Vector3.new(0, radius * 0.35, 0)
	camera.CFrame = CFrame.lookAt(eye, box.Position)
end

local function habitat(name, def): string
	if def.boss then
		return "Boss"
	end
	if type(def.spawnBiomes) == "table" and #def.spawnBiomes > 0 then
		return table.concat(def.spawnBiomes, ", ")
	end
	return "Rare"
end

function BestiaryWindow.new(parent: Instance, onBack: () -> ())
	local window = MenuWindow.new(parent, "BESTIARY", WIDTH, HEIGHT, onBack)
	local body = window.body

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(0, GRID_WIDTH, 1, 0)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 3
	grid.ScrollBarImageColor3 = PALETTE.Line
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = body

	-- Room for the tiles' outlines, which a ScrollingFrame would cut.
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, GRID_PAD)
	padding.PaddingTop = UDim.new(0, GRID_PAD)
	padding.PaddingBottom = UDim.new(0, GRID_PAD)
	padding.Parent = grid

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	layout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	-- The details of whatever is hovered.
	local info = Instance.new("Frame")
	info.Name = "Details"
	info.AnchorPoint = Vector2.new(1, 0)
	info.Position = UDim2.fromScale(1, 0)
	info.Size = UDim2.new(1, -(GRID_WIDTH + 16), 1, 0)
	info.BackgroundColor3 = PALETTE.Raised
	info.BackgroundTransparency = 0
	info.BorderSizePixel = 0
	info.Parent = body
	corner(info, 6)

	local infoName = text(info, Theme.Fonts.Heading, Theme.TextSize.Heading, Theme.Color.Text)
	infoName.Position = UDim2.fromOffset(14, 34)
	infoName.Size = UDim2.new(1, -28, 0, 52)
	infoName.TextYAlignment = Enum.TextYAlignment.Top

	local infoTag = text(info, Theme.Fonts.Heading, Theme.TextSize.Small, GOLD)
	infoTag.Position = UDim2.fromOffset(14, 14)
	infoTag.Size = UDim2.new(1, -28, 0, 16)

	local infoBody = text(info, Theme.Fonts.Body, Theme.TextSize.Body, Theme.Color.TextDim)
	infoBody.Position = UDim2.fromOffset(14, 96)
	infoBody.Size = UDim2.new(1, -28, 1, -110)
	infoBody.TextYAlignment = Enum.TextYAlignment.Top
	infoBody.RichText = true

	local tiles = {}
	local built = false
	local hovered = nil
	local animating = nil

	local function showInfo(tile)
		if not tile then
			infoName.Text = "Creatures"
			infoTag.Text = ""
			infoBody.Text = "Hover a creature to see it move.\n\nGet close to a creature to add it here. Kill one to start its tally."
			return
		end
		local record = BestiaryState.get()
		local kills = record[tile.name]
		local def = tile.def
		if kills == nil then
			infoName.Text = "???"
			infoTag.Text = if def.boss then "BOSS" else ""
			infoTag.TextColor3 = GOLD
			infoBody.Text = "Not discovered yet.\n\nGet close to one to add it to your bestiary."
			return
		end
		-- Where it lives, in its biome's colour, over its name.
		infoName.Text = def.displayName or tile.name
		infoTag.Text = if def.boss then "BOSS" else string.upper(habitat(tile.name, def))
		infoTag.TextColor3 = tile.tint
		infoBody.Text = string.format(
			'<font color="#EEEEEE">%d</font> slain\n<font color="#EEEEEE">%d</font> health',
			kills, def.health or 0
		)
	end

	local function stopAnimating()
		local tile = animating
		animating = nil
		if not tile then
			return
		end
		if tile.connection then
			tile.connection:Disconnect()
			tile.connection = nil
		end
		if tile.model then
			tile.model:PivotTo(CFrame.new())
			if tile.rig then
				for _, joint in pairs(tile.rig.joints) do
					joint.Transform = CFrame.identity
				end
			end
		end
	end

	local function animate(tile)
		stopAnimating()
		if not tile.model then
			return
		end
		animating = tile
		local t = 0
		local height = tile.height
		tile.connection = RunService.RenderStepped:Connect(function(dt)
			t += dt
			-- A slow sway so the side of it shows, and for the creatures with
			-- no legs to move, a hop.
			local sway = CFrame.Angles(0, math.sin(t * 0.9) * 0.5, 0)
			if tile.rig then
				tile.model:PivotTo(sway)
				pcall(tile.rigDef.animate, tile.rig, {
					t = t,
					dt = dt,
					speed = tile.def.speed or 8,
					pose = "walk",
					blend = 1,
					elapsed = t,
				})
			else
				local hop = math.abs(math.sin(t * 3.2))
				tile.model:PivotTo(sway + Vector3.new(0, hop * height * 0.12, 0))
			end
		end)
	end

	local function paint(tile)
		local kills = BestiaryState.get()[tile.name]
		local met = kills ~= nil
		local raised = hovered == tile
		tile.view.ImageColor3 = if met then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
		tile.view.ImageTransparency = if met then 0 else 0.25
		tile.label.Text = if met then (tile.def.displayName or tile.name) else "???"
		tile.label.TextColor3 = if met then Theme.Color.Text else Theme.Color.TextFaint
		tile.kills.Text = if met and kills > 0 then "x" .. kills else ""
		-- A wash of the biome colour from the top, fading into the dark.
		local top = if met then PALETTE.Raised:Lerp(tile.tint, if raised then 0.55 else 0.38) else PALETTE.Raised
		tile.wash.Color = ColorSequence.new(top, PALETTE.Deep)
		tile.button.BackgroundTransparency = 0
		tile.stroke.Transparency = if raised then 0 elseif met or tile.def.boss then 0.35 else 0.6
		tile.stroke.Color = if raised then Theme.Color.Text elseif met or tile.def.boss then tile.tint else PALETTE.Line
		tile.kills.TextColor3 = if met then tile.tint:Lerp(Color3.new(1, 1, 1), 0.4) else Theme.Color.TextDim
	end

	local function addModel(tile)
		local model = cloneModel(tile.def)
		if not model then
			return
		end
		local world = Instance.new("WorldModel")
		world.Parent = tile.view
		model.Parent = world
		local camera = Instance.new("Camera")
		camera.FieldOfView = FOV
		camera.Parent = tile.view
		tile.view.CurrentCamera = camera
		frame(camera, model)
		tile.model = model
		tile.height = select(2, model:GetBoundingBox()).Y

		local rigDef = CreatureRigs[tile.name] or (tile.def.trait and CreatureRigs[tile.def.trait])
		if type(rigDef) == "table" and rigDef.animate then
			local joints = {}
			for _, joint in ipairs(model:GetDescendants()) do
				if joint:IsA("Motor6D") then
					joints[joint.Name] = joint
				end
			end
			local rig = { joints = joints, body = model.PrimaryPart, pose = "walk", poseAt = 0, last = Vector3.zero }
			if not rigDef.setup or pcall(rigDef.setup, rig) then
				tile.rig = rig
				tile.rigDef = rigDef
			end
		end
	end

	local function build()
		built = true
		for order, name in ipairs(BestiaryState.entries()) do
			local def = EnemyConfig.Definitions[name]
			local button = Instance.new("TextButton")
			button.Name = name
			button.LayoutOrder = order
			button.Text = ""
			button.AutoButtonColor = false
			button.BackgroundColor3 = Color3.new(1, 1, 1)
			button.BorderSizePixel = 0
			button.Parent = grid
			corner(button, 5)

			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Thickness = 1.5
			stroke.Parent = button

			local wash = Instance.new("UIGradient")
			wash.Rotation = 90
			wash.Parent = button

			local view = Instance.new("ViewportFrame")
			view.Name = "View"
			view.Size = UDim2.new(1, 0, 0, VIEW_HEIGHT)
			view.BackgroundTransparency = 1
			view.Ambient = Color3.fromRGB(150, 150, 150)
			view.LightColor = Color3.new(1, 1, 1)
			view.LightDirection = Vector3.new(-1, -1.5, -1)
			view.Parent = button

			local label = text(button, Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.Text)
			label.Position = UDim2.fromOffset(6, VIEW_HEIGHT)
			label.Size = UDim2.new(1, -12, 0, TILE_H - VIEW_HEIGHT - 4)
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center
			-- Shrunk to fit rather than wrapped mid-word.
			label.TextWrapped = false
			label.TextScaled = true
			local fit = Instance.new("UITextSizeConstraint")
			fit.MaxTextSize = Theme.TextSize.Small
			fit.MinTextSize = 8
			fit.Parent = label

			local kills = text(button, Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.TextDim)
			kills.AnchorPoint = Vector2.new(1, 0)
			kills.Position = UDim2.new(1, -6, 0, 4)
			kills.Size = UDim2.fromOffset(60, 16)
			kills.TextXAlignment = Enum.TextXAlignment.Right
			kills.ZIndex = 2

			if def.boss then
				local tag = text(button, Theme.Fonts.Heading, Theme.TextSize.Small, GOLD)
				tag.Position = UDim2.fromOffset(6, 4)
				tag.Size = UDim2.fromOffset(50, 16)
				tag.Text = "BOSS"
				tag.ZIndex = 2
			end

			-- `name` is the enemy key; `label` is what the tile shows.
			local tile = {
				name = name, def = def, button = button, stroke = stroke,
				view = view, label = label, kills = kills,
				wash = wash, tint = tintFor(name, def),
			}
			tiles[#tiles + 1] = tile

			button.MouseEnter:Connect(function()
				hovered = tile
				paint(tile)
				showInfo(tile)
				animate(tile)
				Sounds.play("ui.hover")
			end)
			button.MouseLeave:Connect(function()
				if hovered == tile then
					hovered = nil
					stopAnimating()
					showInfo(nil)
				end
				paint(tile)
			end)
			-- A tap on a touch screen has no hover: it selects instead.
			button.Activated:Connect(function()
				if hovered ~= tile then
					local was = hovered
					hovered = tile
					if was then
						paint(was)
					end
					paint(tile)
					showInfo(tile)
					animate(tile)
				end
			end)
		end

		-- Paint first so the grid is readable at once, then fill the views.
		for _, tile in ipairs(tiles) do
			paint(tile)
		end
		task.spawn(function()
			for index, tile in ipairs(tiles) do
				addModel(tile)
				if index % BUILD_PER_FRAME == 0 then
					RunService.RenderStepped:Wait()
				end
			end
		end)
	end

	local function refresh()
		local met, all = BestiaryState.counts()
		local slain = 0
		for _, kills in pairs(BestiaryState.get()) do
			slain += kills
		end
		window.subtitle.Text = string.format("%d / %d DISCOVERED   %d SLAIN", met, all, slain)
		for _, tile in ipairs(tiles) do
			paint(tile)
		end
		showInfo(hovered)
	end

	BestiaryState.Changed:Connect(refresh)
	showInfo(nil)
	refresh()

	local show = window.setVisible
	function window:setVisible(visible: boolean)
		if visible and not built then
			build()
			refresh()
		end
		if not visible then
			hovered = nil
			stopAnimating()
		end
		show(self, visible)
	end

	return window
end

return BestiaryWindow
