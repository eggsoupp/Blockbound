local RS = game:GetService("ReplicatedStorage")
local f = RS:WaitForChild("CombatHoldResults3", 60)
f:GetAttributeChangedSignal("Command"):Connect(function()
	local tool = game.Players.LocalPlayer.Character:FindFirstChild("CombatHoldProbeTool")
	if tool then
		if f:GetAttribute("Command") == "hold" then tool:Activate() else tool:Deactivate() end
	end
end)
