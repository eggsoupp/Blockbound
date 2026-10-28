--[[
	TutorialService

	The first minute in Blockbound, on the server: which step each player is
	on, what finishes it, and the training slime. The words and the drawing
	are the client's - Shared.UI.TutorialSteps, TutorialPanel, TutorialChoice
	and StarterPlayerScripts.TutorialClient. This file only decides.

		TutorialService.Start(player)           bag loaded: hand out tools, publish the step
		TutorialService.TreeFelled(player)      HarvestServer, on a felled tree
		TutorialService.Crafted(player, item)   CraftingServer, on any craft
		TutorialService.EnemyDefeated(player)   EnemyService, on any kill
		TutorialService.Reset(player)           /tutorial: back to the first step

	THE STEPS

		tree      fell one tree with the axe handed out here
		table     craft planks, then a crafting table
		ability   pressing Tab opens a choice of the three common attacks
		fight     a slime is summoned in front of the player; any kill counts
		island    travel home, through the guide's button (TutorialTravel)
		done

	The step is published as the player's "TutorialStep" attribute, and that
	is all the client reads to know where it is. A step only ever moves on
	from the one the player is actually on, so an event that arrives late or
	twice changes nothing.

	SAVED WITH THE INVENTORY

	A section of the inventory's record, like the ability loadout: one key and
	one session lock. A player with no record - new, or a session that could
	not read theirs - starts from the beginning.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))
local AbilityConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))

local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local AbilityLoadout = require(ServerScriptService:WaitForChild("AbilityLoadout"))

local Action = Remotes.ensure("TutorialAction", "RemoteEvent")

local TutorialService = {}

TutorialService.Steps = { "tree", "table", "ability", "fight", "island", "done" }

-- The three the Tab menu offers. The common attacks; Echo Step and Block Wall
-- are common too, but neither is something you kill a slime with.
TutorialService.Choices = { "Fireball", "WindBurst", "WaterBlade" }

-- Handed out once per save, and only if the bag does not already hold one.
-- The axe is what step one needs, the sword finishes the slime, and the
-- pickaxe is the rest of the game.
local STARTER_TOOLS = { "WoodAxe", "WoodSword", "WoodPickaxe" }

-- The training slime: what is summoned, how far in front of the player, and
-- how long after it goes missing (wandered off and despawned) a new one is.
local SLIME_KINDS = { "BlueSlime", "GreenSlime" }
local SLIME_DISTANCE = 16
local SLIME_RESPAWN = 4

-- How hard it hits, against a wild one. A wild slime takes a new player who
-- stands still from full to nothing in about twenty seconds; this is the
-- first fight anyone has, with a power they have had for ten seconds.
local SLIME_DAMAGE_SCALE = 0.4

-- Between two requests from one client.
local MIN_INTERVAL = 0.4

local stepIndex = {}
for index, id in ipairs(TutorialService.Steps) do
	stepIndex[id] = index
end

local choiceSet = {}
for _, name in ipairs(TutorialService.Choices) do
	choiceSet[name] = true
end

--[[
	player -> { step, chosen, ability, granted }

	`chosen` is what was picked in the Tab menu. `ability` is the one the
	tutorial ADDED to the loadout, if it added one - what /tutorial takes back
	so the choice can be made again. A player who picked something they
	already carried has no `ability`, and keeps it.

	Weak-keyed, like AbilityLoadout's loadouts: the entry has to outlive the
	player until the leave-save has read it.
]]
local states = setmetatable({}, { __mode = "k" })
local encounters = {}
local lastRequestAt = {}

local function stateFor(player)
	local state = states[player]
	if not state then
		state = { step = "tree", chosen = nil, ability = nil, granted = {} }
		states[player] = state
	end
	return state
end

local function enemyService()
	-- Late: EnemyService reaches back into this module on every kill.
	return require(ServerScriptService:WaitForChild("EnemyService"))
end

local function isPlayer(value): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function slotOf(player, abilityName): number?
	for slot, name in ipairs(AbilityLoadout.get(player)) do
		if name == abilityName then
			return slot
		end
	end
	return nil
end

--[[
	The attributes the client reads. The step goes last, so that by the time
	the client hears the step change, the pick and its key are already there.
]]
local function publish(player)
	local state = stateFor(player)

	local slot = state.chosen and slotOf(player, state.chosen)
	local key = slot and AbilityConfig.keyForSlot(slot)

	player:SetAttribute("TutorialChosen", state.chosen)
	player:SetAttribute("TutorialKey", key and key.Name)
	player:SetAttribute("TutorialAbility", state.ability)
	player:SetAttribute("TutorialStep", state.step)
end

local function say(player, message)
	player:SetAttribute("TutorialMessage", message)
end

-- ---------------------------------------------------------------------------
-- Saving
-- ---------------------------------------------------------------------------

InventoryStore.registerSection("tutorial", function(player)
	local state = states[player]
	if not state then
		return nil
	end

	local granted = {}
	for name, given in pairs(state.granted) do
		if given then
			granted[name] = true
		end
	end

	return {
		v = 2,
		step = state.step,
		chosen = state.chosen,
		ability = state.ability,
		granted = granted,
	}
end, function(player, value)
	value = if type(value) == "table" then value else {}
	local state = stateFor(player)

	local function choice(name)
		return if type(name) == "string" and choiceSet[name] then name else nil
	end

	state.step = if stepIndex[value.step] then value.step else "tree"
	state.chosen = choice(value.chosen)
	state.ability = choice(value.ability)

	table.clear(state.granted)
	if type(value.granted) == "table" then
		for _, name in ipairs(STARTER_TOOLS) do
			state.granted[name] = value.granted[name] == true
		end
	end

	publish(player)
end)

-- ---------------------------------------------------------------------------
-- Steps
-- ---------------------------------------------------------------------------

local function ownsItem(player, itemName): boolean
	local inventory = InventoryService.GetInventory(player)
	return inventory ~= nil and inventory:Count(itemName) > 0
end

local despawnEncounter

local function setStep(player, step)
	local state = stateFor(player)
	if state.step == step then
		return
	end

	state.step = step
	say(player, nil)

	-- A table already in the bag is a table already made: a player who works
	-- ahead, or replays the tutorial, is not asked to make another.
	if step == "table" and ownsItem(player, "CraftingTable") then
		state.step = "ability"
	end

	-- Already home. Only a replay gets here, since the first trip is the step.
	if state.step == "island" and PlaceConfig.isIsland() then
		state.step = "done"
		player:SetAttribute("TutorialArrived", true)
	end

	if state.step ~= "fight" then
		despawnEncounter(player)
	end

	publish(player)
	InventoryStore.markDirty(player)
end

-- Moves on only from `from`: the event has to be the one the step is waiting for.
local function advance(player, from, to)
	if states[player] and states[player].step == from then
		setStep(player, to)
	end
end

local function grantTools(player)
	local inventory = InventoryService.GetInventory(player)
	if not inventory then
		return
	end

	local state = stateFor(player)
	local changed = false

	-- One flag per tool, so a bag with room for only some of them gets the
	-- rest on a later join rather than never.
	for _, name in ipairs(STARTER_TOOLS) do
		if not state.granted[name] then
			if inventory:Count(name) > 0 or InventoryService.AddItemByName(player, name, 1) then
				state.granted[name] = true
				changed = true
			end
		end
	end

	if changed then
		InventoryStore.markDirty(player)
		InventoryService.SaveAndSync(player)
	end
end

function TutorialService.Start(player)
	if not InventoryService.GetInventory(player) then
		return
	end

	grantTools(player)

	local state = stateFor(player)

	-- The trip home is what finishes the island step, and arriving is the trip.
	if PlaceConfig.isIsland() and state.step == "island" then
		state.step = "done"
		player:SetAttribute("TutorialArrived", true)
		InventoryStore.markDirty(player)
	end

	publish(player)
	player:SetAttribute("TutorialReady", true)
end

function TutorialService.TreeFelled(player)
	advance(player, "tree", "table")
end

function TutorialService.Crafted(player, item)
	if item == "CraftingTable" then
		advance(player, "table", "ability")
	end
end

function TutorialService.EnemyDefeated(player)
	if isPlayer(player) then
		advance(player, "fight", "island")
	end
end

--[[
	Back to the first step, for /tutorial.

	Takes back the ability the tutorial gave, if it is still carried, so the
	Tab menu's choice is a real choice again; and forgets which tools were
	handed out, so an axe that has since been lost is handed out again. Tools
	still in the bag are not doubled - grantTools checks.
]]
function TutorialService.Reset(player)
	local state = stateFor(player)

	if state.ability and AbilityLoadout.has(player, state.ability) then
		AbilityLoadout.remove(player, state.ability)
	end

	state.chosen = nil
	state.ability = nil
	table.clear(state.granted)
	state.step = "tree"

	despawnEncounter(player)
	say(player, nil)
	player:SetAttribute("TutorialArrived", nil)

	-- Bumped so the client restarts from the welcome even if the step it saw
	-- last was already "tree". Before the step is published, so the client
	-- hears "start again" first rather than turning the page backwards.
	player:SetAttribute("TutorialRun", (player:GetAttribute("TutorialRun") or 0) + 1)

	grantTools(player)
	publish(player)
	InventoryStore.markDirty(player)
end

-- ---------------------------------------------------------------------------
-- The choice
-- ---------------------------------------------------------------------------

local function choose(player, abilityName)
	local state = stateFor(player)
	if state.step ~= "ability" or not choiceSet[abilityName] then
		return
	end

	-- Already carried: chosen, and nothing to add or later take back.
	if not AbilityLoadout.has(player, abilityName) then
		local ok, message = AbilityLoadout.add(player, abilityName)
		if not ok then
			say(player, message)
			return
		end
		state.ability = abilityName
	end

	state.chosen = abilityName
	setStep(player, "fight")
end

-- ---------------------------------------------------------------------------
-- The training slime
-- ---------------------------------------------------------------------------

local function targetValue(player): ObjectValue
	local value = player:FindFirstChild("TutorialTarget")
	if not value then
		value = Instance.new("ObjectValue")
		value.Name = "TutorialTarget"
		value.Parent = player
	end
	return value :: ObjectValue
end

function despawnEncounter(player)
	local model = encounters[player]
	encounters[player] = nil

	local value = player:FindFirstChild("TutorialTarget")
	if value then
		value.Value = nil
	end

	if model then
		task.defer(function()
			enemyService().despawn(model, "tutorial over")
		end)
	end
end

local function summon(player)
	local state = states[player]
	if not state or state.step ~= "fight" then
		return
	end

	local enemies = enemyService()
	local current = encounters[player]
	if current and enemies.isAlive(current) then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- In front of where they are facing, so it walks into view rather than
	-- arriving behind them.
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)

	local spot = root.Position + flat * SLIME_DISTANCE
	local ground = Vector3.new(spot.X, enemies.groundAt(spot.X, spot.Z, root.Position.Y), spot.Z)

	local model, reason
	for _, kind in ipairs(SLIME_KINDS) do
		model, reason = enemies.spawn(kind, ground)
		if model then
			break
		end
	end

	if not model then
		warn("[TutorialService] could not summon a slime: " .. tostring(reason))
		say(player, "No slime would come. Defeat any enemy to carry on.")
		return
	end

	encounters[player] = model
	targetValue(player).Value = model
	enemies.setDamageScale(model, SLIME_DAMAGE_SCALE)
	say(player, nil)

	-- Watched until it dies or wanders off. Gone with the step still waiting
	-- means it despawned rather than died; another comes a moment later.
	task.spawn(function()
		while encounters[player] == model and enemies.isAlive(model) do
			task.wait(0.5)
		end

		if encounters[player] ~= model then
			return
		end
		encounters[player] = nil
		targetValue(player).Value = nil

		task.wait(SLIME_RESPAWN)
		if player.Parent and states[player] and states[player].step == "fight" then
			summon(player)
		end
	end)
end

Action.OnServerEvent:Connect(function(player, action, argument)
	if not player:GetAttribute("TutorialReady") then
		return
	end

	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < MIN_INTERVAL then
		return
	end
	lastRequestAt[player] = now

	if action == "choose" and type(argument) == "string" then
		choose(player, argument)
	elseif action == "ready" then
		-- Sent when the Tab menu closes on the fight step: the slime comes
		-- once the player can see it and move.
		summon(player)
	end
end)

--[[
	Beaten by the slime: it goes with them. Otherwise it waits at the spawn
	and is on them again before they can see. The client says "ready" once
	the new character is up, and a fresh one comes in front of them.
]]
local function watchCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			if states[player] and states[player].step == "fight" then
				despawnEncounter(player)
			end
		end)
	end
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	despawnEncounter(player)
	lastRequestAt[player] = nil
end)

return TutorialService
