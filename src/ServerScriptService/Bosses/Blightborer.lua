--[[
	The Blightborer - the Corruption's devourer

	A worm the better part of a hundred studs long that lives in the ground of
	the Corruption and comes up through it. After Terraria's Eater of Worlds:
	you fight it from the surface while it swims beneath you, and you know
	where it is coming from by what the ground does first.

	WHAT IT DOES

	  BREACH          the ground cracks and shakes under whoever it is after,
	                  and a second later it comes straight up through that
	                  spot, blasting a crater out of the ground, arcs over and
	                  dives back in somewhere else. Its basic move: every head
	                  does it on its own clock.
	  RENDING FURROW  it swims a body's width under the surface straight at
	                  you, and the ground over it is torn up as it comes - a
	                  trench racing toward you that ends in a breach past you.
	                  Step out of the line.
	  VILE ARC        a high breach; at the top of the arc the raised segments
	                  spit globs of ichor at everyone in reach. Each one eats
	                  the block it lands on, and some carry a brood that
	                  hatches a Blightling.
	  SINKHOLE        phase two: the ground in a bowl around you cracks, then
	                  falls away up to three blocks deep, and it comes up
	                  through the bottom of the pit. Get out of the ring.
	  BROOD RETCH     phase two: it rears out of the ground and retches up
	                  Blightlings at the top of the arc.
	  SPLITTING       its body is segments. A segment that takes enough damage
	                  bursts - Blightlings spill out - and the worm comes apart
	                  there into two worms, each with its own head and tail.
	                  It also splits on its own at three quarters, half and a
	                  quarter health, at the segment you have hurt most. Never
	                  more than four at once. They share one health pool and
	                  one bar: empty it and every piece dies together.

	HOW IT MOVES

	Underground it steers freely toward a point under whoever it is after.
	Above ground it is a thrown thing: gravity, and only a little steering -
	which is what makes the arcs. The body is follow-the-leader: each piece
	keeps its distance from the one in front and turns to face it, so the
	whole length traces the path the head took, out of the hole it made and
	back into the one it makes coming down.

	Breaches are SCRIPTED where it matters. The exit is chosen, and its
	crater planned, before the ground starts to shake; the head lines up
	beneath it out of sight and rises straight up through it, so it comes out
	exactly where the warning was. Nothing re-aims after the warning.

	THE BODY

	Three models in ReplicatedStorage.EnemyAssets: `head` (the definition's
	asset, which EnemyService clones), `body_segment` and `tail` (found
	ignoring case, spaces and underscores). Each can be a Model or a single
	part. Every piece is measured when it is made - its bounding box, around
	its own centre - so the pivot can sit anywhere in the mesh and the
	spacing still comes out right.

	WHICH WAY THEY FACE is read off the body segment's proportions (see
	detectCorrection): its longest side is the length, front at the positive
	end; its shortest is belly-to-back, back at the negative end. That is how
	the MagicaVoxel parts import. If a piece still faces wrong, put a Vector3
	attribute called WormRotation on it in EnemyAssets, in degrees (pitch,
	yaw, roll) with modelRotation's meaning, where zero is "built facing
	-Z" - it replaces the detection for that piece. The output window prints
	the axes it chose and every piece's size at spawn.

	All three are moved by PivotTo, every tick, as separate models inside the
	one enemy model EnemyService knows about - so a sword or an ability that
	lands on any segment finds the boss, and the boss works out which
	segment it was (nearestPoint / damaged below).

	TERRAIN

	Every block it takes goes through TerrainManager's PlanExcavation and
	ExecuteExcavation: natural, loaded, breakable, dry ground only, never a
	placed block, a structure or bedrock, under hard caps, with no loot.
	Clients are told what really went, and draw it as particles.

	EFFECTS

	Everything visible but the body itself is asked for over BossEffect and
	drawn by Shared.Abilities.VFX.BlightborerVFX from the supplied VFX packs:
	the warnings, the eruptions, the spit in flight, the bursts. The server
	adds nothing to the world but the body, one light in the head, and the
	sky.

	CLEANUP

	Every action runs inside its own AbilityScope, destroyed when it ends
	however it ends; anything that outlives an action (globs in the air)
	lives in `entry.encounterScope`, destroyed in finish. Every wait goes
	through `pause`, which stops the moment the fight is over or the worm is
	leaving.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AbilityScope = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityScope"))

local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local BossService = require(ServerScriptService:WaitForChild("BossService"))
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

-- Ensured by BossService at server start as well; see there.
local BossEffect = Remotes.ensure("BossEffect", "RemoteEvent")

local Blightborer = {}

local SELF = "Blightborer"
local SOURCE = "Blightborer"

local STUD = TerrainConfig.StudSize

-- How far from an effect a client has to be to be told about it.
local BROADCAST_RADIUS = 360

local SKY_EFFECT_NAME = "BlightborerSky"

-- The attribute a piece in EnemyAssets carries when it was not built facing -Z.
local ROTATION_ATTRIBUTE = "WormRotation"

-- The body and tail models, by any of these names. The head is the
-- definition's own `asset`.
local PIECE_ASSETS = {
	body = { "body_segment", "bodysegment", "segment", "body" },
	tail = { "tail" },
}

--[[
	What it sends, in order of preference: the first of these whose model is
	in EnemyAssets. The Blightling is its own creature; until its model
	exists the Corruption's Ghost stands in, and failing that a Demon Eye, so
	the fight works today and gets its proper minion the moment the model is
	added. Said once in the output when it falls back.
]]
local MINIONS = { "Blightling", "Ghost", "ServantEye" }

local Colors = {
	ichor = Color3.fromRGB(150, 220, 70),
}

--[[
	BALANCE

	A player has 100 health. Against an iron or gold sword - 18 to 24 a
	second in reach - 2400 is a fight of a bit under two minutes: more than
	Signus, because the worm is under the ground, out of reach, for a good
	part of it, and because once it splits a player is hitting whichever
	piece is passing rather than one target.

	ONE mistake is survivable from full and three in a row is a death; a
	breach and the body dragging through you afterwards are CombatService's
	invulnerability window apart, so standing on the exit costs one hit, not
	five. Numbers in pairs are { phase one, phase two }.
]]
local Tuning = {
	phase2At = 0.5,

	body = {
		segments = 16, -- body segments between the head and the tail
		-- Head and tail scaled to the segment's length, so all three are on
		-- one voxel scale again; see kindScales.
		matchLengths = true,
		scale = 1.5, -- then the whole worm, uniformly
		overlap = 0.94, -- share of each piece's length between joints; 1 is exactly flush
	},

	-- Underground: it steers freely toward a point under its target.
	swim = {
		speed = { 30, 38 },
		turn = { 140, 180 }, -- degrees a second
		accel = 70,
		depth = 20, -- studs under the surface it cruises at; clear of a body this thick
		lead = 0.4, -- seconds of target movement it aims ahead by
	},

	-- Above ground: a thrown thing. Gravity and a little steering.
	air = {
		gravity = 78,
		steer = 35, -- degrees a second of horizontal bend toward its target
		maxFall = 120,
		stuckAfter = 8, -- seconds in the air before it is put back underground
	},

	-- Touching it. Per player, for the whole boss: two segments at once is
	-- one hit, not two.
	contact = {
		head = 16,
		body = 9,
		tail = 6,
		interval = 0.8,
		margin = 2, -- studs past a piece's own radius that count as touching
	},

	breach = {
		every = { 6.5, 5 }, -- seconds between one head's breaches
		range = 80, -- horizontal studs from its target before it will
		warn = { 1.1, 0.85 },
		depth = 28, -- how far under the exit it lines up before rising
		rise = { 72, 80 }, -- launch speed
		drift = 14, -- horizontal speed it carries out of the hole
		blast = 10, -- radius of the eruption's hit
		damage = 16,
		crater = 2.5, -- blocks: radius of the hole it tears coming up, about the head's
		craterDepth = 2,
		craterCells = 48,
		maxConcurrent = { 1, 2 }, -- breach warnings on the ground at once
	},

	dive = {
		crater = 1.5,
		craterDepth = 1,
	},

	furrow = {
		length = 60, -- studs of trench before it reaches you
		overshoot = 16, -- and past you, where it comes up
		speed = { 42, 50 },
		warn = 0.8,
		width = 2, -- columns either side of the line that are torn up
		damage = 14,
		radius = 9,
		maxCells = 110,
	},

	spit = {
		rise = { 92, 100 }, -- a higher arc than a breach, to spit from
		count = { 4, 7 }, -- globs per arc
		flight = 1.0, -- seconds a glob is in the air when nothing is in the way
		gravity = 60,
		spread = 5, -- studs of scatter around where it aims
		damage = 9,
		splash = 4.5,
		cap = 18, -- the most one arc can deal to one player
		broodChance = { 0.25, 0.4 },
		gap = 0.12,
		reach = 140, -- only players this close are spat at
	},

	sinkhole = {
		radius = 12, -- studs
		depth = 3, -- blocks at the middle, shallower to the rim so you can climb out
		warn = 1.4,
		maxCells = 64,
		damage = 18,
		delay = 0.35, -- after the collapse, before it rises through the pit
	},

	brood = {
		count = { 2, 3 },
		gap = 0.25,
	},

	split = {
		thresholds = { 0.75, 0.5, 0.25 },
		segmentShare = 1, -- a segment's own health, as a share of health / segments
		maxWorms = 4,
		minBodies = 1, -- each half keeps at least this many body segments
		minions = { 1, 2 }, -- spilled by a segment that bursts
	},

	minions = { maxAlive = 6 },

	special = {
		first = 7,
		restMin = { 4.5, 3.2 },
		restMax = { 6.5, 5.0 },
	},

	giveUpRange = 220,
	giveUpSeconds = 25,
	leaveSeconds = 3,
}

local CYCLES = {
	{ "furrow", "spit", "furrow", "spit" },
	{ "sinkhole", "spit", "furrow", "brood", "sinkhole", "furrow", "spit" },
}

-- ---------------------------------------------------------------------------
-- Small things
-- ---------------------------------------------------------------------------

local function byPhase(value, phase: number)
	if type(value) == "table" then
		return value[phase] or value[#value]
	end
	return value
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- A flat direction, or a random one when there is none to be had.
local function flatUnit(v: Vector3): Vector3
	local f = flat(v)
	if f.Magnitude > 1e-3 then
		return f.Unit
	end
	local angle = math.random() * math.pi * 2
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

-- Turns a direction toward another by at most `maxRadians`, around any axis.
-- Directly backwards turns about the vertical, so it never sticks.
local function turnToward(from: Vector3, to: Vector3, maxRadians: number): Vector3
	if to.Magnitude < 1e-3 then
		return from
	end
	to = to.Unit
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxRadians then
		return to
	end
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-4 then
		axis = if math.abs(from.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	end
	return (CFrame.fromAxisAngle(axis.Unit, maxRadians) * from).Unit
end

-- The same, kept flat, for steering in the air.
local function turnFlat(from: Vector3, to: Vector3, maxRadians: number): Vector3
	from = flatUnit(from)
	to = flatUnit(to)
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxRadians then
		return to
	end
	local sign = if from:Cross(to).Y >= 0 then 1 else -1
	return (CFrame.Angles(0, sign * maxRadians, 0) * from).Unit
end

-- Runs a callback handed in by an action, from inside the tick, without
-- letting a mistake in it stop the rest of the tick.
local function call(callback)
	if callback then
		local ok, err = pcall(callback)
		if not ok then
			warn("[Blightborer] callback errored:", err)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------

local function livingPlayers(): { Player }
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end
	return list
end

local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- The same, only while they are alive: a body is not a target.
local function livingRoot(player: Player?): BasePart?
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character:FindFirstChild("HumanoidRootPart")
	end
	return nil
end

local function flatVelocity(root: BasePart): Vector3
	return flat(root.AssemblyLinearVelocity)
end

local function nearestPlayer(position: Vector3, within: number?): (Player?, number)
	local best, bestDistance = nil, within or math.huge
	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best, bestDistance
end

local function playersWithin(position: Vector3, radius: number): { Player }
	local found = {}
	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root and (root.Position - position).Magnitude <= radius then
			table.insert(found, player)
		end
	end
	return found
end

-- In a flat circle, and not too far above or below it.
local function playersInCircle(centre: Vector3, radius: number): { Player }
	local found = {}
	local squared = radius * radius
	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root then
			local offset = root.Position - centre
			local f = flat(offset)
			if f:Dot(f) <= squared and math.abs(offset.Y) <= radius + 6 then
				table.insert(found, player)
			end
		end
	end
	return found
end

-- Damage with a memory: each `key` hits a player once, and one action never
-- deals more than `cap` to anyone.
local function hitOnce(ledger, key, player: Player, amount: number, cap: number): number
	local hits = ledger[player]
	if not hits then
		hits = { total = 0 }
		ledger[player] = hits
	end
	if hits[key] then
		return 0
	end
	hits[key] = true
	local allowed = math.min(amount, cap - hits.total)
	if allowed <= 0 then
		return 0
	end
	hits.total += allowed
	return CombatService.applyDamage(player, allowed, SOURCE)
end

local function announce(text: string, tone: string?)
	for _, player in ipairs(Players:GetPlayers()) do
		CommandFeedback.tell(player, text, tone)
	end
end

-- Asks every client near enough to draw an effect. See BlightborerVFX for the
-- kinds.
local function fx(kind: string, position: Vector3, extra: { [string]: any }?)
	local payload = {
		boss = SELF,
		kind = kind,
		position = position,
		startedAt = workspace:GetServerTimeNow(),
	}
	if extra then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and (root.Position - position).Magnitude <= BROADCAST_RADIUS then
			BossEffect:FireClient(player, payload)
		end
	end
end

-- ---------------------------------------------------------------------------
-- The ground
-- ---------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

-- The first block between two points. Placed blocks are terrain too.
local function terrainRay(from: Vector3, to: Vector3): RaycastResult?
	local folder = workspace:FindFirstChild("GeneratedTerrain")
	if not folder then
		return nil
	end
	rayParams.FilterDescendantsInstances = { folder }
	return workspace:Raycast(from, to - from, rayParams)
end

-- The top of the ground in a column, or `fallback` outside the world.
local function surfaceY(x: number, z: number, fallback: number): number
	local ok, y = pcall(TerrainManager.GetSurfaceY, TerrainManager, x, z)
	if ok and type(y) == "number" then
		return y
	end
	return fallback
end

-- What something standing here would stand on: placed blocks included.
local function groundUnder(position: Vector3): Vector3
	return Vector3.new(position.X, EnemyService.groundAt(position.X, position.Z, position.Y), position.Z)
end

--[[
	The columns of a bowl around a point, nearest first, for PlanExcavation:
	`depth` blocks at the middle tapering to one at the rim, so anything
	that falls in can climb back out a block at a time.
]]
local function bowlColumns(centre: Vector3, radiusBlocks: number, depth: number)
	local columns = {}
	local bx, bz = math.floor(centre.X / STUD), math.floor(centre.Z / STUD)
	local reach = math.ceil(radiusBlocks)
	for dx = -reach, reach do
		for dz = -reach, reach do
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance <= radiusBlocks + 0.01 then
				local share = 1 - distance / (radiusBlocks + 1)
				table.insert(columns, {
					x = (bx + dx + 0.5) * STUD,
					z = (bz + dz + 0.5) * STUD,
					y = centre.Y,
					depth = math.clamp(math.ceil(depth * share), 1, depth),
					distance = distance,
				})
			end
		end
	end
	table.sort(columns, function(a, b)
		return a.distance < b.distance
	end)
	return columns
end

local function planBowl(centre: Vector3, radiusBlocks: number, depth: number, maxCells: number)
	return TerrainManager:PlanExcavation(bowlColumns(centre, radiusBlocks, depth), { maxCells = maxCells })
end

local function dig(plan, maxSamples: number): (number, { any })
	if type(plan) ~= "table" or #plan == 0 then
		return 0, {}
	end
	local removed, samples = TerrainManager:ExecuteExcavation(plan, { maxSamples = maxSamples })
	return removed, samples or {}
end

-- ---------------------------------------------------------------------------
-- The sky
-- ---------------------------------------------------------------------------

--[[
	While it lives the world sickens toward a bruised green-violet, more so
	in its frenzy. A ColorCorrectionEffect of its own in Lighting, left in
	place neutral when the fight ends so a second one cannot have its sky
	deleted from under it.
]]
local SKY = {
	[1] = { TintColor = Color3.fromRGB(228, 222, 236), Saturation = -0.1, Contrast = 0.04, Brightness = -0.02 },
	[2] = { TintColor = Color3.fromRGB(204, 190, 222), Saturation = -0.22, Contrast = 0.1, Brightness = -0.05 },
	clear = { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 },
}

local function setSky(level, seconds: number)
	local effect = Lighting:FindFirstChild(SKY_EFFECT_NAME)
	if not (effect and effect:IsA("ColorCorrectionEffect")) then
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = SKY_EFFECT_NAME
		effect.TintColor = Color3.new(1, 1, 1)
		effect.Parent = Lighting
	end
	TweenService:Create(effect, TweenInfo.new(seconds, Enum.EasingStyle.Sine), SKY[level]):Play()
end

-- ---------------------------------------------------------------------------
-- The pieces
-- ---------------------------------------------------------------------------

-- A name with case, spaces and underscores taken out, for matching assets.
local function squash(name: string): string
	return string.lower((string.gsub(name, "[%s_]", "")))
end

local function findPieceAsset(folder: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local wanted = squash(name)
		for _, child in ipairs(folder:GetChildren()) do
			if squash(child.Name) == wanted and (child:IsA("Model") or child:IsA("BasePart")) then
				return child
			end
		end
	end
	return nil
end

--[[
	Which way a piece's model is built, worked out from the model itself.

	The parts are MagicaVoxel exports (assets/voxel-boss): authored with the
	worm's length along voxel Z, mouth toward +Z, belly toward -Y. MagicaVoxel
	is Z-up and Roblox is Y-up, so an import stands every piece on end -
	length along +Y, mouth at the top, belly toward +Z - which is why they all
	came out at right angles to the body when this assumed -Z.

	So rather than assume, it reads the proportions: the LONGEST side of the
	box is the length and its positive end is the front, and the SHORTEST
	side is belly-to-back with the back on its negative end. That is right
	for the import above, and stays right if the models are later turned in
	Studio as long as they are turned together. The body segment is the one
	measured - its three sides all differ - and the answer is used for all
	three: the head is exactly as wide as it is long, so on its own it cannot
	say which of the two is which.

	Returns the correction as a CFrame: it maps the piece's own front to -Z
	and its back to +Y, the frame the movement thinks in.
]]
local function detectCorrection(model: Model): CFrame
	local _, size = model:GetBoundingBox()
	local axes = {
		{ vector = Vector3.xAxis, length = size.X },
		{ vector = Vector3.yAxis, length = size.Y },
		{ vector = Vector3.zAxis, length = size.Z },
	}
	table.sort(axes, function(a, b)
		return a.length > b.length
	end)
	local front = axes[1].vector
	local back = -axes[3].vector
	-- Built as its inverse, column by column: X goes to front x back, Y to
	-- the back, Z to behind.
	return CFrame.fromMatrix(Vector3.zero, front:Cross(back), back, -front):Inverse()
end

local AXIS_NAMES = { [1] = "X", [2] = "Y", [3] = "Z" }

-- The model-space axis a correction treats as `direction`, for the output.
local function axisName(correction: CFrame, direction: Vector3): string
	local inPiece = correction:VectorToObjectSpace(direction)
	local values = { inPiece.X, inPiece.Y, inPiece.Z }
	local best = 1
	for index = 2, 3 do
		if math.abs(values[index]) > math.abs(values[best]) then
			best = index
		end
	end
	return (if values[best] < 0 then "-" else "+") .. AXIS_NAMES[best]
end

--[[
	The correction for one piece: its template's WormRotation attribute when
	it has one (degrees, pitch/yaw/roll, modelRotation's meaning), and the
	detected one otherwise.
]]
local function correctionFor(entry, kind: string): CFrame
	local template = entry.templates[kind]
	local value = template and template:GetAttribute(ROTATION_ATTRIBUTE)
	if typeof(value) == "Vector3" then
		return CFrame.Angles(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
	end
	return entry.autoCorrection or CFrame.identity
end

--[[
	A Model, whatever the asset was. A single part is wrapped; a model with no
	PrimaryPart gets the same one EnemyService would give it (the first part
	it finds), so a head cloned here measures exactly like the head
	EnemyService cloned.
]]
local function asModel(instance: Instance, name: string): Model?
	if instance:IsA("Model") then
		instance.Name = name
		if not instance.PrimaryPart then
			for _, descendant in ipairs(instance:GetDescendants()) do
				if descendant:IsA("BasePart") then
					instance.PrimaryPart = descendant
					break
				end
			end
		end
		return if instance.PrimaryPart then instance else nil
	elseif instance:IsA("BasePart") then
		local model = Instance.new("Model")
		model.Name = name
		instance.Parent = model
		model.PrimaryPart = instance
		return model
	end
	return nil
end

-- Server-moved, like every enemy: anchored, and nothing for physics or
-- Touched to do. CanQuery stays on, so an ability's raycast that lands on a
-- segment finds the boss through it.
local function preparePiece(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
end

--[[
	Measures a piece where it stands.

	The frame movement thinks in is the piece's bounding-box centre facing
	its front, with the correction applied; `frameToPivot` turns that into
	where its pivot has to go. Both the box and the pivot are read in the
	same moment, so where the model happens to be does not matter.

	`half` is its half-length along its front, `radius` its half-width
	across, both in studs.
]]
local function measure(model: Model, correction: CFrame)
	local boxFrame, size = model:GetBoundingBox()

	local function extent(direction: Vector3): number
		return 0.5 * (math.abs(direction.X) * size.X + math.abs(direction.Y) * size.Y + math.abs(direction.Z) * size.Z)
	end

	local forward = correction:VectorToObjectSpace(Vector3.new(0, 0, -1))
	local up = correction:VectorToObjectSpace(Vector3.yAxis)
	local right = correction:VectorToObjectSpace(Vector3.xAxis)

	return {
		half = math.max(0.5, extent(forward)),
		radius = math.max(0.5, extent(up), extent(right)),
		frameToPivot = correction * (boxFrame:Inverse() * model:GetPivot()),
	}
end

local function newPiece(kind: string, model: Model, correction: CFrame)
	local info = measure(model, correction)
	return {
		kind = kind,
		model = model,
		half = info.half,
		radius = info.radius,
		frameToPivot = info.frameToPivot,
		pos = model:GetPivot().Position,
		look = Vector3.new(0, 0, -1),
		up = Vector3.yAxis,
		damage = 0,
	}
end

-- A fresh head, segment or tail from its template, in the boss's model.
local function cloneKind(entry, kind: string): Model?
	local template = entry.templates[kind]
	-- Clone gives nothing for a template with Archivable switched off.
	local copy = template and template:Clone()
	if not copy then
		return nil
	end
	local model = asModel(copy, if kind == "body" then "Segment" else (kind == "head" and "Head" or "Tail"))
	if not model then
		return nil
	end
	preparePiece(model)
	model.Parent = entry.model
	return model
end

local function scaleModel(model: Model?, factor: number?)
	if model and factor and math.abs(factor - 1) > 1e-3 then
		model:ScaleTo(model:GetScale() * factor)
	end
end

--[[
	How much each kind of piece is scaled by.

	All three parts are authored the same length - 56 voxels each, made to
	mate flush (assets/voxel-boss) - but they came into Roblox at three
	different sizes: the head a little small, the tail a little big. With
	matchLengths each is first scaled to the body segment's length, which
	puts all three back on one voxel scale so the joints line up, and then
	the whole worm by `scale`. Measured on the unscaled models, along each
	one's own front.
]]
local function kindScales(entry, models: { [string]: Model? }): { [string]: number }
	local B = Tuning.body
	local scales = { head = B.scale, body = B.scale, tail = B.scale }
	if not B.matchLengths then
		return scales
	end

	local function lengthOf(kind: string): number?
		local model = models[kind]
		return if model then measure(model, correctionFor(entry, kind)).half * 2 else nil
	end

	local reference = lengthOf("body")
	if not reference then
		return scales
	end
	for kind in pairs(scales) do
		local length = lengthOf(kind)
		if length and length > 0 then
			scales[kind] = B.scale * reference / length
		end
	end
	return scales
end

--[[
	The head EnemyService already made, moved into a Model of its own.

	EnemyService cloned the head asset AS the enemy model, so PivotTo on that
	model would drag every segment inside it along with the head. Everything
	the asset brought goes into a child "Head" model instead, leaving the
	enemy model a plain container that the pieces hang in side by side. Its
	PrimaryPart is still the head's root part, which is what EnemyService
	checks is in the world every tick.
]]
local function adoptHead(entry): Model
	local container = entry.model
	local head = Instance.new("Model")
	head.Name = "Head"

	for _, child in ipairs(container:GetChildren()) do
		if not (child:IsA("BillboardGui") or child:IsA("Highlight")) then
			child.Parent = head
		end
	end

	head.PrimaryPart = entry.root
	head.Parent = container

	-- The name plate rides on the head rather than on a container with no
	-- position of its own.
	local plate = container:FindFirstChild("NamePlate")
	if plate and plate:IsA("BillboardGui") then
		plate.Adornee = entry.root
	end

	return head
end

--[[
	A piece's world frame from where it is and which way it faces.

	The up vector is carried from the piece's last frame rather than taken
	from the world, so a worm going straight up does not spin about its own
	length the moment its look passes vertical; it is eased back toward the
	world's up a little each tick so it never ends up crawling on its back.
]]
local function framePiece(piece): CFrame
	local look = piece.look
	local up = piece.up:Lerp(Vector3.yAxis, 0.08)
	up -= look * look:Dot(up)
	if up.Magnitude < 1e-3 then
		up = look:Cross(Vector3.xAxis)
		if up.Magnitude < 1e-3 then
			up = look:Cross(Vector3.zAxis)
		end
	end
	up = up.Unit
	piece.up = up
	return CFrame.fromMatrix(piece.pos, look:Cross(up), up)
end

local function placePiece(piece)
	if piece.model.Parent then
		piece.model:PivotTo(framePiece(piece) * piece.frameToPivot)
	end
end

-- Swaps a body segment's model for a head or a tail, in place.
local function convert(entry, piece, kind: string)
	local model = cloneKind(entry, kind)
	if not model then
		return
	end
	scaleModel(model, entry.kindScale and entry.kindScale[kind])
	local fresh = newPiece(kind, model, correctionFor(entry, kind))
	piece.model:Destroy()
	piece.model = model
	piece.kind = kind
	piece.half = fresh.half
	piece.radius = fresh.radius
	piece.frameToPivot = fresh.frameToPivot
	piece.damage = 0
	-- Now, not next tick: the clone arrived wherever its template stands.
	placePiece(piece)
end

local function gapBetween(ahead, behind): number
	return (ahead.half + behind.half) * Tuning.body.overlap
end

--[[
	Follow the leader, joint to joint.

	The parts are built to mate flush, socket to socket (assets/voxel-boss),
	so each piece hangs from the back end of the one in front of it: its
	front end sits on that joint and it points from where its own back end
	was toward it. A chain of joints rather than of centres keeps the
	sockets together round a bend instead of letting them drift apart.
	Lengths are scaled by `overlap` so a bend closes over rather than opening
	a gap on its outside.
]]
local function stepChain(worm)
	local pieces = worm.pieces
	local head = pieces[1]
	head.pos = worm.pos
	if worm.vel.Magnitude > 0.05 then
		head.look = worm.vel.Unit
	end

	local overlap = Tuning.body.overlap
	local joint = head.pos - head.look * (head.half * overlap)

	for index = 2, #pieces do
		local piece = pieces[index]
		local length = piece.half * 2 * overlap
		local back = piece.pos - piece.look * piece.half
		local offset = back - joint
		local direction = if offset.Magnitude > 1e-3 then offset.Unit else -pieces[index - 1].look
		piece.pos = joint + direction * (length * 0.5)
		piece.look = -direction
		joint += direction * length
	end
end

local function mouthOf(worm): Vector3
	local head = worm.pieces[1]
	return head.pos + head.look * head.half
end

-- The point on any piece of the boss nearest a position, with the piece,
-- its worm and its index.
local function nearestPiece(entry, position: Vector3)
	local best, bestWorm, bestIndex, bestPoint, bestDistance = nil, nil, nil, nil, math.huge
	for _, worm in ipairs(entry.worms or {}) do
		for index, piece in ipairs(worm.pieces) do
			local offset = position - piece.pos
			local distance = offset.Magnitude
			local surface = distance - piece.radius
			if surface < bestDistance then
				bestDistance = surface
				best, bestWorm, bestIndex = piece, worm, index
				bestPoint = if distance > piece.radius and distance > 1e-3
					then piece.pos + offset / distance * piece.radius
					else position
			end
		end
	end
	return best, bestWorm, bestIndex, bestPoint
end

-- ---------------------------------------------------------------------------
-- Worms
-- ---------------------------------------------------------------------------

local function phaseOf(entry): number
	return if entry.health / entry.def.health <= Tuning.phase2At then 2 else 1
end

local function newWorm(entry, pieces, position: Vector3, velocity: Vector3, mode: string)
	entry.wormCount = (entry.wormCount or 0) + 1
	local worm = {
		id = entry.wormCount,
		pieces = pieces,
		pos = position,
		vel = velocity,
		mode = mode,
		alive = true,
		target = nil,
		action = nil,
		apexed = true,
		breaching = false,
		airSince = os.clock(),
		lastGround = position.Y,
		retargetAt = 0,
		nextBreachAt = os.clock() + 2 + math.random() * 2,
	}
	table.insert(entry.worms, worm)
	return worm
end

-- The bar's line under the name: how many of it there are, and the frenzy.
local function updatePhaseText(entry)
	local parts = {}
	if entry.frenzied then
		table.insert(parts, "Frenzy")
	end
	if #entry.worms > 1 then
		table.insert(parts, string.format("%d worms", #entry.worms))
	end
	entry.bossPhase = if #parts > 0 then table.concat(parts, " - ") else nil
	BossService.update(entry)
end

--[[
	Who a head goes after: the nearest living player in reach, nudged away
	from players another head is already after, so two worms spread out over
	two players instead of queueing for one.
]]
local function chooseTarget(entry, worm): Player?
	local taken = {}
	for _, other in ipairs(entry.worms) do
		if other ~= worm and other.target then
			taken[other.target] = (taken[other.target] or 0) + 1
		end
	end
	local best, bestScore = nil, math.huge
	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root then
			local distance = (root.Position - worm.pos).Magnitude
			if distance <= Tuning.giveUpRange then
				local score = distance + (taken[player] or 0) * 40
				if score < bestScore then
					best, bestScore = player, score
				end
			end
		end
	end
	return best
end

-- Steers the head toward a point and moves it, underground or leaving.
local function steer(worm, aim: Vector3, dt: number, speed: number, turnDegrees: number)
	local offset = aim - worm.pos
	local current = worm.vel
	local look = if current.Magnitude > 1e-3 then current.Unit else worm.pieces[1].look
	if offset.Magnitude > 1e-3 then
		look = turnToward(look, offset.Unit, math.rad(turnDegrees) * dt)
	end
	local magnitude = current.Magnitude
	local accel = Tuning.swim.accel * dt
	magnitude = if magnitude < speed then math.min(speed, magnitude + accel) else math.max(speed, magnitude - accel * 1.5)
	worm.vel = look * magnitude
	worm.pos += worm.vel * dt
end

-- Back into the ground after an arc. A real breach tears a small hole where
-- it goes in; falling back in after surfacing by accident only throws dust.
local function land(entry, worm, ground: number, now: number)
	local entryPoint = Vector3.new(worm.pos.X, ground, worm.pos.Z)
	if worm.breaching then
		local D = Tuning.dive
		local _, samples = dig(planBowl(entryPoint, D.crater, D.craterDepth, 16), 10)
		fx("dive", entryPoint, { blocks = samples, radius = worm.pieces[1].radius })
	else
		fx("dive", entryPoint, { blocks = {}, radius = worm.pieces[1].radius, small = true })
	end
	worm.breaching = false
	worm.mode = "swim"
	worm.onApex = nil
	local callback = worm.onLand
	worm.onLand = nil
	call(callback)
end

local function stepWorm(entry, worm, dt: number, now: number, phase: number)
	local S, A = Tuning.swim, Tuning.air
	local ground = surfaceY(worm.pos.X, worm.pos.Z, worm.lastGround)
	worm.lastGround = ground

	local mode = worm.mode

	if mode == "swim" then
		local root = livingRoot(worm.target)
		local aim
		if root then
			local ahead = root.Position + flatVelocity(root) * S.lead
			local floor = math.min(surfaceY(ahead.X, ahead.Z, ahead.Y), ground)
			aim = Vector3.new(ahead.X, floor - S.depth, ahead.Z)
		else
			-- Nobody to go after: cruise on at depth.
			aim = worm.pos + flatUnit(worm.pieces[1].look) * 20
			aim = Vector3.new(aim.X, ground - S.depth, aim.Z)
		end
		steer(worm, aim, dt, byPhase(S.speed, phase), byPhase(S.turn, phase))

		-- Out of the ground by accident - a valley, a dug hole, a cave mouth -
		-- and it is a thrown thing until it falls back in.
		if worm.pos.Y > surfaceY(worm.pos.X, worm.pos.Z, ground) + 0.5 then
			worm.mode = "air"
			worm.apexed = worm.vel.Y <= 0
			worm.airSince = now
		end
	elseif mode == "approach" then
		local offset = worm.approachTo - worm.pos
		local distance = offset.Magnitude
		if distance > 0.05 then
			local timeLeft = math.max((worm.approachUntil or now) - now, 0.05)
			local speed = math.clamp(distance / timeLeft, byPhase(S.speed, phase), 180)
			worm.vel = offset.Unit * speed
			worm.pos += offset.Unit * math.min(distance, speed * dt)
		else
			-- In place: holding still, nosed up, ready.
			worm.vel = Vector3.new(0, 0.1, 0)
		end
	elseif mode == "rise" then
		local offset = worm.riseTo - worm.pos
		local distance = offset.Magnitude
		local step = worm.riseSpeed * dt
		if distance <= step then
			worm.pos = worm.riseTo
			worm.mode = "air"
			worm.vel = worm.launchVelocity or Vector3.new(0, worm.riseSpeed, 0)
			worm.apexed = false
			worm.airSince = now
			local callback = worm.onSurface
			worm.onSurface = nil
			call(callback)
		else
			worm.vel = offset.Unit * worm.riseSpeed
			worm.pos += worm.vel * dt
		end
	elseif mode == "air" then
		local v = worm.vel
		local horizontal = flat(v)
		local root = livingRoot(worm.target)
		if root and horizontal.Magnitude > 0.5 then
			local toward = flat(root.Position - worm.pos)
			if toward.Magnitude > 1 then
				horizontal = turnFlat(horizontal, toward, math.rad(A.steer) * dt) * horizontal.Magnitude
			end
		end
		local vy = math.max(v.Y - A.gravity * dt, -A.maxFall)
		worm.vel = Vector3.new(horizontal.X, vy, horizontal.Z)
		worm.pos += worm.vel * dt

		if not worm.apexed and vy <= 0 then
			worm.apexed = true
			local callback = worm.onApex
			worm.onApex = nil
			call(callback)
		end

		local here = surfaceY(worm.pos.X, worm.pos.Z, ground)
		if vy < 0 and worm.pos.Y < here - 0.5 then
			land(entry, worm, here, now)
		elseif now - worm.airSince > A.stuckAfter then
			-- Over a hole with no bottom, or something stranger: put it back.
			worm.pos = Vector3.new(worm.pos.X, here - S.depth, worm.pos.Z)
			worm.breaching = false
			worm.mode = "swim"
		end
	elseif mode == "furrow" then
		local path = worm.path
		path.travelled = math.min(path.length, path.travelled + path.speed * dt)
		local point = path.from + path.direction * path.travelled
		-- The ground is blocks, so its height jumps; the head eases over the
		-- steps rather than teleporting up them. Read a block AHEAD: the
		-- column under the head is the one it has just torn the top off.
		local probe = point + path.direction * STUD
		local wanted = surfaceY(probe.X, probe.Z, worm.pos.Y + path.depth) - path.depth
		local dy = math.clamp(wanted - worm.pos.Y, -40 * dt, 40 * dt)
		worm.vel = path.direction * path.speed + Vector3.new(0, dy / math.max(dt, 1e-3), 0)
		worm.pos = Vector3.new(point.X, worm.pos.Y + dy, point.Z)
		call(path.onMove)
		if path.travelled >= path.length and worm.mode == "furrow" then
			local callback = path.onEnd
			worm.path = nil
			worm.mode = "swim"
			call(callback)
		end
	elseif mode == "leave" then
		local aim = worm.pos + flatUnit(worm.pieces[1].look) * 10 + Vector3.new(0, -60, 0)
		steer(worm, aim, dt, byPhase(S.speed, phase), 220)
	end
end

-- ---------------------------------------------------------------------------
-- Touching it
-- ---------------------------------------------------------------------------

local function contactDamage(entry, now: number)
	local C = Tuning.contact
	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		local last = entry.contactAt[player]
		if root and not (last and now - last < C.interval) then
			local position = root.Position
			local touched = nil
			for _, worm in ipairs(entry.worms) do
				for _, piece in ipairs(worm.pieces) do
					local reach = piece.radius + C.margin
					local offset = position - piece.pos
					if offset:Dot(offset) <= reach * reach then
						touched = piece
						break
					end
				end
				if touched then
					break
				end
			end
			if touched then
				entry.contactAt[player] = now
				CombatService.applyDamage(player, C[touched.kind] or C.body, SOURCE)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Minions
-- ---------------------------------------------------------------------------

local warnedMinion = false

-- The minion it can actually send: see MINIONS.
local function minionKind(): string?
	local folder = ReplicatedStorage:FindFirstChild(EnemyConfig.AssetsFolder)
	if not folder then
		return nil
	end
	for index, name in ipairs(MINIONS) do
		local def = EnemyConfig.Definitions[name]
		if def and EnemyConfig.findAsset(folder, def.asset) then
			if index > 1 and not warnedMinion then
				warnedMinion = true
				warn(string.format(
					"[Blightborer] no EnemyAssets.%s model yet; sending %s instead.",
					tostring(EnemyConfig.Definitions[MINIONS[1]] and EnemyConfig.Definitions[MINIONS[1]].asset),
					name
				))
			end
			return name
		end
	end
	if not warnedMinion then
		warnedMinion = true
		warn("[Blightborer] none of " .. table.concat(MINIONS, ", ") .. " has a model in EnemyAssets; it will send nothing.")
	end
	return nil
end

local function minionsAlive(entry): number
	local alive = 0
	for index = #entry.minions, 1, -1 do
		if EnemyService.isAlive(entry.minions[index]) then
			alive += 1
		else
			table.remove(entry.minions, index)
		end
	end
	return alive
end

--[[
	Puts a minion in the world, a moment from now.

	Deferred, always: this is reached from `damaged`, which can run inside
	EnemyService.forEachNear's walk of its own table of enemies (an ability
	hurting everything in a radius), and spawning adds to that table.
]]
local function spawnMinion(entry, position: Vector3)
	task.defer(function()
		if entry.wormFinished or entry.leaving then
			return
		end
		if minionsAlive(entry) >= Tuning.minions.maxAlive then
			return
		end
		local name = minionKind()
		if not name then
			return
		end
		local model = EnemyService.spawn(name, position)
		if model then
			table.insert(entry.minions, model)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Splitting
-- ---------------------------------------------------------------------------

-- Whether breaking the piece at `index` leaves two worms with a head, a tail
-- and at least minBodies segments each.
local function canSplitAt(worm, index: number): boolean
	local pieces = worm.pieces
	local piece = pieces[index]
	local keep = Tuning.split.minBodies
	return piece ~= nil and piece.kind == "body" and index >= keep + 3 and index <= #pieces - keep - 2
end

--[[
	Breaks a worm at a segment: the segment bursts, the front keeps its head
	and grows a tail where it broke, and the back grows a head and goes its
	own way as a worm of its own, carrying on in the direction it was moving.
]]
local function split(entry, worm, index: number): boolean
	if entry.wormFinished or #entry.worms >= Tuning.split.maxWorms or not canSplitAt(worm, index) then
		return false
	end

	local pieces = worm.pieces
	local broken = pieces[index]
	local front = table.move(pieces, 1, index - 1, 1, {})
	local back = table.move(pieces, index + 1, #pieces, 1, {})

	fx("burst", broken.pos, { radius = broken.radius })
	broken.model:Destroy()
	local spill = Tuning.split.minions
	for _ = 1, math.random(spill[1], spill[2]) do
		spawnMinion(entry, broken.pos + flatUnit(Vector3.zero) * 2)
	end

	convert(entry, front[#front], "tail")
	worm.pieces = front

	local newHead = back[1]
	convert(entry, newHead, "head")
	local heading = if back[2] then newHead.pos - back[2].pos else newHead.look
	heading = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.new(0, -1, 0)
	newHead.look = heading

	local phase = phaseOf(entry)
	local ground = surfaceY(newHead.pos.X, newHead.pos.Z, newHead.pos.Y - 1)
	local airborne = newHead.pos.Y > ground + 0.5
	local other = newWorm(entry, back, newHead.pos, heading * byPhase(Tuning.swim.speed, phase), if airborne then "air" else "swim")
	other.target = worm.target
	other.nextBreachAt = os.clock() + 2.5

	if not entry.announcedSplit then
		entry.announcedSplit = true
		announce("The Blightborer tears itself apart!", "bad")
	end
	updatePhaseText(entry)
	return true
end

-- The guaranteed split: on the segment that has taken the most, anywhere.
local function splitMostHurt(entry)
	local bestWorm, bestIndex, bestScore = nil, nil, -math.huge
	for _, worm in ipairs(entry.worms) do
		for index, piece in ipairs(worm.pieces) do
			if canSplitAt(worm, index) then
				-- Damage first; with none anywhere, the middle of the longest worm.
				local middle = (#worm.pieces + 1) / 2
				local score = piece.damage * 10 + #worm.pieces - math.abs(index - middle) * 0.01
				if score > bestScore then
					bestWorm, bestIndex, bestScore = worm, index, score
				end
			end
		end
	end
	if bestWorm then
		split(entry, bestWorm, bestIndex)
	end
end

-- ---------------------------------------------------------------------------
-- Attack plumbing
-- ---------------------------------------------------------------------------

-- Waits, unless the fight is over or it is leaving. False if it stopped.
local function pause(entry, seconds: number): boolean
	local deadline = os.clock() + seconds
	repeat
		if entry.wormFinished or entry.leaving then
			return false
		end
		task.wait()
	until os.clock() >= deadline
	return not (entry.wormFinished or entry.leaving)
end

local function waitFor(entry, predicate: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not predicate() do
		if entry.wormFinished or entry.leaving or os.clock() >= deadline then
			return false
		end
		task.wait()
	end
	return not (entry.wormFinished or entry.leaving)
end

local function inTheArc(worm): boolean
	return worm.mode == "rise" or worm.mode == "air" or worm.mode == "furrow" or worm.mode == "approach"
end

--[[
	Runs one action for one worm in its own thread and its own scope, and
	hands the worm back to the hunt when it ends - however it ends. An action
	that errors halfway leaves its worm swimming, never stuck in a scripted
	mode with nothing driving it.
]]
local function runAction(entry, worm, name: string, action, phase: number, special: boolean)
	worm.action = name
	if special then
		entry.busy = true
	end
	local scope = AbilityScope.new()
	entry.actionScopes[scope] = true

	task.spawn(function()
		local ok, err = pcall(action, entry, worm, phase, scope)
		if not ok then
			warn(string.format("[Blightborer] %s errored: %s", name, tostring(err)))
		end
		entry.actionScopes[scope] = nil
		scope:destroy()

		if entry.wormFinished then
			return
		end
		if worm.action == name then
			worm.action = nil
		end
		if not entry.leaving and worm.mode ~= "air" then
			worm.mode = "swim"
			worm.path = nil
			worm.onSurface = nil
		end
		local every = byPhase(Tuning.breach.every, phaseOf(entry))
		worm.nextBreachAt = math.max(worm.nextBreachAt, os.clock() + every * (0.6 + math.random() * 0.5))
		if special then
			entry.busy = false
			local P = phaseOf(entry)
			local rest = byPhase(Tuning.special.restMin, P)
				+ math.random() * (byPhase(Tuning.special.restMax, P) - byPhase(Tuning.special.restMin, P))
			entry.nextSpecialAt = os.clock() + rest
		end
	end)
end

--[[
	Out of the ground at `exit`: the head rises straight up through it, the
	crater planned for it is blown out and anyone standing on it is hit, and
	then it is airborne with its rise speed and a little drift after its
	target.

	`options`: rise, drift, blast, damage, onSurface, onApex.
]]
local function launch(entry, worm, phase: number, exit: Vector3, plan, options)
	options = options or {}
	local B = Tuning.breach
	local rise = options.rise or byPhase(B.rise, phase)

	local root = livingRoot(worm.target)
	local towards = if root and flat(root.Position - exit).Magnitude > 2
		then flatUnit(root.Position - exit)
		else flatUnit(Vector3.zero)
	local drift = towards * (options.drift or B.drift)

	local blast = options.blast or B.blast
	local damage = options.damage or B.damage

	worm.breaching = true
	worm.mode = "rise"
	worm.riseTo = exit
	worm.riseSpeed = rise
	worm.launchVelocity = Vector3.new(drift.X, rise, drift.Z)
	worm.onApex = options.onApex
	worm.onSurface = function()
		local _, samples = dig(plan, 18)
		fx("erupt", exit, { blocks = samples, radius = blast, width = worm.pieces[1].radius })
		for _, player in ipairs(playersInCircle(exit, blast)) do
			CombatService.applyDamage(player, damage, SOURCE)
		end
		call(options.onSurface)
	end
end

-- ---------------------------------------------------------------------------
-- The attacks
-- ---------------------------------------------------------------------------

--[[
	BREACH

	The exit is under the target's feet - a little ahead of them if they are
	running - and is chosen, with the crater it will make, before the ground
	starts to shake. The head lines up straight beneath it during the warning
	and rises through it when the warning ends, wherever the target is by
	then: you dodge it by moving, not by it missing.

	`options` (for the arcs built on it): exit, rise, warn, onApex.
]]
local function breach(entry, worm, phase: number, scope, options)
	options = options or {}
	local B = Tuning.breach
	local root = livingRoot(worm.target)
	if not root and not options.exit then
		return
	end

	local exit = options.exit or groundUnder(root.Position + flatVelocity(root) * Tuning.swim.lead)
	local plan = planBowl(exit, B.crater, B.craterDepth, B.craterCells)
	local notice = options.warn or byPhase(B.warn, phase)

	local warning = true
	entry.warnings += 1
	local function unwarn()
		if warning then
			warning = false
			entry.warnings -= 1
		end
	end
	scope:add(unwarn)

	fx("rumble", exit, { radius = B.crater * STUD + 4, seconds = notice })

	worm.mode = "approach"
	worm.approachTo = exit - Vector3.new(0, B.depth, 0)
	worm.approachUntil = os.clock() + notice * 0.8

	local ok = pause(entry, notice)
	unwarn()
	if not ok then
		return
	end

	launch(entry, worm, phase, exit, plan, { rise = options.rise, onApex = options.onApex })
	waitFor(entry, function()
		return not inTheArc(worm)
	end, 10)
end

--[[
	RENDING FURROW

	A line from the worm's side of you, through where you stand, and on past
	you. It warns at the far end and along the line, then swims the whole
	length just under the surface tearing up the top block of every column it
	crosses, and comes up out of the far end. The trench stays.
]]
local function furrow(entry, worm, phase: number, scope)
	local F, B = Tuning.furrow, Tuning.breach
	local root = livingRoot(worm.target)
	if not root then
		return
	end

	local here = groundUnder(root.Position)
	local direction = flatUnit(here - worm.pos)
	local from = here - direction * F.length
	from = Vector3.new(from.X, surfaceY(from.X, from.Z, here.Y), from.Z)
	local to = groundUnder(here + direction * F.overshoot)
	local exitPlan = planBowl(to, B.crater, B.craterDepth, B.craterCells)

	fx("furrowline", from, { to = to, seconds = F.warn, radius = F.width * STUD + 2 })

	local depth = math.max(1.5, worm.pieces[1].radius * 0.55)
	worm.mode = "approach"
	worm.approachTo = from - Vector3.new(0, depth + 4, 0)
	worm.approachUntil = os.clock() + F.warn * 0.85
	if not pause(entry, F.warn) then
		return
	end

	local ledger = {}
	local torn = {}
	local cellsLeft = F.maxCells
	local pending = {}
	local lastSent = 0
	local side = Vector3.new(-direction.Z, 0, direction.X)

	worm.breaching = true
	worm.mode = "furrow"
	worm.path = {
		from = flat(from),
		direction = direction,
		length = F.length + F.overshoot,
		travelled = 0,
		speed = byPhase(F.speed, phase),
		depth = depth,

		onMove = function()
			local position = worm.pos
			local columns = {}
			for offset = -F.width, F.width do
				local x = position.X + side.X * offset * STUD
				local z = position.Z + side.Z * offset * STUD
				local key = math.floor(x / STUD) .. ":" .. math.floor(z / STUD)
				if not torn[key] then
					torn[key] = true
					table.insert(columns, { x = x, z = z, y = surfaceY(x, z, position.Y + depth), depth = 1 })
				end
			end
			if #columns > 0 and cellsLeft > 0 then
				local plan = TerrainManager:PlanExcavation(columns, { maxCells = math.min(cellsLeft, #columns) })
				local removed, samples = dig(plan, 6)
				cellsLeft -= removed
				for _, sample in ipairs(samples) do
					table.insert(pending, sample)
				end
			end

			-- In batches, so a trench is a handful of effects rather than one
			-- a tick for BossEffectClient to juggle.
			local now = os.clock()
			if now - lastSent >= 0.2 then
				lastSent = now
				fx("furrow", position + Vector3.new(0, depth, 0), { blocks = pending, direction = direction })
				pending = {}
			end

			for _, player in ipairs(playersInCircle(position + Vector3.new(0, depth, 0), F.radius)) do
				hitOnce(ledger, "furrow", player, F.damage, F.damage)
			end
		end,

		onEnd = function()
			launch(entry, worm, phase, to, exitPlan, { rise = byPhase(B.rise, phase) * 0.85 })
		end,
	}

	waitFor(entry, function()
		return not inTheArc(worm)
	end, 12)
end

-- One glob of ichor: a real arc, ended by the first block in its way.
local function fireGlob(entry, origin: Vector3, destination: Vector3, phase: number, ledger, key: string)
	local P = Tuning.spit
	local gravity = Vector3.new(0, -P.gravity, 0)
	local flight = P.flight
	local velocity = (destination - origin - gravity * (0.5 * flight * flight)) / flight

	local landing, landedAt, normal = destination, flight, Vector3.yAxis
	local previous, previousT = origin, 0
	local steps = 14
	for step = 1, steps do
		local t = flight * 1.4 * step / steps
		local point = origin + velocity * t + gravity * (0.5 * t * t)
		local result = terrainRay(previous, point)
		if result then
			local span = (point - previous).Magnitude
			local fraction = if span > 1e-3 then (result.Position - previous).Magnitude / span else 0
			landing = result.Position
			landedAt = previousT + (t - previousT) * fraction
			normal = result.Normal
			break
		end
		previous, previousT = point, t
	end

	fx("spit", origin, { velocity = velocity, gravity = P.gravity, seconds = landedAt, landing = landing })

	entry.encounterScope:delay(landedAt, function()
		if entry.wormFinished then
			return
		end
		for _, player in ipairs(playersWithin(landing, P.splash)) do
			hitOnce(ledger, key, player, P.damage, P.cap)
		end

		-- The ichor eats the block it struck.
		local inside = landing - normal * (STUD * 0.5)
		local plan = TerrainManager:PlanExcavation({ { x = inside.X, z = inside.Z, y = landing.Y, depth = 1 } }, { maxCells = 1 })
		local _, samples = dig(plan, 1)
		fx("splash", landing, { blocks = samples, normal = normal })

		if math.random() < byPhase(P.broodChance, phase) then
			spawnMinion(entry, landing + normal * 2.5 + Vector3.new(0, 1.5, 0))
		end
	end)
end

-- The raised segments spit, one glob after another, spread along the body
-- and across everyone in reach.
local function spitVolley(entry, worm, phase: number)
	local P = Tuning.spit
	local count = byPhase(P.count, phase)

	local raised = {}
	for index = 2, #worm.pieces do
		local piece = worm.pieces[index]
		if piece.kind == "body" and piece.pos.Y > surfaceY(piece.pos.X, piece.pos.Z, piece.pos.Y) + 3 then
			table.insert(raised, piece)
		end
	end
	if #raised == 0 then
		raised = { worm.pieces[1] }
	end

	local targets = playersWithin(worm.pos, P.reach)
	if #targets == 0 then
		return
	end

	local ledger = {}
	local stride = math.max(1, math.floor(#raised / count))
	for shot = 1, count do
		if entry.wormFinished or entry.leaving then
			return
		end
		local piece = raised[((shot - 1) * stride) % #raised + 1]
		local player = targets[(shot - 1) % #targets + 1]
		local root = livingRoot(player)
		if root and piece.model.Parent then
			local scatter = flatUnit(Vector3.zero) * (math.random() * P.spread)
			local aim = root.Position + flatVelocity(root) * P.flight * 0.6 + scatter
			fireGlob(entry, piece.pos + piece.up * piece.radius, groundUnder(aim), phase, ledger, "glob" .. shot)
		end
		task.wait(P.gap)
	end
end

-- VILE ARC: a high breach that spits from the top.
local function arc(entry, worm, phase: number, scope)
	breach(entry, worm, phase, scope, {
		rise = byPhase(Tuning.spit.rise, phase),
		onApex = function()
			entry.encounterScope:spawn(function()
				spitVolley(entry, worm, phase)
			end)
		end,
	})
end

-- BROOD RETCH: a breach that ends in Blightlings out of its mouth.
local function brood(entry, worm, phase: number, scope)
	breach(entry, worm, phase, scope, {
		rise = byPhase(Tuning.breach.rise, phase) * 0.85,
		onApex = function()
			entry.encounterScope:spawn(function()
				fx("brood", mouthOf(worm), { look = worm.pieces[1].look })
				for _ = 1, byPhase(Tuning.brood.count, phase) do
					if entry.wormFinished or entry.leaving then
						return
					end
					spawnMinion(entry, mouthOf(worm))
					task.wait(Tuning.brood.gap)
				end
			end)
		end,
	})
end

--[[
	SINKHOLE

	A bowl of ground around the target - three blocks deep at the middle,
	one at the rim - is planned, warned, and then collapses; a moment later
	the worm comes up through the bottom of the pit. The rim is shallow on
	purpose: anyone who fell in can climb out a block at a time, if they are
	quick.
]]
local function sinkhole(entry, worm, phase: number, scope)
	local K, B = Tuning.sinkhole, Tuning.breach
	local root = livingRoot(worm.target)
	if not root then
		return
	end

	local centre = groundUnder(root.Position)
	local plan = planBowl(centre, K.radius / STUD, K.depth, K.maxCells)
	if #plan == 0 then
		-- Nothing it may take here - placed blocks, water, bedrock. A plain
		-- breach instead.
		breach(entry, worm, phase, scope)
		return
	end

	fx("sinkwarn", centre, { radius = K.radius, seconds = K.warn })

	local bottom = centre - Vector3.new(0, K.depth * STUD, 0)
	worm.mode = "approach"
	worm.approachTo = bottom - Vector3.new(0, B.depth, 0)
	worm.approachUntil = os.clock() + K.warn * 0.9
	if not pause(entry, K.warn) then
		return
	end

	local _, samples = dig(plan, 24)
	fx("collapse", centre, { blocks = samples, radius = K.radius, depth = K.depth * STUD })
	if not pause(entry, K.delay) then
		return
	end

	launch(entry, worm, phase, bottom, nil, { blast = K.radius * 0.8, damage = K.damage })
	waitFor(entry, function()
		return not inTheArc(worm)
	end, 10)
end

local SPECIALS = {
	furrow = furrow,
	spit = arc,
	sinkhole = sinkhole,
	brood = brood,
}

-- A free head with somebody to go after, for a special: the original head
-- when it is free, since that is the one players are watching.
local function freeWorm(entry): any
	for _, worm in ipairs(entry.worms) do
		if not worm.action and worm.mode == "swim" and livingRoot(worm.target) then
			return worm
		end
	end
	return nil
end

local function startSpecial(entry, phase: number)
	local worm = freeWorm(entry)
	if not worm then
		entry.nextSpecialAt = os.clock() + 0.5
		return
	end

	local cycle = CYCLES[phase] or CYCLES[1]
	entry.cycleIndex = (entry.cycleIndex % #cycle) + 1
	local name = cycle[entry.cycleIndex]
	local action = SPECIALS[name]
	if action then
		runAction(entry, worm, name, action, phase, true)
	end
end

-- ---------------------------------------------------------------------------
-- The fight
-- ---------------------------------------------------------------------------

local function frenzy(entry)
	entry.frenzied = true
	setSky(2, 2)
	announce("The Blightborer writhes in a frenzy!", "bad")
	updatePhaseText(entry)
end

-- Nobody left to hunt: every head turns down and it is gone.
local function leave(entry)
	entry.leaving = true
	entry.busy = true
	for _, worm in ipairs(entry.worms) do
		worm.mode = "leave"
		worm.action = "leave"
		worm.onApex, worm.onSurface, worm.onLand = nil, nil, nil
	end
	announce("The Blightborer sinks back into the deep...", "info")
	entry.encounterScope:delay(Tuning.leaveSeconds, function()
		if not entry.wormFinished then
			EnemyService.despawn(entry.model, "departed")
		end
	end)
end

-- Its pieces pop one after another, tail to head, then the husk is gone.
local function deathHusk(entry)
	local folder = Instance.new("Folder")
	folder.Name = "BlightborerHusk"
	folder.Parent = workspace
	Debris:AddItem(folder, 8)

	local order, points = {}, {}
	for _, worm in ipairs(entry.worms) do
		for index = #worm.pieces, 1, -1 do
			local piece = worm.pieces[index]
			if piece.model and piece.model.Parent then
				piece.model.Parent = folder
				table.insert(order, piece)
				table.insert(points, piece.pos)
			end
		end
	end
	if #order == 0 then
		folder:Destroy()
		return
	end

	local gap = math.clamp(1.6 / #order, 0.04, 0.09)
	fx("death", order[#order].pos, { points = points, gap = gap })

	task.spawn(function()
		for _, piece in ipairs(order) do
			task.wait(gap)
			if piece.model then
				piece.model:Destroy()
			end
		end
		folder:Destroy()
	end)
end

function Blightborer.start(entry)
	entry.wormFinished = false
	entry.leaving = false
	entry.busy = false
	entry.frenzied = false
	entry.warnings = 0
	entry.worms = {}
	entry.actionScopes = {}
	entry.encounterScope = AbilityScope.new()
	entry.contactAt = setmetatable({}, { __mode = "k" })
	entry.minions = {}
	entry.splitsDone = {}
	entry.cycleIndex = 0
	entry.lastSeenAt = os.clock()
	entry.nextSpecialAt = os.clock() + Tuning.special.first
	entry.segmentHealth = entry.def.health / math.max(1, Tuning.body.segments) * Tuning.split.segmentShare

	-- Where EnemyService stood it, before anything is moved.
	local placed = entry.model:GetPivot().Position
	local ground = placed - Vector3.new(0, entry.feetOffset or 0, 0)

	local folder = ReplicatedStorage:FindFirstChild(EnemyConfig.AssetsFolder)
	local headTemplate = folder and EnemyConfig.findAsset(folder, entry.def.asset)
	local bodyTemplate = folder and findPieceAsset(folder, PIECE_ASSETS.body)
	local tailTemplate = folder and findPieceAsset(folder, PIECE_ASSETS.tail)
	if not bodyTemplate then
		warn("[Blightborer] no EnemyAssets.body_segment; the body is made of heads until there is one.")
	end
	if not tailTemplate then
		warn("[Blightborer] no EnemyAssets.tail; it ends in a segment until there is one.")
	end
	entry.templates = {
		head = headTemplate,
		body = bodyTemplate or headTemplate,
		tail = tailTemplate or bodyTemplate or headTemplate,
	}

	local headModel = adoptHead(entry)
	local bodyModels = {}
	for _ = 1, Tuning.body.segments do
		local model = cloneKind(entry, "body")
		if model then
			table.insert(bodyModels, model)
		end
	end
	local tailModel = cloneKind(entry, "tail")

	-- Which way the parts are built, read off a body segment before anything
	-- is measured; see detectCorrection. Then their sizes: see kindScales.
	entry.autoCorrection = detectCorrection(bodyModels[1] or headModel)
	entry.kindScale = kindScales(entry, { head = headModel, body = bodyModels[1], tail = tailModel })
	scaleModel(headModel, entry.kindScale.head)
	for _, model in ipairs(bodyModels) do
		scaleModel(model, entry.kindScale.body)
	end
	scaleModel(tailModel, entry.kindScale.tail)

	local pieces = { newPiece("head", headModel, correctionFor(entry, "head")) }
	for _, model in ipairs(bodyModels) do
		table.insert(pieces, newPiece("body", model, correctionFor(entry, "body")))
	end
	if tailModel then
		table.insert(pieces, newPiece("tail", tailModel, correctionFor(entry, "tail")))
	end

	-- Laid out straight, out of sight under where it was put, pointed at the
	-- nearest player.
	local first = nearestPlayer(ground)
	local firstRoot = rootOf(first)
	local towards = if firstRoot then flatUnit(firstRoot.Position - ground) else Vector3.new(0, 0, -1)
	local headPosition = ground - Vector3.new(0, Tuning.swim.depth + 4, 0) - towards * 10
	pieces[1].pos = headPosition
	pieces[1].look = towards
	for index = 2, #pieces do
		pieces[index].pos = pieces[index - 1].pos - towards * gapBetween(pieces[index - 1], pieces[index])
		pieces[index].look = towards
	end

	local worm = newWorm(entry, pieces, headPosition, towards * byPhase(Tuning.swim.speed, 1), "swim")
	worm.target = first
	-- It announces itself at once.
	worm.nextBreachAt = os.clock() + 1.2

	for _, piece in ipairs(pieces) do
		placePiece(piece)
	end

	-- A sickly light in the head. It shows through the ground, which is a
	-- tell: you can see it coming at night.
	local light = Instance.new("PointLight")
	light.Color = Colors.ichor
	light.Range = 16 * Tuning.body.scale
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = entry.root

	local length = 0
	for index = 2, #pieces do
		length += gapBetween(pieces[index - 1], pieces[index])
	end
	local function size(piece)
		return if piece then string.format("%.1f x %.1f", piece.half * 2, piece.radius * 2) else "-"
	end
	print(string.format(
		"[Blightborer] parts built front along %s, back along %s. head %s, segment %s, tail %s studs "
			.. "(length x width); %d pieces, %.0f studs long. A Vector3 '%s' attribute (degrees) on a "
			.. "model in EnemyAssets overrides the detected facing for that piece.",
		axisName(entry.autoCorrection, Vector3.new(0, 0, -1)), axisName(entry.autoCorrection, Vector3.yAxis),
		size(pieces[1]), size(pieces[2]), size(pieces[#pieces]), #pieces, length, ROTATION_ATTRIBUTE
	))

	setSky(1, 3)
	announce("The Blightborer has awoken!", "bad")
	fx("rumble", ground, { radius = 14, seconds = 1.2 })
end

function Blightborer.step(entry, dt: number, now: number)
	-- Built in start(), which EnemyService runs inside a pcall. If that threw,
	-- it waits rather than erroring once a frame forever.
	if not entry.worms or #entry.worms == 0 then
		return
	end

	local phase = phaseOf(entry)

	for _, worm in ipairs(entry.worms) do
		if now >= worm.retargetAt then
			worm.retargetAt = now + 1.5
			worm.target = chooseTarget(entry, worm)
		end
		if worm.target then
			entry.lastSeenAt = now
		end
		stepWorm(entry, worm, dt, now, phase)
		stepChain(worm)
		for _, piece in ipairs(worm.pieces) do
			placePiece(piece)
		end
	end

	if entry.leaving then
		return
	end

	if now - entry.lastSeenAt >= Tuning.giveUpSeconds then
		leave(entry)
		return
	end

	contactDamage(entry, now)

	if phase == 2 and not entry.frenzied then
		frenzy(entry)
	end

	local B = Tuning.breach
	for _, worm in ipairs(entry.worms) do
		if worm.mode == "swim" and not worm.action and now >= worm.nextBreachAt
			and entry.warnings < byPhase(B.maxConcurrent, phase) then
			local root = livingRoot(worm.target)
			if root and flat(root.Position - worm.pos).Magnitude <= B.range then
				runAction(entry, worm, "breach", breach, phase, false)
			end
		end
	end

	if not entry.busy and now >= entry.nextSpecialAt then
		startSpecial(entry, phase)
	end
end

--[[
	Where a weapon or an ability should think it is: the nearest point on any
	of its pieces. EnemyService.forEachNear asks this rather than reading the
	pivot, which for a worm is only its head. Remembered for a moment, because
	the hit that follows a query is the hit that query found (see damaged).
]]
function Blightborer.nearestPoint(entry, position: Vector3): Vector3?
	local _, _, _, point = nearestPiece(entry, position)
	entry.lastProbe = { position = position, at = os.clock() }
	return point
end

-- The piece a hit landed on: the one the query just before it found, or
-- failing that the one nearest whoever dealt it.
local function pieceHitBy(entry, dealer)
	local probe = entry.lastProbe
	if probe and os.clock() - probe.at <= 0.1 then
		return nearestPiece(entry, probe.position)
	end
	local root = if typeof(dealer) == "Instance" and dealer:IsA("Player") then rootOf(dealer) else nil
	if root then
		return nearestPiece(entry, root.Position)
	end
	return nil
end

-- Where the damage number goes: on the segment that was hit, not on a head
-- eighty studs away.
function Blightborer.impactPoint(entry, dealer): Vector3?
	local _, _, _, point = pieceHitBy(entry, dealer)
	return point
end

function Blightborer.damaged(entry, dealt: number, dealer)
	if not entry.worms or entry.wormFinished or entry.health <= 0 then
		return
	end

	local piece, worm, index = pieceHitBy(entry, dealer)
	if piece and worm and index and piece.kind == "body" then
		piece.damage += dealt
		if piece.damage >= entry.segmentHealth then
			if not split(entry, worm, index) then
				-- It cannot break here yet (too near an end, or four worms
				-- already); it holds at the edge and breaks the moment it can.
				piece.damage = entry.segmentHealth
			end
		end
	end

	local fraction = entry.health / entry.def.health
	for level, threshold in ipairs(Tuning.split.thresholds) do
		if fraction <= threshold and not entry.splitsDone[level] then
			entry.splitsDone[level] = true
			splitMostHurt(entry)
		end
	end
end

function Blightborer.finish(entry, reason: string?)
	entry.wormFinished = true
	entry.busy = false

	if entry.actionScopes then
		for scope in pairs(entry.actionScopes) do
			scope:destroy()
		end
		entry.actionScopes = {}
	end
	if entry.encounterScope then
		entry.encounterScope:destroy()
	end

	-- The sky clears, unless another of it is still out there. EnemyService
	-- has already forgotten this one, so allOf does not count it.
	if #EnemyService.allOf(SELF) == 0 then
		setSky("clear", 3)
	end

	-- Only a death gets a death; leaving takes nothing with it.
	if reason == "died" and entry.worms then
		local ok, err = pcall(deathHusk, entry)
		if not ok then
			warn("[Blightborer] death errored:", err)
		end
		announce("The Blightborer has been defeated!", "good")
	end
end

-- Where the fight changes, as health fractions, for the boss bar's markers
-- (BossService sends it). Two stages: the frenzy at half. The splits are not
-- stages - the bar's subtitle counts the worms instead.
Blightborer.phases = { Tuning.phase2At }

return Blightborer
