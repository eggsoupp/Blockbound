-- Short, scoped punctuation from complete library assemblies. No impact-frame planes.
local Run=game:GetService("RunService")
local Players=game:GetService("Players")
local FX=require(script.Parent.SignusFX)
local A=require(script.Parent.SignusAssemblies)
local Pack=require(script.Parent.PackAssembly)
local VFX={}
-- Umbral Thunder's bolts: white-hot cores edged in the phase's purple.
local BOLT={
 {deep=Color3.fromRGB(140,40,240),main=Color3.fromRGB(196,140,255),hot=Color3.fromRGB(245,235,255)},
 {deep=Color3.fromRGB(80,16,190),main=Color3.fromRGB(160,90,250),hot=Color3.fromRGB(230,210,255)},
}
local active={}
local lastImpact={}
local lastMajor=-math.huge
local lastBeam=-math.huge
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
  strength=if reduced then 0 else math.min(.4,strength)
  local t=now%128;local x=math.noise(t*23,1.2)*strength;local y=math.noise(4.1,t*29)*strength
  previousCamera,previousBase=camera,camera.CFrame
  previousApplied=camera.CFrame*CFrame.new(x,y,0)*CFrame.Angles(y*.018,x*.012,0);camera.CFrame=previousApplied
 end)
end
-- A hard kick with impact frames (a flash, then a contrast slam), for the
-- two releases that end a phase: Totality's ignition and the Black Sun.
local function kickFrames(point,power,scope)
 local tint=scope:add(Instance.new("ColorCorrectionEffect"));tint.Name="SignusImpactFrames"
 tint.Parent=game:GetService("Lighting")
 local e={point=point,power=power,at=workspace:GetServerTimeNow(),tint=tint,frames=true}
 kicks[e]=true;bind()
 task.delay(.45,function() kicks[e]=nil;release() end)
end
VFX.kickFrames=kickFrames
-- A steady shake for something sustained, such as a beam that is firing.
-- Callers renew it every few frames; it lapses on its own when they stop.
function VFX.rumble(point,power,seconds)
 local e={point=point,power=power,at=workspace:GetServerTimeNow(),steady=true}
 kicks[e]=true;bind()
 task.delay(seconds or .25,function() kicks[e]=nil;release() end)
end

function VFX.cancelBursts()
 local cancel={}
 for scope,kind in active do if kind~="death" then table.insert(cancel,scope) end end
 for _,scope in cancel do scope:destroy() end
 table.clear(lastImpact)
 lastBeam=-math.huge
 table.clear(kicks);release()
end
function VFX.preload()
 A.preload()
 -- Preload only the retained beam/sigil textures; obsolete extracted sheets are unused.
 task.spawn(function()
  local assets={}
  for _,name in {"Beam","JetBeam","Lightning","BoltBeam","BoltBeamWide","SigilOrnate","SigilStar","CoronaRing","CrescentEdge"} do
   if FX.Pack[name] then table.insert(assets,FX.Pack[name].Texture) end
  end
  pcall(function()game:GetService("ContentProvider"):PreloadAsync(assets)end)
 end)
end
function VFX.play(payload,scope)
 local now=workspace:GetServerTimeNow()
 if now-(payload.startedAt or now)>1.2 then return 0 end
 local kind=payload.kind
 if kind=="crown" and now-lastMajor<.5 then return 0 end
 if kind=="totality" or kind=="crown" then lastMajor=now end
 -- Beam collisions can report many adjacent blocks in a frame. One crisp accent
 -- per local area is readable; all underlying server collision/damage is untouched.
 if kind=="beamImpact" then
  local p=payload.position;local key=math.floor(p.X/12)..":"..math.floor(p.Y/12)..":"..math.floor(p.Z/12)
  if now-(lastImpact[key] or -math.huge)<.28 or now-lastBeam<.1 then return 0 end
  lastBeam=now
  lastImpact[key]=now
  for old,at in lastImpact do if now-at>2 then lastImpact[old]=nil end end
 end
 active[scope]=kind;scope:add(function()active[scope]=nil end)
 local p=payload.position
 -- TOTALITY's ignition: black then deep purple, one eruption from the sleeves,
 -- over the complete SS3 explosion; a hard camera kick and impact frames.
 if kind=="totality" then
  local up=CFrame.new(p)
  local life=math.max(
   A.emit(scope,"VoidBurst",up,1.9,1.4),
   A.emit(scope,"BloodBurst",up,1.7,1.2,A.Dusk),
   A.emit(scope,"ImpactViolet",up,2.6,1.3,A.Dusk),
   A.explode(scope,up,1.8,1.4,true))
  kickFrames(p,.55,scope)

  return life+.4
 elseif kind=="blackSun" then
  -- The slam: a black core bursting through deep purple, with the ring torn up.
  local radius=payload.radius or 30
  local ground=payload.ground or p
  local life=math.max(
   A.emit(scope,"VoidBurst",CFrame.new(p),2.2,1.5),
   A.emit(scope,"BloodBurst",CFrame.new(p),2,1.3,A.Dusk),
   A.emit(scope,"ImpactViolet",CFrame.new(ground+Vector3.yAxis),radius/8,1.2,A.Dusk),
   A.explode(scope,CFrame.new(ground+Vector3.yAxis*1.5),1.8,1.3,true))
  kickFrames(p,.5,scope)

  return life+.4
 elseif kind=="crescentBreak" then
  -- A thrown blade breaking on a block or on someone.
  local life=A.emit(scope,"ImpactViolet",CFrame.new(p),.55,.7,if payload.phase==2 then A.Dusk else nil)
  local impact=A.mount(scope,"LungeImpact",CFrame.new(p),.45,nil,payload.phase==2 and A.Dusk or nil)
  impact:burst(.8)
  if payload.struck then VFX.rumble(p,.1,.15) end
  return math.max(life,.6)
 end
 if kind=="thunderStrike" then
  -- Umbral Thunder landing: Stylized Thunder's bolts on the mark, a column
  -- for the instant it connects, and the phase's impact ring and sparks.
  local radius=payload.radius or 7
  local s=radius/7
  local tint=BOLT[payload.phase or 1] or BOLT[1]
  local function mount(name,cf,scale) return Pack.mount(scope,workspace,name,{cframe=cf,scale=scale,tint=tint,brightness=2.5}) end
  Pack.bolt(scope,workspace,p,{tint=tint,scale=4.4*s,height=12*s,width=5*s})
  local column=mount("KiBlast4",CFrame.new(p),.6*s)
  column:taper(.55);column:stretch(p+Vector3.yAxis*90,p);column:beamsOn(true)
  scope:delay(.13,function() column:beamsOn(false) end)
  local frame=CFrame.lookAt(p+Vector3.yAxis*1.5,p+Vector3.yAxis*10)
  mount("Impact12",frame,2.2*s):burst(1)
  mount("Impact36",frame,2.6*s):burst(1)
  local life=A.emit(scope,"ImpactViolet",CFrame.new(p+Vector3.yAxis),radius/9,1,if payload.phase==2 then A.Dusk else nil)
  VFX.rumble(p,.14,.2)
  return math.max(life,1)
 end
 local radius=payload.radius or 8
 local major=kind=="death" or kind=="totality" or kind=="crown" or kind=="nova"
 local quiet=kind=="step" or kind=="land" or kind=="takeoff" or kind=="flare" or kind=="cast" or kind=="beamImpact" or kind=="harvest"
 local life
 local hit=kind=="referenceImpact" or kind=="impact" or kind=="erupt" or kind=="shatter" or kind=="beamImpact"
 if major or hit then
  local beam=kind=="beamImpact"
  local scale=if major then 1.8
   elseif beam then .3 elseif kind=="shatter" then .35 else math.clamp(radius/10,1.2,1.55)
  life=A.explode(scope,CFrame.new(p+Vector3.yAxis*math.min(scale,1.5)),scale,
   if major then 1.3 elseif beam then .25 else 1,major or kind=="referenceImpact")
  if kind=="referenceImpact" then
   -- The ring that says where it landed, in the phase's colour; phase two
   -- adds the deep purple burst on top.
   local ground=CFrame.new(p+Vector3.yAxis)
   life=math.max(life,A.emit(scope,"ImpactViolet",ground,radius/9,1,if payload.phase==2 then A.Dusk else nil))
   if payload.phase==2 then life=math.max(life,A.emit(scope,"BloodBurst",ground,radius/14,.8,A.Dusk)) end
  end
 else
  -- Small directional accents belong on hand releases/steps, never on the
  -- actual spell impacts. Those use the complete SS3 explosion above.
  life=if quiet then .65 else 1
  local impact=A.mount(scope,"Impact",CFrame.new(p),math.clamp(radius/12,.3,.8))
  impact:burst(if quiet then .4 else .7)
  local at=os.clock()
  scope:add(Run.Heartbeat:Connect(function()
   impact:set(nil,1-math.clamp((os.clock()-at)/life,0,1),false)
  end))
 end
 if major or kind=="referenceImpact" then
  VFX.rumble(p,major and .3 or .16,.25)

 elseif kind=="beamFire" then
 end
 return life+.25
end
return VFX
