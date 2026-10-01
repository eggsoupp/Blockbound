-- Only this service chooses and grants chest rewards. No scroll reward is replicated globally.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SSS=game:GetService('ServerScriptService')
local Http=game:GetService('HttpService')
local Shared=RS:WaitForChild('Shared')
local Remotes=require(Shared.Net.Remotes)
local Config=require(Shared.Abilities.AbilityConfig)
local Loadout=require(SSS.AbilityLoadout)
local Inventory=require(SSS.InventoryService)
local Store=require(SSS.InventoryStore)
local Feedback=require(SSS.CommandFeedback)
local Request=Remotes.ensure('ScrollChestRequest','RemoteEvent')
local Changed=Remotes.ensure('PrivateScrollChanged','RemoteEvent')
local pending=setmetatable({}, {__mode="k"})
local ready,busy,last={},{},{}
local random=Random.new()
local function locate(player,record)
 local character=player.Character;local root=character and character:FindFirstChild('HumanoidRootPart')
 if not root then return false end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={character}
 local position=(root.CFrame*CFrame.new(0,0,-6)).Position
 local hit=workspace:Raycast(position+Vector3.new(0,4,0),Vector3.new(0,-40,0),params)
 record.position=(if hit then hit.Position else position)+Vector3.new(0,1.4,0)
 record.token=Http:GenerateGUID(false);record.spawned=os.clock();return true
end
local function push(player,relocate)
 local record=pending[player]
 if record and (relocate or not record.position) then locate(player,record) end
 Changed:FireClient(player,if record and record.position then {token=record.token,ability=record.ability,position=record.position} else false)
end
Store.registerSection('privateScroll',function(player)
 local record=pending[player]
 return record and {ability=record.ability} or nil
end,function(player,value)
 pending[player]=nil
 if type(value)=='table' and type(value.ability)=='string' and Config.get(value.ability) then pending[player]={ability=value.ability} end
 ready[player]=true;push(player,false)
end)
Request.OnServerEvent:Connect(function(player,action,value)
 if busy[player] or os.clock()-(last[player] or -10)<.3 then return end
 last[player]=os.clock();busy[player]=true
 local ok,err=pcall(function()
  if not ready[player] or Inventory.IsLoading(player) or not Inventory.GetInventory(player) or Store.isReadOnly(player) then return end
  if action=='sync' then push(player,false);return end
  local character=player.Character;local root=character and character:FindFirstChild('HumanoidRootPart')
  local humanoid=character and character:FindFirstChildOfClass('Humanoid')
  if not root or not humanoid or humanoid.Health<=0 then return end
  if action=='open' then
   if pending[player] then push(player,false);Feedback.tell(player,'Collect your previous scroll before opening another chest.','bad');return end
   if type(value)~='number' or value%1~=0 or value<1 or value>9 then return end
   local name,count=Inventory.GetSlot(player,value)
   if name~='ScrollChest' or count<1 then return end
   local pool={}
   for _,ability in ipairs(Config.names()) do
    if not Loadout.has(player,ability) and not Loadout.isStored(player,ability) then table.insert(pool,ability) end
   end
   if #pool==0 then Feedback.tell(player,'You already own every available ability. Your chest was kept.','bad');return end
   local record={ability=pool[random:NextInteger(1,#pool)]}
   if not locate(player,record) then return end
   -- The reward section is present when the same inventory record is marked dirty.
   pending[player]=record
   local consumed=Inventory.RemoveItemByName(player,'ScrollChest',1)
   if not consumed then pending[player]=nil;return end
   Store.markDirty(player);push(player,false)
   Feedback.tell(player,'Your scroll appeared in front of you. Only you can collect it.','good')
  elseif action=='claim' then
   local record=pending[player]
   if not record or type(value)~='string' or value~=record.token or not record.position then return end
   if os.clock()-record.spawned<.5 or (root.Position-record.position).Magnitude>12 then return end
   local granted,message=Loadout.add(player,record.ability)
   if not granted then Feedback.tell(player,message,'bad');return end
   pending[player]=nil;Store.markDirty(player);push(player,false)
   Feedback.tell(player,message,'good')
  end
 end)
 busy[player]=nil
 if not ok then warn('[ScrollChest]',err);Feedback.tell(player,'The chest could not be processed. Please try again.','bad') end
end)
local function watch(player)
 player.CharacterAdded:Connect(function()
  task.delay(1,function() if player.Parent then push(player,true) end end)
 end)
end
Players.PlayerAdded:Connect(watch)
for _,player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerRemoving:Connect(function(player) ready[player]=nil;busy[player]=nil;last[player]=nil end)
