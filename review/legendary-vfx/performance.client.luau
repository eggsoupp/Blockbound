local RS=game.ReplicatedStorage
local Run=game:GetService("RunService")
local p=game.Players.LocalPlayer
require(RS.Shared.UI.MenuState).requestClose("PauseMenu")
p.PlayerScripts.LegendaryQA:SetAttribute("Freeze",false)
local samples,peakEffects,peakEmitters,visible,sounds,broken={},0,0,0,0,0
local scan,active,elapsed=0,0,0
local conn=Run.RenderStepped:Connect(function(dt)
 elapsed+=dt;scan+=dt
 if scan>.1 then
  scan=0;active=0;local emitters=0
  for _,f in ipairs(workspace:GetChildren())do
   if f:GetAttribute("LegendaryAbility")then active+=1
    for _,d in ipairs(f:GetDescendants())do
     if d:IsA("ParticleEmitter")and d.Enabled then emitters+=1
     elseif d:IsA("BasePart")and d.Transparency<1 then visible+=1
     elseif d:IsA("Sound")then sounds+=1
     elseif d:IsA("Beam")and(not d.Attachment0 or not d.Attachment1)then broken+=1 end
    end
   end
  end
  peakEffects=math.max(peakEffects,active);peakEmitters=math.max(peakEmitters,emitters)
 end
 if active>0 then table.insert(samples,dt*1000)end
end)
task.wait(1)
local root=p.Character.HumanoidRootPart;local start=root.Position
local target=p:GetAttribute("ReferenceQATarget")
RS.Remotes.RequestAbility:FireServer("CelestialLance",target)
task.wait(.1);RS.Remotes.RequestAbility:FireServer("WraithfireOrb",target)
task.wait(.1);RS.Remotes.RequestAbility:FireServer("RiftMaelstrom",target)
p.Character.Humanoid:MoveTo(start+Vector3.new(9,0,0))
task.wait(2)
local travelled=(root.Position-start).Magnitude
task.wait(7)
conn:Disconnect()
table.sort(samples);local sum=0;for _,n in ipairs(samples)do sum+=n end
script:SetAttribute("Result",game.HttpService:JSONEncode({samples=#samples,meanMs=sum/math.max(1,#samples),p95Ms=samples[math.max(1,math.floor(#samples*.95))],peakMs=samples[#samples],peakEffects=peakEffects,peakEmitters=peakEmitters,visible=visible,sounds=sounds,brokenBeams=broken,remaining=active,travelled=travelled}))
script:SetAttribute("Done",true)
