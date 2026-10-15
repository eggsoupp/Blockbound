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
	{ match = { "desert", "cactus" }, biome = "Desert" },
	{ match = { "snow", "pine", "spruce" }, biome = "Snow" },
	{ match = { "hallow", "hollow" }, biome = "Hallow" },
	{ match = { "corrupt" }, biome = "Corruption" },
	{ match = { "crimson" }, biome = "Crimson" },

	-- Plains sub-biomes. These come before the generic Plains entry so a name
	-- carrying a species wins over one merely carrying the biome.
	{ match = { "oak" }, biome = "Plains", variant = "OakForest" },
	{ match = { "birch" }, biome = "Plains", variant = "BirchForest" },

	{ match = { "plain", "grass" }, biome = "Plains" },
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
		radius = 1,
		flatness = 1,
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
			Hallow = 0.35,
			Crimson = 0.25,
			Corruption = 0.25,
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

		-- Enough that a stand stops looking stamped, little enough that no tree
		-- looks like a different species. Health is derived from height, so a
		-- taller tree also takes one more chop now and then, which is a
		-- side effect worth having.
		scaleVariance = 0.12,

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
