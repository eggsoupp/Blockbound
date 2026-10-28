--[[
	Builds one creature into ServerStorage._NewCreatures from a boxes/*.lua file.

	Run in Studio's command bar (or an MCP Edit execute) after pasting the
	contents of a boxes file over `DATA` below, then move the result into
	ReplicatedStorage.EnemyAssets. Voxel sizes used for the shipped assets:

	  Cobra 0.085   Snowman 0.115
	  Lasereye 0.095   GreenWasp 0.065   Shrike 0.2 (boxes exported at factor 2)

	Every box becomes a Part, then the lot is unioned into one PartOperation
	with UsePartColor off, so the per-voxel colours survive and the enemy is a
	single anchored part (cheap to PivotTo, and a SlimeBody can deform it).
	The model's pivot is its feet, centred.
]]

local DATA = nil -- paste: { name = ..., dims = {...}, colors = "...", boxes = "..." }
local VOXEL = 0.1
local ASSET_NAME = "Creature"

local function build(data, voxel, assetName)
	local colors = {}
	for r, g, b in string.gmatch(data.colors, "(%d+),(%d+),(%d+)") do
		table.insert(colors, Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)))
	end
	local dims = data.dims
	local origin = Vector3.new(0, 500, 0)
	local folder = Instance.new("Folder")
	folder.Name = "_CreatureBuild"
	local parts = {}
	for x, y, z, w, h, d, c in string.gmatch(data.boxes, "(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)") do
		x, y, z, w, h, d, c = tonumber(x), tonumber(y), tonumber(z), tonumber(w), tonumber(h), tonumber(d), tonumber(c)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Color = colors[c]
		p.Size = Vector3.new(w, h, d) * voxel
		p.Position = origin + Vector3.new(x + w / 2 - dims[1] / 2, y + h / 2, z + d / 2 - dims[3] / 2) * voxel
		p.Parent = folder
		table.insert(parts, p)
	end
	folder.Parent = workspace
	task.wait()

	local first = table.remove(parts, 1)
	local union = first:UnionAsync(parts, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	union.UsePartColor = false
	union.Name = "Body"
	union.Anchored = true
	union.CanCollide = false
	union.CanTouch = false

	local model = Instance.new("Model")
	model.Name = assetName
	union.Parent = model
	model.PrimaryPart = union
	model.WorldPivot = CFrame.new(origin)
	folder:Destroy()
	model:PivotTo(CFrame.new())

	local stage = game.ServerStorage:FindFirstChild("_NewCreatures") or Instance.new("Folder")
	stage.Name = "_NewCreatures"
	stage.Parent = game.ServerStorage
	model.Parent = stage
	return model
end

if DATA then
	build(DATA, VOXEL, ASSET_NAME)
end
