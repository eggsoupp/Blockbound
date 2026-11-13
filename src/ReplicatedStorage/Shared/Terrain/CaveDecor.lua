--[[
	CaveDecor

	Seats each biome's decorations in the caves CaveMap carved: crystals and
	stalagmites on floors, icicles and roots from ceilings. CaveDecorConfig
	says what and how thickly; this decides where.

	  CaveDecor.init(seed)                 registers the decoration blocks
	  CaveDecor.decorate(record, minX, minZ) -> count
	  CaveDecor.blockName(segmentIndex)    -> block name
	  CaveDecor.segmentName(block, tall, s) -> block name of one segment
	  CaveDecor.stackOf(blockName)         -> segment names, which one
	  CaveDecor.isCollectible(blockName)   -> boolean

	HOW A DECORATION EXISTS

	A decoration is a block, and it is placed by NOT carving its cell: decorate
	runs on a chunk's finished carve record, takes the lowest (or highest) air
	cells of a column back out of the record's air intervals, and lists them in
	record.decor. From then on every reader of the record - the chunk builder,
	the neighbours' border faces, a support query about an unloaded chunk -
	sees a solid cell there, so nothing can disagree about it. ChunkBuilder
	gives the cell its block name; mining it is mining a block.

	WHERE

	Each floor and ceiling cell is offered to the biome's entries in order. An
	entry rolls a position hash against its density, which is full inside its
	PATCHES (a coarse hash grid of its own, so every type clusters somewhere
	different) and thin outside them. That is what makes one stretch of cave
	bristle with icicles and the next stand bare.

	Decorations never narrow a passage that is already tight: a column needs
	MinClearanceBlocks of air, a piece always leaves MinHeadroomBlocks, and a
	floor piece must stand against a wall unless the cave there is a hall. In
	a round tunnel that keeps the walking line clear.

	A pure function of (seed, position, the carved record), so a chunk is
	decorated the same way every time it streams in. Entrance columns are left
	alone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TerrainFolder = script.Parent
local TerrainConfig = require(TerrainFolder:WaitForChild("TerrainConfig"))
local CaveDecorConfig = require(TerrainFolder:WaitForChild("CaveDecorConfig"))
local BlockConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Blocks"):WaitForChild("BlockConfig")
)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local CaveDecor = {}

local CHUNK_SIZE = TerrainConfig.ChunkSize
local CHUNK_AREA = CHUNK_SIZE * CHUNK_SIZE
local HALO_SIZE = CHUNK_SIZE + 2

local MIN_CLEARANCE = CaveDecorConfig.MinClearanceBlocks
local MIN_HEADROOM = CaveDecorConfig.MinHeadroomBlocks
local OPEN_CLEARANCE = CaveDecorConfig.OpenFloorClearance
local MAX_PER_CHUNK = CaveDecorConfig.MaxPerChunk

local DIR_X = { 1, -1, 0, 0 }
local DIR_Z = { 0, 0, 1, -1 }

-- Flattened types, by index. Indices follow the sorted type names, so they
-- are the same on every server for the same config.
local typeMinHeight = {}
local typeHeightSpan = {}
local typeOpen = {}
local collectible = {} -- block name -> true

--[[
	SEGMENTS. A piece several blocks tall is ONE model cut into one-block
	segments, each its own block name, so a three-block icicle is drawn as
	one icicle rather than the same block three times. Segment s of a piece
	`tall` high is segmentName(block, tall, s), counted from the bottom; a
	one-block piece keeps the plain block name. record.decor holds segment
	indices, not type indices.
]]
local segmentBlock = {} -- segment index -> block name
local typeSegmentStart = {} -- type index -> { [tall] = index of its bottom segment }
local stackOf = {} -- block name -> { names = { bottom .. top }, segment = s }
local biomeEntries = {}

local hashSeed = 0
local isReady = false

-- Same family as CaveMap.hashUnit.
local function hashUnit(a, b, c, salt)
	local x = a * 127.1 + b * 311.7 + c * 74.7 + salt * 269.5 + hashSeed
	local y = a * 269.5 + b * 183.3 + c * 246.1 + salt * 113.5 + hashSeed
	local v = math.sin(x) * 43758.5453 + math.sin(y) * 28001.8384
	return v - math.floor(v)
end

--[[
	Which entry of `list`, if any, claims the cell (x, y, z) at `depth` blocks
	below the surface. Returns the type index and a second uniform number for
	the piece's height, or nil.
]]
local function pick(list, x, y, z, depth)
	for i = 1, #list do
		local entry = list[i]
		if depth >= entry.minDepth and depth <= entry.maxDepth then
			local roll = hashUnit(x, y, z, entry.salt)
			-- Most cells fail even the in-patch density, and never pay for
			-- the patch lookup.
			if roll < entry.density then
				local inv = entry.invPatch
				local inPatch = hashUnit(math.floor(x * inv), math.floor(y * inv), math.floor(z * inv), entry.salt + 1)
					< entry.coverage
				local threshold = if inPatch then entry.density else entry.sparse
				if roll < threshold then
					return entry.type, roll / threshold
				end
			end
		end
	end
	return nil
end

local function intervalsContain(intervals, by)
	for i = 1, #intervals, 2 do
		if by >= intervals[i] and by <= intervals[i + 1] then
			return true
		end
	end
	return false
end

-- Is any of the four columns round (bx, bz) solid at row `by`? Reads the
-- columns as carved (record.raw), so the answer does not depend on which
-- cells were decorated first, and the ring outside the chunk from the halo.
local function againstWall(record, bx, bz, by)
	local cells, raw, halo = record.cells, record.raw, record.halo
	for d = 1, 4 do
		local nbx, nbz = bx + DIR_X[d], bz + DIR_Z[d]
		local intervals
		if nbx >= 0 and nbx < CHUNK_SIZE and nbz >= 0 and nbz < CHUNK_SIZE then
			local cell = nbx * CHUNK_SIZE + nbz + 1
			intervals = raw[cell] or cells[cell]
		else
			intervals = halo[(nbx + 1) * HALO_SIZE + (nbz + 1) + 1]
		end
		if intervals == nil or not intervalsContain(intervals, by) then
			return true
		end
	end
	return false
end

--[[
	Decorates one chunk's carve record in place. Returns how many decoration
	blocks it placed (record.decorCount). minX / minZ are the chunk's first
	block column.
]]
function CaveDecor.decorate(record, minX, minZ)
	if not isReady or MAX_PER_CHUNK <= 0 then
		return 0
	end

	local cells = record.cells
	local biomes, ground, entrance, raw = record.biome, record.ground, record.entrance, record.raw
	local decor = record.decor
	local write = 0
	local placed = 0

	-- Ascending cells, not pairs: the per-chunk cap must fall on the same
	-- cells every time.
	for cell = 1, CHUNK_AREA do
		if placed >= MAX_PER_CHUNK then
			break
		end

		local intervals = cells[cell]
		local lists = intervals and not entrance[cell] and biomeEntries[biomes[cell]]
		if lists then
			local index = cell - 1
			local bx, bz = index // CHUNK_SIZE, index % CHUNK_SIZE
			local x, z = minX + bx, minZ + bz
			local height = ground[cell]

			for i = 1, #intervals, 2 do
				local lo, hi = intervals[i], intervals[i + 1]
				local clearance = hi - lo + 1
				if clearance >= MIN_CLEARANCE then
					-- Blocks of this column's air decorations may take.
					local room = clearance - MIN_HEADROOM

					local kind, roll = pick(lists.floor, x, lo, z, height - lo)
					if kind and (typeOpen[kind] or clearance >= OPEN_CLEARANCE or againstWall(record, bx, bz, lo)) then
						local tall = typeMinHeight[kind] + math.floor(roll * typeHeightSpan[kind])
						if tall > room then
							tall = room
						end
						if raw[cell] == nil then
							raw[cell] = table.clone(intervals)
						end
						local segment = typeSegmentStart[kind][tall] - lo
						for by = lo, lo + tall - 1 do
							decor[write + 1] = cell
							decor[write + 2] = by
							decor[write + 3] = segment + by
							write += 3
						end
						intervals[i] = lo + tall
						room -= tall
						placed += tall
					end

					if room >= 1 then
						kind, roll = pick(lists.ceiling, x, hi, z, height - hi)
						if kind then
							local tall = typeMinHeight[kind] + math.floor(roll * typeHeightSpan[kind])
							if tall > room then
								tall = room
							end
							if raw[cell] == nil then
								raw[cell] = table.clone(intervals)
							end
							local bottom = hi - tall + 1
							local segment = typeSegmentStart[kind][tall] - bottom
							for by = bottom, hi do
								decor[write + 1] = cell
								decor[write + 2] = by
								decor[write + 3] = segment + by
								write += 3
							end
							intervals[i + 1] = hi - tall
							placed += tall
						end
					end
				end
			end
		end
	end

	record.decorCount = placed
	record.blocks -= placed
	return placed
end

-- The block name of a record.decor entry (a segment index).
function CaveDecor.blockName(segmentIndex)
	return segmentBlock[segmentIndex]
end

-- Segment s (1 = bottom) of a piece `tall` blocks high. The voxel models in
-- assets/voxel-cave-decor are cut and named the same way.
function CaveDecor.segmentName(block, tall, segment)
	if tall == 1 then
		return block
	end
	return block .. tall .. "_" .. segment
end

--[[
	The piece a decoration block belongs to: its segments' block names from
	the bottom up, and which of them this one is. nil for anything that is
	not a decoration. Breaking one segment takes the whole piece (BlockEdits),
	so no half icicle is left hanging.
]]
function CaveDecor.stackOf(blockName)
	local stack = stackOf[blockName]
	if stack then
		return stack.names, stack.segment
	end
	return nil
end

-- Does mining this block yield an item? Those are remembered once taken
-- (OreDepletion), so a regrown chunk does not hand them out again.
function CaveDecor.isCollectible(blockName)
	return collectible[blockName] == true
end

function CaveDecor.isReady()
	return isReady
end

--[[
	Reads CaveDecorConfig, tells BlockConfig about every decoration block (its
	stand-in look, what it drops, how hard it is, that it is never merged) and
	flattens the biome lists. Must run before the terrain builds its block
	templates. Safe to call again to reseed.
]]
function CaveDecor.init(seed)
	CaveDecorConfig.validate()

	hashSeed = ((seed or 0) % 4096) * 1.7320508076
	table.clear(segmentBlock)
	table.clear(typeSegmentStart)
	table.clear(stackOf)
	table.clear(typeMinHeight)
	table.clear(typeHeightSpan)
	table.clear(typeOpen)
	table.clear(collectible)
	table.clear(biomeEntries)
	isReady = false

	if not CaveDecorConfig.Enabled then
		return
	end

	local names = {}
	for name in pairs(CaveDecorConfig.Types) do
		names[#names + 1] = name
	end
	table.sort(names)

	local indexOf = {}
	for index, name in ipairs(names) do
		local def = CaveDecorConfig.Types[name]
		indexOf[name] = index
		typeMinHeight[index] = def.height.min
		typeHeightSpan[index] = def.height.max - def.height.min + 0.999
		typeOpen[index] = def.open == true

		local drop = def.drop
		if drop and not ItemDefinitions[drop] then
			warn(string.format(
				"[CaveDecor] '%s' drops '%s', which is not in ItemDefinitions; it will drop nothing.",
				name, tostring(drop)
			))
			drop = false
		end
		-- Every height from 1, not just from height.min: decorate shortens a
		-- piece that would block the passage.
		local starts = {}
		typeSegmentStart[index] = starts
		for tall = 1, def.height.max do
			starts[tall] = #segmentBlock + 1
			local names = {}
			for segment = 1, tall do
				local blockName = CaveDecor.segmentName(def.block, tall, segment)
				segmentBlock[#segmentBlock + 1] = blockName
				names[segment] = blockName
				stackOf[blockName] = { names = names, segment = segment }
				if drop then
					collectible[blockName] = true
				end

				-- The stand-in until TerrainAssets.Blocks holds its voxel art.
				BlockConfig.registerGenerated(blockName, def.placeholder)
				BlockConfig.registerBlock(blockName, {
					drop = drop,
					breakSeconds = def.breakSeconds,
					power = def.power,
					unmerged = true,
				})

				-- Anything see-through or walk-through is not an ordinary solid cube.
				local transparency = def.placeholder.transparency or 0
				if def.passable or transparency > 0 then
					BlockConfig.registerSurface(blockName, {
						collides = not def.passable,
						transparency = transparency,
						query = true,
					})
				end
			end
		end
	end

	local multiplier = CaveDecorConfig.DensityMultiplier
	local sparse = CaveDecorConfig.SparseFactor
	for biome, entries in pairs(CaveDecorConfig.Biomes) do
		local lists = { floor = {}, ceiling = {} }
		for order, entry in ipairs(entries) do
			local def = CaveDecorConfig.Types[entry.type]
			local density = math.min(1, entry.density * multiplier)
			local list = lists[def.anchor]
			list[#list + 1] = {
				type = indexOf[entry.type],
				density = density,
				sparse = density * sparse,
				invPatch = 1 / entry.patchBlocks,
				coverage = entry.patchCoverage,
				minDepth = entry.minDepth or 0,
				maxDepth = entry.maxDepth or math.huge,
				-- Per type, not per biome entry, so one type's patches line up
				-- across a biome border; the order term separates two entries
				-- of the same type.
				salt = 5000 + indexOf[entry.type] * 16 + (order - 1) * 2,
			}
		end
		biomeEntries[biome] = lists
	end

	isReady = true
end

return CaveDecor
