--[[
	SignusVFX

	The one-shot, client-drawn half of Signus's spells: the bursts, flashes
	and kicks that ServerScriptService.Bosses.Signus asks for over the
	`BossEffect` remote (see StarterPlayerScripts.BossEffectClient).

		SignusVFX.play(payload, scope) -> seconds it needs

	WHY THIS HALF IS HERE AND THE OTHER HALF IS NOT

	The server keeps everything that PROMISES something: a sigil on the ground
	that says where the moon lands, a crack that says which blocks go, a
	crescent in flight. Those are parts, beams, trails and lights, which
	replicate as instances and show the same thing to everyone. What the
	server cannot do is fire a particle burst on a client - Emit is a call,
	not a property - so every burst is asked for here, drawn locally, and
	thrown away by the scope it ran in.

	One kind per spell beat, named by the server:

	  cast      the release puff between the sleeves
	  shatter   a crescent breaking on a block or a player
	  lock      the Moonfall sigil snapping to its target
	  impact    the moon shard landing: shockwave, scorch, dust, streaks
	  erupt     the fissure cells tearing open, in order
	  step      the Veil Step unfolding
	  lunge     the crescent blade shattering on arrival
	  totality  the eclipse forming at the phase change
	  nova      the Eclipse Nova: black sphere, corona, wave, kick, flash
	  death     the collapse

	THE PALETTE is the boss's own: plum, violet, orchid, pearl, with the opal
	clasp's teal and gold only in the finishers. The textures are the four
	EclipseVFX already loads, so nothing here is an id that has never been
	seen to work in this place.

	Everything is bounded: one anchor part per effect with a handful of
	emitters on it, counts fixed below, and the scope's backstop destroys the
	lot whatever happened in between.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local SignusVFX = {}

local DUST = "rbxassetid://7216854921"
local STREAK = "rbxassetid://9544366974"
local GLOW = "rbxassetid://9544354287"
local SCORCH = "rbxassetid://82556288879264"

local Colors = {
	plum = Color3.fromRGB(58, 18, 78),
	violet = Color3.fromRGB(142, 64, 220),
	orchid = Color3.fromRGB(236, 120, 255),
	pearl = Color3.fromRGB(255, 236, 246),
	teal = Color3.fromRGB(120, 240, 230),
	gold = Color3.fromRGB(255, 214, 120),
	black = Color3.new(0, 0, 0),
}

-- Camera kick and screen flash reach, for the nova and the death.
local KICK_REACH = 60

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function fxPart(scope, size: Vector3, color: Color3, transparency: number, cframe: CFrame): Part
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
	part.Massless = true
	part.CFrame = cframe
	part.Parent = Workspace
	scope:add(part)
	return part
end

-- An invisible part to hang emitters off; a volume, so emitters on it spread
-- across it rather than firing from one point.
local function anchor(scope, position: Vector3, size: number?): Part
	local part = fxPart(scope, Vector3.one * (size or 1), Colors.black, 1, CFrame.new(position))
	part.Material = Enum.Material.SmoothPlastic
	return part
end

local function pair(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) })
end

local function fade(start: number, finish: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, start), NumberSequenceKeypoint.new(1, finish) })
end

local function sizes(start: number, mid: number, finish: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, start),
		NumberSequenceKeypoint.new(0.4, mid),
		NumberSequenceKeypoint.new(1, finish),
	})
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightEmission = 0.9
	e.LightInfluence = 0
	e.Rate = 0
	for name, value in pairs(props) do
		(e :: any)[name] = value
	end
	e.Parent = parent
	return e
end

-- Streaks drawn along their own motion, thrown out of a volume.
local function streaks(parent: Instance, color: Color3, speed: number, life: number, size: number): ParticleEmitter
	return emitter(parent, {
		Texture = STREAK,
		Color = pair(Colors.pearl, color),
		Size = sizes(size * 0.4, size, 0),
		Transparency = fade(0, 1),
		Lifetime = NumberRange.new(life * 0.6, life),
		Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(180, 180),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Drag = 2,
		Acceleration = Vector3.new(0, -6, 0),
	})
end

-- Soft dots that drift up and out: motes.
local function motes(parent: Instance, color: Color3, speed: number, life: number, size: number): ParticleEmitter
	return emitter(parent, {
		Texture = GLOW,
		Color = pair(Colors.pearl, color),
		Size = sizes(0, size, 0),
		Transparency = fade(0.1, 1),
		Lifetime = NumberRange.new(life * 0.7, life),
		Speed = NumberRange.new(speed * 0.3, speed),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 4, 0),
		Drag = 1.5,
		Rotation = NumberRange.new(0, 360),
	})
end

local function dust(parent: Instance, color: Color3, speed: number, life: number, size: number): ParticleEmitter
	return emitter(parent, {
		Texture = DUST,
		Color = pair(color, Colors.plum),
		Size = sizes(size * 0.5, size, size * 1.6),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.3, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(life * 0.7, life),
		Speed = NumberRange.new(speed * 0.4, speed),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 2, 0),
		Drag = 3,
		LightEmission = 0.2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
	})
end

-- The one-shot scorch flipbook, laid flat on the ground.
local function scorch(parent: Instance, color: Color3, size: number, life: number)
	local att = Instance.new("Attachment")
	att.CFrame = CFrame.Angles(math.rad(90), 0, 0)
	att.Parent = parent
	local e = emitter(att, {
		Texture = SCORCH,
		Color = pair(Colors.pearl, color),
		Size = sizes(size * 0.8, size, size),
		Transparency = fade(0, 1),
		Lifetime = NumberRange.new(life, life),
		Speed = NumberRange.new(0, 0),
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(16 / life, 16 / life),
	})
	e:Emit(1)
end

-- A flat ring of light that runs out across the ground and fades.
local function wave(scope, centre: Vector3, radius: number, seconds: number, color: Color3, thickness: number?)
	local ring = fxPart(scope, Vector3.new(thickness or 0.35, 1, 1), color, 0.1,
		CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90)))
	ring.Shape = Enum.PartType.Cylinder
	scope:tween(ring, TweenInfo.new(seconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(thickness or 0.35, radius * 2, radius * 2),
		Transparency = 1,
	})
end

-- A sphere of light that swells and fades.
local function flare(scope, centre: Vector3, radius: number, seconds: number, color: Color3, startTransparency: number?)
	local ball = fxPart(scope, Vector3.one * 1, color, startTransparency or 0.2, CFrame.new(centre))
	ball.Shape = Enum.PartType.Ball
	scope:tween(ball, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	})
	return ball
end

local function light(scope, parent: Instance, color: Color3, range: number, brightness: number, seconds: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	scope:add(l)
	scope:tween(l, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 })
end

local function distanceToViewer(position: Vector3): number
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		return (root.Position - position).Magnitude
	end
	local camera = Workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else math.huge
end

--[[
	A camera kick, strongest at the centre and nothing past KICK_REACH. It
	decays as a square so it hits and lets go; a wobble that outlasts the
	sound reads as a bug. Applied through CFrame offsets on the camera each
	frame and removed by the scope.
]]
local function kick(scope, centre: Vector3, strength: number, seconds: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local distance = distanceToViewer(centre)
	if distance > KICK_REACH then
		return
	end
	local power = strength * (1 - distance / KICK_REACH)
	local began = os.clock()
	local connection
	connection = game:GetService("RunService").RenderStepped:Connect(function()
		local alpha = (os.clock() - began) / seconds
		if alpha >= 1 then
			connection:Disconnect()
			return
		end
		local decay = (1 - alpha) * (1 - alpha) * power
		camera.CFrame = camera.CFrame * CFrame.new(
			(math.random() - 0.5) * decay,
			(math.random() - 0.5) * decay,
			0
		) * CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * decay * 0.8))
	end)
	scope:add(connection)
end

-- A whole-screen flash: colour and light, local to this viewer, over fast.
local function flash(scope, centre: Vector3, color: Color3, strength: number, seconds: number)
	local distance = distanceToViewer(centre)
	if distance > KICK_REACH * 1.6 then
		return
	end
	local power = strength * (1 - distance / (KICK_REACH * 1.6))
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "SignusFlash"
	effect.TintColor = Colors.pearl:Lerp(color, 0.4)
	effect.Brightness = 0.55 * power
	effect.Contrast = 0.2 * power
	effect.Saturation = -0.4 * power
	effect.Parent = Lighting
	scope:add(effect)
	scope:tween(effect, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1),
	})
end

-- ---------------------------------------------------------------------------
-- The kinds
-- ---------------------------------------------------------------------------

local kinds = {}

function kinds.cast(payload, scope)
	local at = anchor(scope, payload.position, 1.5)
	local color = if typeof(payload.color) == "Color3" then payload.color else Colors.orchid
	motes(at, color, 10, 0.6, 1.2):Emit(18)
	streaks(at, color, 24, 0.4, 2):Emit(10)
	flare(scope, payload.position, 2.2, 0.35, Colors.pearl)
	light(scope, at, color, 18, 2, 0.4)
	return 1
end

function kinds.shatter(payload, scope)
	local at = anchor(scope, payload.position, 1)
	local color = if typeof(payload.color) == "Color3" then payload.color else Colors.orchid
	streaks(at, color, 34, 0.6, 2.4):Emit(22)
	motes(at, Colors.pearl, 8, 0.7, 1):Emit(10)
	flare(scope, payload.position, 3, 0.3, Colors.pearl, 0.1)
	-- A ring on the surface it broke on, when the server knows which way
	-- that surface faces.
	if typeof(payload.normal) == "Vector3" and payload.normal.Magnitude > 0.5 then
		local ring = fxPart(scope, Vector3.new(0.25, 1, 1), color, 0.1,
			CFrame.lookAt(payload.position, payload.position + payload.normal) * CFrame.Angles(0, math.rad(90), 0))
		ring.Shape = Enum.PartType.Cylinder
		scope:tween(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.25, 7, 7), Transparency = 1,
		})
	end
	light(scope, at, color, 16, 2.5, 0.35)
	return 1.2
end

function kinds.lock(payload, scope)
	wave(scope, payload.position + Vector3.new(0, 0.3, 0), (payload.radius or 7) * 1.1, 0.5, Colors.pearl, 0.5)
	local at = anchor(scope, payload.position + Vector3.new(0, 0.5, 0), (payload.radius or 7) * 1.4)
	motes(at, Colors.orchid, 6, 0.8, 0.9):Emit(24)
	return 1
end

function kinds.impact(payload, scope)
	local radius = payload.radius or 7
	local centre = payload.position
	local at = anchor(scope, centre + Vector3.new(0, 0.6, 0), 2)

	wave(scope, centre + Vector3.new(0, 0.3, 0), radius * 2.4, 0.7, Colors.pearl, 0.6)
	wave(scope, centre + Vector3.new(0, 0.2, 0), radius * 1.6, 0.5, Colors.violet, 0.4)
	flare(scope, centre + Vector3.new(0, 1, 0), radius * 0.9, 0.45, Colors.pearl, 0)
	scorch(at, Colors.violet, radius * 2.2, 1.4)
	streaks(at, Colors.orchid, 46, 0.9, 3):Emit(48)
	dust(at, Colors.violet, 18, 2.2, 6):Emit(26)
	motes(at, Colors.pearl, 14, 1.6, 1.4):Emit(30)
	light(scope, at, Colors.orchid, 44, 5, 0.8)
	kick(scope, centre, 1.4, 0.45)
	return 2.6
end

function kinds.erupt(payload, scope)
	local positions = payload.positions
	if type(positions) ~= "table" then
		return 0
	end
	local delays = payload.delays
	local count = 0
	for index, position in ipairs(positions) do
		if typeof(position) ~= "Vector3" then
			continue
		end
		count += 1
		if count > 24 then
			break
		end
		local delay = if type(delays) == "table" and type(delays[index]) == "number" then delays[index] else 0
		scope:delay(delay, function()
			local at = anchor(scope, position + Vector3.new(0, 1, 0), 3)
			streaks(at, Colors.orchid, 30, 0.7, 2.2):Emit(14)
			dust(at, Colors.violet, 10, 1.6, 4):Emit(8)
			motes(at, Colors.pearl, 10, 1.2, 1):Emit(8)
			-- A column of light stabbing up out of the cell.
			local column = fxPart(scope, Vector3.new(1.2, 1, 1.2), Colors.pearl, 0.1, CFrame.new(position + Vector3.new(0, 0.5, 0)))
			scope:tween(column, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.5, 14, 0.5), CFrame = CFrame.new(position + Vector3.new(0, 7, 0)), Transparency = 1,
			})
			light(scope, at, Colors.orchid, 14, 2, 0.4)
		end)
	end
	kick(scope, payload.position, 0.9, 0.5)
	return 2.5
end

function kinds.step(payload, scope)
	local at = anchor(scope, payload.position, 6)
	motes(at, Colors.orchid, 6, 0.9, 1.2):Emit(32)
	streaks(at, Colors.pearl, 14, 0.5, 1.6):Emit(10)
	return 1.2
end

function kinds.lunge(payload, scope)
	local at = anchor(scope, payload.position, 3)
	streaks(at, Colors.orchid, 40, 0.7, 3):Emit(40)
	motes(at, Colors.pearl, 10, 1, 1.4):Emit(20)
	wave(scope, payload.position + Vector3.new(0, 0.3, 0), 14, 0.5, Colors.violet, 0.5)
	flare(scope, payload.position, 5, 0.4, Colors.pearl, 0.1)
	light(scope, at, Colors.orchid, 30, 3, 0.5)
	kick(scope, payload.position, 0.9, 0.35)
	return 1.4
end

function kinds.totality(payload, scope)
	local centre = payload.position
	local at = anchor(scope, centre, 10)
	-- Pearl rays streaming down, then the world goes dim around a flash.
	emitter(at, {
		Texture = STREAK,
		Color = pair(Colors.pearl, Colors.orchid),
		Size = sizes(2, 5, 0),
		Transparency = fade(0.1, 1),
		Lifetime = NumberRange.new(1.2, 1.8),
		Speed = NumberRange.new(14, 22),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(30, 30),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	}):Emit(60)
	motes(at, Colors.orchid, 12, 2.4, 1.8):Emit(60)
	streaks(at, Colors.teal, 30, 1.2, 2):Emit(16)
	streaks(at, Colors.gold, 30, 1.2, 2):Emit(16)
	flare(scope, centre, 24, 1.2, Colors.plum, 0.3)
	flare(scope, centre, 16, 0.8, Colors.pearl, 0.1)
	wave(scope, centre - Vector3.new(0, (payload.drop or 12), 0), 40, 1.4, Colors.orchid, 0.6)
	light(scope, at, Colors.orchid, 90, 6, 1.8)
	flash(scope, centre, Colors.violet, 1, 1.2)
	kick(scope, centre, 0.8, 0.8)
	return 3.5
end

function kinds.nova(payload, scope)
	local centre = payload.position
	local radius = payload.radius or 26
	local at = anchor(scope, centre, 4)

	-- The eclipse: a black sphere inside a pink corona, both growing. The
	-- void is opaque and in front, so what is seen is a black disc ringed with
	-- fire.
	local corona = fxPart(scope, Vector3.one, Colors.orchid, 0.1, CFrame.new(centre))
	corona.Shape = Enum.PartType.Ball
	local void = fxPart(scope, Vector3.one, Colors.black, 0, CFrame.new(centre))
	void.Shape = Enum.PartType.Ball
	void.Material = Enum.Material.SmoothPlastic
	scope:tween(corona, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 1.3, Transparency = 1,
	})
	scope:tween(void, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 1.0, Transparency = 1,
	})

	wave(scope, centre + Vector3.new(0, 0.3, 0), radius * 2.1, 0.9, Colors.pearl, 1.2)
	wave(scope, centre + Vector3.new(0, 0.2, 0), radius * 2.0, 1.1, Colors.plum, 2.4)
	wave(scope, centre + Vector3.new(0, 0.4, 0), radius * 1.4, 0.6, Colors.orchid, 0.8)

	-- A pillar of light, up and gone.
	local pillar = fxPart(scope, Vector3.new(6, 2, 6), Colors.pearl, 0.1, CFrame.new(centre))
	scope:tween(pillar, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(2, 160, 2), CFrame = CFrame.new(centre + Vector3.new(0, 80, 0)), Transparency = 1,
	})

	streaks(at, Colors.orchid, 70, 1.2, 4):Emit(70)
	streaks(at, Colors.pearl, 40, 0.8, 2.5):Emit(30)
	dust(at, Colors.violet, 26, 3, 9):Emit(40)
	motes(at, Colors.pearl, 18, 2.2, 1.8):Emit(50)
	scorch(at, Colors.violet, radius * 1.6, 1.6)
	light(scope, at, Colors.orchid, 120, 8, 1.2)
	flash(scope, centre, Colors.pearl, 1.4, 0.7)
	kick(scope, centre, 2.4, 0.8)
	return 4
end

function kinds.death(payload, scope)
	local centre = payload.position
	local at = anchor(scope, centre, 6)
	local void = fxPart(scope, Vector3.one, Colors.black, 0, CFrame.new(centre))
	void.Shape = Enum.PartType.Ball
	void.Material = Enum.Material.SmoothPlastic
	local corona = fxPart(scope, Vector3.one, Colors.orchid, 0.1, CFrame.new(centre))
	corona.Shape = Enum.PartType.Ball
	scope:tween(void, TweenInfo.new(1.0, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * 26, Transparency = 1,
	})
	scope:tween(corona, TweenInfo.new(1.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * 34, Transparency = 1,
	})
	wave(scope, centre - Vector3.new(0, (payload.drop or 9), 0), 36, 1.2, Colors.pearl, 0.8)
	streaks(at, Colors.orchid, 50, 1.4, 3.5):Emit(60)
	streaks(at, Colors.teal, 36, 1.4, 2):Emit(12)
	streaks(at, Colors.gold, 36, 1.4, 2):Emit(12)
	motes(at, Colors.pearl, 12, 3, 2):Emit(70)
	dust(at, Colors.plum, 14, 3, 8):Emit(24)
	light(scope, at, Colors.orchid, 90, 7, 2)
	flash(scope, centre, Colors.violet, 1.1, 1.0)
	kick(scope, centre, 1.6, 0.7)
	return 4
end

function SignusVFX.play(payload, scope): number
	local draw = kinds[payload.kind]
	if not draw then
		return 0
	end
	return draw(payload, scope) or 1
end

return SignusVFX
