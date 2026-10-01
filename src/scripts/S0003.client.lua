local prompt = workspace:WaitForChild("SomePart"):WaitForChild("ProximityPrompt")

prompt.Triggered:Connect(function()
	print("client sent")
end)