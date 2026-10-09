--[[
	TerrainConfig

	World, chunk, streaming and performance tunables for TerrainManager.

	  TerrainConfig    world size, chunks, streaming, budgets
	  LandformConfig   continents, mountain ranges, rivers, lakes, landmarks
	  BiomeConfig      which biomes exist, and how much of each landform they take
	  StructureConfig  trees / rocks / ruins and how they scatter
	  StrataConfig     what the world is made of going down
	  OreConfig        which ores exist and at what depths

	The knobs you reach for most: GridChunksX/Z (world size),
	ViewDistanceChunks (perf dial #1), MaxHeight, WorldFloorY.

	A "block" is one voxel cell, StudSize studs on a side. Noise scales are in
	BLOCKS - bigger means larger features - and they all live in LandformConfig.
]]

local TerrainConfig = {}

-- ===========================================================================
-- WORLD BOUNDS
-- ===========================================================================

-- LOCKED AT 4: PlacementServer and PlacementClient snap player-placed blocks
-- to a 4-stud grid with origin (2,2,2). Changing this desyncs building.
TerrainConfig.StudSize = 4

TerrainConfig.ChunkSize = 16 -- blocks per chunk edge

--[[
	A square of chunks centred on the origin; odd numbers keep chunk (0,0) on
	spawn. 385 * 16 * 4 = 24,640 studs across, about sixteen minutes' sprint
	corner to corner.

	Enlarging this is nearly free at RUN TIME: chunks stream, and neither column
	cost nor memory depends on world size - a column is a pure function of its
	own coordinates (see BiomeMap and Landform). What it does cost is that every
	noise field has to span more of Perlin's 256-unit period, which is what
	LandformConfig.validate checks: past about 200 units a field starts to
	repeat across the map. Growing the world again means growing the scales
	with it.
]]
TerrainConfig.GridChunksX = 385
TerrainConfig.GridChunksZ = 385

--[[
	Surface height clamp in blocks. Bounds the SURFACE only; WorldFloorY is how
	far the world extends down.

	212 blocks of range is 848 studs from the deepest seabed to the highest
	peak. The budget it buys, measured over 28,900 inland samples:

	    4    the floor of the world
	    34   sea level (LandformConfig.SeaLevel)
	    41   the lowest lake surface; the median one is 49
	    56   ordinary grassland - a biome's baseHeight is now the height its
	         ground AVERAGES, since the hill term is centred
	    64   Plains at its 90th percentile
	    84   the median snow column
	    139  snow at its 90th percentile: the ranges
	    183  snow at its 99th
	    216  the rare landmark peak, and the ceiling

	Reached, but barely: 2 columns of 28,900 pinned at the ceiling. That is
	where it should sit - a clamp that fires often flat-tops every summit it
	touches.

	UP FROM 196, and the reason is the relief rework rather than a wish for
	taller mountains. Hills are four octaves at up to 34 blocks now instead of
	three at 17, and every biome's baseHeight rose with them to keep its ground
	the same distance above the water; between them that is about 25 blocks of
	headroom spent before a mountain starts. At 196 the snow peaks were
	arriving flat-topped.

	Raising the ceiling costs nothing at rest - the world is a heightmap and
	only the exposed band is ever rendered. What costs is SLOPE: a column beside
	a twenty-block drop draws twenty side faces. That is why the mountains here
	are built from ridged noise with graded foothills rather than from raw
	amplitude, and why cliffs are deliberately rationed.
]]
TerrainConfig.MinHeight = 4
TerrainConfig.MaxHeight = 216

--[[
	Lowest block layer, in blocks. Negative because block 0 is ground level; the
	bottom StrataConfig.BedrockThickness layers are bedrock so nobody digs out.

	-160 blocks is 640 studs of rock, giving ore ~190 blocks of vertical range.
	Deepening it costs nothing at rest: columns are a surface height plus sparse
	edits, not a per-block array, and only the exposed band is rendered. What it
	does cost is the scan once a column has been dug into, which is why columns
	track how deep they have actually been disturbed.
]]
TerrainConfig.WorldFloorY = -160

-- Terrain sinks toward MinHeight over this many blocks at the border. Since
-- MinHeight is well below the water table, the map ends in a coastline and an
-- ocean rather than in a dry ramp to nothing.
TerrainConfig.EdgeFalloffBlocks = 260

-- How far above MaxHeight structures and player building may reach.
TerrainConfig.StructureHeadroom = 24

-- A number for a fixed world; nil re-rolls per server.
TerrainConfig.WorldSeed = nil

-- ===========================================================================
-- SPAWN
-- ===========================================================================
-- Climate is pulled toward SpawnBiome inside this radius, blended rather than
-- stamped, so players never open into Corruption and there is no hard edge.
TerrainConfig.SpawnBiome = "Plains"
TerrainConfig.SpawnSafeRadiusBlocks = 300

-- The GUARANTEED starting area, as a square (Chebyshev) distance in blocks so
-- it lines up with the chunk grid. 64 blocks = chunks -4..4, a 9x9 block of
-- them. Past it the guarantee smoothsteps out to SpawnSafeRadiusBlocks, so
-- keep this comfortably under that or the transition has nowhere to happen.
TerrainConfig.SpawnGuaranteeBlocks = 64

-- ===========================================================================
-- STREAMING
-- ===========================================================================

--[[
	Chunks around each player: (2n+1)^2. 2 -> 5x5 = 320 studs of sight; 4 ->
	9x9 = 576 studs; 5 -> 11x11 = 704.

	The single biggest cost dial: it drives resident part count, which is what
	the client and replication actually pay for.

	Raised from 2, and it is not a cosmetic change - at 2 nothing further than
	320 studs from the player exists, and a mountain 700 studs tall standing
	1,500 studs away is simply not in the world yet. Every bit of the geography
	work in Landform is invisible at 2, because a range is bigger than the
	radius that renders it.

	4 rather than 5 leaves headroom. The benchmark after the mesher landed
	measured VIEW DISTANCE 5 at 60 fps at rest, 58.6 travelling and 13,855
	client instances - so 5 is affordable too, and is where to go if the
	mountains still do not read. What the terrain changes add on top of that is
	small: visible blocks per column went from 1.00 to 1.11, and nearly all of
	the increase is water rather than slope, because mountains are smooth at
	block scale and the mesher only ever draws the exposed band.

	Re-run /bbbench after changing this rather than trusting the numbers above.

	This is the DEFAULT. Each player has their own, settable from the pause menu
	and held per player by TerrainManager, so one person on a weak machine can
	turn it down without deciding it for everybody else.
]]
TerrainConfig.ViewDistanceChunks = 4

--[[
	What a player is allowed to choose.

	The ceiling is a cost bound, and it is the server that pays: chunks are
	generated once and shared, so a player asking for 8 makes everyone's server
	build (2*8+1)^2 = 289 chunks around THEM. 7 is already 225 and well past
	anything the benchmark has measured, so it is where the option stops.

	The floor is 1 rather than 0 because 0 loads only the chunk a player is
	standing in and they fall out of the world at its edge.
]]
TerrainConfig.MinViewDistanceChunks = 1
TerrainConfig.MaxViewDistanceChunks = 7

-- A chunk out of every player's view is kept this long before unloading, so
-- walking back and forth over a border does not thrash. Cheaper than widening
-- the radius, which grows the loaded set quadratically.
TerrainConfig.UnloadGraceSeconds = 5

TerrainConfig.MovementCheckInterval = 0.22

-- ===========================================================================
-- PERFORMANCE
-- ===========================================================================

--[[
	Generation is time-sliced, not count-sliced: the generator yields once the
	frame's allowance is spent, wherever it has got to.

	The allowance is SHARED and ADAPTIVE - a control loop against the server's
	own frame time. It climbs by RiseStep while frames stay under FrameTarget
	and work is queued, falls by FallStep while they run over, and halves if
	they cross FrameCeiling. Asymmetric on purpose: overshooting costs a visible
	hitch, undershooting costs a little load time.

	A flat 4ms per chunk priced out at ~58ms of CPU and a ~23 SECOND wait per
	chunk at view distance 5, on a server that was not busy.

	GenerateBudgetSeconds is the starting point, not the limit.
]]
TerrainConfig.GenerateBudgetSeconds = 0.004
TerrainConfig.GenerateBudgetMinSeconds = 0.004
TerrainConfig.GenerateBudgetMaxSeconds = 0.012

-- A 60Hz frame is 16.7ms; the target sits just above so the loop keeps pushing
-- until generation genuinely stretches frames.
TerrainConfig.GenerateFrameTargetSeconds = 0.018
TerrainConfig.GenerateFrameCeilingSeconds = 0.026
TerrainConfig.GenerateFrameSmoothing = 0.1
TerrainConfig.GenerateBudgetRiseStep = 0.0005
TerrainConfig.GenerateBudgetFallStep = 0.001

-- How many chunks may build at once. This does NOT multiply throughput - they
-- all draw on the same per-frame allowance - it stops one chunk stuck in a
-- non-sliced section stalling the queue. Keep it low: chunks are dequeued
-- nearest-first, and splitting the allowance makes the nearest one, the one the
-- player is standing at the edge of, take proportionally longer.
TerrainConfig.MaxConcurrentChunks = 2

-- Low-frequency fields (climate, broad elevation) are sampled on a lattice
-- every LatticeStep blocks and bilinearly interpolated: 5x5 = 25 samples per
-- chunk instead of 256. Aligned to global block coordinates, so interpolation
-- is seamless across borders. ChunkSize must be divisible by this.
TerrainConfig.LatticeStep = 4

--[[
	Bounded pure-function caches, so dropping an entry is always safe. Held in
	two generations rather than LRU-evicted: lookups stay O(1), and a full
	generation is demoted instead of the cache being wiped, so columns a player
	is standing on are not thrown away and immediately recomputed. Each
	generation is capped at half the limit.

	The column cache has to hold the whole working set in ONE generation, or
	every rotation promotes it straight back. That set is the loaded columns:

	  (2 * ViewDistanceChunks + 1)^2 * ChunkSize^2
	    VD 2 -> 6,400   VD 3 -> 12,544   VD 4 -> 20,736   VD 5 -> 30,976

	Sized for VD 5 with room to spare. Watch Terrain.columnCacheRotated in the
	profiler: rotations climbing while the player stands still means too small.
]]
TerrainConfig.LatticeCacheLimit = 40000
TerrainConfig.ColumnCacheLimit = 100000
TerrainConfig.CandidateCacheLimit = 400

--[[
	Parts are pooled per block name rather than destroyed. MaxPoolPerType is the
	hard ceiling; MinPoolPerType is the working set kept even for a block type
	that has gone quiet, so walking back into a biome does not re-clone it.

	Between the two, pools follow demand: each trim releases PoolTrimFraction of
	whatever provably sat idle for the whole interval. Without that decay a pool
	only ever grew. PoolTrimMaxPerTick bounds one pass so reclaiming memory
	cannot itself become the frame spike.
]]
TerrainConfig.MaxPoolPerType = 768
TerrainConfig.MinPoolPerType = 32
TerrainConfig.PoolTrimInterval = 6
TerrainConfig.PoolTrimFraction = 0.5
TerrainConfig.PoolTrimMaxPerTick = 256

-- Player edits cannot be recomputed from the seed, so ChunkEdits remembers
-- them - and unbounded that grows for the life of the server. Two ceilings,
-- because either alone can be defeated: many lightly-edited chunks, or one
-- chunk somebody tunnelled through for an hour. 6000 is roughly 100x the
-- working set at view distance 5, so neither should fire in a normal session.
TerrainConfig.MaxEditedChunks = 6000
TerrainConfig.MaxStoredEdits = 400000

--[[
	Merge neighbouring same-type blocks on a layer into one elongated Part
	instead of one Part per block. See Shared.Terrain.TerrainMesher.

	The benchmark measured 148k client Instances at view distance 4 and 222k at
	5, against 37.7 and 23.3 fps standing still - and a flat 7.16 client
	Instances per server Part at every distance, which is the face textures
	riding on each block. Merging N blocks removes their textures too, so the
	saving applies to the whole 7.16x.

	Setting this false does not restore the old renderer; it makes the mesher
	emit one rectangle per block, which isolates a bug in the MERGING from a bug
	in the machinery around it.

	Blocks whose template carries a Decal are never merged - a Decal stretches
	to fit its face. Textures tile per block, which is why merging keeps the
	look.
]]
TerrainConfig.MergeSurfaceRuns = true

-- Rewrite Decal faces on block templates as tiled Textures at startup, which
-- is what makes MergeSurfaceRuns possible for decalled blocks. Lossless on a
-- single cube - same image, face, colour and transparency, one tile per block.
TerrainConfig.ConvertDecalsToTextures = true

TerrainConfig.CastTerrainShadows = false
TerrainConfig.CastStructureShadows = true

--[[
	How water looks. Water is Roblox Terrain (see TerrainManager, WATER), so
	these are Terrain's own water settings, applied when the terrain starts.

	Waves are kept small: in a world of square blocks a gentle shimmer reads as
	water, a rolling sea reads as a different game. Colour and transparency
	were picked to match the old water blocks.
]]
TerrainConfig.Water = {
	Color = Color3.fromRGB(38, 104, 164),
	Transparency = 0.55,
	Reflectance = 0.35,
	WaveSize = 0.05,
	WaveSpeed = 8,
}

-- Tried in order when a biome asks for a template that is not in
-- ReplicatedStorage.TerrainAssets.Blocks.
TerrainConfig.BlockFallbackOrder = { "Dirt", "Grass", "Sand", "Snow", "Sandstone", "Water" }

-- ===========================================================================
-- ISLAND PLACE
-- ===========================================================================

--[[
	In the Island place the same engine builds one small island instead of the
	open world: a far smaller grid, a shallower floor and a fixed seed, so every
	island's untouched ground is identical and only players' changes need to be
	saved. The values live in IslandConfig.Terrain.

	Applied here, before anything is derived, so the client and every server
	module read one consistent set of numbers.
]]
local PlaceConfig = require(script.Parent.Parent:WaitForChild("PlaceConfig"))
if PlaceConfig.isIsland() then
	local IslandConfig = require(script.Parent:WaitForChild("IslandConfig"))
	-- Checked against a list rather than "already has a value", because some
	-- settings (WorldSeed) are legitimately nil in the open world.
	local overridable = {
		GridChunksX = true,
		GridChunksZ = true,
		WorldFloorY = true,
		WorldSeed = true,
		EdgeFalloffBlocks = true,
	}
	for key, value in pairs(IslandConfig.Terrain) do
		assert(overridable[key], "[TerrainConfig] IslandConfig.Terrain cannot override " .. key)
		TerrainConfig[key] = value
	end
end

-- ===========================================================================
-- DERIVED
-- ===========================================================================

-- Highest block layer anything may occupy: structures, and player building.
TerrainConfig.WorldCeilingY = TerrainConfig.MaxHeight + TerrainConfig.StructureHeadroom

TerrainConfig.ChunkStuds = TerrainConfig.ChunkSize * TerrainConfig.StudSize
TerrainConfig.HalfChunksX = math.floor((TerrainConfig.GridChunksX - 1) / 2)
TerrainConfig.HalfChunksZ = math.floor((TerrainConfig.GridChunksZ - 1) / 2)
TerrainConfig.MinChunkX = -TerrainConfig.HalfChunksX
TerrainConfig.MaxChunkX = TerrainConfig.HalfChunksX
TerrainConfig.MinChunkZ = -TerrainConfig.HalfChunksZ
TerrainConfig.MaxChunkZ = TerrainConfig.HalfChunksZ

-- Half-extent of the world in blocks, from the origin.
TerrainConfig.WorldRadiusBlocks = (TerrainConfig.HalfChunksX + 0.5) * TerrainConfig.ChunkSize

-- Fails loudly at require time rather than leaving you to debug a tiling world.
function TerrainConfig.validate()
	assert(
		TerrainConfig.ChunkSize % TerrainConfig.LatticeStep == 0,
		"[TerrainConfig] ChunkSize must be divisible by LatticeStep or the lattice will seam"
	)
	assert(
		TerrainConfig.MaxHeight > TerrainConfig.MinHeight,
		"[TerrainConfig] MaxHeight must exceed MinHeight"
	)
	assert(
		TerrainConfig.StudSize == 4,
		"[TerrainConfig] StudSize is locked at 4; PlacementServer's build grid assumes it"
	)
	assert(
		TerrainConfig.WorldFloorY < 0 and TerrainConfig.WorldFloorY < TerrainConfig.MinHeight,
		"[TerrainConfig] WorldFloorY must sit below ground level"
	)
	assert(
		TerrainConfig.SpawnGuaranteeBlocks < TerrainConfig.SpawnSafeRadiusBlocks,
		"[TerrainConfig] SpawnGuaranteeBlocks must be smaller than SpawnSafeRadiusBlocks, "
			.. "or the guaranteed area has no room to blend into the world"
	)
	assert(
		TerrainConfig.EdgeFalloffBlocks < TerrainConfig.WorldRadiusBlocks,
		"[TerrainConfig] EdgeFalloffBlocks must be smaller than the world radius"
	)

	-- Noise scales live in LandformConfig now, and LandformConfig.validate
	-- checks them against Perlin's period at this world size.
end

return TerrainConfig
