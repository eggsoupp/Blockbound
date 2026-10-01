--[[
	ToolFactory

	Makes sure a Tool template exists for an item, building one if nobody
	authored it.

		local template = ToolFactory.ensure("GoldPickaxe")

	Authored templates in ReplicatedStorage.Tools always win, so this only fills
	gaps. Built templates are parented into the same folder and cached there, so
	each one is assembled once per server and cloned thereafter - the same
	arrangement TestPickaxe and friends already have.

	AUTHORING A TOOL AS A MODEL

	Roblox only puts a Tool in a hand, but modelling a pickaxe as a Tool in
	Studio is awkward - so a MODEL named after the item is wrapped into one at
	server start.

	  Name    exactly the ItemDefinitions key, e.g. WoodPickaxe
	  Handle  the part that should sit in the hand. Without one, PrimaryPart is
	          used and renamed, failing that the first BasePart - each with a
	          message saying so.
	  Grip    optional attributes, for a model that comes out through the
	          wrist: a CFrame called Grip, or GripPos + GripRight + GripUp
	          copied straight out of a Tool's properties, or GripPos +
	          GripAngles in degrees. See gripFromAttributes.

	Parts are unanchored, made massless and non-colliding, and welded to the
	handle. Wrapping consumes the model - only the live server's copy, since the
	place file is rebuilt from on every start.

	A BUILT tool's appearance comes entirely from Shared.Tools.ToolConfig; this
	module only knows how to turn boxes, or somebody's model, into a Tool.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tools"):WaitForChild("ToolConfig")
)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local ToolFactory = {}

local toolsFolder = ReplicatedStorage:FindFirstChild("Tools")
if not toolsFolder then
	toolsFolder = Instance.new("Folder")
	toolsFolder.Name = "Tools"
	toolsFolder.Parent = ReplicatedStorage
end

local function styleBasePart(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

--[[
	Assembles a Tool from a shape description.

	The handle is the grip, centred on the origin, and every other part is welded
	to it at its offset. WeldConstraint rather than Motor6D: nothing here
	animates independently, and a weld survives the tool being cloned, parented
	and equipped without any joint bookkeeping.
]]
local function buildTool(itemName, definition)
	local tool = Instance.new("Tool")
	tool.Name = itemName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = definition and definition.description or itemName

	local handleSpec = ToolConfig.Handle
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = handleSpec.size
	handle.Color = handleSpec.color
	handle.Material = handleSpec.material
	handle.CFrame = CFrame.new()
	styleBasePart(handle)
	handle.Parent = tool

	local metal = ToolConfig.materialFor(itemName)

	for index, spec in ipairs(ToolConfig.shapeFor(definition and definition.classification)) do
		local piece = Instance.new("Part")
		piece.Name = string.format("Piece%d", index)
		piece.Size = spec.size
		piece.Color = metal.color
		piece.Material = metal.material
		piece.CFrame = CFrame.new(spec.offset)
		styleBasePart(piece)
		piece.Parent = tool

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = piece
		weld.Parent = piece
	end

	-- The item name is what every other system identifies a tool by, so it is
	-- stamped on here rather than left to EquipServer to remember.
	tool:SetAttribute("ItemName", itemName)

	return tool
end

--[[
	Picks the part that will sit in the character's hand.

	Prefers one the author already named "Handle", because that is the only
	choice that carries intent - Roblox grips a Tool by its Handle's origin, so
	whichever part this lands on decides how the tool is held. PrimaryPart is the
	next best signal; the first BasePart is a guess, and says so.
]]
local function chooseHandle(itemName, model)
	local named = model:FindFirstChild("Handle", true)
	if named and named:IsA("BasePart") then
		return named
	end

	if model.PrimaryPart then
		warn(string.format(
			"[ToolFactory] '%s' has no part named Handle; using its PrimaryPart '%s' and "
				.. "renaming it. Name a part Handle to choose deliberately.",
			itemName, model.PrimaryPart.Name
		))
		return model.PrimaryPart
	end

	local first = model:FindFirstChildWhichIsA("BasePart", true)
	if first then
		warn(string.format(
			"[ToolFactory] '%s' has no Handle and no PrimaryPart; guessing '%s'. If it sits "
				.. "wrong in the hand, name the right part Handle.",
			itemName, first.Name
		))
	end

	return first
end

--[[
	The optional grip override, in whichever of three forms it was written.

	Roblox holds a Tool by its Handle's origin and axes, so a handle built
	pointing the wrong way comes out through the wrist. The reliable way to find
	the right values is to tune a live Tool in Studio, which shows GripPos,
	GripRight, GripUp and GripForward - hence those names, so the numbers copy
	straight across.

	  Grip                    a CFrame attribute; wins over the rest
	  GripPos + GripRight/Up  the Studio values, verbatim
	  GripPos + GripAngles    Euler degrees, for hand-tuning without a rig

	GripForward is ignored: right and up already determine the third axis, and
	taking all three invites a sign disagreement that would mirror the tool.
]]
local function gripFromAttributes(source)
	local explicit = source:GetAttribute("Grip")
	if typeof(explicit) == "CFrame" then
		return explicit
	end

	local position = source:GetAttribute("GripPos")
	local right = source:GetAttribute("GripRight")
	local up = source:GetAttribute("GripUp")
	local angles = source:GetAttribute("GripAngles")

	local hasPosition = typeof(position) == "Vector3"
	local hasBasis = typeof(right) == "Vector3" and typeof(up) == "Vector3"
	local hasAngles = typeof(angles) == "Vector3"

	if not hasPosition and not hasBasis and not hasAngles then
		return nil
	end

	local origin = if hasPosition then position else Vector3.zero

	if hasBasis then
		-- Third axis derived rather than read, so a basis that is slightly off
		-- orthogonal still produces a valid rotation instead of a sheared one.
		local ok, grip = pcall(CFrame.fromMatrix, origin, right, up)
		if ok then
			return grip
		end

		warn(
			"[ToolFactory] GripRight and GripUp do not form a usable rotation; "
				.. "falling back to position only."
		)
		return CFrame.new(origin)
	end

	if hasAngles then
		return CFrame.new(origin)
			* CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
	end

	return CFrame.new(origin)
end

-- Tools already put through normaliseAuthoredTool. Weak-keyed so it cannot hold
-- a template alive past its folder.
local normalisedTools = setmetatable({}, { __mode = "k" })

--[[
	Makes an authored Tool actually work when equipped.

	Roblox welds exactly one thing to the hand - the direct child named Handle -
	and leaves the rest of the Tool to its own devices, so the natural way to
	build one (a model dropped in beside a small invisible Handle) equips to an
	empty hand.

	This welds the rest to the Handle and fixes the two silent mistakes: a
	Handle nested inside the model, and a Handle spelled "handle". Existing
	joints are left alone, so a tool with its own rig is not fused solid.
]]
local function normaliseAuthoredTool(itemName, tool)
	if normalisedTools[tool] then
		return tool
	end
	normalisedTools[tool] = true

	local handle = tool:FindFirstChild("Handle")

	if not (handle and handle:IsA("BasePart")) then
		local nested = tool:FindFirstChild("Handle", true)
		if nested and nested:IsA("BasePart") then
			warn(string.format(
				"[ToolFactory] '%s' keeps its Handle inside '%s'. Roblox only looks at direct "
					.. "children of the Tool, so it has been moved up.",
				itemName, tostring(nested.Parent and nested.Parent.Name)
			))
			nested.Parent = tool
			handle = nested
		end
	end

	if not (handle and handle:IsA("BasePart")) then
		for _, descendant in ipairs(tool:GetDescendants()) do
			if descendant:IsA("BasePart") and string.lower(descendant.Name) == "handle" then
				warn(string.format(
					"[ToolFactory] '%s' has a part called '%s'. The name has to be exactly "
						.. "'Handle' - renaming it.",
					itemName, descendant.Name
				))
				descendant.Name = "Handle"
				descendant.Parent = tool
				handle = descendant
				break
			end
		end
	end

	if not (handle and handle:IsA("BasePart")) then
		local guess = tool:FindFirstChildWhichIsA("BasePart", true)
		if guess then
			warn(string.format(
				"[ToolFactory] '%s' has no Handle; using '%s'. Add a part named Handle to "
					.. "choose where it is held.",
				itemName, guess.Name
			))
			guess.Name = "Handle"
			guess.Parent = tool
			handle = guess
		end
	end

	if not handle then
		warn(string.format(
			"[ToolFactory] '%s' is a Tool with no BasePart in it, so there is nothing to hold.",
			itemName
		))
		return tool
	end

	-- Anything an existing joint already holds is left for that joint to hold.
	local jointed = {}
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("WeldConstraint") or descendant:IsA("JointInstance") then
			if descendant.Part0 then
				jointed[descendant.Part0] = true
			end
			if descendant.Part1 then
				jointed[descendant.Part1] = true
			end
		end
	end

	-- Welded before anything is unanchored, so each part records the offset it
	-- was authored at.
	local welded = 0
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= handle and not jointed[descendant] then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = descendant
			weld.Parent = descendant
			welded += 1
		end
	end

	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			styleBasePart(descendant)
		end
	end

	if tool:GetAttribute("ItemName") == nil then
		tool:SetAttribute("ItemName", itemName)
	end

	local grip = gripFromAttributes(tool)
	if grip then
		tool.Grip = grip
	end

	return tool
end

--[[
	Wraps a single BasePart - the shape a one-piece mesh export arrives as.

	Kept separate from the Model path because there is nothing to weld and
	nothing to choose: the part IS the handle.
]]
local function wrapBasePart(itemName, definition, part)
	local tool = Instance.new("Tool")
	tool.Name = itemName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = definition and definition.description or itemName

	local grip = gripFromAttributes(part)
	if grip then
		tool.Grip = grip
	end

	styleBasePart(part)
	part.Name = "Handle"
	part.Parent = tool

	tool:SetAttribute("ItemName", itemName)
	return tool
end

--[[
	Turns an authored Model into a Tool.

	Order matters. Everything is welded to the handle BEFORE anything is
	reparented or unanchored: a WeldConstraint locks in the offset between two
	parts as it stands, so welding first is what preserves the shape the model
	was built in.
]]
local function wrapModel(itemName, definition, model)
	local handle = chooseHandle(itemName, model)
	if not handle then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = itemName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = definition and definition.description or itemName

	local grip = gripFromAttributes(model)
	if grip then
		tool.Grip = grip
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end

	-- Anchored parts hang in mid-air instead of following the hand, and a
	-- colliding tool shoves its owner around. Applied to every part, not just
	-- the top level, because a model can nest.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			styleBasePart(descendant)
		end
	end

	-- RequiresHandle looks for a DIRECT child called Handle, so a handle buried
	-- inside a sub-model has to come up to the top. Its welds keep the rest of
	-- the model attached to it wherever it sits in the hierarchy.
	handle.Name = "Handle"
	handle.Parent = tool

	for _, child in ipairs(model:GetChildren()) do
		child.Parent = tool
	end

	tool:SetAttribute("ItemName", itemName)

	model:Destroy()
	return tool
end

--[[
	Returns the template for an item, building it on first use.

	Returns nil for items that are not holdable at all, which is how a caller
	distinguishes "no template" from "this was never meant to be a tool".
]]
function ToolFactory.ensure(itemName)
	if type(itemName) ~= "string" or itemName == "" then
		return nil
	end

	local definition = ItemDefinitions[itemName]
	local existing = toolsFolder:FindFirstChild(itemName)

	if existing then
		if existing:IsA("Tool") then
			return normaliseAuthoredTool(itemName, existing)
		end

		if existing:IsA("BasePart") then
			local wrapped = wrapBasePart(itemName, definition, existing)
			wrapped.Parent = toolsFolder
			return wrapped
		end

		if existing:IsA("Model") then
			local wrapped = wrapModel(itemName, definition, existing)
			if wrapped then
				wrapped.Parent = toolsFolder
				return wrapped
			end

			-- A model with no parts in it cannot become anything.
			warn(string.format(
				"[ToolFactory] '%s' is a Model with no BasePart in it, so it cannot be held.",
				itemName
			))
			existing:Destroy()
		else
			warn(string.format(
				"[ToolFactory] '%s' in ReplicatedStorage.Tools is a %s. Tools must be a Tool "
					.. "or a Model; this one is being ignored.",
				itemName, existing.ClassName
			))
			return nil
		end
	end

	if not definition or not ToolConfig.isHoldable(definition.classification) then
		return nil
	end

	-- Nothing authored. Whether to invent something is a deliberate choice, not
	-- a default: a generated stand-in is indistinguishable at a glance from a
	-- real asset that failed to load, which makes "my model is not showing up"
	-- much harder to notice than it should be.
	if not ToolConfig.GenerateMissingTools then
		return nil
	end

	local tool = buildTool(itemName, definition)
	tool.Parent = toolsFolder
	return tool
end

--[[
	Resolves every tool the item table describes, up front.

	At startup rather than on first equip, so nobody pays for assembly mid-game
	and a mistake in ToolConfig or in somebody's model shows up in the boot log.

	Routed through ensure, so an authored model is wrapped here too. Returns
	built, wrapped, missing.
]]
function ToolFactory.buildAll()
	local built = 0
	local wrapped = 0
	local missing = {}

	for itemName, definition in pairs(ItemDefinitions) do
		if ToolConfig.isHoldable(definition.classification) then
			local authored = toolsFolder:FindFirstChild(itemName)
			local wasAuthoredAsset = authored ~= nil
				and (authored:IsA("Model") or authored:IsA("BasePart"))
			local hadTemplate = authored ~= nil

			if ToolFactory.ensure(itemName) then
				if wasAuthoredAsset then
					wrapped += 1
				elseif not hadTemplate then
					built += 1
				end
			elseif not hadTemplate then
				table.insert(missing, itemName)
			end
		end
	end

	-- Named, not counted. "12 items have no asset" is a statistic; the list is
	-- a task, and it is the only warning that a model failed to be picked up.
	if #missing > 0 then
		table.sort(missing)
		warn(string.format(
			"[ToolFactory] No asset in ReplicatedStorage.Tools for %d holdable item(s); they "
				.. "cannot be equipped: %s",
			#missing, table.concat(missing, ", ")
		))
	end

	return built, wrapped, missing
end

return ToolFactory
