--[[
	FXBuilder

	Turns the extracted reference data into real instances, once, and then hands
	out copies of them.

		FXBuilder.acquire("Portal")        -- a Portal, from the pool
		FXBuilder.release("Portal", portal)
		FXBuilder.emitAll(portal)          -- fire every burst it contains
		FXBuilder.setEnabled(sword, false)

		FXBuilder.buildWeapon(toolTemplate) -- the player's weapon, wearing the
		                                    -- reference sword's particle rig

	WHY BUILD RATHER THAN CLONE FROM STORAGE

	The alternative is asking the developer to paste five parts and a hundred
	and fifty-nine emitters into ReplicatedStorage by hand and keep them in
	sync. Building them from Shared.Abilities.VFX.SacredRainData means the
	effect is under source control, is diffable, and can be regenerated from the
	reference place by re-running tools/extract-sacredrain.ps1.

	CLIENT ONLY

	Nothing here is ever built on the server. Particles are pure presentation;
	spawning them server-side replicates every one of them to every client in
	the game, which is the single most expensive thing the reference does. The
	server decides what happened, and each client near enough to care draws it.

	POOLING, AND WHY IT MATTERS HERE

	One cast is fifteen swords and fifteen portals, and a sword carries
	eighty-seven emitters. Building that per strike is several thousand
	instances created and destroyed every time somebody presses a key. The
	assemblies are therefore reused: acquire takes one from the pool or clones
	the template, release resets it and puts it back. After the first cast a
	barrage allocates almost nothing.

	RESETTING

	A pooled assembly has to go back exactly as it came out, and the two things
	a cast changes are emitter Enabled flags and part Transparency. Both are
	stamped onto the instance as attributes at build time (_BBEnabled,
	_BBTransparency) so the reset survives cloning and needs no side table.
]]

local RunService = game:GetService("RunService")

local Data = require(script.Parent:WaitForChild("SacredRainData"))
local VFXPalette = require(script.Parent:WaitForChild("VFXPalette"))

local FXBuilder = {}

--[[
	How many spare copies of each assembly to keep.

	Sized just over the peak concurrency of one cast: strikes are 0.2s apart and
	a sword is alive for about 2.4s of that, so around a dozen exist at once.
	Anything past the cap is destroyed rather than hoarded.
]]
local POOL_LIMIT = 18

-- The reference sword's length along its own forward axis, used to scale the
-- particle rig onto a weapon of a different size. From SacredRainData.LightSword.
local REFERENCE_BLADE_LENGTH = 10.38429

local templates: { [string]: Instance } = {}
local pools: { [string]: { Instance } } = {}

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

--[[
	Applies a property table, skipping anything the engine refuses at runtime.

	pcall per property rather than per instance: one property Roblox has since
	renamed should cost that property, not the whole emitter.
]]
local function applyProps(instance: Instance, props: { [string]: any }?)
	if not props then
		return
	end

	for name, value in pairs(props) do
		-- Every colour in the effect passes through here on its way onto an
		-- instance, which makes this the one place a palette can be imposed
		-- without editing the generated data. Non-colours come back unchanged.
		value = VFXPalette.apply(value)

		local ok = pcall(function()
			(instance :: any)[name] = value
		end)

		if not ok then
			warn(string.format(
				"[FXBuilder] %s has no property '%s' - the reference data may be from a "
					.. "newer Studio than this place is running.",
				instance.ClassName, name
			))
		end
	end
end

--[[
	Scales a NumberSequence, for fitting the reference's particle sizes to a
	weapon that is not the reference's length.
]]
local function scaleSequence(sequence: NumberSequence, factor: number): NumberSequence
	local points = {}
	for index, keypoint in ipairs(sequence.Keypoints) do
		points[index] =
			NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * factor, keypoint.Envelope * factor)
	end
	return NumberSequence.new(points)
end

--[[
	Builds one node of the description tree.

	`attachments` collects Attachment instances by their data id and `trails`
	collects Trails that still need linking - a Trail can name an attachment
	that appears later in the tree, so linking is a second pass.
]]
local function buildNode(node, parent: Instance, scale: number, attachments, trails)
	local class = node.class
	local instance: Instance

	if class == "Attachment" then
		instance = Instance.new("Attachment")
	elseif class == "ParticleEmitter" then
		instance = Instance.new("ParticleEmitter")
	elseif class == "Trail" then
		instance = Instance.new("Trail")
	elseif class == "Decal" then
		instance = Instance.new("Decal")
	else
		return nil
	end

	instance.Name = node.name or class
	applyProps(instance, node.props)

	if class == "Attachment" then
		local attachment = instance :: Attachment
		attachment.Visible = false

		if scale ~= 1 then
			-- Position scales with the weapon; orientation does not.
			local cframe = attachment.CFrame
			attachment.CFrame = CFrame.new(cframe.Position * scale) * (cframe - cframe.Position)
		end

		if node.id then
			attachments[node.id] = attachment
		end
	elseif class == "ParticleEmitter" then
		local emitter = instance :: ParticleEmitter

		if scale ~= 1 then
			emitter.Size = scaleSequence(emitter.Size, scale)
		end

		-- The reference drives its bursts entirely from these attributes; see
		-- FXBuilder.emitAll. Copied across verbatim, including their absence -
		-- an emitter with no EmitCount emits Roblox's default, which is what
		-- the reference does too.
		if node.attrs then
			for key, value in pairs(node.attrs) do
				emitter:SetAttribute(key, value)
			end
		end

		emitter:SetAttribute("_BBEnabled", emitter.Enabled)
	elseif class == "Trail" then
		local trail = instance :: Trail
		trail:SetAttribute("_BBEnabled", trail.Enabled)
		table.insert(trails, { trail = trail, a0 = node.a0, a1 = node.a1 })
	end

	instance.Parent = parent

	if node.children then
		for _, child in ipairs(node.children) do
			buildNode(child, instance, scale, attachments, trails)
		end
	end

	return instance
end

local function linkTrails(trails, attachments)
	for _, entry in ipairs(trails) do
		local a0 = entry.a0 and attachments[entry.a0]
		local a1 = entry.a1 and attachments[entry.a1]

		if a0 and a1 then
			entry.trail.Attachment0 = a0
			entry.trail.Attachment1 = a1
		else
			-- A trail with no endpoints draws nothing and warns about nothing,
			-- which is exactly the kind of silent gap this game's other loaders
			-- refuse to leave.
			warn(string.format(
				"[FXBuilder] trail '%s' names attachments that were not built; it will not draw.",
				entry.trail.Name
			))
			entry.trail:Destroy()
		end
	end
end

--[[
	Grows a loose set of parts about a pivot, before anything is welded.

	Position scales with the model as well as size, or a two-piece weapon would
	stay the same length and simply get fatter. Meshes need their own attention:
	a MeshPart follows its Size, but a SpecialMesh wearing a FileMesh ignores
	Size entirely and draws at its Scale, so that is scaled instead.

	Must run BEFORE the welds are made. A WeldConstraint fixes the relative pose
	it was created with, so a part moved afterwards is dragged straight back.
]]
local function scaleParts(parts: { BasePart }, pivot: CFrame, factor: number)
	for _, part in ipairs(parts) do
		local relative = pivot:ToObjectSpace(part.CFrame)

		part.Size *= factor
		part.CFrame = pivot
			* CFrame.new(relative.Position * factor)
			* (relative - relative.Position)

		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("SpecialMesh") and child.MeshType == Enum.MeshType.FileMesh then
				child.Scale *= factor
			end

			if child:IsA("DataModelMesh") then
				child.Offset *= factor
			end
		end
	end
end

--[[
	Repaints a set of parts one flat colour.

	Colour alone would not take on most weapons: a MeshPart's TextureID, a
	SurfaceAppearance and a decal all draw over the part's own Color, and a
	weapon whose look lives in its texture would come out unchanged. So the
	texture layers are stripped as well - the point of asking for a colour here
	is to get that colour and nothing else.

	Only ever applied to a purpose-built copy of the model, never to the one the
	player carries.
]]
local function paintParts(parts: { BasePart }, color: Color3)
	for _, part in ipairs(parts) do
		part.Color = color
		part.Reflectance = 0

		-- MeshPart.TextureID has not always been writable from a script, and
		-- there is nothing to do about it when it is not: the mesh keeps its
		-- own texture and reads a little less black than the rest.
		if part:IsA("MeshPart") then
			local meshPart = part
			pcall(function()
				meshPart.TextureID = ""
			end)
		end

		for _, descendant in ipairs(part:GetDescendants()) do
			if descendant:IsA("SurfaceAppearance") or descendant:IsA("Decal") then
				descendant:Destroy()
			elseif descendant:IsA("SpecialMesh") then
				descendant.TextureId = ""
			end
		end
	end
end

--[[
	Strips the parts of an assembly that make it inert scenery: nothing here
	collides, is queried by raycasts, casts shadows or has mass.
]]
local function styleFXPart(part: BasePart, anchored: boolean)
	part.Anchored = anchored
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.Locked = true
	part:SetAttribute("_BBTransparency", part.Transparency)
end

--[[
	Builds one of the reference's standalone assemblies - Portal, Marker, HitFX,
	Dust - as a single anchored part carrying its particle rig.
]]
local function buildAssembly(name: string): BasePart?
	local description = Data[name]
	if not description then
		warn(string.format("[FXBuilder] no reference data for '%s'", name))
		return nil
	end

	local part = Instance.new("Part")
	part.Name = name
	applyProps(part, description.props)
	styleFXPart(part, true)

	local attachments, trails = {}, {}
	if description.children then
		for _, child in ipairs(description.children) do
			buildNode(child, part, 1, attachments, trails)
		end
	end
	linkTrails(trails, attachments)

	return part
end

--[[
	The template for an assembly, built on first use and kept unparented.

	Unparented rather than stashed in a folder: nothing should be able to find
	these by name and use them directly, and a template in the DataModel is one
	that somebody eventually moves.
]]
function FXBuilder.template(name: string): Instance?
	local existing = templates[name]
	if existing then
		return existing
	end

	local built = buildAssembly(name)
	if built then
		templates[name] = built
	end

	return built
end

-- ---------------------------------------------------------------------------
-- The player's weapon, wearing the reference's particle rig
-- ---------------------------------------------------------------------------

--[[
	Which way the weapon points.

	The reference's sword is a mesh built along its own Z axis, and the barrage
	orients it with CFrame.lookAt, so the blade's tip has to sit on -Z. A
	weapon authored by somebody else points wherever they built it pointing.

	Rather than demand a convention, this works it out: the longest side of the
	bounding box is the length of the weapon, and the tip is the end of that
	axis FURTHEST FROM THE HANDLE - because the handle is, by definition, the
	end you hold.

	That is a heuristic, and a weapon whose handle sits in the middle will
	defeat it. So it can be overridden with a `ProjectileForward` Vector3
	attribute on the Tool, in the Handle's own space, pointing at the tip.
]]
local function forwardAxisFor(tool: Instance, boxCFrame: CFrame, boxSize: Vector3, handle: BasePart)
	local override = tool:GetAttribute("ProjectileForward")
	if typeof(override) == "Vector3" and override.Magnitude > 1e-4 then
		return handle.CFrame:VectorToWorldSpace(override.Unit), math.max(boxSize.X, boxSize.Y, boxSize.Z)
	end

	local sizes = { boxSize.X, boxSize.Y, boxSize.Z }
	local axis, length = 1, sizes[1]
	for index = 2, 3 do
		if sizes[index] > length then
			axis, length = index, sizes[index]
		end
	end

	local localAxis = if axis == 1 then Vector3.xAxis elseif axis == 2 then Vector3.yAxis else Vector3.zAxis
	local handleLocal = boxCFrame:PointToObjectSpace(handle.Position)
	local handleAlongAxis = handleLocal:Dot(localAxis)

	-- Point away from the handle. Dead centre is a coin toss, and +axis is as
	-- good an answer as any; the attribute exists for that case.
	if handleAlongAxis > 0 then
		localAxis = -localAxis
	end

	return boxCFrame:VectorToWorldSpace(localAxis), length
end

--[[
	Builds the flying weapon: the player's own model, welded rigid, with the
	reference sword's attachments, emitters and trails grafted onto it.

	`toolTemplate` is the Tool (or Model) out of ReplicatedStorage.Tools -
	whatever the equip path already uses, so the thing that flies is visibly the
	thing in the player's hand.

	Returns nil, with a reason, when there is nothing usable to fly. Nothing is
	invented in that case: an ability with no weapon model does not run.

	`options` builds a variant of the same weapon rather than a second weapon:

	  scale  grows the model and its whole particle rig by this factor
	  color  paints every part of it one flat colour

	Sacred Rain's finale uses both, so the blade that lands on the mark is
	visibly not one of the fourteen that scattered.
]]
export type WeaponOptions = {
	scale: number?,
	color: Color3?,
}

function FXBuilder.buildWeapon(toolTemplate: Instance?, options: WeaponOptions?): (BasePart?, string?)
	if not toolTemplate then
		return nil, "no tool template"
	end

	local modelScale = 1
	local tint: Color3? = nil

	if options then
		if type(options.scale) == "number" and options.scale > 0 then
			modelScale = options.scale
		end
		if typeof(options.color) == "Color3" then
			tint = options.color
		end
	end

	local source = toolTemplate:Clone()

	-- Gameplay has no business inside a decoration. Scripts would run, sounds
	-- would play fifteen times at once, and neither is part of the effect.
	for _, descendant in ipairs(source:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		end
	end

	--[[
		The parts to fly, and which of them is the grip.

		A one-piece mesh export arrives as a bare BasePart rather than a Tool or
		a Model, and it is then both the only part and the handle - so it is
		gathered here rather than by walking descendants it does not have.
	]]
	local parts = {}
	local handle: BasePart?

	if source:IsA("BasePart") then
		parts[1] = source
		handle = source
	else
		for _, descendant in ipairs(source:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end

		local named = source:FindFirstChild("Handle")
		if named and named:IsA("BasePart") then
			handle = named
		else
			handle = source:FindFirstChildWhichIsA("BasePart", true)
		end
	end

	if not handle then
		source:Destroy()
		return nil, "the tool template contains no BasePart"
	end

	-- Measured through a Model so the engine does the bounding box, oriented to
	-- the handle so "along the weapon" means something.
	local measuring = Instance.new("Model")
	for _, part in ipairs(parts) do
		part.Parent = measuring
	end
	measuring.PrimaryPart = handle
	local boxCFrame, boxSize = measuring:GetBoundingBox()

	local forward, length = forwardAxisFor(toolTemplate, boxCFrame, boxSize, handle)

	-- Both are done against the loose parts, around the box they were measured
	-- in, and both have to happen before the welds below.
	if modelScale ~= 1 then
		scaleParts(parts, boxCFrame, modelScale)
		length *= modelScale
	end

	if tint then
		paintParts(parts, tint)
	end

	local root = Instance.new("Part")
	root.Name = "Weapon"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CFrame = CFrame.lookAt(boxCFrame.Position, boxCFrame.Position + forward)
	styleFXPart(root, true)

	for _, part in ipairs(parts) do
		styleFXPart(part, false)
		part.Parent = root

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	-- Both are empty by now: every part has been reparented onto the root. The
	-- one-piece case is why `source` is only destroyed when it is not itself
	-- one of those parts.
	measuring:Destroy()
	if source ~= handle and source.Parent ~= root then
		source:Destroy()
	end

	-- The reference's particle sizes and attachment offsets are tuned to a
	-- blade ten studs long. A weapon of a different length gets them scaled to
	-- match, so the rig fits whatever it is bolted to.
	local override = toolTemplate:GetAttribute("ProjectileScale")
	local scale = if type(override) == "number" and override > 0
		then override * modelScale
		else math.clamp(length / REFERENCE_BLADE_LENGTH, 0.15, 6)

	local swordData = Data.LightSword
	local attachments, trails = {}, {}
	if swordData and swordData.children then
		for _, child in ipairs(swordData.children) do
			buildNode(child, root, scale, attachments, trails)
		end
	end
	linkTrails(trails, attachments)

	return root, nil
end

-- ---------------------------------------------------------------------------
-- Pooling
-- ---------------------------------------------------------------------------

--[[
	Registers an already-built assembly as the template for a name.

	Used for the weapon rig, which cannot be built from data alone because half
	of it is the player's own model.
]]
function FXBuilder.setTemplate(name: string, instance: Instance)
	local previous = templates[name]
	if previous and previous ~= instance then
		previous:Destroy()
	end

	templates[name] = instance

	-- Anything pooled under the old template is the wrong shape now.
	local pool = pools[name]
	if pool then
		for _, pooled in ipairs(pool) do
			pooled:Destroy()
		end
		pools[name] = nil
	end
end

function FXBuilder.hasTemplate(name: string): boolean
	return templates[name] ~= nil
end

--[[
	Puts an assembly back the way it was built: emitters and trails to their
	authored Enabled state, parts to their authored Transparency.
]]
function FXBuilder.reset(root: Instance)
	if root:IsA("BasePart") then
		local transparency = root:GetAttribute("_BBTransparency")
		if type(transparency) == "number" then
			root.Transparency = transparency
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") then
			local enabled = descendant:GetAttribute("_BBEnabled")
			if type(enabled) == "boolean" then
				(descendant :: any).Enabled = enabled
			end
		elseif descendant:IsA("BasePart") then
			local transparency = descendant:GetAttribute("_BBTransparency")
			if type(transparency) == "number" then
				descendant.Transparency = transparency
			end
		end
	end
end

function FXBuilder.acquire(name: string): Instance?
	local pool = pools[name]
	if pool then
		local pooled = table.remove(pool)
		if pooled then
			return pooled
		end
	end

	local template = FXBuilder.template(name)
	if not template then
		return nil
	end

	return template:Clone()
end

function FXBuilder.release(name: string, instance: Instance?)
	if not instance then
		return
	end

	instance.Parent = nil

	local pool = pools[name]
	if not pool then
		pool = {}
		pools[name] = pool
	end

	if #pool >= POOL_LIMIT then
		instance:Destroy()
		return
	end

	FXBuilder.reset(instance)
	table.insert(pool, instance)
end

-- ---------------------------------------------------------------------------
-- Emission
-- ---------------------------------------------------------------------------

--[[
	Fires every burst under `root`, exactly the way the reference does:
	Emit(EmitCount), where an emitter without the attribute passes nil and gets
	Roblox's default count.

	EmitDelay is honoured through the scope, so a cast that is torn down before
	a delayed burst fires does not fire it into an empty workspace.
]]
function FXBuilder.emitAll(root: Instance, scope)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local emitter = descendant
			local count = emitter:GetAttribute("EmitCount")
			local delay = emitter:GetAttribute("EmitDelay")

			if type(delay) == "number" and delay > 0 and scope then
				scope:delay(delay, function()
					if emitter.Parent then
						emitter:Emit(count)
					end
				end)
			else
				emitter:Emit(count)
			end
		end
	end
end

function FXBuilder.setEnabled(root: Instance, enabled: boolean)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") then
			(descendant :: any).Enabled = enabled
		end
	end
end

--[[
	Enables only what lives under a named child - the reference turns on the
	Portal's "Main" attachment without touching its "Explode" one.
]]
function FXBuilder.setEnabledUnder(root: Instance, childName: string, enabled: boolean)
	local child = root:FindFirstChild(childName, true)
	if child then
		FXBuilder.setEnabled(child, enabled)
	end
end

if RunService:IsServer() then
	warn("[FXBuilder] required on the server. Particle assemblies are client-side only.")
end

return FXBuilder
