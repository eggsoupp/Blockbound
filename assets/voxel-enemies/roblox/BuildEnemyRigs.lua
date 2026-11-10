--[[
	BuildEnemyRigs (Studio, Edit only)

	Turns the box data written by ../source/build.pl into animation-ready
	rigs. One Model per creature:

	  <Name>                       Model, PrimaryPart = HumanoidRootPart
	    AnimationController
	      Animator
	    HumanoidRootPart           invisible, anchored, at the root pivot
	    <Part>                     one union per rig part (Torso, RightScythe, ...)
	      <Part>  Motor6D          joins it to its parent part at the pivot
	                               (the root part's joint is "Root", to the HRP)

	Every Motor6D's C0 and C1 are axis-aligned at its pivot, so Transform
	rotates the part about the joint in the model's axes: +X the creature's
	right, +Y up, front -Z. Rest pose = all Transforms identity, so the rigs
	open straight in the Animation Editor.

	Load a Folder holding this module and the Data modules, then
	  require(folder.BuildEnemyRigs)(folder.Data.AshenLich, { parent = ReplicatedStorage.EnemyRigs })
]]

local function settle(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- One part from many. The CSG kernel sometimes refuses a large set, so a
-- refused set is halved and the halves joined.
local function union(parts, name)
	if #parts == 1 then
		return parts[1]
	end
	local first = parts[1]
	local rest = table.move(parts, 2, #parts, 1, {})
	local ok, result = pcall(function()
		return first:UnionAsync(rest, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	end)
	if ok then
		for _, p in parts do p:Destroy() end
		return result
	end
	local half = math.floor(#parts / 2)
	local a = table.move(parts, 1, half, 1, {})
	local b = table.move(parts, half + 1, #parts, 1, {})
	local left, right = union(a, name), union(b, name)
	local ok2, joined = pcall(function()
		return left:UnionAsync({ right }, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	end)
	if ok2 then
		left:Destroy()
		right:Destroy()
		return joined
	end
	-- Keep two pieces: the second is welded to the first.
	warn("[BuildEnemyRigs] " .. name .. " stays in two pieces: " .. tostring(joined))
	right.Name = name .. "Extra"
	right.Parent = left
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = left, right
	weld.Parent = right
	return left
end

return function(data, opts)
	opts = opts or {}
	local voxel = data.voxel
	local origin = opts.origin or Vector3.new(0, 900, 0)

	local colors = {}
	for i, c in data.colors do
		colors[i] = { color = Color3.fromRGB(c[2], c[3], c[4]), glow = c[5] }
	end

	local stage = Instance.new("Folder")
	stage.Name = "_EnemyRigBuild"
	stage.Parent = workspace

	local model = Instance.new("Model")
	model.Name = data.name
	local parts = {}
	local boxCount = 0
	for _, spec in data.parts do
		local list = {}
		for x, y, z, w, h, d, c in string.gmatch(spec.boxes, "(-?%d+),(-?%d+),(-?%d+),(%d+),(%d+),(%d+),(%d+)") do
			x, y, z, w, h, d, c = tonumber(x), tonumber(y), tonumber(z), tonumber(w), tonumber(h), tonumber(d), tonumber(c)
			local b = Instance.new("Part")
			settle(b)
			b.Size = Vector3.new(w, h, d) * voxel
			b.Position = origin + Vector3.new(x + (w - 1) / 2, y + (h - 1) / 2, z + (d - 1) / 2) * voxel
			local col = colors[c]
			b.Color = col.color
			b.Material = if col.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
			b.Parent = stage
			table.insert(list, b)
		end
		boxCount += #list
		local part = union(list, spec.name)
		part.Name = spec.name
		if part:IsA("UnionOperation") then
			part.UsePartColor = false
		end
		settle(part)
		part.Massless = true
		part.Parent = model
		parts[spec.name] = part
		task.wait()
	end

	local rootSpec = data.parts[1]
	local rootPivot = origin + Vector3.new(table.unpack(rootSpec.pivot)) * voxel
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	settle(hrp)
	hrp.Transparency = 1
	hrp.CanQuery = false
	hrp.Size = Vector3.new(4, 4, 2) * (voxel / 0.2)
	hrp.CFrame = CFrame.new(rootPivot)
	hrp.Parent = model

	for _, spec in data.parts do
		local child = parts[spec.name]
		local parent = if spec.parent then parts[spec.parent] else hrp
		local at = CFrame.new(origin + Vector3.new(table.unpack(spec.pivot)) * voxel)
		local joint = Instance.new("Motor6D")
		joint.Name = if spec.parent then spec.name else "Root"
		joint.Part0, joint.Part1 = parent, child
		joint.C0 = parent.CFrame:ToObjectSpace(at)
		joint.C1 = child.CFrame:ToObjectSpace(at)
		joint:SetAttribute("Role", spec.role)
		joint.Parent = child
		child.Anchored = false
	end

	local controller = Instance.new("AnimationController")
	Instance.new("Animator").Parent = controller
	controller.Parent = model

	-- Pivot at the floor centre, facing -Z. With a PrimaryPart the model's
	-- pivot is the PrimaryPart's, so WorldPivot alone would be ignored.
	model.PrimaryPart = hrp
	-- (Voxel row 0 is centred on y = 0, so the floor is half a voxel lower.)
	hrp.PivotOffset = hrp.CFrame:ToObjectSpace(CFrame.new(origin - Vector3.new(0, voxel / 2, 0)))
	model:SetAttribute("ArticulatedRig", true)
	model:SetAttribute("VoxelSize", voxel)
	model:SetAttribute("Source", "assets/voxel-enemies/vox/" .. data.name .. ".vox")

	model.Parent = opts.parent or workspace
	model:PivotTo(opts.at or CFrame.new())
	stage:Destroy()
	return model, boxCount
end
