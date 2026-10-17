--[[
	AllSeeingEye

	A giant eye that never stops watching you - and then opens a mouth.

	WHERE IT COMES FROM

	Terraria's Eye of Cthulhu, and recognisably so on purpose:

	  it hovers directly above whoever it is after and always looks at them;
	  phase one alternates summoning servants out of its pupil with three
	    charges in a row, turning slowly mid-charge so a sidestep works;
	  at half health it spins in place, tears its iris off and shows a fanged
	    mouth, and a wave of servants spills out as it does;
	  phase two stops summoning and charges harder - three, then it hangs in
	    the air - and near death it chain-dashes almost without stopping;
	  it arrives with "You feel an evil presence watching you...", and if it
	    came at night, it leaves at dawn.

	WHAT ONLY THIS GAME CAN DO WITH IT

	It is an EYE in a world made of blocks, so its own moves are about sight,
	and about the ground.

	  WATCHFUL GAZE   a beam of sight locked on one player for a couple of
	                  seconds. If it can still see them at the end, they are
	                  hurt and its servants are sent after them. Blocks in the
	                  way are cover: natural ground burns away under the gaze,
	                  but a block somebody PLACED holds. Building a wall is a
	                  real answer to this, and it is the only one.
	  UPROOT          it tears chunks of the ground out around you by will
	                  alone, holds them in orbit and hurls them back at you.
	  GOUGING CHARGE  phase two: where a charge skims the floor it rips a
	                  trench, drawn on the ground before it comes, and
	                  swallows what it tore up.
	  BLOOD TEARS     phase two: it rises and weeps; every drop is marked
	                  where it will land and leaves a pool that burns.
	  THE SKY         while it is alive the whole world is tinted red - faint
	                  while it watches, blood red once the mouth is open.

	THE TWO MODELS

	  EnemyAssets.AllSeeingEye        the eyeball. The boss IS this model.
	  EnemyAssets.AllSeeingEyeMouth   the eye with a mouth. Cloned inside the
	                                  boss at the start, scaled to the same
	                                  size, centred on it and hidden; revealed
	                                  at the transformation while the eyeball's
	                                  own parts are hidden. One model throughout,
	                                  so EnemyService's record of it never moves.

	Roblox's front is -Z, and that is where the pupil (later the mouth) has to
	end up. These models are built facing +Z, so EnemyConfig's `modelRotation`
	turns the eye 180 degrees; the mouth is fitted to the eye's turned pivot and
	needs no turn of its own (`mouthRotation` 0). See the notes there.

	EVERY POSE GOES THROUGH applyPose: hovering, holding, the dashes, the spin
	and leaving. It aims the model's front along `entry.look`, then applies that
	correction last - so the correction never touches where it aims or moves.

	Its servants are Demon Eyes - EnemyAssets.DemonEye, the Crimson's own
	enemy - spawned as EnemyConfig's ServantEye, a lighter version of it.

	TERRAIN

	Every block it takes goes through TerrainManager's PlanExcavation and
	ExecuteExcavation, the same door the Slime Emperor uses: natural, loaded,
	breakable, dry ground only - never a placed block, a structure, a cave
	wall or bedrock - under hard caps, with no loot. The cells are chosen
	BEFORE the warning is drawn, and nothing re-aims after it. Clients are told
	what really went and animate the swallowing (BossTerrainClient).

	CLEANUP

	Every attack runs inside an AbilityScope (`entry.scope`); everything an
	attack makes goes into it and is destroyed when the attack ends, however
	it ends. `finish` destroys the running one on death or departure. Every
	wait goes through `pause`, which stops the moment `entry.eyeFinished` is
	set. Older effects are on Debris timers measured in seconds.

	IT DRIVES ITSELF

	EnemyService hands this the whole tick. It flies, so it keeps its own
	position and its own 3D look direction and poses the model from those
	every frame; EnemyService's `orient` (from modelRotation) is applied on
	top, so an asset built the wrong way round is still corrected in one
	place.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

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

-- What clients are told about ground it swallowed. Ensured by BossService at
-- server start as well; see there.
local BossTerrain = Remotes.ensure("BossTerrain", "RemoteEvent")

local AllSeeingEye = {}

local SOURCE = "The All Seeing Eye"

-- Its own name in EnemyConfig, the servants' name (Demon Eyes, tuned for the
-- fight), and the mouth model's.
local SELF = "AllSeeingEye"
local SERVANT = "ServantEye"
local MOUTH_ASSET = "AllSeeingEyeMouth"

local STUD_SIZE = TerrainConfig.StudSize

-- How far from it a client has to be to be told about swallowed ground.
local DEBRIS_BROADCAST_RADIUS = 320

-- The sky tint lives in Lighting under this name. See setSky.
local SKY_EFFECT_NAME = "AllSeeingEyeSky"

local Colors = {
	gaze = Color3.fromRGB(255, 52, 52),
	blood = Color3.fromRGB(128, 10, 16),
	bloodBright = Color3.fromRGB(206, 30, 38),
	sclera = Color3.fromRGB(236, 230, 222),
	iris = Color3.fromRGB(64, 124, 214),
	psychic = Color3.fromRGB(190, 116, 255),
	ember = Color3.fromRGB(255, 150, 60),
}

--[[
	BALANCE

	A player has 100 health. Taking the Slime Emperor's yardstick - an iron or
	gold sword, 18 to 24 damage a second, plus an ability now and then - 2200
	health is a fight of about a minute and a half, a little longer than his,
	which suits something that spends a third of its time out of reach above
	you.

	ONE mistake is always survivable from full and THREE in a row is a death:
	nothing here hits for more than 18, and the 18s - the gaze and a phase two
	charge - have the clearest tells in the fight. Frenzy dashes hit for less,
	because there are a lot of them.
]]
local Tuning = {
	phase2At = 0.5,
	-- Phase two only: the chain dashes, then more of them.
	frenzyAt = 0.25,
	frenzyHardAt = 0.1,

	-- Between attacks, by phase. It is relentless in the way the original is:
	-- the rests are short, and phase one's are shorter than you would think
	-- because summoning is itself a breather.
	restMin = { 1.1, 1.4 },
	restMax = { 1.9, 2.4 },

	arrive = { height = 46 },

	hover = {
		height = 22, -- studs above whoever it is watching
		sway = 7, -- how far off dead-centre it drifts
		swayEvery = 2.5,
		speed = { 34, 46 }, -- top speed while hovering, by phase
		response = 2.2, -- how hard it closes on its hover point
		turnRate = 150, -- degrees a second it turns to keep looking at you
		bobAmplitude = 1.2,
		bobPeriod = 2.6,
	},

	-- Touching it. Its body, measured; see contactDamage.
	contact = { damage = { 10, 14 }, interval = 0.8, reach = 0.85 },

	summon = {
		count = { 3, 4 },
		maxAlive = 8,
		gap = 0.35,
		gather = 0.6,
	},

	charge = {
		count = 3,
		windup = { 0.6, 0.45 },
		rearBack = 5,
		speed = { 72, 96 },
		overshoot = 26,
		maxDistance = 150,
		steer = { 28, 22 }, -- degrees a second it turns mid-dash
		recover = { 0.45, 0.3 },
		damage = { 14, 18 },
		capPerVolley = 36,
		hitPadding = 1.5,
		lockTurnRate = 360,
	},

	-- Phase two's chain dashes, after the normal three.
	frenzy = {
		dashes = { soft = 3, hard = 6 },
		windup = 0.2,
		speed = 124,
		overshoot = 14,
		damage = 12,
		recover = 0.1,
		steer = 0,
	},

	-- The trench a phase two charge rips where it skims the floor.
	gouge = {
		sample = 3, -- studs between points tested along the path
		skim = 10, -- how close to the ground the path has to pass to bite it
		maxCells = 40,
		depth = 1,
		swallow = 0.7,
	},

	gaze = {
		lock = 2.2,
		damage = 18,
		servants = 2,
		burnDepth = 3,
		burnCells = 6,
		turnRate = 260,
	},

	uproot = {
		spots = 3,
		ring = 10, -- how far from you the ground is torn up
		telegraph = 1.0,
		rise = 0.8,
		orbit = 0.7,
		throwGap = 0.45,
		flight = 0.65,
		arc = 7,
		radius = 6,
		damage = 14,
		cap = 28,
		size = 4.4,
		orbitGap = 6,
	},

	tears = {
		drops = 6,
		lift = 12, -- extra height while it weeps
		settle = 0.6,
		gap = 0.38,
		warn = 0.9,
		spread = 8,
		radius = 4.5,
		damage = 10,
		cap = 22,
		pool = 3.0,
		poolDamage = 4,
		poolInterval = 0.6,
	},

	transform = { spin = 1.8, revolutions = 5, servants = 4 },

	-- Leaving: nobody near it for this long, or dawn if it came at night.
	giveUpSeconds = 12,
	giveUpRange = 360,
	leaveRise = 70,
	leaveSeconds = 2.4,
}

-- What it does, in order, by phase. A cycle rather than a lottery, because
-- the original is a rhythm - summon, charge, summon, charge - and the moves
-- of its own slot in between rather than replacing that.
local CYCLES = {
	{ "summon", "charge", "gaze", "summon", "charge", "uproot" },
	{ "charge", "charge", "tears" },
}

-- What the boss bar calls each one while it is happening.
local ATTACK_NAMES = {
	summon = "Servants of the Eye",
	charge = "Charge",
	gouge = "Gouging Charge",
	frenzy = "Frenzy",
	gaze = "Watchful Gaze",
	uproot = "Uproot",
	tears = "Blood Tears",
	transform = "The Eye Tears Open",
}

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

-- The same, only while they are alive. What an attack aims at: a body lies
-- where it fell until the respawn, and it is not a target.
local function livingRoot(player: Player?): BasePart?
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character:FindFirstChild("HumanoidRootPart")
	end
	return nil
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

--[[
	Who an aimed attack goes for: the one it has gone for least recently,
	with enough randomness that it is not a round robin you can count. Alone,
	it is simply you.
]]
local function pickTarget(entry, within: number?): Player?
	local now = os.clock()
	local best, bestScore = nil, -math.huge

	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root and not (within and (root.Position - entry.position).Magnitude > within) then
			local since = math.min(20, now - (entry.pressure[player] or -math.huge))
			local score = since + math.random() * 6
			if score > bestScore then
				best, bestScore = player, score
			end
		end
	end

	if best then
		entry.pressure[best] = now
	end
	return best
end

--[[
	Damage with a memory: each `key` hits a player once, and one cast never
	deals more than `cap` to anyone. Crossing a dash, a rock or a drop twice in
	one frame is still one hit.
]]
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

-- Everyone standing inside a circle on the ground, flat like every other
-- area attack in the game.
local function playersInCircle(centre: Vector3, radius: number): { Player }
	local found = {}
	local squared = radius * radius

	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root then
			local offset = root.Position - centre
			local flat = Vector3.new(offset.X, 0, offset.Z)
			-- Not a column to the sky: a player far above or below the mark
			-- is not standing in it.
			if flat:Dot(flat) <= squared and math.abs(offset.Y) <= radius + 6 then
				table.insert(found, player)
			end
		end
	end

	return found
end

local function announce(text: string, tone: string?)
	for _, player in ipairs(Players:GetPlayers()) do
		CommandFeedback.tell(player, text, tone)
	end
end

-- ---------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------

local function newPart(size: Vector3, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- A Cylinder's length runs along X, so it is turned on its side to lie flat.
local function newDisc(centre: Vector3, radius: number, color: Color3, transparency: number): Part
	local disc = newPart(Vector3.new(0.2, radius * 2, radius * 2), color, transparency)
	disc.Shape = Enum.PartType.Cylinder
	disc.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = workspace
	return disc
end

--[[
	A mark on the ground that fills over `seconds`, over a faint disc at its
	final size - so where the edge will be is readable from the first frame,
	not only once it arrives. The same tell the Slime Emperor uses, so a mark
	means the same thing in every fight.
]]
local function telegraph(centre: Vector3, radius: number, seconds: number, color: Color3)
	local lifted = centre + Vector3.new(0, 0.15, 0)
	local edge = newDisc(lifted, radius, color, 0.82)
	local fill = newDisc(lifted + Vector3.new(0, 0.06, 0), 0.5, color, 0.45)

	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
	}):Play()

	local out = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(seconds, function()
		if fill.Parent then
			TweenService:Create(fill, out, { Transparency = 1 }):Play()
		end
		if edge.Parent then
			TweenService:Create(edge, out, { Transparency = 1 }):Play()
		end
	end)

	Debris:AddItem(edge, seconds + 0.35)
	Debris:AddItem(fill, seconds + 0.35)
end

-- A sphere of light that swells and fades: an impact, a pop, a burst.
local function flare(centre: Vector3, radius: number, seconds: number, color: Color3)
	local ball = newPart(Vector3.one * 1.5, color, 0.3)
	ball.Shape = Enum.PartType.Ball
	ball.Position = centre
	ball.Parent = workspace

	TweenService:Create(ball, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ball, seconds + 0.1)
end

-- Bits thrown loose, in the colours given.
local function gore(centre: Vector3, spread: number, count: number, palette: { Color3 })
	for index = 1, count do
		local bit = newPart(Vector3.one * (0.45 + math.random() * 0.6), palette[(index - 1) % #palette + 1], 0)
		bit.Material = Enum.Material.SmoothPlastic
		bit.Anchored = false
		bit.Massless = true
		bit.CFrame = CFrame.new(centre + Vector3.new(
			(math.random() - 0.5) * spread,
			(math.random() - 0.5) * spread,
			(math.random() - 0.5) * spread
		)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		bit.Parent = workspace

		-- After parenting: velocity on an unparented part is thrown away.
		bit.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 46,
			math.random() * 30 + 6,
			(math.random() - 0.5) * 46
		)
		Debris:AddItem(bit, 2.2)
	end
end

-- Lays a thin box along a line, for beams.
local function layBeam(part: BasePart, from: Vector3, to: Vector3, thickness: number)
	local length = math.max(0.05, (to - from).Magnitude)
	part.Size = Vector3.new(thickness, thickness, length)
	part.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length * 0.5)
end

--[[
	What a block of `name` looks like, as a free part: a copy of the authored
	block when there is one, so the ground it throws at you is visibly the
	ground it tore up. A plain stone-coloured part otherwise.
]]
local function blockLook(name: string?): BasePart
	local assets = ReplicatedStorage:FindFirstChild("TerrainAssets")
	local blocks = assets and assets:FindFirstChild("Blocks")
	local template = blocks and name and blocks:FindFirstChild(name)

	if template and template:IsA("Model") then
		template = template.PrimaryPart or template:FindFirstChildWhichIsA("BasePart")
	end

	local part
	if template and template:IsA("BasePart") then
		part = template:Clone()
		-- Faces only: anything else an authored block carries is not for a rock.
		for _, child in ipairs(part:GetChildren()) do
			if not child:IsA("Decal") then
				child:Destroy()
			end
		end
	else
		part = Instance.new("Part")
		part.Material = Enum.Material.Slate
		part.Color = Color3.fromRGB(112, 106, 100)
	end

	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- Ground it took, flown into its mouth on the clients near enough to see it.
local function broadcastDebris(centre: Vector3, blocks, seconds: number)
	if #blocks == 0 then
		return
	end

	local payload = {
		blocks = blocks,
		centre = centre,
		startedAt = workspace:GetServerTimeNow(),
		seconds = seconds,
	}

	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and (root.Position - centre).Magnitude <= DEBRIS_BROADCAST_RADIUS then
			BossTerrain:FireClient(player, payload)
		end
	end
end

-- ---------------------------------------------------------------------------
-- The sky
-- ---------------------------------------------------------------------------

--[[
	While it lives, the world is tinted. A ColorCorrectionEffect in Lighting,
	made on the server so every client sees the same sky; it never touches the
	clock, which the day and night cycle owns.

	Left in place, neutral, when the fight ends rather than destroyed, so a
	second Eye arriving while the first fades out cannot have its sky deleted
	from under it. A neutral colour correction draws nothing.
]]
local SKY = {
	[1] = { TintColor = Color3.fromRGB(255, 226, 226), Saturation = -0.12, Contrast = 0.04 },
	[2] = { TintColor = Color3.fromRGB(255, 166, 158), Saturation = -0.3, Contrast = 0.14 },
	clear = { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 },
}

local function skyEffect(): ColorCorrectionEffect
	local effect = Lighting:FindFirstChild(SKY_EFFECT_NAME)
	if not (effect and effect:IsA("ColorCorrectionEffect")) then
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = SKY_EFFECT_NAME
		effect.TintColor = Color3.new(1, 1, 1)
		effect.Parent = Lighting
	end
	return effect
end

local function setSky(level, seconds: number)
	TweenService:Create(skyEffect(), TweenInfo.new(seconds, Enum.EasingStyle.Sine), SKY[level]):Play()
end

local function isNight(): boolean
	local clock = Lighting.ClockTime
	return clock < 6 or clock >= 18
end

-- ---------------------------------------------------------------------------
-- Sight
-- ---------------------------------------------------------------------------

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Include

--[[
	The first block between two points, or nil when the line is clear.

	Only the terrain is tested, and placed blocks ARE terrain - placement goes
	through the same chunks and the same renderer - so a wall somebody built is
	cover exactly as a hillside is.
]]
local function sightBlock(from: Vector3, to: Vector3): RaycastResult?
	local folder = workspace:FindFirstChild("GeneratedTerrain")
	if not folder then
		return nil
	end

	sightParams.FilterDescendantsInstances = { folder }
	return workspace:Raycast(from, to - from, sightParams)
end

-- ---------------------------------------------------------------------------
-- Where it is, and where it is looking
-- ---------------------------------------------------------------------------

--[[
	Turns a direction toward another, by at most `maxRadians`, about whatever
	axis gets there shortest. The 3D version of the Slime Emperor's turn: an
	eye looks up and down as well as round.
]]
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
		-- Exactly opposite: any perpendicular will do.
		axis = from:Cross(Vector3.yAxis)
		if axis.Magnitude < 1e-4 then
			axis = Vector3.xAxis
		end
	end

	return (CFrame.fromAxisAngle(axis.Unit, maxRadians) * from).Unit
end

--[[
	Keeps a look direction off the vertical. CFrame.lookAt has no sensible
	answer for "straight down", and an eye directly above someone is exactly
	when it would be asked - so it is held a few degrees off.
]]
local function safeLook(look: Vector3): Vector3
	if look.Magnitude < 1e-3 then
		return Vector3.new(0, -0.5, -1).Unit
	end
	look = look.Unit

	if math.abs(look.Y) <= 0.97 then
		return look
	end

	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local y = if look.Y > 0 then 0.97 else -0.97
	return (flat.Unit * math.sqrt(1 - y * y) + Vector3.new(0, y, 0)).Unit
end

-- Poses the model from its position and look, plus its bob and any extra turn.
local function applyPose(entry, extra: CFrame?)
	local position = entry.position + Vector3.new(0, entry.bob or 0, 0)
	local frame = CFrame.lookAt(position, position + safeLook(entry.look))
	if extra then
		frame *= extra
	end
	entry.model:PivotTo(frame * (entry.orient or CFrame.identity))
end

-- The front of the eye: where the pupil is, and later the mouth.
local function pupilOf(entry): Vector3
	return entry.position + safeLook(entry.look) * (entry.radius or 3)
end

local function groundUnder(position: Vector3): Vector3
	return Vector3.new(position.X, EnemyService.groundAt(position.X, position.Z, position.Y), position.Z)
end

-- Eases toward a point with a capped speed: it floats, it does not snap.
local function moveToward(entry, goal: Vector3, dt: number, maxSpeed: number)
	local desired = (goal - entry.position) * Tuning.hover.response
	if desired.Magnitude > maxSpeed then
		desired = desired.Unit * maxSpeed
	end
	entry.velocity = entry.velocity:Lerp(desired, math.clamp(dt * 4, 0, 1))
	entry.position += entry.velocity * dt
end

-- ---------------------------------------------------------------------------
-- The two forms
-- ---------------------------------------------------------------------------

local function assetsFolder(): Instance?
	return ReplicatedStorage:FindFirstChild(EnemyConfig.AssetsFolder or "EnemyAssets")
end

-- Every visible surface under `root`, with the transparency it was built with.
local function visualParts(root: Instance, skip: Instance?)
	local list = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if skip and (descendant == skip or descendant:IsDescendantOf(skip)) then
			continue
		end
		-- Decal covers Texture too.
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			table.insert(list, { instance = descendant, transparency = descendant.Transparency })
		end
	end
	return list
end

local function setVisible(list, visible: boolean)
	if not list then
		return
	end
	for _, item in ipairs(list) do
		if item.instance.Parent then
			item.instance.Transparency = if visible then item.transparency else 1
		end
	end
end

local function asModel(template: Instance): Model?
	if template:IsA("Model") then
		return template:Clone()
	elseif template:IsA("BasePart") then
		local model = Instance.new("Model")
		local part = template:Clone()
		part.Parent = model
		model.PrimaryPart = part
		return model
	end
	return nil
end

local function largest(size: Vector3): number
	return math.max(size.X, size.Y, size.Z)
end

--[[
	Puts the mouthed form inside the boss, hidden, the same size as the eye and
	centred on it, so revealing it later is a swap of what is visible and
	nothing else.
]]
local function buildMouthForm(entry)
	local folder = assetsFolder()
	local template = folder and folder:FindFirstChild(MOUTH_ASSET)
	if not template then
		warn(string.format(
			"[AllSeeingEye] no %s in ReplicatedStorage.%s; it will keep its eye in phase two.",
			MOUTH_ASSET, tostring(EnemyConfig.AssetsFolder)
		))
		return
	end

	local form = asModel(template)
	if not form then
		warn(string.format("[AllSeeingEye] %s must be a Model or a part.", MOUTH_ASSET))
		return
	end
	form.Name = "MouthForm"

	local eyeBox, eyeSize = entry.model:GetBoundingBox()
	local formSize = form:GetExtentsSize()
	if largest(formSize) > 0.01 then
		form:ScaleTo(form:GetScale() * largest(eyeSize) / largest(formSize))
	end

	for _, descendant in ipairs(form:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	-- Turned to the eye's pivot, plus its own correction if it was built a
	-- different way round from the eye; then moved so the two are centred
	-- on each other whatever either model's pivot is.
	local rotation = entry.def.mouthRotation
	local turn = if typeof(rotation) == "Vector3"
		then CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
		else CFrame.identity
	form:PivotTo(entry.model:GetPivot() * turn)
	local formBox = form:GetBoundingBox()
	form:PivotTo(form:GetPivot() + (eyeBox.Position - formBox.Position))

	form.Parent = entry.model

	entry.mouthParts = visualParts(form)
	setVisible(entry.mouthParts, false)
	entry.eyeParts = visualParts(entry.model, form)
end

local function servantsAlive(): number
	return #EnemyService.allOf(SERVANT)
end

-- ---------------------------------------------------------------------------
-- Attack plumbing
-- ---------------------------------------------------------------------------

--[[
	Waits, unless it is finished. False if the fight ended during the wait, so a
	caller stops in one line.
]]
local function pause(entry, seconds: number): boolean
	local deadline = os.clock() + seconds
	repeat
		if entry.eyeFinished then
			return false
		end
		task.wait()
	until os.clock() >= deadline
	return not entry.eyeFinished
end

local function phaseOf(entry): number
	return if entry.health / entry.def.health <= Tuning.phase2At then 2 else 1
end

-- A glowing point held at the pupil for as long as `scope` lives.
local function pupilGlow(entry, scope, color: Color3, size: number): Part
	local glow = newPart(Vector3.one * size, color, 0.15)
	glow.Shape = Enum.PartType.Ball
	glow.Position = pupilOf(entry)
	glow.Parent = workspace
	scope:add(glow)

	scope:spawn(function()
		while glow.Parent and not entry.eyeFinished do
			glow.Position = pupilOf(entry)
			task.wait()
		end
	end)

	return glow
end

-- Said once per server, so a missing model is reported rather than leaving a
-- fight with no servants and no explanation.
local warnedNoServant = false

local function spawnServant(position: Vector3): Model?
	local model, reason = EnemyService.spawn(SERVANT, position)
	if model then
		flare(position, 2.5, 0.35, Colors.gaze)
	elseif not warnedNoServant then
		warnedNoServant = true
		warn("[AllSeeingEye] could not summon a Demon Eye:", reason)
	end
	return model
end

-- ---------------------------------------------------------------------------
-- The attacks
-- ---------------------------------------------------------------------------

--[[
	SERVANTS OF THE EYE

	It settles over you, its pupil swells with light, and small eyes are pushed
	out of it one after another and come for you. Straight from the original.
	Capped, so ignoring them is a choice with a ceiling.
]]
local function summonServants(entry, phase: number)
	local S = Tuning.summon
	local scope = entry.scope

	entry.focus = pickTarget(entry) or entry.focus
	entry.motion = "hover"

	local glow = pupilGlow(entry, scope, Colors.gaze, 0.6)
	scope:tween(glow, TweenInfo.new(S.gather, Enum.EasingStyle.Quad), {
		Size = Vector3.one * math.max(1.2, entry.radius * 0.7),
	})
	if not pause(entry, S.gather) then
		return
	end

	local alive = servantsAlive()
	for _ = 1, S.count[phase] or 3 do
		if alive >= S.maxAlive then
			break
		end
		if spawnServant(pupilOf(entry) + safeLook(entry.look) * 2) then
			alive += 1
		end
		if not pause(entry, S.gap) then
			return
		end
	end
end

--[[
	Plans the trench a gouging charge will rip: every column under its path
	where the path passes close enough to the ground, frozen now and drawn now,
	before it moves. Sorted by how far along the path each cell is, so the
	ground goes as the eye reaches it rather than all at once.
]]
local function planGouge(entry, from: Vector3, to: Vector3)
	local G = Tuning.gouge
	local line = to - from
	local length = line.Magnitude
	if length < 1 then
		return nil
	end
	local unit = line.Unit

	local columns, seen = {}, {}
	for distance = 0, length, G.sample do
		local point = from + unit * distance
		local ground = EnemyService.groundAt(point.X, point.Z, point.Y)
		if point.Y - ground <= G.skim then
			local key = math.floor(point.X / STUD_SIZE) .. "," .. math.floor(point.Z / STUD_SIZE)
			if not seen[key] then
				seen[key] = true
				table.insert(columns, { x = point.X, z = point.Z, y = ground, depth = G.depth })
			end
		end
	end

	if #columns == 0 then
		return nil
	end

	local plan = TerrainManager:PlanExcavation(columns, { maxCells = G.maxCells })
	if #plan == 0 then
		return nil
	end

	-- The trench, drawn on the cells it will take.
	local marks = {}
	for index, cell in ipairs(plan) do
		cell.along = (cell.position - from):Dot(unit)
		local mark = newPart(
			Vector3.new(STUD_SIZE * 0.92, 0.2, STUD_SIZE * 0.92),
			Colors.gaze,
			0.5
		)
		mark.Position = cell.position + Vector3.new(0, STUD_SIZE * 0.5 + 0.12, 0)
		mark.Parent = workspace
		entry.scope:add(mark)
		marks[index] = mark
		cell.mark = mark
	end

	table.sort(plan, function(a, b)
		return a.along < b.along
	end)

	return { plan = plan, from = from, unit = unit, nextIndex = 1 }
end

-- Takes the trench cells the eye has now reached, or all that are left.
local function advanceGouge(entry, gouge, position: Vector3, final: boolean)
	local reached = (position - gouge.from):Dot(gouge.unit)
	local batch = {}

	while gouge.nextIndex <= #gouge.plan do
		local cell = gouge.plan[gouge.nextIndex]
		if not final and cell.along > reached + 2 then
			break
		end
		table.insert(batch, cell)
		if cell.mark then
			cell.mark:Destroy()
		end
		gouge.nextIndex += 1
	end

	if #batch == 0 then
		return
	end

	local removed, samples = TerrainManager:ExecuteExcavation(batch)
	if removed > 0 then
		broadcastDebris(pupilOf(entry), samples, Tuning.gouge.swallow)
	end
end

--[[
	One dash.

	It rears back while it locks on, then goes. A normal dash re-aims at the
	last instant, the way the original does; a gouging one is aimed when the
	trench is drawn and keeps to it, because the mark on the floor is a promise
	and the eye does not break it. Either way it turns slowly mid-dash, so
	stepping sideways is the dodge.
]]
local function dash(entry, target: Player?, ledger, key: string, options): boolean
	local root = livingRoot(target)
	if not root then
		target = nearestPlayer(entry.position)
		root = rootOf(target)
		if not root then
			return false
		end
	end

	entry.motion = "scripted"

	local direction = safeLook(root.Position - entry.position)
	local gouge = nil
	local plannedTravel = 0
	if options.gouge then
		plannedTravel = math.min(
			(root.Position - entry.position).Magnitude + options.overshoot,
			Tuning.charge.maxDistance
		)
		gouge = planGouge(entry, entry.position, entry.position + direction * plannedTravel)
	end

	-- WIND UP: back off, locking on.
	local start = entry.position
	local began = os.clock()
	local last = began
	while os.clock() - began < options.windup do
		if entry.eyeFinished then
			return false
		end
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now

		if not gouge and livingRoot(target) == root then
			direction = safeLook(root.Position - entry.position)
		end
		entry.look = turnToward(entry.look, direction, math.rad(Tuning.charge.lockTurnRate) * dt)

		local alpha = (now - began) / options.windup
		local eased = alpha * alpha * (3 - 2 * alpha)
		entry.position = start - direction * options.rearBack * eased
		applyPose(entry)
		task.wait()
	end

	-- COMMIT. A target who died during the wind-up is not re-aimed at; the
	-- dash goes where it was already locked.
	if not gouge and livingRoot(target) == root then
		direction = safeLook(root.Position - entry.position)
	end
	entry.look = direction

	-- A gouging dash runs the path it drew, from where the rear-back left it.
	local travel = if gouge
		then plannedTravel + options.rearBack
		else math.min((root.Position - entry.position).Magnitude + options.overshoot, Tuning.charge.maxDistance)
	travel = math.clamp(travel, 8, Tuning.charge.maxDistance)

	local reach = (entry.radius or 3) + Tuning.charge.hitPadding
	local moved = 0
	last = os.clock()

	while moved < travel do
		if entry.eyeFinished then
			return false
		end
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now

		if options.steer > 0 and livingRoot(target) == root then
			direction = turnToward(direction, root.Position - entry.position, math.rad(options.steer) * dt)
		end

		local step = options.speed * dt
		entry.position += direction * step
		moved += step
		entry.look = direction
		applyPose(entry)

		for _, player in ipairs(livingPlayers()) do
			local victim = rootOf(player)
			if victim and (victim.Position - entry.position).Magnitude <= reach then
				hitOnce(ledger, key, player, options.damage, options.cap)
			end
		end

		if gouge then
			advanceGouge(entry, gouge, entry.position, false)
		end

		task.wait()
	end

	if gouge then
		advanceGouge(entry, gouge, entry.position, true)
	end

	return pause(entry, options.recover)
end

--[[
	CHARGE

	Three dashes in a row, as the original. In phase two they are faster and
	GOUGE: wherever the path skims the floor a trench is drawn first and torn
	out as the eye passes, the ground flying into its mouth. Below a quarter
	health the three are followed by chain dashes, and below a tenth by twice
	as many.
]]
local function charge(entry, phase: number)
	local C = Tuning.charge
	local target = pickTarget(entry) or nearestPlayer(entry.position)
	if not target then
		return
	end

	local ledger = {}
	local normal = {
		windup = C.windup[phase],
		rearBack = C.rearBack,
		speed = C.speed[phase],
		overshoot = C.overshoot,
		steer = C.steer[phase],
		recover = C.recover[phase],
		damage = C.damage[phase],
		cap = C.capPerVolley,
		gouge = phase == 2,
	}

	for index = 1, C.count do
		if not dash(entry, target, ledger, "dash" .. index, normal) then
			return
		end
	end

	if phase < 2 then
		return
	end

	local F = Tuning.frenzy
	local fraction = entry.health / entry.def.health
	local extra = if fraction <= Tuning.frenzyHardAt
		then F.dashes.hard
		elseif fraction <= Tuning.frenzyAt then F.dashes.soft
		else 0
	if extra == 0 then
		return
	end

	entry.bossPhase = ATTACK_NAMES.frenzy
	BossService.update(entry)

	local quick = {
		windup = F.windup,
		rearBack = 2,
		speed = F.speed,
		overshoot = F.overshoot,
		steer = F.steer,
		recover = F.recover,
		damage = F.damage,
		cap = C.capPerVolley,
		gouge = false,
	}

	for index = 1, extra do
		-- A fresh target each time when there is a crowd, so the frenzy goes
		-- through the room rather than down one player.
		local victim = if index % 2 == 0 then (pickTarget(entry) or target) else target
		if not dash(entry, victim, ledger, "frenzy" .. index, quick) then
			return
		end
	end
end

--[[
	Burns away the cover between the eye and whoever it was looking at:
	the natural ground at the point the gaze struck. A PLACED block refuses to
	burn - TerrainManager will not plan it - which is what makes building a
	wall the answer to the gaze rather than a delay.
]]
local function burnCover(entry, hit: RaycastResult)
	local G = Tuning.gaze
	local inside = hit.Position - hit.Normal * (STUD_SIZE * 0.5)

	local plan = TerrainManager:PlanExcavation({
		{ x = inside.X, z = inside.Z, y = inside.Y, depth = G.burnDepth },
	}, { maxCells = G.burnCells })

	flare(hit.Position, 3, 0.4, Colors.ember)

	if #plan > 0 then
		local removed, samples = TerrainManager:ExecuteExcavation(plan)
		if removed > 0 then
			broadcastDebris(pupilOf(entry), samples, 0.6)
		end
	end
end

--[[
	WATCHFUL GAZE

	It stops, and stares. A beam of sight runs from its pupil to one player,
	thickening for a couple of seconds. If the line is still clear when it
	ends, they are hit and two servants are sent straight at them.

	The beam shows the truth every frame: where a block is in the way it ends
	at the block and goes dim. So a player can see whether they are hidden,
	and from where.

	Hidden behind natural ground, the gaze burns a hole in it. Hidden behind a
	block they PLACED, nothing happens to anyone - see burnCover.
]]
local function watchfulGaze(entry, _phase: number)
	local G = Tuning.gaze
	local scope = entry.scope

	local target = pickTarget(entry) or nearestPlayer(entry.position)
	local root = livingRoot(target)
	if not root then
		return
	end

	entry.focus = target
	entry.motion = "hold"
	entry.turnRate = G.turnRate

	local beam = newPart(Vector3.new(0.3, 0.3, 1), Colors.gaze, 0.6)
	beam.Parent = workspace
	scope:add(beam)

	local glow = pupilGlow(entry, scope, Colors.gaze, 0.8)

	local began = os.clock()
	while os.clock() - began < G.lock do
		-- Stops if they die mid-stare, rather than hitting the body and
		-- sending servants to circle it.
		if entry.eyeFinished or not root.Parent or not livingRoot(target) then
			return
		end

		local from = pupilOf(entry)
		local hit = sightBlock(from, root.Position)
		local alpha = (os.clock() - began) / G.lock

		layBeam(beam, from, if hit then hit.Position else root.Position, 0.25 + alpha * 0.9)
		beam.Transparency = if hit then 0.82 else 0.55 - alpha * 0.35
		glow.Size = Vector3.one * (0.8 + alpha * 1.4)

		task.wait()
	end

	-- THE VERDICT, on the line as it is now.
	local from = pupilOf(entry)
	local hit = sightBlock(from, root.Position)

	if hit then
		layBeam(beam, from, hit.Position, 1.6)
		beam.Transparency = 0.2
		burnCover(entry, hit)
	else
		layBeam(beam, from, root.Position, 1.8)
		beam.Transparency = 0.1
		flare(root.Position, 4, 0.4, Colors.gaze)
		CombatService.applyDamage(target, G.damage, SOURCE)

		-- And its servants are sent: out of nowhere, around the one it saw.
		local alive = servantsAlive()
		for index = 1, G.servants do
			if alive >= Tuning.summon.maxAlive then
				break
			end
			local angle = (index / G.servants) * math.pi * 2 + math.random()
			local spot = root.Position + Vector3.new(math.cos(angle) * 10, 6, math.sin(angle) * 10)
			if spawnServant(spot) then
				alive += 1
			end
		end
	end

	scope:tween(beam, TweenInfo.new(0.35), { Transparency = 1 })
	pause(entry, 0.4)
end

--[[
	UPROOT

	It looks at the ground around you, and the ground comes up. Three patches,
	ringed for a second before they go; the blocks lift out, leaving holes,
	rise and circle the eye, and are thrown at you one after another - each
	landing spot marked as it is thrown, where you are at that moment.

	The patches are chosen and frozen before they are marked. A patch that has
	nothing natural in it to take simply throws nothing.
]]
local function uproot(entry, _phase: number)
	local U = Tuning.uproot
	local scope = entry.scope

	local target = pickTarget(entry) or nearestPlayer(entry.position)
	local root = livingRoot(target)
	if not root then
		return
	end

	entry.focus = target
	entry.motion = "hold"

	-- THE PATCHES, frozen now: a ring around where you are.
	local centre = root.Position
	local base = math.random() * math.pi * 2
	local patches = {}
	for index = 1, U.spots do
		local angle = base + (index - 1) / U.spots * math.pi * 2
		local spot = groundUnder(centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * U.ring)

		local columns = {}
		for dx = 0, 1 do
			for dz = 0, 1 do
				table.insert(columns, {
					x = spot.X + (dx - 0.5) * STUD_SIZE,
					z = spot.Z + (dz - 0.5) * STUD_SIZE,
					y = spot.Y,
					depth = 1,
				})
			end
		end

		local plan = TerrainManager:PlanExcavation(columns, { maxCells = 4 })
		if #plan > 0 then
			table.insert(patches, { spot = spot, plan = plan, angle = angle })
			telegraph(spot, STUD_SIZE * 1.2, U.telegraph, Colors.psychic)
		end
	end

	if #patches == 0 then
		return
	end

	local glow = pupilGlow(entry, scope, Colors.psychic, 0.8)
	scope:tween(glow, TweenInfo.new(U.telegraph), { Size = Vector3.one * 2.2 })
	if not pause(entry, U.telegraph) then
		return
	end

	-- OUT OF THE GROUND.
	local rocks = {}
	for _, patch in ipairs(patches) do
		local removed, samples = TerrainManager:ExecuteExcavation(patch.plan)
		if removed > 0 then
			local rock = blockLook(samples[1] and samples[1].block)
			rock.Size = Vector3.one * U.size
			rock.CFrame = CFrame.new(patch.spot - Vector3.new(0, 1, 0))
			rock.Parent = workspace
			scope:add(rock)

			gore(patch.spot, 3, 6, { rock.Color, Color3.fromRGB(90, 84, 76) })
			table.insert(rocks, { part = rock, angle = patch.angle, from = rock.Position, state = "rise" })
		end
	end

	if #rocks == 0 then
		return
	end

	local ledger = {}
	local orbit = (entry.radius or 3) + U.orbitGap
	local began = os.clock()
	local throwAt = began + U.rise + U.orbit
	for index, rock in ipairs(rocks) do
		rock.throwAt = throwAt + (index - 1) * U.throwGap
	end

	-- One loop drives every rock: rising, circling, flying, landed.
	while true do
		if entry.eyeFinished then
			return
		end

		local now = os.clock()
		local spin = (now - began) * 2.2
		local busy = false

		for index, rock in ipairs(rocks) do
			if rock.state == "done" then
				continue
			end
			busy = true

			local circling = entry.position + Vector3.new(
				math.cos(rock.angle + spin) * orbit,
				1.5,
				math.sin(rock.angle + spin) * orbit
			)
			local position

			if rock.state == "rise" then
				local alpha = math.clamp((now - began) / U.rise, 0, 1)
				local eased = alpha * alpha * (3 - 2 * alpha)
				position = rock.from:Lerp(circling, eased)
				if alpha >= 1 then
					rock.state = "orbit"
				end
			elseif rock.state == "orbit" then
				position = circling
				if now >= rock.throwAt then
					-- Thrown at where you are NOW, and marked there.
					local victim = livingRoot(target) or rootOf((nearestPlayer(entry.position)))
					if victim then
						rock.state = "fly"
						rock.launchedAt = now
						rock.from = circling
						rock.to = groundUnder(victim.Position)
						telegraph(rock.to, U.radius, U.flight, Colors.psychic)
					else
						rock.state = "done"
						rock.part:Destroy()
						continue
					end
				end
			else
				local alpha = math.clamp((now - rock.launchedAt) / U.flight, 0, 1)
				position = rock.from:Lerp(rock.to, alpha) + Vector3.new(0, math.sin(alpha * math.pi) * U.arc, 0)

				if alpha >= 1 then
					for _, player in ipairs(playersInCircle(rock.to, U.radius)) do
						hitOnce(ledger, "rock" .. index, player, U.damage, U.cap)
					end
					flare(rock.to + Vector3.new(0, 1, 0), U.radius, 0.35, Colors.psychic)
					gore(rock.to + Vector3.new(0, 1, 0), 2, 8, { rock.part.Color, Color3.fromRGB(90, 84, 76) })
					rock.part:Destroy()
					rock.state = "done"
					continue
				end
			end

			rock.part.CFrame = CFrame.new(position) * CFrame.Angles(spin, spin * 0.7, 0)
		end

		if not busy then
			break
		end
		task.wait()
	end
end

-- A drop of blood that falls from the eye to a marked spot and pools there.
local function tear(entry, scope, spot: Vector3, ledger, key: string)
	local T = Tuning.tears

	telegraph(spot, T.radius, T.warn, Colors.bloodBright)

	local drop = newPart(Vector3.new(0.9, 1.4, 0.9), Colors.bloodBright, 0)
	drop.Shape = Enum.PartType.Ball
	drop.Position = pupilOf(entry)
	drop.Parent = workspace
	scope:add(drop)

	scope:spawn(function()
		local from = drop.Position
		local began = os.clock()
		while true do
			if entry.eyeFinished or not drop.Parent then
				return
			end
			local alpha = math.clamp((os.clock() - began) / T.warn, 0, 1)
			drop.Position = from:Lerp(spot, alpha * alpha)
			if alpha >= 1 then
				break
			end
			task.wait()
		end
		drop:Destroy()

		for _, player in ipairs(playersInCircle(spot, T.radius)) do
			hitOnce(ledger, key, player, T.damage, T.cap)
		end
		flare(spot + Vector3.new(0, 0.5, 0), T.radius, 0.3, Colors.bloodBright)

		-- The pool. Its own short life, so it outlasts the attack a little and
		-- then goes; it stops hurting the moment the eye is gone.
		local pool = newDisc(spot + Vector3.new(0, 0.28, 0), T.radius * 0.85, Colors.blood, 0.3)
		pool.Material = Enum.Material.SmoothPlastic
		Debris:AddItem(pool, T.pool)

		task.spawn(function()
			for _ = 1, math.floor(T.pool / T.poolInterval) do
				task.wait(T.poolInterval)
				if entry.eyeFinished or not pool.Parent then
					return
				end
				for _, player in ipairs(playersInCircle(spot, T.radius * 0.85)) do
					CombatService.applyDamage(player, T.poolDamage, SOURCE)
				end
			end
		end)
	end)
end

--[[
	BLOOD TEARS

	It climbs, and weeps. Drops fall one after another, the first straight at
	you and the rest around you, each marked on the ground for as long as it
	takes to fall. Where they land they pool, and the pools burn for a few
	seconds - the floor around you gets worse the longer you stand in one
	place.
]]
local function bloodTears(entry, _phase: number)
	local T = Tuning.tears
	local scope = entry.scope

	local target = pickTarget(entry) or nearestPlayer(entry.position)
	if not target then
		return
	end

	entry.focus = target
	entry.motion = "hover"
	entry.hoverLift = T.lift

	pupilGlow(entry, scope, Colors.bloodBright, 1)
	if not pause(entry, T.settle) then
		return
	end

	local ledger = {}
	for index = 1, T.drops do
		local root = livingRoot(target) or rootOf((nearestPlayer(entry.position)))
		if not root then
			break
		end

		local offset = if index == 1
			then Vector3.zero
			else Vector3.new((math.random() - 0.5) * 2 * T.spread, 0, (math.random() - 0.5) * 2 * T.spread)
		tear(entry, scope, groundUnder(root.Position + offset), ledger, "tear" .. index)

		if not pause(entry, T.gap) then
			return
		end
	end

	-- The last drops land before the attack is over and its scope goes.
	pause(entry, T.warn + 0.1)
end

--[[
	THE EYE TEARS OPEN

	The phase change. It stops dead and spins, faster and faster; halfway
	through, the iris tears off in a spray of gore and the mouth is there
	instead. Servants spill out, the sky goes to blood, and it comes out of
	the spin hungry.

	Nothing here hurts anyone. The player just did something good, and
	answering that with an unavoidable hit teaches people to stop pushing.
]]
local function tearOpen(entry)
	gore(pupilOf(entry), entry.radius * 1.2, 26, { Colors.sclera, Colors.iris, Colors.bloodBright, Colors.blood })
	flare(entry.position, entry.radius * 3.5, 0.7, Colors.bloodBright)

	if entry.mouthParts then
		setVisible(entry.eyeParts, false)
		setVisible(entry.mouthParts, true)
	end

	setSky(2, 2.5)
end

local function transform(entry, _phase: number)
	local X = Tuning.transform
	entry.motion = "scripted"

	local began = os.clock()
	local last = began
	local angle = 0
	local opened = false

	while os.clock() - began < X.spin do
		if entry.eyeFinished then
			return
		end
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now

		-- Up to speed and back down: a spin that starts and stops at full
		-- speed reads as the model glitching rather than as the eye turning.
		local alpha = (now - began) / X.spin
		local rate = (2 * math.pi * X.revolutions / X.spin) * (math.pi / 2) * math.sin(alpha * math.pi)
		angle += rate * dt
		applyPose(entry, CFrame.Angles(0, angle, 0))

		if not opened and alpha >= 0.55 then
			opened = true
			tearOpen(entry)
		end

		task.wait()
	end

	if not opened then
		tearOpen(entry)
	end
	applyPose(entry)

	local alive = servantsAlive()
	for index = 1, X.servants do
		if alive >= Tuning.summon.maxAlive then
			break
		end
		local angleOut = (index / X.servants) * math.pi * 2
		local spot = entry.position + Vector3.new(math.cos(angleOut), -0.3, math.sin(angleOut)) * (entry.radius + 3)
		if spawnServant(spot) then
			alive += 1
		end
	end

	entry.transformed = true
	entry.cycleIndex = 0
	pause(entry, 0.6)
end

-- ---------------------------------------------------------------------------
-- The fight
-- ---------------------------------------------------------------------------

local ATTACKS = {
	summon = summonServants,
	charge = charge,
	gaze = watchfulGaze,
	uproot = uproot,
	tears = bloodTears,
	transform = transform,
}

-- The next move in this phase's cycle. Summoning is skipped while the
-- servants are at their cap, since it would do nothing.
local function nextInCycle(entry, phase: number): string
	local cycle = CYCLES[phase]

	for _ = 1, #cycle do
		entry.cycleIndex = (entry.cycleIndex or 0) % #cycle + 1
		local pick = cycle[entry.cycleIndex]
		if not (pick == "summon" and servantsAlive() >= Tuning.summon.maxAlive) then
			return pick
		end
	end

	return "charge"
end

--[[
	One attack, start to finish, in its own thread, with everything it makes
	in a scope that goes when it ends - the same arrangement as the Slime
	Emperor's, for the same reasons. The phase change pre-empts the cycle the
	first time it acts below half health.
]]
local function performAttack(entry, phase: number)
	local pick = if phase == 2 and not entry.transformed then "transform" else nextInCycle(entry, phase)

	entry.bossPhase = if pick == "charge" and phase == 2 then ATTACK_NAMES.gouge else ATTACK_NAMES[pick]
	entry.busy = true
	BossService.update(entry)

	local scope = AbilityScope.new()
	entry.scope = scope

	task.spawn(function()
		local ok, err = pcall(ATTACKS[pick], entry, phase)

		if entry.scope == scope then
			entry.scope = nil
		end
		scope:destroy()

		if entry.eyeFinished then
			return
		end

		if not ok then
			warn("[AllSeeingEye]", pick, "failed:", err)
		end

		-- Back to watching, whatever the attack left it doing.
		entry.motion = "hover"
		entry.focus = nil
		entry.turnRate = nil
		entry.hoverLift = 0
		entry.velocity = Vector3.zero

		local now = phaseOf(entry)
		local rest = math.random() * (Tuning.restMax[now] - Tuning.restMin[now]) + Tuning.restMin[now]
		entry.nextAttackAt = os.clock() + rest
		entry.busy = false
		entry.bossPhase = nil
		BossService.update(entry)
	end)
end

--[[
	Touching it. Its body, measured - a sphere around its centre - so the
	reach is the eye you can see, whatever size the model is.
]]
local function contactDamage(entry, now: number, phase: number)
	local C = Tuning.contact
	local reach = (entry.radius or 3) * C.reach + 1.5

	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root and now - (entry.contactAt[player] or -math.huge) >= C.interval then
			if (root.Position - entry.position).Magnitude <= reach then
				entry.contactAt[player] = now
				CombatService.applyDamage(player, C.damage[phase], SOURCE)
			end
		end
	end
end

-- It rises out of sight and is gone: at dawn if it came at night, or when
-- there has been nobody near it for a while.
local function leave(entry, why: string)
	entry.leaving = true
	entry.busy = true
	entry.motion = "scripted"

	if why == "dawn" then
		announce("The All Seeing Eye closes as the sun rises...", "info")
	end

	task.spawn(function()
		local from = entry.position
		local began = os.clock()
		while os.clock() - began < Tuning.leaveSeconds do
			if entry.eyeFinished then
				return
			end
			local alpha = (os.clock() - began) / Tuning.leaveSeconds
			entry.position = from + Vector3.new(0, Tuning.leaveRise * alpha * alpha, 0)
			applyPose(entry)
			task.wait()
		end
		EnemyService.despawn(entry.model, "departed")
	end)
end

function AllSeeingEye.start(entry)
	entry.eyeFinished = false
	entry.busy = false
	entry.leaving = false
	entry.transformed = false
	entry.scope = nil
	entry.motion = "hover"
	entry.focus = nil
	entry.turnRate = nil
	entry.hoverLift = 0
	entry.hoverOffset = Vector3.zero
	entry.nextSwayAt = 0
	entry.velocity = Vector3.zero
	entry.bob = 0
	entry.bobPhase = 0
	entry.cycleIndex = 0
	entry.pressure = setmetatable({}, { __mode = "k" })
	entry.contactAt = setmetatable({}, { __mode = "k" })
	entry.lastSeenAt = os.clock()

	-- Came at night: then dawn sends it away. Summoned by day, it stays.
	entry.nightBorn = isNight()

	-- Its size, read off the model before anything is added to it.
	entry.radius = largest(entry.model:GetExtentsSize()) * 0.5

	-- It arrives from high above wherever it was put, and comes down to you.
	local placed = entry.model:GetPivot().Position
	entry.position = placed + Vector3.new(0, Tuning.arrive.height, 0)
	local first = rootOf((nearestPlayer(placed)))
	entry.look = safeLook(if first then first.Position - entry.position else Vector3.new(0, -0.5, -1))

	buildMouthForm(entry)

	-- A light inside it, so it reads at night - which is when it comes.
	local light = Instance.new("PointLight")
	light.Color = Colors.gaze
	light.Range = math.max(16, entry.radius * 5)
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = entry.root

	setSky(1, 3)
	announce("You feel an evil presence watching you...", "bad")

	applyPose(entry)
	entry.nextAttackAt = os.clock() + 3
end

function AllSeeingEye.step(entry, dt: number, now: number)
	-- Built in start(), which EnemyService runs inside a pcall. If that threw,
	-- it waits in place rather than erroring once a frame forever.
	if not entry.position then
		return
	end

	local H = Tuning.hover

	entry.bobPhase += dt
	entry.bob = if entry.motion == "scripted"
		then 0
		else math.sin(entry.bobPhase * 2 * math.pi / H.bobPeriod) * H.bobAmplitude

	local phase = phaseOf(entry)
	local target = nearestPlayer(entry.position, Tuning.giveUpRange)
	if target then
		entry.lastSeenAt = now
	end

	if not entry.busy and not entry.leaving then
		if entry.nightBorn and not isNight() then
			leave(entry, "dawn")
			return
		end
		if now - entry.lastSeenAt >= Tuning.giveUpSeconds then
			leave(entry, "alone")
			return
		end
	end

	if entry.motion ~= "scripted" then
		local focus = livingRoot(entry.focus) or rootOf(target)

		if entry.motion == "hover" and focus then
			-- Directly above, drifting a little: never quite still.
			if now >= entry.nextSwayAt then
				entry.nextSwayAt = now + H.swayEvery
				local angle = math.random() * math.pi * 2
				entry.hoverOffset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (math.random() * H.sway)
			end
			local goal = focus.Position + entry.hoverOffset + Vector3.new(0, H.height + (entry.hoverLift or 0), 0)
			moveToward(entry, goal, dt, H.speed[phase])
		elseif entry.motion == "hold" then
			entry.velocity = Vector3.zero
		end

		-- It always looks at you.
		if focus then
			local rate = entry.turnRate or H.turnRate
			entry.look = safeLook(turnToward(entry.look, focus.Position - entry.position, math.rad(rate) * dt))
		end

		applyPose(entry)
	end

	if not entry.leaving then
		contactDamage(entry, now, phase)
	end

	if entry.busy or entry.leaving or not target then
		return
	end

	if now >= (entry.nextAttackAt or 0) then
		performAttack(entry, phase)
	end
end

function AllSeeingEye.finish(entry, reason: string?)
	entry.eyeFinished = true
	entry.busy = false

	if entry.scope then
		entry.scope:destroy()
		entry.scope = nil
	end

	-- The sky clears, unless another of it is still out there watching.
	-- EnemyService has already forgotten this one, so allOf does not count it.
	if #EnemyService.allOf(SELF) == 0 then
		setSky("clear", 3)
	end

	-- Only a death gets a death; leaving takes nothing with it.
	if reason == "died" and entry.position then
		pcall(function()
			gore(entry.position, entry.radius * 1.6, 34, { Colors.blood, Colors.bloodBright, Colors.sclera, Colors.iris })
			flare(entry.position, entry.radius * 6, 0.9, Colors.gaze)
		end)
		announce("The All Seeing Eye has been defeated!", "good")
	end
end

return AllSeeingEye
