--[[
	HallowTreeRainbow

	Cycles the leaves of Hallow-biome trees through the spectrum.

	Client-side on purpose: this once ran on the server, and a Color write on a
	server-owned part replicates - one network update per leaf per frame, for a
	purely cosmetic effect.

	Registration hangs off the "TreePart" tag StructureRegistry already applies,
	so leaves are picked up as their chunk streams in. Scanning the workspace at
	startup found nothing, because terrain arrives afterwards.

	Two kinds of leaf. A tree built from separate parts has parts named
	"leaves", and their Color is cycled. The voxel-pack Hallow trees are one
	mesh each, so their leaves cannot be a part of their own: a TintMask
	SurfaceAppearance carries them instead, whose texture is grey where the
	leaves are and masked off on the trunk, and its Color is what cycles.
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

-- The instance whose Color is the leaf colour - the part itself, or a tinted
-- SurfaceAppearance on it - or nil for anything that is not a Hallow leaf.
local function hallowLeaf(part)
	if not part:IsA("BasePart") then
		return nil
	end

	local model = part:FindFirstAncestorOfClass("Model")
	if not model or string.sub(model.Name, 1, #MODEL_PREFIX) ~= MODEL_PREFIX then
		return nil
	end

	local tint = part:FindFirstChildOfClass("SurfaceAppearance")
	if tint and tint.AlphaMode == Enum.AlphaMode.TintMask then
		return tint
	end

	if string.find(string.lower(part.Name), LEAF_MATCH, 1, true) then
		return part
	end
	return nil
end

local function register(part)
	local leaf = hallowLeaf(part)
	if leaf then
		leafCount += 1
		leaves[leafCount] = leaf
	end
end

for _, part in ipairs(CollectionService:GetTagged(TREE_TAG)) do
	register(part)
end
-- Deferred: a streamed part's tag can arrive a moment before its children, and
-- the SurfaceAppearance is one of them.
CollectionService:GetInstanceAddedSignal(TREE_TAG):Connect(function(part)
	task.defer(register, part)
end)

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
				if leaf and leaf.Parent and leaf.Parent.Parent then
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
