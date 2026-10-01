--[[
	IslandShape

	The Island place's column source: turns a block position into the same
	(height, biome, topBlock, underBlock, variant, waterTop) that BiomeMap gives
	the open world, so TerrainManager can build an island with no other changes.

	Public API (mirrors BiomeMap where TerrainManager needs it to):
	  IslandShape.init(seed)
	  IslandShape.sampleColumn(bx, bz) -> height, biomeName, topBlock, underBlock,
	                                      variantName, waterTop
	  IslandShape.allowStructureAt(bx, bz) -> boolean
	  IslandShape.clearCaches()
	  IslandShape.getStats() -> table

	THE SHAPE, FROM THE MIDDLE OUT

	  clearing   flat, treeless, where players spawn
	  inland     grass, rising gently toward the middle, with low rolling hills
	             and woods of oak and birch
	  beach      a band of sand just clear of the water
	  sea        a sandy floor shelving away to IslandConfig.SeaDepth, out to
	             the edge of the place

	The coastline wobbles with a noise field sampled around a circle rather
	than across the plane, so every ray from the centre crosses the shore
	exactly once: bays and headlands, but no stray islets or inland ponds that
	the template did not mean to have.

	Heights follow BiomeMap's convention: `height` is one above the top solid
	block, and water, when there is any, stands in [height, waterTop).

	Pure function of position and seed, like BiomeMap, so TerrainManager's
	column cache and StructureRegistry can ask about any column at any time.
	See IslandConfig for every number.
]]

local TerrainFolder = script.Parent
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))
local LandformConfig = require(TerrainFolder:WaitForChild("LandformConfig"))
local IslandConfig = require(TerrainFolder:WaitForChild("IslandConfig"))
local NoiseField = require(TerrainFolder:WaitForChild("NoiseField"))

local IslandShape = {}

local SEA_LEVEL = LandformConfig.SeaLevel
local MIN_HEIGHT = TerrainConfig.MinHeight
local MAX_HEIGHT = TerrainConfig.MaxHeight

local RADIUS = IslandConfig.RadiusBlocks
local BEACH = IslandConfig.BeachFraction
local CLEARING = IslandConfig.ClearingRadius

-- How many blocks the place spans, for NoiseField's period guard.
local WORLD_SPAN = TerrainConfig.GridChunksX * TerrainConfig.ChunkSize

-- Grass ramps up from the beach over this fraction of the radius.
local SHORE_RAMP = 0.12

-- The clearing blends into the land around it over this many blocks.
local CLEARING_BLEND = 4

-- Structures keep this far clear of the clearing's edge, in blocks. Covers a
-- tree's footprint radius so no canopy hangs over the spawn.
local STRUCTURE_MARGIN = 2

local coastField = nil
local hillField = nil
local forestField = nil

local sampledColumns = 0

local function clamp01(v)
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

local function smoothstep(v)
	v = clamp01(v)
	return v * v * (3 - 2 * v)
end

--[[
	Distance from the centre, and how far inland that is as a fraction:
	1 at the centre, 0 on the shoreline, negative out at sea.
]]
local function placeOf(x, z)
	local r = math.sqrt(x * x + z * z)

	-- Sampled on a circle of the nominal radius in the direction of this
	-- column, so the coastline's wobble depends on direction only.
	local ux, uz = 1, 0
	if r > 1e-6 then
		ux, uz = x / r, z / r
	end
	local wobble = coastField:sample(ux * RADIUS, uz * RADIUS, IslandConfig.CoastScale)
	local coast = RADIUS * (1 + wobble * IslandConfig.CoastWobble)

	return r, 1 - r / coast, coast
end

local function landHeight(x, z, r, inland)
	local aboveBeach = (inland - BEACH) / (1 - BEACH)

	local height = SEA_LEVEL + IslandConfig.ShoreHeight
		+ (IslandConfig.InlandHeight - IslandConfig.ShoreHeight) * smoothstep((inland - BEACH) / SHORE_RAMP)
		+ IslandConfig.CentreRise * smoothstep(aboveBeach)

	-- Hills fade in away from the shore so the beach stays a beach.
	local hills = hillField:sample(x, z, IslandConfig.HillScale) * IslandConfig.HillAmplitude
	height += hills * smoothstep(aboveBeach * 3)

	-- Flatten the clearing to the height of the very centre.
	if r < CLEARING + CLEARING_BLEND then
		local centre = SEA_LEVEL + IslandConfig.InlandHeight + IslandConfig.CentreRise
		local blend = smoothstep((r - CLEARING) / CLEARING_BLEND)
		height = centre + (height - centre) * blend
	end

	return height
end

local function clampHeight(height)
	height = math.floor(height + 0.5)
	if height < MIN_HEIGHT then
		return MIN_HEIGHT
	elseif height > MAX_HEIGHT then
		return MAX_HEIGHT
	end
	return height
end

function IslandShape.init(seed)
	TerrainConfig.validate()

	seed = seed or IslandConfig.Seed

	-- Distinct planes keep the three fields decorrelated (see NoiseField).
	coastField = NoiseField.new(seed, 11.37, 2, 0.5, 2.0, 2 * RADIUS / IslandConfig.CoastScale, false)
	hillField = NoiseField.new(seed, 23.71, 3, 0.5, 2.0, WORLD_SPAN / IslandConfig.HillScale, true)
	forestField = NoiseField.new(seed, 37.19, 2, 0.5, 2.0, WORLD_SPAN / IslandConfig.ForestScale, true)

	IslandShape.clearCaches()
end

function IslandShape.sampleColumn(bx, bz)
	sampledColumns += 1

	-- Block centres, so the island is symmetric about the spawn rather than
	-- about a block corner.
	local x, z = bx + 0.5, bz + 0.5
	local r, inland, coast = placeOf(x, z)

	if inland <= 0 then
		-- Sea. The floor shelves from just under the surface at the shore to
		-- SeaDepth further out.
		local offshore = r - coast
		local depth = 1 + (IslandConfig.SeaDepth - 1) * smoothstep(offshore / IslandConfig.SeaFloorSlopeBlocks)
		local height = clampHeight(SEA_LEVEL - depth)
		return height,
			IslandConfig.Biome,
			IslandConfig.BeachBlock,
			IslandConfig.BeachBlock,
			"Open",
			SEA_LEVEL
	end

	local height = clampHeight(landHeight(x, z, r, inland))

	local top, under
	if inland < BEACH then
		top, under = IslandConfig.BeachBlock, IslandConfig.BeachBlock
	elseif height - SEA_LEVEL >= IslandConfig.RockAbove then
		top, under = IslandConfig.RockBlock, IslandConfig.UnderBlock
	else
		top, under = IslandConfig.TopBlock, IslandConfig.UnderBlock
	end

	local variant = "Open"
	if r >= CLEARING + STRUCTURE_MARGIN then
		local forest = forestField:sample(x, z, IslandConfig.ForestScale)
		if forest > IslandConfig.ForestThreshold then
			variant = "OakForest"
		elseif forest < -IslandConfig.ForestThreshold then
			variant = "BirchForest"
		end
	end

	return height, IslandConfig.Biome, top, under, variant, 0
end

--[[
	Whether a structure (a tree, a boulder) may be rooted at this column.
	Keeps the spawn clearing and the beach free; the sea is already refused by
	StructureRegistry, which grows nothing in standing water.
]]
function IslandShape.allowStructureAt(bx, bz)
	local r, inland = placeOf(bx + 0.5, bz + 0.5)
	return r >= CLEARING + STRUCTURE_MARGIN and inland >= BEACH
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
	}
end

return IslandShape
