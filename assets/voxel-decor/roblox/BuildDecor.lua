--[[
	BuildDecor (Studio, Edit only)

	Turns the box data written by ../source/build.pl into the decor models
	the game clones: ReplicatedStorage.TerrainAssets.Decor.<Id>.

	  <Id>          Model, WorldPivot = middle of the cell floor, front +Z
	    Body        union of the piece's boxes, each keeping its colour
	    BodyGlow    the glowing boxes (Neon), when there are any
	    Leaf        a door's swinging half (+ LeafGlow)
	    Glass       see-through panes

	Load a Folder holding this module and the Data modules, then
	  require(folder.BuildDecor)(folder.Data.WoodenDoor, { parent = TerrainAssets.Decor })
]]

local function settle(part)
	part.Anchored = true
	part.CanCollide = true
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
		for _, p in parts do
			p:Destroy()
		end
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
	warn("[BuildDecor] " .. name .. " stays in two pieces: " .. tostring(joined))
	right.Name = name .. "Extra"
	right.Parent = left.Parent
	return left
end

return function(data, opts)
	opts = opts or {}
	local voxel = data.voxel
	local origin = opts.origin or Vector3.new(0, 900, 0)

	local stage = Instance.new("Folder")
	stage.Name = "_DecorBuild"
	stage.Parent = workspace

	local model = Instance.new("Model")
	model.Name = data.name
	local boxCount = 0

	for _, spec in data.parts do
		local plain, glowing = {}, {}
		for x, y, z, w, h, d, c in string.gmatch(spec.boxes, "(-?%d+),(-?%d+),(-?%d+),(%d+),(%d+),(%d+),(%d+)") do
			x, y, z, w, h, d, c = tonumber(x), tonumber(y), tonumber(z), tonumber(w), tonumber(h), tonumber(d), tonumber(c)
			local col = data.colors[c]
			local b = Instance.new("Part")
			settle(b)
			b.Size = Vector3.new(w, h, d) * voxel
			b.Position = origin + Vector3.new(x + w / 2, y + h / 2, z + d / 2) * voxel
			b.Color = Color3.fromRGB(col[1], col[2], col[3])
			b.Material = if col[4] then Enum.Material.Neon else Enum.Material.SmoothPlastic
			b.Parent = stage
			table.insert(if col[4] then glowing else plain, b)
		end
		boxCount += #plain + #glowing
		for _, set in { { plain, spec.name }, { glowing, spec.name .. "Glow" } } do
			local list, name = set[1], set[2]
			if #list > 0 then
				local part = union(list, name)
				part.Name = name
				if part:IsA("UnionOperation") then
					part.UsePartColor = false
				end
				settle(part)
				if spec.name == "Glass" then
					part.Transparency = 0.45
					part.CastShadow = false
				end
				if list == glowing then
					part.Material = Enum.Material.Neon
					part:SetAttribute("Glow", true)
				end
				part.Parent = model
				task.wait()
			end
		end
	end

	model.WorldPivot = CFrame.new(origin)
	model:SetAttribute("VoxelSize", voxel)
	model:SetAttribute("Source", "assets/voxel-decor/vox/" .. data.name .. ".vox")
	model.Parent = opts.parent or workspace
	model:PivotTo(CFrame.new())
	stage:Destroy()
	return model, boxCount
end
