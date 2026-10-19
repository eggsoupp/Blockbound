-- Local rendering of replicated, invisible Signus carriers.
-- Tags also discover aura/eclipse/telegraphs when joining or streaming in mid-fight.
local Collection=game:GetService("CollectionService")
local Run=game:GetService("RunService")
local Scope=require(script.Parent.Parent.AbilityScope)
local FX=require(script.Parent.SignusFX)
local Choreo=require(script.Parent.SignusChoreography)
local C=FX.Colors
local Visuals={}
local entries={}
local started=false
local function sequence(a,b) return NumberSequence.new(a,b or a) end

local function build(part,entry)
 if entry.scope then entry.scope:destroy() end
 local scope=Scope.new();entry.scope=scope;entry.particles={};entry.beams={};entry.custom=nil
 entry.kind=part:GetAttribute("SignusKind");entry.phase=part:GetAttribute("Phase") or 1
 if entry.kind=="SpiralCast" or entry.kind=="LanceCast" or entry.kind=="RiftBeam" or entry.kind=="Ascension" or entry.kind=="Aura" then
  entry.custom=Choreo.mount(part,scope);return
 end
 local root=scope:add(FX.attachment(part));root.Name="SignusLocalVFX"
 local function layer(kind,scale,props,attachment)
  local e=FX.emitter(kind,attachment or root,props)
  e.Enabled=true
  table.insert(entry.particles,{e=e,scale=scale,opacity=props.Transparency or sequence(.1,1),rate=e.Rate})
  return e
 end
 local function plane(kind,scale,color,opacity,facing)
  return layer(kind,scale,{
   Enabled=true,Rate=10,Lifetime=NumberRange.new(.22),Speed=NumberRange.new(.001),
   EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.zero,LockedToPart=true,
   Orientation=facing or Enum.ParticleOrientation.VelocityPerpendicular,
   Color=ColorSequence.new(color),LightEmission=.65,Brightness=1,
   Rotation=NumberRange.new(0),RotSpeed=NumberRange.new(0),
   Transparency=sequence(opacity,opacity),Size=sequence(1),
  })
 end
 local kind=entry.kind
 if kind=="Ring" or kind=="Sigil" then
  plane("PressureRing",1,C.pearl,.15)
  if kind=="Sigil" then
   local rune=plane("WarningRing",.9,C.orchid,.25);rune.RotSpeed=NumberRange.new(18)
   plane("PressureRing",.65,C.violet,.2)
  end
 elseif kind=="Disc" then
  root.CFrame=CFrame.Angles(0,-math.pi/2,0) -- cylinder's old local X normal
  plane("WarningRing",1,C.violet,.5)
 elseif kind=="Crescent" then
  plane("Crescent",1.25,C.pearl,.05,Enum.ParticleOrientation.FacingCamera)
  local slash=plane("Slash",1.5,C.orchid,.2,Enum.ParticleOrientation.FacingCamera)
  slash.Lifetime=NumberRange.new(.35);slash.Rate=6;slash.Rotation=NumberRange.new(-20)
  layer("Embers",.06,{Rate=22,Lifetime=NumberRange.new(.2,.4),Speed=NumberRange.new(1,6),Color=ColorSequence.new(C.pearl,C.violet),Size=sequence(.4,0),LightEmission=1,Transparency=sequence(0,1)})
 elseif kind=="Mark" then
  root.CFrame=CFrame.Angles(math.pi/2,0,0)
  plane("Crack",1.15,C.orchid,.12)
  plane("PressureRing",1,C.violet,.5)
 elseif kind=="Pillar" or kind=="Seam" or kind=="Spoke" then
  local beam,a,b=FX.beam(root,Vector3.zero,Vector3.yAxis,1,C.orchid)
  table.insert(entry.beams,{beam=beam,a=a,b=b,kind=kind})
  local core,a2,b2=FX.beam(root,Vector3.zero,Vector3.yAxis,.3,C.pearl,FX.Pack.Lightning.Texture)
  table.insert(entry.beams,{beam=core,a=a2,b=b2,kind=kind,core=true})
 elseif kind=="Eclipse" or kind=="Void" then
  local face=Enum.ParticleOrientation.FacingCamera
  local corona=plane("Aura",1.28,C.orchid,.15,face);corona.RotSpeed=NumberRange.new(12)
  local rim=plane("Core",.93,C.pearl,.05,face);rim.LightEmission=1;rim.Brightness=2;rim.ZOffset=-.1
  local disc=plane("Core",.88,C.black,0,face);disc.LightEmission=0;disc.LightInfluence=0;disc.ZOffset=.6
  if kind=="Eclipse" then
   local tendrils=plane("Swirl",1.6,C.violet,.3,face);tendrils.RotSpeed=NumberRange.new(-12);tendrils.ZOffset=-.4
   layer("Star",.035,{Rate=8,Lifetime=NumberRange.new(1,2),Speed=NumberRange.new(3,7),SpreadAngle=Vector2.new(180,180),Color=ColorSequence.new(C.pearl,C.violet),LightEmission=1,Transparency=sequence(.1,1),Size=sequence(1,0)})
  end
 elseif kind=="Aura" then
  local phase=entry.phase;local scale=if phase==2 then 1.18 else 1
  local hem=FX.attachment(root,CFrame.new(0,-5,0)*CFrame.Angles(math.pi/2,0,0))
  plane("PressureRing",.9*scale,C.orchid,.5,Enum.ParticleOrientation.VelocityPerpendicular).Parent=hem
  local swirl=plane("Swirl",1.2*scale,C.violet,.7,Enum.ParticleOrientation.VelocityPerpendicular)
  swirl.Parent=hem;swirl.RotSpeed=NumberRange.new(24)
  -- Wisps flank the robe; the hood and casting hands stay readable.
  for _,side in ipairs({-1,1}) do
   local a=FX.attachment(root,CFrame.new(side*4,-3,1))
   layer("DarkFire",.46*scale,{Rate=if phase==2 then 13 else 8,Lifetime=NumberRange.new(.7,1.1),Speed=NumberRange.new(2,4),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(12,12),Color=ColorSequence.new(C.violet,C.plum),LightEmission=.4,Brightness=.8,Transparency=sequence(.45,1),Rotation=NumberRange.new(-10,10),Size=sequence(6,9)},a)
   layer("Embers",.025,{Rate=if phase==2 then 14 else 7,Lifetime=NumberRange.new(.7,1.2),Speed=NumberRange.new(4,8),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(20,20),Color=ColorSequence.new(C.pearl,C.orchid),LightEmission=1,Transparency=sequence(.1,1),Size=sequence(.3,0)},a)
  end
  if phase==2 then
   local halo=FX.attachment(root,CFrame.new(0,6,1.5))
   plane("WarningRing",.65,C.orchid,.25,Enum.ParticleOrientation.FacingCamera).Parent=halo
   layer("Star",.04,{Rate=4,Lifetime=NumberRange.new(.7,1.2),Speed=NumberRange.new(2,5),SpreadAngle=Vector2.new(180,180),Color=ColorSequence.new(C.gold,C.teal),LightEmission=1,Transparency=sequence(.3,1),Size=sequence(.6,0)},halo)
  end
 elseif kind=="Halo" then
  layer("Rock",.6,{Rate=7,Lifetime=NumberRange.new(.3),Speed=NumberRange.new(.001),LockedToPart=true,Color=ColorSequence.new(C.plum,C.violet),LightEmission=.2,Transparency=sequence(.15,.5),Size=sequence(2.5,1)})
  layer("Flame",1.1,{Rate=10,Lifetime=NumberRange.new(.3,.6),Speed=NumberRange.new(1,2),Color=ColorSequence.new(C.orchid,C.violet),LightEmission=.8,Transparency=sequence(.35,1),Size=sequence(3,1)})
 elseif kind=="Shard" then
  plane("Star",1.4,C.pearl,.08,Enum.ParticleOrientation.FacingCamera)
  layer("Flame",1.1,{Rate=36,Lifetime=NumberRange.new(.3,.6),Speed=NumberRange.new(3,8),Color=ColorSequence.new(C.pearl,C.violet),LightEmission=.8,Transparency=sequence(.2,1),Size=sequence(5,1)})
 else -- charge and the bright eyes
  plane("Flash",if kind=="Eyes" then 2 else 2.5,C.pearl,.2,Enum.ParticleOrientation.FacingCamera)
  layer("DarkFire",2.4,{Rate=14,Lifetime=NumberRange.new(.3,.5),Speed=NumberRange.new(.1),LockedToPart=true,Color=ColorSequence.new(C.orchid,C.violet),LightEmission=.7,Transparency=sequence(.3,1),Size=sequence(3,1)})
 end
end

local function remove(part)
 local entry=entries[part]
 if not entry then return end
 entries[part]=nil
 if entry.scope then entry.scope:destroy() end
 if entry.pending then entry.pending:Disconnect() end
end
local function observe(part)
 if entries[part] or not part:IsA("BasePart") then return end
 local entry={};entries[part]=entry
 if part:IsDescendantOf(workspace) then build(part,entry)
 else
  entry.pending=part.AncestryChanged:Connect(function()
   if part:IsDescendantOf(workspace) then entry.pending:Disconnect();entry.pending=nil;build(part,entry) end
  end)
 end
end
function Visuals.start()
 if started then return end;started=true
 FX.preload()
 Collection:GetInstanceAddedSignal("SignusVisual"):Connect(observe)
 Collection:GetInstanceRemovedSignal("SignusVisual"):Connect(remove)
 for _,part in ipairs(Collection:GetTagged("SignusVisual")) do observe(part) end
 local accumulator=0
 Run.Heartbeat:Connect(function(dt)
  accumulator+=dt;if accumulator<1/30 then return end;accumulator=0
  local camera=workspace.CurrentCamera
  for part,entry in pairs(entries) do
   if not part:IsDescendantOf(workspace) then
    if entry.scope then remove(part) end
    continue
   end
   if not entry.scope then continue end
   if entry.kind~=part:GetAttribute("SignusKind") or entry.phase~=(part:GetAttribute("Phase") or 1) then build(part,entry) end
   local near=camera and (camera.CFrame.Position-part.Position).Magnitude<420
   if entry.custom then
    if near then entry.custom()
    elseif entry.near~=false then
     for _,v in ipairs(part:GetDescendants()) do
      if v:IsA("ParticleEmitter") or v:IsA("Beam") then v.Enabled=false end
     end
    end
    entry.near=near;continue
   end
   local alpha=part:FindFirstChild("FXOpacity")
   local opacity=if alpha then math.clamp(alpha.Value,0,1) else 1
   local extent=math.max(part.Size.X,part.Size.Y,part.Size.Z)
   if entry.kind=="Aura" then extent=14 elseif entry.kind=="Shard" then extent=5 end
   for _,layer in ipairs(entry.particles) do
    local e=layer.e;e.Enabled=near and opacity>.01
    local size=math.clamp(extent*layer.scale,.05,160)
    if not layer.lastSize or math.abs(size-layer.lastSize)>.03 then
     e.Size=sequence(size);layer.lastSize=size
    end
    local rounded=math.floor(opacity*64+.5)/64
    if layer.lastOpacity~=rounded then
     local keys={}
     for _,k in ipairs(layer.opacity.Keypoints) do table.insert(keys,NumberSequenceKeypoint.new(k.Time,1-(1-k.Value)*rounded,k.Envelope*rounded)) end
     e.Transparency=NumberSequence.new(keys);layer.lastOpacity=rounded
    end
   end
   for _,v in ipairs(entry.beams) do
    local axis=if v.kind=="Pillar" then Vector3.yAxis*part.Size.Y elseif v.kind=="Seam" then Vector3.zAxis*part.Size.Z else Vector3.xAxis*part.Size.X
    v.a.Position=-axis*.5;v.b.Position=axis*.5
    local width=if v.kind=="Pillar" then math.max(1,part.Size.X*2.5) elseif v.kind=="Seam" then .7 else .45
    v.beam.Width0=width*(if v.core then .35 else 1);v.beam.Width1=v.beam.Width0
    v.beam.Transparency=sequence(1-opacity*(if v.core then .9 else .6))
    v.beam.Enabled=near and opacity>.01
   end
  end
 end)
end
return Visuals

