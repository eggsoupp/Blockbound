--[[
	LandformConfig

	The shape of the world, as opposed to what it is made of.

	  LandformConfig  continents, mountain ranges, rivers, lakes, landmarks
	  BiomeConfig     which biome sits where, and how much of each of the above
	                  it takes (see the TERRAIN PROFILE section there)
	  TerrainConfig   world size, chunking, streaming, budgets
	  StrataConfig    what is under the surface
	  OreConfig       which of that is ore

	THE IDEA

	Every one of these is a single WORLD-WIDE field. A biome never gets its own
	landform - it only decides how much of the shared one shows through. That is
	what makes a mountain range cross a biome border and taper off instead of
	stopping dead at it, and it is why adding a biome costs no generation time.

	The stack, coarse to fine:

	  continent   where the land is high or low at all, thousands of studs wide
	  ranges      where mountains are ALLOWED, so ranges cluster into belts with
	              genuinely flat country between them
	  ridges      the mountains themselves - ridged noise, so peaks connect into
	              lines with valleys between rather than scattering as bumps
	  hills       rolling relief, everywhere, over four octaves
	  detail      per-block roughness
	  rivers      ridged noise again, whose creases are river lines
	  basins      broad hollows, where whole districts sit below their
	              surroundings
	  lakes       discrete standing water on a jittered cell grid, each one with
	              its own flat surface at its own altitude
	  landmarks   rare, hand-shaped features on a sparse cell grid

	All of it is a pure function of (blockX, blockZ) and the world seed, which
	is what lets BiomeMap cache it on a lattice and lets any column be sampled
	on its own without generating its neighbours.

	SCALES ARE IN BLOCKS. One block is TerrainConfig.StudSize studs, and a
	scale is roughly the width of one feature. Divide the world span by a scale
	to see how many of that feature fit across the map - and keep every one of
	them well under 256, or Perlin's period repeats the map (NoiseField
	explains this, and validate() below checks it).

	THE REFERENCE SURFACE, WHICH IS WHAT MAKES WATER WORK

	Half the numbers here only make sense against one idea. There is a
	REFERENCE height:

	    reference = baseHeight - hillAmplitude/2
	              + (continent - Pivot) * continentAmplitude
	              - whatever the basin field and a hollow landmark dug out

	which is the ground with everything that can only ADD height taken back off
	- hills, mountains, the positive half of a landmark, the per-block jitter.
	It is therefore a LOWER BOUND on the terrain, and it is a smooth one,
	falling exactly as the continent falls.

	Every moving water level in the world is derived from it, and that is the
	single invariant this file exists to protect: a river surface set at
	`reference - freeboard` is BELOW THE GROUND EVERYWHERE by construction,
	so a channel cannot end up running along a ridge and water cannot end up
	standing higher than the dry ground beside it.

	Break the invariant - add a term that subtracts height without subtracting
	it from the reference too - and the symptom is not subtle: rivers come out
	as raised troughs with levees, standing above the land they cross.
]]

local TerrainFolder = script.Parent
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))

local LandformConfig = {}

-- ===========================================================================
-- CONTINENTS
-- ===========================================================================
-- The slowest field there is: which whole regions are upland and which are
-- lowland. Everything else rides on top of it, so this is what stops the world
-- being uniformly busy - it gives large calm areas and large high areas.

LandformConfig.ContinentScaleBlocks = 980
LandformConfig.ContinentOctaves = 2
LandformConfig.ContinentPersistence = 0.5

--[[
	Stretches the field toward its extremes so upland and lowland are decisive
	rather than everything hovering near the middle. Clamped at the ends, which
	turns the tails into plateaus - big coherent high country and big basins.
	See NoiseField:shaped for why a raw fbm needs this before anything is
	thresholded against it.

	This and BasinDepthBlocks are the two dials for HOW MUCH SEA there is, and
	they are the right two: both of them lower the reference along with the
	ground, so the rivers descend into what they open up instead of hanging
	over it. Lowering a biome's baseHeight would flood the same ground and
	take the river network down with it - past the point where the reference
	clears the sea, every river in the biome clamps to sea level and the
	valleys come out as flooded gullies rather than as valleys.
]]
LandformConfig.ContinentContrast = 2.35

--[[
	The continent value that counts as "neither up nor down".

	This is the single most important number for where water is. The continent
	term is (continent - Pivot) * the biome's continentAmplitude, so below the
	pivot the field SUBTRACTS height - there is genuine lowland, not merely
	less upland.

	Without it the term was continent * amplitude, which is never negative: the
	lowest ground anywhere was the biome's own baseHeight, every biome floated
	above the water table, and the only water that could exist was whatever a
	basin managed to dig back down to it. Measured on the old numbers, 0.82% of
	the map could hold a lake AT ALL, at any depth.

	0.46, just under the middle, so a little over half the world is upland. The
	continental lowlands that fall under SeaLevel become the inland seas, and
	they are why water turns up at the macro scale wherever you explore rather
	than only where a basin happens to be gated open.
]]
LandformConfig.ContinentPivot = 0.46

-- ===========================================================================
-- MOUNTAIN RANGES
-- ===========================================================================

--[[
	Where mountains are allowed at all.

	Without this, ridged noise puts mountains everywhere at some amplitude and
	the whole world reads as corrugated. Gating it behind a slower field means
	ranges gather into belts, with real plains between them, and a player can
	be somewhere that is simply not mountainous.
]]
LandformConfig.RangeScaleBlocks = 640
LandformConfig.RangeOctaves = 2
LandformConfig.RangePersistence = 0.5

--[[
	Stretch, for the reason in NoiseField:shaped, and it is not optional here.

	Raw, this field measured [0.23, 0.78] with a 99th percentile of 0.710 -
	so a belt that only reached full strength at 0.72 was never once fully
	open anywhere in the world. The median belt was 0.21, which meant every
	biome, however alpine its mountainAmplitude said it was, was getting about
	a fifth of the mountain it had asked for. That was the whole reason the
	snow country came out as hills.

	Shaped at 2.10 the belt is now shut over 28% of the map, fully open over
	13%, and graded across the rest: real ranges, real plains, real foothills
	on the approach.
]]
LandformConfig.RangeContrast = 2.10

-- Below Threshold there are no mountains; over the next Feather the belt fades
-- in. A wide feather is what produces foothills on the approach to a range.
--
-- A biome may shift its own position along this ramp with `rangeBias` (see
-- BiomeConfig). The FIELD is still shared - a range crossing out of the snow
-- keeps running - but the cold country meets the gate sooner, so it gets more
-- of the belt than the grassland it borders. That is what stops half of a
-- mountain biome coming out as flat country, without giving it a private
-- mountain field that would stop at its border.
LandformConfig.RangeThreshold = 0.40
LandformConfig.RangeFeather = 0.34

--[[
	The ranges themselves. Ridged, so peaks connect into lines.

	The base scale is one range's width; the octaves subdivide it down to
	individual peaks. With 4 octaves at lacunarity 2.1 the finest detail lands
	around 300 / 2.1^3 = 32 blocks, or roughly 130 studs - small enough to read
	as a distinct summit from inside the streaming radius.
]]
LandformConfig.MountainScaleBlocks = 300
LandformConfig.MountainOctaves = 4
LandformConfig.MountainPersistence = 0.52
LandformConfig.MountainLacunarity = 2.1

-- How strongly a high coarse octave lets finer ones through: crisp, rocky
-- summits and smooth valley floors. See NoiseField:ridged.
LandformConfig.MountainGain = 2.1

--[[
	How much the CONTINENT scales the mountains standing on it.

	A range in high country should be a bigger range than the same range out on
	the coastal plain - that is what makes a cordillera read as one landform
	rather than as an even corrugation everywhere the belt happens to be open.

	The mountain amplitude is multiplied by (1 + this * (continent - Pivot)),
	so at 0.9 a range on the highest ground is about 1.4x the one at the pivot
	and a range in the lowlands about 0.6x. Free: both numbers are already
	sampled, so this adds one multiply per column and no noise at all.

	It also gives the graded approach the eye needs - crossing from lowland to
	upland the same range grows as you walk into it, instead of switching on.

	It pairs with BiomeConfig.TemperatureLapseRate, which puts the cold biomes
	on the high ground in the first place: the two together are why snow
	country is mountainous rather than merely white.
]]
LandformConfig.MountainContinentLift = 0.90

-- ===========================================================================
-- HILLS AND DETAIL
-- ===========================================================================

--[[
	Rolling relief, and the layer that decides whether the world reads as
	landscape or as a table with features on it.

	IT IS CENTRED. The term is (hills - 0.5) * hillAmplitude, so it digs as far
	as it lifts and `baseHeight` means the height the ground actually averages
	rather than its floor. The reference surface subtracts the same half
	amplitude, which keeps the water invariant at the top of this file intact.

	FOUR OCTAVES, AND WHY THE SCALE WENT UP TO GET THEM. Measured on the old
	three octaves from 190 blocks, 66% of the world had one block or less of
	relief across a 32-stud window and Plains had a median of one - the ground
	between the mountains was, quite literally, a table. The finest octave
	there landed at 47 blocks with 14% of the amplitude, which is nothing you
	can stand on.

	The fix is a fourth octave and a flatter persistence, and the scale has to
	rise to pay for it: the finest octave is what reaches furthest across
	Perlin's period (see validate below), and 4 octaves from 190 would span
	259 units and tile the map. From 260 the octaves land at 260 / 130 / 65 /
	32 blocks and the reach is 190, comfortably inside.
]]
LandformConfig.HillScaleBlocks = 260
LandformConfig.HillOctaves = 4
LandformConfig.HillPersistence = 0.60
LandformConfig.HillLacunarity = 2.0

-- Stretched like the other fields, for the same reason: four-octave fbm sits
-- in an even tighter bell than two, so without this a biome asking for 26
-- blocks of relief would see about half of it and the hilltops and hollows
-- would both be soft. Kept mild - past about 1.5 the tails clamp and hills
-- come out as plateaus with steep sides.
LandformConfig.HillContrast = 1.40

-- 26 rather than a rounder number for one reason: at this world span it is the
-- coarsest value that still fits inside Perlin's 256-unit period, so even the
-- per-block jitter never repeats across the map.
LandformConfig.DetailScaleBlocks = 26

-- ===========================================================================
-- RIVERS
-- ===========================================================================

--[[
	Rivers are the creases of a ridged field, for the same reason mountains are
	its peaks: a zero crossing is a continuous curve, so the channels come out
	connected and branching rather than as disconnected puddles.

	WHY THEY RUN DOWNHILL

	A noise field knows nothing about gradient, so the river is not routed down
	the terrain - the terrain is cut down to the river. The channel is carved to
	sit just below the REFERENCE described at the top of this file, and the two
	properties that follow are the whole design:

	  The reference is a lower bound on the ground, so the channel is genuinely
	  below its own banks and a river cannot end up running along a ridge.

	  The reference falls exactly as the continent falls, so the river descends
	  from upland to lowland without ever needing to be routed, and it stays a
	  constant shallow depth the whole way instead of cutting a canyon wherever
	  the ground happens to be high.

	WATER LEVEL IS NOT THE SAME QUESTION AS RIVER LEVEL

	A river's surface follows that reference downhill. A LAKE cannot: a level
	that changes across its own width is a sloping sheet of water, which is the
	one thing standing water must never be. So a lake gets ONE number for its
	whole body - see the LAKES section - and a river running into one is graded
	onto that number over the lake's own extent, which is what an estuary is.

	Do not try to unify these two rules. They answer different questions and
	the difference is physical, not a tidiness problem.
]]
LandformConfig.RiverScaleBlocks = 520
LandformConfig.RiverOctaves = 2
LandformConfig.RiverPersistence = 0.45
LandformConfig.RiverLacunarity = 2.0
LandformConfig.RiverGain = 1.7

--[[
	How much of the ridged field counts as river.

	This is the dial for "how many waterways". Small is important: the field is
	near 1 only right along a crease, so 0.085 already gives a network you meet
	every few hundred studs, and doubling it turns the map into marsh.

	Width is a fraction of the field, not a distance in blocks, so a river is
	naturally wider where the field is flatter - which is the lowlands.

	The old 0.045 / 0.11 was written as though the ridged field were uniform.
	It is not: it is near 1 only in a hair-thin band along each crease, and a
	SECOND octave has to be near its own crease at the same place for the sum
	to clear the threshold. So the channels came out as disconnected beads
	rather than as rivers - 0.87% of columns, nearly all of it in Swamp, and
	1.06% of the map wide enough to hold a channel in upland at all. These
	measured 4.2% overall, with rivers that actually connect.
]]
LandformConfig.RiverWidthHigh = 0.115 -- in upland, where rivers are young
LandformConfig.RiverWidthLow = 0.20 -- in lowland, where they have gathered

--[[
	The banks are graded over this much more of the field than the water itself,
	which is what gives a river a flood plain instead of a slot cut in the
	ground. Terrain inside it is pulled toward the water level.

	DOWN FROM 0.28, and that was the second-largest cause of the world being
	flat. Three multipliers stack here: 0.28 x a 1.15 affinity x a 1.9 drainage
	bias reached 0.61, and a bank width of 0.61 means every column whose river
	field clears 0.39 - most of the map - is being dragged toward the water
	table. Flood plains are supposed to be the exception, not the fabric.

	Not as far down as it first went, though. At 0.19 the plains stopped being
	flattened and the rivers went with them: the channel is cut relative to the
	reference, which now sits half a hill amplitude below the ground, so
	without a graded flood plain to meet it halfway a river only holds water
	along its exact centre line and comes out as a chain of beads.
]]
LandformConfig.RiverBankWidth = 0.24

--[[
	How much harder the network runs downhill.

	Width is multiplied by (1 + this * (Pivot - continent)), so channels widen
	and multiply as the land falls away and thin to headwaters on high ground.
	That is the drainage: without it the river field is a decoration laid over
	the terrain with no idea where the terrain goes, and rivers are as likely
	on a plateau as in a valley.

	Cheap for the same reason MountainContinentLift is - the continent is
	already sampled, so this is a multiply. It composes with the width
	interpolation above rather than replacing it: that one sets how BROAD a
	given river is, this one sets how MANY there are.
]]
LandformConfig.RiverDrainageBias = 0.90

-- How far a river's surface sits below the reference. Small, because the
-- reference is already the ground with its relief removed. The biome's own
-- roughness is subtracted on top of this inside Landform, since that is the
-- one term that can push the ground BELOW the reference.
LandformConfig.RiverFreeboardBlocks = 3

-- How far the bed sits under the water surface, at the head and at the mouth.
LandformConfig.RiverDepthHigh = 3
LandformConfig.RiverDepthLow = 7

--[[
	The one flat water table for the SEA: the inland seas that fill the
	continental lowlands, and the ocean around the edge of the world.

	Everything below this holds water. With a bipolar continent (see
	ContinentPivot) that is what distributes water at the macro scale: the
	continental lowlands are under the table, so they are inland seas, and
	every biome that crosses one meets water without anything having to place
	it there.

	It is NOT what puts lakes on high ground - a single global level cannot,
	since almost nowhere upland is under it. That is the LAKES section below,
	and the two are deliberately separate mechanisms answering "where is the
	ocean" and "where is standing water" as the different questions they are.
]]
LandformConfig.SeaLevel = 34

-- Rivers give up above this height, so a range's summit is not perforated by
-- channels. Below it they cut hard, which is what makes a gorge where a river
-- crosses high ground.
--
-- Raised with the mountains: at 132 the fade started below the height a snow
-- range now spends most of its area at, so the whole flank was dry and the
-- rivers coming down out of the mountains had nowhere to start.
LandformConfig.RiverMaxLandHeight = 178
LandformConfig.RiverFadeBlocks = 46

-- ===========================================================================
-- BASINS
-- ===========================================================================

--[[
	Broad hollows: whole districts that sit below their surroundings.

	This is a CONTINENTAL-scale term, not a lake maker. What it does is give
	the macro map somewhere for water to gather that the continent field alone
	did not put there, so the inland seas are not simply "wherever the
	continent is lowest" and the coastline has more to say.

	It is subtracted from the REFERENCE as well as from the ground, which is
	the fix for the raised-river artifact: dug out of the ground alone, a basin
	pulled the land 19 blocks below a river surface that had no idea it had
	happened, and the river came out standing on a levee above the hollow it
	crossed. Now both fall together and the river runs down into the basin, as
	a river does.

	Discrete standing water is the LAKES section below.
]]
LandformConfig.BasinScaleBlocks = 700
LandformConfig.BasinOctaves = 2
LandformConfig.BasinPersistence = 0.5

-- Shaped like the range belt, and for the same reason. See NoiseField:shaped.
LandformConfig.BasinContrast = 1.90

LandformConfig.BasinThreshold = 0.52
LandformConfig.BasinFeather = 0.18

-- How deep a basin digs itself, at full strength. Deep, because this is now
-- the main thing putting ground under the sea that the continent field did not
-- already put there - and because it is subtracted from the reference too,
-- depth here costs no artifacts, only coastline.
LandformConfig.BasinDepthBlocks = 28

--[[
	The deepest water rendered anywhere. Water is drawn as a surface plus its
	edge wall (see TerrainManager), so this bounds what a shoreline column
	costs, not what a lake looks like from above.

	It is also why the lake depths below can be as large as they are for free.
	A bed dug thirty blocks under the surface is raised back to nine before
	anything is drawn, so the depth is not buying deep water - it is buying
	WIDTH, because the waterline is wherever the bowl brings the ground under
	the surface and a deeper target reaches it further out.
]]
LandformConfig.MaxWaterDepth = 9

-- ===========================================================================
-- LAKES
-- ===========================================================================

--[[
	Discrete standing water, at whatever altitude the ground happens to be.

	WHY THIS IS A CELL GRID AND NOT A NOISE FIELD

	Standing water has one property no noise field can give it: its surface is
	FLAT. Not smooth, not slowly varying - one number over the whole body, or
	the water visibly runs downhill. A field-based lake is a level that changes
	across its own width, and every attempt to hide that ends up either
	terracing the surface or letting it stand above the ground beside it.

	So a lake is an OBJECT. The world is divided into cells; each cell hashes
	to a yes/no, a kind, a jittered site and an ellipse. The lake's surface is
	a single integer worked out once for that cell, and every column inside it
	reads the same number. Perfectly level, by construction, for free.

	The old system had no such object. It dug hollows with the basin field and
	then asked whether the result happened to fall under the single global
	SeaLevel - which upland, where most of the world is, it essentially never
	did. Measured over 250,000 columns: NINE bodies of standing water enclosed
	inside a sample patch, five of them under 40 blocks of surface. That is why
	lakes were impossible to find.

	HOW THE LEVEL IS CHOSEN, AND WHY IT CANNOT FLOOD

	The level is the REFERENCE (top of this file) probed around the lake's own
	RIM, taking the MINIMUM, minus LakeFreeboardBlocks.

	The rim is the only place this has to hold, and that is the whole safety
	argument. Water appears where the bowl has dug the ground below the
	surface; at the rim the bowl digs nothing; so a surface under the untouched
	ground THERE is a surface the lake cannot spill over. The interior is free
	to dip lower - that only makes the lake deeper. What comes out is a
	shoreline that is wherever the digging stops rather than a hard edge where
	the disc runs out, and no column with water standing above dry ground
	beside it.

	AND THE SIZE IS FITTED TO THE GROUND. A rim on a slope hands the lake a
	surface far below its own middle, and that is not a lower lake - it is a
	lake that should have been smaller. Landform tries each size in turn and
	keeps the largest whose rim is level enough to hold water, so a lake in a
	hollow gets its full extent and one on a slope shrinks to the basin it is
	actually in.

	Three more things fade rather than gate, for the usual reason - a hard test
	on a smooth field draws a line on the ground:

	  the biome's lakeAffinity at the SITE scales the chance, so a swamp is
	  riddled with water and a desert is not, and a lake that crosses a biome
	  border is not carved into crescents;

	  the range belt at the site refuses the heart of a mountain range, which
	  leaves tarns on the flanks where they belong;

	  the bowl itself fades out against ground that rises too far above the
	  surface, so a lake landing on a hillside stops at the slope instead of
	  quarrying into it.

	The probes cost one biome blend each, worked out once per cell and
	memoised. A session visits a few hundred cells.

	MEASURED, over 605,000 columns and eight seeds: 231 lakes across the world
	against 60 under the first version of this and none at all before it; 65
	enclosed bodies in the sample patches, spread 21 puddles / 10 ponds / 23
	small / 8 lakes / 3 large; 1.5% of the world in lake, 3.9% in river, 8.2%
	in sea; and 0.01% of wet columns standing above dry ground, down from
	0.41%.
]]

--[[
	THE dial for how much lake there is. One cell holds at most one lake, so
	this is also roughly how far apart two lakes are.

	180 blocks is 720 studs, and at that spacing a walk in any direction meets
	water every minute or two. It was 300 first, which put sixty lakes in the
	whole world - one per 3,200 studs of travel - and a body of water you meet
	once every ten minutes is a landmark, not geography.

	Small cells are what let this be dense without every lake being the same
	size: the kinds below still range from a 26-block pond to a 130-block lake,
	and neighbouring cells that both draw large ones merge into something
	larger still.
]]
LandformConfig.LakeCellBlocks = 180

-- Fraction of cells hosting a lake, before the biome's lakeAffinity at the
-- site scales it. Above 1 after that multiply simply means "always", which is
-- what Swamp gets. Roughly a third of cells are refused anyway - by the range
-- ceiling and by the sea margin below - so this is not the share that ends up
-- with water in it.
LandformConfig.LakeChance = 1.00

-- How far a lake's site may sit from the centre of its cell, as a fraction.
-- Large on purpose: it is what stops a 300-block grid being readable as a
-- grid. validate() below bounds it against the reach of the biggest lake.
LandformConfig.LakeJitter = 0.40

--[[
	How far the surface sits below the lowest reference in the lake's disc.

	Small. It is not setting the depth - LakeKinds does that by digging the bed
	down from the surface - it is only the margin that keeps the level under
	the untouched ground, and the only thing it has to clear is the per-block
	roughness, which is the one term that can put the ground below the
	reference at all.
]]
LandformConfig.LakeFreeboardBlocks = 3

--[[
	A lake needs its surface this far above the sea before it is allowed to
	exist, so that a second, higher water level cannot end up standing against
	the ocean with nothing between them.

	SMALL, and the reason is that the rim probe has already done most of this
	job. A lake's surface is the minimum reference around its own rim less the
	freeboard, so the untouched ground at the rim is at least
	`level + freeboard - roughness` - about three blocks up. Ask only that the
	level clears the sea by two and the rim is provably dry ground, which is
	all that was ever needed: past the rim the ground goes on falling and meets
	the sea wherever it does, with a dry shore in between.

	It was 6 first, on no reasoning beyond caution, and it was the single
	largest reason lakes were rare - it refused 44% of otherwise valid cells,
	nearly all of them in ordinary country where the reference merely dipped
	below neutral. Half the world has no business being lakeless.
]]
LandformConfig.LakeSeaMarginBlocks = 1

-- No lakes in the heart of a mountain range: the belt at the site has to be
-- less open than this. Flanks and foothills still get them, which is where
-- tarns belong.
LandformConfig.LakeRangeCeiling = 0.85

--[[
	How far the ground may stand above a lake before the lake gives up on it.

	This is what stops a bowl gouging into a hillside, and it replaced a hard
	cap on the DIG, which did the opposite of what it looked like: a cap stops
	digging while the bowl is still asking for more, so the hole arrives exactly
	as deep as the cap and still short of the water line. Six of every fourteen
	lakes came out completely dry that way.

	Full strength up to Tolerance above the surface, gone by another Fade past
	it. Tolerance is roughly a biome hill amplitude, since that is what the
	ground inside a lake's own footprint actually does.
]]
LandformConfig.LakeRiseToleranceBlocks = 24
LandformConfig.LakeRiseFadeBlocks = 16

--[[
	The sizes, and the mix between them.

	  weight   relative share of lakes that are this kind
	  radius   blocks, the mean semi-axis of the ellipse
	  depth    blocks the bed is dug below the surface at the centre
	  shore    fraction of the radius spent sloping up to the rim. Small is a
	           steep-sided lake with a broad flat bottom; large is a saucer
	  stretch  how eccentric the ellipse may get, 0 for a circle. Area is
	           preserved, so this changes the shape and not the size

	The shoreline itself is not any of these. It is wherever the dug bed
	crosses the flat surface, and the bed carries the terrain's own noise, so
	the outline comes out organic however round the ellipse underneath is.
]]
LandformConfig.LakeKinds = {
	{ name = "Pond", weight = 2.6, radius = 26, depth = 8, shore = 0.45, stretch = 0.35 },
	{ name = "Tarn", weight = 2.2, radius = 52, depth = 14, shore = 0.38, stretch = 0.40 },
	{ name = "Lake", weight = 1.3, radius = 95, depth = 20, shore = 0.32, stretch = 0.42 },
	{ name = "Great", weight = 0.45, radius = 130, depth = 26, shore = 0.28, stretch = 0.45 },
}

-- ===========================================================================
-- LANDMARKS
-- ===========================================================================

--[[
	Rare, large, deliberately shaped features.

	The world is divided into square cells. Each hashes to a yes/no, a position
	inside itself, and a type - so a landmark is a pure function of position
	like everything else here, needs no registry, and cannot be duplicated
	across a chunk border. A column tests the nine cells around it, and the
	usual answer after one hash is "nothing here".

	Radius must stay under half the cell so a column can never be reached by a
	cell further away than its immediate neighbours.

	  weight       relative share of landmarks that are this kind
	  radius       blocks of influence
	  lift         blocks added at the centre (negative digs)
	  flatten      0..1, how strongly the top is levelled - what makes a mesa a
	               mesa rather than a dome
	  rimLift      blocks added in a ring at the edge, for crater walls
	  needsRange   only appears where the mountain belt is already open
	  needsArid    only appears in dry country (mesas)
	  needsLow     only appears in lowland

	SUITABILITY IS TESTED AT THE LANDMARK'S OWN CENTRE, not per column. Tested
	per column it is a hard threshold on a smooth field running straight
	through the middle of the feature, so a great peak whose cell straddles the
	edge of a range belt came out sliced in half down a line.
]]
LandformConfig.LandmarkCellBlocks = 620
LandformConfig.LandmarkChance = 0.20

LandformConfig.Landmarks = {
	{
		-- The one you can see from the next biome. Rare even among landmarks.
		name = "GreatPeak",
		weight = 0.9,
		radius = 190,
		lift = 78,
		flatten = 0,
		rimLift = 0,
		needsRange = true,
	},
	{
		name = "Crater",
		weight = 1.0,
		radius = 150,
		lift = -34,
		flatten = 0.45,
		rimLift = 16,
	},
	{
		name = "Mesa",
		weight = 1.1,
		radius = 165,
		lift = 40,
		flatten = 0.88,
		rimLift = 0,
		needsArid = true,
	},
	{
		name = "Basin",
		weight = 1.2,
		radius = 240,
		lift = -26,
		flatten = 0.6,
		rimLift = 0,
		needsLow = true,
	},
	{
		name = "Bluff",
		weight = 1.4,
		radius = 130,
		lift = 30,
		flatten = 0.7,
		rimLift = 0,
	},
}

-- ===========================================================================
-- SURFACE BY ALTITUDE
-- ===========================================================================

--[[
	Height and exposure change the surface block, on top of whatever the biome
	nominated.

	This is what turns a biome border into a landscape. Walking from grassland
	up into the cold country you cross grass, then bare rock where the ridges
	break through, then snow above the snow line - and none of it needed a
	biome of its own, because all three are the same biome at three heights.

	The snow line is per biome (BiomeConfig.snowLine) so the cold end of the
	world is white almost to its feet and the desert never is.
]]
LandformConfig.RockBlock = "Stone"
LandformConfig.SnowBlock = "Snow"

-- Standing water. TerrainManager draws it as its own band above the ground,
-- and BlockConfig.Surfaces is what makes it see-through and non-solid.
LandformConfig.WaterBlock = "Water"

-- How much bare ridge has to be showing before the surface goes to rock.
LandformConfig.RockRidgeThreshold = 0.52

-- ...and how mountainous the biome has to be for that to apply at all. Without
-- it the same ridge field speckles grassland with stone wherever it crests.
-- Plains (14) and Desert (20) are below it, so grass stays grass and the dunes
-- stay sand; Hallow (46), the evil biomes (58) and Snow (104) are above.
LandformConfig.RockMinMountainAmplitude = 24

-- Rock also appears on anything this high regardless of ridge, so the shoulders
-- of a big landmark peak are stone rather than grass.
--
-- Moved up with the ceiling and the base heights, which between them raised
-- the whole world by about fifteen blocks. Left at 118 it would have started
-- greying over ordinary upland that used to be well under it.
LandformConfig.RockHeight = 132

-- Continuous contour variation, sampled from the existing detail field.
-- This bends the snow/rock line without scattering individual surface blocks.
LandformConfig.SurfaceContourVariationBlocks = 3

-- Sand on warm coasts and desert banks. Cold shores use stone/snow and inland
-- temperate banks keep their turf; BiomeMap resolves the climate policy.
LandformConfig.ShoreBlock = "Sand"
LandformConfig.ShoreHeightBlocks = 2

function LandformConfig.validate()
	local span = TerrainConfig.WorldRadiusBlocks * 2

	local scales = {
		ContinentScaleBlocks = { LandformConfig.ContinentScaleBlocks, LandformConfig.ContinentOctaves, 2 },
		RangeScaleBlocks = { LandformConfig.RangeScaleBlocks, LandformConfig.RangeOctaves, 2 },
		MountainScaleBlocks = {
			LandformConfig.MountainScaleBlocks,
			LandformConfig.MountainOctaves,
			LandformConfig.MountainLacunarity,
		},
		RiverScaleBlocks = {
			LandformConfig.RiverScaleBlocks,
			LandformConfig.RiverOctaves,
			LandformConfig.RiverLacunarity,
		},
		BasinScaleBlocks = { LandformConfig.BasinScaleBlocks, LandformConfig.BasinOctaves, 2 },
		HillScaleBlocks = {
			LandformConfig.HillScaleBlocks,
			LandformConfig.HillOctaves,
			LandformConfig.HillLacunarity,
		},
	}

	for name, entry in pairs(scales) do
		local scale, octaves, lacunarity = entry[1], entry[2], entry[3]
		assert(
			type(scale) == "number" and scale > 0,
			string.format("[LandformConfig] %s must be positive", name)
		)

		-- The finest octave is what reaches furthest across Perlin's period.
		local reach = (span / scale) * lacunarity ^ (octaves - 1)
		if reach > 200 then
			warn(string.format(
				"[LandformConfig] %s = %d spans %.0f Perlin units at its finest octave. Past "
					.. "256 the field repeats across the world; raise the scale, drop an "
					.. "octave, or shrink TerrainConfig.GridChunksX/Z.",
				name, scale, reach
			))
		end
	end

	assert(
		LandformConfig.RiverWidthLow > LandformConfig.RiverWidthHigh,
		"[LandformConfig] rivers must widen downstream: RiverWidthLow > RiverWidthHigh"
	)
	assert(
		LandformConfig.RiverBankWidth >= LandformConfig.RiverWidthLow,
		"[LandformConfig] RiverBankWidth must be at least RiverWidthLow, or the banks would "
			.. "be narrower than the water they grade down to"
	)
	assert(
		LandformConfig.RiverDepthLow >= LandformConfig.RiverDepthHigh,
		"[LandformConfig] rivers must deepen downstream: RiverDepthLow >= RiverDepthHigh"
	)
	assert(
		LandformConfig.SeaLevel > TerrainConfig.MinHeight,
		"[LandformConfig] SeaLevel must sit above MinHeight, or there is nowhere for a lake "
			.. "bed to be dug and every one bottoms out at the floor of the world"
	)
	assert(
		LandformConfig.SeaLevel < TerrainConfig.MaxHeight,
		"[LandformConfig] SeaLevel must sit below MaxHeight"
	)
	assert(
		LandformConfig.MaxWaterDepth > 0,
		"[LandformConfig] MaxWaterDepth must be positive"
	)

	assert(
		LandformConfig.ContinentPivot > 0 and LandformConfig.ContinentPivot < 1,
		"[LandformConfig] ContinentPivot must sit strictly inside the field's 0..1 range, "
			.. "or the continent term is one-sided again and there is no lowland"
	)

	--[[
		A threshold on a field that has been stretched has to stay inside what
		the stretch can actually reach, or the gate is shut everywhere - which
		is exactly the failure that made the mountain belt and the lake basins
		inert. A shaped field reaches roughly 0.5 +/- 0.5 * contrast * amplitude,
		and two-octave fbm peaks around 0.42 of full amplitude, so this is the
		furthest a gate can be asked to open.
	]]
	local function checkGate(name, threshold, feather, contrast)
		local reach = 0.5 + 0.5 * contrast * 0.42
		if threshold + feather > reach then
			warn(string.format(
				"[LandformConfig] %s reaches %.2f but the field shaped at contrast %.2f only "
					.. "gets to about %.2f, so the gate never opens fully. Lower the threshold, "
					.. "narrow the feather, or raise the contrast.",
				name, threshold + feather, contrast, reach
			))
		end
	end

	checkGate(
		"RangeThreshold + RangeFeather",
		LandformConfig.RangeThreshold, LandformConfig.RangeFeather, LandformConfig.RangeContrast
	)
	checkGate(
		"BasinThreshold + BasinFeather",
		LandformConfig.BasinThreshold, LandformConfig.BasinFeather, LandformConfig.BasinContrast
	)

	local half = LandformConfig.LandmarkCellBlocks * 0.5
	local total = 0
	for index, mark in ipairs(LandformConfig.Landmarks) do
		local label = string.format("[LandformConfig] Landmarks[%d]", index)
		assert(type(mark.name) == "string" and mark.name ~= "", label .. " needs a name")
		assert(
			type(mark.weight) == "number" and mark.weight > 0,
			label .. " needs a positive weight"
		)
		assert(
			type(mark.radius) == "number" and mark.radius > 0 and mark.radius < half,
			string.format(
				"%s radius must be positive and under half of LandmarkCellBlocks (%d), or a "
					.. "column could be inside a landmark it never tests for",
				label, half
			)
		)
		total += mark.weight
	end
	assert(total > 0, "[LandformConfig] Landmarks needs at least one entry")

	assert(
		LandformConfig.LandmarkChance >= 0 and LandformConfig.LandmarkChance <= 1,
		"[LandformConfig] LandmarkChance must be a fraction"
	)

	--[[
		THE 3x3 WINDOW BOUND, for lakes.

		A column tests the nine lake cells around it. A cell two away sits at
		least (1.5 - jitter) cells off, so nothing further than that may ever
		reach the column - and the furthest a lake reaches is its long
		semi-axis, which `stretch` extends past the nominal radius.
	]]
	local jitter = LandformConfig.LakeJitter
	assert(
		jitter >= 0 and jitter < 0.5,
		"[LandformConfig] LakeJitter is a fraction of a cell and must be under 0.5"
	)
	assert(
		LandformConfig.LakeChance >= 0,
		"[LandformConfig] LakeChance must not be negative"
	)

	local lakeRoom = (1.5 - jitter) * LandformConfig.LakeCellBlocks
	local lakeTotal = 0
	for index, kind in ipairs(LandformConfig.LakeKinds) do
		local label = string.format("[LandformConfig] LakeKinds[%d]", index)
		assert(type(kind.name) == "string" and kind.name ~= "", label .. " needs a name")
		assert(
			type(kind.weight) == "number" and kind.weight > 0,
			label .. " needs a positive weight"
		)
		assert(
			type(kind.radius) == "number" and kind.radius > 0,
			label .. " needs a positive radius"
		)
		assert(
			type(kind.depth) == "number" and kind.depth > 0,
			label .. " needs a positive depth"
		)
		assert(
			type(kind.shore) == "number" and kind.shore > 0 and kind.shore <= 1,
			label .. " shore must be a fraction of the radius, over 0 and at most 1"
		)

		local stretch = kind.stretch or 0
		assert(stretch >= 0 and stretch < 1, label .. " stretch must be a fraction under 1")

		--[[
			The LONG semi-axis, which is what actually has to fit.

			Landform preserves a lake's area by taking its axes as r*e and r/e,
			and clamps the eccentricity to at least 1/(1 + stretch) precisely so
			that this is the furthest it can reach. Written as r*(1 + stretch)
			without that clamp the check would pass while a lake at the other
			end of the range stretched to r/(1 - stretch) - half again as far.
		]]
		local furthest = kind.radius * (1 + stretch)
		assert(
			furthest < lakeRoom,
			string.format(
				"%s reaches %.0f blocks but a column only tests the 3x3 lake cells around it, "
					.. "which bounds any reach at %.0f (LakeCellBlocks %d, LakeJitter %.2f). "
					.. "A lake past that would be cut off along the cell grid.",
				label, furthest, lakeRoom, LandformConfig.LakeCellBlocks, jitter
			)
		)

		lakeTotal += kind.weight
	end
	assert(lakeTotal > 0, "[LandformConfig] LakeKinds needs at least one entry")

	assert(
		LandformConfig.LakeFreeboardBlocks > 0,
		"[LandformConfig] LakeFreeboardBlocks must be positive, or a lake's surface sits "
			.. "level with the untouched ground and floods wherever the per-block roughness "
			.. "happens to dip"
	)
	assert(
		LandformConfig.LakeSeaMarginBlocks >= 0,
		"[LandformConfig] LakeSeaMarginBlocks must not be negative"
	)
end

return LandformConfig
