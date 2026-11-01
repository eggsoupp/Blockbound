-- Short, scoped punctuation from complete library assemblies. No impact-frame planes.
local Run=game:GetService("RunService")
local Players=game:GetService("Players")
local FX=require(script.Parent.SignusFX)
local A=require(script.Parent.SignusAssemblies)
local VFX={}
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
 if kind=="lungeImpact" then
  local direction=payload.direction or Vector3.zAxis
  local impact=A.mount(scope,"LungeImpact",CFrame.lookAt(p,p+direction)*CFrame.Angles(-math.pi/2,0,0),1.1)
  impact:burst(1.4)
  local host=FX.host(scope,p,"SignusCrescentImpact")
  FX.sound(host,.55,1.1,FX.Sounds.blast);VFX.rumble(p,.12,.18)
  return .65
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
  local host=FX.host(scope,p,"SignusImpactSound")
  FX.sound(host,major and 1 or .55,major and .65 or .9,major and FX.Sounds.thunder or FX.Sounds.boom)
 elseif kind=="beamFire" then
  local host=FX.host(scope,p,"SignusReleaseSound");FX.sound(host,.75,.7,FX.Sounds.blast)
 end
 return life+.25
end
return VFX
