-- Reference silhouettes are built with textured Beams, authored flipbooks and
-- particles. All hosts are invisible; moved terrain is handled by the server.
local FX=require(script.Parent.SignusFX)
local C=FX.Colors
local Choreo={}
local TAU=math.pi*2
local function ns(a,b) return NumberSequence.new(a,b or a) end
local function mix(a,b,t) return a+(b-a)*math.clamp(t,0,1) end
local function smooth(t) t=math.clamp(t,0,1);return t*t*(3-2*t) end
local function emitter(parent,kind,size,rate,color,extra)
 local props={Size=ns(size*.65,size),Rate=rate,Enabled=true,Lifetime=NumberRange.new(.3,.55),Speed=NumberRange.new(0,2),LightEmission=.85,Brightness=1.5,Color=ColorSequence.new(color or C.violet,C.plum),Transparency=ns(.08,1),SpreadAngle=Vector2.new(180,180)}
 for k,v in pairs(extra or {}) do props[k]=v end
 -- The neutral blackfire flipbook accepts the violet palette cleanly; the
 -- coloured orange fire sheet retains a red cast when tinted.
 return FX.emitter(if kind=="FlameJet" then "DarkFire" else kind,parent,props)
end
local function axisFrame(point,tangent,normal)
 return CFrame.fromMatrix(point,tangent.Unit,normal.Unit,tangent.Unit:Cross(normal.Unit))
end
-- Four cubic Beams describe a continuous circle/arc. The texture carries the
-- irregular edge, while the curve gives the reference its sweeping silhouette.
local function ribbon(parent,col,width,texture)
 local parts={}
 for i=1,4 do
  local beam,a,b=FX.beam(parent,Vector3.zero,Vector3.zero,width,col,texture or FX.Pack.JetBeam.Texture)
  beam.Segments=12;beam.TextureLength=10;beam.TextureSpeed=1.5;beam.LightEmission=1;beam.Brightness=1.5
  table.insert(parts,{beam=beam,a=a,b=b})
 end
 return function(frame,radius,w,opacity,spin,arc)
  local span=(arc or 1)*TAU/4
  for i,v in ipairs(parts) do
   local a=(i-1)*span+spin;local b=a+span
   local p0=Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius)
   local p1=Vector3.new(math.cos(b)*radius,0,math.sin(b)*radius)
   local t0=Vector3.new(-math.sin(a),0,math.cos(a));local t1=Vector3.new(-math.sin(b),0,math.cos(b))
   v.a.CFrame=frame*axisFrame(p0,t0,Vector3.yAxis);v.b.CFrame=frame*axisFrame(p1,t1,Vector3.yAxis)
   local curve=4/3*math.tan(span/4)*radius
   v.beam.CurveSize0=curve;v.beam.CurveSize1=curve
   v.beam.Width0=w*1.8;v.beam.Width1=w*1.3;v.beam.Enabled=opacity>.01
   v.beam.Transparency=ns(1-opacity)
  end
 end
end
local function line(parent,col,texture)
 local b,a0,a1=FX.beam(parent,Vector3.zero,Vector3.zero,1,col,texture or FX.Pack.JetBeam.Texture)
 b.TextureSpeed=4;b.TextureLength=8;b.Segments=16;b.LightEmission=1;b.Brightness=1.5
 return function(from,to,width,opacity)
  a0.Position=from;a1.Position=to;b.Width0=width;b.Width1=width*.65
  b.Enabled=opacity>.01;b.Transparency=ns(1-opacity)
 end
end
local function pulse(parent,diameter)
 local a=FX.attachment(parent,CFrame.Angles(math.pi/2,0,0))
 return emitter(a,"CoreRing",diameter,6,C.orchid,{Lifetime=NumberRange.new(.3),Speed=NumberRange.new(.01),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.zero,Orientation=Enum.ParticleOrientation.VelocityPerpendicular,LockedToPart=true,Rotation=NumberRange.new(0),RotSpeed=NumberRange.new(0),Size=ns(diameter),Transparency=ns(.35,.65)})
end
function Choreo.mount(part,scope)
 local root=scope:add(FX.attachment(part));root.Name="SignusReferenceVFX"
 local kind=part:GetAttribute("SignusKind")
 local radius=part:GetAttribute("Radius") or 12
 local target=part:GetAttribute("Target") or part.Position
 local offset=target-part.Position
 local began=part:GetAttribute("StartedAt") or workspace:GetServerTimeNow()
 local duration=part:GetAttribute("Duration") or 5
 local all={}
 local function emit(parent,name,size,rate,col,props)
  local e=emitter(parent,name,size,rate,col,props);table.insert(all,{e=e,rate=rate});return e
 end
 local function rates(alpha)
  for _,r in ipairs(all) do r.e.Rate=r.rate*alpha;r.e.Enabled=alpha>.01 end
 end
 local rings={ribbon(root,C.orchid,1),ribbon(root,C.pearl,.4),ribbon(root,C.violet,1),ribbon(root,C.orchid,.7)}
 if kind=="SpiralCast" or kind=="Ascension" then
  local centre=FX.attachment(root,CFrame.new(0,3,0))
  emit(centre,"SpiralSmoke",radius*1.7,7,C.plum,{LightEmission=.25,Transparency=ns(.45,1),Speed=NumberRange.new(.01),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.zero,Orientation=Enum.ParticleOrientation.VelocityPerpendicular})
  local electric=emit(centre,"Electric",radius*1.6,9,C.violet,{Lifetime=NumberRange.new(.25),Speed=NumberRange.new(0),Transparency=ns(.05,1)})
  emit(centre,"FlameJet",radius,28,C.violet,{Speed=NumberRange.new(3,8),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(15,15),Lifetime=NumberRange.new(.4,.65)})
  emit(centre,"Embers",.5,35,C.orchid,{Speed=NumberRange.new(8,20),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(20,20)})
  local floor=pulse(root,radius*2)
  local columns={}
  for i=1,5 do columns[i]=line(root,if i%2==0 then C.pearl else C.violet,FX.Pack.Lightning.Texture) end
  return function()
   local t=workspace:GetServerTimeNow()-began
   local attack=math.clamp((t-1.25)/.4,0,1);local burst=math.clamp((t-2.3)/.18,0,1)
   local fade=1-smooth((t-duration+.7)/.7)
   local r=radius*(if t<1.25 then mix(1,.72,t/1.25) elseif t<2.3 then mix(.72,.42,(t-1.25)/1.05) else mix(.42,1.35,burst))
   for i,draw in ipairs(rings) do
    local tilt=if i%2==0 then .25 else -.2
    local height=if i==4 then .35 else 1+(i-1)*3*attack
    draw(CFrame.new(0,height,0)*CFrame.Angles(tilt*attack,0,.15*math.sin(t*3+i)*attack),r*(1-(i-1)*.12),(.32+attack*.85)*(if i==2 then .42 else 1),fade,t*(if i%2==0 then -3 else 3)+i,if i==4 then 1 else .82)
   end
   rates(fade*(.12+attack*.88));electric.Rate=9*attack*fade
   floor.Enabled=fade>.01
   for i,draw in ipairs(columns) do
    local a=i/5*TAU+t;local p=Vector3.new(math.cos(a),0,math.sin(a))*radius*.55
    draw(p,p+Vector3.yAxis*(14+i*3),.4+.9*burst,burst*fade*(.7+.3*math.sin(t*18+i)))
   end
  end
 elseif kind=="LanceCast" then
  local orb=FX.attachment(root);local impact=FX.attachment(root,CFrame.new(offset))
  local glow=emit(orb,"Core",6,8,C.orchid,{LockedToPart=true,Speed=NumberRange.new(0),Lifetime=NumberRange.new(.25),Color=ColorSequence.new(C.violet),Brightness=1.2,Transparency=ns(.12,.3)})
  emit(orb,"EnergyGather",10,8,C.violet,{Speed=NumberRange.new(.01),Orientation=Enum.ParticleOrientation.FacingCamera,LockedToPart=true})
  emit(orb,"Electric",9,9,C.violet,{LockedToPart=true,Speed=NumberRange.new(0)})
  local flame=emit(impact,"FlameJet",13,0,C.violet,{Speed=NumberRange.new(16,25),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(12,12),Lifetime=NumberRange.new(.5,.8)})
  local sparks=emit(impact,"Embers",.6,0,C.orchid,{Speed=NumberRange.new(25,45),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(20,20),Lifetime=NumberRange.new(.6,1.2)})
  local warning=pulse(impact,radius*2)
  local shaft={line(root,C.violet,FX.Pack.JetBeam.Texture),line(root,C.orchid),line(root,C.pearl,FX.Pack.Lightning.Texture)}
  return function()
   local t=workspace:GetServerTimeNow()-began
   local fly=smooth((t-1.3)/.65)
   local point=Vector3.zero:Lerp(offset+Vector3.yAxis*2,fly)+Vector3.yAxis*math.sin(fly*math.pi)*5
   orb.Position=point
   local rise=smooth((t-2.55)/.16);local fade=1-smooth((t-4.4)/.75)
   local active=rise*fade
   glow.Size=ns(if t<1.3 then mix(1.5,4,t/1.3) elseif t<2.55 then mix(4,9,(t-1.95)/.6) else 8*fade)
   rates(fade);flame.Rate=48*active;sparks.Rate=70*active
   warning.Enabled=t<2.55
   local top=offset+Vector3.yAxis*(95*rise)
   for i,draw in ipairs(shaft) do draw(offset,top,({13,7,2.3})[i],active*({.65,.9,1})[i]) end
   rings[1](CFrame.new(point)*CFrame.Angles(.3,0,.35),if t<2.55 then 4+fly*4 else radius*1.1,1.1,fade,t*4,.88)
   rings[2](CFrame.new(offset+Vector3.yAxis*(3+rise*47))*CFrame.Angles(.12,0,0),radius*.8,.55,active,-t*3,1)
   rings[3](CFrame.new(offset+Vector3.yAxis*(1+rise*24))*CFrame.Angles(-.2,0,0),radius*1.25,1.3,active,t*3,1)
   rings[4](CFrame.new(offset+Vector3.yAxis*.4),radius*mix(.8,2,rise),.8,active,t,1)
  end
 elseif kind=="RiftBeam" then
  local delta=offset;local direction=if delta.Magnitude>.1 then delta.Unit else Vector3.zAxis
  local sideways=direction:Cross(Vector3.yAxis).Unit;local up=sideways:Cross(direction).Unit
  local head=FX.attachment(root);local endHost=FX.attachment(root,CFrame.new(offset))
  local core=emit(head,"Core",7,8,C.pearl,{Speed=NumberRange.new(0),LockedToPart=true,Color=ColorSequence.new(C.pearl),Transparency=ns(.1,.4)})
  local charge=emit(head,"EnergyGather",12,10,C.orchid,{Speed=NumberRange.new(0),LockedToPart=true,Orientation=Enum.ParticleOrientation.FacingCamera})
  local jet=emit(head,"FlameJet",8,40,C.violet,{Speed=NumberRange.new(2,5),Lifetime=NumberRange.new(.25,.45)})
  local endFire=emit(endHost,"FlameJet",10,50,C.violet,{Speed=NumberRange.new(6,15),Lifetime=NumberRange.new(.3,.6)})
  local beam={line(root,C.violet,FX.Pack.JetBeam.Texture),line(root,C.violet),line(root,C.orchid,FX.Pack.Lightning.Texture)}
  local jets={}
  for i=1,10 do
   local a=FX.attachment(root,CFrame.new(offset*i/10))
   local e=emit(a,"FlameJet",10,8,C.violet,{Speed=NumberRange.new(3,8),Lifetime=NumberRange.new(.3,.45)})
   local sp=emit(a,"Embers",.45,6,C.orchid,{Speed=NumberRange.new(8,15),Lifetime=NumberRange.new(.3,.7)})
   table.insert(jets,{e=e,s=sp,a=a,f=i/10})
  end
  local filaments={};for i=1,12 do filaments[i]=line(root,C.orchid,FX.Pack.JetBeam.Texture) end
  return function()
   local t=workspace:GetServerTimeNow()-began
   local active=smooth((t-1.5)/.18)*(1-smooth((t-5)/.5));local fade=1-smooth((t-5)/.7)
   rates(fade);jet.Rate=40*fade;endFire.Rate=50*active
   core.Size=ns(mix(.5,3.5,smooth(t/1.5)));charge.Rate=10*(1-active)*fade
   for i,draw in ipairs(beam) do draw(Vector3.zero,offset,({8,4,1.2})[i]*(.92+.08*math.sin(t*25)),active*({.7,.95,1})[i]) end
   for _,v in ipairs(jets) do v.e.Rate=8*active;v.s.Rate=6*active end
   for i,draw in ipairs(filaments) do
    local f0=(i-1)/12;local f1=i/12
    local function p(f) return offset*f+(sideways*math.sin(f*TAU*2-t*9)+up*math.cos(f*TAU*2-t*9))*(1.4+f) end
    draw(p(f0),p(f1),.5,active*.8)
   end
   local facing=CFrame.lookAt(Vector3.zero,direction)*CFrame.Angles(math.pi/2,0,0)
   rings[1](facing,4,.7,fade,t*4,.85);rings[2](facing,4.6,.25,fade,-t*4,1)
   rings[3](CFrame.new(offset)*facing.Rotation,5,.6,active,t*2,.85);rings[4](CFrame.new(offset)*facing.Rotation,7,.35,active,-t*2,1)
  end
 elseif kind=="Aura" then
  local phase=part:GetAttribute("Phase") or 1
  local feet=FX.attachment(root,CFrame.new(0,-5,0))
  emit(feet,"SpiralSmoke",11,3,C.violet,{Speed=NumberRange.new(.01),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.zero,Orientation=Enum.ParticleOrientation.VelocityPerpendicular,Transparency=ns(.6,1),LightEmission=.4})
  emit(feet,"Embers",.25,if phase==2 then 15 else 8,C.orchid,{Speed=NumberRange.new(2,5),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(30,30),Lifetime=NumberRange.new(.7,1.3)})
  local hands=FX.attachment(root,CFrame.new(0,0,-3))
  emit(hands,"Electric",5,if phase==2 then 3 else 1,C.violet,{Speed=NumberRange.new(0),Transparency=ns(.5,1)})
  return function()
   local t=workspace:GetServerTimeNow();local alpha=part:FindFirstChild("FXOpacity");local fade=alpha and alpha.Value or 1
   rings[1](CFrame.new(0,-5,0),6,.35,fade*.65,t*.8,.82)
   rings[2](CFrame.new(0,-4.7,0),6.8,.16,fade*.5,-t*.6,.7)
   rings[3](CFrame.new(0,0,0)*CFrame.Angles(.25,0,.15),7,.3,if phase==2 then fade*.65 else 0,t*.6,.65)
   rings[4](CFrame.new(0,3,0)*CFrame.Angles(-.3,0,0),5,.25,if phase==2 then fade*.6 else 0,-t*.7,.65)
   rates(fade)
  end
 end
 return function() end
end
return Choreo
