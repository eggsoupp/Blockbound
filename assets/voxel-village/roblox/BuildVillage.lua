--[[
	BuildVillage (Studio, Edit only)

	Turns the box data written by ../source/build.pl into the spawn village's
	models: ServerStorage.VillageAssets.<Name>. Front -Z, pivot = middle of
	the floor.

	  <Name>              Model
	    <Part>            one union per part, each box keeping its colour
	    <Part>Glow        the part's glowing boxes (Neon in a `neon` part, no collision)
	    LightN            Attachment + PointLight, in the part nearest to it

	Collision per part from the data: "box" (CollisionFidelity.Box),
	"precise" (PreciseConvexDecomposition) or "none" (CanCollide off).
	Anchors become attributes on the model: Anchor_<Name> = Vector3 (studs,
	model space).

	A rig (data.rig) is built ready to animate, the way BuildEnemyRigs does:
	an invisible anchored HumanoidRootPart at the root part's pivot, a Motor6D
	per part named after it (the root's is "Root") with axis-aligned C0/C1 at
	the pivot, glow unions welded to their part, everything else unanchored,
	massless and non-colliding, and an AnimationController with an Animator.
	Rest pose = every Transform identity, so it opens in the Animation Editor.

	Load a Folder holding this module and the Data modules, then
	  require(folder.BuildVillage)(require(folder.Data.Merchant), { parent = ServerStorage.VillageAssets })
]]

local FIDELITY = {
	box = Enum.CollisionFidelity.Box,
	precise = Enum.CollisionFidelity.PreciseConvexDecomposition,
	none = Enum.CollisionFidelity.Box,
}

-- Neon is for lamps only: a part the design marks `neon` (lanterns, candle
-- flames, the merchant's eyes) has its glowing boxes in Neon. Glowing boxes
-- in any other part (runes, gems, jars, the shrine's star) are built as
-- ordinary colour. The PointLights carry the lighting either way.

local function settle(part)
	part.Anchored = true
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- One part from many. The CSG kernel sometimes refuses a large set, so a
-- refused set is halved and the halves joined.
local function union(parts, name, fidelity)
	if #parts == 1 then
		return parts[1]
	end
	local first = parts[1]
	local rest = table.move(parts, 2, #parts, 1, {})
	local ok, result = pcall(function()
		return first:UnionAsync(rest, fidelity, Enum.RenderFidelity.Precise)
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
	local left, right = union(a, name, fidelity), union(b, name, fidelity)
	local ok2, joined = pcall(function()
		return left:UnionAsync({ right }, fidelity, Enum.RenderFidelity.Precise)
	end)
	if ok2 then
		left:Destroy()
		right:Destroy()
		return joined
	end
	warn("[BuildVillage] " .. name .. " stays in two pieces: " .. tostring(joined))
	right.Name = name .. "Extra"
	right.Parent = left.Parent
	return left, right
end

-- Distance from a point to a part's box.
local function boxDistance(part, point)
	local p = part.CFrame:PointToObjectSpace(point)
	local h = part.Size / 2
	local d = Vector3.new(math.max(math.abs(p.X) - h.X, 0), math.max(math.abs(p.Y) - h.Y, 0), math.max(math.abs(p.Z) - h.Z, 0))
	return d.Magnitude
end

return function(data, opts)
	opts = opts or {}
	local voxel = data.voxel
	local origin = opts.origin or Vector3.new(0, 900, 0)

	local stage = Instance.new("Folder")
	stage.Name = "_VillageBuild"
	stage.Parent = workspace

	local model = Instance.new("Model")
	model.Name = data.name
	model.Parent = stage
	local main = {} -- spec name -> main union
	local glows = {} -- spec name -> glow union
	local extras = {}
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
			b.Material = if col[4] and spec.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
			b.Parent = stage
			table.insert(if col[4] then glowing else plain, b)
		end
		boxCount += #plain + #glowing
		local fidelity = FIDELITY[spec.collide] or FIDELITY.box
		for _, set in { { plain, spec.name, false }, { glowing, spec.name .. "Glow", true } } do
			local list, name, isGlow = set[1], set[2], set[3]
			if #list > 0 then
				local part, extra = union(list, name, if isGlow then Enum.CollisionFidelity.Box else fidelity)
				for _, p in { part, extra } do
					p.Name = if p == extra then name .. "Extra" else name
					if p:IsA("UnionOperation") then
						p.UsePartColor = false
					end
					settle(p)
					p.CanCollide = not isGlow and spec.collide ~= "none" and not data.rig
					p.CanQuery = p.CanCollide
					if isGlow then
						p.Material = if spec.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
						p.CastShadow = not spec.neon
						p:SetAttribute("Glow", true)
					end
					p.Parent = model
				end
				if extra then
					table.insert(extras, { extra, spec.name })
				end
				if isGlow then
					glows[spec.name] = part
				else
					main[spec.name] = part
				end
				task.wait()
			end
		end
		-- A part with only glowing boxes: its glow union is its body.
		if not main[spec.name] and glows[spec.name] then
			main[spec.name] = glows[spec.name]
			main[spec.name].Name = spec.name
			glows[spec.name] = nil
		end
	end

	-- Lights, each in the part nearest to it so a rig carries its lights.
	for i, light in data.lights or {} do
		local at = origin + Vector3.new(table.unpack(light.at))
		local best, bestD = nil, math.huge
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				local d = boxDistance(part, at)
				if d < bestD then
					best, bestD = part, d
				end
			end
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = "Light" .. i
		attachment.WorldPosition = at
		attachment.Parent = best
		attachment.WorldPosition = at
		local pl = Instance.new("PointLight")
		pl.Range = light.range
		pl.Brightness = 0.9
		pl.Shadows = false
		pl.Color = Color3.fromRGB(light.color[1], light.color[2], light.color[3])
		pl.Parent = attachment
	end

	for name, at in data.anchors or {} do
		model:SetAttribute("Anchor_" .. name, Vector3.new(table.unpack(at)))
	end

	if data.rig then
		local function pivotAt(spec)
			return CFrame.new(origin + (Vector3.new(table.unpack(spec.pivot)) + Vector3.new(0.5, 0.5, 0.5)) * voxel)
		end
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		settle(hrp)
		hrp.Transparency = 1
		hrp.CanCollide = false
		hrp.CanQuery = false
		hrp.Size = Vector3.new(2, 2, 1)
		hrp.CFrame = pivotAt(data.parts[1])
		hrp.Parent = model

		for _, spec in data.parts do
			local child = main[spec.name]
			if child then
				local parent = if spec.parent then main[spec.parent] else hrp
				local at = pivotAt(spec)
				local joint = Instance.new("Motor6D")
				joint.Name = if spec.parent then spec.name else "Root"
				joint.Part0, joint.Part1 = parent, child
				joint.C0 = parent.CFrame:ToObjectSpace(at)
				joint.C1 = child.CFrame:ToObjectSpace(at)
				joint.Parent = child
			end
		end
		local function weld(piece, to)
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = to, piece
			w.Parent = piece
		end
		for name, glow in glows do
			weld(glow, main[name])
		end
		for _, e in extras do
			weld(e[1], main[e[2]])
		end
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part ~= hrp then
				part.Anchored = false
				part.Massless = true
				part.CanCollide = false
				part.CanQuery = false
			end
		end

		local controller = Instance.new("AnimationController")
		Instance.new("Animator").Parent = controller
		controller.Parent = model
		model.PrimaryPart = hrp
		hrp.PivotOffset = hrp.CFrame:ToObjectSpace(CFrame.new(origin))
		model:SetAttribute("ArticulatedRig", true)
	else
		model.WorldPivot = CFrame.new(origin)
	end

	model:SetAttribute("VoxelSize", voxel)
	model:SetAttribute("Source", "assets/voxel-village/vox/" .. data.name .. ".vox")
	model.Parent = opts.parent or workspace
	model:PivotTo(opts.at or CFrame.new())
	stage:Destroy()
	return model, boxCount
end
