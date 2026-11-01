local RS=game.ReplicatedStorage
local f=Instance.new('Folder') f.Name='CombatHoldResults3' f.Parent=RS
local p=game.Players:GetPlayers()[1]

local E=require(game.ServerScriptService.EnemyService)
local W=require(RS.Shared.Combat.WeaponAnimations)
local c=p.Character local root=c.HumanoidRootPart
local dummy=Instance.new('Model') local part=Instance.new('Part') part.Size=Vector3.new(2,2,2) part.Anchored=true part.Transparency=1 part.Parent=dummy dummy.PrimaryPart=part dummy.Parent=workspace
local pos=root.Position+Vector3.new(0,0,-10) dummy:PivotTo(CFrame.new(pos))
local near,damage=E.forEachNear,E.damage local hits={}
local tool=RS.Tools.Bloodfang:Clone() tool.Name='CombatHoldProbeTool' tool:SetAttribute('ItemName','MythrilSword')
E.forEachNear=function(origin,range,visit) if (pos-origin).Magnitude<=range then visit(dummy,pos) end end
E.damage=function(model,amount,dealer)
 if model~=dummy then return damage(model,amount,dealer) end
 local index=tool:GetAttribute('AttackStep')
 local profile=W.Classes.Sword.steps[index]
 local trackTime=nil
 for _,track in c.Humanoid.Animator:GetPlayingAnimationTracks() do
  if track.Animation.AnimationId==profile.animationId then trackTime=track.TimePosition end
 end
 table.insert(hits,{step=index,amount=amount,elapsed=workspace:GetServerTimeNow()-tool:GetAttribute('AttackStarted'),expected=profile.hit/1.25,trackTime=trackTime})
 return true
end
local ok,err=pcall(function()
 tool.Parent=c task.wait(2) f:SetAttribute('Command','hold')
 local deadline=os.clock()+15
 repeat task.wait(.01) until tool:GetAttribute('AttackStep')==5 or os.clock()>deadline
 assert(tool:GetAttribute('AttackStep')==5,'Held combo did not reach five')
 f:SetAttribute('Command','release')
 task.wait(.65)
 assert(#hits==5,'Expected exactly five hits, got '..#hits)
 for i,hit in hits do
  assert(hit.step==i,'Wrong held combo step')
  assert(hit.elapsed>=hit.expected-.01 and hit.elapsed<=hit.expected+.09,'Attack speed timing mismatch')
  assert(hit.trackTime and math.abs(hit.trackTime-W.Classes.Sword.steps[i].hit)<.10,'Animation was not at its contact pose')
 end
 f:SetAttribute('Passed',true)
end)
f:SetAttribute('Report',game:GetService('HttpService'):JSONEncode(hits))
if not ok then f:SetAttribute('Error',tostring(err)) end
E.forEachNear,E.damage=near,damage
tool:Destroy() dummy:Destroy()
f:SetAttribute('Finished',true)
