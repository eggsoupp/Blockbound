--[[
	StrataConfig

	What the world is made of as you go down, expressed as depth bands rather
	than as branches inside the generator.

	DEPTH is measured in blocks below the surface of the column:
	  depth 0  = the top solid block (the one wearing the biome's topBlock)
	  depth 1  = one block under it
	  ...

	Layers are consulted in order and the first whose maxDepth covers the depth
	wins. `block = false` means "whatever the biome nominated as its underBlock",
	which is what keeps dirt-under-grass and sandstone-under-sand working without
	naming either here.

	The bottom BedrockThickness blocks of the world are always BedrockBlock, so
	players cannot dig out through the floor. BlockConfig marks it unbreakable.

	ADDING A LAYER
	  Insert a row in Layers, in increasing maxDepth order. Nothing else changes;
	  the generator has no per-layer code.
]]

local StrataConfig = {}

StrataConfig.Layers = {
	-- Topsoil: whatever the biome says sits under its surface block.
	{ maxDepth = 3, block = false },

	-- A short transition so the dirt-to-stone line is not a dead flat plane.
	-- Handled by jitterBlocks below rather than by a separate layer.

	-- Everything below is stone, which is also what ores replace.
	{ maxDepth = math.huge, block = "Stone" },
}

-- The soil/stone boundary is nudged up or down by up to this many blocks using
-- a per-column hash, so the transition reads as natural rather than as a
-- perfectly level seam across the whole world.
StrataConfig.JitterBlocks = 2

StrataConfig.BedrockThickness = 2
StrataConfig.BedrockBlock = "Bedrock"

--[[
	Which base block sits at `depth` below the surface.

	  depth            blocks below the column's surface block (0 = surface)
	  underBlock       the biome's subsurface block name
	  jitter           [-JitterBlocks, +JitterBlocks], derived from the column
	                   by the caller so it is stable and seamless

	Returns a block name. Bedrock is decided by the caller, which is the only
	place that knows where the floor is.
]]
function StrataConfig.blockAt(depth, underBlock, jitter)
	local adjusted = depth - (jitter or 0)

	for _, layer in ipairs(StrataConfig.Layers) do
		if adjusted <= layer.maxDepth then
			if layer.block == false then
				return underBlock
			end
			return layer.block
		end
	end

	return underBlock
end

--[[
	The deepest layer's block name, i.e. what ores are expected to replace.
	Used for validation so a mistyped host block fails loudly at startup.
]]
function StrataConfig.getDeepBlock()
	local last = StrataConfig.Layers[#StrataConfig.Layers]
	return (last and last.block) or "Stone"
end

function StrataConfig.validate()
	assert(#StrataConfig.Layers > 0, "[StrataConfig] Layers is empty")

	local previous = -math.huge
	for index, layer in ipairs(StrataConfig.Layers) do
		assert(
			type(layer.maxDepth) == "number" and layer.maxDepth > previous,
			string.format("[StrataConfig] Layers[%d].maxDepth must increase", index)
		)
		assert(
			layer.block == false or type(layer.block) == "string",
			string.format("[StrataConfig] Layers[%d].block must be a name or false", index)
		)
		previous = layer.maxDepth
	end

	assert(
		StrataConfig.Layers[#StrataConfig.Layers].maxDepth == math.huge,
		"[StrataConfig] the last layer must be open-ended (maxDepth = math.huge)"
	)
end

return StrataConfig
