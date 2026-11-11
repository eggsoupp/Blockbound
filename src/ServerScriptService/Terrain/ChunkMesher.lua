--[[
	ChunkMesher

	Turns what each column wants drawn (data.visible) into Parts: records
	visible blocks and dirty layers, plans each dirty layer into merged
	rectangles reusing the Parts that already draw them, and applies the plans
	new-before-old so nothing flickers. Part of TerrainManager; see
	TerrainManager for the map of terrain modules.

	Owns the visible-block counter (ChunkMesher.visibleBlocks).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))
local TerrainMesher = require(TerrainShared:WaitForChild("TerrainMesher"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local BlockParts = require(script.Parent:WaitForChild("BlockParts"))
local FaceCulling = require(script.Parent:WaitForChild("FaceCulling"))

local ChunkMesher = {}

local STUD_SIZE = TerrainConfig.StudSize
local CHUNK_SIZE = TerrainConfig.ChunkSize
local CHUNK_AREA = TerrainGrid.CHUNK_AREA
local RETIRE_SECONDS = TerrainConfig.EditZone.RetireSeconds

--[[
	Inlinable copies of TerrainGrid helpers, on purpose. Luau's optimiser only
	inlines a `local function` defined in the same script, and these run per
	block in the visibility and face passes; calling TerrainGrid's versions
	across modules measured ~10% slower there. Keep them identical to
	TerrainGrid (the canonical definitions).
]]
local function cellOf(bx, bz)
	return bx * CHUNK_SIZE + bz + 1
end
local getPooledPart = BlockParts.getPooledPart
local releasePart = BlockParts.releasePart
local isMergeable = BlockParts.isMergeable
local partRect = BlockParts.partRect
local partCounts = BlockParts.counts
local maskFor = FaceCulling.maskFor
local applyFaces = FaceCulling.apply
local showFaces = FaceCulling.show
local processFaceChanges = FaceCulling.processChanges

-- How many BLOCKS are currently drawn, as opposed to how many Parts draw them.
-- The ratio between the two is the merge ratio, and it is the single number that
-- says whether meshing is earning its complexity in this world.
local visibleBlocks = 0

--[[
	Emits one rectangle of identical blocks as a single Part.

	sizeX / sizeZ are in blocks. A 1x1 rectangle is exactly the cube the old
	renderer drew, so the unmerged mode costs nothing extra here.
]]
local function emitMeshPart(data, bx, bz, sizeX, sizeZ, by, blockName)
	local rect = {
		cx = data.cx,
		cz = data.cz,
		bx = bx,
		bz = bz,
		sizeX = sizeX,
		sizeZ = sizeZ,
		by = by,
		name = blockName,
	}

	-- Decided first, from the block data alone, so a new Part can be cloned
	-- already carrying exactly these faces. See FACE VARIANTS.
	local mask = maskFor(data, rect)

	local part = getPooledPart(blockName, mask)
	if not part then
		return nil
	end

	-- (Its Name is already blockName: pools and templates are per block name.)
	part.Size = Vector3.new(sizeX * STUD_SIZE, STUD_SIZE, sizeZ * STUD_SIZE)
	part.CFrame = CFrame.new(
		(data.minBlockX + bx) * STUD_SIZE + sizeX * STUD_SIZE * 0.5,
		by * STUD_SIZE + STUD_SIZE * 0.5,
		(data.minBlockZ + bz) * STUD_SIZE + sizeZ * STUD_SIZE * 0.5
	)

	partRect[part] = rect

	-- Before it is in the world, so a client never receives a covered face. A
	-- fresh clone already matches; one out of the pool is corrected here.
	applyFaces(part, blockName, mask)

	part.Parent = data.model
	partCounts.rendered += 1

	Profiler.count("Terrain.partPlaced")
	return part
end

-- Scratch, reused across every layer of every chunk. Meshing never yields, so
-- nothing can observe these half-written.
local layerGrid = {}
local layerRects = {}

-- The mesher's rectangles after decalled blocks have been split back into
-- cubes: five entries each, same layout as layerRects.
local finalRects = {}

local function rectKey(bx, bz, sizeX, sizeZ)
	-- Sizes run 1..ChunkSize, so 32 leaves room; bx/bz are 0..ChunkSize-1.
	return ((bx * CHUNK_SIZE + bz) * 32 + sizeX) * 32 + sizeZ
end

local function markLayerDirty(data, by)
	if not data.dirtyLayers[by] then
		data.dirtyLayers[by] = true
		data.dirtyCount += 1
	end
end

--[[
	Works out how one Y layer of a chunk should be drawn, without touching any
	Part yet - applyLayerPlans does that, for every layer of an edit at once.

	A Part already drawing EXACTLY one of the new rectangles is kept, untouched.
	Every other rectangle gets a new Part. Existing Parts are never moved or
	resized: a Part moving under a client is visible as jitter, and shrinking a
	slab before the pieces replacing it have arrived opens a hole.

	A Part nothing wants any more is either released at once - when none of
	the ground it covered is still drawn (a mined block) - or RETIRED: left in
	place a moment longer because the ground it covers is still there and the
	Parts now drawing it are new and may not have reached every client yet.
]]
local function planLayer(data, by)
	table.clear(layerGrid)

	local visible = data.visible
	local hot = data.hot

	-- cell -> name of every block drawn on this layer, zone or not, for
	-- deciding below whether an old Part still covers anything.
	local drawn = {}
	local hotCells = {}

	for cell = 1, CHUNK_AREA do
		local name = visible[cell][by]
		if name ~= nil then
			drawn[cell] = name
			if hot[cell] then
				table.insert(hotCells, cell)
			else
				layerGrid[cell] = name
			end
		end
	end

	local plan = {
		data = data,
		by = by,
		rects = {}, -- five entries per rectangle: bx, bz, sizeX, sizeZ, name
		count = 0,
		parts = {}, -- rectangle -> the Part that will draw it
		release = {}, -- old Parts covering nothing that is still drawn
		retire = {}, -- old Parts covering ground that is still drawn
	}

	-- Rectangles: merged outside edit zones, one per block inside them.
	table.clear(layerRects)
	local count = TerrainMesher.meshLayer(
		layerGrid, CHUNK_SIZE, TerrainConfig.MergeSurfaceRuns, layerRects
	)

	table.clear(finalRects)
	local write = 0

	local function push(bx, bz, sizeX, sizeZ, name)
		finalRects[write + 1] = bx
		finalRects[write + 2] = bz
		finalRects[write + 3] = sizeX
		finalRects[write + 4] = sizeZ
		finalRects[write + 5] = name
		write += 5
	end

	for index = 0, count - 1 do
		local base = index * 5
		local bx = layerRects[base + 1]
		local bz = layerRects[base + 2]
		local sizeX = layerRects[base + 3]
		local sizeZ = layerRects[base + 4]
		local name = layerRects[base + 5]

		if (sizeX > 1 or sizeZ > 1) and not isMergeable(name) then
			-- Decalled block. Broken back into cubes rather than smearing one
			-- decal across the whole run.
			for dx = 0, sizeX - 1 do
				for dz = 0, sizeZ - 1 do
					push(bx + dx, bz + dz, 1, 1, name)
				end
			end
		else
			push(bx, bz, sizeX, sizeZ, name)
		end
	end

	for _, cell in ipairs(hotCells) do
		local index = cell - 1
		push(index // CHUNK_SIZE, index % CHUNK_SIZE, 1, 1, drawn[cell])
	end

	-- Copied out of the scratch buffer: plans are applied after every dirty
	-- layer has been planned, and the next planLayer reuses finalRects.
	local rects = plan.rects
	table.move(finalRects, 1, write, 1, rects)
	plan.count = write // 5

	local existing = data.layerParts[by]
	if not existing or #existing == 0 then
		return plan
	end

	-- Exact matches, through a lookup so a big layer is not n * m.
	local byShape = {}
	for index, part in ipairs(existing) do
		local rect = partRect[part]
		if rect then
			local key = rectKey(rect.bx, rect.bz, rect.sizeX, rect.sizeZ)
			local list = byShape[key]
			if not list then
				list = {}
				byShape[key] = list
			end
			table.insert(list, index)
		end
	end

	local taken = {}
	for r = 1, plan.count do
		local base = (r - 1) * 5
		local list = byShape[rectKey(rects[base + 1], rects[base + 2], rects[base + 3], rects[base + 4])]
		if list then
			for _, index in ipairs(list) do
				local part = existing[index]
				if not taken[index] and part.Name == rects[base + 5] then
					taken[index] = true
					plan.parts[r] = part
					break
				end
			end
		end
	end

	for index, part in ipairs(existing) do
		if not taken[index] then
			local rect = partRect[part]
			local stillDrawn = false

			if rect then
				for dx = 0, rect.sizeX - 1 do
					for dz = 0, rect.sizeZ - 1 do
						if drawn[cellOf(rect.bx + dx, rect.bz + dz)] then
							stillDrawn = true
							break
						end
					end
					if stillDrawn then
						break
					end
				end
			end

			table.insert(if stillDrawn then plan.retire else plan.release, part)
		end
	end

	return plan
end

--[[
	A Part leaving the screen a moment from now rather than at once - see
	planLayer. Kept parented and drawing its old rectangle until then; tracked
	on the chunk so an unload can release it early.
]]
local function retirePart(data, part)
	data.retiring[part] = true
	task.delay(RETIRE_SECONDS, function()
		if data.retiring[part] then
			data.retiring[part] = nil
			releasePart(part)
		end
	end)
end

--[[
	Applies a set of layer plans: every new Part first, on every layer, then
	removals. `immediate` releases retiring Parts at once instead of after the
	delay - for an ability crater, where the hole should open with the blast.
]]
local function applyLayerPlans(plans, immediate)
	for _, plan in ipairs(plans) do
		local rects = plan.rects
		for r = 1, plan.count do
			if not plan.parts[r] then
				local base = (r - 1) * 5
				-- false only when the block has no usable template, which
				-- warns elsewhere.
				plan.parts[r] = emitMeshPart(
					plan.data, rects[base + 1], rects[base + 2], rects[base + 3], rects[base + 4],
					plan.by, rects[base + 5]
				) or false
			else
				-- Kept as it was, but an edit zone may have opened or closed over
				-- it, or the ground around it changed.
				showFaces(plan.data, plan.parts[r])
			end
		end
	end

	for _, plan in ipairs(plans) do
		for _, part in ipairs(plan.release) do
			releasePart(part)
		end

		for _, part in ipairs(plan.retire) do
			if immediate then
				releasePart(part)
			else
				retirePart(plan.data, part)
			end
		end

		local bucket = {}
		for r = 1, plan.count do
			local part = plan.parts[r]
			if part then
				table.insert(bucket, part)
			end
		end

		plan.data.layerParts[plan.by] = if #bucket > 0 then bucket else nil
		Profiler.count("Terrain.layerMeshed")
	end
end

--[[
	Rebuilds every layer that changed since the last flush, across every chunk
	given - an edit on a chunk border changes two chunks, and they have to be
	applied together for new-before-old to hold across the border.

	Visibility is decided per column, but a Part spans columns, so the two
	cannot be done in one step: the whole column pass has to finish before the
	layers it touched can be meshed. Callers do a batch of column updates and
	then flush once.
]]
local function flushChunks(list, immediate)
	local plans = {}

	for _, data in ipairs(list) do
		if data.dirtyCount > 0 then
			for by in pairs(data.dirtyLayers) do
				table.insert(plans, planLayer(data, by))
			end
			table.clear(data.dirtyLayers)
			data.dirtyCount = 0
		end
	end

	if #plans > 0 then
		applyLayerPlans(plans, immediate)
	end

	-- In the same step as the redraw, so a face an edit uncovers gets its
	-- images back in the same frame the block beside it goes.
	processFaceChanges()
end

local function flushChunkMesh(data)
	flushChunks({ data })
end

--[[
	flushChunkMesh for a chunk that is still being generated, and so is not in
	the world yet: a layer at a time, calling `slice` (which may yield) between
	layers. Each layer is planned and applied with no yield in between, so an
	edit that flushes the same chunk during a yield always sees a whole layer.
]]
local function flushChunkMeshSliced(data, slice)
	while data.dirtyCount > 0 do
		local by = next(data.dirtyLayers)
		data.dirtyLayers[by] = nil
		data.dirtyCount -= 1
		applyLayerPlans({ planLayer(data, by) })
		slice()
	end
end

--[[
	Records that a block should be drawn, and that its layer therefore needs
	rebuilding.

	Writing the same name again is deliberately free. Re-running visibility over
	an unchanged column is common - every edit refreshes its four neighbours -
	and marking those layers dirty would remesh the whole chunk for nothing.
]]
local function setVisible(data, cell, by, blockName)
	local column = data.visible[cell]
	local previous = column[by]

	if previous ~= blockName then
		if previous == nil then
			visibleBlocks += 1
			data.visibleCount += 1
		end

		column[by] = blockName

		if not data.dirtyLayers[by] then
			data.dirtyLayers[by] = true
			data.dirtyCount += 1
		end
	end
end

local function clearVisible(data, cell, by)
	local column = data.visible[cell]

	if column[by] ~= nil then
		column[by] = nil
		visibleBlocks -= 1
		data.visibleCount -= 1

		if not data.dirtyLayers[by] then
			data.dirtyLayers[by] = true
			data.dirtyCount += 1
		end
	end
end

-- Blocks drawn across every loaded chunk.
function ChunkMesher.visibleBlocks()
	return visibleBlocks
end

-- A chunk's drawn blocks leaving with it as it unloads.
function ChunkMesher.forgetVisible(count)
	visibleBlocks -= count
end

ChunkMesher.markLayerDirty = markLayerDirty
ChunkMesher.flushChunks = flushChunks
ChunkMesher.flushChunkMesh = flushChunkMesh
ChunkMesher.flushChunkMeshSliced = flushChunkMeshSliced
ChunkMesher.setVisible = setVisible
ChunkMesher.clearVisible = clearVisible

return ChunkMesher
