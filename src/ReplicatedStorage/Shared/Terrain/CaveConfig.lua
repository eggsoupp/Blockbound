--[[
	CaveConfig

	Every tunable for the underground: how often caves occur, how big they get,
	how much ground must stay between them and the surface, and how each biome
	flavours them. CaveMap reads this and TerrainManager carves what it says.
	Nothing in here is code - a biome's caves change by editing its profile.

	TWO KINDS OF CAVE

	  Small   the ones a new player trips over: a sloped entrance, a few tight
	          bending tunnels, a fork, maybe a modest room. Shallow, common,
	          bounded to a few dozen blocks.

	  Large   rare, deep systems: two to four big chambers (epicentres) joined
	          by broad passages and tighter side tunnels, with sub-chambers,
	          ledges and changes of level. Sized for future bosses, rare
	          resources and cave structures.

	Both are PLANNED, not sprinkled. The world is cut into a grid of cells per
	category; each cell hashes to decide whether it hosts a plan, and the plan
	is a small list of capsules and ellipsoids in absolute block coordinates.
	Every chunk that intersects a plan rebuilds the same plan from the same
	hash, so a tunnel crossing a chunk border continues exactly, whatever
	order the chunks load in. See CaveMap.

	UNITS: blocks (TerrainConfig.StudSize studs). Depths are blocks below the
	surface of the column at the plan's origin.

	=========================================================================
	BIOME PROFILE FIELDS
	=========================================================================

	  smallFrequency, largeFrequency   multiply the category's base chance.
	                                   0 switches that category off here.
	  depth = { small = {min,max}, large = {min,max} }
	                                   where a plan's origin sits below the
	                                   surface. Large should start deeper.
	  tunnelRadius = {min,max}         tight tunnels and entrances. Keep min
	                                   at or above Entrance.MinRadius so a
	                                   character fits.
	  passageRadius = {min,max}        the broad passages of large systems.
	  roomRadius = {min,max}           small-cave rooms and large sub-chambers.
	  chamberRadius = {min,max}        large-cave epicentres (horizontal).
	  chamberFlatten                   vertical radius as a fraction of the
	                                   horizontal one. Low is a wide low hall,
	                                   high is a dome.
	  verticality      0..1            how steeply tunnels climb and drop.
	  roughness        0..1            how far the walls wander off the clean
	                                   shape. 0 is geometric, 1 is ragged.
	  angularity       0..1            0 keeps rooms rounded; 1 squares them
	                                   off (Snow's ice-block look).
	  entranceChance   small caves     chance a small cave opens to the surface
	                                   rather than merely passing near it.
	  largeEntranceChance              the same for large systems.
	  materials = { floor, ceiling, wall }
	                                   block names to restyle the cave's
	                                   surfaces with, or nil to leave the
	                                   natural strata. Walls cost the most
	                                   overrides; floor and ceiling are cheap.
	  content = {...}                  read by nothing yet. Tags and densities
	                                   future chest / ore-pocket / enemy / prop
	                                   placement will key on. Candidates carry
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
-- starting chunks are solid ground throughout.
CaveConfig.SpawnExclusionBlocks = TerrainConfig.SpawnGuaranteeBlocks + 32

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

-- How many plans may carve one chunk. Any beyond are dropped in a
-- deterministic order, so the bound never produces a seam.
CaveConfig.MaxPlansPerChunk = 6

-- Hard ceiling on primitives in one plan, whatever the profile asks for.
CaveConfig.MaxPrimitivesPerPlan = 96

-- Ceilings every profile is checked against.
CaveConfig.MaxTunnelRadius = 4
CaveConfig.MaxChamberRadius = 14

-- Steepest tunnel a plan may draw, as rise over run. 1 is 45 degrees.
CaveConfig.MaxTunnelSlope = 0.9

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
}

-- ===========================================================================
-- SHAPE NOISE
-- ===========================================================================

-- Wall roughness is a 3D noise warp of each primitive's radius, sampled at
-- this scale in blocks. Larger reads as gentle undulation, smaller as
-- knobbly rock. It perturbs a coherent shape rather than thresholding noise,
-- which is why it cannot leave stray one-block pockets.
CaveConfig.RoughnessScaleBlocks = 7

-- The most a wall may move, as a fraction of the radius, at roughness 1.
CaveConfig.RoughnessAmplitude = 0.45

-- ===========================================================================
-- CATEGORIES
-- ===========================================================================

CaveConfig.Categories = {
	Small = {
		-- Grid cell edge. One cell hosts at most one plan.
		CellBlocks = 112,
		-- Chance a cell hosts a plan, before the biome multiplier.
		Chance = 0.5,
		-- Nothing in a plan reaches further than this from its origin.
		MaxExtentBlocks = 48,

		Segments = { min = 3, max = 6 },
		SegmentLength = { min = 6, max = 13 },
		-- Degrees a tunnel may turn between segments.
		Turn = { min = 20, max = 70 },
		ForkChance = 0.35,
		ForkSegments = { min = 1, max = 3 },
		Rooms = { min = 0, max = 2 },

		-- A plan without an entrance still starts within this many blocks
		-- of the surface, so it is reachable by shallow digging.
		NearSurfaceBlocks = 8,
	},

	Large = {
		CellBlocks = 448,
		Chance = 0.45,
		MaxExtentBlocks = 120,

		Epicentres = { min = 2, max = 4 },
		-- Horizontal distance between neighbouring epicentres.
		EpicentreSpacing = { min = 28, max = 60 },
		-- How far apart in height two epicentres may sit.
		EpicentreLevelChange = 14,
		-- Passage polyline pieces between two epicentres.
		PassageSegments = { min = 2, max = 4 },
		SubChambers = { min = 2, max = 5 },
		SideTunnels = { min = 2, max = 4 },
		SideTunnelSegments = { min = 2, max = 4 },
		SideTunnelLength = { min = 8, max = 16 },
		-- Shelves cut into chamber walls, per epicentre.
		Ledges = { min = 1, max = 2 },
		-- Extra passage closing a loop between first and last epicentre,
		-- when there are at least three.
		LoopChance = 0.5,
	},
}

-- ===========================================================================
-- BIOME PROFILES
-- ===========================================================================

CaveConfig.Default = {
	smallFrequency = 1.0,
	largeFrequency = 1.0,
	depth = { small = { min = 5, max = 26 }, large = { min = 30, max = 100 } },
	tunnelRadius = { min = 1.6, max = 2.3 },
	passageRadius = { min = 2.6, max = 3.6 },
	roomRadius = { min = 3, max = 5 },
	chamberRadius = { min = 7, max = 11 },
	chamberFlatten = 0.7,
	verticality = 0.35,
	roughness = 0.35,
	angularity = 0,
	entranceChance = 0.8,
	largeEntranceChance = 0.6,
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
		smallFrequency = 1.0,
		largeFrequency = 1.0,
		depth = { small = { min = 5, max = 24 }, large = { min = 30, max = 96 } },
		tunnelRadius = { min = 1.6, max = 2.3 },
		passageRadius = { min = 2.6, max = 3.6 },
		roomRadius = { min = 3, max = 5 },
		chamberRadius = { min = 7, max = 11 },
		chamberFlatten = 0.7,
		verticality = 0.35,
		roughness = 0.35,
		angularity = 0,
		entranceChance = 0.85,
		largeEntranceChance = 0.65,
		materials = {},
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
		depth = { small = { min = 8, max = 28 }, large = { min = 34, max = 104 } },
		tunnelRadius = { min = 1.8, max = 2.6 },
		passageRadius = { min = 3.0, max = 4.0 },
		roomRadius = { min = 4, max = 6 },
		chamberRadius = { min = 9, max = 13 },
		chamberFlatten = 0.5,
		verticality = 0.2,
		roughness = 0.25,
		angularity = 0.1,
		entranceChance = 0.7,
		largeEntranceChance = 0.6,
		materials = { floor = "Sandstone" },
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
		smallFrequency = 0.8,
		largeFrequency = 0.9,
		depth = { small = { min = 6, max = 26 }, large = { min = 32, max = 100 } },
		tunnelRadius = { min = 1.6, max = 2.2 },
		passageRadius = { min = 2.5, max = 3.4 },
		roomRadius = { min = 3, max = 5 },
		chamberRadius = { min = 7, max = 10 },
		chamberFlatten = 0.75,
		verticality = 0.5,
		roughness = 0.45,
		angularity = 0.6,
		entranceChance = 0.6,
		largeEntranceChance = 0.5,
		materials = {},
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
		largeFrequency = 1.0,
		depth = { small = { min = 6, max = 26 }, large = { min = 30, max = 96 } },
		tunnelRadius = { min = 1.7, max = 2.4 },
		passageRadius = { min = 2.8, max = 3.8 },
		roomRadius = { min = 3, max = 5 },
		chamberRadius = { min = 7, max = 11 },
		chamberFlatten = 0.9,
		verticality = 0.4,
		roughness = 0.2,
		angularity = 0,
		entranceChance = 0.75,
		largeEntranceChance = 0.6,
		materials = { floor = "HallowedStone", ceiling = "HallowedStone", wall = "HallowedStone" },
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
		largeFrequency = 1.3,
		depth = { small = { min = 6, max = 28 }, large = { min = 30, max = 110 } },
		tunnelRadius = { min = 1.6, max = 2.6 },
		passageRadius = { min = 2.6, max = 3.8 },
		roomRadius = { min = 4, max = 6 },
		chamberRadius = { min = 8, max = 12 },
		chamberFlatten = 0.7,
		verticality = 0.6,
		roughness = 0.6,
		angularity = 0,
		entranceChance = 0.5,
		largeEntranceChance = 0.5,
		materials = { floor = "CorruptedStone", ceiling = "CorruptedStone", wall = "CorruptedStone" },
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
		largeFrequency = 1.3,
		depth = { small = { min = 6, max = 28 }, large = { min = 30, max = 110 } },
		tunnelRadius = { min = 1.7, max = 2.7 },
		passageRadius = { min = 2.8, max = 4.0 },
		roomRadius = { min = 4, max = 6 },
		chamberRadius = { min = 8, max = 12 },
		chamberFlatten = 0.6,
		verticality = 0.5,
		roughness = 0.55,
		angularity = 0,
		entranceChance = 0.5,
		largeEntranceChance = 0.5,
		materials = { floor = "CrimsonStone", ceiling = "CrimsonStone", wall = "CrimsonStone" },
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
		largeFrequency = 0.6,
		depth = { small = { min = 8, max = 26 }, large = { min = 32, max = 90 } },
		tunnelRadius = { min = 1.6, max = 2.3 },
		passageRadius = { min = 2.6, max = 3.4 },
		roomRadius = { min = 3, max = 5 },
		chamberRadius = { min = 7, max = 10 },
		chamberFlatten = 0.6,
		verticality = 0.3,
		roughness = 0.4,
		angularity = 0,
		entranceChance = 0.5,
		largeEntranceChance = 0.4,
		materials = {},
		content = {
			tags = { "swamp", "wet" },
			decorationDensity = 0.5,
			chestDensity = 0.5,
			orePocketDensity = 0.5,
			enemyDensity = 0.6,
		},
	},
}

-- ===========================================================================
-- CACHES
-- ===========================================================================

-- Per-chunk carve records and per-cell plans are pure functions of the seed,
-- held in two generations like TerrainManager's column cache. The record
-- cache has to hold the loaded set plus a one-chunk halo; 600 covers view
-- distance 7 for one player with room to spare.
CaveConfig.RecordCacheLimit = 600
CaveConfig.PlanCacheLimit = 512

-- ===========================================================================
-- DERIVED AND VALIDATION
-- ===========================================================================

function CaveConfig.profileFor(biomeName)
	return CaveConfig.Biomes[biomeName] or CaveConfig.Default
end

-- The largest frequency any profile declares, for the cheap rejection that
-- runs before a plan's origin column is ever sampled.
function CaveConfig.maxFrequency(category)
	local field = if category == "Large" then "largeFrequency" else "smallFrequency"
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

	assert(type(profile.smallFrequency) == "number" and profile.smallFrequency >= 0,
		label .. ".smallFrequency must be >= 0")
	assert(type(profile.largeFrequency) == "number" and profile.largeFrequency >= 0,
		label .. ".largeFrequency must be >= 0")

	assert(type(profile.depth) == "table", label .. ".depth is required")
	assertRange(profile.depth.small, label .. ".depth.small", 1, 200)
	assertRange(profile.depth.large, label .. ".depth.large", 1, 200)
	assert(profile.depth.large.min >= profile.depth.small.min,
		label .. ": large caves should start no shallower than small ones")

	assertRange(profile.tunnelRadius, label .. ".tunnelRadius", entrance.MinRadius, CaveConfig.MaxTunnelRadius)
	assertRange(profile.passageRadius, label .. ".passageRadius", entrance.MinRadius, CaveConfig.MaxTunnelRadius)
	assertRange(profile.roomRadius, label .. ".roomRadius", 2, CaveConfig.MaxChamberRadius)
	assertRange(profile.chamberRadius, label .. ".chamberRadius", 4, CaveConfig.MaxChamberRadius)

	assert(type(profile.chamberFlatten) == "number" and profile.chamberFlatten > 0.2 and profile.chamberFlatten <= 1.2,
		label .. ".chamberFlatten must be in (0.2, 1.2]")
	assertUnit(profile.verticality, label .. ".verticality")
	assertUnit(profile.roughness, label .. ".roughness")
	assertUnit(profile.angularity, label .. ".angularity")
	assertUnit(profile.entranceChance, label .. ".entranceChance")
	assertUnit(profile.largeEntranceChance, label .. ".largeEntranceChance")

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

	assert(CaveConfig.MinSurfaceCoverBlocks >= 1, "[CaveConfig] MinSurfaceCoverBlocks must be at least 1")
	assert(CaveConfig.MinSurfaceCoverUnderWaterBlocks >= CaveConfig.MinSurfaceCoverBlocks,
		"[CaveConfig] cover under water must not be thinner than cover on land")
	assert(CaveConfig.MinFloorThicknessBlocks >= 1,
		"[CaveConfig] MinFloorThicknessBlocks must be at least 1, or a restyled floor could land on bedrock")
	assert(CaveConfig.SpawnExclusionBlocks >= TerrainConfig.SpawnGuaranteeBlocks,
		"[CaveConfig] SpawnExclusionBlocks must cover the guaranteed spawn area")
	assert(CaveConfig.EntranceSafeDistanceBlocks >= CaveConfig.SpawnExclusionBlocks,
		"[CaveConfig] EntranceSafeDistanceBlocks must be at least SpawnExclusionBlocks")
	assert(CaveConfig.StructureSupportDepthBlocks >= 1, "[CaveConfig] StructureSupportDepthBlocks must be positive")

	assert(CaveConfig.MaxPlansPerChunk >= 1, "[CaveConfig] MaxPlansPerChunk must be at least 1")
	assert(CaveConfig.MaxPrimitivesPerPlan >= 8, "[CaveConfig] MaxPrimitivesPerPlan is too small to draw a cave")
	assert(CaveConfig.MaxTunnelRadius >= entrance.MinRadius, "[CaveConfig] MaxTunnelRadius below Entrance.MinRadius")
	assert(CaveConfig.MaxChamberRadius > CaveConfig.MaxTunnelRadius, "[CaveConfig] MaxChamberRadius must exceed MaxTunnelRadius")
	assert(CaveConfig.MaxTunnelSlope > 0 and CaveConfig.MaxTunnelSlope <= 1.5, "[CaveConfig] MaxTunnelSlope must be in (0, 1.5]")

	assert(entrance.MaxSlope > 0 and entrance.MaxSlope <= CaveConfig.MaxTunnelSlope,
		"[CaveConfig] Entrance.MaxSlope must be positive and no steeper than MaxTunnelSlope")
	assert(entrance.MinRadius >= 1.5, "[CaveConfig] Entrance.MinRadius under 1.5 does not fit a character")
	assert(entrance.MaxSurfaceRelief >= 0, "[CaveConfig] Entrance.MaxSurfaceRelief must be >= 0")
	assert(entrance.MinSurfaceHeight < entrance.MaxSurfaceHeight, "[CaveConfig] Entrance surface height band is empty")

	assert(CaveConfig.RoughnessScaleBlocks > 0, "[CaveConfig] RoughnessScaleBlocks must be positive")
	assertUnit(CaveConfig.RoughnessAmplitude, "[CaveConfig] RoughnessAmplitude")
	assert(CaveConfig.RoughnessAmplitude < 0.5, "[CaveConfig] RoughnessAmplitude must stay under 0.5 or a tunnel can pinch shut")

	assert(CaveConfig.RecordCacheLimit >= 64 and CaveConfig.PlanCacheLimit >= 64, "[CaveConfig] cache limits are too small")

	for name, category in pairs(CaveConfig.Categories) do
		local label = "[CaveConfig] Categories." .. name
		assert(category.CellBlocks >= TerrainConfig.ChunkSize, label .. ".CellBlocks must be at least one chunk")
		assertUnit(category.Chance, label .. ".Chance")
		assert(category.MaxExtentBlocks > 0 and category.MaxExtentBlocks < 2 * category.CellBlocks,
			label .. ".MaxExtentBlocks must be positive and under two cells, or the neighbourhood search is unbounded")
	end
	assert(CaveConfig.Categories.Small and CaveConfig.Categories.Large, "[CaveConfig] both Small and Large categories are required")

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
