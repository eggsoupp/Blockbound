-- A gathering wind well, electric pulses, then a short ascending column.
-- Uses supplied emitter artwork with a new layout, palette and shared timeline.
local RunService=game:GetService('RunService')
local ContentProvider=game:GetService('ContentProvider')
local Plan=require(script.Parent.Parent.StormWellPlan)
local Packs=script.Parent:WaitForChild('ElementalPacks')
local BeamPacks=script.Parent:WaitForChild('AnnihilationPacks')
local VFX={}
local loaded=false
local teal=Color3.fromRGB(75,220,215)
local white=Color3.fromRGB(225,255,245)
function VFX.duration() return Plan.duration() end
function VFX.preload()
 if loaded then return end;loaded=true
 task.spawn(function()
  local ok,err=pcall(function() ContentProvider:PreloadAsync({Packs,BeamPacks}) end)
  if not ok then warn('[Storm Well] Asset preload: '..tostring(err)) end
 end)
end
local function carrier(folder,name,position)
 local part=Instance.new('Part');part.Name=name;part.Size=Vector3.new(.2,.2,.2)
 part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false
 part.Transparency=1;part.CFrame=CFrame.new(position);part.Parent=folder
 return part
end
function VFX.play(payload,scope)
 if typeof(payload.origin)~='CFrame' or type(payload.startedAt)~='number' then return false end
 if workspace:GetServerTimeNow()-payload.startedAt>=Plan.duration() then return false end
 VFX.preload()
 local folder=scope:add(Instance.new('Folder'));folder.Name='StormWellVFX';folder.Parent=workspace
 local centre=payload.origin.Position
 local states={}
 local nodes={}
 local function group(template,at,stop,radius,height,scale,continuous)
  local root=carrier(folder,'Storm_'..template.Name,centre)
  local count=0
  for _,source in ipairs(template:GetDescendants()) do
   if not source:IsA('ParticleEmitter') then continue end
   if string.find(string.lower(source.Name),'star',1,true) then continue end
   count+=1;if count>8 then break end
   local attachment=Instance.new('Attachment');attachment.Parent=root
   local angle=count*math.pi/4
   attachment.Position=Vector3.new(math.cos(angle)*radius,height,math.sin(angle)*radius)
   local emitter=source:Clone();emitter.Enabled=false;emitter.Parent=attachment
   emitter.Color=ColorSequence.new(if count%3==0 then white else teal)
   emitter.TimeScale=1;emitter.ZOffset=0;emitter.Acceleration=Vector3.zero
   emitter.Lifetime=NumberRange.new(math.min(emitter.Lifetime.Min,1.2),math.min(emitter.Lifetime.Max,1.6))
   emitter.Speed=NumberRange.new(math.min(emitter.Speed.Min,8),math.min(emitter.Speed.Max,14))
   emitter.Rate=math.min(math.max(emitter.Rate,6),18)
   local keys={}
   for _,key in ipairs(emitter.Size.Keypoints) do
    table.insert(keys,NumberSequenceKeypoint.new(key.Time,math.min(key.Value*scale,24),math.min(key.Envelope*scale,3)))
   end
   emitter.Size=NumberSequence.new(keys)
   table.insert(states,{item=emitter,at=at+math.clamp(source:GetAttribute('EmitDelay') or 0,0,.15),stop=stop,
    count=math.clamp(source:GetAttribute('EmitCount') or 6,1,24),continuous=continuous,fired=false})
  end
  table.insert(nodes,root)
 end
 group(Packs.Windburst,.08,2.65,6,.3,.45,true)
 group(BeamPacks.Constellation,.25,2.7,4,2,.35,true)
 group(BeamPacks.ElectricCharge,.45,2.7,3,3,.4,true)
 group(Packs.LightningCharge,.6,2.65,7,1,.5,true)
 group(BeamPacks.Halftone,Plan.Release,3.35,0,.4,.55,false)
 group(BeamPacks.LaserFire,Plan.Release,3.4,0,20,.3,true)
 group(BeamPacks.BeamImpact,Plan.Release,3.4,0,1,.5,true)
 group(BeamPacks.Explode,Plan.Release,3.1,0,.4,.5,false)
 group(Packs.BurstA,Plan.Release,3.1,0,.3,.65,false)
 group(Packs.BurstB,Plan.Release+.1,3.2,0,.3,.65,false)
 group(Packs.AstralImpact,Plan.Release+.08,3.2,0,.4,.45,false)
 for _,at in ipairs(Plan.Hits) do group(Packs.LightningImpact,at,at+.15,0,.5,.25,false) end
 local beamRoot=carrier(folder,'WellColumn',centre)
 local bottom=Instance.new('Attachment');bottom.Position=Vector3.new(0,.5,0);bottom.Parent=beamRoot
 local top=Instance.new('Attachment');top.Position=Vector3.new(0,.5,0);top.Parent=beamRoot
 local beams={}
 for _,template in ipairs({BeamPacks.BeamImpact,BeamPacks.LaserFire}) do
  for _,source in ipairs(template:GetDescendants()) do
   if source:IsA('Beam') then
    local beam=source:Clone();beam.Attachment0=bottom;beam.Attachment1=top
    beam.CurveSize0=0;beam.CurveSize1=0;beam.Width0=5;beam.Width1=3
    beam.Color=ColorSequence.new(teal);beam.LightEmission=1;beam.FaceCamera=true
    beam.Enabled=false;beam.Parent=beamRoot;table.insert(beams,beam)
   end
  end
 end
 -- A narrow luminous core ensures the upward strike remains readable.
 local core=Instance.new('Beam');core.Attachment0=bottom;core.Attachment1=top
 core.Width0=1.4;core.Width1=.8;core.Color=ColorSequence.new(white)
 core.FaceCamera=true;core.LightEmission=1;core.Enabled=false;core.Parent=beamRoot;table.insert(beams,core)
 local function update()
  local elapsed=workspace:GetServerTimeNow()-payload.startedAt
  if elapsed>=Plan.duration() then scope:destroy();return end
  for i,root in ipairs(nodes) do
   root.CFrame=payload.origin*CFrame.Angles(0,elapsed*(if i%2==0 then -.8 else 1.1),0)
  end
  for _,entry in ipairs(states) do
   if not entry.fired and elapsed>=entry.at then
    entry.fired=true
    if elapsed-entry.at<.2 then entry.item:Emit(entry.count) end
   end
   entry.item.Enabled=entry.continuous and elapsed>=entry.at and elapsed<entry.stop
  end
  local age=elapsed-Plan.Release
  local travel=math.clamp(age/.18,0,1)
  top.Position=Vector3.new(0,.5+42*travel,0)
  for _,beam in ipairs(beams) do
   beam.Enabled=age>=0 and age<.65
   beam.Transparency=NumberSequence.new(math.clamp((age-.25)/.4,0,1))
  end
 end
 update()
 if not scope:isDead() then scope:add(RunService.Heartbeat:Connect(update)) end
 return true
end
return VFX
