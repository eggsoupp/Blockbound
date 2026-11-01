--[[
	spring-crouch-walk

	Sprint on Shift, crouch on C, with the field of view widening as you run.
	ToolWalk owns all grounded animations; this script only sets speed and FOV.

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

local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local tweenSprint = TweenService:Create(camera, tweenInfo, { FieldOfView = SPRINT_FOV })
local tweenNormal = TweenService:Create(camera, tweenInfo, { FieldOfView = NORMAL_FOV })

local isSprinting = false
local isCrouching = false

-- ToolWalk is the sole grounded animation controller.
local runMode = false
local function setRunMode(on)
    runMode = on
end

-- The one place WalkSpeed is written, so crouching while sprinting and
-- releasing either one cannot leave the two states disagreeing about it.
-- A SpeedMultiplier attribute on the character (set by the server - a
-- spider's web) scales whichever speed applies, and is re-applied when it
-- changes, so being slowed mid-sprint and recovering both just work.
local function applySpeed()
	character:SetAttribute("Sprinting", isSprinting and not isCrouching)
	local multiplier = character:GetAttribute("SpeedMultiplier") or 1
	if isCrouching then
		humanoid.WalkSpeed = CROUCH_SPEED * multiplier
	elseif isSprinting then
		humanoid.WalkSpeed = RUN_SPEED * multiplier
	else
		humanoid.WalkSpeed = NORMAL_SPEED * multiplier
	end
end

character:GetAttributeChangedSignal("SpeedMultiplier"):Connect(applySpeed)

local function setSprinting(sprinting)
	if sprinting == isSprinting then
		return
	end
	isSprinting = sprinting

	applySpeed()

	if sprinting then
		tweenSprint:Play()
		setRunMode(true)
	else
		tweenNormal:Play()
		setRunMode(false)
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
    if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
        setSprinting(false)
        return
    end
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

--[[
	A touch screen's RUN and CROUCH buttons (StarterPlayerScripts.TouchControls)
	are toggles kept as attributes on the player, so they outlive this script's
	character; a new body starts standing and walking, so they start off.
]]
player:SetAttribute("TouchSprint", false)
player:SetAttribute("TouchCrouch", false)

player:GetAttributeChangedSignal("TouchSprint"):Connect(function()
	local on = player:GetAttribute("TouchSprint") == true
	if on and (MenuState.isAnyOpen() or camera.CameraType ~= Enum.CameraType.Custom) then
		player:SetAttribute("TouchSprint", false)
		return
	end
	setSprinting(on)
end)

player:GetAttributeChangedSignal("TouchCrouch"):Connect(function()
	if MenuState.isAnyOpen() then
		player:SetAttribute("TouchCrouch", isCrouching)
		return
	end
	setCrouching(player:GetAttribute("TouchCrouch") == true)
end)

-- A menu opening swallows the key-up that would have ended a sprint, which
-- otherwise leaves the player running at 25 with the animation looping.
MenuState.Changed:Connect(function(_, _, anyOpen)
	if anyOpen then
		setSprinting(false)
		player:SetAttribute("TouchSprint", false)
	end
end)

-- Keeps the animation honest when the player stops moving without letting go
-- of Shift - walking into a wall, or being caught on terrain.
humanoid.Running:Connect(function(speed)
	if speed >= RUN_ANIMATION_SPEED and isSprinting then
		if not runMode then
			setRunMode(true)
			tweenSprint:Play()
		end
	elseif speed < RUN_ANIMATION_SPEED and runMode then
		setRunMode(false)
		tweenNormal:Play()
	end
end)

humanoid.Jumping:Connect(function()
	if runMode then
		setRunMode(false)
	end
end)

applySpeed()
camera.FieldOfView = NORMAL_FOV
