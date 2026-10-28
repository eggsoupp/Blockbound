-- Reference choreography. Server owns every aim, hit and displaced terrain cell.
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
	trench toward them.
]]
local BEAM={
 charge={1.5,1.35},lock=.55,fire={3,3.8},collapse=.35,
 range={130,170},radius={4.5,6},tick=.25,damage={6,7},cap={32,40},
 track=140,sweep={0,15}, -- degrees a second: during the charge, and after firing
 bore={10,24},boreEvery={.32,.24},rend=8,
 standoff=20,backoff=16, -- studs it wants between it and its target, and how fast it backs off
 burn=12, -- its own rubble vaporised per beam
 depth=2, -- cells below where it first met the ground that it will dig to
}
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
 local function target(entry)
  local player=ctx.pickTarget(entry);local root=ctx.root(player)
  if root then entry.focus=player;return ctx.ground(root.Position),root end
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
 -- A point beside `centre`: another player's feet when there is one, else a
 -- spot `distance` off in a random direction.
 local function besides(entry,centre,distance)
  local other=ctx.root(ctx.other(entry,entry.focus))
  if other and (ctx.ground(other.Position)-centre).Magnitude>distance*.6 then return ctx.ground(other.Position) end
  local angle=math.random()*math.pi*2
  return ctx.ground(centre+Vector3.new(math.cos(angle),0,math.sin(angle))*distance)
 end

 -- UMBRAL MAELSTROM. Phase two opens a second, smaller storm beside the first.
 local function maelstrom(entry,phase,centre,radius,cells,ledger,key,main)
  local plan=Terrain:PlanExcavation(columns(centre,radius,1),{maxCells=cells})
  cast(entry,"SpiralCast",centre,centre,4.6,radius,{Phase=phase})
  if not ctx.pause(entry,1.25) then return end -- fixed warning; no chasing the player
  if main then ctx.pose(entry,"raise",.22) end
  local blocks=displace(entry.scope,plan,centre,radius,"orbit")
  moved(entry,blocks.count)
  local erupted=false
  if not run(entry,2.75,function(t)
   blocks:update(t)
   if t>.4 and not erupted then
    erupted=true;if main then ctx.pose(entry,"slam",.12) end
    hit(entry,centre,radius,if phase==2 then 31 else 26,ledger,key,if phase==2 then 44 else 26)
    ctx.fx("referenceImpact",centre,{style="spiral",radius=radius,phase=phase})
   end
  end) then return end
  blocks:finish()
 end
 function moves.spiral(entry,phase)
  local centre=target(entry);if not centre then return end
  local radius=if phase==2 then 14 else 12
  entry.motion="hold";lift(entry);ctx.pose(entry,"gather",.35)
  entry.model:SetAttribute("SignusLastMovedBlocks",0)
  local ledger={};local pending={count=0}
  if phase==2 then
   local twin=besides(entry,centre,radius*1.8)
   pending.count+=1
   entry.scope:spawn(function()
    if ctx.pause(entry,.45) then maelstrom(entry,phase,twin,radius-3,16,ledger,"spiral2",false) end
    pending.count-=1
   end)
  end
  maelstrom(entry,phase,centre,radius,28,ledger,"spiral",true)
  if not settle(entry,pending) then return end
  ctx.pose(entry,"rest",.4);ctx.pause(entry,.6)
 end

 -- ECLIPSE JUDGMENT. Phase two calls down two more columns either side.
 local function judgment(entry,phase,centre,radius,cells,ledger,key,main)
  local origin=ctx.hand(entry)
  local plan=Terrain:PlanExcavation(columns(centre,radius,2),{maxCells=cells})
  cast(entry,"LanceCast",origin,centre,5.4,radius,{Phase=phase})
  if not ctx.pause(entry,1.3) then return end
  if main then ctx.pose(entry,"release",.18) end
  if not ctx.pause(entry,.65) then return end
  if main then ctx.pose(entry,"raise",.2) end
  local blocks=displace(entry.scope,plan,centre,radius,"column")
  moved(entry,blocks.count)
  local struck=false
  if not run(entry,2.65,function(t)
   blocks:update(t)
   if t>.23 and not struck then
    struck=true
    hit(entry,centre,radius,if main then (if phase==2 then 36 else 30) else 22,ledger,key,if phase==2 then 48 else 30)
    ctx.fx("referenceImpact",centre,{style="lance",radius=radius,phase=phase})
   end
  end) then return end
  blocks:finish()
 end
 function moves.lance(entry,phase)
  local centre=target(entry);if not centre then return end
  entry.motion="hold";lift(entry);ctx.pose(entry,"gather",.35)
  entry.model:SetAttribute("SignusLastMovedBlocks",0)
  local radius=if phase==2 then 12 else 10
  local ledger={};local pending={count=0}
  if phase==2 then
   local toward=ctx.flat(centre-entry.position);local side=Vector3.new(-toward.Z,0,toward.X)
   for i,s in ipairs({-1,1}) do
    local spot=ctx.ground(centre+side*s*17+toward*4)
    pending.count+=1
    entry.scope:spawn(function()
     if ctx.pause(entry,.3*i) then judgment(entry,phase,spot,8,10,ledger,"lance"..i,false) end
     pending.count-=1
    end)
   end
  end
  judgment(entry,phase,centre,radius,32,ledger,"lance",true)
  if not settle(entry,pending) then return end
  ctx.pose(entry,"rest",.4);ctx.pause(entry,.8)
 end

 function moves.beam(entry,phase)
  local _,root=target(entry);if not root then return end
  local B=BEAM
  local charge,fire=B.charge[phase],B.fire[phase]
  local range=B.range[phase]
  entry.motion="aim";lift(entry);entry.model:SetAttribute("SignusLastMovedBlocks",0)
  ctx.pose(entry,"gather",.4)
  local function aimPoint()
   local r=ctx.root(entry.focus);return r and r.Position+Vector3.new(0,.5,0)
  end
  local origin=ctx.hand(entry)
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
    fired=true;ctx.pose(entry,"release",.12)
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
    local nowTick=math.floor(age/B.tick)
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
  ctx.pose(entry,"droop",.3)
  -- The collapse, and whatever is still in the air coming down.
  if not run(entry,1.1,function(t) carry(total+t*1.1) end) then return end
  for _,g in ipairs(groups) do if not g.done then g.moved:finish() end end
  ctx.pause(entry,.5)
 end

 -- TOTALITY. It climbs, the sky goes to eclipse, the ground orbits it, and at
 -- the top the eclipse ignites behind its hood. It does not come down again.
 function moves.totality(entry)
  entry.motion="hold";entry.hem=ctx.airHem+3;ctx.pose(entry,"raise",.65)
  local centre=ctx.ground(entry.position)
  ctx.announce("The moon swallows the sun. Signus enters Totality.","bad")
  ctx.sky(2,3.5)
  cast(entry,"Ascension",centre,centre,5,18,{Phase=2})
  local plan=Terrain:PlanExcavation(columns(centre,18,1),{maxCells=28})
  if not ctx.pause(entry,1.25) then return end
  local blocks=displace(entry.scope,plan,centre,18,"orbit")
  entry.model:SetAttribute("SignusLastMovedBlocks",blocks.count)
  if not run(entry,3,function(t) blocks:update(t) end) then return end
  blocks:finish()
  ctx.fx("totality",entry.position,{drop=entry.position.Y-ctx.ground(entry.position).Y})
  ctx.eclipse(entry);entry.transformed=true
  if entry.aura then entry.aura:SetAttribute("Phase",2) end
  ctx.pose(entry,"rest",.6);entry.hem=ctx.airHem;ctx.pause(entry,1)
 end
 return moves
end
return Moves
