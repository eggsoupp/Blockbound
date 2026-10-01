--[[
	BiomeMap

	Turns a world position into (surfaceHeight, biome, topBlock, underBlock,
	variant, waterTop).

	This is the hot path of the whole generator, so it is built around three
	ideas:

	1. ONE SHARED SET OF LANDFORMS.
	   Every biome reuses the same continental, mountain, hill and river fields
	   and only contributes AMPLITUDES to a blend. Cost is therefore the same
	   whether there are 3 biomes or 30, and a mountain range or a river crosses
	   a biome border and tapers instead of stopping at it. The fields
	   themselves live in Landform; this decides how much of each one shows.

	2. A GLOBAL LATTICE.
	   The domain warp and every landform field change slowly, so they are
	   evaluated only on a lattice every TerrainConfig.LatticeStep blocks and
	   bilinearly interpolated. The lattice is keyed on absolute block
	   coordinates, so a column sampled on its own and the same column sampled
	   during chunk generation go through identical arithmetic and cannot
	   disagree. Only the per-block detail roughness is sampled directly,
	   because it exists precisely to differ between neighbours.

	   The sub-biome field joined the lattice too, and that alone removed 512
	   Perlin evaluations from every chunk - more than the whole rest of the
	   lattice put together. What is categorical about a variant is the
	   threshold, not the 260-block field under it.

	3. REGION-BASED BIOME LOOKUP.
	   The world is cut into territories on a jittered grid, looked up in warped
	   space, and each one draws a biome by weighted lottery. Territory SIZE is
	   one number for the whole world; a biome's RARITY is a separate one; its
	   climate claim decides only WHERE it may be drawn. Those were a single
	   number when selection was a Voronoi in climate space, which is why a rare
	   biome could only ever come out as a sliver. See BiomeConfig.

	   The grids are memoised per cell rather than per column - a session visits
	   a few hundred cells - so the per-column cost is nine table reads and nine
	   distances, and climate left the lattice entirely.

	   Climate is not independent of the ground any more. It is sampled at
	   region sites through climateAt, which makes high country colder and low
	   country wetter, so the cold biomes land on the high ground the mountains
	   are already on. See BiomeConfig.TemperatureLapseRate.

	4. COHERENT SURFACE REGIONS.
	   Blocks and structures use the same territory. Heights blend across
	   borders; materials follow continuous contours without per-block lotteries.

	Public API:
	  BiomeMap.init(seed)
	  BiomeMap.sampleColumn(bx, bz) -> height, biomeName, topBlock, underBlock,
	                                   variantName?, waterTop
	  BiomeMap.sampleClimate(bx, bz) -> temperature, humidity
	  BiomeMap.clearCaches()
	  BiomeMap.getStats() -> table

	`waterTop` is the block y of the water surface, or 0 for a dry column. The
	land height is the BED, so water occupies [height, waterTop). See
	TerrainManager for how that is drawn.

	This describes the SURFACE only. What sits underneath is StrataConfig's job,
	and which of that is ore is OreRegistry's, both resolved from the height
	this returns.

	All coordinates are BLOCK coordinates (world studs / TerrainConfig.StudSize).
]]

local TerrainFolder = script.Parent
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))
local BiomeConfig = require(TerrainFolder:WaitForChild("BiomeConfig"))
local LandformConfig = require(TerrainFolder:WaitForChild("LandformConfig"))
local Landform = require(TerrainFolder:WaitForChild("Landform"))
local NoiseField = require(TerrainFolder:WaitForChild("NoiseField"))

local BiomeMap = {}

-- ---------------------------------------------------------------------------
-- Localised config (these are read hundreds of times per chunk)
-- ---------------------------------------------------------------------------

local LATTICE_STEP = TerrainConfig.LatticeStep
local INV_LATTICE_STEP = 1 / LATTICE_STEP
local WORLD_RADIUS = TerrainConfig.WorldRadiusBlocks
local WORLD_SPAN = WORLD_RADIUS * 2
local EDGE_FALLOFF = TerrainConfig.EdgeFalloffBlocks

local CLIMATE_SCALE = BiomeConfig.ClimateScaleBlocks
local WARP_SCALE = BiomeConfig.ClimateWarpScaleBlocks
local WARP_STRENGTH = BiomeConfig.ClimateWarpStrengthBlocks
local BORDER_WARP_SCALE = BiomeConfig.BorderWarpScaleBlocks
local BORDER_WARP_STRENGTH = BiomeConfig.BorderWarpStrengthBlocks
local CONTRAST = BiomeConfig.ClimateContrast
local TEMP_LAPSE = BiomeConfig.TemperatureLapseRate
local HUMID_LOWLAND = BiomeConfig.HumidityLowlandBias
local TEMP_BIAS = BiomeConfig.TemperatureBias
local HUMID_BIAS = BiomeConfig.HumidityBias
local BUFFER_STRENGTH = BiomeConfig.BufferStrength

local REGION_CELL = BiomeConfig.RegionCellBlocks
local INV_REGION_CELL = 1 / REGION_CELL
local PROVINCE_CELL = BiomeConfig.ProvinceCellBlocks
local INV_PROVINCE_CELL = 1 / PROVINCE_CELL
local PROVINCE_BIAS = BiomeConfig.ProvinceBias
local REGION_JITTER = BiomeConfig.RegionJitter
local REGION_BLEND = BiomeConfig.RegionBlendBlocks
local INV_REGION_BLEND = 1 / REGION_BLEND
local CLIMATE_AFFINITY_SQ = BiomeConfig.ClimateAffinity * BiomeConfig.ClimateAffinity

local VARIANT_SCALE = BiomeConfig.VariantScaleBlocks
local VARIANT_EDGE_JITTER = BiomeConfig.VariantEdgeJitter or 0

local DANGER_ONSET = BiomeConfig.DangerOnsetBlocks
local DANGER_RAMP_BASE = BiomeConfig.DangerRampBase
local DANGER_RAMP = BiomeConfig.DangerRampBlocks

local CONTINENT_PIVOT = LandformConfig.ContinentPivot

local ROCK_BLOCK = LandformConfig.RockBlock
local SNOW_BLOCK = LandformConfig.SnowBlock
local ROCK_RIDGE = LandformConfig.RockRidgeThreshold
local ROCK_HEIGHT = LandformConfig.RockHeight
local CONTOUR_VARIATION = LandformConfig.SurfaceContourVariationBlocks
local ROCK_MIN_AMPLITUDE = LandformConfig.RockMinMountainAmplitude
local SHORE_BLOCK = LandformConfig.ShoreBlock
local SHORE_HEIGHT = LandformConfig.ShoreHeightBlocks

-- Lattice keys are packed into a single number so the cache needs no strings.
-- Lattice index range is WorldRadiusBlocks / LatticeStep, comfortably inside
-- these bounds for any sane world size.
local KEY_OFFSET = 8192
local KEY_STRIDE = 65536

-- ---------------------------------------------------------------------------
-- Flattened biome tables
-- ---------------------------------------------------------------------------
-- Arrays instead of hash lookups: the per-column loop touches every one of
-- these once, and array reads are meaningfully cheaper in Luau.

local biomeCount = 0
local biomeNames = {}
local biomeIndexByName = {}
local biomeTemp = {}
local biomeHumid = {}
local biomeRegionWeight = {}
local biomeTop = {}
local biomeUnder = {}

-- The terrain profile, one array per field. Every one of these is blended
-- across a border, which is what makes transitions geographical rather than
-- abrupt - see BiomeConfig's TERRAIN PROFILE notes.
local biomeBase = {}
local biomeContinent = {}
local biomeHill = {}
local biomeRangeBias = {}
local biomeMountain = {}
local biomeSharpness = {}
local biomeRoughness = {}
local biomeCliff = {}
local biomeRiver = {}
local biomeLake = {}
local biomeLandmark = {}
local biomeAridity = {}
local biomeSnowLine = {}

-- Distance-from-spawn gating, precomputed per biome at init. onset is where the
-- biome first gets a ticket in a region lottery; span is how long it takes to
-- reach a full one. biomeAlwaysAvailable marks danger-0 biomes, which skip the
-- calculation entirely.
local biomeOnset = {}
local biomeSpan = {}
local biomeAlwaysAvailable = {}

--[[
	Sub-biome tables, one entry per biome index.

	  biomeVariantNames[i]      array of variant names, or nil if the biome
	                            declares none
	  biomeVariantThresholds[i] cumulative normalised weights, so picking a
	                            variant is a walk over a handful of numbers

	nil rather than an empty array for a biome without variants: the per-column
	path tests this to decide whether to sample the variant field at all.
]]
local biomeVariantNames = {}
local biomeVariantThresholds = {}
local anyBiomeHasVariants = false

-- incompatibleRule[aIndex][bIndex] = { via = index, band = number }
local incompatibleRule = {}

local fallbackIndex = 1
local spawnIndex = 1
local spawnRadius = TerrainConfig.SpawnSafeRadiusBlocks
local spawnGuarantee = TerrainConfig.SpawnGuaranteeBlocks

local function buildBiomeTables()
	local arrays = {
		biomeNames, biomeTemp, biomeHumid, biomeRegionWeight, biomeTop, biomeUnder,
		biomeBase, biomeContinent, biomeHill, biomeRangeBias, biomeMountain, biomeSharpness,
		biomeRoughness, biomeCliff, biomeRiver, biomeLake, biomeLandmark,
		biomeAridity, biomeSnowLine,
		biomeOnset, biomeSpan, biomeAlwaysAvailable,
		biomeVariantNames, biomeVariantThresholds,
	}
	for _, array in ipairs(arrays) do
		table.clear(array)
	end

	biomeCount = 0
	table.clear(biomeIndexByName)
	table.clear(incompatibleRule)
	anyBiomeHasVariants = false

	local defaults = BiomeConfig.TerrainDefaults

	for _, name in ipairs(BiomeConfig.Order) do
		local def = BiomeConfig.Definitions[name]
		if def then
			biomeCount += 1
			local i = biomeCount

			biomeNames[i] = name
			biomeIndexByName[name] = i
			biomeTemp[i] = def.temperature
			biomeHumid[i] = def.humidity
			biomeRegionWeight[i] = def.regionWeight
			biomeTop[i] = def.topBlock
			biomeUnder[i] = def.underBlock

			-- Every profile field falls back to TerrainDefaults, so a biome only
			-- has to name what makes it different.
			local function profile(field)
				local value = def[field]
				return if value ~= nil then value else defaults[field]
			end

			biomeBase[i] = profile("baseHeight")
			biomeContinent[i] = profile("continentAmplitude")
			biomeHill[i] = profile("hillAmplitude")
			biomeRangeBias[i] = profile("rangeBias")
			biomeMountain[i] = profile("mountainAmplitude")
			biomeSharpness[i] = profile("ridgeSharpness")
			biomeRoughness[i] = profile("roughness")
			biomeCliff[i] = profile("cliffStrength")
			biomeRiver[i] = profile("riverAffinity")
			biomeLake[i] = profile("lakeAffinity")
			biomeLandmark[i] = profile("landmarkAffinity")
			biomeAridity[i] = profile("aridity")
			biomeSnowLine[i] = profile("snowLine")

			-- Distance gating, resolved once here rather than per region cell.
			local danger = def.danger or 0
			biomeAlwaysAvailable[i] = danger <= 0
			biomeOnset[i] = danger * DANGER_ONSET
			biomeSpan[i] = DANGER_RAMP_BASE + danger * DANGER_RAMP

			--[[
				Variant weights, turned into cumulative thresholds in 0..1 so a
				lookup is a short walk instead of a sum. Normalised here, which
				is what lets the weights in the config be any scale the author
				finds readable.
			]]
			if def.variants and #def.variants > 0 then
				local names = table.create(#def.variants)
				local thresholds = table.create(#def.variants)

				local total = 0
				for _, variant in ipairs(def.variants) do
					total += variant.weight
				end

				local running = 0
				for index, variant in ipairs(def.variants) do
					running += variant.weight
					names[index] = variant.name
					-- The last threshold is pinned to 1 rather than computed,
					-- so floating-point drift can never leave a sliver of the
					-- field matching no variant at all.
					thresholds[index] = if index == #def.variants then 1 else running / total
				end

				biomeVariantNames[i] = names
				biomeVariantThresholds[i] = thresholds
				anyBiomeHasVariants = true
			end
		end
	end

	fallbackIndex = biomeIndexByName[BiomeConfig.Fallback] or 1

	for _, rule in ipairs(BiomeConfig.Incompatible) do
		local a = biomeIndexByName[rule.a]
		local b = biomeIndexByName[rule.b]
		local via = biomeIndexByName[rule.via or BiomeConfig.Fallback]

		if a and b and via then
			local entry = { via = via, band = rule.band or 0.2 }
			incompatibleRule[a] = incompatibleRule[a] or {}
			incompatibleRule[b] = incompatibleRule[b] or {}
			incompatibleRule[a][b] = entry
			incompatibleRule[b][a] = entry
		end
	end

	local spawnName = if BiomeConfig.Definitions[TerrainConfig.SpawnBiome]
		then TerrainConfig.SpawnBiome
		else BiomeConfig.Fallback

	spawnIndex = biomeIndexByName[spawnName] or fallbackIndex
end

-- ---------------------------------------------------------------------------
-- Noise fields
-- ---------------------------------------------------------------------------
-- Only climate and the variant field live here. Everything that shapes the
-- ground is Landform's.

local warpFieldX, warpFieldZ
local borderWarpX, borderWarpZ
local temperatureField, humidityField
local variantField
local activeSeed = 0

local function buildNoiseFields(seed)
	activeSeed = seed

	local function field(salt, plane, scale, octaves, persistence)
		return NoiseField.new(seed + salt, plane, octaves, persistence, 2, WORLD_SPAN / scale)
	end

	-- Distinct Y planes keep the fields from correlating with each other.
	warpFieldX = field(1, 3.17, WARP_SCALE, 1, 0.5)
	warpFieldZ = field(2, 19.43, WARP_SCALE, 1, 0.5)

	borderWarpX = field(8, 53.11, BORDER_WARP_SCALE, 1, 0.5)
	borderWarpZ = field(9, 71.29, BORDER_WARP_SCALE, 1, 0.5)

	temperatureField = field(
		3, 41.09, CLIMATE_SCALE, BiomeConfig.ClimateOctaves, BiomeConfig.ClimatePersistence
	)
	humidityField = field(
		4, 67.71, CLIMATE_SCALE, BiomeConfig.ClimateOctaves, BiomeConfig.ClimatePersistence
	)

	--[[
		The sub-biome field. Its own plane and offset, so which forest you are
		standing in is uncorrelated with the temperature, the humidity and the
		shape of the ground - otherwise every oak wood would sit in the same
		kind of valley.
	]]
	variantField = field(
		7, 149.33, VARIANT_SCALE, BiomeConfig.VariantOctaves, BiomeConfig.VariantPersistence
	)
end

--[[
	Calibration for the variant field, so that a variant's `weight` means the
	share of ground it actually covers.

	Cutting the field at the cumulative weights only divides it in those
	proportions if the field is UNIFORM. fbm is not: it is a bell clustered hard
	around the middle. Measured over three worlds, weights of 1.0 / 0.85 / 1.5
	produced 2% / 66% / 32% - the first variant had all but vanished.

	So the field is mapped through its own distribution first, which turns it
	uniform; the cut points then land where the weights say. The mean and spread
	are measured from the field itself rather than assumed, so changing the
	octaves recalibrates automatically instead of quietly skewing every biome.
]]
local variantMean = 0.5
local variantSigma = 0.15

local function calibrateVariantField()
	if not anyBiomeHasVariants then
		return
	end

	-- A fixed grid over the whole world: deterministic for a given seed, and
	-- wide enough to span many features of the field rather than sampling one
	-- hill repeatedly.
	local STEPS = 81
	local step = WORLD_SPAN / (STEPS - 1)

	local count = 0
	local sum = 0
	local sumSquares = 0

	for i = 0, STEPS - 1 do
		local bx = -WORLD_RADIUS + i * step
		for j = 0, STEPS - 1 do
			local bz = -WORLD_RADIUS + j * step
			local value = variantField:sample01(bx, bz, VARIANT_SCALE)

			count += 1
			sum += value
			sumSquares += value * value
		end
	end

	variantMean = sum / count

	local variance = sumSquares / count - variantMean * variantMean
	variantSigma = math.max(1e-4, math.sqrt(math.max(0, variance)))
end

--[[
	Which sub-region of its biome a column belongs to, or nil when the biome
	declares no variants.

	The FIELD is read off the lattice - `raw` is handed in by the caller. What
	is categorical is the threshold, not the field under it, and the field is a
	260-block fbm that the 4-block lattice resolves many times over. Sampling
	it per column instead cost two Perlin evaluations for every one of the 256
	columns in a chunk - 512 calls, more than the whole rest of the lattice put
	together - to reproduce a number that four interpolated neighbours already
	agree on.

	The per-column part that genuinely has to be per column is the edge jitter
	below, which exists to be different for adjacent blocks.
]]
local function variantAt(biomeIndex, raw, bx, bz)
	local names = biomeVariantNames[biomeIndex]
	if not names then
		return nil
	end

	-- Bell -> uniform, so the cut points below land where the weights say. The
	-- logistic is a standard approximation to the normal CDF, accurate to about
	-- one percent - far finer than anyone can perceive in the size of a wood.
	local value = 1 / (1 + math.exp(-1.702 * (raw - variantMean) / variantSigma))

	-- Roughen the border so the treeline is ragged at tree scale. A threshold
	-- on a smooth field is otherwise a suspiciously clean curve on the ground.
	if VARIANT_EDGE_JITTER > 0 then
		local jitter = math.sin(bx * 12.9898 + bz * 78.233) * 43758.5453
		jitter -= math.floor(jitter)
		value += (jitter - 0.5) * VARIANT_EDGE_JITTER

		if value < 0 then
			value = 0
		elseif value > 1 then
			value = 1
		end
	end

	local thresholds = biomeVariantThresholds[biomeIndex]
	for index = 1, #thresholds do
		if value <= thresholds[index] then
			return names[index]
		end
	end

	return names[#names]
end

-- ---------------------------------------------------------------------------
-- Lattice cache
-- ---------------------------------------------------------------------------
-- Eight parallel numeric maps rather than one map of tables: no per-point
-- allocation, and clearing is eight table.clear calls.
--
-- EVICTION. Held in two generations rather than one map that is emptied when it
-- fills. Wiping wholesale is O(1) and safe - these are pure functions of
-- position - but it throws away the points being used RIGHT NOW along with the
-- ones that went cold, so a player standing on a cache boundary pays to
-- recompute their own surroundings immediately after clearing them.
--
-- Instead, a full young generation is demoted to old and a fresh young one
-- starts. A lookup that misses young but hits old is promoted back, so anything
-- still in use survives every rotation, while anything genuinely cold is
-- dropped one rotation later. Lookups stay O(1) - at worst two hash probes -
-- and total residency is still bounded by LatticeCacheLimit.

local FIELD_COUNT = 9

local young = {}
local old = {}
local latticeCount = 0
local oldLatticeCount = 0

for i = 1, FIELD_COUNT do
	young[i] = {}
	old[i] = {}
end

local LATTICE_GENERATION_LIMIT = math.max(1, math.floor(TerrainConfig.LatticeCacheLimit / 2))

local function rotateLatticeGenerations()
	for i = 1, FIELD_COUNT do
		old[i] = young[i]
		young[i] = {}
	end
	oldLatticeCount = latticeCount
	latticeCount = 0
end

local function clamp01(v)
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

--[[
	Stretches raw fbm toward the extremes and applies the world-wide bias.
	Clamping at the ends is deliberate: it turns the tails into plateaus, which
	is what gives large, coherent hot and cold regions instead of thin slivers.
]]
local function shapeClimate(raw, bias)
	return clamp01(0.5 + raw * CONTRAST * 0.5 + bias)
end

--[[
	The climate at a position, after the ground it sits on has had its say.

	Two noise fields alone know nothing about the land under them, so where a
	biome goes and what shape the ground there is were independent rolls -
	which is what let snow country turn up on the coastal plain and deserts in
	basins. The continent field is the one piece of geography that exists
	before any biome is chosen, so it is what both corrections read.

	  high ground is COLDER   (BiomeConfig.TemperatureLapseRate)
	  low ground is WETTER    (BiomeConfig.HumidityLowlandBias)

	Sampled at region and province SITES only - a few hundred times for a whole
	session - so the extra continent sample costs nothing per column, and the
	same function runs inside calibrateClimateFit so a biome's SHARE of the
	world is unchanged by either correction. Only where it sits changes.
]]
local function climateAt(x, z)
	local elevation = Landform.continentAt(x, z) - CONTINENT_PIVOT

	local temperature = shapeClimate(
		temperatureField:sample(x, z, CLIMATE_SCALE), TEMP_BIAS - TEMP_LAPSE * elevation
	)
	local humidity = shapeClimate(
		humidityField:sample(x, z, CLIMATE_SCALE), HUMID_BIAS - HUMID_LOWLAND * elevation
	)

	return temperature, humidity
end

--[[
	Evaluates and caches one lattice point. ix/iz are lattice indices, so the
	world position is (ix * LATTICE_STEP, iz * LATTICE_STEP).

	Returns warpedX, warpedZ, continent, ranges, ridge, hills, riverness,
	basin, variant - in that order, matching the field arrays.

	The first two used to be temperature and humidity. They are the WARPED
	POSITION now: the region grid is what selects a biome, and it is looked up
	in warped space so that its cells come out as organic territories rather
	than as squares. Climate is still sampled, but only at region sites - a few
	hundred times for a whole session - so it left the lattice entirely and took
	two Perlin calls per lattice point with it.
]]
local function latticeAt(ix, iz)
	local key = (ix + KEY_OFFSET) * KEY_STRIDE + (iz + KEY_OFFSET)

	local y1 = young[1]
	local cached = y1[key]
	if cached ~= nil then
		return cached, young[2][key], young[3][key], young[4][key], young[5][key],
			young[6][key], young[7][key], young[8][key], young[9][key]
	end

	-- Still warm, one generation back. Read it all out BEFORE any rotation,
	-- which would otherwise overwrite the tables these values live in.
	local aged = old[1][key]
	if aged ~= nil then
		local a2, a3, a4 = old[2][key], old[3][key], old[4][key]
		local a5, a6, a7 = old[5][key], old[6][key], old[7][key]
		local a8, a9 = old[8][key], old[9][key]

		if latticeCount >= LATTICE_GENERATION_LIMIT then
			rotateLatticeGenerations()
		end

		young[1][key] = aged
		young[2][key] = a2
		young[3][key] = a3
		young[4][key] = a4
		young[5][key] = a5
		young[6][key] = a6
		young[7][key] = a7
		young[8][key] = a8
		young[9][key] = a9
		latticeCount += 1

		return aged, a2, a3, a4, a5, a6, a7, a8, a9
	end

	if latticeCount >= LATTICE_GENERATION_LIMIT then
		rotateLatticeGenerations()
	end

	local wx = ix * LATTICE_STEP
	local wz = iz * LATTICE_STEP

	--[[
		Domain warp, in two stages.

		The continental warp displaces the region lookup by hundreds of blocks,
		which is what turns a grid of cells into long interlocking territories.
		The border warp adds a few blocks of high-frequency wobble on top, which
		roughens the last stretch of an edge without being able to move it - so
		borders come out bitten rather than drawn, and the regions themselves
		stay whole.

		Amplitude has to stay well under the warp SCALE or the map folds back on
		itself and tears regions into pieces. At 495 over 2025 the gradient is
		about a third, comfortably smooth.
	]]
	local warpedX = wx
		+ warpFieldX:sample(wx, wz, WARP_SCALE) * WARP_STRENGTH
		+ borderWarpX:sample(wx, wz, BORDER_WARP_SCALE) * BORDER_WARP_STRENGTH
	local warpedZ = wz
		+ warpFieldZ:sample(wx, wz, WARP_SCALE) * WARP_STRENGTH
		+ borderWarpZ:sample(wx, wz, BORDER_WARP_SCALE) * BORDER_WARP_STRENGTH

	-- The landform fields are sampled at the UNWARPED position: the warp is
	-- about the shape of biome borders, and applying it to the geography as
	-- well would drag rivers and ranges sideways with the biome map.
	local continent, ranges, ridge, hills, riverness, basin = Landform.sampleLow(wx, wz)

	-- The sub-biome field. On the lattice like everything else slow: it is a
	-- 260-block fbm, so four interpolated neighbours reproduce it exactly, and
	-- sampling it per column was the single largest noise cost in a chunk.
	local variant = variantField:sample01(wx, wz, VARIANT_SCALE)

	young[1][key] = warpedX
	young[2][key] = warpedZ
	young[3][key] = continent
	young[4][key] = ranges
	young[5][key] = ridge
	young[6][key] = hills
	young[7][key] = riverness
	young[8][key] = basin
	young[9][key] = variant
	latticeCount += 1

	return warpedX, warpedZ, continent, ranges, ridge, hills, riverness, basin, variant
end

-- Bilinear read of the lattice, filled into the caller's scratch array so that
-- eight interpolated values cost no allocation.
local sampled = table.create(FIELD_COUNT, 0)

local function sampleLattice(bx, bz)
	local fx = bx * INV_LATTICE_STEP
	local fz = bz * INV_LATTICE_STEP
	local ix = math.floor(fx)
	local iz = math.floor(fz)
	local tx = fx - ix
	local tz = fz - iz

	local a1, a2, a3, a4, a5, a6, a7, a8, a9 = latticeAt(ix, iz)
	local b1, b2, b3, b4, b5, b6, b7, b8, b9 = latticeAt(ix + 1, iz)
	local c1, c2, c3, c4, c5, c6, c7, c8, c9 = latticeAt(ix, iz + 1)
	local d1, d2, d3, d4, d5, d6, d7, d8, d9 = latticeAt(ix + 1, iz + 1)

	-- Written out rather than looped through a helper: this runs once per
	-- column, and a closure here would allocate 256 of them per chunk.
	local t0, t1

	t0 = a1 + (b1 - a1) * tx
	t1 = c1 + (d1 - c1) * tx
	sampled[1] = t0 + (t1 - t0) * tz

	t0 = a2 + (b2 - a2) * tx
	t1 = c2 + (d2 - c2) * tx
	sampled[2] = t0 + (t1 - t0) * tz

	t0 = a3 + (b3 - a3) * tx
	t1 = c3 + (d3 - c3) * tx
	sampled[3] = t0 + (t1 - t0) * tz

	t0 = a4 + (b4 - a4) * tx
	t1 = c4 + (d4 - c4) * tx
	sampled[4] = t0 + (t1 - t0) * tz

	t0 = a5 + (b5 - a5) * tx
	t1 = c5 + (d5 - c5) * tx
	sampled[5] = t0 + (t1 - t0) * tz

	t0 = a6 + (b6 - a6) * tx
	t1 = c6 + (d6 - c6) * tx
	sampled[6] = t0 + (t1 - t0) * tz

	t0 = a7 + (b7 - a7) * tx
	t1 = c7 + (d7 - c7) * tx
	sampled[7] = t0 + (t1 - t0) * tz

	t0 = a8 + (b8 - a8) * tx
	t1 = c8 + (d8 - c8) * tx
	sampled[8] = t0 + (t1 - t0) * tz

	t0 = a9 + (b9 - a9) * tx
	t1 = c9 + (d9 - c9) * tx
	sampled[9] = t0 + (t1 - t0) * tz

	return sampled
end

--[[
	How strongly the spawn area asserts itself at a position, from 1 at the
	origin to 0 past SpawnSafeRadiusBlocks.

	  THE GUARANTEE. Inside SpawnGuaranteeBlocks this returns exactly 1, and
	  measures distance as a SQUARE rather than a circle - so it lines up with
	  the chunk grid and the promise is literally "the first N chunks".

	  THE BLEND. Between the guarantee and SpawnSafeRadiusBlocks it smoothsteps
	  down to 0, so the safe area dissolves into the world instead of ending at
	  a visible line.
]]
local function spawnInfluence(bx, bz)
	if spawnRadius <= 0 then
		return 0
	end

	-- Chebyshev distance: the guarantee is a square of chunks, not a disc.
	local square = math.max(math.abs(bx), math.abs(bz))
	if square <= spawnGuarantee then
		return 1
	end

	local distance = math.sqrt(bx * bx + bz * bz)
	if distance >= spawnRadius then
		return 0
	end

	local inner = math.min(spawnGuarantee, spawnRadius - 1)
	local k = 1 - (distance - inner) / (spawnRadius - inner)
	if k <= 0 then
		return 0
	elseif k >= 1 then
		return 1
	end

	return k * k * (3 - 2 * k) -- smoothstep, so the edge of the safe zone is invisible
end

-- ---------------------------------------------------------------------------
-- Regions
-- ---------------------------------------------------------------------------

--[[
	THE SELECTION MODEL

	The world is cut into REGION CELLS on a jittered grid, looked up in WARPED
	space so the cells come out as organic territories rather than squares. Each
	cell draws one biome by weighted lottery; a column blends the cells nearest
	it. Three separate numbers do three separate jobs:

	  RegionCellBlocks  how big a territory is    - one number, all biomes
	  regionWeight      how often a biome is drawn - per biome, rarity only
	  temperature       where it may be drawn      - per biome, placement only
	  humidity

	WHY IT REPLACED CLIMATE-SPACE VORONOI

	A biome used to win the ground nearest its climate claim, so its territory
	WAS its share of climate space: one number set both how often you met it and
	how large it was. "Rare" could therefore only mean "small", which is exactly
	backwards - the biome you seldom find is the one that most has to be worth
	the walk. Measured on the old model, Corruption held 3.9% of the world in
	regions typically 1,000 studs across with 12% of its area in fragments under
	600 studs, and turned up in 12 of 60 ten-minute walks.

	Splitting the two costs one grid lookup per column and no extra noise: the
	warp was already sampled, and climate moved OFF the lattice to region sites,
	which is a couple of hundred samples for a whole session instead of two per
	lattice point.
]]

-- The project's usual position hash: cheap, deterministic, no allocation.
local function hashCell(x, z, salt)
	local v = math.sin(x * 127.1 + z * 311.7 + salt) * 43758.5453
	return v - math.floor(v)
end

--[[
	Each biome's AVERAGE climate fit over the world, measured at init.

	Without it `regionWeight` does not mean what it says. A claim near the
	middle of climate space scores nearly 1 almost everywhere, while one out on
	a JOINT tail - Desert is hot AND dry, Corruption cold AND wet - scores a
	fraction of that, because two independent bell-shaped fields rarely reach
	their extremes together. Measured, that alone held Desert to 2.1% of the
	world on weights that should have given it 14%.

	Dividing each biome's fit by its own mean makes every claim worth the same
	on average, so climate decides WHERE a biome may be drawn and the weight
	decides HOW MUCH of the world it gets. Same trick, and the same reason, as
	calibrateVariantField above.
]]
local climateFitMean = {}

local function calibrateClimateFit()
	local STEPS = 41
	local step = WORLD_SPAN / (STEPS - 1)

	for i = 1, biomeCount do
		climateFitMean[i] = 0
	end

	local count = 0
	for i = 0, STEPS - 1 do
		local bx = -WORLD_RADIUS + i * step
		for j = 0, STEPS - 1 do
			local bz = -WORLD_RADIUS + j * step
			local temperature, humidity = climateAt(bx, bz)
			count += 1

			for k = 1, biomeCount do
				local dt = temperature - biomeTemp[k]
				local dh = humidity - biomeHumid[k]
				climateFitMean[k] += math.exp(-(dt * dt + dh * dh) / CLIMATE_AFFINITY_SQ)
			end
		end
	end

	for i = 1, biomeCount do
		local mean = climateFitMean[i] / count
		climateFitMean[i] = if mean < 1e-4 then 1e-4 else mean
	end
end

--[[
	How much of a ticket biome `i` gets in a lottery held `radius` blocks from
	the origin. 0 means it is simply not drawn here.

	This is `danger`, and it is now evaluated ONCE PER TERRITORY at that
	territory's own site rather than per column. That is the whole difference
	from the old gate: a biome is either drawn for a region or it is not, and if
	it is, the region is full size. The old version multiplied a per-column
	distance, so a half-available biome did not appear half as often - it
	appeared as half-sized fragments wedged between its neighbours.

	`radius` is measured in WARPED space, so it is out by up to the warp
	amplitude. That is left alone deliberately: the ramp is hundreds of blocks
	wide already, and the error turns "dangerous country starts here" from a
	perfect circle around the origin into a ragged one.
]]
local function dangerTicket(i, radius)
	if biomeAlwaysAvailable[i] then
		return 1
	end

	local t = (radius - biomeOnset[i]) / biomeSpan[i]
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return t * t * (3 - 2 * t)
end

-- Scratch for the lottery. Never survives a yield.
local lotteryWeight = table.create(16, 0)

--[[
	The lottery both grids run.

	`boostIndex` is the province's biome and `boostAmount` how hard a region
	cell is pulled toward it; the province grid itself passes neither. Climate
	is sampled HERE, at the site, which is the only place it is sampled at all.
]]
local function drawBiome(siteX, siteZ, salt, boostIndex, boostAmount)
	local temperature, humidity = climateAt(siteX, siteZ)

	local radius = math.sqrt(siteX * siteX + siteZ * siteZ)
	local total = 0

	for i = 1, biomeCount do
		local ticket = dangerTicket(i, radius)
		local weight = 0

		if biomeTop[i] == SNOW_BLOCK then
			ticket *= clamp01((BiomeConfig.SnowMaxTemperature - temperature)
				/ BiomeConfig.ClimateEligibilityFeather)
		elseif biomeNames[i] == "Desert" then
			ticket *= clamp01((temperature - BiomeConfig.DesertMinTemperature)
				/ BiomeConfig.ClimateEligibilityFeather)
		end

		if ticket > 0 then
			local dt = temperature - biomeTemp[i]
			local dh = humidity - biomeHumid[i]
			local fit = math.exp(-(dt * dt + dh * dh) / CLIMATE_AFFINITY_SQ)
				/ climateFitMean[i]

			weight = biomeRegionWeight[i] * fit * ticket
			if i == boostIndex then
				weight *= 1 + boostAmount
			end
		end

		lotteryWeight[i] = weight
		total += weight
	end

	-- Only reachable if every biome is danger-gated out, which the spawn biome
	-- never is. Falling back to it beats returning nothing.
	if total <= 0 then
		return spawnIndex
	end

	local roll = hashCell(siteX * 0.013, siteZ * 0.017, salt) * total
	local running = 0
	for i = 1, biomeCount do
		running += lotteryWeight[i]
		if roll <= running then
			return i
		end
	end

	return biomeCount
end

--[[
	Memoised grid cells. Both are pure functions of a cell index and the seed,
	and a session visits a few hundred of them, so they are worked out once
	rather than per column - the same treatment Landform gives landmark cells.

	Regions hold three values each, so they are three parallel maps rather than
	a table per cell: no allocation, and clearing is three table.clear calls.
]]
local provinceBiome = {}
local regionSiteX = {}
local regionSiteZ = {}
local regionBiome = {}

local function provinceAt(cx, cz)
	local key = (cx + KEY_OFFSET) * KEY_STRIDE + (cz + KEY_OFFSET)

	local cached = provinceBiome[key]
	if cached ~= nil then
		return cached
	end

	local jx = 0.5 + (hashCell(cx, cz, activeSeed * 0.011 + 31.7) - 0.5) * 2 * REGION_JITTER
	local jz = 0.5 + (hashCell(cx, cz, activeSeed * 0.011 + 57.3) - 0.5) * 2 * REGION_JITTER

	local biome = drawBiome(
		(cx + jx) * PROVINCE_CELL,
		(cz + jz) * PROVINCE_CELL,
		activeSeed * 0.019 + 91.3
	)

	provinceBiome[key] = biome
	return biome
end

local function regionAt(cx, cz)
	local key = (cx + KEY_OFFSET) * KEY_STRIDE + (cz + KEY_OFFSET)

	local cached = regionBiome[key]
	if cached ~= nil then
		return regionSiteX[key], regionSiteZ[key], cached
	end

	local jx = 0.5 + (hashCell(cx, cz, activeSeed * 0.011 + 3.1) - 0.5) * 2 * REGION_JITTER
	local jz = 0.5 + (hashCell(cx, cz, activeSeed * 0.011 + 7.9) - 0.5) * 2 * REGION_JITTER

	local siteX = (cx + jx) * REGION_CELL
	local siteZ = (cz + jz) * REGION_CELL

	-- The province is found from the SITE, not from the cell index, so a cell
	-- whose site has drifted over a province border belongs to the province it
	-- actually sits in.
	local province = provinceAt(
		math.floor(siteX * INV_PROVINCE_CELL),
		math.floor(siteZ * INV_PROVINCE_CELL)
	)

	local biome = drawBiome(
		siteX, siteZ, activeSeed * 0.023 + 13.7, province, PROVINCE_BIAS
	)

	regionSiteX[key] = siteX
	regionSiteZ[key] = siteZ
	regionBiome[key] = biome

	return siteX, siteZ, biome
end

-- ---------------------------------------------------------------------------
-- Biome resolution
-- ---------------------------------------------------------------------------

--[[
	Scratch buffers, reused across calls. Generation is single-threaded per
	chunk and these never survive a yield, so sharing them is safe and saves an
	allocation per column.

	THERE ARE TWO SETS. computeBlend is re-entrant now: resolving a lake cell
	asks what the ground is like at the lake site, and that question is a biome
	blend, asked from inside compose while the COLUMN blend is still being read.
	Handing the buffers in rather than closing over one set is what keeps the
	two from overwriting each other - and it means the site answer and the
	column answer go through identical arithmetic, which they must, because a
	lake surface derived from a different blend than the ground under it is a
	lake that floods or vanishes.
]]
local cellBiome = table.create(9, 0)
local cellDistance = table.create(9, 0)
local blendWeight = table.create(16, 0)

local siteCellBiome = table.create(9, 0)
local siteCellDistance = table.create(9, 0)
local siteWeight = table.create(16, 0)

--[[
	Turns a warped position into normalised blend weights in blendWeight, indexed
	by biome index, and returns the dominant biome index.

	Every one of the nine cells around the column contributes whatever the
	falloff gives it, which is nothing for most of them - so there is no nearest-
	N list to sort, and two cells that drew the SAME biome simply add together,
	which is what merges neighbouring cells into one territory.

	Nine is enough, and provably so: BiomeConfig.validate refuses a jitter and
	blend width combination that would let a tenth cell matter. Widen the blend
	without checking that and the map seams along the cell grid.

	Also enforces BiomeConfig.Incompatible: when a forbidden pair turns up, the
	rule's `via` biome is faded in across their border hard enough to own the
	surface there, so the two never actually meet.

	`influence` is the spawn guarantee, and the caller supplies it because it
	has to be measured at the column's REAL position - the warped one can be
	hundreds of blocks away, which would put the starting area somewhere else.
]]
local function computeBlend(warpedX, warpedZ, influence, blendWeight, cellBiome, cellDistance)
	for i = 1, biomeCount do
		blendWeight[i] = 0
	end

	local cx = math.floor(warpedX * INV_REGION_CELL)
	local cz = math.floor(warpedZ * INV_REGION_CELL)

	local nearest = math.huge
	local slot = 0

	for ox = -1, 1 do
		for oz = -1, 1 do
			local siteX, siteZ, biome = regionAt(cx + ox, cz + oz)
			local dx = warpedX - siteX
			local dz = warpedZ - siteZ
			local distance = dx * dx + dz * dz

			slot += 1
			cellBiome[slot] = biome
			cellDistance[slot] = distance

			if distance < nearest then
				nearest = distance
			end
		end
	end

	local total = 0
	local contributors = 0
	nearest = math.sqrt(nearest)
	local cutoffSquared = (nearest + REGION_BLEND) ^ 2

	for i = 1, 9 do
		-- Most region sites cannot contribute. Reject in squared distance,
		-- saving their square roots on every generated column and site probe.
		if cellDistance[i] >= cutoffSquared then
			continue
		end
		cellDistance[i] = math.sqrt(cellDistance[i])
		local falloff = 1 - (cellDistance[i] - nearest) * INV_REGION_BLEND
		if falloff > 0 then
			local weight = falloff * falloff
			blendWeight[cellBiome[i]] += weight
			total += weight

			-- Compact the contributing cells to the front, so the pair check
			-- below walks two or three entries rather than nine.
			contributors += 1
			cellBiome[contributors] = cellBiome[i]
			cellDistance[contributors] = cellDistance[i]
		end
	end

	--[[
		Compatibility buffers.

		Every contributing pair is checked, not just the closest two: where three
		territories meet, a forbidden pair can be second and third in the list,
		and checking only the top two lets them touch at that corner.
	]]
	for a = 1, contributors - 1 do
		local rulesForA = incompatibleRule[cellBiome[a]]
		if rulesForA then
			local d1 = cellDistance[a]

			for b = a + 1, contributors do
				local rule = rulesForA[cellBiome[b]]
				if rule then
					local d2 = cellDistance[b]
					local low, high = d1, d2
					if low > high then
						low, high = high, low
					end

					local sum = low + high
					-- 0 exactly on the border between the two, rising as one
					-- territory pulls ahead.
					local closeness = if sum > 1e-6 then (high - low) / sum else 0

					if closeness < rule.band then
						local strength = 1 - closeness / rule.band
						strength = strength * strength * (3 - 2 * strength)

						local extra = strength * BUFFER_STRENGTH
						blendWeight[rule.via] += extra
						total += extra
					end
				end
			end
		end
	end

	if total <= 0 then
		blendWeight[cellBiome[1]] = 1
		total = 1
	end

	--[[
		The spawn guarantee, applied to the finished weights.

		Lerping toward a pure spawn-biome distribution is both simpler and
		stronger than nudging climate was: inside SpawnGuaranteeBlocks the
		influence is exactly 1, so the starting area IS the spawn biome, and it
		dissolves smoothly over SpawnSafeRadiusBlocks because the influence is
		already a smoothstep.
	]]
	local inverseTotal = 1 / total
	local dominant = cellBiome[1]
	local dominantWeight = -1

	for i = 1, biomeCount do
		local weight = blendWeight[i] * inverseTotal

		if influence > 0 then
			local target = if i == spawnIndex then 1 else 0
			weight += (target - weight) * influence
		end

		blendWeight[i] = weight
		if weight > dominantWeight then
			dominantWeight = weight
			dominant = i
		end
	end

	-- The share as well as the winner: a column whose dominant biome holds
	-- essentially all of the weight is not near a border, and the surface
	-- lottery has nothing to decide there.
	return dominant, dominantWeight
end

-- 1 well inside the world, easing to 0 at the boundary. Since MinHeight is
-- below the water table, that turns the border into a coastline.
local function edgeFactor(bx, bz)
	if EDGE_FALLOFF <= 0 then
		return 1
	end

	local marginX = WORLD_RADIUS - math.abs(bx)
	local marginZ = WORLD_RADIUS - math.abs(bz)
	local margin = if marginX < marginZ then marginX else marginZ

	if margin >= EDGE_FALLOFF then
		return 1
	elseif margin <= 0 then
		return 0
	end

	local k = margin / EDGE_FALLOFF
	return k * k * (3 - 2 * k)
end

-- Surface regions follow the same warped territory as structures. Height
-- profiles still blend, but individual blocks are never chosen by lottery.
-- Reuse the coherent detail field for small contour variation, without another
-- noise evaluation or isolated salt-and-pepper snow/stone pixels.
local function surfaceBlock(dominant, height, mountain, mountainAmplitude, detail, shoreLevel)
	local snowLine = biomeSnowLine[dominant] + detail * CONTOUR_VARIATION
	local snowy = biomeTop[dominant] == SNOW_BLOCK or height >= snowLine
	if mountainAmplitude >= ROCK_MIN_AMPLITUDE and mountain > ROCK_RIDGE + 0.07 + detail * 0.025 then
		return ROCK_BLOCK
	end
	if snowy then
		return SNOW_BLOCK
	end
	if height >= ROCK_HEIGHT + detail * CONTOUR_VARIATION then
		return ROCK_BLOCK
	end
	if shoreLevel > 0 and height >= shoreLevel and height <= shoreLevel + SHORE_HEIGHT then
		-- Cold shores stay rocky. Inland temperate lakes retain grassy banks;
		-- sand belongs to warm coasts and the desert, not every water contour.
		if biomeTemp[dominant] < 0.35 then
			return ROCK_BLOCK
		end
		if biomeTop[dominant] == SHORE_BLOCK or shoreLevel <= LandformConfig.SeaLevel then
			return SHORE_BLOCK
		end
	end
	return biomeTop[dominant]
end
-- ---------------------------------------------------------------------------
-- The site probe
-- ---------------------------------------------------------------------------

--[[
	What the ground is like at an arbitrary POSITION, for Landform's cell grids.

	Landform's lakes and landmarks are objects rather than fields, and an object
	has to settle its properties once for its whole body. A lake in particular
	has to choose one surface height and hold it - a level that varies across
	its own width is water running downhill - and choosing it needs to know the
	biome numbers at the lake's site.

	That is a question only this module can answer, and Landform is required BY
	this module, so the dependency is inverted: Landform.setSiteProbe installs
	this at init and calls it a handful of times per cell, memoised. A session
	resolves a few hundred cells.

	Three things this must not do, all of them because it is called from inside
	Landform.compose while a column is halfway through being built:

	  * touch Landform.Profile - compose is reading it;
	  * use the shared blend buffers - hence the site set;
	  * go through the lattice, which is sized and evicted for the columns a
	    player is actually standing near. Probe points are hundreds of blocks
	    away and used once, so they warp their own position directly.
]]
local function probeSite(x, z)
	local warpedX = x
		+ warpFieldX:sample(x, z, WARP_SCALE) * WARP_STRENGTH
		+ borderWarpX:sample(x, z, BORDER_WARP_SCALE) * BORDER_WARP_STRENGTH
	local warpedZ = z
		+ warpFieldZ:sample(x, z, WARP_SCALE) * WARP_STRENGTH
		+ borderWarpZ:sample(x, z, BORDER_WARP_SCALE) * BORDER_WARP_STRENGTH

	local influence = spawnInfluence(x, z)
	computeBlend(warpedX, warpedZ, influence, siteWeight, siteCellBiome, siteCellDistance)

	local base, continentAmplitude, hillAmplitude = 0, 0, 0
	local aridity, lakeAffinity = 0, 0

	for i = 1, biomeCount do
		local weight = siteWeight[i]
		if weight > 0 then
			base += biomeBase[i] * weight
			continentAmplitude += biomeContinent[i] * weight
			hillAmplitude += biomeHill[i] * weight
			aridity += biomeAridity[i] * weight
			lakeAffinity += biomeLake[i] * weight
		end
	end

	-- The spawn guarantee suppresses dug and standing water, and it has to do
	-- so here as well or a lake settles inside the starting area and then finds
	-- the ground under it lifted out from underneath.
	lakeAffinity *= 1 - influence

	return base, continentAmplitude, hillAmplitude, aridity, lakeAffinity
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	Must be called before sampling. Safe to call again to reseed; caches are
	dropped so nothing stale survives.
]]
function BiomeMap.init(seed)
	TerrainConfig.validate()
	BiomeConfig.validate()

	-- Perlin repeats every 256 lattice units; a climate scale below this makes
	-- the same biome layout tile across the map. Checked here because it needs
	-- both configs. LandformConfig.validate does the same for the geography.
	local minScale = WORLD_SPAN / 200
	if CLIMATE_SCALE < minScale or WARP_SCALE < minScale then
		warn(string.format(
			"[BiomeMap] ClimateScaleBlocks (%d) / ClimateWarpScaleBlocks (%d) should exceed "
				.. "%.1f at this world radius, or the biome layout will visibly repeat.",
			CLIMATE_SCALE, WARP_SCALE, minScale
		))
	end

	spawnRadius = TerrainConfig.SpawnSafeRadiusBlocks
	spawnGuarantee = TerrainConfig.SpawnGuaranteeBlocks

	buildBiomeTables()
	buildNoiseFields(seed or 0)
	Landform.init(seed or 0)

	-- Both need the fields to exist. calibrateVariantField is skipped entirely
	-- when no biome declares variants; calibrateClimateFit is what makes
	-- regionWeight mean the same thing for a claim in the middle of climate
	-- space and one out on a joint tail, so it always runs.
	calibrateVariantField()
	calibrateClimateFit()

	-- Last, and after the calibration: the probe runs a full biome blend, so
	-- everything it reads has to be standing. Installing it also drops
	-- Landform's cell caches, which is what stops a reseed inheriting the old
	-- world's lakes.
	Landform.setSiteProbe(probeSite)

	BiomeMap.clearCaches()
end

function BiomeMap.clearCaches()
	for i = 1, FIELD_COUNT do
		table.clear(young[i])
		table.clear(old[i])
	end
	latticeCount = 0
	oldLatticeCount = 0

	-- The region and province grids are keyed on the seed, so a reseed has to
	-- drop them or the new world inherits the old one's territories. They are
	-- bounded by the cells a session actually visits - a few hundred at this
	-- cell size - so they are never evicted, only cleared.
	table.clear(provinceBiome)
	table.clear(regionSiteX)
	table.clear(regionSiteZ)
	table.clear(regionBiome)

	-- Landform holds the lake and landmark grids on the same terms: pure
	-- functions of the seed, memoised, and safe to drop at any time.
	Landform.clearCaches()
end

--[[
	Climate at a block position, after warping and shaping. Useful for debugging
	and for anything that wants to gate on climate.

	Sampled directly rather than read off the lattice: climate no longer decides
	a column's biome - it decides which biome a REGION may draw, and that
	happens at region sites - so it is not on the lattice to be read.
]]
function BiomeMap.sampleClimate(bx, bz)
	local fields = sampleLattice(bx, bz)

	-- Through climateAt, so what this reports is what the region lottery
	-- actually saw - including the lapse that makes high ground colder.
	return climateAt(fields[1], fields[2])
end

--[[
	The one function chunk generation calls per column.

	Returns: height (integer blocks - the top of the SOLID ground), biomeName,
	topBlockName, underBlockName, variantName (nil when the biome declares
	none), waterTop (block y of the water surface, 0 when dry).

	Returns multiple values rather than a table on purpose - this runs 256 times
	per chunk and the table would be pure garbage.
]]
function BiomeMap.sampleColumn(bx, bz)
	--[[
		Read out of the shared lattice buffer IMMEDIATELY.

		`sampled` is one table reused by every caller, and resolving a lake
		cell inside compose below asks the probe about positions hundreds of
		blocks away, which samples the lattice again and overwrites it. Nine
		locals cost nothing and make that impossible to get wrong.

		[1] and [2] are the interpolated WARPED position, which is where the
		region grid is looked up - that is what makes its cells organic rather
		than square. [9] is the sub-biome field.
	]]
	local fields = sampleLattice(bx, bz)
	local warpedX, warpedZ = fields[1], fields[2]
	local continentValue, rangeValue, ridgeValue = fields[3], fields[4], fields[5]
	local hillValue, riverValue, basinValue = fields[6], fields[7], fields[8]
	local variantValue = fields[9]

	-- Measured at the REAL position, not the warped one, and handed to the
	-- blend: the warp can be hundreds of blocks, which would put the starting
	-- area somewhere other than where the player starts.
	local influence = spawnInfluence(bx, bz)

	local dominant = computeBlend(
		warpedX, warpedZ, influence, blendWeight, cellBiome, cellDistance
	)

	-- Blend the biome PARAMETERS, not the landform. One shared geography, many
	-- biome flavours, and every transition gradual because every one of these
	-- numbers crosses the border as a ramp.
	local base, continent, hill, rangeBias, mountainAmp = 0, 0, 0, 0, 0
	local sharpness, roughness, cliff = 0, 0, 0
	local river, lake, landmark, aridity = 0, 0, 0, 0

	for i = 1, biomeCount do
		local weight = blendWeight[i]
		if weight > 0 then
			base += biomeBase[i] * weight
			continent += biomeContinent[i] * weight
			hill += biomeHill[i] * weight
			rangeBias += biomeRangeBias[i] * weight
			mountainAmp += biomeMountain[i] * weight
			sharpness += biomeSharpness[i] * weight
			roughness += biomeRoughness[i] * weight
			cliff += biomeCliff[i] * weight
			river += biomeRiver[i] * weight
			lake += biomeLake[i] * weight
			landmark += biomeLandmark[i] * weight
			aridity += biomeAridity[i] * weight

		end
	end

	--[[
		Water is faded out of the spawn area along with everything else the
		guarantee suppresses.

		It is applied to the AFFINITY rather than to the finished column, so the
		channel is never carved in the first place - suppressing the water alone
		would leave the starting area criss-crossed by dry gullies. It also
		keeps the spawn platform from ever landing in a lake.

		Affinity covers the water that is CUT or DUG. The sea is a separate
		question, because it stands wherever the ground is under the table
		whether or not anything dug it, and that is what profile.waterAllowed
		turns off - as a floor under the GROUND rather than a veto on the
		water, since a veto is a hard threshold and drew the ocean's edge as a
		visible circle at the radius where it lapsed. See Landform.compose.
	]]
	local dryness = 1 - influence

	local profile = Landform.Profile
	profile.waterAllowed = dryness
	profile.baseHeight = base
	profile.continentAmplitude = continent
	profile.hillAmplitude = hill
	profile.rangeBias = rangeBias
	profile.mountainAmplitude = mountainAmp
	profile.ridgeSharpness = sharpness
	profile.roughness = roughness
	profile.cliffStrength = cliff
	profile.riverAffinity = river * dryness
	profile.lakeAffinity = lake * dryness
	-- Landmarks are faded out of the starting area too: a crater or a great peak
	-- centred on spawn would decide the first thing every player ever sees.
	profile.landmarkAffinity = landmark * dryness
	profile.aridity = aridity

	--[[
		The starting area is pulled toward NEUTRAL ELEVATION as well as toward
		the spawn biome.

		The continent term now subtracts height as well as adding it, so on a
		seed whose continental lowland happens to lie under the origin the
		ground there is below the water table and the game opens with the
		player in a sea. Easing the field toward LandformConfig.ContinentPivot
		puts spawn on ground at the blended baseHeight - comfortably dry - and
		because `influence` is already a smoothstep out to SpawnSafeRadiusBlocks
		it costs one lerp and leaves no seam.

		Applied to the FIELD rather than to the finished height on purpose: the
		river reference, the drainage bias and the mountain lift are all read
		off the same number, so they stay consistent with the ground instead of
		being corrected separately.
	]]
	local continentHere = continentValue
	if influence > 0 then
		continentHere += (CONTINENT_PIVOT - continentHere) * influence
	end

	local detail = Landform.detail(bx, bz)
	local height, waterTop, mountainTerm, shoreLevel = Landform.compose(
		bx, bz,
		continentHere, rangeValue, ridgeValue, hillValue, riverValue, basinValue,
		detail,
		edgeFactor(bx, bz)
	)

	local under = biomeUnder[dominant]
	local top
	if waterTop > 0 then
		local cold = biomeTemp[dominant] < 0.35 or height >= biomeSnowLine[dominant]
		top = if cold then ROCK_BLOCK
			else if waterTop - height <= SHORE_HEIGHT then SHORE_BLOCK else under
	else
		top = surfaceBlock(dominant, height, mountainTerm, mountainAmp, detail, shoreLevel)
	end
	return height,
		biomeNames[dominant],
		top,
		under,
		variantAt(dominant, variantValue, bx, bz),
		waterTop
end

function BiomeMap.getStats()
	local regions = 0
	for _ in pairs(regionBiome) do
		regions += 1
	end

	local provinces = 0
	for _ in pairs(provinceBiome) do
		provinces += 1
	end

	local landform = Landform.getStats()

	return {
		seed = activeSeed,
		biomeCount = biomeCount,
		latticePoints = latticeCount + oldLatticeCount,
		latticeYoung = latticeCount,
		latticeOld = oldLatticeCount,
		regionCells = regions,
		provinceCells = provinces,

		-- Lake cells resolved so far, and how many of them hold water. A
		-- session that has walked a long way and found no lakes is a bug
		-- report, and this is where it shows.
		lakeCells = landform.lakeCells,
		lakeKinds = landform.lakeKinds,
	}
end

return BiomeMap
