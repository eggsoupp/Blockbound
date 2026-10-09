--[[
	HarvestClient

	Swinging an axe at a tree, and what that looks like.

	ASKING: on a click, if what the player holds can harvest anything at all,
	this raycasts and tells the server what was hit. That is the whole of the
	client's involvement - HarvestServer re-checks reach, owns the tree's
	remaining chops, decides when it falls and pays out the wood.

	DRAWING: one message per chop arrives from the server and becomes chips and
	a sound. The fall itself is not drawn here; the server tips the model over,
	so every player watches the same tree go down.

	One script rather than one per axe, watching the character for any Tool the
	way ToolFeedback does. What counts as an axe is StructureConfig's business:
	it declares which tool classification each harvestable thing needs, so a
	structure made choppable by a new class works without this file learning its
	name.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local StructureConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("StructureConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local RequestHarvest = Remotes.wait("RequestHarvest")
local HarvestEffect = Remotes.wait("HarvestEffect")

local player = Players.LocalPlayer

--[[
	How far a swing reaches, measured FROM THE CHARACTER.

	Not from the camera, which is where the ray starts - see chop() for why the
	two came apart and broke chopping entirely.

	Shorter than HarvestServer's MAX_REACH of 20 on purpose. The server's number
	is a limit on what it will believe from a lagging client; this one is what
	the game actually feels like, and a chop that connects with a tree the player
	can barely see is worse than one that misses.
]]
local CHOP_RANGE = 14

-- Chips per chop, and on the swing that brings it down.
local CHIPS_PER_CHOP = 7
local CHIPS_ON_FELL = 16

local CHIP_SIZE = 0.34
local CHIP_LIFETIME = 1.2

-- ---------------------------------------------------------------------------
-- Asking
-- ---------------------------------------------------------------------------

local function itemNameFor(tool)
	local attribute = tool:GetAttribute("ItemName") or tool:GetAttribute("itemName")
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end

	local value = tool:FindFirstChild("ItemName") or tool:FindFirstChild("itemName")
	if value and value:IsA("StringValue") and value.Value ~= "" then
		return value.Value
	end

	return tool.Name
end

--[[
	Whether swinging this tool is worth telling the server about.

	Read from StructureConfig rather than tested against "Tool" here; see the
	note at the top. `any` means something in the world can be harvested with
	bare hands, and then every swing is worth sending.
]]
local function canHarvest(tool): boolean
	local classes = StructureConfig.harvestToolClasses()
	if classes.any then
		return true
	end

	local definition = ItemDefinitions[itemNameFor(tool)]
	return definition ~= nil and classes[definition.classification] == true
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true -- water is Terrain; aim through it

local function chop(tool)
	local character = player.Character
	local camera = workspace.CurrentCamera
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and camera and root) then
		return
	end

	if not canHarvest(tool) then
		return
	end

	rayParams.FilterDescendantsInstances = { character }

	--[[
		Aimed from the CAMERA, reached from the CHARACTER.

		These are two different distances and conflating them is what stopped
		the axe working at all. The ray has to start at the camera, because that
		is where the player is aiming from - but in third person the camera sits
		about twelve studs BEHIND the character, so a ray only CHOP_RANGE long
		ran out roughly a stud in front of them and never reached a tree they
		were standing next to.

		So the ray is long enough to cover the camera's own set-back as well,
		and the reach is then checked properly: from the character to whatever
		was hit. Mining has always worked this way - it aims with an unbounded
		camera ray and lets the server measure from the root.
	]]
	local origin = camera.CFrame.Position
	local setBack = (origin - root.Position).Magnitude

	local result = workspace:Raycast(
		origin,
		camera.CFrame.LookVector * (setBack + CHOP_RANGE),
		rayParams
	)

	if not result then
		return
	end

	-- The reach that actually matters. Without it, aiming past the trees at
	-- one further away would chop it from wherever you were standing.
	if (result.Position - root.Position).Magnitude > CHOP_RANGE then
		return
	end

	--[[
		The part, and nothing else.

		Not the position, not the model, not what the client thinks it is
		worth - the server takes the part, finds its tag, finds its model
		and re-measures the distance itself. A client that sends a part it
		is nowhere near gets nothing back.
	]]
	RequestHarvest:FireServer(result.Instance)
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

--[[
	A shower of small cubes in the wood's own colour.

	Real parts rather than a ParticleEmitter, matching MiningClient: the game is
	blocky, so blocky debris reads correctly and it needs no particle texture.
	They are unanchored but massless and non-colliding, so they cost almost
	nothing and cannot shove anybody around.
]]
local function spawnChips(position: Vector3, color: Color3, count: number)
	for _ = 1, count do
		local chip = Instance.new("Part")
		chip.Size = Vector3.new(CHIP_SIZE, CHIP_SIZE, CHIP_SIZE * 2.2)
		chip.Color = color
		chip.Material = Enum.Material.Wood
		chip.CanCollide = false
		chip.CanQuery = false
		chip.CanTouch = false
		chip.Massless = true
		chip.CFrame = CFrame.new(position + Vector3.new(
			(math.random() - 0.5) * 1.6,
			(math.random() - 0.5) * 1.6,
			(math.random() - 0.5) * 1.6
		)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chip.Parent = workspace

		-- Velocity has to be set AFTER parenting: an unparented part has no
		-- assembly for the physics engine to apply it to, so setting it first
		-- silently does nothing and the chips just drop straight down.
		chip.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 16,
			math.random() * 11 + 4,
			(math.random() - 0.5) * 16
		)

		Debris:AddItem(chip, CHIP_LIFETIME)
	end
end

HarvestEffect.OnClientEvent:Connect(function(position, color, felled)
	if typeof(position) ~= "Vector3" then
		return
	end

	local tint = if typeof(color) == "Color3" then color else Color3.fromRGB(146, 106, 62)

	if felled then
		spawnChips(position, tint, CHIPS_ON_FELL)
		Sounds.playAt("mine.break.wood", position)
	else
		spawnChips(position, tint, CHIPS_PER_CHOP)
		Sounds.playAt("mine.hit.wood", position)
	end
end)

-- ---------------------------------------------------------------------------
-- Following the character
-- ---------------------------------------------------------------------------

local tracked = setmetatable({}, { __mode = "k" })

local function trackTool(tool: Tool)
	if tracked[tool] then
		return
	end
	tracked[tool] = true

	tool.Activated:Connect(function()
		chop(tool)
	end)
end

local function watchCharacter(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			trackTool(child)
		end
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			trackTool(child)
		end
	end)
end

if player.Character then
	watchCharacter(player.Character)
end
player.CharacterAdded:Connect(watchCharacter)
