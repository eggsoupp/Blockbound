local CombatAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.CombatAudio)
-- Tidecaller, drawn from two kinds of message:
--   summon  the caster stamps a tide pool open at their feet: mist, a toon
--           splash and a ring; the pool ripples and bubbles, and eight water
--           orbs rise out of it to circle the caster
--   shot    one orb leaves the circle and arcs onto its target as a water
--           bolt trailing a ribbon of spray, landing in a toon splash with a
--           ripple ring and a shake; the last bolt adds impact frames and a
--           punch
-- Every visible effect is an authored particle, Beam or Trail; Parts are
-- invisible emitter hosts only.
local Plan = require(script.Parent.Parent.TidePlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.TideParticles)

local VFX = {}
local T = Plan.Tuning
local FOAM = Color3.fromRGB(225, 245, 255)
local AQUA = Color3.fromRGB(60, 175, 255)
local DEEPWATER = Color3.fromRGB(20, 85, 190)
local ns, curve, colors = Kit.ns, Kit.curve, Kit.colors
local live = 0
local preloaded = false
-- Summons still circling, by cast id, so each shot can take its orb.
local rigs = {}

local Sheets = {
	-- Slash VFX Trail2: a soft-edged band, laid flat for the pool's rings.
	Band = {Texture = "rbxassetid://16892374733"},
}

local SOUND_WATER = CombatAudio.ids.water_walk
local SOUND_SWISH = CombatAudio.ids.swing_air

function VFX.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload(Kit.textures(Library, Sheets), {SOUND_WATER, SOUND_SWISH})
end

function VFX.duration()
	return Plan.duration()
end

local function emitter(kind, parent, props)
	return Kit.emitter(if Sheets[kind] then Sheets else Library, kind, parent, props)
end

-- A stroke lying flat in its host's XZ plane. A beam bends along its
-- attachments' X axes and spreads its width along their Y axes, so Y points
-- across the stroke on the ground. An untextured stroke is a solid band.
local function stroke(host, width, color, emission, z, texture)
	local a0, a1 = Kit.attachment(host), Kit.attachment(host)
	local beam = Kit.beam(host, a0, a1, {
		Texture = texture or Sheets.Band.Texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1, FaceCamera = false,
		Segments = 12, Width0 = width, Width1 = width, Color = ColorSequence.new(color), LightEmission = emission,
		Brightness = if emission > 0.5 then 2 else 1, Transparency = ns(1), Enabled = false, ZOffset = z or 0,
	})
	return {beam = beam, a0 = a0, a1 = a1, width = width}
end

local function radial(theta)
	return Vector3.new(math.cos(theta), 0, math.sin(theta))
end

-- A whole circle in four quarter arcs; a cubic quarter arc is circular when
-- its control points sit 0.5523 of the radius along each end's tangent.
local function circle(host, width, color, emission, z, texture)
	local arcs = {}
	for q = 1, 4 do arcs[q] = stroke(host, width, color, emission, z, texture) end
	return arcs
end

local function layoutCircle(arcs, radius, opacity, widthScale)
	for q, s in ipairs(arcs) do
		local t0, t1 = (q - 1) * math.pi / 2, q * math.pi / 2
		s.a0.CFrame = CFrame.fromMatrix(radial(t0) * radius, radial(t0 + math.pi / 2), radial(t0))
		s.a1.CFrame = CFrame.fromMatrix(radial(t1) * radius, radial(t1 + math.pi / 2), radial(t1))
		s.beam.CurveSize0, s.beam.CurveSize1 = radius * 0.5523, radius * 0.5523
		local width = s.width * (widthScale or 1)
		s.beam.Width0, s.beam.Width1 = width, width
		Kit.opacity(s.beam, if radius > 0.05 then opacity else 0)
	end
end

local function outward(t)
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

local function summon(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.pool) ~= "Vector3" or type(payload.id) ~= "string"
		or type(payload.startedAt) ~= "number" then
		return false
	end
	local total = Plan.duration()
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 4 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local pool = payload.pool
	local R = T.PoolRadius
	local caster = payload.caster
	local character = caster and caster.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "Tidecaller"
	folder.Parent = workspace

	-- The stamp -------------------------------------------------------------------
	local poolFrame = CFrame.new(pool + Vector3.new(0, 0.15, 0))
	local poolHost = Kit.host(folder, "Pool", poolFrame)
	local feet = Kit.attachment(poolHost, CFrame.new(pool + Vector3.new(0, 0.8, 0)))
	local stamp = {
		{emitter("Splash", feet, {Color = colors(FOAM, AQUA), Size = ns(9), Lifetime = NumberRange.new(0.5), LightEmission = 0.2,
			LightInfluence = 0}), 2},
		{emitter("Spray", feet, {Size = ns(10), Lifetime = NumberRange.new(0.6), LightInfluence = 0}), 2},
		{emitter("Ring", feet, {Color = colors(FOAM, AQUA), Size = curve({0, 2}, {1, 22}), Lifetime = NumberRange.new(0.35), Brightness = 1.5}), 1},
		{emitter("Mist", feet, {Color = colors(FOAM, AQUA), Size = curve({0, 3}, {1, 7}), Speed = NumberRange.new(14, 22),
			Lifetime = NumberRange.new(0.8), Drag = 4, LightInfluence = 0.3, Brightness = 1}), 10},
		{emitter("Dots", feet, {Color = ColorSequence.new(FOAM), Speed = NumberRange.new(10, 20), SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -30, 0), Size = curve({0, 0}, {0.2, 0.6}, {1, 0}),
			Lifetime = NumberRange.new(0.6, 1)}), 16},
	}

	-- The pool --------------------------------------------------------------------
	local surface = circle(poolHost, R, DEEPWATER, 0, -0.1, "")
	local rim = circle(poolHost, 1.2, AQUA, 0.3, 0.1)
	local rimGlow = circle(poolHost, 3.5, FOAM, 1, 0)
	local ripples = {}
	for i = 1, 3 do ripples[i] = circle(poolHost, 0.6, FOAM, 0.6, 0.15) end
	local floor = Kit.host(folder, "Floor", poolFrame * CFrame.new(0, 0.4, 0), Vector3.new(R * 1.4, 0.2, R * 1.4))
	local bubbling = {
		emitter("Bubble", floor, {Color = colors(FOAM, AQUA), Size = ns(1.4), Lifetime = NumberRange.new(0.8), LightInfluence = 0,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Rate = 6}),
		emitter("Dots", floor, {Color = ColorSequence.new(FOAM), Speed = NumberRange.new(1, 3), EmissionDirection = Enum.NormalId.Top,
			Size = curve({0, 0}, {0.2, 0.4}, {1, 0}), ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Rate = 10}),
	}
	local poolLight = Kit.light(poolHost, AQUA, 22)

	-- The orbs --------------------------------------------------------------------
	local orbs = {}
	for i = 1, T.Shots do
		local host = Kit.host(folder, "Orb" .. i, CFrame.new(pool))
		local at = Kit.attachment(host)
		orbs[i] = {host = host, emitters = {
			emitter("Swirl", at, {Color = colors(FOAM, AQUA), Size = curve({0, 1.6}, {1, 2.4}), Lifetime = NumberRange.new(0.4), Rate = 16,
				LockedToPart = true, LightInfluence = 0, LightEmission = 0.2}),
			emitter("Bubble", at, {Color = colors(FOAM, AQUA), Size = ns(2.2), Lifetime = NumberRange.new(1.2), Rate = 3, LockedToPart = true,
				LightInfluence = 0}),
			emitter("Flare", at, {Color = ColorSequence.new(AQUA), Size = ns(3), Rate = 8, LockedToPart = true}),
			emitter("Dots", at, {Color = ColorSequence.new(FOAM), Speed = NumberRange.new(0, 2), Size = curve({0, 0}, {0.2, 0.4}, {1, 0}),
				Lifetime = NumberRange.new(0.5, 0.8), Rate = 6}),
		}}
	end
	local rig = {fired = {}}
	rigs[payload.id] = rig
	scope:add(function()
		if rigs[payload.id] == rig then rigs[payload.id] = nil end
	end)

	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local open = outward(elapsed / 0.35)
		local fade = 1 - Kit.ramp(elapsed, total - 0.6, total)
		local reach = R * open
		layoutCircle(surface, reach * 0.5, 0.35 * fade, 0.98 * open)
		layoutCircle(rim, reach, fade)
		layoutCircle(rimGlow, reach, 0.4 * fade)
		for i, ring in ipairs(ripples) do
			local p = ((elapsed + i * 0.45) % 1.35) / 1.35
			layoutCircle(ring, R * p, if elapsed > 0.3 then 0.6 * (1 - p) * fade else 0)
		end
		Kit.setEnabled(bubbling, elapsed > 0.2 and elapsed < total - 0.5)
		poolLight.Brightness = 1.2 * fade * open
		local centre = if root and root.Parent then root.Position else payload.origin.Position
		for i, orb in ipairs(orbs) do
			local shown = not rig.fired[i] and elapsed > 0.15
			Kit.setEnabled(orb.emitters, shown)
			if shown then orb.host.CFrame = CFrame.new(Plan.orbit(centre, i, elapsed)) end
		end
	end, {folder})
	timeline.at(0, function()
		Kit.burst(stamp)
		Kit.sound(poolHost, SOUND_WATER, 0.6, 0.8)
		ImpactFX.shake(pool, 0.6, 0.25, 50)
	end)
	return true
end

local function shot(payload, scope)
	if typeof(payload.from) ~= "Vector3" or typeof(payload.landing) ~= "Vector3" or type(payload.index) ~= "number"
		or type(payload.startedAt) ~= "number" or type(payload.seed) ~= "number" then
		return false
	end
	local total = T.Flight + 1.1
	if workspace:GetServerTimeNow() - payload.startedAt >= total then return false end
	local rig = type(payload.id) == "string" and rigs[payload.id]
	if rig then rig.fired[payload.index] = true end
	VFX.preload()

	local from, landing = payload.from, payload.landing
	local rng = Random.new(payload.seed)
	local final = payload.index == T.Shots
	local scale = if final then 1.5 else 1
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "TidecallerBolt"
	folder.Parent = workspace

	-- The bolt --------------------------------------------------------------------
	local boltHost = Kit.host(folder, "Bolt", CFrame.new(from))
	local core = Kit.attachment(boltHost)
	local top, bottom = Kit.attachment(boltHost), Kit.attachment(boltHost)
	top.Position, bottom.Position = Vector3.new(0, 0.8, 0), Vector3.new(0, -0.8, 0)
	local body = {
		emitter("Swirl", core, {Color = colors(FOAM, AQUA), Size = curve({0, 2.4}, {1, 1.2}), Lifetime = NumberRange.new(0.3), Rate = 40,
			LightInfluence = 0, LightEmission = 0.2}),
		emitter("Bubble", core, {Color = colors(FOAM, AQUA), Size = ns(2.6), Lifetime = NumberRange.new(0.6), Rate = 6, LockedToPart = true,
			LightInfluence = 0}),
		emitter("Flare", core, {Color = ColorSequence.new(AQUA), Size = ns(3.5), Rate = 12, LockedToPart = true}),
		emitter("Dots", core, {Color = ColorSequence.new(FOAM), Speed = NumberRange.new(1, 4), Size = curve({0, 0}, {0.2, 0.5}, {1, 0}),
			Lifetime = NumberRange.new(0.4, 0.7), Acceleration = Vector3.new(0, -20, 0), Rate = 30}),
	}
	local ribbon = {
		Kit.trail(boltHost, top, bottom, {Texture = Library.Stream.Texture, Color = colors(FOAM, AQUA, DEEPWATER), LightEmission = 0.2,
			FaceCamera = true, Lifetime = 0.22, Transparency = curve({0, 0}, {1, 1}), WidthScale = curve({0, 1}, {1, 0.3}), Enabled = false}),
		Kit.trail(boltHost, top, bottom, {Texture = Library.StreamGlow.Texture, Color = colors(FOAM, AQUA), LightEmission = 1,
			FaceCamera = true, Lifetime = 0.15, Transparency = curve({0, 0.3}, {1, 1}), WidthScale = curve({0, 0.6}, {1, 0.2}), Enabled = false}),
	}

	-- The splash ------------------------------------------------------------------
	local landHost = Kit.host(folder, "Landing", CFrame.new(landing + Vector3.new(0, 0.15, 0)))
	local splashAt = Kit.attachment(landHost, CFrame.new(landing + Vector3.new(0, 1.2, 0)))
	local splash = {
		{emitter("Splash", splashAt, {Color = colors(FOAM, AQUA), Size = ns(7 * scale), Lifetime = NumberRange.new(0.45), LightEmission = 0.2,
			LightInfluence = 0}), 2},
		{emitter("Spray", splashAt, {Size = ns(7 * scale), Lifetime = NumberRange.new(0.55), LightInfluence = 0}), 1},
		{emitter("Bubble", splashAt, {Color = colors(FOAM, AQUA), Size = ns(1.6), Lifetime = NumberRange.new(0.5), Speed = NumberRange.new(6, 12),
			SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -25, 0), LightInfluence = 0}), 5},
		{emitter("Ring", splashAt, {Color = colors(FOAM, AQUA), Size = curve({0, 1}, {1, 10 * scale}), Lifetime = NumberRange.new(0.25),
			Brightness = 1.5}), 1},
		{emitter("Dots", splashAt, {Color = ColorSequence.new(FOAM), Speed = NumberRange.new(14, 26), SpreadAngle = Vector2.new(70, 70),
			EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -50, 0), Size = curve({0, 0}, {0.15, 0.7}, {1, 0}),
			Lifetime = NumberRange.new(0.5, 0.8)}), math.round(14 * scale)},
		{emitter("Mist", splashAt, {Color = colors(FOAM, AQUA), Size = curve({0, 2}, {1, 4.5 * scale}), Speed = NumberRange.new(8, 12),
			Lifetime = NumberRange.new(0.6), Drag = 4, LightInfluence = 0.3, Brightness = 1}), 5},
	}
	local ripple = circle(landHost, 0.8, FOAM, 0.6, 0.15)
	local rippleGlow = circle(landHost, 2.5, AQUA, 1, 0.1)
	local light = Kit.light(landHost, AQUA, 16)

	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local flying = elapsed < T.Flight
		if flying then
			local t = math.clamp(elapsed / T.Flight, 0, 1)
			local position = Plan.arc(from, landing, t)
			local ahead = Plan.arc(from, landing, math.min(1, t + 0.05))
			boltHost.CFrame = if (ahead - position).Magnitude > 0.01 then CFrame.lookAt(position, ahead) else CFrame.new(position)
		end
		Kit.setEnabled(body, flying)
		for _, trail in ipairs(ribbon) do
			if trail.Enabled ~= flying then trail.Enabled = flying end
		end
		local age = elapsed - T.Flight
		local wave = age / 0.5
		local waveOn = wave >= 0 and wave <= 1
		local reach = 1 + 7 * scale * outward(wave)
		layoutCircle(ripple, reach, if waveOn then 1 - wave else 0)
		layoutCircle(rippleGlow, reach, if waveOn then 0.5 * (1 - wave) else 0)
		light.Brightness = if age >= 0 then 3 * math.exp(-age * 6) else 0
	end, {folder})
	timeline.at(0, function()
		Kit.sound(boltHost, SOUND_SWISH, 0.25, rng:NextNumber(1.2, 1.5))
	end)
	timeline.at(T.Flight, function()
		Kit.burst(splash)
		Kit.sound(landHost, SOUND_WATER, 0.45, rng:NextNumber(0.85, 1.15))
		if final then
			ImpactFX.hit(landing, {tint = AQUA, pattern = "double", shake = 1.2, shakeDuration = 0.35, punch = 4, radius = 70})
		else
			ImpactFX.shake(landing, 0.45, 0.15, 50)
		end
	end)
	return true
end

function VFX.play(payload, scope)
	if payload.phase == "summon" then return summon(payload, scope) end
	if payload.phase == "shot" then return shot(payload, scope) end
	return false
end

return VFX
