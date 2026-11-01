--[[
	PlayerBiome

	Publishes the biome each player stands in as the "Biome" attribute on their
	Player, for per-player presentation such as the sky. The server answers
	because it holds the initialised BiomeMap; clients do not.

	A new biome must hold for two samples, so walking a blended border does not
	flicker between skies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

if require(Shared:WaitForChild("PlaceConfig")).isIsland() then
	return
end

local BiomeMap = require(Shared:WaitForChild("Terrain"):WaitForChild("BiomeMap"))

local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))

local SAMPLE_INTERVAL = 1
local STUD_SIZE = TerrainConfig.StudSize

local pending = {}

Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
end)

while true do
	task.wait(SAMPLE_INTERVAL)

	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

		if root then
			-- pcall: BiomeMap errors until TerrainManager has called init.
			local ok, _, biome = pcall(
				BiomeMap.sampleColumn,
				math.floor(root.Position.X / STUD_SIZE),
				math.floor(root.Position.Z / STUD_SIZE)
			)

			if ok and type(biome) == "string" then
				if pending[player] == biome then
					player:SetAttribute("Biome", biome)
				end
				pending[player] = biome
			end
		end
	end
end
