--[[
	HarvestClient

	Swinging an axe at a tree, and what that looks like.

	ASKING: on a click, if what the player holds can harvest anything at all,
	this finds the tree under the CURSOR - forgivingly, since a trunk is far
	thinner than a block (see aimAtTree) - and tells the server which part. That
	is the whole of the client's involvement - HarvestServer re-checks reach,
	owns the tree's remaining chops, decides when it falls and pays out the wood.

	DRAWING: one message per chop arrives from the server and becomes chips and
	a sound. The fall itself is not drawn here; the server tips the model over,
	so every player watches the same tree go down.

	TARGETING: while an axe is held, the tree a swing would reach is outlined
	(Shared.UI.WorldFeedback's focus, claimed as "harvest") and whitens as its
	Health value - the server's own count of chops left - goes down. A chop the
	server confirms flashes it; a swing at a tree out of reach flashes red.

	One script rather than one per axe, watching the character for any Tool the
	way ToolFeedback does. What counts as an axe is StructureConfig's business:
	it declares which tool classification each harvestable thing needs, so a
	structure made choppable by a new class works without this file learning its
	name.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local StructureConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("StructureConfig"))
local MenuState = require(Shared:WaitForChild("UI"):WaitForChild("MenuState"))
local WorldFeedback = require(Shared.UI:WaitForChild("WorldFeedback"))
local ToolConfig = require(Shared:WaitForChild("Tools"):WaitForChild("ToolConfig"))
local ToolAnimation = require(Shared.Tools:WaitForChild("ToolAnimation"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local RequestHarvest = Remotes.wait("RequestHarvest")
local HarvestEffect = Remotes.wait("HarvestEffect")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

--[[
	How far a swing reaches, measured FROM THE CHARACTER to the point struck -
	the same reach, measured the same way, as mining. HarvestServer enforces it.
]]
local REACH = StructureConfig.HarvestReach

--[[
	How forgiving the aim is. A tree is a thin trunk and some branches, not a
	four-stud cube, so a ray that has to land exactly on one made chopping much
	harder than mining. Two allowances, tried in order after the exact ray:

	  AIM_RADIUS   the ray is fattened to this radius, so a trunk or branch the
	               cursor slid just past still counts
	  NEAR_RADIUS  a click landing this close to a tree - on the ground at its
	               foot, through a gap in the leaves - counts as the tree

	Both only ever pick a tree the cursor is visibly at: the fat ray stops at
	the first thing it touches, and the near search is around the point the
	cursor actually landed on, so nothing is chopped through a wall.
]]
local AIM_RADIUS = 1.25
local NEAR_RADIUS = 2.5

-- Chips per chop, and on the swing that brings it down.
local CHIPS_PER_CHOP = 7
local CHIPS_ON_FELL = 16

local CHIP_SIZE = 0.34
local CHIP_LIFETIME = 1.2

-- How often the hover outline re-aims while an axe is held.
local HOVER_INTERVAL = 1 / 15

-- The tags HarvestServer reads: every structure that declares a harvest.
local harvestTags = {}
for _, def in ipairs(StructureConfig.Definitions) do
	if def.tag and def.harvest and not table.find(harvestTags, def.tag) then
		table.insert(harvestTags, def.tag)
	end
end

local function isHarvestable(part: Instance): boolean
	for _, tag in ipairs(harvestTags) do
		if CollectionService:HasTag(part, tag) then
			return true
		end
	end
	return false
end

-- Trees seen to fall from here. Weak, so they go when the model does.
local fallen = setmetatable({}, { __mode = "k" })

-- The model a part belongs to, the way HarvestServer finds it, or nil for one
-- that is already on its way down.
local function standingTreeFor(part: Instance): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	if not model or fallen[model] or model:GetAttribute("Felled") then
		return nil
	end
	return model
end

-- The part the last chop was sent for, so the server's confirmation can be
-- told apart from somebody else's chop nearby. HarvestServer reports the hit
-- part's own position, which is what makes the match exact.
local pendingPart: BasePart? = nil
local pendingAt = 0

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

-- ---------------------------------------------------------------------------
-- Aiming
-- ---------------------------------------------------------------------------

-- Built once; only the character in the filter ever changes.
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true -- water is Terrain; aim through it

local nearParams = OverlapParams.new()
nearParams.FilterType = Enum.RaycastFilterType.Exclude

local aimExcluded = {}

-- The nearest point of a part's box to `point`.
local function nearestPointOn(part: BasePart, point: Vector3): Vector3
	local half = part.Size * 0.5
	local localPoint = part.CFrame:PointToObjectSpace(point)
	return part.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	))
end

-- The tree part closest to where the cursor landed, within NEAR_RADIUS.
local function treePartNear(at: Vector3)
	local best, bestPoint, bestDistance = nil, nil, NEAR_RADIUS

	for _, candidate in ipairs(workspace:GetPartBoundsInRadius(at, NEAR_RADIUS, nearParams)) do
		if isHarvestable(candidate) then
			local point = nearestPointOn(candidate, at)
			local distance = (point - at).Magnitude
			if distance <= bestDistance then
				best, bestPoint, bestDistance = candidate, point, distance
			end
		end
	end

	return best, bestPoint
end

--[[
	The standing tree part the cursor is at, where on it, and whether that is
	within REACH of the character - or nil when the cursor is at no tree.

	Aimed with the CURSOR, as mining is. It used to be the middle of the
	screen, so with a free mouse a tree under the cursor was simply not what
	the axe aimed at. The ray starts at the camera and is long enough to cover
	the camera's set-back behind the character as well as the reach; the reach
	itself is measured from the character to the point struck.

	Then forgiving, in order: the exact ray, a fat ray, a tree right beside
	where the cursor landed. See AIM_RADIUS and NEAR_RADIUS.
]]
local function aimAtTree(character: Model, root: BasePart)
	if aimExcluded[1] ~= character then
		aimExcluded[1] = character
		aimParams.FilterDescendantsInstances = aimExcluded
		nearParams.FilterDescendantsInstances = aimExcluded
	end

	local ray = mouse.UnitRay
	local length = (ray.Origin - root.Position).Magnitude + REACH + NEAR_RADIUS
	local direction = ray.Direction * length

	local part, point = nil, nil

	local hit = workspace:Raycast(ray.Origin, direction, aimParams)
	if hit and isHarvestable(hit.Instance) then
		part, point = hit.Instance, hit.Position
	else
		local fat = workspace:Spherecast(ray.Origin, AIM_RADIUS, direction, aimParams)
		if fat and isHarvestable(fat.Instance) then
			part, point = fat.Instance, fat.Position
		elseif hit then
			part, point = treePartNear(hit.Position)
		end
	end

	if not part or not standingTreeFor(part) then
		return nil
	end

	return part, point, (point - root.Position).Magnitude <= REACH
end

local function chop(tool)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root) or MenuState.isAnyOpen() then
		return
	end

	if not canHarvest(tool) then
		return
	end

	local part, _, inReach = aimAtTree(character, root)
	if not part then
		return
	end

	if not inReach then
		-- Say so on the tree rather than swinging at nothing.
		WorldFeedback.flash(standingTreeFor(part), "Invalid")
		return
	end

	pendingPart = part
	pendingAt = os.clock()

	--[[
		The part, and nothing else.

		Not the position, not the model, not what the client thinks it is
		worth - the server takes the part, finds its tag, finds its model
		and re-measures the distance itself, to the nearest point of that
		part. A client that sends a part it is nowhere near gets nothing back.
	]]
	RequestHarvest:FireServer(part)
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

	-- Ours, rather than a neighbour's: the server reports the hit part's own
	-- position, so the part we asked about matches it exactly.
	local part = pendingPart
	if not (part and os.clock() - pendingAt < 1 and (part.Position - position).Magnitude < 0.05) then
		return
	end
	pendingPart = nil

	if felled then
		-- Down, so nothing to outline any more - at once, not after a fade.
		-- Remembered too: the Felled attribute can land a moment after this
		-- message, and the hover loop must not re-outline a falling tree.
		local model = part:FindFirstAncestorOfClass("Model")
		if model then
			fallen[model] = true
		end
		WorldFeedback.release("harvest", true)
		WorldFeedback.impact(position, tint:Lerp(Color3.new(1, 1, 1), 0.35), 3.5)
	else
		WorldFeedback.flash(standingTreeFor(part), "Hit", 0.16)
	end
end)

-- ---------------------------------------------------------------------------
-- Following the character
-- ---------------------------------------------------------------------------

--[[
	THE RHYTHM

	One swing per StructureConfig.ChopSeconds, however the button is pressed.
	Holding it swings on that beat for as long as it is held; clicking faster
	than the beat does nothing extra, because a swing is only ever started by
	the beat. HarvestServer enforces the same interval, so this is the honest
	rhythm rather than a suggestion.

	Each swing plays the axe's animation and swing sound - here, not in
	ToolFeedback, so what the player sees and hears matches the chops actually
	happening rather than the clicks - and then chops whatever tree the cursor
	is at, if any.
]]
local CHOP_SECONDS = StructureConfig.ChopSeconds

local holding = false
local holdToken = 0
local lastSwingAt = -math.huge

local function playSwing(tool)
	local character = player.Character
	local definition = ItemDefinitions[itemNameFor(tool)]
	local id = definition and ToolConfig.animationFor(definition.classification, definition)
	local track = id and character and ToolAnimation.track(character, id)
	if not track then
		return
	end

	if track.IsPlaying then
		track:Stop(0.05)
	end
	-- One swing per chop. The pickaxe shares this animation and loops it
	-- while mining; this must not inherit that.
	track.Looped = false
	track:Play()
end

local function swing(tool)
	lastSwingAt = os.clock()
	Sounds.play("tool.swing")
	playSwing(tool)
	chop(tool)
end

local function stopChopping()
	holding = false
	holdToken += 1
end

local function startChopping(tool)
	if not canHarvest(tool) then
		return
	end

	holding = true
	holdToken += 1
	local token = holdToken

	task.spawn(function()
		while holding and holdToken == token and tool.Parent and tool.Parent == player.Character do
			local wait = lastSwingAt + CHOP_SECONDS - os.clock()
			if wait <= 0 then
				swing(tool)
				wait = CHOP_SECONDS
			end
			task.wait(wait)
		end
	end)
end

-- A menu over the world ends the hold, as it does mining's.
MenuState.Changed:Connect(function(_, _, anyOpen)
	if anyOpen then
		stopChopping()
	end
end)

local tracked = setmetatable({}, { __mode = "k" })

local function trackTool(tool: Tool)
	if tracked[tool] then
		return
	end
	tracked[tool] = true

	tool.Activated:Connect(function()
		startChopping(tool)
	end)
	tool.Deactivated:Connect(stopChopping)
	tool.Unequipped:Connect(stopChopping)
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

-- ---------------------------------------------------------------------------
-- Hover outline
-- ---------------------------------------------------------------------------
--[[
	Outlines the tree a swing would chop, asking aimAtTree - the very same
	question chop() asks, cursor, forgiveness and reach included - so what is
	outlined is always what a click takes. 15Hz rather than per frame.

	Progress is the tree's own Health IntValue, which HarvestServer counts down
	and which replicates with the model. Its maximum is not stored anywhere, so
	the first value seen stands in for it: an untouched tree is at full health,
	and a tree somebody else started is shown from where this client met it.
]]

local maxHealthSeen = setmetatable({}, { __mode = "k" })

-- canHarvest builds a table per call; asked once per equip instead.
local hoverTool, hoverToolHarvests = nil, false

local function heldHarvestTool(character)
	local tool = character:FindFirstChildOfClass("Tool")
	if tool ~= hoverTool then
		hoverTool = tool
		hoverToolHarvests = tool ~= nil and canHarvest(tool)
	end
	return hoverToolHarvests
end

local function updateHover()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root or MenuState.isAnyOpen() or not heldHarvestTool(character) then
		WorldFeedback.release("harvest")
		return
	end

	local part, _, inReach = aimAtTree(character, root)
	local tree = part and inReach and standingTreeFor(part)

	if not tree then
		WorldFeedback.release("harvest")
		return
	end

	WorldFeedback.focus("harvest", tree, "Harvest")

	local health = tree:FindFirstChild("Health")
	if health and health:IsA("IntValue") then
		local most = math.max(maxHealthSeen[tree] or 0, health.Value)
		maxHealthSeen[tree] = most
		WorldFeedback.progress("harvest", if most > 0 then 1 - health.Value / most else 0)
	end
end

local hoverAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	hoverAccumulator += dt
	if hoverAccumulator < HOVER_INTERVAL then
		return
	end
	hoverAccumulator = 0
	updateHover()
end)
