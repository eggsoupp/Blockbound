--[[
	InventoryManager

	Owns the lifecycle of each player's inventory and serves the three remotes
	the inventory UI drives: full refresh, slot swap, and stack transfer.

	All three are authoritative: the client asks, the server decides, and the
	server pushes the result back - including when the request is refused - so a
	client that guesses wrong is corrected rather than left believing itself.

	InventoryStore owns the DataStore mechanics; this script decides WHEN:

	    join      load, then register and sync
	    change    flagged dirty via InventoryService's change listener
	    every 90s a dirty player is written back
	    leave     final save, then the session lock is released
	    shutdown  BindToClose saves everyone still online, in parallel

	The autosave is what bounds the damage from a server dying without warning.

	Set DEBUG to true for a running commentary of every swap and transfer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local Inventory = require(ServerScriptService:WaitForChild("InventoryClass"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local PromptItemMappings = require(ReplicatedStorage:WaitForChild("PromptItemMappings"))

-- Declared here so it exists before any client waits for it; the payload is
-- built and sent by InventoryService, which is the only place that knows what
-- each client has already been told.
Remotes.ensure("InventoryChanged", "RemoteEvent")
local RequestFullInventory = Remotes.ensure("RequestFullInventory", "RemoteEvent")
local RequestSwapSlots = Remotes.ensure("RequestSwapSlots", "RemoteEvent")
local RequestTransferStack = Remotes.ensure("RequestTransferStack", "RemoteEvent")

local DEBUG = false

local function log(...)
	if DEBUG then
		print("[InventoryManager]", ...)
	end
end

local function swarn(...)
	warn("[InventoryManager]", ...)
end

-- ---------------------------------------------------------------------------
-- Persistence lifecycle
-- ---------------------------------------------------------------------------

-- How long a dirty inventory may go unwritten. The ceiling on how much an
-- unexpected server death can cost a player.
local AUTOSAVE_INTERVAL = 90

-- How often the autosave loop looks for work. Small relative to the interval so
-- saves spread out across players instead of firing in one burst.
local AUTOSAVE_TICK = 10

-- Seconds BindToClose will wait for outstanding saves before letting the server
-- die. Roblox allows about 30.
local SHUTDOWN_TIMEOUT = 25

-- Players whose load is still running, so PlayerRemoving knows not to save an
-- inventory that was never theirs.
local loading = {}

--[[
	Marks a player dirty on every inventory change. Registered once, here,
	because this is the script that owns saving.
]]
InventoryService.SetChangeListener(function(player)
	InventoryStore.markDirty(player)
end)

local function saveNow(player, reason)
	local inv = InventoryService.GetInventory(player)
	if not inv then
		return false
	end

	local ok, err = InventoryStore.save(player, inv, reason)
	if not ok and err ~= "read-only session" and err ~= "datastore unavailable" then
		swarn(string.format("Save failed for %s (%s): %s", player.Name, tostring(reason), tostring(err)))
	end
	return ok
end

local function onPlayerAdded(player)
	if loading[player] or InventoryService.GetInventory(player) then
		return -- already handled; PlayerAdded and the startup sweep can overlap
	end
	loading[player] = true

	-- Tell InventoryService to buffer anything granted while the fetch runs.
	-- Mining and harvesting destroy the target before awarding the drop, so
	-- without this a block broken during the load window is simply lost.
	InventoryService.BeginLoading(player)

	local ok, inv, info = pcall(InventoryStore.load, player)

	if not ok then
		-- InventoryStore is written not to throw, so this is a bug rather than a
		-- DataStore outage. Give them a working bag either way - but latch the
		-- session read-only first, because the empty bag they are about to get is
		-- a guess and must never be written over their real save.
		swarn("Inventory load errored for", player.Name, ":", inv)
		InventoryStore.setReadOnly(player, "load errored")
		inv, info = nil, { source = "fallback", readOnly = true, reason = "error", repairs = 0 }
	end

	loading[player] = nil

	-- The player may have left while the fetch was in flight.
	if not player.Parent then
		InventoryService.Unregister(player)
		InventoryStore.release(player, nil, "left during load")
		return
	end

	if not inv then
		inv = Inventory.new()
	end

	local queuedApplied = InventoryService.Register(player, inv)
	-- Full, not a delta: this is the client's first sight of the bag, so there
	-- is nothing for a delta to be relative to.
	InventoryService.SyncFull(player)

	if (queuedApplied or 0) > 0 then
		-- Items arrived during the load, so what is in memory already differs
		-- from what is stored.
		InventoryStore.markDirty(player)
	end

	log(string.format(
		"Inventory ready for %s (source=%s readOnly=%s repairs=%d queued=%d)",
		player.Name, tostring(info and info.source), tostring(info and info.readOnly),
		(info and info.repairs) or 0, queuedApplied or 0
	))

	if info and info.readOnly then
		swarn(string.format(
			"%s is playing with an UNSAVEABLE inventory (their data could not be read or is "
				.. "locked by another server). Nothing they do this session will be kept.",
			player.Name
		))

		-- Said to the player too. Silent, this looked exactly like "my inventory
		-- never saves". Delayed so their client is listening by then.
		--
		-- Worded per cause. It used to be one message blaming another server for
		-- everything, which in Studio with API access off - the usual case in a
		-- new experience - sent the developer looking for a server that did not
		-- exist, on every single playtest.
		local reason = info.reason
		local message, tone

		if reason == "unavailable" and RunService:IsStudio() then
			message = "Saving is off in this Studio test. To test saving, turn on Game Settings > "
				.. "Security > Enable Studio Access to API Services."
			tone = "info"
		elseif reason == "unavailable" then
			message = "Saving is unavailable right now, so nothing you collect this session will be kept."
			tone = "bad"
		elseif reason == "locked" then
			message = "Your saved inventory is still open on another server. Nothing you collect now "
				.. "will be saved - rejoin in a minute."
			tone = "bad"
		else
			message = "Your saved inventory couldn't be read. Nothing you collect now will be saved - "
				.. "rejoin to try again."
			tone = "bad"
		end

		task.delay(4, function()
			if player.Parent then
				CommandFeedback.tell(player, message, tone)
			end
		end)
	end
end

local function onPlayerRemoving(player)
	local inv = InventoryService.GetInventory(player)

	-- release() saves and then drops the session lock. Passing nil when there is
	-- no inventory still clears the lock, which matters for a player who left
	-- mid-load: their key would otherwise stay claimed until the lock expires.
	InventoryStore.release(player, inv, "leave")
	InventoryService.Unregister(player)
	loading[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- PlayerAdded only fires for players who join after this line runs. In Studio,
-- and on a busy server start, someone can already be in before it does.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

--[[
	Autosave. Writes back any player whose inventory has changed and has not been
	saved recently, so an unexpected shutdown costs seconds rather than a session.
]]
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_TICK)

		for _, player in ipairs(Players:GetPlayers()) do
			if InventoryStore.shouldAutosave(player, AUTOSAVE_INTERVAL) then
				-- Spawned so one slow DataStore call cannot hold up the others.
				task.spawn(saveNow, player, "autosave")
			end
		end
	end
end)

--[[
	Last line of defence. Roblox gives a closing server a short grace period;
	saves run in parallel and the handler blocks until they finish or the budget
	runs out.
]]
game:BindToClose(function()
	local players = Players:GetPlayers()

	log(string.format("Shutdown: saving %d inventories", #players))

	local remaining = #players
	for _, player in ipairs(players) do
		task.spawn(function()
			local inv = InventoryService.GetInventory(player)
			pcall(InventoryStore.release, player, inv, "shutdown")
			remaining -= 1
		end)
	end

	--[[
		Also wait for saves that are ALREADY running.

		This used to return straight away when nobody was left - but a server
		only closes because the last player left, and that player's leave-save
		is in flight at exactly this moment. Returning let the server die
		mid-write, which lost the save and left the session lock behind, so the
		next server (the place they teleported to, or their next visit) loaded
		an empty, unsaveable bag.
	]]
	local deadline = os.clock() + SHUTDOWN_TIMEOUT
	while (remaining > 0 or InventoryStore.hasPendingWrites()) and os.clock() < deadline do
		task.wait(0.1)
	end

	if remaining > 0 or InventoryStore.hasPendingWrites() then
		swarn("Shutdown timed out with inventory saves unfinished.")
	end
end)

RequestFullInventory.OnServerEvent:Connect(function(player)
	-- Asking for everything re-baselines this client, so subsequent deltas are
	-- measured against what was actually just sent.
	InventoryService.SyncFull(player)
end)

RequestSwapSlots.OnServerEvent:Connect(function(player, index1, index2)
	local inv = InventoryService.GetInventory(player)
	if not inv or type(index1) ~= "number" or type(index2) ~= "number" then
		return
	end

	local ok, err, discarded = inv:SwapSlots(math.floor(index1), math.floor(index2))
	if not ok then
		log("Swap refused for", player.Name, ":", err)
	end

	--[[
		Say what the bin ate.

		The one destructive action in the grid, and the only one with no
		confirmation in front of it - so it has to be legible after the fact
		instead. Without this the item simply is not there any more and the
		player is left working out whether they did that.
	]]
	if discarded and discarded.name then
		local label = discarded.name
		if (discarded.count or 1) > 1 then
			label = string.format("%s x%d", label, discarded.count)
		end
		CommandFeedback.tell(player, string.format("Binned %s.", label), "bad")
	end

	-- Sync either way: on success to show the new layout, on refusal to snap the
	-- client's optimistic drag back.
	InventoryService.SaveAndSync(player)
end)

RequestTransferStack.OnServerEvent:Connect(function(player, srcIndex, dstIndex, amount)
	local inv = InventoryService.GetInventory(player)
	if not inv then
		return
	end

	if
		type(srcIndex) ~= "number" or type(dstIndex) ~= "number"
		or type(amount) ~= "number" or amount <= 0
	then
		InventoryService.SaveAndSync(player)
		return
	end

	local ok, err = inv:TransferStack(math.floor(srcIndex), math.floor(dstIndex), math.floor(amount))
	if not ok then
		log("Transfer refused for", player.Name, ":", err)
	end

	InventoryService.SaveAndSync(player)
end)

--[[
	Development item dispensers. Prompts that are not dispensers are ignored -
	crafting stations put their own prompts in the world and this is not their
	handler.
]]
ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	local items = PromptItemMappings[prompt]
	if not items then
		return
	end

	for _, item in ipairs(items) do
		if ItemDefinitions[item.name] then
			InventoryService.AddItemByName(player, item.name, item.amount)
		else
			swarn("Dispenser lists unknown item:", item.name)
		end
	end
end)
