-- Only pack particles, textured beams, light and bounded camera effects.
local Run=game:GetService("RunService")
local Players=game:GetService("Players")
local FX=require(script.Parent.SignusFX)
local C=FX.Colors
local VFX={}
local function ns(a,b) return NumberSequence.new(a,b) end
local function color(a,b) return ColorSequence.new(a,b or a) end
local function anchor(scope,point) return FX.host(scope,point,"SignusBurst") end
local function flash(parent,size)
 FX.burst("Flash",parent,1,{Size=ns(size,0),Lifetime=NumberRange.new(.14),Color=color(C.pearl),Transparency=ns(.12,1),LightEmission=1,Brightness=1.2})
end
local function ring(scope,point,diameter,seconds,col,delay)
 scope:delay(delay or 0,function()
  local p=anchor(scope,point+Vector3.new(0,.25,0));p.CFrame=CFrame.new(p.Position)*CFrame.Angles(math.pi/2,0,0)
  FX.burst("PressureRing",p,1,{Size=ns(2,diameter),Lifetime=NumberRange.new(seconds),Speed=NumberRange.new(.001),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.zero,Orientation=Enum.ParticleOrientation.VelocityPerpendicular,Color=color(col),Transparency=ns(.1,1),LightEmission=.8,Rotation=NumberRange.new(0),RotSpeed=NumberRange.new(0)})
 end)
end
local function sparks(parent,count,speed,size,life)
 FX.burst("Embers",parent,count,{Size=ns(size,0),Lifetime=NumberRange.new(life*.5,life),Speed=NumberRange.new(speed*.4,speed),SpreadAngle=Vector2.new(180,180),Color=color(C.pearl,C.orchid),LightEmission=1,Brightness=1.4,Transparency=ns(.05,1),Drag=2,Acceleration=Vector3.new(0,-12,0)})
end
local function smoke(parent,count,size,life)
 FX.burst("Smoke",parent,count,{Size=ns(size*.4,size),Lifetime=NumberRange.new(life*.6,life),Speed=NumberRange.new(3,12),SpreadAngle=Vector2.new(180,180),Color=color(C.violet,C.plum),LightEmission=.18,Brightness=.8,Transparency=ns(.55,1),Drag=2,Acceleration=Vector3.new(0,5,0)})
end
local function fire(parent,count,size,life)
 FX.burst("DarkFire",parent,count,{Size=ns(size*.5,size),Lifetime=NumberRange.new(life*.7,life),Speed=NumberRange.new(4,13),SpreadAngle=Vector2.new(180,180),Color=color(C.orchid,C.violet),LightEmission=.7,Brightness=1,Transparency=ns(.15,1),Rotation=NumberRange.new(-180,180)})
end
local function light(scope,parent,range,power,duration)
 local l=scope:add(Instance.new("PointLight"));l.Color=C.orchid;l.Range=math.min(60,range);l.Brightness=power;l.Shadows=false;l.Parent=parent
 scope:tween(l,TweenInfo.new(duration),{Brightness=0})
end
local function pillar(scope,point,height,width,seconds)
 local p=anchor(scope,point)
 local b=FX.beam(p,Vector3.zero,Vector3.yAxis*height,width,C.orchid)
 local core=FX.beam(p,Vector3.zero,Vector3.yAxis*height,width*.25,C.pearl,FX.Pack.Lightning.Texture)
 scope:tween(b,TweenInfo.new(seconds),{Width0=0,Width1=0})
 scope:tween(core,TweenInfo.new(seconds),{Width0=0,Width1=0})
 scope:delay(seconds,function() p:Destroy() end)
end
local kicks={}
local bound=false
local previousCamera,previousBase,previousApplied
local function restoreCamera()
 if previousCamera and previousCamera==workspace.CurrentCamera and previousCamera.CFrame==previousApplied then previousCamera.CFrame=previousBase end
 previousCamera,previousBase,previousApplied=nil,nil,nil
end
local function release()
 if not next(kicks) and bound then
  Run:UnbindFromRenderStep("SignusCameraBefore");Run:UnbindFromRenderStep("SignusCameraAfter");restoreCamera();bound=false
 end
end
local function bind()
 if bound then return end;bound=true
 Run:BindToRenderStep("SignusCameraBefore",Enum.RenderPriority.Camera.Value-3,restoreCamera)
 Run:BindToRenderStep("SignusCameraAfter",Enum.RenderPriority.Last.Value+10,function()
  local camera=workspace.CurrentCamera;if not camera then return end
  local now=workspace:GetServerTimeNow();local strength=0
  local reduced=Players.LocalPlayer:GetAttribute("ReducedMotion")==true
  for effect in pairs(kicks) do
   local age=now-effect.at;local near=math.clamp(1-(camera.CFrame.Position-effect.point).Magnitude/130,0,1)
   -- A rumble holds its strength for its short life; a kick decays.
   strength+=effect.power*near*(if effect.steady then 1 else math.exp(-age*6))
   if effect.tint then
    local bright,contrast,sat=0,0,0
    if effect.frames and not reduced then
     if age<.04 then bright,contrast,sat=.35,.35,-.5
     elseif age>.065 and age<.11 then bright,contrast,sat=-.15,.65,-.8 end
    end
    effect.tint.Brightness=bright*near;effect.tint.Contrast=contrast*near;effect.tint.Saturation=sat*near
   end
  end
  strength=if reduced then 0 else math.min(1.5,strength)
  local t=now%128;local x=math.noise(t*23,1.2)*strength;local y=math.noise(4.1,t*29)*strength
  previousCamera,previousBase=camera,camera.CFrame
  previousApplied=camera.CFrame*CFrame.new(x,y,0)*CFrame.Angles(y*.018,x*.012,0);camera.CFrame=previousApplied
 end)
end
local function kick(scope,point,power,frames)
 local e={point=point,power=power,at=workspace:GetServerTimeNow(),frames=frames}
 local tint=scope:add(Instance.new("ColorCorrectionEffect"));tint.Name="SignusImpactFrames";tint.Parent=workspace.CurrentCamera;e.tint=tint
 kicks[e]=true
 local function remove()
  kicks[e]=nil;if tint.Parent then tint:Destroy() end
  release()
 end
 scope:add(remove);scope:delay(1.2,remove)
 bind()
end
-- A steady shake for something sustained, such as a beam that is firing.
-- Callers renew it every few frames; it lapses on its own when they stop.
function VFX.rumble(point,power,seconds)
 local e={point=point,power=power,at=workspace:GetServerTimeNow(),steady=true}
 kicks[e]=true;bind()
 task.delay(seconds or .25,function() kicks[e]=nil;release() end)
end
local kinds={}
function kinds.referenceImpact(payload,scope)
 local p=anchor(scope,payload.position+Vector3.yAxis)
 local r=payload.radius or 12
 local a=FX.attachment(p,CFrame.Angles(math.pi/2,0,0))
 FX.burst("GroundPulse",a,1,{Size=ns(r,r*3.5),Lifetime=NumberRange.new(.4),Speed=NumberRange.new(.01),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.zero,Orientation=Enum.ParticleOrientation.VelocityPerpendicular,Color=color(C.orchid),LightEmission=1,Transparency=ns(.05,1)})
 FX.burst("Electric",p,3,{Size=ns(r*1.7,r*2.3),Lifetime=NumberRange.new(.25,.4),Speed=NumberRange.new(0),Color=color(C.violet),LightEmission=1,Transparency=ns(.05,1)})
 flash(p,r*2);sparks(p,55,38,.5,1);smoke(p,7,r,1.2)
 if payload.phase==2 then
  -- The eclipse in it: a black core swallowed by a pearl rim, and a second wave.
  FX.burst("Core",p,1,{Size=ns(r*.4,r*1.6),Lifetime=NumberRange.new(.45),Color=color(C.black),LightEmission=0,LightInfluence=0,Transparency=ns(0,1),Speed=NumberRange.new(0),ZOffset=1,Orientation=Enum.ParticleOrientation.FacingCamera})
  FX.burst("PressureRing",p,1,{Size=ns(r,r*4.5),Lifetime=NumberRange.new(.5),Speed=NumberRange.new(0),Orientation=Enum.ParticleOrientation.FacingCamera,Color=color(C.pearl),LightEmission=1,Transparency=ns(0,1),Rotation=NumberRange.new(0),RotSpeed=NumberRange.new(0)})
  ring(scope,payload.position,r*5,.7,C.violet,.12)
  FX.burst("Streaks",p,36,{Size=ns(1.4,0),Lifetime=NumberRange.new(.25,.5),Speed=NumberRange.new(50,95),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(70,70),Color=color(C.pearl,C.orchid),LightEmission=1,Transparency=ns(0,1)})
  light(scope,p,36,2.5,.6)
 end
 kick(scope,payload.position,if payload.phase==2 then 1.7 else 1.2,true)
 FX.sound(p,.7,.7);FX.sound(p,if payload.phase==2 then 1.2 else .6,.8,FX.Sounds.thunder);return 1.8
end
-- A part at `point` whose Front looks along `direction`, so an emitter on it
-- set to EmissionDirection Front fires that way.
local function facing(scope,point,direction)
 local p=anchor(scope,point)
 if direction.Magnitude>.01 then p.CFrame=CFrame.lookAt(point,point+direction.Unit) end
 return p
end
local function flat(scope,point)
 local p=anchor(scope,point+Vector3.new(0,.3,0))
 return p,FX.attachment(p,CFrame.Angles(math.pi/2,0,0)) -- Front faces up
end
local function plate(kind,parent,from,to,seconds,col,props)
 local base={Size=ns(from,to),Lifetime=NumberRange.new(seconds),Speed=NumberRange.new(.01),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.zero,Orientation=Enum.ParticleOrientation.VelocityPerpendicular,Color=color(col),LightEmission=1,Transparency=ns(.05,1),Rotation=NumberRange.new(-180,180),RotSpeed=NumberRange.new(0)}
 for k,v in pairs(props or {}) do base[k]=v end
 FX.burst(kind,parent,1,base)
end
-- Worldrend leaving the hands: a blast ring square to the beam, a spray of
-- streaks down its line, and a kick with impact frames.
function kinds.beamFire(payload,scope)
 local dir=if typeof(payload.direction)=="Vector3" then payload.direction else Vector3.zAxis
 local big=if payload.phase==2 then 1.4 else 1
 local p=facing(scope,payload.position,dir)
 flash(p,20*big)
 plate("PressureRing",p,3,30*big,.4,C.pearl)
 scope:delay(.07,function() plate("PressureRing",p,4,44*big,.55,C.orchid) end)
 plate("GroundPulse",p,6,34*big,.32,C.orchid)
 FX.burst("Streaks",p,40,{Size=ns(1.3*big,0),Lifetime=NumberRange.new(.2,.4),Speed=NumberRange.new(70,130),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.new(22,22),Color=color(C.pearl,C.orchid),LightEmission=1,Transparency=ns(0,1)})
 FX.burst("Electric",p,3,{Size=ns(10*big,16*big),Lifetime=NumberRange.new(.2,.3),Speed=NumberRange.new(0),Color=color(C.violet),LightEmission=1,Transparency=ns(.05,1)})
 fire(p,8,10*big,.5);sparks(p,45,40,.6,.7)
 light(scope,p,36,3,.5);kick(scope,payload.position,1.3*big,true)
 FX.sound(p,1.6,.6,FX.Sounds.blast);FX.sound(p,1.1,.62)
 return 1.2
end
-- Each bite the beam takes out of the ground it meets.
function kinds.beamImpact(payload,scope)
 local normal=if typeof(payload.normal)=="Vector3" then payload.normal else Vector3.yAxis
 local big=if payload.phase==2 then 1.3 else 1
 local p=facing(scope,payload.position+normal*.3,normal)
 plate("GroundBurst",p,4,15*big,.35,C.orchid,{LightEmission=.8})
 FX.burst("Rock",p,14,{Size=ns(.9,0),Lifetime=NumberRange.new(.6,1.1),Speed=NumberRange.new(20,42),SpreadAngle=Vector2.new(50,50),EmissionDirection=Enum.NormalId.Front,Acceleration=Vector3.new(0,-70,0),Color=color(C.plum,C.violet),Transparency=ns(.1,1),LightEmission=.15,Rotation=NumberRange.new(-180,180),RotSpeed=NumberRange.new(-200,200)})
 FX.burst("SmokeShock",p,2,{Size=ns(5*big,11*big),Lifetime=NumberRange.new(.5,.8),Speed=NumberRange.new(3,8),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.new(30,30),Color=color(C.violet,C.plum),LightEmission=.3,Transparency=ns(.3,1)})
 flash(p,9*big);kick(scope,payload.position,.55*big,false)
 FX.sound(p,.8,.9+math.random()*.2)
 return 1.2
end
-- Phase two's flight: coming down to recover, and going back up.
function kinds.land(payload,scope)
 local p,a=flat(scope,payload.position)
 plate("DustRing",a,6,30,.55,C.pearl,{LightEmission=.4,Transparency=ns(.2,1)})
 ring(scope,payload.position,26,.5,C.orchid)
 smoke(p,8,9,1.1)
 FX.burst("Rock",p,10,{Size=ns(.7,0),Lifetime=NumberRange.new(.5,.9),Speed=NumberRange.new(14,26),SpreadAngle=Vector2.new(60,60),EmissionDirection=Enum.NormalId.Top,Acceleration=Vector3.new(0,-50,0),Color=color(C.violet,C.plum),Transparency=ns(.15,1)})
 kick(scope,payload.position,.7,false);FX.sound(p,.55,1.05)
 return 1.4
end
function kinds.takeoff(payload,scope)
 local p,a=flat(scope,payload.position)
 plate("DustRing",a,4,26,.5,C.pearl,{LightEmission=.4,Transparency=ns(.2,1)})
 plate("GroundPulse",a,4,22,.35,C.orchid)
 FX.burst("Streaks",p,26,{Size=ns(1.1,0),Lifetime=NumberRange.new(.25,.45),Speed=NumberRange.new(40,75),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(25,25),Color=color(C.pearl,C.violet),LightEmission=1,Transparency=ns(.05,1)})
 fire(p,6,8,.5);smoke(p,6,8,1)
 kick(scope,payload.position,.5,false);FX.sound(p,.8,1.6,FX.Sounds.blast)
 return 1.2
end
-- The eclipse crown igniting behind the hood at the climax of Totality.
function kinds.crown(payload,scope)
 local p=anchor(scope,payload.position)
 flash(p,44)
 FX.burst("Core",p,1,{Size=ns(2,26),Lifetime=NumberRange.new(.8),Color=color(C.black),LightEmission=0,LightInfluence=0,Transparency=ns(0,1),Speed=NumberRange.new(0),ZOffset=1,Orientation=Enum.ParticleOrientation.FacingCamera})
 FX.burst("Aura",p,3,{Size=ns(6,50),Lifetime=NumberRange.new(1),Color=color(C.orchid),LightEmission=1,Transparency=ns(.05,1),Speed=NumberRange.new(0),Orientation=Enum.ParticleOrientation.FacingCamera})
 for i,size in ipairs({60,90,120}) do
  scope:delay((i-1)*.12,function()
   FX.burst("PressureRing",p,1,{Size=ns(4,size),Lifetime=NumberRange.new(.6+i*.15),Speed=NumberRange.new(0),Orientation=Enum.ParticleOrientation.FacingCamera,Color=color(if i==2 then C.orchid else C.pearl),LightEmission=1,Transparency=ns(0,1),Rotation=NumberRange.new(0),RotSpeed=NumberRange.new(0)})
  end)
 end
 FX.burst("Star",p,40,{Size=ns(2.4,0),Lifetime=NumberRange.new(.8,1.6),Speed=NumberRange.new(25,60),SpreadAngle=Vector2.new(180,180),Color=color(C.pearl,C.orchid),LightEmission=1,Transparency=ns(.05,1),Drag=1.5})
 FX.burst("Streaks",p,60,{Size=ns(1.8,0),Lifetime=NumberRange.new(.3,.6),Speed=NumberRange.new(70,140),SpreadAngle=Vector2.new(180,180),Color=color(C.pearl,C.violet),LightEmission=1,Transparency=ns(0,1)})
 light(scope,p,50,4,1.2);kick(scope,payload.position,2,true)
 FX.sound(p,2,.7,FX.Sounds.thunder);FX.sound(p,1,.45)
 return 2.5
end
function kinds.flare(payload,scope)
 local p=anchor(scope,payload.position);flash(p,(payload.radius or 3)*2)
 FX.burst("Star",p,1,{Size=ns((payload.radius or 3)*2,0),Lifetime=NumberRange.new(.3),Color=color(payload.color or C.orchid),LightEmission=1,Transparency=ns(.1,1)})
 return .5
end
function kinds.cast(payload,scope)
 local p=anchor(scope,payload.position);flash(p,9);fire(p,4,7,.45);sparks(p,22,24,.5,.6);light(scope,p,22,2,.5)
 return 1
end
function kinds.shatter(payload,scope)
 local p=anchor(scope,payload.position);flash(p,14);fire(p,6,9,.5);sparks(p,34,38,.6,.7)
 FX.burst("Slash",p,2,{Size=ns(8,13),Lifetime=NumberRange.new(.4),Speed=NumberRange.new(.001),Color=color(C.orchid),LightEmission=.8,Rotation=NumberRange.new(-180,180),Transparency=ns(.1,1)})
 light(scope,p,22,2,.4);return 1.1
end
function kinds.lock(payload,scope)
 local p=anchor(scope,payload.position+Vector3.new(0,.3,0));ring(scope,payload.position,(payload.radius or 7)*2,.35,C.pearl);sparks(p,24,10,.4,.65)
 return .9
end
function kinds.impact(payload,scope)
 local r=payload.radius or 7;local p=anchor(scope,payload.position+Vector3.new(0,1,0))
 flash(p,r*3);ring(scope,payload.position,r*4.5,.65,C.pearl);ring(scope,payload.position,r*3.5,.8,C.orchid,.08)
 pillar(scope,payload.position,50,10,.5);fire(p,12,r*2,.8);sparks(p,70,55,.65,1);smoke(p,14,r*2,1.8)
 FX.burst("Rock",p,28,{Size=ns(.8,0),Lifetime=NumberRange.new(.5,1.2),Speed=NumberRange.new(18,38),SpreadAngle=Vector2.new(80,180),EmissionDirection=Enum.NormalId.Top,Acceleration=Vector3.new(0,-50,0),Color=color(C.violet,C.plum),Transparency=ns(.1,1),LightEmission=.2})
 light(scope,p,48,4,.8);kick(scope,payload.position,1.4,true);FX.sound(p,.6,.85)
 return 2.2
end
function kinds.erupt(payload,scope)
 if type(payload.positions)~="table" then return 0 end
 for i,point in ipairs(payload.positions) do
  if i>24 then break end
  local delay=if payload.delays then payload.delays[i] or 0 else 0
  scope:delay(delay,function()
   local p=anchor(scope,point+Vector3.new(0,.4,0))
   pillar(scope,point,15,3.5,.4);fire(p,3,7,.6);sparks(p,12,28,.4,.7);smoke(p,3,6,1.2)
   FX.burst("Rock",p,6,{Size=ns(.55,0),Lifetime=NumberRange.new(.5,.9),Speed=NumberRange.new(12,24),SpreadAngle=Vector2.new(45,45),EmissionDirection=Enum.NormalId.Top,Acceleration=Vector3.new(0,-40,0),Color=color(C.violet,C.plum),Transparency=ns(.15,1)})
  end)
 end
 kick(scope,payload.position,.8,false);return 3
end
function kinds.step(payload,scope)
 local p=anchor(scope,payload.position)
 FX.burst("Echo",p,2,{Size=ns(12,18),Lifetime=NumberRange.new(.45),Color=color(C.orchid,C.violet),LightEmission=.65,Transparency=ns(.1,1)})
 FX.burst("Slash",p,2,{Size=ns(10,20),Lifetime=NumberRange.new(.45),Color=color(C.pearl,C.violet),LightEmission=.7,Transparency=ns(.25,1)})
 sparks(p,30,20,.4,.7);return 1
end
function kinds.lunge(payload,scope)
 local p=anchor(scope,payload.position);flash(p,20);fire(p,8,13,.6);sparks(p,55,45,.6,.9)
 ring(scope,payload.position,28,.55,C.orchid);kick(scope,payload.position,.9,false);return 1.5
end
local function eclipseBurst(payload,scope,death)
 local point=payload.position;local r=payload.radius or 26;local p=anchor(scope,point)
 FX.burst("Aura",p,2,{Size=ns(4,r*2),Lifetime=NumberRange.new(.65),Color=color(C.orchid),LightEmission=.8,Transparency=ns(.05,1),Speed=NumberRange.new(0),Orientation=Enum.ParticleOrientation.FacingCamera})
 FX.burst("Core",p,1,{Size=ns(3,r*1.4),Lifetime=NumberRange.new(.5),Color=color(C.black),LightEmission=0,LightInfluence=0,Transparency=ns(0,1),Speed=NumberRange.new(0),ZOffset=.6,Orientation=Enum.ParticleOrientation.FacingCamera})
 ring(scope,point,r*4,.85,C.pearl,.06);ring(scope,point,r*3.6,1.1,C.orchid,.15);pillar(scope,point,120,18,.8)
 flash(p,r*2);fire(p,18,28,1.1);sparks(p,100,75,.8,1.4);smoke(p,22,24,2.4)
 FX.burst("Star",p,14,{Size=ns(2,0),Lifetime=NumberRange.new(.7,1.5),Speed=NumberRange.new(15,35),SpreadAngle=Vector2.new(180,180),Color=color(C.gold,C.teal),LightEmission=1,Transparency=ns(.1,1)})
 light(scope,p,60,6,1.2);kick(scope,point,2,true);FX.sound(p,.85,if death then .6 else .75)
 return 3.2
end
function kinds.nova(payload,scope) return eclipseBurst(payload,scope,false) end
function kinds.death(payload,scope) return eclipseBurst(payload,scope,true) end
function kinds.totality(payload,scope)
 local p=anchor(scope,payload.position)
 local ground=payload.position-Vector3.yAxis*(payload.drop or 12)
 ring(scope,ground,80,1.2,C.orchid);ring(scope,ground,130,1.6,C.pearl,.15);ring(scope,ground,170,2,C.violet,.3)
 local _,a=flat(scope,ground)
 plate("DustRing",a,10,90,1.1,C.pearl,{LightEmission=.4,Transparency=ns(.15,1)})
 flash(p,50);fire(p,18,26,1.3);sparks(p,110,55,.8,1.8);pillar(scope,ground,180,16,1.4);pillar(scope,ground,180,6,2)
 FX.burst("Star",p,36,{Size=ns(2,0),Lifetime=NumberRange.new(1,2),Speed=NumberRange.new(10,30),SpreadAngle=Vector2.new(180,180),Color=color(C.pearl,C.teal),LightEmission=1,Transparency=ns(.1,1)})
 FX.burst("Streaks",p,60,{Size=ns(1.6,0),Lifetime=NumberRange.new(.4,.7),Speed=NumberRange.new(60,120),SpreadAngle=Vector2.new(180,180),Color=color(C.pearl,C.orchid),LightEmission=1,Transparency=ns(0,1)})
 kick(scope,payload.position,1.8,true);FX.sound(p,.8,.5);FX.sound(p,2,.85,FX.Sounds.thunder);return 2.8
end
function kinds.harvest(payload,scope)
 local seconds=math.clamp(payload.seconds or 1,.2,2);local moving={}
 for i,sample in ipairs(payload.blocks or {}) do
  if i>24 then break end
  local p=anchor(scope,sample.position)
  local e=FX.emitter("Rock",p,{Rate=12,Size=ns(.75,0),Lifetime=NumberRange.new(.2,.4),Speed=NumberRange.new(0,2),Color=color(C.plum,C.violet),Transparency=ns(.1,1),LightEmission=.25});e.Enabled=true
  local energy=FX.emitter("Embers",p,{Rate=16,Size=ns(.3,0),Lifetime=NumberRange.new(.25,.5),Speed=NumberRange.new(0,2),Color=color(C.pearl,C.violet),Transparency=ns(.1,1),LightEmission=1});energy.Enabled=true
  table.insert(moving,{p=p,from=sample.position,e=e,energy=energy})
 end
 local began=payload.startedAt or workspace:GetServerTimeNow()
 scope:add(Run.Heartbeat:Connect(function()
  local t=math.clamp((workspace:GetServerTimeNow()-began)/seconds,0,1)
  for _,m in ipairs(moving) do
   m.p.Position=m.from:Lerp(payload.position,t*t)+Vector3.yAxis*math.sin(t*math.pi)*7
   if t>=1 then m.e.Enabled=false;m.energy.Enabled=false end
  end
 end))
 return seconds+.7
end
function VFX.preload() FX.preload() end
function VFX.play(payload,scope)
 local draw=kinds[payload.kind];if not draw then return 0 end
 if workspace:GetServerTimeNow()-(payload.startedAt or workspace:GetServerTimeNow())>4 then return 0 end
 return draw(payload,scope) or 1
end
return VFX
