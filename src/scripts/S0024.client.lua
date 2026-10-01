--[[
	spring-crouch-walk

	Sprint on Shift, crouch on C, with the field of view widening as you run.

	StarterCharacterScripts, so it re-runs per character and every reference
	below belongs to the body it is holding.

	Bound through ContextActionService, which keeps firing while a full-screen
	menu is up - hence the MenuState guards. Movement is already locked there,
	but without them a player could toggle crouch behind the menu and come back
	out of it in a state they never asked for.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MenuState = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("MenuState")
)

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local camera = workspace.CurrentCamera

-- === Editable config ===
local ANIM_ID = 10862419793
local NORMAL_SPEED = 16
local RUN_SPEED = 25
local CROUCH_SPEED = 8
local NORMAL_FOV = 70
local SPRINT_FOV = 80
local SPRINT_KEY = Enum.KeyCode.LeftShift
local CROUCH_KEY = Enum.KeyCode.C
local CROUCH_HIP_OFFSET = -1 -- studs taken off HipHeight while crouched

-- Below this the run animation stops; above it, and sprinting, it plays.
local RUN_ANIMATION_SPEED = 10

local runAnimation = Instance.new("Animation")
runAnimation.AnimationId = "rbxassetid://" .. ANIM_ID

--[[
	Loaded through the Animator, not the Humanoid: Humanoid:LoadAnimation has
	been deprecated for years and does not work at all from a LocalScript in
	some contexts.

	Roblox makes an Animator with the Humanoid, so the wait is about ordering -
	but one is created if it somehow is not there, because a nil track would
	turn a missing animation into half a dozen runtime errors below.
]]
local animator = humanoid:FindFirstChildOfClass("Animator")
	or humanoid:WaitForChild("Animator", 5)
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

local runTrack = animator:LoadAnimation(runAnimation)

local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local tweenSprint = TweenService:Create(camera, tweenInfo, { FieldOfView = SPRINT_FOV })
local tweenNormal = TweenService:Create(camera, tweenInfo, { FieldOfView = NORMAL_FOV })

local isSprinting = false
local isCrouching = false

-- The one place WalkSpeed is written, so crouching while sprinting and
-- releasing either one cannot leave the two states disagreeing about it.
local function applySpeed()
	if isCrouching then
		humanoid.WalkSpeed = CROUCH_SPEED
	elseif isSprinting then
		humanoid.WalkSpeed = RUN_SPEED
	else
		humanoid.WalkSpeed = NORMAL_SPEED
	end
end

local function setSprinting(sprinting)
	if sprinting == isSprinting then
		return
	end
	isSprinting = sprinting

	applySpeed()

	if sprinting then
		tweenSprint:Play()
		if not runTrack.IsPlaying then
			runTrack:Play()
		end
	else
		tweenNormal:Play()
		if runTrack.IsPlaying then
			runTrack:Stop()
		end
	end
end

local function setCrouching(crouching)
	if crouching == isCrouching then
		return
	end

	-- Applied as a delta against the height the character actually has, and
	-- only ever once in each direction, so it cannot drift.
	humanoid.HipHeight += if crouching then CROUCH_HIP_OFFSET else -CROUCH_HIP_OFFSET
	isCrouching = crouching

	applySpeed()
end

local function onSprint(_actionName, inputState)
	if MenuState.isAnyOpen() then
		return
	end

	-- Scriptable means something else is driving the camera - the pause menu's
	-- pull-back, an ability - and sprinting into that looks like a glitch.
	if camera.CameraType ~= Enum.CameraType.Custom then
		return
	end

	setSprinting(inputState == Enum.UserInputState.Begin)
end

local function onCrouch(_actionName, inputState)
	if MenuState.isAnyOpen() then
		return
	end

	if inputState == Enum.UserInputState.Begin then
		setCrouching(not isCrouching)
	end
end

ContextActionService:BindAction("SprintAction", onSprint, false, SPRINT_KEY)
ContextActionService:BindAction("CrouchAction", onCrouch, false, CROUCH_KEY)

-- A menu opening swallows the key-up that would have ended a sprint, which
-- otherwise leaves the player running at 25 with the animation looping.
MenuState.Changed:Connect(function(_, _, anyOpen)
	if anyOpen then
		setSprinting(false)
	end
end)

-- Keeps the animation honest when the player stops moving without letting go
-- of Shift - walking into a wall, or being caught on terrain.
humanoid.Running:Connect(function(speed)
	if speed >= RUN_ANIMATION_SPEED and isSprinting then
		if not runTrack.IsPlaying then
			runTrack:Play()
			tweenSprint:Play()
		end
	elseif speed < RUN_ANIMATION_SPEED and runTrack.IsPlaying then
		runTrack:Stop()
		tweenNormal:Play()
	end
end)

humanoid.Jumping:Connect(function()
	if runTrack.IsPlaying then
		runTrack:Stop()
	end
end)

humanoid.WalkSpeed = NORMAL_SPEED
camera.FieldOfView = NORMAL_FOV
