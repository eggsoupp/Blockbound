--[[
	DecorModels

	Builds a placeable decor piece (Shared.Building.DecorCatalog) for the
	world, the bag and the crafting window.

	  DecorModels.build(id, withEffects) -> Model or nil

	The look is the piece's voxel model: ReplicatedStorage.TerrainAssets.Decor
	.<id>, made in Studio from assets/voxel-decor (MagicaVoxel files built from
	the game's own block textures). Those models are place assets. Without
	one, a plain box the model's size stands in, so a missing model is
	obvious but harmless.

	Everything that is behaviour rather than look comes from
	Shared.Building.DecorShapes (generated with the models) and is added here,
	in the cell's frame: origin = middle of the cell floor, front +Z, which is
	also the model's pivot.

	Attributes the rest of the game reads:
	  NoCollide  StationService leaves the part non-solid
	  Swing      a door's leaf: DecorServer turns it about the Hinge part
	  LightFx    an emitter or light that follows a light's lit state
	  Glow       a glowing (Neon) voxel part; dimmed while a light is out

	`withEffects` adds flames and lights. An inventory icon is built without.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PixelFlipbooks = require(Shared:WaitForChild("Abilities"):WaitForChild("VFX"):WaitForChild("PixelFlipbooks"))
local DecorShapes = require(script.Parent:WaitForChild("DecorShapes"))

local DecorModels = {}

local FLAME = PixelFlipbooks.FireFlame.Texture

local function v3(list)
	return Vector3.new(list[1], list[2], list[3])
end

local function seq(points)
	local keys = {}
	for _, point in ipairs(points) do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keys)
end

-- An invisible, non-solid part (hinges, effect hosts).
local function marker(model, name, at)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(at)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p:SetAttribute("NoCollide", true)
	p.Parent = model
	return p
end

local function pointLight(parent, range, color)
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = color
	light.Range = range
	light.Brightness = 1.4
	light.Shadows = true
	light:SetAttribute("LightFx", true)
	light.Parent = parent
end

--[[
	A flame: the looping pixel FireFlame flipbook, a few cinders off it, and
	optionally a warm PointLight. `size` is the flame's height in studs.
]]
local function flame(model, at, size, lightRange)
	local host = marker(model, "FlameHost", at)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Flame"
	attachment.Parent = host

	local fire = Instance.new("ParticleEmitter")
	fire.Name = "Flame"
	fire.Texture = FLAME
	fire.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
	fire.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	fire.FlipbookFramerate = NumberRange.new(20, 26)
	fire.FlipbookStartRandom = true
	fire.Lifetime = NumberRange.new(0.9, 1.1)
	fire.Rate = 3
	fire.Speed = NumberRange.new(0)
	fire.LockedToPart = true
	fire.Size = seq({ { 0, size * 0.85 }, { 0.5, size }, { 1, size * 0.85 } })
	fire.Transparency = seq({ { 0, 1 }, { 0.2, 0 }, { 0.8, 0 }, { 1, 1 } })
	fire.LightEmission = 0.6
	fire.Brightness = 1.6
	-- Drawn a little toward the camera, so the parts around a flame (a
	-- fireplace's cheeks, a lantern's cap) never sort in front of it.
	fire.ZOffset = 0.6
	fire:SetAttribute("LightFx", true)
	fire.Parent = attachment

	local cinders = Instance.new("ParticleEmitter")
	cinders.Name = "Cinders"
	cinders.Texture = FLAME
	cinders.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
	cinders.FlipbookMode = Enum.ParticleFlipbookMode.Random
	cinders.Lifetime = NumberRange.new(0.8, 1.5)
	cinders.Rate = math.clamp(size * 2.5, 1.5, 8)
	cinders.Speed = NumberRange.new(size * 0.6, size * 1.4)
	cinders.SpreadAngle = Vector2.new(18, 18)
	cinders.EmissionDirection = Enum.NormalId.Top
	cinders.Acceleration = Vector3.new(0, 0.6, 0)
	cinders.Drag = 1
	cinders.Size = seq({ { 0, size * 0.09 }, { 1, 0 } })
	cinders.Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } })
	cinders.Color = ColorSequence.new(Color3.fromRGB(255, 196, 96), Color3.fromRGB(255, 96, 32))
	cinders.LightEmission = 1
	cinders.Brightness = 2
	cinders:SetAttribute("LightFx", true)
	cinders.Parent = attachment

	if lightRange then
		pointLight(host, lightRange, Color3.fromRGB(255, 170, 90))
	end
end

-- The authored voxel model, or a box its size.
local function body(id, shape)
	local assets = ReplicatedStorage:FindFirstChild("TerrainAssets")
	local folder = assets and assets:FindFirstChild("Decor")
	local template = folder and folder:FindFirstChild(id)
	if template and template:IsA("Model") then
		local model = template:Clone()
		model:PivotTo(CFrame.identity)
		return model
	end

	local model = Instance.new("Model")
	local size = if shape then v3(shape.size) else Vector3.new(4, 4, 4)
	local box = Instance.new("Part")
	box.Name = "Body"
	box.Size = size
	-- The footprint runs from the placed cell to the right and back.
	box.CFrame = CFrame.new((size.X - 4) / 2, size.Y / 2, -(size.Z - 4) / 2)
	box.Color = Color3.fromRGB(150, 112, 70)
	box.Material = Enum.Material.SmoothPlastic
	box.Anchored = true
	box.Parent = model
	model.WorldPivot = CFrame.identity
	return model
end

function DecorModels.has(id)
	return DecorShapes[id] ~= nil
end

-- A piece's footprint in grid cells, { w across, h up, d back }, or nil.
function DecorModels.cells(id)
	local shape = DecorShapes[id]
	return shape and shape.cells
end

-- What a piece's top is for standing things on, in studs, or nil.
function DecorModels.surface(id)
	local shape = DecorShapes[id]
	return shape and shape.surface
end

function DecorModels.build(id, withEffects)
	local shape = DecorShapes[id]
	if not shape then
		return nil
	end
	local model = body(id, shape)
	model.Name = id

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			if shape.collide == "none" then
				part:SetAttribute("NoCollide", true)
			end
			if part.Name == "Leaf" or part.Name == "LeafGlow" then
				part:SetAttribute("Swing", true)
			end
		end
	end

	if shape.hinge then
		marker(model, "Hinge", v3(shape.hinge))
	end

	if shape.seat then
		local seatPart = Instance.new("Seat")
		seatPart.Name = "Seat"
		seatPart.Size = v3(shape.seat.size)
		-- A Seat seats you looking along its own -Z: turned half round to
		-- look out of the +Z front. Its top sits at the cushion.
		seatPart.CFrame = CFrame.new(v3(shape.seat.at) - Vector3.new(0, seatPart.Size.Y / 2, 0))
			* CFrame.Angles(0, math.pi, 0)
		seatPart.Transparency = 1
		seatPart.Anchored = true
		seatPart:SetAttribute("NoCollide", true)
		seatPart.Parent = model
	end

	for _, rung in ipairs(shape.rungs or {}) do
		local p = Instance.new("Part")
		p.Name = "Rung"
		p.Size = Vector3.new(rung[4], rung[5], rung[6])
		p.CFrame = CFrame.new(rung[1], rung[2], rung[3])
		p.Transparency = 1
		p.Anchored = true
		p.Parent = model
	end

	if withEffects then
		for _, f in ipairs(shape.flames or {}) do
			flame(model, v3(f.at), f.size, f.range)
		end
		for _, g in ipairs(shape.glows or {}) do
			local host = marker(model, "LightHost", v3(g.at))
			pointLight(host, g.range, Color3.fromRGB(g.color[1], g.color[2], g.color[3]))
		end
	end

	model.WorldPivot = CFrame.identity
	return model
end

return DecorModels
