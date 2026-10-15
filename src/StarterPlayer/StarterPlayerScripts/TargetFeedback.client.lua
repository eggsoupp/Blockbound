--[[
	TargetFeedback

	The outlines nothing else owns: the enemy a weapon swing would hit, and the
	station, scroll or dispenser whose prompt is showing. Plus what the attacker
	sees when the server reports how a swing went.

	Mining, chopping and building claim their own outlines in their own scripts,
	off the rays those actions already cast. All of them go through
	Shared.UI.WorldFeedback, which draws exactly one at a time.

	THE ENEMY OUTLINE PREDICTS, IT DOES NOT DECIDE

	WeaponServer picks the nearest live enemy inside the weapon's range and its
	forward arc, measured from the character's facing. This asks the same
	question with the same WeaponConfig numbers - ten times a second, over the
	enemies folder rather than the whole Workspace - so the outline sits on the
	thing the next swing will connect with. The server still answers for real:
	a swing it refuses, or that finds nothing, comes back and says so.

		"hit"      the enemy flashes white (bosses: edge only, so the body that
		           is winding up a telegraph is never painted over)
		"kill"     a shell of light where it died - the model is already gone
		"miss"     the outlined enemy, if any, flashes red: out of the arc
		"refused"  the outlined enemy flashes grey: the swing came too soon

	THE PROMPT OUTLINE USES ROBLOX'S OWN CHOICE

	ProximityPromptService already decides which one prompt is showing, by
	distance and facing. That decision is the target; nothing here searches.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local MenuState = require(Shared:WaitForChild("UI"):WaitForChild("MenuState"))
local WorldFeedback = require(Shared.UI:WaitForChild("WorldFeedback"))
local Theme = require(Shared.UI:WaitForChild("Theme"))
local WeaponConfig = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponConfig"))
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))

local CombatFeedback = Remotes.wait("CombatFeedback")

local player = Players.LocalPlayer

-- How often the weapon target is re-predicted.
local ENEMY_INTERVAL = 0.1

-- A prompt's model is outlined whole only if it is about furniture-sized;
-- anything larger outlines just the part the prompt hangs on.
local PROMPT_MODEL_MAX_EXTENT = 24

-- The shell a kill leaves, as a fraction of the enemy's height.
local KILL_SHELL_SCALE = 0.9
local KILL_SHELL_COLOR = Color3.new(1, 1, 1):Lerp(Theme.Color.Accent, 0.25)

-- ---------------------------------------------------------------------------
-- Enemies
-- ---------------------------------------------------------------------------

-- model -> true, kept by the folder's own signals rather than a scan.
local enemies = {}

local function watchFolder(folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			enemies[child] = true
		end
	end

	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			enemies[child] = true
		end
	end)

	folder.ChildRemoved:Connect(function(child)
		enemies[child] = nil
	end)
end

do
	local folder = workspace:FindFirstChild(EnemyConfig.WorldFolder)
	if folder then
		watchFolder(folder)
	else
		local waiting
		waiting = workspace.ChildAdded:Connect(function(child)
			if child.Name == EnemyConfig.WorldFolder then
				waiting:Disconnect()
				watchFolder(child)
			end
		end)
	end
end

-- The same three sources, in the same order, WeaponServer reads.
local function itemNameFor(tool)
	local attribute = tool:GetAttribute("ItemName") or tool:GetAttribute("itemName")
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end

	local value = tool:FindFirstChild("ItemName") or tool:FindFirstChild("itemName")
	if value and value:IsA("StringValue") and value.Value ~= "" then
		return value.Value
	end

	return tool.Name
end

-- Weapon stats for the held tool, looked up once per equip.
local heldTool, heldStats = nil, nil

local function heldWeaponStats(character)
	local tool = character:FindFirstChildOfClass("Tool")
	if tool ~= heldTool then
		heldTool = tool
		heldStats = if tool then WeaponConfig.get(itemNameFor(tool)) else nil
	end
	return heldStats
end

-- The enemy currently outlined as the weapon's target, if any.
local target: Model? = nil

--[[
	WeaponServer's choice, asked on this side: nearest within range, inside the
	arc of the character's flattened facing. Allocation free - the walk keeps
	one model and a distance.
]]
local function predictTarget()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local stats = character and heldWeaponStats(character)

	if not (root and stats) or MenuState.isAnyOpen() then
		return nil
	end

	local origin = root.Position
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local facing = if flat.Magnitude < 1e-3 then nil else flat.Unit
	local rangeSquared = stats.range * stats.range

	local best, bestSquared = nil, math.huge

	for model in pairs(enemies) do
		if model.Parent then
			local offset = model:GetPivot().Position - origin
			local squared = offset:Dot(offset)

			if squared <= rangeSquared and squared < bestSquared then
				local inArc = true
				if facing then
					local across = Vector3.new(offset.X, 0, offset.Z)
					inArc = across.Magnitude <= 1e-3 or across.Unit:Dot(facing) >= stats.arcCosine
				end

				if inArc then
					best, bestSquared = model, squared
				end
			end
		end
	end

	return best
end

local enemyAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	enemyAccumulator += dt
	if enemyAccumulator < ENEMY_INTERVAL then
		return
	end
	enemyAccumulator = 0

	local predicted = predictTarget()
	if predicted ~= target then
		target = predicted
		WorldFeedback.focus("enemy", predicted, "Enemy")
	end
end)

local function isBoss(enemyName)
	local definition = type(enemyName) == "string" and EnemyConfig.Definitions[enemyName]
	return definition ~= nil and definition ~= false and definition.boss == true
end

CombatFeedback.OnClientEvent:Connect(function(kind, model, position, enemyName, height)
	if kind == "hit" then
		WorldFeedback.flash(model, if isBoss(enemyName) then "HitOutline" else "Hit", 0.16)
	elseif kind == "kill" then
		-- The model is destroyed on the server in the same step, so the outline
		-- is dropped now rather than when its removal replicates.
		if target ~= nil and target == model then
			target = nil
			WorldFeedback.release("enemy", true)
		end

		if typeof(position) == "Vector3" then
			local size = math.clamp((tonumber(height) or 4) * KILL_SHELL_SCALE, 2, 14)
			WorldFeedback.impact(position, KILL_SHELL_COLOR, size, "Ball", 0.45)
		end
	elseif kind == "miss" then
		WorldFeedback.flash(target, "Invalid", 0.18)
	elseif kind == "refused" then
		WorldFeedback.flash(target, "Refused", 0.18)
	end
end)

-- ---------------------------------------------------------------------------
-- Prompts
-- ---------------------------------------------------------------------------

local shownPrompt: ProximityPrompt? = nil
local shownAdornee: Instance? = nil

-- What to outline for a prompt: its model when that is station-sized, else the
-- part it hangs on. Asked once per PromptShown, which is rare.
local function adorneeFor(prompt: ProximityPrompt): Instance?
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		parent = parent.Parent
	end

	if not parent or not parent:IsDescendantOf(workspace) then
		return nil
	end

	local model = if parent:IsA("Model") then parent else parent:FindFirstAncestorOfClass("Model")
	if model and model ~= workspace and model:GetExtentsSize().Magnitude <= PROMPT_MODEL_MAX_EXTENT then
		return model
	end

	return if parent:IsA("BasePart") then parent else nil
end

local function claimPrompt()
	if shownAdornee and not MenuState.isAnyOpen() then
		WorldFeedback.focus("interact", shownAdornee, "Interact")
	else
		WorldFeedback.release("interact")
	end
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	shownPrompt = prompt
	shownAdornee = adorneeFor(prompt)
	claimPrompt()
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	if prompt == shownPrompt then
		shownPrompt, shownAdornee = nil, nil
		WorldFeedback.release("interact")
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeredBy)
	if triggeredBy == player and prompt == shownPrompt then
		WorldFeedback.flash(shownAdornee, "Confirm")
	end
end)

-- A menu over the world hides the outline; closing it brings back the one
-- whose prompt is still showing.
MenuState.Changed:Connect(claimPrompt)
