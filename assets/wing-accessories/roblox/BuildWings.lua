--[[
	BuildWings (Studio, Edit only)

	Turns the box data from export_wings.ps1 into the wearable wing models in
	ReplicatedStorage.WingAssets, one Model per item:

	  WingAssets.<ItemName>             Model, PrimaryPart = Frame
	    Frame                           the wearable frame (union)
	      WingMount                     Attachment at the Frame origin: the
	                                    upper-back centre, matched to the
	                                    wearer's BodyBackAttachment
	    <Piece>                         one union per rig piece (R_Arm, L_Fan,
	      <Piece>  Motor6D              R_Feather03, L_Upper ...), jointed to its
	                                    parent piece at the rigging.json pivot

	Every Motor6D's C0 and C1 are axis-aligned at its pivot, so a joint's
	Transform rotates the piece about that pivot in the frame's own axes:
	X across the back (+X the wearer's right), Y up, Z rearward.

	The models are place assets: the place must be saved for them to persist.
	Run it by loading a Folder holding this module plus the data modules, then:

	  require(folder.BuildWings)(folder.Data, 0.05)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Which animation family each pair uses (Shared.Flight.WingRigs).
local STYLES = {
	AngelWings = "Feather",
	BatWings = "Membrane",
	DemonWings = "Membrane",
	FairyWings = "Fairy",
	FlameWings = "Feather",
	FrostWings = "Feather",
	LeafWings = "Feather",
}

local function union(parts)
	local first = table.remove(parts, 1)
	if #parts == 0 then
		return first
	end
	local ok, result = pcall(function()
		return first:UnionAsync(parts, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	end)
	if ok then
		first:Destroy()
		for _, p in ipairs(parts) do p:Destroy() end
		return result
	end
	-- The CSG kernel sometimes refuses a large set: halve it and join halves.
	table.insert(parts, 1, first)
	local half = math.floor(#parts / 2)
	local a, b = {}, {}
	for i, p in ipairs(parts) do table.insert(if i <= half then a else b, p) end
	local left, right = union(a), union(b)
	local ok2, joined = pcall(function()
		return left:UnionAsync({ right }, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	end)
	if ok2 then
		left:Destroy(); right:Destroy()
		return joined
	end
	warn("[BuildWings] left a piece in two unions:", tostring(joined))
	local model = Instance.new("Model")
	left.Parent = model; right.Parent = model
	return model
end

local function settle(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
end

local function buildOne(data, voxel, origin, stage)
	local colors = {}
	for r, g, b in string.gmatch(data.colors, "(%d+),(%d+),(%d+)") do
		table.insert(colors, Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)))
	end

	local model = Instance.new("Model")
	model.Name = data.name
	model:SetAttribute("Style", STYLES[data.name] or "Feather")
	model:SetAttribute("Voxel", voxel)

	local pieces, pivots = {}, {}
	for _, piece in ipairs(data.pieces) do
		local folder = Instance.new("Folder")
		folder.Name = "_Wing_" .. piece.name
		local parts = {}
		for x, y, z, w, h, d, c in string.gmatch(piece.boxes, "(%-?%d+),(%-?%d+),(%-?%d+),(%d+),(%d+),(%d+),(%d+)") do
			x, y, z, w, h, d, c = tonumber(x), tonumber(y), tonumber(z), tonumber(w), tonumber(h), tonumber(d), tonumber(c)
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.Material = Enum.Material.SmoothPlastic
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Color = colors[c]
			p.Size = Vector3.new(w, h, d) * voxel
			-- Box x/y/z is the first voxel's centre; the box spans half a voxel either side.
			p.Position = origin + Vector3.new(x - 0.5 + w / 2, y - 0.5 + h / 2, z - 0.5 + d / 2) * voxel
			p.Parent = folder
			table.insert(parts, p)
		end
		folder.Parent = stage
		task.wait()
		local part = union(parts)
		if part:IsA("BasePart") then
			if part:IsA("PartOperation") then part.UsePartColor = false end
			settle(part)
		end
		part.Name = piece.name
		part.Parent = model
		folder:Destroy()
		pieces[piece.name] = part
		pivots[piece.name] = origin + Vector3.new(piece.pivot[1], piece.pivot[2], piece.pivot[3]) * voxel
		task.wait()
	end

	local frame = pieces.Frame
	local mount = Instance.new("Attachment")
	mount.Name = "WingMount"
	mount.CFrame = frame.CFrame:Inverse() * CFrame.new(pivots.Frame)
	mount.Parent = frame

	for _, piece in ipairs(data.pieces) do
		if piece.parent then
			local part0, part1 = pieces[piece.parent], pieces[piece.name]
			local at = CFrame.new(pivots[piece.name])
			local joint = Instance.new("Motor6D")
			joint.Name = piece.name
			joint.Part0 = part0
			joint.Part1 = part1
			joint.C0 = part0.CFrame:Inverse() * at
			joint.C1 = part1.CFrame:Inverse() * at
			joint.Parent = part1
		end
	end

	model.PrimaryPart = frame
	model.WorldPivot = CFrame.new(pivots.Frame)
	model:PivotTo(CFrame.new())
	return model
end

return function(dataFolder, voxel)
	voxel = voxel or 0.05
	local assets = ReplicatedStorage:FindFirstChild("WingAssets")
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "WingAssets"
		assets.Parent = ReplicatedStorage
	end
	local stage = Instance.new("Folder")
	stage.Name = "_WingBuild"
	stage.Parent = workspace

	local report = {}
	for _, module in ipairs(dataFolder:GetChildren()) do
		if module:IsA("ModuleScript") then
			local data = require(module)
			local old = assets:FindFirstChild(data.name)
			if old then old:Destroy() end
			local model = buildOne(data, voxel, Vector3.new(0, 800, 0), stage)
			model.Parent = assets
			local unions = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then unions += 1 end
			end
			table.insert(report, data.name .. " parts=" .. unions)
		end
	end
	stage:Destroy()
	return table.concat(report, "\n")
end
