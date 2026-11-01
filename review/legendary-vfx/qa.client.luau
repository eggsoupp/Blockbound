-- Ordinary LocalScript: casts the real RequestAbility remote and observes normal gameplay.
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local p=game.Players.LocalPlayer
repeat task.wait(.2) until p:GetAttribute("GodMode") and p.Character
task.wait(.5)
local Menu=require(RS.Shared.UI.MenuState)
Menu.requestClose("PauseMenu")
task.wait(.6)
local camera=workspace.CurrentCamera
camera.CameraType=Enum.CameraType.Custom;camera.CameraSubject=p.Character:FindFirstChildOfClass("Humanoid")
p.CameraMinZoomDistance=45;p.CameraMaxZoomDistance=45
p.PlayerGui.InventoryUI.Enabled=false
camera.CFrame=CFrame.lookAt(p.Character:GetPivot().Position+Vector3.new(23,33,-23),p.Character:GetPivot().Position+Vector3.new(0,0,0))
local counts,packets={},{ }
RS.Remotes.AbilityImpact.OnClientEvent:Connect(function(packet)
 if not require(RS.Shared.Abilities.ReferencePlan)[packet.ability] then return end
 counts[packet.event]=(counts[packet.event] or 0)+1
 table.insert(packets,{event=packet.event,ability=packet.ability,time=packet.startedAt,position=tostring(packet.position)})
 script:SetAttribute("Signals",game.HttpService:JSONEncode(counts))
 script:SetAttribute("Packets",game.HttpService:JSONEncode(packets))
end)
script:GetAttributeChangedSignal("Go"):Connect(function()
 Menu.requestClose("PauseMenu")
 task.wait(1)
 local target=script:GetAttribute("Target") or p:GetAttribute("ReferenceQATarget")
 if script:GetAttribute("Ability")=="CelestialLance" or script:GetAttribute("Ability")=="WraithfireOrb" then target+=Vector3.yAxis*4 end
 script:SetAttribute("LastCast",workspace:GetServerTimeNow())
 RS.Remotes.RequestAbility:FireServer(script:GetAttribute("Ability"),target)
 if script:GetAttribute("Move") then p.Character.Humanoid:MoveTo(p.Character.HumanoidRootPart.Position+Vector3.new(7,0,0)) end
end)
local acc,n,sum,peak,maxEffects,maxEmitters,maxVisible,maxSounds=0,0,0,0,0,0,0,0
local samples={}
RunService.RenderStepped:Connect(function(dt)
 game.Lighting.ClockTime=14
 camera.CameraType=Enum.CameraType.Custom
 n+=1;sum+=dt;peak=math.max(peak,dt);acc+=dt
 local effects,emitters,visible,sounds=0,0,0,0
 for _,folder in ipairs(workspace:GetChildren()) do
  if folder:GetAttribute("ReferenceAbility") then
   effects+=1
   for _,d in ipairs(folder:GetDescendants()) do
    if d:IsA("ParticleEmitter") and d.Enabled then emitters+=1
    elseif d:IsA("BasePart") and d.Transparency<1 then visible+=1
    elseif d:IsA("Sound") then sounds+=1 end
   end
  end
 end
 maxEffects=math.max(maxEffects,effects);maxEmitters=math.max(maxEmitters,emitters);maxVisible=math.max(maxVisible,visible);maxSounds=math.max(maxSounds,sounds)
 script:SetAttribute("Active",effects)
 if acc>1 then
  local row={meanMs=sum/n*1000,peakMs=peak*1000,effects=effects,emitters=emitters}
  table.insert(samples,row);if #samples>120 then table.remove(samples,1) end
  script:SetAttribute("Samples",game.HttpService:JSONEncode(samples))
  script:SetAttribute("MaxEffects",maxEffects);script:SetAttribute("MaxEmitters",maxEmitters)
  script:SetAttribute("VisibleCarriers",maxVisible);script:SetAttribute("Sounds",maxSounds)
  n=0;sum=0;peak=0;acc=0
 end
end)
script:SetAttribute("Ready",true)

RS.Remotes.AbilityImpact.OnClientEvent:Connect(function(packet)
 if not script:GetAttribute("Freeze") or not (packet.event=="hit" or packet.event=="collapse" or packet.event=="strike" and packet.index==3) then return end
 task.delay(.12,function() for _,f in ipairs(workspace:GetChildren()) do if f:GetAttribute("LegendaryAbility") then for _,d in ipairs(f:GetDescendants()) do if d:IsA("ParticleEmitter") then d.TimeScale=0;d.Enabled=false end end end end end)
end)
