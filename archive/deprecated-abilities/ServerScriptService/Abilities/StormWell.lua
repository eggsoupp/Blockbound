local RS=game:GetService('ReplicatedStorage')
local SSS=game:GetService('ServerScriptService')
local Players=game:GetService('Players')
local Plan=require(RS.Shared.Abilities.StormWellPlan)
local EnemyService=require(SSS:WaitForChild('EnemyService'))
local CombatService=require(SSS:WaitForChild('CombatService'))
local Attack={}
function Attack.duration() return Plan.duration() end
function Attack.cast(context)
 local params=RaycastParams.new()
 params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={context.character}
 local hit=workspace:Raycast(context.target+Vector3.new(0,3,0),Vector3.new(0,-18,0),params)
 local centre=if hit then hit.Position else context.target
 context.broadcast({origin=CFrame.new(centre),startedAt=workspace:GetServerTimeNow()})
 for index,at in ipairs(Plan.Hits) do
  context.scope:delay(at,function()
   local seen={}
   local function amount(position)
    local d=(position-centre).Magnitude
    return if d<=Plan.Radius then (if index==#Plan.Hits then Plan.FinalDamage else Plan.Damage)*(1-.3*d/Plan.Radius) else 0
   end
   EnemyService.forEachNear(centre,Plan.Radius,function(model,position)
    if seen[model] then return end;seen[model]=true
    local damage=amount(position)
    if damage>0 then context.damage(model,damage) end
   end)
   for _,victim in ipairs(Players:GetPlayers()) do
    if victim==context.player then continue end
    local root=victim.Character and victim.Character:FindFirstChild('HumanoidRootPart')
    if root and root:IsA('BasePart') then
     local damage=amount(root.Position)
     if damage>0 then CombatService.applyDamage(victim,damage,context.abilityName) end
    end
   end
  end)
 end
 return true
end
return Attack
