--[[
	Builds a winged creature as three unions - Body, LeftWing, RightWing - with
	each wing on a Motor6D hinged at its shoulder, so StarterPlayerScripts.
	CreatureFX can flap the wings independently of the body.

	A ModuleScript for Studio (Edit): require it and call
	  Build.build(boxesData, voxelSize, assetName, Build.Split.<Kind>, flap)
	The model carries ArticulatedRig = true, so EnemyService anchors only the
	body and the wings ride their joints; the pivot is the body's centre.

	`flap` = { rate = Hz, angle = degrees, glide = 0..1 } is stored as
	attributes the client reads (WingRate, WingAngle, WingGlide).
]]

local Build = {}

-- Which part a box belongs to: "Body", "LeftWing" or "RightWing".
-- Box fields are in the boxes file's voxel units: x, y, z, w, h, d, colour.
Build.Split = {
	-- The membrane is colour 1 above the body; a box straddling the middle
	-- is the root bar across the back and stays on the body.
	GreenWasp = function(x, y, _z, w, _h, _d, c)
		if c ~= 1 or y < 45 then return "Body" end
		if x + w <= 50 then return "LeftWing" end
		if x >= 50 then return "RightWing" end
		return "Body"
	end,
	-- For buildJointed: the coil on the ground, the raised neck, the hooded
	-- head. Boxes go by their bottom row.
	Cobra = function(_x, y)
		if y < 8 then return "Coil" end
		if y < 36 then return "Neck" end
		return "Head"
	end,
	-- Body is the middle band; every other box joins the leg whose line
	-- (root to tip, traced from a top-down map, voxel x/z) it is nearest.
	GreenSpider = (function()
		local legs = {
			L1 = { 70, 16, 40, 4 }, L2 = { 70, 21, 30, 20 }, L3 = { 68, 26, 30, 36 }, L4 = { 68, 32, 38, 50 },
			R1 = { 90, 16, 114, 4 }, R2 = { 90, 21, 126, 20 }, R3 = { 92, 26, 126, 35 }, R4 = { 92, 32, 116, 50 },
		}
		local function distance(px, pz, l)
			local ax, az, bx, bz = l[1], l[2], l[3], l[4]
			local dx, dz = bx - ax, bz - az
			local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz), 0, 1)
			return math.sqrt((ax + dx * t - px) ^ 2 + (az + dz * t - pz) ^ 2)
		end
		return function(x, _y, z, w, _h, d)
			local cx, cz = x + w / 2, z + d / 2
			if cx >= 70 and cx <= 91 then return "Body" end
			local best, bestDistance = "Body", math.huge
			for name, line in pairs(legs) do
				local dist = distance(cx, cz, line)
				if dist < bestDistance then best, bestDistance = name, dist end
			end
			return best
		end
	end)(),
	-- Factor-2 boxes. The wings are the raised V above the shoulders and the
	-- feathers hanging down the outside of the body.
	Shrike = function(x, y, _z, w, _h, _d, _c)
		local centre = x + w / 2
		local outboard = x + w <= 26 or x >= 40
		if y >= 17 or (outboard and y >= 8) then
			return if centre < 33 then "LeftWing" else "RightWing"
		end
		return "Body"
	end,
}

--[[
	One part from many. The CSG kernel occasionally refuses a large set
	("Internal kernel Error -31" on the Shrike's body), so a refused set is
	unioned in halves and the halves unioned; halves that still refuse stay
	separate and are welded to the first, as `extras`.
]]
local function unionParts(parts)
	if #parts == 1 then
		return parts[1], {}
	end
	local first = parts[1]
	local rest = table.move(parts, 2, #parts, 1, {})
	local ok, result = pcall(function()
		return first:UnionAsync(rest, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	end)
	if ok then
		return result, {}
	end

	-- Halves are parented beside their parts: the kernel wants them in the world.
	local half = #parts // 2
	local a, extrasA = unionParts(table.move(parts, 1, half, 1, {}))
	local b, extrasB = unionParts(table.move(parts, half + 1, #parts, 1, {}))
	a.Parent, b.Parent = first.Parent, first.Parent
	local joined
	ok, joined = pcall(function()
		return a:UnionAsync({ b }, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	end)
	local extras = table.move(extrasB, 1, #extrasB, #extrasA + 1, extrasA)
	if ok then
		return joined, extras
	end
	table.insert(extras, b)
	return a, extras
end

local function union(parts, name)
	local result, extras = unionParts(parts)
	result.Name = name
	for _, part in ipairs({ result, table.unpack(extras) }) do
		if part:IsA("PartOperation") then part.UsePartColor = false end
		part.CanCollide, part.CanTouch, part.CanQuery = false, false, true
		part.Anchored = true
	end
	return result, extras
end

-- Welds pieces a union could not absorb onto it, keeping them in the model.
local function attach(model, main, extras)
	for i, piece in ipairs(extras) do
		piece.Name = main.Name .. "Piece" .. i
		piece.Anchored = false
		piece.Massless = true
		piece.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = main, piece
		weld.Parent = piece
	end
end

function Build.build(data, voxel, assetName, split, flap)
	local colors = {}
	for r, g, b in string.gmatch(data.colors, "(%d+),(%d+),(%d+)") do
		table.insert(colors, Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)))
	end
	local dims = data.dims
	local origin = Vector3.new(0, 500, 0)
	local folder = Instance.new("Folder")
	folder.Name = "_WingedBuild"

	local groups = { Body = {}, LeftWing = {}, RightWing = {} }
	for x, y, z, w, h, d, c in string.gmatch(data.boxes, "(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)") do
		x, y, z, w, h, d, c = tonumber(x), tonumber(y), tonumber(z), tonumber(w), tonumber(h), tonumber(d), tonumber(c)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide = true, false
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Color = colors[c]
		p.Size = Vector3.new(w, h, d) * voxel
		p.Position = origin + Vector3.new(x + w / 2 - dims[1] / 2, y + h / 2, z + d / 2 - dims[3] / 2) * voxel
		p.Parent = folder
		table.insert(groups[split(x, y, z, w, h, d, c)], p)
	end
	folder.Parent = workspace
	task.wait()

	local model = Instance.new("Model")
	model.Name = assetName
	local body, bodyExtras = union(groups.Body, "Body")
	body.Parent = model
	model.PrimaryPart = body
	attach(model, body, bodyExtras)

	for _, side in ipairs({ "LeftWing", "RightWing" }) do
		local wing, wingExtras = union(groups[side], side)
		wing.Anchored = false
		wing.Massless = true
		wing.Parent = model
		attach(model, wing, wingExtras)

		-- The shoulder: the wing's edge nearest the body, at its lowest
		-- point, halfway along it.
		local inner = if wing.Position.X < body.Position.X
			then wing.Position.X + wing.Size.X / 2
			else wing.Position.X - wing.Size.X / 2
		local hinge = CFrame.new(inner, wing.Position.Y - wing.Size.Y / 2 + 0.1, wing.Position.Z)

		local joint = Instance.new("Motor6D")
		joint.Name = side
		joint.Part0, joint.Part1 = body, wing
		joint.C0 = body.CFrame:ToObjectSpace(hinge)
		joint.C1 = wing.CFrame:ToObjectSpace(hinge)
		joint.Parent = body
	end
	folder:Destroy()

	model:SetAttribute("ArticulatedRig", true)
	model:SetAttribute("WingRate", flap.rate)
	model:SetAttribute("WingAngle", flap.angle)
	model:SetAttribute("WingGlide", flap.glide or 0)
	model.WorldPivot = CFrame.new(model:GetBoundingBox().Position)
	model:PivotTo(CFrame.new())
	return model
end

--[[
	A chain of unions on Motor6Ds, for a body that bends rather than flaps:
	`joints` is a list of { parent, child, hinge? } group names, the first
	group in `order` is the anchored root, and each child hinges at `hinge`
	(a point in the boxes file's voxel units: x, height, z) or, without one,
	at the bottom centre of its own box. The pivot is the root's feet,
	centred.
]]
function Build.buildJointed(data, voxel, assetName, split, order, joints)
	local colors = {}
	for r, g, b in string.gmatch(data.colors, "(%d+),(%d+),(%d+)") do
		table.insert(colors, Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)))
	end
	local dims = data.dims
	local origin = Vector3.new(0, 500, 0)
	local folder = Instance.new("Folder")
	folder.Name = "_WingedBuild"

	local groups = {}
	for _, name in ipairs(order) do groups[name] = {} end
	for x, y, z, w, h, d, c in string.gmatch(data.boxes, "(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)") do
		x, y, z, w, h, d, c = tonumber(x), tonumber(y), tonumber(z), tonumber(w), tonumber(h), tonumber(d), tonumber(c)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide = true, false
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Color = colors[c]
		p.Size = Vector3.new(w, h, d) * voxel
		p.Position = origin + Vector3.new(x + w / 2 - dims[1] / 2, y + h / 2, z + d / 2 - dims[3] / 2) * voxel
		p.Parent = folder
		table.insert(groups[split(x, y, z, w, h, d, c)], p)
	end
	folder.Parent = workspace
	task.wait()

	local model = Instance.new("Model")
	model.Name = assetName
	local parts = {}
	for i, name in ipairs(order) do
		local part, extras = union(groups[name], name)
		part.Parent = model
		if i == 1 then
			model.PrimaryPart = part
		else
			part.Anchored = false
			part.Massless = true
		end
		attach(model, part, extras)
		parts[name] = part
	end

	for _, pair in ipairs(joints) do
		local parent, child = parts[pair[1]], parts[pair[2]]
		local at = pair[3]
		local hinge = if at
			then CFrame.new(origin + Vector3.new(at[1] - dims[1] / 2, at[2], at[3] - dims[3] / 2) * voxel)
			else CFrame.new(child.Position - Vector3.new(0, child.Size.Y / 2, 0))
		local joint = Instance.new("Motor6D")
		joint.Name = pair[2]
		joint.Part0, joint.Part1 = parent, child
		joint.C0 = parent.CFrame:ToObjectSpace(hinge)
		joint.C1 = child.CFrame:ToObjectSpace(hinge)
		joint.Parent = parent
	end
	folder:Destroy()

	model:SetAttribute("ArticulatedRig", true)
	local bounds = model:GetBoundingBox()
	local root = model.PrimaryPart
	model.WorldPivot = CFrame.new(bounds.Position.X, root.Position.Y - root.Size.Y / 2, bounds.Position.Z)
	model:PivotTo(CFrame.new())
	return model
end

return Build
