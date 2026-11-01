-- Signus choreography. Server carriers remain the only authority for aim and time.
local FX=require(script.Parent.SignusFX)
local A=require(script.Parent.SignusAssemblies)
local VFX=require(script.Parent.SignusVFX)
local C=FX.Colors
local Choreo={}
local TAU=math.pi*2
local function ns(a,b)return NumberSequence.new(a,b or a)end
local function smooth(t)t=math.clamp(t,0,1);return t*t*(3-2*t)end
local function mix(a,b,t)return a+(b-a)*math.clamp(t,0,1)end
local function aim(p,d)
 d=if d.Magnitude>.001 then d.Unit else Vector3.yAxis
 return CFrame.lookAt(p,p+d,if math.abs(d.Y)>.98 then Vector3.zAxis else Vector3.yAxis)
end
-- Existing beam ribbon construction: retained with its curved silhouette and textures.
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
  for i,v in parts do
   local a=(i-1)*span+spin;local b=a+span
   local p0=Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius)
   local p1=Vector3.new(math.cos(b)*radius,0,math.sin(b)*radius)
   local t0=Vector3.new(-math.sin(a),0,math.cos(a));local t1=Vector3.new(-math.sin(b),0,math.cos(b))
   v.a.CFrame=frame*CFrame.fromMatrix(p0,t0,Vector3.yAxis,t0:Cross(Vector3.yAxis))
   v.b.CFrame=frame*CFrame.fromMatrix(p1,t1,Vector3.yAxis,t1:Cross(Vector3.yAxis))
   v.beam.CurveSize0=4/3*math.tan(span/4)*radius;v.beam.CurveSize1=v.beam.CurveSize0
   v.beam.Width0=w*1.8;v.beam.Width1=w*1.3
   v.beam.Enabled=opacity>.01;v.beam.Transparency=ns(1-opacity)
  end
 end
end
local function lineWith(parent,col,texture,dark)
 local b,a0,a1=FX.beam(parent,Vector3.zero,Vector3.zero,1,col,texture or FX.Pack.JetBeam.Texture)
 b.TextureSpeed=4;b.TextureLength=8;b.Segments=16;b.LightEmission=if dark then 0 else 1
 return function(from,to,width,opacity)
  a0.Position=from;a1.Position=to;b.Width0=width;b.Width1=width*.65
  b.Enabled=opacity>.01;b.Transparency=ns(1-opacity)
 end,b
end
local function line(parent,col,texture,dark)return (lineWith(parent,col,texture,dark))end
local function sigils(parent,frame,radius,scope)
 local a=FX.attachment(parent,frame)
 -- Preserve the established pair of counter-rotating ornate/star spell circles.
 local outer=FX.circle(a,"SigilOrnate",radius*2.6,C.violet,{RotSpeed=NumberRange.new(-25),Brightness=1.2})
 local inner=FX.circle(a,"SigilStar",radius*1.9,C.orchid,{RotSpeed=NumberRange.new(45),Brightness=1.2})
 return function(alpha)
  outer.Enabled=alpha>.02;inner.Enabled=alpha>.02
  -- Alpha rather than extra layers is what makes a warning intensify.
  outer.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.2,1-.75*alpha),NumberSequenceKeypoint.new(.75,1-.75*alpha),NumberSequenceKeypoint.new(1,1)})
  inner.Transparency=outer.Transparency
 end
end
function Choreo.mount(part,scope)
 local root=scope:add(FX.attachment(part))
 local kind=part:GetAttribute("SignusKind")
 local phase=part:GetAttribute("Phase") or 1
 local radius=part:GetAttribute("Radius") or 12
 local target=part:GetAttribute("Target") or part.Position
 local offset=target-part.Position
 local began=part:GetAttribute("StartedAt") or workspace:GetServerTimeNow()
 local duration=part:GetAttribute("Duration") or 5
 local strong=phase==2
 local function age()return workspace:GetServerTimeNow()-began end
 local function alpha()
  local v=part:FindFirstChild("FXOpacity");return math.clamp(v and v.Value or 1,0,1)
 end
 if kind=="SpiralCast" or kind=="Ascension" then
  local circle=sigils(root,CFrame.new(0,.35,0)*CFrame.Angles(math.pi/2,0,0),radius,scope)
  local s=radius/12*.7
  local storm=A.mount(scope,"Storm",CFrame.new(part.Position+Vector3.yAxis*8*s),s)
  local swirl=A.mount(scope,"Swirl",CFrame.new(part.Position+Vector3.yAxis*.6),radius*2/125,3)
  local upper=A.mount(scope,"Swirl",part.CFrame,radius*1.25/125,8)
  local spineScale=(strong and 1.8 or 1.2)*radius/12
  local spine=A.mount(scope,"Column",CFrame.new(part.Position+Vector3.yAxis*20*spineScale)*CFrame.Angles(0,0,math.pi/2),spineScale)
  local ascending=kind=="Ascension"
  local warning=part:GetAttribute("Warning") or 1.25
  local strike=part:GetAttribute("StrikeAt") or 2.35
  return function(near)
   local t=age();local fade=(1-smooth((t-duration+.6)/.6))*(near==false and 0 or 1)
   local release=smooth((t-warning)/.22)
   local intensity=(.06+.28*release)*fade
   circle(fade*(.6+.4*smooth(t/warning)))
   -- The authored portal layers climb from their original lower attachment.
   storm:set(CFrame.new(part.Position+Vector3.yAxis*8*s),intensity,true)
   swirl:set(CFrame.new(part.Position+Vector3.yAxis*(.6+release*2))*CFrame.Angles(0,t*(ascending and -1.8 or -2.8),0),fade*(.15+.6*release),false)
   upper:set(CFrame.new(part.Position+Vector3.yAxis*(6+release*(strong and 30 or 18)))*CFrame.Angles(.35,t*3.5,.12),release*fade*.65,false)
   spine:set(nil,release*fade*.42*(1-smooth((t-strike-.65)/.4)),true)
  end
 elseif kind=="LanceCast" then
  local warning=part:GetAttribute("Warning") or 1.3
  local travel=part:GetAttribute("Travel") or .65
  local strike=part:GetAttribute("StrikeAt") or 2.5595
  local circle=sigils(root,CFrame.new(offset+Vector3.yAxis*.3)*CFrame.Angles(math.pi/2,0,0),radius,scope)
  local orb=A.mount(scope,"Orb",part.CFrame,.35)
  local colScale=if strong then 1.25 else 1
  local column=A.mount(scope,"Column",CFrame.new(target+Vector3.yAxis*20*colScale)*CFrame.Angles(0,0,math.pi/2),colScale)
  local shafts={line(root,C.violet,FX.Pack.JetBeam.Texture),line(root,C.orchid),line(root,C.pearl,FX.Pack.Lightning.Texture)}
  local draw,b=lineWith(root,C.pearl,FX.Pack.BoltBeamWide.Texture)
  b.TextureMode=Enum.TextureMode.Stretch;b.TextureLength=1;b.TextureSpeed=4;b.Brightness=3;b.ZOffset=.3
  table.insert(shafts,draw)
  local void=strong and line(root,C.black,nil,true) or nil
  return function(near)
   local t=age();local visible=near==false and 0 or 1
   local fly=smooth((t-warning)/travel)
   local point=part.Position:Lerp(target+Vector3.yAxis*2,fly)+Vector3.yAxis*math.sin(fly*math.pi)*5
   local active=smooth((t-strike)/.08)*(1-smooth((t-strike-.7)/.4))*visible
   local fade=(1-smooth((t-duration+.65)/.65))*visible
   circle(fade)
   orb:set(CFrame.new(point),fade*(1-smooth((t-strike)/.12))*.7,true)
   column:set(nil,active*.4,true)
   local top=offset+Vector3.yAxis*((strong and 140 or 95)*smooth((t-strike)/.12))
   for i,shaft in shafts do shaft(offset,top,({13,7,2.3,6})[i]*(strong and 1.3 or 1),active*({.65,.9,1,.9})[i]) end
   if void then void(offset,top,2.4,active) end
  end
 elseif kind=="RiftBeam" then
  -- Preserve Worldrend's layered beam, lightning helix, and opening spell gates.
  local charge=part:GetAttribute("Charge") or 1.5
  local stop=duration-.35
  local big=strong and 1.4 or 1
  local gates={}
  for i,spec in {{d=2,size=9,kind="SigilStar",spin=90,col=C.pearl},{d=5.5,size=14,kind="SigilOrnate",spin=-60,col=C.orchid},{d=9.5,size=19,kind="SigilStar",spin=45,col=C.orchid},{d=14,size=11,kind="SigilOrnate",spin=-120,col=C.pearl}} do
   if i==4 and not strong then break end
   local a=FX.attachment(root)
   table.insert(gates,{a=a,e=FX.circle(a,spec.kind,spec.size*big,spec.col,{RotSpeed=NumberRange.new(spec.spin),Brightness=2}),spec=spec})
  end
  local layers={}
  local function layer(col,tail,texture,width,opacity,speed,light,z)
   local draw,b=lineWith(root,col,texture,light==0)
   b.Color=ColorSequence.new(col,tail);b.TextureSpeed=speed;b.TextureLength=14;b.Segments=24;b.ZOffset=z or 0;b.LightEmission=light or 1
   table.insert(layers,{draw=draw,b=b,width=width*big,opacity=opacity})
  end
  layer(C.violet,C.plum,FX.Pack.JetBeam.Texture,14,.6,6,.5)
  layer(C.violet,C.violet,"",9,.28,0)
  layer(C.orchid,C.violet,"",5,.6,0,1,.1)
  layer(C.pearl,C.orchid,"",strong and 2.9 or 2.3,.95,0,1,.2)
  layer(C.pearl,C.orchid,FX.Pack.Lightning.Texture,3.8,.8,16,1,.25)
  if strong then layer(C.black,C.black,"",1.9,1,0,0,.45) end
  local helix={}
  for h=1,2 do for i=1,12 do table.insert(helix,{draw=line(root,h==1 and C.orchid or C.pearl,FX.Pack.JetBeam.Texture),h=h,i=i}) end end
  local rings={ribbon(root,C.orchid,.8),ribbon(root,C.pearl,.3),ribbon(root,C.orchid,.6)}
  local orb=A.mount(scope,"Orb",part.CFrame,.45*big)
  local endColumn=A.mount(scope,"Column",CFrame.new(target),.22*big)
  local sight=line(root,C.orchid,FX.Pack.Lightning.Texture)
  local lamp=Instance.new("PointLight");lamp.Color=C.orchid;lamp.Range=18;lamp.Shadows=false;lamp.Parent=root
  local hum=FX.sound(part,.35,.42,FX.Sounds.roar,true);scope:add(function()hum:Stop();hum:Destroy()end)
  local shown=offset;local last=os.clock();local lastRumble=0
  return function(near)
   local now=os.clock();local dt=math.min(now-last,.1);last=now
   local t=age();local visible=near==false and 0 or 1
   local want=(part:GetAttribute("Target") or target)-part.Position
   shown=shown:Lerp(want,math.clamp(dt*24,0,1))
   local hit=part:GetAttribute("Hit")==true
   local normal=part:GetAttribute("Normal") or Vector3.yAxis
   local dir=shown.Magnitude>.1 and shown.Unit or Vector3.zAxis
   local frame=aim(Vector3.zero,dir)
   local charging=t<charge;local c=smooth(t/charge)
   local on=smooth((t-charge)/.08)*(1-smooth((t-stop)/.3))*visible
   local tip=shown*smooth((t-charge)/.14)
   for _,g in gates do
    local open=(charging and smooth((c-.15*(g.spec.d/9))/.45) or on)*visible
    g.a.CFrame=frame*CFrame.new(0,0,-g.spec.d*big)
    g.e.Size=ns(g.spec.size*big*math.max(open,.01)*(charging and 1 or 1.15+.05*math.sin(t*20)))
    g.e.Enabled=open>.02
   end
   sight(Vector3.zero,shown,.35*big,charging and .3*visible or 0)
   local throb=1+.12*math.sin(t*38)+.06*math.sin(t*91)
   for _,l in layers do
    local w=l.width*throb*on;local o=l.opacity*on
    l.draw(Vector3.zero,tip,w,o);l.b.Width1=w*(hit and .9 or .3)
    l.b.Transparency=hit and ns(1-o) or NumberSequence.new({NumberSequenceKeypoint.new(0,1-o),NumberSequenceKeypoint.new(.7,1-o),NumberSequenceKeypoint.new(1,1)})
   end
   for _,v in helix do
    local spin=t*(v.h==1 and 11 or -9)+(v.h-1)*math.pi
    local function at(f)
     local a=f*TAU*2.5+spin;local r=(1.4+f*1.6)*big
     return frame*Vector3.new(math.cos(a)*r,math.sin(a)*r,-f*tip.Magnitude)
    end
    v.draw(at((v.i-1)/12),at(v.i/12),.45*big,on*.65)
   end
   local muzzleAlpha=(charging and c or on)*visible
   rings[1](frame*CFrame.Angles(math.pi/2,0,0),mix(6,3.5,c)*big,.8,muzzleAlpha,t*5,.85)
   rings[2](frame*CFrame.Angles(math.pi/2,0,0),mix(7.5,4.2,c)*big,.3,muzzleAlpha,-t*6,1)
   local endFrame=aim(shown,normal)
   rings[3](endFrame*CFrame.Angles(math.pi/2,0,0),5*big,.7,hit and on or 0,t*3,.85)
   orb:set(CFrame.new(part.Position),muzzleAlpha*.6,true)
   endColumn:set(CFrame.new(part.Position+shown+normal*4.4*big)*CFrame.Angles(0,0,math.pi/2),hit and on*.35 or 0,true)
   lamp.Brightness=charging and c*.7*visible or on
   hum.Volume=on*.5+(charging and c*.25*visible or 0)
   if on>.2 and now-lastRumble>.2 and near~=false then lastRumble=now;VFX.rumble(part.Position+tip*.5,.15*on,.22) end
  end
 elseif kind=="CrescentLunge" then
  local scale=radius*2/12*1.3
  local blade=A.mount(scope,"LungeBlade",part.CFrame,scale)
  local wake=A.mount(scope,"LungeWake",part.CFrame,.23*(strong and 1.15 or 1))
  local edgeAnchor=FX.attachment(root,CFrame.new(0,2.5,0))
  local edge=FX.emitter("CrescentEdge",edgeAnchor,{Rate=10,Lifetime=NumberRange.new(.2),Speed=NumberRange.new(.01),EmissionDirection=Enum.NormalId.Front,LockedToPart=true,Color=ColorSequence.new(C.orchid),Brightness=1.5,Rotation=NumberRange.new(0),Transparency=NumberSequence.new(.12,1)})
  local sight=line(root,C.orchid,FX.Pack.Lightning.Texture)
  local trail=Instance.new("Trail")
  trail.Name="CrescentWake";trail.Attachment0=FX.attachment(root,CFrame.new(0,-2,0));trail.Attachment1=FX.attachment(root,CFrame.new(0,2,0))
  trail.Texture=FX.Pack.JetBeam.Texture;trail.Color=ColorSequence.new(C.orchid,C.violet)
  trail.Lifetime=.18;trail.FaceCamera=true;trail.MinLength=.25;trail.LightEmission=1;trail.Brightness=1.3
  trail.Transparency=NumberSequence.new(.15,1);trail.WidthScale=NumberSequence.new(1,0)
  trail.Enabled=false;trail.Parent=root
  local released=false
  return function(near)
   local stage=part:GetAttribute("Stage") or "Charge"
   local visible=near==false and 0 or 1
   local charge=part:GetAttribute("Charge") or .6
   local a=smooth(age()/charge)
   local rushAt=part:GetAttribute("RushAt")
   local travel=part:GetAttribute("Travel") or .4
   local rush=if rushAt then math.clamp((workspace:GetServerTimeNow()-rushAt)/travel,0,1) else 0
   local decayAt=part:GetAttribute("DecayAt")
   local decay=if decayAt then 1-smooth((workspace:GetServerTimeNow()-decayAt)/.4) else 1
   local charging=stage=="Charge"
   trail.Enabled=stage=="Rush" and visible>0
   local locked=age()>=charge-(part:GetAttribute("Lock") or .22)
   local opacity=visible*decay*(if charging then (if locked then .95 else .15+.65*a) else 1)
   -- One curved authored blade, swept once. No continuously spinning discs.
   local roll=if charging then mix(-.6,-.25,a) else mix(-.25,.55,smooth(rush))
   edgeAnchor.CFrame=CFrame.new(0,2.5,0)*CFrame.Angles(0,0,roll)
   edge.Size=ns(radius*2.6*(if charging then .3+.7*a else 1))
   edge.Enabled=visible>0 and stage~="Decay"
   local frame=(part.CFrame+Vector3.yAxis*2.5)*CFrame.Angles(0,0,roll)*CFrame.Angles(0,math.pi/2,0)
   if blade.model then blade.model:ScaleTo(scale*(if charging then .3+.7*a else 1)) end
   blade:set(frame,opacity,stage=="Rush")
   wake:set(part.CFrame*CFrame.Angles(math.pi/2,0,0),visible*(if stage=="Rush" then .8 else 0),stage=="Rush")
   local to=(part:GetAttribute("Target") or part.Position)-part.Position
   local localTo=part.CFrame:VectorToObjectSpace(to)
   sight(Vector3.zero,localTo,.22,charging and visible*(if locked then .65 else .32*a) or 0)
   if stage=="Rush" and not released then
    released=true;blade:burst(1);wake:burst(.65)
    FX.sound(part,.45,1.2,FX.Sounds.wind)
   end
  end
 elseif kind=="Aura" then
  local circles=sigils(root,CFrame.new(0,-5.6,0)*CFrame.Angles(math.pi/2,0,0),strong and 9 or 6.5,scope)
  local shroud=A.mount(scope,"Column",part.CFrame,.16)
  local eclipse=strong and A.mount(scope,"EclipseCore",part.CFrame,3.1) or nil
  local corona=strong and A.mount(scope,"EclipseCorona",part.CFrame,2.4) or nil
  local sunAnchor=strong and FX.attachment(root) or nil
  local rim=sunAnchor and FX.circle(sunAnchor,"CoronaRing",24,C.orchid,{Orientation=Enum.ParticleOrientation.FacingCamera,RotSpeed=NumberRange.new(-12),Brightness=1.4,Rate=1.8,ZOffset=-.5}) or nil
  return function(near)
   local a=alpha()*(near==false and 0 or 1);local t=workspace:GetServerTimeNow()
   circles(a*.75)
   shroud:set(part.CFrame*CFrame.new(0,0,2)*CFrame.Angles(0,0,math.pi/2),a*.18,true)
   if eclipse then
    local frame=part.CFrame*CFrame.new(0,7.5,14)
    eclipse:set(frame,math.min(a*2,1),true)
    corona:set(frame,a*.55,true)
    sunAnchor.CFrame=CFrame.new(0,7.5,14)
    rim.Enabled=a>.02;rim.Size=ns(24+.45*math.sin(t*1.8))
   end
  end
 elseif kind=="Sigil" or kind=="Ring" or kind=="Disc" then
  local size=math.max(part.Size.X,part.Size.Y,part.Size.Z)
  local frame=kind=="Disc" and CFrame.Angles(0,-math.pi/2,0) or CFrame.identity
  local a=FX.attachment(root,frame)
  local outer=FX.circle(a,kind=="Ring" and "CoronaRing" or "SigilOrnate",size*(kind=="Sigil" and 1.45 or 1.05),C.violet,{RotSpeed=NumberRange.new(-14),Brightness=1.3})
  local inner=kind=="Sigil" and FX.circle(a,"SigilStar",size*1.05,C.orchid,{RotSpeed=NumberRange.new(26),Brightness=1.3}) or nil
  return function(near)
   local a=alpha()*(near==false and 0 or 1)
   local extent=math.max(part.Size.X,part.Size.Y,part.Size.Z)
   outer.Size=ns(extent*(kind=="Sigil" and 1.45 or 1.05))
   if inner then inner.Size=ns(extent*1.05) end
   outer.Enabled=a>.02;outer.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.2,1-.85*a),NumberSequenceKeypoint.new(.75,1-.85*a),NumberSequenceKeypoint.new(1,1)})
   if inner then inner.Enabled=outer.Enabled;inner.Transparency=outer.Transparency end
  end
 elseif kind=="Pillar" or kind=="Seam" or kind=="Spoke" then
  local draw,b=lineWith(root,C.orchid,FX.Pack.Beam.Texture)
  local core=line(root,C.pearl,FX.Pack.BoltBeam.Texture)
  return function(near)
   local a=alpha()*(near==false and 0 or 1)
   local axis=kind=="Pillar" and Vector3.yAxis*part.Size.Y or kind=="Seam" and Vector3.zAxis*part.Size.Z or Vector3.xAxis*part.Size.X
   local w=kind=="Pillar" and math.max(1,part.Size.X*2.5) or .7
   draw(-axis*.5,axis*.5,w,a*.6);core(-axis*.5,axis*.5,w*.35,a*.9)
  end
 else
  local name=kind=="Crescent" and "Slash" or kind=="Mark" and "Swirl" or "Orb"
  local extent=math.max(part.Size.X,part.Size.Y,part.Size.Z)
  local scale=if name=="Slash" then math.clamp(extent/28,.2,1.1) elseif name=="Swirl" then math.clamp(extent/125,.02,.15) else (kind=="Halo" and .16 or kind=="Eyes" and .12 or kind=="Shard" and .35 or math.clamp(extent/12,.18,1))
  local assembly=A.mount(scope,name,part.CFrame,scale)
  return function(near)
   local cf=part.CFrame
   if name=="Slash" then cf*=CFrame.Angles(math.pi/2,0,0)
   elseif kind=="Eclipse" or kind=="Void" then cf*=CFrame.Angles(0,workspace:GetServerTimeNow()*.3,0) end
   assembly:set(cf,alpha()*(near==false and 0 or 1)*(kind=="Mark" and .35 or 1),name=="Orb")
  end
 end
end
return Choreo
