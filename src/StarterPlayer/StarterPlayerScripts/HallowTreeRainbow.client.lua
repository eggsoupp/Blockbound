--[[
	HallowTreeRainbow

	Cycles the leaves of Hallow-biome trees through the spectrum.

	Client-side on purpose: this once ran on the server, and a Color write on a
	server-owned part replicates - one network update per leaf per frame, for a
	purely cosmetic effect.

	Registration hangs off the "TreePart" tag StructureRegistry already applies,
	so leaves are picked up as their chunk streams in. Scanning the workspace at
	startup found nothing, because terrain arrives afterwards.
]]

local CollectionService = game:GetService("CollectionService")

-- Applied to every BasePart of a placed tree by StructureRegistry.
local TREE_TAG = "TreePart"

-- Models the generator names for the Hallow biome (StructureConfig.nameFormat
-- "%sTree" plus the biome name).
local MODEL_PREFIX = "Hallow"
local LEAF_MATCH = "leaves"

-- 20Hz is indistinguishable from per-frame for a colour this slow, at a third
-- of the cost. The hue rate matches what the server version used.
local UPDATE_INTERVAL = 1 / 20
local HUE_PER_SECOND = 0.12

local leaves = {}
local leafCount = 0

local function isHallowLeaf(part)
	if not part:IsA("BasePart") then
		return false
	end

	if not string.find(string.lower(part.Name), LEAF_MATCH, 1, true) then
		return false
	end

	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and string.sub(model.Name, 1, #MODEL_PREFIX) == MODEL_PREFIX
end

local function register(part)
	if isHallowLeaf(part) then
		leafCount += 1
		leaves[leafCount] = part
	end
end

for _, part in ipairs(CollectionService:GetTagged(TREE_TAG)) do
	register(part)
end
CollectionService:GetInstanceAddedSignal(TREE_TAG):Connect(register)

task.spawn(function()
	local hue = 0

	while true do
		local dt = task.wait(UPDATE_INTERVAL)

		if leafCount > 0 then
			hue = (hue + HUE_PER_SECOND * dt) % 1
			local color = Color3.fromHSV(hue, 1, 1)

			-- Swap-remove leaves whose chunk has streamed out, so the list stays
			-- the length of what is actually on screen.
			for i = leafCount, 1, -1 do
				local leaf = leaves[i]
				if leaf and leaf.Parent then
					leaf.Color = color
				else
					leaves[i] = leaves[leafCount]
					leaves[leafCount] = nil
					leafCount -= 1
				end
			end
		end
	end
end)
