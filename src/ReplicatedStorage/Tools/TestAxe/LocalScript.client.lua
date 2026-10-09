--[[
	TestAxe

	Points at what the player swung at and tells the server. That is all it does.

	It used to damage the tree and call Destroy on the model itself. A client
	calling Destroy only removes the model on that client, so the tree reappeared
	the moment anything refreshed - and letting the client decide that a tree
	fell, and what it dropped, is not something the server can check after the
	fact. HarvestServer owns both now, and re-does the raycast's conclusion
	against its own view of where the player is.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local RequestHarvest = Remotes.wait("RequestHarvest")

local tool = script.Parent
local CHOP_RANGE = 12

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true -- water is Terrain; aim through it

tool.Activated:Connect(function()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return
	end

	rayParams.FilterDescendantsInstances = { character }

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local origin = camera.CFrame.Position
	local result = workspace:Raycast(origin, camera.CFrame.LookVector * CHOP_RANGE, rayParams)
	if result then
		RequestHarvest:FireServer(result.Instance)
	end
end)
