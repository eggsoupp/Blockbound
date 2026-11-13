--[[
	BlockEdits

	Player-facing block edits: resolving what a click points at (never trusting
	the client past its own reach), inspecting, breaking and placing a block,
	and the single removal path every server-side excavation shares. Part of
	TerrainManager; see TerrainManager for the map of terrain modules.

	Methods are written with `:` because TerrainManager exposes them as its own
	(TerrainManager.BreakBlock = BlockEdits.BreakBlock); `self` is unused.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))
local ChunkEdits = require(TerrainShared:WaitForChild("ChunkEdits"))
local BlockConfig = require(Shared:WaitForChild("Blocks"):WaitForChild("BlockConfig"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local WorldZones = require(TerrainShared:WaitForChild("WorldZones"))
local OreRegistry = require(TerrainShared:WaitForChild("OreRegistry"))
local CaveDecor = require(TerrainShared:WaitForChild("CaveDecor"))

local ChunkData = require(script.Parent:WaitForChild("ChunkData"))
local OreDepletion = require(script.Parent:WaitForChild("OreDepletion"))
local BlockParts = require(script.Parent:WaitForChild("BlockParts"))
local ChunkMesher = require(script.Parent:WaitForChild("ChunkMesher"))
local ColumnVisibility = require(script.Parent:WaitForChild("ColumnVisibility"))
local EditZones = require(script.Parent:WaitForChild("EditZones"))

local BlockEdits = {}

local STUD_SIZE = TerrainConfig.StudSize
local CHUNK_SIZE = TerrainConfig.ChunkSize
local FLOOR_Y = TerrainConfig.WorldFloorY
local MAX_BLOCK_Y = TerrainConfig.WorldCeilingY
local MAX_REACH_STUDS = 34
local DIR_X = TerrainGrid.DIR_X
local DIR_Z = TerrainGrid.DIR_Z

local chunks = ChunkData.chunks
local reservedCells = ChunkData.reservedCells
local isPresentInData = ChunkData.isPresentInData
local isBlockPresent = ChunkData.isBlockPresent
local markDisturbed = ChunkData.markDisturbed
local blockNameFor = ChunkData.blockNameFor
local markRemoved = ChunkData.markRemoved
local applyPlacement = ChunkData.applyPlacement
local noteSolidChange = ChunkData.noteSolidChange
local chunkKey = TerrainGrid.chunkKey
local isChunkInBounds = TerrainGrid.isChunkInBounds
local isBlockInWorld = TerrainGrid.isBlockInWorld
local normalizeCell = TerrainGrid.normalizeCell
local worldToChunkLocal = TerrainGrid.worldToChunkLocal
local cellOf = TerrainGrid.cellOf
local partRect = BlockParts.partRect
local getBlockPartTemplate = BlockParts.getBlockPartTemplate
local clearVisible = ChunkMesher.clearVisible
local refreshAdjacentColumns = ColumnVisibility.refreshAdjacentColumns
local openEditZone = EditZones.open
local isProtected = WorldZones.isProtected
local isStarter = WorldZones.isStarter
local isOre = OreRegistry.isOre
local isCollectibleDecor = CaveDecor.isCollectible
local stackOf = CaveDecor.stackOf
local STARTER_BUILD_HEIGHT = WorldZones.StarterBuildHeight

-- Ore taken in the open world is remembered so regrown rock does not carry
-- it again (OreDepletion). An island never regrows, so it has no need.
local TRACK_ORE = WorldZones.enabled

--[[
	SPAWN ZONES (Shared.Terrain.WorldZones)

	The protected core is enforced at the two places every terrain change
	passes: removeResolvedBlock for anything taken away - a pickaxe, a crater,
	a boss bite, a wall's source blocks - and buildRefusal for anything put
	down. A caller that plans ahead (TerrainExcavation) asks isProtected itself
	so it never promises ground it will be refused.
]]

-- Why a block may not be put at this cell of a loaded chunk, or nil if it may.
local function buildRefusal(data, cell, blockX, by, blockZ)
	if isProtected(blockX, blockZ) then
		return "The spawn area is protected"
	end

	if isStarter(blockX, blockZ) then
		local ground = math.max(data.height[cell], data.waterTop[cell])
		if by >= ground + STARTER_BUILD_HEIGHT then
			return "Too high to build this close to spawn"
		end
	end

	return nil
end

--[[
	Resolves a block from a world position alone, trusting nothing about which
	part the caller named.

	Searches outward from the block the click landed in rather than scanning the
	whole column: with a 190-block-deep world a full scan would be the most
	expensive thing mining does, and it would get worse every time the floor is
	lowered.
]]
local function resolveByPosition(clickPos)
	local cx, cz, bx, bz = worldToChunkLocal(clickPos.X, clickPos.Z)
	if not isChunkInBounds(cx, cz) then
		return nil
	end

	local data = chunks[chunkKey(cx, cz)]
	if not data then
		return nil
	end

	local cell = cellOf(bx, bz)
	local scanTop = data.topScan[cell]
	local guess = math.floor(clickPos.Y / STUD_SIZE)

	local function candidate(by)
		return by >= FLOOR_Y and by < scanTop and isPresentInData(data, cell, by)
	end

	if candidate(guess) then
		return data, cell, guess
	end

	for radius = 1, 2 do
		if candidate(guess - radius) then
			return data, cell, guess - radius
		end
		if candidate(guess + radius) then
			return data, cell, guess + radius
		end
	end

	return nil
end

--[[
	Resolves a mining target to (chunk, cell, by).

	ONE PART IS NO LONGER ONE BLOCK. A part covers a rectangle of identical
	blocks, so knowing which part was hit is not enough - the position within it
	decides which block the player actually pointed at.

	That position comes from the client, and it is CLAMPED to the rectangle
	before it is used. So the worst a lying client can do is pick a different
	block inside the part it genuinely clicked, which it could always do by
	aiming a few studs over. It cannot reach past the part, cannot reach a
	different chunk, and cannot reach anything out of range - validateReach has
	already run against the same position.

	The staleness guard is Parent rather than an identity check against the
	stored cell: releasePart unparents and clears the rect together, so a part
	that is still parented to the chunk it claims is still drawing that
	rectangle. A part reused from the pool has had its rect overwritten.
]]
local function resolveTarget(targetPart, clickPos)
	if targetPart and clickPos then
		local rect = partRect[targetPart]

		if rect and isChunkInBounds(rect.cx, rect.cz) then
			local data = chunks[chunkKey(rect.cx, rect.cz)]

			if data and targetPart.Parent == data.model then
				local minBlockX = rect.cx * CHUNK_SIZE + rect.bx
				local minBlockZ = rect.cz * CHUNK_SIZE + rect.bz

				-- The claimed hit point must actually lie on this rectangle.
				--
				-- Without this the clamp below would be an exploit rather than a
				-- safeguard: a client could name a distant part, claim a hit
				-- point next to their own feet to satisfy the reach check, and
				-- have it clamped into the far rectangle. Requiring both to be
				-- true of the SAME point closes that - a point cannot be within
				-- reach of the player and on a part they cannot reach.
				--
				-- Half a stud of slack because a click lands exactly on a face.
				local minX = minBlockX * STUD_SIZE - 0.5
				local minZ = minBlockZ * STUD_SIZE - 0.5
				local maxX = (minBlockX + rect.sizeX) * STUD_SIZE + 0.5
				local maxZ = (minBlockZ + rect.sizeZ) * STUD_SIZE + 0.5
				local minY = rect.by * STUD_SIZE - 0.5
				local maxY = (rect.by + 1) * STUD_SIZE + 0.5

				local onRect = clickPos.X >= minX and clickPos.X <= maxX
					and clickPos.Y >= minY and clickPos.Y <= maxY
					and clickPos.Z >= minZ and clickPos.Z <= maxZ

				if not onRect then
					-- Fall through to resolving purely from the position, which
					-- trusts nothing about which part was named.
					return resolveByPosition(clickPos)
				end

				local blockX = math.clamp(
					math.floor(clickPos.X / STUD_SIZE), minBlockX, minBlockX + rect.sizeX - 1
				)
				local blockZ = math.clamp(
					math.floor(clickPos.Z / STUD_SIZE), minBlockZ, minBlockZ + rect.sizeZ - 1
				)

				local cell = cellOf(blockX - rect.cx * CHUNK_SIZE, blockZ - rect.cz * CHUNK_SIZE)
				local by = rect.by

				if isPresentInData(data, cell, by) then
					return data, cell, by
				end
			end
		end
	end

	-- No usable part, or the named part did not hold up. Resolve from position.
	if not clickPos then
		return nil
	end

	return resolveByPosition(clickPos)
end

--[[
	Turns whatever the caller handed us - a rendered part, or a world position -
	into a point in space. Shared by the two entry points below so they can never
	disagree about which block a request refers to.
]]
local function toClickPosition(wx, wy, wz)
	if typeof(wx) == "Instance" then
		-- A part plus the point on it that was hit. Required now that one part
		-- can cover a whole run of blocks: its centre would resolve to the
		-- middle of the run rather than to the block the player aimed at. The
		-- position is clamped to the part's own rectangle in resolveTarget, so
		-- accepting it from the caller does not widen what a client can reach.
		if typeof(wy) == "Vector3" then
			return wx, wy
		end

		if wx:IsA("BasePart") then
			return wx, wx.Position
		end
		if wx:IsA("Model") then
			local primary = wx.PrimaryPart or wx:FindFirstChildWhichIsA("BasePart")
			return wx, primary and primary.Position or nil
		end
		return wx, nil
	end

	if typeof(wx) == "number" and typeof(wy) == "number" and typeof(wz) == "number" then
		return nil, Vector3.new(wx, wy, wz)
	end

	return nil, nil
end

--[[
	Server-authoritative reach check. Returns the click position only if the
	player is genuinely standing next to it.
]]
local function validateReach(player, clickPos)
	if not clickPos then
		return false, "bad_target"
	end

	if not (player and typeof(player) == "Instance" and player:IsA("Player")) then
		return false, "no_player"
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, "no_character"
	end

	if (hrp.Position - clickPos).Magnitude > MAX_REACH_STUDS then
		return false, "too_far"
	end

	return true
end

--[[
	What block is the player pointing at, without touching it?

	Mining needs this before it starts its timer: how long a block takes to break
	is a property of the block, and the server has to decide that rather than
	take the client's word for it.

	Returns blockName, itemName (what it would drop), reason, resolved cell centre.
]]
function BlockEdits:InspectBlock(wx, wy, wz, initiator)
	local targetPart, clickPos = toClickPosition(wx, wy, wz)

	local ok, reason = validateReach(initiator, clickPos)
	if not ok then
		return nil, nil, reason
	end

	local data, cell, by = resolveTarget(targetPart, clickPos)
	if not data then
		return nil, nil, "no_block"
	end

	local index = cell - 1

	-- No block name either: a caller that only checks for one (MiningServer)
	-- then never starts a swing at ground it cannot break.
	if isProtected(data.minBlockX + index // CHUNK_SIZE, data.minBlockZ + index % CHUNK_SIZE) then
		return nil, nil, "protected"
	end

	local blockName = blockNameFor(data, cell, by)
	if BlockConfig.isUnbreakable(blockName) then
		return blockName, nil, "unbreakable"
	end

	local centre = Vector3.new(
		(data.minBlockX + index // CHUNK_SIZE + 0.5) * STUD_SIZE,
		(by + 0.5) * STUD_SIZE,
		(data.minBlockZ + index % CHUNK_SIZE + 0.5) * STUD_SIZE
	)
	return blockName, BlockConfig.getDrop(blockName), "ok", centre
end

--[[
	Removes one block.

	Accepts either a rendered part or world coordinates, and returns
	(ok, itemName, reason). itemName is what the player should receive, which is
	BlockConfig's business, not the caller's.
]]
local function removeResolvedBlock(data, cell, by, refresh)
	local index = cell - 1
	if isProtected(data.minBlockX + index // CHUNK_SIZE, data.minBlockZ + index % CHUNK_SIZE) then
		return false, nil, "protected"
	end

	local blockName = blockNameFor(data, cell, by)
	if BlockConfig.isUnbreakable(blockName) then
		return false, nil, "unbreakable"
	end

	local key = chunkKey(data.cx, data.cz)
	local extra = data.extra[cell]

	if extra and extra[by] then
		-- A block sitting above the terrain: either a structure's, or one a
		-- player put there. Those are remembered differently, because forgetting
		-- a placement restores the ground beneath it while a structure block has
		-- to be actively suppressed on the next regeneration.
		if ChunkEdits.isPlaced(key, cell, by) then
			ChunkEdits.clearPlacement(key, cell, by)
		else
			ChunkEdits.recordRemoval(key, cell, by)
		end

		extra[by] = nil
		markDisturbed(data, cell, by)
		noteSolidChange(data, cell, by)
	else
		local override = data.override[cell]
		if override and override[by] then
			override[by] = nil
		end

		ChunkEdits.recordRemoval(key, cell, by)
		markRemoved(data, cell, by)

		-- Generated ore, whoever took it and whether or not it paid out; and
		-- the cave decorations that yield an item, which are a resource in
		-- exactly the same way.
		if TRACK_ORE and (isOre(blockName) or isCollectibleDecor(blockName)) then
			data.oreGone = OreDepletion.record(key, cell, by)
		end
	end

	-- The block stops being drawn; refreshAdjacentColumns below re-derives the
	-- rest of the column and its neighbours and rebuilds the affected layers in
	-- one pass. Releasing an individual Part here would be wrong now - the Part
	-- covering this block probably covers several others that are still there.
	clearVisible(data, cell, by)

	if refresh ~= false then
		refreshAdjacentColumns(data.cx, data.cz, index // CHUNK_SIZE, index % CHUNK_SIZE)
	end

	return true, BlockConfig.getDrop(blockName), "ok"
end

function BlockEdits:BreakBlock(wx, wy, wz, initiator)
	Profiler.enter("Terrain.breakBlock")

	local function finish(ok, item, reason)
		Profiler.leave("Terrain.breakBlock")
		return ok, item, reason
	end

	local targetPart, clickPos = toClickPosition(wx, wy, wz)

	local reachOk, reachReason = validateReach(initiator, clickPos)
	if not reachOk then
		return finish(false, nil, reachReason)
	end

	local data, cell, by = resolveTarget(targetPart, clickPos)
	if not data then
		return finish(false, nil, "no_block")
	end

	-- Usually already open from when the swing started (OpenEditZone); this
	-- covers anything that breaks blocks without one, and keeps it alive.
	local index = cell - 1
	openEditZone(data.minBlockX + index // CHUNK_SIZE, data.minBlockZ + index % CHUNK_SIZE)

	-- A cave decoration several blocks tall is one piece: breaking any of
	-- its blocks takes the rest, so no icicle tip is left in mid-air.
	local stack, segment = stackOf(blockNameFor(data, cell, by))

	local ok, item, reason = removeResolvedBlock(data, cell, by, stack == nil)
	if stack and ok then
		for k = 1, #stack do
			local y = by - segment + k
			if k ~= segment and blockNameFor(data, cell, y) == stack[k] then
				removeResolvedBlock(data, cell, y, false)
			end
		end
		refreshAdjacentColumns(data.cx, data.cz, index // CHUNK_SIZE, index % CHUNK_SIZE)
	end
	return finish(ok, item, reason)
end

--[[
	Opens an edit zone around a world position (see EDIT ZONES). MiningServer
	calls it when a swing STARTS, so the ground around the target is already
	split into single blocks - and the layer under it drawn - by the time the
	block breaks, and the swing time is the warning clients get.
]]
function BlockEdits:OpenEditZone(position: Vector3)
	if typeof(position) ~= "Vector3" then
		return
	end
	openEditZone(math.floor(position.X / STUD_SIZE), math.floor(position.Z / STUD_SIZE))
end

--[[
	Puts a block down.

	Player placement goes through the same chunk data and the same renderer as
	generated terrain, which is the whole point: a placed block is then mineable,
	occludes and is occluded correctly, and is culled and pooled like everything
	else. It used to be a separate folder of loose parts, which is why mining one
	broke the terrain underneath it instead.

	Every check here is server-side. The caller supplies a grid cell and a block
	name; nothing about the client's view of the world is trusted.
]]
function BlockEdits:PlaceBlock(player, blockX, by, blockZ, blockName)
	Profiler.enter("Terrain.placeBlock")

	local function finish(ok, reason)
		Profiler.leave("Terrain.placeBlock")
		return ok, reason
	end

	if type(blockX) ~= "number" or type(by) ~= "number" or type(blockZ) ~= "number" then
		return finish(false, "Bad position")
	end

	blockX = math.floor(blockX)
	by = math.floor(by)
	blockZ = math.floor(blockZ)

	if by < FLOOR_Y or by > MAX_BLOCK_Y then
		return finish(false, "Out of range")
	end

	if not isBlockInWorld(blockX, blockZ) then
		return finish(false, "Outside the world")
	end

	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return finish(false, "No character")
	end

	local centre = Vector3.new(
		blockX * STUD_SIZE + STUD_SIZE * 0.5,
		by * STUD_SIZE + STUD_SIZE * 0.5,
		blockZ * STUD_SIZE + STUD_SIZE * 0.5
	)
	if (hrp.Position - centre).Magnitude > MAX_REACH_STUDS then
		return finish(false, "Too far")
	end

	-- Not inside yourself. The client's preview cannot see the character - it
	-- filters it out of its own raycast - so aiming down at your feet asks for
	-- a block in the cell you are standing in, which seals you in.
	local characterCF, characterSize = character:GetBoundingBox()
	local gap = characterCF.Position - centre
	local halfX = characterSize.X * 0.5 + STUD_SIZE * 0.5
	local halfY = characterSize.Y * 0.5 + STUD_SIZE * 0.5
	local halfZ = characterSize.Z * 0.5 + STUD_SIZE * 0.5
	if
		math.abs(gap.X) < halfX
		and math.abs(gap.Y) < halfY
		and math.abs(gap.Z) < halfZ
	then
		return finish(false, "You are standing there")
	end

	local cx, cz, bx, bz = normalizeCell(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE,
		blockX % CHUNK_SIZE, blockZ % CHUNK_SIZE)

	local key = chunkKey(cx, cz)
	local data = chunks[key]
	if not data then
		return finish(false, "Area not loaded")
	end

	local cell = cellOf(bx, bz)

	local refusal = buildRefusal(data, cell, blockX, by, blockZ)
	if refusal then
		return finish(false, refusal)
	end

	if reservedCells[key..":"..cell..":"..by] then return finish(false,"A block is moving here") end
	if isPresentInData(data, cell, by) then
		return finish(false, "Cell occupied")
	end

	-- A block has to touch something, so players cannot build floating islands
	-- out in the air.
	local supported = false
	for i = 1, 4 do
		if isBlockPresent(cx, cz, bx + DIR_X[i], bz + DIR_Z[i], by) then
			supported = true
			break
		end
	end
	if not supported then
		supported = isBlockPresent(cx, cz, bx, bz, by + 1)
			or isBlockPresent(cx, cz, bx, bz, by - 1)
	end
	if not supported then
		return finish(false, "Needs support")
	end

	if not getBlockPartTemplate(blockName) then
		return finish(false, "Missing template")
	end

	-- Before the edit, so the ground around it is already drawn block by block
	-- when it changes. See EDIT ZONES.
	openEditZone(blockX, blockZ)

	applyPlacement(data, cell, by, blockName)
	ChunkEdits.recordPlacement(key, cell, by, blockName)

	refreshAdjacentColumns(cx, cz, bx, bz)
	return finish(true, "Placed")
end

--[[
	Is there a solid block at this grid cell? Used by the placement preview path
	and by station placement, so both agree with the renderer about what is where.
]]
function BlockEdits:IsSolidAt(blockX, by, blockZ)
	if by < FLOOR_Y or by > MAX_BLOCK_Y or not isBlockInWorld(blockX, blockZ) then
		return false
	end

	local cx, cz, bx, bz = normalizeCell(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE,
		blockX % CHUNK_SIZE, blockZ % CHUNK_SIZE)

	return isBlockPresent(cx, cz, bx, bz, by)
end

--[[
	May something be built into this grid cell, as far as the spawn zones are
	concerned? Returns ok, reason. For builders that are not terrain blocks
	(StationService), so stations obey the same zones as blocks do.
]]
function BlockEdits:CheckBuildZone(blockX, by, blockZ)
	if not isStarter(blockX, blockZ) then
		return true
	end

	local cx, cz, bx, bz = normalizeCell(blockX // CHUNK_SIZE, blockZ // CHUNK_SIZE,
		blockX % CHUNK_SIZE, blockZ % CHUNK_SIZE)
	local data = chunks[chunkKey(cx, cz)]
	if not data then
		return false, "Area not loaded"
	end

	local refusal = buildRefusal(data, cellOf(bx, bz), blockX, by, blockZ)
	return refusal == nil, refusal
end

BlockEdits.removeResolvedBlock = removeResolvedBlock

return BlockEdits
