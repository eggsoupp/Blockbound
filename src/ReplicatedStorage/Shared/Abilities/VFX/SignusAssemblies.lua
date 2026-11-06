-- Complete SoulShroud assemblies; the explosion path retains authored particle settings.
local RS=game:GetService("ReplicatedStorage")
local Content=game:GetService("ContentProvider")
local Run=game:GetService("RunService")
local Library=RS:WaitForChild("SignusLibrary")
-- Phase two's additions: the aura colourways, the black and blood bursts, the
-- impact rings, the eye flare and the eclipse (see its sources.json).
local Eclipse=RS:WaitForChild("SignusEclipseLibrary")
local A={}
local violet=Color3.fromRGB(145,38,245)
local orchid=Color3.fromRGB(206,90,255)
local pearl=Color3.fromRGB(243,215,255)
-- A palette recolours an assembly: `main` for its body, `hot` for its
-- brightest layers. Phase one is the violet herald; phase two is a darker,
-- deeper purple.
A.Violet={main=violet,hot=pearl,edge=orchid}
A.Dusk={main=Color3.fromRGB(84,14,165),hot=Color3.fromRGB(205,160,255),edge=Color3.fromRGB(140,46,250)}
local function template(name)
 return Library:FindFirstChild(name) or Eclipse:FindFirstChild(name)
end
local counts={Storm=42,Column=28,Orb=28,Impact=0,Slash=0,Swirl=0,LungeBlade=38,LungeWake=90,LungeImpact=0}
local active=0
local folder
local function world()
 if not folder or not folder.Parent then folder=Instance.new("Folder");folder.Name="SignusCosmetics";folder.Parent=workspace end
 return folder
end
local function nsScale(seq,alpha)
 local keys={}
 for _,k in seq.Keypoints do table.insert(keys,NumberSequenceKeypoint.new(k.Time,1-(1-k.Value)*alpha,k.Envelope*alpha)) end
 return NumberSequence.new(keys)
end
function A.preload()
 task.spawn(function()pcall(function()Content:PreloadAsync(Library:GetChildren())end)end)
end
function A.mount(scope,name,cf,scale,heightScale,palette)
 local blank={set=function()end,burst=function()end}
 if active>=32 then return blank end
 palette=palette or A.Violet
 local source=template(name)
 if not source then warn("[Signus] Missing assembly "..name) return blank end
 local model=scope:add(source:Clone())
 model.Name="Signus_"..name
 model:ScaleTo(math.clamp(scale or 1,.015,6))
 model:PivotTo(cf)
 local emitters,beams,meshes={}, {}, {}
 local sum=0
 for _,v in model:GetDescendants() do if v:IsA("ParticleEmitter") then sum+=v.Rate end end
 local factor=math.min(1,(counts[name] or 20)/math.max(sum,1))
 for _,v in model:GetDescendants() do
  if v:IsA("BasePart") then
   v.Anchored=true;v.CanCollide=false;v.CanTouch=false;v.CanQuery=false;v.CastShadow=false
   if v:IsA("MeshPart") then
    if name=="LungeBlade" then v.DoubleSided=true end
    if name=="Swirl" and heightScale then v.Size=Vector3.new(v.Size.X,v.Size.Y*heightScale,v.Size.Z) end
    v.Material=Enum.Material.Neon
    v.Color=if v.Name=="Inner" then palette.hot else palette.main
    -- Solid bodies: a pack mesh reads as a shape, not a tint.
    table.insert(meshes,{v=v,opacity=if name=="LungeBlade" then .95 elseif name=="Swirl" then .72 elseif name=="Slash" then .95 else .8})
   else v.Transparency=1 end
  elseif v:IsA("ParticleEmitter") then
   local keys={}
   for _,k in v.Color.Keypoints do
    local c=k.Value
    local lum=math.max(c.R,c.G,c.B)
    -- Bright source layers take the edge colour, the rest the body. Additive
    -- white washes out in daylight; saturated colour over the dark layers
    -- and solid meshes is what keeps the contrast.
    local color=if lum>=.92 then palette.edge:Lerp(palette.hot,.25) elseif lum>=.55 then palette.edge else palette.main
    table.insert(keys,ColorSequenceKeypoint.new(k.Time,color))
   end
   v.Color=ColorSequence.new(keys)
   -- These energy textures composite additively. Keep the black backing invisible;
   -- use emission/count/alpha for restraint instead of exposing the backing.
   v.LightEmission=1;v.LightInfluence=0;v.Brightness=math.min(v.Brightness,1.4)
   v.Enabled=false
   v.Lifetime=NumberRange.new(math.min(v.Lifetime.Min,1.2),math.min(v.Lifetime.Max,1.5))
   local rate=v.Rate*factor
   table.insert(emitters,{v=v,rate=rate,alpha=v.Transparency,burst=math.clamp(math.floor(v.Rate*.055+.5),1,14)})
   v.Rate=0
  elseif v:IsA("Beam") then
   -- Keep the source's dark beam cores and alpha masks; flattening all layers
   -- into additive light erases the column's authored silhouette.
   v.Color=if v.LightEmission==0 then ColorSequence.new(Color3.fromRGB(40,8,65)) else ColorSequence.new(palette.edge,palette.main)
   v.LightInfluence=0;v.Brightness=math.min(v.Brightness,1.2)
   table.insert(beams,{v=v,alpha=v.Transparency})
   v.Enabled=false
  elseif v:IsA("Trail") then v.Enabled=false
  elseif v:IsA("PointLight") then v.Enabled=false
  elseif v:IsA("SurfaceAppearance") then pcall(function()v.Color=violet end)
  elseif v:IsA("LuaSourceContainer") then v:Destroy()
  end
 end
 model.Parent=world()
 active+=1
 local dead=false
 scope:add(function()if not dead then dead=true;active-=1 end end)
 local result={model=model}
 local lastAlpha=-1
 function result:set(frame,alpha,stream)
  if dead or not model.Parent then return end
  if frame then model:PivotTo(frame) end
  alpha=math.clamp(alpha or 1,0,1)
  for _,e in emitters do
   e.v.Enabled=stream==true and alpha>.015
   e.v.Rate=e.rate*alpha
   if math.abs(alpha-lastAlpha)>.025 then e.v.Transparency=nsScale(e.alpha,alpha) end
  end
  for _,b in beams do b.v.Enabled=alpha>.015;if math.abs(alpha-lastAlpha)>.025 then b.v.Transparency=nsScale(b.alpha,alpha) end end
  for _,m in meshes do m.v.Transparency=1-m.opacity*alpha end
  if math.abs(alpha-lastAlpha)>.025 then lastAlpha=alpha end
 end
 function result:burst(strength)
  self:set(nil,math.min(strength or 1,1),false)
  for _,e in emitters do e.v:Emit(math.clamp(math.floor(e.burst*(strength or 1)),1,22)) end
 end
 result:set(cf,0,false)
 return result
end

-- SS3 #64 has several Rate=0 layers intended for Emit(), including its radial
-- flash and long sparks. Do not pass it through the ambient recolor/rate adapter.
function A.explode(scope,cf,scale,strength,grand)
 if active>=32 or scope:isDead() then return 0 end
 local template=Library:FindFirstChild("PurpleExplosion")
 if not template then warn("[Signus] Missing PurpleExplosion assembly");return 0 end
 local model=scope:add(template:Clone())
 model.Name="Signus_PurpleExplosion"
 model:ScaleTo(math.clamp(scale or 1,.15,1.8));model:PivotTo(cf)
 local emitters={}
 local life=0
 strength=math.clamp(strength or 1,.15,1.5)
 for _,v in model:GetDescendants() do
  if v:IsA("BasePart") then
   v.Anchored=true;v.CanCollide=false;v.CanTouch=false;v.CanQuery=false;v.CastShadow=false
   if not v:IsA("MeshPart") then v.Transparency=1 end
  elseif v:IsA("ParticleEmitter") then
   v.Enabled=false
   local count
   if v.Rate==0 then count=if v.Speed.Max>30 then 20 else 1
   elseif v.Speed.Max>30 then count=math.max(5,math.ceil(v.Rate*.22))
   else count=math.clamp(math.ceil(v.Rate*.12),1,4) end
   -- Each authored layer emits once; source color, size/speed curves, alpha,
   -- drag, brightness, flipbooks, attachments and lifetimes stay intact.
   table.insert(emitters,{v=v,count=math.max(1,math.floor(count*strength+.5))})
   life=math.max(life,v.Lifetime.Max)
  elseif v:IsA("LuaSourceContainer") then v:Destroy() end
 end
 model.Parent=world();active+=1
 scope:add(function()active-=1 end)
 for _,e in emitters do e.v:Emit(e.count) end

 if grand then
  local shell=Library:FindFirstChild("GrandExplosion")
  if shell then
   local mesh=scope:add(shell:Clone());mesh.Name="Signus_GrandExplosion"
   local target=math.clamp(scale*.25,.12,.34)
   mesh:ScaleTo(target)
   local origin=cf*CFrame.new(4*target,7*target,0)
   mesh:PivotTo(origin)
   local parts,meshEmitters={},{}
   local windIndex=0
   for _,v in mesh:GetDescendants() do
    if v:IsA("BasePart") then
     v.Anchored=true;v.CanCollide=false;v.CanTouch=false;v.CanQuery=false;v.CastShadow=false
     if v.Name=="Rocks" then v.Transparency=1 -- terrain debris is already physical/server-owned
     else
      if v.Name=="Wind" then windIndex+=1 end
      local color=if v.Name=="Inner" then pearl elseif v.Name=="Inner Purple" then Color3.fromRGB(100,155,255)
       elseif v.Name=="Middle" then orchid else violet
      v.Color=color
      table.insert(parts,{v=v,size=v.Size,frame=origin:ToObjectSpace(v.CFrame),alpha=math.max(v.Transparency,.3),spin=if v.Name=="Wind" then (if windIndex%2==0 then -1 else 1) else .2})
     end
    elseif v:IsA("ParticleEmitter") then v.Enabled=false;table.insert(meshEmitters,v)
    elseif v:IsA("LuaSourceContainer") then v:Destroy() end
   end
   for _,m in parts do
    m.v.Size=m.size*.35
    m.v.CFrame=origin*CFrame.new(m.frame.Position*.35)*m.frame.Rotation
   end
   mesh.Parent=world()
   for _,v in meshEmitters do v:Emit(12) end
   -- Expand the pack's curved meshes from a tight core, then dissolve. No
   -- primitive shockwave parts or screen-facing rectangles are introduced.
   local started=os.clock()
   local connection
   connection=scope:add(Run.Heartbeat:Connect(function()
    local age=os.clock()-started
    if age>=.72 then mesh:Destroy();connection:Disconnect();return end
    local spread=1-math.exp(-age*14)
    local grow=.35+.65*spread
    local fade=math.clamp((age-.08)/.64,0,1)
    for _,m in parts do
     m.v.Transparency=m.alpha+(1-m.alpha)*fade
     m.v.Size=m.size*grow
     m.v.CFrame=origin*CFrame.new(m.frame.Position*grow)*m.frame.Rotation*CFrame.Angles(0,m.spin*age*4,0)
    end
   end))
  end
 end
 return life+.15
end

--[[
	One authored burst from either library, its own colours, curves and
	flipbooks intact: each layer emits once, in proportion to its authored
	rate. `scale` multiplies sizes, speeds and acceleration (part templates
	have no ScaleTo). `tint`, a palette, recolours bright layers by brightness and
	leaves dark ones dark - the same black-and-blood VoidBurst/BloodBurst pair
	can then read as one eruption.
]]
function A.emit(scope,name,cf,scale,strength,tint)
 if scope:isDead() then return 0 end
 local source=template(name)
 if not source then warn("[Signus] Missing assembly "..name);return 0 end
 local copy=scope:add(source:Clone())
 copy.Name="Signus_"..name
 scale=scale or 1;strength=strength or 1
 local life=0
 for _,v in copy:GetDescendants() do
  if v:IsA("BasePart") then
   v.Anchored=true;v.CanCollide=false;v.CanTouch=false;v.CanQuery=false;v.CastShadow=false;v.Transparency=1
  elseif v:IsA("Attachment") then
   v.Position*=scale
  elseif v:IsA("ParticleEmitter") then
   v.Enabled=false;v.LightInfluence=0
   local keys={}
   for _,k in v.Size.Keypoints do table.insert(keys,NumberSequenceKeypoint.new(k.Time,k.Value*scale,k.Envelope*scale)) end
   v.Size=NumberSequence.new(keys)
   v.Speed=NumberRange.new(v.Speed.Min*scale,v.Speed.Max*scale);v.Acceleration*=scale
   if tint then
    -- A palette: each bright keypoint takes the palette by its brightness,
    -- dark keypoints stay dark, so the authored gradient survives.
    local keys={}
    for _,k in v.Color.Keypoints do
     local c=k.Value;local lum=math.max(c.R,c.G,c.B)
     local color=if lum<.25 then c elseif lum>=.9 then tint.edge:Lerp(tint.hot,.35) elseif lum>=.6 then tint.edge else tint.main
     table.insert(keys,ColorSequenceKeypoint.new(k.Time,color))
    end
    v.Color=ColorSequence.new(keys)
   end
   local count=if v.Rate<=0 then 3 else math.clamp(math.ceil(v.Rate*.1),2,28)
   v:SetAttribute("SignusCount",math.max(1,math.floor(count*strength+.5)))
   life=math.max(life,v.Lifetime.Max)
  elseif v:IsA("LuaSourceContainer") or v:IsA("PointLight") then v:Destroy() end
 end
 if copy:IsA("Model") then copy:PivotTo(cf) elseif copy:IsA("BasePart") then copy.CFrame=cf end
 copy.Parent=world()
 for _,v in copy:GetDescendants() do
  if v:IsA("ParticleEmitter") then v:Emit(v:GetAttribute("SignusCount") or 1) end
 end
 return life
end

--[[
	The eclipse: the place's own `eclipse` attachment (a black disc inside
	violet crescents, shine and smoke), cloned whole onto an invisible host.
	Around it go discs made from its own layers and the pack's corona ring: a
	tilted disc of crescents turning about it, a counter-turning ring, a slow
	ripple outward, and a soft purple aura behind. `scale` multiplies every
	authored size and speed: 1 is the attachment as authored, a ten-stud core.
	`set(frame, alpha, scale)` moves, fades and resizes it.
]]
local CORONA_RING="rbxassetid://122514726839250" -- SignusParticles.CoronaRing
function A.eclipse(scope,cf,scale)
 local blank={set=function()end}
 local source=template("Eclipse")
 if not source then warn("[Signus] Missing assembly Eclipse") return blank end
 local host=scope:add(Instance.new("Part"))
 host.Name="Signus_Eclipse";host.Size=Vector3.one*.1;host.Transparency=1
 host.Anchored=true;host.CanCollide=false;host.CanQuery=false;host.CanTouch=false;host.CastShadow=false
 host.CFrame=cf
 local core=source:Clone();core.Name="Eclipse";core.CFrame=CFrame.identity;core.Parent=host
 local authored={}
 for _,v in core:GetChildren() do if v:IsA("ParticleEmitter") and not authored[v.Name] then authored[v.Name]=v end end
 local function derive(from,parent,props)
  local e=from:Clone()
  for k,v in props do e[k]=v end
  e.Parent=parent
  return e
 end
 local function ring(parent,props)
  local e=Instance.new("ParticleEmitter")
  e.Texture=CORONA_RING;e.Orientation=Enum.ParticleOrientation.FacingCamera;e.LockedToPart=true
  e.LightEmission=1;e.LightInfluence=0;e.Speed=NumberRange.new(0);e.Rotation=NumberRange.new(0,360)
  for k,v in props do e[k]=v end
  e.Parent=parent
  return e
 end
 -- The disc lies in the attachment's XZ plane: tilted toward the viewer.
 local tilt=Instance.new("Attachment");tilt.Name="EclipseDisc";tilt.CFrame=CFrame.Angles(math.rad(70),0,math.rad(14));tilt.Parent=host
 -- The authored layers are faint by design; these added discs carry the
 -- shape, bright enough to read against a daylight sky.
 local function hold(alpha)
  return NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.2,alpha),NumberSequenceKeypoint.new(.75,alpha),NumberSequenceKeypoint.new(1,1)})
 end
 local edge,deep=Color3.fromRGB(176,90,255),Color3.fromRGB(120,30,235)
 if authored.Cres2 then
  derive(authored.Cres2,tilt,{Name="Disc",Orientation=Enum.ParticleOrientation.VelocityPerpendicular,EmissionDirection=Enum.NormalId.Top,
   Speed=NumberRange.new(.01),Size=NumberSequence.new(30,34),Rate=10,Lifetime=NumberRange.new(1.4),RotSpeed=NumberRange.new(80),
   Color=ColorSequence.new(deep),Brightness=2.4,Transparency=hold(.45),ZOffset=-.2})
 end
 if authored.Cres then
  derive(authored.Cres,tilt,{Name="DiscInner",Orientation=Enum.ParticleOrientation.VelocityPerpendicular,EmissionDirection=Enum.NormalId.Top,
   Speed=NumberRange.new(.01),Size=NumberSequence.new(19,21),Rate=8,Lifetime=NumberRange.new(1.4),RotSpeed=NumberRange.new(-120),
   Color=ColorSequence.new(edge),Brightness=2.4,Transparency=hold(.4),ZOffset=.4})
 end
 if authored.Shine then
  -- The corona: a bright rim just outside the black disc, behind it.
  derive(authored.Shine,core,{Name="Corona",Color=ColorSequence.new(edge),Size=NumberSequence.new(14,15),Brightness=3,
   Rate=10,Lifetime=NumberRange.new(.8),RotSpeed=NumberRange.new(-60,60),Transparency=hold(.1),ZOffset=-.1})
 end
 ring(core,{Name="Ring",Color=ColorSequence.new(edge),Size=NumberSequence.new(13),Brightness=3,
  Rate=2.6,Lifetime=NumberRange.new(1.2),RotSpeed=NumberRange.new(-30),ZOffset=.6,Transparency=hold(0)})
 ring(core,{Name="Ripple",Color=ColorSequence.new(edge,Color3.fromRGB(84,14,165)),
  Size=NumberSequence.new({NumberSequenceKeypoint.new(0,12),NumberSequenceKeypoint.new(1,32)}),Brightness=1.6,
  Rate=1.2,Lifetime=NumberRange.new(1.8),RotSpeed=NumberRange.new(12),ZOffset=-.8,
  Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(1,1)})})
 if authored.Shine then
  -- The aura: the attachment's own shine, wide and soft behind everything.
  derive(authored.Shine,core,{Name="Aura",Color=ColorSequence.new(Color3.fromRGB(104,24,200)),Size=NumberSequence.new(24,28),
   Brightness=1,Rate=8,Lifetime=NumberRange.new(1.6),RotSpeed=NumberRange.new(-20,20),ZOffset=-2,
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.3,.35),NumberSequenceKeypoint.new(1,1)})})
 end
 local emitters={}
 for _,v in host:GetDescendants() do
  if v:IsA("ParticleEmitter") then
   v.Enabled=false
   table.insert(emitters,{v=v,size=v.Size,speed=v.Speed,rate=v.Rate,alpha=v.Transparency})
  end
 end
 host.Parent=world()
 local result={host=host}
 local lastAlpha,lastScale=-1,-1
 function result:set(frame,alpha,size)
  if not host.Parent then return end
  if frame then host.CFrame=frame end
  alpha=math.clamp(alpha or 1,0,1)
  size=size or scale or 1
  local resize=math.abs(size-lastScale)>.01
  local refade=math.abs(alpha-lastAlpha)>.025
  for _,e in emitters do
   e.v.Enabled=alpha>.015
   e.v.Rate=e.rate*alpha
   if resize then
    local keys={}
    for _,k in e.size.Keypoints do table.insert(keys,NumberSequenceKeypoint.new(k.Time,k.Value*size,k.Envelope*size)) end
    e.v.Size=NumberSequence.new(keys)
    e.v.Speed=NumberRange.new(e.speed.Min*size,e.speed.Max*size)
   end
   if refade then e.v.Transparency=nsScale(e.alpha,alpha) end
  end
  if resize then lastScale=size end
  if refade then lastAlpha=alpha end
 end
 result:set(cf,0,scale)
 return result
end
return A
