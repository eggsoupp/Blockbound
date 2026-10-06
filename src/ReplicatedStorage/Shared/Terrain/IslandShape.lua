--[[
	IslandShape

	The Island place's column source: turns a block position into the same
	(height, biome, topBlock, underBlock, variant, waterTop) that BiomeMap gives
	the open world, so TerrainManager can build an island with its usual
	machinery.

	Public API:
	  IslandShape.init(seed)
	  IslandShape.sampleColumn(bx, bz) -> height, biomeName, topBlock, underBlock,
	                                      variantName, waterTop
	  IslandShape.applyBlocks(cx, cz, writer)   hollows out under the island
	  IslandShape.allowStructureAt(bx, bz) -> boolean
	  IslandShape.clearCaches()
	  IslandShape.getStats() -> table

	HOW A FLOATING ISLAND FITS A HEIGHTMAP ENGINE

	TerrainManager's world is a heightmap: every column is solid from the floor
	up to its height. It has no notion of a column with sky underneath. So the
	island is made in two steps:

	  1. sampleColumn reports island columns as ordinary ground reaching all the
	     way down to the floor, and every other column as empty (height = floor).
	  2. applyBlocks then carves out everything in an island column below its
	     underside, during generation, through the same writer structures use.

	A carved block is exactly what a mined one is, and mined-out space is
	something the engine already handles everywhere: rendering, mining,
	placing and collision. Nothing about it is special-cased. Carving happens
	at generation, not through ChunkEdits, so it is part of the template and
	never ends up in a player's save.

	THE SHAPE

	  top        flat grass, a slight mound toward the middle, the odd one-block
	             step, a treeless clearing at the centre where players spawn
	  rim        RimThickness blocks thick at the edge: grass, dirt, then stone
	  underside  tapers from the rim to a rough point under the middle, with
	             rocky lumps hanging off it

	The edge wobbles with a noise field sampled around a circle rather than
	across the plane, so every ray from the centre crosses the edge exactly
	once: a natural outline with no stray fragments floating off it.

	Pure function of position and seed, like BiomeMap. See IslandConfig for
	every number.
]]

local TerrainFolder = script.Parent
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))
local IslandConfig = require(TerrainFolder:WaitForChild("IslandConfig"))
local NoiseField = require(TerrainFolder:WaitForChild("NoiseField"))

local IslandShape = {}

local CHUNK_SIZE = TerrainConfig.ChunkSize
local FLOOR_Y = TerrainConfig.WorldFloorY
local MAX_HEIGHT = TerrainConfig.MaxHeight

local RADIUS = IslandConfig.RadiusBlocks
local CLEARING = IslandConfig.ClearingRadius

-- How many blocks the place spans, for NoiseField's period guard.
local WORLD_SPAN = TerrainConfig.GridChunksX * CHUNK_SIZE

-- The lowest an island block may sit. Two layers above the floor, because the
-- floor's own bottom layers are bedrock and the island should have none.
local LOWEST_BASE = FLOOR_Y + 2

-- Trees keep this far clear of the clearing's edge, in blocks, so no canopy
-- hangs over the spawn.
local STRUCTURE_MARGIN = 2

local edgeField = nil
local bumpField = nil
local lumpField = nil

local sampledColumns = 0
local carvedBlocks = 0

local function clamp01(v)
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

--[[
	Distance from the centre, and how far in from the edge that is as a
	fraction: 1 at the centre, 0 at the edge, negative outside the island.
	Takes block-centre coordinates.
]]
local function placeOf(x, z)
	local r = math.sqrt(x * x + z * z)

	-- Sampled on a circle of the nominal radius in the direction of this
	-- column, so the edge's wobble depends on direction only.
	local ux, uz = 1, 0
	if r > 1e-6 then
		ux, uz = x / r, z / r
	end
	local wobble = edgeField:sample(ux * RADIUS, uz * RADIUS, IslandConfig.EdgeScale)
	local edge = RADIUS * (1 + wobble * IslandConfig.EdgeWobble)

	return r, 1 - r / edge
end

-- Height of an island column, by the engine's convention: one above the top
-- solid block.
local function topHeight(x, z, r, inland)
	local height = IslandConfig.SurfaceHeight + IslandConfig.CentreRise * inland

	-- The clearing stays perfectly flat.
	if r >= CLEARING then
		height += bumpField:sample(x, z, IslandConfig.BumpScale) * 2 * IslandConfig.Bumps
	end

	height = math.floor(height + 0.5)
	if height > MAX_HEIGHT then
		height = MAX_HEIGHT
	end
	return height
end

-- The lowest solid block of an island column.
local function baseOf(x, z, inland, height)
	local thickness = IslandConfig.RimThickness
		+ IslandConfig.CoreDepth * inland ^ IslandConfig.TaperPower
		+ lumpField:sample(x, z, IslandConfig.UndersideScale) * IslandConfig.UndersideLumps * math.sqrt(inland)

	local base = math.floor(height - thickness + 0.5)
	if base < LOWEST_BASE then
		base = LOWEST_BASE
	end
	if base > height - 1 then
		base = height - 1
	end
	return base
end

function IslandShape.init(seed)
	TerrainConfig.validate()

	seed = seed or IslandConfig.Seed

	-- Distinct planes keep the fields decorrelated (see NoiseField).
	edgeField = NoiseField.new(seed, 11.37, 2, 0.5, 2.0, 2 * RADIUS / IslandConfig.EdgeScale, false)
	bumpField = NoiseField.new(seed, 23.71, 2, 0.5, 2.0, WORLD_SPAN / IslandConfig.BumpScale, true)
	lumpField = NoiseField.new(seed, 37.19, 2, 0.5, 2.0, WORLD_SPAN / IslandConfig.UndersideScale, true)

	IslandShape.clearCaches()
end

function IslandShape.sampleColumn(bx, bz)
	sampledColumns += 1

	-- Block centres, so the island is symmetric about the spawn rather than
	-- about a block corner.
	local x, z = bx + 0.5, bz + 0.5
	local r, inland = placeOf(x, z)

	-- Water level: the floor, for every column, which means "dry" however far
	-- down it is dug. NOT 0, BiomeMap's dry value: a sky column's ground is the
	-- floor, which is below 0, and TerrainManager would read 0 as water standing
	-- above it.
	if inland <= 0 then
		-- Open sky. A column whose height is the floor holds nothing at all.
		return FLOOR_Y, IslandConfig.Biome, IslandConfig.TopBlock, IslandConfig.UnderBlock, IslandConfig.Variant, FLOOR_Y
	end

	return topHeight(x, z, r, inland),
		IslandConfig.Biome,
		IslandConfig.TopBlock,
		IslandConfig.UnderBlock,
		IslandConfig.Variant,
		FLOOR_Y
end

--[[
	Hollows out everything under the island, for one chunk. Called by
	TerrainManager while the chunk is generating, before structures and before
	any player edits are replayed, so a block a player later places down there
	still lands in empty space.

	The writer's carve is in absolute block coordinates and refuses anything
	that is not solid, so this cannot touch a column that is already empty.
]]
function IslandShape.applyBlocks(cx, cz, writer)
	local minBlockX = cx * CHUNK_SIZE
	local minBlockZ = cz * CHUNK_SIZE

	for bx = minBlockX, minBlockX + CHUNK_SIZE - 1 do
		for bz = minBlockZ, minBlockZ + CHUNK_SIZE - 1 do
			local x, z = bx + 0.5, bz + 0.5
			local r, inland = placeOf(x, z)

			if inland > 0 then
				local base = baseOf(x, z, inland, topHeight(x, z, r, inland))
				for by = FLOOR_Y, base - 1 do
					writer.carve(bx, bz, by)
				end
				carvedBlocks += base - FLOOR_Y
			end
		end
	end
end

--[[
	The lowest solid block of a column as generated, or nil when nothing is
	carved under it. Lets TerrainManager answer "is there a block here?" for a
	chunk that has not loaded yet, which it otherwise reads straight off the
	heightmap - and the heightmap alone would say the sky under the island is
	solid rock.
]]
function IslandShape.baseAt(bx, bz)
	local x, z = bx + 0.5, bz + 0.5
	local r, inland = placeOf(x, z)
	if inland <= 0 then
		return nil
	end
	return baseOf(x, z, inland, topHeight(x, z, r, inland))
end

--[[
	Whether a structure (a tree) may be rooted at this column. Keeps the spawn
	clearing and a margin along the edge free. Open sky is already refused by
	StructureRegistry, whose structures all need ground above height 2.
]]
function IslandShape.allowStructureAt(bx, bz)
	local r, inland = placeOf(bx + 0.5, bz + 0.5)
	return r >= CLEARING + STRUCTURE_MARGIN and inland >= IslandConfig.TreeEdgeMargin
end

function IslandShape.clearCaches()
	-- Nothing is cached here: an island is small enough that TerrainManager's
	-- own column cache holds every column of it.
end

function IslandShape.getStats()
	return {
		source = "IslandShape",
		templateVersion = IslandConfig.TemplateVersion,
		sampledColumns = sampledColumns,
		carvedBlocks = carvedBlocks,
	}
end

return IslandShape
