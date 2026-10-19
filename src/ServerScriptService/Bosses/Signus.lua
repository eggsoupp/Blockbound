--[[
	Signus - the Hallowed Eclipse

	A hooded lunar spellcaster. It floats, it keeps its distance, and it
	fights with the ground and the sky rather than with its body.

	WHAT IT DOES

	  UMBRAL MAELSTROM  a fixed warning tightens into coiling violet ribbons;
	                    terrain rises into orbit, then is flung onto the rim.
	  ECLIPSE JUDGMENT  charges and launches an orb; the target compresses,
	                    then erupts into a towering beam with orbiting rings.
	                    Real terrain rises and lands around a lasting crater.
	  WORLDREND         a sustained violet flame beam, with a fixed aim and a
	                    clear windup, tears a strip of ground into moving blocks.
	  TOTALITY          the half-health transformation raises an orbit of
	                    terrain, changes the sky and forms the overhead eclipse.
	  CRESCENT LUNGE    a short charge followed by a vulnerable recovery.
	  VEIL STEP         a short reposition with a crescent and departure burst.

	SignusMoves owns the three reference attacks and Totality. The earlier
	attack helpers remain private below and are not in the active ATTACKS map.

	HOW IT MOVES

	It holds a casting ring twenty-odd studs from whoever it is after, hem a
	couple of studs off the ground, drifting slowly round and going still
	while it casts. That puts its pivot inside a sword's reach when you stand
	beside it. It rises only for Moonfall and Totality, and sinks to the
	ground for the Fissure, the Nova and the end of a Lunge.

	THE RIG

	EnemyAssets.Signus is a Motor6D rig: an anchored, invisible RootPart and
	four jointed MeshParts (see assets/signus-hallow/roblox). This module only
	ever moves the RootPart, through applyPose -> Model:PivotTo, exactly as
	the All Seeing Eye does. The joints are posed by EnemyAnimator when a
	track is published and by short C0 tweens on the Motor6Ds (POSES below)
	when it is not; the two never run on the same move, and the RootPart is
	no joint's Part1, so nothing here can move it.

	TERRAIN

	Every block it takes goes through TerrainManager's PlanExcavation and
	ExecuteExcavation: natural, loaded, breakable, dry ground only, never a
	placed block, a structure, a cave wall or bedrock, under the caps in
	Tuning, with no loot. Cells are chosen BEFORE the warning is drawn and
	nothing re-aims after it. Clients are told what really went over
	BossEffect; particle shards stream out of the actual excavated cells into
	the halo. No cosmetic terrain clones are made.

	EFFECTS

	Invisible carriers replicate the authoritative positions, sizes and opacity
	of telegraphs, projectiles, aura and eclipse. SignusVisuals renders pack
	particles and beams locally, including when an observer joins mid-fight.
	Bursts, flashes and camera kicks use BossEffect and SignusVFX.

	CLEANUP

	Every spell runs inside `entry.scope`, destroyed when it ends however it
	ends. Persistent encounter effects (lights, halo, eclipse, sky) live in
	`entry.encounterScope`, destroyed in finish. Every wait goes through
	`pause`, which stops the moment `entry.signusFinished` is set.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AbilityScope = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityScope"))

local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local EnemyAnimator = require(ServerScriptService:WaitForChild("EnemyAnimator"))
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local BossService = require(ServerScriptService:WaitForChild("BossService"))
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

-- Both ensured by BossService at server start as well; see there.
local BossEffect = Remotes.ensure("BossEffect", "RemoteEvent")

local Signus = {}

local SOURCE = "Signus"
local SELF = "Signus"

local STUD_SIZE = TerrainConfig.StudSize

-- How far from an effect a client has to be to be told about it.
local BROADCAST_RADIUS = 320

local SKY_EFFECT_NAME = "SignusSky"

local Colors = {
	plum = Color3.fromRGB(58, 18, 78),
	violet = Color3.fromRGB(142, 64, 220),
	orchid = Color3.fromRGB(236, 120, 255),
	pearl = Color3.fromRGB(255, 236, 246),
	teal = Color3.fromRGB(120, 240, 230),
	gold = Color3.fromRGB(255, 214, 120),
	black = Color3.new(0, 0, 0),
}

--[[
	BALANCE

	A player has 100 health. Against an iron or gold sword - 18 to 24 damage a
	second while in reach, plus an ability now and then - 2000 health is a
	fight of a minute and a half to two: a little under the Eye's health,
	because Signus is in reach more of the time, but it holds still less.

	ONE mistake is survivable from full and THREE in a row is a death. The
	Nova is the one thing that hits for more than 18, and it is the one thing
	a wall stops outright. Numbers in pairs are { phase one, phase two }.
]]
local Tuning = {
	phase2At = 0.5,

	restMin = { 1.6, 1.2 },
	restMax = { 2.4, 1.9 },

	-- Where it waits between spells: a ring around whoever it is after.
	hover = {
		ring = { 24, 27 }, -- studs from its focus
		hem = 2.5, -- studs between the bottom of the robe and the ground
		ringDrift = 0.22, -- radians a second the ring position slides round
		speed = { 14, 17 }, -- top speed drifting round the ring
		response = 1.6,
		turnRate = 200, -- degrees a second it turns to face you
		bobAmplitude = 0.9,
		bobPeriod = 3.2,
		leanRate = 3, -- how fast a lean eases in
	},

	-- Touching the robe. Its body, measured; see contactDamage.
	-- Lateral reach is kept inside a sword's: standing five to eight studs
	-- out is in range to hit it and out of range to be touched.
	contact = { damage = 8, interval = 0.8, reach = 4.5, height = 10 },

	volley = {
		count = { 3, 5 },
		gather = 0.9,
		gap = 0.15,
		speed = 70,
		hitRadius = 3.5,
		damage = 8,
		cap = 16,
		life = 1.6,
		homing = { 0, 22 }, -- degrees a second a crescent bends toward you
		radius = 2.6, -- of the crescent arc
		segments = 7,
		recover = 0.7,
	},

	moonfall = {
		hem = 7,
		track = 0.6,
		fall = 0.8,
		radius = 7,
		damage = 18,
		cap = 36,
		depth = { 1, 2 },
		cap_cells = { 9, 18 },
		sigils = { 1, 2 },
		halo = 4, -- fragments the crater feeds into the halo
		recover = 0.8,
	},

	fissure = {
		cracks = { 1, 2 },
		fan = 35, -- degrees between the two cracks
		length = 40,
		start = 5, -- the crack begins this far from its hem
		raise = 0.45,
		warn = 1.2,
		stagger = 0.05, -- seconds between cells erupting
		width = 3.5,
		safeHeight = 6.5, -- root this far above the cell is clear of it
		damage = 14,
		cap = 24,
		recover = 1.2,
	},

	lunge = {
		farDistance = 38,
		farSeconds = 4,
		hiddenSeconds = 4,
		windup = 0.7,
		rearBack = 4,
		speed = 60,
		overshoot = 6,
		reach = 5.5,
		damage = 16,
		cooldown = 12,
		recover = 1.5,
		bladeRadius = 4.2,
	},

	step = {
		nearDistance = 9,
		nearSeconds = 2.5,
		fold = 0.25,
		distance = 18,
		glide = 0.35,
		cooldown = { 7, 5 },
	},

	totality = {
		hem = 10,
		ring = { 8, 11 },
		columns = 16,
		cap = 16,
		warn = 1.4,
		settle = 1.6,
		haloMax = 12,
	},

	nova = {
		radius = 26,
		channel = 2.4,
		hold = 0.15,
		damage = 24,
		scorch = { 9, 12 },
		columns = 16,
		cap = 24,
		recover = 3,
	},

	halo = {
		radius = 8.5,
		spin = 0.9,
		lift = 1.5,
		size = 3.2,
	},

	-- Leaving: nobody near it for this long.
	giveUpSeconds = 14,
	giveUpRange = 360,
	leaveRise = 70,
	leaveSeconds = 2.4,
}

-- What it does, in order, by phase. Lunge and Veil Step are not in the
-- cycle: they answer what the player is doing, between its turns.
local CYCLES = {
	{ "spiral", "lance", "beam", "spiral", "lance" },
	{ "lance", "spiral", "beam", "lance", "beam" },
}

local ATTACK_NAMES = {
	spiral = "Umbral Maelstrom",
	lance = "Eclipse Judgment",
	beam = "Worldrend",
	volley = "Crescent Volley",
	moonfall = "Moonfall",
	fissure = "Umbral Fissure",
	lunge = "Crescent Lunge",
	step = "Veil Step",
	totality = "Totality",
	nova = "Eclipse Nova",
}

-- Points on the rig, in RootPart space, from the export's pivots: where the
-- sleeves meet, the clasp on the chest, and the eyes in the hood.
local HANDS = CFrame.new(0, -0.6, -3.6)
local CLASP = CFrame.new(0, 1.6, -3.1)
local EYES = CFrame.new(0, 5.6, -2.7)

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

-- Who an aimed spell goes for: the one it has gone for least recently, with
-- enough randomness that it is not a round robin you can count.
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

-- Another living player than `first`, for a second sigil or a second crack.
local function otherPlayer(entry, first: Player?): Player?
	local best, bestScore = nil, -math.huge
	for _, player in ipairs(livingPlayers()) do
		if player ~= first and rootOf(player) then
			local score = math.random()
			if score > bestScore then
				best, bestScore = player, score
			end
		end
	end
	return best
end

-- Damage with a memory: each `key` hits a player once, and one cast never
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

local function playersInCircle(centre: Vector3, radius: number): { Player }
	local found = {}
	local squared = radius * radius
	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root then
			local offset = root.Position - centre
			local flat = Vector3.new(offset.X, 0, offset.Z)
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
-- Effects: the server half
-- ---------------------------------------------------------------------------

-- These are invisible replicated carriers, never rendered geometry. The client
-- draws authored pack particles/beams on them, including for late observers.
local function newPart(size: Vector3, color: Color3, transparency: number, kind: string?): Part
 local part = Instance.new("Part")
 part.Name = "SignusFX_" .. (kind or "Charge")
 part.Size = size
 part.Color = color
 part.Transparency = 1
 part.Anchored = true
 part.CanCollide = false
 part.CanQuery = false
 part.CanTouch = false
 part.CastShadow = false
 part:SetAttribute("SignusKind",kind or "Charge")
 local opacity=Instance.new("NumberValue")
 opacity.Name="FXOpacity";opacity.Value=1-transparency;opacity.Parent=part
 CollectionService:AddTag(part,"SignusVisual")
 return part
end

local function tweenFX(scope,part,info,goals)
 local values=table.clone(goals)
 if values.Transparency~=nil then
  scope:tween(part.FXOpacity,info,{Value=1-values.Transparency})
  values.Transparency=nil
 end
 if next(values) then scope:tween(part,info,values) end
end

-- A Cylinder's length runs along X, so it is turned on its side to lie flat.
local function newDisc(centre: Vector3, radius: number, color: Color3, transparency: number): Part
	local disc = newPart(Vector3.new(0.2, radius * 2, radius * 2), color, transparency, "Disc")
	disc.Shape = Enum.PartType.Cylinder
	disc.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = workspace
	return disc
end

local function newLight(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
	return light
end

-- Asks every client near enough to draw a burst. See SignusVFX for the kinds.
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

-- One invisible carrier per complete arc replaces the old neon segments.
local function makeArc(scope, _count: number, color: Color3, transparency: number): { Part }
 local part=newPart(Vector3.one*.1,color,transparency,"Ring")
 part.Parent=workspace;scope:add(part)
 return {part}
end

local function layArc(parts: {Part}, frame: CFrame, radius: number, _from: number, _to: number, _thick: number, taper: boolean?)
 local part=parts[1]
 if not part then return end
 part.Size=Vector3.new(math.max(.1,radius*2),math.max(.1,radius*2),.1)
 part.CFrame=frame
 part:SetAttribute("SignusKind",if taper then "Crescent" else "Ring")
end

-- A frame lying flat on the ground at `centre`, turned by `spin`, whose local
-- XY plane is the world XZ plane.
local function groundFrame(centre: Vector3, spin: number): CFrame
	return CFrame.new(centre) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, 0, spin)
end

local TAU = math.pi * 2

local function layRing(parts: { Part }, centre: Vector3, radius: number, spin: number, thick: number)
	layArc(parts, groundFrame(centre, spin), radius, 0, TAU, thick)
end

local function flare(_scope, centre: Vector3, radius: number, seconds: number, color: Color3)
 fx("flare",centre,{radius=radius,seconds=seconds,color=color})
end

-- A steady stream of motes on a part: the only emitters the server makes,
-- and only ever Enabled ones, which replicate as a property.
local function moteStream(parent: Instance, color: Color3, rate: number, size: number, speed: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://11187840108" -- supplied pack embers
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Colors.pearl),
		ColorSequenceKeypoint.new(1, color),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = rate
	emitter.Acceleration = Vector3.new(0, 3, 0)
	emitter.Drag = 2
	emitter.Parent = parent
	return emitter
end

-- The server still removes the exact terrain cells. Their absorption is
-- presented as particle rock shards and violet streams, not cloned blocks.
local function broadcastDebris(centre: Vector3, blocks, seconds: number)
 if #blocks>0 then fx("harvest",centre,{blocks=blocks,seconds=seconds}) end
end

-- ---------------------------------------------------------------------------
-- The sky
-- ---------------------------------------------------------------------------

--[[
	While it lives the world cools toward violet twilight, and goes to eclipse
	in phase two. A ColorCorrectionEffect in Lighting, left in place neutral
	when the fight ends so a second Signus cannot have its sky deleted from
	under it. It never touches the clock.
]]
local SKY = {
	[1] = { TintColor = Color3.fromRGB(230, 220, 255), Saturation = -0.08, Contrast = 0.02, Brightness = 0 },
	[2] = { TintColor = Color3.fromRGB(196, 168, 236), Saturation = -0.24, Contrast = 0.1, Brightness = -0.06 },
	clear = { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 },
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

-- ---------------------------------------------------------------------------
-- Sight and ground
-- ---------------------------------------------------------------------------

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Include

--[[
	The first block between two points, or nil when the line is clear. Only
	the terrain is tested, and placed blocks ARE terrain, so a wall somebody
	built is cover exactly as a hillside is.
]]
local function sightBlock(from: Vector3, to: Vector3): RaycastResult?
	local folder = workspace:FindFirstChild("GeneratedTerrain")
	if not folder then
		return nil
	end
	sightParams.FilterDescendantsInstances = { folder }
	return workspace:Raycast(from, to - from, sightParams)
end

local function groundUnder(position: Vector3): Vector3
	return Vector3.new(position.X, EnemyService.groundAt(position.X, position.Z, position.Y), position.Z)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

-- Turns a flat direction toward another by at most `maxRadians`.
local function turnFlat(from: Vector3, to: Vector3, maxRadians: number): Vector3
	from = flat(from)
	to = flat(to)
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxRadians then
		return to
	end
	local sign = if from:Cross(to).Y >= 0 then 1 else -1
	return (CFrame.Angles(0, sign * maxRadians, 0) * from).Unit
end

-- Turns a 3D direction toward another by at most `maxRadians`, for a
-- homing crescent.
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
		return from
	end
	return (CFrame.fromAxisAngle(axis.Unit, maxRadians) * from).Unit
end

-- ---------------------------------------------------------------------------
-- Where it is, and how it stands
-- ---------------------------------------------------------------------------

-- The pivot's height above the ground for a given hem clearance.
local function pivotHeight(entry, ground: Vector3, hem: number): number
	return ground.Y + entry.feetOffset + hem
end

--[[
	Poses the model from its position and flat look, plus the bob, the lean
	and any extra turn. The one place the RootPart moves. EnemyService's
	orient (modelRotation) is applied last; it is zero for this rig.
]]
local function applyPose(entry, extra: CFrame?)
	local position = entry.position + Vector3.new(0, entry.bob or 0, 0)
	local frame = CFrame.lookAt(position, position + flat(entry.look))
		* CFrame.Angles(entry.lean or 0, 0, entry.roll or 0)
	if extra then
		frame *= extra
	end
	entry.model:PivotTo(frame * (entry.orient or CFrame.identity))
	if entry.aura then entry.aura.CFrame=entry.model:GetPivot() end
end

-- A point on the rig, in the world, from its RootPart-space offset.
local function rigPoint(entry, offset: CFrame): Vector3
	return (entry.model:GetPivot() * offset).Position
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
-- The rig: procedural poses on the joints
-- ---------------------------------------------------------------------------

local JOINTS = {
	core = "CoreJoint",
	hood = "HoodJoint",
	left = "LeftSleeveJoint",
	right = "RightSleeveJoint",
}

--[[
	Casting poses, as offsets from each joint's resting C0.

	A sleeve hangs below its shoulder hinge, so a negative pitch raises it
	forward; a hood sits above its hinge, so a positive pitch tips it forward.
	Roll moves the sleeves out to the sides: negative for the left one,
	positive for the right.

	Only used for a move whose published track is missing. C0 replicates, so
	every client sees the pose; Motor6D.Transform would not. Each change is a
	short tween, and a new pose cancels the previous tween, so poses never
	race each other.
]]
local function sleeves(pitch: number, out: number, extra: { [string]: CFrame }?)
	local pose = {
		left = CFrame.Angles(pitch, 0, -out),
		right = CFrame.Angles(pitch, 0, out),
	}
	if extra then
		for key, value in pairs(extra) do
			pose[key] = value
		end
	end
	return pose
end

local POSES = {
	rest = {},
	gather = sleeves(-1.25, 0.15, { hood = CFrame.Angles(-0.18, 0, 0) }),
	release = sleeves(-0.85, 0.55, { hood = CFrame.Angles(0.22, 0, 0), core = CFrame.Angles(0.08, 0, 0) }),
	raise = sleeves(-2.6, 0.45, { hood = CFrame.Angles(-0.3, 0, 0) }),
	slam = sleeves(-0.3, 0.95, { hood = CFrame.Angles(0.35, 0, 0), core = CFrame.Angles(0.15, 0, 0) }),
	lunge = sleeves(1.1, 0.6, { hood = CFrame.Angles(0.3, 0, 0) }),
	droop = sleeves(0.15, 0.5, { hood = CFrame.Angles(0.4, 0, 0), core = CFrame.Angles(0.1, 0, 0) }),
	channel = sleeves(-1.6, 1.2, { hood = CFrame.Angles(-0.25, 0, 0) }),
	stepFold = sleeves(-0.4, -0.3, { hood = CFrame.Angles(0.15, 0, 0) }),
}

-- Which published track stands in for each procedural pose.
local POSE_TRACK = {
	gather = "Cast",
	release = "Cast",
	raise = "Cast",
	slam = "Cast",
	channel = "Cast",
	lunge = "Lunge",
	droop = "Hover",
	stepFold = "Hover",
	rest = "Hover",
}

local function findRig(entry)
	local motors, rest = {}, {}
	for key, name in pairs(JOINTS) do
		local motor = entry.model:FindFirstChild(name, true)
		if motor and motor:IsA("Motor6D") and motor.Part1 ~= entry.root then
			motors[key] = motor
			rest[key] = motor.C0
		end
	end
	entry.rig = { motors = motors, rest = rest }
end

--[[
	Moves the joints to a named pose over `seconds`, unless the published
	track that covers it exists - then the track is played instead (once per
	call for a one-shot, left alone for the loop) and the joints are not
	touched, so the two never fight.
]]
local function setPose(entry, name: string, seconds: number)
	local pose = POSES[name] or POSES.rest
	local trackName = POSE_TRACK[name]
	local animator = entry.animator

	if animator and trackName and animator:has(trackName) then
		-- A one-shot already running covers the whole move: gather and
		-- release are two poses here but one published Cast.
		if trackName ~= "Hover" and not animator:isPlaying(trackName) then
			animator:play(trackName, { fadeTime = 0.08 })
		end
		return
	end

	local rig = entry.rig
	if not rig then
		return
	end

	if entry.poseScope then
		entry.poseScope:destroy()
	end
	local scope = AbilityScope.new()
	entry.poseScope = scope

	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for key, motor in pairs(rig.motors) do
		if motor.Parent then
			scope:tween(motor, info, { C0 = rig.rest[key] * (pose[key] or CFrame.identity) })
		end
	end
end

-- A short jolt of the core when hit, if there is no Hurt track.
local function flinch(entry)
	local animator = entry.animator
	if animator and animator:has("Hurt") then
		animator:play("Hurt", { fadeTime = 0.05 })
		return
	end
	local rig = entry.rig
	local motor = rig and rig.motors.core
	if not (motor and motor.Parent) then
		return
	end
	local base = motor.C0
	local side = if math.random() < 0.5 then -1 else 1
	local tween = TweenService:Create(motor, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
		C0 = base * CFrame.Angles(0.05, 0, side * 0.07),
	})
	tween:Play()
end

-- ---------------------------------------------------------------------------
-- Attack plumbing
-- ---------------------------------------------------------------------------

-- Waits, unless it is finished. False if the fight ended during the wait.
local function pause(entry, seconds: number): boolean
	local deadline = os.clock() + seconds
	repeat
		if entry.signusFinished then
			return false
		end
		task.wait()
	until os.clock() >= deadline
	return not entry.signusFinished
end

local function phaseOf(entry): number
	return if entry.health / entry.def.health <= Tuning.phase2At then 2 else 1
end

local function setBossPhase(entry, text: string?)
	entry.bossPhase = text
	BossService.update(entry)
end

-- A glowing orb held between the sleeves for as long as `scope` lives.
local function handOrb(entry, scope, color: Color3, size: number): Part
	local orb = newPart(Vector3.one * size, color, 0.1)
	orb.Shape = Enum.PartType.Ball
	orb.Position = rigPoint(entry, HANDS)
	orb.Parent = workspace
	scope:add(orb)
	newLight(orb, color, 18, 2)
	moteStream(orb, color, 30, 0.9, 5)
	scope:spawn(function()
		while orb.Parent and not entry.signusFinished do
			orb.Position = rigPoint(entry, HANDS)
			task.wait()
		end
	end)
	return orb
end

-- ---------------------------------------------------------------------------
-- The halo and the eclipse: phase two's persistent spectacle
-- ---------------------------------------------------------------------------

-- Fragments of ground it tore up, kept in orbit. Cosmetic parts made from
-- the excavation samples; the blocks themselves are gone.
local function addHalo(entry, samples, count: number)
	local halo = entry.halo
	if not halo then
		return
	end
	local scope = entry.encounterScope
	local H = Tuning.halo
	for index = 1, math.min(count, #samples) do
		if #halo.parts >= Tuning.totality.haloMax then
			break
		end
		local fragment = newPart(Vector3.one,Colors.violet,.1,"Halo")
		fragment.Size = Vector3.one * H.size
		fragment.CFrame = CFrame.new(samples[index].position)
		fragment.Parent = workspace
		scope:add(fragment)
		newLight(fragment, Colors.violet, 9, 0.8)
		table.insert(halo.parts, {
			part = fragment,
			angle = math.random() * TAU,
			lift = (math.random() - 0.5) * 2 * H.lift,
			from = fragment.Position,
			bornAt = os.clock(),
		})
	end
end

local function stepHalo(entry, dt: number)
	local halo = entry.halo
	if not halo or #halo.parts == 0 then
		return
	end
	local H = Tuning.halo
	halo.spin += dt * H.spin * (halo.speed or 1)
	local now = os.clock()
	for _, fragment in ipairs(halo.parts) do
		local part = fragment.part
		if not part.Parent then
			continue
		end
		local angle = fragment.angle + halo.spin
		local orbit = entry.position + Vector3.new(math.cos(angle) * H.radius, fragment.lift, math.sin(angle) * H.radius)
		-- Newly taken fragments rise into orbit over a second rather than
		-- appearing there.
		local alpha = math.clamp((now - fragment.bornAt) / 1.1, 0, 1)
		local eased = alpha * alpha * (3 - 2 * alpha)
		local position = fragment.from:Lerp(orbit, eased)
		part.CFrame = CFrame.new(position) * CFrame.Angles(halo.spin * 0.7, angle, halo.spin * 0.3)
	end
end

-- Hurls every fragment outward and destroys it: the Nova spends the halo.
local function spendHalo(entry, scope)
	local halo = entry.halo
	if not halo then
		return
	end
	for _, fragment in ipairs(halo.parts) do
		local part = fragment.part
		if part.Parent then
			local away = flat(part.Position - entry.position)
			tweenFX(scope,part, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(part.Position + away * 34 + Vector3.new(0, 6, 0)) * CFrame.Angles(2, 1, 0),
				Transparency = 1,
			})
			Debris:AddItem(part, 0.8)
		end
	end
	halo.parts = {}
end

-- The black sun that hangs over phase two: a void disc inside a corona,
-- facing the fight, turning slowly. Built once in Totality.
local function buildEclipse(entry)
 local visual=newPart(Vector3.new(22,22,.1),Colors.orchid,0,"Eclipse")
 visual.CFrame=CFrame.new(entry.position+Vector3.new(0,38,0))
 visual.Parent=workspace;entry.encounterScope:add(visual)
 entry.eclipse={visual=visual}
end

local function stepEclipse(entry,_dt: number)
 if entry.eclipse and entry.eclipse.visual.Parent then
  entry.eclipse.visual.CFrame=CFrame.new(entry.position+Vector3.new(0,38,0))
 end
end

-- ---------------------------------------------------------------------------
-- The spells
-- ---------------------------------------------------------------------------

--[[
	CRESCENT VOLLEY

	It tilts back, the sleeves rise, and a lunar orb kindles between them.
	Crescents fan out around the orb, turning, and are flung one after
	another, each locking its line the instant it leaves. Any block stops
	one; in phase two there are five and they bend after you.
]]
local function volley(entry, phase: number)
	local V = Tuning.volley
	local scope = entry.scope

	local target = pickTarget(entry) or nearestPlayer(entry.position)
	if not livingRoot(target) then
		return
	end
	entry.focus = target
	entry.motion = "hold"
	entry.leanGoal = -0.12

	setPose(entry, "gather", 0.4)
	local orb = handOrb(entry, scope, Colors.orchid, 0.6)
	tweenFX(scope,orb, TweenInfo.new(V.gather, Enum.EasingStyle.Quad), { Size = Vector3.one * 2.2 })

	-- The crescents, forming around the orb.
	local count = V.count[phase]
	local crescents = {}
	for index = 1, count do
		local parts = makeArc(scope, V.segments, Colors.orchid, 0.1)
		local middle = parts[1]
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 1.4, 0)
		a0.Parent = middle
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -1.4, 0)
		a1.Parent = middle
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Colors.pearl),
			ColorSequenceKeypoint.new(1, Colors.violet),
		})
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Texture = "rbxassetid://12781812529" -- supplied aura ribbon
		trail.Lifetime = 0.35
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.LightEmission = 1
		trail.Enabled = false
		trail.Parent = middle
		crescents[index] = {
			parts = parts,
			trail = trail,
			fan = (index - (count + 1) * 0.5) * (0.5 / math.max(1, count - 1)) * 2,
			state = "form",
			spin = math.random() * TAU,
		}
	end

	-- GATHER: the crescents grow in a fan in front of the orb.
	local began = os.clock()
	while os.clock() - began < V.gather do
		if entry.signusFinished then
			return
		end
		local alpha = math.clamp((os.clock() - began) / V.gather, 0, 1)
		local eased = alpha * alpha * (3 - 2 * alpha)
		local pivot = entry.model:GetPivot()
		for _, crescent in ipairs(crescents) do
			if crescent.state == "form" then
				crescent.spin += 0.05
				local offset = CFrame.new(math.sin(crescent.fan) * 4.5, 0.5 + math.cos(crescent.fan) * 1.5, -5.5)
				local frame = pivot * HANDS * offset * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(crescent.spin, 0, 0)
				layArc(crescent.parts, frame, V.radius * eased, math.pi * 0.55, math.pi * 1.45, 0.45 * eased + 0.05, true)
			end
		end
		task.wait()
	end

	-- RELEASE, one after another; each flies in its own thread.
	setPose(entry, "release", 0.12)
	entry.leanGoal = 0.1
	fx("cast", rigPoint(entry, HANDS), { color = Colors.orchid })

	local ledger = {}
	local flying = 0

	local function fly(crescent, index: number)
		local root = livingRoot(target) or rootOf((nearestPlayer(entry.position)))
		local middle = crescent.parts[1]
		local position = middle.Position
		local aim = if root then root.Position + Vector3.new(0, 1.5, 0) else position + flat(entry.look) * 40
		local direction = (aim - position).Unit
		local homing = math.rad(V.homing[phase])
		crescent.state = "fly"
		crescent.trail.Enabled = true

		local launched = os.clock()
		local last = launched
		local spin = crescent.spin
		while os.clock() - launched < V.life do
			if entry.signusFinished then
				return
			end
			local now = os.clock()
			local dt = math.min(now - last, 0.1)
			last = now

			if homing > 0 and livingRoot(target) then
				local victim = rootOf(target)
				direction = turnToward(direction, (victim.Position + Vector3.new(0, 1.5, 0)) - position, homing * dt)
			end

			local next_ = position + direction * V.speed * dt
			local hit = sightBlock(position, next_)
			if hit then
				fx("shatter", hit.Position, { color = Colors.orchid, normal = hit.Normal })
				break
			end

			local struck = false
			for _, player in ipairs(livingPlayers()) do
				local victim = rootOf(player)
				if victim and (victim.Position - next_).Magnitude <= V.hitRadius then
					hitOnce(ledger, "crescent" .. index, player, V.damage, V.cap)
					fx("shatter", victim.Position, { color = Colors.pearl })
					struck = true
				end
			end
			if struck then
				break
			end

			position = next_
			spin += dt * 9
			local frame = CFrame.lookAt(position, position + direction) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(spin, 0, 0)
			layArc(crescent.parts, frame, V.radius, math.pi * 0.55, math.pi * 1.45, 0.5, true)
			task.wait()
		end

		for _, part in ipairs(crescent.parts) do
			part:Destroy()
		end
		flying -= 1
	end

	for index, crescent in ipairs(crescents) do
		flying += 1
		scope:spawn(function()
			fly(crescent, index)
		end)
		if not pause(entry, V.gap) then
			return
		end
	end

	tweenFX(scope,orb, TweenInfo.new(0.3), { Size = Vector3.one * 0.2, Transparency = 1 })
	setPose(entry, "rest", 0.5)
	entry.leanGoal = 0

	-- The last crescent lands before the scope goes.
	local deadline = os.clock() + V.life + 0.2
	while flying > 0 and os.clock() < deadline do
		if not pause(entry, 0.05) then
			return
		end
	end
	pause(entry, V.recover)
end

--[[
	THE LUNAR SIGIL: two rings, six ticks and a turning crescent, pearl on
	violet. Made once and re-laid as it tracks, swells and locks.
]]
local function makeSigil(scope)
 local carrier=newPart(Vector3.one*.1,Colors.orchid,.2,"Sigil")
 carrier.Parent=workspace;scope:add(carrier)
 return {outer={carrier},spin=0}
end

local function laySigil(sigil,centre: Vector3,radius: number,spin: number,bright: number)
 local carrier=sigil.outer[1]
 carrier.Size=Vector3.new(radius*2,radius*2,.1)
 carrier.CFrame=groundFrame(centre+Vector3.new(0,.25,0),spin)
 carrier.FXOpacity.Value=.65+bright*.35
end

-- Flat marks on the cells an excavation will take: the honest half of a
-- terrain telegraph. Returns the marks so a spell can light them in order.
local function markCells(scope, plan, color: Color3, transparency: number): { Part }
	local marks = {}
	for index, cell in ipairs(plan) do
		local mark = newPart(Vector3.new(STUD_SIZE * 0.9, 0.18, STUD_SIZE * 0.9), color, transparency, "Mark")
		mark.Position = cell.position + Vector3.new(0, STUD_SIZE * 0.5 + 0.1, 0)
		mark.Parent = workspace
		scope:add(mark)
		marks[index] = mark
	end
	return marks
end

--[[
	MOONFALL

	A sigil opens under you and follows you for a moment, then LOCKS: the
	outer ring snaps in to the real radius, the crater's cells are chosen and
	marked, and a pillar of light drops from the sky. A shard of the moon
	comes down it. The stone it breaks out streams up into Signus's clasp and
	joins its halo.
]]
local function moonShard(entry, scope, target: Player?, ledger, key: string, phase: number)
	local M = Tuning.moonfall
	local root = livingRoot(target) or rootOf((nearestPlayer(entry.position)))
	if not root then
		return
	end

	local sigil = makeSigil(scope)
	local centre = groundUnder(root.Position)

	-- TRACK.
	local began = os.clock()
	while os.clock() - began < M.track do
		if entry.signusFinished then
			return
		end
		local alpha = math.clamp((os.clock() - began) / M.track, 0, 1)
		local victim = livingRoot(target)
		if victim then
			centre = groundUnder(victim.Position)
		end
		sigil.spin += 0.04
		laySigil(sigil, centre, M.radius * (1.25 - 0.25 * alpha) * (0.3 + 0.7 * alpha), sigil.spin, alpha * 0.5)
		task.wait()
	end

	-- LOCK. The crater is planned now, before its cells are marked.
	fx("lock", centre, { radius = M.radius })
	local columns = {}
	for dx = -1, 1 do
		for dz = -1, 1 do
			table.insert(columns, {
				x = centre.X + dx * STUD_SIZE,
				z = centre.Z + dz * STUD_SIZE,
				y = centre.Y,
				depth = M.depth[phase],
			})
		end
	end
	local plan = TerrainManager:PlanExcavation(columns, { maxCells = M.cap_cells[phase] })
	local marks = markCells(scope, plan, Colors.pearl, 0.55)

	-- The pillar from the sky, and the shard at the top of it.
	local top = centre + Vector3.new(0, 70, 0)
	local pillar = newPart(Vector3.new(0.6, 70, 0.6), Colors.pearl, 0.6, "Pillar")
	pillar.CFrame = CFrame.new(centre:Lerp(top, 0.5))
	pillar.Parent = workspace
	scope:add(pillar)
	tweenFX(scope,pillar, TweenInfo.new(M.fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = Vector3.new(3.2, 70, 3.2),
		Transparency = 0.25,
	})
	local shard = newPart(Vector3.new(2.4, 11, 2.4), Colors.pearl, 0.05, "Shard")
	shard.Shape = Enum.PartType.Ball
	shard.CFrame = CFrame.new(top)
	shard.Parent = workspace
	scope:add(shard)
	newLight(shard, Colors.orchid, 30, 3)
	moteStream(shard, Colors.orchid, 50, 1.4, 8)
	tweenFX(scope,shard, TweenInfo.new(M.fall, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		CFrame = CFrame.new(centre + Vector3.new(0, 2, 0)),
	})

	began = os.clock()
	while os.clock() - began < M.fall do
		if entry.signusFinished then
			return
		end
		local alpha = (os.clock() - began) / M.fall
		sigil.spin += 0.09 + alpha * 0.1
		laySigil(sigil, centre, M.radius * (1 + math.sin(alpha * TAU * 3) * 0.03), sigil.spin, 0.5 + alpha * 0.5)
		for _, mark in ipairs(marks) do
			mark.FXOpacity.Value = 1-(0.55 - alpha * 0.4)
		end
		task.wait()
	end

	-- IMPACT.
	for _, player in ipairs(playersInCircle(centre, M.radius)) do
		hitOnce(ledger, key, player, M.damage, M.cap)
	end
	shard:Destroy()
	pillar:Destroy()
	for _, part in ipairs(sigil.outer) do
		part.FXOpacity.Value = 1-(1)
	end
	fx("impact", centre, { radius = M.radius })
	flare(scope, centre + Vector3.new(0, 1, 0), M.radius * 0.8, 0.4, Colors.pearl)

	local removed, samples = TerrainManager:ExecuteExcavation(plan)
	for _, mark in ipairs(marks) do
		mark:Destroy()
	end
	if removed > 0 then
		broadcastDebris(rigPoint(entry, CLASP), samples, 0.8)
		addHalo(entry, samples, math.min(removed, M.halo))
	end
end

local function moonfall(entry, phase: number)
	local M = Tuning.moonfall
	local scope = entry.scope

	local target = pickTarget(entry) or nearestPlayer(entry.position)
	if not livingRoot(target) then
		return
	end
	entry.focus = target
	entry.motion = "hold"
	entry.hem = M.hem
	entry.leanGoal = -0.18

	setPose(entry, "raise", 0.5)
	local orb = handOrb(entry, scope, Colors.pearl, 1.2)
	fx("cast", rigPoint(entry, HANDS), { color = Colors.pearl })

	local ledger = {}
	local running = 1
	if M.sigils[phase] > 1 then
		local second = otherPlayer(entry, target) or target
		running += 1
		scope:spawn(function()
			pause(entry, 0.3)
			moonShard(entry, scope, second, ledger, "shard2", phase)
			running -= 1
		end)
	end
	moonShard(entry, scope, target, ledger, "shard1", phase)
	running -= 1

	while running > 0 do
		if not pause(entry, 0.05) then
			return
		end
	end

	tweenFX(scope,orb, TweenInfo.new(0.3), { Size = Vector3.one * 0.2, Transparency = 1 })
	setPose(entry, "rest", 0.5)
	entry.hem = Tuning.hover.hem
	entry.leanGoal = 0
	pause(entry, M.recover)
end

--[[
	UMBRAL FISSURE

	It drops to the ground, sweeps its sleeves up over its hood and slams
	them down. From its hem a crack races at you: every sampled point along
	the line is marked, and every natural cell among them gets a pearl seam
	that lights in sequence. Then the line erupts in order: the planned cells
	are torn out and flung upward, and anyone standing on the line, within
	six and a half studs of the ground, is hit. Standing two blocks up is
	safety; so is stepping off the line.
]]
local function planCrack(entry, scope, from: Vector3, direction: Vector3, length: number)
	local F = Tuning.fissure
	local points, columns = {}, {}
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local index = 0
	for distance = F.start, length, STUD_SIZE do
		index += 1
		local jag = side * ((index % 2 == 0) and STUD_SIZE * 0.45 or -STUD_SIZE * 0.45) * ((index % 3 == 0) and 1 or 0.5)
		local point = groundUnder(from + direction * distance + jag)
		table.insert(points, point)
		table.insert(columns, { x = point.X, z = point.Z, y = point.Y, depth = 1 })
	end
	if #points == 0 then
		return nil
	end

	local plan = TerrainManager:PlanExcavation(columns, { maxCells = F.cap })

	-- Every point is marked: the line is the danger whatever is under it.
	local marks = {}
	for i, point in ipairs(points) do
		local mark = newPart(Vector3.new(STUD_SIZE * 0.8, 0.16, STUD_SIZE * 0.8), Colors.violet, 0.6, "Mark")
		mark.CFrame = CFrame.new(point + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, (i % 2) * 0.3, 0)
		mark.Parent = workspace
		scope:add(mark)
		marks[i] = mark
	end

	-- And the cells that will go get a seam along the crack.
	local seams = {}
	for i, cell in ipairs(plan) do
		cell.along = (cell.position - from):Dot(direction)
		local seam = newPart(Vector3.new(0.3, 0.22, STUD_SIZE * 1.05), Colors.pearl, 0.6, "Seam")
		seam.CFrame = CFrame.lookAt(cell.position + Vector3.new(0, STUD_SIZE * 0.5 + 0.16, 0), cell.position + direction + Vector3.new(0, STUD_SIZE * 0.5 + 0.16, 0))
		seam.Parent = workspace
		scope:add(seam)
		seams[i] = seam
	end
	table.sort(plan, function(a, b)
		return a.along < b.along
	end)

	return { points = points, plan = plan, marks = marks, seams = seams, from = from, direction = direction }
end

local function fissure(entry, phase: number)
	local F = Tuning.fissure
	local scope = entry.scope

	local target = pickTarget(entry) or nearestPlayer(entry.position)
	local root = livingRoot(target)
	if not root then
		return
	end
	entry.focus = target
	entry.motion = "ground"
	entry.leanGoal = -0.2

	-- RAISE: sleeves up over the hood, the hem settling to the floor.
	setPose(entry, "raise", F.raise)
	local orb = handOrb(entry, scope, Colors.violet, 1.4)
	if not pause(entry, F.raise) then
		return
	end

	-- SLAM, and the crack is planned from where it now stands.
	setPose(entry, "slam", 0.12)
	entry.leanGoal = 0.25
	local from = groundUnder(entry.position)
	flare(scope, from + Vector3.new(0, 0.5, 0), 9, 0.5, Colors.violet)
	fx("cast", from + Vector3.new(0, 0.5, 0), { color = Colors.violet })
	tweenFX(scope,orb, TweenInfo.new(0.2), { Size = Vector3.one * 0.2, Transparency = 1 })

	local toward = flat(root.Position - from)
	local length = math.min((root.Position - from).Magnitude + 8, F.length)
	local cracks = {}
	local first = planCrack(entry, scope, from, toward, length)
	if first then
		table.insert(cracks, first)
	end
	if F.cracks[phase] > 1 then
		local second = otherPlayer(entry, target)
		local secondRoot = second and livingRoot(second)
		local direction
		if secondRoot and flat(secondRoot.Position - from):Dot(toward) < 0.8 then
			direction = flat(secondRoot.Position - from)
		else
			local sign = if math.random() < 0.5 then -1 else 1
			direction = (CFrame.Angles(0, math.rad(F.fan) * sign, 0) * toward).Unit
		end
		local crack = planCrack(entry, scope, from, direction, length)
		if crack then
			table.insert(cracks, crack)
		end
	end
	if #cracks == 0 then
		pause(entry, F.recover)
		return
	end

	-- WARN: the seams light in order as the crack runs out.
	local began = os.clock()
	while os.clock() - began < F.warn do
		if entry.signusFinished then
			return
		end
		local alpha = (os.clock() - began) / F.warn
		local pulse = 0.5 + 0.5 * math.sin(alpha * alpha * 40)
		for _, crack in ipairs(cracks) do
			local reach = alpha * 1.25
			for i, mark in ipairs(crack.marks) do
				local t = i / #crack.marks
				mark.FXOpacity.Value = 1-(if t <= reach then 0.35 - pulse * 0.15 else 0.65)
			end
			for i, seam in ipairs(crack.seams) do
				local t = i / #crack.seams
				seam.FXOpacity.Value = 1-(if t <= reach then 0.05 + (1 - alpha) * 0.3 else 0.6)
			end
		end
		task.wait()
	end

	-- ERUPT. The ground goes now, all of it, exactly as planned; the
	-- eruption is drawn and the line is checked cell by cell in order.
	local ledger = {}
	for _, crack in ipairs(cracks) do
		local removed, samples = TerrainManager:ExecuteExcavation(crack.plan)
		local middle = crack.from + crack.direction * length * 0.5
		if removed > 0 then
			broadcastDebris(middle + Vector3.new(0, 18, 0), samples, 1.0)
		end
		for _, seam in ipairs(crack.seams) do
			seam:Destroy()
		end

		local positions, delays = {}, {}
		for i, point in ipairs(crack.points) do
			if i > 24 then
				break
			end
			positions[i] = point
			delays[i] = (i - 1) * F.stagger
		end
		fx("erupt", middle, { positions = positions, delays = delays })

		scope:spawn(function()
			for i, point in ipairs(crack.points) do
				if entry.signusFinished then
					return
				end
				for _, player in ipairs(livingPlayers()) do
					local victim = rootOf(player)
					if victim then
						local offset = victim.Position - point
						local lateral = Vector3.new(offset.X, 0, offset.Z).Magnitude
						if lateral <= F.width and offset.Y >= -3 and offset.Y <= F.safeHeight then
							hitOnce(ledger, "fissure", player, F.damage, F.damage)
						end
					end
				end
				local mark = crack.marks[i]
				if mark then
					mark.Color = Colors.pearl
					mark.FXOpacity.Value = 1-(0.1)
					tweenFX(scope,mark, TweenInfo.new(0.5), { Transparency = 1 })
				end
				task.wait(F.stagger)
			end
		end)
	end

	setPose(entry, "droop", 0.6)
	entry.leanGoal = 0.08
	pause(entry, F.stagger * 12 + F.recover)
	setPose(entry, "rest", 0.5)
	entry.leanGoal = 0
end

--[[
	CRESCENT LUNGE

	Its answer to being kept away from or hidden from. It rears back with a
	crescent blade forming edge-on at its front, eyes flaring, then dashes
	along a shallow arc. The blade cuts whoever is near its path. It arrives
	low, hem on the ground, spent, and stays there for the recovery.
]]
local function lunge(entry, _phase: number)
	local L = Tuning.lunge
	local scope = entry.scope

	local target = entry.lungeTarget or pickTarget(entry) or nearestPlayer(entry.position)
	entry.lungeTarget = nil
	local root = livingRoot(target)
	if not root then
		return
	end
	entry.focus = target
	entry.motion = "scripted"
	entry.lean = 0
	entry.bob = 0

	setPose(entry, "lunge", 0.3)

	-- The eyes, and the blade.
	local eyes = newPart(Vector3.new(2.2, 0.6, 0.6), Colors.pearl, 0.2, "Eyes")
	eyes.Parent = workspace
	scope:add(eyes)
	newLight(eyes, Colors.pearl, 20, 3)
	local blade = makeArc(scope, 9, Colors.orchid, 0.1)
	local bladeMid = blade[1]
	newLight(bladeMid, Colors.orchid, 16, 2)
	moteStream(bladeMid, Colors.orchid, 40, 1, 6)

	local function layBlade(scale: number, spin: number)
		local pivot = entry.model:GetPivot()
		local frame = pivot * CFrame.new(0, -2, -7) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(spin, 0, 0)
		layArc(blade, frame, L.bladeRadius * scale, math.pi * 0.55, math.pi * 1.45, 0.7 * scale + 0.05, true)
		eyes.CFrame = pivot * EYES
	end

	-- WIND UP: back off, locking on.
	local start = entry.position
	local began = os.clock()
	local last = began
	local direction = flat(root.Position - entry.position)
	while os.clock() - began < L.windup do
		if entry.signusFinished then
			return
		end
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		if livingRoot(target) == root then
			direction = flat(root.Position - entry.position)
		end
		entry.look = turnFlat(entry.look, direction, math.rad(360) * dt)
		local alpha = (now - began) / L.windup
		local eased = alpha * alpha * (3 - 2 * alpha)
		entry.position = start - direction * L.rearBack * eased
		entry.lean = -0.25 * eased
		applyPose(entry)
		layBlade(eased, alpha * 4)
		task.wait()
	end

	-- COMMIT: the path is fixed now, to where you are, ending low.
	if livingRoot(target) == root then
		direction = flat(root.Position - entry.position)
	end
	entry.look = direction
	local landing = groundUnder(root.Position + direction * L.overshoot)
	local goal = Vector3.new(landing.X, pivotHeight(entry, landing, 0.6), landing.Z)
	local from = entry.position
	local travel = (goal - from).Magnitude
	local seconds = math.clamp(travel / L.speed, 0.25, 1.6)
	local ledger = {}

	began = os.clock()
	last = began
	local spin = 0
	while os.clock() - began < seconds do
		if entry.signusFinished then
			return
		end
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		local alpha = math.clamp((now - began) / seconds, 0, 1)
		entry.position = from:Lerp(goal, alpha) + Vector3.new(0, math.sin(alpha * math.pi) * 3, 0)
		entry.lean = 0.35 * math.sin(alpha * math.pi)
		applyPose(entry)
		spin += dt * 12
		layBlade(1, spin)

		local cutter = entry.position - Vector3.new(0, entry.feetOffset * 0.6, 0)
		for _, player in ipairs(livingPlayers()) do
			local victim = rootOf(player)
			if victim and (victim.Position - cutter).Magnitude <= L.reach then
				hitOnce(ledger, "lunge", player, L.damage, L.damage)
			end
		end
		task.wait()
	end

	-- ARRIVAL: the blade shatters; it hangs there, spent.
	entry.position = goal
	entry.lean = 0.1
	applyPose(entry)
	fx("lunge", entry.position - Vector3.new(0, entry.feetOffset * 0.6, 0))
	for _, part in ipairs(blade) do
		part:Destroy()
	end
	eyes:Destroy()
	setPose(entry, "droop", 0.4)
	entry.motion = "ground"
	entry.leanGoal = 0.1
	pause(entry, L.recover)
	setPose(entry, "rest", 0.5)
	entry.leanGoal = 0
end

--[[
	VEIL STEP

	Hugged too long, it folds into a crescent of light and glides away along
	a curve, unfolding eighteen studs off in a ripple of motes. Never further
	than that: it buys a moment, not an escape.
]]
local function veilStep(entry, _phase: number)
	local S = Tuning.step
	local scope = entry.scope
	local near, _ = nearestPlayer(entry.position)
	local nearRoot = rootOf(near)
	local away = if nearRoot then flat(entry.position - nearRoot.Position) else -flat(entry.look)

	entry.motion = "scripted"
	setPose(entry, "stepFold", S.fold)

	-- The crescent that wraps it: upright, around the robe.
	local wrap = makeArc(scope, 11, Colors.pearl, 0.1)
	local wrapMid = wrap[1]
	newLight(wrapMid, Colors.orchid, 22, 2.5)
	local function layWrap(scale: number, spin: number)
		local pivot = entry.model:GetPivot()
		local frame = pivot * CFrame.new(0, -1, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(spin, 0, 0)
		layArc(wrap, frame, 9 * scale, math.pi * 0.5, math.pi * 1.5, 0.8 * scale, true)
	end

	local began = os.clock()
	while os.clock() - began < S.fold do
		if entry.signusFinished then
			return
		end
		local alpha = (os.clock() - began) / S.fold
		layWrap(alpha, alpha * 2)
		entry.roll = alpha * 0.2
		applyPose(entry)
		task.wait()
	end

	-- A curve to the side rather than a straight slide.
	local side = Vector3.new(-away.Z, 0, away.X) * (if math.random() < 0.5 then -1 else 1)
	local from = entry.position
	local landing = groundUnder(from + away * S.distance)
	local goal = Vector3.new(landing.X, pivotHeight(entry, landing, Tuning.hover.hem), landing.Z)

	began = os.clock()
	while os.clock() - began < S.glide do
		if entry.signusFinished then
			return
		end
		local alpha = math.clamp((os.clock() - began) / S.glide, 0, 1)
		local eased = alpha * alpha * (3 - 2 * alpha)
		entry.position = from:Lerp(goal, eased) + side * math.sin(alpha * math.pi) * 5
		entry.roll = 0.2 * (1 - alpha)
		applyPose(entry)
		layWrap(1 - alpha * 0.4, 2 + alpha * 6)
		task.wait()
	end

	entry.position = goal
	entry.roll = 0
	applyPose(entry)
	for _, part in ipairs(wrap) do
		part:Destroy()
	end
	fx("step", entry.position - Vector3.new(0, 3, 0))
	setPose(entry, "rest", 0.4)
	entry.motion = "hover"
end

--[[
	A ring of columns around a point, between two radii, for the Totality's
	halo and the Nova's scorch. Planned at once, so the caller marks exactly
	what will go.
]]
local function ringColumns(centre: Vector3, inner: number, outer: number, count: number)
	local columns = {}
	local base = math.random() * TAU
	for index = 1, count do
		local angle = base + (index - 1) / count * TAU
		local radius = inner + (outer - inner) * ((index % 3) / 2)
		local spot = groundUnder(centre + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		table.insert(columns, { x = spot.X, z = spot.Z, y = spot.Y, depth = 1 })
	end
	return columns
end

--[[
	TOTALITY

	The phase change. It rises, spreads its sleeves, and the sky goes to
	eclipse. The ring of ground beneath it is chosen and marked, cracks with
	light, and lifts into orbit around it as the Moonstone Halo. The black sun
	forms overhead and stays for the rest of the fight. Nothing here hurts
	anyone: the player just did something good.
]]
local function totality(entry, _phase: number)
	local T = Tuning.totality
	local scope = entry.scope

	entry.focus = pickTarget(entry) or entry.focus
	entry.motion = "hold"
	entry.hem = T.hem
	entry.leanGoal = -0.15

	announce("The moon swallows the sun. Signus enters Totality.", "bad")
	setBossPhase(entry, ATTACK_NAMES.totality)
	setPose(entry, "channel", 0.8)
	setSky(2, 2.5)

	local orb = handOrb(entry, scope, Colors.pearl, 1.6)
	tweenFX(scope,orb, TweenInfo.new(T.warn, Enum.EasingStyle.Quad), { Size = Vector3.one * 4 })

	local shadow = groundUnder(entry.position)
	local plan = TerrainManager:PlanExcavation(ringColumns(shadow, T.ring[1], T.ring[2], T.columns), { maxCells = T.cap })
	local marks = markCells(scope, plan, Colors.pearl, 0.5)
	local ring = makeArc(scope, 24, Colors.orchid, 0.2)

	local began = os.clock()
	while os.clock() - began < T.warn do
		if entry.signusFinished then
			return
		end
		local alpha = (os.clock() - began) / T.warn
		layRing(ring, shadow + Vector3.new(0, 0.3, 0), T.ring[2] + 1.5, alpha * 2, 0.3 + alpha * 0.4)
		for _, mark in ipairs(marks) do
			mark.FXOpacity.Value = 1-(0.5 - alpha * 0.4)
		end
		task.wait()
	end

	local removed, samples = TerrainManager:ExecuteExcavation(plan)
	for _, mark in ipairs(marks) do
		mark:Destroy()
	end
	for _, part in ipairs(ring) do
		part:Destroy()
	end
	if removed > 0 then
		broadcastDebris(rigPoint(entry, CLASP), samples, 1.2)
		addHalo(entry, samples, math.min(removed, T.haloMax))
	end

	fx("totality", entry.position, { drop = entry.position.Y - shadow.Y })
	flare(scope, entry.position, 14, 0.9, Colors.pearl)
	buildEclipse(entry)
	tweenFX(scope,orb, TweenInfo.new(0.4), { Size = Vector3.one * 0.2, Transparency = 1 })

	entry.transformed = true
	if entry.aura then entry.aura:SetAttribute("Phase",2) end
	pause(entry, T.settle)
	setPose(entry, "rest", 0.6)
	entry.hem = Tuning.hover.hem
	entry.leanGoal = 0
end

--[[
	ECLIPSE NOVA

	It comes down to the ground and channels. A sigil twenty-six studs wide
	opens under it, rings close inward across it, spokes drag toward the
	core, the halo spins faster, and the scorch ring is marked. The last
	fraction of a second is silent and the core goes black. Then it
	detonates: everyone within reach who can be SEEN from the core is hit,
	a block of any kind between you and it is enough, and the ring of ground
	around it is torn away and flung up into the dark. It hangs there spent
	afterwards, sleeves down, for three seconds.
]]
local function nova(entry, _phase: number)
	local N = Tuning.nova
	local scope = entry.scope

	entry.focus = pickTarget(entry) or entry.focus
	entry.motion = "ground"
	entry.leanGoal = -0.22
	if entry.halo then
		entry.halo.speed = 3.5
	end

	setPose(entry, "channel", 0.7)
	local orb = handOrb(entry, scope, Colors.orchid, 1.2)
	tweenFX(scope,orb, TweenInfo.new(N.channel, Enum.EasingStyle.Quad), { Size = Vector3.one * 5 })

	-- The sigil and the scorch ring, chosen and marked before anything moves.
	local centre = groundUnder(entry.position)
	local plan = TerrainManager:PlanExcavation(ringColumns(centre, N.scorch[1], N.scorch[2], N.columns), { maxCells = N.cap })
	local marks = markCells(scope, plan, Colors.pearl, 0.5)

	local outer = makeArc(scope, 28, Colors.pearl, 0.2)
	local closing1 = makeArc(scope, 20, Colors.orchid, 0.15)
	local closing2 = makeArc(scope, 16, Colors.violet, 0.15)
	local spokes = {}
	for index = 1, 12 do
		local spoke = newPart(Vector3.new(1, 0.22, 0.22), Colors.pearl, 0.4, "Spoke")
		spoke.Parent = workspace
		scope:add(spoke)
		spokes[index] = spoke
	end
	local fill = newDisc(centre + Vector3.new(0, 0.1, 0), N.radius, Colors.plum, 0.8)
	scope:add(fill)
	local core = newPart(Vector3.one * 0.5, Colors.black, 0, "Void")
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.SmoothPlastic
	core.Parent = workspace
	scope:add(core)

	local began = os.clock()
	local lifted = centre + Vector3.new(0, 0.25, 0)
	while os.clock() - began < N.channel do
		if entry.signusFinished then
			return
		end
		local alpha = (os.clock() - began) / N.channel
		local spin = alpha * 3
		layRing(outer, lifted, N.radius, spin * 0.5, 0.4 + alpha * 0.5)
		layRing(closing1, lifted + Vector3.new(0, 0.05, 0), N.radius * (1 - alpha * 0.92), -spin, 0.35)
		layRing(closing2, lifted + Vector3.new(0, 0.1, 0), N.radius * (1 - ((alpha * 1.6) % 1) * 0.9), spin * 1.3, 0.3)
		for index, spoke in ipairs(spokes) do
			local angle = spin * 0.5 + (index - 1) / 12 * TAU
			local reach = N.radius * (1 - alpha * 0.7)
			local mid = lifted + Vector3.new(math.cos(angle) * reach * 0.5, 0.08, math.sin(angle) * reach * 0.5)
			spoke.Size = Vector3.new(reach, 0.22, 0.22)
			spoke.CFrame = CFrame.new(mid) * CFrame.Angles(0, -angle, 0)
			spoke.FXOpacity.Value = 1-(0.5 - alpha * 0.4)
		end
		fill.FXOpacity.Value = 1-(0.8 - alpha * 0.3)
		for _, mark in ipairs(marks) do
			mark.FXOpacity.Value = 1-(0.5 - alpha * 0.4)
		end
		core.Position = rigPoint(entry, CLASP)
		core.Size = Vector3.one * (0.5 + alpha * 3)
		task.wait()
	end

	-- THE HELD BREATH: the orb is gone, the core is black, nothing moves.
	orb.FXOpacity.Value = 1-(1)
	for _, spoke in ipairs(spokes) do
		spoke.FXOpacity.Value = 1-(1)
	end
	if not pause(entry, N.hold) then
		return
	end

	-- DETONATION.
	local origin = rigPoint(entry, CLASP)
	for _, player in ipairs(livingPlayers()) do
		local victim = rootOf(player)
		if victim and (victim.Position - origin).Magnitude <= N.radius then
			if not sightBlock(origin, victim.Position) then
				CombatService.applyDamage(player, N.damage, SOURCE)
			end
		end
	end

	core:Destroy()
	fill:Destroy()
	for _, list in ipairs({ outer, closing1, closing2 }) do
		for _, part in ipairs(list) do
			part:Destroy()
		end
	end
	fx("nova", origin, { radius = N.radius })
	flare(scope, origin, N.radius * 0.5, 0.5, Colors.pearl)
	spendHalo(entry, scope)
	if entry.halo then
		entry.halo.speed = 1
	end

	local removed, samples = TerrainManager:ExecuteExcavation(plan)
	for _, mark in ipairs(marks) do
		mark:Destroy()
	end
	if removed > 0 then
		broadcastDebris(entry.position + Vector3.new(0, 26, 0), samples, 1.0)
	end

	-- SPENT.
	setPose(entry, "droop", 0.5)
	entry.leanGoal = 0.12
	pause(entry, N.recover)
	setPose(entry, "rest", 0.6)
	entry.leanGoal = 0
end

-- ---------------------------------------------------------------------------
-- The fight
-- ---------------------------------------------------------------------------

local referenceMoves=require(script.Parent.SignusMoves).create({
	carrier=newPart,pickTarget=pickTarget,root=livingRoot,ground=groundUnder,
	pose=setPose,pause=pause,playersInCircle=playersInCircle,players=livingPlayers,
	cover=sightBlock,hit=hitOnce,fx=fx,flat=flat,applyPose=applyPose,
	hand=function(entry) return rigPoint(entry,HANDS) end,
	sky=setSky,eclipse=buildEclipse,
})
local ATTACKS = {
	spiral = referenceMoves.spiral,
	lance = referenceMoves.lance,
	beam = referenceMoves.beam,
	lunge = lunge,
	step = veilStep,
	totality = referenceMoves.totality,
}

local function nextInCycle(entry, phase: number): string
	local cycle = CYCLES[phase]
	entry.cycleIndex = (entry.cycleIndex or 0) % #cycle + 1
	return cycle[entry.cycleIndex]
end

--[[
	One spell, start to finish, in its own thread, with everything it makes
	in a scope that goes when it ends. Totality pre-empts the cycle the first
	time it acts below half health.
]]
local function performAttack(entry, pick: string, phase: number)
	setBossPhase(entry, ATTACK_NAMES[pick])
	entry.busy = true

	local scope = AbilityScope.new()
	entry.scope = scope

	task.spawn(function()
		local ok, err = pcall(ATTACKS[pick], entry, phase)

		if entry.scope == scope then
			entry.scope = nil
		end
		scope:destroy()

		if entry.signusFinished then
			return
		end
		if not ok then
			warn("[Signus]", pick, "failed:", err)
		end

		-- Back to its ring, whatever the spell left it doing.
		entry.motion = "hover"
		entry.hem = Tuning.hover.hem
		entry.leanGoal = 0
		entry.roll = 0
		entry.velocity = Vector3.zero
		if entry.halo then
			entry.halo.speed = 1
		end
		setPose(entry, "rest", 0.5)

		local now = phaseOf(entry)
		local rest = if pick == "step" or pick == "lunge"
			then 0.3
			else math.random() * (Tuning.restMax[now] - Tuning.restMin[now]) + Tuning.restMin[now]
		entry.nextAttackAt = os.clock() + rest
		entry.busy = false
		setBossPhase(entry, nil)
	end)
end

-- Touching the robe: a short cylinder around its centre.
local function contactDamage(entry, now: number)
	local C = Tuning.contact
	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root and now - (entry.contactAt[player] or -math.huge) >= C.interval then
			local offset = root.Position - entry.position
			local lateral = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if lateral <= C.reach and math.abs(offset.Y) <= C.height then
				entry.contactAt[player] = now
				CombatService.applyDamage(player, C.damage, SOURCE)
			end
		end
	end
end

-- It rises out of sight and is gone, when there has been nobody near it.
local function leave(entry)
	entry.leaving = true
	entry.busy = true
	entry.motion = "scripted"
	setPose(entry, "rest", 0.6)
	task.spawn(function()
		local from = entry.position
		local began = os.clock()
		while os.clock() - began < Tuning.leaveSeconds do
			if entry.signusFinished then
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

--[[
	Decides whether something other than the cycle is called for: a lunge
	at someone who keeps away or hides, or a step away from someone who will
	not leave it alone. Returns the pick, or nil for the cycle.
]]
local function situational(entry, now: number, phase: number): string?
	local L = Tuning.lunge
	local S = Tuning.step

	local near, nearDistance = nearestPlayer(entry.position)
	if not near then
		return nil
	end
	local nearRoot = rootOf(near)

	if nearDistance <= S.nearDistance then
		entry.nearSince = entry.nearSince or now
	else
		entry.nearSince = nil
	end
	if entry.nearSince and now - entry.nearSince >= S.nearSeconds and now >= (entry.nextStepAt or 0) then
		entry.nearSince = nil
		entry.nextStepAt = now + S.cooldown[phase]
		return "step"
	end

	local focusRoot = livingRoot(entry.focus) or nearRoot
	local focusPlayer = if livingRoot(entry.focus) then entry.focus else near
	local far = (focusRoot.Position - entry.position).Magnitude >= L.farDistance
	local hidden = sightBlock(rigPoint(entry, EYES), focusRoot.Position) ~= nil
	if far then
		entry.farSince = entry.farSince or now
	else
		entry.farSince = nil
	end
	if hidden then
		entry.hiddenSince = entry.hiddenSince or now
	else
		entry.hiddenSince = nil
	end
	local lungeDue = (entry.farSince and now - entry.farSince >= L.farSeconds)
		or (entry.hiddenSince and now - entry.hiddenSince >= L.hiddenSeconds)
	if lungeDue and now >= (entry.nextLungeAt or 0) then
		entry.farSince = nil
		entry.hiddenSince = nil
		entry.nextLungeAt = now + L.cooldown
		entry.lungeTarget = focusPlayer
		return "lunge"
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- Death
-- ---------------------------------------------------------------------------

--[[
	THE HUSK. EnemyService destroys the model straight after finish, so the
	collapse is played on a cosmetic copy: not registered, not queryable,
	nothing a weapon or a drop roll can find. It plays the Death track when
	one is published; otherwise the hood tips, the sleeves fall and the core
	dims by tweening the copy's own joints. Either way it fades and is gone
	in two and a half seconds.
]]
local function deathHusk(entry)
	local husk = entry.model:Clone()
	husk.Name = "SignusHusk"
	for _, descendant in ipairs(husk:GetDescendants()) do
		if descendant:IsA("BillboardGui") or descendant:IsA("Highlight") or descendant:IsA("PointLight")
			or descendant:IsA("ParticleEmitter") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CanCollide = false
		end
	end
	local root = husk.PrimaryPart or husk:FindFirstChild("RootPart")
	if root then
		root.Anchored = true
	end
	husk:PivotTo(entry.model:GetPivot())
	husk.Parent = workspace
	Debris:AddItem(husk, 2.6)

	local played = false
	local ids = EnemyConfig.Animations and EnemyConfig.Animations.Signus
	local deathId = ids and ids.Death
	local controller = husk:FindFirstChildOfClass("AnimationController")
	local animator = controller and controller:FindFirstChildOfClass("Animator")
	if animator and (type(deathId) == "number" or (type(deathId) == "string" and string.match(deathId, "%d+$")
		and not string.match(deathId, "^PUBLISH"))) then
		local animation = Instance.new("Animation")
		animation.AnimationId = if type(deathId) == "number" then "rbxassetid://" .. deathId
			elseif string.match(deathId, "^rbxassetid://") then deathId
			else "rbxassetid://" .. deathId
		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.05)
			played = true
		end
	end

	local sink = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if not played then
		for key, name in pairs(JOINTS) do
			local motor = husk:FindFirstChild(name, true)
			if motor and motor:IsA("Motor6D") then
				local pose = if key == "hood" then CFrame.Angles(0.7, 0, 0.2)
					elseif key == "left" then CFrame.Angles(0.3, 0, -0.9)
					elseif key == "right" then CFrame.Angles(0.3, 0, 0.9)
					else CFrame.Angles(0.25, 0, 0)
				TweenService:Create(motor, sink, { C0 = motor.C0 * pose }):Play()
			end
		end
	end
	if root then
		TweenService:Create(root, sink, { CFrame = root.CFrame * CFrame.new(0, -3, 0) * CFrame.Angles(0.15, 0, 0) }):Play()
	end

	-- The fade, after the collapse has read.
	task.delay(0.9, function()
		for _, descendant in ipairs(husk:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant ~= root then
				TweenService:Create(descendant, TweenInfo.new(1.3, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function Signus.start(entry)
	entry.signusFinished = false
	entry.busy = false
	entry.leaving = false
	entry.transformed = false
	entry.scope = nil
	entry.poseScope = nil
	entry.encounterScope = AbilityScope.new()
	entry.motion = "hover"
	entry.focus = nil
	entry.hem = Tuning.hover.hem
	entry.lean = 0
	entry.leanGoal = 0
	entry.roll = 0
	entry.bob = 0
	entry.bobPhase = math.random() * 10
	entry.velocity = Vector3.zero
	entry.cycleIndex = 0
	entry.ringAngle = math.random() * TAU
	entry.ringSpin = if math.random() < 0.5 then -Tuning.hover.ringDrift else Tuning.hover.ringDrift
	entry.pressure = setmetatable({}, { __mode = "k" })
	entry.contactAt = setmetatable({}, { __mode = "k" })
	entry.lastSeenAt = os.clock()
	entry.lastHurtAt = 0
	entry.halo = { parts = {}, spin = 0, speed = 1 }

	local placed = entry.model:GetPivot().Position
	entry.position = placed
	local first = rootOf((nearestPlayer(placed)))
	entry.look = flat(if first then first.Position - placed else Vector3.new(0, 0, -1))
	if first then
		entry.ringAngle = math.atan2(placed.Z - first.Position.Z, placed.X - first.Position.X)
	end

	findRig(entry)
	entry.aura=newPart(Vector3.new(14,18,14),Colors.violet,0,"Aura")
	entry.aura:SetAttribute("Phase",1)
	entry.aura.Parent=workspace
	entry.encounterScope:add(entry.aura)

	local animator, reason = EnemyAnimator.new(entry.model, EnemyConfig.Animations.Signus)
	if animator then
		entry.animator = animator
		animator:play("Hover")
	else
		warn("[Signus] no animator: " .. tostring(reason))
	end

	-- Its lights: the eyes and the clasp, for as long as it lives.
	local eyeLight = newLight(entry.root, Colors.pearl, 22, 1.2)
	entry.encounterScope:add(eyeLight)
	local hood = entry.model:FindFirstChild("Hood")
	if hood and hood:IsA("BasePart") then
		local glow = newLight(hood, Colors.orchid, 14, 0.9)
		entry.encounterScope:add(glow)
	end
	local clasp = Instance.new("Attachment")
	clasp.CFrame = CLASP
	clasp.Parent = entry.root
	entry.encounterScope:add(clasp)
	local claspMotes = moteStream(clasp, Colors.teal, 6, 0.6, 2)
	claspMotes.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Colors.gold),
		ColorSequenceKeypoint.new(0.5, Colors.teal),
		ColorSequenceKeypoint.new(1, Colors.orchid),
	})

	setSky(1, 3)
	announce("A hush falls. The moon has sent its herald...", "bad")

	applyPose(entry)
	entry.nextAttackAt = os.clock() + 2.5
end

function Signus.step(entry, dt: number, now: number)
	if not entry.position then
		return
	end

	local H = Tuning.hover
	local phase = phaseOf(entry)

	entry.bobPhase += dt
	entry.bob = if entry.motion == "scripted"
		then 0
		else math.sin(entry.bobPhase * TAU / H.bobPeriod) * H.bobAmplitude
	-- A scripted move writes the lean itself; easing it here as well would
	-- fight it within the same frame.
	if entry.motion ~= "scripted" then
		entry.lean += (entry.leanGoal - entry.lean) * math.clamp(dt * H.leanRate, 0, 1)
	end

	local target = nearestPlayer(entry.position, Tuning.giveUpRange)
	if target then
		entry.lastSeenAt = now
	end

	if not entry.busy and not entry.leaving and now - entry.lastSeenAt >= Tuning.giveUpSeconds then
		leave(entry)
		return
	end

	if entry.motion ~= "scripted" then
		local focus = livingRoot(entry.focus) or rootOf(target)

		if entry.motion == "hover" and focus then
			entry.ringAngle += entry.ringSpin * dt
			local ring = focus.Position + Vector3.new(math.cos(entry.ringAngle), 0, math.sin(entry.ringAngle)) * H.ring[phase]
			local ground = groundUnder(Vector3.new(ring.X, focus.Position.Y, ring.Z))
			local goal = Vector3.new(ring.X, pivotHeight(entry, ground, entry.hem), ring.Z)
			moveToward(entry, goal, dt, H.speed[phase])
		elseif entry.motion == "hold" or entry.motion == "ground" then
			-- Still, but settling to the height the spell wants.
			local hem = if entry.motion == "ground" then 0.2 else entry.hem
			local ground = groundUnder(entry.position)
			local goalY = pivotHeight(entry, ground, hem)
			entry.velocity = Vector3.zero
			entry.position = Vector3.new(
				entry.position.X,
				entry.position.Y + (goalY - entry.position.Y) * math.clamp(dt * 3, 0, 1),
				entry.position.Z
			)
		end

		if focus then
			entry.look = turnFlat(entry.look, focus.Position - entry.position, math.rad(H.turnRate) * dt)
		end

		applyPose(entry)
	end

	stepHalo(entry, dt)
	stepEclipse(entry, dt)

	if not entry.leaving then
		contactDamage(entry, now)
	end

	if entry.busy or entry.leaving or not target then
		return
	end

	if now >= (entry.nextAttackAt or 0) then
		local pick
		if phase == 2 and not entry.transformed then
			pick = "totality"
		else
			pick = situational(entry, now, phase) or nextInCycle(entry, phase)
		end
		performAttack(entry, pick, phase)
	end
end

-- The flinch: Hurt if it is published, a jolt of the core if not. Throttled,
-- because a barrage lands fifteen times.
function Signus.damaged(entry, _dealt: number)
	if entry.signusFinished or not entry.position then
		return
	end
	local now = os.clock()
	if now - (entry.lastHurtAt or 0) < 0.45 then
		return
	end
	entry.lastHurtAt = now
	flinch(entry)
end

function Signus.finish(entry, reason: string?)
	entry.signusFinished = true
	entry.busy = false

	if entry.scope then
		entry.scope:destroy()
		entry.scope = nil
	end
	if entry.poseScope then
		entry.poseScope:destroy()
		entry.poseScope = nil
	end

	-- The death is presented BEFORE the encounter effects go, on a copy of
	-- the model as it stands now.
	if reason == "died" and entry.position then
		pcall(function()
			local shadow = groundUnder(entry.position)
			fx("death", entry.position, { drop = entry.position.Y - shadow.Y })
			deathHusk(entry)
		end)
		announce("Signus has been defeated! The eclipse passes.", "good")
	end

	if entry.encounterScope then
		entry.encounterScope:destroy()
		entry.encounterScope = nil
	end
	entry.halo = nil
	entry.eclipse = nil
	entry.aura = nil

	if entry.animator then
		entry.animator:destroy()
		entry.animator = nil
	end

	-- The sky clears, unless another of it is still out there.
	if #EnemyService.allOf(SELF) == 0 then
		setSky("clear", 3)
	end
end

-- Where the fight changes, as health fractions, for the boss bar's markers
-- (BossService sends it): two stages, Totality at half.
Signus.phases = { Tuning.phase2At }

return Signus
