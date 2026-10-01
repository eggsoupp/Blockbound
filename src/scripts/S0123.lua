local ReplicatedStorage=game:GetService('ReplicatedStorage')
local ServerScriptService=game:GetService('ServerScriptService')
local Players=game:GetService('Players')
local Plan=require(ReplicatedStorage.Shared.Abilities.ElementalPlan)
local CombatService=require(ServerScriptService:WaitForChild('CombatService'))
local EnemyService=require(ServerScriptService:WaitForChild('EnemyService'))
local Attack={}
function Attack.duration() return Plan.duration() end
function Attack.cast(context)
 local tuning=Plan.Tuning[context.abilityName]
 if not tuning then return false end
 local params=RaycastParams.new()
 params.FilterType=Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances={context.character}
 local packet=Plan.build(context.abilityName,context.origin,context.target,function(a,b)
  return workspace:Raycast(a,b,params)
 end)
 packet.origin=context.origin
 packet.startedAt=workspace:GetServerTimeNow()
 context.broadcast(packet)
 context.scope:delay(packet.impactAt,function()
  local seen={}
  local function amount(position)
   local distance=(position-packet.impact).Magnitude
   if distance>tuning.radius then return 0 end
   return tuning.damage*(1-.35*math.clamp(distance/tuning.radius,0,1))
  end
  EnemyService.forEachNear(packet.impact,tuning.radius,function(model,position)
   if seen[model] then return end
   seen[model]=true
   local damage=amount(position)
   if damage>0 then EnemyService.damage(model,damage,context.player) end
  end)
  for _,player in ipairs(Players:GetPlayers()) do
   if player==context.player then continue end
   local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if root and root:IsA('BasePart') then
    local damage=amount(root.Position)
    if damage>0 then CombatService.applyDamage(player,damage,context.abilityName) end
   end
  end
 end)
 return true
end
return Attack
