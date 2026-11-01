-- Own grounded idle/walk/run; default Animate handles airborne/special states.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Profiles = require(Shared.Tools:WaitForChild("LocomotionProfiles"))
local ToolAnimation = require(Shared.Tools:WaitForChild("ToolAnimation"))
local Definitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local player = Players.LocalPlayer
local FADE = 0.15
local character, held, profile, track, trackId
local armTrack, armId
local lastPosition, elapsed, distance = nil, 0, 0
local measuredSpeed = 0
local busy = false

local function stopBody()
	if track then track:Stop(FADE) end
	track, trackId = nil, nil
end
local function stopArm()
	if armTrack then armTrack:Stop(FADE) end
	armTrack, armId = nil, nil
end
local function stop()
	stopBody()
	stopArm()
end
local function itemName(tool)
	local name = tool:GetAttribute("ItemName") or tool:GetAttribute("itemName")
	if type(name) == "string" and name ~= "" then return name end
	local value = tool:FindFirstChild("ItemName") or tool:FindFirstChild("itemName")
	return if value and value:IsA("StringValue") then value.Value else tool.Name
end
local function update(dt)
	local body = player.Character
	if character ~= body then
		stop()
		character, held, profile = body, nil, nil
		lastPosition, elapsed, distance, measuredSpeed = nil, 0, 0, 0
	end
	local humanoid = body and body:FindFirstChildOfClass("Humanoid")
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if not root or not humanoid or humanoid.Health <= 0 then stop() return end
	local position = root.Position
	if lastPosition then
		local delta = position - lastPosition
		if delta.Magnitude < 10 then distance += Vector3.new(delta.X, 0, delta.Z).Magnitude end
	end
	lastPosition = position
	elapsed += dt
	if elapsed >= 0.1 then
		measuredSpeed = distance / elapsed
		elapsed, distance = 0, 0
	end
	local tool = body:FindFirstChildOfClass("Tool")
	if not profile or tool ~= held then
		stop()
		held = tool
		profile = Profiles.forDefinition(tool and Definitions[itemName(tool)])
	end
	local state = humanoid:GetState()
	local grounded = (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.RunningNoPhysics)
		and humanoid.FloorMaterial ~= Enum.Material.Air and not humanoid.Sit
	if not grounded then
		body:SetAttribute("LocomotionState", "AirOrSpecial")
		stop()
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = math.min(Vector3.new(v.X, 0, v.Z).Magnitude, measuredSpeed)
	local moving = humanoid.MoveDirection.Magnitude > 0.05 and speed > 0.65
	local gait, id, rate = "Idle", profile.idle, 1
	if moving then
		local running = body:GetAttribute("Sprinting") == true and speed >= 10
		gait = if running then "Run" else "Walk"
		id = if running then profile.run else profile.walk
		local reference = if running then 25 else (profile.walkReference or 16)
		rate = math.clamp(speed / reference, 0.25, 1.5)
	end
	body:SetAttribute("LocomotionState", profile.name .. gait)
	if id ~= trackId or not track or not track.IsPlaying then
		stopBody()
		local nextTrack = ToolAnimation.track(body, id, Enum.AnimationPriority.Movement)
		if body ~= player.Character or tool ~= body:FindFirstChildOfClass("Tool") then return end
		if nextTrack then
			track, trackId = nextTrack, id
			track.Priority = Enum.AnimationPriority.Movement
			track.Looped = true
			track:Play(FADE, 1, rate)
		end
	end
	if track then track:AdjustSpeed(rate) end
	-- These published clips key only the right shoulder, elbow and wrist.
	-- The same unarmed track supplies every other joint, including the left arm.
	local nextArmId = profile.rightArm and profile.rightArm[gait]
	if nextArmId ~= armId or (armTrack and not armTrack.IsPlaying) then
		stopArm()
		if nextArmId then
			local loaded = ToolAnimation.track(body, nextArmId, Enum.AnimationPriority.Action)
			if body ~= player.Character or tool ~= body:FindFirstChildOfClass("Tool") then return end
			if loaded then
				armTrack, armId = loaded, nextArmId
				armTrack.Looped = true
				armTrack:Play(FADE, 1, rate)
			end
		end
	end
	if armTrack then armTrack:AdjustSpeed(rate) end
end
RunService.Heartbeat:Connect(function(dt)
	-- Serialise yielding asset loads so stale callbacks cannot leave orphan runs.
	if busy then return end
	busy = true
	local ok, err = pcall(update, dt)
	busy = false
	if not ok then warn("[ToolWalk] " .. tostring(err)) end
end)
