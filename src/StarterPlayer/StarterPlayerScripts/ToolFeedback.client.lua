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

	Both are empty because this project has no swing animation yet. A tool with
	none still makes its sound and still hits; it simply does not move.

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
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local player = Players.LocalPlayer

-- tool -> { track: AnimationTrack? }, for the tools currently in the character.
local activeTools = {}

--[[
	character -> animation id -> AnimationTrack, or false for one that failed.

	Loading an animation is a round trip to the asset and a tool can be clicked
	several times a second, so each is loaded once per body. Weak-keyed on the
	character, so a respawn drops the whole set rather than leaving tracks bound
	to a corpse.
]]
local tracksByCharacter = setmetatable({}, { __mode = "k" })

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
	The animation this tool should play, or nil for one with none configured.
]]
local function animationIdFor(tool)
	local definition = ItemDefinitions[itemNameFor(tool)]

	return ToolConfig.animationFor(definition and definition.classification, definition)
end

--[[
	A loaded, ready-to-play track for an id on this character.

	Failures are remembered as `false` rather than retried: an id that does not
	load will not start loading because somebody clicked again, and warning once
	per body per id is the difference between a message and a flood.
]]
local function trackFor(character, id)
	local perCharacter = tracksByCharacter[character]
	if not perCharacter then
		perCharacter = {}
		tracksByCharacter[character] = perCharacter
	end

	local cached = perCharacter[id]
	if cached ~= nil then
		return cached or nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = id

	local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
	animation:Destroy()

	if not ok or not loaded then
		warn(string.format(
			"[ToolFeedback] could not load the swing animation '%s' - check the id is an "
				.. "Animation you own. Tools using it will not move.",
			id
		))
		perCharacter[id] = false
		return nil
	end

	--[[
		Action priority, so the swing plays OVER walking and idling rather than
		being blended into a shrug by them. Set here rather than expected of the
		asset, because an animation uploaded with the wrong priority is the most
		common reason a swing does not appear to play at all.
	]]
	pcall(function()
		loaded.Priority = Enum.AnimationPriority.Action
	end)

	perCharacter[id] = loaded
	return loaded
end

--[[
	One swing.

	The sound plays whether or not there is an animation to go with it: it is
	the half of the feedback that always works, and a click with no response at
	all is what this script exists to prevent.
]]
local function swing(tool)
	local state = activeTools[tool]
	if not state then
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

	local track = trackFor(character, id)
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
