--[[
	StructureConfig

	Everything the world scatters on top of the raw terrain: trees, rocks, ruins,
	caves, anything else you add later.

	The terrain generator knows nothing about any specific structure. It asks
	StructureRegistry for placements and applies them. So adding content means
	adding a table here - never editing the generator.

	ORES DO NOT LIVE HERE. They are dense, they are everywhere underground, and
	they are cheap to answer for lazily; a candidate-and-footprint system is the
	wrong shape for that. See OreConfig / OreRegistry instead.

	===========================================================================
	DEFINITION SCHEMA
	===========================================================================

	id              string    unique. Used in logs and as the model name prefix.
	kind            string    "Model" | "Blocks" | "Custom"
	enabled         boolean   default true
	priority        number    higher wins when two structures want the same
	                          space. Ties break on a deterministic hash.

	--- where it may appear -------------------------------------------------
	biomes          map       biomeName -> density multiplier. Omit the table
	                          entirely for "every biome at 1.0"; omit a biome
	                          from the table to ban it there.
	variants        map       variantName -> density multiplier, for biomes that
	                          declare sub-biomes in BiomeConfig. Same rule as
	                          `biomes` one level down: omit the table for "every
	                          variant at 1.0", omit a variant to ban it there.
	                          Columns in a biome with no variants ignore this.
	density         number    expected structures per surface column, before
	                          multipliers. 0.03 is roughly one per 33 columns.
	spacing         number    blocks between candidate origins of this same
	                          structure. Also the sampling grid size, so raising
	                          it makes candidate generation cheaper.
	radius          number    footprint radius in blocks. Two structures may not
	                          overlap within r1 + r2 of each other.
	minSurfaceHeight, maxSurfaceHeight
	                number    surface height band, in blocks.
	flatness        number    max height difference allowed across the
	                          footprint. nil disables the check.
	flatRadius      number?   how far out the flatness check reaches, when that
	                          is wider than radius. Defaults to radius.
	maxSink         number?   how far below its own column a structure may be
	                          lowered to keep an overhanging base in contact
	                          with ground that steps down. Defaults to
	                          `flatness`, which the footprint was already vetted
	                          against, so it can never dig into a step that
	                          placement would have refused.
	surfaces        array?    surface block names this may stand on. Omit for
	                          "any". This is the only way to say "not on bare
	                          rock": the surface block is decided by altitude
	                          and by the ridge field long after the biome is, so
	                          a column in the middle of Plains can be Stone and
	                          neither its height nor its biome name says so.
	requiresBlocks  array     block names that must exist in
	                          TerrainAssets.Blocks. If any is missing the
	                          structure disables itself with a warning instead
	                          of generating something wrong.

	--- what it builds ------------------------------------------------------
	Model kind:
	  modelSource   string    folder under ReplicatedStorage.TerrainAssets
	  modelKeywords map       see TreeKeywords below; picks a per-biome pool
	  quietFallback boolean?  a biome with no keyword pool silently uses the
	                          unmatched models instead of warning about it
	  GroundSink    attribute on a template model, in studs: buried that much
	                          further than its lowest point (a plant in a pot)
	  nameFormat    string?   string.format pattern receiving the biome name.
	                          nil keeps the source model's own name.
	  tag           string?   CollectionService tag applied to every BasePart
	  health        "auto"|number|nil
	                          adds a Health IntValue; "auto" derives it from the
	                          model's height
	  randomYaw     boolean   random rotation about Y
	  scaleVariance number?   fractional size jitter, e.g. 0.1 for plus or minus
	                          10%. Deterministic from position, so a model keeps
	                          its size across chunk reloads. Everything derived
	                          from the model - where it sits on the ground, and
	                          its "auto" health - is measured after scaling.
	  harvest       table?    what breaking it down yields, read by
	                          ServerScriptService.HarvestServer:
	                            item        item name granted
	                            min, max    how many
	                            bonus       optional second drop:
	                                          { item, chance, min, max }
	                            toolClass   ItemDefinitions classification the
	                                        held tool must have ("Tool" for axes)
	                            damage      hit points removed per swing
	                          Requires `tag`, which is how a hit part is traced
	                          back to this definition. Omit harvest entirely and
	                          the structure simply cannot be harvested.

	Blocks kind:
	  blocks        array of { dx, dy, dz, block, mode }
	                          dx/dz are offsets from the origin column.
	                          dy is relative to the ground: 0 is the first cell
	                          ABOVE the surface, -1 is the top solid block.
	                          mode is "add" (default) | "override" | "carve".

	Custom kind:
	  build(ctx)    function  ctx exposes:
	                            ctx.blockX, ctx.blockZ, ctx.surfaceY, ctx.biome
	                            ctx:setBlock(dx, dy, dz, name)
	                            ctx:overrideBlock(dx, dy, dz, name)
	                            ctx:carve(dx, dy, dz)
	                            ctx:surfaceAt(dx, dz)
	                            ctx:random(salt)  -- deterministic [0,1)
	                          Writes outside the chunk being generated are
	                          dropped; the neighbouring chunk recomputes the
	                          same structure and writes its own share, so
	                          structures cross chunk borders correctly.
]]

local StructureConfig = {}

-- Master switch and a single dial for "more/less stuff everywhere".
StructureConfig.Enabled = true
StructureConfig.GlobalDensityMultiplier = 1.0

-- Safety rail: no structure may reach further than this from its origin, since
-- conflict resolution only inspects the 3x3 chunk neighbourhood.
StructureConfig.MaxRadiusBlocks = 8

--[[
	How far a chop reaches, in studs from the character's root to the nearest
	point of the part struck. The same as mining's reach (MiningServer's
	MAX_MINE_DISTANCE), so a tree is exactly as easy to reach as a block.

	HarvestClient uses it to decide what a click aims at and outlines;
	HarvestServer enforces it, with a little slack for lag.
]]
StructureConfig.HarvestReach = 34

--[[
	One chop per this many seconds, however fast the clicks come. Holding the
	button chops at exactly this rhythm (HarvestClient); HarvestServer refuses
	anything quicker, so clicking faster gains nothing.
]]
StructureConfig.ChopSeconds = 1.0

--[[
	THE TREE NAMING CONVENTION

	Which pool a tree model belongs to is decided by its NAME. Put a fragment
	from the table below anywhere in the model's name, in any case, and it sorts
	itself:

	    OakTree1, oak_big, PlainsOakA   -> Plains / OakForest
	    BirchTree1, birch_thin          -> Plains / BirchForest
	    PineTree2, SnowySpruce          -> Snow
	    Cactus1, desert_shrub           -> Desert
	    HallowTree1                     -> Hallow
	    CrimsonTree1                    -> Crimson
	    CorruptTree1                    -> Corruption

	An entry with a `variant` narrows it to that sub-biome of the biome; an
	entry with only a `biome` covers the whole biome. Anything matching nothing
	lands in the shared default pool and can turn up anywhere, which is the
	right home for a generic tree.

	FIRST HIT WINS, so order matters where names overlap. "snow" is listed
	before the Plains entries deliberately: a model called "SnowyOak" is a snow
	tree, not an oak wood tree.

	Adding a species means one line here, one variant in BiomeConfig, and models
	named to match. StructureRegistry warns at startup if a variant ends up with
	no models, so a typo announces itself rather than quietly emptying a forest.
]]
StructureConfig.TreeKeywords = {
	-- Bare broadleaves stand in the swamp; a bare pine is still a Snow pine.
	{ match = { "maple_tree_leafless", "oak_tree_leafless" }, biome = "Swamp" },
	-- Autumn colour belongs to the plains, ahead of "pine" and "oak" below.
	{ match = { "autumn" }, biome = "Plains" },
	{ match = { "desert", "cactus", "palm" }, biome = "Desert" },
	{ match = { "snow", "pine", "spruce" }, biome = "Snow" },
	{ match = { "hallow", "hollow" }, biome = "Hallow" },
	{ match = { "corrupt" }, biome = "Corruption" },
	{ match = { "crimson" }, biome = "Crimson" },

	-- Plains sub-biomes. These come before the generic Plains entry so a name
	-- carrying a species wins over one merely carrying the biome.
	-- The original birch models were retired to UnusedAssets for not matching
	-- the voxel pack; the pack's green maples stand in the birch woods now.
	{ match = { "oak" }, biome = "Plains", variant = "OakForest" },
	{ match = { "birch", "maple" }, biome = "Plains", variant = "BirchForest" },

	{ match = { "plain", "grass" }, biome = "Plains" },
}

--[[
	GROUND COVER

	Everything below the trees: flowers, grass, shrubs, rocks, fallen wood.
	Each family is its own definition over its own TerrainAssets folder, so a
	meadow's flowers and a forest's mushrooms get their own densities rather
	than sharing one roll. The models are the imported voxel pack, scaled up
	in place to sit with 4-stud blocks; anything you walk through has
	CanCollide and CanQuery off on the template, so it never blocks a step, a
	mining click or a chop.

	Plains' Open variant thins structures to 0.06 so the clearings stay clear
	of trees. Ground cover wants the opposite, so its variants table hands
	the clearings most of that back.

	PATCHES. Nothing small is scattered evenly: a `patch` table gathers a
	family into discs - a bed of one flower, a stand of wheat, a ring of
	mushrooms - with bare ground between them. `density` is then the density
	INSIDE a patch, at its centre.

	  patch.size      cell size in blocks; at most one patch per cell
	  patch.coverage  chance a cell holds a patch
	  patch.radius    patch radius in blocks, at most size / 2
	  patch.mix       share of a patch drawn as any species rather than the
	                  patch's own one

	Every part placed from this table carries the GroundCover tag, which the
	client's level-of-detail setting hides (StarterPlayerScripts.GroundCoverLOD).
]]
local SOIL = { "Grass", "Dirt", "HallowedDirt" }
local MEADOW = { Open = 12, OakForest = 0.6, BirchForest = 0.6 }
local WOODS = { Open = 3, OakForest = 1, BirchForest = 1 }

-- Keyword tables for the families that split by biome.
local DEADWOOD_KEYWORDS = {
	{ match = { "mossy" }, biome = "Swamp" },
	-- A black stump, the only deadwood the Hallow gets.
	{ match = { "hallow" }, biome = "Hallow" },
}
local MUSHROOM_KEYWORDS = {
	{ match = { "pruple", "purple" }, biome = "Corruption" },
	{ match = { "red" }, biome = "Crimson" },
}
local BOULDER_KEYWORDS = { { match = { "mossy" }, biome = "Swamp" } }

-- Shared by every ground-cover definition: deterministic size jitter and a
-- random facing, so a meadow never repeats itself in rows.
local function cover(def)
	def.kind = "Model"
	def.randomYaw = true
	def.scaleVariance = def.scaleVariance or 0.3
	def.priority = def.priority or 5
	def.radius = def.radius or 0
	def.flatness = def.flatness or 0
	def.minSurfaceHeight = def.minSurfaceHeight or 2
	-- Unmatched models are the family's general pool, not a naming mistake.
	def.quietFallback = true
	def.groundCover = true
	return def
end

StructureConfig.GroundCover = {
	-- Flower beds: one colour each, a few strays mixed in.
	cover({
		id = "Flowers",
		modelSource = "Flowers",
		density = 1.0,
		spacing = 1,
		patch = { size = 14, coverage = 0.4, radius = 4, mix = 0.12 },
		surfaces = SOIL,
		biomes = { Plains = 1.0, Swamp = 0.3 },
		variants = MEADOW,
	}),
	-- Wheat fields: wide, dense, rare.
	cover({
		id = "Wheat",
		modelSource = "Wheat",
		density = 1.4,
		spacing = 1,
		patch = { size = 24, coverage = 0.22, radius = 6, mix = 0.3 },
		surfaces = { "Grass" },
		biomes = { Plains = 1.0 },
		variants = { Open = 12 },
	}),
	-- Thickets at the edges of the woods.
	cover({
		id = "Shrubs",
		-- Wider than a block, so the blocks around it must be level too.
		flatRadius = 1,
		modelSource = "Shrubs",
		density = 0.7,
		spacing = 1,
		patch = { size = 12, coverage = 0.35, radius = 3, mix = 0.35 },
		surfaces = SOIL,
		biomes = { Plains = 1.0, Swamp = 1.5 },
		variants = WOODS,
	}),
	-- Small tight clusters of one kind.
	cover({
		id = "Mushrooms",
		modelSource = "Mushrooms",
		modelKeywords = MUSHROOM_KEYWORDS,
		density = 1.2,
		spacing = 1,
		patch = { size = 12, coverage = 0.3, radius = 2 },
		surfaces = { "Grass", "Dirt", "CrimsonDirt", "CorruptedDirt" },
		biomes = { Plains = 1.0, Swamp = 2.0, Crimson = 3.0, Corruption = 3.0 },
		variants = { OakForest = 1, BirchForest = 1 },
	}),
	-- Cactus groves with open sand between them.
	cover({
		id = "DesertPlants",
		modelSource = "DesertPlants",
		density = 0.9,
		spacing = 1,
		patch = { size = 14, coverage = 0.4, radius = 3, mix = 0.4 },
		surfaces = { "Sand" },
		biomes = { Desert = 4.0 },
	}),
	-- Bamboo groves and reed beds.
	cover({
		id = "Wetland",
		-- Wider than a block, so the blocks around it must be level too.
		flatRadius = 1,
		modelSource = "Wetland",
		density = 1.0,
		spacing = 1,
		patch = { size = 12, coverage = 0.5, radius = 4, mix = 0.15 },
		surfaces = SOIL,
		biomes = { Swamp = 2.0 },
	}),
	-- Scree: small spills of loose stone.
	cover({
		id = "Pebbles",
		scaleVariance = 0.4,
		modelSource = "Pebbles",
		density = 0.6,
		spacing = 1,
		patch = { size = 14, coverage = 0.25, radius = 2, mix = 0.5 },
		biomes = { Plains = 1.0, Swamp = 1.0, Desert = 3.0, Snow = 2.0, Crimson = 2.0, Corruption = 2.0 },
		variants = WOODS,
	}),
	cover({
		id = "Boulders",
		-- Some boulders are knee-high, some twice that.
		scaleVariance = 0.5,
		-- Long and low: on a step one end hangs in the air, so only flat ground.
		flatness = 0,
		modelSource = "Boulders",
		modelKeywords = BOULDER_KEYWORDS,
		priority = 15,
		density = 0.003,
		spacing = 6,
		radius = 1,
		biomes = { Plains = 1.0, Swamp = 1.0, Desert = 3.0, Snow = 2.0, Crimson = 2.0, Corruption = 2.0 },
		variants = WOODS,
	}),
	cover({
		id = "Deadwood",
		-- Long and low: on a step one end hangs in the air, so only flat ground.
		flatness = 0,
		modelSource = "Deadwood",
		modelKeywords = DEADWOOD_KEYWORDS,
		priority = 15,
		density = 0.005,
		spacing = 5,
		radius = 1,
		surfaces = { "Grass", "Dirt", "Snow", "HallowedDirt" },
		biomes = { Plains = 1.0, Swamp = 1.5, Snow = 1.5, Hallow = 1.5 },
		variants = WOODS,
		scaleVariance = 0.25,

		-- Stumps and fallen logs chop like a small tree, for a little wood.
		tag = "DeadwoodPart",
		health = 2,
		harvest = {
			item = "Wood",
			min = 1,
			max = 2,
			toolClass = "Tool",
			damage = 1,
		},
	}),
}

StructureConfig.Definitions = {

	-- =======================================================================
	-- Trees. Reads ReplicatedStorage.TerrainAssets.Trees and sorts the models
	-- into per-biome pools using TreeKeywords; anything unmatched becomes the
	-- shared default pool. Densities match the previous generator so existing
	-- worlds look the same.
	-- =======================================================================
	{
		id = "Tree",
		kind = "Model",
		priority = 20,

		density = 0.035,
		spacing = 3,
		-- Trunks four blocks apart at least: the pack's canopies are five wide.
		radius = 2,
		-- Level under the trunk and the blocks round it: on a step the trunk either
		-- hangs in the air or sinks into the block. Roots reaching further sink a
		-- little into a neighbour, which reads as roots.
		flatRadius = 1,
		flatness = 0,
		minSurfaceHeight = 2,

		--[[
			Soil, sand and snow. Everything a biome puts down as its own top
			block, and nothing that altitude puts down over it.

			Stone is the point of the list. A ridge breaking through grassland
			and the shoulders of a landmark peak both get a stone surface from
			BiomeMap.surfaceBlock while staying inside a wooded biome, so
			without this trees grow straight out of bare rock faces. The
			*Stone under-blocks are absent for the same reason: they surface on
			lake beds, and a tree on a dry lake bed is the same wrong picture.

			Snow IS here - a snowy biome's trees standing in snow is the whole
			look of the place - and so is Sand, which is what carries the
			desert's own thin scattering.
		]]
		surfaces = {
			"Grass", "Dirt", "Sand", "Snow",
			"HallowedDirt", "CrimsonDirt", "CorruptedDirt",
		},

		biomes = {
			Plains = 1.00,
			-- Wet ground, so thinner than grassland but far from bare. Trees
			-- are refused in standing water regardless (see StructureRegistry),
			-- which is what leaves them on the islands between the channels.
			Swamp = 0.55,
			Desert = 0.22,
			Snow = 0.35,
			-- The three evil-and-holy biomes run thin on structures (BiomeConfig),
			-- so their recoloured woods are pushed up to read as woods at all.
			Hallow = 1.2,
			Crimson = 1.4,
			Corruption = 1.4,
		},

		--[[
			Per-sub-biome multipliers, on top of the biome ones above and the
			variant's own structureDensity in BiomeConfig.

			Listing them all at 1.0 is not the same as omitting the table: a
			structure that declares `variants` is BANNED in any variant it does
			not name, which is how you would make something appear only in birch
			woods. Trees belong in all three, so all three are here, and the
			actual thinning of the open ground is BiomeConfig's Open variant at
			0.06.
		]]
		variants = {
			OakForest = 1.0,
			BirchForest = 1.0,
			Open = 1.0,
		},

		modelSource = "Trees",
		modelKeywords = StructureConfig.TreeKeywords,

		-- Set to nil to keep each model's authored name instead. The rainbow
		-- leaf effect (StarterPlayerScripts.HallowTreeRainbow) matches on the
		-- biome prefix this produces, so changing the format changes what it
		-- picks up.
		nameFormat = "%sTree",
		tag = "TreePart",
		health = "auto",
		randomYaw = true,

		-- Wide: a stand has saplings and giants in it, never one size stamped
		-- over and over. Health is derived from height, so a
		-- taller tree also takes one more chop now and then, which is a
		-- side effect worth having.
		scaleVariance = 0.3,

		-- Chopping a tree is the only source of Wood, which the whole crafting
		-- tree hangs off. HarvestServer reads this; nothing else does.
		harvest = {
			item = "Wood",
			min = 3,
			max = 6,
			toolClass = "Tool",
			damage = 1,

			-- Occasional second drop. Herb is otherwise unobtainable, which
			-- left the health potion recipe permanently out of reach.
			bonus = { item = "Herb", chance = 0.35, min = 1, max = 2 },
		},
	},

	-- =======================================================================
	-- A worked example of the Blocks kind: a small stone lump on the surface.
	--
	-- Off by default so the world still contains exactly what it did before.
	-- Flip enabled to true to see the block pipeline live - including a
	-- boulder that straddles a chunk border, which both chunks build their own
	-- half of. Disables itself automatically if TerrainAssets.Blocks has no
	-- "Stone".
	-- =======================================================================
	{
		id = "Boulder",
		kind = "Blocks",
		enabled = false,
		priority = 10,

		density = 0.004,
		spacing = 6,
		radius = 2,
		flatness = 1,
		minSurfaceHeight = 2,
		requiresBlocks = { "Stone" },

		biomes = {
			Plains = 1.0,
			Snow = 1.2,
			Desert = 0.5,
			Swamp = 0.3,
			Crimson = 0.6,
			Corruption = 0.6,
		},

		blocks = {
			{ 0, 0, 0, "Stone" },
			{ 1, 0, 0, "Stone" },
			{ -1, 0, 0, "Stone" },
			{ 0, 0, 1, "Stone" },
			{ 0, 0, -1, "Stone" },
			{ 0, 1, 0, "Stone" },
		},
	},

	--[[
		=======================================================================
		THE ALTAR. Where the Gelatinous Crown is used to call the Slime Emperor
		(ServerScriptService.AltarSummon).

		A 3x3 plinth of AltarStone with a short pillar at each corner and the
		glowing AltarCore raised in the middle - a shape that reads as "built"
		from a distance, out of the two placeholder blocks in BlockConfig.
		Generated. Both blocks disable the structure if they go missing
		(requiresBlocks), which they cannot while Generated carries them.

		VERY RARE, AND ONLY ON PLAINS GRASS. Surface Grass only, so it never
		sits on a ridge's bare stone; flat ground, so it never half-floats. The
		density works out at about one per 150x150 blocks of open plains: a
		landmark you remember the way back to, not something you trip over. The
		variant multipliers undo Plains' own sub-biome structureDensity (Open is
		0.06, the forests ~1.3) so it prefers the clearings, where it can be
		seen, over the woods: open ground gets the full rate, the woods a
		quarter of it.

		Priority above trees, so a tree never wins the altar's footprint; a
		radius of 2 keeps everything else that far away from the plinth.
		=======================================================================
	]]
	{
		id = "Altar",
		kind = "Blocks",
		priority = 60,

		density = 0.00005,
		spacing = 16,
		radius = 2,
		flatness = 1,
		minSurfaceHeight = 3,
		surfaces = { "Grass" },
		requiresBlocks = { "AltarStone", "AltarCore" },

		biomes = { Plains = 1.0 },
		variants = {
			Open = 16.7,
			OakForest = 0.19,
			BirchForest = 0.2,
		},

		blocks = {
			-- The plinth: a 3x3 slab laid on the grass.
			{ -1, 0, -1, "AltarStone" }, { 0, 0, -1, "AltarStone" }, { 1, 0, -1, "AltarStone" },
			{ -1, 0, 0, "AltarStone" }, { 0, 0, 0, "AltarStone" }, { 1, 0, 0, "AltarStone" },
			{ -1, 0, 1, "AltarStone" }, { 0, 0, 1, "AltarStone" }, { 1, 0, 1, "AltarStone" },

			-- Four corner pillars, one block tall.
			{ -1, 1, -1, "AltarStone" },
			{ 1, 1, -1, "AltarStone" },
			{ -1, 1, 1, "AltarStone" },
			{ 1, 1, 1, "AltarStone" },

			-- The core, raised in the middle so it stands above the pillars.
			{ 0, 1, 0, "AltarStone" },
			{ 0, 2, 0, "AltarCore" },
		},
	},

	-- =======================================================================
	-- Template to copy for ruins / houses / anything hand-authored. Left off so
	-- it costs nothing; flip enabled and point modelSource at a folder.
	-- =======================================================================
	{
		id = "DesertRuin",
		kind = "Model",
		enabled = false,
		priority = 40,

		density = 0.0006,
		spacing = 24,
		radius = 5,
		flatness = 1,
		minSurfaceHeight = 3,

		biomes = { Desert = 1.0 },

		modelSource = "Ruins",
		randomYaw = true,
	},
}

for _, def in ipairs(StructureConfig.GroundCover) do
	table.insert(StructureConfig.Definitions, def)
end

--[[
	Structural sanity check. Runs at require time.
]]
function StructureConfig.validate()
	local seen = {}

	for index, def in ipairs(StructureConfig.Definitions) do
		local label = string.format("[StructureConfig] Definitions[%d]", index)

		assert(type(def.id) == "string" and def.id ~= "", label .. " needs an id")
		assert(not seen[def.id], label .. " reuses the id '" .. tostring(def.id) .. "'")
		seen[def.id] = true

		assert(
			def.kind == "Model" or def.kind == "Blocks" or def.kind == "Custom",
			label .. " has unknown kind " .. tostring(def.kind)
		)
		assert(
			type(def.density) == "number" and def.density >= 0,
			label .. " needs a non-negative density"
		)

		local radius = def.radius or 0
		assert(
			radius <= StructureConfig.MaxRadiusBlocks,
			string.format(
				"%s has radius %d, above MaxRadiusBlocks (%d). Overlap resolution only "
					.. "inspects neighbouring chunks, so a larger footprint could overlap "
					.. "something it never saw.",
				label, radius, StructureConfig.MaxRadiusBlocks
			)
		)

		--[[
			An EMPTY surfaces list is refused rather than treated as "any".

			An empty allow-list means the structure can never be placed
			anywhere, and it produces exactly the same world as a structure that
			is simply rare: nothing, quietly, in a way no amount of flying
			around would ever diagnose.
		]]
		if def.surfaces ~= nil then
			assert(
				type(def.surfaces) == "table" and #def.surfaces > 0,
				label .. " has a surfaces list that is empty or is not an array"
			)
		end

		if def.maxSink ~= nil then
			assert(
				type(def.maxSink) == "number" and def.maxSink >= 0,
				label .. " has a maxSink that is not a non-negative number"
			)
		end

		if def.kind == "Blocks" then
			assert(type(def.blocks) == "table", label .. " is kind Blocks but has no blocks array")
		elseif def.kind == "Custom" then
			assert(type(def.build) == "function", label .. " is kind Custom but has no build function")
		elseif def.kind == "Model" then
			assert(type(def.modelSource) == "string", label .. " is kind Model but has no modelSource")
		end
	end
end

--[[
	Which held-tool classifications can harvest anything at all.

	The client needs this to decide whether a click is worth sending to the
	server: swinging an axe at a tree is a request, and swinging a pickaxe at
	the same tree is not. Asking here rather than hard-coding "Tool" in the
	client keeps that decision in the same table that declares it - a structure
	made choppable by a new tool class starts working without the client
	learning its name.

	`true` under the `any` key means some structure has no toolClass at all and
	can be harvested bare-handed, in which case every click is worth sending.

	Built on each call, and the client calls it on every swing: it walks a
	handful of definitions and builds a table of two or three entries, which is
	nothing next to the raycast the same click is about to do.
]]
function StructureConfig.harvestToolClasses()
	local classes = {}

	for _, def in ipairs(StructureConfig.Definitions) do
		if def.harvest and def.enabled ~= false then
			local required = def.harvest.toolClass

			if type(required) == "string" then
				classes[required] = true
			else
				classes.any = true
			end
		end
	end

	return classes
end

return StructureConfig
