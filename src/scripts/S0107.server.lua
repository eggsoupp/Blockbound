--[[
	EquipServer

	Hands a player the Tool for an item they asked to equip, and takes it away
	again when they ask for nothing.

	The client never creates or destroys tools - it fires RequestEquipTool with
	an item name, or with nil to go empty-handed, and the server does the rest.
	A Tool destroyed on a client is still there on the server, so anything that
	asks "what are they holding?" would go on getting the old answer; making
	this the only place tools appear and disappear is what keeps that honest.

	Set DEBUG to true to trace the equip flow.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DEBUG = false
local function log(...)
	if DEBUG then
		print("[EquipServer]", ...)
	end
end

local ToolFactory = require(ServerScriptService:WaitForChild("ToolFactory"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestEquipTool = remotes:WaitForChild("RequestEquipTool")

-- Builds a template for every holdable item that does not already have one
-- authored. Before this, only the three Test tools had templates, so every tool
-- the crafting tree produced was unequippable.
local built, wrapped = ToolFactory.buildAll()
log(("built %d tool templates, wrapped %d authored model(s)"):format(built, wrapped))

-- Both an attribute and a StringValue: the attribute is what everything reads
-- now, the child is kept for the hand-authored tools in the place file.
local function tagTool(tool, itemName)
	tool:SetAttribute("ItemName", itemName)

	local existing = tool:FindFirstChild("ItemName") or tool:FindFirstChild("itemName")
	if existing and existing:IsA("StringValue") then
		existing.Value = itemName
		return
	end

	local value = Instance.new("StringValue")
	value.Name = "ItemName"
	value.Value = itemName
	value.Parent = tool
end

-- Everything the player is carrying, in both places a Tool can live.
local function clearTools(player)
	for _, place in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
		if place then
			for _, child in ipairs(place:GetChildren()) do
				if child:IsA("Tool") then
					child:Destroy()
				end
			end
		end
	end
end

local function give(player, itemName, template)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return false
	end

	clearTools(player)

	local tool = template:Clone()
	tagTool(tool, itemName)
	tool.Parent = backpack

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
		log(("equipped %s for %s"):format(itemName, player.Name))
	else
		log(("no humanoid for %s; %s left in the Backpack"):format(player.Name, itemName))
	end

	return true
end

--[[
	Which request is the current one, per player.

	Bumped by every request. The delayed retry below carries the number it was
	scheduled with and gives up if it is no longer the latest - without which a
	retry can hand somebody a sword AFTER they have already switched to
	something that is not holdable at all.

	That is the bug behind "I selected wood and the sword is still in my hand":
	the unequip arrived, cleared the tools, and then a two-tenths-of-a-second-old
	equip request finished the job it had been given and put the sword back.

	Weak-keyed, so a player leaving takes their counter with them.
]]
local generation = setmetatable({}, { __mode = "k" })

RequestEquipTool.OnServerEvent:Connect(function(player, itemName)
	local mine = (generation[player] or 0) + 1
	generation[player] = mine

	-- Anything that is not a name means "hold nothing", which is what an empty
	-- hotbar slot, a second press of the selected one, and selecting something
	-- that cannot be held all send.
	if type(itemName) ~= "string" or itemName == "" then
		clearTools(player)
		log(player.Name, "unequipped")
		return
	end

	local template = ToolFactory.ensure(itemName)
	if not template then
		--[[
			Not holdable. The client should not have asked - it checks
			ToolConfig.isHoldable first - but if it does, the honest answer is
			empty hands rather than leaving whatever was there before.

			Falling through silently is what made selecting a Material look
			like it had not registered: the request was dropped and the sword
			from the previous slot simply stayed.
		]]
		log(("no tool template for '%s'; unequipping instead"):format(itemName))
		clearTools(player)
		return
	end

	if give(player, itemName, template) then
		return
	end

	-- A player who joined a moment ago may not have a Backpack yet. One retry,
	-- because the alternative is a tool that silently never arrives.
	log("no Backpack yet for", player.Name, "- retrying")
	task.delay(0.2, function()
		-- Only if nothing has been asked for since. See `generation`.
		if generation[player] ~= mine then
			log("retry for", player.Name, "superseded; dropping it")
			return
		end

		if player.Parent and not give(player, itemName, template) then
			log("Backpack still missing on retry for", player.Name)
		end
	end)
end)
