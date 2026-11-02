-- Broad bounds work for terrain blocks, but a one-mesh tree includes empty air
-- beside its trunk. Only those tree candidates need a collision-shape query.
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Geometry = {}
local probe
local treeParams = OverlapParams.new()
treeParams.FilterType = Enum.RaycastFilterType.Include

function Geometry.isCellBlocked(center, grid, overlapParams)
	local size = Vector3.one * (grid - .1)
	local candidates = Workspace:GetPartBoundsInBox(CFrame.new(center), size, overlapParams)
	local trees = {}
	for _, part in ipairs(candidates) do
		if part.CanCollide then
			if CollectionService:HasTag(part, "TreePart") then
				table.insert(trees, part)
			else
				return true
			end
		end
	end
	if #trees == 0 then return false end
	if not probe or not probe.Parent then
		probe = Instance.new("Part")
		probe.Name = "PlacementCollisionProbe"
		probe.Anchored, probe.Transparency = true, 1
		probe.CanCollide, probe.CanTouch, probe.CanQuery = false, false, false
		probe.CastShadow = false
		probe.Parent = Workspace
	end
	probe.Size, probe.CFrame = size, CFrame.new(center)
	treeParams.FilterDescendantsInstances = trees
	return #Workspace:GetPartsInPart(probe, treeParams) > 0
end

return Geometry
