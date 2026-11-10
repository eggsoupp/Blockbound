--[[
	VoxelRigFX

	Draws the voxel creatures' move effects (ServerScriptService.Creatures.
	VoxelMoves) from the server's VoxelRigFX messages, through
	Shared.Enemies.VoxelRigs.Effects. Their animation runs in CreatureFX,
	which picks the rigs up from Shared.Enemies.CreatureRigs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Effects = require(Shared:WaitForChild("Enemies"):WaitForChild("VoxelRigs"):WaitForChild("Effects"))

local remote = Remotes.wait("VoxelRigFX", math.huge) -- made when the first creature loads

remote.OnClientEvent:Connect(function(kind, ...)
	local handler = Effects[kind]
	if type(handler) ~= "function" then
		return
	end
	local ok, err = pcall(handler, ...)
	if not ok then
		warn("[VoxelRigFX] " .. tostring(kind) .. ": " .. tostring(err))
	end
end)
