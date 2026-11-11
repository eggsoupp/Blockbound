--[[
	GeneratedColumns

	What the generator says a column is, before anyone has touched it: the
	place's column source (the open world's BiomeMap, or the Island template),
	whether caves are carved here, and the two-generation speed cache in front
	of sampleColumn. Part of TerrainManager; see TerrainManager for the map of
	terrain modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))
local BiomeMap = require(TerrainShared:WaitForChild("BiomeMap"))
local IslandShape = require(TerrainShared:WaitForChild("IslandShape"))
local CaveConfig = require(TerrainShared:WaitForChild("CaveConfig"))
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local GeneratedColumns = {}

local FLOOR_Y = TerrainConfig.WorldFloorY
local BLOCK_KEY_OFFSET = TerrainGrid.BLOCK_KEY_OFFSET
local BLOCK_KEY_STRIDE = TerrainGrid.BLOCK_KEY_STRIDE

--[[
	Where columns come from: the open world's BiomeMap, or in the Island place
	the island template. Both answer sampleColumn with the same six values, so
	nothing below this line knows which place it is in. TerrainConfig and
	OreConfig make the matching size, depth and ore adjustments themselves.
]]
local ColumnSource = if PlaceConfig.isIsland() then IslandShape else BiomeMap
GeneratedColumns.source = ColumnSource

--[[
	CAVES

	The heightmap says a column is solid from the floor to its height. Caves
	are the second thing, after the island's underside, that make that untrue
	for GENERATED ground - so every place that reads the heightmap for a chunk
	that is not loaded also asks CaveMap, and a loaded chunk has its cave
	cells marked removed at generation, before structures and before player
	edits are replayed. From then on cave air is mined-out space, which the
	renderer, mining, placement, support queries and persistence already
	understand: nothing stores it, and a chunk carves it again identically
	every time it streams in.
]]
local CAVES_ENABLED = CaveConfig.Enabled and (CaveConfig.EnabledOnIsland or not PlaceConfig.isIsland())
GeneratedColumns.cavesEnabled = CAVES_ENABLED

-- ---------------------------------------------------------------------------
-- Generated column cache
-- ---------------------------------------------------------------------------
-- BiomeMap is a pure function of position, so this is purely a speed cache and
-- can be dropped at any time. It exists because visibility culling and
-- structure validation ask about neighbouring columns constantly, including
-- columns in chunks that are not loaded.

-- EVICTION. Two generations rather than one map wiped when it fills. Wiping is
-- correct - these are pure functions of position - but it discards the columns
-- in active use together with the cold ones, so a player crossing the boundary
-- pays to recompute the ground they are standing on. Worse here than for the
-- lattice, because the visibility pass asks about neighbouring columns
-- constantly, including columns in chunks that are not loaded.
--
-- A full young generation is demoted; a hit in old is promoted back into young.
-- Anything still in use therefore survives every rotation, and anything cold is
-- released one rotation after it stops being touched. Each generation is capped
-- at half of ColumnCacheLimit, so the configured ceiling is unchanged.

local genHeight = {}
local genBiome = {}
local genTop = {}
local genUnder = {}
local genVariant = {}
local genWater = {}
local genCount = 0

local oldHeight = {}
local oldBiome = {}
local oldTop = {}
local oldUnder = {}
local oldVariant = {}
local oldWater = {}
local oldGenCount = 0

local COLUMN_GENERATION_LIMIT = math.max(1, math.floor(TerrainConfig.ColumnCacheLimit / 2))

local function rotateColumnGenerations()
	oldHeight, genHeight = genHeight, {}
	oldBiome, genBiome = genBiome, {}
	oldTop, genTop = genTop, {}
	oldUnder, genUnder = genUnder, {}
	oldVariant, genVariant = genVariant, {}
	oldWater, genWater = genWater, {}
	oldGenCount = genCount
	genCount = 0
	Profiler.count("Terrain.columnCacheRotated")
end

--[[
	height is the top of the SOLID ground; water, when there is any, stands in
	[height, waterTop). Both come from BiomeMap and are pure functions of
	position, so this is only ever a speed cache.
]]
local function getGeneratedColumn(blockX, blockZ)
	local key = (blockX + BLOCK_KEY_OFFSET) * BLOCK_KEY_STRIDE + (blockZ + BLOCK_KEY_OFFSET)

	local height = genHeight[key]
	if height ~= nil then
		return height, genBiome[key], genTop[key], genUnder[key], genVariant[key], genWater[key]
	end

	-- Read out of the old generation BEFORE any rotation, which would otherwise
	-- overwrite the table these values live in.
	local agedHeight = oldHeight[key]
	if agedHeight ~= nil then
		local agedBiome = oldBiome[key]
		local agedTop = oldTop[key]
		local agedUnder = oldUnder[key]
		local agedVariant = oldVariant[key]
		local agedWater = oldWater[key]

		if genCount >= COLUMN_GENERATION_LIMIT then
			rotateColumnGenerations()
		end

		genHeight[key] = agedHeight
		genBiome[key] = agedBiome
		genTop[key] = agedTop
		genUnder[key] = agedUnder
		genVariant[key] = agedVariant
		genWater[key] = agedWater
		genCount += 1

		Profiler.count("Terrain.columnPromoted")
		return agedHeight, agedBiome, agedTop, agedUnder, agedVariant, agedWater
	end

	if genCount >= COLUMN_GENERATION_LIMIT then
		rotateColumnGenerations()
	end

	local biome, top, under, variant, water
	height, biome, top, under, variant, water = ColumnSource.sampleColumn(blockX, blockZ)

	--[[
		A dry column reports its water at or below its ground (BiomeMap uses 0).
		Pinned to the floor here so it stays dry however deep the column is dug:
		the renderer draws water wherever waterTop is above the CURRENT height,
		so a dry shaft dug below y = 0 used to grow a phantom water block, and an
		island's sky columns - whose ground IS the floor, below 0 - drew a ring
		of water around the island.
	]]
	if water <= height then
		water = FLOOR_Y
	end

	genHeight[key] = height
	genBiome[key] = biome
	genTop[key] = top
	genUnder[key] = under
	genVariant[key] = variant
	genWater[key] = water
	genCount += 1

	Profiler.count("Terrain.columnSampled")
	return height, biome, top, under, variant, water
end
GeneratedColumns.get = getGeneratedColumn

-- How many columns the cache holds, across both generations.
function GeneratedColumns.count()
	return genCount + oldGenCount
end

-- Drops every cached column (benchmark cold starts). Pure cache: safe any time.
function GeneratedColumns.clear()
	table.clear(genHeight)
	table.clear(genBiome)
	table.clear(genTop)
	table.clear(genUnder)
	table.clear(genVariant)
	table.clear(genWater)
	genCount = 0

	table.clear(oldHeight)
	table.clear(oldBiome)
	table.clear(oldTop)
	table.clear(oldUnder)
	table.clear(oldVariant)
	table.clear(oldWater)
	oldGenCount = 0
end

return GeneratedColumns
