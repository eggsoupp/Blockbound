--[[
	BiomeSky

	Swaps the sky to match the biome this player stands in. A client write to
	Lighting does not replicate, so each player sees their own biome's sky.

	Faces are preloaded before the swap so the sky never flashes blank.
]]

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeSkies = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Terrain"):WaitForChild("BiomeSkies")
)

-- Roblox's Sky properties do not face where the purchased images expect, so
-- each image goes on the property that lines it up with Up (assets/skybox).
local PROPERTY_FOR_FACE = {
	Bk = "SkyboxRt",
	Rt = "SkyboxFt",
	Lf = "SkyboxBk",
	Ft = "SkyboxLf",
	Up = "SkyboxUp",
	Dn = "SkyboxDn",
}

local player = Players.LocalPlayer
local sky = Lighting:WaitForChild("Sky")

local defaultFaces = {}
for _, property in PROPERTY_FOR_FACE do
	defaultFaces[property] = sky[property]
end

local function facesFor(biome)
	local entry = BiomeSkies.Skies[biome]
	if not entry then
		return defaultFaces
	end

	local faces = {}
	for face, property in PROPERTY_FOR_FACE do
		if not entry[face] then
			return defaultFaces
		end
		faces[property] = "rbxassetid://" .. entry[face]
	end
	return faces
end

local function apply()
	local biome = player:GetAttribute("Biome")
	local faces = facesFor(biome)

	local preload = Instance.new("Sky")
	for property, id in faces do
		preload[property] = id
	end
	ContentProvider:PreloadAsync({ preload })
	preload:Destroy()

	-- The player may have walked on during the preload.
	if player:GetAttribute("Biome") ~= biome then
		return
	end

	for property, id in faces do
		sky[property] = id
	end
end

player:GetAttributeChangedSignal("Biome"):Connect(apply)
apply()
