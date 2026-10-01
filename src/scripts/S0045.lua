--[[
	Landform

	The geography of the world: continents, mountain ranges, rivers, lakes and
	landmarks. LandformConfig holds the numbers; this holds the arithmetic.

	  Landform.init(seed)
	  Landform.setSiteProbe(fn)   -> how to ask BiomeMap what a POSITION is like
	  Landform.sampleLow(bx, bz)  -> the six slow fields, for BiomeMap's lattice
	  Landform.detail(bx, bz)     -> per-block roughness, -1..1
	  Landform.compose(bx, bz, ...) -> landHeight, waterTop, mountain, shoreLevel

	WHERE THIS SITS

	BiomeMap decides WHICH biome a column is and blends its parameters; this
	decides what the ground actually does. The split matters because every field
	here is world-wide and shared: a biome contributes only amplitudes, so a
	mountain range crossing out of the snow does not stop at the border, it
	tapers - and the cost of generation does not depend on how many biomes
	exist.

	Everything is a pure function of (blockX, blockZ) and the seed. Nothing here
	looks at a neighbouring column, which is what lets BiomeMap cache the slow
	half on a lattice and lets any column be sampled entirely on its own.

	THE PROFILE

	`compose` needs about a dozen blended per-biome numbers. They arrive in
	Landform.Profile, a shared table BiomeMap fills in before each call, rather
	than as arguments or a fresh table - this runs 256 times per chunk and both
	alternatives cost more than the call itself.

	THE SITE PROBE

	Two features here - lakes and landmarks - are OBJECTS on a cell grid rather
	than fields, and an object has to settle its properties once for its whole
	body instead of per column. A lake in particular has to choose one surface
	height and hold it, or the water runs downhill.

	Choosing that height needs to know what the ground is like at the lake's
	own site, which is a biome question, and BiomeMap is the module that
	answers biome questions - but BiomeMap already requires this one. So the
	dependency is inverted: BiomeMap installs a probe at init, and this calls
	it a handful of times per CELL, memoised. A session resolves a few hundred
	cells, so the cost does not show up anywhere.

	The probe must not touch Landform.Profile - it is called from inside
	compose, which is reading it.
]]

local TerrainFolder = script.Parent
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))
local LandformConfig = require(TerrainFolder:WaitForChild("LandformConfig"))
local NoiseField = require(TerrainFolder:WaitForChild("NoiseField"))

local Landform = {}

-- ---------------------------------------------------------------------------
-- Localised config
-- ---------------------------------------------------------------------------

local MIN_HEIGHT = TerrainConfig.MinHeight
local MAX_HEIGHT = TerrainConfig.MaxHeight
local WORLD_SPAN = TerrainConfig.WorldRadiusBlocks * 2

local CONTINENT_SCALE = LandformConfig.ContinentScaleBlocks
local CONTINENT_CONTRAST = LandformConfig.ContinentContrast
local CONTINENT_PIVOT = LandformConfig.ContinentPivot
local RANGE_SCALE = LandformConfig.RangeScaleBlocks
local RANGE_CONTRAST = LandformConfig.RangeContrast
local RANGE_THRESHOLD = LandformConfig.RangeThreshold
local RANGE_FEATHER = LandformConfig.RangeFeather
local MOUNTAIN_SCALE = LandformConfig.MountainScaleBlocks
local MOUNTAIN_GAIN = LandformConfig.MountainGain
local MOUNTAIN_LIFT = LandformConfig.MountainContinentLift
local HILL_SCALE = LandformConfig.HillScaleBlocks
local HILL_CONTRAST = LandformConfig.HillContrast
local DETAIL_SCALE = LandformConfig.DetailScaleBlocks

local RIVER_SCALE = LandformConfig.RiverScaleBlocks
local RIVER_GAIN = LandformConfig.RiverGain
local RIVER_WIDTH_HIGH = LandformConfig.RiverWidthHigh
local RIVER_WIDTH_LOW = LandformConfig.RiverWidthLow
local RIVER_BANK_WIDTH = LandformConfig.RiverBankWidth
local RIVER_DRAINAGE_BIAS = LandformConfig.RiverDrainageBias
local RIVER_FREEBOARD = LandformConfig.RiverFreeboardBlocks
local SEA_LEVEL = LandformConfig.SeaLevel
local RIVER_DEPTH_HIGH = LandformConfig.RiverDepthHigh
local RIVER_DEPTH_LOW = LandformConfig.RiverDepthLow
local RIVER_MAX_LAND = LandformConfig.RiverMaxLandHeight
local RIVER_FADE = LandformConfig.RiverFadeBlocks

local BASIN_SCALE = LandformConfig.BasinScaleBlocks
local BASIN_CONTRAST = LandformConfig.BasinContrast
local BASIN_THRESHOLD = LandformConfig.BasinThreshold
local BASIN_FEATHER = LandformConfig.BasinFeather
local BASIN_DEPTH = LandformConfig.BasinDepthBlocks
local MAX_WATER_DEPTH = LandformConfig.MaxWaterDepth

local LAKE_CELL = LandformConfig.LakeCellBlocks
local INV_LAKE_CELL = 1 / LAKE_CELL
local LAKE_CHANCE = LandformConfig.LakeChance
local LAKE_JITTER = LandformConfig.LakeJitter
local LAKE_FREEBOARD = LandformConfig.LakeFreeboardBlocks
local LAKE_SEA_MARGIN = LandformConfig.LakeSeaMarginBlocks
local LAKE_RANGE_CEILING = LandformConfig.LakeRangeCeiling
local LAKE_RISE_TOLERANCE = LandformConfig.LakeRiseToleranceBlocks
local LAKE_RISE_FADE = LandformConfig.LakeRiseFadeBlocks

local LANDMARK_CELL = LandformConfig.LandmarkCellBlocks
local INV_LANDMARK_CELL = 1 / LANDMARK_CELL
local LANDMARK_CHANCE = LandformConfig.LandmarkChance

--[[
	How far a river valley may pull the surrounding ground down, and how deep
	the channel itself may cut.

	Both are bounds on APPEARANCE and on COST at once. An uncapped bank grade
	turns every upland river into a canyon the width of the flood plain, and
	every block of extra depth is another exposed side face on both walls - the
	one thing in this renderer that scales with how dramatic the terrain is.
]]
local MAX_BANK_DROP = 18
local MAX_RIVER_CUT = 28

-- How far the banks stand above the water they grade down to.
local BANK_RISE = 2

-- How hard the flood plain is pulled toward the water level.
local BANK_STRENGTH = 0.62

-- Cliff terracing. More steps means finer ledges; the strength is per biome.
local CLIFF_STEPS = 7

--[[
	How finely a lake's rim is probed when its surface height is settled.

	The minimum reference AROUND THE RIM is the whole safety argument, and it
	is enough on its own: the water can only appear where the bowl dug the
	ground below the surface, and at the rim the bowl digs nothing, so the rim
	is the only place the level has to be provably under the ground. The
	interior is free to dip lower - that just makes the lake deeper.

	One probe every LAKE_PROBE_SPACING blocks of rim, so a pond costs the
	minimum and a great lake gets the resolution its size needs. The reference
	varies over hundreds of blocks, so this is comfortably finer than it moves.
]]
local LAKE_PROBE_SPACING = 55
local LAKE_PROBE_MIN = 8
local LAKE_PROBE_MAX = 28

--[[
	Sizes a lake is allowed to shrink to when the ground it landed on is
	tilted, and how far its rim may sit below its middle before it does.

	The tilt bound is really a statement about depth: a lake whose rim is N
	blocks below its centre carries N blocks of water at the centre before its
	own depth is added, and LandformConfig.MaxWaterDepth stops rendering past
	nine. Past that the extra is not a deeper lake, it is a bowl the water
	never fills to the top of.
]]
local LAKE_FIT_SCALES = { 1.0, 0.66, 0.42 }
local LAKE_MAX_TILT = 8

-- ---------------------------------------------------------------------------
-- Shared scratch
-- ---------------------------------------------------------------------------

--[[
	Filled by BiomeMap before every compose() call. Never survives a yield, so
	sharing one table across every column is safe and saves an allocation per
	column.
]]
Landform.Profile = {
	baseHeight = 30,
	continentAmplitude = 20,
	hillAmplitude = 10,
	mountainAmplitude = 8,
	ridgeSharpness = 1.5,
	roughness = 1,
	cliffStrength = 0,

	-- Shifts this biome along the mountain-belt ramp. The belt FIELD is shared
	-- world-wide; this only moves where a given biome meets its threshold, so
	-- an alpine biome gets more of the same ranges rather than ranges of its
	-- own that would stop at its border.
	rangeBias = 0,

	riverAffinity = 1,
	lakeAffinity = 1,
	landmarkAffinity = 1,
	aridity = 0,

	-- 0..1, and the only member of this table that is not a biome trait: it is
	-- the spawn guarantee, faded in by BiomeMap. The ground is lifted clear of
	-- the water table where it is low, so the starting area cannot come up
	-- flooded on a seed whose continental lowland happens to sit under the
	-- origin.
	waterAllowed = 1,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function clamp01(v)
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

local function smoothstep(v)
	return v * v * (3 - 2 * v)
end

-- 0 below `low`, 1 above `high`, eased between.
local function band(v, low, high)
	if high <= low then
		return if v >= high then 1 else 0
	end
	return smoothstep(clamp01((v - low) / (high - low)))
end

-- The project's usual position hash: cheap, deterministic, no allocation.
local function hash(x, z, salt)
	local v = math.sin(x * 127.1 + z * 311.7 + salt) * 43758.5453
	return v - math.floor(v)
end

-- ---------------------------------------------------------------------------
-- Fields
-- ---------------------------------------------------------------------------

local continentField, rangeField, mountainField
local hillField, detailField, riverField, basinField
local activeSeed = 0

-- Memoised cells; see lakeCell / landmarkCell. Declared here so init can drop
-- them on a reseed, which it must - the entries are keyed on the old seed.
local landmarkCells = {}
local lakeCells = {}
local rawLakeCells = {}

-- The 3x3 cell windows a column reads, held between calls; see lakeWindowAt
-- and markWindowAt. Declared here so init and setSiteProbe can invalidate them
-- - assigning them further down would create globals instead.
local lakeWindow, lakeWindowCount = {}, 0
local lakeWindowX, lakeWindowZ = math.huge, math.huge
local markWindow, markWindowCount = {}, 0
local markWindowX, markWindowZ = math.huge, math.huge

--[[
	What a position is like, for the cell grids. Installed by BiomeMap.

	  probe(x, z) -> baseHeight, continentAmplitude, hillAmplitude,
	                 aridity, lakeAffinity

	Nil until BiomeMap.init runs, and the cell code copes: without it lakes
	simply do not form, which is the right failure for a module being unit
	tested on its own rather than a crash.
]]
local siteProbe = nil

function Landform.setSiteProbe(fn)
	siteProbe = fn
	table.clear(lakeCells)
	table.clear(rawLakeCells)
	table.clear(landmarkCells)
	lakeWindowX, lakeWindowZ = math.huge, math.huge
	markWindowX, markWindowZ = math.huge, math.huge
end

function Landform.init(seed)
	LandformConfig.validate()
	activeSeed = seed or 0
	table.clear(landmarkCells)
	table.clear(lakeCells)
	table.clear(rawLakeCells)
	lakeWindowX, lakeWindowZ = math.huge, math.huge
	markWindowX, markWindowZ = math.huge, math.huge

	--[[
		Each field gets its own Y plane so they do not correlate, and its own
		span so NoiseField can keep the world inside one Perlin period.

		`rotate` turns the sampling frame off the world axes, and it is set for
		every field slow enough that the world covers only a handful of Perlin
		cells - continent, ranges, rivers, basins. Those are the fields whose
		lattice would otherwise be READABLE as a square grid running along the
		same axes as the chunks. The mountain and hill fields are fine detail
		by comparison, cover hundreds of cells, and would spend period budget
		they do not have to spare on it.
	]]
	local function field(salt, plane, scale, octaves, persistence, lacunarity, rotate)
		return NoiseField.new(
			activeSeed + salt, plane, octaves, persistence, lacunarity,
			WORLD_SPAN / scale, rotate
		)
	end

	continentField = field(
		11, 211.7, CONTINENT_SCALE,
		LandformConfig.ContinentOctaves, LandformConfig.ContinentPersistence, 2, true
	)
	rangeField = field(
		12, 233.9, RANGE_SCALE,
		LandformConfig.RangeOctaves, LandformConfig.RangePersistence, 2, true
	)
	mountainField = field(
		13, 257.3, MOUNTAIN_SCALE,
		LandformConfig.MountainOctaves, LandformConfig.MountainPersistence,
		LandformConfig.MountainLacunarity
	)
	hillField = field(
		14, 281.1, HILL_SCALE,
		LandformConfig.HillOctaves, LandformConfig.HillPersistence,
		LandformConfig.HillLacunarity
	)
	detailField = field(15, 307.5, DETAIL_SCALE, 1, 0.5, 2)
	riverField = field(
		16, 331.9, RIVER_SCALE,
		LandformConfig.RiverOctaves, LandformConfig.RiverPersistence,
		LandformConfig.RiverLacunarity, true
	)
	basinField = field(
		17, 359.3, BASIN_SCALE,
		LandformConfig.BasinOctaves, LandformConfig.BasinPersistence, 2, true
	)
end

--[[
	The slow half, all six fields at once.

	Returned as six values rather than a table because BiomeMap calls this per
	lattice point and stores them in parallel arrays. Everything here changes
	over hundreds of blocks, which is what makes sampling it on a lattice and
	interpolating between points indistinguishable from sampling it directly.
]]
function Landform.sampleLow(bx, bz)
	-- Everything with a THRESHOLD downstream of it goes through :shaped rather
	-- than :sample01, because raw fbm does not reach the ends of its own
	-- range. Hills are shaped too, though nothing thresholds them: four-octave
	-- fbm sits in a tighter bell still, so without it a biome asking for 26
	-- blocks of relief would see about half of that.
	local continent = continentField:shaped(bx, bz, CONTINENT_SCALE, CONTINENT_CONTRAST)
	local ranges = rangeField:shaped(bx, bz, RANGE_SCALE, RANGE_CONTRAST)
	local ridge = mountainField:ridged(bx, bz, MOUNTAIN_SCALE, MOUNTAIN_GAIN)
	local hills = hillField:shaped(bx, bz, HILL_SCALE, HILL_CONTRAST)
	local riverness = riverField:ridged(bx, bz, RIVER_SCALE, RIVER_GAIN)
	local basin = basinField:shaped(bx, bz, BASIN_SCALE, BASIN_CONTRAST)

	return continent, ranges, ridge, hills, riverness, basin
end

-- Per-block roughness. The one field not on the lattice: it exists precisely
-- to vary between adjacent columns, so interpolating it would erase it.
function Landform.detail(bx, bz)
	return detailField:sample(bx, bz, DETAIL_SCALE)
end

--[[
	Continental elevation on its own, for BiomeMap's climate lapse.

	It is the only piece of geography that exists before a biome has been
	chosen - every other field here is scaled by numbers that come FROM the
	biome - which is what makes it the one thing biome selection is allowed to
	read without a circular dependency. Sampled at region sites only, a few
	hundred times per session.
]]
function Landform.continentAt(x, z)
	return continentField:shaped(x, z, CONTINENT_SCALE, CONTINENT_CONTRAST)
end

-- ---------------------------------------------------------------------------
-- The reference surface
-- ---------------------------------------------------------------------------

--[[
	The ground with everything that can only ADD height taken back off - see
	LandformConfig's header. A lower bound on the terrain, and the thing every
	water level in the world is measured down from.

	Two callers, and they must agree exactly or water stands above dry land:
	compose() below, which has the blended profile in hand already, and the
	lake cells, which ask the site probe for it.
]]
local function referenceHeight(base, hillAmplitude, continentAmplitude, continent, basinOpen)
	local reference = base
		- hillAmplitude * 0.5
		+ (continent - CONTINENT_PIVOT) * continentAmplitude

	if basinOpen > 0 then
		reference -= BASIN_DEPTH * basinOpen
	end

	return reference
end

-- How far open the basin field is here, 0..1, before the biome's lake affinity
-- scales it.
local function basinOpenness(basin, lakeAffinity)
	local open = band(basin, BASIN_THRESHOLD, BASIN_THRESHOLD + BASIN_FEATHER) * lakeAffinity
	return if open > 1 then 1 else open
end

-- Forward declaration: the reference has to account for a landmark that DIGS,
-- and landmarks are defined further down.
local landmarkAt

-- The reference at an arbitrary position, for the cell grids. Costs a probe
-- plus two noise samples, and only ever runs a handful of times per cell.
local function referenceAt(x, z)
	local base, continentAmplitude, hillAmplitude, _aridity, lakeAffinity = siteProbe(x, z)

	local continent = continentField:shaped(x, z, CONTINENT_SCALE, CONTINENT_CONTRAST)
	local basin = basinField:shaped(x, z, BASIN_SCALE, BASIN_CONTRAST)

	local reference = referenceHeight(
		base, hillAmplitude, continentAmplitude, continent, basinOpenness(basin, lakeAffinity)
	)

	-- A crater or a hollow landmark takes the ground down without any of the
	-- fields above knowing, so it comes off here too - otherwise a lake whose
	-- rim clipped one would settle on a surface above the ground there.
	local lift, _flatten, rim = landmarkAt(x, z)
	local hollow = lift + rim
	if hollow < 0 then
		reference += hollow
	end

	return reference
end

-- ---------------------------------------------------------------------------
-- Weighted cell kinds
-- ---------------------------------------------------------------------------

-- Turns a weight list into cumulative thresholds in 0..1, so picking one is a
-- walk over a handful of numbers rather than a sum per lookup.
local function cumulative(list)
	local thresholds = table.create(#list)
	local total = 0
	for _, entry in ipairs(list) do
		total += entry.weight
	end

	local running = 0
	for index, entry in ipairs(list) do
		running += entry.weight
		-- The last is pinned to 1 rather than computed, so floating-point
		-- drift can never leave a sliver of the roll matching nothing.
		thresholds[index] = if index == #list then 1 else running / total
	end

	return thresholds
end

local function pick(thresholds, roll)
	for index = 1, #thresholds do
		if roll <= thresholds[index] then
			return index
		end
	end
	return #thresholds
end

-- ---------------------------------------------------------------------------
-- Lakes
-- ---------------------------------------------------------------------------

local lakeKinds = LandformConfig.LakeKinds
local lakeThresholds = cumulative(lakeKinds)

--[[
	Everything about a lake cell EXCEPT what its neighbours think, memoised.

	All of it is settled once per cell rather than per column, which is what
	lets a lake have a single flat surface at all. The expensive part is the
	ring of reference probes; see LandformConfig's LAKES section for why the
	minimum over them is the whole safety argument.

	`false` is stored for an empty cell so a miss is one table read rather than
	a rehash every time a column asks.
]]
local function rawLakeCell(cx, cz)
	local key = (cx + 4096) * 16384 + (cz + 4096)

	local entry = rawLakeCells[key]
	if entry ~= nil then
		return entry or nil
	end

	if siteProbe == nil or LAKE_CHANCE <= 0 then
		rawLakeCells[key] = false
		return nil
	end

	local jitterX = 0.5 + (hash(cx, cz, activeSeed * 0.031 + 5.17) - 0.5) * 2 * LAKE_JITTER
	local jitterZ = 0.5 + (hash(cx, cz, activeSeed * 0.037 + 23.41) - 0.5) * 2 * LAKE_JITTER

	local centreX = (cx + jitterX) * LAKE_CELL
	local centreZ = (cz + jitterZ) * LAKE_CELL

	--[[
		The affinity at the site scales the chance, so a swamp is riddled with
		water and a desert is not - and it is asked ONCE, for the whole lake,
		rather than per column. Asked per column it would carve a lake into
		crescents wherever it crossed a biome border.
	]]
	local _base, _continentAmplitude, _hillAmplitude, _aridity, lakeAffinity =
		siteProbe(centreX, centreZ)

	if hash(cx, cz, activeSeed * 0.041 + 61.29) >= LAKE_CHANCE * lakeAffinity then
		rawLakeCells[key] = false
		return nil
	end

	-- Not in the heart of a range. Foothills and flanks still get tarns.
	local ranges = rangeField:shaped(centreX, centreZ, RANGE_SCALE, RANGE_CONTRAST)
	if band(ranges, RANGE_THRESHOLD, RANGE_THRESHOLD + RANGE_FEATHER) > LAKE_RANGE_CEILING then
		rawLakeCells[key] = false
		return nil
	end

	local kind = lakeKinds[pick(lakeThresholds, hash(cx, cz, activeSeed * 0.043 + 17.83))]

	--[[
		An ellipse rather than a circle, area preserved, at a random angle. The
		shoreline is organic either way - it is where the dug bed crosses the
		flat surface, and the bed carries the terrain's own noise - but a field
		of circles reads as a field of circles from the air.
	]]
	local stretch = kind.stretch or 0
	local eccentric = 1 + stretch * (hash(cx, cz, activeSeed * 0.047 + 7.61) * 2 - 1)

	--[[
		The floor is 1 / (1 + stretch), and it is a CORRECTNESS bound rather
		than a taste one.

		Area is preserved by taking the axes as r*e and r/e, so the LONG one is
		r * max(e, 1/e) - and an eccentricity of 1 - stretch makes 1/e larger
		than 1 + stretch, not smaller. At stretch 0.45 that is r * 1.82 against
		the r * 1.45 the config's 3x3 window bound was checked against, so the
		widest lakes would have reached two cells away from columns that only
		ever test one, and been sliced off along the grid.
	]]
	local minEccentric = 1 / (1 + stretch)
	if eccentric < minEccentric then
		eccentric = minEccentric
	end

	local semiA = kind.radius * eccentric
	local semiB = kind.radius / eccentric
	local angle = hash(cx, cz, activeSeed * 0.053 + 29.11) * math.pi
	local axisCos = math.cos(angle)
	local axisSin = math.sin(angle)

	--[[
		The surface: the LOWEST reference anywhere on the lake's own rim, less
		the freeboard.

		The rim is the only place this has to hold. Water appears where the
		bowl has dug the ground below the surface, and at the rim the bowl digs
		nothing - so a surface under the untouched ground there is a surface
		the lake cannot spill over. Inside, a lower reference simply means
		deeper water.

		Probed on the real ellipse rather than on a circle around it, because a
		circle samples ground the lake never reaches and can miss a dip on the
		rim itself.

		AND THE SIZE IS FITTED TO THE GROUND, largest first.

		Taking the minimum over a rim that sits on a slope hands the lake a
		surface far below its own middle - and that is not a lower lake, it is
		a lake that should have been smaller. Measured with one fixed radius,
		40% of cells came out with a level under the sea and were thrown away
		entirely, most of them large ones on gently tilted country.

		So each size is tried in turn and the first whose rim is level enough
		to hold water is kept. A lake in a hollow gets its full extent; one on
		a slope shrinks until it fits the basin it is actually in, which is
		what a lake does. Only if even the smallest is still tilted does it
		fall back to that size and let the sea margin below decide.
	]]
	local function rimMinimum(a, b)
		local perimeter = math.pi * (a + b)
		local ring = math.clamp(
			math.ceil(perimeter / LAKE_PROBE_SPACING), LAKE_PROBE_MIN, LAKE_PROBE_MAX
		)

		local lowest = math.huge
		for i = 0, ring - 1 do
			local theta = (i / ring) * 2 * math.pi
			local ex = math.cos(theta) * a
			local ez = math.sin(theta) * b

			local reference = referenceAt(
				centreX + ex * axisCos - ez * axisSin,
				centreZ + ex * axisSin + ez * axisCos
			)
			if reference < lowest then
				lowest = reference
			end
		end

		return lowest
	end

	local centre = referenceAt(centreX, centreZ)
	local lowest = centre

	for index = 1, #LAKE_FIT_SCALES do
		local scale = LAKE_FIT_SCALES[index]
		local a = semiA * scale
		local b = semiB * scale

		local rim = rimMinimum(a, b)
		if rim > centre then
			rim = centre
		end

		if centre - rim <= LAKE_MAX_TILT or index == #LAKE_FIT_SCALES then
			semiA, semiB, lowest = a, b, rim
			break
		end
	end

	entry = {
		centreX = centreX,
		centreZ = centreZ,
		cos = axisCos,
		sin = axisSin,
		invA = 1 / semiA,
		invB = 1 / semiB,
		reach = if semiA > semiB then semiA else semiB,
		invShore = 1 / kind.shore,
		depth = kind.depth,
		level = math.floor(lowest - LAKE_FREEBOARD),
	}

	rawLakeCells[key] = entry
	return entry
end

--[[
	The same cell, after its neighbours have had their say.

	Two lakes whose discs overlap must hold the SAME surface, or the sheet of
	water steps where one disc ends and the other carries on. Each of them
	settled its own level from its own rim, and rims a couple of hundred blocks
	apart rarely agree to the block.

	So a cell takes the lowest level among the lakes it overlaps, itself
	included. The test is symmetric - a circle around each, which is generous
	rather than exact - so both members of a pair reach the same answer and
	their shared water is flat. Lower is also the only safe direction: it can
	shrink a lake, never spill it over ground its own rim probe cleared.

	Overlap is tested one step out, which settles every pair. A CHAIN of three
	where the outer two do not touch can still disagree by a block or two at
	the middle join; resolving that properly means a flood fill across the
	whole grid, which is exactly the global, unbounded computation the cell
	model exists to avoid.

	The sea margin is applied here, after the merge, because it is the merged
	level that the water actually stands at.
]]
local function lakeCell(cx, cz)
	local key = (cx + 4096) * 16384 + (cz + 4096)

	local cached = lakeCells[key]
	if cached ~= nil then
		return cached or nil
	end

	local raw = rawLakeCell(cx, cz)
	if not raw then
		lakeCells[key] = false
		return nil
	end

	local level = raw.level

	for ox = -1, 1 do
		for oz = -1, 1 do
			if ox ~= 0 or oz ~= 0 then
				local other = rawLakeCell(cx + ox, cz + oz)
				if other and other.level < level then
					local dx = other.centreX - raw.centreX
					local dz = other.centreZ - raw.centreZ
					local span = raw.reach + other.reach
					if dx * dx + dz * dz < span * span then
						level = other.level
					end
				end
			end
		end
	end

	-- Under the sea there is already water, and a second higher level beside
	-- it would be a wall at the shoreline.
	if level <= SEA_LEVEL + LAKE_SEA_MARGIN or level > MAX_HEIGHT then
		lakeCells[key] = false
		return nil
	end

	local entry = {
		centreX = raw.centreX,
		centreZ = raw.centreZ,
		cos = raw.cos,
		sin = raw.sin,
		invA = raw.invA,
		invB = raw.invB,
		reach = raw.reach,
		invShore = raw.invShore,
		depth = raw.depth,
		level = level,
	}

	lakeCells[key] = entry
	return entry
end

--[[
	The 3x3 window of lake cells around a column, compacted to only the cells
	that actually hold one.

	A cell is hundreds of blocks and a chunk is sixteen, so every column of a
	chunk almost always wants the same window. Resolving it once per window
	rather than once per column turns nine hashed table lookups per column into
	a loop over the usual zero or one entries.
]]
local function lakeWindowAt(cellX, cellZ)
	if cellX ~= lakeWindowX or cellZ ~= lakeWindowZ then
		lakeWindowX = cellX
		lakeWindowZ = cellZ
		lakeWindowCount = 0

		for ox = -1, 1 do
			for oz = -1, 1 do
				local cell = lakeCell(cellX + ox, cellZ + oz)
				if cell then
					lakeWindowCount += 1
					lakeWindow[lakeWindowCount] = cell
				end
			end
		end
	end

	return lakeWindowCount
end

--[[
	The lake covering a column, if any: its surface height and how deep into
	the bowl the column sits (1 at the middle, 0 at the rim).

	Where two lakes overlap the LOWEST surface wins, and the strongest bowl.
	Lower is the safe direction - a new lake entering the picture can only
	deepen the water, never raise it over ground that a moment ago was dry -
	and it is also what a pair of merged basins does.
]]
local function lakeAt(bx, bz)
	if lakeWindowAt(math.floor(bx * INV_LAKE_CELL), math.floor(bz * INV_LAKE_CELL)) == 0 then
		return 0, 0, 0
	end

	local level, shape, depth = 0, 0, 0

	for i = 1, lakeWindowCount do
		local cell = lakeWindow[i]

		local dx = bx - cell.centreX
		local dz = bz - cell.centreZ
		local reach = cell.reach

		if dx > -reach and dx < reach and dz > -reach and dz < reach then
			local cos, sin = cell.cos, cell.sin
			local u = (dx * cos + dz * sin) * cell.invA
			local v = (dz * cos - dx * sin) * cell.invB
			local distance = u * u + v * v

			if distance < 1 then
				local t = 1 - math.sqrt(distance)
				local here = smoothstep(clamp01(t * cell.invShore))

				if here > 0 then
					if here > shape then
						shape = here
						depth = cell.depth
					end
					if level == 0 or cell.level < level then
						level = cell.level
					end
				end
			end
		end
	end

	return level, shape, depth
end

-- ---------------------------------------------------------------------------
-- Landmarks
-- ---------------------------------------------------------------------------

local landmarkList = LandformConfig.Landmarks
local landmarkThresholds = cumulative(landmarkList)

-- The slope fraction of each kind's radius: 1 is a dome, 0.25 a flat top with
-- steep sides. Derived from `flatten` so a kind declares its character once.
local function edgeFractionFor(mark)
	local flatten = mark.flatten or 0
	return 1 - flatten * 0.8
end

--[[
	What a landmark cell holds, memoised.

	Whether a cell hosts a landmark, which kind, where in the cell it sits AND
	WHETHER IT SUITS THE COUNTRY are all pure functions of the cell index and
	the seed, so they are worked out once instead of per column.

	Suitability moved here from the per-column path, and that is a fix rather
	than an optimisation. Tested per column it is a hard threshold on a smooth
	field passing through the middle of the feature: a great peak whose cell
	sat on the edge of a mountain belt was cut off along the line where the
	belt crossed its threshold, leaving a cliff down the middle of it.
]]
local function landmarkCell(cx, cz)
	local key = (cx + 4096) * 16384 + (cz + 4096)

	local entry = landmarkCells[key]
	if entry ~= nil then
		return entry or nil
	end

	if hash(cx, cz, activeSeed * 0.011 + 7.31) >= LANDMARK_CHANCE then
		landmarkCells[key] = false
		return nil
	end

	local mark = landmarkList[pick(landmarkThresholds, hash(cx, cz, activeSeed * 0.017 + 19.77))]

	local jitterX = hash(cx, cz, activeSeed * 0.023 + 3.19)
	local jitterZ = hash(cx, cz, activeSeed * 0.029 + 11.53)
	local centreX = (cx + jitterX) * LANDMARK_CELL
	local centreZ = (cz + jitterZ) * LANDMARK_CELL

	-- Suitability, at the centre. A great peak in flat farmland or a mesa in a
	-- swamp would read as something dropped on the map rather than something
	-- the map grew.
	local allowed = true

	if mark.needsRange then
		local ranges = rangeField:shaped(centreX, centreZ, RANGE_SCALE, RANGE_CONTRAST)
		allowed = ranges >= RANGE_THRESHOLD
	end

	if allowed and mark.needsLow then
		local continent = continentField:shaped(
			centreX, centreZ, CONTINENT_SCALE, CONTINENT_CONTRAST
		)
		allowed = continent <= 0.45
	end

	if allowed and mark.needsArid then
		if siteProbe then
			local _base, _continentAmplitude, _hillAmplitude, aridity = siteProbe(centreX, centreZ)
			allowed = aridity >= 0.5
		else
			allowed = false
		end
	end

	if not allowed then
		landmarkCells[key] = false
		return nil
	end

	entry = {
		mark = mark,
		centreX = centreX,
		centreZ = centreZ,
		radius = mark.radius,
		invRadius = 1 / mark.radius,
		invEdge = 1 / edgeFractionFor(mark),
		lift = mark.lift or 0,
		flatten = mark.flatten or 0,
		rimLift = mark.rimLift or 0,
	}

	landmarkCells[key] = entry
	return entry
end

-- The same window trick as lakes, and for the same reason: the cell is 620
-- blocks and a chunk is sixteen.
local function markWindowAt(cellX, cellZ)
	if cellX ~= markWindowX or cellZ ~= markWindowZ then
		markWindowX = cellX
		markWindowZ = cellZ
		markWindowCount = 0

		for ox = -1, 1 do
			for oz = -1, 1 do
				local cell = landmarkCell(cellX + ox, cellZ + oz)
				if cell then
					markWindowCount += 1
					markWindow[markWindowCount] = cell
				end
			end
		end
	end

	return markWindowCount
end

--[[
	The landmark influence on one column, if any.

	Returns lift (blocks to add), flatten (0..1, how much local relief to
	suppress) and rim (blocks to add in a ring). Zero for the overwhelming
	majority of columns, which reach that answer without touching a hash.

	The nine cells around the column are enough because LandformConfig.validate
	refuses a radius over half a cell, so nothing further away can reach here.
]]
function landmarkAt(bx, bz)
	local affinity = Landform.Profile.landmarkAffinity
	if affinity <= 0 or LANDMARK_CHANCE <= 0 then
		return 0, 0, 0
	end

	if markWindowAt(math.floor(bx * INV_LANDMARK_CELL), math.floor(bz * INV_LANDMARK_CELL)) == 0 then
		return 0, 0, 0
	end

	local lift, flatten, rim = 0, 0, 0

	for i = 1, markWindowCount do
		local cell = markWindow[i]

		local dx = bx - cell.centreX
		local dz = bz - cell.centreZ
		local radius = cell.radius

		if dx > -radius and dx < radius and dz > -radius and dz < radius then
			local distance = math.sqrt(dx * dx + dz * dz)

			if distance < radius then
				-- 1 at the centre, 0 at the rim.
				local t = 1 - distance * cell.invRadius
				local shape = smoothstep(clamp01(t * cell.invEdge))

				lift += cell.lift * shape * affinity
				flatten += cell.flatten * shape

				local rimLift = cell.rimLift
				if rimLift ~= 0 then
					-- A soft ring just inside the rim: the crater wall.
					local offset = (t - 0.18) / 0.16
					local bump = 1 - offset * offset
					if bump > 0 then
						rim += rimLift * bump * affinity
					end
				end
			end
		end
	end

	if flatten > 1 then
		flatten = 1
	end

	return lift, flatten, rim
end

-- ---------------------------------------------------------------------------
-- Composition
-- ---------------------------------------------------------------------------

--[[
	Soft terracing, for cliffs and mesa ledges.

	Rounds the value toward a set of steps but eases across each riser, so the
	ground gets flats and breaks rather than either a smooth slope or a
	staircase of exact one-block treads.
]]
local function terrace(v, steps)
	local scaled = v * steps
	local floored = math.floor(scaled)
	local frac = scaled - floored
	return (floored + smoothstep(frac)) / steps
end

--[[
	Everything above, turned into one column.

	Takes the six interpolated slow fields plus the per-column detail, reads the
	blended biome numbers out of Landform.Profile, and returns:

	  land        the final integer land height
	  waterTop    the water surface above it, 0 for a dry column
	  mountain    the mountain term, so BiomeMap can put rock on bare ridges
	  shoreLevel  the water level this column is NEAR, whether or not it is
	              itself wet, so BiomeMap can lay a beach along the water line

	`edge` is the world-border falloff, applied here rather than by the caller
	so that water is decided against the height the column actually ends up
	with - which is what turns the border into a coastline instead of a dry
	ramp with rivers hanging off it.
]]
function Landform.compose(bx, bz, continent, ranges, ridge, hills, riverness, basin, detail, edge)
	local profile = Landform.Profile

	--[[
		Elevation relative to the pivot, and the number most of what follows is
		built on. NEGATIVE in lowland, which is the whole point: the continent
		term can now take height away as well as add it, so the world has
		genuine low country for water to gather in rather than a floor at each
		biome's baseHeight. See LandformConfig.ContinentPivot.
	]]
	local elevation = continent - CONTINENT_PIVOT

	-- 1. The mountain belt, and the mountains in it.
	--
	-- rangeBias shifts a biome along the ramp without giving it a field of its
	-- own, so the cold country meets the gate sooner than the grassland it
	-- borders while both are still looking at the same ranges.
	local belt = band(
		ranges + profile.rangeBias, RANGE_THRESHOLD, RANGE_THRESHOLD + RANGE_FEATHER
	)
	local mountain = 0

	-- A range standing on high ground is a bigger range than the same one out
	-- on the plain, which is what stops the belt reading as an even corrugation
	-- and gives the graded approach as you walk up into a cordillera.
	local mountainAmplitude = profile.mountainAmplitude
	if MOUNTAIN_LIFT ~= 0 then
		local scale = 1 + MOUNTAIN_LIFT * elevation
		if scale < 0.15 then
			scale = 0.15
		end
		mountainAmplitude *= scale
	end

	if belt > 0 and mountainAmplitude > 0 then
		mountain = ridge ^ profile.ridgeSharpness

		local cliff = profile.cliffStrength
		if cliff > 0 then
			mountain += (terrace(mountain, CLIFF_STEPS) - mountain) * cliff
		end

		mountain *= belt
	end

	-- 2. Landmarks, before the relief they suppress is added.
	local lift, flatten, rim = landmarkAt(bx, bz)

	--[[
		3. The land itself.

		The hill term is CENTRED: (hills - 0.5) digs as far as it lifts, so
		baseHeight is the height the ground averages rather than its floor, and
		raising a biome's hillAmplitude gives it hollows as well as rises. The
		reference below subtracts the same half amplitude, which is what keeps
		it a lower bound on the ground.
	]]
	local relief = 1 - flatten
	local hillAmplitude = profile.hillAmplitude
	local roughness = profile.roughness

	local land = profile.baseHeight
		+ elevation * profile.continentAmplitude
		+ (hills - 0.5) * hillAmplitude * relief
		+ mountain * mountainAmplitude
		+ detail * roughness * relief

	land += lift + rim

	--[[
		4. Basins: broad hollows, whole districts below their surroundings.

		Subtracted from the REFERENCE as well, further down, which is the
		difference between a river running down into a basin and a river
		standing on a levee above one. See LandformConfig's BASINS section.
	]]
	local basinOpen = basinOpenness(basin, profile.lakeAffinity)
	if basinOpen > 0 then
		land -= BASIN_DEPTH * basinOpen
	end

	--[[
		5. The reference surface - the ground with everything that can only add
		height taken back off. Every water level below is measured down from
		it, and it is a LOWER BOUND on the terrain, which is the invariant that
		keeps water from standing above dry ground. See LandformConfig's
		header.

		A landmark that DIGS is the one addition that can go the other way, so
		its negative part comes off the reference too and a river crossing a
		crater descends into it.
	]]
	local reference = referenceHeight(
		profile.baseHeight, hillAmplitude * relief, profile.continentAmplitude,
		continent, basinOpen
	)

	local hollow = lift + rim
	if hollow < 0 then
		reference += hollow
	end

	--[[
		6. Lakes. Dug before the river is cut, so a channel running into one
		ends up in the bowl rather than crossing it.

		THE BOWL FADES OUT AGAINST RISING GROUND rather than being cut off by a
		hard limit on how far it may dig. Those are not the same thing: a hard
		limit stops digging while the bowl is still asking for more, so a lake
		that lands against a hillside gouges a pit exactly as deep as the limit
		and then fails to reach its own water line - a dry crater with a lake's
		outline. Measured with a 30-block cap, six of every fourteen lakes came
		out with no water in them at all.

		Fading instead means the lake simply stops where the ground gets too
		high for it, which is where a lake does stop. The dig is bounded as a
		side effect - nothing past the tolerance is ever dug - and the shore
		comes out following the hillside rather than a circle.
	]]
	local lakeLevel, lakeShape, lakeDepth = lakeAt(bx, bz)

	if lakeShape > 0 then
		local rise = land - lakeLevel
		if rise > LAKE_RISE_TOLERANCE then
			lakeShape *= 1 - band(
				rise, LAKE_RISE_TOLERANCE, LAKE_RISE_TOLERANCE + LAKE_RISE_FADE
			)
		end
	end

	if lakeShape > 0 then
		local target = lakeLevel - lakeDepth
		if land > target then
			land -= (land - target) * lakeShape
		end
	end

	--[[
		7. Rivers, and the valleys they run in.

		The channel is cut relative to the reference, less the biome's own
		roughness - the one term that can put the ground BELOW the reference,
		and therefore the one the freeboard has to cover for the invariant to
		hold at every single column rather than merely on average.
	]]
	local downstream = 1 - continent
	local surface = reference - RIVER_FREEBOARD - roughness

	-- A river never runs below the sea it drains into. Clamping here is what
	-- makes an estuary: approaching the lowlands the channel flattens out to
	-- exactly the level of the sea and merges with it instead of meeting it at
	-- a one-block step.
	if surface < SEA_LEVEL then
		surface = SEA_LEVEL
	end

	--[[
		A river meeting a lake takes the lake's level, graded over the lake's
		own extent. Both are derived from the same reference so they are never
		far apart, and this closes the last few blocks between them - which is
		what a river slowing into still water looks like.
	]]
	if lakeShape > 0 then
		surface += (lakeLevel - surface) * lakeShape
	end

	-- The border eases the ground down to a coastline, and the rivers with it,
	-- so a channel does not hang in the air over the falloff.
	if edge < 1 then
		surface = SEA_LEVEL + (surface - SEA_LEVEL) * edge
	end

	local riverAffinity = profile.riverAffinity
	local core, bankMix = 0, 0

	if riverAffinity > 0 then
		-- Rivers give out at altitude: a summit should not be perforated by
		-- channels, and the fade is what turns a river crossing high ground
		-- into a gorge that peters out rather than one that climbs.
		local altitude = 1 - band(land, RIVER_MAX_LAND - RIVER_FADE, RIVER_MAX_LAND)

		if altitude > 0 then
			--[[
				Drainage. The network thickens as the ground falls away and
				thins to headwaters on high country, so the channels gather
				downhill instead of being scattered evenly over terrain the
				noise field knows nothing about. `downstream` above already
				makes an individual river BROADER downstream; this decides how
				many there are at all.
			]]
			local drainage = 1
			if RIVER_DRAINAGE_BIAS ~= 0 then
				drainage = 1 - RIVER_DRAINAGE_BIAS * elevation
				if drainage < 0.25 then
					drainage = 0.25
				end
			end

			local width = (RIVER_WIDTH_HIGH + downstream * (RIVER_WIDTH_LOW - RIVER_WIDTH_HIGH))
				* riverAffinity * drainage
			local bankWidth = RIVER_BANK_WIDTH * riverAffinity * drainage

			--[[
				These are fractions OF THE FIELD, and a width of 1 means "every
				column is river". Three multipliers stack here - the lowland
				interpolation, the biome's affinity and the drainage bias - and
				the config numbers alone do not make the ceiling obvious, so it
				is enforced rather than assumed.
			]]
			if width > 0.9 then
				width = 0.9
			end
			if bankWidth > 0.95 then
				bankWidth = 0.95
			end

			if width > 0 then
				core = smoothstep(clamp01((riverness - (1 - width)) / width)) * altitude
			end
			if bankWidth > 0 then
				bankMix = smoothstep(clamp01((riverness - (1 - bankWidth)) / bankWidth)) * altitude
			end
		end
	end

	if bankMix > 0 then
		-- Grade the flood plain toward the water, bounded so an upland river
		-- leaves a valley rather than a trench.
		local target = surface + BANK_RISE
		if land > target then
			local drop = (land - target) * bankMix * BANK_STRENGTH
			if drop > MAX_BANK_DROP then
				drop = MAX_BANK_DROP
			end
			land -= drop
		end
	end

	if core > 0 then
		-- Cut the channel. Bounded the same way: where the ground is far above
		-- the water table the river becomes a dry valley rather than a canyon
		-- to the bottom of the map, which is both what happens in the world and
		-- what keeps the exposed wall affordable.
		local depth = RIVER_DEPTH_HIGH + downstream * (RIVER_DEPTH_LOW - RIVER_DEPTH_HIGH)
		local bed = surface - depth
		local floor = land - MAX_RIVER_CUT
		if bed < floor then
			bed = floor
		end

		if land > bed then
			land += (bed - land) * core
		end
	end

	-- 8. The world border, eased down so the map ends in a shore.
	if edge < 1 then
		land = MIN_HEIGHT + (land - MIN_HEIGHT) * edge
	end

	--[[
		9. The spawn guarantee, as a floor under the ground rather than as a
		veto on the water.

		It used to be the latter - standing water was simply refused where the
		guarantee was strong - and a veto is a hard threshold, so the ocean
		began along a visible circle at exactly the radius where it lapsed.
		Lifting the GROUND instead is smooth, needs no special case in the
		water rules below, and is also the more honest fix: the reason the
		starting area is dry is that it is high, which is a thing a player can
		see.
	]]
	local guarantee = 1 - profile.waterAllowed
	if guarantee > 0 then
		local dry = SEA_LEVEL + 3
		if land < dry then
			land += (dry - land) * guarantee
		end
	end

	if land < MIN_HEIGHT then
		land = MIN_HEIGHT
	elseif land > MAX_HEIGHT then
		land = MAX_HEIGHT
	end

	land = math.floor(land + 0.5)

	--[[
		10. Where the water actually stands.

		Three sources, and they answer three different questions:

		  A RIVER's surface follows the reference downhill, so it descends with
		  the land it runs through.

		  A LAKE cannot do that - a level that changes across its own width is
		  a sloping sheet of water - so it holds one number over its whole
		  body, chosen in lakeCell above and guaranteed to sit below the
		  untouched ground everywhere inside it.

		  THE SEA fills everything under one global level, which is what makes
		  the continental lowlands into inland seas and the border into a
		  coastline.

		Taking the highest of whichever apply is safe because each one is
		already below the dry ground beside it: the river by the freeboard, the
		lake by the minimum over its own probe ring, and the sea because being
		under it is the test.
	]]
	local waterTop = 0

	if core > 0.02 then
		local top = math.floor(surface + 0.5)
		if top > land then
			waterTop = top
		end
	end

	if lakeShape > 0 and lakeLevel > land and lakeLevel > waterTop then
		waterTop = lakeLevel
	end

	if land < SEA_LEVEL and SEA_LEVEL > waterTop then
		waterTop = SEA_LEVEL
	end

	if waterTop > 0 then
		-- Shallow up anything past the cap by raising the BED, never by
		-- lowering the surface: standing water has to hold one level across its
		-- whole area or its edge steps. This also bounds what a shoreline
		-- column costs to draw, which is the only place water is not free.
		if waterTop - land > MAX_WATER_DEPTH then
			land = waterTop - MAX_WATER_DEPTH
		end

		if waterTop > MAX_HEIGHT then
			waterTop = MAX_HEIGHT
		end
	end

	--[[
		The water level this column is NEAR, wet or not, so BiomeMap can lay a
		beach along the line rather than clipping grass off at the exact block
		the water reaches.

		A dry column cannot see its neighbours - but it does not need to. The
		three things that could put water beside it are the sea, a lake and a
		river, and it already knows all three: the sea has one level
		everywhere, the lake is an object it is either inside or not, and the
		river's surface it computed itself. Taking the highest that applies
		here and letting BiomeMap compare it against the column's own height is
		what makes a shore a band a couple of blocks deep rather than a line.

		`bankMix` rather than `core` for the river, so the sand covers the bank
		the river built and not merely the channel: outside the flood plain the
		height test refuses it anyway.
	]]
	local shoreLevel = if lakeShape > 0 then lakeLevel else SEA_LEVEL

	if bankMix > 0 then
		local top = math.floor(surface + 0.5)
		if top > shoreLevel then
			shoreLevel = top
		end
	end

	if waterTop > shoreLevel then
		shoreLevel = waterTop
	end

	return land, waterTop, mountain, shoreLevel
end

--[[
	Drops the memoised cell grids.

	They are pure functions of position and the seed, so this is only ever a
	speed cache and dropping it is always safe. BiomeMap.clearCaches calls it,
	which matters for exactly one caller: TerrainBench tears the world down and
	then times the rebuild as a COLD load, and a cold load that kept a few
	hundred resolved lakes would not be one.
]]
function Landform.clearCaches()
	table.clear(landmarkCells)
	table.clear(lakeCells)
	table.clear(rawLakeCells)
	lakeWindowX, lakeWindowZ = math.huge, math.huge
	markWindowX, markWindowZ = math.huge, math.huge
end

function Landform.getStats()
	local lakes = 0
	for _, entry in pairs(lakeCells) do
		if entry then
			lakes += 1
		end
	end

	return {
		seed = activeSeed,
		landmarkKinds = #landmarkList,
		lakeKinds = #lakeKinds,
		lakeCells = lakes,
	}
end

return Landform
