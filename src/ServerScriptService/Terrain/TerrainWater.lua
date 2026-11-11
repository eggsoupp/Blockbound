--[[
	TerrainWater

	Water as Roblox Terrain voxels: written per chunk as it is built, per
	column after an edit, and cleared as the chunk unloads. Part of
	TerrainManager; see TerrainManager for the map of terrain modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local TerrainGrid = require(TerrainShared:WaitForChild("TerrainGrid"))

local ChunkData = require(script.Parent:WaitForChild("ChunkData"))

local TerrainWater = {}

local STUD_SIZE = TerrainConfig.StudSize
local CHUNK_SIZE = TerrainConfig.ChunkSize
local CHUNK_AREA = TerrainGrid.CHUNK_AREA

local cellOf = TerrainGrid.cellOf
local isPresentInData = ChunkData.isPresentInData

--[[
	Water is Roblox Terrain, not blocks.

	It used to be drawn like any other block - see-through Parts, culled to the
	band a viewer could see - and that could never work as water:

	  * nobody can swim in a Part. Humanoids only swim in Terrain water, which
	    is also what gives the underwater tint and the swim animation;
	  * culling drew a lake as a skin one block deep, so diving through the
	    surface left you standing in nothing;
	  * every seam between two transparent Parts showed through.

	Terrain voxels are four studs, exactly a block, so a water cell is one voxel
	and the two grids agree everywhere. Water fills [currentHeight, waterTop) in
	a column, except for any cell holding a block - which is how a block placed
	in a lake displaces the water around it, and a lake bed mined out fills in.

	The server writes it; it replicates to every client like any other terrain.
	A chunk's water is written once when the chunk is built, one column at a time
	after each edit, and cleared when the chunk unloads. data.waterLow/waterHigh
	remember how far down and up this chunk has ever written, so unloading can
	clear exactly that.
]]
local TerrainVoxels = workspace.Terrain
local WATER_MATERIAL = Enum.Material.Water
local AIR_MATERIAL = Enum.Material.Air

--[[
	Writes a box of voxels, in BLOCK coordinates, as water wherever
	isWet(ix, iy, iz) says (0-based offsets into the box) and air elsewhere.
]]
local function writeWaterBox(minX, minY, minZ, sizeX, sizeY, sizeZ, isWet)
	if sizeX <= 0 or sizeY <= 0 or sizeZ <= 0 then
		return
	end

	local materials = table.create(sizeX)
	local occupancy = table.create(sizeX)

	for ix = 0, sizeX - 1 do
		local materialX = table.create(sizeY)
		local occupancyX = table.create(sizeY)
		materials[ix + 1] = materialX
		occupancy[ix + 1] = occupancyX

		for iy = 0, sizeY - 1 do
			local materialY = table.create(sizeZ)
			local occupancyY = table.create(sizeZ)
			materialX[iy + 1] = materialY
			occupancyX[iy + 1] = occupancyY

			for iz = 0, sizeZ - 1 do
				local wet = isWet(ix, iy, iz)
				materialY[iz + 1] = if wet then WATER_MATERIAL else AIR_MATERIAL
				occupancyY[iz + 1] = if wet then 1 else 0
			end
		end
	end

	local low = Vector3.new(minX, minY, minZ) * STUD_SIZE
	local high = Vector3.new(minX + sizeX, minY + sizeY, minZ + sizeZ) * STUD_SIZE
	TerrainVoxels:WriteVoxels(Region3.new(low, high), STUD_SIZE, materials, occupancy)
end

local function isWaterCell(data, cell, by)
	return by >= data.currentHeight[cell]
		and by < data.waterTop[cell]
		and not isPresentInData(data, cell, by)
end

local function widenWaterSpan(data, low, high)
	if not data.waterLow or low < data.waterLow then
		data.waterLow = low
	end
	if not data.waterHigh or high > data.waterHigh then
		data.waterHigh = high
	end
end

-- Every wet column of a freshly built chunk, in one write.
local function syncChunkWater(data)
	local low, high = math.huge, -math.huge
	for cell = 1, CHUNK_AREA do
		local bottom = data.currentHeight[cell]
		local top = data.waterTop[cell]
		if top > bottom then
			if bottom < low then
				low = bottom
			end
			if top > high then
				high = top
			end
		end
	end

	if low >= high then
		return -- a dry chunk, which is nearly all of them
	end

	widenWaterSpan(data, low, high)

	writeWaterBox(data.minBlockX, low, data.minBlockZ, CHUNK_SIZE, high - low, CHUNK_SIZE, function(ix, iy, iz)
		return isWaterCell(data, cellOf(ix, iz), low + iy)
	end)
end

--[[
	One column after an edit. Covers everything from the column's current floor
	to its water surface, so a block placed in the water clears its cell and a
	mined-out lake bed fills.
]]
local function syncColumnWater(data, cell)
	local bottom = data.currentHeight[cell]
	local top = data.waterTop[cell]
	if top <= bottom then
		return -- dry, and nothing here was ever water
	end

	widenWaterSpan(data, bottom, top)

	local index = cell - 1
	writeWaterBox(
		data.minBlockX + index // CHUNK_SIZE, bottom, data.minBlockZ + index % CHUNK_SIZE,
		1, top - bottom, 1,
		function(_, iy)
			return isWaterCell(data, cell, bottom + iy)
		end
	)
end

-- Removes everything this chunk ever wrote, as it unloads.
local function clearChunkWater(data)
	if not data.waterLow then
		return
	end

	writeWaterBox(
		data.minBlockX, data.waterLow, data.minBlockZ,
		CHUNK_SIZE, data.waterHigh - data.waterLow, CHUNK_SIZE,
		function()
			return false
		end
	)

	data.waterLow, data.waterHigh = nil, nil
end

-- Water is Terrain; its look is Terrain's. Applied once at Init.
function TerrainWater.applyLook()
	local waterLook = TerrainConfig.Water
	TerrainVoxels.WaterColor = waterLook.Color
	TerrainVoxels.WaterTransparency = waterLook.Transparency
	TerrainVoxels.WaterReflectance = waterLook.Reflectance
	TerrainVoxels.WaterWaveSize = waterLook.WaveSize
	TerrainVoxels.WaterWaveSpeed = waterLook.WaveSpeed
end

TerrainWater.syncChunkWater = syncChunkWater
TerrainWater.syncColumnWater = syncColumnWater
TerrainWater.clearChunkWater = clearChunkWater

return TerrainWater
