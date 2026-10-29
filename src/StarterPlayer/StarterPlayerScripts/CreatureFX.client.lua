--[[
	CreatureFX

	Draws the voxel creatures' signature moves from the server's CreatureFX
	messages (ServerScriptService.Creatures.CreatureKit). The server has
	already decided everything - where the laser went, how the snowball
	flies - and this only shows it.

	  charge   (model, eye, seconds, lockAfter, aim)
	                                              the Lasereye gathering, with a thin aim line
	                                              that follows a character until it locks, or
	                                              points at a fixed spot
	  lock     (model, aim)                       the aim line stops following
	  sweep    (model, eye, base, pitch, from, to, seconds, length)
	                                              the raking beam, swung through its arc
	  laser    (model, eye, finish, seconds)      the lance
	  cancel   (model)                            a charge that will not fire
	  throw    (id, origin, velocity, gravity)    a snowball on the server's own arc
	  splash   (id, point)                        where it burst
	  spin     (model, seconds, radius)           the Snowman's broom spin
	  dive     (model, seconds)                   a streak behind a darting wasp or swooping bird
	  strike   (model, seconds)                   the Cobra's bite
	  flare    (model, color)                     the one-beat tell before a move

	Every visible effect is an authored particle, Beam or Trail from
	Shared.Enemies.CreatureParticles; Parts are invisible emitter hosts,
	except the snowball, which is the projectile itself.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Library = require(Shared:WaitForChild("Enemies"):WaitForChild("CreatureParticles"))
local Rigs = require(Shared:WaitForChild("Enemies"):WaitForChild("CreatureRigs"))

--[[
	The few effect building blocks used below: invisible emitter hosts,
	library emitters, beams, trails and sounds. Kept here rather than shared
	with the ability VFX so the creatures do not depend on that code.
]]
local Kit = {}

-- Library fields that are not emitter properties.
local META = { count = true }

function Kit.host(parent, name, cframe)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Transparency = name, Vector3.one * 0.2, 1
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.CFrame, p.Parent = cframe, parent
	return p
end

function Kit.attachment(parent)
	local a = Instance.new("Attachment")
	a.Parent = parent
	return a
end

-- A disabled emitter from `library[kind]` with `props` over it. Layout first:
-- the flipbook properties depend on it, and table order is not fixed.
function Kit.emitter(library, kind, parent, props)
	local data = library[kind]
	assert(data, "no library entry " .. tostring(kind))
	local p = Instance.new("ParticleEmitter")
	p.Name = kind
	if data.FlipbookLayout then p.FlipbookLayout = data.FlipbookLayout end
	for key, value in pairs(data) do
		if not META[key] then p[key] = value end
	end
	p.Enabled, p.Rate = false, 0
	for key, value in pairs(props or {}) do p[key] = value end
	p.Parent = parent
	return p
end

function Kit.beam(parent, a0, a1, props)
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1, beam.LightInfluence = a0, a1, 0
	for key, value in pairs(props) do beam[key] = value end
	beam.Parent = parent
	return beam
end

function Kit.trail(parent, a0, a1, props)
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1, trail.LightInfluence = a0, a1, 0
	for key, value in pairs(props) do trail[key] = value end
	trail.Parent = parent
	return trail
end

-- Beam transparency without rebuilding the sequence every frame.
function Kit.opacity(beam, value)
	local transparency = 1 - math.clamp(value, 0, 1)
	if beam.Transparency.Keypoints[1].Value ~= transparency then
		beam.Transparency = NumberSequence.new(transparency)
	end
	local on = transparency < 0.99
	if beam.Enabled ~= on then beam.Enabled = on end
end

function Kit.sound(parent, id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed = id, volume or 0.5, pitch or 1
	s.RollOffMinDistance, s.RollOffMaxDistance = 12, 180
	s.Parent = parent
	s:Play()
	return s
end

-- Fetches the textures and sounds in the background, each through a Decal or
-- Sound, since bare content strings do not reliably fetch images.
function Kit.preload(library, sounds)
	task.spawn(function()
		local assets = {}
		for _, data in pairs(library) do
			local decal = Instance.new("Decal")
			decal.Texture = data.Texture
			table.insert(assets, decal)
		end
		for _, id in ipairs(sounds) do
			local sound = Instance.new("Sound")
			sound.SoundId = id
			table.insert(assets, sound)
		end
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(assets) end)
		for _, asset in ipairs(assets) do asset:Destroy() end
	end)
end

local CreatureFX = Remotes.wait("CreatureFX")

local SOUND_HIT = "rbxasset://sounds/hit.wav"

local LASER_RED = Color3.fromRGB(255, 45, 30)
local LASER_HOT = Color3.fromRGB(255, 110, 80)
local SNOW = Color3.fromRGB(235, 245, 255)

local folder = Instance.new("Folder")
folder.Name = "CreatureFX"
folder.Parent = workspace

Kit.preload(Library, { SOUND_HIT })

local function emitter(kind, parent, props)
	return Kit.emitter(Library, kind, parent, props)
end

local function scaled(sequence: NumberSequence, k: number): NumberSequence
	local points = {}
	for _, p in ipairs(sequence.Keypoints) do
		table.insert(points, NumberSequenceKeypoint.new(p.Time, p.Value * k, p.Envelope * k))
	end
	return NumberSequence.new(points)
end

-- A one-off burst at a point: { kind, count, props } layers on one host.
local function burst(position: Vector3, layers, life: number?)
	local host = Kit.host(folder, "CreatureBurst", CFrame.new(position))
	for _, layer in ipairs(layers) do
		local e = emitter(layer[1], host, layer[3])
		e:Emit(layer[2])
	end
	Debris:AddItem(host, life or 3)
	return host
end

local function body(model): BasePart?
	if typeof(model) ~= "Instance" or not model.Parent then
		return nil
	end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

-- The top of a model, for an attachment that should ride on its head.
local function topOf(model): Vector3
	local cframe, size = model:GetBoundingBox()
	return cframe.Position + Vector3.new(0, size.Y * 0.5, 0)
end

-- Runs `update(elapsed)` each frame for `seconds`, or until it returns false.
local function during(seconds: number, update, finish)
	local startedAt = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startedAt
		if elapsed >= seconds or update(elapsed) == false then
			connection:Disconnect()
			if finish then
				finish()
			end
		end
	end)
end

local handlers = {}

-- ---------------------------------------------------------------------------
-- Lasereye
-- ---------------------------------------------------------------------------

local LASER_WHITE = Color3.fromRGB(255, 236, 228)
local SCORCH = Color3.fromRGB(60, 40, 36)

local charges = {}

local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = color, range, brightness, false
	l.Parent = parent
	return l
end

--[[
	The beam both attacks share, three layers deep: a wide red glow, the
	pack's flowing fire core, and a thin white-hot line down the middle that
	keeps the centre reading as a beam rather than smoke. `scale` widens all
	three; setLaser fades and pulses them together.
]]
local function laserBeam(host, a0, a1, scale)
	local function layer(texture, color, width, emission, brightness, speed)
		return {
			width = width * scale,
			beam = Kit.beam(host, a0, a1, {
				Texture = texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1,
				TextureSpeed = speed or 0, Segments = 1, FaceCamera = true,
				Color = ColorSequence.new(color), LightEmission = emission, Brightness = brightness,
				Width0 = width * scale, Width1 = width * scale, Transparency = NumberSequence.new(0),
			}),
		}
	end
	return {
		layer(Library.LaserGlow.Texture, LASER_RED, 3.8, 1, 2, Library.LaserGlow.TextureSpeed),
		layer(Library.LaserCore.Texture, LASER_HOT, 1.6, 0.8, 3, Library.LaserCore.TextureSpeed),
		layer("", LASER_WHITE, 0.32, 1, 1),
	}
end

local function setLaser(layers, opacity: number, pulse: number)
	for i, layer in ipairs(layers) do
		Kit.opacity(layer.beam, opacity)
		local width = layer.width * (if i == 3 then 1 else pulse)
		layer.beam.Width0, layer.beam.Width1 = width, width
	end
end

local function endCharge(model)
	local charge = charges[model]
	if charge then
		charges[model] = nil
		charge.host:Destroy()
		charge.target:Destroy()
	end
end

--[[
	The eye gathering: rings drawn inward, a growing red core and light, and
	a thin aim line. `aim` is either a character (the lance: the line follows
	it until it locks) or a point (the sweep: where the rake will start).
]]
function handlers.charge(model, eye: Vector3, seconds: number, lockAfter: number, aim)
	endCharge(model)

	local host = Kit.host(folder, "LaserCharge", CFrame.new(eye))
	local target = Kit.host(folder, "LaserAim", CFrame.new(eye))
	local energy = emitter("ChargeEnergy", host, {
		Enabled = true, Rate = 9, Color = ColorSequence.new(LASER_RED), Size = scaled(Library.ChargeEnergy.Size, 0.7),
	})
	-- Dimmer than the pack's core, which blooms to white and loses the red.
	local core = emitter("ChargeCore", host, {
		Enabled = true, Rate = 30, Color = ColorSequence.new(LASER_RED), Size = NumberSequence.new(0.6),
		Brightness = 1.5, LightEmission = 0.6,
	})
	local glow = light(host, LASER_RED, 6, 0)

	local a0, a1 = Kit.attachment(host), Kit.attachment(target)
	local line = Kit.beam(host, a0, a1, {
		Texture = Library.LaserGlow.Texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1,
		Color = ColorSequence.new(LASER_RED), LightEmission = 1, FaceCamera = true, Segments = 1,
		Width0 = 0.12, Width1 = 0.12, Transparency = NumberSequence.new(0.8),
	})

	local charge = { host = host, target = target, locked = false }
	charges[model] = charge
	if typeof(aim) == "Vector3" then
		target.Position = aim
		charge.locked = true
	end

	during(seconds + 0.6, function(elapsed)
		if charges[model] ~= charge then
			return false
		end
		local k = math.clamp(elapsed / seconds, 0, 1)
		if not charge.locked then
			local root = typeof(aim) == "Instance" and aim.Parent and aim:FindFirstChild("HumanoidRootPart")
			if root then
				target.Position = root.Position
			end
		end

		-- Thickens and brightens as it gathers; flickers once it has locked.
		local width = 0.08 + 0.26 * k
		line.Width0, line.Width1 = width, width
		local opacity = 0.2 + 0.5 * k
		if charge.locked then
			opacity = if math.sin(elapsed * 60) > 0 then 0.95 else 0.55
		end
		Kit.opacity(line, opacity)
		core.Size = NumberSequence.new(0.5 + 1.4 * k)
		energy.Rate = 9 + 14 * k
		glow.Brightness = 0.5 + 2.5 * k
		glow.Range = 6 + 8 * k
	end, function()
		if charges[model] == charge then
			endCharge(model)
		end
	end)

	if typeof(aim) ~= "Vector3" then
		-- The server's "lock" carries the exact aim; this only stops the line
		-- chasing the character if that message is late.
		task.delay(lockAfter, function()
			charge.locked = true
		end)
	end
end

function handlers.lock(model, aim: Vector3)
	local charge = charges[model]
	if charge then
		charge.locked = true
		charge.target.Position = aim
	end
end

function handlers.cancel(model)
	endCharge(model)
end

-- Where a beam from `eye` along `direction` stops: the first thing it meets
-- that is not a creature, a player or an effect.
local beamParams = RaycastParams.new()
beamParams.FilterType = Enum.RaycastFilterType.Exclude

local function beamEnd(eye: Vector3, direction: Vector3, length: number): Vector3
	local exclude = { folder }
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then table.insert(exclude, enemies) end
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		if player.Character then table.insert(exclude, player.Character) end
	end
	beamParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(eye, direction * length, beamParams)
	return if hit then hit.Position else eye + direction * length
end

-- The muzzle and the impact: a flare that stays lit on the eye, and sparks,
-- a glow and a trail of scorch smoke wherever the beam lands.
local function laserEnds(host, far)
	local muzzle = emitter("Flare", host, {
		Enabled = true, Rate = 14, Color = ColorSequence.new(LASER_RED), Size = NumberSequence.new(3.2),
		Lifetime = NumberRange.new(0.25),
	})
	local sparks = emitter("BoomSparks", far, {
		Enabled = true, Rate = 80, Color = ColorSequence.new(Color3.fromRGB(255, 120, 60)),
		Speed = NumberRange.new(18, 30), Lifetime = NumberRange.new(0.35, 0.6), Size = NumberSequence.new(0.7, 0),
	})
	-- The pack glow runs at Brightness 50, which as a continuous stream on
	-- snow whites out the whole screen; a tenth of it still reads as heat.
	local heat = emitter("BoomGlow", far, {
		Enabled = true, Rate = 10, Color = ColorSequence.new(LASER_RED), Size = scaled(Library.BoomGlow.Size, 0.28),
		Brightness = 4, LightEmission = 0.7,
	})
	-- Not locked to the moving end, so the smoke stays where the beam passed.
	local scorch = emitter("Puff", far, {
		Enabled = true, Rate = 22, Color = ColorSequence.new(SCORCH), Size = NumberSequence.new(1.8),
		Lifetime = NumberRange.new(0.9), LockedToPart = false, Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, 3, 0),
	})
	return { muzzle, sparks, heat, scorch }, light(host, LASER_RED, 12, 2), light(far, LASER_HOT, 9, 1.5)
end

local function stopEmitters(list)
	for _, e in ipairs(list) do
		e.Enabled = false
	end
end

--[[
	The sweep: the beam rakes along the ground through an arc, recomputed every
	frame from the server's own numbers (base direction, pitch, start and end
	angle, duration) and stopped by whatever it meets.
]]
function handlers.sweep(model, eye: Vector3, base: Vector3, pitch: number, from: number, to: number, seconds: number, length: number)
	endCharge(model)

	local host = Kit.host(folder, "Sweep", CFrame.new(eye))
	local far = Kit.host(folder, "SweepEnd", CFrame.new(eye))
	local a0, a1 = Kit.attachment(host), Kit.attachment(far)
	local layers = laserBeam(host, a0, a1, 1)
	local emitters, eyeLight, endLight = laserEnds(host, far)
	Kit.sound(host, SOUND_HIT, 0.5, 0.55)

	during(seconds + 0.25, function(elapsed)
		local t = math.clamp(elapsed / seconds, 0, 1)
		local eased = t * t * (3 - 2 * t)
		local angle = math.rad(from + (to - from) * eased)
		local flat = (CFrame.Angles(0, angle, 0) * CFrame.new(base)).Position
		local direction = (flat * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)).Unit
		far.Position = beamEnd(eye, direction, length)

		local fade = if elapsed <= seconds then 1 else 1 - (elapsed - seconds) / 0.25
		if elapsed > seconds then
			stopEmitters(emitters)
		end
		setLaser(layers, fade, 1 + 0.12 * math.sin(elapsed * 45))
		eyeLight.Brightness, endLight.Brightness = 2 * fade, 1.5 * fade
	end, function()
		stopEmitters(emitters)
		Debris:AddItem(host, 1)
		Debris:AddItem(far, 1.2)
	end)
end

-- The lance: one heavy, straight, locked shot.
function handlers.laser(model, eye: Vector3, finish: Vector3, seconds: number)
	endCharge(model)

	local host = Kit.host(folder, "Laser", CFrame.new(eye))
	local far = Kit.host(folder, "LaserEnd", CFrame.new(finish))
	local a0, a1 = Kit.attachment(host), Kit.attachment(far)
	local layers = laserBeam(host, a0, a1, 1.35)
	local emitters, eyeLight, endLight = laserEnds(host, far)

	burst(eye, {
		{ "BoomGlow", 1, { Color = ColorSequence.new(LASER_RED), Size = scaled(Library.BoomGlow.Size, 0.45), Brightness = 8 } },
		{ "ChargeEnergy", 1, { Color = ColorSequence.new(LASER_HOT), Size = scaled(Library.ChargeEnergy.Size, 1.2) } },
	}, 1)
	burst(finish, {
		{ "BoomGlow", 1, { Color = ColorSequence.new(LASER_RED), Size = scaled(Library.BoomGlow.Size, 0.6), Brightness = 8 } },
		{ "BoomSparks", 22, { Color = ColorSequence.new(Color3.fromRGB(255, 120, 60)), Speed = NumberRange.new(30, 45) } },
		{ "Puff", 4, { Color = ColorSequence.new(SCORCH), Size = NumberSequence.new(3) } },
	}, 2)
	Kit.sound(far, SOUND_HIT, 0.6, 0.6)

	during(seconds + 0.2, function(elapsed)
		local fade = math.clamp(1 - (elapsed - seconds * 0.6) / (seconds * 0.4 + 0.2), 0, 1)
		if elapsed > seconds then
			stopEmitters(emitters)
		end
		setLaser(layers, fade, (1 + 0.15 * math.sin(elapsed * 50)) * (0.4 + 0.6 * fade))
		eyeLight.Brightness, endLight.Brightness = 2.5 * fade, 2 * fade
	end, function()
		stopEmitters(emitters)
		Debris:AddItem(host, 1)
		Debris:AddItem(far, 1.2)
	end)
end

-- ---------------------------------------------------------------------------
-- Snowman
-- ---------------------------------------------------------------------------

local snowballs = {}

local WEB = Color3.fromRGB(236, 240, 228)

-- `style` "web" is the spider's glob; anything else is a snowball.
function handlers.throw(id: string, origin: Vector3, velocity: Vector3, gravity: number, style: string?)
	-- The projectile itself: a packed block of snow, or a wad of web.
	local web = style == "web"
	local ball = Instance.new("Part")
	ball.Name = if web then "WebGlob" else "Snowball"
	ball.Size = Vector3.one * (if web then 0.8 else 1.1)
	ball.Material = if web then Enum.Material.Fabric else Enum.Material.Snow
	ball.Color = if web then WEB else SNOW
	ball.Anchored, ball.CanCollide, ball.CanTouch, ball.CanQuery = true, false, false, false
	ball.CFrame = CFrame.new(origin)
	ball.Parent = folder
	emitter("Puff", ball, {
		Enabled = true, Rate = if web then 24 else 14, Color = ColorSequence.new(if web then WEB else SNOW),
		Size = NumberSequence.new(if web then 0.6 else 1.1),
		Lifetime = NumberRange.new(if web then 0.25 else 0.35), LockedToPart = false,
	})
	snowballs[id] = ball

	local spin = CFrame.Angles(math.random() * 6, math.random() * 6, 0)
	during(3.5, function(t)
		if snowballs[id] ~= ball then
			return false
		end
		local point = origin + velocity * t + Vector3.new(0, -0.5 * gravity * t * t, 0)
		ball.CFrame = CFrame.new(point) * spin * CFrame.Angles(t * 9, t * 6, 0)
	end, function()
		if snowballs[id] == ball then
			snowballs[id] = nil
		end
		ball:Destroy()
	end)
end

function handlers.splash(id: string, point: Vector3, style: string?)
	local ball = snowballs[id]
	snowballs[id] = nil
	if ball then
		ball:Destroy()
	end
	if style == "web" then
		-- A splat of web: a white burst and a star of strands.
		local host = burst(point, {
			{ "Puff", 5, { Color = ColorSequence.new(WEB), Size = NumberSequence.new(1.8), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180) } },
			{ "Slash", 1, { Color = ColorSequence.new(WEB), Size = NumberSequence.new(3.5), LockedToPart = false } },
		}, 2)
		Kit.sound(host, SOUND_HIT, 0.35, 1.6)
		return
	end
	local host = burst(point, {
		{ "Puff", 6, { Color = ColorSequence.new(SNOW), Size = NumberSequence.new(2.6), Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(180, 180) } },
		{ "Glints", 5, { Color = ColorSequence.new(Color3.fromRGB(200, 235, 255)), Size = NumberSequence.new(0.8) } },
	}, 2)
	Kit.sound(host, SOUND_HIT, 0.45, 1.3)
end

-- The broom spin: a ring of snow thrown out to its reach, and the broom's
-- sweep drawn as slashes around it while it turns.
function handlers.spin(model, seconds: number, radius: number)
	local part = body(model)
	if not part then
		return
	end
	local cframe, size = model:GetBoundingBox()
	local feet = cframe.Position - Vector3.new(0, size.Y * 0.5 - 0.6, 0)

	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		local at = feet + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.75
		burst(at, {
			{ "Puff", 2, { Color = ColorSequence.new(SNOW), Size = NumberSequence.new(2.4), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(60, 60) } },
		}, 1.5)
	end
	burst(feet, {
		{ "Glints", 8, { Color = ColorSequence.new(Color3.fromRGB(200, 235, 255)), Size = NumberSequence.new(1) } },
	}, 1.5)

	local at = Kit.attachment(part)
	local slash = emitter("Slash", at, {
		Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)), Size = NumberSequence.new(radius * 0.9),
		LockedToPart = false,
	})
	local last = -1
	during(seconds, function(elapsed)
		local beat = math.floor(elapsed / 0.08)
		if beat ~= last and model.Parent then
			last = beat
			local look = model:GetPivot().LookVector
			at.WorldCFrame = CFrame.lookAt(feet + Vector3.new(0, 1.5, 0), feet + Vector3.new(0, 1.5, 0) + look)
			slash:Emit(1)
		end
	end, function()
		Debris:AddItem(at, 0.4)
	end)
	Kit.sound(part, SOUND_HIT, 0.5, 0.8)
end

-- ---------------------------------------------------------------------------
-- Wasp, Shrike, Cobra
-- ---------------------------------------------------------------------------

function handlers.dive(model, seconds: number)
	local part = body(model)
	if not part then
		return
	end

	-- Across the body, so the trail is a ribbon the width of the creature.
	local half = math.min(part.Size.X, part.Size.Z) * 0.35
	local a0, a1 = Kit.attachment(part), Kit.attachment(part)
	a0.Position, a1.Position = Vector3.new(-half, 0, 0), Vector3.new(half, 0, 0)
	local trail = Kit.trail(part, a0, a1, {
		Texture = Library.Band.Texture, TextureMode = Enum.TextureMode.Stretch,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)), LightEmission = 0.6,
		Transparency = NumberSequence.new(0.45, 1), Lifetime = 0.3, MinLength = 0.05, FaceCamera = false,
	})

	task.delay(seconds, function()
		trail.Enabled = false
		task.delay(0.35, function()
			trail:Destroy()
			a0:Destroy()
			a1:Destroy()
		end)
	end)
end

function handlers.strike(model, _seconds: number)
	local part = body(model)
	if not part then
		return
	end
	local pivot = model:GetPivot()
	local at = Kit.attachment(part)
	at.WorldCFrame = CFrame.lookAt(topOf(model) + pivot.LookVector * 1.5, topOf(model) + pivot.LookVector * 3)
	local slash = emitter("Slash", at, { Color = ColorSequence.new(Color3.fromRGB(255, 230, 140)), Size = NumberSequence.new(4) })
	slash:Emit(1)
	Debris:AddItem(at, 0.6)
end

function handlers.flare(model, color: Color3?)
	local part = body(model)
	if not part then
		return
	end
	local at = Kit.attachment(part)
	at.WorldPosition = topOf(model) + Vector3.new(0, 0.6, 0)
	local flare = emitter("Flare", at, {
		Color = ColorSequence.new(color or Color3.fromRGB(255, 216, 76)), Size = NumberSequence.new(2.6),
	})
	flare:Emit(1)
	Debris:AddItem(at, 0.8)
end

-- ---------------------------------------------------------------------------
-- Always on: wings, the rainbow, the snow trail
-- ---------------------------------------------------------------------------

--[[
	Things a creature does all the time rather than on a message, driven here
	every frame from attributes on its model, so none of it costs a remote.

	WINGS. A model with LeftWing/RightWing Motor6Ds on its body (built by
	assets/voxel-creatures/source/BuildWinged.lua) has its wings beaten
	locally: WingRate (Hz) and WingAngle (degrees) are set on the asset,
	WingMode ("flap", "glide", "fold", "spread") by the server as it moves.
	WingGlide above 0 marks a bird - wings raised at rest, beating downward
	from there - and 0 an insect, buzzing either side of level.

	RAINBOW. A model with Rainbow = true gets a hue-cycling sheen over its
	texture, a rainbow light and a trail of rainbow glints.

	SNOW TRAIL. A model with SnowTrail = true kicks up snow at its base in
	proportion to how fast it is going.
]]
local tracked = {}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(110, 255, 110)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 200, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 110, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 110, 220)),
})

local function setUp(model)
	local part = model.PrimaryPart
	if not part then
		return nil
	end
	local state = { model = model, part = part, phase = math.random() * 10 }

	local wings = {}
	for _, name in ipairs({ "LeftWing", "RightWing" }) do
		local joint = part:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			table.insert(wings, { joint = joint, side = if joint.C0.Position.X >= 0 then 1 else -1, down = 0, back = 0 })
		end
	end
	if #wings > 0 then
		state.wings = wings
	end

	-- A jointed rig with its own procedural animation (Shared.Enemies.CreatureRigs).
	local rigName = model:GetAttribute("Rig")
	local rigDef = rigName and Rigs[rigName]
	if rigDef then
		local joints = {}
		for _, joint in ipairs(model:GetDescendants()) do
			if joint:IsA("Motor6D") then
				joints[joint.Name] = joint
			end
		end
		local rig = { joints = joints, body = part, pose = "walk", poseAt = 0, last = model:GetPivot().Position }
		rigDef.setup(rig)
		state.rig = rig
		state.rigDef = rigDef
	end

	-- A neck and head on joints (the Cobra): see snakePose below.
	local neck = part:FindFirstChild("Neck")
	local neckPart = model:FindFirstChild("Neck")
	local head = neckPart and neckPart:FindFirstChild("Head")
	if neck and neck:IsA("Motor6D") and head and head:IsA("Motor6D") then
		state.snake = { neck = neck, head = head, pitch = 0, headPitch = 0 }
	end

	if model:GetAttribute("Rainbow") then
		local sheen = Instance.new("Highlight")
		sheen.Adornee = model
		sheen.FillTransparency = 0.4
		sheen.OutlineTransparency = 0.2
		sheen.DepthMode = Enum.HighlightDepthMode.Occluded
		sheen.Parent = folder
		state.sheen = sheen
		state.glow = light(part, Color3.new(1, 1, 1), 20, 1.6)
		state.glints = emitter("Glints", part, {
			Enabled = true, Rate = 18, Color = RAINBOW, Size = NumberSequence.new(2.2),
			LockedToPart = false, Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180),
		})

		--[[
			A rainbow arching over it: five curved beams, outermost red. A beam
			bows toward each attachment's X axis by its CurveSize, so the ends
			point their X axis up and the far end's curve is negative.
		]]
		local half = part.Size.X * 0.55
		local rise = part.Size.Y * 0.9
		for i, hue in ipairs({ 0, 0.1, 0.3, 0.55, 0.75 }) do
			local inset = (i - 1) * 0.45
			local a0, a1 = Kit.attachment(part), Kit.attachment(part)
			a0.Position = Vector3.new(-half + inset, part.Size.Y * 0.1, 0)
			a1.Position = Vector3.new(half - inset, part.Size.Y * 0.1, 0)
			a0.Axis, a1.Axis = Vector3.yAxis, Vector3.yAxis
			Kit.beam(part, a0, a1, {
				Color = ColorSequence.new(Color3.fromHSV(hue, 0.95, 1)), LightEmission = 0.5,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.1),
					NumberSequenceKeypoint.new(0.85, 0.1), NumberSequenceKeypoint.new(1, 1),
				}),
				Width0 = 0.6, Width1 = 0.6, FaceCamera = true, Segments = 24,
				CurveSize0 = rise - inset, CurveSize1 = -(rise - inset),
			})
		end
	end

	if model:GetAttribute("SnowTrail") then
		local foot = Kit.attachment(part)
		foot.Position = Vector3.new(0, -part.Size.Y * 0.5 + 0.3, 0)
		state.snow = emitter("Puff", foot, {
			Enabled = true, Rate = 0, Color = ColorSequence.new(SNOW), Size = NumberSequence.new(1.3, 2.2),
			Lifetime = NumberRange.new(0.6), LockedToPart = false, Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(70, 70), Acceleration = Vector3.new(0, 2, 0),
		})
		state.last = part.Position
	end

	if not (state.wings or state.snake or state.rig or state.sheen or state.snow) then
		return false
	end
	return state
end

local function tearDown(state)
	if state.sheen then
		state.sheen:Destroy()
	end
end

-- Picks up new creatures twice a second; attributes set at spawn may land a
-- moment after the model does, so an undecided one is looked at again.
local firstSeen = setmetatable({}, { __mode = "k" })

task.spawn(function()
	local enemies = workspace:WaitForChild("Enemies")
	while true do
		local now = os.clock()
		for _, model in ipairs(enemies:GetChildren()) do
			if tracked[model] == nil and model:IsA("Model") then
				firstSeen[model] = firstSeen[model] or now
				local ok, state = pcall(setUp, model)
				-- Nothing to draw is only final once it has had time to say so.
				if ok and (state or (state == false and now - firstSeen[model] > 2)) then
					tracked[model] = state
				end
			end
		end
		task.wait(0.5)
	end
end)

local function beatWing(wing, mode, bird, now, rate, amplitude, glide, dt)
	local down, back = 0, 0
	if mode == "flap" then
		local swing = math.sin(now * rate * math.pi * 2)
		down = if bird then amplitude * (0.5 - 0.5 * math.cos(now * rate * math.pi * 2)) else amplitude * swing
	elseif mode == "glide" then
		down = if bird then amplitude * (0.75 + 0.1 * glide) + 0.04 * math.sin(now * 3) else 0
	elseif mode == "fold" then
		down, back = if bird then -0.3 else 0.1, 0.9
	elseif mode == "spread" then
		down = if bird then -0.2 else 0
	end

	-- Beating is drawn exactly; settling into a pose is eased.
	local ease = if mode == "flap" then 1 else math.min(1, dt * 10)
	wing.down += (down - wing.down) * ease
	wing.back += (back - wing.back) * math.min(1, dt * 10)
	wing.joint.Transform = CFrame.Angles(0, wing.back * wing.side, -wing.down * wing.side)
end

--[[
	The Cobra's neck and head, by the CobraPose the server sets:
	  idle     a slow, searching sway, the head held level against it
	  slither  a faster, wider weave as it moves
	  rear     drawn back, head tipped down at its mark, trembling
	  strike   thrown forward, head driving in
	The sway is drawn exactly; the lean of each pose is eased, so a strike
	snaps forward and a rear draws back. Pitch about X: positive tips the
	neck back (the model faces -Z).
]]
local SNAKE_POSES = {
	idle = { pitch = 0.05, head = 0, rate = 1.6, sway = 0.22 },
	slither = { pitch = 0.18, head = -0.1, rate = 3.4, sway = 0.34 },
	rear = { pitch = 0.5, head = -0.45, rate = 9, sway = 0.04 },
	strike = { pitch = -0.75, head = 0.25, rate = 0, sway = 0 },
}

local function snakePose(snake, pose, t, dt)
	local p = SNAKE_POSES[pose] or SNAKE_POSES.idle
	local ease = math.min(1, dt * (if pose == "strike" then 30 else 8))
	snake.pitch += (p.pitch - snake.pitch) * ease
	snake.headPitch += (p.head - snake.headPitch) * ease

	local swing = math.sin(t * p.rate) * p.sway
	local roll = math.sin(t * p.rate + 1.2) * p.sway * 0.4
	-- A rise and fall in the neck, like breathing, under everything else.
	local breathe = math.sin(t * 1.1) * 0.04
	snake.neck.Transform = CFrame.Angles(snake.pitch + breathe, swing, roll)
	-- The head counters most of the sway, so it keeps looking at its prey.
	snake.head.Transform = CFrame.Angles(snake.headPitch - breathe, -swing * 0.7, -roll * 0.8)
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero

	for model, state in pairs(tracked) do
		if not model.Parent then
			if state then
				tearDown(state)
			end
			tracked[model] = nil
		elseif state and (state.part.Position - eye).Magnitude < 300 then
			local t = now + state.phase

			if state.wings then
				local rate = model:GetAttribute("WingRate") or 10
				local amplitude = math.rad(model:GetAttribute("WingAngle") or 30)
				local glide = model:GetAttribute("WingGlide") or 0
				local mode = model:GetAttribute("WingMode") or "flap"
				for _, wing in ipairs(state.wings) do
					beatWing(wing, mode, glide > 0, t, rate, amplitude, glide, dt)
				end
			end

			if state.snake then
				snakePose(state.snake, model:GetAttribute("CobraPose") or "idle", t, dt)
			end

			if state.rig then
				local rig = state.rig
				local pivot = model:GetPivot().Position
				local moved = (pivot - rig.last) * Vector3.new(1, 0, 1)
				rig.last = pivot
				-- Smoothed, so one long frame does not jolt the stride.
				rig.speed = (rig.speed or 0) + (moved.Magnitude / math.max(dt, 1e-3) - (rig.speed or 0)) * math.min(1, dt * 10)

				local pose = model:GetAttribute("Pose") or "walk"
				if pose ~= rig.pose then
					rig.pose, rig.poseAt = pose, now
				end
				state.rigDef.animate(rig, {
					t = t, dt = dt, speed = rig.speed, pose = pose,
					blend = math.clamp((now - rig.poseAt) / 0.18, 0, 1),
				})
			end

			if state.sheen then
				local hue = (t * 0.22) % 1
				local color = Color3.fromHSV(hue, 0.75, 1)
				state.sheen.FillColor = color
				state.sheen.OutlineColor = Color3.fromHSV((hue + 0.5) % 1, 0.6, 1)
				state.glow.Color = color
			end

			if state.snow then
				local speed = (state.part.Position - state.last).Magnitude / math.max(dt, 1e-3)
				state.last = state.part.Position
				state.snow.Rate = math.clamp((speed - 1) * 3, 0, 30)
			end
		end
	end
end)

CreatureFX.OnClientEvent:Connect(function(kind, ...)
	local handler = handlers[kind]
	if handler then
		local ok, err = pcall(handler, ...)
		if not ok then
			warn("[CreatureFX] " .. tostring(kind) .. ": " .. tostring(err))
		end
	end
end)
