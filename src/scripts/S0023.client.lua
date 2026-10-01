local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local RunService=game:GetService('RunService')
local Shared=RS:WaitForChild('Shared')
local Remotes=require(Shared.Net.Remotes)
local Theme=require(Shared.UI.Theme)
local Config=require(Shared.Abilities.AbilityConfig)
local Changed=Remotes.wait('PrivateScrollChanged')
local Request=Remotes.wait('ScrollChestRequest')
local model,spin,currentToken
local function clear()
 if spin then spin:Disconnect();spin=nil end
 if model then model:Destroy();model=nil end
 currentToken=nil
end
Changed.OnClientEvent:Connect(function(packet)
 if type(packet)=='table' and packet.token==currentToken then return end
 clear()
 if type(packet)~='table' or typeof(packet.position)~='Vector3' then return end
 local definition=Config.get(packet.ability);if not definition then return end
 currentToken=packet.token
 model=Instance.new('Model');model.Name='YourScroll';model.Parent=workspace
 local function part(name,size,color,y)
  local p=Instance.new('Part');p.Name=name;p.Shape=Enum.PartType.Cylinder
  p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
  p.Size=size;p.Color=color;p.CFrame=CFrame.new(0,y,0)*CFrame.Angles(0,0,math.pi/2);p.Parent=model
  return p
 end
 local paper=part('Paper',Vector3.new(1.8,.65,.65),Color3.fromRGB(238,226,196),0)
 model.PrimaryPart=paper
 for _,y in ipairs({-.9,.9}) do
  part('Band',Vector3.new(.16,.8,.8),Theme.rarityColor(definition.rarity),y).Material=Enum.Material.Neon
 end
 local prompt=Instance.new('ProximityPrompt');prompt.ActionText='Learn';prompt.ObjectText=(definition.displayName or packet.ability)..' Scroll'
 prompt.HoldDuration=.6;prompt.MaxActivationDistance=10;prompt.RequiresLineOfSight=false;prompt.Parent=paper
 prompt.Triggered:Connect(function() Request:FireServer('claim',packet.token) end)
 local start=os.clock()
 local function update()
  local age=os.clock()-start
  model:PivotTo(CFrame.new(packet.position+Vector3.new(0,math.sin(age*2)*.2,0))*CFrame.Angles(0,age*.7,math.pi/2))
 end
 update();spin=RunService.Heartbeat:Connect(update)
end)
task.spawn(function()
 for i=1,5 do Request:FireServer('sync');task.wait(2) end
end)
Players.LocalPlayer.CharacterAdded:Connect(function() task.delay(2,function() Request:FireServer('sync') end) end)
