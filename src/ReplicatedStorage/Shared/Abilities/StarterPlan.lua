-- Server and observers share timing; only the server resolves hits and movement.
local Plan = {}
Plan.Fireball = {windup=.22, speed=70, range=90, radius=1.35, damage=20, splash=5}
Plan.WaterBlade = {windup=.18, speed=90, range=80, radius=2.4, damage=24, splash=0}
Plan.WindBurst = {windup=.16, range=18, damage=8, halfAngle=55, push=42, lift=28}
Plan.EchoStep = {range=18, minimum=4}
Plan.BlockWall = {travel=.72, columns=3, rows=3, range=16, offset=9}
function Plan.duration() return 4 end
function Plan.flat(direction)
	local flat=Vector3.new(direction.X,0,direction.Z)
	return if flat.Magnitude>.01 then flat.Unit else Vector3.new(0,0,-1)
end
function Plan.wallPosition(from,to,alpha,index)
	local t=math.clamp(alpha,0,1)
	local ease=t*t*(3-2*t)
	return from:Lerp(to,ease)+Vector3.new(0,math.sin(t*math.pi)*(5+(index%3)),0)
end
return Plan
