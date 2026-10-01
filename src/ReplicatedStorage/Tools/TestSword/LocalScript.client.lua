--[[
	TestSword

	Keeps the sword's handle welded to the hand while it is equipped.

	TWO FIXES
	  It used to call `handle:FindFirstChildWhichIsA("WeldConstraint").Destroy()`
	  on both equip and unequip. That is wrong twice over: FindFirstChild returns
	  nil when there is no weld yet - which is the normal case on the first equip
	  - and `.Destroy()` with a dot rather than a colon passes no self. Equipping
	  the sword threw every time.

	  The swing animation that used to live here has moved to
	  StarterPlayerScripts.ToolFeedback, which does it for every tool rather than
	  just this one. It also tweened the handle's world CFrame, which fought the
	  weld it had just created.
]]

local Players = game:GetService("Players")

local tool = script.Parent
local player = Players.LocalPlayer
local handle = tool:WaitForChild("Handle")

local WELD_NAME = "SwordGripWeld"

local function clearWeld()
	local existing = handle:FindFirstChild(WELD_NAME)
	if existing then
		existing:Destroy()
	end
end

local function attachHandle()
	local character = player.Character
	if not character then
		return
	end

	local hand = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	if not hand then
		return
	end

	clearWeld()

	local weld = Instance.new("WeldConstraint")
	weld.Name = WELD_NAME
	weld.Part0 = handle
	weld.Part1 = hand
	weld.Parent = handle
end

tool.Equipped:Connect(function()
	handle.Anchored = false
	handle.CanCollide = false
	attachHandle()
end)

tool.Unequipped:Connect(function()
	clearWeld()
	handle.Anchored = true
	handle.CanCollide = true
end)
