--[[
	GroundCoverLOD

	Applies the Detail setting to the ground cover the server scatters -
	flowers, shrubs, mushrooms, rocks, logs. Every part of it carries the
	"GroundCover" tag (StructureRegistry). Low hides all of it; High shows it.

	Hidden locally, not removed: LocalTransparencyModifier takes it off screen,
	and CanCollide and CanQuery off take it out of this player's way, so a
	hidden log is not an invisible wall. The server's copy is untouched, and the
	map streams, so a chunk that comes back is caught by the tag signal.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerSettings = require(Shared:WaitForChild("UI"):WaitForChild("PlayerSettings"))

local TAG = "GroundCover"

-- part -> { collide, query } as the server set them, for putting back.
local original = setmetatable({}, { __mode = "k" })

local hidden = PlayerSettings.get("detailLevel") == "Low"

local function apply(part: BasePart)
	if hidden then
		if not original[part] then
			original[part] = { part.CanCollide, part.CanQuery }
		end
		part.LocalTransparencyModifier = 1
		part.CanCollide = false
		part.CanQuery = false
	else
		local saved = original[part]
		part.LocalTransparencyModifier = 0
		if saved then
			part.CanCollide = saved[1]
			part.CanQuery = saved[2]
			original[part] = nil
		end
	end
end

local function applyAll()
	for _, part in ipairs(CollectionService:GetTagged(TAG)) do
		if part:IsA("BasePart") then
			apply(part)
		end
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(part)
	if part:IsA("BasePart") and hidden then
		apply(part)
	end
end)

PlayerSettings.Changed.Event:Connect(function(key, value)
	if key == "detailLevel" then
		local wasHidden = hidden
		hidden = value == "Low"
		if hidden ~= wasHidden then
			applyAll()
		end
	end
end)

if hidden then
	applyAll()
end
