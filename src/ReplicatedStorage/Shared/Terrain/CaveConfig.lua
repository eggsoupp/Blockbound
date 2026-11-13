--[[
	CaveConfig

	Every tunable for the underground: how often caves occur, how long and how
	big they get, how much ground must stay between them and the surface, and
	how each biome flavours them. CaveMap reads this and TerrainManager carves
	what it says. Nothing in here is code - a biome's caves change by editing
	its profile. What grows in a cave is CaveDecorConfig; what ore shows on its
	walls is OreConfig.CaveExposure.

	FOUR KINDS OF CAVE

	  Small     the ones a new player trips over: usually a sloped mouth, then
	            a winding tunnel a hundred blocks or so long with a branch or
	            two and the odd room. Shallow and common.

	  Network   the long ones. A narrow tunnel that winds for several hundred
	            blocks, sinking as it goes, swelling into wide stretches and
	            rooms, throwing off branches that loop back, spiral down, end
	            in a pocket or climb out to the surface - and tunnelling across
	            to whatever other caves lie in reach, which is what turns
	            separate caves into one system.

	  Large     rare, deep chamber systems: two to four big chambers joined by
	            broad passages, with sub-chambers, ledges and side tunnels.

	  Colossal  the rare discovery: an enormous hall of overlapping lobes,
	            hundreds of studs across, with terraces, galleries up on its
	            walls and long narrow feeder tunnels leading away - so the way
	            in is a tight passage that opens into it.

	All four are PLANNED, not sprinkled. The world is cut into a grid of cells
	per category; each cell hashes to decide whether it hosts a plan, and the
	plan is a list of capsules (tunnels, which may taper) and ellipsoids
	(rooms, chambers, lobes) in absolute block coordinates. Every chunk that a
	plan reaches rebuilds the same plan from the same hash, so a tunnel
	crossing a chunk border continues exactly, whatever order the chunks load
	in. See CaveMap.

	NO ABRUPT DEAD ENDS. Every tunnel that stops does one of three things:
	joins another part of its cave (a loop), climbs out to a mouth on the
	surface, or opens into a rounded pocket.

	UNITS: blocks (TerrainConfig.StudSize studs). Depths are blocks below the
	surface of the column in question.

	=========================================================================
	BIOME PROFILE FIELDS
	=========================================================================

	A biome profile lists only what differs from CaveConfig.Default; everything
	else is filled in from Default when this module loads.

	  smallFrequency, networkFrequency, largeFrequency, colossalFrequency
	                                   multiply the category's base chance.
	                                   0 switches that category off here.
	  depth = { small, network, networkEnd, large, colossal }   each {min,max}
	                                   small / network / large / colossal: how
	                                   deep that kind of cave starts (its hub).
	                                   small is also how deep a small cave's
	                                   tunnels wander; networkEnd is how deep
	                                   the far end of a network gets.
	  tunnelRadius = {min,max}         ordinary tunnels and entrances. Keep min
	                                   at or above Entrance.MinRadius so a
	                                   character fits.
	  wideRadius = {min,max}           what a tunnel swells to for a stretch.
	  passageRadius = {min,max}        the broad passages of large systems.
	  roomRadius = {min,max}           rooms along tunnels, and sub-chambers.
	  chamberRadius = {min,max}        large-cave chambers (horizontal).
	  cavernRadius = {min,max}         one lobe of a colossal hall (horizontal).
	  chamberFlatten                   vertical radius of a room or chamber as
	                                   a fraction of the horizontal one. Low is
	                                   a wide low hall, high is a dome.
	  cavernFlatten                    the same for a colossal lobe. This is
	                                   the dial for how TALL the great halls
	                                   are, which is most of what they cost to
	                                   draw; keep it low.
	  verticality      0..1            how steeply tunnels climb and drop.
	  roughness        0..1            how far the walls wander off the clean
	                                   shape. 0 is geometric, 1 is ragged.
	  angularity       0..1            0 keeps rooms rounded; 1 squares them
	                                   off (Snow's ice-block look).
	  entranceChance                   chance a small cave has a mouth.
	  networkEntranceChance            ... a network has one at its start.
	  largeEntranceChance              ... a large system has one.
	  exitChance                       chance a branch or feeder that ends near
	                                   the surface climbs out through a mouth
	                                   of its own instead of ending in a pocket.
	  materials = { floor, ceiling, wall }
	                                   block names to restyle the cave's
	                                   surfaces with, or nil to leave the
	                                   natural rock. Usually empty now: the
	                                   rock is already the biome's own stone
	                                   (BiomeConfig `stoneBlock`).
	  content = {...}                  tags and densities future chest / enemy
	                                   placement can key on. Candidates carry
	                                   them (see CaveMap.getCandidates).
]]

local TerrainFolder = script.Parent
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))
local StrataConfig = require(TerrainFolder:WaitForChild("StrataConfig"))
local BiomeConfig = require(TerrainFolder:WaitForChild("BiomeConfig"))

local CaveConfig = {}

-- Master switch. Off, and TerrainManager never asks CaveMap anything.
CaveConfig.Enabled = true

-- An island is a building plot, and its template is part of every save, so
-- it stays solid.
CaveConfig.EnabledOnIsland = false

--[[
	One dial for "more / fewer caves of every kind": multiplies every
	category's Chance (the result is capped at 1).

	THIS IS A COST DIAL. A chunk with a tunnel through it draws about twice the
	blocks of one without, and they merge into Parts far less well than open
	ground does: measured at these settings, about 110 Parts against 41. So
	the share of chunks that hold cave is what the underground costs, in Parts
	held by the server and streamed to clients and in chunk build time. At 1.0
	roughly one chunk in seven holds cave (it was one in twenty-five before
	the overhaul), which works out at about a quarter more Parts across the
	world; a route chosen to pass over a network, a large system and a colossal
	hall measured 31% more Parts and 24% more build time per chunk. Raise it
	and both go up in proportion; /bbprof (Terrain.cave.chunksWithCaves
	against Terrain.chunkGenerated, and Terrain.chunkUnloadParts) says where
	a setting landed.
]]
CaveConfig.DensityMultiplier = 1.0

-- ===========================================================================
-- SAFETY
-- ===========================================================================

-- Solid ground kept between any cave and the surface, except where a plan
-- deliberately opens an entrance. Tunnels that would come closer are capped
-- at this depth; they do not break through.
CaveConfig.MinSurfaceCoverBlocks = 4

-- Thicker cover under standing water (lakes, rivers, the sea), so a cave
-- passing beneath a lake never opens into it. Water lives in
-- [height, waterTop) and caves stay below height, so this is belt and braces.
CaveConfig.MinSurfaceCoverUnderWaterBlocks = 8

-- Solid rock kept above the bedrock layers. Must be at least 1 so a restyled
-- cave floor can never land on bedrock and make it mineable.
CaveConfig.MinFloorThicknessBlocks = 4

-- No cave air inside this square (Chebyshev) distance of the origin, in
-- blocks. Larger than TerrainConfig.SpawnGuaranteeBlocks so the guaranteed
-- starting chunks are solid ground throughout. Tunnels steer round it, and
-- the carver refuses the square outright as well.
CaveConfig.SpawnExclusionBlocks = TerrainConfig.SpawnGuaranteeBlocks + 32

-- How far outside that square a cave must START. Tunnels may then wander up
-- to the square's edge, so the first caves are not pushed a long walk away.
CaveConfig.SpawnOriginMarginBlocks = 24

-- No surface entrance inside this radius of the origin.
CaveConfig.EntranceSafeDistanceBlocks = 160

-- Surface entrances never open in a wet column.
CaveConfig.AllowUnderwaterEntrances = false

--[[
	Structures refuse to root on a column that has cave air within this many
	blocks below its surface, at the origin or anywhere in the footprint. The
	cave is planned first and the tree yields, which is what keeps a tree from
	standing over a hole.
]]
CaveConfig.StructureSupportDepthBlocks = 6

-- ===========================================================================
-- BOUNDS
-- ===========================================================================

-- How many plans may carve one chunk, counted after dropping the plans that
-- reach the chunk's neighbourhood but put nothing in it. A safety valve: in
-- practice a chunk sees one to four.
CaveConfig.MaxPlansPerChunk = 16

-- Hard ceiling on primitives in one plan, whatever the profile asks for. A
-- long network with all its branches is about 150.
CaveConfig.MaxPrimitivesPerPlan = 360

-- Ceilings every profile is checked against.
CaveConfig.MaxTunnelRadius = 5
CaveConfig.MaxChamberRadius = 14
CaveConfig.MaxCavernRadius = 34

-- Steepest tunnel a plan may draw, as rise over run. 1 is 45 degrees.
CaveConfig.MaxTunnelSlope = 0.9

--[[
	Rooms, chambers and cavern lobes are ellipsoids with the bottom cut off
	flat, so there is a floor to walk on rather than a bowl to slide into, and
	tunnels arrive at floor level. The cut sits this fraction of the vertical
	radius below the centre; the floor then undulates by a block either way.
]]
CaveConfig.ChamberFloorCut = 0.5

--[[
	The big chambers of large systems and the lobes of colossal halls are cut
	off level at the top as well, this fraction of the vertical radius above
	the centre, so a hall is (ChamberFloorCut + ChamberRoofCut) vertical radii
	tall with a roof that steps a block up or down in broad patches.

	This is a COST setting as much as a look. The terrain draws each layer of
	blocks as merged rectangles, and layers never merge with one another: a
	level roof is a few large Parts, where a dome is a stack of thin rings,
	one per layer, that barely merge at all. Rooms on tunnels, pockets and
	ledges are small enough to stay domed.
]]
CaveConfig.ChamberRoofCut = 0.6

-- ===========================================================================
-- ENTRANCES
-- ===========================================================================

CaveConfig.Entrance = {
	-- Rise over run of the entrance ramp. 0.5 is one block up for every two
	-- along: a step a character clears with an ordinary jump.
	MaxSlope = 0.5,

	-- Entrance and tunnel radius floor, so every passage is at least three
	-- blocks (12 studs) across and tall.
	MinRadius = 1.6,

	-- The ground around the mouth may vary this much, in blocks, or the
	-- entrance is not attempted there.
	MaxSurfaceRelief = 3,

	-- Surface heights an entrance may open at. Keeps mouths off beaches and
	-- off the very peaks.
	MinSurfaceHeight = 40,
	MaxSurfaceHeight = 170,

	-- A mouth is only attempted from a point this close under the surface:
	-- the ramp is two blocks long for every block of depth.
	MaxDepthBlocks = 34,
}

-- ===========================================================================
-- TUNNELS
-- ===========================================================================

--[[
	How a tunnel walks. Shared by every category; the numbers that differ per
	category (how many segments, how long) are in Categories below.

	  CurlDegrees        how much the bend may change from one segment to the
	                     next. The bend carries over, so a tunnel swings in
	                     long curves instead of zig-zagging.
	  MaxTurnDegrees     the sharpest bend between two segments.
	  SpiralTurnDegrees  the bend held through a spiral descent, {min,max}.
	  SpiralSegments     how many segments a spiral lasts, {min,max}.
	  WidenChance        per segment, the chance the tunnel starts swelling
	                     toward the profile's wideRadius...
	  WidenSegments      ... for this many segments, {min,max}, easing in and
	                     back out so it widens gradually.
	  LoopReachBlocks    a tunnel end joins another part of its own cave if
	                     one lies within this distance.
	  LoopChance         ... with this chance when one does.
	  PocketRadius       the rounded room a tunnel ends in otherwise, as a
	                     multiple of the tunnel's radius, {min,max}.
]]
CaveConfig.Tunnel = {
	CurlDegrees = 30,
	MaxTurnDegrees = 52,
	SpiralTurnDegrees = { min = 56, max = 78 },
	SpiralSegments = { min = 3, max = 5 },
	WidenChance = 0.09,
	WidenSegments = { min = 3, max = 6 },
	LoopReachBlocks = 30,
	LoopChance = 0.75,
	PocketRadius = { min = 1.6, max = 2.3 },
}

--[[
	Vertical passages. Where two parts of one cave pass nearly above one
	another, a steep shaft may join them. Both ends are already connected the
	long way round by walkable tunnel, so a shaft is a shortcut and a feature,
	never the only way through.

	Keep them, and spiral descents (a category's SpiralChance), occasional.
	Anything vertical is the most expensive shape a cave can take: its wall is
	a separate ring of Parts on every layer it passes. A spiral with a shaft
	down the middle of it measured 673 Parts in one chunk, against about 40
	for plain ground and about 110 for a chunk with an ordinary tunnel.

	  MinDropBlocks / MaxDropBlocks   how tall a shaft may be
	  MaxOffsetBlocks                 how far apart its ends may be sideways
	  Radius                          {min,max}
]]
CaveConfig.Shaft = {
	MinDropBlocks = 8,
	MaxDropBlocks = 26,
	MaxOffsetBlocks = 11,
	Radius = { min = 2.0, max = 2.8 },
}

--[[
	Links between caves. A plan that rolls under its category's LinkChance
	tunnels across to the start (the hub) of up to MaxLinks other caves whose
	hubs lie inside its own extent box. The rest stay isolated. Of two caves
	that could each reach for the other only one does, so a pair is joined by
	one tunnel, not two.

	  MinBlocks / MaxBlocks  how long a link may be, hub to nearest tunnel
	  SegmentBlocks          roughly how long each bend of a link is
]]
CaveConfig.Link = {
	MinBlocks = 10,
	MaxBlocks = 130,
	SegmentBlocks = 12,
}

-- ===========================================================================
-- SHAPE NOISE
-- ===========================================================================

-- Wall roughness is a 3D noise warp of each primitive's radius, sampled at
-- this scale in blocks. Larger reads as gentle undulation, smaller as
-- knobbly rock. It perturbs a coherent shape rather than thresholding noise,
-- which is why it cannot leave stray one-block pockets.
CaveConfig.RoughnessScaleBlocks = 7

-- Cavern lobes are warped at this scale instead: a wall thirty blocks out
-- wants broad buttresses and bays, not the knobbles of a tunnel.
CaveConfig.CavernRoughnessScaleBlocks = 13

-- The most a wall may move, as a fraction of the radius, at roughness 1.
CaveConfig.RoughnessAmplitude = 0.45

-- ===========================================================================
-- CATEGORIES
-- ===========================================================================

--[[
	Shared fields:

	  CellBlocks       grid cell edge. One cell hosts at most one plan.
	  Chance           chance a cell hosts a plan, before the biome multiplier
	                   and CaveConfig.DensityMultiplier.
	  MaxExtentBlocks  nothing a plan draws is centred further than this from
	                   its origin (a square box).
	  HubDepthSpread   the hub sits between the profile's depth.min for the
	                   category and this many blocks below that.
	  LinkChance, MaxLinks   see CaveConfig.Link.
	  Shafts           how many vertical shafts to look for, {min,max}.

	Tunnel fields (Small, Network, and the side tunnels of the other two):

	  Segments         how many segments the main tunnel has, {min,max}.
	  SegmentLength    blocks per segment, {min,max}.
	  Branches         side tunnels off the main one, {min,max}.
	  BranchSegments   how long each is, {min,max}.
	  SubBranchChance  chance a branch has a branch of its own.
	  RoomChance       per segment, the chance of a room there.
	  SpiralChance     per segment, the chance a spiral descent starts.
	  SlopeScale       multiplies the profile's verticality for this category.
]]
CaveConfig.Categories = {
	Small = {
		CellBlocks = 96,
		Chance = 0.3,
		MaxExtentBlocks = 92,
		HubDepthSpread = 9,

		Segments = { min = 3, max = 7 },
		SegmentLength = { min = 7, max = 14 },
		Branches = { min = 0, max = 2 },
		BranchSegments = { min = 2, max = 5 },
		SubBranchChance = 0,
		RoomChance = 0.13,
		SpiralChance = 0.01,
		SlopeScale = 1.0,

		Shafts = { min = 0, max = 1 },
		LinkChance = 0.4,
		MaxLinks = 1,
	},

	Network = {
		CellBlocks = 336,
		Chance = 0.2,
		MaxExtentBlocks = 236,
		HubDepthSpread = 18,

		Segments = { min = 20, max = 36 },
		SegmentLength = { min = 9, max = 17 },
		-- Chance the system also runs the other way from its hub, at about
		-- two thirds the length.
		TwoWayChance = 0.5,
		Branches = { min = 3, max = 7 },
		BranchSegments = { min = 4, max = 11 },
		SubBranchChance = 0.35,
		RoomChance = 0.1,
		SpiralChance = 0.02,
		SlopeScale = 1.1,

		Shafts = { min = 0, max = 2 },
		LinkChance = 0.75,
		MaxLinks = 3,
	},

	Large = {
		CellBlocks = 448,
		Chance = 0.38,
		MaxExtentBlocks = 150,
		HubDepthSpread = 70,

		Epicentres = { min = 2, max = 4 },
		-- Horizontal distance between neighbouring chambers.
		EpicentreSpacing = { min = 28, max = 60 },
		-- How far apart in height two chambers may sit.
		EpicentreLevelChange = 14,
		-- Passage polyline pieces between two chambers.
		PassageSegments = { min = 2, max = 4 },
		SubChambers = { min = 2, max = 5 },
		-- Shelves cut into chamber walls, per chamber.
		Ledges = { min = 1, max = 2 },
		-- Extra passage closing a loop between first and last chamber, when
		-- there are at least three.
		LoopChance = 0.5,

		-- Side tunnels wandering off the chambers and passages.
		Branches = { min = 2, max = 4 },
		BranchSegments = { min = 3, max = 8 },
		SegmentLength = { min = 8, max = 15 },
		SubBranchChance = 0.2,
		RoomChance = 0.08,
		SpiralChance = 0.02,
		SlopeScale = 1.0,

		Shafts = { min = 0, max = 1 },
		LinkChance = 0.65,
		MaxLinks = 2,
	},

	Colossal = {
		CellBlocks = 624,
		Chance = 0.36,
		MaxExtentBlocks = 230,
		HubDepthSpread = 60,

		-- The hall is this many overlapping lobes in a wandering line.
		Lobes = { min = 3, max = 6 },
		-- Distance between neighbouring lobe centres, as a fraction of the
		-- lobe's radius. Under 1 so they always overlap into one space.
		LobeSpacing = { min = 0.8, max = 1.25 },
		-- How far the floor may step between two lobes; a broad ramp is cut
		-- between them.
		LobeLevelChange = 5,
		-- Galleries: shelves high on a lobe's wall, each with a stair tunnel
		-- climbing round to it from the floor. Per lobe.
		Galleries = { min = 0, max = 2 },

		-- Feeders: the long narrow tunnels that lead away from the hall,
		-- climbing. FeederExitChance is the chance one that ends near the
		-- surface opens a mouth there (it replaces the profile's exitChance
		-- when higher).
		FeederExitChance = 0.65,
		Branches = { min = 2, max = 4 },
		BranchSegments = { min = 8, max = 18 },
		SegmentLength = { min = 9, max = 16 },
		SubBranchChance = 0.3,
		RoomChance = 0.06,
		SpiralChance = 0.015,
		SlopeScale = 1.1,

		Shafts = { min = 0, max = 1 },
		LinkChance = 0.9,
		MaxLinks = 3,
	},
}

-- The order CaveMap numbers them in. Small and Large keep 1 and 2.
CaveConfig.CategoryOrder = { "Small", "Large", "Network", "Colossal" }

-- ===========================================================================
-- BIOME PROFILES
-- ===========================================================================

CaveConfig.Default = {
	smallFrequency = 1.0,
	networkFrequency = 1.0,
	largeFrequency = 1.0,
	colossalFrequency = 1.0,
	depth = {
		small = { min = 5, max = 30 },
		network = { min = 10, max = 28 },
		networkEnd = { min = 34, max = 130 },
		large = { min = 30, max = 100 },
		colossal = { min = 58, max = 125 },
	},
	tunnelRadius = { min = 1.6, max = 2.4 },
	wideRadius = { min = 2.9, max = 4.2 },
	passageRadius = { min = 2.6, max = 3.6 },
	roomRadius = { min = 3, max = 5.5 },
	chamberRadius = { min = 7, max = 11 },
	cavernRadius = { min = 19, max = 30 },
	chamberFlatten = 0.7,
	cavernFlatten = 0.5,
	verticality = 0.32,
	roughness = 0.35,
	angularity = 0,
	entranceChance = 0.8,
	networkEntranceChance = 0.6,
	largeEntranceChance = 0.45,
	exitChance = 0.3,
	materials = {},
	content = {
		tags = { "generic" },
		decorationDensity = 0.5,
		chestDensity = 0.5,
		orePocketDensity = 0.5,
		enemyDensity = 0.5,
	},
}

CaveConfig.Biomes = {
	Plains = {
		entranceChance = 0.85,
		networkEntranceChance = 0.65,
		largeEntranceChance = 0.5,
		content = {
			tags = { "plains", "beginner", "temperate" },
			decorationDensity = 0.5,
			chestDensity = 0.6,
			orePocketDensity = 0.5,
			enemyDensity = 0.4,
		},
	},

	-- Broad, dry, low halls. Wide chambers, little climbing, smooth walls.
	Desert = {
		smallFrequency = 0.9,
		largeFrequency = 1.1,
		colossalFrequency = 1.15,
		depth = { small = { min = 8, max = 32 }, large = { min = 34, max = 104 } },
		tunnelRadius = { min = 1.8, max = 2.6 },
		wideRadius = { min = 3.2, max = 4.6 },
		passageRadius = { min = 3.0, max = 4.0 },
		roomRadius = { min = 4, max = 6 },
		chamberRadius = { min = 9, max = 13 },
		cavernRadius = { min = 22, max = 33 },
		chamberFlatten = 0.5,
		cavernFlatten = 0.42,
		verticality = 0.22,
		roughness = 0.25,
		angularity = 0.1,
		entranceChance = 0.7,
		content = {
			tags = { "desert", "dry", "broad" },
			decorationDensity = 0.3,
			chestDensity = 0.6,
			orePocketDensity = 0.6,
			enemyDensity = 0.5,
		},
	},

	-- Cold and angular: squared-off rooms, steeper tunnels, more broken walls.
	Snow = {
		smallFrequency = 0.85,
		largeFrequency = 0.9,
		depth = { small = { min = 6, max = 30 }, large = { min = 32, max = 100 } },
		tunnelRadius = { min = 1.6, max = 2.2 },
		passageRadius = { min = 2.5, max = 3.4 },
		chamberRadius = { min = 7, max = 10 },
		chamberFlatten = 0.75,
		verticality = 0.52,
		roughness = 0.45,
		angularity = 0.6,
		entranceChance = 0.65,
		networkEntranceChance = 0.45,
		content = {
			tags = { "snow", "cold", "angular" },
			decorationDensity = 0.4,
			chestDensity = 0.5,
			orePocketDensity = 0.6,
			enemyDensity = 0.5,
		},
	},

	-- Smooth, tall, elegant domes in the biome's own stone.
	Hallow = {
		smallFrequency = 0.9,
		depth = { small = { min = 6, max = 30 }, large = { min = 30, max = 96 } },
		tunnelRadius = { min = 1.7, max = 2.4 },
		passageRadius = { min = 2.8, max = 3.8 },
		chamberFlatten = 0.9,
		cavernFlatten = 0.58,
		verticality = 0.42,
		roughness = 0.2,
		entranceChance = 0.75,
		content = {
			tags = { "hallow", "bright", "elegant", "rare" },
			decorationDensity = 0.7,
			chestDensity = 0.7,
			orePocketDensity = 0.5,
			enemyDensity = 0.6,
		},
	},

	-- Organic, ragged, climbing and dropping. More caves, and more of them
	-- large.
	Corruption = {
		smallFrequency = 1.1,
		networkFrequency = 1.2,
		largeFrequency = 1.3,
		colossalFrequency = 1.2,
		depth = { small = { min = 6, max = 32 }, large = { min = 30, max = 110 } },
		tunnelRadius = { min = 1.6, max = 2.6 },
		passageRadius = { min = 2.6, max = 3.8 },
		roomRadius = { min = 4, max = 6 },
		chamberRadius = { min = 8, max = 12 },
		verticality = 0.6,
		roughness = 0.6,
		entranceChance = 0.6,
		networkEntranceChance = 0.45,
		content = {
			tags = { "corruption", "organic", "dangerous" },
			decorationDensity = 0.6,
			chestDensity = 0.5,
			orePocketDensity = 0.7,
			enemyDensity = 0.9,
		},
	},

	-- Organic like Corruption but wider and lower: fleshy halls.
	Crimson = {
		smallFrequency = 1.1,
		networkFrequency = 1.2,
		largeFrequency = 1.3,
		colossalFrequency = 1.2,
		depth = { small = { min = 6, max = 32 }, large = { min = 30, max = 110 } },
		tunnelRadius = { min = 1.7, max = 2.7 },
		wideRadius = { min = 3.2, max = 4.6 },
		passageRadius = { min = 2.8, max = 4.0 },
		roomRadius = { min = 4, max = 6 },
		chamberRadius = { min = 8, max = 12 },
		chamberFlatten = 0.6,
		verticality = 0.5,
		roughness = 0.55,
		entranceChance = 0.6,
		networkEntranceChance = 0.45,
		content = {
			tags = { "crimson", "organic", "dangerous" },
			decorationDensity = 0.6,
			chestDensity = 0.5,
			orePocketDensity = 0.7,
			enemyDensity = 0.9,
		},
	},

	-- Wet ground above, so fewer caves and fewer mouths; the thicker cover
	-- under water is global.
	Swamp = {
		smallFrequency = 0.7,
		networkFrequency = 0.7,
		largeFrequency = 0.6,
		colossalFrequency = 0.6,
		depth = { small = { min = 8, max = 28 }, large = { min = 32, max = 90 } },
		passageRadius = { min = 2.6, max = 3.4 },
		chamberRadius = { min = 7, max = 10 },
		chamberFlatten = 0.6,
		verticality = 0.3,
		roughness = 0.4,
		entranceChance = 0.55,
		networkEntranceChance = 0.4,
		largeEntranceChance = 0.4,
		content = {
			tags = { "swamp", "wet" },
			decorationDensity = 0.5,
			chestDensity = 0.5,
			orePocketDensity = 0.5,
			enemyDensity = 0.6,
		},
	},
}

-- Fill every profile in from Default, so the rest of the code never has to
-- ask whether a field is there. `depth` is merged a level deeper, since a
-- biome usually changes one or two of its bands.
for _, profile in pairs(CaveConfig.Biomes) do
	for key, value in pairs(CaveConfig.Default) do
		if profile[key] == nil then
			profile[key] = value
		elseif key == "depth" then
			for band, range in pairs(value) do
				if profile.depth[band] == nil then
					profile.depth[band] = range
				end
			end
		end
	end
end

-- ===========================================================================
-- CACHES
-- ===========================================================================

-- Per-chunk carve records, per-cell plans and per-cell sites are pure
-- functions of the seed, held in two generations like TerrainManager's column
-- cache. The record cache has to hold, in ONE generation (half the limit),
-- the loaded set plus the three chunks around it that structure planning asks
-- about: 21 x 21 = 441 records at view distance 7. Most records are the one
-- shared empty table. A plan is its primitives - a few hundred small tables
-- for the longest network - and one player's surroundings touch about sixty
-- plan cells, most of them hosting nothing.
CaveConfig.RecordCacheLimit = 1600
CaveConfig.PlanCacheLimit = 768
CaveConfig.SiteCacheLimit = 4096

-- ===========================================================================
-- DERIVED AND VALIDATION
-- ===========================================================================

local FREQUENCY_FIELD = {
	Small = "smallFrequency",
	Network = "networkFrequency",
	Large = "largeFrequency",
	Colossal = "colossalFrequency",
}
CaveConfig.FrequencyField = FREQUENCY_FIELD

-- Which profile.depth band says where a category's hub sits.
CaveConfig.DepthField = {
	Small = "small",
	Network = "network",
	Large = "large",
	Colossal = "colossal",
}

function CaveConfig.profileFor(biomeName)
	return CaveConfig.Biomes[biomeName] or CaveConfig.Default
end

-- The largest frequency any profile declares, for the cheap rejection that
-- runs before a plan's origin column is ever sampled.
function CaveConfig.maxFrequency(category)
	local field = FREQUENCY_FIELD[category]
	local best = CaveConfig.Default[field]
	for _, profile in pairs(CaveConfig.Biomes) do
		if profile[field] > best then
			best = profile[field]
		end
	end
	return best
end

local function assertRange(range, label, low, high)
	assert(type(range) == "table" and type(range.min) == "number" and type(range.max) == "number",
		label .. " needs {min, max}")
	assert(range.min <= range.max, label .. " needs min <= max")
	assert(range.min >= low, string.format("%s.min must be at least %s", label, tostring(low)))
	assert(range.max <= high, string.format("%s.max must be at most %s", label, tostring(high)))
end

local function assertUnit(value, label)
	assert(type(value) == "number" and value >= 0 and value <= 1, label .. " must be in [0, 1]")
end

local function validateProfile(name, profile)
	local label = "[CaveConfig] " .. name
	local entrance = CaveConfig.Entrance

	for _, field in pairs(FREQUENCY_FIELD) do
		assert(type(profile[field]) == "number" and profile[field] >= 0,
			string.format("%s.%s must be >= 0", label, field))
	end

	assert(type(profile.depth) == "table", label .. ".depth is required")
	for _, band in ipairs({ "small", "network", "networkEnd", "large", "colossal" }) do
		assertRange(profile.depth[band], label .. ".depth." .. band, 1, 200)
	end
	assert(profile.depth.large.min >= profile.depth.small.min,
		label .. ": large caves should start no shallower than small ones")
	assert(profile.depth.networkEnd.min >= profile.depth.network.min,
		label .. ": a network should end no shallower than it starts")

	assertRange(profile.tunnelRadius, label .. ".tunnelRadius", entrance.MinRadius, CaveConfig.MaxTunnelRadius)
	assertRange(profile.wideRadius, label .. ".wideRadius", entrance.MinRadius, CaveConfig.MaxTunnelRadius)
	assertRange(profile.passageRadius, label .. ".passageRadius", entrance.MinRadius, CaveConfig.MaxTunnelRadius)
	assertRange(profile.roomRadius, label .. ".roomRadius", 2, CaveConfig.MaxChamberRadius)
	assertRange(profile.chamberRadius, label .. ".chamberRadius", 4, CaveConfig.MaxChamberRadius)
	assertRange(profile.cavernRadius, label .. ".cavernRadius", 8, CaveConfig.MaxCavernRadius)

	assert(type(profile.chamberFlatten) == "number" and profile.chamberFlatten > 0.2 and profile.chamberFlatten <= 1.2,
		label .. ".chamberFlatten must be in (0.2, 1.2]")
	assert(type(profile.cavernFlatten) == "number" and profile.cavernFlatten >= 0.25 and profile.cavernFlatten <= 0.8,
		label .. ".cavernFlatten must be in [0.25, 0.8]")
	assertUnit(profile.verticality, label .. ".verticality")
	assertUnit(profile.roughness, label .. ".roughness")
	assertUnit(profile.angularity, label .. ".angularity")
	assertUnit(profile.entranceChance, label .. ".entranceChance")
	assertUnit(profile.networkEntranceChance, label .. ".networkEntranceChance")
	assertUnit(profile.largeEntranceChance, label .. ".largeEntranceChance")
	assertUnit(profile.exitChance, label .. ".exitChance")

	assert(type(profile.materials) == "table", label .. ".materials must be a table (may be empty)")
	for key, value in pairs(profile.materials) do
		assert(key == "floor" or key == "ceiling" or key == "wall",
			label .. ".materials has unknown key " .. tostring(key))
		assert(type(value) == "string" and value ~= "", label .. ".materials." .. key .. " must be a block name")
	end

	assert(type(profile.content) == "table" and type(profile.content.tags) == "table",
		label .. ".content.tags is required")
end

--[[
	Fails loudly at init rather than carving a world that cannot be stood in.
]]
function CaveConfig.validate()
	local entrance = CaveConfig.Entrance

	assert(CaveConfig.DensityMultiplier >= 0, "[CaveConfig] DensityMultiplier must not be negative")
	assert(CaveConfig.MinSurfaceCoverBlocks >= 1, "[CaveConfig] MinSurfaceCoverBlocks must be at least 1")
	assert(CaveConfig.MinSurfaceCoverUnderWaterBlocks >= CaveConfig.MinSurfaceCoverBlocks,
		"[CaveConfig] cover under water must not be thinner than cover on land")
	assert(CaveConfig.MinFloorThicknessBlocks >= 1,
		"[CaveConfig] MinFloorThicknessBlocks must be at least 1, or a restyled floor could land on bedrock")
	assert(CaveConfig.SpawnExclusionBlocks >= TerrainConfig.SpawnGuaranteeBlocks,
		"[CaveConfig] SpawnExclusionBlocks must cover the guaranteed spawn area")
	assert(CaveConfig.SpawnOriginMarginBlocks >= 8,
		"[CaveConfig] SpawnOriginMarginBlocks must leave a cave room to start outside the spawn square")
	assert(CaveConfig.EntranceSafeDistanceBlocks >= CaveConfig.SpawnExclusionBlocks,
		"[CaveConfig] EntranceSafeDistanceBlocks must be at least SpawnExclusionBlocks")
	assert(CaveConfig.StructureSupportDepthBlocks >= 1, "[CaveConfig] StructureSupportDepthBlocks must be positive")

	assert(CaveConfig.MaxPlansPerChunk >= 4, "[CaveConfig] MaxPlansPerChunk is too small")
	assert(CaveConfig.MaxPrimitivesPerPlan >= 32, "[CaveConfig] MaxPrimitivesPerPlan is too small to draw a cave")
	assert(CaveConfig.MaxTunnelRadius >= entrance.MinRadius, "[CaveConfig] MaxTunnelRadius below Entrance.MinRadius")
	assert(CaveConfig.MaxChamberRadius > CaveConfig.MaxTunnelRadius, "[CaveConfig] MaxChamberRadius must exceed MaxTunnelRadius")
	assert(CaveConfig.MaxCavernRadius >= CaveConfig.MaxChamberRadius, "[CaveConfig] MaxCavernRadius must be at least MaxChamberRadius")
	assert(CaveConfig.MaxTunnelSlope > 0 and CaveConfig.MaxTunnelSlope <= 1.5, "[CaveConfig] MaxTunnelSlope must be in (0, 1.5]")
	assert(CaveConfig.ChamberFloorCut > 0.1 and CaveConfig.ChamberFloorCut <= 1,
		"[CaveConfig] ChamberFloorCut must be in (0.1, 1]")
	assert(CaveConfig.ChamberRoofCut > 0.2 and CaveConfig.ChamberRoofCut <= 1,
		"[CaveConfig] ChamberRoofCut must be in (0.2, 1]")

	assert(entrance.MaxSlope > 0 and entrance.MaxSlope <= CaveConfig.MaxTunnelSlope,
		"[CaveConfig] Entrance.MaxSlope must be positive and no steeper than MaxTunnelSlope")
	assert(entrance.MinRadius >= 1.5, "[CaveConfig] Entrance.MinRadius under 1.5 does not fit a character")
	assert(entrance.MaxSurfaceRelief >= 0, "[CaveConfig] Entrance.MaxSurfaceRelief must be >= 0")
	assert(entrance.MinSurfaceHeight < entrance.MaxSurfaceHeight, "[CaveConfig] Entrance surface height band is empty")
	assert(entrance.MaxDepthBlocks > CaveConfig.MinSurfaceCoverBlocks, "[CaveConfig] Entrance.MaxDepthBlocks is under the cover")

	local tunnel = CaveConfig.Tunnel
	assert(tunnel.CurlDegrees >= 0 and tunnel.MaxTurnDegrees > 0 and tunnel.MaxTurnDegrees < 90,
		"[CaveConfig] Tunnel turn limits must be under 90 degrees")
	assertRange(tunnel.SpiralTurnDegrees, "[CaveConfig] Tunnel.SpiralTurnDegrees", 30, 100)
	assertRange(tunnel.SpiralSegments, "[CaveConfig] Tunnel.SpiralSegments", 2, 16)
	assertRange(tunnel.WidenSegments, "[CaveConfig] Tunnel.WidenSegments", 1, 16)
	assertRange(tunnel.PocketRadius, "[CaveConfig] Tunnel.PocketRadius", 1.2, 4)
	assertUnit(tunnel.WidenChance, "[CaveConfig] Tunnel.WidenChance")
	assertUnit(tunnel.LoopChance, "[CaveConfig] Tunnel.LoopChance")

	local shaft = CaveConfig.Shaft
	assert(shaft.MinDropBlocks >= 4 and shaft.MaxDropBlocks > shaft.MinDropBlocks, "[CaveConfig] Shaft drop band is empty")
	assertRange(shaft.Radius, "[CaveConfig] Shaft.Radius", entrance.MinRadius, CaveConfig.MaxTunnelRadius)

	local link = CaveConfig.Link
	assert(link.MinBlocks > 0 and link.MaxBlocks > link.MinBlocks and link.SegmentBlocks >= 4,
		"[CaveConfig] Link lengths are inconsistent")

	assert(CaveConfig.RoughnessScaleBlocks > 0 and CaveConfig.CavernRoughnessScaleBlocks > 0,
		"[CaveConfig] roughness scales must be positive")
	assertUnit(CaveConfig.RoughnessAmplitude, "[CaveConfig] RoughnessAmplitude")
	assert(CaveConfig.RoughnessAmplitude < 0.5, "[CaveConfig] RoughnessAmplitude must stay under 0.5 or a tunnel can pinch shut")

	assert(
		CaveConfig.RecordCacheLimit >= 64 and CaveConfig.PlanCacheLimit >= 64 and CaveConfig.SiteCacheLimit >= 64,
		"[CaveConfig] cache limits are too small"
	)

	for _, name in ipairs(CaveConfig.CategoryOrder) do
		local category = CaveConfig.Categories[name]
		local label = "[CaveConfig] Categories." .. name
		assert(category, label .. " is in CategoryOrder but not defined")
		assert(category.CellBlocks >= TerrainConfig.ChunkSize, label .. ".CellBlocks must be at least one chunk")
		assertUnit(category.Chance, label .. ".Chance")
		assert(category.MaxExtentBlocks > 0 and category.MaxExtentBlocks < 2 * category.CellBlocks,
			label .. ".MaxExtentBlocks must be positive and under two cells, or the neighbourhood search is unbounded")
		assert(type(category.HubDepthSpread) == "number" and category.HubDepthSpread >= 0,
			label .. ".HubDepthSpread must be a non-negative number")
		assertUnit(category.LinkChance, label .. ".LinkChance")
		assert(category.MaxLinks >= 1, label .. ".MaxLinks must be at least 1")
		assertRange(category.Shafts, label .. ".Shafts", 0, 8)
		assertRange(category.Branches, label .. ".Branches", 0, 16)
		assertRange(category.BranchSegments, label .. ".BranchSegments", 1, 48)
		assertRange(category.SegmentLength, label .. ".SegmentLength", 4, 32)
		assertUnit(category.SubBranchChance, label .. ".SubBranchChance")
		assertUnit(category.RoomChance, label .. ".RoomChance")
		assertUnit(category.SpiralChance, label .. ".SpiralChance")
		assert(category.SlopeScale > 0, label .. ".SlopeScale must be positive")
	end
	assert(#CaveConfig.CategoryOrder == 4 and CaveConfig.CategoryOrder[1] == "Small" and CaveConfig.CategoryOrder[2] == "Large",
		"[CaveConfig] CategoryOrder must be Small, Large, Network, Colossal")
	assertRange(CaveConfig.Categories.Small.Segments, "[CaveConfig] Categories.Small.Segments", 1, 64)
	assertRange(CaveConfig.Categories.Network.Segments, "[CaveConfig] Categories.Network.Segments", 4, 96)
	assertRange(CaveConfig.Categories.Colossal.Lobes, "[CaveConfig] Categories.Colossal.Lobes", 1, 10)
	assertRange(CaveConfig.Categories.Colossal.LobeSpacing, "[CaveConfig] Categories.Colossal.LobeSpacing", 0.3, 1.6)

	-- The world has to be deep enough for the deepest allowed cave to keep
	-- its floor above the bedrock margin and its roof under the thinnest
	-- surface.
	local floorLimit = TerrainConfig.WorldFloorY + StrataConfig.BedrockThickness + CaveConfig.MinFloorThicknessBlocks
	local shallowestSurface = TerrainConfig.MinHeight
	assert(
		shallowestSurface - CaveConfig.MinSurfaceCoverBlocks - floorLimit >= 2 * CaveConfig.MaxChamberRadius,
		"[CaveConfig] the world is not deep enough between MinHeight and WorldFloorY for MaxChamberRadius"
	)

	validateProfile("Default", CaveConfig.Default)
	for name, profile in pairs(CaveConfig.Biomes) do
		validateProfile(name, profile)
		if not BiomeConfig.Definitions[name] then
			warn(string.format("[CaveConfig] profile '%s' names a biome BiomeConfig does not define", name))
		end
	end

	for _, biomeName in ipairs(BiomeConfig.Order) do
		if not CaveConfig.Biomes[biomeName] then
			warn(string.format("[CaveConfig] biome '%s' has no cave profile; using Default", biomeName))
		end
	end
end

return CaveConfig
