--[[
	IslandConfig

	What a player's island looks like, and how the terrain engine is reconfigured
	in the Island place to build one instead of the open world.

	Read only when PlaceConfig says this is the Island place:

	  TerrainConfig   applies IslandConfig.Terrain over its own world settings
	  OreConfig       restricts generation to IslandConfig.Ores
	  IslandShape     reads everything else here to shape the island
	  TerrainManager  uses IslandShape instead of BiomeMap as its column source

	Everything else - meshing, mining, placing, trees, chunk streaming - is the
	same engine the open world runs on, so building at home feels exactly like
	building out there.

	THE ISLAND

	A floating island in an empty sky: a flat grass top for building on, a
	thin rim, and a rocky underside tapering to a point. A handful of trees for
	a first load of wood, and nothing else - the island is a plot, not a place
	to explore. Players can build out past its edge into the sky, up to the
	edge of the place.

	EVERY ISLAND STARTS FROM THE SAME TEMPLATE

	The shape is a pure function of these numbers and Seed, and is the same for
	every player. A saved island stores only what its owner CHANGED, replayed
	over this template when it loads.

	That makes the template part of every save. Changing anything that moves a
	block - Seed, any size, height or noise setting below, or the Terrain
	overrides - changes the ground every existing island's edits are replayed
	onto. Bump TemplateVersion when you do, so the island store can tell old
	saves apart.
]]

local IslandConfig = {}

IslandConfig.TemplateVersion = 1

-- Fixed, not random: see the header.
IslandConfig.Seed = 718201

-- ===========================================================================
-- TERRAIN ENGINE OVERRIDES
-- ===========================================================================

--[[
	Applied over TerrainConfig in the Island place, before its derived values
	are computed.

	13 x 13 chunks is 208 blocks, 832 studs, across: the island in the middle
	and a wide margin of sky around it to build out into. Nothing outside the
	island generates, so the margin costs nothing until someone builds there.

	The floor sits just under the island's lowest point. Below it nothing can
	exist, so it is also how far down anyone can build.
]]
IslandConfig.Terrain = {
	GridChunksX = 13,
	GridChunksZ = 13,
	WorldFloorY = -4,
	WorldSeed = IslandConfig.Seed,

	-- Only used by the open world's BiomeMap, but TerrainConfig.validate
	-- requires it to fit inside the world radius.
	EdgeFalloffBlocks = 16,
}

--[[
	Which ores may generate inside an island. Basics only: the rare ones are
	what the open world is for.

	Ores not listed here still exist as blocks (so one carried home still
	mines and drops normally); they just never generate here.
]]
IslandConfig.Ores = {
	Coal = true,
	Copper = true,
}

-- ===========================================================================
-- TOP
-- ===========================================================================

-- Distance from the centre to the edge, in blocks, before the edge wobble.
-- 32 blocks is 128 studs: about 256 studs of island across.
IslandConfig.RadiusBlocks = 32

-- How far the edge wanders in and out, as a fraction of the radius, and how
-- large its bumps are, in blocks.
IslandConfig.EdgeWobble = 0.14
IslandConfig.EdgeScale = 22

--[[
	The height of the grass, as a block layer: the top block sits at
	SurfaceHeight - 1. 36 blocks (144 studs) puts the island well clear of the
	floor with room for its underside.
]]
IslandConfig.SurfaceHeight = 36

-- The top is nearly flat, because it is for building on. CentreRise lifts the
-- middle slightly so the island reads as a mound rather than a table; Bumps is
-- how many blocks the ground may step up or down.
IslandConfig.CentreRise = 2
IslandConfig.Bumps = 1
IslandConfig.BumpScale = 14

IslandConfig.TopBlock = "Grass"
IslandConfig.UnderBlock = "Dirt"

-- ===========================================================================
-- UNDERSIDE
-- ===========================================================================

-- How thick the island is at its edge, in blocks, and how much thicker it gets
-- toward the middle. RimThickness + CoreDepth is roughly the depth under the
-- centre, before the lumps.
IslandConfig.RimThickness = 4
IslandConfig.CoreDepth = 24

-- Shape of the taper. Below 1 the underside bulges (a bowl); above 1 it
-- narrows quickly into a spike.
IslandConfig.TaperPower = 0.75

-- Rocky lumps hanging off the underside: how many blocks they reach, and how
-- wide they are. Faded out toward the rim so the edge stays a clean line.
IslandConfig.UndersideLumps = 4
IslandConfig.UndersideScale = 6

-- ===========================================================================
-- TREES
-- ===========================================================================

-- Biome the island reports. It decides which trees grow, so it must exist in
-- BiomeConfig. "Open" Plains is open grass with a lone tree here and there -
-- about half a dozen on an island this size.
IslandConfig.Biome = "Plains"
IslandConfig.Variant = "Open"

-- A treeless clearing at the centre where players spawn, in blocks.
IslandConfig.ClearingRadius = 8

-- Trees keep this fraction of the radius back from the edge.
IslandConfig.TreeEdgeMargin = 0.12

return IslandConfig
