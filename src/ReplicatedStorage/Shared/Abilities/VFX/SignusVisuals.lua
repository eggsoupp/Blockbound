-- Client-only rendering of authoritative Signus carriers.
local Collection=game:GetService("CollectionService")
local Run=game:GetService("RunService")
local Scope=require(script.Parent.Parent.AbilityScope)
local Choreo=require(script.Parent.SignusChoreography)
local VFX=require(script.Parent.SignusVFX)
local Visuals={}
local entries={}
local started=false
local function build(part,entry)
 if entry.scope then entry.scope:destroy() end
 entry.scope=Scope.new()
 entry.kind=part:GetAttribute("SignusKind")
 entry.phase=part:GetAttribute("Phase") or 1
 local ok,update=pcall(Choreo.mount,part,entry.scope)
 if ok then entry.update=update else
  warn("[SignusVisuals] "..tostring(update));entry.scope:destroy();entry.update=nil
 end
end
local function remove(part)
 local entry=entries[part];if not entry then return end
 entries[part]=nil
 if entry.scope then entry.scope:destroy() end
 if entry.pending then entry.pending:Disconnect() end
 if entry.kind=="Aura" then
  local another=false
  for p,e in entries do if e.kind=="Aura" and p:IsDescendantOf(workspace) then another=true break end end
  if not another then VFX.cancelBursts() end
 end
end
local function observe(part)
 if entries[part] or not part:IsA("BasePart") then return end
 local entry={};entries[part]=entry
 if part:IsDescendantOf(workspace) then build(part,entry) else
  entry.pending=part.AncestryChanged:Connect(function()
   if part:IsDescendantOf(workspace) then entry.pending:Disconnect();entry.pending=nil;build(part,entry) end
  end)
 end
end
function Visuals.start()
 if started then return end;started=true
 VFX.preload()
 -- The body (clips, aura, eyes) and the eclipse sky.
 require(script.Parent.SignusRig).start()
 require(script.Parent.SignusSky).start()
 Collection:GetInstanceAddedSignal("SignusVisual"):Connect(observe)
 Collection:GetInstanceRemovedSignal("SignusVisual"):Connect(remove)
 for _,p in Collection:GetTagged("SignusVisual") do observe(p) end
 Run.Heartbeat:Connect(function()
  local camera=workspace.CurrentCamera
  for part,e in entries do
   if not part:IsDescendantOf(workspace) then if e.scope then remove(part) end continue end
   if e.kind~=part:GetAttribute("SignusKind") or e.phase~=(part:GetAttribute("Phase") or 1) then build(part,e) end
   if e.update then
    local ok,err=pcall(e.update,camera and (camera.CFrame.Position-part.Position).Magnitude<350)
    if not ok then warn("[SignusVisuals] "..tostring(err));e.scope:destroy();e.update=nil end
   end
  end
 end)
end
return Visuals

