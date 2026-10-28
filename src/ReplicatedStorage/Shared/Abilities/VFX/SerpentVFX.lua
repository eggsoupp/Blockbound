-- Serpent Flare, drawn from one message:
--   rouse   fire flares off the caster as six flame serpents burst out
--           round them
--   weave   each serpent trails a ribbon of flame as it swings up and over
--           and dives onto a ring round the aim, striking in a burst
--   ignite  the scorched ring catches into a wall of fire and closes in
--   erupt   the ring meets in the middle and erupts as a whirling column of
--           fire, with impact frames, a shake and a punch
-- Every visible effect is an authored particle, Beam or Trail; Parts are
-- invisible emitter hosts only.
local Plan = require(script.Parent.Parent.SerpentPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.SerpentParticles)

local VFX = {}
local T = Plan.Tuning
local HOT = Color3.fromRGB(255, 240, 200)
local GOLD = Color3.fromRGB(255, 200, 70)
local FLAME = Color3.fromRGB(255, 110, 25)
local CRIMSON = Color3.fromRGB(200, 25, 20)
local SOOT = Color3.fromRGB(40, 25, 20)
local ns, curve, colors = Kit.ns, Kit.curve, Kit.colors
local live = 0
local preloaded = false

local Sheets = {
	-- Slash VFX Trail2: a soft-edged band, laid flat for the ring of fire.
	Band = {Texture = "rbxassetid://16892374733"},
}

local SOUND_SWISH = "rbxassetid://12222208"
local SOUND_BOOM = "rbxassetid://5540424854"
local SOUND_HIT = "rbxasset://sounds/hit.wav"

function VFX.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload(Kit.textures(Library, Sheets), {SOUND_SWISH, SOUND_BOOM, SOUND_HIT})
end

function VFX.duration()
	return Plan.duration()
end

local function emitter(kind, parent, props)
	return Kit.emitter(if Sheets[kind] then Sheets else Library, kind, parent, props)
end

-- A stroke lying flat in its host's XZ plane. A beam bends along its
-- attachments' X axes and spreads its width along their Y axes, so Y points
-- across the stroke on the ground.
local function stroke(host, width, color, emission, z)
	local a0, a1 = Kit.attachment(host), Kit.attachment(host)
	local beam = Kit.beam(host, a0, a1, {
		Texture = Sheets.Band.Texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1, FaceCamera = false,
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
local function circle(host, width, color, emission, z)
	local arcs = {}
	for q = 1, 4 do arcs[q] = stroke(host, width, color, emission, z) end
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
		Kit.opacity(s.beam, if radius > 0.1 then opacity else 0)
	end
end

local function outward(t)
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

-- A flame serpent: a burning head and three ribbons of flame trailing it.
local function serpentRig(folder, index)
	local host = Kit.host(folder, "Serpent" .. index, CFrame.new())
	local head = Kit.attachment(host)
	local top, bottom = Kit.attachment(host), Kit.attachment(host)
	top.Position, bottom.Position = Vector3.new(0, 1.5, 0), Vector3.new(0, -1.5, 0)
	local midTop, midBottom = Kit.attachment(host), Kit.attachment(host)
	midTop.Position, midBottom.Position = Vector3.new(0, 0.4, 0), Vector3.new(0, -0.4, 0)
	local function trail(kind, a0, a1, props)
		local data = Library[kind]
		local all = {Texture = data.Texture, TextureMode = Enum.TextureMode.Stretch, FaceCamera = true, Enabled = false}
		for key, value in pairs(props) do all[key] = value end
		return Kit.trail(host, a0, a1, all)
	end
	return {
		host = host,
		emitters = {
			emitter("Flame", head, {Color = colors(GOLD, FLAME, CRIMSON), Size = curve({0, 1.8}, {1, 0.4}), Lifetime = NumberRange.new(0.25),
				LightEmission = 0.4, LightInfluence = 0, LockedToPart = false, Rate = 30}),
			emitter("Flicker", head, {Color = colors(GOLD, FLAME), Size = curve({0, 1.6, 0.4}, {1, 0.4}), Lifetime = NumberRange.new(0.3),
				LightInfluence = 0, Rate = 30}),
			emitter("Glare", head, {Color = colors(HOT, GOLD), Size = curve({0, 4}, {1, 2}), Lifetime = NumberRange.new(0.15), Brightness = 2,
				LockedToPart = true, Rate = 8}),
			emitter("Embers", head, {Color = colors(GOLD, FLAME), Size = curve({0, 0}, {0.2, 0.35}, {1, 0}), Lifetime = NumberRange.new(0.6, 1),
				Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 6, 0), LockedToPart = false,
				Rate = 25}),
		},
		trails = {
			trail("TrailFlame", top, bottom, {Color = colors(FLAME, CRIMSON, SOOT), LightEmission = 0.25, Brightness = 2, Lifetime = 0.45,
				Transparency = curve({0, 0}, {0.7, 0.3}, {1, 1}), WidthScale = curve({0, 1}, {0.3, 0.8}, {1, 0.15})}),
			trail("TrailWisp", top, bottom, {Color = colors(GOLD, FLAME), LightEmission = 1, Brightness = 2, Lifetime = 0.3,
				Transparency = curve({0, 0}, {1, 1}), WidthScale = curve({0, 0.75}, {1, 0.1})}),
			trail("TrailCore", midTop, midBottom, {Color = colors(HOT, GOLD), LightEmission = 1, Brightness = 3, Lifetime = 0.12,
				Transparency = curve({0, 0}, {1, 1}), WidthScale = curve({0, 1}, {1, 0.3})}),
		},
	}
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.centre) ~= "Vector3" or type(payload.landings) ~= "table"
		or type(payload.startedAt) ~= "number" or type(payload.seed) ~= "number" then
		return false
	end
	local serpents = Plan.serpents(payload.seed, payload.origin)
	for i = 1, #serpents do
		if typeof(payload.landings[i]) ~= "Vector3" then return false end
	end
	local total = Plan.duration()
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 3 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local origin, centre, landings = payload.origin, payload.centre, payload.landings
	local up = Vector3.yAxis
	local igniteAt, eruptAt = Plan.igniteAt(serpents), Plan.eruptAt(serpents)
	local R = T.RingRadius
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "SerpentFlare"
	folder.Parent = workspace

	-- The rouse --------------------------------------------------------------------
	local casterHost = Kit.host(folder, "Caster", origin)
	local back = Kit.attachment(casterHost, origin * CFrame.new(0, 1.5, 1.5))
	local rouse = {
		{emitter("Glare", back, {Color = colors(HOT, GOLD), Size = curve({0, 12}, {1, 0}), Lifetime = NumberRange.new(0.25), Brightness = 2}), 1},
		{emitter("Crescents", back, {Color = colors(GOLD, FLAME), Size = curve({0, 0}, {1, 7}), Lifetime = NumberRange.new(0.4), Brightness = 3}), 4},
		{emitter("Puff", back, {Color = colors(GOLD, FLAME, CRIMSON), Size = curve({0, 0}, {0.4, 4}, {1, 4.5}), Speed = NumberRange.new(8, 16),
			SpreadAngle = Vector2.new(180, 180), LightEmission = 0.3, LightInfluence = 0, LockedToPart = false}), 8},
		{emitter("Embers", back, {Color = colors(GOLD, FLAME), Size = curve({0, 0}, {0.2, 0.4}, {1, 0}), Speed = NumberRange.new(10, 22),
			SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(0.6, 1), LockedToPart = false}), 20},
	}
	local starts = {}
	for i, serpent in ipairs(serpents) do
		starts[i] = {emitter("Billow", Kit.attachment(casterHost, CFrame.new(serpent.start)), {Color = colors(GOLD, FLAME, CRIMSON),
			Size = curve({0, 0}, {0.15, 4}, {1, 3}), Speed = NumberRange.new(-20, 20), LightEmission = 0.3, LightInfluence = 0, Brightness = 1.5}), 3}
	end

	-- The serpents and their strikes ------------------------------------------------------
	local rigs, strikes, scorches = {}, {}, {}
	local strikeHost = Kit.host(folder, "Strikes", CFrame.new(centre))
	for i, landing in ipairs(landings) do
		rigs[i] = serpentRig(folder, i)
		local at = Kit.attachment(strikeHost, CFrame.new(landing + up * 1.2))
		strikes[i] = {
			{emitter("Glare", at, {Color = colors(HOT, GOLD), Size = curve({0, 14}, {1, 0}), Lifetime = NumberRange.new(0.25), Brightness = 2}), 1},
			{emitter("Puff", at, {Color = colors(GOLD, FLAME, CRIMSON), Size = curve({0, 0}, {0.4, 5}, {1, 5.5}), Speed = NumberRange.new(10, 20),
				SpreadAngle = Vector2.new(180, 180), LightEmission = 0.3, LightInfluence = 0, LockedToPart = false}), 6},
			{emitter("Billow", at, {Color = colors(GOLD, FLAME, CRIMSON), Size = curve({0, 0}, {0.15, 7}, {1, 5}), LightEmission = 0.3,
				LightInfluence = 0, Brightness = 1.5}), 5},
			{emitter("Sparks", at, {Color = colors(GOLD, FLAME), Speed = NumberRange.new(30, 60), Size = curve({0, 1}, {1, 0}),
				Lifetime = NumberRange.new(0.6, 0.9), LightInfluence = 0}), 14},
			{emitter("Crescents", at, {Color = colors(GOLD, FLAME), Size = curve({0, 0}, {1, 5}), Lifetime = NumberRange.new(0.35), Brightness = 3}), 3},
			{emitter("Smoke", at, {Color = ColorSequence.new(SOOT), Size = curve({0, 0}, {0.15, 5}, {1, 4}), LightInfluence = 0,
				Lifetime = NumberRange.new(1.2, 1.8)}), 3},
		}
		local scorchHost = Kit.host(folder, "Scorch" .. i, CFrame.new(landing + up * 0.15))
		-- A band wider than its radius overlaps itself: a soft filled scorch.
		scorches[i] = circle(scorchHost, 3.6, SOOT, 0, 0)
	end

	-- The ring of fire ----------------------------------------------------------------
	local ringHost = Kit.host(folder, "Ring", CFrame.new(centre + up * 0.2))
	local band = circle(ringHost, 2.5, CRIMSON, 0.3, 0.1)
	local bandGlow = circle(ringHost, 6, FLAME, 1, 0)
	local wall = {}
	for i = 1, 12 do
		local at = Kit.attachment(ringHost)
		wall[i] = {at = at, emitters = {
			emitter("Flame", at, {Color = colors(GOLD, FLAME, CRIMSON), Size = curve({0, 3}, {1, 1.2}), Lifetime = NumberRange.new(0.5),
				Speed = NumberRange.new(6, 12), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(10, 10), LightEmission = 0.4,
				LightInfluence = 0, LockedToPart = false, Rate = 18}),
			emitter("Flicker", at, {Color = colors(GOLD, FLAME), Size = curve({0, 1.6, 0.4}, {1, 0.4}), EmissionDirection = Enum.NormalId.Top,
				LightInfluence = 0, Rate = 10}),
		}}
	end

	-- The eruption ------------------------------------------------------------------
	local base = Kit.attachment(ringHost, CFrame.new(centre))
	local top = Kit.attachment(ringHost, CFrame.new(centre))
	local function column(kind, width, color, emission, z)
		return {width = width, beam = Kit.beam(ringHost, base, top, {Texture = Library[kind].Texture, TextureMode = Enum.TextureMode.Stretch,
			TextureLength = 1, TextureSpeed = 2, Color = color, LightEmission = emission, Brightness = 2, FaceCamera = true, Segments = 1,
			Width0 = width, Width1 = width, ZOffset = z, Transparency = curve({0, 0}, {0.7, 0.2}, {1, 1}), Enabled = false})}
	end
	local pillar = {
		column("TrailFlame", 14, colors(FLAME, CRIMSON), 0.2, 0),
		column("TrailFlame", 9, colors(GOLD, FLAME), 0.4, 0.05),
		column("TrailWisp", 7, colors(GOLD, FLAME), 0.8, 0.1),
		column("TrailCore", 2.4, colors(HOT, GOLD), 1, 0.2),
	}
	local eruptAtt = Kit.attachment(ringHost, CFrame.new(centre + up * 2))
	local whirl = {
		emitter("Spin", eruptAtt, {Color = colors(GOLD, FLAME, CRIMSON), Size = curve({0, 2}, {1, 14}), Lifetime = NumberRange.new(0.7),
			Speed = NumberRange.new(25, 40), EmissionDirection = Enum.NormalId.Top, LightEmission = 0.6, LightInfluence = 0, LockedToPart = false, Rate = 14}),
		emitter("SpinWide", eruptAtt, {Color = colors(HOT, GOLD, FLAME), Size = curve({0, 3}, {1, 18}), Lifetime = NumberRange.new(0.6),
			Speed = NumberRange.new(30, 45), EmissionDirection = Enum.NormalId.Top, LightEmission = 0.8, LightInfluence = 0, LockedToPart = false, Rate = 8}),
	}
	local erupt = {
		{emitter("Glare", eruptAtt, {Color = colors(GOLD, FLAME), Size = curve({0, 18}, {1, 0}), Lifetime = NumberRange.new(0.25), Brightness = 1.5}), 1},
		{emitter("Shockwave", eruptAtt, {Color = colors(FLAME, CRIMSON), Size = curve({0, 0}, {1, 30}), Lifetime = NumberRange.new(0.35),
			Brightness = 1, LightInfluence = 0, Transparency = curve({0, 0.45}, {1, 1})}), 1},
		{emitter("Billow", eruptAtt, {Color = colors(GOLD, FLAME, CRIMSON), Size = curve({0, 0}, {0.15, 14}, {1, 10}), LightEmission = 0.3,
			LightInfluence = 0, Brightness = 1.5, Speed = NumberRange.new(-60, 60)}), 14},
		{emitter("Puff", eruptAtt, {Color = colors(GOLD, FLAME, CRIMSON), Size = curve({0, 0}, {0.4, 7}, {1, 8}), Speed = NumberRange.new(30, 50),
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(25, 25), LightEmission = 0.3, LightInfluence = 0, Lifetime = NumberRange.new(0.8),
			LockedToPart = false}), 12},
		{emitter("Sparks", eruptAtt, {Color = colors(GOLD, FLAME), Speed = NumberRange.new(60, 120), Size = curve({0, 1.6}, {1, 0}),
			Lifetime = NumberRange.new(0.8, 1.2), LightInfluence = 0}), 40},
		{emitter("Crescents", eruptAtt, {Color = colors(GOLD, FLAME), Size = curve({0, 0}, {1, 9}), Lifetime = NumberRange.new(0.45), Brightness = 3}), 6},
		{emitter("Smoke", eruptAtt, {Color = ColorSequence.new(SOOT), Size = curve({0, 0}, {0.12, 12}, {1, 10}), LightInfluence = 0,
			Lifetime = NumberRange.new(1.5, 2.2), Speed = NumberRange.new(-30, 30)}), 8},
	}
	local shock = circle(ringHost, 2.5, GOLD, 1, 0.2)
	local shockGlow = circle(ringHost, 7, FLAME, 1, 0.1)
	local light = Kit.light(ringHost, FLAME, 50)

	local spin = 0
	local last
	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local dt = if last then math.max(elapsed - last, 0) else 0
		last = elapsed
		-- The serpents in flight.
		for i, serpent in ipairs(serpents) do
			local rig = rigs[i]
			local t = (elapsed - serpent.launch) / serpent.flight
			local flying = t >= 0 and t < 1
			if flying then
				local position = Plan.path(serpent, landings[i], t)
				local ahead = Plan.path(serpent, landings[i], math.min(1, t + 0.03))
				rig.host.CFrame = if (ahead - position).Magnitude > 0.01 then CFrame.lookAt(position, ahead) else CFrame.new(position)
			end
			Kit.setEnabled(rig.emitters, flying)
			for _, trail in ipairs(rig.trails) do
				if trail.Enabled ~= flying then trail.Enabled = flying end
			end
			local landed = elapsed >= Plan.landsAt(serpent)
			layoutCircle(scorches[i], 1.4, if landed then 0.55 * (1 - Kit.ramp(elapsed, eruptAt, total)) else 0)
		end
		-- The ring catches and closes in, turning.
		local close = Kit.smooth((elapsed - igniteAt) / T.Collapse)
		local burning = elapsed >= igniteAt and elapsed < eruptAt
		local radius = R * (1 - close) + 0.1
		local catch = Kit.smooth((elapsed - igniteAt) / 0.12)
		layoutCircle(band, radius, if burning then catch else 0)
		layoutCircle(bandGlow, radius, if burning then 0.6 * catch else 0)
		spin += dt * (2 + 6 * close)
		for i, flame in ipairs(wall) do
			flame.at.Position = radial(spin + (i - 1) / #wall * math.pi * 2) * radius
			Kit.setEnabled(flame.emitters, burning)
		end
		-- The column shoots up, swells and burns out.
		local age = elapsed - eruptAt
		local rising = age >= 0 and age < 0.9
		local height = T.ColumnHeight * outward(age / 0.15)
		local swell = if age >= 0 then (1 + 0.4 * math.exp(-age * 8)) * (1 - Kit.ramp(age, 0.5, 0.9)) else 0
		top.WorldPosition = centre + up * math.max(height, 0.1)
		for _, col in ipairs(pillar) do
			local width = col.width * swell
			col.beam.Width0, col.beam.Width1 = width, width * 1.3
			local on = rising and width > 0.05
			if col.beam.Enabled ~= on then col.beam.Enabled = on end
		end
		Kit.setEnabled(whirl, age >= 0 and age < 0.7)
		local wave = age / 0.45
		local waveOn = wave >= 0 and wave <= 1
		layoutCircle(shock, 2 + 20 * outward(wave), if waveOn then 1 - wave else 0, 1 - 0.7 * math.clamp(wave, 0, 1))
		layoutCircle(shockGlow, 2 + 18 * outward(wave), if waveOn then 0.5 * (1 - wave) else 0)
		light.Brightness = if burning then 1.5 * catch elseif age >= 0 then 6 * math.exp(-age * 4) else 0
	end, {folder})

	timeline.at(0, function()
		Kit.burst(rouse)
		Kit.sound(casterHost, SOUND_SWISH, 0.5, 0.7)
		ImpactFX.shake(origin.Position, 0.4, 0.2, 40)
	end)
	for i, serpent in ipairs(serpents) do
		timeline.at(serpent.launch, function()
			Kit.burst({starts[i]})
			if i % 2 == 1 then Kit.sound(casterHost, SOUND_SWISH, 0.3, 1.1 + i * 0.05) end
		end)
		timeline.at(Plan.landsAt(serpent), function()
			Kit.burst(strikes[i])
			Kit.sound(strikeHost, SOUND_BOOM, 0.35, 1.3 + (i % 3) * 0.1)
			ImpactFX.shake(landings[i], 0.5, 0.15, 60)
		end)
	end
	timeline.at(igniteAt, function()
		Kit.sound(ringHost, SOUND_SWISH, 0.5, 0.6)
	end)
	timeline.at(eruptAt, function()
		Kit.burst(erupt)
		Kit.sound(ringHost, SOUND_BOOM, 0.8, 0.8)
		Kit.sound(ringHost, SOUND_HIT, 0.5, 0.7)
		ImpactFX.hit(centre + up * 3, {tint = FLAME, pattern = "triple", shake = 2.4, shakeDuration = 0.6, punch = 8, radius = 90})
	end)
	return true
end

return VFX
