--[[
	DISABLED (default.project.json) - superseded by
	StarterPlayerScripts.HallowTreeRainbow, which colours the generated
	Hallow trees on each client instead of replicating a Color write per leaf
	per frame. Nothing in the place is named "hallowTree1" any more, so this
	only cost a callback for every instance added to the workspace and an
	empty loop every Heartbeat. Kept for reference.
]]

-- Services
local RunService = game:GetService("RunService")

-- Table to store all leaves that need to be rainbowed
local rainbowLeaves = {}

-- Function to register all leaves under a given tree model
local function registerLeaves(tree)
	for _, descendant in ipairs(tree:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name:lower():find("leaves") then
			table.insert(rainbowLeaves, descendant)
		end
	end
end

-- Detect when hallowTree1 models are added to workspace
workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Model") and descendant.Name == "hallowTree1" then
		registerLeaves(descendant)
	end
end)

-- Also register any trees that already exist
for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("Model") and descendant.Name == "hallowTree1" then
		registerLeaves(descendant)
	end
end

-- Clean up removed leaves automatically
for _, leaf in ipairs(rainbowLeaves) do
	leaf.AncestryChanged:Connect(function(_, parent)
		if not parent then
			table.remove(rainbowLeaves, table.find(rainbowLeaves, leaf))
		end
	end)
end

-- Single rainbow update loop (very efficient)
task.spawn(function()
	local hue = 0
	while true do
		hue = (hue + 0.002) % 1
		local color = Color3.fromHSV(hue, 1, 1)
		for i = #rainbowLeaves, 1, -1 do
			local leaf = rainbowLeaves[i]
			if leaf and leaf.Parent then
				leaf.Color = color
			else
				table.remove(rainbowLeaves, i)
			end
		end
		RunService.Heartbeat:Wait()
	end
end)
