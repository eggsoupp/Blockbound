--[[
	BlockParts

	Everything about the Parts that draw blocks: the authored templates (and
	stand-ins for missing ones), the face-variant templates new Parts are
	cloned from, the per-name part pools, and which rectangle each live Part
	is drawing (partRect). Part of TerrainManager; see TerrainManager for the
	map of terrain modules.

	Owns the rendered/pooled part counters (BlockParts.counts), maintained at
	the two places parts enter and leave play.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local BiomeConfig = require(TerrainShared:WaitForChild("BiomeConfig"))
local StrataConfig = require(TerrainShared:WaitForChild("StrataConfig"))
local OreRegistry = require(TerrainShared:WaitForChild("OreRegistry"))
local LandformConfig = require(TerrainShared:WaitForChild("LandformConfig"))
local BlockConfig = require(Shared:WaitForChild("Blocks"):WaitForChild("BlockConfig"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local BlockParts = {}

local STUD_SIZE = TerrainConfig.StudSize
local WATER_BLOCK = LandformConfig.WaterBlock
local BEDROCK_BLOCK = StrataConfig.BedrockBlock

-- ---------------------------------------------------------------------------
-- Assets
-- ---------------------------------------------------------------------------

--[[
	Waited for with a limit. These are authored assets, and assets get lost:
	waiting forever here froze terrain and, through it, mining, crafting,
	harvesting, enemies and abilities - a whole server stalled by one missing
	folder, with nothing on screen saying why. Without them the world is drawn
	from plain stand-ins (see resolveTemplateName) and Output says what to add.
]]
local ASSET_WAIT_SECONDS = 10

local function assetFolder(parent: Instance, name: string): Instance
	local folder = parent:WaitForChild(name, ASSET_WAIT_SECONDS)
	if folder then
		return folder
	end

	warn(string.format(
		"[TerrainManager] %s.%s is missing, so every block is drawn as a plain stand-in. "
			.. "Put the block parts back in ReplicatedStorage.TerrainAssets.Blocks.",
		parent:GetFullName(), name
	))
	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local TerrainAssets = assetFolder(ReplicatedStorage, "TerrainAssets")
local BlocksFolder = assetFolder(TerrainAssets, "Blocks")
BlockParts.TerrainAssets = TerrainAssets
BlockParts.BlocksFolder = BlocksFolder

local partPool = {} -- blockName -> array of parts
-- blockName -> fewest parts left in that pool since the last trim. Parts below
-- that line were never needed during the interval, which is what makes them
-- safe to release; see trimPoolsIfNeeded.
local poolLowWater = {}
local lastPoolTrim = 0

local resolvedTemplateName = {}
local resolvedTemplatePart = {}

-- Running totals, maintained at the two places parts enter and leave play.
-- Counting them on demand meant walking every cell of every loaded chunk, which
-- is fine for a chat command and far too expensive to sample once a second
-- during a benchmark.
local counts = { rendered = 0, pooled = 0 }
BlockParts.counts = counts

--[[
	Which blocks a rendered part is currently drawing.

	One part no longer means one block: the mesher collapses a run of identical
	neighbouring blocks into a single elongated Part, so this records the
	RECTANGLE a part covers - chunk, minimum corner, extent and layer - rather
	than a single cell.

	Weak-keyed, and cleared by releasePart on the way back to the pool, so an
	entry can never outlive the part or describe a part that has since been
	reused for something else.

	This replaces the six SetAttribute calls the original renderer made on every
	part it placed. Attributes replicate to every client, so those were pure
	network cost for data only the server reads.
]]
local partRect = setmetatable({}, { __mode = "k" })
BlockParts.partRect = partRect

--[[
	Per-Part face state, shared with FaceCulling (which fills in the culling
	half under HIDDEN FACES). One table rather than a run of locals.

	textures: part -> { [NormalId name] = { face images } }, every image the
	part owns, whether it is showing it or not.
]]
local Faces = { textures = setmetatable({}, { __mode = "k" }) }
BlockParts.Faces = Faces

-- ---------------------------------------------------------------------------
-- Block templates and part pooling
-- ---------------------------------------------------------------------------

--[[
	Builds a stand-in part for a block that has no authored asset - bedrock and
	the ores, unless someone drops real parts into TerrainAssets.Blocks, in which
	case those win and this never runs for that name.

	Cloned from an existing block so it inherits the project's block size and
	surface settings rather than inventing its own.
]]
local function buildGeneratedTemplate(name, description)
	local donor = BlocksFolder:FindFirstChild("Stone")
		or BlocksFolder:FindFirstChildWhichIsA("BasePart")

	local part
	if donor and donor:IsA("BasePart") then
		part = donor:Clone()
		-- Decals from the donor would show the wrong texture on the new block.
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("Decal") or child:IsA("Texture") then
				child:Destroy()
			end
		end
	else
		part = Instance.new("Part")
		part.Size = Vector3.new(STUD_SIZE, STUD_SIZE, STUD_SIZE)
	end

	part.Name = name
	part.Color = description.color or Color3.fromRGB(120, 120, 120)
	part.Material = description.material or Enum.Material.Rock
	part.Reflectance = description.reflectance or 0
	part.Transparency = description.transparency or 0
	part.Anchored = true
	part.Parent = BlocksFolder

	return part
end

--[[
	Makes sure every block name the configs can produce has a template, building
	stand-ins for the ones that do not. Runs once at Init.
]]
local function ensureGeneratedTemplates()
	for name, description in pairs(BlockConfig.Generated) do
		if not BlocksFolder:FindFirstChild(name) then
			buildGeneratedTemplate(name, description)
		end
	end
end

--[[
	Reports what the block templates carry on their faces, and converts Decals
	into tiled Textures so runs of blocks can be merged.

	WHY THIS DECIDES WHETHER MERGING WORKS AT ALL

	A Decal STRETCHES to fill whatever face it is on. A Texture TILES, at
	StudsPerTile. On a single 4-stud cube the two are indistinguishable - one
	image, one face - which is why authored blocks are often either. On a Part
	stretched across ten blocks they are completely different: the Decal smears
	one image over the whole run, the Texture repeats ten times and looks
	exactly like ten cubes.

	So a Decal is unmergeable, and a block world made of Decals cannot be meshed
	at all. Converting is lossless on the cube it started as - same image, same
	face, same colour, same transparency, one tile per block - and is what makes
	the run version correct.

	The count is printed once, because "what is on my block faces" turned out to
	be the single most load-bearing fact about this renderer and it is not
	visible from anywhere in the source: the templates live in the place file.
]]
local function normaliseBlockFaces()
	local textures, decals, converted = 0, 0, 0

	local function visit(part)
		for _, child in ipairs(part:GetChildren()) do
			-- Temper the vivid grass-top artwork without desaturating other blocks.
			-- Apply before conversion so merged terrain inherits the same tint.
			if child:IsA("Decal") and child.Texture == "rbxassetid://92680494635879" then
				child.Color3 = Color3.fromRGB(205, 170, 145)
			end
			-- ClassName rather than IsA, because Texture derives from Decal.
			if child.ClassName == "Texture" then
				textures += 1
				child.StudsPerTileU = STUD_SIZE
				child.StudsPerTileV = STUD_SIZE
			elseif child.ClassName == "Decal" then
				decals += 1

				if TerrainConfig.ConvertDecalsToTextures then
					local texture = Instance.new("Texture")
					texture.Name = child.Name
					texture.Texture = child.Texture
					texture.Face = child.Face
					texture.Color3 = child.Color3
					texture.Transparency = child.Transparency
					texture.StudsPerTileU = STUD_SIZE
					texture.StudsPerTileV = STUD_SIZE
					texture.Parent = part

					child:Destroy()
					converted += 1
				end
			end
		end
	end

	for _, template in ipairs(BlocksFolder:GetChildren()) do
		if template:IsA("BasePart") then
			visit(template)
		elseif template:IsA("Model") then
			for _, descendant in ipairs(template:GetDescendants()) do
				if descendant:IsA("BasePart") then
					visit(descendant)
				end
			end
		end
	end

	print(string.format(
		"[TerrainManager] Block faces: %d texture(s), %d decal(s), %d converted to tiled textures.",
		textures, decals, converted
	))

	if decals > converted then
		warn(
			"[TerrainManager] Some block faces are still Decals. Decals cannot tile, so those "
				.. "blocks are drawn one Part per block and will hold the merge ratio down. Set "
				.. "TerrainConfig.ConvertDecalsToTextures = true to convert them."
		)
	end
end

local function resolveTemplateName(requested)
	local cached = resolvedTemplateName[requested]
	if cached ~= nil then
		return cached
	end

	if BlocksFolder:FindFirstChild(requested) then
		resolvedTemplateName[requested] = requested
		return requested
	end

	for _, fallbackName in ipairs(TerrainConfig.BlockFallbackOrder) do
		-- Never water for a solid block: water is always generated, so with no
		-- authored blocks at all every missing block would become a sea you
		-- fall straight through.
		if fallbackName ~= WATER_BLOCK and BlocksFolder:FindFirstChild(fallbackName) then
			warn(string.format(
				"[TerrainManager] Missing block template '%s'; using '%s'.",
				tostring(requested), fallbackName
			))
			resolvedTemplateName[requested] = fallbackName
			return fallbackName
		end
	end

	-- Nothing authored to borrow, so a plain grey block under the right name:
	-- solid, mineable and visibly a stand-in, rather than a hole in the world.
	if type(requested) == "string" and requested ~= "" then
		warn(string.format(
			"[TerrainManager] Missing block template '%s' and no fallback; drawing a grey stand-in.",
			requested
		))
		buildGeneratedTemplate(requested, {})
		resolvedTemplateName[requested] = requested
		return requested
	end

	resolvedTemplateName[requested] = false
	return false
end

local function getBlockPartTemplate(name)
	local actualName = resolveTemplateName(name)
	if not actualName then
		return nil
	end

	local cached = resolvedTemplatePart[actualName]
	if cached then
		return cached
	end

	local template = BlocksFolder:FindFirstChild(actualName)
	if template and template:IsA("BasePart") then
		resolvedTemplatePart[actualName] = template
		return template
	end

	if template and template:IsA("Model") then
		local part = template.PrimaryPart or template:FindFirstChildWhichIsA("BasePart")
		if part then
			resolvedTemplatePart[actualName] = part
			return part
		end
	end

	warn(string.format(
		"[TerrainManager] Block template '%s' is not a usable part/model.",
		tostring(actualName)
	))
	return nil
end

--[[
	FACE VARIANTS

	A block template is a Part with an image on each of its six faces: seven
	Instances. Cloning all seven for every new Part and then taking most of the
	images off again (see HIDDEN FACES - about 60% of faces are covered) was the
	largest single cost of drawing a chunk: 56 microseconds for the clone and 9
	more to unparent four images, against 17 for the bare Part.

	So a new Part is cloned from a template that already carries exactly the
	images it is going to show. There is one such template per block name and
	face mask, built the first time that combination is asked for and kept out
	of the world. An image a Part was not born with is cloned onto it later, if
	that face is ever uncovered (Faces.apply).

	The mask is one bit per face, Faces.BIT. Faces.shown[part] is the mask a
	Part currently shows, so re-deciding a Part whose faces have not changed
	touches no Instance at all.
]]
do
	local FACE_BIT = { Top = 1, Bottom = 2, Right = 4, Left = 8, Back = 16, Front = 32 }
	Faces.BIT = FACE_BIT
	Faces.shown = setmetatable({}, { __mode = "k" })
	-- name -> { [face name] = { image templates } }, every image the block has.
	Faces.images = {}
	Faces.layouts = {} -- variant template -> face name per child, in order

	local bases = {} -- name -> the configured Part with no images; false if none
	local variants = {} -- name -> { [mask] = template }

	local function baseFor(name)
		local base = bases[name]
		if base ~= nil then
			return base
		end

		local template = getBlockPartTemplate(name)
		if not template then
			bases[name] = false
			Faces.images[name] = {}
			return false
		end

		--[[
			Most blocks are solid opaque cubes and are forced to be, because an
			authored template can carry anything. The exceptions are declared in
			BlockConfig.Surfaces - water being the whole reason it exists: it has to
			be see-through so the bed reads through it, non-solid so a player wades
			instead of walking on it, and invisible to the mouse ray so aiming at a
			shoreline targets the ground rather than the surface.

			Set once per block name: every clone inherits all of it, tag included.
		]]
		local surface = BlockConfig.surfaceFor(name)

		base = template:Clone()
		base.Name = name
		base.Size = Vector3.new(STUD_SIZE, STUD_SIZE, STUD_SIZE)
		base.Anchored = true
		base.CanCollide = if surface then surface.collides ~= false else true
		base.CanQuery = if surface then surface.query ~= false else true
		base.CanTouch = false
		base.Transparency = if surface then surface.transparency or 0 else 0
		base.TopSurface = Enum.SurfaceType.Smooth
		base.BottomSurface = Enum.SurfaceType.Smooth
		base.CastShadow = TerrainConfig.CastTerrainShadows
		CollectionService:AddTag(base, "TerrainBlock")

		local byFace = {}
		for _, child in ipairs(base:GetChildren()) do
			-- Pin every face texture to one tile per block, so a part stretched
			-- over a run of ten blocks shows ten tiles instead of one smeared
			-- image. On a 1x1 part this is exactly what an untiled texture
			-- already did, so it changes nothing for blocks that never merge.
			if child:IsA("Texture") then
				child.StudsPerTileU = STUD_SIZE
				child.StudsPerTileV = STUD_SIZE
			end
			-- Decal covers Texture too.
			if child:IsA("Decal") then
				local face = child.Face.Name
				local list = byFace[face]
				if not list then
					list = {}
					byFace[face] = list
				end
				table.insert(list, child)
				child.Parent = nil
			end
		end

		bases[name] = base
		Faces.images[name] = byFace
		return base
	end

	-- The template for `name` showing exactly the faces in `mask`, or false.
	function Faces.variantFor(name, mask)
		local set = variants[name]
		if not set then
			set = {}
			variants[name] = set
		end

		local variant = set[mask]
		if variant == nil then
			local base = baseFor(name)
			if not base then
				set[mask] = false
				return false
			end

			variant = base:Clone()
			for face, list in pairs(Faces.images[name]) do
				if bit32.btest(mask, FACE_BIT[face]) then
					for _, image in ipairs(list) do
						image:Clone().Parent = variant
					end
				end
			end
			set[mask] = variant

			-- Which face each child is an image for, in child order, so a clone
			-- can file its images without reading a property off each one.
			-- Checked against a real clone once; a template whose clone came
			-- back in another order gets no layout and is read the slow way.
			local layout = {}
			for index, child in ipairs(variant:GetChildren()) do
				layout[index] = if child:IsA("Decal") then child.Face.Name else false
			end
			for index, child in ipairs(variant:Clone():GetChildren()) do
				if layout[index] ~= (if child:IsA("Decal") then child.Face.Name else false) then
					layout = nil
					break
				end
			end
			Faces.layouts[variant] = layout
		end

		return variant
	end

	-- Files a fresh clone's images under their faces, for Faces.apply.
	function Faces.adopt(part, variant, mask)
		local faces = {}
		if mask ~= 0 then
			local layout = Faces.layouts[variant]
			for index, child in ipairs(part:GetChildren()) do
				local face
				if layout then
					face = layout[index]
				elseif child:IsA("Decal") then
					face = child.Face.Name
				end
				if face then
					local list = faces[face]
					if list then
						list[#list + 1] = child
					else
						faces[face] = { child }
					end
				end
			end
		end
		Faces.textures[part] = faces
		Faces.shown[part] = mask
	end
end

-- `mask` is the faces a NEW Part should be born showing (see FACE VARIANTS). A
-- Part out of the pool shows whatever it last did; Faces.apply corrects it.
local function getPooledPart(name, mask)
	local pool = partPool[name]
	if pool then
		local count = #pool
		if count > 0 then
			local part = pool[count]
			pool[count] = nil
			counts.pooled -= 1

			local remaining = count - 1
			local low = poolLowWater[name]
			if low == nil or remaining < low then
				poolLowWater[name] = remaining
			end

			Profiler.count("Terrain.partReused")
			return part
		end
	end

	mask = mask or 63
	local variant = Faces.variantFor(name, mask)
	if not variant then
		return nil
	end

	local part = variant:Clone()
	Faces.adopt(part, variant, mask)

	Profiler.count("Terrain.partCloned")
	return part
end

--[[
	Returns a part to its pool.
]]
local function releasePart(part)
	if not part then
		return
	end

	part.Parent = nil
	partRect[part] = nil
	counts.rendered -= 1

	local name = part.Name
	local pool = partPool[name]
	if not pool then
		pool = {}
		partPool[name] = pool
		-- A brand new pool has never been drawn from, so nothing is provably
		-- surplus yet. Starting at zero buys it one interval of grace before
		-- the trim starts measuring it.
		poolLowWater[name] = 0
	end

	if #pool < TerrainConfig.MaxPoolPerType then
		pool[#pool + 1] = part
		counts.pooled += 1
	else
		part:Destroy()
		Profiler.count("Terrain.partDestroyed")
	end
end

--[[
	Shrinks the pools toward recent demand.

	A pool exists to absorb the gap between parts being released (a chunk
	unloading) and re-acquired (the next chunk loading). How wide that gap gets
	is a property of how the player is moving, which no fixed number can know -
	so this measures it instead of guessing.

	LOW WATER MARK. Every acquire records how few parts of that type were left
	behind. The smallest value seen across an interval is the number that sat
	untouched for the whole interval: nothing needed them, so they are surplus.
	Half the surplus is released each pass, which decays an idle pool
	geometrically while leaving a busy one - whose low water sits near zero -
	completely alone.

	This replaces trimming to a flat MaxPoolPerType, which never actually fired:
	releasePart already refuses to grow a pool past that cap, so the old trim
	could only ever find work if the cap had been lowered at runtime. The pools
	therefore only ever grew, and a session that had visited a snow biome kept
	its snow parts for the rest of the server's life.

	Bounded per pass, because destroying a few hundred Parts inside one frame is
	exactly the sort of spike the rest of this file works to avoid.
]]
local function trimPoolsIfNeeded()
	local now = os.clock()
	if now - lastPoolTrim < TerrainConfig.PoolTrimInterval then
		return
	end
	lastPoolTrim = now

	local hardLimit = TerrainConfig.MaxPoolPerType
	local floorSize = TerrainConfig.MinPoolPerType
	local fraction = TerrainConfig.PoolTrimFraction
	local budget = TerrainConfig.PoolTrimMaxPerTick

	for name, pool in pairs(partPool) do
		local size = #pool
		local target = size

		if target > hardLimit then
			target = hardLimit
		end

		local surplus = (poolLowWater[name] or 0) - floorSize
		if surplus > 0 then
			local shrunk = size - math.ceil(surplus * fraction)
			if shrunk < target then
				target = shrunk
			end
		end

		if target < floorSize then
			target = floorSize
		end

		while size > target and budget > 0 do
			local part = pool[size]
			pool[size] = nil
			size -= 1
			counts.pooled -= 1
			budget -= 1
			if part then
				part:Destroy()
			end
			Profiler.count("Terrain.partTrimmed")
		end

		-- Restart the measurement from where the pool now stands, so the next
		-- interval reports its own idleness rather than inheriting this one's.
		poolLowWater[name] = size

		if budget <= 0 then
			break
		end
	end
end

local function warnForMissingTemplates()
	local seen = {}
	local missing = {}

	local function check(name)
		if name and not seen[name] then
			seen[name] = true
			if not BlocksFolder:FindFirstChild(name) then
				table.insert(missing, name)
			end
		end
	end

	for _, name in ipairs(TerrainConfig.BlockFallbackOrder) do
		check(name)
	end
	for _, biomeName in ipairs(BiomeConfig.Order) do
		local def = BiomeConfig.Definitions[biomeName]
		check(def.topBlock)
		check(def.underBlock)
	end
	for _, name in ipairs(OreRegistry.getBlockNames()) do
		check(name)
	end
	check(BEDROCK_BLOCK)
	check(StrataConfig.getDeepBlock())

	-- The surface blocks altitude can substitute for a biome's own, and the
	-- water. None of these belongs to any one biome, so nothing above catches
	-- them if that biome is ever removed.
	check(LandformConfig.RockBlock)
	check(LandformConfig.SnowBlock)
	check(WATER_BLOCK)

	if #missing > 0 then
		warn("[TerrainManager] Missing block templates: " .. table.concat(missing, ", "))
	end
end

-- ---------------------------------------------------------------------------
-- Meshing
-- ---------------------------------------------------------------------------

--[[
	Can a run of this block be drawn as one stretched Part?

	A Texture tiles - StudsPerTile is set to one block when the part is built,
	so a 10-block run reads as ten tiles and looks identical to ten cubes. A
	Decal does NOT tile; it stretches to fit whatever face it is on, so spreading
	one across a run would smear a single image over the whole thing. Those
	blocks fall back to one Part each.

	Cached: it is a property of the template, and the answer is needed once per
	emitted rectangle.
]]
local mergeableByName = {}

local function isMergeable(blockName)
	local cached = mergeableByName[blockName]
	if cached ~= nil then
		return cached
	end

	local mergeable = true
	local template = getBlockPartTemplate(blockName)
	if template then
		-- Stretching a wedge, sphere, or authored mesh across a rectangle
		-- creates slivers and uncovered cells. Only full cubes can tile it.
		mergeable = template:IsA("Part") and template.Shape == Enum.PartType.Block
		for _, child in ipairs(template:GetChildren()) do
			-- ClassName, NOT IsA. Texture derives from Decal in Roblox, so
			-- IsA("Decal") is true for a Texture as well - which marked every
			-- textured block in the game unmergeable and pinned the merge ratio
			-- at exactly 1.00. A ratio of precisely 1 is what gave it away: real
			-- terrain would have produced some ragged fraction.
			if child.ClassName == "Decal" or child:IsA("DataModelMesh") then
				mergeable = false
				break
			end
		end
	end

	mergeableByName[blockName] = mergeable
	return mergeable
end

--[[
	Destroys every pooled Part (benchmark cold starts; see TerrainManager:_FlushAll).
]]
local function dropPools()
	for name, pool in pairs(partPool) do
		for i = #pool, 1, -1 do
			local part = pool[i]
			pool[i] = nil
			if part then
				part:Destroy()
			end
		end
		partPool[name] = nil
		poolLowWater[name] = nil
	end
	counts.pooled = 0
end

BlockParts.ensureGeneratedTemplates = ensureGeneratedTemplates
BlockParts.normaliseBlockFaces = normaliseBlockFaces
BlockParts.getBlockPartTemplate = getBlockPartTemplate
BlockParts.getPooledPart = getPooledPart
BlockParts.releasePart = releasePart
BlockParts.trimPoolsIfNeeded = trimPoolsIfNeeded
BlockParts.warnForMissingTemplates = warnForMissingTemplates
BlockParts.isMergeable = isMergeable
BlockParts.dropPools = dropPools

return BlockParts
