--[[
	PlacementServer

	Validates a build request and hands it to whichever system owns the result.

	  classification "Block"      -> TerrainManager, as a real terrain block
	  classification "Workbench"  -> StationService, as a crafting station

	Blocks go INTO the terrain rather than into a loose folder, so a placed
	block is mineable, hides the faces behind it, is pooled like any other, and
	survives its chunk streaming out and back in (see Terrain.ChunkEdits).

	The client sends a slot index and a grid cell. This decides whether the slot
	really holds a placeable item; TerrainManager and StationService decide
	whether the cell is free, supported, in the world and in reach. The item is
	consumed only after the block exists, so a refusal never costs materials.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local BlockConfig = require(Shared:WaitForChild("Blocks"):WaitForChild("BlockConfig"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local ChunkEdits = require(Shared.Terrain:WaitForChild("ChunkEdits"))
local IslandConfig = require(Shared.Terrain:WaitForChild("IslandConfig"))
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))

local IS_ISLAND = PlaceConfig.isIsland()

local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
local StationService = require(ServerScriptService:WaitForChild("StationService"))

local RequestPlaceBlock = Remotes.ensure("RequestPlaceBlock", "RemoteEvent")
local PlacementResult = Remotes.ensure("PlacementResult", "RemoteEvent")

StationService.init(TerrainManager)

local GRID_SIZE = TerrainConfig.StudSize
local MIN_REQUEST_INTERVAL = 0.06

local lastRequestTime = {}

local function sendResult(player, success, message)
	PlacementResult:FireClient(player, success, message)
end

--[[
	The placement grid and the terrain block grid are the same grid: a block at
	block coordinates (x, y, z) is centred at ((x + 0.5) * StudSize, ...). The
	client may send either a world position or the indices directly.
]]
local function toGridCell(a, b, c)
	if typeof(a) == "Vector3" and b == nil and c == nil then
		return math.floor(a.X / GRID_SIZE),
			math.floor(a.Y / GRID_SIZE),
			math.floor(a.Z / GRID_SIZE)
	end

	if type(a) == "number" and type(b) == "number" and type(c) == "number" then
		return math.floor(a + 0.5), math.floor(b + 0.5), math.floor(c + 0.5)
	end

	return nil
end

Players.PlayerRemoving:Connect(function(player)
	lastRequestTime[player] = nil
end)

RequestPlaceBlock.OnServerEvent:Connect(function(player, slotIndex, a, b, c)
	local now = os.clock()
	local last = lastRequestTime[player]
	if last and now - last < MIN_REQUEST_INTERVAL then
		return
	end
	lastRequestTime[player] = now

	if type(slotIndex) ~= "number" then
		sendResult(player, false, "Bad slot")
		return
	end

	slotIndex = math.floor(slotIndex)
	if slotIndex < 1 then
		sendResult(player, false, "Bad slot")
		return
	end

	local ix, iy, iz = toGridCell(a, b, c)
	if not ix then
		sendResult(player, false, "Bad position")
		return
	end

	local itemName, count = InventoryService.GetSlot(player, slotIndex)
	if not itemName or count <= 0 then
		sendResult(player, false, "Empty slot")
		return
	end

	-- An island stores every change in one save, which has a size limit. Mining
	-- is never refused - the island bounds it - but building past the limit is.
	if IS_ISLAND and ChunkEdits.getStats().totalEdits >= IslandConfig.MaxEdits then
		sendResult(player, false, "Your island has reached its build limit")
		return
	end

	local placed, reason

	if StationService.isStationItem(itemName) then
		placed, reason = StationService.place(player, ix, iy, iz, itemName)
	elseif BlockConfig.isPlaceable(itemName) then
		if StationService.isCellOccupied(ix, iy, iz) then
			placed, reason = false, "Cell occupied"
		else
			placed, reason = TerrainManager:PlaceBlock(player, ix, iy, iz, itemName)
		end
	else
		placed, reason = false, "Not placeable"
	end

	if not placed then
		sendResult(player, false, reason)
		return
	end

	-- The block exists now, so the item has to go. If this somehow fails the
	-- player would be duplicating blocks, so it is loud rather than silent.
	if not InventoryService.RemoveItemByName(player, itemName, 1) then
		warn(string.format(
			"[PlacementServer] Placed %s for %s but could not consume it.", itemName, player.Name
		))
	end

	sendResult(player, true, "Placed")
end)
