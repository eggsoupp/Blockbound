-- Signus's spells. Server owns every aim, hit and displaced terrain cell; the
-- body plays retargeted pack clips (Shared.Enemies.SignusClips) whose Hit
-- markers are the moments damage and terrain land.
local RS=game:GetService("ReplicatedStorage")
local Terrain=require(script.Parent.Parent.TerrainManager)
local Items=require(RS.Shared.UI.ItemModels)
local Moves={}
local CELL=4
--[[
	WORLDREND. Numbers in pairs are { phase one, phase two }.

	The aim follows its target through the charge and locks for the last half
	second of it: that is the dodge. The beam has no end of its own. It runs
	until it meets a block or fades out at its range; natural ground it meets
	is burnt out and flung aside, so it bores on through a hillside, while a
	placed wall stops it dead. In phase two it fires from the air and keeps
	turning after its target, slowly enough to outrun sideways, ploughing a
	trench toward them. The body plays Grimoire Hit 5: its long Swing -> Hit
	is the charge, held at Hit while the beam fires.
]]
local BEAM={
 charge={1.15,.95},lock=.3,fire={2.4,2.85},collapse=.35,
 range={145,180},radius={6,7.5},tick=.25,damage={8,10},cap={40,52},
 track=160,sweep={12,36}, -- cut inward or change direction instead of kiting at long range
 bore={10,24},boreEvery={.32,.24},rend=8,
 standoff=20,backoff=16, -- studs it wants between it and its target, and how fast it backs off
 burn=12, -- its own rubble vaporised per beam
 depth=2, -- cells below where it first met the ground that it will dig to
}
--[[
	UMBRAL MAELSTROM. The warning is fixed where it first appears; the slam's
	Hit marker is the eruption. Phase two: the storm walks. Two aftershocks
	open after the first, each re-aimed at where its target is heading, each
	with a full warning of its own.
]]
local STORM={warn={.9,.75},active={1.8,1.7},strike=.22,radius={17,19},damage={34,40},cap={34,60},
 chain={radius=14,cells=14,gap=.55,lead=.45,damage=30}}
--[[
	ECLIPSE JUDGMENT. Grimoire Hit 1 points the sleeve; on its Hit a sun of
	judgment forms high over the mark and falls into it as a column. Nothing
	is thrown: the warning is the sigil on the ground and the orb above it.
	Phase two: Judgment Cross. A smaller main column, then two pairs of arms
	sixteen studs out, as a plus one cast and a cross the next. The diagonals
	between the arms are the way out.
]]
local JUDGMENT={warn={.85,.72},travel={.38,.3},active={1.75,1.65},strike=.16,radius={16,12},damage={38,44},cap={38,64},height=30,
 arm={radius=8,reach=16,stagger=.28,damage=28,cells=8}}
--[[
	UMBRAL THUNDER. A sleeve raised to the sky (Grimoire Up Tilt), and violet
	lightning answers: one mark at a time opens on the ground where its target
	is heading and is struck when it closes, so standing still or running in a
	straight line is what gets you hit. A block overhead is cover. Each strike
	tears up a little of the ground it lands on.
	Phase two: Eclipse Storm. A faster, longer chain, ending in a crown - a
	ring of strikes round where you stand and one in the middle, with a band
	between them that is the way out.
]]
local THUNDER={strikes={3,5},gap={.55,.38},warn={.85,.7},radius={7,6.5},damage={14,14},cap={28,42},lead=.35,
 crown={count=7,ring=13,radius=4.2,centre=4,warn=.95,damage=18},cells=3,height=46,recover={.5,.35}}
--[[
	BLACK SUN (phase two). It holds a black sun over its head for over two
	seconds while a thirty-stud ring closes on the ground; then it slams it
	down. Everyone in reach who can see the sun's core is burnt: a block
	between you and it - a hillside, a wall you built - is the cover. The ground
	around it is torn up and thrown. Afterwards it sinks, spent, for a long
	melee window.
]]
local SUN={raise=.35,channel=2.1,radius=30,damage=30,cap=30,height=13,ring={9,13},columns=16,cells=18,recover=2.3}
--[[
	TOTALITY, the turn to phase two. It cannot be hurt while it plays. Grimoire
	Heavy is stretched into a long gather; its Hit is the ignition: the air
	darkens to a purple dusk, the eyes burn violet, the aura deepens and the
	eclipse halo rises. The ground
	under it orbits and is flung, as ever.
]]
local TOTALITY={gather=1.7,hold=1.3,radius=18,cells=28}
--[[
	Cells its spells have dropped a block into. Committed rubble is recorded
	as a placement, exactly like a block a player put down, so this is the only
	way to tell the two apart: Worldrend burns through its own rubble, and a
	wall somebody built still stops it.
]]
local rubble={}
local rubbleCount=0
local function cellKey(position)
 return math.floor(position.X/CELL)..":"..math.floor(position.Y/CELL)..":"..math.floor(position.Z/CELL)
end
local function addRubble(position)
 if rubbleCount>6000 then rubble={};rubbleCount=0 end
 local key=cellKey(position)
 if not rubble[key] then rubble[key]=true;rubbleCount+=1 end
end
--[[
	How high the ground was, per 8-stud patch, the first time a Worldrend met
	it this fight. A beam may only dig BEAM.depth cells below that, so later
	beams cannot each go two cells deeper than the last trench. A patch seen
	for the first time takes the highest of its known neighbours, so a beam
	following its own trench downhill does not start a staircase.
]]
local function groundReference(surface,cell)
 local px,pz=math.floor(cell.X/8),math.floor(cell.Z/8)
 local key=px..":"..pz
 if not surface[key] then
  local y=cell.Y
  for dx=-1,1 do for dz=-1,1 do
   local known=surface[(px+dx)..":"..(pz+dz)]
   if known and known>y then y=known end
  end end
  surface[key]=y
 end
 return surface[key]
end
local function columns(centre,radius,depth)
 local result={}
 for x=-radius,radius,4 do for z=-radius,radius,4 do
  if x*x+z*z<=radius*radius then table.insert(result,{x=centre.X+x,z=centre.Z+z,y=centre.Y,depth=depth or 1}) end
 end end
 table.sort(result,function(a,b) return (Vector3.new(a.x,a.y,a.z)-centre).Magnitude<(Vector3.new(b.x,b.y,b.z)-centre).Magnitude end)
 return result
end
-- A ring of columns between two radii, planned at once so the warning shows
-- exactly what will go.
local function ringColumns(ground,centre,inner,outer,count)
 local result={}
 local base=math.random()*math.pi*2
 for i=1,count do
  local angle=base+(i-1)/count*math.pi*2
  local radius=inner+(outer-inner)*((i%3)/2)
  local spot=ground(centre+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius))
  table.insert(result,{x=spot.X,z=spot.Z,y=spot.Y,depth=1})
 end
 return result
end
local function blockActor(record,parent)
 local template=Items.find(record.block)
 if template and not template:IsA("BasePart") then template=template:FindFirstChildWhichIsA("BasePart",true) end
 local p=if template then template:Clone() else Instance.new("Part")
 for _,child in ipairs(p:GetChildren()) do
  if not (child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance")) then child:Destroy() end
 end
 p.Name=record.block;p.Size=Vector3.one*4;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
 p:SetAttribute("SignusTerrainBlock",true);p.CFrame=CFrame.new(record.source.position);p.Parent=parent
 return p
end
-- A travelling block represents exactly one removed cell and is committed at
-- its reserved landing cell. No cosmetic rock clones and no dropped resources.
local function displace(scope,plan,centre,radius,mode)
 local targets={}
 for i,r in ipairs(plan) do
  local angle=math.atan2(r.position.Z-centre.Z,r.position.X-centre.X)+.35
  targets[i]=centre+Vector3.new(math.cos(angle),0,math.sin(angle))*(radius+8+(i%3)*4)
 end
 local loan=Terrain:BeginBossDisplacement(plan,targets)
 local folder=scope:add(Instance.new("Folder"));folder.Name="SignusMovingTerrain";folder.Parent=workspace
 local actors={};local done=false
 scope:add(function() if not done then Terrain:FinishBossDisplacement(loan,false) end end)
 for i,r in ipairs(loan.records) do actors[i]=blockActor(r,folder) end
 local result={count=#actors}
 function result:update(t)
  if done then return end
  t=math.clamp(t,0,1)
  for i,r in ipairs(loan.records) do
   local from,to=r.source.position,r.target.position
   local point
   if mode=="orbit" then
    local angle=math.atan2(from.Z-centre.Z,from.X-centre.X)+t*math.pi*2
    local orbit=centre+Vector3.new(math.cos(angle)*radius,10+math.sin(i*2)*3,math.sin(angle)*radius)
    if t<.25 then point=from:Lerp(orbit,t/.25)
    elseif t<.65 then point=orbit
    else point=orbit:Lerp(to,(t-.65)/.35) end
   else point=from:Lerp(to,t)+Vector3.yAxis*math.sin(math.pi*t)*(if mode=="column" then 26+(i%5)*3 else 9+i%4) end
   actors[i].CFrame=CFrame.new(point)*CFrame.Angles(math.sin(t*math.pi)*i*.3,t*math.pi*2,math.sin(t*math.pi)*.8)
  end
 end
 function result:finish()
  if done then return end
  self:update(1);Terrain:FinishBossDisplacement(loan,true);done=true;folder:Destroy()
  -- A block whose landing was taken goes back to its source, so both count.
  for _,r in ipairs(loan.records) do addRubble(r.target.position);addRubble(r.source.position) end
 end
 return result
end
-- Turns a direction toward another by at most `maxRadians`.
local function turn(from,to,maxRadians)
 local angle=math.acos(math.clamp(from:Dot(to),-1,1))
 if angle<=maxRadians then return to end
 local axis=from:Cross(to)
 if axis.Magnitude<1e-4 then return from end
 return (CFrame.fromAxisAngle(axis.Unit,maxRadians)*from).Unit
end
function Moves.create(ctx)
 local moves={}
 -- Attributes go on before the carrier is parented, so a client never
 -- mounts it once as phase one and again as phase two.
 local function cast(entry,kind,origin,target,duration,radius,extra)
  local p=ctx.carrier(Vector3.one,Color3.new(1,1,1),0,kind)
  p.CFrame=CFrame.new(origin);p:SetAttribute("Target",target);p:SetAttribute("StartedAt",workspace:GetServerTimeNow())
  p:SetAttribute("Duration",duration);p:SetAttribute("Radius",radius)
  for key,value in pairs(extra or {}) do p:SetAttribute(key,value) end
  p.Parent=workspace;entry.scope:add(p)
  return p
 end
 local function run(entry,seconds,update)
  local began=os.clock()
  repeat
   if entry.signusFinished or entry.scope:isDead() then return false end
   update(math.clamp((os.clock()-began)/seconds,0,1));task.wait()
  until os.clock()-began>=seconds
  update(1);return true
 end
 local function predicted(root,seconds)
  local velocity=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z)
  if velocity.Magnitude>25 then velocity=velocity.Unit*25 end
  return ctx.ground(root.Position+velocity*seconds)
 end
 local function target(entry,lead)
  local player=ctx.pickTarget(entry);local root=ctx.root(player)
  if root then entry.focus=player;return predicted(root,lead or 0),root end
 end
 local function hit(entry,point,radius,amount,ledger,key,cap)
  for _,p in ipairs(ctx.playersInCircle(point,radius)) do
   local root=ctx.root(p)
   if root and not ctx.cover(point+Vector3.yAxis*3,root.Position) then ctx.hit(ledger,key,p,amount,cap or amount) end
  end
 end
 local function moved(entry,count)
  entry.model:SetAttribute("SignusLastMovedBlocks",(entry.model:GetAttribute("SignusLastMovedBlocks") or 0)+count)
 end
 -- Phase two casts from the air.
 local function lift(entry)
  if entry.transformed then entry.hem=ctx.airHem end
 end
 -- Waits for spells spawned beside the main one, so the scope outlives them.
 local function settle(entry,pending)
  while pending.count>0 do if not ctx.pause(entry,.05) then return false end end
  return true
 end
 local function spawnSide(entry,pending,delay,fn)
  pending.count+=1
  entry.scope:spawn(function()
   if ctx.pause(entry,delay) then fn() end
   pending.count-=1
  end)
 end

 -- UMBRAL MAELSTROM
 local function maelstrom(entry,phase,centre,radius,cells,ledger,key,damage)
  local M=STORM;local warn,active=M.warn[phase],M.active[phase]
  local plan=Terrain:PlanExcavation(columns(centre,radius,1),{maxCells=cells})
  cast(entry,"SpiralCast",centre,centre,warn+active+.35,radius,{Phase=phase,Warning=warn,StrikeAt=warn+active*M.strike,Active=active})
  if not ctx.pause(entry,warn) then return end -- centre stays fixed after the warning appears
  local blocks=displace(entry.scope,plan,centre,radius,"orbit")
  moved(entry,blocks.count)
  local erupted=false
  if not run(entry,active,function(t)
   blocks:update(t)
   if t>=M.strike and not erupted then
    erupted=true
    hit(entry,centre,radius,damage or M.damage[phase],ledger,key,M.cap[phase])
    ctx.fx("referenceImpact",centre,{style="spiral",radius=radius,phase=phase})
   end
  end) then return end
  blocks:finish()
 end
 function moves.spiral(entry,phase)
  local centre=target(entry,if phase==2 then .4 else .2);if not centre then return end
  local M=STORM;local radius=M.radius[phase]
  entry.motion="hold";lift(entry)
  entry.model:SetAttribute("SignusLastMovedBlocks",0)
  -- AirSlam's Hit is the eruption: its rise is the whole warning.
  local strikeAt=M.warn[phase]+M.active[phase]*M.strike
  local plan=ctx.clipPlan("AirSlam",{})
  ctx.clip(entry,"AirSlam",{windup=math.max(.2,strikeAt-plan.release),speed=.85})
  local ledger={};local pending={count=0}
  if phase==2 then
   -- The storm walks: each aftershock opens where its target is heading.
   for i=1,2 do
    spawnSide(entry,pending,strikeAt+(i-1)*M.chain.gap,function()
     local root=ctx.root(entry.focus)
     if root then maelstrom(entry,phase,predicted(root,M.chain.lead+M.warn[phase]),M.chain.radius,M.chain.cells,ledger,"chain"..i,M.chain.damage) end
    end)
   end
  end
  maelstrom(entry,phase,centre,radius,28,ledger,"spiral")
  if not settle(entry,pending) then return end
  ctx.pause(entry,.2)
 end

 -- ECLIPSE JUDGMENT
 local function judgment(entry,phase,centre,radius,cells,ledger,key,damage)
  local J=JUDGMENT;local warn,travel,active=J.warn[phase],J.travel[phase],J.active[phase]
  local plan=Terrain:PlanExcavation(columns(centre,radius,2),{maxCells=cells})
  -- The orb forms over the mark, not in the hand: it falls, it is not thrown.
  cast(entry,"LanceCast",centre+Vector3.yAxis*J.height,centre,warn+travel+active+.4,radius,{Phase=phase,Warning=warn,Travel=travel,StrikeAt=warn+travel+active*J.strike,Active=active})
  if not ctx.pause(entry,warn+travel) then return end
  local blocks=displace(entry.scope,plan,centre,radius,"column")
  moved(entry,blocks.count)
  local struck=false
  if not run(entry,active,function(t)
   blocks:update(t)
   if t>=J.strike and not struck then
    struck=true
    hit(entry,centre,radius,damage,ledger,key,J.cap[phase])
    ctx.fx("referenceImpact",centre,{style="lance",radius=radius,phase=phase})
   end
  end) then return end
  blocks:finish()
 end
 function moves.lance(entry,phase)
  local centre=target(entry,if phase==2 then .25 else .2);if not centre then return end
  local J=JUDGMENT
  entry.motion="hold";lift(entry)
  entry.model:SetAttribute("SignusLastMovedBlocks",0)
  -- Hit 1's Hit is where the warning ends and the orb falls.
  local plan=ctx.clipPlan("Light1",{})
  ctx.clip(entry,"Light1",{windup=math.max(.25,J.warn[phase]-plan.release)})
  local ledger={};local pending={count=0}
  if phase==2 then
   -- Judgment Cross: a plus one cast, a cross the next.
   entry.crossTurn=not entry.crossTurn
   local toward=ctx.flat(centre-entry.position)
   local side=Vector3.new(-toward.Z,0,toward.X)
   if entry.crossTurn then toward,side=(toward+side).Unit,(side-toward).Unit end
   local arms={{toward,-toward},{side,-side}}
   for i,pair in ipairs(arms) do
    for _,dir in ipairs(pair) do
     spawnSide(entry,pending,J.warn[phase]*.5+(i-1)*J.arm.stagger,function()
      local spot=ctx.ground(centre+dir*J.arm.reach)
      judgment(entry,phase,spot,J.arm.radius,J.arm.cells,ledger,"arm"..i,J.arm.damage)
     end)
    end
   end
  end
  ctx.fx("cast",ctx.hand(entry),{phase=phase})
  judgment(entry,phase,centre,J.radius[phase],32,ledger,"lance",J.damage[phase])
  if not settle(entry,pending) then return end
  ctx.pause(entry,.25)
 end

 -- WORLDREND
 function moves.beam(entry,phase)
  local _,root=target(entry);if not root then return end
  local B=BEAM
  local charge,fire=B.charge[phase],B.fire[phase]
  local range=B.range[phase]
  entry.motion="aim";lift(entry);entry.model:SetAttribute("SignusLastMovedBlocks",0)
  -- Swing -> Hit of Grimoire Hit 5 is the charge; it holds at Hit while firing.
  local plan=ctx.clipPlan("Light5",{})
  ctx.clip(entry,"Light5",{windup=plan.windup,speed=(plan.hit-plan.swing)/math.max(charge-plan.windup,.2),hold=fire+5})
  local function aimPoint()
   local r=ctx.root(entry.focus);return r and r.Position+Vector3.new(0,.5,0)
  end
  local origin=ctx.hand(entry)
  ctx.fx("beamCharge",origin,{audioOnly=true,phase=phase})
  local direction=((aimPoint() or origin+ctx.flat(entry.look)*20)-origin).Unit
  local carrier=cast(entry,"RiftBeam",origin,origin+direction*range,charge+fire+B.collapse,B.radius[phase],{Charge=charge,Phase=phase,Hit=false,Normal=Vector3.yAxis})
  local ledger={};local groups={};local rend={}
  local tick=-1;local fired=false;local bored,burnt=0,0;local lastBore=-math.huge
  entry.beamGround=entry.beamGround or {}
  local surface=entry.beamGround -- see groundReference
  local lastEnd
  local last=os.clock()
  local function carry(age)
   for _,g in ipairs(groups) do
    if not g.done then
     local a=math.clamp((age-g.at)/1.1,0,1);g.moved:update(a)
     if a>=1 then g.moved:finish();g.done=true end
    end
   end
  end
  local total=charge+fire
  if not run(entry,total,function(t)
   local now=os.clock();local dt=math.min(now-last,.1);last=now
   local age=t*total
   local want=aimPoint()
   -- Too close to fire across at them: it drifts back while it charges.
   if want and age<charge then
    local away=Vector3.new(entry.position.X-want.X,0,entry.position.Z-want.Z)
    if away.Magnitude<B.standoff then
     entry.position+=(if away.Magnitude>.5 then away.Unit else -ctx.flat(entry.look))*B.backoff*dt
    end
   end
   origin=ctx.hand(entry);carrier.CFrame=CFrame.new(origin)
   if want and (want-origin).Magnitude>1 then
    local to=(want-origin).Unit
    if age<charge-B.lock then direction=turn(direction,to,math.rad(B.track)*dt)
    elseif age>=charge and B.sweep[phase]>0 then direction=turn(direction,to,math.rad(B.sweep[phase])*dt) end
   end
   entry.look=ctx.flat(direction)
   -- The first block on the line, if any: that is where it ends.
   local block=ctx.cover(origin,origin+direction*range)
   local finish=if block then block.Position else origin+direction*range
   if not lastEnd or (finish-lastEnd).Magnitude>.15 then carrier:SetAttribute("Target",finish);lastEnd=finish end
   carrier:SetAttribute("Hit",block~=nil)
   if block then carrier:SetAttribute("Normal",block.Normal) end
   if age>=charge and not fired then
    fired=true
    ctx.fx("beamFire",origin,{direction=direction,phase=phase})
    -- Ground close under the beam's line tears up, from the hands outward.
    local delta=finish-origin
    for d=8,delta.Magnitude,7 do
     if #rend>=B.rend then break end
     local point=origin+direction*d;local ground=ctx.ground(point)
     if point.Y-ground.Y<7 then table.insert(rend,{at=age+d/delta.Magnitude*.6,column={x=ground.X,z=ground.Z,y=ground.Y,depth=1},point=ground}) end
    end
   end
   if fired then
    for _,r in ipairs(rend) do
     if not r.taken and age>=r.at then
      r.taken=true
      local plan=Terrain:PlanExcavation({r.column},{maxCells=1})
      if #plan>0 then local m=displace(entry.scope,plan,r.point,5,"throw");moved(entry,m.count);table.insert(groups,{moved=m,at=age}) end
     end
    end
    -- What it meets burns, so the beam bores on: natural ground is torn out
    -- and flung aside, and its own rubble is vaporised. It ploughs rather
    -- than drills: never deeper than a couple of cells below the ground it
    -- first met there (groundReference).
    if block and age-lastBore>=B.boreEvery[phase] then
     lastBore=age
     local cell=block.Position-block.Normal*(CELL*.5)
     if cell.Y>=groundReference(surface,cell)-B.depth*CELL-.1 then
      if rubble[cellKey(cell)] then
       local plan=Terrain:PlanExcavation({{x=cell.X,z=cell.Z,y=cell.Y,depth=1}},{maxCells=1,naturalOnly=false})
       local key=plan[1] and cellKey(plan[1].position)
       if key and rubble[key] and burnt<B.burn then
        rubble[key]=nil
        burnt+=Terrain:ExecuteExcavation(plan,{naturalOnly=false})
       end
      elseif bored<B.bore[phase] then
       local cols={{x=cell.X,z=cell.Z,y=cell.Y,depth=2}}
       if phase==2 then
        local side=direction:Cross(Vector3.yAxis)
        if side.Magnitude>.1 then
         side=side.Unit*CELL
         table.insert(cols,{x=cell.X+side.X,z=cell.Z+side.Z,y=cell.Y,depth=1})
         table.insert(cols,{x=cell.X-side.X,z=cell.Z-side.Z,y=cell.Y,depth=1})
        end
       end
       local plan=Terrain:PlanExcavation(cols,{maxCells=math.min(4,B.bore[phase]-bored)})
       if #plan>0 then
        local m=displace(entry.scope,plan,block.Position,4,"throw")
        bored+=m.count;moved(entry,m.count);table.insert(groups,{moved=m,at=age})
       end
      end
     end
     ctx.fx("beamImpact",block.Position,{normal=block.Normal,phase=phase})
    end
    local nowTick=math.floor((age-charge)/B.tick)
    if nowTick~=tick then
     tick=nowTick
     local delta=finish-origin
     for _,p in ipairs(ctx.players()) do
      local pr=ctx.root(p)
      if pr then
       local f=math.clamp((pr.Position-origin):Dot(delta)/math.max(delta:Dot(delta),.01),0,1)
       local near=(pr.Position-origin:Lerp(finish,f)).Magnitude<B.radius[phase]
       -- Past the end of a blocked beam only the open side of the block burns.
       if near and block and f>=.98 and ctx.cover(finish+block.Normal*1.5,pr.Position) then near=false end
       if near then ctx.hit(ledger,"beam"..tick,p,B.damage[phase],B.cap[phase]) end
      end
     end
    end
   end
   carry(age)
  end) then return end
  -- The beam is spent: the arm comes down through the rest of the clip.
  ctx.clip(entry,"Light5",{from=plan.hit})
  ctx.stance(entry,"spent")
  -- The collapse, and whatever is still in the air coming down.
  if not run(entry,1.1,function(t) carry(total+t*1.1) end) then return end
  for _,g in ipairs(groups) do if not g.done then g.moved:finish() end end
  ctx.pause(entry,.15)
 end

 -- UMBRAL THUNDER
 -- One strike: its mark opens at `centre` and the bolt lands `warn` later on
 -- everyone in it with open sky above them. Mirror Veil calls it too.
 local function bolt(entry,phase,centre,radius,warn,damage,ledger,key,cap)
  local T=THUNDER
  cast(entry,"Thunder",centre,centre,warn+1,radius,{Phase=phase,Warning=warn})
  local plan=Terrain:PlanExcavation(columns(centre,math.min(radius,5),1),{maxCells=T.cells})
  if not ctx.pause(entry,warn) then return end
  ctx.fx("thunderStrike",centre,{radius=radius,phase=phase})
  for _,p in ipairs(ctx.playersInCircle(centre,radius)) do
   local root=ctx.root(p)
   if root and not ctx.cover(root.Position+Vector3.yAxis*T.height,root.Position+Vector3.yAxis*2) then
    ctx.hit(ledger,key,p,damage,cap or damage)
   end
  end
  if #plan>0 then
   local blocks=displace(entry.scope,plan,centre,radius,"throw")
   moved(entry,blocks.count)
   if run(entry,.9,function(t) blocks:update(t) end) then blocks:finish() end
  end
 end
 moves.bolt=bolt
 function moves.thunder(entry,phase)
  local _,root=target(entry);if not root then return end
  local T=THUNDER
  entry.motion="hold";lift(entry)
  entry.model:SetAttribute("SignusLastMovedBlocks",0)
  local count=T.strikes[phase]
  local span=(count-1)*T.gap[phase]+T.warn[phase]+(if phase==2 then T.gap[phase]+T.crown.warn else 0)
  -- Up Tilt raises the sleeve to the sky on its Hit and holds it there.
  local marks=ctx.clip(entry,"UpTilt",{windup=.4,hold=span})
  if not ctx.pause(entry,marks.hit) then return end
  ctx.fx("cast",ctx.hand(entry),{phase=phase})
  local ledger={};local pending={count=0}
  for i=1,count do
   spawnSide(entry,pending,(i-1)*T.gap[phase],function()
    local r=ctx.root(entry.focus);if not r then return end
    bolt(entry,phase,predicted(r,T.lead+T.warn[phase]*.5),T.radius[phase],T.warn[phase],T.damage[phase],ledger,"bolt"..i,T.cap[phase])
   end)
  end
  if phase==2 then
   -- The crown, round where its target stands when it opens.
   spawnSide(entry,pending,count*T.gap[phase],function()
    local r=ctx.root(entry.focus);if not r then return end
    local C=T.crown
    local centre=ctx.ground(r.Position)
    local spin=math.random()*math.pi*2
    for k=1,C.count do
     local a=spin+(k-1)*math.pi*2/C.count
     local spot=ctx.ground(centre+Vector3.new(math.cos(a),0,math.sin(a))*C.ring)
     spawnSide(entry,pending,0,function() bolt(entry,phase,spot,C.radius,C.warn,C.damage,ledger,"crown",T.cap[phase]) end)
    end
    bolt(entry,phase,centre,C.centre,C.warn,C.damage,ledger,"crown",T.cap[phase])
   end)
  end
  if not settle(entry,pending) then return end
  ctx.pause(entry,T.recover[phase])
 end

 -- BLACK SUN (phase two)
 function moves.blacksun(entry,phase)
  local _,root=target(entry);if not root then return end
  local S=SUN
  entry.motion="hold";entry.hem=ctx.airHem*.6
  entry.model:SetAttribute("SignusLastMovedBlocks",0)
  local raise=ctx.clipPlan("UpTilt",{windup=S.raise})
  ctx.clip(entry,"UpTilt",{windup=S.raise,hold=S.channel+1})
  local centre=ctx.ground(entry.position)
  local sunAt=function() return entry.model:GetPivot().Position+Vector3.yAxis*S.height end
  local plan=Terrain:PlanExcavation(ringColumns(ctx.ground,centre,S.ring[1],S.ring[2],S.columns),{maxCells=S.cells})
  local sun=cast(entry,"BlackSun",sunAt(),centre,raise.marks.hit+S.channel+.9,S.radius,{Phase=2,Charge=raise.marks.hit+S.channel})
  local ok=run(entry,raise.marks.hit+S.channel,function()
   sun.CFrame=CFrame.new(sunAt())
   local r=ctx.root(entry.focus);if r then entry.look=ctx.flat(r.Position-entry.position);ctx.applyPose(entry) end
  end)
  if not ok then return end
  -- The slam: AirSlam's Hit is the detonation.
  local slam=ctx.clip(entry,"AirSlam",{windup=.12})
  if not ctx.pause(entry,slam.hit) then return end
  local core=sunAt()
  sun:SetAttribute("DetonatedAt",workspace:GetServerTimeNow())
  local ledger={}
  for _,p in ipairs(ctx.players()) do
   local pr=ctx.root(p)
   if pr and (pr.Position-core).Magnitude<=S.radius+S.height*.5 and (Vector3.new(pr.Position.X,0,pr.Position.Z)-Vector3.new(centre.X,0,centre.Z)).Magnitude<=S.radius
    and not ctx.cover(core,pr.Position) then
    ctx.hit(ledger,"sun",p,S.damage,S.cap)
   end
  end
  ctx.fx("blackSun",core,{radius=S.radius,ground=centre})
  local blocks=displace(entry.scope,plan,centre,S.ring[2],"column")
  moved(entry,blocks.count)
  -- Spent: it sinks and stays down - the melee window.
  entry.motion="ground";ctx.stance(entry,"spent")
  if not run(entry,1.1,function(t) blocks:update(t) end) then return end
  blocks:finish()
  ctx.pause(entry,S.recover-1.1)
 end

 -- TOTALITY
 function moves.totality(entry)
  local T=TOTALITY
  ctx.guard(entry,true)
  entry.motion="hold";entry.hem=ctx.airHem+3
  local centre=ctx.ground(entry.position)
  ctx.announce("The moon swallows the sun. Signus enters Totality.","bad")
  ctx.sky("gather",1.6)
  local marks=ctx.clip(entry,"Heavy",{windup=T.gather,hold=T.hold,speed=.8})
  cast(entry,"Ascension",centre,centre,marks.hit+T.hold+1.2,T.radius,{Phase=2,Warning=marks.hit-.2,StrikeAt=marks.hit})
  local plan=Terrain:PlanExcavation(columns(centre,T.radius,1),{maxCells=T.cells})
  if not ctx.pause(entry,.35) then return end
  local blocks=displace(entry.scope,plan,centre,T.radius,"orbit")
  entry.model:SetAttribute("SignusLastMovedBlocks",blocks.count)
  local orbit=marks.hit+T.hold+.5-.35
  local ignited=false
  if not run(entry,orbit,function(t)
   blocks:update(t)
   if not ignited and t*orbit>=marks.hit-.35 then
    -- Heavy's Hit: the ignition.
    ignited=true
    ctx.sky(2,.5)
    ctx.ignite(entry)
    ctx.fx("totality",ctx.hand(entry),{drop=entry.position.Y-centre.Y})
   end
  end) then return end
  blocks:finish()
  entry.hem=ctx.airHem
  ctx.guard(entry,false)
  ctx.pause(entry,.5)
 end
 return moves
end
return Moves
