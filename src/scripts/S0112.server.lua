--[[
	SpawnServer

	Puts the spawn point on the ground.

	The world is generated around the origin and the terrain under it is a
	different height on every seed, so a SpawnLocation left wherever it was
	dragged in Studio is either buried or floating. This finds the surface at the
	origin and sits the spawn on it, every time the place starts.

	It also lays a small platform, which is what players land on while the chunk
	beneath them streams in.

	The guarantee that the ground here is Plains, rather than whatever the noise
	felt like, comes from TerrainConfig.SpawnGuaranteeBlocks - see BiomeMap.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TerrainConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Terrain"):WaitForChild("TerrainConfig")
)
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))

-- The platform is a flat disc of the same block grid, so it reads as part of
-- the world rather than as a dropped prop.
local PLATFORM_RADIUS_STUDS = 14
local PLATFORM_THICKNESS = 1

local SPAWN_SIZE = Vector3.new(12, 1, 12)

-- Init is idempotent, so calling it here removes any dependence on whether
-- InitTerrain happened to run first.
TerrainManager:Init()

local function findSpawnHeight()
	local surfaceY = TerrainManager:GetSurfaceY(0, 0)
	if not surfaceY then
		-- Outside the world somehow; fall back to ground level.
		return TerrainConfig.MinHeight * TerrainConfig.StudSize
	end
	return surfaceY
end

local surfaceY = findSpawnHeight()

-- The visible pad, sitting flush on the surface height the generator reports.
local platform = workspace:FindFirstChild("SpawnPlatform")
if not platform then
	platform = Instance.new("Part")
	platform.Name = "SpawnPlatform"
	platform.Shape = Enum.PartType.Cylinder
	platform.Parent = workspace
end

platform.Size = Vector3.new(PLATFORM_THICKNESS, PLATFORM_RADIUS_STUDS * 2, PLATFORM_RADIUS_STUDS * 2)
-- A cylinder's length runs along X, so it has to be rolled onto its face.
platform.CFrame = CFrame.new(0, surfaceY + PLATFORM_THICKNESS * 0.5, 0)
	* CFrame.Angles(0, 0, math.rad(90))
platform.Anchored = true
platform.CanCollide = true
platform.CanQuery = true
platform.CanTouch = false
platform.Material = Enum.Material.Slate
platform.Color = Color3.fromRGB(122, 128, 118)
platform.TopSurface = Enum.SurfaceType.Smooth
platform.BottomSurface = Enum.SurfaceType.Smooth

-- Reuses whatever SpawnLocation is already in the place, so a hand-placed one
-- keeps its settings and only its position is taken over.
local spawn = workspace:FindFirstChildOfClass("SpawnLocation")

if not spawn then
	spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Size = SPAWN_SIZE
	spawn.Neutral = true
	spawn.Transparency = 0.6
	spawn.Color = Color3.fromRGB(196, 186, 150)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = workspace
end

-- Only the things that must be true are forced. An existing SpawnLocation keeps
-- its size, look and team settings - this moves it and makes sure it works.
local height = spawn.Size.Y
spawn.CFrame = CFrame.new(0, surfaceY + PLATFORM_THICKNESS + height * 0.5, 0)
spawn.Anchored = true
spawn.CanCollide = true
spawn.Enabled = true

-- Belt and braces: a player who ends up under the world - spawning before the
-- platform existed, or through a chunk that had not loaded - is put back
-- rather than left falling forever.
local RESCUE_Y = (TerrainConfig.WorldFloorY - 8) * TerrainConfig.StudSize

local function watchCharacter(character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end

	task.spawn(function()
		while root.Parent and character.Parent do
			if root.Position.Y < RESCUE_Y then
				root.CFrame = spawn.CFrame + Vector3.new(0, 6, 0)
				root.AssemblyLinearVelocity = Vector3.zero
			end
			task.wait(1)
		end
	end)
end

local function watchPlayer(player)
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)
