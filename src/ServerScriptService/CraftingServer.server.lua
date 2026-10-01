--[[
	CraftingServer

	The authority on crafting. Nothing the client sends is trusted beyond "which
	recipe id do you want" - and even that is looked up in the shared RecipeBook
	rather than taken at face value.

	What firing the remote cannot achieve:
	  a recipe that does not exist        RecipeBook lookup fails
	  a made-up ingredient list           the remote carries no such field
	  a station recipe from anywhere      range re-checked at craft time
	  crafting without the materials      counted before anything is consumed
	  losing the cost to a full bag       space checked before the take
	  spamming it                         rate limited per player
	  racing two crafts into one stock    per-player busy flag, and no yields
	                                      between check and commit
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local RecipeBook = require(Shared:WaitForChild("Crafting"):WaitForChild("RecipeBook"))
local StationConfig = require(Shared.Crafting:WaitForChild("StationConfig"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local ServerScriptService = game:GetService("ServerScriptService")
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local StationService = require(ServerScriptService:WaitForChild("StationService"))
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))

local RequestCraft = Remotes.ensure("RequestCraft", "RemoteEvent")
local CraftingResult = Remotes.ensure("CraftingResult", "RemoteEvent")

StationService.init(TerrainManager)

-- Minimum gap between craft requests from one player. Generous enough that
-- holding the button feels responsive, tight enough that a script cannot empty
-- a furnace in a frame.
local MIN_REQUEST_INTERVAL = 0.12

local lastRequestAt = {}
local busy = {}

local function reply(player, ok, recipeId, message)
	CraftingResult:FireClient(player, ok, recipeId, message)
end

--[[
	Runs one craft, start to finish, with no yields between the checks and the
	commit.

	Returns ok, message.
]]
local function tryCraft(player, recipeId)
	local recipe = RecipeBook.get(recipeId)
	if not recipe then
		return false, "Unknown recipe"
	end

	-- Station gate. Recipes with no station are craftable anywhere; the rest
	-- require the player to be genuinely standing at one right now.
	if recipe.station and not StationService.isNear(player, recipe.station) then
		return false, string.format(
			"Needs a %s nearby", StationConfig.getDisplayName(recipe.station)
		)
	end

	local inventory = InventoryService.GetInventory(player)
	if not inventory then
		return false, "No inventory"
	end

	-- Count everything before taking anything.
	for _, ingredient in ipairs(recipe.ingredients) do
		if inventory:Count(ingredient.item) < ingredient.count then
			return false, string.format("Not enough %s", ingredient.item)
		end
	end

	-- And make sure the result will fit, so a full bag cannot eat the cost.
	local hasRoom, roomReason = inventory:CanAdd(recipe.output.item, recipe.output.count)
	if not hasRoom then
		return false, roomReason or "No space"
	end

	for _, ingredient in ipairs(recipe.ingredients) do
		local removed = inventory:Remove(ingredient.item, ingredient.count)
		if not removed then
			-- Should be unreachable: the counts were just verified and nothing
			-- has yielded since. Reported rather than ignored, because if it
			-- ever does happen it means an invariant broke somewhere else.
			warn(string.format(
				"[CraftingServer] '%s' vanished mid-craft for %s; recipe '%s' aborted.",
				ingredient.item, player.Name, recipeId
			))
			InventoryService.SaveAndSync(player)
			return false, "Materials changed"
		end
	end

	inventory:Add(recipe.output.item, recipe.output.count)
	InventoryService.SaveAndSync(player)

	return true, string.format("Crafted %s", recipe.output.item)
end

RequestCraft.OnServerEvent:Connect(function(player, recipeId)
	if type(recipeId) ~= "string" then
		reply(player, false, nil, "Bad request")
		return
	end

	local now = os.clock()
	local last = lastRequestAt[player]
	if last and now - last < MIN_REQUEST_INTERVAL then
		return
	end
	lastRequestAt[player] = now

	-- Belt and braces alongside the yield-free sequence in tryCraft: if a future
	-- change ever introduces a yield in there, this still stops two requests
	-- overlapping on one player.
	if busy[player] then
		return
	end
	busy[player] = true

	Profiler.enter("Crafting.craft")
	local pcallOk, succeeded, reason = pcall(tryCraft, player, recipeId)
	Profiler.leave("Crafting.craft")

	busy[player] = nil

	if not pcallOk then
		warn("[CraftingServer] craft errored for", player.Name, succeeded)
		reply(player, false, recipeId, "Crafting failed")
		return
	end

	reply(player, succeeded == true, recipeId, reason)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
	busy[player] = nil
end)

