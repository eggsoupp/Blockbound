local SS = game:GetService("SoundService")
local Sounds = require(game.ReplicatedStorage.Shared.Audio.Sounds)
local originalWeather = workspace:GetAttribute("Weather")
local originalMaster = Sounds.MasterVolume
local out = {}
workspace:SetAttribute("Weather", "Rain")
task.wait(1)
local rain = SS.WorldAmbience:FindFirstChild("rain_light")
out.rain = rain and {id=rain.SoundId,loaded=rain.IsLoaded,playing=rain.IsPlaying}
Sounds.MasterVolume = 0
task.wait(.75)
out.mutePassed = true
out.mutedBeds = {}
for _, sound in SS.WorldAmbience:GetChildren() do
    out.mutedBeds[sound.Name] = {volume=sound.Volume,playing=sound.IsPlaying}
    if sound.Volume ~= 0 or sound.IsPlaying then out.mutePassed=false end
end
Sounds.MasterVolume = originalMaster
workspace:SetAttribute("Weather", originalWeather)
local host = Instance.new("Part")
host.Name, host.Anchored, host.Transparency = "AudioReviewFire", true, 1
host.CanCollide, host.CanQuery, host.CanTouch = false, false, false
host:SetAttribute("AmbienceKey", "fire")
host.Parent = workspace
game:GetService("CollectionService"):AddTag(host, "BlockboundAmbience")
task.wait(.75)
local loop = host:FindFirstChild("AmbientLoop")
out.spatialFire = loop and {loaded=loop.IsLoaded,playing=loop.IsPlaying}
game:GetService("CollectionService"):RemoveTag(host, "BlockboundAmbience")
task.wait(.2)
out.spatialCleanup = host:FindFirstChild("AmbientLoop") == nil
host:Destroy()
SS:SetAttribute("AudioIntegrationResults", game:GetService("HttpService"):JSONEncode(out))
