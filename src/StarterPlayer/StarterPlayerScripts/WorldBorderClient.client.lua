--[[
	Draws the world border with the pack's Force Field wherever the player is
	near it. The authored model is an arc of seven panels; it is laid out flat
	here and slides along the border with the player, since the world's edge is
	far too long to line with panels. Collision is WorldBorder.server.lua.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))

if not PlaceConfig.isWorld() then
	return
end

local WORLD_EDGE = TerrainConfig.WorldRadiusBlocks * TerrainConfig.StudSize
local SHOW_DISTANCE = 500
local PANEL_WIDTH = 16
local PANEL_HEIGHT = 35
local PANEL_COUNT = 7
local SIDE_PANELS = 24 -- plain panels each side of the reactive row
-- Whole multiples of the hexagon tile, so a slide doesn't jump the pattern.
local SLIDE_STEP = 80
local LIFT_STEP = 36

local SIDES = {
	{ axis = "X", sign = 1 },
	{ axis = "X", sign = -1 },
	{ axis = "Z", sign = 1 },
	{ axis = "Z", sign = -1 },
}

local template = ReplicatedStorage:WaitForChild("WorldBorderForceField")
local folder = Instance.new("Folder")
folder.Name = "WorldBorderForceField"
folder.Parent = workspace

local function setup(panel, offset)
	panel.Anchored = true
	panel.CanCollide = false
	panel.CanQuery = false
	panel.CanTouch = false
	panel:SetAttribute("BorderOffset", offset)
end

local function buildSide(side)
	local model = template:Clone()
	local script = model:FindFirstChild("ForceField Config")
	local parts = {}
	for i = 1, PANEL_COUNT do
		local panel = model:FindFirstChild(tostring(i))
		setup(panel, (i - 4) * PANEL_WIDTH)
		table.insert(parts, panel)
	end

	local plain = model:FindFirstChild("4")
	for i = 1, SIDE_PANELS do
		for _, direction in { -1, 1 } do
			local panel = plain:Clone()
			panel.Name = "Plain"
			setup(panel, direction * (3 + i) * PANEL_WIDTH)
			panel.Parent = model
			table.insert(parts, panel)
		end
	end

	side.parts = parts
	side.model = model
	side.script = script
	side.cell = nil
end

local function place(side, along, height)
	-- Panels face the map's centre.
	local frame
	if side.axis == "X" then
		local position = Vector3.new(side.sign * WORLD_EDGE, height, along)
		frame = CFrame.lookAt(position, position - Vector3.new(side.sign, 0, 0))
	else
		local position = Vector3.new(along, height, side.sign * WORLD_EDGE)
		frame = CFrame.lookAt(position, position - Vector3.new(0, 0, side.sign))
	end
	for _, panel in side.parts do
		panel.CFrame = frame * CFrame.new(panel:GetAttribute("BorderOffset"), 0, 0)
	end
end

for _, side in SIDES do
	buildSide(side)
end

local function snap(value, step)
	return math.round(value / step) * step
end

RunService.Heartbeat:Connect(function()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local position = root.Position
	for _, side in SIDES do
		local across = if side.axis == "X" then position.X else position.Z
		local along = if side.axis == "X" then position.Z else position.X
		local near = WORLD_EDGE - across * side.sign < SHOW_DISTANCE

		if near then
			local slide = math.clamp(snap(along, SLIDE_STEP), -WORLD_EDGE, WORLD_EDGE)
			local height = snap(position.Y, LIFT_STEP) + PANEL_HEIGHT * 0.25
			local cell = slide .. "/" .. height
			if side.cell ~= cell then
				side.cell = cell
				place(side, slide, height)
			end
			if side.model.Parent ~= folder then
				side.model.Parent = folder
				side.script.Enabled = true
			end
		end
	end
end)
