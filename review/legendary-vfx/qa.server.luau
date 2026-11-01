-- Temporary Studio playtest only; removed from the edit DataModel after QA.
local Players=game:GetService("Players")
local SSS=game:GetService("ServerScriptService")
local p=Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
repeat task.wait(.2) until p.Character and p.Character:FindFirstChild("HumanoidRootPart") and p:GetAttribute("TutorialReady")
task.wait(4)
local Loadout=require(SSS.AbilityLoadout)
local Combat=require(SSS.CombatService)
script:SetAttribute("Original",game.HttpService:JSONEncode(Loadout.get(p)))
Loadout.clear(p)
for _,name in ipairs({"VioletTempest","CelestialLance","WraithfireOrb"}) do assert(Loadout.add(p,name)) end
Combat.setInvulnerable(p,true)
local trees=Instance.new("Folder");trees.Name="ReferenceQATrees";trees.Parent=game.ServerStorage
for _,chunk in ipairs(workspace.GeneratedTerrain:GetChildren()) do
 for _,v in ipairs(chunk:GetChildren()) do
  if v:IsA("Model") and string.find(string.lower(v.Name),"tree") and (v:GetPivot().Position-Vector3.new(-60,252,-110)).Magnitude<120 then
   v:SetAttribute("ReferenceQAParent",chunk.Name);v.Parent=trees
  end
 end
end
local start,target
for _,x in ipairs({-100,-60,-20}) do
 for _,z in ipairs({-155,-125,-95}) do
  local ground=workspace:Raycast(Vector3.new(x,450,z),Vector3.new(0,-450,0))
  local finish=workspace:Raycast(Vector3.new(x,450,z+45),Vector3.new(0,-450,0))
  if ground and finish and ground.Instance.Name=="Grass" and finish.Instance.Name=="Grass" then
   local clear=true
   for step=5,40,5 do
    local h=workspace:Raycast(Vector3.new(x,450,z+step),Vector3.new(0,-450,0))
    if not h or h.Position.Y>ground.Position.Y+(finish.Position.Y-ground.Position.Y)*step/45+1 then clear=false end
   end
   if clear then start=ground.Position;target=finish.Position;break end
  end
 end
 if start then break end
end
start=start or Vector3.new(-100,260,-155);target=target or Vector3.new(-100,250,-110)
p.Character:PivotTo(CFrame.lookAt(start+Vector3.yAxis*3,Vector3.new(target.X,start.Y+3,target.Z)))
p:SetAttribute("ReferenceQATarget",target)
script:GetAttributeChangedSignal("Fourth"):Connect(function()
 Loadout.remove(p,"VioletTempest");Loadout.add(p,"RiftMaelstrom")
end)
script:GetAttributeChangedSignal("First"):Connect(function()
 Loadout.remove(p,"RiftMaelstrom");Loadout.add(p,"VioletTempest")
end)
script:GetAttributeChangedSignal("Cancel"):Connect(function() require(SSS.AbilityService).cancelAll(p) end)
script:GetAttributeChangedSignal("Restore"):Connect(function()
 require(SSS.AbilityService).cancelAll(p)
 Loadout.clear(p)
 for _,name in ipairs(game.HttpService:JSONDecode(script:GetAttribute("Original"))) do Loadout.add(p,name) end
 Combat.setInvulnerable(p,false)
 for _,v in ipairs(trees:GetChildren()) do v.Parent=workspace.GeneratedTerrain:FindFirstChild(v:GetAttribute("ReferenceQAParent"));v:SetAttribute("ReferenceQAParent",nil) end
 trees:Destroy();script:SetAttribute("Restored",true)
 p:SetAttribute("ReferenceQATarget",nil)
end)
script:SetAttribute("Ready",true)
