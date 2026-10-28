-- Reference silhouettes are built with textured Beams, authored flipbooks and
-- particles. All hosts are invisible; moved terrain is handled by the server.
local FX=require(script.Parent.SignusFX)
local VFX=require(script.Parent.SignusVFX)
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
-- A frame at `point` whose X axis (a Beam's curve axis) runs along `tangent`.
local function tangentFrame(point,tangent)
 local up=if math.abs(tangent.Unit.Y)>.95 then Vector3.zAxis else Vector3.yAxis
 return CFrame.fromMatrix(point,tangent.Unit,tangent:Cross(up).Unit)
end
-- A frame at `position` whose Front (-Z) looks along `direction`, safe when
-- that is straight up or down.
local function aim(position,direction)
 local unit=if direction.Magnitude>1e-3 then direction.Unit else Vector3.yAxis
 return CFrame.lookAt(position,position+unit,if math.abs(unit.Y)>.98 then Vector3.zAxis else Vector3.yAxis)
end
-- Four cubic Beams describe a continuous circle/arc. The texture carries the
-- irregular edge, while the curve gives the reference its sweeping silhouette.
-- A dark ribbon is drawn without light emission so black reads as black.
local function ribbon(parent,col,width,texture,dark)
 local parts={}
 for i=1,4 do
  local beam,a,b=FX.beam(parent,Vector3.zero,Vector3.zero,width,col,texture or FX.Pack.JetBeam.Texture)
  beam.Segments=12;beam.TextureLength=10;beam.TextureSpeed=1.5
  beam.LightEmission=if dark then 0 else 1;beam.Brightness=if dark then 1 else 1.5
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
-- A straight textured stroke. lineWith also hands back the Beam for callers
-- that shape its taper and transparency themselves.
local function lineWith(parent,col,texture,dark)
 local b,a0,a1=FX.beam(parent,Vector3.zero,Vector3.zero,1,col,texture or FX.Pack.JetBeam.Texture)
 b.TextureSpeed=4;b.TextureLength=8;b.Segments=16
 b.LightEmission=if dark then 0 else 1;b.Brightness=if dark then 1 else 1.5
 return function(from,to,width,opacity)
  a0.Position=from;a1.Position=to;b.Width0=width;b.Width1=width*.65
  b.Enabled=opacity>.01;b.Transparency=ns(1-opacity)
 end,b
end
local function line(parent,col,texture,dark)
 return (lineWith(parent,col,texture,dark))
end
local function pulse(parent,diameter)
 local a=FX.attachment(parent,CFrame.Angles(math.pi/2,0,0))
 return emitter(a,"CoreRing",diameter,6,C.orchid,{Lifetime=NumberRange.new(.3),Speed=NumberRange.new(.01),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.zero,Orientation=Enum.ParticleOrientation.VelocityPerpendicular,LockedToPart=true,Rotation=NumberRange.new(0),RotSpeed=NumberRange.new(0),Size=ns(diameter),Transparency=ns(.35,.65)})
end

--[[
	THE ECLIPSE CROWN

	Phase two's eclipse, worn behind the hood: a black disc in a pearl rim,
	a corona of rays that always fan out toward whoever is looking, a
	diamond-ring flare creeping round the rim, a slow violet shroud, and two
	tilted orbit rings that give it depth from the side. It grows in when the
	transformation lands.
]]
local CROWN=CFrame.new(0,11.4,2.2)
local function eclipseCrown(root,part,emit)
 local born=os.clock()
 local R=3.8
 local centre=FX.attachment(root,CROWN)
 local face=Enum.ParticleOrientation.FacingCamera
 local function plane(kind,size,col,opacity,z,props)
  local base={LockedToPart=true,Speed=NumberRange.new(0),Lifetime=NumberRange.new(.22),Orientation=face,Color=ColorSequence.new(col),Transparency=ns(opacity),ZOffset=z,Rotation=NumberRange.new(0),RotSpeed=NumberRange.new(0),SpreadAngle=Vector2.zero}
  for k,v in pairs(props or {}) do base[k]=v end
  return emit(centre,kind,size,14,col,base)
 end
 local shroud=plane("Swirl",R*4.6,C.violet,.5,0,{LightEmission=.7,Rotation=NumberRange.new(-180,180),RotSpeed=NumberRange.new(-40)})
 local corona=plane("Aura",R*4.2,C.orchid,.15,.5,{LightEmission=1,Brightness=2,Rotation=NumberRange.new(-180,180),RotSpeed=NumberRange.new(70)})
 local rim=plane("Core",R*2.3,C.pearl,0,1,{LightEmission=1,Brightness=4})
 local disc=plane("Core",R*2,C.black,0,1.3,{LightEmission=0,Brightness=1})
 local diamondHost=FX.attachment(root,CROWN)
 local diamond=emit(diamondHost,"Star",R*1.6,12,C.pearl,{LockedToPart=true,Speed=NumberRange.new(0),Lifetime=NumberRange.new(.2),Orientation=face,Color=ColorSequence.new(C.pearl),Transparency=ns(0),ZOffset=1.8,LightEmission=1,Brightness=3,Rotation=NumberRange.new(0),RotSpeed=NumberRange.new(0),SpreadAngle=Vector2.zero})
 emit(centre,"Embers",.35,24,C.orchid,{Speed=NumberRange.new(2,6),SpreadAngle=Vector2.new(180,180),Lifetime=NumberRange.new(1,1.8),Color=ColorSequence.new(C.pearl,C.violet),Transparency=ns(.05,1),LightEmission=1})
 local orbits={ribbon(root,C.pearl,.22),ribbon(root,C.orchid,.4)}
 local rays={}
 for i=1,14 do
  -- Untextured, so each ray is a clean tapering spike of light.
  local b,a0,a1=FX.beam(root,Vector3.zero,Vector3.zero,1,C.pearl,"")
  b.Color=ColorSequence.new(C.pearl,C.orchid);b.LightEmission=1;b.Brightness=3;b.Segments=2
  b.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(.5,.45),NumberSequenceKeypoint.new(1,1)})
  rays[i]={b=b,a0=a0,a1=a1,seed=i*1.73}
 end
 local lamp=Instance.new("PointLight");lamp.Color=C.orchid;lamp.Range=30;lamp.Brightness=0;lamp.Shadows=false;lamp.Parent=centre
 local centrePos=CROWN.Position
 return function(t,fade)
  local grow=smooth((os.clock()-born)/1.4)*fade
  local s=math.max(grow,.01)*(1+.03*math.sin(t*3))
  disc.Size=ns(R*2*s);rim.Size=ns(R*2.3*s*(1+.025*math.sin(t*7)))
  corona.Size=ns(R*4.2*s*(1+.08*math.sin(t*2.3)));shroud.Size=ns(R*4.6*s)
  local camera=workspace.CurrentCamera
  if camera then
   -- Rays and the flare live in the plane facing the camera, so the corona
   -- reads as a sun from every side.
   local right=part.CFrame:VectorToObjectSpace(camera.CFrame.RightVector)
   local up=part.CFrame:VectorToObjectSpace(camera.CFrame.UpVector)
   for i,ray in ipairs(rays) do
    local a=i/#rays*TAU+t*.12
    local d=right*math.cos(a)+up*math.sin(a)
    local len=R*(1+1.8*math.clamp(.5+math.noise(t*1.1,ray.seed),0,1))*(if i%2==0 then .55 else 1)
    ray.a0.Position=centrePos+d*R*1.02*s;ray.a1.Position=centrePos+d*(R*1.02+len)*s
    ray.b.Width0=(if i%2==0 then .55 else 1)*s;ray.b.Width1=0;ray.b.Enabled=grow>.02
   end
   local da=t*.3
   diamondHost.Position=centrePos+(right*math.cos(da)+up*math.sin(da))*R*1.02*s
   diamond.Size=ns(R*(1+.6*math.sin(t*4)^2)*s)
  end
  local spin=t*.55
  orbits[1](CFrame.new(centrePos)*CFrame.Angles(1.15,spin,.35),R*1.5*s,.3,grow*.85,t*1.4,.9)
  orbits[2](CFrame.new(centrePos)*CFrame.Angles(-.75,-spin*.8,-.5),R*1.75*s,.4,grow*.6,-t,.78)
  lamp.Brightness=3*grow
 end
end

--[[
	THE WINGS

	Two crescent wings of violet fire, three curved strokes each, rooted
	between the shoulders. They beat faster the faster it moves, so a dive
	reads differently from a hover.
]]
local function flameWings(root,part,emit)
 local born=os.clock()
 local wings={}
 local WIDTH={4.2,4.8,3.8}
 local LENGTH={16,14,11.5}
 for _,side in ipairs({-1,1}) do
  local strokes={}
  for j=1,3 do
   -- A violet flame, only half emissive so it stays violet against a bright
   -- sky, around a solid glowing core on the same two attachments.
   local b,a0,a1=FX.beam(root,Vector3.zero,Vector3.zero,1,C.violet,FX.Pack.JetBeam.Texture)
   b.Color=ColorSequence.new(C.violet,C.plum)
   b.LightEmission=.45;b.Brightness=2;b.FaceCamera=true
   b.TextureSpeed=-3;b.TextureLength=7;b.Segments=16
   b.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(.7,.2),NumberSequenceKeypoint.new(1,1)})
   local core=Instance.new("Beam");core.Name="SignusWingCore";core.Attachment0=a0;core.Attachment1=a1
   core.Texture="";core.FaceCamera=true;core.Segments=16;core.LightEmission=1;core.LightInfluence=0;core.Brightness=2
   core.Color=ColorSequence.new(C.orchid,C.violet);core.ZOffset=.1
   core.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(.75,.45),NumberSequenceKeypoint.new(1,1)})
   core.Parent=root
   strokes[j]={b=b,core=core,a0=a0,a1=a1}
  end
  -- The leading edge: a clean bright line along the top stroke.
  local edge,e0,e1=FX.beam(root,Vector3.zero,Vector3.zero,1,C.pearl,"")
  edge.Color=ColorSequence.new(C.pearl,C.orchid);edge.LightEmission=1;edge.Brightness=2.5;edge.Segments=16
  edge.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(.8,.35),NumberSequenceKeypoint.new(1,1)})
  local tip=FX.attachment(root)
  emit(tip,"DarkFire",6,18,C.violet,{Speed=NumberRange.new(1,4),Lifetime=NumberRange.new(.35,.7),Color=ColorSequence.new(C.orchid,C.violet),Transparency=ns(.25,1),LightEmission=.7})
  emit(tip,"Embers",.35,20,C.pearl,{Speed=NumberRange.new(2,7),Lifetime=NumberRange.new(.5,1.1),Color=ColorSequence.new(C.pearl,C.violet),Transparency=ns(0,1),LightEmission=1})
  wings[side]={strokes=strokes,edge={b=edge,a0=e0,a1=e1},tip=tip}
 end
 local last,lastPos,speed=os.clock(),part.Position,0
 return function(t,fade)
  local now=os.clock();local dt=math.max(now-last,1/240);last=now
  speed=mix(speed,(part.Position-lastPos).Magnitude/dt,math.clamp(dt*4,0,1));lastPos=part.Position
  local open=smooth((now-born)/1.2)*fade
  local beat=math.sin(t*(2+math.min(speed,30)*.09))
  for side,wing in pairs(wings) do
   -- Spread wide and low, under the crown rather than into it.
   local base=Vector3.new(side*1.2,2.4,2.4)
   for j,s in ipairs(wing.strokes) do
    local rise=math.rad(28-(j-1)*22+beat*(13-j*2))
    local length=LENGTH[j]*open
    local outward=Vector3.new(side*math.cos(rise),math.sin(rise),.28+j*.1).Unit
    local tipPos=base+outward*length
    s.a0.CFrame=tangentFrame(base,outward+Vector3.yAxis*.9)
    s.a1.CFrame=tangentFrame(tipPos,outward-Vector3.yAxis*.55)
    s.b.CurveSize0=length*.38;s.b.CurveSize1=length*.3
    s.b.Width0=WIDTH[j]*open;s.b.Width1=.3*open
    s.b.Enabled=open>.02
    s.core.CurveSize0=s.b.CurveSize0;s.core.CurveSize1=s.b.CurveSize1
    s.core.Width0=WIDTH[j]*.38*open;s.core.Width1=.12*open;s.core.Enabled=s.b.Enabled
    if j==1 then
     local e=wing.edge
     e.a0.CFrame=s.a0.CFrame;e.a1.CFrame=s.a1.CFrame
     e.b.CurveSize0=s.b.CurveSize0;e.b.CurveSize1=s.b.CurveSize1
     e.b.Width0=.6*open;e.b.Width1=.1*open;e.b.Enabled=s.b.Enabled
     wing.tip.Position=tipPos
    end
   end
  end
 end
end

function Choreo.mount(part,scope)
 local root=scope:add(FX.attachment(part));root.Name="SignusReferenceVFX"
 local kind=part:GetAttribute("SignusKind")
 local phase=part:GetAttribute("Phase") or 1
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
  local strong=phase==2
  local centre=FX.attachment(root,CFrame.new(0,3,0))
  emit(centre,"Smoke",radius*.8,8,C.plum,{LightEmission=.3,Transparency=ns(.65,1),Speed=NumberRange.new(2,5),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(15,15),Lifetime=NumberRange.new(.4,.7)})
  local electric=emit(centre,"Electric",radius*1.6,9,C.violet,{Lifetime=NumberRange.new(.25),Speed=NumberRange.new(0),Transparency=ns(.05,1)})
  emit(centre,"FlameJet",radius,if strong then 40 else 28,C.violet,{Speed=NumberRange.new(3,8),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(15,15),Lifetime=NumberRange.new(.4,.65)})
  emit(centre,"Embers",.5,if strong then 55 else 35,C.orchid,{Speed=NumberRange.new(8,20),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(20,20)})
  local floor=pulse(root,radius*2)
  local count=if strong then 9 else 5
  local columns={}
  for i=1,count do columns[i]=line(root,if i%2==0 then C.orchid else C.violet,FX.Pack.JetBeam.Texture) end
  -- Phase two: black rings coil against the violet ones, and a black-cored
  -- pillar bursts up through the eye of the storm.
  local voids={}
  local spine
  if strong then
   voids={ribbon(root,C.black,1.2,nil,true),ribbon(root,C.black,.8,nil,true)}
   spine={line(root,C.pearl,FX.Pack.Lightning.Texture),line(root,C.black,nil,true)}
  end
  return function()
   local t=workspace:GetServerTimeNow()-began
   local attack=math.clamp((t-1.25)/.4,0,1);local burst=math.clamp((t-2.3)/.18,0,1)
   local fade=1-smooth((t-duration+.7)/.7)
   local fold=smooth((t-1.45)/.45)*(1-smooth((t-2.2)/.25))
   local r=radius*(if t<1.25 then mix(1,.72,t/1.25) elseif t<2.3 then mix(.72,.42,(t-1.25)/1.05) else mix(.42,1.35,burst))
   for i,draw in ipairs(rings) do
    local tilt=if i%2==0 then .25 else -.2
    local height=if i==4 then .35 else 3+(i-1)*4*attack+fold*4
    local upright=if i==1 or i==3 then fold*math.pi*.48 else 0
    draw(CFrame.new(0,height,0)*CFrame.Angles(tilt*attack+upright,i*.7,.15*math.sin(t*3+i)*attack),r*(1-(i-1)*.12),(.32+attack*1.25)*(if i==2 then .42 else 1),fade,t*(if i%2==0 then -3 else 3)+i,if i==4 then 1 else .82)
   end
   for i,draw in ipairs(voids) do
    local height=2+i*3*attack+fold*3
    draw(CFrame.new(0,height,0)*CFrame.Angles(.3*attack*(if i==1 then 1 else -1),i,0),r*(1.12-i*.18),(.4+attack)*(if i==1 then 1 else .7),fade*.85,-t*(3+i),.9)
   end
   rates(fade*(.12+attack*.88));electric.Rate=9*attack*fade
   floor.Enabled=fade>.01
   for i,draw in ipairs(columns) do
    local a=i/count*TAU+t;local p=Vector3.new(math.cos(a),0,math.sin(a))*radius*.55
    draw(p,p+Vector3.yAxis*((if strong then 22 else 14)+i*3),(.5+1.5*burst)*(if strong then 1.5 else 1),burst*fade*(.7+.3*math.sin(t*18+i)))
   end
   if spine then
    local top=Vector3.yAxis*(75*burst)
    spine[1](Vector3.zero,top,6+4*burst,burst*fade*.9)
    spine[2](Vector3.zero,top,2.2,burst*fade)
   end
  end
 elseif kind=="LanceCast" then
  local strong=phase==2
  local big=if strong then 1.3 else 1
  local orb=FX.attachment(root);local impact=FX.attachment(root,CFrame.new(offset))
  local glow=emit(orb,"Core",6,8,C.orchid,{LockedToPart=true,Speed=NumberRange.new(0),Lifetime=NumberRange.new(.25),Color=ColorSequence.new(C.violet),Brightness=1.2,Transparency=ns(.12,.3)})
  emit(orb,"EnergyGather",10*big,8,C.violet,{Speed=NumberRange.new(.01),Orientation=Enum.ParticleOrientation.FacingCamera,LockedToPart=true})
  emit(orb,"Electric",9*big,9,C.violet,{LockedToPart=true,Speed=NumberRange.new(0)})
  local flame=emit(impact,"FlameJet",13*big,0,C.violet,{Speed=NumberRange.new(16,25),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(12,12),Lifetime=NumberRange.new(.5,.8)})
  local sparks=emit(impact,"Embers",.6,0,C.orchid,{Speed=NumberRange.new(25,45),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(20,20),Lifetime=NumberRange.new(.6,1.2)})
  local warning=pulse(impact,radius*2)
  local shaft={line(root,C.violet,FX.Pack.JetBeam.Texture),line(root,C.orchid),line(root,C.pearl,FX.Pack.Lightning.Texture)}
  local void=if strong then line(root,C.black,nil,true) else nil
  local height=if strong then 140 else 95
  return function()
   local t=workspace:GetServerTimeNow()-began
   local fly=smooth((t-1.3)/.65)
   local point=Vector3.zero:Lerp(offset+Vector3.yAxis*2,fly)+Vector3.yAxis*math.sin(fly*math.pi)*5
   orb.Position=point
   local rise=smooth((t-2.55)/.16);local fade=1-smooth((t-4.4)/.75)
   local active=rise*fade
   glow.Size=ns(big*(if t<1.3 then mix(1.5,4,t/1.3) elseif t<2.55 then mix(4,9,(t-1.95)/.6) else 8*fade))
   rates(fade);flame.Rate=48*active;sparks.Rate=70*active
   warning.Enabled=t<2.55
   local top=offset+Vector3.yAxis*(height*rise)
   for i,draw in ipairs(shaft) do draw(offset,top,({13,7,2.3})[i]*big,active*({.65,.9,1})[i]) end
   if void then void(offset,top,2.4,active) end
   rings[1](CFrame.new(point)*CFrame.Angles(.3,0,.35),if t<2.55 then 4+fly*4 else radius*1.1,1.1,fade,t*4,.88)
   rings[2](CFrame.new(offset+Vector3.yAxis*(3+rise*47*big))*CFrame.Angles(.12,0,0),radius*.8,.55,active,-t*3,1)
   rings[3](CFrame.new(offset+Vector3.yAxis*(1+rise*24*big))*CFrame.Angles(-.2,0,0),radius*1.25,1.3,active,t*3,1)
   rings[4](CFrame.new(offset+Vector3.yAxis*.4),radius*mix(.8,2,rise),.8,active,t,1)
  end
 elseif kind=="RiftBeam" then
  --[[
	WORLDREND. The carrier rides the hands; its Target is wherever the beam
	ends RIGHT NOW (the first block it meets, or its range), and Hit says
	which. The charge sucks light in and draws a sight line; the beam then
	runs out to its end in a blink. A beam that meets a block ends in a
	sustained blast at the surface; one that meets nothing tapers out.
  ]]
  local charge=part:GetAttribute("Charge") or 1.5
  local strong=phase==2
  local big=if strong then 1.4 else 1
  local stop=duration-.35
  local lockAt=charge-.55
  local muzzle=FX.attachment(root)
  local core=emit(muzzle,"Core",1,12,C.orchid,{Speed=NumberRange.new(0),LockedToPart=true,Color=ColorSequence.new(C.pearl,C.orchid),Transparency=ns(.3,.6),Lifetime=NumberRange.new(.2),Brightness=2,Orientation=Enum.ParticleOrientation.FacingCamera})
  local glow=emit(muzzle,"Aura",10*big,6,C.violet,{LockedToPart=true,Speed=NumberRange.new(0),Lifetime=NumberRange.new(.3),Color=ColorSequence.new(C.violet),Transparency=ns(.3,1),LightEmission=.6,Orientation=Enum.ParticleOrientation.FacingCamera})
  local gather=emit(muzzle,"EnergyGather",13*big,12,C.orchid,{Speed=NumberRange.new(0),LockedToPart=true,Orientation=Enum.ParticleOrientation.FacingCamera})
  local arcs=emit(muzzle,"Electric",9*big,10,C.violet,{LockedToPart=true,Speed=NumberRange.new(0),Lifetime=NumberRange.new(.18)})
  local blowback=emit(muzzle,"FlameJet",7*big,0,C.violet,{EmissionDirection=Enum.NormalId.Back,Speed=NumberRange.new(6,14),Lifetime=NumberRange.new(.2,.4),SpreadAngle=Vector2.new(55,55)})
  local exhaust=emit(muzzle,"Streaks",1.2*big,0,C.pearl,{EmissionDirection=Enum.NormalId.Front,Speed=NumberRange.new(80,120),Lifetime=NumberRange.new(.15,.3),SpreadAngle=Vector2.new(6,6),Color=ColorSequence.new(C.pearl,C.orchid),Transparency=ns(0,1),LightEmission=1})
  -- Light drawn in from a shell around the hands while it charges.
  local well=FX.host(scope,part.Position,"SignusBeamWell");well.Size=Vector3.one*20*big
  local suck=FX.emitter("Streaks",well,{Enabled=true,Rate=0,Shape=Enum.ParticleEmitterShape.Sphere,ShapeInOut=Enum.ParticleEmitterShapeInOut.Inward,ShapeStyle=Enum.ParticleEmitterShapeStyle.Surface,Speed=NumberRange.new(30,36),Lifetime=NumberRange.new(.3),Size=ns(.9*big,.3),Color=ColorSequence.new(C.pearl,C.orchid),LightEmission=1,Transparency=ns(.15,.5)})
  local lamp=Instance.new("PointLight");lamp.Color=C.orchid;lamp.Shadows=false;lamp.Brightness=0;lamp.Parent=muzzle
  -- The sight line and the closing ring where it will land.
  local sight,sightBeam=lineWith(root,C.orchid,FX.Pack.Lightning.Texture);sightBeam.TextureSpeed=-6
  local markHost=FX.attachment(root)
  local mark=FX.emitter("PressureRing",markHost,{Enabled=true,Rate=0,Lifetime=NumberRange.new(.4),Speed=NumberRange.new(.01),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.zero,Orientation=Enum.ParticleOrientation.VelocityPerpendicular,LockedToPart=true,Size=ns(9*big,2),Color=ColorSequence.new(C.orchid),LightEmission=1,Transparency=ns(.25,1),Rotation=NumberRange.new(0),RotSpeed=NumberRange.new(0)})
  -- The beam itself. Untextured bands give it a solid, defined body - a
  -- white-hot core in an orchid body in a violet glow - and the pack's flame
  -- and lightning sheets ride over it. The flame sheath is only half
  -- emissive, so it stays violet against a bright sky. Phase two threads a
  -- black core through it.
  local layers={}
  local function layer(col,tail,texture,width,opacity,speed,light,z)
   local draw,b=lineWith(root,col,texture,light==0)
   b.Color=ColorSequence.new(col,tail);b.TextureSpeed=speed;b.TextureLength=14;b.Segments=24;b.ZOffset=z or 0
   b.LightEmission=light or 1
   table.insert(layers,{draw=draw,b=b,width=width*big,opacity=opacity})
  end
  layer(C.violet,C.plum,FX.Pack.JetBeam.Texture,14,.6,6,.5)
  layer(C.violet,C.violet,"",9,.28,0)
  layer(C.orchid,C.violet,"",5,.6,0,1,.1)
  -- In phase two the white core widens into a rim around a black one.
  layer(C.pearl,C.orchid,"",if strong then 2.9 else 2.3,.95,0,1,.2)
  layer(C.pearl,C.orchid,FX.Pack.Lightning.Texture,3.8,.8,16,1,.25)
  if strong then layer(C.black,C.black,"",1.9,1,0,0,.45) end
  local helix={}
  for h=1,2 do for i=1,12 do table.insert(helix,{draw=line(root,if h==1 then C.orchid else C.pearl,FX.Pack.JetBeam.Texture),h=h,i=i}) end end
  local waves={}
  for i=1,3 do waves[i]=ribbon(root,if i==2 then C.pearl else C.orchid,.6) end
  local streams={}
  for i=1,6 do
   local a=FX.attachment(root)
   local streak=emit(a,"Streaks",.9*big,0,C.pearl,{EmissionDirection=Enum.NormalId.Front,Speed=NumberRange.new(60,110),Lifetime=NumberRange.new(.12,.25),SpreadAngle=Vector2.new(8,8),Color=ColorSequence.new(C.pearl,C.orchid),Transparency=ns(0,1),LightEmission=1})
   local flame=emit(a,"FlameJet",6*big,0,C.violet,{Speed=NumberRange.new(3,8),Lifetime=NumberRange.new(.25,.45)})
   streams[i]={a=a,streak=streak,flame=flame,at=(i-.5)/6}
  end
  -- Where it meets a block.
  local impact=FX.attachment(root)
  local hot=emit(impact,"Core",4.5*big,0,C.orchid,{LockedToPart=true,Speed=NumberRange.new(0),Lifetime=NumberRange.new(.2),Color=ColorSequence.new(C.pearl,C.orchid),Transparency=ns(.3,.6),Brightness=2,Orientation=Enum.ParticleOrientation.FacingCamera})
  local plume=emit(impact,"DarkFire",11*big,0,C.violet,{EmissionDirection=Enum.NormalId.Front,Speed=NumberRange.new(8,20),Lifetime=NumberRange.new(.35,.6),SpreadAngle=Vector2.new(35,35),Color=ColorSequence.new(C.orchid,C.violet),LightEmission=.8})
  local spray=emit(impact,"Embers",.6*big,0,C.pearl,{EmissionDirection=Enum.NormalId.Front,Speed=NumberRange.new(30,70),Lifetime=NumberRange.new(.4,.9),SpreadAngle=Vector2.new(70,70),Acceleration=Vector3.new(0,-70,0),Drag=1,Color=ColorSequence.new(C.pearl,C.orchid),Transparency=ns(0,1),LightEmission=1})
  local chips=emit(impact,"Rock",.8,0,C.plum,{EmissionDirection=Enum.NormalId.Front,Speed=NumberRange.new(18,40),Lifetime=NumberRange.new(.6,1.1),SpreadAngle=Vector2.new(55,55),Acceleration=Vector3.new(0,-70,0),Color=ColorSequence.new(C.plum,C.violet),Transparency=ns(.1,1),LightEmission=.15,Rotation=NumberRange.new(-180,180),RotSpeed=NumberRange.new(-200,200)})
  local scorch=emit(impact,"GroundCrack",12*big,0,C.orchid,{EmissionDirection=Enum.NormalId.Front,Speed=NumberRange.new(.01),SpreadAngle=Vector2.zero,Orientation=Enum.ParticleOrientation.VelocityPerpendicular,Lifetime=NumberRange.new(.5),LockedToPart=true,Color=ColorSequence.new(C.orchid,C.violet),Transparency=ns(.2,1),LightEmission=1})
  local smog=emit(impact,"Smoke",8*big,0,C.plum,{EmissionDirection=Enum.NormalId.Front,Speed=NumberRange.new(4,9),Lifetime=NumberRange.new(.6,1),SpreadAngle=Vector2.new(25,25),Transparency=ns(.5,1),LightEmission=.2})
  local impactLamp=Instance.new("PointLight");impactLamp.Color=C.orchid;impactLamp.Range=20;impactLamp.Shadows=false;impactLamp.Brightness=0;impactLamp.Parent=impact
  local mountedAt=workspace:GetServerTimeNow()-began
  local chargeSound=if mountedAt<charge then FX.sound(muzzle,.9,.6,FX.Sounds.roar) else nil
  local hum,crackle
  local shown=offset
  local last=os.clock()
  local lastRumble=0
  return function()
   local now=os.clock();local dt=math.min(now-last,.1);last=now
   local t=workspace:GetServerTimeNow()-began
   -- The replicated end steps at the server's rate; ease toward it.
   local want=(part:GetAttribute("Target") or target)-part.Position
   shown=shown:Lerp(want,math.clamp(dt*24,0,1))
   local hit=part:GetAttribute("Hit")==true
   local normal=part:GetAttribute("Normal") or Vector3.yAxis
   local length=shown.Magnitude
   local dir=if length>.1 then shown/length else Vector3.zAxis
   local frame=aim(Vector3.zero,dir)
   muzzle.CFrame=frame;well.CFrame=CFrame.new(part.Position)
   local charging=t<charge
   local c=smooth(t/charge)
   local on=smooth((t-charge)/.08)*(1-smooth((t-stop)/.3))
   local reach=smooth((t-charge)/.14)
   local locked=t>=lockAt
   local fizzle=if hit then 0 else 1 -- an open-ended beam tapers away
   -- CHARGE.
   core.Size=ns(if charging then mix(.5,3.8*big,c) else 3.2*big*(.9+.1*math.sin(t*40))*on)
   glow.Size=ns(mix(4,12*big,c)*(if charging then 1 else 1.3*on))
   gather.Rate=if charging then 14 else 0
   arcs.Rate=if charging then 6+10*c else 14*on
   suck.Rate=if charging then 30+90*c else 0
   core.Rate=if charging or on>.01 then 12 else 0;glow.Rate=core.Rate*.5
   lamp.Range=mix(8,22,c);lamp.Brightness=if charging then .5+1.5*c else 2*on
   local tele=if not charging then 0 elseif locked then .55+.35*math.sin(t*50)^2 else .2+.1*math.sin(t*20)
   sight(Vector3.zero,shown,(if locked then .8 else .3)*big,tele)
   markHost.CFrame=aim(shown+normal*.2,normal)
   mark.Rate=if charging and hit then (if locked then 16 else 6) else 0
   -- FIRE.
   local tip=shown*reach
   local throb=1+.12*math.sin(t*38)+.06*math.sin(t*91)
   for _,l in ipairs(layers) do
    local w=l.width*throb*on;local o=l.opacity*on
    l.draw(Vector3.zero,tip,w,o)
    l.b.Width1=w*(if hit then .9 else .3)
    l.b.Transparency=if hit then ns(1-o) else NumberSequence.new({NumberSequenceKeypoint.new(0,1-o),NumberSequenceKeypoint.new(.7,1-o),NumberSequenceKeypoint.new(1,1)})
   end
   local span=tip.Magnitude
   for _,v in ipairs(helix) do
    local spin=t*(if v.h==1 then 11 else -9)+(v.h-1)*math.pi
    local function at(f)
     local a=f*TAU*2.5+spin;local r=(1.4+f*1.6)*big
     return frame*Vector3.new(math.cos(a)*r,math.sin(a)*r,-f*span)
    end
    local f0=(v.i-1)/12;local f1=v.i/12
    v.draw(at(f0),at(f1),.45*big,on*.8*(1-fizzle*smooth((f1-.65)/.35)))
   end
   for i,draw in ipairs(waves) do
    local f=(t*1.8+i/3)%1
    draw(CFrame.new(tip*f)*frame*CFrame.Angles(math.pi/2,0,0),(2.5+f*2.5)*big,.5,on*.75*(1-f*.4)*(1-fizzle*smooth((f-.65)/.35)),t*6+i,1)
   end
   for _,s in ipairs(streams) do
    s.a.CFrame=CFrame.new(tip*s.at)*frame
    local alive=on*(1-fizzle*smooth((s.at-.7)/.3))
    s.streak.Rate=40*alive;s.flame.Rate=10*alive
   end
   blowback.Rate=30*on;exhaust.Rate=45*on
   local face=frame*CFrame.Angles(math.pi/2,0,0)
   local muzzleAlpha=if charging then c else on
   rings[1](face,mix(6,3.5,c)*big,.8,muzzleAlpha,t*5,.85)
   rings[2](face,mix(7.5,4.2,c)*big,.3,muzzleAlpha,-t*6,1)
   -- IMPACT.
   local smash=if hit then on*reach else 0
   impact.CFrame=aim(shown,normal)
   local endFace=impact.CFrame*CFrame.Angles(math.pi/2,0,0)
   rings[3](endFace,5*big*(1+.12*math.sin(t*20)),.7,smash,t*3,.85)
   rings[4](endFace,8.5*big,.35,smash,-t*2,1)
   hot.Rate=12*smash;hot.Size=ns(4.5*big*throb)
   plume.Rate=45*smash;spray.Rate=80*smash;chips.Rate=18*smash;scorch.Rate=5*smash;smog.Rate=8*smash
   impactLamp.Brightness=2*smash
   -- SOUND and SHAKE.
   if t>=charge and not hum then
    if chargeSound then chargeSound:Stop() end
    hum=FX.sound(muzzle,1,.42,FX.Sounds.roar,true)
    crackle=FX.sound(impact,0,1.5,FX.Sounds.boom,true)
   end
   if hum then hum.Volume=1.1*on;crackle.Volume=1.4*smash end
   if on>.2 and now-lastRumble>.15 then
    lastRumble=now
    local camera=workspace.CurrentCamera
    if camera then
     local from=part.Position;local f=math.clamp((camera.CFrame.Position-from):Dot(tip)/math.max(tip:Dot(tip),.01),0,1)
     VFX.rumble(from+tip*f,(if strong then .5 else .34)*on,.22)
     if hit then VFX.rumble(from+tip,(if strong then .5 else .32)*on,.22) end
    end
   end
  end
 elseif kind=="Aura" then
  local feet=FX.attachment(root,CFrame.new(0,-5,0))
  emit(feet,"Smoke",7,5,C.plum,{Speed=NumberRange.new(1,3),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(15,15),Transparency=ns(.75,1),LightEmission=.3,Lifetime=NumberRange.new(.6,1)})
  for _,side in ipairs({-1,1}) do
   local shoulder=FX.attachment(root,CFrame.new(side*3,-2,1))
   emit(shoulder,"Aura",6,if phase==2 then 7 else 4,C.violet,{Speed=NumberRange.new(1,3),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(10,10),Lifetime=NumberRange.new(.45,.8),Transparency=ns(.45,1),LightEmission=1,Brightness=1,LockedToPart=true})
  end
  emit(feet,"Embers",.25,if phase==2 then 15 else 8,C.orchid,{Speed=NumberRange.new(2,5),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(30,30),Lifetime=NumberRange.new(.7,1.3)})
  local hands=FX.attachment(root,CFrame.new(0,0,-3))
  emit(hands,"Electric",5,if phase==2 then 3 else 1,C.violet,{Speed=NumberRange.new(0),Transparency=ns(.5,1)})
  local crown,wings
  if phase==2 then
   crown=eclipseCrown(root,part,emit)
   wings=flameWings(root,part,emit)
   -- Eyes lit white inside the hood, trailing violet.
   for _,x in ipairs({-.65,.65}) do
    local eye=FX.attachment(root,CFrame.new(x,5.7,-2.8))
    emit(eye,"Core",.9,12,C.pearl,{LockedToPart=true,Speed=NumberRange.new(0),Lifetime=NumberRange.new(.2),Color=ColorSequence.new(C.pearl),Transparency=ns(0),LightEmission=1,Brightness=4,ZOffset=.5,Orientation=Enum.ParticleOrientation.FacingCamera})
    emit(eye,"Embers",.22,10,C.orchid,{Speed=NumberRange.new(1,3),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(10,10),Lifetime=NumberRange.new(.4,.7),Color=ColorSequence.new(C.pearl,C.violet),Transparency=ns(0,1),LightEmission=1})
   end
  end
  return function()
   local t=workspace:GetServerTimeNow();local alpha=part:FindFirstChild("FXOpacity");local fade=alpha and alpha.Value or 1
   rings[1](CFrame.new(0,-5,0),6,.35,fade*.65,t*.8,.82)
   rings[2](CFrame.new(0,-4.7,0),6.8,.16,fade*.5,-t*.6,.7)
   rings[3](CFrame.new(0,0,0)*CFrame.Angles(.25,0,.15),7,.3,if phase==2 then fade*.65 else 0,t*.6,.65)
   rings[4](CFrame.new(0,3,0)*CFrame.Angles(-.3,0,0),5,.25,if phase==2 then fade*.6 else 0,-t*.7,.65)
   rates(fade)
   if crown then crown(t,fade) end
   if wings then wings(t,fade) end
  end
 end
 return function() end
end
return Choreo
