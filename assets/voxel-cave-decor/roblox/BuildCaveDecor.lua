--[[
	BuildCaveDecor (Studio, Edit only)

	Turns one block's box data, written by ../source/build.pl, into the
	terrain template the game clones for it:
	ReplicatedStorage.TerrainAssets.Blocks.<Block>.

	  <Block>       Part, 4 x 4 x 4, invisible (attribute CellArt): the cell.
	                It is what collides and what the mouse ray hits.
	    Body        union of the opaque boxes, each keeping its colour
	    BodyGlow    the glowing boxes (Neon), when there are any
	    Ice / Glass see-through boxes, at the data's transparency

	The unions are unanchored, Massless and Welded to the cell, with no
	collision or ray of their own, so they follow the pooled Part wherever
	the terrain mesher puts it (see BlockParts, CellArt).

	Load a Folder holding this module and the Data modules, then
	  require(folder.BuildCaveDecor)(require(folder.Data.Icicle3_1), { parent = TerrainAssets.Blocks })
]]

local STUD = 4

local function settle(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- One part from many. The CSG kernel sometimes refuses a large set, so a
-- refused set is halved and the halves joined.
local function union(parts, name)
	if #parts == 1 then
		return parts
	end
	local first = parts[1]
	local rest = table.move(parts, 2, #parts, 1, {})
	local ok, result = pcall(function()
		return first:UnionAsync(rest, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	end)
	if ok then
		result.Parent = first.Parent
		for _, p in parts do
			p:Destroy()
		end
		return { result }
	end
	local half = math.floor(#parts / 2)
	local a = table.move(parts, 1, half, 1, {})
	local b = table.move(parts, half + 1, #parts, 1, {})
	local left, right = union(a, name), union(b, name)
	local joined = table.move(right, 1, #right, #left + 1, table.clone(left))
	if #left == 1 and #right == 1 then
		local ok2, merged = pcall(function()
			return left[1]:UnionAsync({ right[1] }, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
		end)
		if ok2 then
			merged.Parent = left[1].Parent
			left[1]:Destroy()
			right[1]:Destroy()
			return { merged }
		end
	end
	warn("[BuildCaveDecor] " .. name .. " stays in " .. #joined .. " pieces")
	return joined
end

return function(data, opts)
	opts = opts or {}
	local voxel = data.voxel
	local origin = opts.origin or Vector3.new(0, 900, 0)

	local stage = Instance.new("Folder")
	stage.Name = "_CaveDecorBuild"
	stage.Parent = workspace

	local cell = Instance.new("Part")
	cell.Name = data.name
	cell.Size = Vector3.new(STUD, STUD, STUD)
	cell.CFrame = CFrame.new(origin)
	cell.Anchored = true
	cell.CanCollide = true
	cell.CanTouch = false
	cell.CastShadow = false
	cell.Transparency = 1
	cell.Material = Enum.Material.SmoothPlastic
	cell.TopSurface = Enum.SurfaceType.Smooth
	cell.BottomSurface = Enum.SurfaceType.Smooth
	cell:SetAttribute("CellArt", true)
	cell:SetAttribute("Segment", data.segment)
	cell:SetAttribute("Tall", data.tall)
	cell:SetAttribute("Source", "assets/voxel-cave-decor/vox/" .. data.model .. ".vox")
	cell.Parent = stage

	-- Voxel frame: x and z -8..7, y 0..15, with the cell's centre at (0, 8, 0).
	local corner = origin - Vector3.new(0, STUD / 2, 0)
	local boxCount = 0
	local made = {}

	for _, spec in data.parts do
		local plain, glowing = {}, {}
		for x, y, z, w, h, d, c in string.gmatch(spec.boxes, "(-?%d+),(-?%d+),(-?%d+),(%d+),(%d+),(%d+),(%d+)") do
			x, y, z, w, h, d, c = tonumber(x), tonumber(y), tonumber(z), tonumber(w), tonumber(h), tonumber(d), tonumber(c)
			local col = data.colors[c]
			local b = Instance.new("Part")
			settle(b)
			b.Size = Vector3.new(w, h, d) * voxel
			b.Position = corner + Vector3.new(x + w / 2, y + h / 2, z + d / 2) * voxel
			b.Color = Color3.fromRGB(col[1], col[2], col[3])
			b.Material = if col[4] then Enum.Material.Neon else Enum.Material.SmoothPlastic
			b.Parent = stage
			table.insert(if col[4] then glowing else plain, b)
		end
		boxCount += #plain + #glowing
		for _, set in { { plain, spec.name, false }, { glowing, spec.name .. "Glow", true } } do
			local list, name, glow = set[1], set[2], set[3]
			if #list > 0 then
				for i, part in union(list, name) do
					part.Name = if i == 1 then name else name .. i
					if part:IsA("UnionOperation") then
						part.UsePartColor = false
					end
					settle(part)
					if glow then
						part.Material = Enum.Material.Neon
					end
					if spec.transparency then
						part.Transparency = spec.transparency
					end
					table.insert(made, part)
				end
				task.wait()
			end
		end
	end

	for _, part in made do
		local weld = Instance.new("Weld")
		weld.Name = "CellWeld"
		weld.Part0 = cell
		weld.Part1 = part
		weld.C0 = cell.CFrame:ToObjectSpace(part.CFrame)
		weld.Parent = part
		part.Parent = cell
	end

	cell.Parent = opts.parent or workspace
	-- Out of the workspace now, so nothing falls: the art follows the cell
	-- through its welds once the terrain parents a clone.
	for _, part in made do
		part.Anchored = false
	end
	stage:Destroy()
	return cell, boxCount
end
