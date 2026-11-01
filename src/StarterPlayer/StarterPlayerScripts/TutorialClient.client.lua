--[[
	TutorialClient

	Runs the tutorial on screen: which step the guide shows, the Tab menu's
	ability choice, and the arrow over the tree and the slime. About a minute
	from first look to the island:

		tree      chop one tree with the axe on the hotbar
		table     craft planks, then a crafting table           [B]
		ability   Tab opens the menu on three common attacks    [Tab]
		fight     a training slime, cast at it and finish it
		island    the guide's button takes the player home

	The server (ServerScriptService.TutorialService) owns progress and says
	where the player is through the "TutorialStep" attribute; this file never
	moves a step itself. It only reads that, the bag (for which hotbar number
	the axe and the sword are on) and which menus are open, and draws.

	The guide is Shared.UI.TutorialPanel, the choice Shared.UI.TutorialChoice,
	the arrow Shared.UI.TutorialMarker, and every word is in
	Shared.UI.TutorialSteps.

	THE MENUS

	The Tab menu, the settings window, a chest and a confirm hide the guide.
	The crafting window does not: the table is made inside it, and the guide
	is what says which recipe comes next. The ability step never opens the
	Tab menu itself: pressing Tab is the thing it teaches.

	/tutorial (an admin command, DebugConsole) resets the server's state and
	bumps "TutorialRun"; that starts this from the top as well.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local MenuState = require(UI:WaitForChild("MenuState"))
local TutorialSteps = require(UI:WaitForChild("TutorialSteps"))
local Responsive = require(UI:WaitForChild("Responsive"))
local TutorialPanel = require(UI:WaitForChild("TutorialPanel"))
local TutorialChoice = require(UI:WaitForChild("TutorialChoice"))
local TutorialMarker = require(UI:WaitForChild("TutorialMarker"))
local InventoryMirror = require(Shared:WaitForChild("Inventory"):WaitForChild("InventoryMirror"))
local AbilityConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local Action = Remotes.wait("TutorialAction")
local Travel = Remotes.wait("TutorialTravel")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- After the character is up, before the first word. Long enough for the HUD
-- to settle, short enough that nobody has wandered off.
local WELCOME_DELAY = 1.2

-- Between a step ticking its boxes and the next one arriving.
local STEP_PAUSE = 0.9

-- The island button stays pressed this long, whatever the teleport does.
local TRAVEL_HOLD = 5

-- How long the last card stays after arriving home.
local FAREWELL = 9

-- /tutorial: the old guide leaves, and the welcome arrives this long after.
local RESTART_HOLD = 0.6

-- Where the hotbar ends in the bag.
local HOTBAR = 9

-- The tag HarvestServer chops by; see StructureConfig.
local TREE_TAG = "TreePart"
local TREE_RANGE = 220
local TREE_REAIM = 0.5

-- Menus that hide the guide. Crafting is missing on purpose; see the header.
local HIDES_GUIDE = { "PauseMenu", "Settings", "Chest", "Confirm" }

local panel = TutorialPanel.new(playerGui)
local choice = TutorialChoice.new(playerGui, TutorialSteps.Choices)
local marker = TutorialMarker.new(playerGui)

local started = false

-- What this run has done, cleared by /tutorial.
local run = {}

local function newRun()
	run = {
		-- The step the guide is showing, and one it is on its way to.
		shown = nil,
		pending = nil,
		token = 0,
		-- The pick was made in the Tab menu that is still open.
		choseInMenu = false,
		travelAt = nil,
		farewell = false,
		lastReadyAt = -math.huge,
		holdUntil = 0,
	}
end
newRun()

local refresh

-- ---------------------------------------------------------------------------
-- What the player is carrying
-- ---------------------------------------------------------------------------

local function isAxe(name: string): boolean
	return string.match(name, "Axe$") ~= nil and string.match(name, "Pickaxe$") == nil
end

local function isSword(name: string): boolean
	return string.match(name, "Sword$") ~= nil
end

-- The hotbar number of the first thing that passes `test`, or nil.
local function hotbarSlot(test: (string) -> boolean): number?
	local bag = InventoryMirror.get()
	for index = 1, HOTBAR do
		local slot = bag[index]
		if slot and type(slot.name) == "string" and (slot.count or 0) > 0 and test(slot.name) then
			return index
		end
	end
	return nil
end

local function countOf(itemName: string): number
	local total = 0
	for _, slot in pairs(InventoryMirror.get()) do
		if slot.name == itemName then
			total += slot.count or 0
		end
	end
	return total
end

local function displayName(abilityName: string?): string?
	local definition = AbilityConfig.get(abilityName)
	return definition and (definition.displayName or abilityName) or abilityName
end

-- The fight step's line for using what was picked.
local function castLine(abilityName: string?): string
	for _, card in ipairs(TutorialSteps.Choices) do
		if card.name == abilityName and card.cast then
			return if Responsive.isTouch() and card.touchCast then card.touchCast else card.cast
		end
	end
	return if Responsive.isTouch() then TutorialSteps.Touch.DefaultCast else TutorialSteps.DefaultCast
end

-- ---------------------------------------------------------------------------
-- The words
-- ---------------------------------------------------------------------------

--[[
	Fills a step's {braces}. A key that is not known - no axe on the hotbar,
	say - takes its brackets and the space before them with it, so the line
	reads "Hold your axe and click a tree" rather than "your axe [] and".
]]
local function fill(template: string, values): string
	local text = string.gsub(template, " %[{(%w+)}%]", function(key)
		local value = values[key]
		return if value then " [" .. tostring(value) .. "]" else ""
	end)
	text = string.gsub(text, "{(%w+)}", function(key)
		local value = values[key]
		return if value then tostring(value) else ""
	end)
	return text
end

local function isTravelling(): boolean
	return run.travelAt ~= nil and os.clock() - run.travelAt < TRAVEL_HOLD
end

local function viewFor(stepId: string)
	local step = TutorialSteps.byId(stepId)
	if not step then
		return nil
	end

	local chosen = player:GetAttribute("TutorialChosen")
	local values = {
		axe = hotbarSlot(isAxe),
		sword = hotbarSlot(isSword),
		key = player:GetAttribute("TutorialKey") or "Z",
		ability = displayName(chosen) or "your ability",
	}

	-- A touch screen has buttons where a computer has keys; see TutorialSteps.Touch.
	local touch = Responsive.isTouch()
	local body = if touch and step.touchBody then step.touchBody else step.body
	if stepId == "ability" and MenuState.isOpen("Crafting") then
		body = if touch then TutorialSteps.Touch.closeCrafting else TutorialSteps.Waits.closeCrafting
	end
	-- A plain replace, before the braces are filled: the line has braces of
	-- its own.
	body = string.gsub(body, "{cast}", function()
		return castLine(chosen)
	end)

	local goals = {}
	for index, text in ipairs(step.goals) do
		goals[index] = { text = text, done = false }
	end
	if stepId == "table" and goals[1] then
		goals[1].done = countOf("WoodPlank") > 0
	end

	return {
		id = stepId,
		index = step.index,
		count = TutorialSteps.Count,
		speaker = TutorialSteps.Speaker,
		title = step.title,
		body = fill(body, values),
		goals = goals,
		message = player:GetAttribute("TutorialMessage"),
		action = if step.action and isTravelling() then TutorialSteps.Travelling else step.action,
		actionEnabled = not isTravelling(),
	}
end

-- ---------------------------------------------------------------------------
-- The guide
-- ---------------------------------------------------------------------------

local function indexOf(stepId: string?): number
	local step = TutorialSteps.byId(stepId)
	return step and step.index or 0
end

--[[
	Shows a step. Moving on, the old one ticks its boxes first and the new one
	follows a moment later; anything else - the same step changing, or going
	back to the start - is shown at once.
]]
local function showStep(stepId: string)
	local view = viewFor(stepId)
	if not view then
		return
	end

	if run.pending then
		if run.pending == stepId then
			return
		end
		if indexOf(stepId) < indexOf(run.pending) then
			run.pending = nil
			run.token += 1
		end
	end

	local from = run.pending or run.shown
	if from and from ~= stepId and indexOf(stepId) > indexOf(from) and panel:isShown() then
		run.pending = stepId
		run.token += 1
		local token = run.token

		panel:complete()
		task.delay(STEP_PAUSE, function()
			if run.token ~= token then
				return
			end
			run.pending = nil
			run.shown = stepId
			local latest = viewFor(stepId)
			if latest then
				panel:show(latest)
			end
			refresh()
		end)
		return
	end

	run.shown = stepId
	panel:show(view)
end

local function guideHidden(): boolean
	for _, name in ipairs(HIDES_GUIDE) do
		if MenuState.isOpen(name) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- The choice in the Tab menu
-- ---------------------------------------------------------------------------

local function updateChoice(stepId: string)
	local tabOpen = MenuState.isOpen("PauseMenu")

	if stepId == "ability" and tabOpen then
		choice:showChoices(TutorialSteps.ChoiceTitle, TutorialSteps.ChoiceSubtitle)
		choice:setMessage(player:GetAttribute("TutorialMessage"))
	elseif stepId == "fight" and tabOpen and run.choseInMenu then
		local chosen = player:GetAttribute("TutorialChosen")
		local name = displayName(chosen) or "Your power"
		choice:showChosen(
			chosen,
			string.format(TutorialSteps.ChosenTitle, string.upper(name)),
			string.format(
				if Responsive.isTouch() then TutorialSteps.Touch.ChosenSubtitle else TutorialSteps.ChosenSubtitle,
				player:GetAttribute("TutorialKey") or "Z"
			)
		)
	else
		choice:hide()
	end
end

choice.onChoose = function(abilityName: string)
	Action:FireServer("choose", abilityName)

	-- A pick the server never answers - refused for a reason it did not
	-- say - must not leave the cards dead.
	task.delay(3, function()
		if choice:pendingName() == abilityName and player:GetAttribute("TutorialStep") == "ability" then
			choice:release()
		end
	end)
end

choice.onContinue = function()
	MenuState.requestClose("PauseMenu")
end

-- ---------------------------------------------------------------------------
-- The fight
-- ---------------------------------------------------------------------------

local function trainingTarget(): Instance?
	local value = player:FindFirstChild("TutorialTarget")
	return if value and value:IsA("ObjectValue") then value.Value else nil
end

-- Tells the server the player can see and move: the slime comes now.
local function readyToFight(stepId: string)
	if stepId ~= "fight" or MenuState.isOpen("PauseMenu") or trainingTarget() then
		return
	end
	local now = os.clock()
	if now - run.lastReadyAt < 2 then
		return
	end
	run.lastReadyAt = now
	Action:FireServer("ready")
end

-- ---------------------------------------------------------------------------
-- The arrow
-- ---------------------------------------------------------------------------

-- Tree models by any one of their tagged parts, kept as trees stream in and out.
local treeModels: { [Model]: BasePart } = {}
local partModel: { [Instance]: Model } = {}

local function trackTree(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		partModel[part] = model
		if not treeModels[model] then
			treeModels[model] = part :: BasePart
		end
	end
end

for _, part in ipairs(CollectionService:GetTagged(TREE_TAG)) do
	trackTree(part)
end
CollectionService:GetInstanceAddedSignal(TREE_TAG):Connect(trackTree)
CollectionService:GetInstanceRemovedSignal(TREE_TAG):Connect(function(part)
	local model = partModel[part]
	partModel[part] = nil
	if model and treeModels[model] == part then
		treeModels[model] = nil
	end
end)

local function nearestTree(): Model?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local here = root.Position
	local best, bestDistance = nil, TREE_RANGE
	for model, part in pairs(treeModels) do
		if model.Parent and part.Parent and not model:GetAttribute("Felled") then
			local distance = (part.Position - here).Magnitude
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

local function updateMarker(stepId: string)
	if stepId == "tree" then
		marker:point(nearestTree(), "TREE")
	elseif stepId == "fight" then
		marker:point(trainingTarget(), "SLIME")
	else
		marker:point(nil)
	end
end

-- Re-picks the nearest tree as the player walks.
task.spawn(function()
	while true do
		task.wait(TREE_REAIM)
		if started and player:GetAttribute("TutorialStep") == "tree" then
			marker:point(nearestTree(), "TREE")
		end
	end
end)

-- ---------------------------------------------------------------------------
-- The island
-- ---------------------------------------------------------------------------

panel.onAction = function()
	if player:GetAttribute("TutorialStep") ~= "island" or isTravelling() then
		return
	end
	run.travelAt = os.clock()
	Travel:FireServer()
	refresh()

	local current = run
	task.delay(TRAVEL_HOLD + 0.1, function()
		if run == current then
			refresh()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Everything, from the attributes
-- ---------------------------------------------------------------------------

function refresh()
	if not started or not player:GetAttribute("TutorialReady") then
		return
	end

	-- Restarting: the guide is on its way out, and comes back once it has gone.
	if os.clock() < run.holdUntil then
		return
	end

	local stepId = player:GetAttribute("TutorialStep")
	if type(stepId) ~= "string" or not TutorialSteps.byId(stepId) then
		return
	end

	panel:setSuppressed(guideHidden())

	if stepId == "done" then
		marker:point(nil)
		choice:hide()

		-- The last card is for arriving home. Done anywhere else, there is
		-- nothing left to say.
		if not player:GetAttribute("TutorialArrived") then
			run.token += 1
			run.pending = nil
			panel:hide()
			return
		end

		if not run.farewell then
			run.farewell = true
			local current = run
			task.delay(STEP_PAUSE + FAREWELL, function()
				if run == current and player:GetAttribute("TutorialStep") == "done" then
					panel:hide()
				end
			end)
			showStep(stepId)
		end
		return
	end

	showStep(stepId)
	updateChoice(stepId)
	updateMarker(stepId)
	readyToFight(stepId)
end

local lastStep = nil

player:GetAttributeChangedSignal("TutorialStep"):Connect(function()
	local stepId = player:GetAttribute("TutorialStep")

	-- Picked in the Tab menu that is still up: it says so before it closes.
	if lastStep == "ability" and stepId == "fight" and MenuState.isOpen("PauseMenu") then
		run.choseInMenu = true
	end
	lastStep = stepId

	refresh()
end)

for _, attribute in ipairs({
	"TutorialReady", "TutorialMessage", "TutorialChosen", "TutorialKey", "TutorialArrived",
}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		refresh()
	end)
end

-- /tutorial: from the top, with the whole entrance.
player:GetAttributeChangedSignal("TutorialRun"):Connect(function()
	newRun()
	run.holdUntil = os.clock() + RESTART_HOLD
	marker:point(nil)
	choice:hide()
	panel:hide()

	local current = run
	task.delay(RESTART_HOLD + 0.05, function()
		if run == current then
			lastStep = player:GetAttribute("TutorialStep")
			refresh()
		end
	end)
end)

-- The slime's arrow follows the server's pointer to it.
local function watchTarget(value: Instance)
	if value.Name == "TutorialTarget" and value:IsA("ObjectValue") then
		value.Changed:Connect(function()
			refresh()
		end)
		refresh()
	end
end
for _, child in ipairs(player:GetChildren()) do
	watchTarget(child)
end
player.ChildAdded:Connect(watchTarget)

MenuState.Changed:Connect(function(name, open)
	-- Closing the Tab menu after choosing is the cue for the fight.
	if name == "PauseMenu" and not open then
		run.choseInMenu = false
	end
	refresh()
end)

-- Hotbar numbers and the planks tick follow the bag. Only the steps that
-- show either.
InventoryMirror.onChanged(function()
	local stepId = player:GetAttribute("TutorialStep")
	if stepId == "tree" or stepId == "table" or stepId == "fight" then
		refresh()
	end
end)

player.CharacterAdded:Connect(function()
	task.delay(1, refresh)
end)

task.spawn(function()
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart")
	task.wait(WELCOME_DELAY)

	lastStep = player:GetAttribute("TutorialStep")
	started = true
	refresh()
end)
