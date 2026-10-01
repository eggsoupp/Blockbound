--[[
	ScrollService

	A scroll is a thing in the WORLD now, not a thing in a bag.

		ScrollService.start()                       -- adopt whatever is already there
		ScrollService.place(abilityName, cframe)    -- put one down
		ScrollService.adopt(instance)               -- make an authored one live
		ScrollService.count()                       -- how many are lying about

	Walk up to one, hold the prompt, and the ability is yours. The prompt is
	named after what it teaches - "Eclipse Scroll" - so what you get is legible
	from across the room and does not need a description to explain it.

	WHY IT IS NOT AN INVENTORY ITEM ANY MORE

	It was: ScrollOfEclipse sat in the bag, you equipped it, clicked, and
	confirmed a dialog. That is three interactions and a modal to learn one
	ability, and the whole middle of it was inventory plumbing - a tool
	template, a holdable classification, a stack size - none of which had
	anything to do with abilities. The item, the tool shape, the Scroll
	classification, the client that watched for the click and the remote it
	fired are all gone.

	What is left is the part that was always the point: an object in the world
	that you find, and taking it teaches you something.

	AUTHORING ONE IN STUDIO

	Tag a Model or a BasePart `AbilityScroll` and give it an `Ability` attribute
	naming an ability. That is the whole contract - this builds the prompt, the
	label and the glow, so nothing about the presentation has to be repeated on
	every copy, and changing it here changes every scroll in the place.

	The attribute is matched loosely (AbilityConfig.resolve), so "sacred rain"
	and "SacredRain" both work. One that names nothing real warns with the name
	it was given and is left inert rather than being deleted - somebody's typo
	should cost them a warning, not their model.

	===========================================================================
	THE TRUST BOUNDARY
	===========================================================================

	ProximityPromptService.PromptTriggered gives us a server-side prompt and a
	server-side Player, so there is no payload to forge. What a modified client
	CAN do is trigger a prompt it should not be able to reach - the range check
	that stops you activating things across the map is enforced by the client
	that draws the prompt, and a client that has been edited does not enforce
	anything. So every one of these is re-checked here, on a grant that is
	permanent and free:

	  1. the prompt is one of OURS, from this registry. An arbitrary prompt
	     somewhere in the world is not a scroll however it is triggered.
	  2. the scroll is UNCLAIMED, and it is claimed before anything that could
	     yield. Two triggers in one frame must not both be a grant.
	  3. the player is ALIVE and has a root part to measure from.
	  4. the player is actually NEAR IT - measured here, from the anchor's own
	     position, against the prompt's activation distance CLAMPED to a sane
	     ceiling. The clamp matters for an authored prompt: somebody setting
	     MaxActivationDistance to 500 in Studio should get a generous prompt,
	     not a hole in this check.
	  5. the scroll is still IN THE WORLD - not destroyed, not reparented out.
	  6. and it is rate limited per player, so a script cannot spend a frame
	     hammering every prompt in the place.

	A refusal that could only come from a modified client is WARNED rather than
	swallowed. Nothing here punishes anybody - it just means the first sign of
	somebody poking at this is a line in the log rather than an ability nobody
	can account for.

	THE ORDER: TEACH, THEN DESTROY

	AbilityLoadout.add is the thing that can fail - three slots full is the
	ordinary case, and the bin in the Tab menu is the answer to it. Destroying
	the scroll first would delete an ability nobody received. So the scroll is
	only removed once the ability is definitely in a slot, and a refusal puts
	the prompt straight back.

	NOBODY OPENS THE MENU FROM HERE

	AbilityLoadout.add pushes the new loadout, StarterPlayerScripts.AbilityClient
	notices exactly one new name, and PauseMenu is asked to open so the
	backdrop's flourish plays to a screen somebody is looking at. That path
	already existed for /add; a scroll is just another thing that calls the same
	function.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))

local AbilityLoadout = require(ServerScriptService:WaitForChild("AbilityLoadout"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

local ScrollService = {}

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- Tag an instance with this and give it an `Ability` attribute; see the header.
local SCROLL_TAG = "AbilityScroll"
local ABILITY_ATTRIBUTE = "Ability"

-- Where placed scrolls live, so the workspace root does not fill up with them
-- and so a developer can see at a glance what is out there.
local WORLD_FOLDER = "Scrolls"

local PROMPT_NAME = "ScrollPrompt"

--[[
	How long the prompt must be held.

	This IS the confirmation. There used to be a dialog - "Read the Scroll of
	Eclipse?" - because a scroll was consumed out of the bag and a mis-click
	burned it. A hold is the world-object version of the same question: it
	cannot be triggered by a stray key, it needs no modal over the game, and it
	is the idiom every player already knows.
]]
local HOLD_SECONDS = 0.6

-- How close you have to be. The ceiling is what an authored prompt is clamped
-- to before the distance check below trusts it.
local REACH = 12
local REACH_CEILING = 24

--[[
	Slack on the distance check, in studs.

	A player is where the SERVER last heard they were, which on a bad connection
	is a moment behind where they were when they let go of the prompt. Refusing
	on that would mean scrolls that fail for people with lag and work for
	everybody else, which is the worst kind of bug to be told about. Two studs
	is far less than the walk from anywhere useful.
]]
local REACH_SLACK = 2

-- Minimum gap between one player's grabs. A person cannot reach it; a script
-- sweeping every prompt in the place can.
local MIN_INTERVAL = 0.35

-- The placeholder, when no model has been authored. A rolled tube with a cap at
-- each end, floating and turning - the shape reads as "a scroll" and the motion
-- reads as "an item", which between them is the whole job.
--[[
	A Cylinder part's LENGTH is its Size.X and its diameter is Y and Z, and it
	therefore lies on its side until something turns it upright. That is the
	single most commonly missed thing about using one, and it is why these are
	written as length and diameter rather than as a Vector3 that would silently
	mean something else if the axes were swapped.
]]
local TUBE_LENGTH = 2.2
local TUBE_DIAMETER = 0.5
local CAP_LENGTH = 0.3
local CAP_DIAMETER = 0.85

local SPIN_SPEED = 0.9
local BOB_HEIGHT = 0.25
local BOB_SPEED = 1.6

-- Folder under ReplicatedStorage for authored scroll models, keyed by ability
-- name. Optional in every sense: a missing folder, or a missing model in it,
-- falls through to the placeholder.
local ASSETS_FOLDER = "ScrollAssets"

local DEBUG = false
local function log(...)
	if DEBUG then
		print("[ScrollService]", ...)
	end
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--[[
	prompt -> { ability, instance, anchor, claimed, reach }

	Keyed by the PROMPT, because that is what PromptTriggered hands us and the
	lookup is the first half of "is this one of ours". `instances` is the same
	set the other way round, so adopting something twice is a no-op rather than
	a second prompt on the same model.
]]
local scrolls = {}
local instances = {}
local scrollCount = 0

-- player -> os.clock() of their last grab attempt. Weak, so a player leaving
-- cannot keep their own record alive.
local lastGrabAt = setmetatable({}, { __mode = "k" })

-- The shared bob-and-spin. One connection for every scroll in the world, and
-- none at all when there are none.
local spin = nil

local started = false

-- ---------------------------------------------------------------------------
-- The world
-- ---------------------------------------------------------------------------

local function worldFolder(): Folder
	local folder = workspace:FindFirstChild(WORLD_FOLDER)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = WORLD_FOLDER
		folder.Parent = workspace
	end

	return folder :: Folder
end

--[[
	The BasePart a scroll is measured and prompted from.

	A Model's PrimaryPart if it has one, its first part otherwise, and the
	instance itself when it is already a part. Everything downstream - the
	prompt's parent, the distance check, the spin - wants one part rather than
	a shape, and this is the one place that decides which.
]]
local function anchorOf(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function stepSpin()
	local clock = os.clock()

	for _, record in pairs(scrolls) do
		local instance = record.instance

		if instance.Parent then
			local bob = math.sin(clock * BOB_SPEED + record.phase) * BOB_HEIGHT
			local turn = CFrame.Angles(0, clock * SPIN_SPEED + record.phase, 0)

			-- Around the point it was PUT, not around wherever it drifted to.
			-- Composing onto the live pivot would integrate the bob and walk it
			-- into the sky over a few minutes.
			local home = record.home
			instance:PivotTo(CFrame.new(home.Position + Vector3.new(0, bob, 0)) * turn)
		end
	end
end

local function updateSpin()
	if scrollCount > 0 and not spin then
		spin = RunService.Heartbeat:Connect(stepSpin)
	elseif scrollCount == 0 and spin then
		spin:Disconnect()
		spin = nil
	end
end

-- ---------------------------------------------------------------------------
-- Building one
-- ---------------------------------------------------------------------------

local function newPart(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

--[[
	The stand-in, coloured by what it teaches.

	Rarity rather than a scroll colour, and the same rarity the Tab menu paints
	the ability's name in: the object on the floor and the slot it ends up in
	are the same thing at two moments, and having them disagree about how rare
	it is would be the world telling the player one story and the menu another.
]]
local function buildPlaceholder(abilityName: string): Model
	local definition = AbilityConfig.get(abilityName)
	local tint = Theme.rarityColor(definition and definition.rarity)

	local model = Instance.new("Model")
	model.Name = abilityName .. "Scroll"

	-- Standing it up: a Cylinder's axis is its local X, so a quarter turn about
	-- Z is what points it at the sky. See the sizes above.
	local upright = CFrame.Angles(0, 0, math.rad(90))

	local tube = newPart(
		"Paper",
		Vector3.new(TUBE_LENGTH, TUBE_DIAMETER, TUBE_DIAMETER),
		Color3.fromRGB(238, 226, 196)
	)
	tube.Shape = Enum.PartType.Cylinder
	tube.CFrame = upright
	tube.Parent = model

	--[[
		The caps are the rarity, not the paper.

		Paper is paper at every tier, and a Legendary scroll that is entirely
		gold reads as a gold bar. Two bright bands on a pale roll is legible at
		distance and still obviously a scroll up close.
	]]
	for index, end_ in ipairs({ TUBE_LENGTH * 0.5, -TUBE_LENGTH * 0.5 }) do
		local cap = newPart(
			"Cap" .. index,
			Vector3.new(CAP_LENGTH, CAP_DIAMETER, CAP_DIAMETER),
			tint
		)
		cap.Shape = Enum.PartType.Cylinder
		cap.Material = Enum.Material.Neon
		cap.CFrame = CFrame.new(0, end_, 0) * upright
		cap.Parent = model
	end

	model.PrimaryPart = tube
	return model
end

--[[
	An authored model for this ability, or nil.

	Looked up by ability name so adding art is dropping a model into
	ReplicatedStorage.ScrollAssets and calling it "Eclipse" - no code, no table,
	no second name to keep in step with the first.
]]
local function authoredModel(abilityName: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild(ASSETS_FOLDER)
	local template = folder and folder:FindFirstChild(abilityName)

	if template and (template:IsA("Model") or template:IsA("BasePart")) then
		return template:Clone()
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- Adoption
-- ---------------------------------------------------------------------------

--[[
	The prompt on a scroll, built to look the same on every one of them.

	Reused rather than replaced when the instance already has one, so a model
	authored with its own prompt keeps whatever position and offset the artist
	gave it and only has its TEXT and its rules overwritten. Those are the parts
	that must not vary: a scroll whose prompt says something else, or which can
	be triggered from further away, is a different object.
]]
local function ensurePrompt(instance: Instance, anchor: BasePart, abilityName: string): ProximityPrompt
	local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = anchor
	end

	local definition = AbilityConfig.get(abilityName)
	local label = (definition and definition.displayName) or abilityName

	prompt.Name = PROMPT_NAME
	prompt.ObjectText = label .. " Scroll"
	prompt.ActionText = "Learn"
	prompt.HoldDuration = HOLD_SECONDS
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = REACH
	prompt.Enabled = true

	return prompt
end

--[[
	Makes an instance a live scroll. Idempotent.

	Returns the ability it teaches, or nil and a reason - which the tag handler
	turns into a warning and `place` treats as a bug on its own part.
]]
function ScrollService.adopt(instance: Instance): (string?, string?)
	if instances[instance] then
		return instances[instance].ability
	end

	local raw = instance:GetAttribute(ABILITY_ATTRIBUTE)
	if type(raw) ~= "string" or raw == "" then
		return nil, string.format(
			"%s has no `%s` attribute naming an ability", instance:GetFullName(), ABILITY_ATTRIBUTE
		)
	end

	local abilityName = AbilityConfig.resolve(raw)
	if not abilityName then
		return nil, string.format(
			"%s teaches '%s', which is not an ability", instance:GetFullName(), raw
		)
	end

	local anchor = anchorOf(instance)
	if not anchor then
		return nil, string.format("%s has no BasePart to stand on", instance:GetFullName())
	end

	-- Nothing about a scroll should be solid, and an authored model that is
	-- would let a player push it out of the room it was placed in.
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		elseif descendant:IsA("LuaSourceContainer") then
			-- An authored model must not smuggle scripts into the live world.
			descendant:Destroy()
		end
	end
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
	end

	local prompt = ensurePrompt(instance, anchor, abilityName)

	local record = {
		ability = abilityName,
		instance = instance,
		anchor = anchor,
		prompt = prompt,
		claimed = false,

		-- Where it belongs, so the bob has something to return to. See stepSpin.
		home = instance:GetPivot(),

		-- So a row of them does not bob in lockstep.
		phase = math.random() * math.pi * 2,

		-- Clamped once, here, rather than read off the prompt at grab time: an
		-- authored prompt with a huge activation distance gets the prompt it
		-- asked for and the reach check it deserves.
		reach = math.min(prompt.MaxActivationDistance, REACH_CEILING) + REACH_SLACK,
	}

	scrolls[prompt] = record
	instances[instance] = record
	scrollCount += 1
	updateSpin()

	CollectionService:AddTag(instance, SCROLL_TAG)

	log("adopted", instance:GetFullName(), "->", abilityName)
	return abilityName
end

--[[
	Forgets one, and takes it out of the world unless told to leave it.

	`destroy = false` is for a scroll that is being untagged rather than taken:
	somebody clearing the tag in Studio means "stop being a scroll", not "delete
	my model".
]]
local function release(record, destroy: boolean)
	if not scrolls[record.prompt] then
		return
	end

	scrolls[record.prompt] = nil
	instances[record.instance] = nil
	scrollCount -= 1
	updateSpin()

	if destroy then
		record.instance:Destroy()
	elseif record.prompt.Parent then
		record.prompt:Destroy()
	end
end

--[[
	Puts a scroll down at a CFrame. Returns the model, or nil and why.

	The public seam for everything that should be able to hand one out - the
	admin command today, a boss drop or a chest tomorrow. Nothing about the
	grant lives at the call site: it places an object, and the object is what
	teaches.
]]
function ScrollService.place(abilityName: string, cframe: CFrame): (Instance?, string?)
	local resolved = AbilityConfig.resolve(abilityName)
	if not resolved then
		return nil, string.format("There is no ability called '%s'.", tostring(abilityName))
	end

	local instance = authoredModel(resolved) or buildPlaceholder(resolved)
	instance:SetAttribute(ABILITY_ATTRIBUTE, resolved)
	instance:PivotTo(cframe)
	instance.Parent = worldFolder()

	local _, problem = ScrollService.adopt(instance)
	if problem then
		instance:Destroy()
		return nil, problem
	end

	return instance
end

function ScrollService.count(): number
	return scrollCount
end

-- ---------------------------------------------------------------------------
-- Taking one
-- ---------------------------------------------------------------------------

--[[
	Every reason a grant can be refused, in one place.

	Returns the record, or nil plus up to two things: something to TELL the
	player, and something to LOG.

	They are separate because most refusals are neither. Somebody else got there
	first, or you are dead - those are ordinary, and the player is the only one
	who needs to hear about them. A trigger from forty studs away is the
	opposite: there is nothing useful to say to whoever sent it, and the log is
	the only place it would ever be noticed.
]]
local function vet(prompt: ProximityPrompt, player: Player, now: number)
	local record = scrolls[prompt]
	if not record then
		-- Not ours. Crafting stations and dispensers put prompts in the world
		-- too, and this handler sees all of them.
		return nil
	end

	if record.claimed then
		return nil, "Somebody already took that."
	end

	if not (record.instance.Parent and record.anchor.Parent) then
		return nil, "That scroll is gone."
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not (root and humanoid and humanoid.Health > 0) then
		return nil
	end

	if now - (lastGrabAt[player] or -math.huge) < MIN_INTERVAL then
		return nil, nil, "triggered again inside the rate limit"
	end

	--[[
		The one check the client was doing for us.

		Measured from the ANCHOR rather than from the prompt, because a prompt
		can carry an offset and the thing the player walked up to is the model.
	]]
	local distance = ((root :: BasePart).Position - record.anchor.Position).Magnitude
	if distance > record.reach then
		return nil, nil, string.format(
			"triggered a %s scroll from %.1f studs away, against a reach of %.1f",
			record.ability, distance, record.reach
		)
	end

	return record
end

local function onTriggered(prompt: ProximityPrompt, player: Player)
	local now = os.clock()
	local record, message, suspicion = vet(prompt, player, now)

	if not record then
		if suspicion then
			-- Only reachable from a client that is not enforcing its own rules.
			-- Logged rather than acted on: this is the one place anybody would
			-- ever notice it.
			warn(string.format("[ScrollService] refused %s: %s", player.Name, suspicion))
		end
		if message then
			CommandFeedback.tell(player, message, "bad")
		end
		return
	end

	lastGrabAt[player] = now

	--[[
		CLAIMED BEFORE ANYTHING ELSE, and the prompt goes down with it.

		Everything after this line could in principle yield, and two triggers
		that both got past the check above would then both grant. Claiming here
		makes the second one fail the `record.claimed` test rather than race the
		first one to the loadout.
	]]
	record.claimed = true
	prompt.Enabled = false

	local added, reply = AbilityLoadout.add(player, record.ability)

	if not added then
		-- Three slots full, or they already carry it. The scroll is untouched
		-- and goes straight back, because nothing was spent.
		record.claimed = false
		prompt.Enabled = true

		CommandFeedback.tell(player, reply, "bad")
		log(player.Name, "could not take", record.ability, "-", reply)
		return
	end

	CommandFeedback.tell(player, reply, "good")
	log(player.Name, "took", record.ability)

	-- The menu opens itself; see the header.
	release(record, true)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--[[
	Connects the handlers and adopts whatever is already tagged.

	Safe to call twice - InitAbilities calls it once, and a second call from a
	reloaded script should not end up with two handlers granting two abilities
	for one prompt.
]]
function ScrollService.start()
	if started then
		return
	end
	started = true

	for _, instance in ipairs(CollectionService:GetTagged(SCROLL_TAG)) do
		local _, problem = ScrollService.adopt(instance)
		if problem then
			warn("[ScrollService]", problem)
		end
	end

	CollectionService:GetInstanceAddedSignal(SCROLL_TAG):Connect(function(instance)
		local _, problem = ScrollService.adopt(instance)
		if problem then
			warn("[ScrollService]", problem)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(SCROLL_TAG):Connect(function(instance)
		local record = instances[instance]
		if record then
			release(record, false)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local ok, err = pcall(onTriggered, prompt, player)
		if not ok then
			warn("[ScrollService] grab errored for", player.Name, err)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastGrabAt[player] = nil
	end)
end

return ScrollService
