--[[
	BiomeConfig

	Which biomes exist, how large they are, how common they are, which ones are
	not allowed to touch - and what shape the ground takes in each.

	HOW BIOME SELECTION WORKS

	The world is divided into REGIONS on a jittered grid, and each region draws
	one biome by weighted lottery. A column blends the region sites nearest it.
	Three numbers, doing three separate jobs:

	  RegionCellBlocks  how big a territory is        - the same for every biome
	  regionWeight      how often a biome is drawn    - per biome, rarity only
	  temperature       where in the world it may be  - per biome, placement only
	  humidity            drawn, via two slow climate fields

	Those used to be one number. See the REGIONS section below for why that
	could not express "rare, but large when you find it", which is the whole
	point of the rework.

	ADDING A BIOME
	  1. Add an entry to Definitions.
	  2. Add its name to Order.
	  3. Give it a climate claim that is not already crowded, and a regionWeight.
	The generator has no per-biome branches.

	UNITS
	  temperature / humidity : 0..1 climate-space coordinates
	  every height, amplitude and line : blocks
]]

-- Only for validate(), which checks each biome's base height against the water
-- table. LandformConfig depends on TerrainConfig and nothing else, so this
-- cannot cycle.
local TerrainFolder = script.Parent
local LandformConfig = require(TerrainFolder:WaitForChild("LandformConfig"))

local BiomeConfig = {}

-- ===========================================================================
-- REGIONS  (how big a biome is, and how often it turns up)
-- ===========================================================================

--[[
	THE TWO NUMBERS THAT USED TO BE ONE

	Biomes used to be chosen by nearest-claim in climate space. Under that
	scheme a biome's territory was its share of the climate square, which set
	how OFTEN you met it and how BIG it was with a single number - so "rare"
	could only ever mean "small". Rare biomes came out as slivers, which is
	exactly the wrong shape: the one you seldom find is the one that most needs
	to be worth the walk.

	So selection is now REGION-BASED, on two grids:

	  province  a coarse grid; each province draws one dominant biome
	  region    a finer grid inside it; each cell draws a biome too, but
	            heavily biased toward its province's, so cells CLUSTER into
	            large contiguous territories with ragged edges rather than
	            speckling

	A column takes the nearest region sites around it and blends them. Size is
	RegionCellBlocks and clustering is ProvinceBias - the same for every biome.
	Rarity is `regionWeight`, one number per biome, and it changes nothing about
	size. Climate has not gone away, but its job is now placement only: it
	decides WHERE a biome may be drawn (snow country is cold, desert is dry),
	never how much of the world it gets.

	Measured over eight worlds: every biome present in all eight, typical region
	3,800-6,500 studs and up to 11,000, and not one rare biome with a measurable
	share of its area in fragments under 600 studs.
]]

-- THE "how big is a biome" dial. One region cell is the smallest a territory
-- can be; neighbouring cells that draw the same biome merge into one.
BiomeConfig.RegionCellBlocks = 560

--[[
	The coarse grid, and how hard a cell is pulled toward its province.

	Without this every cell is an independent draw and the map is a mosaic of
	single cells - correct in share, wrong in shape. At bias 12 a province's own
	biome takes most of its cells, so territories come out several cells across
	with the odd intrusion at the edges, which is what makes a border look
	geological rather than tiled.

	Keep the province a small multiple of the cell (2-3x). Much larger and the
	world has too few provinces for every biome to get one; much smaller and the
	clustering has nothing to cluster.
]]
BiomeConfig.ProvinceCellBlocks = 1400
BiomeConfig.ProvinceBias = 12

--[[
	How far a region's site may sit from the centre of its cell, as a fraction.

	This is a CORRECTNESS bound, not a style knob. A column only tests the 3x3
	cells around it, so no site outside that window may ever be close enough to
	deserve weight. Past about 0.15 at this blend width one can be, and the
	result is a seam along the cell grid - see validate(). Regularity is hidden
	by the domain warp below, which displaces the whole lookup by hundreds of
	blocks, not by the jitter.
]]
BiomeConfig.RegionJitter = 0.15

--[[
	How wide a border is, in BLOCKS - which is the unit it should always have
	been in. A column's weight for a region falls off over this much extra
	distance, so the graded band is about half of it either side: 200 gives
	roughly 400 studs of transition, over which all twelve terrain numbers
	cross-fade. That is what turns the approach to the snow country into
	foothills instead of a wall.
]]
BiomeConfig.RegionBlendBlocks = 200

--[[
	How fussy a cell is about matching a biome's climate claim, in climate-space
	units. Small values pin every biome to its own corner of the world and make
	the map predictable; large values scatter snow next to desert.

	0.38 is a little wider than the gap between neighbouring claims, so a cell
	usually draws something that suits it while leaving room for a rare biome to
	win somewhere merely plausible.
]]
BiomeConfig.ClimateAffinity = 0.38

-- ===========================================================================
-- CLIMATE FIELD  (where a biome may be drawn)
-- ===========================================================================

--[[
	Blocks per climate feature.

	This no longer sizes anything - regions do that - so it is free to be large:
	it now only has to vary slowly enough that neighbouring provinces have
	similar climate, which is what keeps the cold country in one part of the
	world instead of scattering snow regions at random.

	Sampled at region and province SITES only, not per column and not on the
	lattice, so it costs two Perlin calls per cell - a few hundred for a whole
	session - rather than two per lattice point.
]]
BiomeConfig.ClimateScaleBlocks = 1500

--[[
	ONE octave.

	It matters less than it did - a wobble in the climate field can no longer
	flip a border back and forth, because climate does not draw borders any more,
	it only decides what a region is allowed to be. But a second octave would
	still let two neighbouring cells of one province disagree about their climate
	and draw different biomes, which is speckle by another route.
]]
BiomeConfig.ClimateOctaves = 1
BiomeConfig.ClimatePersistence = 0.5

--[[
	Domain warp, at two scales, doing two different jobs.

	CONTINENTAL warp displaces the REGION lookup by hundreds of blocks over a
	distance of hundreds more. That is what turns a grid of cells into long,
	interlocking, organic territories - the difference between a Voronoi diagram
	and a map. It is also the only thing hiding the grid, since RegionJitter is
	held small for correctness, so do not weaken it.

	BORDER warp is small and fast: a couple of dozen blocks of displacement at a
	150-block scale. It only ever roughens the last hundred studs of an edge,
	which is what makes a coastline look bitten rather than drawn. It is far too
	fine to move a border anywhere, so it cannot reintroduce patchiness.

	Both are kept in proportion to ClimateScaleBlocks - the continental warp at
	roughly 1.35x its scale and a third of it in strength. Scaled any other way
	the warp either stops bending the regions at all (too weak) or folds them
	back on themselves and shreds the thing the larger scale just bought.
]]
BiomeConfig.ClimateWarpScaleBlocks = 2025
BiomeConfig.ClimateWarpStrengthBlocks = 495

BiomeConfig.BorderWarpScaleBlocks = 150
BiomeConfig.BorderWarpStrengthBlocks = 22

--[[
	fbm output clusters around the middle of its range. Contrast stretches it
	toward the extremes so the hot and cold ends of climate space are actually
	reached, and clamping at the ends turns the tails into plateaus - which is
	what lets Desert and Snow form big solid regions instead of thin slivers.

	It no longer has to carry the weight it used to. A claim out on a joint tail
	(Desert is hot AND dry) is reached by only a percent or two of the world
	however hard this stretches, and that used to make such a biome rare by
	accident. BiomeMap now divides each biome's climate fit by its own average
	over the world, so an awkwardly-placed claim costs a biome nothing in share
	- only in where it is allowed to appear.
]]
BiomeConfig.ClimateContrast = 1.75

-- Shifts the whole world. Negative temperature = colder world = more snow.
BiomeConfig.TemperatureBias = -0.02
BiomeConfig.HumidityBias = 0.0

-- Climate eligibility is a hard boundary on the regional lottery. Rarity
-- calibration must never turn a warm region into snow country or vice versa.
BiomeConfig.SnowMaxTemperature = 0.42
BiomeConfig.DesertMinTemperature = 0.60
BiomeConfig.ClimateEligibilityFeather = 0.12

--[[
	CLIMATE FOLLOWS THE GROUND

	Temperature and humidity were two noise fields with no idea what the land
	under them was doing, so where a biome went and what shape the ground there
	was were independent rolls. That is the difference between a world and a
	pair of overlays: snow country turned up on the coastal plain as often as
	on the high ground, deserts appeared in basins, and swamps on plateaus.

	Both are corrected by the CONTINENT field, which is the one part of the
	geography that exists before any biome is chosen - so this costs one extra
	noise sample per region site, a few hundred for a whole session, and no
	per-column work at all.

	  LAPSE     high ground is colder. At 0.34 the highest continental ground
	            is about 0.18 of climate space colder than the lowest, which is
	            a quarter of the spread between the hottest and coldest claims -
	            enough to bias where the cold biomes land without overriding
	            the climate field and reducing the map to a height chart.

	            It is also half of why the snow country is mountainous.
	            LandformConfig.MountainContinentLift already makes a range on
	            high ground a bigger range; this is what puts Snow on the high
	            ground for it to act on.

	  LOWLAND   low ground is wetter, being nearer the sea and the water table.
	            Milder, because the geography is weaker: a plateau can perfectly
	            well be wet.

	Both are folded into calibrateClimateFit as well as into the draw, so a
	biome's share of the world is unchanged by them - only where it sits.
]]
BiomeConfig.TemperatureLapseRate = 0.34
BiomeConfig.HumidityLowlandBias = 0.13

-- ===========================================================================
-- TRANSITIONS  (how borders look)
-- ===========================================================================

--[[
	Border width lives in RegionBlendBlocks now, up in the REGIONS section,
	because it is a distance on the ground rather than a distance in climate
	space. What it does is unchanged and is still the thing that makes a
	transition GEOGRAPHICAL rather than a line: every terrain number below is
	cross-faded across it, so walking toward the cold country the mountain
	amplitude climbs gradually - rolling hills, rough ground, foothills,
	mountains - without a line of code describing that progression.

	There is no BlendCount any more either. A column sees exactly the nine
	region cells around it and every one of them contributes whatever the
	falloff gives it, which is nothing for most.
]]

-- ===========================================================================
-- VARIANTS  (sub-biomes: forests within a biome)
-- ===========================================================================
--
-- A biome may be divided into large sub-regions that share its terrain and
-- blocks but differ in what grows on them. Plains uses this to separate oak
-- woodland, birch woodland and open grassland.
--
-- Rolling a species per TREE mixes everything everywhere, which is what makes a
-- mixed stand read as noise rather than as a forest. A variant is decided by a
-- low-frequency field instead, so a whole hillside agrees on what it is.
--
-- Variants are OPTIONAL. A biome with no `variants` reports none.

-- Blocks per variant region. THE dial for "how big is a forest".
-- Scaled up with the biomes: a 165-block wood inside a 4,000-stud biome region
-- reads as scattered stands rather than as forest and open country.
BiomeConfig.VariantScaleBlocks = 260

-- Two octaves keeps regions blobby without fragmenting them. Raising this
-- shreds forests into patches, which is the thing variants exist to avoid.
BiomeConfig.VariantOctaves = 2
BiomeConfig.VariantPersistence = 0.45

-- Roughens the border between two variants, as a fraction of the field, so the
-- treeline is ragged at tree scale. 0 disables it.
BiomeConfig.VariantEdgeJitter = 0.04

-- ===========================================================================
-- DANGER  (how far from spawn a biome starts appearing)
-- ===========================================================================
--
-- Each biome carries a `danger` from 0 to 1: how far from the origin its
-- territories start appearing. It does not change what the biome IS.
--
-- IT IS NOW EVALUATED PER REGION, AT THE REGION'S OWN SITE, and it scales that
-- biome's ticket in the cell's lottery. So a dangerous biome is either drawn
-- for a territory or it is not - and if it is, the territory is full size.
--
-- That is the whole difference from before. The old gate multiplied a
-- per-column distance, so a half-available biome did not appear half as often,
-- it appeared as half-sized fragments squeezed between its neighbours. At
-- 1,200 blocks out - about where ten minutes of walking gets you - Crimson and
-- Corruption sat at 0.13 availability, which inflated their reported distance
-- by 2.8x and made them essentially unwinnable anywhere a player would go.
-- Measured over sixty ten-minute walks, Crimson turned up in 13 of them and
-- Corruption in 12, and never as anything but a sliver.
--
--   onset = d * DangerOnsetBlocks              first territories
--   full  = onset + DangerRampBase + d * DangerRampBlocks
--
-- danger = 0 is exempt and drawn everywhere, which is what makes Plains the
-- fabric of the world rather than merely the most common thing in it.
--
-- A danger-0.40 biome now has its first territories from ~360 blocks and full
-- share past ~890 - inside a single session's walk, where before the equivalent
-- ramp did not finish until 2,100.

BiomeConfig.DangerOnsetBlocks = 900
BiomeConfig.DangerRampBase = 250
BiomeConfig.DangerRampBlocks = 700

-- ===========================================================================
-- BIOME DEFINITIONS
-- ===========================================================================
--
-- IDENTITY
--  regionWeight     RARITY, and nothing else: this biome's share of the tickets
--                   in every region lottery it is eligible for. Independent of
--                   how large a region is, which is BiomeConfig.RegionCellBlocks
--                   and the same for everything
--  temperature      climate claim - WHERE in the world this biome is drawn, not
--  humidity         how much of it there is. BiomeMap normalises each claim by
--                   its own average fit, so a claim out on a joint tail costs
--                   share nothing
--  topBlock         block name for the exposed surface layer
--  underBlock       block name for everything beneath it
--  structureDensity global multiplier on structures rolled in this biome
--  danger           0 to 1; see above
--  variants         optional sub-regions
--
-- TERRAIN PROFILE
--  Every one of these is blended with the neighbouring biomes over
--  RegionBlendBlocks, and every one scales a field shared by the whole world (see
--  Landform). A biome never gets terrain of its own - it decides how much of
--  the world's terrain shows through here, which is why a mountain range
--  crosses a border and fades instead of stopping at it.
--
--  baseHeight         the height this biome sits at where the continent is
--                     NEUTRAL - i.e. at LandformConfig.ContinentPivot, not its
--                     floor. Ground goes below it in continental lowland
--  continentAmplitude how far the slowest field moves it, up AND down. Large
--                     values make a biome's own upland and lowland far apart;
--                     large enough and its lowland goes under the water table,
--                     which is where that biome's seas and lakes come from
--  hillAmplitude      rolling relief, and the layer that decides whether the
--                     country between the ranges reads as landscape. CENTRED:
--                     the term is (hills - 0.5) * this, so it digs as far as
--                     it lifts and baseHeight is the height the ground
--                     actually averages
--  rangeBias          shifts this biome along the mountain-belt ramp. The belt
--                     FIELD is shared world-wide - a range crosses a border
--                     and tapers - but a biome may meet the gate sooner or
--                     later than its neighbour, so an alpine biome gets more
--                     of the same ranges instead of a private mountain field
--                     that would stop dead at its border
--  mountainAmplitude  how much of the ridged mountain field shows. THE dial
--                     that separates a plain from an alpine range
--  ridgeSharpness     exponent on the ridge. Low is broad and massive, high is
--                     narrow and spiky
--  roughness          per-block jitter
--  cliffStrength      0..1, how much the mountain term is terraced into ledges
--                     and cliffs rather than smooth slope
--  riverAffinity      multiplier on river width here. 0 is a biome with none
--  lakeAffinity       multiplier on standing water
--  landmarkAffinity   multiplier on rare large features
--  aridity            0..1. Gates the landmarks that only belong in dry country
--  snowLine           height above which the surface goes white regardless of
--                     biome. Set it above MaxHeight for a biome that never
--                     snows; it blends, so a Plains/Snow border gets a snow
--                     line halfway between the two
--
-- Block names must exist in ReplicatedStorage.TerrainAssets.Blocks (the
-- generator falls back and warns if one is missing).

--[[
	WHERE THE CLAIMS SIT

	The six other biomes are arranged as a RING around Plains in climate space,
	which is not decoration: the only biomes that can ever meet are neighbours
	on that ring, so every border in the world is one somebody chose. Going
	round: Desert (hot, dry) - Crimson (hot) - Swamp (hot, wet) - Hallow (wet) -
	Corruption (cold, wet) - Snow (cold) - back to Desert.

	It is also what let the buffer strips shrink. Hallow and Corruption used to
	sit 0.22 apart with identical humidity and needed a 0.38 band of Plains
	shoved between them; on the ring they are 0.36 apart and 0.18 does it. Those
	bands were eating a large part of the territory of exactly the biomes that
	were hardest to find.
]]
BiomeConfig.Definitions = {
	--[[
		Home. Rolling hills, a little of everything, and the only biome
		available at every distance from spawn.
	]]
	Plains = {
		regionWeight = 1.55,
		temperature = 0.50,
		humidity = 0.48,
		topBlock = "Grass",
		underBlock = "Dirt",
		structureDensity = 1.0,
		danger = 0.00,

		--[[
			The height the ground AVERAGES, not its floor.

			That changed with the hill term: hills are centred now, so they dig
			as far as they lift and this sits in the middle of them rather than
			underneath. Every baseHeight in this file went up by about half its
			biome's new hill amplitude for exactly that reason - to leave the
			ground the same distance above the water it was before, while the
			relief around it roughly tripled.

			It is also what the river network is measured down from: the
			reference is baseHeight - hillAmplitude/2, so a river runs at the
			floor of the rolling country rather than through the middle of it.
			See LandformConfig's header.
		]]
		baseHeight = 56,
		-- Wide, and it cuts both ways: Plains has real high country and real
		-- lowland, and where the lowland goes under SeaLevel it is where the
		-- inland seas and the big river systems are. Widened with the rest of
		-- the vertical budget, since a taller world with the same continental
		-- range is a world where the macro shape matters less.
		continentAmplitude = 70,
		-- The layer that decides whether the country between the ranges is
		-- landscape or a table. At 9, with the old three-octave hill field,
		-- 84% of Plains had one block or less of relief across a 32-stud
		-- window - measurably flat, not merely gentle. Centred now (see
		-- Landform), so this digs hollows as well as raising rises, which is
		-- also where a good share of the new lakes end up sitting.
		hillAmplitude = 26,
		-- Small but not zero. It buys the grassland some SHAPED relief - low
		-- ridges that run somewhere - which the hill field cannot give it,
		-- being made of blobs. At mountainAmplitude 14 that is rising ground
		-- and a skyline, not mountains.
		rangeBias = 0.05,
		-- Small but NOT zero. A range running out of the mountains has to have
		-- somewhere to die away, and this is the tail of it: low ridges and
		-- rising ground on the approach to the cold country. Kept under
		-- LandformConfig.RockMinMountainAmplitude so grass stays grass.
		mountainAmplitude = 14,
		ridgeSharpness = 1.75,
		roughness = 1.2,
		cliffStrength = 0.0,
		riverAffinity = 1.15,
		lakeAffinity = 1.15,
		landmarkAffinity = 1.0,
		aridity = 0.10,
		snowLine = 170,

		--[[
			Oak woodland, birch woodland, and open ground between them.

			Open is weighted heaviest on purpose. Continuous forest leaves
			nowhere to build and nothing to look across; the clearings are what
			make the woods read as woods. Its structureDensity is not zero
			either - a handful of lone trees on open grass looks intentional,
			whereas a bare field beside a dense wood looks like the generator
			stopped.
		]]
		variants = {
			{ name = "OakForest", weight = 1.0, structureDensity = 1.35 },
			{ name = "BirchForest", weight = 0.85, structureDensity = 1.25 },
			{ name = "Open", weight = 1.5, structureDensity = 0.06 },
		},
	},

	--[[
		Wet, low and flat, and the one biome defined by its water rather than
		its ground. Nearly no relief at all, a heavy lake affinity and wide
		rivers, so it comes out as a maze of shallow water and low islands.

		It shares Plains' blocks. That is a known compromise: the geometry and
		the water are what identify it, not the palette. A dedicated mud or
		marsh-grass block would be one line here and one asset.
	]]
	Swamp = {
		regionWeight = 0.95,
		temperature = 0.72,
		humidity = 0.86,
		topBlock = "Grass",
		underBlock = "Dirt",
		structureDensity = 0.55,
		danger = 0.10,

		-- Low base, narrow continental range: the swamp barely rises above the
		-- water table anywhere, which is what floods it. It does not need a
		-- huge lakeAffinity to do that any more - it needs to be LOW, and being
		-- low is now sufficient on its own.
		baseHeight = 43,
		continentAmplitude = 30,
		hillAmplitude = 8,
		-- Pushed the other way: a swamp is the one place flat is the point.
		rangeBias = -0.06,
		mountainAmplitude = 0,
		ridgeSharpness = 2.0,
		roughness = 0.7,
		cliffStrength = 0.0,
		riverAffinity = 1.60,
		lakeAffinity = 2.20,
		landmarkAffinity = 0.35,
		aridity = 0.0,
		snowLine = 260,
	},

	--[[
		Dunes, and the mesas that stand out of them. High roughness at low
		amplitude gives the rippled sand; the cliff terracing plus a strong
		landmark affinity gives the flat-topped rock.
	]]
	Desert = {
		regionWeight = 1.15,
		temperature = 0.82,
		humidity = 0.20,
		topBlock = "Sand",
		underBlock = "Sandstone",
		structureDensity = 0.22,
		danger = 0.12,

		baseHeight = 53,
		continentAmplitude = 58,
		hillAmplitude = 30,
		-- Dunes, so this is where nearly all the deserts relief comes from.
		rangeBias = -0.02,
		-- Held just under LandformConfig.RockMinMountainAmplitude on purpose:
		-- a desert butte should be sandstone, and going over that line would
		-- put grey mountain stone in the dunes.
		mountainAmplitude = 20,
		-- Narrow and spiky, so what mountain there is comes out as isolated
		-- buttes rather than as an alpine ridge.
		ridgeSharpness = 2.4,
		-- The dunes. Desert takes almost all of its relief from the hill and
		-- detail fields - its ridgeSharpness is high enough that the mountain
		-- term is nearly always nothing - so this is the layer that ripples it.
		roughness = 2.0,
		cliffStrength = 0.60,
		-- Rivers here are the exception that proves the rule: a thin ribbon of
		-- green in the sand, and nothing else. Standing water is a different
		-- matter - where the desert's own lowland drops under the table it is a
		-- salt flat or an oasis, and that is geography, not affinity.
		riverAffinity = 0.35,
		lakeAffinity = 0.35,
		landmarkAffinity = 1.30,
		aridity = 1.0,
		snowLine = 260,
	},

	--[[
		The mountains.

		Everything about where a range RUNS - the ridgelines, the valleys
		between them, where the foothills start - comes from the shared ridged
		field, so the same range continues out of this biome and dies away in
		whatever it borders. What Snow contributes is amplitude, and it now has
		FIVE things working together rather than one:

		  continentAmplitude 82   the biome's own high country and low country,
		                          two Perlin scales up from the ranges. This is
		                          what makes crossing the biome a journey rather
		                          than a traverse of one massif
		  hillAmplitude 34        rolling relief under all of it, over four
		                          octaves, so even the ground between two ranges
		                          is landscape rather than a shelf
		  rangeBias 0.13          more of the shared belt reaches this biome, so
		                          less of it comes out as plain
		  mountainAmplitude 96    the ranges themselves, on top of all that
		  MountainContinentLift   in LandformConfig, which multiplies the last
		                          by the first - so ranges in the high country
		                          are half again the size of the same range down
		                          on the biome's coastal edge

		  TemperatureLapseRate    and the reason the high country is where Snow
		                          lands in the first place. High ground is cold,
		                          so the cold biome is drawn onto high ground,
		                          so the lift above has something to lift.

		THE COMPLAINT THIS ANSWERS was that snow biomes generate flat. Measured
		before: the mountain term had a MEDIAN of 4.3 blocks - half of the snow
		country had no mountain in it at all - and 48% of the biome had one
		block or less of relief across a 32-stud window. After: the mountain
		term's median is 24, the height median is 84 against a 90th percentile
		of 139 and a 99th of 183, and 24% of it is flat. What did most of that
		is rangeBias and the lapse rate, not the amplitudes: the ranges were
		always this big, they were simply not being let in.
	]]
	Snow = {
		regionWeight = 1.35,
		temperature = 0.14,
		humidity = 0.42,
		topBlock = "Snow",
		underBlock = "Dirt",
		structureDensity = 0.40,
		danger = 0.10,

		baseHeight = 63,
		continentAmplitude = 82,
		hillAmplitude = 34,
		-- THE FIX FOR FLAT SNOW, together with BiomeConfig.TemperatureLapseRate.
		-- The range belt is shut over 28% of the map, and a biome that draws
		-- its whole identity from mountains cannot afford to spend a quarter of
		-- itself as plain. This shifts Snow along the same shared ramp so it
		-- meets the gate sooner than the grassland it borders - the ranges are
		-- still the world ranges, still crossing the border and tapering, there
		-- is simply more of them here.
		rangeBias = 0.13,
		mountainAmplitude = 96,
		-- Low, so the massifs are broad and heavy rather than a field of
		-- spikes. Broad is what reads as a mountain from a distance.
		ridgeSharpness = 1.12,
		roughness = 1.2,
		-- The terracing is what turns a steep slope into ledges and drops, and
		-- it is where the genuinely impassable ground comes from.
		cliffStrength = 0.50,
		-- Meltwater. Worth having now that the flanks sit below
		-- RiverMaxLandHeight and a channel can actually start up there.
		riverAffinity = 0.95,
		lakeAffinity = 0.95,
		landmarkAffinity = 1.50,
		aridity = 0.20,
		-- Above the valley floors, so the low ground reads as snowfield and
		-- the ridges above it as bare rock and ice rather than uniform white.
		snowLine = 78,
	},

	-- Bright, strange, and moderately mountainous: tall narrow spires on
	-- otherwise gentle ground.
	Hallow = {
		regionWeight = 0.90,
		temperature = 0.50,
		humidity = 0.86,
		topBlock = "HallowedDirt",
		underBlock = "HallowedStone",
		structureDensity = 0.40,
		danger = 0.35,

		baseHeight = 56,
		continentAmplitude = 68,
		hillAmplitude = 27,
		rangeBias = 0.05,
		mountainAmplitude = 46,
		ridgeSharpness = 1.95,
		roughness = 1.3,
		cliffStrength = 0.25,
		riverAffinity = 1.05,
		lakeAffinity = 1.10,
		landmarkAffinity = 1.20,
		aridity = 0.20,
		snowLine = 168,
	},

	--[[
		Jagged and aggressive. The high roughness is what makes it feel organic
		and unpleasant underfoot; the low ridge exponent widens the mountain
		term into broken uneven massifs rather than clean peaks, and the cliff
		terracing cuts ravines into them.
	]]
	Crimson = {
		-- Twice the climate territory it had. At the old 0.40 it was winning a
		-- sliver even where it was available, and the sliver was then split
		-- again by the buffer strips against Hallow.
		regionWeight = 0.95,
		temperature = 0.84,
		humidity = 0.62,
		topBlock = "CrimsonDirt",
		underBlock = "CrimsonStone",
		structureDensity = 0.28,
		danger = 0.40,

		baseHeight = 56,
		continentAmplitude = 64,
		hillAmplitude = 31,
		rangeBias = 0.05,
		mountainAmplitude = 58,
		ridgeSharpness = 1.15,
		roughness = 2.3,
		cliffStrength = 0.45,
		riverAffinity = 0.80,
		lakeAffinity = 0.85,
		landmarkAffinity = 1.10,
		aridity = 0.30,
		snowLine = 178,
	},

	--[[
		Crimson's twin, a shade colder and a shade more broken.

		This is the biome the region rework was aimed at, and the numbers are
		the clearest statement of what it did. Before: 3.9% of the world, the
		typical region 1,000 studs across, 12% of its area in fragments under
		600 studs, and found in 12 of 60 ten-minute walks. After: 9.2%, typical
		region 4,000 studs and up to 6,900, nothing at all in fragments, found
		in 15 of the same 60 walks.

		Note which number did NOT have to go up much. Its share barely more than
		doubled; what changed is that the share now arrives as whole territories
		instead of as slivers, because size stopped being a function of rarity.
	]]
	Corruption = {
		regionWeight = 1.05,
		temperature = 0.22,
		humidity = 0.76,
		topBlock = "CorruptedDirt",
		underBlock = "CorruptedStone",
		structureDensity = 0.28,
		danger = 0.40,

		baseHeight = 56,
		continentAmplitude = 64,
		hillAmplitude = 31,
		rangeBias = 0.06,
		mountainAmplitude = 58,
		ridgeSharpness = 1.15,
		roughness = 2.3,
		cliffStrength = 0.50,
		riverAffinity = 0.75,
		lakeAffinity = 0.85,
		landmarkAffinity = 1.10,
		aridity = 0.35,
		snowLine = 178,
	},
}

-- Iteration order. Deterministic ordering matters for tie-breaking.
BiomeConfig.Order = { "Plains", "Swamp", "Desert", "Snow", "Hallow", "Crimson", "Corruption" }

-- Used when a lookup somehow fails, and as the default transition buffer.
BiomeConfig.Fallback = "Plains"

-- ===========================================================================
-- COMPATIBILITY  (which biomes may not touch)
-- ===========================================================================
--
-- Whenever an incompatible pair turns up among the nearest biomes at a
-- position, the `via` biome is faded in across their border, producing a real
-- strip of neutral terrain instead of an abrupt seam.
--
--   a, b : the pair that must not touch (order does not matter)
--   via  : biome inserted between them. Must exist and differ from a and b.
--   band : how wide the strip is, as a fraction of the climate-space gap.
--          Pairs whose claims sit close together need a wider band.
--
-- To forbid another pairing later, add one row.

--
-- Every band here is narrower than it was, because the claims themselves moved
-- apart (see the ring, above). A buffer band is territory taken away from both
-- biomes it separates, so a wide one used to compensate for crowded claims is
-- paid for twice - and it was being paid by the rarest biomes on the map.
BiomeConfig.Incompatible = {
	-- The only pair on the ring that is genuinely adjacent and must not touch:
	-- sand meeting snowfield with nothing in between.
	{ a = "Desert", b = "Snow", via = "Plains", band = 0.22 },

	-- Hallow's neighbours around the ring.
	{ a = "Hallow", b = "Corruption", via = "Plains", band = 0.18 },
	{ a = "Hallow", b = "Crimson", via = "Plains", band = 0.16 },

	-- Not adjacent on the ring, so these almost never fire. Kept because a
	-- later change to a claim could make them adjacent again, and a rule that
	-- costs nothing while it is unreachable is cheaper than the bug.
	{ a = "Desert", b = "Corruption", via = "Plains", band = 0.16 },
	{ a = "Desert", b = "Swamp", via = "Plains", band = 0.16 },
}

-- How hard the `via` biome asserts itself at the exact border. Above 1.0 it
-- reliably wins the surface block there, which is what makes the buffer strip
-- visible rather than merely nudging the blend.
BiomeConfig.BufferStrength = 1.7

--[[
	Every terrain-profile field, with the default used when a biome omits it.
	Read by BiomeMap when it flattens the definitions into arrays, and by
	validate below, so a new knob is added in exactly one place.
]]
BiomeConfig.TerrainDefaults = {
	-- baseHeight is the height at LandformConfig.ContinentPivot, so it has to
	-- clear LandformConfig.SeaLevel by a comfortable margin or a biome that
	-- omits it comes out permanently flooded. validate() checks this.
	baseHeight = 54,
	continentAmplitude = 62,
	hillAmplitude = 22,
	rangeBias = 0.0,
	mountainAmplitude = 6,
	ridgeSharpness = 1.6,
	roughness = 1.0,
	cliffStrength = 0.0,
	riverAffinity = 1.0,
	lakeAffinity = 1.0,
	landmarkAffinity = 1.0,
	aridity = 0.0,
	snowLine = 200,
}

--[[
	Structural sanity check. Runs at require time.
]]
function BiomeConfig.validate()
	assert(BiomeConfig.SnowMaxTemperature < BiomeConfig.DesertMinTemperature,
		"[BiomeConfig] Snow and desert need a temperate climate gap")
	assert(BiomeConfig.ClimateEligibilityFeather > 0,
		"[BiomeConfig] ClimateEligibilityFeather must be positive")
	assert(#BiomeConfig.Order > 0, "[BiomeConfig] Order is empty")

	--[[
		THE 3x3 WINDOW BOUND.

		A column only looks at the nine region cells around it. That is sound
		only while every cell outside the window is provably too far to earn any
		weight; otherwise a cell contributes nothing right up to the moment it
		enters the window and then jumps in at full strength, and the map grows
		a seam along every cell boundary.

		Worst case inside the window is a site in the column's own cell at the
		far corner of its jitter box: sqrt(2) * (0.5 + jitter) cells away.
		Nearest possible site outside it is (1.5 - jitter) cells away. The gap
		between those, in blocks, is all the blend width there is to spend.
	]]
	local jitter = BiomeConfig.RegionJitter
	assert(
		jitter >= 0 and jitter < 0.5,
		"[BiomeConfig] RegionJitter is a fraction of a cell and must be under 0.5"
	)

	local nearestOutside = (1.5 - jitter) * BiomeConfig.RegionCellBlocks
	local furthestInside = math.sqrt(2) * (0.5 + jitter) * BiomeConfig.RegionCellBlocks
	local room = nearestOutside - furthestInside
	assert(
		BiomeConfig.RegionBlendBlocks < room,
		string.format(
			"[BiomeConfig] RegionBlendBlocks (%d) must stay under %.0f at RegionCellBlocks %d "
				.. "and RegionJitter %.2f, or a region cell outside the 3x3 window a column "
				.. "tests can still deserve weight and the biome map seams along the grid. "
				.. "Lower the blend, lower the jitter, or raise the cell size.",
			BiomeConfig.RegionBlendBlocks, room, BiomeConfig.RegionCellBlocks, jitter
		)
	)

	assert(
		BiomeConfig.ProvinceCellBlocks > BiomeConfig.RegionCellBlocks,
		"[BiomeConfig] ProvinceCellBlocks must exceed RegionCellBlocks, or the coarse grid "
			.. "has nothing to cluster"
	)
	assert(
		BiomeConfig.ProvinceBias >= 0,
		"[BiomeConfig] ProvinceBias must not be negative"
	)
	assert(
		BiomeConfig.ClimateAffinity > 0,
		"[BiomeConfig] ClimateAffinity must be positive"
	)

	for _, name in ipairs(BiomeConfig.Order) do
		local def = BiomeConfig.Definitions[name]
		assert(def, string.format("[BiomeConfig] '%s' is in Order but has no definition", name))
		assert(
			type(def.regionWeight) == "number" and def.regionWeight > 0,
			string.format(
				"[BiomeConfig] '%s' needs a positive regionWeight. (This replaced "
					.. "`frequency`, which conflated rarity with region size.)",
				name
			)
		)
		assert(
			type(def.temperature) == "number" and type(def.humidity) == "number",
			string.format("[BiomeConfig] '%s' needs a temperature and humidity claim", name)
		)
		assert(
			type(def.topBlock) == "string" and type(def.underBlock) == "string",
			string.format("[BiomeConfig] '%s' needs topBlock and underBlock names", name)
		)
		assert(
			def.danger == nil
				or (type(def.danger) == "number" and def.danger >= 0 and def.danger <= 1),
			string.format("[BiomeConfig] '%s' danger must be a number between 0 and 1", name)
		)

		-- Every terrain knob has to be a number if it is present at all. A typo
		-- would otherwise fall back to the default silently and the biome would
		-- simply come out flat, which is a hard thing to notice from the ground.
		for field in pairs(BiomeConfig.TerrainDefaults) do
			assert(
				def[field] == nil or type(def[field]) == "number",
				string.format("[BiomeConfig] '%s' %s must be a number", name, field)
			)
		end

		local sharpness = def.ridgeSharpness
		assert(
			sharpness == nil or sharpness > 0,
			string.format("[BiomeConfig] '%s' ridgeSharpness must be positive", name)
		)

		local cliff = def.cliffStrength
		assert(
			cliff == nil or (cliff >= 0 and cliff <= 1),
			string.format("[BiomeConfig] '%s' cliffStrength must be a fraction", name)
		)

		--[[
			Where this biome's RIVERS sit against the sea.

			Checked against the reference rather than against baseHeight, which
			is no longer the number that matters: the hill term is centred, so
			the ground digs half an amplitude below its base, and it is that
			floor - baseHeight - hillAmplitude/2 - that every water level in the
			biome is measured down from. A biome whose reference sits at the sea
			has its whole river network clamped to sea level and comes out as
			flooded gullies rather than as valleys.

			Raising hillAmplitude without raising baseHeight with it is the easy
			way to do this by accident, which is exactly why it is checked.

			A warning, not an assert: a deliberately drowned biome is a
			reasonable thing to want, and Swamp is deliberately close to it.
		]]
		local defaults = BiomeConfig.TerrainDefaults
		local base = def.baseHeight or defaults.baseHeight
		local hill = def.hillAmplitude or defaults.hillAmplitude
		local reference = base - hill * 0.5

		if reference <= LandformConfig.SeaLevel + 2 then
			warn(string.format(
				"[BiomeConfig] '%s' has baseHeight %d and hillAmplitude %d, so its reference "
					.. "surface sits at %d - at or under the water table (SeaLevel %d). Its "
					.. "rivers will all clamp to sea level and most of it will generate "
					.. "flooded. Raise baseHeight by about half of any rise in hillAmplitude.",
				name, base, hill, reference, LandformConfig.SeaLevel
			))
		end

		if def.variants ~= nil then
			assert(
				type(def.variants) == "table" and #def.variants > 0,
				string.format("[BiomeConfig] '%s' variants must be a non-empty array", name)
			)

			local seenVariant = {}
			for index, variant in ipairs(def.variants) do
				local label = string.format("[BiomeConfig] '%s' variants[%d]", name, index)

				assert(
					type(variant.name) == "string" and variant.name ~= "",
					label .. " needs a name"
				)
				assert(not seenVariant[variant.name], label .. " reuses the name " .. variant.name)
				seenVariant[variant.name] = true

				assert(
					type(variant.weight) == "number" and variant.weight > 0,
					label .. " needs a positive weight"
				)
				assert(
					variant.structureDensity == nil
						or (type(variant.structureDensity) == "number" and variant.structureDensity >= 0),
					label .. " structureDensity must be a non-negative number"
				)
			end
		end
	end

	assert(
		BiomeConfig.Definitions[BiomeConfig.Fallback].danger == nil
			or BiomeConfig.Definitions[BiomeConfig.Fallback].danger == 0,
		"[BiomeConfig] the Fallback biome must have danger 0, or there would be places "
			.. "where nothing at all is available"
	)

	for name in pairs(BiomeConfig.Definitions) do
		if not table.find(BiomeConfig.Order, name) then
			warn(string.format(
				"[BiomeConfig] '%s' is defined but missing from Order, so it will never generate.",
				name
			))
		end
	end

	assert(
		BiomeConfig.Definitions[BiomeConfig.Fallback],
		"[BiomeConfig] Fallback names a biome that does not exist"
	)

	for index, rule in ipairs(BiomeConfig.Incompatible) do
		local label = string.format("[BiomeConfig] Incompatible[%d]", index)
		assert(BiomeConfig.Definitions[rule.a], label .. ": unknown biome " .. tostring(rule.a))
		assert(BiomeConfig.Definitions[rule.b], label .. ": unknown biome " .. tostring(rule.b))
		assert(rule.a ~= rule.b, label .. ": a and b are the same biome")

		local via = rule.via or BiomeConfig.Fallback
		assert(BiomeConfig.Definitions[via], label .. ": unknown via biome " .. tostring(via))
		assert(
			via ~= rule.a and via ~= rule.b,
			label .. ": via must differ from both a and b, otherwise it cannot separate them"
		)
	end
end

return BiomeConfig
