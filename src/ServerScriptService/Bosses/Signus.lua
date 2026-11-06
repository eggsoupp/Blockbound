--[[
	Signus - the Hallowed Eclipse

	A hooded lunar spellcaster. It floats, it keeps its distance, and it
	fights with the ground and the sky rather than with its body.

	WHAT IT DOES (SignusMoves has the numbers)

	Phase one, the Herald: violet over black, pearl eyes.
	  UMBRAL MAELSTROM  a fixed warning tightens into coiling ribbons; terrain
	                    rises into orbit and the slam erupts, flinging it onto
	                    the rim.
	  ECLIPSE JUDGMENT  a sigil opens on the target and a sun of judgment
	                    forms over it, then falls into a towering column. Real
	                    terrain rises and lands around a lasting crater.
	  WORLDREND         a sustained beam with no end of its own: it runs until
	                    it meets a block, bores on through natural ground and
	                    fades out at its range. The aim locks before it fires.
	  UMBRAL THUNDER    a sleeve raised to the sky; marks open one by one where
	                    you are heading and violet lightning lands on each. A
	                    block overhead is cover.
	  MIRROR VEIL       it splits into itself and two fainter decoys that
	                    circle you. Strike the real one and the decoys
	                    scatter, leaving it stunned; too slow and every image
	                    calls the thunder down on you in turn.
	  VEIL STEP         a blink away from someone hugging it.

	It is a mage: it never charges or dashes at you. It hovers, blinks and
	casts.

	TOTALITY at half health: it cannot be hurt while it gathers; the ground
	orbits it, and on the release the air darkens to a purple dusk, its eyes
	burn violet, its aura deepens and an eclipse rises behind its hood.

	Phase two, the Eclipse: it flies, casts from the air, and lands spent
	after each spell. The Maelstrom walks after you in two aftershocks, the
	Judgment falls as a cross with safe diagonals, the Worldrend turns after
	you with a black core, the Thunder becomes a storm ending in a crown of
	strikes with one way out, the Mirror Veil
	makes four decoys that are hard to tell from it and trade places, and
	the BLACK SUN - held overhead while a thirty-stud ring closes, then
	slammed down - burns everyone who can see it: get out, or get a block
	between you and it.

	HOW IT MOVES

	It holds a casting ring twenty-odd studs from whoever it is after, hem a
	couple of studs off the ground, drifting slowly round and going still
	while it casts. That puts its pivot inside a sword's reach when you stand
	beside it. After Totality it flies (Tuning.flight): it circles high and
	wide, casts from the air, and comes down after every spell to recover
	before taking off again.

	THE RIG

	EnemyAssets.Signus is a Motor6D rig: an anchored, invisible RootPart and
	four jointed MeshParts (see assets/signus-hallow/roblox). This module only
	ever moves the RootPart, through applyPose -> Model:PivotTo. The joints
	play retargeted pack clips (Shared.Enemies.SignusClips): a move plans a
	clip here, writes it to the SignusClip attribute, and times its damage
	from the clip's own markers; every client (SignusRig) poses the joints
	from the same plan. SignusPhase and SignusStance pick its aura, eyes and
	idle.

	TERRAIN

	Every block it takes goes through TerrainManager's PlanExcavation and
	ExecuteExcavation or a boss displacement: natural, loaded, breakable, dry
	ground only, never a placed block, a structure, a cave wall or bedrock,
	under the caps in SignusMoves, with no loot. Cells are chosen BEFORE the
	warning is drawn and nothing re-aims after it. A placed block is always
	cover.

	EFFECTS

	Invisible carriers replicate the authoritative positions, sizes and opacity
	of telegraphs, projectiles, aura and eclipse. SignusVisuals renders pack
	particles and beams locally, including when an observer joins mid-fight.
	Bursts, flashes and camera kicks use BossEffect and SignusVFX.

	CLEANUP

	Every spell runs inside `entry.scope`, destroyed when it ends however it
	ends. Persistent encounter effects (lights, aura, eclipse, sky) live in
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
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AbilityScope = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityScope"))
local SignusClips = require(Shared:WaitForChild("Enemies"):WaitForChild("SignusClips"))

local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local BossService = require(ServerScriptService:WaitForChild("BossService"))
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

-- Both ensured by BossService at server start as well; see there.
local BossEffect = Remotes.ensure("BossEffect", "RemoteEvent")

local Signus = {}

-- The rig every Mirror Veil decoy is cloned from: the boss's own asset.
local SIGNUS_ASSET = ReplicatedStorage:WaitForChild("EnemyAssets"):WaitForChild("Signus")

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

	Second boss tier: 2300 health, between the Eye and Blightborer. Against
	base movement (walk 16, sprint 25), commitment and direction changes
	beat the fixed telegraphs; simply circling no longer clears every spell.
	Major hits cost roughly a third of unarmoured health. Phase two uses
	reacquired follow-ups and more, better-hidden decoys, with a per-action
	cap.
	Short grounded recoveries remain the melee opening.
]]
local Tuning = {
	phase2At = 0.5,

	restMin = { 0.7, 0.45 },
	restMax = { 1.05, 0.7 },

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

	-- Mirror Veil. Per phase where there are two numbers.
	mirror = {
		farDistance = 34,
		farSeconds = 2,
		hiddenSeconds = 2.5,
		cooldown = { 9, 7 },
		images = { 3, 5 }, -- Signus and its decoys
		decoyAlpha = { 0.55, 0.18 }, -- a decoy robe's Transparency; Signus is solid
		ring = { 15, 17 }, -- studs from the target they circle at
		spin = { 0.55, 0.85 }, -- radians a second round the ring: slower than you can walk
		follow = 0.5, -- how quickly the ring's centre drifts after its target
		split = 0.8, -- phase one: seconds fanning out from where it stood
		window = { 6, 6.5 }, -- seconds to find it before the images strike
		shuffle = { {}, { 2.2, 4.2 } }, -- seconds in at which the images trade places
		glide = 0.4, -- seconds a trade takes
		stun = { 1.8, 1.5 }, -- seconds it stays down, spent, once found
		-- When it is not found: each image calls a thunder strike in turn.
		stagger = { 0.5, 0.38 }, -- seconds between images; Signus goes last
		warn = { 0.8, 0.65 }, -- each mark's warning
		lead = 0.45, -- seconds ahead of its target that a mark is laid
		radius = { 6.5, 6 },
		finalRadius = { 9, 9.5 }, -- Signus's own strike
		damage = { 22, 26 },
		cap = { 34, 48 },
		recover = { 0.85, 0.7 },
	},

	step = {
		nearDistance = 9,
		nearSeconds = 2.5,
		fold = 0.25,
		distance = 18,
		unfold = 0.35, -- seconds the crescent takes to open again where it arrives
		cooldown = { 7, 5 },
	},

	-- Phase two: it takes to the air. It circles high and casts from there,
	-- then comes down after each spell to recover - the window a sword has -
	-- and takes off again before the next.
	flight = {
		hem = 13, -- studs of air under the robe while it circles
		castHem = 15, -- and while it casts
		ring = 30,
		speed = 30,
		drift = 2.1, -- the ring slides round this much faster
		bobAmplitude = 0.4,
		bank = 0, -- an upright, weightless glide rather than banking the robe
		perch = { 1.25, 1.7 }, -- a deliberate melee punish window
		airTime = 0.55,
	},

	-- Leaving: nobody near it for this long.
	giveUpSeconds = 14,
	giveUpRange = 360,
	leaveRise = 70,
	leaveSeconds = 2.4,
}

-- Mirror Veil is part of the pressure cycle as well as the answer to distant
-- or hidden targets. Veil Step remains a response to prolonged close pressure.
local CYCLES = {
	{ "spiral", "thunder", "lance", "beam", "mirror", "thunder", "spiral", "lance" },
	{ "blacksun", "lance", "thunder", "spiral", "beam", "mirror", "lance", "blacksun", "spiral", "thunder", "beam", "mirror" },
}

-- Phase two's names for the spells that change.
local ATTACK_NAMES = {
	spiral = { "Umbral Maelstrom", "Walking Maelstrom" },
	lance = { "Eclipse Judgment", "Judgment Cross" },
	beam = { "Worldrend", "Worldrend" },
	thunder = { "Umbral Thunder", "Eclipse Storm" },
	blacksun = { "Black Sun", "Black Sun" },
	mirror = { "Mirror Veil", "Hall of Mirrors" },
	step = { "Veil Step", "Veil Step" },
	totality = { "Totality", "Totality" },
}

-- Points on the rig, in RootPart space, from the export's pivots: where the
-- sleeves meet, the clasp on the chest, and the eyes in the hood.
local HANDS = CFrame.new(0, -0.6, -3.6)
local CLASP = CFrame.new(0, 1.6, -3.1)
local EYES = CFrame.new(0, 5.6, -2.7)
-- Behind and above the hood, where phase two's eclipse crown sits.
local CROWN = CFrame.new(0, 11.4, 2.2)

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

local TAU = math.pi * 2

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

-- ---------------------------------------------------------------------------
-- The sky
-- ---------------------------------------------------------------------------

--[[
	While it lives the world cools toward violet twilight, and darkens to a
	deep purple dusk in phase two (SignusSky adds the haze on each client).
	A ColorCorrectionEffect in Lighting, left in place neutral
	when the fight ends so a second Signus cannot have its sky deleted from
	under it. It never touches the clock.
]]
local SKY = {
	[1] = { TintColor = Color3.fromRGB(230, 220, 255), Saturation = -0.08, Contrast = 0.02, Brightness = 0 },
	-- The gather before Totality: the colour drains out first.
	gather = { TintColor = Color3.fromRGB(214, 198, 246), Saturation = -0.22, Contrast = 0.08, Brightness = -0.02 },
	-- Dusk: drained colour and a deep purple cast, and no darker: each client's
	-- SignusSky sets the exposure for the hour, so night is never crushed.
	[2] = { TintColor = Color3.fromRGB(206, 184, 246), Saturation = -0.26, Contrast = 0.12, Brightness = 0 },
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
-- The rig: retargeted pack clips
-- ---------------------------------------------------------------------------

--[[
	Every move is a clip from Shared.Enemies.SignusClips, planned here and
	drawn by each client (SignusRig) from the SignusClip attribute, so the
	server only ever moves the RootPart. `playClip` returns the plan's marks:
	seconds from now to its Swing, Hit, resume (after any hold), Reset and
	finish. Attacks wait on those, so damage lands on the frame the clip
	releases. Between clips the stance picks a procedural idle.
]]
local function clipPlan(name: string, options)
	return SignusClips.plan(name, options)
end

-- The same on any Signus rig: its decoys play clips too.
local function clipOn(model: Model, name: string, options)
	local plan = SignusClips.plan(name, options)
	model:SetAttribute("SignusClip", SignusClips.encode(plan, workspace:GetServerTimeNow()))
	return plan.marks
end

local function playClip(entry, name: string, options)
	local marks = clipOn(entry.model, name, options)
	entry.clipEndsAt = os.clock() + marks.finish
	return marks
end

-- "hover", "flight" or "spent".
local function setStance(entry, stance: string)
	if entry.stance ~= stance then
		entry.stance = stance
		entry.model:SetAttribute("SignusStance", stance)
	end
end

-- The idle between spells: aloft in phase two, down and spent while it
-- recovers on the ground, else hovering.
local function restStance(entry): string
	if not entry.transformed then
		return "hover"
	end
	return if os.clock() >= (entry.perchUntil or 0) then "flight" else "spent"
end

-- Blocking-hit recoil, only when nothing else is playing.
local function flinch(entry)
	if entry.busy or os.clock() < (entry.clipEndsAt or 0) then
		return
	end
	playClip(entry, "BlockHit", { speed = 1.3 })
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

-- Phase two's eclipse is worn as a halo behind the hood: the aura carrier
-- draws it once its Phase is 2 (SignusChoreography). This is the moment it
-- ignites.
local function buildEclipse(entry)
 fx("crown",rigPoint(entry,CROWN))
 entry.eclipse={}
end

-- ---------------------------------------------------------------------------
-- The spells
-- ---------------------------------------------------------------------------


-- While Totality plays it takes no damage: EnemyService asks a trait's
-- guard what share of a blow lands. While the Mirror Veil is up, the guard
-- decides whether a blow found Signus or one of its decoys.
local IMMUNE = { guard = function() return 0 end }

-- SignusMoves, created further down: Mirror Veil borrows its thunder.
local Spells

-- A decoy breaks where it stands: a veil flash and a crescent shatter.
local function breakImage(entry, image)
 if image.gone then return end
 image.gone=true
 if image.model.Parent then
  local at=image.model:GetPivot().Position
  fx("step",at-Vector3.new(0,3,0),{phase=entry.mirrorPhase})
  fx("crescentBreak",at,{phase=entry.mirrorPhase,struck=true})
  image.model:Destroy()
 end
 if image.aura then image.aura:Destroy() end
end

local MIRROR = { guard = function(entry)
 -- nearestPoint was asked a moment ago by whatever aimed this blow. A blow
 -- nothing aimed (a burn ticking, rubble) lands but finds nothing.
 local query=entry.imageQuery
 local image=query and os.clock()-query.at<.25 and query.image
 if not image then return 1 end
 entry.imageQuery=nil
 if not image.real then
  breakImage(entry,image)
  return 0
 end
 entry.mirrorFound=true
 return 1
end }

-- `on` is true for Totality's immunity, a trait table for another guard, or
-- false to give back whatever trait it had.
local function setGuard(entry, on)
	local trait = if on == true then IMMUNE elseif type(on) == "table" then on else nil
	if trait then
		if entry.trait ~= IMMUNE and entry.trait ~= MIRROR then
			entry.guardedTrait = entry.trait
		end
		entry.trait = trait
	elseif entry.trait == IMMUNE or entry.trait == MIRROR then
		entry.trait = entry.guardedTrait
		entry.guardedTrait = nil
	end
end

--[[
	MIRROR VEIL

	Its answer to being kept away from or hidden from, and a test of your
	eye. It folds into its veil and splits into images that circle whoever it
	is after, facing in. One is Signus; the rest are decoys. Strike the real
	one and the decoys scatter, leaving it down and spent; strike a decoy and
	only that one breaks. Find it too late and every image raises its sleeve
	in turn and calls Umbral Thunder down where you are heading, Signus last
	and widest.

	Phase one: two decoys, see-through, with a thin aura and no eyes, and
	they fan out from where it stood, so it can be followed. Phase two: four
	decoys, barely fainter than it, wearing its aura and eyes; they appear
	already on the ring and trade places twice.

	Weapons and abilities find the images through Signus.nearestPoint below;
	the MIRROR guard then decides what the blow hit.
]]
local function mirrorImage(entry, phase: number): Model
 local image=SIGNUS_ASSET:Clone()
 image.Name="SignusImage"
 for _,d in image:GetDescendants() do
  if d:IsA("BasePart") then
   d.CanCollide=false;d.CanQuery=false;d.CanTouch=false
   d.Anchored=d.Name=="RootPart"
   if d.Name~="RootPart" then d.Transparency=Tuning.mirror.decoyAlpha[phase] end
  end
 end
 -- SignusRig draws a decoy from these: its phase's colours, and (phase one)
 -- the thinner aura and no eyes.
 -- The eye light Signus.start gives the real one.
 local root=image:FindFirstChild("RootPart")
 if root then newLight(root,Colors.pearl,22,1.2) end
 image:SetAttribute("SignusDecoy",phase)
 image:SetAttribute("SignusPhase",entry.model:GetAttribute("SignusPhase"))
 image:SetAttribute("SignusStance","hover")
 image:PivotTo(entry.model:GetPivot())
 image.Parent=workspace
 CollectionService:AddTag(image,"SignusRig")
 entry.scope:add(image)
 return image
end

-- Its own aura carrier (the sigil under it and, in phase two, the eclipse
-- halo): faint on phase one's decoys, as strong as the real one's on phase two's.
local function imageAura(entry, phase: number, image: Model): Part
 local aura=newPart(Vector3.new(14,18,14),Colors.violet,if phase==1 then .6 else 0,"Aura")
 aura:SetAttribute("Phase",entry.aura and entry.aura:GetAttribute("Phase") or phase)
 aura:SetAttribute("Veiled",true)
 aura.CFrame=image:GetPivot()
 aura.Parent=workspace
 entry.scope:add(aura)
 return aura
end

local function smoothstep(a: number): number
 a=math.clamp(a,0,1)
 return a*a*(3-2*a)
end

local function mirror(entry, phase: number)
 local M=Tuning.mirror
 local target=entry.mirrorTarget or pickTarget(entry) or nearestPlayer(entry.position)
 entry.mirrorTarget=nil
 local root=livingRoot(target);if not root then return end
 entry.focus=target
 entry.nextMirrorAt=os.clock()+M.cooldown[phase]
 entry.motion="scripted";entry.lean=0;entry.roll=0;entry.bob=0
 setStance(entry,"hover")

 -- The veil folds.
 local from=entry.position
 fx("step",from-Vector3.new(0,3,0),{phase=phase})
 playClip(entry,"Parry",{speed=1.2})
 if not pause(entry,.25) then return end

 local count=M.images[phase]
 local real=math.random(count)
 local images={}
 for k=1,count do
  local isReal=k==real
  local model=if isReal then entry.model else mirrorImage(entry,phase)
  table.insert(images,{real=isReal,slot=k,bob=math.random()*TAU,model=model,aura=if isReal then nil else imageAura(entry,phase,model)})
 end
 entry.images=images;entry.mirrorPhase=phase;entry.mirrorFound=false
 -- Its name plate would point straight at it, and five halos crowd the
 -- screen: every image folds its eclipse away while the veil is up.
 local plate=entry.model:FindFirstChild("NamePlate")
 local plateWas=plate and plate:IsA("BillboardGui") and plate.Enabled
 if plateWas then plate.Enabled=false end
 local aura=entry.aura
 if aura then aura:SetAttribute("Veiled",true) end
 entry.scope:add(function()
  entry.images=nil;entry.imageQuery=nil
  if plateWas and plate.Parent then plate.Enabled=true end
  if aura and aura.Parent then aura:SetAttribute("Veiled",nil) end
 end)
 setGuard(entry,MIRROR)

 local function place(image,position,look,lean)
  if image.gone then return end
  if image.real then
   entry.position=position;entry.look=look;entry.lean=lean or 0;applyPose(entry)
  elseif image.model.Parent then
   image.model:PivotTo(CFrame.lookAt(position,position+look)*CFrame.Angles(lean or 0,0,0))
   if image.aura then image.aura.CFrame=image.model:GetPivot() end
  end
 end
 local function positionOf(image): Vector3
  return if image.real then entry.position else image.model:GetPivot().Position
 end

 -- The circle. Phase two's images are simply there, each in a veil flash.
 local first=phase==2
 local centre=root.Position
 local base=math.atan2(from.Z-centre.Z,from.X-centre.X)
 local spin,dir=0,if math.random()<.5 then 1 else -1
 local shuffles=M.shuffle[phase]
 local nextShuffle,glideAt=1,nil
 local began,last=os.clock(),os.clock()
 while os.clock()-began<M.window[phase] and not entry.mirrorFound do
  if entry.signusFinished or entry.scope:isDead() then return end
  local now=os.clock();local dt=math.min(now-last,.1);last=now
  local live=livingRoot(target);if not live then break end
  local t=now-began
  -- The ring drifts after its target slowly enough that an image can be walked up to.
  centre=centre:Lerp(live.Position,math.clamp(dt*M.follow,0,1))
  spin+=dir*M.spin[phase]*dt
  if shuffles[nextShuffle] and t>=shuffles[nextShuffle] then
   -- They trade places: every image takes another's slot, sliding round
   -- the ring through each other, behind a veil flash each.
   nextShuffle+=1
   local order={}
   for k=1,count do order[k]=k end
   for k=count,2,-1 do local j=math.random(k);order[k],order[j]=order[j],order[k] end
   for i,image in images do
    image.fromSlot=image.slot;image.slot=order[i]
    if not image.gone then fx("step",positionOf(image)-Vector3.new(0,3,0),{phase=phase}) end
   end
   glideAt=now
  end
  local glide=if glideAt then smoothstep((now-glideAt)/M.glide) else 1
  local spread=if phase==1 then smoothstep(t/M.split) else 1
  for _,image in images do
   local slot=if glideAt and image.fromSlot then image.fromSlot+(image.slot-image.fromSlot)*glide else image.slot
   local angle=base+(slot-1)*TAU/count+spin
   local ring=centre+Vector3.new(math.cos(angle),0,math.sin(angle))*M.ring[phase]
   local ground=groundUnder(Vector3.new(ring.X,centre.Y,ring.Z))
   local spot=Vector3.new(ring.X,pivotHeight(entry,ground,Tuning.hover.hem),ring.Z)+Vector3.yAxis*math.sin(t*2.2+image.bob)*.6
   local position=if spread<1 then from:Lerp(spot,spread) else spot
   place(image,position,flat(live.Position-position))
   if first then fx("step",position-Vector3.new(0,3,0),{phase=phase}) end
  end
  first=false
  if glideAt and glide>=1 then glideAt=nil end
  task.wait()
 end

 local function scatter()
  for _,image in images do if not image.real then breakImage(entry,image) end end
  entry.images=nil
  setGuard(entry,false)
 end
 local function found()
  -- Found: the decoys scatter and it is left down and spent.
  scatter()
  fx("crescentBreak",rigPoint(entry,CLASP),{phase=phase,struck=true})
  playClip(entry,"BlockHit",{speed=.9})
  entry.motion="ground";entry.lean=0;applyPose(entry);setStance(entry,"spent")
  pause(entry,M.stun[phase])
 end
 if entry.mirrorFound then return found() end
 if not livingRoot(target) then scatter() return end

 -- Not found in time: one after another each image raises its sleeve and
 -- calls Umbral Thunder down on you, Signus last and widest. Every mark
 -- opens where you are heading and closes on its own warning.
 local ledger={}
 local order={}
 for _,image in images do if not image.real and not image.gone then table.insert(order,image) end end
 for k=#order,2,-1 do local j=math.random(k);order[k],order[j]=order[j],order[k] end
 for _,image in images do if image.real then table.insert(order,image) end end

 local pending=0
 for index,image in order do
  if entry.mirrorFound or entry.signusFinished or entry.scope:isDead() then break end
  local live=livingRoot(target)
  if live and not image.gone then
   local marks=clipOn(image.model,"UpTilt",{windup=.2,hold=M.warn[phase]+.2})
   if image.real then entry.clipEndsAt=os.clock()+marks.finish end
   local velocity=Vector3.new(live.AssemblyLinearVelocity.X,0,live.AssemblyLinearVelocity.Z)
   if velocity.Magnitude>25 then velocity=velocity.Unit*25 end
   local mark=groundUnder(live.Position+velocity*M.lead)
   local radius=if image.real then M.finalRadius[phase] else M.radius[phase]
   pending+=1
   entry.scope:spawn(function()
    Spells.bolt(entry,phase,mark,radius,M.warn[phase],M.damage[phase],ledger,"image"..index,M.cap[phase])
    pending-=1
   end)
   -- A decoy is spent by its spell: it breaks as the bolt lands.
   if not image.real then
    entry.scope:spawn(function()
     if pause(entry,M.warn[phase]) then breakImage(entry,image) end
    end)
   end
  end
  if index<#order and not pause(entry,M.stagger[phase]) then return end
 end
 while pending>0 and not entry.signusFinished and not entry.scope:isDead() do task.wait() end
 if entry.mirrorFound then return found() end
 scatter()
 entry.motion="ground";entry.leanGoal=0;entry.lean=0;setStance(entry,"spent")
 pause(entry,M.recover[phase])
end

--[[
	VEIL STEP

	Hugged too long, it folds into a crescent of light and blinks: gone in a
	veil flash, unfolding eighteen studs off in another. No glide and no
	dash, and never further than that: it buys a moment, not an escape.
]]
local function veilStep(entry, _phase: number)
	local S = Tuning.step
	local scope = entry.scope
	local near, _ = nearestPlayer(entry.position)
	local nearRoot = rootOf(near)
	local away = if nearRoot then flat(entry.position - nearRoot.Position) else -flat(entry.look)

	entry.motion = "scripted"
	playClip(entry, "Parry", { speed = 1.2 })

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

	-- The blink: gone from here, there in the same instant.
	local from = entry.position
	local landing = groundUnder(from + away * S.distance)
	local goal = Vector3.new(landing.X, pivotHeight(entry, landing, Tuning.hover.hem), landing.Z)
	fx("step", from - Vector3.new(0, 3, 0))
	entry.position = goal
	entry.roll = 0
	applyPose(entry)
	fx("step", goal - Vector3.new(0, 3, 0))
	began = os.clock()
	while os.clock() - began < S.unfold do
		if entry.signusFinished then
			return
		end
		local alpha = math.clamp((os.clock() - began) / S.unfold, 0, 1)
		layWrap(1 - alpha, 2 + alpha * 6)
		task.wait()
	end
	for _, part in ipairs(wrap) do
		part:Destroy()
	end
	setStance(entry, restStance(entry))
	entry.motion = "hover"
end


-- ---------------------------------------------------------------------------
-- The fight
-- ---------------------------------------------------------------------------


-- The moment of Totality: the eyes, aura and crown turn, for every client.
local function ignite(entry)
	entry.transformed = true
	entry.model:SetAttribute("SignusPhase", 2)
	if entry.aura then entry.aura:SetAttribute("Phase", 2) end
	buildEclipse(entry)
end

local moves=require(script.Parent.SignusMoves).create({
	carrier=newPart,pickTarget=pickTarget,root=livingRoot,ground=groundUnder,
	clip=playClip,clipPlan=clipPlan,stance=setStance,pause=pause,
	playersInCircle=playersInCircle,players=livingPlayers,
	cover=sightBlock,hit=hitOnce,fx=fx,flat=flat,applyPose=applyPose,
	hand=function(entry) return rigPoint(entry,HANDS) end,
	sky=setSky,ignite=ignite,guard=setGuard,announce=announce,
	airHem=Tuning.flight.castHem,
})
Spells=moves
local ATTACKS = {
	spiral = moves.spiral,
	lance = moves.lance,
	beam = moves.beam,
	thunder = moves.thunder,
	blacksun = moves.blacksun,
	mirror = mirror,
	step = veilStep,
	totality = moves.totality,
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
	setBossPhase(entry, ATTACK_NAMES[pick] and ATTACK_NAMES[pick][phase] or pick)
	entry.busy = true
	entry.activeAttack = pick

	local scope = AbilityScope.new()
	entry.scope = scope

	task.spawn(function()
		local ok, err = pcall(ATTACKS[pick], entry, phase)

		if entry.scope == scope then
			entry.scope = nil
		end
		scope:destroy()
		entry.activeAttack = nil

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
		-- However the spell ended, Totality's immunity or the veil's guard ends with it.
		setGuard(entry, false)

		local now = phaseOf(entry)
		local rest = if pick == "step" or pick == "mirror"
			then 0.3
			else math.random() * (Tuning.restMax[now] - Tuning.restMin[now]) + Tuning.restMin[now]
		-- Aloft, every spell but a step ends on the ground, spent; it takes off
		-- again a moment before the next. Totality ends in the air.
		if entry.transformed and pick ~= "step" and pick ~= "totality" then
			local F = Tuning.flight
			local perch = F.perch[1] + math.random() * (F.perch[2] - F.perch[1])
			entry.perchUntil = os.clock() + perch
			rest = perch + F.airTime
		end
		setStance(entry, restStance(entry))
		entry.nextAttackAt = os.clock() + rest
		entry.busy = false
		setBossPhase(entry, nil)
	end)
end

-- Touching the robe: a short cylinder around its centre.
local function contactDamage(entry, now: number)
	-- The rush capsules own Mirror Veil's damage, under its shared cap.
	if entry.activeAttack == "mirror" then return end
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
	setStance(entry, restStance(entry))
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
	Decides whether something other than the cycle is called for: a veil
	at someone who keeps away or hides, or a step away from someone who will
	not leave it alone. Returns the pick, or nil for the cycle.
]]
local function situational(entry, now: number, phase: number): string?
	local L = Tuning.mirror
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
	local mirrorDue = (entry.farSince and now - entry.farSince >= L.farSeconds)
		or (entry.hiddenSince and now - entry.hiddenSince >= L.hiddenSeconds)
	if mirrorDue and now >= (entry.nextMirrorAt or 0) then
		entry.farSince = nil
		entry.hiddenSince = nil
		entry.nextMirrorAt = now + L.cooldown[phase]
		entry.mirrorTarget = focusPlayer
		return "mirror"
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

	-- The copy keeps the SignusRig tag, so clients pose it: the last of Heavy's
	-- sweep, slowed, settling into the spent stance. No aura, no eyes.
	husk:SetAttribute("SignusPhase", 0)
	husk:SetAttribute("SignusStance", "spent")
	husk:SetAttribute("SignusClip", SignusClips.encode(
		SignusClips.plan("Heavy", { from = SignusClips.Data.Heavy.markers.Hit, speed = 0.7 }),
		workspace:GetServerTimeNow()
	))

	local sink = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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
	entry.perchUntil = nil
	entry.perched = false
	entry.scope = nil
	entry.stance = nil
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

	local placed = entry.model:GetPivot().Position
	entry.position = placed
	local first = rootOf((nearestPlayer(placed)))
	entry.look = flat(if first then first.Position - placed else Vector3.new(0, 0, -1))
	if first then
		entry.ringAngle = math.atan2(placed.Z - first.Position.Z, placed.X - first.Position.X)
	end

	entry.aura=newPart(Vector3.new(14,18,14),Colors.violet,0,"Aura")
	entry.aura:SetAttribute("Phase",1)
	entry.aura.Parent=workspace
	entry.encounterScope:add(entry.aura)

	-- The body: clients pose it from these (SignusRig).
	entry.model:SetAttribute("SignusPhase", 1)
	entry.model:SetAttribute("SignusClip", nil)
	setStance(entry, "hover")
	CollectionService:AddTag(entry.model, "SignusRig")

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
	local F = Tuning.flight
	local phase = phaseOf(entry)
	-- Aloft: transformed, and not down recovering from a spell.
	local flying = entry.transformed and now >= (entry.perchUntil or 0)

	entry.bobPhase += dt
	entry.bob = if entry.motion == "scripted"
		then 0
		else math.sin(entry.bobPhase * TAU / H.bobPeriod) * (if entry.transformed then F.bobAmplitude else H.bobAmplitude)
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
			-- Down recovering it drifts at half pace; aloft it circles wide and fast.
			local perched = entry.transformed and not flying
			entry.ringAngle += entry.ringSpin * dt * (if flying then F.drift elseif perched then 0.5 else 1)
			local radius = if flying then F.ring else H.ring[phase]
			local ring = focus.Position + Vector3.new(math.cos(entry.ringAngle), 0, math.sin(entry.ringAngle)) * radius
			local ground = groundUnder(Vector3.new(ring.X, focus.Position.Y, ring.Z))
			local goal = Vector3.new(ring.X, pivotHeight(entry, ground, if flying then F.hem else entry.hem), ring.Z)
			moveToward(entry, goal, dt, if flying then F.speed elseif perched then H.speed[phase] * 0.5 else H.speed[phase])
		elseif entry.motion == "hold" or entry.motion == "ground" or entry.motion == "aim" then
			-- Still, but settling to the height the spell wants. A spell that
			-- aims ("aim") turns it itself.
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

		if focus and entry.motion ~= "aim" then
			entry.look = turnFlat(entry.look, focus.Position - entry.position, math.rad(H.turnRate) * dt)
		end

		-- The silhouette stays upright; the stance shows whether it is aloft
		-- (sleeves swept back) or down recovering.
		if entry.transformed and entry.motion == "hover" then
			entry.roll += (0 - entry.roll) * math.clamp(dt * 6, 0, 1)
			entry.leanGoal = 0
			if not entry.busy then
				setStance(entry, restStance(entry))
			end
		end

		applyPose(entry)
	end

	-- Touching down after a spell, and taking off again.
	if entry.transformed and entry.motion == "hover" then
		local ground = groundUnder(entry.position)
		if flying and entry.perched then
			entry.perched = false
			fx("takeoff", ground)
		elseif not flying and not entry.perched
			and entry.position.Y - pivotHeight(entry, ground, Tuning.hover.hem) < 1.5 then
			entry.perched = true
			fx("land", ground)
		end
	end

	if not entry.leaving then
		contactDamage(entry, now)
	end

	if entry.busy or entry.leaving or not target then
		return
	end

	-- A spell asked for by name (/signus <spell> in the debug console) goes
	-- next, once it is free; Totality still comes first at half health.
	local asked = entry.model:GetAttribute("SignusCast")
	if asked ~= nil and not ATTACKS[asked] then
		entry.model:SetAttribute("SignusCast", nil)
		asked = nil
	end

	if now >= (entry.nextAttackAt or 0) or asked then
		local pick
		if phase == 2 and not entry.transformed then
			pick = "totality"
		elseif asked then
			pick = asked
			entry.model:SetAttribute("SignusCast", nil)
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

--[[
	Where its body is, for a swing or an ability looking from `position`.
	While the Mirror Veil is up that is whichever image is nearest - Signus or
	a decoy - remembered so the MIRROR guard can tell which the blow found.
	Otherwise nil, and EnemyService uses the pivot.
]]
function Signus.nearestPoint(entry, position: Vector3): Vector3?
	local images = entry.images
	if not images then
		return nil
	end
	local best, bestPoint, bestDistance = nil, nil, math.huge
	for _, image in images do
		if not image.gone and image.model.Parent then
			local point = image.model:GetPivot().Position
			local distance = (point - position).Magnitude
			if distance < bestDistance then
				best, bestPoint, bestDistance = image, point, distance
			end
		end
	end
	if best then
		entry.imageQuery = { image = best, at = os.clock() }
	end
	return bestPoint
end

-- The damage number goes on the image that was struck.
function Signus.impactPoint(entry, _dealer): Vector3?
	local query = entry.imageQuery
	if entry.images and query and os.clock() - query.at < 0.25 and query.image.model.Parent then
		return query.image.model:GetPivot().Position
	end
	return nil
end

function Signus.finish(entry, reason: string?)
	entry.signusFinished = true
	entry.busy = false

	if entry.scope then
		entry.scope:destroy()
		entry.scope = nil
	end
	setGuard(entry, false)

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
	entry.eclipse = nil
	entry.aura = nil
	entry.model:SetAttribute("SignusClip", nil)

	-- The sky clears, unless another of it is still out there.
	if #EnemyService.allOf(SELF) == 0 then
		setSky("clear", 3)
	end
end

-- Where the fight changes, as health fractions, for the boss bar's markers
-- (BossService sends it): two stages, Totality at half.
Signus.phases = { Tuning.phase2At }

return Signus
