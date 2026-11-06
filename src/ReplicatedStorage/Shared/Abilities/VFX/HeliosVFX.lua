local CombatAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.CombatAudio)
-- Helios Lance, drawn from one message:
--   charge  a small sun gathers over the caster, embers rushing into it
--   sweep   a lance of molten light pours from it to the ground and drags
--           across, the contact boiling with fire, sparks, rock and smoke,
--           carving a burning scar behind it
--   blast   the beam collapses into a blast at the end of the sweep, with
--           impact frames, a shake and a punch
--   embers  the scar burns on, then smoulders out
-- Every visible effect is an authored particle or textured Beam; Parts are
-- invisible emitter hosts only.
local Plan = require(script.Parent.Parent.HeliosPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.HeliosParticles)
local EnemyConfig = require(script.Parent.Parent.Parent.Enemies.EnemyConfig)

local VFX = {}
local T = Plan.Tuning
local EMBER = Color3.fromRGB(255, 96, 20)
local FLAME = Color3.fromRGB(255, 150, 40)
local SUN = Color3.fromRGB(255, 226, 140)
local MAGMA = Color3.fromRGB(200, 40, 10)
local CHAR = Color3.fromRGB(40, 16, 8)
local SMOKE = Color3.fromRGB(70, 56, 50)
local ns, curve, colors = Kit.ns, Kit.curve, Kit.colors
local live = 0
local preloaded = false

local Sheets = {
	-- Slash VFX Trail2: a soft band, the burning scar on the ground.
	Band = {Texture = "rbxassetid://16892374733"},
}

local SOUND_CHARGE = CombatAudio.ids.power_up
local SOUND_BOOM = CombatAudio.ids.flame_blast4

function VFX.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload(Kit.textures(Library, Sheets), {SOUND_CHARGE, SOUND_BOOM})
end

function VFX.duration()
	return Plan.duration()
end

local function emitter(kind, parent, props)
	return Kit.emitter(if Sheets[kind] then Sheets else Library, kind, parent, props)
end

local function rayParams(folder)
	local enemies = workspace:FindFirstChild(EnemyConfig.WorldFolder)
	return Kit.rayParams({folder, enemies})
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.sun) ~= "Vector3" or typeof(payload.from) ~= "Vector3"
		or typeof(payload.to) ~= "Vector3" or type(payload.startedAt) ~= "number" then
		return false
	end
	local blastAt = Plan.blastAt()
	local total = blastAt + T.Aftermath
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 3 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local sun, from, to = payload.sun, payload.from, payload.to
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "HeliosLance"
	folder.Parent = workspace
	local params = rayParams(folder)

	-- The sun ------------------------------------------------------------------
	-- A sphere-sized host so the embers start on its surface and rush in.
	local sunHost = Kit.host(folder, "Sun", CFrame.new(sun), Vector3.one * 16)
	local core = Kit.attachment(sunHost)
	local aura = emitter("FlameAura", core, {Color = colors(FLAME, EMBER), Size = curve({0, 5, 1.5}, {1, 0}), Rate = 0,
		Speed = NumberRange.new(0, 3), Brightness = 2, LightEmission = 1})
	local glow = emitter("Glow", core, {Color = ColorSequence.new(EMBER), Size = curve({0, 6}, {1, 2}), Rate = 0, Brightness = 1.2,
		Lifetime = NumberRange.new(0.3, 0.5), Transparency = curve({0, 0.4}, {1, 1}), Acceleration = Vector3.zero, LockedToPart = true})
	local ring = emitter("Circle", core, {Color = colors(SUN, EMBER), Orientation = Enum.ParticleOrientation.FacingCamera,
		Size = curve({0, 9}, {1, 2}), Lifetime = NumberRange.new(0.4), Speed = NumberRange.new(0.01), Brightness = 2, LightEmission = 1, Rate = 0})
	local inflow = emitter("FireSpecs", sunHost, {Color = colors(SUN, EMBER), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Speed = NumberRange.new(18, 26), Lifetime = NumberRange.new(0.3, 0.4), Drag = 0, Size = curve({0, 0.9}, {1, 0}),
		LightEmission = 1, Brightness = 2, Rate = 70})
	local sunLight = Kit.light(sunHost, EMBER, 26)

	-- The lance ----------------------------------------------------------------
	local sunAt = Kit.attachment(sunHost)
	local contact = Kit.host(folder, "Contact", CFrame.new(from))
	local groundAt = Kit.attachment(contact)
	local function lance(kind, color, width, brightness, z, emission)
		local data = Library[kind]
		return Kit.beam(sunHost, sunAt, groundAt, {
			Texture = data.Texture, TextureMode = Enum.TextureMode.Wrap, TextureLength = 6, TextureSpeed = -3,
			FaceCamera = true, Segments = 1, Color = ColorSequence.new(color), Width0 = width * 0.7, Width1 = width,
			LightEmission = emission, Brightness = brightness, ZOffset = z, Enabled = false,
		})
	end
	-- Outside in: a dark magma sheath, the orange flow, a flame core and a
	-- thin sun-white thread.
	local lances = {
		{beam = lance("LavaBeamA", MAGMA, 7.5, 1.4, 0, 0.4), width = 7.5},
		{beam = lance("LavaBeamB", EMBER, 5, 1.6, 0.1, 0.8), width = 5},
		{beam = lance("LavaBeamC", FLAME, 2.6, 1.8, 0.2, 1), width = 2.6},
		{beam = lance("LavaBeamC", SUN, 1, 2.2, 0.3, 1), width = 1},
	}
	-- What boils up where the lance lands.
	local up = Kit.attachment(contact)
	up.CFrame = CFrame.lookAt(Vector3.zero, Vector3.yAxis)
	local boiling = {
		emitter("Fire", up, {Color = colors(FLAME, EMBER), Size = curve({0, 0}, {0.14, 3.4}, {1, 0}), Rate = 70,
			Speed = NumberRange.new(6, 16), SpreadAngle = Vector2.new(50, 50), EmissionDirection = Enum.NormalId.Front,
			Acceleration = Vector3.new(0, 12, 0), LightEmission = 0.6, Brightness = 2}),
		emitter("FireBig", up, {Color = colors(FLAME, EMBER), Size = curve({0, 0}, {0.5, 8}, {1, 8.5}), Rate = 14,
			LockedToPart = false, Speed = NumberRange.new(4, 8), EmissionDirection = Enum.NormalId.Front, LightEmission = 0.4, Brightness = 2}),
		emitter("Sparks", up, {Color = colors(SUN, FLAME), Size = curve({0, 1.6}, {1, 0}), Rate = 40, Speed = NumberRange.new(40, 80),
			SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Front, LockedToPart = false, Brightness = 2}),
		emitter("Rock", up, {Color = ColorSequence.new(CHAR), Rate = 14, Speed = NumberRange.new(30, 55), Size = curve({0, 0}, {0.3, 1, 0.5}, {1, 0}),
			SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(0, -60, 0)}),
		emitter("SmokeDark", up, {Color = colors(SMOKE, CHAR), Size = curve({0, 2}, {1, 7, 1}), Rate = 8, Speed = NumberRange.new(6, 12),
			SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Front, Transparency = curve({0, 0.5}, {1, 1}),
			LockedToPart = false, Drag = 1, Acceleration = Vector3.new(0, 4, 0)}),
		emitter("Glow", up, {Color = ColorSequence.new(EMBER), Size = curve({0, 7}, {1, 3}), Rate = 14, Lifetime = NumberRange.new(0.2, 0.3),
			Brightness = 1.2, LockedToPart = true, Acceleration = Vector3.zero}),
	}
	local contactLight = Kit.light(contact, EMBER, 24)

	-- The scar: laid a segment at a time behind the contact.
	local scarHost = Kit.host(folder, "Scar", CFrame.new(from))
	local segments = {}
	local function laySegment(a, b)
		local forward = Kit.flat(b - a)
		local side = forward:Cross(Vector3.yAxis).Unit
		local a0 = Kit.attachment(scarHost, CFrame.fromMatrix(a + Vector3.new(0, 0.15, 0), forward, side))
		local a1 = Kit.attachment(scarHost, CFrame.fromMatrix(b + Vector3.new(0, 0.15, 0), forward, side))
		local char = Kit.beam(scarHost, a0, a1, {Texture = Sheets.Band.Texture, TextureMode = Enum.TextureMode.Stretch, FaceCamera = false,
			Segments = 2, Width0 = T.ScarWidth * 2, Width1 = T.ScarWidth * 2, Color = ColorSequence.new(CHAR), LightEmission = 0,
			Transparency = ns(0.15), ZOffset = 0})
		local hot = Kit.beam(scarHost, a0, a1, {Texture = Sheets.Band.Texture, TextureMode = Enum.TextureMode.Stretch, FaceCamera = false,
			Segments = 2, Width0 = T.ScarWidth * 0.9, Width1 = T.ScarWidth * 0.9, Color = ColorSequence.new(EMBER), LightEmission = 1,
			Brightness = 2, Transparency = ns(0.1), ZOffset = 0.1})
		local mid = (a + b) / 2
		local box = Kit.host(folder, "Burn", CFrame.lookAt(mid + Vector3.new(0, 0.4, 0), mid + Vector3.new(0, 0.4, 0) + forward),
			Vector3.new(T.ScarWidth, 0.3, math.max((b - a).Magnitude, 0.5)))
		local fire = {
			emitter("FireBig", box, {Color = colors(FLAME, EMBER), Size = curve({0, 0}, {0.5, 3.2}, {1, 3.4}), Rate = 3, LockedToPart = false,
				Speed = NumberRange.new(1, 3), EmissionDirection = Enum.NormalId.Top, Shape = Enum.ParticleEmitterShape.Box, LightEmission = 0.4, Brightness = 2}),
			emitter("Fire", box, {Color = colors(FLAME, EMBER), Size = curve({0, 0}, {0.14, 2.2}, {1, 0}), Rate = 16,
				Speed = NumberRange.new(2, 5), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(15, 15),
				Acceleration = Vector3.new(0, 8, 0), Shape = Enum.ParticleEmitterShape.Box, LightEmission = 0.5, Brightness = 2}),
			emitter("FireSpecs", box, {Color = colors(SUN, EMBER), Rate = 6, Speed = NumberRange.new(2, 6), EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(30, 30), Shape = Enum.ParticleEmitterShape.Box, LightEmission = 1, Brightness = 2,
				Acceleration = Vector3.new(0, 4, 0), Lifetime = NumberRange.new(0.8, 1.2)}),
			emitter("SmokeDark", box, {Color = colors(SMOKE, CHAR), Size = curve({0, 1.5}, {1, 5, 1}), Rate = 1.5, Speed = NumberRange.new(2, 5),
				EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(20, 20), Shape = Enum.ParticleEmitterShape.Box,
				Transparency = curve({0, 0.6}, {1, 1}), LockedToPart = false, Drag = 0.5, Lifetime = NumberRange.new(1.2, 1.6)}),
		}
		Kit.setEnabled(fire, true)
		table.insert(segments, {char = char, hot = hot, fire = fire})
	end

	-- The blast ----------------------------------------------------------------
	local blastPoint = Plan.landing(sun, to, params)
	local blastHost = Kit.host(folder, "Blast", CFrame.new(blastPoint))
	local blastCore = Kit.attachment(blastHost)
	local blast = {
		{emitter("Flare", blastCore, {Color = colors(SUN, EMBER), Size = curve({0, 8}, {0.2, 26}, {1, 0}), Brightness = 2}), 1},
		{emitter("Glow", blastCore, {Color = ColorSequence.new(FLAME), Size = curve({0, 20}, {1, 6}), Lifetime = NumberRange.new(0.6),
			Brightness = 2, Transparency = curve({0, 0.2}, {1, 1}), Acceleration = Vector3.zero}), 2},
		{emitter("Wind", blastCore, {Color = ColorSequence.new(FLAME), Orientation = Enum.ParticleOrientation.FacingCamera,
			Size = curve({0, 0}, {0.3, 18, 1}, {1, 28, 2}), Brightness = 2, LightEmission = 1}), 3},
		{emitter("Lines", blastCore, {Color = colors(SUN, EMBER), Speed = NumberRange.new(90, 150), Size = curve({0, 0}, {0.48, 2.6}, {1, 0})}), 24},
		{emitter("Sparks", blastCore, {Color = colors(SUN, FLAME), Speed = NumberRange.new(60, 120), Size = curve({0, 2.4}, {1, 0}),
			LockedToPart = false, Brightness = 2}), 30},
		{emitter("Rock", blastCore, {Color = ColorSequence.new(CHAR), Speed = NumberRange.new(40, 80), Size = curve({0, 0}, {0.3, 1.6, 0.6}, {1, 0}),
			SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top}), 24},
		{emitter("FireBig", blastCore, {Color = colors(SUN, FLAME, EMBER), Size = curve({0, 0}, {0.4, 9}, {1, 10}), LockedToPart = false,
			Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top, Brightness = 2}), 8},
		{emitter("Fire", blastCore, {Color = colors(SUN, FLAME, EMBER), Size = curve({0, 0}, {0.14, 3.5}, {1, 0}), Speed = NumberRange.new(20, 40),
			Drag = 4, LightEmission = 0.6, Brightness = 2}), 40},
		{emitter("BlastSmoke", blastCore, {Color = colors(SMOKE, CHAR), Speed = NumberRange.new(20, 60), Size = curve({0, 1}, {0.2, 7, 1}, {0.8, 8, 0.5}, {1, 0}),
			Transparency = curve({0, 1}, {0.15, 0.55}, {1, 1}), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(70, 70)}), 18},
	}
	local blastLight = Kit.light(blastHost, FLAME, 50)

	local lastLanding = nil
	local nextShake = 0
	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local charging = elapsed < T.Charge
		local firing = elapsed >= T.Charge and elapsed < blastAt
		local k = Kit.smooth(elapsed / T.Charge)
		-- The sun swells while it charges and holds while it fires.
		aura.Rate = if charging then 30 + 60 * k elseif firing then 90 else 0
		aura.Enabled = elapsed < blastAt
		glow.Rate = if elapsed < blastAt then 12 else 0
		glow.Enabled = elapsed < blastAt
		glow.Size = curve({0, 4 + 8 * k}, {1, 2})
		ring.Rate = if charging then 4 else 0
		ring.Enabled = charging
		inflow.Enabled = charging
		sunLight.Brightness = if elapsed < blastAt then 0.4 + 0.8 * k else 0
		if firing then
			local landing = Plan.landing(sun, from:Lerp(to, Plan.progress(elapsed)), params)
			contact.CFrame = CFrame.new(landing)
			if not lastLanding then
				lastLanding = landing
			elseif (landing - lastLanding).Magnitude > 1.6 then
				laySegment(lastLanding, landing)
				lastLanding = landing
			end
			-- The lance thins in its last tenth of a second, collapsing.
			local pinch = 1 - Kit.ramp(elapsed, blastAt - 0.12, blastAt) * 0.85
			local flicker = 0.92 + 0.08 * math.sin(elapsed * 60)
			for _, l in ipairs(lances) do
				l.beam.Width1 = l.width * pinch * flicker
				l.beam.Width0 = l.width * 0.7 * pinch
			end
			if os.clock() >= nextShake then
				nextShake = os.clock() + 0.18
				ImpactFX.shake(landing, 0.45, 0.22, 60)
			end
		end
		for _, l in ipairs(lances) do
			if l.beam.Enabled ~= firing then l.beam.Enabled = firing end
		end
		Kit.setEnabled(boiling, firing)
		contactLight.Brightness = if firing then 1.5 else 0
		local age = elapsed - blastAt
		blastLight.Brightness = if age >= 0 then math.exp(-age * 4) * 5 else 0
		-- The scar cools from orange to char and its fires die down.
		local cool = if age >= 0 then Kit.ramp(age, 0.4, T.Aftermath - 0.3) else 0
		for _, s in ipairs(segments) do
			Kit.opacity(s.hot, (1 - cool) * 0.9)
			Kit.opacity(s.char, 0.85 * (1 - Kit.ramp(age, T.Aftermath - 0.6, T.Aftermath)))
			if cool > 0.75 then Kit.setEnabled(s.fire, false) end
		end
	end, {folder})

	timeline.at(0, function()
		Kit.sound(sunHost, SOUND_CHARGE, 0.5, 0.55)
		ImpactFX.punch(payload.origin.Position, 4, T.Charge + 0.2, 60)
	end)
	timeline.at(T.Charge, function()
		Kit.sound(contact, SOUND_BOOM, 0.5, 1.7)
		Kit.sound(sunHost, SOUND_CHARGE, 0.45, 0.8)
		ImpactFX.shake(payload.origin.Position, 1, 0.3, 60)
	end)
	timeline.at(blastAt, function()
		Kit.burst(blast)
		Kit.sound(blastHost, SOUND_BOOM, 0.7, 0.95)
		ImpactFX.hit(blastPoint, {tint = EMBER, pattern = "triple", shake = 2.2, shakeDuration = 0.55, punch = 8, radius = 85})
	end)
	return true
end

return VFX
