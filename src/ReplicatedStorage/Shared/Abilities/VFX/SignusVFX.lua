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
local function kick(scope,point,power,frames)
 local e={point=point,power=power,at=workspace:GetServerTimeNow(),frames=frames}
 local tint=scope:add(Instance.new("ColorCorrectionEffect"));tint.Name="SignusImpactFrames";tint.Parent=workspace.CurrentCamera;e.tint=tint
 kicks[e]=true
 local function remove()
  kicks[e]=nil;if tint.Parent then tint:Destroy() end
  if not next(kicks) and bound then
   Run:UnbindFromRenderStep("SignusCameraBefore");Run:UnbindFromRenderStep("SignusCameraAfter");restoreCamera();bound=false
  end
 end
 scope:add(remove);scope:delay(1.2,remove)
 if bound then return end;bound=true
 Run:BindToRenderStep("SignusCameraBefore",Enum.RenderPriority.Camera.Value-3,restoreCamera)
 Run:BindToRenderStep("SignusCameraAfter",Enum.RenderPriority.Last.Value+10,function()
  local camera=workspace.CurrentCamera;if not camera then return end
  local now=workspace:GetServerTimeNow();local strength=0
  local reduced=Players.LocalPlayer:GetAttribute("ReducedMotion")==true
  for effect in pairs(kicks) do
   local age=now-effect.at;local near=math.clamp(1-(camera.CFrame.Position-effect.point).Magnitude/130,0,1)
   strength+=effect.power*near*math.exp(-age*6)
   local bright,contrast,sat=0,0,0
   if effect.frames and not reduced then
    if age<.04 then bright,contrast,sat=.35,.35,-.5
    elseif age>.065 and age<.11 then bright,contrast,sat=-.15,.65,-.8 end
   end
   effect.tint.Brightness=bright*near;effect.tint.Contrast=contrast*near;effect.tint.Saturation=sat*near
  end
  strength=if reduced then 0 else math.min(1.5,strength)
  local t=now%128;local x=math.noise(t*23,1.2)*strength;local y=math.noise(4.1,t*29)*strength
  previousCamera,previousBase=camera,camera.CFrame
  previousApplied=camera.CFrame*CFrame.new(x,y,0)*CFrame.Angles(y*.018,x*.012,0);camera.CFrame=previousApplied
 end)
end
local kinds={}
function kinds.referenceImpact(payload,scope)
 local p=anchor(scope,payload.position+Vector3.yAxis)
 local r=payload.radius or 12
 local a=FX.attachment(p,CFrame.Angles(math.pi/2,0,0))
 FX.burst("GroundPulse",a,1,{Size=ns(r,r*3.5),Lifetime=NumberRange.new(.4),Speed=NumberRange.new(.01),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.zero,Orientation=Enum.ParticleOrientation.VelocityPerpendicular,Color=color(C.orchid),LightEmission=1,Transparency=ns(.05,1)})
 FX.burst("Electric",p,3,{Size=ns(r*1.7,r*2.3),Lifetime=NumberRange.new(.25,.4),Speed=NumberRange.new(0),Color=color(C.violet),LightEmission=1,Transparency=ns(.05,1)})
 flash(p,r*2);sparks(p,55,38,.5,1);smoke(p,7,r,1.2)
 kick(scope,payload.position,1.2,true);FX.sound(p,.7,.7);return 1.8
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
 ring(scope,payload.position-Vector3.yAxis*(payload.drop or 12),80,1.2,C.orchid)
 flash(p,35);fire(p,14,22,1.2);sparks(p,80,42,.7,1.7);pillar(scope,payload.position,60,8,1.2)
 FX.burst("Star",p,24,{Size=ns(1.5,0),Lifetime=NumberRange.new(1,2),Speed=NumberRange.new(8,24),SpreadAngle=Vector2.new(180,180),Color=color(C.pearl,C.teal),LightEmission=1,Transparency=ns(.1,1)})
 kick(scope,payload.position,1.1,true);FX.sound(p,.7,.6);return 2.8
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
