-- Collection feedback: a short pluck and a thin 140ms trail, without a neon
-- cube or catch flash. Inventory grants remain entirely server-owned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local Theme = require(Shared.UI:WaitForChild("Theme"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local player = Players.LocalPlayer
Sounds.preload({"loot.pickup"})

local active = 0
local function collect(from, itemName)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    Sounds.play("loot.pickup")
    -- Cap visual clutter independently of sound; a batch still gets one pluck.
    if active >= 6 then return end
    local definition = ItemDefinitions[itemName]
    local color = Theme.rarityColor(definition and definition.rarity)
    local host = Instance.new("Part")
    host.Name, host.Size, host.Transparency = "PickupTrailHost", Vector3.one * .1, 1
    host.Anchored, host.CanCollide, host.CanTouch, host.CanQuery = true, false, false, false
    host.CastShadow, host.CFrame = false, CFrame.new(from)
    local a, b = Instance.new("Attachment"), Instance.new("Attachment")
    a.Position, b.Position = Vector3.new(0, .055, 0), Vector3.new(0, -.055, 0)
    a.Parent, b.Parent = host, host
    local trail = Instance.new("Trail")
    trail.Name, trail.Attachment0, trail.Attachment1 = "PickupTrail", a, b
    trail.Lifetime, trail.MinLength, trail.FaceCamera = .055, .02, true
    trail.Color = ColorSequence.new(color)
    trail.Transparency = NumberSequence.new(.55, 1)
    trail.LightEmission, trail.LightInfluence = .2, 0
    trail.Parent, host.Parent = host, workspace
    Debris:AddItem(host, .3)
    active += 1
    local elapsed = 0
    local connection
    connection = RunService.RenderStepped:Connect(function(dt)
        elapsed += dt
        if elapsed >= .14 or not root.Parent or not host.Parent then
            connection:Disconnect()
            active -= 1
            host:Destroy()
            return
        end
        local alpha = math.clamp(elapsed / .14, 0, 1)
        host.Position = from:Lerp(root.Position + Vector3.new(0, 1, 0), alpha * alpha)
    end)
end

Remotes.wait("EnemyDropFlight").OnClientEvent:Connect(function(from, itemName)
    if typeof(from) == "Vector3" and type(itemName) == "string" and itemName ~= "" then
        collect(from, itemName)
    end
end)
