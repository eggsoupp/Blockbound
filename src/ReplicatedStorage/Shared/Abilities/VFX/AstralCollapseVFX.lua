local RunService=game:GetService('RunService')
local ContentProvider=game:GetService('ContentProvider')
local Plan=require(script.Parent.Parent.AstralCollapsePlan)
local Packs=script.Parent:WaitForChild('ElementalPacks')
local VFX={}
local violet=Color3.fromRGB(168,80,255)
local cyan=Color3.fromRGB(100,235,255)
local loaded=false
function VFX.preload()
 if loaded then return end;loaded=true
 task.spawn(function()
  local ok,err=pcall(function() ContentProvider:PreloadAsync({Packs.AstralImpact,Packs.AstralShard}) end)
  if not ok then warn('[Astral Collapse] Asset preload: '..tostring(err)) end
 end)
end
function VFX.duration() return Plan.duration() end
local function carrier(folder,name,position)
 local part=Instance.new('Part');part.Name=name
 part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false
 part.Size=Vector3.new(.1,.1,.1);part.Transparency=1;part.CFrame=CFrame.new(position);part.Parent=folder
 return part
end
function VFX.play(payload,scope)
 if typeof(payload.origin)~='CFrame' or type(payload.startedAt)~='number' then return false end
 if workspace:GetServerTimeNow()-payload.startedAt>=Plan.duration() then return false end
 VFX.preload()
 local folder=scope:add(Instance.new('Folder'));folder.Name='AstralCollapseVFX';folder.Parent=workspace
 local centre=payload.origin.Position
 local hub=carrier(folder,'CollapseCore',centre+Vector3.new(0,3,0))
 hub.Shape=Enum.PartType.Ball;hub.Material=Enum.Material.Neon;hub.Color=cyan
 local hubAttachment=Instance.new('Attachment');hubAttachment.Parent=hub
 local shards={}
 for i=1,Plan.Count do
  local shard=Packs.AstralShard:Clone();shard.Name='OrbitShard'..i
  shard.Color=if i%2==0 then cyan else violet;shard.Material=Enum.Material.Neon;shard.TextureID=''
  shard.Size=Vector3.new(.7,5,.7);shard.Parent=folder
  local a=Instance.new('Attachment');a.Position=Vector3.new(0,2,0);a.Parent=shard
  local b=Instance.new('Attachment');b.Position=Vector3.new(0,-2,0);b.Parent=shard
  local beam=Instance.new('Beam');beam.Attachment0=a;beam.Attachment1=hubAttachment
  beam.Width0=.1;beam.Width1=.35;beam.FaceCamera=true;beam.LightEmission=1;beam.Enabled=false
  beam.Color=ColorSequence.new(shard.Color);beam.Parent=shard
  local sparks=Packs.AstralImpact:FindFirstChild('Sparkle',true):Clone()
  sparks.Color=ColorSequence.new(shard.Color)
  sparks.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.28),NumberSequenceKeypoint.new(1,0)})
  sparks.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(1,1)})
  sparks.Lifetime=NumberRange.new(.12,.22);sparks.Speed=NumberRange.new(.2,.8)
  sparks.Rate=22;sparks.Enabled=false;sparks.Parent=b
  table.insert(shards,{part=shard,beam=beam,sparks=sparks})
 end
 local bursts={}
 for index,at in ipairs(Plan.Hits) do
  local root=Packs.AstralImpact:Clone();root.Name='CollapsePulse'..index
  root.CFrame=CFrame.new(centre+Vector3.new(0,.2,0));root.Parent=folder
  for _,item in ipairs(root:GetDescendants()) do
   if item:IsA('ParticleEmitter') then
    item.Enabled=false;item.TimeScale=1
    item.Color=ColorSequence.new(if index==2 then cyan else violet)
    item.Lifetime=NumberRange.new(math.min(item.Lifetime.Min,1.8),math.min(item.Lifetime.Max,1.8))
    local keys={}
    for _,key in ipairs(item.Size.Keypoints) do
     table.insert(keys,NumberSequenceKeypoint.new(key.Time,math.min(key.Value*(.45+index*.12),26),math.min(key.Envelope*.4,3)))
    end
    item.Size=NumberSequence.new(keys)
    table.insert(bursts,{item=item,at=at+math.clamp(item:GetAttribute('EmitDelay') or 0,0,.25),
     count=math.clamp(item:GetAttribute('EmitCount') or 8,1,36),fired=false})
   end
  end
 end
 local function update()
  local elapsed=workspace:GetServerTimeNow()-payload.startedAt
  if elapsed>=Plan.duration() then scope:destroy();return end
  for i,entry in ipairs(shards) do
   local offset,opacity=Plan.shard(i,elapsed)
   local position=centre+offset
   entry.part.CFrame=CFrame.lookAt(position,hub.Position+Vector3.new(0,.01,0))*CFrame.Angles(math.pi/2,0,elapsed*2)
   entry.part.Size=Vector3.new(.7,5,.7)*math.max(opacity,.001)
   entry.part.Transparency=1-opacity
   entry.beam.Enabled=opacity>.05;entry.sparks.Enabled=opacity>.05
  end
  local pulse=0
  for _,at in ipairs(Plan.Hits) do if elapsed>=at then pulse+=math.exp(-(elapsed-at)*9) end end
  local charge=math.clamp(elapsed/1.9,0,1)
  local size=if elapsed<1.9 then .4+charge*2.2 else 2+pulse*12
  hub.Size=Vector3.new(size,size,size)
  hub.Transparency=if elapsed<1.9 then .4 else 1-math.min(pulse,.8)
  for _,burst in ipairs(bursts) do
   if not burst.fired and elapsed>=burst.at then
    burst.fired=true
    if elapsed-burst.at<.25 then burst.item:Emit(burst.count) end
   end
  end
 end
 update()
 if not scope:isDead() then scope:add(RunService.Heartbeat:Connect(update)) end
 return true
end
return VFX
