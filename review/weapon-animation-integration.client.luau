local p=game.Players.LocalPlayer
local RS=game:GetService('ReplicatedStorage')
local f=RS:WaitForChild('CombatIntegrationResults',60)
local remote=RS:WaitForChild('Remotes'):WaitForChild('WeaponInput')
local last=0
local function stage()
 local n=f:GetAttribute('InputStage') if not n or n==last then return end last=n
 local cmd=f:GetAttribute('Command')
 if cmd=='invalid' then remote:FireServer(workspace,true) remote:FireServer(nil,true) return end
 local c=p.Character local t=c and c:FindFirstChild(f:GetAttribute('ToolName')) if not t then return end
 t:Activate()
 task.wait(.025) t:Deactivate()
 if cmd=='cancel' then task.wait(.05) t.Parent=p.Backpack end
end
f:GetAttributeChangedSignal('InputStage'):Connect(function()task.spawn(stage)end)
stage()
