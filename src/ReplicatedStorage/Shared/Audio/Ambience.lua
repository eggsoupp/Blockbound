-- Client ambient bed. Weather is consumed from attributes; this does not create weather.
-- Optional spatial loops: tag a BasePart/Attachment "BlockboundAmbience" and set
-- AmbienceKey to "fire", "waterfall", etc. Untagging or removing it stops its loop.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local Assets = require(script.Parent:WaitForChild("DownloadedSounds"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local Ambience = {}
local started = false
local beds, spatial = {}, {}
-- These two uploads failed client approval checks on 2026-11-01. Do not try
-- to play the waterfall until approved; use the working rain quietly instead.
local unavailable = {waterfall = true}
local overrides = {rain_light = Assets.ambience_rain_heavy}
local levels = {wind = .08, night = .16, sea = .14, snow = .12,
    rain_light = .2, rain_heavy = .22, thunderstorm = .18}

local function desired()
    local player = Players.LocalPlayer
    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    if not head then return nil end
    -- Suppress outdoor beds under a roof, including caves.
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then table.insert(exclude, p.Character) end
    end
    params.FilterDescendantsInstances = exclude
    params.RespectCanCollide = true
    if workspace:Raycast(head.Position, Vector3.new(0, 100, 0), params) then return nil end
    local weather = workspace:GetAttribute("Weather")
    if type(weather) == "string" then weather = string.lower(weather) end
    if weather == "thunderstorm" then return "thunderstorm" end
    if weather == "storm" or weather == "heavyrain" then return "rain_heavy" end
    if weather == "rain" or workspace:GetAttribute("Raining") == true then return "rain_light" end
    local biome = player:GetAttribute("Biome")
    if biome == "Snow" then return "snow" end
    if biome == "Ocean" or biome == "Beach" then return "sea" end
    if Lighting.ClockTime < 6 or Lighting.ClockTime >= 18 then return "night" end
    return "wind"
end

local function spatialLoop(host)
    if spatial[host] or not (host:IsA("BasePart") or host:IsA("Attachment")) then return end
    local key = host:GetAttribute("AmbienceKey")
    if type(key) ~= "string" then return end
    local id = Assets["ambience_" .. key]
    if not id or unavailable[key] then return end
    local sound = Instance.new("Sound")
    sound.Name, sound.SoundId, sound.Looped, sound.Volume = "AmbientLoop", id, true, 0
    sound.RollOffMinDistance, sound.RollOffMaxDistance = 8, 80
    sound.Parent = host
    spatial[host] = sound
    sound:Play()
end

function Ambience.start()
    if started or not RunService:IsClient() then return end
    started = true
    local folder = Instance.new("Folder")
    folder.Name, folder.Parent = "WorldAmbience", SoundService
    for _, host in ipairs(CollectionService:GetTagged("BlockboundAmbience")) do spatialLoop(host) end
    CollectionService:GetInstanceAddedSignal("BlockboundAmbience"):Connect(spatialLoop)
    CollectionService:GetInstanceRemovedSignal("BlockboundAmbience"):Connect(function(host)
        local sound = spatial[host]
        if sound then sound:Destroy(); spatial[host] = nil end
    end)
    task.spawn(function()
        while started do
            local key = desired()
            local master = math.clamp(Sounds.MasterVolume, 0, 1)
            if key and master > 0 and not beds[key] then
                local sound = Instance.new("Sound")
                sound.Name, sound.SoundId = key, overrides[key] or Assets["ambience_" .. key]
                sound.Looped, sound.Volume, sound.Parent = true, 0, folder
                beds[key] = sound
            end
            for name, sound in pairs(beds) do
                local target = if name == key then levels[name] * master else 0
                sound.Volume += (target - sound.Volume) * .18
                if master == 0 then sound.Volume = 0 end
                if target > 0 then
                    if not sound.IsPlaying then sound:Resume() end
                elseif sound.Volume < .001 then
                    sound.Volume = 0
                    sound:Pause()
                end
            end
            for host, sound in pairs(spatial) do
                if not host:IsDescendantOf(workspace) then
                    sound:Destroy(); spatial[host] = nil
                else
                    sound.Volume = .25 * master
                    if master == 0 then sound:Pause()
                    elseif not sound.IsPlaying then sound:Resume() end
                end
            end
            task.wait(.25)
        end
    end)
end

return Ambience
