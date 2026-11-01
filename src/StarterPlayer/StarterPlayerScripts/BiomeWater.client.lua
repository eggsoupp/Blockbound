--[[
	BiomeWater

	Tints the water to match the biome this player stands in - pink in the
	Hallow, red in the Crimson, silty in the desert (TerrainConfig.Water.Biomes).

	Terrain water has a single colour for the whole world, so it cannot be
	painted lake by lake. A client write to Terrain does not replicate, though,
	so each player sees their own biome's water, the same way BiomeSky gives
	each their own sky. Eased rather than snapped, so crossing a border reads
	as the water turning.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TerrainConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Terrain"):WaitForChild("TerrainConfig")
)

local EASE = TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local player = Players.LocalPlayer
local terrain = workspace:WaitForChild("Terrain")
local water = TerrainConfig.Water

local current = nil

local function apply()
	local look = water.Biomes[player:GetAttribute("Biome")] or {}

	if current then
		current:Cancel()
	end
	current = TweenService:Create(terrain, EASE, {
		WaterColor = look.Color or water.Color,
		WaterTransparency = look.Transparency or water.Transparency,
	})
	current:Play()
end

player:GetAttributeChangedSignal("Biome"):Connect(apply)
apply()
