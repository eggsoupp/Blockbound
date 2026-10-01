--[[
	ItemModels

	Where an item's 3D asset lives, for anything that wants to show one.

		local source = ItemModels.find("GoldPickaxe")

	There are two places a model can be, both already built and replicated for
	reasons unrelated to the UI: ReplicatedStorage.Tools[item] and
	ReplicatedStorage.TerrainAssets.Blocks[item]. So nothing extra has to be
	authored for an item to be previewable.

	Nothing here is ever parented anywhere. `find` returns the live template and
	callers clone it - reparenting one would empty the folder the terrain builds
	from.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemModels = {}

local cache: { [string]: Instance } = {}

local function toolsFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("Tools")
end

local function blocksFolder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("TerrainAssets")
	return assets and assets:FindFirstChild("Blocks")
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
