-- Complete SoulShroud assemblies; the explosion path retains authored particle settings.
local RS=game:GetService("ReplicatedStorage")
local Content=game:GetService("ContentProvider")
local Run=game:GetService("RunService")
local Library=RS:WaitForChild("SignusLibrary")
local A={}
local violet=Color3.fromRGB(145,38,245)
local orchid=Color3.fromRGB(206,90,255)
local pearl=Color3.fromRGB(243,215,255)
local counts={Storm=42,Column=28,Orb=28,EclipseCore=6,Impact=0,Slash=0,Swirl=0,LungeBlade=38,LungeWake=90,LungeImpact=0,EclipseCorona=7}
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
function A.mount(scope,name,cf,scale,heightScale)
 local blank={set=function()end,burst=function()end}
 if active>=32 and name~="EclipseCore" and name~="EclipseCorona" then return blank end
 local template=Library:FindFirstChild(if name=="EclipseCore" then "Orb" else name)
 if not template then warn("[Signus] Missing assembly "..name) return blank end
 local model=scope:add(template:Clone())
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
    v.Material=if name=="EclipseCore" then Enum.Material.SmoothPlastic else Enum.Material.Neon
    v.Color=if name=="EclipseCore" then Color3.new(0,0,0) elseif v.Name=="Inner" then pearl else violet
    table.insert(meshes,{v=v,opacity=if name=="EclipseCore" then 1 elseif name=="LungeBlade" then .95 elseif name=="Swirl" then .55 elseif name=="Slash" then .85 else .5})
   else v.Transparency=1 end
  elseif v:IsA("ParticleEmitter") then
   local keys={}
   for _,k in v.Color.Keypoints do
    local c=k.Value
    local lum=math.max(c.R,c.G,c.B)
    local color=if name=="EclipseCorona" and lum<.25 then c else violet:Lerp(pearl,math.clamp((lum-.5)*.25,0,.18))
    table.insert(keys,ColorSequenceKeypoint.new(k.Time,color))
   end
   v.Color=ColorSequence.new(keys)
   -- These energy textures composite additively. Keep the black backing invisible;
   -- use emission/count/alpha for restraint instead of exposing the backing.
   v.LightEmission=1;v.LightInfluence=0;v.Brightness=math.min(v.Brightness,1.3)
   v.Enabled=false
   if name=="EclipseCorona" or name=="EclipseCore" then v.LockedToPart=true end
   v.Lifetime=NumberRange.new(math.min(v.Lifetime.Min,1.2),math.min(v.Lifetime.Max,1.5))
   local rate=if name=="EclipseCore" then math.min(v.Rate*factor,2) else v.Rate*factor
   table.insert(emitters,{v=v,rate=rate,alpha=v.Transparency,burst=math.clamp(math.floor(v.Rate*.055+.5),1,14)})
   v.Rate=0
  elseif v:IsA("Beam") then
   -- Keep the source's dark beam cores and alpha masks; flattening all layers
   -- into additive light erases the column's authored silhouette.
   v.Color=if v.LightEmission==0 then ColorSequence.new(Color3.fromRGB(40,8,65)) else ColorSequence.new(orchid,violet)
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
return A
