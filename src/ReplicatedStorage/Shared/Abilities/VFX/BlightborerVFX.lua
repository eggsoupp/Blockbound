--[[
	BlightborerVFX

	Everything visible about the Blightborer except its body: the warnings,
	the eruptions, the trench, the spit in flight, the bursts. Asked for by
	ServerScriptService.Bosses.Blightborer over the `BossEffect` remote (see
	StarterPlayerScripts.BossEffectClient), drawn here, thrown away by the
	scope it ran in.

		BlightborerVFX.play(payload, scope) -> seconds it needs

	  rumble      a breach coming: the ground cracks, shakes and spits pebbles
	              where it will come up            { radius, seconds }
	  erupt       it comes up: rock of whatever blocks really went, a smoke
	              shock, a dust ring, ichor        { blocks, radius, width }
	  dive        it goes back in                  { blocks, radius, small }
	  furrowline  a Rending Furrow's warning, cracks along the whole line
	                                               { to, seconds, radius }
	  furrow      the trench tearing open over its head, in small batches
	                                               { blocks, direction }
	  spit        one glob in flight, along the arc the server computed
	                                               { velocity, gravity, seconds, landing }
	  splash      a glob landing, and the block it ate
	                                               { blocks, normal }
	  sinkwarn    the Sinkhole's ring of cracks    { radius, seconds }
	  collapse    the ground falling in            { blocks, radius, depth }
	  burst       a segment bursting as it splits  { radius }
	  brood       Blightlings retched up           { look }
	  death       the pieces popping, tail to head { points, gap }

	EVERY TEXTURE IS FROM THE SUPPLIED PACKS (BlightborerParticles). The only
	parts made here are invisible emitter hosts; nothing is drawn with a
	visible Part. Block debris is particles tinted the colour of the blocks
	the server says it really took.

	LATE IS SHORTER, NOT LATER. Every payload carries the server time it
	started; a warning that arrives a tenth of a second late is a tenth of a
	second shorter, and a glob that arrives late starts partway along its
	arc, so what this client sees is always where the server is.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemModels = require(Shared:WaitForChild("UI"):WaitForChild("ItemModels"))
local Library = require(script.Parent:WaitForChild("BlightborerParticles"))

local BlightborerVFX = {}

local Colors = {
	ichor = Color3.fromRGB(150, 220, 70),
	bile = Color3.fromRGB(96, 150, 40),
	rot = Color3.fromRGB(70, 34, 86),
	bruise = Color3.fromRGB(122, 74, 140),
	dust = Color3.fromRGB(104, 90, 104),
	shadow = Color3.fromRGB(26, 12, 32),
	pale = Color3.fromRGB(224, 236, 196),
}

-- How far away the ground has to be for its shaking to reach this camera.
local SHAKE_REACH = 90

-- ---------------------------------------------------------------------------
-- Building blocks
-- ---------------------------------------------------------------------------

local function sequence(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local function sizes(start: number, mid: number, finish: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, start),
		NumberSequenceKeypoint.new(0.35, mid),
		NumberSequenceKeypoint.new(1, finish),
	})
end

-- An authored size curve, kept, at another scale.
local function scaled(curve: NumberSequence, factor: number): NumberSequence
	local points = {}
	for _, key in ipairs(curve.Keypoints) do
		table.insert(points, NumberSequenceKeypoint.new(key.Time, key.Value * factor, key.Envelope * factor))
	end
	return NumberSequence.new(points)
end

local function tint(a: Color3, b: Color3?): ColorSequence
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) })
end

-- An invisible part to hang emitters off. A volume, when `size` says so, so
-- emitters on it spread across it rather than firing from one point.
local function host(scope, position: Vector3, size: Vector3?): Part
	local part = Instance.new("Part")
	part.Name = "BlightborerFX"
	part.Size = size or Vector3.one * 0.2
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	scope:add(part)
	return part
end

-- A pack template on a host. Texture and layout first: see BlightborerParticles.
local function emitter(kind: string, parent: Instance, props: { [string]: any }?): ParticleEmitter
	local data = Library[kind]
	local e = Instance.new("ParticleEmitter")
	e.Name = "Blightborer_" .. kind
	e.Texture = data.Texture
	e.FlipbookLayout = data.FlipbookLayout or Enum.ParticleFlipbookLayout.None
	for key, value in pairs(data) do
		(e :: any)[key] = value
	end
	e.Enabled = false
	e.Rate = 0
	if props then
		for key, value in pairs(props) do
			(e :: any)[key] = value
		end
	end
	e.Parent = parent
	return e
end

local function burst(kind: string, parent: Instance, count: number, props: { [string]: any }?): ParticleEmitter
	local e = emitter(kind, parent, props)
	if count > 0 then
		e:Emit(count)
	end
	return e
end

-- A stream for `seconds`, then off; what is already out finishes its life.
local function stream(scope, kind: string, parent: Instance, rate: number, seconds: number, props: { [string]: any }?)
	local e = emitter(kind, parent, props)
	e.Rate = rate
	e.Enabled = true
	scope:delay(math.max(0, seconds), function()
		e.Enabled = false
	end)
	return e
end

-- A brief glow, faded out. A light, not a part.
local function glow(scope, parent: Instance, color: Color3, range: number, brightness: number, seconds: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
	scope:tween(light, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 })
end

-- Turns a host so its top face - where emitters fire from - points along a
-- direction. lookAt cannot be asked to look straight up or down.
local function faceAlong(part: BasePart, direction: Vector3)
	local position = part.Position
	if direction.Y > 0.99 then
		part.CFrame = CFrame.new(position)
	elseif direction.Y < -0.99 then
		part.CFrame = CFrame.new(position) * CFrame.Angles(math.pi, 0, 0)
	else
		part.CFrame = CFrame.lookAt(position, position + direction) * CFrame.Angles(-math.pi / 2, 0, 0)
	end
end

local function age(payload): number
	if type(payload.startedAt) ~= "number" then
		return 0
	end
	return math.max(0, workspace:GetServerTimeNow() - payload.startedAt)
end

-- ---------------------------------------------------------------------------
-- What the blocks looked like
-- ---------------------------------------------------------------------------

--[[
	The colour to tint rock debris for a block. Read off the block's own
	model where it has a plain colour; a textured block's part is usually
	white under its decals, so a name that says what it is wins over that.
]]
local NAMED = {
	{ "corrupt", Color3.fromRGB(92, 76, 104) },
	{ "crimson", Color3.fromRGB(128, 52, 52) },
	{ "hallow", Color3.fromRGB(198, 186, 226) },
	{ "grass", Color3.fromRGB(86, 110, 52) },
	{ "dirt", Color3.fromRGB(110, 78, 52) },
	{ "sand", Color3.fromRGB(214, 196, 140) },
	{ "snow", Color3.fromRGB(236, 240, 246) },
	{ "stone", Color3.fromRGB(112, 110, 106) },
	{ "cobble", Color3.fromRGB(112, 110, 106) },
}

local colorCache: { [string]: Color3 } = {}

local function blockColor(name: string?): Color3
	if type(name) ~= "string" then
		return Colors.dust
	end
	local cached = colorCache[name]
	if cached then
		return cached
	end

	local color = nil
	local lower = string.lower(name)
	for _, row in ipairs(NAMED) do
		if string.find(lower, row[1], 1, true) then
			color = row[2]
			break
		end
	end

	if not color then
		local ok, source = pcall(ItemModels.find, name)
		local part = ok and source and (if source:IsA("BasePart") then source else source:FindFirstChildWhichIsA("BasePart", true))
		if part then
			color = part.Color
		end
	end

	color = color or Colors.dust
	colorCache[name] = color
	return color
end

-- Up to three colours, most common first, from the server's block samples.
local function colorsOf(blocks): { Color3 }
	local counts, order = {}, {}
	if type(blocks) == "table" then
		for _, record in ipairs(blocks) do
			local name = type(record) == "table" and record.block
			if type(name) == "string" then
				if not counts[name] then
					counts[name] = 0
					table.insert(order, name)
				end
				counts[name] += 1
			end
		end
	end
	table.sort(order, function(a, b)
		return counts[a] > counts[b]
	end)
	local colors = {}
	for index = 1, math.min(3, #order) do
		table.insert(colors, blockColor(order[index]))
	end
	return colors
end

-- Rock thrown out of the ground in the blocks' own colours: `count` in all,
-- shared between them.
local function rocks(parent: Instance, blocks, count: number, props: { [string]: any })
	local colors = colorsOf(blocks)
	if #colors == 0 then
		colors = { Colors.dust }
	end
	local each = math.max(1, math.floor(count / #colors))
	for _, color in ipairs(colors) do
		local settings = table.clone(props)
		settings.Color = tint(color)
		burst("Rock", parent, each, settings)
	end
end

-- ---------------------------------------------------------------------------
-- The camera
-- ---------------------------------------------------------------------------

--[[
	One bounded mixer for every shake at once. Applied after the camera
	scripts have placed the camera and taken back off before they run next
	frame, so it never fights them for aim and never accumulates.
]]
local shakes = {}
local bound = false
local previousCamera, previousBase, previousApplied

local function restore()
	if previousCamera and previousCamera == workspace.CurrentCamera and previousCamera.CFrame == previousApplied then
		previousCamera.CFrame = previousBase
	end
	previousCamera, previousBase, previousApplied = nil, nil, nil
end

local function applyShake()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = workspace:GetServerTimeNow()
	local amount = 0
	for token in pairs(shakes) do
		local t = now - token.startedAt
		if t >= 0 and t <= token.seconds then
			-- A warning builds; a blow lands and dies away.
			local envelope = if token.build then t / token.seconds else math.exp(-t * 6)
			local near = math.clamp(1 - (camera.CFrame.Position - token.centre).Magnitude / token.reach, 0, 1)
			amount += token.strength * envelope * near
		end
	end
	if amount <= 0.002 then
		return
	end
	amount = math.min(amount, 2)
	local clock = os.clock() * 22
	local base = camera.CFrame
	local applied = base * CFrame.Angles(
		math.noise(clock, 0.5) * 0.018 * amount,
		math.noise(clock, 1.5) * 0.018 * amount,
		math.noise(clock, 2.5) * 0.008 * amount
	)
	camera.CFrame = applied
	previousCamera, previousBase, previousApplied = camera, base, applied
end

local function shake(scope, centre: Vector3, strength: number, seconds: number, startedAt: number, build: boolean?)
	local player = Players.LocalPlayer
	if player and player:GetAttribute("ReducedMotion") == true then
		return
	end
	local token = {
		centre = centre,
		strength = strength,
		seconds = seconds,
		startedAt = startedAt,
		build = build,
		reach = SHAKE_REACH,
	}
	shakes[token] = true
	scope:add(function()
		shakes[token] = nil
		if not next(shakes) and bound then
			bound = false
			RunService:UnbindFromRenderStep("BlightborerCameraBefore")
			RunService:UnbindFromRenderStep("BlightborerCameraAfter")
			restore()
		end
	end)
	if not bound then
		bound = true
		RunService:BindToRenderStep("BlightborerCameraBefore", Enum.RenderPriority.Camera.Value - 4, restore)
		RunService:BindToRenderStep("BlightborerCameraAfter", Enum.RenderPriority.Last.Value + 12, applyShake)
	end
end

-- ---------------------------------------------------------------------------
-- Pieces of effects, shared between kinds
-- ---------------------------------------------------------------------------

-- A crack lying on the ground, staying `life` seconds.
local function crack(parent: Instance, diameter: number, life: number, color: Color3?)
	burst("GroundCrack", parent, 1, {
		Size = sequence(diameter, diameter),
		Lifetime = NumberRange.new(life),
		Color = tint(color or Colors.shadow),
		Speed = NumberRange.new(0.01),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.zero,
	})
end

-- A flat ring on the ground, pulsing `count` times over `seconds`.
local function pulses(scope, parent: Instance, diameter: number, seconds: number, color: Color3)
	local ring = emitter("WarningRing", parent, {
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.zero,
		Speed = NumberRange.new(0.01),
		Size = sizes(diameter * 0.3, diameter * 0.9, diameter),
		Lifetime = NumberRange.new(0.5),
		Color = tint(color),
		Brightness = 4,
		LightEmission = 0.8,
	})
	local count = math.max(1, math.floor(seconds / 0.3))
	for index = 0, count - 1 do
		scope:delay(index * seconds / count, function()
			ring:Emit(1)
		end)
	end
end

-- A dust ring rolling out flat over the ground.
local function dustRing(parent: Instance, diameter: number, color: Color3)
	burst("DustRing", parent, 2, {
		Size = scaled(Library.DustRing.Size, diameter / 31),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.zero,
		Color = tint(color),
	})
end

-- ---------------------------------------------------------------------------
-- The kinds
-- ---------------------------------------------------------------------------

local KINDS = {}

function KINDS.rumble(payload, scope): number
	local radius = tonumber(payload.radius) or 8
	local seconds = (tonumber(payload.seconds) or 1) - age(payload)
	if seconds <= 0.05 then
		return 0
	end
	local centre = payload.position + Vector3.new(0, 0.2, 0)
	local area = host(scope, centre, Vector3.new(radius * 1.6, 0.2, radius * 1.6))
	local point = host(scope, centre)

	crack(point, radius * 2.4, seconds + 0.8)
	pulses(scope, point, radius * 2.2, seconds, Colors.ichor)
	stream(scope, "Smoke", area, 16, seconds, {
		Color = tint(Colors.dust, Colors.rot),
		Size = sizes(1.5, 3.5, 5),
		Speed = NumberRange.new(4, 9),
		Lifetime = NumberRange.new(0.9, 1.5),
		SpreadAngle = Vector2.new(25, 25),
		LightEmission = 0.1,
	})
	stream(scope, "Rock", area, 22, seconds, {
		Color = tint(Colors.dust),
		Size = sizes(0, 0.6, 0),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, -80, 0),
		Drag = 2,
		Lifetime = NumberRange.new(0.4, 0.7),
	})
	shake(scope, centre, 0.7, seconds, workspace:GetServerTimeNow(), true)
	return seconds + 1.5
end

function KINDS.erupt(payload, scope): number
	local radius = tonumber(payload.radius) or 7
	local width = tonumber(payload.width) or 3
	local centre = payload.position
	local point = host(scope, centre + Vector3.new(0, 0.5, 0))

	rocks(point, payload.blocks, 36, {
		Size = sizes(0, 1.2, 0.4),
		Speed = NumberRange.new(40, 75),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, -95, 0),
		Drag = 1.5,
		Lifetime = NumberRange.new(0.8, 1.4),
	})
	burst("SmokeShock", point, 1, {
		Size = sequence(radius * 3, radius * 3.4),
		Color = tint(Colors.dust),
		Lifetime = NumberRange.new(0.9),
	})
	dustRing(point, radius * 3.2, Colors.dust)
	burst("GroundBurst", point, 1, {
		Size = scaled(Library.GroundBurst.Size, radius / 9),
		Color = tint(Colors.ichor),
	})
	burst("Smoke", point, 14, {
		Color = tint(Colors.dust, Colors.rot),
		Size = sizes(width, width * 2, width * 3),
		Speed = NumberRange.new(18, 34),
		SpreadAngle = Vector2.new(22, 22),
		Lifetime = NumberRange.new(1.2, 2),
		Drag = 2.5,
		LightEmission = 0.1,
	})
	burst("DarkFire", point, 8, {
		Color = tint(Colors.ichor, Colors.bile),
		Size = sizes(width * 0.8, width * 1.6, 0),
		Speed = NumberRange.new(25, 45),
		SpreadAngle = Vector2.new(25, 25),
		Lifetime = NumberRange.new(0.5, 0.8),
		FlipbookFramerate = NumberRange.new(24),
		LightEmission = 0.5,
		Transparency = sequence(0.1, 1),
		Acceleration = Vector3.new(0, -40, 0),
		Drag = 2,
	})
	burst("Flash", point, 1, {
		Color = tint(Colors.pale),
		Size = scaled(Library.Flash.Size, radius / 4),
	})
	glow(scope, point, Colors.ichor, radius * 4, 3, 0.6)
	shake(scope, centre, 1.4, 0.9, payload.startedAt or workspace:GetServerTimeNow())
	return 2.5
end

function KINDS.dive(payload, scope): number
	local radius = tonumber(payload.radius) or 3
	local point = host(scope, payload.position + Vector3.new(0, 0.4, 0))
	dustRing(point, radius * 4, Colors.dust)
	burst("Smoke", point, if payload.small then 4 else 8, {
		Color = tint(Colors.dust),
		Size = sizes(radius * 0.6, radius * 1.4, radius * 2),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(45, 45),
		Lifetime = NumberRange.new(0.8, 1.4),
		Drag = 2.5,
		LightEmission = 0.1,
	})
	if not payload.small then
		rocks(point, payload.blocks, 16, {
			Size = sizes(0, 0.9, 0.3),
			Speed = NumberRange.new(20, 38),
			SpreadAngle = Vector2.new(50, 50),
			Acceleration = Vector3.new(0, -95, 0),
			Drag = 1.5,
			Lifetime = NumberRange.new(0.6, 1),
		})
		shake(scope, payload.position, 0.6, 0.5, payload.startedAt or workspace:GetServerTimeNow())
	end
	return 2
end

function KINDS.furrowline(payload, scope): number
	if typeof(payload.to) ~= "Vector3" then
		return 0
	end
	local seconds = (tonumber(payload.seconds) or 0.8) - age(payload)
	local from, to = payload.position, payload.to
	local line = to - from
	local length = line.Magnitude
	local steps = math.clamp(math.floor(length / 8), 2, 12)
	local width = tonumber(payload.radius) or 6

	for index = 0, steps do
		local at = from + line * (index / steps) + Vector3.new(0, 0.2, 0)
		local point = host(scope, at)
		-- The cracks open along the line toward you, and stay while the
		-- trench is torn under them.
		scope:delay(math.max(0, seconds) * index / steps * 0.6, function()
			crack(point, width * 2.2, math.max(0.5, seconds) + 2.5)
			burst("Smoke", point, 2, {
				Color = tint(Colors.dust),
				Size = sizes(1, 2.5, 3.5),
				Speed = NumberRange.new(3, 7),
				SpreadAngle = Vector2.new(30, 30),
				Lifetime = NumberRange.new(0.8, 1.2),
				LightEmission = 0.1,
			})
		end)
	end

	local exit = host(scope, to + Vector3.new(0, 0.2, 0))
	pulses(scope, exit, 12, math.max(0.3, seconds) + 1, Colors.ichor)
	shake(scope, from, 0.5, math.max(0.3, seconds), workspace:GetServerTimeNow(), true)
	return math.max(0, seconds) + 3.5
end

function KINDS.furrow(payload, scope): number
	local point = host(scope, payload.position)
	rocks(point, payload.blocks, 10, {
		Size = sizes(0, 1, 0.3),
		Speed = NumberRange.new(22, 40),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -95, 0),
		Drag = 1.5,
		Lifetime = NumberRange.new(0.6, 1),
	})
	burst("Smoke", point, 3, {
		Color = tint(Colors.dust),
		Size = sizes(2, 4, 6),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(35, 35),
		Lifetime = NumberRange.new(0.9, 1.5),
		Drag = 2,
		LightEmission = 0.1,
	})
	shake(scope, payload.position, 0.35, 0.3, payload.startedAt or workspace:GetServerTimeNow())
	return 1.2
end

function KINDS.spit(payload, scope): number
	local velocity = payload.velocity
	local landing = payload.landing
	local seconds = tonumber(payload.seconds)
	local gravity = tonumber(payload.gravity)
	if typeof(velocity) ~= "Vector3" or typeof(landing) ~= "Vector3" or not seconds or not gravity then
		return 0
	end
	local origin = payload.position
	local start = if type(payload.startedAt) == "number" then payload.startedAt else workspace:GetServerTimeNow()
	if workspace:GetServerTimeNow() - start >= seconds then
		return 0
	end
	local fall = Vector3.new(0, -gravity, 0)
	local function at(t: number): Vector3
		return origin + velocity * t + fall * (0.5 * t * t)
	end

	local glob = host(scope, at(math.max(0, workspace:GetServerTimeNow() - start)))
	local core = emitter("Void", glob, {
		Color = tint(Colors.bile, Colors.rot),
		Size = sizes(1.6, 1.3, 0.6),
		Transparency = sequence(0.05, 0.6),
		Lifetime = NumberRange.new(0.18, 0.25),
		Speed = NumberRange.new(0),
		LightEmission = 0.2,
	})
	core.Rate = 50
	core.Enabled = true
	local trail = emitter("DarkFire", glob, {
		Color = tint(Colors.ichor, Colors.bile),
		Size = sizes(1.2, 0.9, 0),
		Transparency = sequence(0.1, 1),
		Lifetime = NumberRange.new(0.25, 0.4),
		Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180),
		FlipbookFramerate = NumberRange.new(30),
		LightEmission = 0.5,
	})
	trail.Rate = 45
	trail.Enabled = true
	local drips = emitter("Embers", glob, {
		Color = tint(Colors.ichor),
		Size = sizes(0, 0.35, 0),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(1, 3),
		Acceleration = Vector3.new(0, -30, 0),
		Drag = 1,
		LightEmission = 0.6,
	})
	drips.Rate = 20
	drips.Enabled = true

	local connection
	connection = scope:add(RunService.Heartbeat:Connect(function()
		local t = workspace:GetServerTimeNow() - start
		if t >= seconds then
			glob.CFrame = CFrame.new(landing)
			core.Enabled, trail.Enabled, drips.Enabled = false, false, false
			connection:Disconnect()
			return
		end
		glob.CFrame = CFrame.new(at(t))
	end))
	return seconds + 0.6
end

function KINDS.splash(payload, scope): number
	local normal = if typeof(payload.normal) == "Vector3" and payload.normal.Magnitude > 0.1 then payload.normal.Unit else Vector3.yAxis
	local point = host(scope, payload.position + normal * 0.3)
	faceAlong(point, normal)

	burst("DarkFire", point, 6, {
		Color = tint(Colors.ichor, Colors.bile),
		Size = sizes(1, 2.4, 0),
		Transparency = sequence(0.1, 1),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(60, 60),
		Lifetime = NumberRange.new(0.4, 0.6),
		FlipbookFramerate = NumberRange.new(26),
		LightEmission = 0.5,
		Drag = 3,
	})
	burst("Embers", point, 14, {
		Color = tint(Colors.ichor),
		Size = sizes(0, 0.5, 0),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -60, 0),
		Lifetime = NumberRange.new(0.5, 0.8),
		Drag = 2,
		LightEmission = 0.7,
	})
	burst("Smoke", point, 3, {
		Color = tint(Colors.bile, Colors.rot),
		Size = sizes(1.5, 3, 4),
		Speed = NumberRange.new(2, 5),
		Lifetime = NumberRange.new(1, 1.6),
		LightEmission = 0.2,
		Transparency = sequence(0.5, 1),
	})
	if type(payload.blocks) == "table" and #payload.blocks > 0 then
		rocks(point, payload.blocks, 6, {
			Size = sizes(0, 0.8, 0.2),
			Speed = NumberRange.new(12, 22),
			SpreadAngle = Vector2.new(50, 50),
			Acceleration = Vector3.new(0, -90, 0),
			Drag = 1,
			Lifetime = NumberRange.new(0.5, 0.8),
		})
	end
	glow(scope, point, Colors.ichor, 10, 2, 0.5)
	return 2
end

function KINDS.sinkwarn(payload, scope): number
	local radius = tonumber(payload.radius) or 9
	local seconds = (tonumber(payload.seconds) or 1.4) - age(payload)
	if seconds <= 0.05 then
		return 0
	end
	local centre = payload.position + Vector3.new(0, 0.2, 0)
	local point = host(scope, centre)
	local area = host(scope, centre, Vector3.new(radius * 2, 0.2, radius * 2))

	crack(point, radius * 2.6, seconds + 0.6)
	pulses(scope, point, radius * 2.2, seconds, Colors.ichor)
	stream(scope, "Smoke", area, 24, seconds, {
		Color = tint(Colors.dust, Colors.rot),
		Size = sizes(1.5, 3.5, 5),
		Speed = NumberRange.new(3, 8),
		SpreadAngle = Vector2.new(20, 20),
		Lifetime = NumberRange.new(0.9, 1.4),
		LightEmission = 0.1,
	})
	stream(scope, "Rock", area, 30, seconds, {
		Color = tint(Colors.dust),
		Size = sizes(0, 0.6, 0),
		Speed = NumberRange.new(8, 14),
		SpreadAngle = Vector2.new(20, 20),
		Acceleration = Vector3.new(0, -80, 0),
		Drag = 2,
		Lifetime = NumberRange.new(0.4, 0.6),
	})
	shake(scope, centre, 1, seconds, workspace:GetServerTimeNow(), true)
	return seconds + 1.5
end

function KINDS.collapse(payload, scope): number
	local radius = tonumber(payload.radius) or 9
	local depth = tonumber(payload.depth) or 12
	local centre = payload.position
	local area = host(scope, centre + Vector3.new(0, 1, 0), Vector3.new(radius * 1.8, 0.5, radius * 1.8))
	local point = host(scope, centre + Vector3.new(0, 0.5, 0))

	rocks(area, payload.blocks, 40, {
		Size = sizes(0, 1.3, 0.5),
		Speed = NumberRange.new(4, 12),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -110, 0),
		Drag = 0.5,
		Lifetime = NumberRange.new(0.5, 0.9),
	})
	burst("Smoke", area, 22, {
		Color = tint(Colors.dust, Colors.rot),
		Size = sizes(3, 6, 9),
		Speed = NumberRange.new(6, 16),
		SpreadAngle = Vector2.new(30, 30),
		Lifetime = NumberRange.new(1.6, 2.6),
		Drag = 1.5,
		LightEmission = 0.1,
	})
	dustRing(point, radius * 3, Colors.dust)
	burst("PressureRing", point, 1, {
		Size = scaled(Library.PressureRing.Size, radius / 18),
		Color = tint(Colors.shadow),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.zero,
	})
	-- Dust boiling up out of the pit after it, from the bottom.
	local bottom = host(scope, centre - Vector3.new(0, depth * 0.6, 0), Vector3.new(radius, 0.5, radius))
	stream(scope, "Smoke", bottom, 10, 1.2, {
		Color = tint(Colors.dust),
		Size = sizes(2, 5, 7),
		Speed = NumberRange.new(8, 14),
		SpreadAngle = Vector2.new(15, 15),
		Lifetime = NumberRange.new(1, 1.6),
		Drag = 1,
		LightEmission = 0.1,
	})
	shake(scope, centre, 1.5, 1, payload.startedAt or workspace:GetServerTimeNow())
	return 3
end

function KINDS.burst(payload, scope): number
	local radius = tonumber(payload.radius) or 3
	local point = host(scope, payload.position, Vector3.one * math.max(1, radius))

	burst("DarkFire", point, 14, {
		Color = tint(Colors.ichor, Colors.bile),
		Size = sizes(radius * 0.8, radius * 1.8, 0),
		Transparency = sequence(0.05, 1),
		Speed = NumberRange.new(10, 26),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.5, 0.8),
		FlipbookFramerate = NumberRange.new(24),
		LightEmission = 0.5,
		Drag = 3,
	})
	burst("Embers", point, 26, {
		Color = tint(Colors.ichor),
		Size = sizes(0, 0.6, 0),
		Speed = NumberRange.new(14, 30),
		Acceleration = Vector3.new(0, -50, 0),
		Lifetime = NumberRange.new(0.6, 1),
		Drag = 2,
		LightEmission = 0.7,
	})
	burst("Rock", point, 12, {
		Color = tint(Colors.bruise, Colors.rot),
		Size = sizes(0, 1, 0.4),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -90, 0),
		Lifetime = NumberRange.new(0.6, 1),
		Drag = 1.5,
	})
	burst("Void", point, 5, {
		Color = tint(Colors.rot, Colors.shadow),
		Size = sizes(radius, radius * 2.2, radius * 2.6),
		Transparency = sequence(0.2, 1),
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.5, 0.7),
	})
	burst("Flash", point, 1, {
		Color = tint(Colors.pale),
		Size = scaled(Library.Flash.Size, radius / 2),
	})
	glow(scope, point, Colors.ichor, radius * 6, 4, 0.7)
	shake(scope, payload.position, 1, 0.6, payload.startedAt or workspace:GetServerTimeNow())
	return 2
end

function KINDS.brood(payload, scope): number
	local look = if typeof(payload.look) == "Vector3" and payload.look.Magnitude > 0.1 then payload.look.Unit else Vector3.yAxis
	local point = host(scope, payload.position)
	-- Emitting from the host's top face, so the host is turned to face along
	-- the mouth.
	faceAlong(point, look)

	burst("DarkFire", point, 12, {
		Color = tint(Colors.ichor, Colors.bile),
		Size = sizes(1.5, 3, 0),
		Transparency = sequence(0.05, 1),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(25, 25),
		Lifetime = NumberRange.new(0.5, 0.8),
		FlipbookFramerate = NumberRange.new(24),
		LightEmission = 0.5,
		Acceleration = Vector3.new(0, -30, 0),
		Drag = 2,
	})
	burst("Embers", point, 20, {
		Color = tint(Colors.ichor),
		Size = sizes(0, 0.5, 0),
		Speed = NumberRange.new(12, 24),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, -50, 0),
		Lifetime = NumberRange.new(0.6, 1),
		Drag = 1.5,
		LightEmission = 0.7,
	})
	glow(scope, point, Colors.ichor, 18, 3, 0.8)
	return 2
end

function KINDS.death(payload, scope): number
	local points = payload.points
	if type(points) ~= "table" or #points == 0 then
		return 0
	end
	local gap = math.clamp(tonumber(payload.gap) or 0.06, 0.02, 0.2)
	local late = age(payload)

	for index, position in ipairs(points) do
		if typeof(position) == "Vector3" then
			scope:delay(math.max(0, (index - 1) * gap - late), function()
				local point = host(scope, position, Vector3.one * 2)
				burst("DarkFire", point, 8, {
					Color = tint(Colors.ichor, Colors.bile),
					Size = sizes(1.5, 3.5, 0),
					Transparency = sequence(0.05, 1),
					Speed = NumberRange.new(8, 20),
					SpreadAngle = Vector2.new(180, 180),
					Lifetime = NumberRange.new(0.5, 0.8),
					FlipbookFramerate = NumberRange.new(24),
					LightEmission = 0.5,
					Drag = 3,
				})
				burst("Embers", point, 12, {
					Color = tint(Colors.ichor),
					Size = sizes(0, 0.6, 0),
					Speed = NumberRange.new(12, 26),
					Acceleration = Vector3.new(0, -50, 0),
					Lifetime = NumberRange.new(0.6, 1),
					Drag = 2,
					LightEmission = 0.7,
				})
				burst("Smoke", point, 3, {
					Color = tint(Colors.rot, Colors.dust),
					Size = sizes(2, 4, 6),
					Speed = NumberRange.new(3, 8),
					Lifetime = NumberRange.new(1, 1.6),
					LightEmission = 0.1,
				})
				if index == #points then
					burst("Flash", point, 1, {
						Color = tint(Colors.pale),
						Size = scaled(Library.Flash.Size, 3),
					})
					glow(scope, point, Colors.ichor, 40, 5, 1.2)
					shake(scope, position, 1.6, 1, workspace:GetServerTimeNow())
				end
			end)
		end
	end
	return #points * gap + 2.5
end

function BlightborerVFX.play(payload, scope): number
	local draw = KINDS[payload.kind]
	if not draw then
		return 0
	end
	return draw(payload, scope)
end

return BlightborerVFX
