--[[
	StationService

	Owns crafting stations as world objects: putting them down, picking them back
	up, and answering "is this player actually standing at one?"

	A ModuleScript because three systems need it and none owns it:
	PlacementServer routes Workbench items here, MiningServer asks whether a
	target is a station before falling through to terrain, and CraftingServer
	asks whether the player is in range of one.

	Stations are NOT terrain blocks: terrain is drawn from a pool of
	interchangeable parts recycled the moment they are culled, so there is
	nothing stable to hang a ProximityPrompt on. A station is a single
	persistent instance that still occupies a cell on the same block grid.

	Every check runs on the server, and range is re-checked at craft time rather
	than only when the prompt appears.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StationConfig = require(Shared:WaitForChild("Crafting"):WaitForChild("StationConfig"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))

local StationService = {}

local STUD_SIZE = TerrainConfig.StudSize
local STATION_TAG = "CraftingStation"

local TerrainManager = nil -- injected by init, to avoid a require cycle

-- gridKey -> { instance, stationId, x, y, z, ownerUserId }
local stationsByCell = {}

-- bucketKey -> { gridKey -> station }, a coarse spatial index so range queries
-- stay cheap no matter how many stations players build.
local BUCKET_BLOCKS = 8
local stationsByBucket = {}

local worldFolder = nil
local templateCache = {}
local stationCount = 0

-- ---------------------------------------------------------------------------
-- Keys
-- ---------------------------------------------------------------------------

--[[
	Cell coordinates packed into one number, so the registry needs no strings.

	The Y field is sized well past the world's actual vertical range rather than
	snugly around it. Terrain now reaches from WorldFloorY to WorldCeilingY, and
	a y outside what the packing can hold does not fail loudly - it silently
	collides with another cell and two stations start overwriting each other.
	The spare room is free; the bug would not be.
]]
local KEY_OFFSET = 8192
local KEY_Y_BIAS = 1024
local KEY_Y_SPAN = 2048

local function gridKey(x, y, z)
	return (((x + KEY_OFFSET) * KEY_Y_SPAN + (y + KEY_Y_BIAS)) * 16384) + (z + KEY_OFFSET)
end

local function bucketKey(x, z)
	return (x // BUCKET_BLOCKS + KEY_OFFSET) * 65536 + (z // BUCKET_BLOCKS + KEY_OFFSET)
end

local function cellCentre(x, y, z)
	return Vector3.new(
		x * STUD_SIZE + STUD_SIZE * 0.5,
		y * STUD_SIZE + STUD_SIZE * 0.5,
		z * STUD_SIZE + STUD_SIZE * 0.5
	)
end

-- ---------------------------------------------------------------------------
-- Templates
-- ---------------------------------------------------------------------------

--[[
	Builds the stand-in a station is placed as when there is no authored model.

	Deliberately simple geometry: a base plus a lighter top, sized to exactly one
	grid cell so it lines up with the blocks around it. Drop a model named after
	the station into TerrainAssets.Stations and this is never used again.
]]
local function buildStandIn(def)
	local appearance = def.appearance or {}

	local model = Instance.new("Model")
	model.Name = def.id

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(STUD_SIZE * 0.9, STUD_SIZE * 0.75, STUD_SIZE * 0.9)
	base.Color = appearance.color or Color3.fromRGB(120, 120, 120)
	base.Material = appearance.material or Enum.Material.WoodPlanks
	base.Anchored = true
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = model

	local top = Instance.new("Part")
	top.Name = "Top"
	top.Size = Vector3.new(STUD_SIZE, STUD_SIZE * 0.25, STUD_SIZE)
	top.Color = appearance.topColor or appearance.color or Color3.fromRGB(150, 150, 150)
	top.Material = appearance.material or Enum.Material.WoodPlanks
	top.Anchored = true
	top.TopSurface = Enum.SurfaceType.Smooth
	top.BottomSurface = Enum.SurfaceType.Smooth
	top.Parent = model

	-- Top sits on the base; the model pivot ends up at the cell centre.
	base.CFrame = CFrame.new(0, -STUD_SIZE * 0.125, 0)
	top.CFrame = CFrame.new(0, STUD_SIZE * 0.375, 0)
	model.PrimaryPart = top

	return model
end

local function getTemplate(def)
	local cached = templateCache[def.id]
	if cached ~= nil then
		return cached or nil
	end

	local authored = nil
	local assets = ReplicatedStorage:FindFirstChild("TerrainAssets")
	local folder = assets and assets:FindFirstChild(StationConfig.ModelFolderName)
	if folder then
		local candidate = folder:FindFirstChild(def.modelSource or def.id)
		if candidate and (candidate:IsA("Model") or candidate:IsA("BasePart")) then
			authored = candidate
		end
	end

	local template = authored or buildStandIn(def)
	templateCache[def.id] = template
	return template
end

-- ---------------------------------------------------------------------------
-- Registry
-- ---------------------------------------------------------------------------

local function register(station)
	local key = gridKey(station.x, station.y, station.z)
	stationsByCell[key] = station
	station.key = key

	local bucket = bucketKey(station.x, station.z)
	local list = stationsByBucket[bucket]
	if not list then
		list = {}
		stationsByBucket[bucket] = list
	end
	list[key] = station
	station.bucket = bucket

	stationCount += 1
end

local function unregister(station)
	stationsByCell[station.key] = nil

	local list = stationsByBucket[station.bucket]
	if list then
		list[station.key] = nil
		if next(list) == nil then
			stationsByBucket[station.bucket] = nil
		end
	end

	stationCount -= 1
end

--[[
	The station instance a part belongs to, or nil. Mining hands us whatever the
	player clicked, which is usually a child part of the station model.
]]
local function stationFromInstance(instance)
	if typeof(instance) ~= "Instance" or not instance:IsA("BasePart") then
		return nil
	end

	-- Every part of a station carries the cell key, so this is normally a single
	-- attribute read. The walk up only matters for an authored model that nests
	-- parts under folders.
	local current = instance
	while current and current ~= worldFolder do
		local key = current:GetAttribute("StationCellKey")
		if key then
			return stationsByCell[key]
		end
		current = current.Parent
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function StationService.init(terrainManager)
	if worldFolder then
		return
	end

	StationConfig.validate()
	TerrainManager = terrainManager

	worldFolder = workspace:FindFirstChild(StationConfig.WorldFolderName)
	if not worldFolder then
		worldFolder = Instance.new("Folder")
		worldFolder.Name = StationConfig.WorldFolderName
		worldFolder.Parent = workspace
	end
end

--[[
	Is this item one that should become a station rather than a block?
]]
function StationService.isStationItem(itemName)
	return StationConfig.get(itemName) ~= nil
end

--[[
	Places a station at a grid cell.

	Validation, in order: known station, inside the world, cell free of both
	stations and terrain, sitting on something solid, and within reach. The
	caller is responsible only for having verified the player owns the item; the
	world checks are all here so placement cannot be talked into overlapping
	terrain by a crafted remote call.

	Returns ok, reason.
]]
function StationService.place(player, blockX, by, blockZ, stationId)
	local def = StationConfig.get(stationId)
	if not def then
		return false, "Unknown station"
	end

	if type(blockX) ~= "number" or type(by) ~= "number" or type(blockZ) ~= "number" then
		return false, "Bad position"
	end

	blockX, by, blockZ = math.floor(blockX), math.floor(by), math.floor(blockZ)

	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, "No character"
	end

	local centre = cellCentre(blockX, by, blockZ)
	if (hrp.Position - centre).Magnitude > 34 then
		return false, "Too far"
	end

	if stationsByCell[gridKey(blockX, by, blockZ)] then
		return false, "Cell occupied"
	end

	if TerrainManager:IsSolidAt(blockX, by, blockZ) then
		return false, "Cell occupied"
	end

	-- Must rest on something, so stations cannot be parked in mid-air.
	if
		not TerrainManager:IsSolidAt(blockX, by - 1, blockZ)
		and not stationsByCell[gridKey(blockX, by - 1, blockZ)]
	then
		return false, "Needs support"
	end

	local template = getTemplate(def)
	if not template then
		return false, "Missing template"
	end

	local instance = template:Clone()
	local key = gridKey(blockX, by, blockZ)

	instance.Name = def.id
	instance:SetAttribute("StationId", def.id)
	instance:SetAttribute("StationCellKey", key)
	instance:SetAttribute("OwnerUserId", player.UserId)

	-- GetDescendants does not include the instance itself, so a single-part
	-- station would otherwise miss all of this.
	local parts = instance:GetDescendants()
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end

	for _, descendant in ipairs(parts) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = true
			descendant.CanQuery = true
			descendant.CanTouch = false
			descendant:SetAttribute("StationCellKey", key)
			CollectionService:AddTag(descendant, STATION_TAG)
		elseif descendant:IsA("LuaSourceContainer") then
			-- An authored model must not smuggle scripts into the live world.
			descendant:Destroy()
		end
	end

	if instance:IsA("Model") then
		-- Centre the model's BOUNDING BOX on the cell rather than its pivot. An
		-- authored model can have its pivot anywhere, and the stand-in's is on
		-- its table top; either way what should line up with the grid is the
		-- shape, not the origin someone happened to build it around.
		local bounds = instance:GetBoundingBox()
		instance:PivotTo(instance:GetPivot() + (centre - bounds.Position))
	else
		instance.CFrame = CFrame.new(centre)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UsePrompt"
	prompt.ActionText = def.actionText or "Use"
	prompt.ObjectText = def.displayName or def.id
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = def.useRange
	prompt:SetAttribute("StationId", def.id)
	prompt.Parent = if instance:IsA("Model")
		then (instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart"))
		else instance

	instance.Parent = worldFolder

	register({
		instance = instance,
		stationId = def.id,
		x = blockX,
		y = by,
		z = blockZ,
		ownerUserId = player.UserId,
	})

	return true, "Placed"
end

--[[
	Picks a station back up, if the target is one and the player can reach it.

	Returns ok, itemName. `ok == false` with no itemName means "this was not a
	station" - the caller should carry on and treat it as terrain.
]]
function StationService.tryBreak(player, target)
	local station = stationFromInstance(target)
	if not station then
		return false, nil
	end

	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, nil, "no_character"
	end

	local centre = cellCentre(station.x, station.y, station.z)
	if (hrp.Position - centre).Magnitude > 34 then
		return false, nil, "too_far"
	end

	unregister(station)
	station.instance:Destroy()

	return true, station.stationId
end

--[[
	Is this player standing close enough to a live station of the given type?

	Only buckets that can possibly be in range are scanned, so a world full of
	stations does not make every craft slower.
]]
function StationService.isNear(player, stationId)
	local def = StationConfig.get(stationId)
	if not def then
		return false
	end

	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end

	local position = hrp.Position
	local range = def.useRange
	local rangeSquared = range * range

	local blockX = math.floor(position.X / STUD_SIZE)
	local blockZ = math.floor(position.Z / STUD_SIZE)
	local reach = math.ceil(range / STUD_SIZE / BUCKET_BLOCKS) + 1

	for dx = -reach, reach do
		for dz = -reach, reach do
			local list = stationsByBucket[bucketKey(blockX + dx * BUCKET_BLOCKS, blockZ + dz * BUCKET_BLOCKS)]
			if list then
				for _, station in pairs(list) do
					if station.stationId == stationId and station.instance.Parent then
						local delta = cellCentre(station.x, station.y, station.z) - position
						if delta:Dot(delta) <= rangeSquared then
							return true
						end
					end
				end
			end
		end
	end

	return false
end

--[[
	Does the grid cell hold a station? Terrain placement asks this so a block
	cannot be built inside one.
]]
function StationService.isCellOccupied(blockX, by, blockZ)
	return stationsByCell[gridKey(blockX, by, blockZ)] ~= nil
end

function StationService.getStats()
	return { stations = stationCount }
end

return StationService
