local RunService=game:GetService('RunService')
local ContentProvider=game:GetService('ContentProvider')
local Plan=require(script.Parent.Parent.ElementalPlan)
-- Waited for with a limit: a missing pack is an asset to add, and should say so rather than hang the cast.
local Packs=script.Parent:WaitForChild('ElementalPacks',10) or error('[VFX] Shared.Abilities.VFX.ElementalPacks is missing, so this ability has no effects')
local VFX={}
local preloaded=false
function VFX.preload()
 if preloaded then return end
 preloaded=true
 task.spawn(function()
  local ok,err=pcall(function() ContentProvider:PreloadAsync(Packs:GetDescendants()) end)
  if not ok then warn('[Elemental VFX] Some supplied textures could not load: '..tostring(err)) end
 end)
end
function VFX.duration() return Plan.duration() end
local function carrier(folder,name,position)
 local part=Instance.new('Part')
 part.Name=name;part.Size=Vector3.new(.4,.4,.4)
 part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false
 part.Transparency=1;part.CFrame=CFrame.new(position);part.Parent=folder
 return part
end
local function rig(folder,name,position,at,chargeDuration,frame)
 local root=Packs:FindFirstChild(name):Clone()
 root.CFrame=frame or CFrame.new(position);root.Parent=folder
 local emitters,lights={},{}
 for _,item in ipairs(root:GetDescendants()) do
  if item:IsA('ParticleEmitter') then
   item.Enabled=false
   item.TimeScale=1
   item.Lifetime=NumberRange.new(math.min(item.Lifetime.Min,3),math.min(item.Lifetime.Max,3))
   local delay=math.clamp(item:GetAttribute('EmitDelay') or 0,0,1)
   local duration=if chargeDuration then chargeDuration else math.clamp(item:GetAttribute('EmitDuration') or 0,0,.5)
   local count=math.clamp(item:GetAttribute('EmitCount') or 5,1,80)
   item.Rate=math.min(item.Rate,80)
   table.insert(emitters,{item=item,delay=delay,duration=duration,count=count,fired=false})
  elseif item:IsA('PointLight') then
   item.Enabled=false;table.insert(lights,item)
  end
 end
 return function(elapsed)
  local age=elapsed-at
  for _,entry in ipairs(emitters) do
   local activeAge=age-entry.delay
   if not entry.fired and activeAge>=0 then
    entry.fired=true
    -- Avoid replaying an old flash when a delayed packet arrives.
    if activeAge<.25 then entry.item:Emit(entry.count) end
   end
   entry.item.Enabled=activeAge>=0 and activeAge<entry.duration
  end
  for _,light in ipairs(lights) do light.Enabled=age>=0 and age<(chargeDuration or .2) end
 end
end
local function projectile(folder,payload)
 local wind=payload.kind=='Windburst'
 local orb=carrier(folder,'ElementalProjectile',payload.start)
 orb.Shape=Enum.PartType.Ball;orb.Size=Vector3.new(1.1,1.1,1.1)
 orb.Material=Enum.Material.Neon;orb.Color=if wind then Color3.fromRGB(220,255,245) else Color3.fromRGB(115,215,255)
 local a=Instance.new('Attachment');a.Position=Vector3.new(0,.45,0);a.Parent=orb
 local b=Instance.new('Attachment');b.Position=Vector3.new(0,-.45,0);b.Parent=orb
 local trail=Instance.new('Trail')
 trail.Attachment0=a;trail.Attachment1=b;trail.FaceCamera=true;trail.Lifetime=.22
 trail.Color=ColorSequence.new(orb.Color);trail.LightEmission=1
 trail.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,1)})
 trail.WidthScale=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)})
 trail.Parent=orb;trail.Enabled=false
 local source=Packs.BurstA:FindFirstChild('Fireflies 2',true)
 local motes=if not wind and source then source:Clone() else nil
 if motes then
  motes.Size=NumberSequence.new(.35);motes.Lifetime=NumberRange.new(.15,.3)
  motes.Speed=NumberRange.new(0,1);motes.Rate=35;motes.Enabled=false;motes.Parent=orb
 end
 return function(elapsed)
  local active=elapsed>=0 and elapsed<payload.impactAt
  local position
  if wind then
   position=payload.start:Lerp(payload.impact,math.clamp(elapsed/payload.impactAt,0,1))
  else
   local t=math.min(math.max(0,elapsed/payload.travel),payload.stopT)
   position=Plan.bezier(payload.start,payload.control,payload.target,t)
  end
  orb.CFrame=CFrame.new(position)
  orb.Transparency=if active then (if wind then .65 else .05) else 1
  trail.Enabled=active
  if motes then motes.Enabled=active end
 end
end
local function lightningBolt(folder,payload)
 local root=carrier(folder,'LightningBolt',payload.impact)
 local random=Random.new(payload.seed or 517)
 local points={}
 for i=0,14 do
  local attachment=Instance.new('Attachment')
  local jitter=if i==0 or i==14 then Vector3.zero else Vector3.new(random:NextNumber(-4,4),0,random:NextNumber(-4,4))
  attachment.Position=Vector3.new(0,60*(1-i/14),0)+jitter
  attachment.Parent=root;table.insert(points,attachment)
 end
 local beams={}
 for i=1,#points-1 do
  for layer=1,2 do
   local beam=Instance.new('Beam')
   beam.Attachment0=points[i];beam.Attachment1=points[i+1]
   beam.Width0=if layer==1 then 2.3 else .55;beam.Width1=beam.Width0
   beam.Color=ColorSequence.new(if layer==1 then Color3.fromRGB(35,85,255) else Color3.fromRGB(210,240,255))
   beam.FaceCamera=true;beam.LightEmission=1;beam.Segments=1;beam.Enabled=false;beam.Parent=root
   table.insert(beams,beam)
  end
 end
 return function(elapsed)
  local age=elapsed-payload.impactAt
  local visible=age>=0 and age<.42 and (age<.08 or math.floor(age*45)%3~=0)
  for _,beam in ipairs(beams) do
   beam.Enabled=visible
   beam.Transparency=NumberSequence.new(math.clamp(age/.42,0,1))
  end
 end
end
function VFX.play(payload,scope)
 if not Plan.Tuning[payload.kind] or typeof(payload.impact)~='Vector3' or type(payload.startedAt)~='number' then return false end
 if workspace:GetServerTimeNow()-payload.startedAt>=Plan.duration() then return false end
 VFX.preload()
 local folder=scope:add(Instance.new('Folder'));folder.Name=payload.kind..'VFX';folder.Parent=workspace
 local updates={}
 if payload.kind=='LightningStrike' then
  table.insert(updates,rig(folder,'LightningCharge',payload.impact,0,payload.impactAt))
  table.insert(updates,rig(folder,'LightningImpact',payload.impact,payload.impactAt))
  table.insert(updates,lightningBolt(folder,payload))
 elseif payload.kind=='ArcBurst' then
  table.insert(updates,projectile(folder,payload))
  table.insert(updates,rig(folder,'BurstA',payload.impact,payload.impactAt))
  table.insert(updates,rig(folder,'BurstB',payload.impact,payload.impactAt+.055))
 else
  -- This pack emits along local Front (-Z), so LookAt follows the aim in 3D.
  local up=if math.abs(payload.direction.Y)>.99 then Vector3.new(1,0,0) else Vector3.new(0,1,0)
  local frame=CFrame.lookAt(payload.impact,payload.impact+payload.direction,up)
  table.insert(updates,rig(folder,'Windburst',payload.impact,payload.impactAt,nil,frame))
 end
 local function update()
  local elapsed=workspace:GetServerTimeNow()-payload.startedAt
  if elapsed>=Plan.duration() then scope:destroy();return end
  for _,callback in ipairs(updates) do callback(elapsed) end
 end
 update()
 if not scope:isDead() then scope:add(RunService.Heartbeat:Connect(update)) end
 return true
end
return VFX
