--[[
	ToolWalk

	Walks and runs the character with the held tool the way that tool is
	carried: a sword walk for a sword, a heavier one for a heavy sword, a lance
	walk for a lance, and the normal walk for a pickaxe, an axe or anything else
	held - and, sprinting, the matching run. Which is which is ToolConfig.
	WalkAnimations and RunAnimations, keyed by the weapon's `weaponClass` in
	ItemDefinitions.

	ONLY WHILE MOVING, ONLY WHILE HOLDING

	A walk or a run plays while the character is on the ground and moving with
	a tool out. Standing still, jumping, falling, swimming or climbing hands
	straight back to the default animations. Empty hands are never touched.

	Sprinting is told apart by WalkSpeed being above ToolConfig.
	WalkReferenceSpeed (spring-crouch-walk raises it); the run plays only once
	actually moving at RunMinimumSpeed, the same threshold spring-crouch-walk
	uses, and below that a sprinting player walks. spring-crouch-walk plays its
	own run only with empty hands, so the two never play at once.

	LAYERED, NOT REPLACED

	The default Animate script is left alone and keeps playing its walk
	underneath. This one plays at Movement priority, which wins over that walk
	and over the held-tool arm pose, and loses to an Action swing - so mining
	while walking moves the legs with this and the arms with the swing.

	Played on this character's own Animator, so everyone else sees it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ToolConfig = require(Shared:WaitForChild("Tools"):WaitForChild("ToolConfig"))
local ToolAnimation = require(Shared.Tools:WaitForChild("ToolAnimation"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local player = Players.LocalPlayer

-- Below this horizontal speed the character counts as standing, so drifting
-- to a stop does not leave a walk playing in place.
local MOVING_SPEED = 0.6

-- How quickly the walk fades in and out, matching the default Animate's feel.
local FADE = 0.2

-- Bounds on the playback rate, so a shove or a slope cannot spin the legs.
local MIN_RATE = 0.4
local MAX_RATE = 1.25

local GROUNDED = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
}

-- The same three sources, in the same order, every tool script reads.
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

-- The held tool, its walk and its run, worked out once per equip rather than
-- per frame.
local heldTool, heldWalk, heldRun, heldIdle = nil, nil, nil, nil

-- What is playing now.
local playing = { character = nil, id = nil, track = nil }

local function stop()
	if playing.track then
		playing.track:Stop(FADE)
	end
	playing.id, playing.track = nil, nil
end

local function play(character, id)
	stop()

	local track = ToolAnimation.track(character, id, Enum.AnimationPriority.Movement)
	if not track then
		return
	end

	track.Looped = true
	track:Play(FADE)
	playing.character, playing.id, playing.track = character, id, track
end

RunService.Heartbeat:Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	-- A new body: whatever was playing belonged to the old one.
	if playing.character ~= character then
		playing.character, playing.id, playing.track = character, nil, nil
	end

	if not (humanoid and root) or humanoid.Health <= 0 then
		stop()
		return
	end

	-- Empty hands (or a block, or any item that is not a held Tool) use the
	-- Default walk and run, so `definition` nil is a real case, not a skip.
	local tool = character:FindFirstChildOfClass("Tool")
	if tool ~= heldTool or heldWalk == nil then
		heldTool = tool
		local definition = tool and ItemDefinitions[itemNameFor(tool)]
		heldWalk = ToolConfig.walkAnimationFor(definition)
		heldRun = ToolConfig.runAnimationFor(definition)
		heldIdle = ToolConfig.idleAnimationFor(definition)
	end

	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local grounded = GROUNDED[humanoid:GetState()]

	local moving = grounded
		and speed > MOVING_SPEED
		and humanoid.MoveDirection.Magnitude > 0.05

	if not moving then
		-- Standing on the ground with a class that has its own idle (a lance).
		if grounded and heldIdle then
			if playing.id ~= heldIdle then
				play(character, heldIdle)
			end
			if playing.track then
				playing.track:AdjustSpeed(1)
			end
		elseif playing.id then
			stop()
		end
		return
	end

	-- Walk or run, and the speed that gait was made for.
	local gait, reference = heldWalk, ToolConfig.WalkReferenceSpeed
	if humanoid.WalkSpeed > ToolConfig.WalkReferenceSpeed and speed >= ToolConfig.RunMinimumSpeed then
		gait, reference = heldRun, ToolConfig.RunReferenceSpeed
	end

	-- Switching gait cross-fades: play() fades the old one out as this fades in.
	if playing.id ~= gait then
		play(character, gait)
	end

	if playing.track then
		playing.track:AdjustSpeed(math.clamp(speed / reference, MIN_RATE, MAX_RATE))
	end
end)
