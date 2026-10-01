-- Six original mesh templates are shared by every circle, beam and cast.
-- Optional imported OBJ MeshParts under AnnihilationAssets avoid runtime mesh APIs.
local AssetService = game:GetService("AssetService")
local Data = require(script.Parent.AnnihilationMeshData)
local BeamData = require(script.Parent.AnnihilationBeamData)
local Geometry = table.clone(Data)
for name, mesh in pairs(BeamData) do Geometry[name] = mesh end
local Meshes = {}
local templates = nil
local building = false
local retryAt = 0

local function configure(part: MeshPart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.DoubleSided = true
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.TextureID = ""
	-- Imported meshes may carry a SurfaceAppearance that overrides the neon.
	for _, child in part:GetChildren() do
		child:Destroy()
	end
end

function Meshes.get()
	while building do
		task.wait()
	end
	if templates then
		return templates
	end
	if os.clock() < retryAt then
		return nil
	end
	building = true
	local result, resources = {}, {}
	local ok, err = pcall(function()
		local imported = script.Parent:FindFirstChild("AnnihilationAssets")
		for _, name in { "Rim", "Glyphs", "Core", "Column", "Helix", "Shockwave" } do
			local source = imported and imported:FindFirstChild(name)
			local part
			if source and source:IsA("MeshPart") then
				part = source:Clone()
				table.insert(resources, part)
			else
				local mesh = AssetService:CreateEditableMesh()
				assert(mesh, "EditableMesh memory budget exhausted")
				table.insert(resources, mesh)
				local vertices = {}
				for i, v in ipairs(Geometry[name].vertices) do
					vertices[i] = mesh:AddVertex(Vector3.new(v[1], v[2], v[3]))
				end
				for _, face in ipairs(Geometry[name].faces) do
					mesh:AddTriangle(vertices[face[1]], vertices[face[2]], vertices[face[3]])
				end
				part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
				table.insert(resources, part)
			end
			configure(part)
			part.Name = name
			-- Use geometry bounds so all layers retain their authored proportions.
			local lowX, highX, lowZ, highZ = math.huge, -math.huge, math.huge, -math.huge
			local lowY, highY = math.huge, -math.huge
			for _, v in ipairs(Geometry[name].vertices) do
				lowY, highY = math.min(lowY, v[2]), math.max(highY, v[2])
				lowX, highX = math.min(lowX, v[1]), math.max(highX, v[1])
				lowZ, highZ = math.min(lowZ, v[3]), math.max(highZ, v[3])
			end
			result[name] = {
				part = part,
				size = Vector3.new(highX - lowX, math.max(0.05, highY - lowY), highZ - lowZ),
				offset = Vector3.new((highX + lowX) / 2, (highY + lowY) / 2, (highZ + lowZ) / 2),
			}
		end
	end)
	building = false
	if not ok then
		for i = #resources, 1, -1 do
			resources[i]:Destroy()
		end
		retryAt = os.clock() + 10
		warn("[Annihilation] Could not prepare custom meshes. Enable Allow Mesh & Image APIs, "
			.. "or import assets/annihilation OBJ layers into Shared.Abilities.VFX.AnnihilationAssets. "
			.. tostring(err))
		return nil
	end
	-- Keep EditableMesh references alive with the templates; bounded to six meshes.
	result.resources = resources
	templates = result
	return templates
end

return Meshes
