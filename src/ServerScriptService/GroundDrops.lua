--[[
	GroundDrops

	Items lying in the world, waiting to be picked up. Everything the world
	pays out lands here rather than going into the bag: mined blocks, felled
	trees, enemy loot, an Annihilation crater.

		GroundDrops.spawn("Stone", 1, position, player)        -- public drop
		GroundDrops.spawn("Slime", 2, position, player, true)  -- private drop
		GroundDrops.blockRemovedAt(cellCentre)                 -- the block under some went

	A drop rests on the first solid block below where it appeared. Walk within
	DropConfig.PickupRadius and it flies to you along DropFlight's curve, trail
	and all, and lands in the bag. As much of a stack as fits is taken; the rest
	stays down until there is room.

	PUBLIC AND PRIVATE

	A public drop is seen by everyone. Only the player who caused it can take it
	for DropConfig.OwnerSeconds, then anyone can.

	A private drop - enemy loot - belongs to the killer for its whole life.
	Nobody else can take it, and nobody else can SEE it: their clients are never
	told it exists. It goes when its owner leaves, since nobody else could ever
	pick it up.

	THE SERVER OWNS ALL OF IT

	There is no Part on the server. A drop is an entry in `drops`, and each
	client draws its own cube for the drops it has been told about (see
	StarterPlayerScripts.GroundDropClient). That is what makes privacy real: a
	server Part would replicate to every client whatever its owner.

	Pickups are decided here and only here, by measuring the server's own copy
	of each character against the server's own copy of each drop, ten times a
	second. The item, the amount, who may see it and who may take it are fixed
	by the server when it spawns. The one message a client can send is "sync",
	which asks for a fresh copy of what that client is already allowed to see;
	it carries nothing and changes nothing.

	What this cannot stop is what no server-side pickup can: a character is
	simulated by its own client, so an exploiter who teleports can REACH a drop
	the way a walker could. They cannot make one, see someone else's private
	one, change one, or take one twice.

	NOTHING IS LOST, NOTHING IS PAID TWICE

	What a pickup takes is subtracted from the entry - or the entry removed -
	before anything is granted, so a second player, tick or call can never take
	it again. The grant waits for the flight to land (EnemyConfig.
	DropFlightSeconds, so the "+1 Stone" line appears as the cube arrives). If
	it then fails - the bag filled up mid-flight, or the player left - the same
	amount goes back on the ground. Inventory:Add is all-or-nothing, so a failed
	grant has given nothing and putting it all back is exact.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local DropConfig = require(Shared:WaitForChild("Inventory"):WaitForChild("DropConfig"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))

--[[
	Server -> client, only ever to the players allowed to see the drop:

		("add", id, itemName, amount, restPosition)
		("move", id, restPosition)
		("amount", id, amount)
		("remove", id)
		("snapshot", { { id, itemName, amount, restPosition }, ... })

	Client -> server: ("sync") and nothing else.
]]
local DropEvent = Remotes.ensure("GroundDrops", "RemoteEvent")

-- The flight a pickup plays: "something flies from here to you on a curve with
-- a trail", which DropFlight already draws.
local DropFlight = Remotes.ensure("EnemyDropFlight", "RemoteEvent")

local GroundDrops = {}

-- ---------------------------------------------------------------------------
-- Tuning (the shared half is DropConfig)
-- ---------------------------------------------------------------------------

-- How often pickups are checked.
local STEP_INTERVAL = 0.1

-- How often a bag that had no room is asked again about the same drop.
local FULL_RETRY_SECONDS = 0.5

-- How far a drop will fall looking for something to rest on, in blocks.
local MAX_FALL_BLOCKS = 16

-- How far from the middle of its cell a drop may come to rest, so two items in
-- one cell float side by side instead of inside each other.
local JITTER = 0.9

-- How often one player may ask for a snapshot.
local SYNC_COOLDOWN = 2

local STUD_SIZE = TerrainConfig.StudSize
local FLIGHT_SECONDS = EnemyConfig.DropFlightSeconds
local RADIUS_SQUARED = DropConfig.PickupRadius * DropConfig.PickupRadius
local FLIGHT_LIFT = Vector3.new(0, DropConfig.Hover, 0)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

-- id -> entry. The only record of what is on the ground.
local drops = {}
local dropCount = 0
local nextId = 0

local lastSyncAt = {}

local random = Random.new()

-- ---------------------------------------------------------------------------
-- Telling clients
-- ---------------------------------------------------------------------------

-- To the one player who may see a private drop, or to everyone.
local function send(entry, ...)
	local viewer = entry.viewer
	if viewer then
		if viewer.Parent then
			DropEvent:FireClient(viewer, ...)
		end
	else
		DropEvent:FireAllClients(...)
	end
end

local function canSee(entry, player)
	return entry.viewer == nil or entry.viewer == player
end

-- ---------------------------------------------------------------------------
-- Resting on the ground
-- ---------------------------------------------------------------------------

local function cellOf(position)
	return math.floor(position.X / STUD_SIZE),
		math.floor(position.Y / STUD_SIZE),
		math.floor(position.Z / STUD_SIZE)
end

--[[
	The first solid block at or below `by` in this column, from the terrain's
	own data rather than a raycast: a raycast would see whatever the renderer
	has drawn, which lags an edit and merges runs of blocks. Nil when there is
	nothing within MAX_FALL_BLOCKS.
]]
local function groundBelow(blockX, by, blockZ)
	for y = by, by - MAX_FALL_BLOCKS, -1 do
		if TerrainManager:IsSolidAt(blockX, y, blockZ) then
			return y
		end
	end
	return nil
end

-- Where the cube would sit if it lay on the ground. Clients float it above.
local function restPosition(entry, fallbackY)
	local y = if entry.restBy
		then (entry.restBy + 1) * STUD_SIZE + DropConfig.Size * 0.5
		else fallbackY

	return Vector3.new(
		(entry.blockX + 0.5) * STUD_SIZE + entry.offsetX,
		y,
		(entry.blockZ + 0.5) * STUD_SIZE + entry.offsetZ
	)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function remove(entry)
	if drops[entry.id] ~= entry then
		return false
	end

	drops[entry.id] = nil
	dropCount -= 1
	send(entry, "remove", entry.id)
	return true
end

local function removeOldest()
	local oldest = nil
	for _, entry in pairs(drops) do
		if not oldest or entry.spawnedAt < oldest.spawnedAt then
			oldest = entry
		end
	end

	if oldest then
		remove(oldest)
	end
end

local function isLivePlayer(value)
	return typeof(value) == "Instance" and value:IsA("Player") and value.Parent ~= nil
end

--[[
	Puts `amount` of `itemName` on the ground, falling from `position` to the
	first block below it.

	`owner` is the player who caused it, or nil for a drop anyone may take at
	once. `private` makes it the owner's alone, to see and to take; it needs an
	owner, and without one there is nobody to give it to, so nothing spawns.

	A drop of the same item, owner and privacy already lying in that cell is
	added to instead, so mining a column straight down leaves one stack.
]]
function GroundDrops.spawn(itemName: string, amount: number?, position: Vector3, owner: Player?, private: boolean?)
	if type(itemName) ~= "string" or not ItemDefinitions[itemName] or typeof(position) ~= "Vector3" then
		return
	end

	local count = math.floor(tonumber(amount) or 1)
	if count <= 0 then
		return
	end

	if not isLivePlayer(owner) then
		owner = nil
	end

	local viewer = nil
	if private then
		if not owner then
			return
		end
		viewer = owner
	end

	local now = os.clock()
	local blockX, by, blockZ = cellOf(position)
	local restBy = groundBelow(blockX, by, blockZ)

	for _, entry in pairs(drops) do
		if
			entry.item == itemName
			and entry.owner == owner
			and entry.viewer == viewer
			and entry.blockX == blockX
			and entry.blockZ == blockZ
			and entry.restBy == restBy
		then
			entry.amount += count
			entry.expiresAt = now + DropConfig.DespawnSeconds
			send(entry, "amount", entry.id, entry.amount)
			return
		end
	end

	if dropCount >= DropConfig.MaxDrops then
		removeOldest()
	end

	nextId += 1

	local entry = {
		id = nextId,
		item = itemName,
		amount = count,
		owner = owner,
		viewer = viewer,
		blockX = blockX,
		blockZ = blockZ,
		restBy = restBy,
		offsetX = (random:NextNumber() - 0.5) * 2 * JITTER,
		offsetZ = (random:NextNumber() - 0.5) * 2 * JITTER,
		position = position,
		spawnedAt = now,
		readyAt = now + DropConfig.PickupDelay,
		-- A private drop never becomes anyone else's.
		publicAt = if viewer then math.huge else now + DropConfig.OwnerSeconds,
		expiresAt = now + DropConfig.DespawnSeconds,
		nextCheck = 0,
	}
	entry.position = restPosition(entry, position.Y)

	drops[entry.id] = entry
	dropCount += 1

	send(entry, "add", entry.id, entry.item, entry.amount, entry.position)
end

--[[
	A block at `cellCentre` has gone. Anything that was resting on it falls to
	whatever is below now, so digging down under a drop does not leave it
	hanging over the hole.
]]
function GroundDrops.blockRemovedAt(cellCentre: Vector3)
	if typeof(cellCentre) ~= "Vector3" or dropCount == 0 then
		return
	end

	local blockX, by, blockZ = cellOf(cellCentre)

	for _, entry in pairs(drops) do
		if entry.restBy == by and entry.blockX == blockX and entry.blockZ == blockZ then
			entry.restBy = groundBelow(blockX, by, blockZ)
			entry.position = restPosition(entry, entry.position.Y)
			send(entry, "move", entry.id, entry.position)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Pickup
-- ---------------------------------------------------------------------------

-- How much of `amount` this bag can take right now, all-or-nothing per try.
local function fitting(player, itemName, amount)
	if InventoryService.CanAddItem(player, itemName, amount) then
		return amount
	end

	local low, high = 0, amount - 1
	while low < high do
		local mid = math.ceil((low + high) / 2)
		if InventoryService.CanAddItem(player, itemName, mid) then
			low = mid
		else
			high = mid - 1
		end
	end
	return low
end

local function collect(player, entry, now)
	local take = fitting(player, entry.item, entry.amount)
	if take <= 0 then
		-- No room: the drop stays down and the bag is asked again shortly.
		entry.nextCheck = now + FULL_RETRY_SECONDS
		return
	end

	-- Taken from the record FIRST. From here on these items exist only in this
	-- function, so nothing else can collect them.
	if take < entry.amount then
		entry.amount -= take
		entry.nextCheck = now + FULL_RETRY_SECONDS
		send(entry, "amount", entry.id, entry.amount)
	elseif not remove(entry) then
		return
	end

	local itemName, from, private = entry.item, entry.position, entry.viewer ~= nil

	DropFlight:FireClient(player, from + FLIGHT_LIFT, itemName, take)

	task.delay(FLIGHT_SECONDS, function()
		if player.Parent and InventoryService.AddItemByName(player, itemName, take) then
			return
		end

		-- Not granted, so nothing was given (Add is all-or-nothing): put it all
		-- back down, at the player if they are still here.
		local character = player.Parent and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		GroundDrops.spawn(itemName, take, if root then root.Position else from, player, private)
	end)
end

local function step()
	local now = os.clock()

	for _, entry in pairs(drops) do
		if now >= entry.expiresAt then
			remove(entry)
		end
	end

	if dropCount == 0 then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if root and humanoid and humanoid.Health > 0 then
			local origin = root.Position

			for _, entry in pairs(drops) do
				if
					now >= entry.readyAt
					and now >= entry.nextCheck
					and canSee(entry, player)
					and (entry.owner == nil or entry.owner == player or now >= entry.publicAt)
				then
					local offset = entry.position - origin
					if offset:Dot(offset) <= RADIUS_SQUARED then
						collect(player, entry, now)
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < STEP_INTERVAL then
		return
	end
	accumulator = 0
	step()
end)

--[[
	A client asking for everything it may see, when it starts listening. It
	names nothing and is answered only with drops that player could already be
	told about, so it is rate-limited for the bandwidth and for nothing else.
]]
DropEvent.OnServerEvent:Connect(function(player, action)
	if action ~= "sync" then
		return
	end

	local now = os.clock()
	local last = lastSyncAt[player]
	if last and now - last < SYNC_COOLDOWN then
		return
	end
	lastSyncAt[player] = now

	local list = {}
	for _, entry in pairs(drops) do
		if canSee(entry, player) then
			table.insert(list, { entry.id, entry.item, entry.amount, entry.position })
		end
	end

	DropEvent:FireClient(player, "snapshot", list)
end)

Players.PlayerRemoving:Connect(function(player)
	lastSyncAt[player] = nil

	for _, entry in pairs(drops) do
		if entry.viewer == player then
			-- Theirs alone, so nobody else could ever take it.
			drops[entry.id] = nil
			dropCount -= 1
		elseif entry.owner == player then
			entry.owner = nil
		end
	end
end)

return GroundDrops
