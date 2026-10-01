-- Shared trajectories and timing for the three supplied elemental effects.
local Plan = {}
Plan.Tuning = {
 Windburst = { damage=24, radius=10, impactAt=.05 },
 ArcBurst = { damage=30, radius=8, impactAt=1 },
 LightningStrike = { damage=95, radius=15, impactAt=.85 },
}
function Plan.duration(): number return 6 end
function Plan.bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
 return a*(1-t)^2 + b*(2*(1-t)*t) + c*t^2
end
function Plan.build(name, origin, target, raycast)
 local tuning=Plan.Tuning[name]
 local start=origin.Position+Vector3.new(0,1,0)
 local packet={kind=name, start=start, target=target, impact=target, impactAt=tuning.impactAt, stopT=1}
 if name=='ArcBurst' then
  local distance=(target-start).Magnitude
  packet.control=(start+target)*.5+Vector3.new(0,math.clamp(distance*.3,6,24),0)+origin.RightVector*math.min(distance*.18,12)
  local travel=math.clamp(distance/85,.35,1.25)
  packet.travel=travel
  local previous=start
  for i=1,64 do
   local t=i/64
   local point=Plan.bezier(start,packet.control,target,t)
   local hit=raycast(previous,point-previous)
   if hit then
    local fraction=math.clamp((hit.Position-previous).Magnitude/math.max((point-previous).Magnitude,.001),0,1)
    packet.stopT=(i-1+fraction)/64
    packet.impact=hit.Position
    break
   end
   previous=point
  end
  packet.impactAt=math.max(.02,travel*packet.stopT)
 elseif name=='Windburst' then
  -- The cursor is the effect position; no travelling gust or intervening ray.
  local delta=target-start
  packet.direction=if delta.Magnitude>.001 then delta.Unit else origin.LookVector
 else
  local hit=raycast(target+Vector3.new(0,3,0),Vector3.new(0,-18,0))
  if hit then packet.impact=hit.Position end
 end
 return packet
end
return Plan
