--[[
	ColumnVisibility

	Decides which blocks of a column need a Part (the fast and general paths),
	and the redraw orchestration around it: refreshing a column and its four
	neighbours after an edit, and a loaded neighbour's border after a chunk
	appears. Part of TerrainManager; see TerrainManager for the map of terrain
	modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local ChunkData = require(script.Parent:WaitForChild("ChunkData"))
local ChunkMesher = require(script.Parent:WaitForChild("ChunkMesher"))
local FaceCulling = require(script.Parent:WaitForChild("FaceCulling"))
local TerrainWater = require(script.Parent:WaitForChild("TerrainWater"))

local ColumnVisibility = {}

local CHUNK_SIZE = TerrainConfig.ChunkSize
local FLOOR_Y = TerrainConfig.WorldFloorY
local EDIT_DEPTH = TerrainConfig.EditZone.Depth
local DIR_X = TerrainGrid.DIR_X
local DIR_Z = TerrainGrid.DIR_Z

local chunks = ChunkData.chunks
local generatingChunks = ChunkData.generating
--[[
	Inlinable copies of TerrainGrid helpers, on purpose. Luau's optimiser only
	inlines a `local function` defined in the same script, and these run per
	block in the visibility and face passes; calling TerrainGrid's versions
	across modules measured ~10% slower there. Keep them identical to
	TerrainGrid (the canonical definitions).
]]
local function chunkKey(cx, cz)
	return (cx + 8192) * 65536 + (cz + 8192)
end
local MIN_CHUNK_X, MAX_CHUNK_X = TerrainConfig.MinChunkX, TerrainConfig.MaxChunkX
local MIN_CHUNK_Z, MAX_CHUNK_Z = TerrainConfig.MinChunkZ, TerrainConfig.MaxChunkZ
local function isChunkInBounds(cx, cz)
	return cx >= MIN_CHUNK_X and cx <= MAX_CHUNK_X and cz >= MIN_CHUNK_Z and cz <= MAX_CHUNK_Z
end
local function normalizeCell(cx, cz, bx, bz)
	if bx < 0 or bx >= CHUNK_SIZE then
		local shift = bx // CHUNK_SIZE
		cx += shift
		bx -= shift * CHUNK_SIZE
	end
	if bz < 0 or bz >= CHUNK_SIZE then
		local shift = bz // CHUNK_SIZE
		cz += shift
		bz -= shift * CHUNK_SIZE
	end
	return cx, cz, bx, bz
end
local function cellOf(bx, bz)
	return bx * CHUNK_SIZE + bz + 1
end
local isPresentInData = ChunkData.isPresentInData
local isBlockPresent = ChunkData.isBlockPresent
local neighbourColumn = ChunkData.neighbourColumn
local blockNameFor = ChunkData.blockNameFor
local setVisible = ChunkMesher.setVisible
local clearVisible = ChunkMesher.clearVisible
local flushChunks = ChunkMesher.flushChunks
local flushChunkMesh = ChunkMesher.flushChunkMesh
local syncColumnWater = TerrainWater.syncColumnWater

--[[
	Decides which blocks of one column need a real part.

	A block is worth rendering only if one of its six faces is exposed.

	FAST PATH. In an untouched column - no mined holes, no added blocks, and the
	same for its four neighbours - a block is exposed exactly when it is the top
	block or when it sits at or above the shortest neighbouring column. So the
	visible band is simply [min(neighbourHeights), currentHeight - 1] and
	everything buried below it is never looked at. This is why the world can be
	160 blocks deep and still cost one part per flat column.

	GENERAL PATH. Once a column or one of its neighbours has been dug into, some
	blocks below the surface band may be exposed. Rather than scan the whole
	column - which is what would make a deep world expensive - each column
	remembers the band it has actually been disturbed in, and only that band plus
	the surface band is tested. A tunnel 140 blocks down therefore costs a
	handful of tests, not 190.
]]
--[[
	The six-face test, over one contiguous band of a column.

	Deliberately a top-level function rather than a closure inside
	updateColumnVisibility: that runs once per column per chunk load, and a
	closure there would allocate on every single call.
]]
local function scanColumnRange(data, cx, cz, bx, bz, cell, column, low, high, waterLow, waterHigh, force)
	for by = low, high do
		if not isPresentInData(data, cell, by) then
			-- Anything in the water band belongs to the water pass below, which
			-- runs after this one. Clearing it here would delete the surface and
			-- then have it put straight back, dirtying the layer every time a
			-- neighbouring chunk loads.
			if by >= waterLow and by <= waterHigh then
				-- left alone
			elseif column[by] ~= nil then
				clearVisible(data, cell, by)
			end
		else
			-- In an edit zone every block in the band is drawn, exposed or not:
			-- that is the layer of warning a fast edit needs. See EDIT ZONES.
			local visible = force or not isBlockPresent(cx, cz, bx, bz, by + 1)

			if not visible and by > FLOOR_Y and not isBlockPresent(cx, cz, bx, bz, by - 1) then
				visible = true
			end

			if not visible then
				for i = 1, 4 do
					if not isBlockPresent(cx, cz, bx + DIR_X[i], bz + DIR_Z[i], by) then
						visible = true
						break
					end
				end
			end

			if visible then
				-- As in the fast path: an already-drawn block keeps the name it
				-- was given. Anything that could change that name - a mined
				-- block, a placement, a structure override - clears the slot
				-- first, so a filled slot is by construction still correct.
				if column[by] == nil then
					setVisible(data, cell, by, blockNameFor(data, cell, by))
				end
			elseif column[by] ~= nil then
				clearVisible(data, cell, by)
			end
		end
	end
end

local function updateColumnVisibility(cx, cz, bx, bz)
	local data = chunks[chunkKey(cx, cz)]
	if not data then
		return
	end

	Profiler.enter("Terrain.columnVisibility")

	local cell = cellOf(bx, bz)
	local column = data.visible[cell]
	local currentHeight = data.currentHeight[cell]

	-- In an edit zone: drawn a little deeper, every block in the bands. Always
	-- the general path, which is the one that knows how to.
	local zoned = data.hot[cell] ~= nil
	local extra = if zoned then EDIT_DEPTH else 0

	local minNeighbour = math.huge
	local bandLow = data.distLow[cell]
	local bandHigh = data.distHigh[cell]
	local neighbourComplex = false

	-- The lowest point any neighbour covers, counting its own water as cover.
	-- This is what makes a lake interior one block thick: its neighbours' water
	-- reaches the same level, so there is no edge to draw.
	local minCover = math.huge

	for i = 1, 4 do
		local ncx, ncz, nbx, nbz = normalizeCell(cx, cz, bx + DIR_X[i], bz + DIR_Z[i])
		local height, complex, low, high, water = neighbourColumn(ncx, ncz, nbx, nbz)
		if height < minNeighbour then
			minNeighbour = height
		end

		local cover = if water > height then water else height
		if cover < minCover then
			minCover = cover
		end

		if complex then
			neighbourComplex = true
		end
		if low < bandLow then
			bandLow = low
		end
		if high > bandHigh then
			bandHigh = high
		end
	end

	-- Lower edge of the surface band, shared by both paths.
	local surfaceLow = minNeighbour
	if surfaceLow > currentHeight - 1 then
		surfaceLow = currentHeight - 1
	end
	if surfaceLow < FLOOR_Y then
		surfaceLow = FLOOR_Y
	end

	--[[
		No water is drawn here any more. Water is Roblox Terrain, written as a
		whole volume by syncColumnWater - see WATER below for why. The band is
		kept, empty, so the block passes below still have one place that says
		which cells are not theirs to touch.

		Water is still NOT part of the heightmap: `currentHeight` is the top of
		the solid ground, so mining, placement and the strata below are all
		untouched by it.
	]]
	local waterLow, waterHigh = 1, 0 -- empty

	if not data.complex[cell] and not neighbourComplex and not zoned then
		if currentHeight <= FLOOR_Y then
			for by in pairs(column) do
				clearVisible(data, cell, by)
			end
			Profiler.leave("Terrain.columnVisibility")
			return
		end

		for by in pairs(column) do
			if
				(by < surfaceLow or by >= currentHeight)
				and not (by >= waterLow and by <= waterHigh)
			then
				clearVisible(data, cell, by)
			end
		end

		-- Only blocks that are not already drawn need their name worked out.
		-- On this path the column and its neighbours are untouched, so
		-- blockNameFor is a pure function of position that cannot have changed
		-- since the slot was filled - and it is not cheap, being a strata
		-- lookup plus an ore lookup. Border refreshes re-run this pass over
		-- sixteen columns per neighbouring chunk load, so skipping the settled
		-- ones matters.
		for by = surfaceLow, currentHeight - 1 do
			if column[by] == nil then
				setVisible(data, cell, by, blockNameFor(data, cell, by))
			end
		end

		Profiler.leave("Terrain.columnVisibility")
		return
	end

	-- General path. Two bands: the surface, and whatever has been dug into.
	-- One block of margin on the disturbed band covers the blocks that line a
	-- hole from below and above.
	local scanTop = data.topScan[cell]

	local lowA, highA = surfaceLow - extra, scanTop - 1
	if lowA < FLOOR_Y then
		lowA = FLOOR_Y
	end
	local lowB, highB = 1, 0 -- empty by default

	if bandLow <= bandHigh then
		lowB = bandLow - 1 - extra
		highB = bandHigh + 1 + extra
		if lowB < FLOOR_Y then
			lowB = FLOOR_Y
		end
		if highB > scanTop - 1 then
			highB = scanTop - 1
		end

		if highB >= lowA - 1 then
			-- The bands touch; treat them as one so nothing is tested twice.
			if lowB < lowA then
				lowA = lowB
			end
			lowB, highB = 1, 0
		end
	end

	for by in pairs(column) do
		if
			not ((by >= lowA and by <= highA) or (by >= lowB and by <= highB))
			and not (by >= waterLow and by <= waterHigh)
		then
			clearVisible(data, cell, by)
		end
	end

	scanColumnRange(data, cx, cz, bx, bz, cell, column, lowB, highB, waterLow, waterHigh, zoned)
	scanColumnRange(data, cx, cz, bx, bz, cell, column, lowA, highA, waterLow, waterHigh, zoned)

	Profiler.count("Terrain.columnSlowPath")
	Profiler.leave("Terrain.columnVisibility")
end

--[[
	Re-evaluates a column and its four neighbours after an edit, then rebuilds
	whatever layers that touched.

	The flush happens once, after all five columns have settled, and covers every
	chunk involved - an edit on a chunk border moves blocks in two of them, and
	meshing one before the other had finished would build a rectangle out of a
	half-updated layer.
]]
local function refreshAdjacentColumns(cx, cz, bx, bz, immediate)
	local touched = {}

	local own = chunks[chunkKey(cx, cz)]
	if own then
		touched[own] = true
		-- Only the edited column's water can have changed: water does not flow,
		-- so a neighbour's stays exactly where it was.
		syncColumnWater(own, cellOf(bx, bz))
	end

	updateColumnVisibility(cx, cz, bx, bz)

	for i = 1, 4 do
		local ncx, ncz, nbx, nbz = normalizeCell(cx, cz, bx + DIR_X[i], bz + DIR_Z[i])
		if isChunkInBounds(ncx, ncz) then
			local nkey = chunkKey(ncx, ncz)
			local neighbour = chunks[nkey]
			if neighbour and generatingChunks[nkey] then
				-- Never draw a half-built chunk; see refreshChunkBorders.
				neighbour.bordersStale = true
			elseif neighbour then
				touched[neighbour] = true
				updateColumnVisibility(ncx, ncz, nbx, nbz)
			end
		end
	end

	-- Together, so new Parts in one chunk are made before old ones in the
	-- other are removed. See applyLayerPlans.
	local list = {}
	for data in pairs(touched) do
		table.insert(list, data)
	end
	flushChunks(list, immediate)
end

--[[
	Re-evaluates the border columns of already-loaded neighbours after a chunk
	appears. Heights alone would not need this (an unloaded neighbour already
	answers with its generated height), but added blocks would: a boulder that
	spills across the border only exists once both chunks are built.

	A neighbour that is itself still generating is NOT touched. It sits in
	`chunks` from its structure phase onward, so flushing it here would mesh and
	publish whatever part of it was drawn so far - before its structures and
	replayed edits were in - and its own flush a few frames later would then
	replace those Parts with differently shaped ones. With two chunks in flight
	side by side that is the pop and flicker at the streaming edge. It is
	flagged instead, and re-reads its own borders before its one flush.
]]
local function refreshChunkBorders(cx, cz)
	for i = 1, 4 do
		local ncx = cx + DIR_X[i]
		local ncz = cz + DIR_Z[i]

		local nkey = chunkKey(ncx, ncz)
		local neighbour = isChunkInBounds(ncx, ncz) and chunks[nkey]
		if neighbour and generatingChunks[nkey] then
			neighbour.bordersStale = true
		elseif neighbour then
			for j = 0, CHUNK_SIZE - 1 do
				local bx, bz
				if DIR_X[i] == 1 then
					bx, bz = 0, j
				elseif DIR_X[i] == -1 then
					bx, bz = CHUNK_SIZE - 1, j
				elseif DIR_Z[i] == 1 then
					bx, bz = j, 0
				else
					bx, bz = j, CHUNK_SIZE - 1
				end
				updateColumnVisibility(ncx, ncz, bx, bz)
			end

			-- Whole border done; now the neighbour's affected layers can be
			-- rebuilt as complete rows rather than sixteen times over.
			flushChunkMesh(neighbour)
		end

		-- Its border faces were decided against the heightmap, which knows
		-- nothing of this chunk's structures or edits. Still generating or not:
		-- some of its Parts may already be drawn.
		if neighbour then
			FaceCulling.refreshEdge(neighbour, -DIR_X[i], -DIR_Z[i])
		end
	end
end

ColumnVisibility.updateColumnVisibility = updateColumnVisibility
ColumnVisibility.refreshAdjacentColumns = refreshAdjacentColumns
ColumnVisibility.refreshChunkBorders = refreshChunkBorders

return ColumnVisibility
