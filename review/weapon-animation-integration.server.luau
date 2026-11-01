-- Temporary integration harness; removed after playtest.
local RS=game:GetService('ReplicatedStorage')
local P=game:GetService('Players')
local Run=game:GetService('RunService')
local E=require(game.ServerScriptService.EnemyService)
local W=require(RS.Shared.Combat.WeaponAnimations)
local Config=require(RS.Shared.Combat.WeaponConfig)
local f=Instance.new('Folder') f.Name='CombatIntegrationResults' f.Parent=RS
local realNear,realDamage=E.forEachNear,E.damage
local target=Instance.new('Model') target.Name='CombatTestTarget'
local part=Instance.new('Part') part.Anchored=true part.Transparency=1 part.Size=Vector3.new(2,2,2) part.Parent=target target.PrimaryPart=part target.Parent=workspace
local pos=Vector3.zero local hits={}
E.forEachNear=function(origin,range,visit)
 if (pos-origin).Magnitude<=range then visit(target,pos) end
end
E.damage=function(model,damage,dealer)
 if model==target then table.insert(hits,{time=workspace:GetServerTimeNow(),damage=damage}) return true end
 return realDamage(model,damage,dealer)
end
local function waitUntil(fn,timeout)
 local endAt=os.clock()+timeout repeat if fn() then return true end task.wait(.01) until os.clock()>endAt return false
end
local function run()
 local p=P:GetPlayers()[1] or P.PlayerAdded:Wait()
 local c=p.Character or p.CharacterAdded:Wait()
 local root=c:WaitForChild('HumanoidRootPart',60)
 local h=c:WaitForChild('Humanoid')
 h.MaxHealth=100000 h.Health=100000 root.Anchored=true
 root.CFrame=CFrame.new(0,500,0)
 task.wait(10)
 for _,t in c:GetChildren() do if t:IsA('Tool') then t.Parent=p.Backpack end end
 local report={}
 local serial=0
 local function input(kind,tool)
  serial+=1 f:SetAttribute('ToolName',tool.Name) f:SetAttribute('Command',kind) f:SetAttribute('InputStage',serial)
 end
 for _,item in {'Bloodfang','Thunderveil','LightLance'} do
  local tool=RS.Tools[item]:Clone() tool.Name='CombatTest_'..item tool:SetAttribute('ItemName',item) tool.Parent=c
  local stats=Config.get(item) local speed=.55/stats.cooldown local profile=W.forClass(stats.weaponClass)
  task.wait(2)
  for index,step in profile.steps do
   hits={} pos=root.Position+Vector3.new(0,0,-10) target:PivotTo(CFrame.new(pos))
   local prior=tool:GetAttribute('AttackStarted')
   input('tap',tool)
   assert(waitUntil(function()return tool:GetAttribute('AttackStarted')~=prior end,15),'Attack did not start: '..item..index)
   local began=tool:GetAttribute('AttackStarted')
   assert(tool:GetAttribute('AttackStep')==index,'Wrong combo index')
   task.wait(step.hitEnd/speed+.08)
   assert(#hits==1,'Expected one damage application: '..item..index..' got '..#hits)
   local delta=hits[1].time-began
   assert(delta>=step.hit/speed-.01,'Damage before contact')
   assert(delta<=step.hit/speed+.09,'Damage too late: '..delta)
   local expected=math.floor(stats.damage*step.damage+.5)
   assert(hits[1].damage==expected,'Damage mismatch')
   table.insert(report,{item=item,step=index,expected=step.hit/speed,actual=delta,damage=hits[1].damage})
   task.wait(math.max(0,step.recover/speed-(workspace:GetServerTimeNow()-began))+.05)
  end
  tool:Destroy() task.wait(1)
 end
 -- Geometry and cancellation, always fresh combo; await prior recovery.
 local function case(name,offset,command,expect,moveLate)
  local tool=RS.Tools.Bloodfang:Clone() tool.Name='CombatTest_Geometry' tool:SetAttribute('ItemName','Bloodfang') tool.Parent=c task.wait(.5)
  hits={} pos=root.Position+offset target:PivotTo(CFrame.new(pos))
  input(command or 'tap',tool)
  assert(waitUntil(function()return tool:GetAttribute('AttackStarted')~=nil end,10),'Case did not start')
  if moveLate then task.delay(.29,function()pos=root.Position+Vector3.new(0,0,-10) target:PivotTo(CFrame.new(pos))end) end
  task.wait(.65)
  assert(#hits==expect,name..': '..#hits..' hits instead of '..expect)
  table.insert(report,{case=name,hits=#hits})
  tool:Destroy() task.wait(1)
 end
 case('side forgiveness',Vector3.new(10,0,0),'tap',1)
 case('touching behind',Vector3.new(0,0,3),'tap',1)
 case('distant behind misses',Vector3.new(0,0,10),'tap',0)
 case('outside reach misses',Vector3.new(0,0,-20),'tap',0)
 case('enters contact window',Vector3.new(0,0,-20),'tap',1,true)
 case('unequip during windup',Vector3.new(0,0,-10),'cancel',0)
 -- Invalid input cannot damage while no weapon is equipped.
 hits={} input('invalid',Instance.new('Tool')) task.wait(.5)
 assert(#hits==0,'Invalid input dealt damage')
 f:SetAttribute('Report',game:GetService('HttpService'):JSONEncode(report))
 f:SetAttribute('Passed',true)
end
local ok,err=pcall(run)
E.forEachNear,E.damage=realNear,realDamage
target:Destroy()
f:SetAttribute('Finished',true)
if not ok then f:SetAttribute('Error',tostring(err)) warn('Combat integration: '..tostring(err)) end
