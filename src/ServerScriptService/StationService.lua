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

	STORAGE STATIONS (a chest: StationConfig `storage`) carry their contents
	on their own record, `station.items` - { [slot] = { name, count } } - so
	they are exported, saved and restored with the station rather than kept
	somewhere that could disagree with it. ChestServer is what changes them.
	A storage station is marked StorageId instead of StationId, which is what
	keeps the crafting window from treating it as a bench, and it refuses to
	be picked up while anything is in it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StationConfig = require(Shared:WaitForChild("Crafting"):WaitForChild("StationConfig"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))

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

-- Forward declared: place and restore both build through it, and it is
-- defined below them with the rest of the public API.
local spawnStation

-- See StationService.setChangeListener.
local changeListener = nil

local function notifyChanged()
	if changeListener then
		changeListener()
	end
end

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
-- Storage contents
-- ---------------------------------------------------------------------------

-- Whether a storage station's contents hold anything at all.
local function holdsItems(items)
	if type(items) ~= "table" then
		return false
	end
	for _, stack in pairs(items) do
		if type(stack) == "table" and stack.name and (stack.count or 0) > 0 then
			return true
		end
	end
	return false
end

--[[
	A saved list - { { slot, name, count }, ... } - back into the slot map,
	dropping anything outside the station's slots or not shaped like a stack.
	What an item IS is ChestServer's to judge when it is moved; here it only
	has to be the shape a slot holds.
]]
local function itemsFromList(list, size)
	local items = {}
	if type(list) ~= "table" then
		return items
	end
	for _, record in ipairs(list) do
		if type(record) == "table" then
			local slot, name, count = record[1], record[2], record[3]
			if
				type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= size
				and type(name) == "string" and name ~= ""
				and type(count) == "number" and count % 1 == 0 and count >= 1
				and not items[slot]
			then
				items[slot] = { name = name, count = count }
			end
		end
	end
	return items
end

local function itemsToList(items)
	local list = {}
	if type(items) ~= "table" then
		return list
	end
	for slot, stack in pairs(items) do
		if type(stack) == "table" and stack.name and (stack.count or 0) > 0 then
			table.insert(list, { slot, stack.name, stack.count })
		end
	end
	table.sort(list, function(a, b)
		return a[1] < b[1]
	end)
	return list
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

-- An authored model by name, with no stand-in: a chest's open model, which
-- is simply not used when it is not there.
local function getAuthored(name)
	local assets = ReplicatedStorage:FindFirstChild("TerrainAssets")
	local folder = assets and assets:FindFirstChild(StationConfig.ModelFolderName)
	local candidate = folder and type(name) == "string" and folder:FindFirstChild(name)
	if candidate and (candidate:IsA("Model") or candidate:IsA("BasePart")) then
		return candidate
	end
	return nil
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

	-- See StationConfig: out in the open world its contents would not
	-- outlive the server.
	if def.islandOnly and not PlaceConfig.isIsland() then
		return false, string.format("%ss can only be placed on an island", def.displayName or def.id)
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

	-- A chest turns to face whoever put it down, a quarter turn at a time.
	local facing = 0
	if def.facesPlacer then
		local toward = hrp.Position - centre
		if math.abs(toward.X) > math.abs(toward.Z) then
			facing = if toward.X > 0 then 1 else 3
		else
			facing = if toward.Z > 0 then 0 else 2
		end
	end

	local ok, reason = spawnStation(def, blockX, by, blockZ, player.UserId, nil, facing)
	if ok then
		notifyChanged()
	end
	return ok, reason
end

--[[
	Puts back a station a save says was here, without any of place's player
	checks: nobody is placing it, and the terrain it stands on may not have
	been generated yet. The cell still has to be free of other stations.

	`items` is a storage station's saved contents, the list exportAll wrote,
	and `facing` the quarter turns it was placed at (0 to 3).

	Returns ok, reason.
]]
function StationService.restore(stationId, blockX, by, blockZ, ownerUserId, items, facing)
	local def = StationConfig.get(stationId)
	if not def then
		return false, "Unknown station"
	end

	if type(blockX) ~= "number" or type(by) ~= "number" or type(blockZ) ~= "number" then
		return false, "Bad position"
	end

	blockX, by, blockZ = math.floor(blockX), math.floor(by), math.floor(blockZ)

	if stationsByCell[gridKey(blockX, by, blockZ)] then
		return false, "Cell occupied"
	end

	return spawnStation(def, blockX, by, blockZ, ownerUserId, items, facing)
end

--[[
	Every station standing right now, as plain data for a save:
	{ { id = "Workbench", x = 3, y = 38, z = -2 }, ... }

	A storage station that holds anything also has `items`, a list of
	{ slot, name, count }, and one turned to face its placer has `facing`.
]]
function StationService.exportAll()
	local list = {}
	for _, station in pairs(stationsByCell) do
		if station.instance.Parent then
			local record = {
				id = station.stationId,
				x = station.x,
				y = station.y,
				z = station.z,
			}
			if holdsItems(station.items) then
				record.items = itemsToList(station.items)
			end
			if station.facing and station.facing ~= 0 then
				record.facing = station.facing
			end
			table.insert(list, record)
		end
	end
	return list
end

--[[
	Called with no arguments whenever a player places or picks up a station.
	Restores do not count: they change nothing that is not already saved.
]]
function StationService.setChangeListener(listener)
	changeListener = listener
end

-- Every part of a station: anchored, solid, clickable, and marked with its
-- cell so a click on any of them finds the station. Scripts are stripped -
-- an authored model must not smuggle them into the live world.
local function prepareParts(root, key)
	-- GetDescendants does not include the root itself, so a single-part
	-- station would otherwise miss all of this.
	local parts = root:GetDescendants()
	table.insert(parts, root)

	for _, descendant in ipairs(parts) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = true
			descendant.CanQuery = true
			descendant.CanTouch = false
			descendant:SetAttribute("StationCellKey", key)
			CollectionService:AddTag(descendant, STATION_TAG)
		elseif descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
end

-- A part on its own is put in a Model, so every look moves and measures the
-- same way.
local function asModel(instance)
	if instance:IsA("Model") then
		return instance
	end
	local model = Instance.new("Model")
	instance.Parent = model
	model.PrimaryPart = instance
	return model
end

-- The lowest and highest a model reaches along a direction: its bounding
-- box's eight corners, projected.
local function reach(model, direction)
	local frame, size = model:GetBoundingBox()
	local half = size * 0.5
	local low, high = math.huge, -math.huge
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local along = frame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)):Dot(direction)
				low = math.min(low, along)
				high = math.max(high, along)
			end
		end
	end
	return low, high
end

--[[
	Turns, sizes and seats one of a storage station's looks.

	Turned about the world's up by `turn` and its own FacingYaw, so its +Z
	faces the way the chest does; scaled so it is `fitWidth` across; then
	moved by `seat`, which is handed the turned and sized model and says how
	far to shift it. Done in that order because the width is only known once
	it is turned, and where it sits only once it is sized.
]]
local function arrangeLook(look, def, turn, across, seat)
	local yaw = tonumber(look:GetAttribute("FacingYaw")) or 0
	local pivot = look:GetPivot()
	look:PivotTo(CFrame.new(pivot.Position) * turn * CFrame.Angles(0, math.rad(yaw), 0) * pivot.Rotation)

	if def.fitWidth then
		local low, high = reach(look, across)
		if high - low > 1e-3 then
			look:ScaleTo(look:GetScale() * def.fitWidth / (high - low))
		end
	end

	look:PivotTo(look:GetPivot() + seat(look))
end

--[[
	A storage station's body: a Model holding whichever look is showing - the
	closed one, or while somebody has it open the open one - plus an
	invisible anchor at the cell centre that carries the prompt, so the
	prompt does not come and go with the lid.

	The closed look sits centred on its cell, on the cell's floor. The open
	look sits on the same floor with its FRONT face where the closed look's
	front face is and centred the same way across: the lid swings back and
	up, so the open model is deeper and taller than the closed one only
	behind and above, and lining it up by its middle would shove the body
	forward when the lid opened.
]]
local function buildStorage(def, blockX, by, blockZ, facing, key)
	local closed = asModel(getTemplate(def):Clone())
	local openTemplate = getAuthored(def.openModel)
	local open = openTemplate and asModel(openTemplate:Clone()) or nil

	local turn = CFrame.Angles(0, (facing or 0) * math.pi / 2, 0)
	local front = turn:VectorToWorldSpace(Vector3.zAxis)
	local across = turn:VectorToWorldSpace(Vector3.xAxis)
	local centre = cellCentre(blockX, by, blockZ)
	local floorY = by * STUD_SIZE

	arrangeLook(closed, def, turn, across, function(look)
		local frontLow, frontHigh = reach(look, front)
		local acrossLow, acrossHigh = reach(look, across)
		local bottom = reach(look, Vector3.yAxis)
		return front * (centre:Dot(front) - (frontLow + frontHigh) * 0.5)
			+ across * (centre:Dot(across) - (acrossLow + acrossHigh) * 0.5)
			+ Vector3.yAxis * (floorY - bottom)
	end)

	local _, closedFront = reach(closed, front)
	local closedAcrossLow, closedAcrossHigh = reach(closed, across)

	if open then
		arrangeLook(open, def, turn, across, function(look)
			local _, lookFront = reach(look, front)
			local acrossLow, acrossHigh = reach(look, across)
			local bottom = reach(look, Vector3.yAxis)
			return front * (closedFront - lookFront)
				+ across * ((closedAcrossLow + closedAcrossHigh) * 0.5 - (acrossLow + acrossHigh) * 0.5)
				+ Vector3.yAxis * (floorY - bottom)
		end)
	end

	local container = Instance.new("Model")

	local anchor = Instance.new("Part")
	anchor.Name = "PromptAnchor"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.CFrame = CFrame.new(centre)
	anchor:SetAttribute("StationCellKey", key)
	anchor.Parent = container
	container.PrimaryPart = anchor

	closed.Name = "Closed"
	prepareParts(closed, key)
	closed.Parent = container

	if open then
		open.Name = "Open"
		prepareParts(open, key)
		-- Held out of the world until somebody opens the chest.
	end

	return container, anchor, { closed = closed, open = open }
end

--[[
	Builds a station into the world and registers it. Every check is the
	caller's: place validates a player's request, restore a save's.
]]
function spawnStation(def, blockX, by, blockZ, ownerUserId, items, facing)
	local template = getTemplate(def)
	if not template then
		return false, "Missing template"
	end

	local centre = cellCentre(blockX, by, blockZ)
	local key = gridKey(blockX, by, blockZ)

	-- A chest is not a bench: StationId is what the crafting window looks for.
	local idAttribute = if def.storage then "StorageId" else "StationId"

	facing = if type(facing) == "number" and facing % 1 == 0 and facing >= 0 and facing <= 3 then facing else 0

	local instance, promptParent, looks
	if def.storage then
		instance, promptParent, looks = buildStorage(def, blockX, by, blockZ, facing, key)
	else
		instance = template:Clone()
		prepareParts(instance, key)

		if instance:IsA("Model") then
			-- Centre the model's BOUNDING BOX on the cell rather than its
			-- pivot. An authored model can have its pivot anywhere, and the
			-- stand-in's is on its table top; either way what should line up
			-- with the grid is the shape, not the origin someone happened to
			-- build it around.
			local bounds = instance:GetBoundingBox()
			instance:PivotTo(instance:GetPivot() + (centre - bounds.Position))
		else
			instance.CFrame = CFrame.new(centre)
		end

		promptParent = if instance:IsA("Model")
			then (instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart"))
			else instance
	end

	instance.Name = def.id
	instance:SetAttribute(idAttribute, def.id)
	instance:SetAttribute("StationCellKey", key)
	instance:SetAttribute("OwnerUserId", ownerUserId)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UsePrompt"
	prompt.ActionText = def.actionText or "Use"
	prompt.ObjectText = def.displayName or def.id
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = def.useRange
	prompt:SetAttribute(idAttribute, def.id)
	prompt.Parent = promptParent

	instance.Parent = worldFolder

	register({
		instance = instance,
		stationId = def.id,
		x = blockX,
		y = by,
		z = blockZ,
		ownerUserId = ownerUserId,
		facing = if def.facesPlacer then facing else 0,
		looks = looks,
		items = if def.storage then itemsFromList(items, def.storage) else nil,
	})

	return true, "Placed"
end

-- Takes a station out of the world: every look it has, including the one
-- held out of the world while it is not showing.
local function destroyStation(station)
	if station.looks then
		for _, look in pairs(station.looks) do
			look:Destroy()
		end
	end
	station.instance:Destroy()
end

--[[
	Shows a storage station open or shut - its open model while anybody has
	it open. A station with no open model has nothing to show and is left as
	it is. ChestServer says when.
]]
function StationService.setOpen(station, open)
	local looks = station and station.looks
	if not (looks and looks.open and station.instance.Parent) then
		return
	end
	if open then
		looks.closed.Parent = nil
		looks.open.Parent = station.instance
	else
		looks.open.Parent = nil
		looks.closed.Parent = station.instance
	end
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

	-- Like Terraria: a chest comes up empty or not at all, so nothing in it
	-- can be lost or spilled by a swing.
	if holdsItems(station.items) then
		return false, nil, "not_empty"
	end

	unregister(station)
	destroyStation(station)
	notifyChanged()

	return true, station.stationId
end

--[[
	The live station record a part belongs to, or nil - for ChestServer, which
	is handed the prompt somebody used. The record is this service's own; a
	caller may read it and change `items`, and must call markChanged after.
]]
function StationService.fromInstance(instance)
	local station = stationFromInstance(instance)
	if station and station.instance.Parent then
		return station
	end
	return nil
end

-- Whether a record from fromInstance is still standing in the world.
function StationService.isLive(station)
	return station ~= nil and stationsByCell[station.key] == station and station.instance.Parent ~= nil
end

-- The world position of a station's cell centre.
function StationService.centreOf(station)
	return cellCentre(station.x, station.y, station.z)
end

--[[
	Something about a station changed that a save should keep - a chest's
	contents. Marks the island unsaved, exactly as placing one does.
]]
function StationService.markChanged()
	notifyChanged()
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
