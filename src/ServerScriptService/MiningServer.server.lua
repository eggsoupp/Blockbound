--[[
	MiningServer

	Turns a client's "I clicked that" into a validated, timed block break.

	The client sends only what it clicked. Everything that decides whether the
	break happens, how long it takes, and what the player gets is worked out
	here:

	  * the tool must be a real Pickaxe by ItemDefinitions, held right now
	  * the target must resolve to a block the terrain actually has
	  * the block must be breakable at all (bedrock is not)
	  * how long it takes comes from the BLOCK's hardness and the TOOL's speed
	  * the player must stay in range for the whole duration
	  * the item awarded comes from BlockConfig, not from the client and not
	    from the part's name

	This is also the one place mining edits are applied, so player-placed blocks,
	structure blocks and generated terrain all break through the same path.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local BlockConfig = require(Shared:WaitForChild("Blocks"):WaitForChild("BlockConfig"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local StationService = require(ServerScriptService:WaitForChild("StationService"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local RequestMineRE = Remotes.ensure("RequestMineBlock", "RemoteEvent")
local MiningStartedRE = Remotes.ensure("MiningStarted", "RemoteEvent")
local MiningResultRE = Remotes.ensure("MiningResult", "RemoteEvent")
local CancelMineRE = Remotes.ensure("CancelMine", "RemoteEvent")

StationService.init(TerrainManager)

local MAX_MINE_DISTANCE = 34

-- How often the server re-checks reach and tool. Nothing is sent on this
-- cadence: the duration goes out once and MiningClient animates against its own
-- clock. The break still happens here, only when this loop says it may.
local VALIDATE_INTERVAL = 0.1

local miningSessions = {}

local function sendResult(player, success, itemName, reason)
	MiningResultRE:FireClient(player, success, itemName, reason)
end

-- Tools are tagged by EquipServer, but a hand-placed one in Studio may only
-- have its name, so all three sources are accepted, most trustworthy first.
local function getToolItemName(tool)
	if not tool then
		return nil
	end

	local attribute = tool:GetAttribute("itemName") or tool:GetAttribute("ItemName")
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end

	local value = tool:FindFirstChild("ItemName") or tool:FindFirstChild("itemName")
	if value and value:IsA("StringValue") and value.Value ~= "" then
		return value.Value
	end

	return tool.Name
end

-- The pickaxe the player is holding, or nil - the whole permission check.
local function getEquippedPickaxe(player)
	local character = player.Character
	if not character then
		return nil, nil
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil, nil
	end

	local def = ItemDefinitions[getToolItemName(tool)]
	if def and def.classification == "Pickaxe" then
		return tool, def
	end

	def = ItemDefinitions[tool.Name]
	if def and def.classification == "Pickaxe" then
		return tool, def
	end

	return nil, nil
end

--[[
	The point this request is about.

	The client's hit position wins over the target's centre: the renderer merges
	runs of identical blocks into one Part, so a Part's centre is the middle of
	the run and would resolve the wrong block.

	Trusting the client with the POINT is not trusting it with the outcome.
	TerrainManager re-checks it and requires it to lie on the named Part, so a
	fabricated point either fails the range check or fails to match.
]]
local function getTargetPosition(target, hitPos)
	if typeof(hitPos) == "Vector3" then
		return hitPos
	end

	if typeof(target) == "Instance" then
		if target:IsA("BasePart") then
			return target.Position
		end
		if target:IsA("Model") then
			local primary = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
			return primary and primary.Position or nil
		end
	end

	return nil
end

local function awardItem(player, itemName)
	if not itemName or itemName == "" then
		return
	end

	local ok = InventoryService.AddItemByName(player, itemName, 1)
	if not ok then
		-- Full bag. The block is already gone, so say so rather than silently
		-- dropping the item on the floor of a system that has no floor.
		warn(string.format(
			"[MiningServer] %s had no room for %s.", player.Name, tostring(itemName)
		))
	end
end

CancelMineRE.OnServerEvent:Connect(function(player)
	local session = miningSessions[player]
	if session then
		session.cancelled = true
	end
end)

local function mine(player, target, hitPos)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		sendResult(player, false, nil, "no_character")
		return
	end

	local session = miningSessions[player]
	if session and session.busy then
		sendResult(player, false, nil, "already_mining")
		return
	end

	local targetPos = getTargetPosition(target, hitPos)
	if not targetPos then
		sendResult(player, false, nil, "bad_target")
		return
	end

	if (hrp.Position - targetPos).Magnitude > MAX_MINE_DISTANCE then
		sendResult(player, false, nil, "too_far")
		return
	end

	local tool, pickaxeDef = getEquippedPickaxe(player)
	if not tool then
		sendResult(player, false, nil, "no_pickaxe")
		return
	end

	-- Crafting stations are single instances rather than pooled terrain parts,
	-- so they come up whole rather than being chipped away. Asked before the
	-- terrain, and quietly ignored when the target is not one.
	local isStation, stationItem, stationReason = StationService.tryBreak(player, target)
	if isStation then
		awardItem(player, stationItem)
		sendResult(player, true, stationItem, "ok")
		return
	elseif stationReason then
		sendResult(player, false, nil, stationReason)
		return
	end

	-- Ask the terrain what this block is BEFORE spending time on it. How long a
	-- block takes is a property of the block, so the server has to know which
	-- block it is; taking the client's word for it would let anyone mine
	-- anything instantly.
	local blockName, dropName, inspectReason, cellCentre
	if typeof(target) == "Instance" then
		blockName, dropName, inspectReason, cellCentre = TerrainManager:InspectBlock(target, targetPos, nil, player)
	else
		blockName, dropName, inspectReason, cellCentre =
			TerrainManager:InspectBlock(targetPos.X, targetPos.Y, targetPos.Z, player)
	end

	if not blockName then
		sendResult(player, false, nil, inspectReason or "no_block")
		return
	end
	if inspectReason == "unbreakable" then
		sendResult(player, false, nil, "unbreakable")
		return
	end

	-- Asked before the swing starts, not after the block is gone. Breaking a
	-- block the player has nowhere to put deletes it and pays nothing, which
	-- looks exactly like the item having been eaten.
	local drop = BlockConfig.getDrop(blockName)
	if drop and not InventoryService.CanAddItem(player, drop, 1) then
		-- The drop rides along so the player is told WHAT has no room. A full
		-- bag can still take more of what it already has a part-stack of,
		-- which is how grass can mine fine while the dirt under it refuses.
		sendResult(player, false, drop, "inventory_full")
		return
	end

	-- Freeze the resolved voxel, not a pooled rendering Part that may be reshaped.
	if cellCentre then
		target = nil
		targetPos = cellCentre
	end

	-- Draw the ground around the target block by block, and the layer under
	-- it, NOW: the swing is the head start clients get to receive those Parts
	-- before the break needs them. See TerrainManager, EDIT ZONES.
	TerrainManager:OpenEditZone(targetPos)
	local speed = tonumber(pickaxeDef.miningSpeed) or 1
	if speed <= 0 then
		speed = 1
	end

	local miningTime = math.clamp(
		BlockConfig.getBreakSeconds(blockName) / speed,
		BlockConfig.MinBreakSeconds,
		BlockConfig.MaxBreakSeconds
	)

	session = { busy = true, cancelled = false }
	miningSessions[player] = session

	-- One message for the whole swing: how long this block takes. Everything the
	-- player sees between now and the result is animated from it locally.
	MiningStartedRE:FireClient(player, miningTime, blockName)

	-- Against a real clock, not an accumulator of nominal waits. task.wait
	-- overshoots, so adding VALIDATE_INTERVAL per pass made every break finish
	-- measurably later than the duration the client was animating to.
	local deadline = os.clock() + miningTime

	while os.clock() < deadline do
		if session.cancelled then
			miningSessions[player] = nil
			sendResult(player, false, nil, "cancelled")
			return
		end

		if
			not hrp.Parent
			or not tool.Parent
			or (hrp.Position - targetPos).Magnitude > MAX_MINE_DISTANCE
		then
			miningSessions[player] = nil
			sendResult(player, false, nil, "moved_too_far")
			return
		end

		task.wait(math.min(VALIDATE_INTERVAL, deadline - os.clock()))
	end

	if not cellCentre then targetPos = getTargetPosition(target, hitPos) end
	if not targetPos or (hrp.Position - targetPos).Magnitude > MAX_MINE_DISTANCE then
		miningSessions[player] = nil
		sendResult(player, false, nil, "target_lost")
		return
	end

	local currentName, _, _, currentCentre = TerrainManager:InspectBlock(
		targetPos.X, targetPos.Y, targetPos.Z, player
	)
	if currentName ~= blockName or (currentCentre and (currentCentre - targetPos).Magnitude > 0.01) then
		miningSessions[player] = nil
		sendResult(player, false, nil, "target_lost")
		return
	end
	Profiler.count("Mining.break")

	local ok, broke, itemName = pcall(function()
		if typeof(target) == "Instance" then
			return TerrainManager:BreakBlock(target, targetPos, nil, player)
		end
		return TerrainManager:BreakBlock(targetPos.X, targetPos.Y, targetPos.Z, player)
	end)

	miningSessions[player] = nil

	if not ok then
		warn("[MiningServer] TerrainManager:BreakBlock failed:", broke)
		sendResult(player, false, nil, "terrain_error")
		return
	end

	if not broke then
		sendResult(player, false, nil, "break_failed")
		return
	end

	awardItem(player, itemName)
	sendResult(player, true, itemName, "ok")
end
RequestMineRE.OnServerEvent:Connect(function(player, target, hitPos)
	local ok, err = xpcall(function()
		mine(player, target, hitPos)
	end, debug.traceback)
	if not ok then
		miningSessions[player] = nil
		warn("[MiningServer] Mining request failed: " .. tostring(err))
		sendResult(player, false, nil, "terrain_error")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	miningSessions[player] = nil
end)
