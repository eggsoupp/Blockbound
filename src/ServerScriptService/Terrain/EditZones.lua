--[[
	EditZones

	Opens, extends and closes the edit zones around mining and placement, in
	which every block is its own Part and the layers just below are drawn too.
	Part of TerrainManager; see TerrainManager for the map of terrain modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))

local ChunkData = require(script.Parent:WaitForChild("ChunkData"))
local ChunkMesher = require(script.Parent:WaitForChild("ChunkMesher"))
local ColumnVisibility = require(script.Parent:WaitForChild("ColumnVisibility"))

local EditZones = {}

local CHUNK_SIZE = TerrainConfig.ChunkSize

local chunks = ChunkData.chunks
local generatingChunks = ChunkData.generating
local chunkKey = TerrainGrid.chunkKey
local normalizeCell = TerrainGrid.normalizeCell
local cellOf = TerrainGrid.cellOf
local markLayerDirty = ChunkMesher.markLayerDirty
local flushChunks = ChunkMesher.flushChunks
local updateColumnVisibility = ColumnVisibility.updateColumnVisibility

--[[
	EDIT ZONES

	Merging is what keeps the part count affordable, and it is also what makes
	editing jitter: break one block out of a slab and the slab has to become
	several new Parts, which every client receives a moment after the old slab
	went. At an end-game mining speed that is a visible flicker every swing, and
	a floor that can vanish under you.

	So the ground around an edit is drawn differently for a while:

	  * every block is its own Part - breaking one removes exactly that Part,
	    and nothing else on screen changes;
	  * the layers just under the exposed ones are drawn too (EditZone.Depth),
	    hidden behind the surface. The block a break uncovers is therefore
	    already standing on every client before the break happens; the only
	    new Parts an edit needs are the ones it will uncover NEXT time.

	A zone is opened around a mining target when the swing starts (MiningServer)
	and around every break and placement, and lasts EditZone.Seconds after the
	last one, after which it merges back into slabs.

	data.hot[cell] is when that column's zone time runs out.
]]
local EDIT_ZONE = TerrainConfig.EditZone
local EDIT_RADIUS = EDIT_ZONE.Radius
local EDIT_SECONDS = EDIT_ZONE.Seconds

-- Redraws one column for a zone opening or closing on it: the visibility
-- pass picks up the change in depth, and every layer it draws is remeshed so
-- its blocks are split out of (or merged back into) the slabs around them.
local function redrawZoneColumn(data, cell, touched)
	local index = cell - 1
	updateColumnVisibility(data.cx, data.cz, index // CHUNK_SIZE, index % CHUNK_SIZE)
	for by in pairs(data.visible[cell]) do
		markLayerDirty(data, by)
	end
	touched[data] = true
end

local function flushTouched(touched)
	local list = {}
	for data in pairs(touched) do
		table.insert(list, data)
	end
	flushChunks(list)
end

--[[
	Opens (or extends) an edit zone around a block position. Columns already
	in a zone just get more time; only newly zoned ones are redrawn, so calling
	this on every swing costs next to nothing once the zone exists.
]]
local function openEditZone(blockX, blockZ)
	local expiresAt = os.clock() + EDIT_SECONDS
	local touched = {}

	for dx = -EDIT_RADIUS, EDIT_RADIUS do
		for dz = -EDIT_RADIUS, EDIT_RADIUS do
			local x, z = blockX + dx, blockZ + dz
			local cx, cz, bx, bz = normalizeCell(x // CHUNK_SIZE, z // CHUNK_SIZE, x % CHUNK_SIZE, z % CHUNK_SIZE)
			local key = chunkKey(cx, cz)
			local data = chunks[key]

			if data and not generatingChunks[key] then
				local cell = cellOf(bx, bz)
				local was = data.hot[cell]
				data.hot[cell] = expiresAt

				if not was then
					data.hotCount += 1
					redrawZoneColumn(data, cell, touched)
				end
			end
		end
	end

	flushTouched(touched)
end

-- Merges zones nobody has edited in EditZone.Seconds back into slabs.
local lastZoneSweep = 0

local function closeExpiredEditZones()
	local now = os.clock()
	if now - lastZoneSweep < 1 then
		return
	end
	lastZoneSweep = now

	local touched = {}

	for key, data in pairs(chunks) do
		if data.hotCount > 0 and not generatingChunks[key] then
			for cell, expiresAt in pairs(data.hot) do
				if expiresAt <= now then
					data.hot[cell] = nil
					data.hotCount -= 1
					redrawZoneColumn(data, cell, touched)
				end
			end
		end
	end

	flushTouched(touched)
end

EditZones.open = openEditZone
EditZones.closeExpired = closeExpiredEditZones

return EditZones
