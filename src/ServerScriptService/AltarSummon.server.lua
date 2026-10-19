--[[
	AltarSummon

	Using the Gelatinous Crown on an altar calls the Slime Emperor.

	The client (InventoryClient) sends what it clicked while the crown was the
	selected hotbar item: the slot, the part under the mouse and the hit point.
	Everything that decides whether a boss appears is settled here:

	  * the slot really holds a Gelatinous Crown right now
	  * the click resolves, through TerrainManager, to an altar block - one of
	    the two the Altar structure (StructureConfig) is built from - within
	    mining reach of the player
	  * no Slime Emperor is already in the world
	  * the enemy cap has room (EnemyService.spawn says no otherwise)

	Only then is the crown taken, and it is taken BEFORE he spawns and refunded
	if the spawn fails, so a cap or a missing model never costs the crown and a
	laggy double-click never summons two.

	WHERE HE APPEARS

	On the ground on the far side of the altar from whoever used it, a short
	way off. Not on the altar: he arrives swelling to full size (see
	SlimeEmperor.start) and would stand inside the plinth; not on the player,
	who should get to see him arrive rather than be under him.

	Clicking the crown on anything that is not an altar does nothing but say
	so. That is the whole reason this is a remote of its own rather than a line
	in ScrollChest: a chest opens wherever you are, and a crown has to be used
	somewhere.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local Inventory = require(ServerScriptService:WaitForChild("InventoryService"))
local Store = require(ServerScriptService:WaitForChild("InventoryStore"))
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local Feedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

local Request = Remotes.ensure("AltarUseRequest", "RemoteEvent")

local CROWN_ITEM = "GelatinousCrown"
local BOSS_NAME = "SlimeEmperor"

-- The blocks that count as "an altar". Either part of the structure will do:
-- the core is the obvious target, but the plinth is most of what you can hit.
local ALTAR_BLOCKS = {
	AltarStone = true,
	AltarCore = true,
}

-- Studs from the altar block to where the boss is put down.
local SPAWN_DISTANCE = 16

-- Seconds between accepted clicks per player, so holding the button is one
-- request rather than sixty.
local CLICK_INTERVAL = 0.3

local busy = setmetatable({}, { __mode = "k" })
local lastClickAt = setmetatable({}, { __mode = "k" })

--[[
	Where the boss should stand: SPAWN_DISTANCE studs past the altar along the
	line from the player through it, dropped onto the ground there. Someone
	standing on the altar gets him put down to the north, since the line has no
	direction to give.
]]
local function spawnPointFor(altarCentre: Vector3, from: Vector3): Vector3
	local away = Vector3.new(altarCentre.X - from.X, 0, altarCentre.Z - from.Z)
	if away.Magnitude < 1 then
		away = Vector3.new(0, 0, -1)
	else
		away = away.Unit
	end

	local x = altarCentre.X + away.X * SPAWN_DISTANCE
	local z = altarCentre.Z + away.Z * SPAWN_DISTANCE
	local y = EnemyService.groundAt(x, z, altarCentre.Y)

	return Vector3.new(x, y, z)
end

local function use(player, slot, target, hitPos)
	if not Inventory.GetInventory(player) or Inventory.IsLoading(player) or Store.isReadOnly(player) then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 then
		return
	end

	local held, count = Inventory.GetSlot(player, slot)
	if held ~= CROWN_ITEM or (count or 0) < 1 then
		return
	end

	if typeof(hitPos) ~= "Vector3" then
		Feedback.tell(player, "Use the crown on an altar.", "bad")
		return
	end

	--[[
		What was clicked, by the terrain's own reckoning: a block name the
		player cannot fake, and a reach check they cannot skip. A hit on
		something that is not terrain at all - a tree, a slime, the sky - comes
		back as no block, which is the same answer as "not an altar".
	]]
	local blockName, _drop, reason, centre
	if typeof(target) == "Instance" and target:IsA("BasePart") then
		blockName, _drop, reason, centre = TerrainManager:InspectBlock(target, hitPos, nil, player)
	else
		blockName, _drop, reason, centre = TerrainManager:InspectBlock(hitPos.X, hitPos.Y, hitPos.Z, player)
	end

	if reason == "too_far" then
		Feedback.tell(player, "The altar is too far away.", "bad")
		return
	end

	if not blockName or not ALTAR_BLOCKS[blockName] then
		Feedback.tell(player, "The crown does nothing here. Use it on an altar.", "bad")
		return
	end

	if #EnemyService.allOf(BOSS_NAME) > 0 then
		Feedback.tell(player, "The Slime Emperor is already here.", "bad")
		return
	end

	-- InspectBlock only reports a centre for a breakable block; the altar's
	-- blocks are, but fall back to the click point rather than assume.
	local altarCentre = centre or hitPos

	-- Taken first. If the spawn then refuses, it goes straight back; a crown
	-- is far too expensive to lose to a full enemy cap.
	if not Inventory.RemoveItemByName(player, CROWN_ITEM, 1) then
		return
	end

	local model, why = EnemyService.spawn(BOSS_NAME, spawnPointFor(altarCentre, root.Position))
	if not model then
		Inventory.AddItemByName(player, CROWN_ITEM, 1)
		warn(string.format("[AltarSummon] %s used a crown but the Slime Emperor could not spawn: %s", player.Name, tostring(why)))
		Feedback.tell(player, "Nothing answers. The crown was kept.", "bad")
		return
	end

	Store.markDirty(player)
	Feedback.tell(player, "The altar hums. The Slime Emperor rises.", "good")
end

Request.OnServerEvent:Connect(function(player, slot, target, hitPos)
	local now = os.clock()
	if busy[player] or now - (lastClickAt[player] or -CLICK_INTERVAL) < CLICK_INTERVAL then
		return
	end
	lastClickAt[player] = now
	busy[player] = true

	local ok, err = xpcall(function()
		use(player, slot, target, hitPos)
	end, debug.traceback)

	busy[player] = nil

	if not ok then
		warn("[AltarSummon] request failed: " .. tostring(err))
		Feedback.tell(player, "The altar could not be used. Please try again.", "bad")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
	lastClickAt[player] = nil
end)
