--[[
	ItemModels

	Where an item's 3D asset lives, for anything that wants to show one.

		local source = ItemModels.find("GoldPickaxe")

	There are two places a model can be, both already built and replicated for
	reasons unrelated to the UI: ReplicatedStorage.Tools[item] and
	ReplicatedStorage.TerrainAssets.Blocks[item]. So nothing extra has to be
	authored for an item to be previewable. Failing both, an item with a `look`
	in ItemDefinitions gets a simple model built from it (see buildFromLook).

	Nothing here is ever parented anywhere. `find` returns the live template and
	callers clone it - reparenting one would empty the folder the terrain builds
	from.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local ItemModels = {}

local cache: { [string]: Instance } = {}

local function toolsFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("Tools")
end

local function blocksFolder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("TerrainAssets")
	return assets and assets:FindFirstChild("Blocks")
end

-- ---------------------------------------------------------------------------
-- Models built from a description
-- ---------------------------------------------------------------------------

--[[
	The third place a model can come from: an item's own `look` in
	ItemDefinitions, for things with no art at all yet - the accessories.

		look = { shape = "Ring" | "Amulet", metal = Color3, gem = Color3 }

	Built once per item, from plain parts, and never parented: callers clone it
	like any other template. Rough on purpose - enough to tell a ring from an
	amulet and one gem from another, until real models exist. Dropping a real
	model into ReplicatedStorage.Tools under the item's name replaces this.
]]
local function lookPart(size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	part.Material = material
	return part
end

local RING_SEGMENTS = 16
local RING_RADIUS = 0.9

local function buildFromLook(itemName: string): Instance?
	local definition = ItemDefinitions[itemName]
	local look = definition and definition.look
	if type(look) ~= "table" then
		return nil
	end

	local metal = if typeof(look.metal) == "Color3" then look.metal else Color3.fromRGB(200, 200, 200)
	local gemColor = if typeof(look.gem) == "Color3" then look.gem else Color3.fromRGB(255, 255, 255)

	local model = Instance.new("Model")
	model.Name = itemName

	local gem = lookPart(Vector3.new(0.7, 0.7, 0.7), gemColor, Enum.Material.Neon)
	gem.Name = "Gem"
	gem.Shape = Enum.PartType.Ball

	if look.shape == "Ring" then
		-- A band of short segments around a circle in the XY plane, with the gem
		-- set on top of it.
		for index = 0, RING_SEGMENTS - 1 do
			local angle = index / RING_SEGMENTS * math.pi * 2
			local segment = lookPart(Vector3.new(0.42, 0.24, 0.3), metal, Enum.Material.Metal)
			segment.Name = "Band"
			segment.CFrame = CFrame.Angles(0, 0, angle) * CFrame.new(0, RING_RADIUS, 0)
			segment.Parent = model
		end

		gem.CFrame = CFrame.new(0, RING_RADIUS + 0.35, 0)
	else
		-- An amulet: a round plate facing forward, the gem in its middle, and a
		-- loop of chain above it.
		local plate = lookPart(Vector3.new(0.25, 1.6, 1.6), metal, Enum.Material.Metal)
		plate.Name = "Plate"
		plate.Shape = Enum.PartType.Cylinder
		-- A cylinder runs along its X axis; turned so the flat face points along Z.
		plate.CFrame = CFrame.Angles(0, math.rad(90), 0)
		plate.Parent = model

		for side = -1, 1, 2 do
			local chain = lookPart(Vector3.new(0.12, 1.0, 0.12), metal, Enum.Material.Metal)
			chain.Name = "Chain"
			chain.CFrame = CFrame.new(side * 0.3, 1.15, 0) * CFrame.Angles(0, 0, math.rad(side * 24))
			chain.Parent = model
		end

		gem.Size = Vector3.new(0.75, 0.75, 0.75)
		gem.CFrame = CFrame.new(0, 0, 0)
	end

	gem.Parent = model
	model.PrimaryPart = gem

	return model
end

-- Tools first: an item that is both holdable and placeable should preview as
-- the thing you hold, that being the version with a shape worth looking at.
function ItemModels.find(itemName: string?): Instance?
	if type(itemName) ~= "string" or itemName == "" then
		return nil
	end

	local cached = cache[itemName]
	if cached then
		return cached
	end

	local tools = toolsFolder()
	local found = tools and tools:FindFirstChild(itemName)

	if not found then
		local blocks = blocksFolder()
		found = blocks and blocks:FindFirstChild(itemName)
	end

	-- A placeable station's own model (TerrainAssets.Stations), so a chest
	-- or a bench in the bag looks like the thing it puts down.
	if not found then
		local assets = ReplicatedStorage:FindFirstChild("TerrainAssets")
		local stations = assets and assets:FindFirstChild("Stations")
		found = stations and stations:FindFirstChild(itemName)
	end

	if not found then
		found = buildFromLook(itemName)
	end

	-- A miss is deliberately NOT cached. ToolFactory builds missing tools at
	-- server start and the block folder fills in the same way, so an early
	-- lookup can legitimately fail for an item that exists a second later.
	if not found then
		return nil
	end

	cache[itemName] = found
	return found
end

local function idFrom(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	return string.match(value, "%d+")
end

--[[
	The first mesh asset id inside an item's model, as a bare number string
	("rbxassetid://123" -> "123", which is what a thumbnail URL wants), or nil
	for a model made of plain parts.

	This is what makes a thumbnail possible without anybody filling in an id by
	hand: an uploaded mesh is something Roblox can render a picture of.
]]
function ItemModels.meshId(itemName: string?): string?
	local source = ItemModels.find(itemName)
	if not source then
		return nil
	end

	if source:IsA("MeshPart") then
		local id = idFrom(source.MeshId)
		if id then
			return id
		end
	end

	for _, descendant in ipairs(source:GetDescendants()) do
		if descendant:IsA("MeshPart") or descendant:IsA("SpecialMesh") then
			local id = idFrom(descendant.MeshId)
			if id then
				return id
			end
		end
	end

	return nil
end

--[[
	The first face image on an item's model, as a bare id, or nil.

	The block case: a block template is a plain Part wearing Textures of its
	material, so the picture of a block already exists and it is the block's own
	face rather than a render of a cube. Cheaper and better-looking than a
	thumbnail for exactly the items a mining game has most of.
]]
function ItemModels.faceTextureId(itemName: string?): string?
	local source = ItemModels.find(itemName)
	if not source then
		return nil
	end

	local candidates = source:GetDescendants()
	table.insert(candidates, source)

	for _, instance in ipairs(candidates) do
		-- Texture is a subclass of Decal, so this catches both.
		if instance:IsA("Decal") then
			local id = idFrom(instance.Texture)
			if id then
				return id
			end
		end
	end

	return nil
end

return ItemModels
