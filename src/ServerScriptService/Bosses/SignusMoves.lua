-- Reference choreography. Server owns every aim, hit and displaced terrain cell.
local RS=game:GetService("ReplicatedStorage")
local Terrain=require(script.Parent.Parent.TerrainManager)
local Items=require(RS.Shared.UI.ItemModels)
local Moves={}
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
 end
 return result
end
function Moves.create(ctx)
 local moves={}
 local function cast(entry,kind,origin,target,duration,radius)
  local p=ctx.carrier(Vector3.one,Color3.new(1,1,1),0,kind)
  p.CFrame=CFrame.new(origin);p:SetAttribute("Target",target);p:SetAttribute("StartedAt",workspace:GetServerTimeNow())
  p:SetAttribute("Duration",duration);p:SetAttribute("Radius",radius);p.Parent=workspace;entry.scope:add(p)
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
 function moves.spiral(entry,phase)
  local centre=target(entry);if not centre then return end
  local radius=if phase==2 then 14 else 12
  entry.motion="hold";ctx.pose(entry,"gather",.35)
  local plan=Terrain:PlanExcavation(columns(centre,radius,1),{maxCells=28})
  cast(entry,"SpiralCast",centre,centre,4.6,radius)
  if not ctx.pause(entry,1.25) then return end -- fixed warning; no chasing the player
  ctx.pose(entry,"raise",.22)
  local blocks=displace(entry.scope,plan,centre,radius,"orbit")
  entry.model:SetAttribute("SignusLastMovedBlocks",blocks.count)
  local ledger={};local erupted=false
  if not run(entry,2.75,function(t)
   blocks:update(t)
   if t>.4 and not erupted then
    erupted=true;ctx.pose(entry,"slam",.12)
    hit(entry,centre,radius,if phase==2 then 31 else 26,ledger,"spiral")
    ctx.fx("referenceImpact",centre,{style="spiral",radius=radius})
   end
  end) then return end
  blocks:finish();ctx.pose(entry,"rest",.4);ctx.pause(entry,.6)
 end
 function moves.lance(entry,phase)
  local centre=target(entry);if not centre then return end
  entry.motion="hold";ctx.pose(entry,"gather",.35)
  local origin=ctx.hand(entry);local radius=if phase==2 then 12 else 10
  local plan=Terrain:PlanExcavation(columns(centre,radius,2),{maxCells=32})
  cast(entry,"LanceCast",origin,centre,5.4,radius)
  if not ctx.pause(entry,1.3) then return end
  ctx.pose(entry,"release",.18)
  if not ctx.pause(entry,.65) then return end
  ctx.pose(entry,"raise",.2)
  local blocks=displace(entry.scope,plan,centre,radius,"column")
  entry.model:SetAttribute("SignusLastMovedBlocks",blocks.count)
  local ledger={};local struck=false
  if not run(entry,2.65,function(t)
   blocks:update(t)
   if t>.23 and not struck then
    struck=true;hit(entry,centre,radius,if phase==2 then 36 else 30,ledger,"lance")
    ctx.fx("referenceImpact",centre,{style="lance",radius=radius})
   end
  end) then return end
  blocks:finish();ctx.pose(entry,"rest",.4);ctx.pause(entry,.8)
 end
 function moves.beam(entry,phase)
  local centre,root=target(entry);if not centre then return end
  entry.motion="scripted";entry.model:SetAttribute("SignusLastMovedBlocks",0);ctx.pose(entry,"gather",.4)
  local origin=ctx.hand(entry);local direction=ctx.flat(centre-origin)
  entry.look=direction;ctx.applyPose(entry)
  origin=ctx.hand(entry)
  local length=math.clamp((centre-origin).Magnitude+20,36,76)
  local endPoint=ctx.ground(origin+direction*length)+Vector3.yAxis*1.5
  -- Beam stops at real cover. Natural ground beneath its path is torn out;
  -- player walls and protected structures remain useful cover.
  local block=ctx.cover(origin,endPoint)
  if block then endPoint=block.Position end
  cast(entry,"RiftBeam",origin,endPoint,6.4,6)
  if not ctx.pause(entry,1.5) then return end
  ctx.pose(entry,"release",.12)
  local groups={};local ledger={};local nextLift=0;local tick=-1
  if not run(entry,3.5,function(t)
   local age=t*3.5
   if age>=nextLift and #groups<6 then
    local f=(#groups+1)/6;local p=ctx.ground(origin:Lerp(endPoint,f))
    local side=Vector3.new(-direction.Z,0,direction.X)
    local cols={}
    for j=-1,1 do local c=p+side*j*4;table.insert(cols,{x=c.X,z=c.Z,y=c.Y,depth=1}) end
    local plan=Terrain:PlanExcavation(cols,{maxCells=3})
    local moved=displace(entry.scope,plan,p,9,"throw")
    table.insert(groups,{moved=moved,at=age});nextLift+=.42
    entry.model:SetAttribute("SignusLastMovedBlocks",(entry.model:GetAttribute("SignusLastMovedBlocks") or 0)+moved.count)
   end
   for _,g in ipairs(groups) do local a=math.clamp((age-g.at)/1.1,0,1);g.moved:update(a);if a>=1 then g.moved:finish() end end
   local nowTick=math.floor(age/.5)
   if nowTick~=tick then
    tick=nowTick
    for _,p in ipairs(ctx.players()) do
     local pr=ctx.root(p)
     if pr then
      local delta=endPoint-origin;local f=math.clamp((pr.Position-origin):Dot(delta)/math.max(delta:Dot(delta),.01),0,1)
      if (pr.Position-origin:Lerp(endPoint,f)).Magnitude<6 and not ctx.cover(origin,pr.Position) then
       ctx.hit(ledger,"beam"..tick,p,8,if phase==2 then 40 else 32)
      end
     end
    end
   end
  end) then return end
  for _,g in ipairs(groups) do g.moved:finish() end
  ctx.pose(entry,"droop",.3);ctx.pause(entry,1.4)
 end
 function moves.totality(entry)
  entry.motion="hold";entry.hem=7;ctx.pose(entry,"raise",.65)
  local centre=ctx.ground(entry.position)
  ctx.sky(2,2.5)
  cast(entry,"Ascension",centre,centre,5,18)
  local plan=Terrain:PlanExcavation(columns(centre,18,1),{maxCells=28})
  if not ctx.pause(entry,1.25) then return end
  local blocks=displace(entry.scope,plan,centre,18,"orbit")
  entry.model:SetAttribute("SignusLastMovedBlocks",blocks.count)
  if not run(entry,3,function(t) blocks:update(t) end) then return end
  blocks:finish();ctx.eclipse(entry);entry.transformed=true
  if entry.aura then entry.aura:SetAttribute("Phase",2) end
  ctx.pose(entry,"rest",.6);entry.hem=2.5;ctx.pause(entry,.75)
 end
 return moves
end
return Moves
