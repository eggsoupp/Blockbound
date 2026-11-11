--[[
	TerrainExcavation

	Server-owned terrain changes no player asked for: meteor and ability
	craters, bounded boss bites (plan, then execute), and moving real blocks
	(the Block Wall ability and Signus's displacement) under reservations that
	keep their chunks resident. Every removal goes through
	BlockEdits.removeResolvedBlock, so ChunkEdits records it like mining.
	Part of TerrainManager; see TerrainManager for the map of terrain modules.

	Methods are written with `:` because TerrainManager exposes them as its own;
	`self` is unused.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))
local ChunkEdits = require(TerrainShared:WaitForChild("ChunkEdits"))
local BlockConfig = require(Shared:WaitForChild("Blocks"):WaitForChild("BlockConfig"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local ChunkData = require(script.Parent:WaitForChild("ChunkData"))
local ChunkMesher = require(script.Parent:WaitForChild("ChunkMesher"))
local ColumnVisibility = require(script.Parent:WaitForChild("ColumnVisibility"))
local TerrainWater = require(script.Parent:WaitForChild("TerrainWater"))
local BlockEdits = require(script.Parent:WaitForChild("BlockEdits"))

local TerrainExcavation = {}

local STUD_SIZE = TerrainConfig.StudSize
local CHUNK_SIZE = TerrainConfig.ChunkSize
local FLOOR_Y = TerrainConfig.WorldFloorY
local MAX_BLOCK_Y = TerrainConfig.WorldCeilingY
local DIR_X = TerrainGrid.DIR_X
local DIR_Z = TerrainGrid.DIR_Z

local chunks = ChunkData.chunks
local generatingChunks = ChunkData.generating
local reservedCells = ChunkData.reservedCells
local pinnedChunks = ChunkData.pinnedChunks
local isPresentInData = ChunkData.isPresentInData
local blockNameFor = ChunkData.blockNameFor
local applyPlacement = ChunkData.applyPlacement
local chunkKey = TerrainGrid.chunkKey
local isChunkInBounds = TerrainGrid.isChunkInBounds
local normalizeCell = TerrainGrid.normalizeCell
local worldToChunkLocal = TerrainGrid.worldToChunkLocal
local getChunkWorldOrigin = TerrainGrid.getChunkWorldOrigin
local cellOf = TerrainGrid.cellOf
local flushChunks = ChunkMesher.flushChunks
local updateColumnVisibility = ColumnVisibility.updateColumnVisibility
local refreshAdjacentColumns = ColumnVisibility.refreshAdjacentColumns
local syncColumnWater = TerrainWater.syncColumnWater
local removeResolvedBlock = BlockEdits.removeResolvedBlock

-- Server-only meteor bowl. All edits use the normal persistence path; never
-- deletes rendered slabs directly. Bound the volume and remesh each chunk once.
function TerrainExcavation:MineMeteorCrater(centre, radius, depth)
	local samples, rewards = {}, {}
	if typeof(centre) ~= "Vector3" or centre.X ~= centre.X or centre.Y ~= centre.Y or centre.Z ~= centre.Z
		or math.max(math.abs(centre.X), math.abs(centre.Y), math.abs(centre.Z)) > 1e6 then
		return 0, samples, rewards
	end
	if type(radius) ~= "number" or radius ~= radius or type(depth) ~= "number" or depth ~= depth then
		return 0, samples, rewards
	end
	radius, depth = math.clamp(radius, 4, 32), math.clamp(depth, 4, 24)
	local top = math.min(MAX_BLOCK_Y, math.floor((centre.Y - 0.05) / STUD_SIZE))
	local extent = math.ceil(radius / STUD_SIZE)
	local blockX, blockZ = math.floor(centre.X / STUD_SIZE), math.floor(centre.Z / STUD_SIZE)
	local dirty, removed = {}, 0
	for dx = -extent, extent do
		for dz = -extent, extent do
			local x, z = blockX + dx, blockZ + dz
			local distance2 = ((x + 0.5) * STUD_SIZE - centre.X)^2 + ((z + 0.5) * STUD_SIZE - centre.Z)^2
			if distance2 > radius * radius then continue end
			local cx, cz, bx, bz = normalizeCell(x // CHUNK_SIZE, z // CHUNK_SIZE, x % CHUNK_SIZE, z % CHUNK_SIZE)
			local key = chunkKey(cx, cz)
			local data = chunks[key]
			if not isChunkInBounds(cx, cz) or not data or generatingChunks[key] then continue end
			local cell = cellOf(bx, bz)
			local layers = math.max(1, math.ceil(depth / STUD_SIZE * (1 - distance2 / (radius * radius))))
			local bottom = math.max(FLOOR_Y, top - layers + 1)
			for by = math.min(MAX_BLOCK_Y, top + 2), bottom, -1 do
				if removed >= 1800 then break end
				if not isPresentInData(data, cell, by) then continue end
				local name = blockNameFor(data, cell, by)
				-- Never dig underneath bedrock or a protected solid layer.
				if BlockConfig.isUnbreakable(name) then break end
				local ok, item = removeResolvedBlock(data, cell, by, false)
				if ok then
					removed += 1
					if item then rewards[item] = (rewards[item] or 0) + 1 end
					dirty[key .. ":" .. cell] = {cx, cz, bx, bz}
					-- Reservoir sampling covers the whole bowl rather than its first edge.
					local record = {position = Vector3.new((x + .5)*STUD_SIZE, (by + .5)*STUD_SIZE, (z + .5)*STUD_SIZE), block = name}
					if #samples < 48 then table.insert(samples, record)
					else local slot = math.random(1, removed); if slot <= 48 then samples[slot] = record end end
				end
			end
		end
	end
	local columns, touched = {}, {}
	local function addColumn(cx, cz, bx, bz)
		local ncx, ncz, nbx, nbz = normalizeCell(cx, cz, bx, bz)
		local key = chunkKey(ncx, ncz)
		local data = chunks[key]
		if not isChunkInBounds(ncx, ncz) or not data then return end
		if generatingChunks[key] then data.bordersStale = true; return end
		columns[key .. ":" .. cellOf(nbx, nbz)] = {ncx, ncz, nbx, nbz}
		touched[data] = true
	end
	for _, c in pairs(dirty) do
		local data = chunks[chunkKey(c[1], c[2])]
		syncColumnWater(data, cellOf(c[3], c[4]))
		addColumn(c[1], c[2], c[3], c[4])
		for i = 1, 4 do addColumn(c[1], c[2], c[3] + DIR_X[i], c[4] + DIR_Z[i]) end
	end
	for _, c in pairs(columns) do updateColumnVisibility(c[1], c[2], c[3], c[4]) end
	local list = {}
	for data in pairs(touched) do table.insert(list, data) end
	flushChunks(list, true)
	return removed, samples, rewards
end

-- Server-only ability excavation. Exact loaded cells, no mining-reach override on
-- BreakBlock and no client remote. Clear the beam shaft as well as the crater.
function TerrainExcavation:MineAbilityCrater(centre, canCollect, collect, beamHeight, beamRadius)
	if typeof(centre) ~= "Vector3" or centre.X ~= centre.X or centre.Y ~= centre.Y or centre.Z ~= centre.Z then return 0 end
	if math.abs(centre.X)>1e6 or math.abs(centre.Y)>1e6 or math.abs(centre.Z)>1e6 then return 0 end
	local top = math.floor((centre.Y-0.05)/STUD_SIZE)
	local shaftHeight = math.clamp(beamHeight or 280, 0, 280)
	local shaftRadius = math.clamp(beamRadius or 20, 0, 20) / STUD_SIZE
	local shaftTop = math.floor((centre.Y+shaftHeight-0.05)/STUD_SIZE)
	local dirty, removed, debris = {}, 0, {}
	local groundDebris, shaftDebris = {}, {}
	local groundRemoved, shaftRemoved = 0, 0
	-- Descend through overhangs before excavating the six tapered ground layers.
	-- The pressure field clears overhangs across the crater's footprint too.
	for depth = top-shaftTop, 5 do
		local radius = if depth < 0 then shaftRadius else 5-depth
		local extent = math.ceil(radius)
		for dx = -extent, extent do
			for dz = -extent, extent do
				if dx*dx+dz*dz>radius*radius then continue end
				local cx,cz,bx,bz=worldToChunkLocal(centre.X+dx*STUD_SIZE,centre.Z+dz*STUD_SIZE)
				if not isChunkInBounds(cx,cz) then continue end
				local data=chunks[chunkKey(cx,cz)]
				local by=top-depth
				local cell=cellOf(bx,bz)
				if not data or by<FLOOR_Y or not isPresentInData(data,cell,by) then continue end
				local name=blockNameFor(data,cell,by)
				if BlockConfig.isUnbreakable(name) then continue end
				local ok,item=removeResolvedBlock(data,cell,by,false)
				if ok then
					removed+=1
					local samples
					local zoneCount
					if depth<0 then shaftRemoved+=1; samples=shaftDebris; zoneCount=shaftRemoved
					else groundRemoved+=1; samples=groundDebris; zoneCount=groundRemoved end
					if zoneCount%3==1 and #samples<64 then
						local ox,oz=getChunkWorldOrigin(cx,cz)
						table.insert(samples,{position=Vector3.new(ox+(bx+.5)*STUD_SIZE,(by+.5)*STUD_SIZE,oz+(bz+.5)*STUD_SIZE),block=name})
					end
					dirty[chunkKey(cx,cz)..":"..cell]={cx,cz,bx,bz}
					-- Ability destruction still works when there is no room for loot.
					if item and canCollect(item) then collect(item) end
				end
			end
		end
	end
	for _,column in pairs(dirty) do
		-- Immediate: a crater should open with the blast, not a moment after it.
		refreshAdjacentColumns(column[1],column[2],column[3],column[4],true)
	end
	-- Keep ground fragments visible even when a dense overhead shaft fills the cap.
	local groundLimit=math.min(#groundDebris,math.max(32,64-#shaftDebris))
	for i=1,math.min(#shaftDebris,64-groundLimit) do table.insert(debris,shaftDebris[i]) end
	for i=1,groundLimit do table.insert(debris,groundDebris[i]) end
	return removed,debris
end

--[[
	BOUNDED SERVER-OWNED EXCAVATION - a boss eating the ground.

	MineAbilityCrater above is shaped around one thing: a 280-stud beam shaft
	and a six-layer tapered crater. A boss that takes shallow bites out of the
	floor at the ends of a few tendrils wants none of that shape, so this is the
	general operation underneath: "here are some columns, remove the top block
	or two of each, tell me what actually went".

	It is in TWO STEPS on purpose. The caller plans first and executes later,
	because a telegraph has to promise the ground that will actually be hit:
	the plan is the frozen list of cells the warning is drawn from, and the
	execution removes exactly those cells - re-validated, because a player may
	have mined or built there during the warning - and nothing else.

	TERRAIN SAFETY RULES, all enforced here rather than trusted to the caller:

	  loaded only       a column whose chunk is not resident, or is still being
	                    generated, is skipped. Nothing is ever written into
	                    chunk data that is about to be replaced.
	  world bounds      chunk bounds, the world floor and the ceiling.
	  unbreakable       BlockConfig.isUnbreakable wins over everything.
	  natural only      by default a cell is skipped if it is an ADDED block
	                    (data.extra: a structure's block or a player's
	                    placement - ChunkEdits tells them apart, and neither is
	                    the boss's to eat) or a RESTYLED one (data.override: a
	                    structure's restyle of the ground under it, or a cave
	                    wall). Overrides cannot be told apart from each other,
	                    so both are protected; the cost is that he bites less
	                    around caves, which is fine.
	  dry only          by default a column under standing water is skipped. A
	                    bite under a lake would be invisible and the water sync
	                    would have to redraw for nothing.
	  no loot           the item a removed block would have dropped is thrown
	                    away. This is not mining; a boss must not be a farm.
	  hard caps         on columns considered, cells planned, cells removed and
	                    samples returned, whatever the caller asks for.
	  no reach check    this is a server-owned action, not a player's request.
	                    Nothing here reads a client, and no client chooses a
	                    cell or reports a removal.

	Removal goes through removeResolvedBlock, so ChunkEdits records it exactly
	as a mined block and the renderer re-derives the column - and dirty columns
	are deduplicated and refreshed once each at the end rather than per block.

	The sample records are `{ position = Vector3, block = name }` of blocks
	that were REALLY removed, for clients to animate copies of. A client never
	sees a block the server did not take.
]]
local EXCAVATE_MAX_COLUMNS = 48
local EXCAVATE_MAX_CELLS = 64
local EXCAVATE_MAX_SAMPLES = 24
local EXCAVATE_MAX_DEPTH = 3

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and math.abs(value) < 1e6
end

-- Natural, expendable ground: not added, not restyled. See the rules above.
local function isNaturalCell(data, cell, by)
	local extra = data.extra[cell]
	if extra and extra[by] then
		return false
	end
	local override = data.override[cell]
	if override and override[by] then
		return false
	end
	return true
end

local function cellAllowed(data, cell, by, options)
	if not isPresentInData(data, cell, by) then
		return false
	end
	if options.naturalOnly ~= false and not isNaturalCell(data, cell, by) then
		return false
	end
	if BlockConfig.isUnbreakable(blockNameFor(data, cell, by)) then
		return false
	end
	return true
end

--[[
	Resolves a set of columns into the exact cells a later ExecuteExcavation
	will remove.

	  columns  { { x = worldX, z = worldZ, y = worldY, depth = n }, ... }
	           y is where to start looking for the top of the ground (the
	           caller's idea of the floor there); depth is how many blocks
	           down from that top block to take, 1..EXCAVATE_MAX_DEPTH.
	  options  naturalOnly (default true), skipWet (default true),
	           maxCells (clamped to EXCAVATE_MAX_CELLS)

	Returns an array of cell records, top-down within each column so that
	removing them in order lowers the column the way mining it would.
]]
function TerrainExcavation:PlanExcavation(columns, options)
	options = options or {}
	local maxCells = math.clamp(tonumber(options.maxCells) or EXCAVATE_MAX_CELLS, 0, EXCAVATE_MAX_CELLS)
	local plan = {}

	if type(columns) ~= "table" then
		return plan
	end

	for index, column in ipairs(columns) do
		if index > EXCAVATE_MAX_COLUMNS or #plan >= maxCells then
			break
		end
		if type(column) ~= "table" or not (isFiniteNumber(column.x) and isFiniteNumber(column.z) and isFiniteNumber(column.y)) then
			continue
		end

		local cx, cz, bx, bz = worldToChunkLocal(column.x, column.z)
		if not isChunkInBounds(cx, cz) then
			continue
		end
		local key = chunkKey(cx, cz)
		local data = chunks[key]
		if not data or generatingChunks[key] then
			continue
		end

		local cell = cellOf(bx, bz)

		if options.skipWet ~= false and data.waterTop[cell] > data.currentHeight[cell] then
			continue
		end

		-- The top solid block near the caller's floor height: a short scan,
		-- two blocks up for a step and four down for a hollow, never further.
		local from = math.min(MAX_BLOCK_Y, math.floor(column.y / STUD_SIZE) + 2)
		local to = math.max(FLOOR_Y, from - 6)
		local top = nil
		for by = from, to, -1 do
			if isPresentInData(data, cell, by) then
				top = by
				break
			end
		end
		if not top then
			continue
		end

		local depth = math.clamp(math.floor(tonumber(column.depth) or 1), 1, EXCAVATE_MAX_DEPTH)
		local ox, oz = getChunkWorldOrigin(cx, cz)

		for step = 0, depth - 1 do
			local by = top - step
			if #plan >= maxCells then
				break
			end
			-- A protected block ends the column: biting out from under an
			-- unbreakable or placed block would leave it floating, and a
			-- bite is a surface thing anyway.
			if not cellAllowed(data, cell, by, options) then
				break
			end
			table.insert(plan, {
				cx = cx, cz = cz, cell = cell, by = by,
				bx = bx, bz = bz,
				position = Vector3.new(ox + (bx + 0.5) * STUD_SIZE, (by + 0.5) * STUD_SIZE, oz + (bz + 0.5) * STUD_SIZE),
				block = blockNameFor(data, cell, by),
			})
		end
	end

	return plan
end

--[[
	Removes the cells of a plan from PlanExcavation. Every cell is checked
	again - still loaded, still present, still natural, still breakable -
	because the world may have moved between the plan and now.

	Returns the number of blocks actually removed and a capped sample of
	`{ position, block }` records for the blocks that really went.
]]
function TerrainExcavation:ExecuteExcavation(plan, options)
	options = options or {}
	local maxRemoved = math.clamp(tonumber(options.maxRemoved) or EXCAVATE_MAX_CELLS, 0, EXCAVATE_MAX_CELLS)
	local maxSamples = math.clamp(tonumber(options.maxSamples) or EXCAVATE_MAX_SAMPLES, 0, EXCAVATE_MAX_SAMPLES)

	local removed, samples, dirty = 0, {}, {}
	local gone = {}

	if type(plan) ~= "table" then
		return 0, samples
	end

	Profiler.enter("Terrain.excavate")

	for index, record in ipairs(plan) do
		if index > EXCAVATE_MAX_CELLS or removed >= maxRemoved then
			break
		end
		if type(record) ~= "table" then
			continue
		end

		local key = chunkKey(record.cx, record.cz)
		local data = chunks[key]
		if not data or generatingChunks[key] or not isChunkInBounds(record.cx, record.cz) then
			continue
		end
		if not cellAllowed(data, record.cell, record.by, options) then
			continue
		end

		local name = blockNameFor(data, record.cell, record.by)
		local ok = removeResolvedBlock(data, record.cell, record.by, false)
		if ok then
			removed += 1
			-- The drop is deliberately not collected: see the rules above.
			dirty[key .. ":" .. record.cell] = { record.cx, record.cz, record.bx, record.bz }
			table.insert(gone, { position = record.position, block = name })
		end
	end

	-- Once per column, immediately: the bite opens with the attack that made
	-- it, and a column with two blocks gone is rebuilt once, not twice.
	for _, column in pairs(dirty) do
		refreshAdjacentColumns(column[1], column[2], column[3], column[4], true)
	end

	-- Spread the samples over everything that went rather than taking the
	-- first N, so the debris comes from the whole bite and not one corner.
	if maxSamples > 0 and #gone > 0 then
		local stride = math.max(1, math.ceil(#gone / maxSamples))
		for index = 1, #gone, stride do
			if #samples >= maxSamples then
				break
			end
			table.insert(samples, gone[index])
		end
	end

	Profiler.leave("Terrain.excavate")
	Profiler.count("Terrain.excavated", removed)

	return removed, samples
end

-- Server-only earth movement. A loan lasts less than a second, reserves both
-- ends, and pins the touched chunks until it commits or rolls back on cancel.
local function wallCell(x, y, z)
	local cx,cz,bx,bz=normalizeCell(x//CHUNK_SIZE,z//CHUNK_SIZE,x%CHUNK_SIZE,z%CHUNK_SIZE)
	local key=chunkKey(cx,cz)
	local cell=cellOf(bx,bz)
	return {cx=cx,cz=cz,bx=bx,bz=bz,cell=cell,by=y,key=key,
		id=key..":"..cell..":"..y,position=Vector3.new(x+.5,y+.5,z+.5)*STUD_SIZE}
end

function TerrainExcavation:PlanBlockWall(origin, forward)
	local axis=if math.abs(forward.X)>math.abs(forward.Z) then Vector3.new(if forward.X>0 then 1 else -1,0,0) else Vector3.new(0,0,if forward.Z>0 then 1 else -1)
	local side=Vector3.new(-axis.Z,0,axis.X)
	local centre=origin+axis*9
	local x,z=math.floor(centre.X/STUD_SIZE),math.floor(centre.Z/STUD_SIZE)
	local targets,excluded={},{}
	local ray=RaycastParams.new()
	ray.FilterType=Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances={workspace:FindFirstChild("GeneratedTerrain")}
	for column=-1,1 do
		local tx,tz=x+side.X*column,z+side.Z*column
		local hit=workspace:Raycast(Vector3.new((tx+.5)*STUD_SIZE,origin.Y+6,(tz+.5)*STUD_SIZE),Vector3.new(0,-24,0),ray)
		if not hit or hit.Normal.Y<.8 then return nil,"Block Wall needs solid ground in front of you." end
		local bottom=math.floor((hit.Position.Y+.05)/STUD_SIZE)
		excluded[tx..":"..tz]=true
		for row=0,2 do
			local c=wallCell(tx,bottom+row,tz)
			local data=chunks[c.key]
			if not data or generatingChunks[c.key] or c.by>MAX_BLOCK_Y or reservedCells[c.id] or isPresentInData(data,c.cell,c.by) then
				return nil,"There is no room for a wall here."
			end
			table.insert(targets,c)
		end
	end
	local candidates={}
	local bx,bz=math.floor(origin.X/STUD_SIZE),math.floor(origin.Z/STUD_SIZE)
	for dx=-4,4 do for dz=-4,4 do
		local wx,wz=(bx+dx+.5)*STUD_SIZE,(bz+dz+.5)*STUD_SIZE
		local distance=(Vector3.new(wx,origin.Y,wz)-origin).Magnitude
		if distance>=4.5 and distance<=16 and not excluded[(bx+dx)..":"..(bz+dz)] then
			table.insert(candidates,{x=wx,z=wz,y=origin.Y-3,depth=1,distance=distance})
		end
	end end
	table.sort(candidates,function(a,b) return a.distance<b.distance end)
	local sources={}
	for _,column in ipairs(candidates) do
		local cells=TerrainExcavation:PlanExcavation({column},{naturalOnly=true,skipWet=true,maxCells=1})
		local cell=cells[1]
		if cell then
			local c=wallCell(math.floor(cell.position.X/STUD_SIZE),cell.by,math.floor(cell.position.Z/STUD_SIZE))
			if not reservedCells[c.id] then c.block=cell.block;table.insert(sources,c) end
		end
		if #sources==9 then break end
	end
	if #sources<9 then return nil,"Not enough nearby natural blocks to raise a wall." end
	local records={}
	for i,c in ipairs(sources) do table.insert(records,{source=c,target=targets[i],block=c.block}) end
	return records
end

function TerrainExcavation:TakeBlockWall(records)
	if type(records)~="table" or #records~=9 then return nil end
	for _,r in ipairs(records) do
		local s,t=r.source,r.target
		local from,to=chunks[s.key],chunks[t.key]
		if not from or not to or generatingChunks[s.key] or generatingChunks[t.key]
			or reservedCells[s.id] or reservedCells[t.id]
			or not cellAllowed(from,s.cell,s.by,{naturalOnly=true,skipWet=true})
			or blockNameFor(from,s.cell,s.by)~=r.block or isPresentInData(to,t.cell,t.by) then return nil end
	end
	local loan={records=records,done=false,keys={}}
	for _,r in ipairs(records) do
		for _,c in ipairs({r.source,r.target}) do
			reservedCells[c.id]=loan
			if not loan.keys[c.key] then loan.keys[c.key]=true;pinnedChunks[c.key]=(pinnedChunks[c.key] or 0)+1 end
		end
		local c=r.source
		removeResolvedBlock(chunks[c.key],c.cell,c.by,false)
	end
	for _,r in ipairs(records) do local c=r.source;refreshAdjacentColumns(c.cx,c.cz,c.bx,c.bz,true) end
	return loan
end

function TerrainExcavation:FinishBlockWall(loan, commit)
	if not loan or loan.done then return end
	loan.done=true
	for _,r in ipairs(loan.records) do
		local c=if commit then r.target else r.source
		local data=chunks[c.key]
		-- Pinned above: no chunk can disappear while the blocks travel.
		if data then applyPlacement(data,c.cell,c.by,r.block) end
		ChunkEdits.recordPlacement(c.key,c.cell,c.by,r.block)
		reservedCells[r.source.id],reservedCells[r.target.id]=nil,nil
	end
	for key in pairs(loan.keys) do
		local count=(pinnedChunks[key] or 1)-1
		pinnedChunks[key]=if count>0 then count else nil
	end
	for _,r in ipairs(loan.records) do
		local c=if commit then r.target else r.source
		refreshAdjacentColumns(c.cx,c.cz,c.bx,c.bz,true)
	end
end

-- Signus moves actual terrain cells. Sources stay reserved and chunks stay
-- resident until the travelling blocks have been deposited or rolled back.
function TerrainExcavation:BeginBossDisplacement(plan, destinations)
	local loan={records={},keys={},done=false}
	local function pin(c)
		if not loan.keys[c.key] then
			loan.keys[c.key]=true
			pinnedChunks[c.key]=(pinnedChunks[c.key] or 0)+1
		end
	end
	local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude
	local exclusions={workspace:FindFirstChild("GeneratedTerrain")}
	local moving=workspace:FindFirstChild("SignusMovingTerrain");if moving then table.insert(exclusions,moving) end
	overlap.FilterDescendantsInstances=exclusions
	for i,r in ipairs(plan) do
		if #loan.records>=32 then break end
		local s=wallCell(math.floor(r.position.X/STUD_SIZE),r.by,math.floor(r.position.Z/STUD_SIZE))
		local data=chunks[s.key]
		if not data or generatingChunks[s.key] or reservedCells[s.id]
			or not cellAllowed(data,s.cell,s.by,{naturalOnly=true,skipWet=true}) then continue end
		local desired=destinations[i];local target=nil
		if typeof(desired)~="Vector3" then continue end
		-- Find supported, empty ground beside the intended landing point.
		for attempt=0,24 do
			local angle=attempt*2.399963;local radius=math.ceil(attempt/8)
			local x=math.floor(desired.X/STUD_SIZE)+math.round(math.cos(angle)*radius)
			local z=math.floor(desired.Z/STUD_SIZE)+math.round(math.sin(angle)*radius)
			local seed=wallCell(x,0,z);local td=chunks[seed.key]
			if not td or generatingChunks[seed.key] or not isChunkInBounds(seed.cx,seed.cz) then continue end
			local height=td.currentHeight[seed.cell]
			if not height or td.waterTop[seed.cell]>height then continue end
			local top=height-1 -- currentHeight is the first empty cell, not the top solid cell
			for y=top+1,math.min(top+5,MAX_BLOCK_Y) do
				local t=wallCell(x,y,z)
				if reservedCells[t.id] or isPresentInData(td,t.cell,y)
					or not isPresentInData(td,t.cell,y-1) then continue end
				local occupied=false
				for _,p in ipairs(workspace:GetPartBoundsInBox(CFrame.new(t.position),Vector3.one*(STUD_SIZE-.15),overlap)) do
					if p.CanCollide or p:FindFirstAncestorOfClass("Model") and p:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") then occupied=true;break end
				end
				if not occupied then target=t;break end
			end
			if target then break end
		end
		if not target then continue end
		local name=blockNameFor(data,s.cell,s.by)
		if not removeResolvedBlock(data,s.cell,s.by,false) then continue end
		reservedCells[s.id]=loan;reservedCells[target.id]=loan
		pin(s);pin(target)
		table.insert(loan.records,{source=s,target=target,block=name})
	end
	for _,r in ipairs(loan.records) do local c=r.source;refreshAdjacentColumns(c.cx,c.cz,c.bx,c.bz,true) end
	return loan
end

function TerrainExcavation:FinishBossDisplacement(loan,commit)
	if not loan or loan.done then return end
	loan.done=true
	local characters={}
	for _,player in ipairs(Players:GetPlayers()) do if player.Character then table.insert(characters,player.Character) end end
	local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include;overlap.FilterDescendantsInstances=characters
	for _,r in ipairs(loan.records) do
		local c=if commit then r.target else r.source
		local data=chunks[c.key]
		-- Another operation may have removed the landing support while flying.
		if commit and (not data or isPresentInData(data,c.cell,c.by) or not isPresentInData(data,c.cell,c.by-1)
			or #workspace:GetPartBoundsInBox(CFrame.new(c.position),Vector3.one*(STUD_SIZE-.2),overlap)>0) then c=r.source;data=chunks[c.key] end
		if data then
			applyPlacement(data,c.cell,c.by,r.block)
			ChunkEdits.recordPlacement(c.key,c.cell,c.by,r.block)
			refreshAdjacentColumns(c.cx,c.cz,c.bx,c.bz,true)
		end
		reservedCells[r.source.id]=nil;reservedCells[r.target.id]=nil
	end
	for key in pairs(loan.keys) do
		local count=(pinnedChunks[key] or 1)-1
		pinnedChunks[key]=if count>0 then count else nil
	end
end

return TerrainExcavation
