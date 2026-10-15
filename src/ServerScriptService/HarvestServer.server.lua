--[[
	HarvestServer

	Breaking down tagged structures - trees today, whatever gets a `harvest`
	block in StructureConfig tomorrow.

	Nothing here names a tree. Structures declare `tag` and `harvest` in
	StructureConfig and this builds a tag -> rules map at startup, so making
	rocks or ruins harvestable later is a config change.

	A structure carries its remaining chops as a Health IntValue, stamped on by
	StructureRegistry. Each accepted swing takes one off and tells nearby
	clients to throw chips; the swing that reaches zero marks the model, pays
	out, and tips it over before removing it.

	The fall happens HERE rather than on the clients - see `fell` - because
	every player has to watch the same tree go down.

	The wood lands on the ground beside the trunk (GroundDrops) rather than in
	the bag, and is picked up by walking over to it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local StructureConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("StructureConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local GroundDrops = require(ServerScriptService:WaitForChild("GroundDrops"))

local RequestHarvest = Remotes.ensure("RequestHarvest", "RemoteEvent")

--[[
	One message per chop, to everybody near enough to hear the axe.

	The clients draw the chips and play the sound; nothing about what the chop
	DID travels in it, because that has already happened on this side by the
	time it is sent.
]]
local HarvestEffect = Remotes.ensure("HarvestEffect", "RemoteEvent")

--[[
	How far from the character a struck part may be, measured to the NEAREST
	POINT of that part rather than its centre.

	It used to be the centre, with a reach of 20 - and a tree is a few big
	parts whose centres sit high up and far in, so a chop at a trunk right in
	front of the player could be measured as out of reach and dropped without a
	word. The nearest point is what the player actually swung at.

	StructureConfig.HarvestReach is the reach the client aims with; the slack is
	for a player who stepped back while the request was in flight.
]]
local REACH_SLACK = 4
local MAX_REACH = StructureConfig.HarvestReach + REACH_SLACK
local MIN_REQUEST_INTERVAL = 0.25

--[[
	The chop rhythm: one landed chop per StructureConfig.ChopSeconds per player.

	Separate from MIN_REQUEST_INTERVAL, which only stops a flood of requests.
	This is the gameplay rule, and it is why clicking faster no longer chops
	faster. Stamped when a chop LANDS, so a request that fails for any other
	reason (out of reach, wrong tool) does not cost the player their next one.

	The grace absorbs network jitter: the client sends exactly once per
	ChopSeconds, and a request that arrives a hair early must not be dropped.
]]
local CHOP_GRACE = 0.1
local CHOP_INTERVAL = StructureConfig.ChopSeconds - CHOP_GRACE

-- Distance from a point to the nearest point of a part's box.
local function distanceToPart(part: BasePart, point: Vector3): number
	local half = part.Size * 0.5
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local nearest = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return (localPoint - nearest).Magnitude
end

-- How far a chop is drawn and heard. A little past the distance a tree is
-- recognisable from, so nothing pops silently at the edge of view.
local EFFECT_RADIUS = 180

--[[
	How a tree falls: how long it takes to go over, and how far past horizontal
	it keeps turning.

	Slightly past ninety degrees, because a trunk that stops exactly flat looks
	placed rather than fallen. The whole thing is over in half a second - long
	enough to read as a fall, short enough that nobody is waiting for their wood.
]]
local FALL_TIME = 0.55
local FALL_ANGLE = math.rad(96)

--[[
	The FALLBACK number of chops, for a structure that reaches here without one.

	Normally it never applies: StructureRegistry stamps a Health IntValue onto
	every structure as it is built, derived from the model's height when the
	definition says "auto". This is for the case where something harvestable was
	placed by another path and has no Health at all - which used to default to a
	single chop, so the first swing felled it whatever it was.
]]
local AUTO_HEALTH_PER_STUD = 0.25
local AUTO_HEALTH_MIN = 2
local AUTO_HEALTH_MAX = 6

local rulesByTag = {}
local lastRequestAt = {}
local lastChopAt = {}
local rng = Random.new()

for _, def in ipairs(StructureConfig.Definitions) do
	if def.tag and def.harvest and ItemDefinitions[def.harvest.item] then
		-- The health lives beside the harvest rules rather than in them: it is
		-- a property of the structure, and StructureConfig declares it there.
		rulesByTag[def.tag] = { harvest = def.harvest, health = def.health }
	elseif def.harvest then
		warn(string.format(
			"[HarvestServer] '%s' declares harvest but is missing a tag or a known item; ignored.",
			tostring(def.id)
		))
	end
end

--[[
	What a part belongs to: its structure's harvest rules and its health, or nil
	if it is not part of anything harvestable.
]]
local function rulesFor(part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return nil
	end

	for tag, rules in pairs(rulesByTag) do
		if CollectionService:HasTag(part, tag) then
			return rules
		end
	end

	return nil
end

--[[
	How many chops this structure takes, when it arrived without a Health value
	of its own.

	Mirrors what StructureRegistry does at build time - a number is that many
	chops, "auto" derives it from the model's height - so a tree that missed
	being stamped still behaves like the ones around it rather than falling to
	one swing.
]]
local function healthFor(model, spec)
	local declared = spec and spec.health

	if type(declared) == "number" and declared > 0 then
		return math.max(1, math.floor(declared))
	end

	if declared == "auto" then
		local height = model:GetExtentsSize().Y
		return math.clamp(
			math.round(height * AUTO_HEALTH_PER_STUD),
			AUTO_HEALTH_MIN,
			AUTO_HEALTH_MAX
		)
	end

	return AUTO_HEALTH_MIN + 1
end

--[[
	Tells everybody nearby that a chop landed.

	Sent to players rather than to everyone: a tree coming down on the far side
	of the world is not worth a packet, and this fires several times per tree.
]]
local function broadcast(position: Vector3, color: Color3, felled: boolean)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if root and (root.Position - position).Magnitude <= EFFECT_RADIUS then
			HarvestEffect:FireClient(player, position, color, felled)
		end
	end
end

--[[
	Puts the tree on the ground and then removes it.

	Done on the SERVER, unlike most of this game's effects, and deliberately: a
	falling tree is one model turning for half a second, and everybody has to
	see the same one go down. Drawn per client instead, half the players would
	watch a tree vanish while the other half watched it topple.

	It accelerates rather than turning evenly - the square below is what makes
	it read as falling rather than as being rotated - and it turns AWAY from
	whoever chopped it, which is the detail that makes it feel like their doing.

	The model is checked every step: chunks stream out, and a tree can be
	unloaded from under this while it is coming down.
]]
local function fell(model: Model, awayFrom: Vector3)
	local pivot = model:GetPivot()
	local box, size = model:GetBoundingBox()

	-- The base of the trunk, which is the only sensible thing to turn about:
	-- rotating around the middle would sink half the tree into the ground.
	local base = box.Position - Vector3.new(0, size.Y * 0.5, 0)

	local away = (box.Position - awayFrom) * Vector3.new(1, 0, 1)
	local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)

	-- The axis to turn about is horizontal and across the fall direction.
	local axis = Vector3.yAxis:Cross(direction)
	if axis.Magnitude < 0.01 then
		axis = Vector3.xAxis
	end
	axis = axis.Unit

	task.spawn(function()
		local startedAt = os.clock()

		while true do
			if not model.Parent then
				return
			end

			local progress = (os.clock() - startedAt) / FALL_TIME
			if progress >= 1 then
				break
			end

			local angle = FALL_ANGLE * progress * progress
			local turn = CFrame.fromAxisAngle(axis, angle)

			model:PivotTo(CFrame.new(base) * turn * CFrame.new(-base) * pivot)
			task.wait()
		end

		if model.Parent then
			model:Destroy()
		end
	end)
end

local function holdsRequiredTool(player, toolClass)
	if not toolClass then
		return true
	end

	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return false
	end

	local named = tool:GetAttribute("ItemName") or tool:GetAttribute("itemName") or tool.Name
	local def = ItemDefinitions[named]
	return def ~= nil and def.classification == toolClass
end

RequestHarvest.OnServerEvent:Connect(function(player, target)
	local now = os.clock()
	local last = lastRequestAt[player]
	if last and now - last < MIN_REQUEST_INTERVAL then
		return
	end

	local lastChop = lastChopAt[player]
	if lastChop and now - lastChop < CHOP_INTERVAL then
		return
	end
	lastRequestAt[player] = now

	local spec = rulesFor(target)
	if not spec then
		return
	end

	local rules = spec.harvest

	local model = target:FindFirstAncestorOfClass("Model")
	if not model or not model.Parent then
		return
	end

	-- Already chopped down and on its way over. The parts are still tagged and
	-- still there for the length of the fall, so without this a fast second
	-- click would harvest the same tree twice.
	if model:GetAttribute("Felled") then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or distanceToPart(target, hrp.Position) > MAX_REACH then
		return
	end

	if not holdsRequiredTool(player, rules.toolClass) then
		return
	end

	--[[
		The tree's remaining chops.

		StructureRegistry puts this on every structure as it builds it, so the
		branch below is the exception rather than the rule - see healthFor. An
		IntValue on the model rather than a table in this script because it is
		the tree's state, not the server's: it is visible in the explorer while
		debugging and it disappears with the tree instead of leaking an entry per
		tree the world has ever generated.
	]]
	local health = model:FindFirstChild("Health")
	if not health or not health:IsA("IntValue") then
		health = Instance.new("IntValue")
		health.Name = "Health"
		health.Value = healthFor(model, spec)
		health.Parent = model
	end

	local damage = rules.damage or 1
	local amount = rng:NextInteger(rules.min or 1, rules.max or rules.min or 1)

	-- No room-in-the-bag refusal any more: the wood lands on the ground and
	-- waits there, so a full bag can no longer destroy it.

	lastChopAt[player] = now
	health.Value -= damage

	-- The chip colour is the wood's own, taken from the part that was actually
	-- hit, so a birch throws pale chips and an oak throws brown ones without
	-- anybody configuring either.
	broadcast(target.Position, target.Color, health.Value <= 0)

	if health.Value > 0 then
		return
	end

	--[[
		Marked and untagged BEFORE anything is paid out.

		The model has to stay in the world for the length of the fall, so it
		cannot be destroyed here the way it used to be - and a tree that is
		still standing, still tagged and already paid for is exactly the shape
		of a duplication bug. The attribute is what the guard above reads; the
		tags come off so nothing else can find it either.
	]]
	model:SetAttribute("Felled", true)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			for tag in pairs(rulesByTag) do
				if CollectionService:HasTag(descendant, tag) then
					CollectionService:RemoveTag(descendant, tag)
				end
			end
		end
	end

	fell(model, hrp.Position)

	-- On the chopper's side of the trunk, a step out from it: straight down
	-- from the trunk would leave the wood floating inside the falling tree.
	local where = target.Position
	local toward = (hrp.Position - where) * Vector3.new(1, 0, 1)
	if toward.Magnitude > 0.1 then
		where += toward.Unit * 3
	end

	GroundDrops.spawn(rules.item, amount, where, player)

	-- Optional second drop, rolled on the server like everything else.
	local bonus = rules.bonus
	if bonus and ItemDefinitions[bonus.item] and rng:NextNumber() < (bonus.chance or 0) then
		GroundDrops.spawn(
			bonus.item,
			rng:NextInteger(bonus.min or 1, bonus.max or bonus.min or 1),
			where,
			player
		)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
	lastChopAt[player] = nil
end)
