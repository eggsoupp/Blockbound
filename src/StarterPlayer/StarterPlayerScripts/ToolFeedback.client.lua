--[[
	ToolFeedback

	Plays the swing when a tool is used, and the sounds for picking one up and
	putting it away.

	One script rather than one per tool: it watches the character for any Tool,
	so every tool present and future gets the same behaviour.

	ADDING A SWING IS ADDING AN ID

	  Shared.Tools.ToolConfig.Animations.Weapon = "rbxassetid://123"

	and every weapon swings. A single item can overrule its class with
	`animation` in its own ItemDefinitions entry. No rigging, no per-tool
	script, no server involvement.

	Weapons and axes have none yet. A tool with none still makes its sound and
	still hits; it simply does not move. Pickaxes do have one, but it is the
	mining swing and MiningClient plays it - looped while held, timed to the
	pickaxe's miningSpeed - so this script leaves pickaxes alone.

	NO PROCEDURAL FALLBACK, DELIBERATELY. Tweening the Tool's Grip needs no
	asset, which was its appeal - but Grip changes made on a CLIENT do not
	replicate, so the wielder saw an arc and everyone else saw them holding a
	motionless sword. It also fought everything else that writes the grip: the
	weld TestSword makes, a future holster, an ability that poses the weapon.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local ToolConfig = require(Shared:WaitForChild("Tools"):WaitForChild("ToolConfig"))
local ToolAnimation = require(Shared.Tools:WaitForChild("ToolAnimation"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local player = Players.LocalPlayer

-- tool -> { track: AnimationTrack? }, for the tools currently in the character.
local activeTools = {}

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

--[[
	The animation this tool should play on a click, or nil for one with none
	configured.

	Nil for a pickaxe whatever is configured: its swing is MiningClient's, which
	loops it for as long as the button is held and times it to the pickaxe's
	miningSpeed. Playing it here as well would start a second copy on every
	click and fight that loop.
]]
local function animationIdFor(tool)
	local definition = ItemDefinitions[itemNameFor(tool)]
	if definition and definition.classification == "Pickaxe" then
		return nil
	end

	return ToolConfig.animationFor(definition and definition.classification, definition)
end

--[[
	Whether this script stays out of a tool's swing entirely, sound included.

	The axe ("Tool"): HarvestClient swings it once per StructureConfig.
	ChopSeconds, playing the animation and the sound itself, so they match the
	chops rather than the clicks. A sound here on every click would put the
	click speed straight back into what the player hears.
]]
local function swingOwnedElsewhere(tool)
	local definition = ItemDefinitions[itemNameFor(tool)]
	return definition ~= nil and definition.classification == "Tool"
end

--[[
	One swing.

	The sound plays whether or not there is an animation to go with it: it is
	the half of the feedback that always works, and a click with no response at
	all is what this script exists to prevent.
]]
local function swing(tool)
	local state = activeTools[tool]
	if not state or swingOwnedElsewhere(tool) then
		return
	end

	Sounds.play("tool.swing")

	local id = animationIdFor(tool)
	if not id then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local track = ToolAnimation.track(character, id)
	if not track then
		return
	end

	--[[
		Restarted rather than layered. Holding the mouse down fires Activated
		repeatedly, and letting each one start its own pass over the top of the
		last produces a tool that jitters instead of one that swings; stopping
		first makes a held click read as a rhythm.
	]]
	if track.IsPlaying then
		track:Stop(0.05)
	end

	track:Play()
	state.track = track
end

local function trackTool(tool)
	if activeTools[tool] then
		return
	end

	activeTools[tool] = { track = nil }

	tool.Activated:Connect(function()
		swing(tool)
	end)

	tool.AncestryChanged:Connect(function(_, parent)
		if not parent then
			activeTools[tool] = nil
		end
	end)
end

--[[
	Puts a tool away: stops its swing if one was still running, so a weapon
	unequipped mid-arc does not leave the character holding the pose.
]]
local function releaseTool(tool)
	local state = activeTools[tool]
	if not state then
		return
	end

	if state.track and state.track.IsPlaying then
		state.track:Stop(0.1)
	end

	activeTools[tool] = nil
end

local function watchCharacter(character)
	table.clear(activeTools)

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			trackTool(child)
		end
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			trackTool(child)
			Sounds.play("tool.equip")
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			releaseTool(child)
		end
	end)
end

if player.Character then
	watchCharacter(player.Character)
end
player.CharacterAdded:Connect(watchCharacter)
