--[[
	StructureRegistry

	Decides what gets scattered on the terrain, and where. The terrain generator
	calls three functions and never learns what a "tree" is.

	  StructureRegistry.init(options)
	  StructureRegistry.applyBlocks(cx, cz, writer)   -- before visibility pass
	  StructureRegistry.applyModels(cx, cz, writer)   -- after visibility pass
	  StructureRegistry.register(def)                 -- add a structure at runtime

	===========================================================================
	HOW PLACEMENT STAYS CORRECT
	===========================================================================

	Candidates come from a jittered grid keyed on ABSOLUTE world coordinates, so
	the set of candidates near a point is identical no matter which chunk asks.
	Nothing depends on chunk load order.

	Overlap is resolved by a deterministic contest: every candidate carries a
	score (its definition's priority plus a positional hash), and a candidate is
	accepted only if no overlapping candidate outranks it. Because the ordering
	is total and position-derived, two chunks resolving the same border pair
	always agree. Acceptance is memoised on the candidate, so the comparison
	runs once per candidate rather than once per chunk that can see it.

	Structures that straddle a chunk border are computed by BOTH chunks; each
	writer silently drops writes outside its own chunk. So a boulder half in
	chunk A and half in chunk B renders correctly, and still does after B is
	unloaded and reloaded on its own.

	===========================================================================
	WRITER INTERFACE  (supplied by TerrainManager)
	===========================================================================

	  writer.setBlock(blockX, blockZ, blockY, name)      add a block
	  writer.overrideBlock(blockX, blockZ, blockY, name) restyle an existing one
	  writer.carve(blockX, blockZ, blockY)               remove one
	  writer.surfaceAt(blockX, blockZ) -> height?        ground as built, or nil
	  writer.addModel(model)                             parent a finished model

	All coordinates are absolute block coordinates. The writer is responsible
	for ignoring anything outside the chunk it is building.

	===========================================================================
	HOW A MODEL FINDS THE GROUND
	===========================================================================

	Three separate things went wrong here often enough to be worth writing down,
	because every one of them looks like the same bug from inside the game - a
	tree that is not standing on the floor.

	  1. Model:GetBoundingBox() is aligned to the model's PIVOT, not to the
	     world. Measure a model whose PrimaryPart was authored at any angle and
	     the box you get is tilted with it, so its "bottom" is not the lowest
	     point in the world - and placement then squares the model upright,
	     which moves the real bottom somewhere the measurement never described.
	     Some trees sank, some hovered, and which one a model did was a property
	     of how its artist happened to leave the pivot.

	     So the model is ORIENTED FIRST and measured afterwards, in world space,
	     off the parts themselves.

	  2. A model sits on the column its origin block names, and a tree wider
	     than one block overhangs its neighbours. Step down by one at a cliff
	     edge and the overhanging side is standing on nothing. So the seat is
	     the LOWEST column the model's BASE actually covers - its base, not its
	     canopy, which is why the footprint below is measured from the parts
	     near the bottom rather than from the whole model.

	  3. Ground gets built up and dug out. See writer.surfaceAt.
]]

local CollectionService = game:GetService("CollectionService")

local TerrainFolder = script.Parent
local StructureConfig = require(TerrainFolder:WaitForChild("StructureConfig"))
local BiomeConfig = require(TerrainFolder:WaitForChild("BiomeConfig"))

local StructureRegistry = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local prepared = {} -- array of prepared definitions
local options = nil
local chunkSize = 16
local studSize = 4
local hashSeed = 0
local isReady = false

local candidateCache = {}
local candidateCacheCount = 0

local KEY_OFFSET = 8192
local KEY_STRIDE = 65536

local SALT_ACCEPT = 1
local SALT_JITTER_X = 2
local SALT_JITTER_Z = 3
local SALT_PRIORITY = 4
local SALT_YAW = 5
local SALT_MODEL = 6
local SALT_CUSTOM = 7
local SALT_SCALE = 8

local candidateCacheLimit = 400

-- Scratch buffers reused between calls. Nothing here survives a yield.
local scratchCandidates = {}
local scratchRelevant = {}

-- ---------------------------------------------------------------------------
-- Deterministic hashing
-- ---------------------------------------------------------------------------

--[[
	Position hash in [0, 1). Deterministic for a given world seed, allocation
	free, and independent of evaluation order - which is what lets two chunks
	agree about a structure on their shared border.
]]
local function hashUnit(a, b, c, salt)
	local x = a * 127.1 + b * 311.7 + c * 74.7 + salt * 269.5 + hashSeed
	local y = a * 269.5 + b * 183.3 + c * 246.1 + salt * 113.5 + hashSeed
	local v = math.sin(x) * 43758.5453 + math.sin(y) * 28001.8384
	return v - math.floor(v)
end

local function chunkKeyOf(cx, cz)
	return (cx + KEY_OFFSET) * KEY_STRIDE + (cz + KEY_OFFSET)
end

-- ---------------------------------------------------------------------------
-- Definition preparation
-- ---------------------------------------------------------------------------

local function findAssetFolder(sourceName)
	if not options or not options.assetsRoot then
		return nil
	end
	return options.assetsRoot:FindFirstChild(sourceName)
end

--[[
	The pool key for a biome, optionally narrowed to one of its sub-biomes.

	"Plains|OakForest" rather than a nested table: one string compare picks the
	pool, and the biome-only key is the natural fallback for a variant nobody
	authored models for.
]]
local function poolKey(biome, variant)
	if variant then
		return biome .. "|" .. variant
	end
	return biome
end

--[[
	Sorts the models in a source folder into pools, using the definition's
	keyword table.

	There is a pool per biome, a pool per sub-biome of each biome, and a shared
	default that everything falls back to. Which pool a model lands in is decided
	entirely by its NAME - so adding a birch wood means naming models "Birch..."
	and adding one line to StructureConfig.TreeKeywords, with no code change.
]]
local function buildModelPools(def)
	local pools = { __default = {}, __all = {} }

	for _, name in ipairs(BiomeConfig.Order) do
		pools[name] = {}

		local biomeDef = BiomeConfig.Definitions[name]
		if biomeDef and biomeDef.variants then
			for _, variant in ipairs(biomeDef.variants) do
				pools[poolKey(name, variant.name)] = {}
			end
		end
	end

	local folder = findAssetFolder(def.modelSource)
	if not folder then
		return pools, 0
	end

	local total = 0

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if not primary then
				warn(string.format(
					"[StructureRegistry] '%s' model '%s' has no BasePart; skipping.",
					def.id, model.Name
				))
				continue
			end

			model.PrimaryPart = primary
			table.insert(pools.__all, model)
			total += 1

			local matchedBiome, matchedVariant = nil, nil
			if def.modelKeywords then
				local lower = string.lower(model.Name)
				for _, entry in ipairs(def.modelKeywords) do
					local hit = false
					for _, fragment in ipairs(entry.match) do
						if string.find(lower, fragment, 1, true) then
							hit = true
							break
						end
					end
					if hit then
						matchedBiome = entry.biome
						matchedVariant = entry.variant
						break
					end
				end
			end

			--[[
				A keyword may name a sub-biome, a biome, or neither.

				A model matched to a VARIANT joins two pools: its own, and its
				biome's. That second membership is what makes the open ground
				between the woods work - it has no species of its own, so it
				falls back to the biome pool, and the biome pool should mean
				"every tree that belongs in Plains" rather than only the ones
				nobody assigned to a forest. Without it the fallback used to
				reach past Plains entirely and pull in pines and cacti.
			]]
			if matchedBiome then
				local variantPool = matchedVariant and pools[poolKey(matchedBiome, matchedVariant)]
				if variantPool then
					table.insert(variantPool, model)
				end

				local biomePool = pools[matchedBiome]
				if biomePool then
					table.insert(biomePool, model)
				elseif not variantPool then
					table.insert(pools.__default, model)
				end
			else
				table.insert(pools.__default, model)
			end
		end
	end

	return pools, total
end

--[[
	Returns false (with a warning) if the definition asks for block templates
	that are not in TerrainAssets.Blocks. Better to disable one structure than
	to silently build a rock out of dirt.
]]
local function requiredBlocksExist(def)
	if not def.requiresBlocks then
		return true
	end

	local blocksFolder = options and options.blocksFolder
	if not blocksFolder then
		return false
	end

	for _, name in ipairs(def.requiresBlocks) do
		if not blocksFolder:FindFirstChild(name) then
			warn(string.format(
				"[StructureRegistry] '%s' disabled: TerrainAssets.Blocks has no '%s'.",
				def.id, name
			))
			return false
		end
	end

	return true
end

local function prepareDefinition(def, index)
	local entry = {
		source = def,
		index = index,
		id = def.id,
		kind = def.kind,
		enabled = def.enabled ~= false,
		priority = def.priority or 0,

		density = def.density or 0,
		spacing = math.max(1, math.floor(def.spacing or 4)),
		radius = def.radius or 0,
		flatness = def.flatness,
		minSurfaceHeight = def.minSurfaceHeight,
		maxSurfaceHeight = def.maxSurfaceHeight,

		biomes = def.biomes,
		variants = def.variants,
		blocks = def.blocks,
		build = def.build,

		-- How far below its own column a model may be seated to stay in contact
		-- with the ground its base overhangs. Defaults to the flatness the
		-- footprint was already vetted against, so it can never dig a structure
		-- into a step the placement rules would have refused anyway.
		maxSink = def.maxSink,

		nameFormat = def.nameFormat,
		tag = def.tag,
		health = def.health,
		randomYaw = def.randomYaw,
		scaleVariance = def.scaleVariance,
	}

	entry.cellArea = entry.spacing * entry.spacing

	--[[
		Which surface blocks this structure will stand on, as a set.

		Absent means "any", which is what everything did before this existed.
		Present and the column's top block is checked against it, which is the
		only way to say "not on bare rock": the surface block is chosen by
		altitude and by the ridge field long after the biome is, so a column in
		the middle of Plains can be Stone and nothing about its height or its
		biome name gives that away.
	]]
	if def.surfaces then
		local set = {}
		for _, name in ipairs(def.surfaces) do
			set[name] = true
		end
		entry.surfaces = set
	end

	--[[
		Highest density multiplier any biome - or any sub-biome of it - can
		contribute. Used to reject the overwhelming majority of grid cells before
		paying for a column sample.

		It has to be a true UPPER bound over everything the exact test below can
		produce, variants included. Underestimate it and structures silently stop
		appearing in whichever variant was left out, which is close to
		undiagnosable from looking at the world.
	]]
	local maxMultiplier = 0
	for _, name in ipairs(BiomeConfig.Order) do
		local biomeDef = BiomeConfig.Definitions[name]
		local perBiome = if entry.biomes then (entry.biomes[name] or 0) else 1
		local base = perBiome * (biomeDef.structureDensity or 1)

		local bestVariant = 1
		if biomeDef.variants then
			bestVariant = 0
			for _, variant in ipairs(biomeDef.variants) do
				local perVariant = if entry.variants then (entry.variants[variant.name] or 0) else 1
				local combined = perVariant * (variant.structureDensity or 1)
				if combined > bestVariant then
					bestVariant = combined
				end
			end
		end

		local combined = base * bestVariant
		if combined > maxMultiplier then
			maxMultiplier = combined
		end
	end
	entry.maxMultiplier = maxMultiplier

	if entry.enabled and not requiredBlocksExist(def) then
		entry.enabled = false
	end

	if entry.enabled and entry.kind == "Model" then
		local pools, total = buildModelPools(def)
		entry.pools = pools

		--[[
			Two different mistakes, worth telling apart.

			A variant the keyword table CLAIMS to name models for, whose pool is
			empty, is a typo: an oak wood quietly full of birches. A variant
			with no keyword entry - Open, which has no species of its own - is
			meant to fall back and is not worth mentioning.

			A biome with nothing at all now places nothing there, since the
			fallback no longer reaches for unrelated models, so that one is
			worth saying loudly.
		]]
		local namedVariants = {}
		if def.modelKeywords then
			for _, keyword in ipairs(def.modelKeywords) do
				if keyword.variant then
					namedVariants[keyword.variant] = true
				end
			end
		end

		for _, biomeName in ipairs(BiomeConfig.Order) do
			local biomeDef = BiomeConfig.Definitions[biomeName]
			local allowedHere = if entry.biomes then (entry.biomes[biomeName] or 0) > 0 else true

			if allowedHere then
				local biomePool = pools[biomeName]
				local biomeEmpty = not biomePool or #biomePool == 0

				if biomeEmpty then
					if #pools.__default == 0 then
						warn(string.format(
							"[StructureRegistry] '%s' has no models for %s and no unmatched models "
								.. "to fall back on, so none will be placed there. Name a model "
								.. "after the biome (see StructureConfig.TreeKeywords).",
							def.id, biomeName
						))
					else
						warn(string.format(
							"[StructureRegistry] '%s' has no models named for %s, so the %d model(s) "
								.. "matching no keyword at all will be used there. If that is not "
								.. "what you want, name them.",
							def.id, biomeName, #pools.__default
						))
					end
				end

				if biomeDef.variants then
					for _, variant in ipairs(biomeDef.variants) do
						local wanted = if entry.variants
							then (entry.variants[variant.name] or 0) > 0
							else true
						local pool = pools[poolKey(biomeName, variant.name)]

						if wanted and namedVariants[variant.name] and pool and #pool == 0 then
							warn(string.format(
								"[StructureRegistry] '%s' has no models named for %s/%s, though "
									.. "TreeKeywords says there should be; it will draw from the "
									.. "whole %s pool there instead.",
								def.id, biomeName, variant.name, biomeName
							))
						end
					end
				end
			end
		end

		if total == 0 then
			warn(string.format(
				"[StructureRegistry] '%s' disabled: TerrainAssets.%s has no usable models.",
				def.id, tostring(def.modelSource)
			))
			entry.enabled = false
		end
	end

	if entry.enabled and (entry.density <= 0 or maxMultiplier <= 0) then
		entry.enabled = false
	end

	return entry
end

-- ---------------------------------------------------------------------------
-- Candidate generation
-- ---------------------------------------------------------------------------

--[[
	A biome's variant entry by name, or nil. Linear over a handful of entries,
	which beats building and holding a lookup table for something asked once per
	accepted candidate.
]]
local function variantDefinition(biome, variant)
	local biomeDef = BiomeConfig.Definitions[biome]
	if not biomeDef or not biomeDef.variants then
		return nil
	end

	for _, entry in ipairs(biomeDef.variants) do
		if entry.name == variant then
			return entry
		end
	end

	return nil
end

local function makeCandidate(entry, gx, gz, blockX, blockZ, surfaceY, biome, variant, cx, cz)
	return {
		entry = entry,
		defIndex = entry.index,
		gx = gx,
		gz = gz,
		x = blockX,
		z = blockZ,
		cx = cx,
		cz = cz,
		surfaceY = surfaceY,
		biome = biome,
		variant = variant,
		radius = entry.radius,
		score = entry.priority + hashUnit(gx, gz, entry.index, SALT_PRIORITY),
		accepted = nil,
	}
end

--[[
	Footprint must sit on ground flat enough for the structure, inside the
	world, and out of the water. Runs only for candidates that already survived
	the density roll.

	The water test is per FOOTPRINT column, not just the origin: a tree whose
	trunk is on the bank but whose canopy overhangs a lake is fine, but one
	standing half in the shallows is not, and the footprint is what tells them
	apart.
]]
local function footprintIsValid(entry, blockX, blockZ, surfaceY)
	local radius = entry.radius
	if radius <= 0 or entry.flatness == nil then
		return true
	end

	local tolerance = entry.flatness
	local step = if radius > 2 then math.floor(radius / 2) else 1

	for dx = -radius, radius, step do
		for dz = -radius, radius, step do
			if dx ~= 0 or dz ~= 0 then
				local nx = blockX + dx
				local nz = blockZ + dz
				if not options.isInWorld(nx, nz) then
					return false
				end

				local height, _biome, _variant, water = options.getColumn(nx, nz)
				if math.abs(height - surfaceY) > tolerance then
					return false
				end
				if water ~= nil and water > height then
					return false
				end
			end
		end
	end

	return true
end

--[[
	Every candidate whose origin lies inside chunk (cx, cz), post density roll
	and post validation. Cached, because neighbouring chunks ask for the same
	list during overlap resolution.
]]
local function getCandidates(cx, cz)
	local key = chunkKeyOf(cx, cz)
	local cached = candidateCache[key]
	if cached then
		return cached
	end

	if candidateCacheCount >= candidateCacheLimit then
		table.clear(candidateCache)
		candidateCacheCount = 0
	end

	local list = {}

	local minBlockX = cx * chunkSize
	local minBlockZ = cz * chunkSize
	local maxBlockX = minBlockX + chunkSize - 1
	local maxBlockZ = minBlockZ + chunkSize - 1
	local globalMultiplier = StructureConfig.GlobalDensityMultiplier

	for _, entry in ipairs(prepared) do
		if entry.enabled then
			local spacing = entry.spacing
			local baseChance = entry.density * entry.cellArea * globalMultiplier
			local ceilingChance = baseChance * entry.maxMultiplier

			if ceilingChance > 0 then
				local gxMin = math.floor(minBlockX / spacing)
				local gxMax = math.floor(maxBlockX / spacing)
				local gzMin = math.floor(minBlockZ / spacing)
				local gzMax = math.floor(maxBlockZ / spacing)

				for gx = gxMin, gxMax do
					for gz = gzMin, gzMax do
						local roll = hashUnit(gx, gz, entry.index, SALT_ACCEPT)

						-- Cheap rejection first: no biome can push the chance
						-- above ceilingChance, so anything above it is out
						-- without sampling the world at all.
						if roll < ceilingChance then
							local blockX = gx * spacing
								+ math.floor(hashUnit(gx, gz, entry.index, SALT_JITTER_X) * spacing)
							local blockZ = gz * spacing
								+ math.floor(hashUnit(gx, gz, entry.index, SALT_JITTER_Z) * spacing)

							-- The jittered point may land in a neighbouring
							-- chunk; that chunk owns it.
							if
								blockX >= minBlockX and blockX <= maxBlockX
								and blockZ >= minBlockZ and blockZ <= maxBlockZ
								and options.isInWorld(blockX, blockZ)
								and (options.allowStructureAt == nil or options.allowStructureAt(blockX, blockZ))
							then
								local surfaceY, biome, variant, waterTop, surfaceBlock =
									options.getColumn(blockX, blockZ)
								local perBiome = if entry.biomes then (entry.biomes[biome] or 0) else 1

								--[[
									Nothing grows on bare rock.

									Checked at the ORIGIN column only: a tree on
									the last patch of grass before a crag, with
									its canopy out over the stone, is the right
									picture.

									Skipped entirely when the provider does not
									report a surface block, rather than treated
									as a name that matches nothing. The second
									reading would disable every structure with a
									`surfaces` list, worldwide, silently.
								]]
								if
									surfaceBlock ~= nil
									and entry.surfaces
									and not entry.surfaces[surfaceBlock]
								then
									perBiome = 0
								end

								-- The sub-biome, if this column has one. A
								-- structure that lists `variants` is banned
								-- wherever it does not name the variant, exactly
								-- as `biomes` works one level up.
								local perVariant = 1
								if variant then
									local variantDef = variantDefinition(biome, variant)
									perVariant = (variantDef and variantDef.structureDensity or 1)

									if entry.variants then
										perVariant *= (entry.variants[variant] or 0)
									end
								end

								if perBiome > 0 and perVariant > 0 then
									local biomeDef = BiomeConfig.Definitions[biome]
									local multiplier = perBiome
										* (biomeDef and biomeDef.structureDensity or 1)
										* perVariant

									if
										roll < baseChance * multiplier
										-- Nothing grows in standing water.
										and (waterTop == nil or waterTop <= surfaceY)
										and (entry.minSurfaceHeight == nil or surfaceY >= entry.minSurfaceHeight)
										and (entry.maxSurfaceHeight == nil or surfaceY <= entry.maxSurfaceHeight)
										and footprintIsValid(entry, blockX, blockZ, surfaceY)
									then
										table.insert(
											list,
											makeCandidate(
												entry, gx, gz, blockX, blockZ, surfaceY, biome, variant, cx, cz
											)
										)
									end
								end
							end
						end
					end
				end
			end
		end
	end

	candidateCache[key] = list
	candidateCacheCount += 1
	return list
end

-- ---------------------------------------------------------------------------
-- Overlap resolution
-- ---------------------------------------------------------------------------

--[[
	Strict total order over candidates. Score first, then position, then
	definition index - so it never depends on which chunk is asking.
]]
local function outranks(other, candidate)
	if other.score ~= candidate.score then
		return other.score > candidate.score
	end
	if other.x ~= candidate.x then
		return other.x < candidate.x
	end
	if other.z ~= candidate.z then
		return other.z < candidate.z
	end
	return other.defIndex < candidate.defIndex
end

--[[
	A candidate is accepted unless something overlapping it outranks it.
	Memoised on the candidate: acceptance is a global property, so it is worth
	computing once even though many chunks may ask.
]]
local function isAccepted(candidate)
	if candidate.accepted ~= nil then
		return candidate.accepted
	end

	local cx, cz = candidate.cx, candidate.cz
	local accepted = true

	for ox = cx - 1, cx + 1 do
		for oz = cz - 1, cz + 1 do
			for _, other in ipairs(getCandidates(ox, oz)) do
				if other ~= candidate then
					local reach = candidate.radius + other.radius
					if reach > 0 then
						local dx = other.x - candidate.x
						local dz = other.z - candidate.z
						if dx * dx + dz * dz < reach * reach and outranks(other, candidate) then
							accepted = false
							break
						end
					end
				end
			end
			if not accepted then
				break
			end
		end
		if not accepted then
			break
		end
	end

	candidate.accepted = accepted
	return accepted
end

--[[
	Accepted candidates that can affect chunk (cx, cz): its own, plus anything
	in the eight neighbours whose footprint reaches in. Written into the shared
	scratch buffer, which the caller must consume before yielding.
]]
local function collectRelevant(cx, cz)
	table.clear(scratchRelevant)

	local minBlockX = cx * chunkSize
	local minBlockZ = cz * chunkSize
	local maxBlockX = minBlockX + chunkSize - 1
	local maxBlockZ = minBlockZ + chunkSize - 1

	for ox = cx - 1, cx + 1 do
		for oz = cz - 1, cz + 1 do
			local own = ox == cx and oz == cz

			for _, candidate in ipairs(getCandidates(ox, oz)) do
				local reaches = own
				if not reaches then
					local radius = candidate.radius
					reaches = candidate.x + radius >= minBlockX
						and candidate.x - radius <= maxBlockX
						and candidate.z + radius >= minBlockZ
						and candidate.z - radius <= maxBlockZ
				end

				if reaches and isAccepted(candidate) then
					table.insert(scratchRelevant, candidate)
				end
			end
		end
	end

	return scratchRelevant
end

-- ---------------------------------------------------------------------------
-- Build context (what Custom structures see)
-- ---------------------------------------------------------------------------

local BuildContext = {}
BuildContext.__index = BuildContext

function BuildContext:setBlock(dx, dy, dz, name)
	self.writer.setBlock(self.blockX + dx, self.blockZ + dz, self.surfaceY + dy, name)
end

function BuildContext:overrideBlock(dx, dy, dz, name)
	self.writer.overrideBlock(self.blockX + dx, self.blockZ + dz, self.surfaceY + dy, name)
end

function BuildContext:carve(dx, dy, dz)
	self.writer.carve(self.blockX + dx, self.blockZ + dz, self.surfaceY + dy)
end

function BuildContext:surfaceAt(dx, dz)
	return options.getColumn(self.blockX + dx, self.blockZ + dz)
end

--[[
	Deterministic [0, 1) tied to this structure's position. Same salt always
	gives the same number, in every chunk that recomputes this structure - which
	is what keeps cross-border structures identical on both sides.
]]
function BuildContext:random(salt)
	return hashUnit(self.blockX, self.blockZ, self.defIndex, SALT_CUSTOM + (salt or 0))
end

local function makeContext(candidate, writer)
	return setmetatable({
		writer = writer,
		blockX = candidate.x,
		blockZ = candidate.z,
		surfaceY = candidate.surfaceY,
		biome = candidate.biome,
		variant = candidate.variant,
		defIndex = candidate.defIndex,
		id = candidate.entry.id,
	}, BuildContext)
end

-- ---------------------------------------------------------------------------
-- Model placement
-- ---------------------------------------------------------------------------

local function pickModel(entry, biome, variant, roll)
	local pools = entry.pools
	if not pools then
		return nil
	end

	--[[
		Narrowest pool that has anything in it:

		  the sub-biome  an oak wood draws oaks
		  the biome      open Plains ground draws from every Plains tree, which
		                 is oak and birch and nothing else
		  the default    models matching no keyword at all, which the naming
		                 convention defines as "suits anywhere"

		AND THEN IT STOPS. There used to be a final fall-through to every model
		in the folder, which sounds harmless and is not: the moment a pool came
		up empty the Hallow filled with cacti and the plains grew pines. An
		empty pool now places nothing, because no tree is a better answer than
		the wrong tree.
	]]
	local pool = if variant then pools[poolKey(biome, variant)] else nil

	if not pool or #pool == 0 then
		pool = pools[biome]
	end
	if not pool or #pool == 0 then
		pool = pools.__default
	end
	if not pool or #pool == 0 then
		return nil
	end

	local index = math.floor(roll * #pool) + 1
	if index > #pool then
		index = #pool
	end
	return pool[index]
end

--[[
	How much of a model counts as its BASE, in blocks above its lowest point.

	A tree is a metre of trunk under eight metres of canopy, and it is the trunk
	that has to touch the ground. Measure the whole model's footprint instead
	and a tree at a cliff edge seats itself against whatever the far side of its
	canopy happens to hang over, which is how you bury a tree to its branches.
]]
local BASE_BAND_BLOCKS = 1.25

--[[
	How much of a block the base must cover before that block's ground counts.

	A trunk centred in its own block that pokes a tenth of a block into the
	neighbour is standing on its own column. Letting that tenth drag the whole
	tree down a step would be the floating bug in reverse.
]]
local BASE_BITE = 0.3

-- Seated this far into the ground rather than exactly on it. Small enough to be
-- invisible, large enough that a base which is flat to the millimetre never
-- shows a hairline of daylight under it from floating point alone.
local SEAT_BIAS = 0.05

--[[
	Where a model actually is, in WORLD space.

	Returns  minY, spanY, baseMinX, baseMaxX, baseMinZ, baseMaxZ
	or nil if it has no parts.

	Model:GetBoundingBox() answers a different question - it is aligned to the
	model's pivot, see the header - so this projects each part onto the world
	axes itself. For a part with rotation R and size s the half extent along
	world Y is

	    0.5 * (|R.x.y| * s.x + |R.y.y| * s.y + |R.z.y| * s.z)

	which for a box is exact rather than conservative. RightVector, UpVector and
	LookVector are the world directions of the part's own three axes, so their
	Y components are that middle row of R, up to a sign the absolute discards.
]]
local function measureModel(model)
	local parts = {}
	local bottoms = {}

	local minY, maxY = math.huge, -math.huge

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local cf, size = descendant.CFrame, descendant.Size
			local half = 0.5 * (
				math.abs(cf.RightVector.Y) * size.X
				+ math.abs(cf.UpVector.Y) * size.Y
				+ math.abs(cf.LookVector.Y) * size.Z
			)

			local bottom = cf.Position.Y - half
			local top = cf.Position.Y + half

			table.insert(parts, descendant)
			table.insert(bottoms, bottom)

			if bottom < minY then
				minY = bottom
			end
			if top > maxY then
				maxY = top
			end
		end
	end

	if #parts == 0 then
		return nil
	end

	-- Whatever is standing on the floor, plus anything within a block or so of
	-- it. The part that owns minY always qualifies, so this is never empty.
	local baseLine = minY + BASE_BAND_BLOCKS * studSize
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge

	for index, part in ipairs(parts) do
		if bottoms[index] <= baseLine then
			local cf, size = part.CFrame, part.Size

			local halfX = 0.5 * (
				math.abs(cf.RightVector.X) * size.X
				+ math.abs(cf.UpVector.X) * size.Y
				+ math.abs(cf.LookVector.X) * size.Z
			)
			local halfZ = 0.5 * (
				math.abs(cf.RightVector.Z) * size.X
				+ math.abs(cf.UpVector.Z) * size.Y
				+ math.abs(cf.LookVector.Z) * size.Z
			)

			local position = cf.Position
			if position.X - halfX < minX then
				minX = position.X - halfX
			end
			if position.X + halfX > maxX then
				maxX = position.X + halfX
			end
			if position.Z - halfZ < minZ then
				minZ = position.Z - halfZ
			end
			if position.Z + halfZ > maxZ then
				maxZ = position.Z + halfZ
			end
		end
	end

	return minY, maxY - minY, minX, maxX, minZ, maxZ
end

--[[
	The block height a model should stand on.

	The LOWEST ground under its base, so a side that overhangs a step down is
	never left in the air - floored at `maxSink` blocks below the model's own
	column, so nothing can be swallowed by a step the footprint check would have
	refused in the first place.

	Asks the writer first and the generator second: see writer.surfaceAt for why
	those two can disagree, and why only the caller can decide that the
	generator is a good enough answer for a column in somebody else's chunk.
]]
local function seatHeight(entry, candidate, writer, minX, maxX, minZ, maxZ)
	--[[
		Anchored to the model's OWN column as this chunk will render it, not as
		the generator described it. Somebody who builds a metre of dirt under a
		tree should get a tree standing on their dirt when the chunk streams
		back, and somebody who mines the ground out from under one should get a
		tree that has come down to meet what is left.

		It is also the answer when the scan below consults nothing at all, which
		is what happens to a base narrow enough to straddle a block boundary
		without taking a real bite out of either side.
	]]
	local origin = if writer.surfaceAt then writer.surfaceAt(candidate.x, candidate.z) else nil
	if origin == nil then
		origin = candidate.surfaceY
	end

	local best = origin
	local lowest = origin - (entry.maxSink or entry.flatness or 1)

	-- Bounded by the footprint the definition declared, so a model with an
	-- unexpectedly wide base cannot turn one placement into a thousand column
	-- lookups. It is also the only region the flatness check ever vetted.
	local reach = entry.radius + 1
	local bite = BASE_BITE * studSize

	local fromX = math.max(math.floor(minX / studSize), candidate.x - reach)
	local toX = math.min(math.floor(maxX / studSize), candidate.x + reach)
	local fromZ = math.max(math.floor(minZ / studSize), candidate.z - reach)
	local toZ = math.min(math.floor(maxZ / studSize), candidate.z + reach)

	for blockX = fromX, toX do
		local overlapX = math.min(maxX, (blockX + 1) * studSize) - math.max(minX, blockX * studSize)

		if overlapX >= bite then
			for blockZ = fromZ, toZ do
				local overlapZ = math.min(maxZ, (blockZ + 1) * studSize)
					- math.max(minZ, blockZ * studSize)

				if overlapZ >= bite then
					local height = if writer.surfaceAt then writer.surfaceAt(blockX, blockZ) else nil

					-- The writer only knows its own chunk. A base that reaches
					-- across the border asks the generator for the rest, which
					-- is the right answer there until somebody edits it.
					if height == nil and options.isInWorld(blockX, blockZ) then
						height = options.getColumn(blockX, blockZ)
					end

					if height and height < best then
						best = height
					end
				end
			end
		end
	end

	return if best < lowest then lowest else best
end

local function placeModel(candidate, writer)
	local entry = candidate.entry

	local template = pickModel(
		entry,
		candidate.biome,
		candidate.variant,
		hashUnit(candidate.gx, candidate.gz, entry.index, SALT_MODEL)
	)
	if not template then
		return
	end

	local model = template:Clone()
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not primary then
		model:Destroy()
		return
	end
	model.PrimaryPart = primary

	--[[
		A little variation in size, so a stand of one model does not read as the
		same tree stamped repeatedly.

		Scaled BEFORE the model is measured, because everything below - where
		the trunk meets the ground, and how many chops it takes - is derived
		from that measurement. Measuring first and scaling after would leave
		bigger trees hovering and smaller ones buried.

		Deterministic from the candidate's own grid cell, which matters more
		here than it looks: a chunk is regenerated from scratch every time it
		streams back in, and a tree that re-rolled its size would visibly twitch
		whenever a player walked away and came back.
	]]
	local variance = entry.scaleVariance
	if variance and variance > 0 then
		local roll = hashUnit(candidate.gx, candidate.gz, entry.index, SALT_SCALE)

		-- Multiplied by the scale the model ALREADY has, not set outright.
		-- ScaleTo is absolute: a model an artist scaled to 2.5x after importing
		-- it reports GetScale() == 2.5, and ScaleTo(1.06) would discard that and
		-- shrink it back to roughly its import size. Whatever the asset was
		-- authored at is the size it should vary AROUND.
		model:ScaleTo(model:GetScale() * (1 + (roll * 2 - 1) * variance))
	end

	--[[
		Stood up first, measured second, seated third.

		The order is the whole fix. A model is measured in the orientation it
		will actually be in, so an asset whose pivot was authored at an angle -
		which is most of what "some sank and some hovered" turned out to be -
		is measured square rather than measured tilted and then squared up
		afterwards. Y is a placeholder here; the real one needs the measurement
		this pass makes possible.
	]]
	local yaw = 0
	if entry.randomYaw then
		yaw = hashUnit(candidate.gx, candidate.gz, entry.index, SALT_YAW) * math.pi * 2
	end

	local worldX = candidate.x * studSize + studSize * 0.5
	local worldZ = candidate.z * studSize + studSize * 0.5

	model:PivotTo(CFrame.new(worldX, 0, worldZ) * CFrame.Angles(0, yaw, 0))

	local minY, spanY, baseMinX, baseMaxX, baseMinZ, baseMaxZ = measureModel(model)
	if not minY then
		-- Nothing but folders and attachments. Nothing to stand on the ground.
		model:Destroy()
		return
	end

	local groundY = seatHeight(entry, candidate, writer, baseMinX, baseMaxX, baseMinZ, baseMaxZ)
		* studSize

	-- Down by a hair, never up: a model that is a fraction too low is buried by
	-- a fraction, and one that is a fraction too high is floating.
	model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - minY - SEAT_BIAS, 0))

	if entry.nameFormat then
		-- Both are passed, so a format may use either or both: "%sTree" names by
		-- biome as before, "%s%sTree" names by biome and sub-biome.
		model.Name = string.format(
			entry.nameFormat, tostring(candidate.biome), tostring(candidate.variant or "")
		)
	end

	if entry.health ~= nil then
		local health = model:FindFirstChild("Health")
		if not health or not health:IsA("IntValue") then
			health = Instance.new("IntValue")
			health.Name = "Health"
			health.Parent = model
		end
		-- Off the world-space height rather than the pivot-aligned one, so a
		-- model with a tilted pivot is no longer credited with the extra height
		-- its own tilt added to the box.
		health.Value = if entry.health == "auto"
			then math.max(1, math.ceil(spanY / (studSize * 2)))
			else math.max(1, math.floor(entry.health))
	end

	local castShadow = options.castStructureShadows
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanTouch = false
			descendant.CastShadow = castShadow
			if entry.tag then
				CollectionService:AddTag(descendant, entry.tag)
			end
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	writer.addModel(model)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	options = {
	  seed                 number,
	  chunkSize            number,
	  studSize             number,
	  assetsRoot           Instance,   -- ReplicatedStorage.TerrainAssets
	  blocksFolder         Instance,
	  castStructureShadows boolean,
	  candidateCacheLimit  number?,
	  getColumn            function(blockX, blockZ) ->
	                         height, biomeName, variantName?, waterTop?,
	                         surfaceBlock?
	                       waterTop is the block y of any standing water; a
	                       column is underwater when it exceeds height.
	                       surfaceBlock is the name of the block on top, which
	                       is what `surfaces` is checked against; a provider
	                       that does not report it simply cannot use `surfaces`.
	  isInWorld            function(blockX, blockZ) -> boolean
	  allowStructureAt     optional function(blockX, blockZ) -> boolean; a
	                       structure is only ever rooted where it says true
	}
]]
function StructureRegistry.init(opts)
	assert(type(opts) == "table", "[StructureRegistry] init needs an options table")
	assert(type(opts.getColumn) == "function", "[StructureRegistry] options.getColumn is required")
	assert(type(opts.isInWorld) == "function", "[StructureRegistry] options.isInWorld is required")

	StructureConfig.validate()

	options = opts
	chunkSize = opts.chunkSize or 16
	studSize = opts.studSize or 4
	hashSeed = (opts.seed or 0) % 4096 * 1.6180339887
	candidateCacheLimit = opts.candidateCacheLimit or 400

	-- Overlap resolution only inspects the 3x3 chunk neighbourhood around a
	-- candidate. Two candidates can conflict at most (r1 + r2) apart, so that
	-- reach must not exceed one chunk or a conflict could go unseen.
	assert(
		2 * StructureConfig.MaxRadiusBlocks <= chunkSize,
		string.format(
			"[StructureRegistry] StructureConfig.MaxRadiusBlocks (%d) is too large for "
				.. "ChunkSize %d; overlap between distant chunks could go undetected.",
			StructureConfig.MaxRadiusBlocks, chunkSize
		)
	)

	table.clear(prepared)
	StructureRegistry.clearCaches()

	if not StructureConfig.Enabled then
		isReady = true
		return
	end

	for index, def in ipairs(StructureConfig.Definitions) do
		table.insert(prepared, prepareDefinition(def, index))
	end

	isReady = true
end

--[[
	Adds a structure after init. Same schema as StructureConfig.Definitions.
	Caches are dropped so already-loaded chunks pick it up on their next load.
]]
function StructureRegistry.register(def)
	assert(isReady, "[StructureRegistry] register called before init")
	local entry = prepareDefinition(def, #prepared + 1)
	table.insert(prepared, entry)
	StructureRegistry.clearCaches()
	return entry.enabled
end

function StructureRegistry.clearCaches()
	table.clear(candidateCache)
	candidateCacheCount = 0
end

--[[
	Phase 1: terrain edits (added blocks, retextured blocks, carved holes).
	Must run before the chunk's visibility pass so the chunk renders once.
]]
function StructureRegistry.applyBlocks(cx, cz, writer)
	if not isReady or #prepared == 0 then
		return
	end

	for _, candidate in ipairs(collectRelevant(cx, cz)) do
		local entry = candidate.entry

		if entry.kind == "Blocks" then
			local context = makeContext(candidate, writer)
			for _, spec in ipairs(entry.blocks) do
				local mode = spec[5] or "add"
				if mode == "add" then
					context:setBlock(spec[1], spec[2], spec[3], spec[4])
				elseif mode == "override" then
					context:overrideBlock(spec[1], spec[2], spec[3], spec[4])
				elseif mode == "carve" then
					context:carve(spec[1], spec[2], spec[3])
				end
			end
		elseif entry.kind == "Custom" then
			entry.build(makeContext(candidate, writer))
		end
	end
end

--[[
	Phase 2: models. Only the chunk that owns a candidate's origin builds it, so
	a model is never duplicated by a neighbour.
]]
function StructureRegistry.applyModels(cx, cz, writer)
	if not isReady or #prepared == 0 then
		return
	end

	table.clear(scratchCandidates)
	for _, candidate in ipairs(getCandidates(cx, cz)) do
		if candidate.entry.kind == "Model" and isAccepted(candidate) then
			table.insert(scratchCandidates, candidate)
		end
	end

	for _, candidate in ipairs(scratchCandidates) do
		placeModel(candidate, writer)
	end
end

function StructureRegistry.getStats()
	local enabled = 0
	for _, entry in ipairs(prepared) do
		if entry.enabled then
			enabled += 1
		end
	end

	return {
		definitions = #prepared,
		enabled = enabled,
		cachedChunks = candidateCacheCount,
	}
end

return StructureRegistry
