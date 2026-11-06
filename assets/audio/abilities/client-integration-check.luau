local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("SoundService")
local Http = game:GetService("HttpService")
local Audio = require(RS.Shared.Audio.CombatAudio)
local Cues = require(RS.Shared.Audio.CombatCues)
local Sounds = require(RS.Shared.Audio.Sounds)
local Scope = require(RS.Shared.Abilities.AbilityScope)
local Config = require(RS.Shared.Abilities.AbilityConfig)
local Settings = require(RS.Shared.UI.PlayerSettings)
local player = game.Players.LocalPlayer
local root = (player.Character or player.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
task.wait(4)
local point = root.Position
local results = {modules={}, clips={}, checks={}, observed={}}
local observed = results.observed
workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Sound") and item:GetAttribute("CombatAudio") then
		observed[item.Name] = (observed[item.Name] or 0)+1
	end
end)
local function save()
	SS:SetAttribute("CombatAudioQAResults", Http:JSONEncode(results))
end
for name, definition in pairs(Config.Definitions) do
	local ok, module = pcall(require, RS.Shared.Abilities.VFX[definition.vfx])
	results.modules[name] = ok and type(module.play)=="function"
end
local originalVolume = Sounds.MasterVolume
Sounds.MasterVolume = .05
for key in pairs(Audio.Bank) do
	local sound = Audio.play(key, point, .15, 1, false, {throttle=0})
	if sound then
		pcall(function() game:GetService("ContentProvider"):PreloadAsync({sound}) end)
		task.wait(.04)
		results.clips[key] = {loaded=sound.IsLoaded, playing=sound.IsPlaying, position=sound.TimePosition,
			spatial=sound.Parent:IsA("BasePart") and sound.Parent.Transparency==1}
		sound:Destroy()
	else results.clips[key] = {error="No voice"} end
end
task.wait(.1)
local host = Instance.new("Part"); host.Transparency=1;host.Anchored=true;host.Position=point;host.Parent=workspace
local tail = Audio.play("energy_blast", host, .15)
host:Destroy(); task.wait(.1)
results.checks.detachedTail = tail and tail.Parent~=nil and tail.IsPlaying
if tail then tail:Destroy() end
local first = Audio.play("slime_pop",point,.15,1,false,{throttle=.2})
local blocked = Audio.play("slime_pop",point,.15,1,false,{throttle=.2})
local other = Audio.play("slime_pop",point+Vector3.new(32,0,0),.15,1,false,{throttle=.2})
results.checks.spatialThrottle = first~=nil and blocked==nil and other~=nil
if first then first:Destroy() end;if other then other:Destroy() end
local clip = Audio.play("energy_blast",point,.15,1,false,{clip=.15,throttle=0})
task.wait(.5);results.checks.clipCleanup = clip and clip.Parent==nil
local playing = Audio.play("power_up",point,.15,1,false,{throttle=0})
Sounds.MasterVolume=0;Settings.Changed:Fire("sfxVolume",0);task.wait()
results.checks.liveMute = playing and playing.Volume==0
Sounds.MasterVolume=.05;Settings.Changed:Fire("sfxVolume",.05);task.wait()
results.checks.liveUnmute = playing and playing.Volume>0
if playing then playing:Destroy() end
local scope = Scope.new()
Cues.cast({ability="CelestialLance",origin=CFrame.new(point),startedAt=workspace:GetServerTimeNow()},scope)
scope:destroy();task.wait(.1)
results.checks.cancelCleanup = Audio.stats().voices==0
local stress={}
for key in pairs(Audio.Bank) do
	local sound=Audio.play(key,point,.01,1,false,{throttle=0})
	if sound then table.insert(stress,sound) end
end
results.checks.voiceCap = Audio.stats().voices==40 and #stress==40
for _,sound in ipairs(stress) do sound:Destroy() end
task.wait(.1);results.checks.voiceCleanup = Audio.stats().voices==0
Sounds.MasterVolume=originalVolume
Settings.Changed:Fire("sfxVolume",originalVolume)
results.coreComplete=true
save()
SS:SetAttribute("CombatAudioQAReady",true)
while true do save();task.wait(.5) end
