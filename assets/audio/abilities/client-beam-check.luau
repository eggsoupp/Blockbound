local RS=game.ReplicatedStorage
local Audio=require(RS.Shared.Audio.CombatAudio)
local Cues=require(RS.Shared.Audio.CombatCues)
local Sounds=require(RS.Shared.Audio.Sounds)
local Settings=require(RS.Shared.UI.PlayerSettings)
local Choreo=require(RS.Shared.Abilities.VFX.SignusChoreography)
local Scope=require(RS.Shared.Abilities.AbilityScope)
local p=game.Players.LocalPlayer
local root=(p.Character or p.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
task.wait(4)
local original=Sounds.MasterVolume
local point=root.Position+Vector3.new(0,5,0)
local function mount(at)
	local part=Instance.new("Part");part.Transparency=1;part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false
	part.Position=at;part:SetAttribute("SignusKind","RiftBeam");part:SetAttribute("Charge",.1)
	part:SetAttribute("Duration",3);part:SetAttribute("Target",at+Vector3.zAxis*40)
	part:SetAttribute("StartedAt",workspace:GetServerTimeNow()-.3);part.Parent=workspace
	local scope=Scope.new();scope:add(part)
	local update=Choreo.mount(part,scope)
	return part,scope,update
end
local result={}
local part,scope,update=mount(point)
update(true);task.wait(.1)
local sound=part:FindFirstChildOfClass("Sound")
result.loopPlaying=sound~=nil and sound.IsPlaying and sound.Looped
Sounds.MasterVolume=0;Settings.Changed:Fire("sfxVolume",0);update(true)
result.animatedLoopMute=sound~=nil and sound.Volume==0
Sounds.MasterVolume=.5;Settings.Changed:Fire("sfxVolume",.5);update(true)
result.animatedLoopUnmute=sound~=nil and sound.Volume>0
scope:destroy();task.wait(.1);result.loopCleanup=Audio.stats().voices==0
local far,farScope,farUpdate=mount(point+Vector3.xAxis*1000)
result.outOfRangeSafe=pcall(farUpdate,false) and far:FindFirstChildOfClass("Sound")==nil
farScope:destroy()
local stress={}
for i=1,40 do table.insert(stress,Audio.play("electric_hum",point,.01,1,false,{throttle=0})) end
local capped,cappedScope,cappedUpdate=mount(point)
result.voiceCapSafe=pcall(cappedUpdate,true) and capped:FindFirstChildOfClass("Sound")==nil
cappedScope:destroy();for _,s in ipairs(stress) do s:Destroy() end
local glass
local warm=Instance.new("Sound");warm.SoundId=Audio.ids.glass_break1
game:GetService("ContentProvider"):PreloadAsync({warm});warm:Destroy()
local connection=workspace.DescendantAdded:Connect(function(v) if v:IsA("Sound") and v.Name=="glass_break1" then glass=v end end)
Cues.boss({boss="Signus",kind="crescentBreak",struck=true,position=point,startedAt=workspace:GetServerTimeNow()})
local deadline=os.clock()+2
repeat task.wait(.05) until (glass and glass.IsLoaded and glass.IsPlaying) or os.clock()>deadline
result.struckCrescent=glass~=nil and glass.IsLoaded and glass.IsPlaying
if glass then glass:Destroy() end;connection:Disconnect()
Sounds.MasterVolume=original;Settings.Changed:Fire("sfxVolume",original)
task.wait(.1);result.finalCleanup=Audio.stats().voices==0
game.SoundService:SetAttribute("CombatBeamQAResults",game.HttpService:JSONEncode(result))
