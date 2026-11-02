--[[
	spring-crouch-walk

	Sprint on Shift, with the field of view widening as you run.
	ToolWalk owns all grounded animations; this script only sets speed and FOV.

	StarterCharacterScripts, so it re-runs per character and every reference
	below belongs to the body it is holding.

	Bound through ContextActionService, which keeps firing while a full-screen
	menu is up - hence the MenuState guards. Movement is already locked there,
	and sprint should not start behind the menu.
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
local NORMAL_FOV = 70
local SPRINT_FOV = 80
local SPRINT_KEY = Enum.KeyCode.LeftShift

-- Below this the run animation stops; above it, and sprinting, it plays.
local RUN_ANIMATION_SPEED = 10

local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local tweenSprint = TweenService:Create(camera, tweenInfo, { FieldOfView = SPRINT_FOV })
local tweenNormal = TweenService:Create(camera, tweenInfo, { FieldOfView = NORMAL_FOV })

local isSprinting = false

-- ToolWalk is the sole grounded animation controller.
local runMode = false
local function setRunMode(on)
    runMode = on
end

-- The one place WalkSpeed is written for walking and sprinting.
-- A SpeedMultiplier attribute on the character (set by the server - a
-- spider's web) scales whichever speed applies, and is re-applied when it
-- changes, so being slowed mid-sprint and recovering both just work.
local function applySpeed()
	character:SetAttribute("Sprinting", isSprinting)
	local multiplier = character:GetAttribute("SpeedMultiplier") or 1
	if isSprinting then
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

ContextActionService:BindAction("SprintAction", onSprint, false, SPRINT_KEY)

--[[
	A touch screen's RUN button (StarterPlayerScripts.TouchControls) toggles
	an attribute on the player; a new body starts walking, so it starts off.
]]
player:SetAttribute("TouchSprint", false)

player:GetAttributeChangedSignal("TouchSprint"):Connect(function()
	local on = player:GetAttribute("TouchSprint") == true
	if on and (MenuState.isAnyOpen() or camera.CameraType ~= Enum.CameraType.Custom) then
		player:SetAttribute("TouchSprint", false)
		return
	end
	setSprinting(on)
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
