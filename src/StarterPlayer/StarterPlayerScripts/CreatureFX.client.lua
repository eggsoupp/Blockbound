--[[
	CreatureFX

	Draws the voxel creatures' signature moves from the server's CreatureFX
	messages (ServerScriptService.Creatures.CreatureKit). The server has
	already decided everything - where the laser went, how the snowball
	flies - and this only shows it.

	  charge   (model, eye, seconds, lockAfter, character)
	                                              the Lasereye gathering, with a thin aim line
	                                              that follows the character until it locks
	  lock     (model, aim)                       the aim line stops following
	  laser    (model, eye, finish, seconds)      the beam itself
	  cancel   (model)                            a charge that will not fire
	  throw    (id, origin, velocity, gravity)    a snowball on the server's own arc
	  splash   (id, point)                        where it burst
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

local charges = {}

local function endCharge(model)
	local charge = charges[model]
	if charge then
		charges[model] = nil
		charge.host:Destroy()
		charge.target:Destroy()
	end
end

function handlers.charge(model, eye: Vector3, seconds: number, lockAfter: number, character)
	endCharge(model)

	local host = Kit.host(folder, "LaserCharge", CFrame.new(eye))
	local target = Kit.host(folder, "LaserAim", CFrame.new(eye))
	local energy = emitter("ChargeEnergy", host, {
		Enabled = true, Rate = 9, Color = ColorSequence.new(LASER_RED), Size = scaled(Library.ChargeEnergy.Size, 0.6),
	})
	-- Dimmer than the pack's core, which blooms to white and loses the red.
	local core = emitter("ChargeCore", host, {
		Enabled = true, Rate = 30, Color = ColorSequence.new(LASER_RED), Size = NumberSequence.new(0.6),
		Brightness = 1.5, LightEmission = 0.6,
	})

	local a0, a1 = Kit.attachment(host), Kit.attachment(target)
	local line = Kit.beam(host, a0, a1, {
		Texture = Library.LaserGlow.Texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1,
		Color = ColorSequence.new(LASER_RED), LightEmission = 1, FaceCamera = true, Segments = 1,
		Width0 = 0.12, Width1 = 0.12, Transparency = NumberSequence.new(0.8),
	})

	local charge = { host = host, target = target, locked = false }
	charges[model] = charge

	during(seconds + 0.6, function(elapsed)
		if charges[model] ~= charge then
			return false
		end
		local k = math.clamp(elapsed / seconds, 0, 1)
		if not charge.locked then
			local root = character and character.Parent and character:FindFirstChild("HumanoidRootPart")
			if root then
				target.Position = root.Position
			end
		end

		-- Thickens and brightens as it gathers; flickers once it has locked.
		local width = 0.08 + 0.22 * k
		line.Width0, line.Width1 = width, width
		local opacity = 0.2 + 0.5 * k
		if charge.locked then
			opacity = if math.sin(elapsed * 60) > 0 then 0.95 else 0.55
		end
		Kit.opacity(line, opacity)
		core.Size = NumberSequence.new(0.5 + 1.1 * k)
		energy.Rate = 9 + 12 * k
	end, function()
		if charges[model] == charge then
			endCharge(model)
		end
	end)

	-- The server's "lock" carries the exact aim; this only stops the line
	-- chasing the character if that message is late.
	task.delay(lockAfter, function()
		charge.locked = true
	end)
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

function handlers.laser(model, eye: Vector3, finish: Vector3, seconds: number)
	endCharge(model)

	local host = Kit.host(folder, "Laser", CFrame.new(eye))
	local far = Kit.host(folder, "LaserEnd", CFrame.new(finish))
	local a0, a1 = Kit.attachment(host), Kit.attachment(far)

	local function beam(kind, width, color)
		local data = Library[kind]
		return Kit.beam(host, a0, a1, {
			Texture = data.Texture, TextureMode = data.TextureMode, TextureLength = data.TextureLength,
			TextureSpeed = data.TextureSpeed, Brightness = data.Brightness, Segments = data.Segments,
			Color = ColorSequence.new(color), LightEmission = 0.7, FaceCamera = true,
			Width0 = width, Width1 = width, Transparency = NumberSequence.new(0),
		})
	end
	local glow = beam("LaserGlow", 3.2, LASER_RED)
	local core = beam("LaserCore", 1.3, LASER_HOT)

	burst(eye, {
		{ "BoomGlow", 1, { Color = ColorSequence.new(LASER_RED), Size = scaled(Library.BoomGlow.Size, 0.35) } },
	}, 1)
	burst(finish, {
		{ "BoomGlow", 1, { Color = ColorSequence.new(LASER_RED), Size = scaled(Library.BoomGlow.Size, 0.45) } },
		{ "BoomSparks", 10, { Color = ColorSequence.new(LASER_RED), Speed = NumberRange.new(30) } },
		{ "Puff", 2, { Color = ColorSequence.new(Color3.fromRGB(90, 70, 60)), Size = NumberSequence.new(2.5) } },
	}, 2)
	Kit.sound(far, SOUND_HIT, 0.5, 0.7)

	during(seconds + 0.15, function(elapsed)
		local fade = math.clamp(1 - (elapsed - seconds * 0.5) / (seconds * 0.5 + 0.15), 0, 1)
		Kit.opacity(glow, fade * 0.8)
		Kit.opacity(core, fade)
		local pulse = 1 + 0.15 * math.sin(elapsed * 50)
		glow.Width0, glow.Width1 = 3.2 * pulse * fade, 3.2 * pulse * fade
	end, function()
		host:Destroy()
		Debris:AddItem(far, 1)
	end)
end

-- ---------------------------------------------------------------------------
-- Snowman
-- ---------------------------------------------------------------------------

local snowballs = {}

function handlers.throw(id: string, origin: Vector3, velocity: Vector3, gravity: number)
	-- The projectile itself: a packed block of snow.
	local ball = Instance.new("Part")
	ball.Name = "Snowball"
	ball.Size = Vector3.one * 1.1
	ball.Material = Enum.Material.Snow
	ball.Color = SNOW
	ball.Anchored, ball.CanCollide, ball.CanTouch, ball.CanQuery = true, false, false, false
	ball.CFrame = CFrame.new(origin)
	ball.Parent = folder
	emitter("Puff", ball, {
		Enabled = true, Rate = 14, Color = ColorSequence.new(SNOW), Size = NumberSequence.new(1.1),
		Lifetime = NumberRange.new(0.35), LockedToPart = false,
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

function handlers.splash(id: string, point: Vector3)
	local ball = snowballs[id]
	snowballs[id] = nil
	if ball then
		ball:Destroy()
	end
	local host = burst(point, {
		{ "Puff", 6, { Color = ColorSequence.new(SNOW), Size = NumberSequence.new(2.6), Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(180, 180) } },
		{ "Glints", 5, { Color = ColorSequence.new(Color3.fromRGB(200, 235, 255)), Size = NumberSequence.new(0.8) } },
	}, 2)
	Kit.sound(host, SOUND_HIT, 0.45, 1.3)
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

CreatureFX.OnClientEvent:Connect(function(kind, ...)
	local handler = handlers[kind]
	if handler then
		local ok, err = pcall(handler, ...)
		if not ok then
			warn("[CreatureFX] " .. tostring(kind) .. ": " .. tostring(err))
		end
	end
end)
