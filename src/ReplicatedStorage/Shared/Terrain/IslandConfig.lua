--[[
	IslandConfig

	What a player's island looks like, and how the terrain engine is reconfigured
	in the Island place to build one instead of the open world.

	Read only when PlaceConfig says this is the Island place:

	  TerrainConfig   applies IslandConfig.Terrain over its own world settings
	  OreConfig       restricts generation to IslandConfig.Ores
	  IslandShape     reads everything else here to shape the island
	  TerrainManager  uses IslandShape instead of BiomeMap as its column source

	Everything else - meshing, mining, placing, trees, water, chunk streaming -
	is the same engine the open world runs on, so building at home feels
	exactly like building out there.

	EVERY ISLAND STARTS FROM THE SAME TEMPLATE

	The shape is a pure function of these numbers and Seed, and is the same for
	every player. A saved island stores only what its owner CHANGED, replayed
	over this template when it loads.

	That makes the template part of every save. Changing anything that moves a
	block - Seed, any radius, height or noise setting below, or the island
	Terrain overrides - changes the ground every existing island's edits are
	replayed onto. Bump TemplateVersion when you do, so the island store can
	tell old saves apart (see the island store once it exists).
]]

local IslandConfig = {}

IslandConfig.TemplateVersion = 1

-- Fixed, not random: see the header. Any integer works; this one was picked
-- for a pleasant coastline.
IslandConfig.Seed = 718201

-- ===========================================================================
-- TERRAIN ENGINE OVERRIDES
-- ===========================================================================

--[[
	Applied over TerrainConfig in the Island place, before its derived values
	are computed.

	13 x 13 chunks is 208 blocks, 832 studs, across - the island plus a ring of
	sea. Small enough that the whole place is a few hundred chunks at most, so
	an island server is cheap.

	The floor is shallow on purpose. The open world is 160 blocks deep because
	its depths are where the rare ore is; an island only needs enough rock under
	it to dig a basement and a mine shaft, and a shallow floor keeps the
	island from becoming an infinite private quarry.
]]
IslandConfig.Terrain = {
	GridChunksX = 13,
	GridChunksZ = 13,
	WorldFloorY = -32,
	WorldSeed = IslandConfig.Seed,

	-- Only used by the open world's BiomeMap, but TerrainConfig.validate
	-- requires it to fit inside the world radius.
	EdgeFalloffBlocks = 16,
}

--[[
	Which ores may generate under an island. Basics only: the rare ones are what
	the open world is for.

	Ores not listed here still exist as blocks (so a player can still hold,
	place or mine one they brought home); they just never generate here.
]]
IslandConfig.Ores = {
	Coal = true,
	Copper = true,
}

-- ===========================================================================
-- SHAPE
-- ===========================================================================

-- Distance from the centre to the shoreline, in blocks, before the coastline
-- wobble. 46 blocks is 184 studs: about 370 studs of land across.
IslandConfig.RadiusBlocks = 46

-- How far the coastline wanders in and out, as a fraction of the radius, and
-- how large its bays and headlands are, in blocks.
IslandConfig.CoastWobble = 0.22
IslandConfig.CoastScale = 30

-- The beach: the outer fraction of the island (by radius) that is sand at the
-- water's edge rather than grass.
IslandConfig.BeachFraction = 0.10

-- Heights, in blocks above sea level (LandformConfig.SeaLevel).
IslandConfig.ShoreHeight = 1 -- the beach, just clear of the water
IslandConfig.InlandHeight = 4 -- where the grass starts
IslandConfig.CentreRise = 7 -- extra height the middle of the island gains
IslandConfig.HillAmplitude = 4 -- gentle rolling relief on top of that
IslandConfig.HillScale = 18

-- Bare rock breaks through above this many blocks over sea level; nothing
-- grows on it. Set it high to keep the whole island green.
IslandConfig.RockAbove = 15

-- Sea floor: how many blocks below sea level it sinks, and over how many
-- blocks offshore it gets there.
IslandConfig.SeaDepth = 12
IslandConfig.SeaFloorSlopeBlocks = 14

-- ===========================================================================
-- SURFACE AND TREES
-- ===========================================================================

-- Biome the island reports. It decides which trees grow and what the
-- surrounding systems think of the ground, so it must exist in BiomeConfig.
IslandConfig.Biome = "Plains"

IslandConfig.TopBlock = "Grass"
IslandConfig.UnderBlock = "Dirt"
IslandConfig.BeachBlock = "Sand"
IslandConfig.RockBlock = "Stone"

--[[
	Woods. A slow noise field decides where the island is wooded: above
	ForestThreshold it is oak, below -ForestThreshold birch, between them open
	grass with the odd lone tree. Uses the Plains sub-biomes, so tree density
	is BiomeConfig's.
]]
IslandConfig.ForestScale = 20
IslandConfig.ForestThreshold = 0.18

-- A flat, treeless clearing at the centre, where players spawn and where the
-- first thing they build usually goes. In blocks.
IslandConfig.ClearingRadius = 10

return IslandConfig
