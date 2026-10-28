-- Abyss Gate, drawn from one message:
--   call     shadow cracks off the caster's hand
--   sigil    two rings, a turning band of runes and a pentagram draw
--            themselves on the ground at the aim, black over a violet glow,
--            while murk is dragged inwards and black lightning crackles
--   erupt    the gate opens: a black pillar with a white-hot core tears up out
--            of the sigil over a spinning void, with impact frames, a shake
--            and a punch; ash and white streaks stream up it
--   implode  the pillar is sucked back into the ground, then a white star
--            bursts out of it with black shards, smoke and a ground ring
-- Every visible effect is an authored particle or textured Beam; Parts are
-- invisible emitter hosts only.
local Plan = require(script.Parent.Parent.AbyssPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.AbyssParticles)

local VFX = {}
local T = Plan.Tuning
local VOID = Color3.new(0, 0, 0)
local INK = Color3.fromRGB(30, 16, 52)
local DUSK = Color3.fromRGB(125, 95, 210)
local PALE = Color3.fromRGB(236, 230, 255)
local ns, curve = Kit.ns, Kit.curve
local live = 0
local preloaded = false

local Sheets = {
	-- Slash VFX Trail2: a soft-edged band, laid flat for the sigil's strokes.
	Band = {Texture = "rbxassetid://16892374733"},
}

local SOUND_CALL = "rbxassetid://12222208"
local SOUND_BOOM = "rbxassetid://5540424854"
local SOUND_HIT = "rbxasset://sounds/hit.wav"

function VFX.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload(Kit.textures(Library, Sheets), {SOUND_CALL, SOUND_BOOM, SOUND_HIT})
end

function VFX.duration()
	return Plan.duration()
end

local function emitter(kind, parent, props)
	return Kit.emitter(if Sheets[kind] then Sheets else Library, kind, parent, props)
end

-- A stroke lying flat in its host's XZ plane: the host stands with Y along
-- the ground normal. Flat particles do not show on this ground, so the whole
-- sigil is drawn in beams: crisp bands for the ink, the pillar's soft streak
-- for glows.
local function stroke(host, width, color, emission, z, texture)
	local a0, a1 = Kit.attachment(host), Kit.attachment(host)
	local beam = Kit.beam(host, a0, a1, {
		Texture = texture or if emission > 0 then Library.PillarCore.Texture else Sheets.Band.Texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1, FaceCamera = false,
		Segments = 12, Width0 = width, Width1 = width, Color = ColorSequence.new(color), LightEmission = emission,
		Brightness = if emission > 0 then 2 else 1, Transparency = ns(1), Enabled = false, ZOffset = z or 0,
	})
	return {beam = beam, a0 = a0, a1 = a1, width = width}
end

local function tangent(theta)
	return Vector3.new(-math.sin(theta), 0, math.cos(theta))
end

local function radial(theta)
	return Vector3.new(math.cos(theta), 0, math.sin(theta))
end

-- A beam bends along its attachments' X axes and spreads its width along
-- their Y axes, so a stroke lies flat when Y points across it on the ground.
-- A cubic arc is circular when its control points sit (4/3)tan(sweep/4) of
-- the radius along each end's tangent.
local function layoutArc(s, radius, t0, t1, opacity, widthScale)
	s.a0.CFrame = CFrame.fromMatrix(radial(t0) * radius, tangent(t0), radial(t0))
	s.a1.CFrame = CFrame.fromMatrix(radial(t1) * radius, tangent(t1), radial(t1))
	local k = 4 / 3 * math.tan((t1 - t0) / 4) * radius
	s.beam.CurveSize0, s.beam.CurveSize1 = k, k
	local width = s.width * (widthScale or 1)
	s.beam.Width0, s.beam.Width1 = width, width
	Kit.opacity(s.beam, opacity)
end

local function layoutLine(s, from, to, opacity)
	local along = to - from
	if along.Magnitude < 0.05 then
		Kit.opacity(s.beam, 0)
		return
	end
	local across = Vector3.yAxis:Cross(along).Unit
	s.a0.CFrame = CFrame.fromMatrix(from, along.Unit, across)
	s.a1.CFrame = CFrame.fromMatrix(to, along.Unit, across)
	Kit.opacity(s.beam, opacity)
end

-- A whole circle in four quarter arcs.
local function circle(host, width, color, emission, z, texture)
	local arcs = {}
	for q = 1, 4 do arcs[q] = stroke(host, width, color, emission, z, texture) end
	return arcs
end

local function layoutCircle(arcs, radius, opacity, widthScale)
	for q, s in ipairs(arcs) do
		layoutArc(s, radius, (q - 1) * math.pi / 2, q * math.pi / 2, opacity, widthScale)
	end
end

local function outward(t)
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.centre) ~= "Vector3" or typeof(payload.normal) ~= "Vector3"
		or type(payload.startedAt) ~= "number" or type(payload.seed) ~= "number" then
		return false
	end
	local total = Plan.duration()
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 3 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local origin, centre, normal = payload.origin, payload.centre, payload.normal
	local up = Vector3.yAxis
	local rng = Random.new(payload.seed)
	local openAt, collapseAt = T.Open, Plan.collapseAt()
	local R = T.Radius
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "AbyssGate"
	folder.Parent = workspace

	-- The call -----------------------------------------------------------------
	local caster = payload.caster
	local character = caster and caster.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local handPoint = if hand then hand.Position else (origin * CFrame.new(1.2, 0.8, -1)).Position
	local callHost = Kit.host(folder, "Call", CFrame.new(handPoint))
	local callAt = Kit.attachment(callHost, CFrame.new(handPoint))
	local call = {
		{emitter("Shadow", callAt, {Size = ns(7), Lifetime = NumberRange.new(0.4), Rotation = NumberRange.new(0, 360)}), 1},
		{emitter("BlackFlash", callAt, {Size = ns(6), Lifetime = NumberRange.new(0.35), Rotation = NumberRange.new(0, 360)}), 2},
		{emitter("SmokeDark", callAt, {Color = ColorSequence.new(INK), LightEmission = 0, Brightness = 1, Size = curve({0, 1}, {1, 4}),
			Transparency = curve({0, 0.3}, {1, 1}), Lifetime = NumberRange.new(0.5), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180)}), 4},
	}

	-- The sigil ----------------------------------------------------------------
	local side = normal:Cross(Vector3.zAxis)
	side = if side.Magnitude > 0.1 then side.Unit else Vector3.xAxis
	local ringFrame = CFrame.fromMatrix(centre + normal * 0.2, side, normal)
	local outerHost = Kit.host(folder, "Outer", ringFrame)
	local runeHost = Kit.host(folder, "Runes", ringFrame)
	local innerHost = Kit.host(folder, "Inner", ringFrame)
	-- A soft black disc under everything: the pit the gate opens into.
	local shade = circle(outerHost, R, VOID, 0, -0.1, "")
	local outer = circle(outerHost, 1, VOID, 0, 0.1)
	local outerGlow = circle(outerHost, 3.5, DUSK, 1)
	local inner = circle(innerHost, 0.7, VOID, 0, 0.1)
	local innerGlow = circle(innerHost, 2.6, DUSK, 1)
	local runes = {}
	for i = 1, 12 do runes[i] = stroke(runeHost, 0.9, VOID, 0, 0.1) end
	local star, starGlow = {}, {}
	for i = 1, 5 do
		star[i] = stroke(innerHost, 0.55, VOID, 0, 0.1)
		starGlow[i] = stroke(innerHost, 2.2, DUSK, 1)
	end
	local starRadius = R * 0.72
	local function vertex(k)
		local t = -math.pi / 2 + k * 2 * math.pi / 5
		return Vector3.new(math.cos(t), 0, math.sin(t)) * starRadius
	end
	local tip = Kit.attachment(innerHost)
	local tipGlow = emitter("StarLight", tip, {Color = ColorSequence.new(PALE), Size = curve({0, 2.2}, {1, 0}), Lifetime = NumberRange.new(0.3),
		Transparency = curve({0, 0.2}, {1, 1}), Brightness = 3, LockedToPart = false, Rate = 60})
	-- Murk dragged in from the rim.
	local suction = {}
	for i = 1, 8 do
		local t = i * math.pi / 4
		local p = (ringFrame * CFrame.new(math.cos(t) * R, 1.2, math.sin(t) * R)).Position
		local at = Kit.attachment(outerHost, CFrame.lookAt(p, centre + normal * 1.2))
		suction[i] = emitter("SmokeDark", at, {Color = ColorSequence.new(INK), LightEmission = 0, Brightness = 1, Size = curve({0, 3}, {1, 0.8}),
			Transparency = curve({0, 1}, {0.25, 0.4}, {1, 1}), Lifetime = NumberRange.new(0.55), Speed = NumberRange.new(R / 0.55),
			SpreadAngle = Vector2.new(12, 12), EmissionDirection = Enum.NormalId.Front, Drag = 0, RotSpeed = NumberRange.new(-120, 120), Rate = 7})
	end
	local bolts = {}
	for i = 1, 6 do
		local t = i * math.pi / 3 + 0.3
		local p = (ringFrame * CFrame.new(math.cos(t) * R * 0.8, 1.5, math.sin(t) * R * 0.8)).Position
		bolts[i] = emitter("BlackFlash", Kit.attachment(outerHost, CFrame.new(p)), {Size = ns(6), Lifetime = NumberRange.new(0.3),
			Rotation = NumberRange.new(0, 360)})
	end
	local eye = emitter("VoidOrb", Kit.attachment(outerHost, CFrame.new(centre + normal * 1.5)), {Size = ns(1), Lifetime = NumberRange.new(0.6),
		Rate = 5, LockedToPart = true, Rotation = NumberRange.new(0, 360)})
	-- Ash lifting off the floor of the circle.
	local floor = Kit.host(folder, "Floor", ringFrame * CFrame.new(0, 0.5, 0), Vector3.new(R * 1.6, 0.2, R * 1.6))
	local motes = emitter("Ash", floor, {Size = curve({0, 0}, {0.3, 1.2}, {1, 0}), Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(10, 10), EmissionDirection = Enum.NormalId.Top, Drag = 0,
		LockedToPart = false, Acceleration = Vector3.new(0, 6, 0), ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Rate = 25})

	-- The pillar ---------------------------------------------------------------
	local pillarHost = Kit.host(folder, "Pillar", CFrame.new(centre))
	local base = Kit.attachment(pillarHost, CFrame.new(centre))
	local top = Kit.attachment(pillarHost, CFrame.new(centre))
	local function column(kind, width, color, emission, z, props)
		local data = Library[kind]
		local all = {
			Texture = data.Texture, TextureSpeed = data.TextureSpeed or 0, Brightness = data.Brightness or 1,
			Color = ColorSequence.new(color), LightEmission = emission, ZOffset = z, Width0 = width, Width1 = width,
			FaceCamera = true, Segments = 1, CurveSize0 = 0, CurveSize1 = 0, TextureMode = Enum.TextureMode.Wrap, TextureLength = 16,
			Transparency = curve({0, 0}, {0.75, 0}, {1, 1}), Enabled = false,
		}
		for key, value in pairs(props or {}) do all[key] = value end
		return {beam = Kit.beam(pillarHost, base, top, all), width = width, crackle = kind == "PillarArc"}
	end
	-- Solid black flow with flame-ragged edges inside a fainter wider one,
	-- black filaments crackling past its edges and a white-hot core. The
	-- filament texture only runs along a beam when stretched.
	local function stretched(extra)
		local all = {TextureMode = Enum.TextureMode.Stretch, TextureLength = 1}
		for key, value in pairs(extra) do all[key] = value end
		return all
	end
	local pillar = {
		column("PillarArc", 22, VOID, 0, -0.3, stretched({TextureSpeed = 1.5})),
		column("PillarFlow", 18, VOID, 0, -0.25, {TextureSpeed = 1.2, Transparency = curve({0, 0.55}, {0.75, 0.55}, {1, 1})}),
		column("PillarFlow", 12, VOID, 0, -0.1, {TextureSpeed = 2}),
		column("PillarFlow", 8, VOID, 0, 0, stretched({TextureSpeed = 1})),
		column("PillarCore", 2.6, PALE, 1, 0.1, stretched({Brightness = 2.5})),
		column("PillarFlow", 1.2, Color3.new(1, 1, 1), 1, 0.2, {Brightness = 4, TextureSpeed = 4}),
		column("PillarArc", 5, PALE, 1, 0.15, stretched({TextureSpeed = -2, Brightness = 2})),
	}
	local foot = Kit.attachment(pillarHost, CFrame.new(centre + up * 1.5))
	local stream = {
		emitter("Ash", foot, {Size = curve({0, 0}, {0.2, 2.4}, {1, 0}), Lifetime = NumberRange.new(0.6, 0.9), Speed = NumberRange.new(45, 80),
			SpreadAngle = Vector2.new(8, 8), EmissionDirection = Enum.NormalId.Top, Drag = 0, LockedToPart = false, Rate = 45}),
		emitter("SlashLines", foot, {Color = ColorSequence.new(PALE), Speed = NumberRange.new(90, 150), SpreadAngle = Vector2.new(6, 6),
			EmissionDirection = Enum.NormalId.Top, Lifetime = NumberRange.new(0.3, 0.5), Drag = 0, Rate = 35,
			Size = curve({0, 0}, {0.4, 1.5}, {0.55, 3.2}, {0.8, 1}, {1, 0})}),
		emitter("DarkSpin", foot, {Size = ns(22), Lifetime = NumberRange.new(0.5), Rate = 4, Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-200), LockedToPart = true}),
		emitter("VoidOrb", foot, {Size = ns(9), Lifetime = NumberRange.new(0.6), Rate = 4, Rotation = NumberRange.new(0, 360), LockedToPart = true}),
		emitter("SmokeDark", foot, {Color = ColorSequence.new(VOID), LightEmission = 0, Brightness = 1, Size = curve({0, 6}, {1, 10}),
			Transparency = curve({0, 0.4}, {1, 1}), Lifetime = NumberRange.new(0.6), Speed = NumberRange.new(6, 10),
			SpreadAngle = Vector2.new(80, 80), EmissionDirection = Enum.NormalId.Top, Rate = 10}),
	}
	local pillarBolts = {}
	for i, height in ipairs({6, 15, 26, 38, 50}) do
		pillarBolts[i] = emitter("BlackFlash", Kit.attachment(pillarHost, CFrame.new(centre + up * height)), {Size = ns(10 + height * 0.08),
			Lifetime = NumberRange.new(0.25), Rotation = NumberRange.new(0, 360)})
	end
	local light = Kit.light(pillarHost, PALE, 45)

	-- Eruption and implosion bursts ---------------------------------------------
	local burstAt = Kit.attachment(pillarHost, CFrame.new(centre + up * 2))
	local function shards(count, speed)
		return {
			{emitter("ShardsDark", burstAt, {Speed = NumberRange.new(speed * 0.5, speed), Size = curve({0, 0}, {0.25, 4.5, 1.5}, {1, 0})}), count},
			{emitter("SpecsDark", burstAt, {Speed = NumberRange.new(speed * 0.45, speed * 0.9)}), count},
			{emitter("SmokeDark", burstAt, {Color = ColorSequence.new(VOID), Size = curve({0, 8}, {0.3, 16}, {1, 20}),
				Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(25, 40), Drag = 3, LightEmission = 0, Brightness = 1,
				EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(80, 80), Transparency = curve({0, 0.3}, {1, 1})}), math.ceil(count / 3)},
		}
	end
	local erupt = {
		{emitter("Star", burstAt, {Color = ColorSequence.new(PALE), Size = curve({0, 46}, {1, 0}), Lifetime = NumberRange.new(0.14), Brightness = 3}), 1},
		{emitter("HitFlash", burstAt, {Color = ColorSequence.new(PALE), Size = curve({0, 24}, {1, 0}), Lifetime = NumberRange.new(0.18)}), 2},
		{emitter("HitRing", burstAt, {Color = ColorSequence.new(VOID), LightEmission = 0, Size = curve({0, 4}, {0.5, 26}, {1, 32}),
			Lifetime = NumberRange.new(0.35), Brightness = 1}), 2},
		{emitter("HitLines", burstAt, {Color = ColorSequence.new(PALE), Speed = NumberRange.new(80, 140), Size = curve({0, 6, 1}, {1, 0}),
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(40, 40), LockedToPart = false}), 14},
	}
	for _, layer in ipairs(shards(24, 140)) do table.insert(erupt, layer) end
	local implode = {
		{emitter("Star", burstAt, {Color = ColorSequence.new(PALE), Size = curve({0, 54}, {1, 0}), Lifetime = NumberRange.new(0.2), Brightness = 3}), 2},
		{emitter("HitFlash", burstAt, {Color = ColorSequence.new(PALE), Size = curve({0, 26}, {1, 0}), Lifetime = NumberRange.new(0.22)}), 2},
		{emitter("Shadow", burstAt, {Size = ns(30), Lifetime = NumberRange.new(0.4), Rotation = NumberRange.new(0, 360)}), 2},
		{emitter("HitRing", burstAt, {Color = ColorSequence.new(PALE), LightEmission = 1, Size = curve({0, 4}, {0.5, 36}, {1, 44}),
			Lifetime = NumberRange.new(0.4), Brightness = 3}), 2},
		{emitter("DarkSpin", burstAt, {Size = curve({0, 10}, {1, 46}), Lifetime = NumberRange.new(0.45), Rotation = NumberRange.new(0, 360)}), 1},
		{emitter("BlackFlash", burstAt, {Size = ns(16), Lifetime = NumberRange.new(0.35), Rotation = NumberRange.new(0, 360)}), 3},
		{emitter("Ash", burstAt, {Speed = NumberRange.new(40, 80), SpreadAngle = Vector2.new(180, 180), Size = curve({0, 0}, {0.2, 3}, {1, 0}),
			Lifetime = NumberRange.new(0.6, 0.9), LockedToPart = false, Drag = 3}), 30},
		{emitter("HitLines", burstAt, {Color = ColorSequence.new(PALE), Speed = NumberRange.new(100, 180), Size = curve({0, 8, 1}, {1, 0}),
			LockedToPart = false}), 20},
	}
	for _, layer in ipairs(shards(40, 170)) do table.insert(implode, layer) end
	local waveHost = Kit.host(folder, "Wave", ringFrame)
	local eruptWave = circle(waveHost, 2.6, VOID, 0, 0.1)
	local eruptGlow = circle(waveHost, 6, DUSK, 1)
	local implodeWave = circle(waveHost, 1.8, PALE, 1, 0.2)
	local implodeShadow = circle(waveHost, 4, VOID, 0, 0.1)

	local spin = 0
	local last
	local nextBolt = 0.15
	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local dt = if last then math.max(elapsed - last, 0) else 0
		last = elapsed
		local erupting = elapsed >= openAt and elapsed < collapseAt
		-- The sigil opens out and lets go after the implosion.
		local open = Kit.smooth(elapsed / 0.3)
		local fade = 1 - Kit.ramp(elapsed, collapseAt + 0.05, collapseAt + 0.6)
		local shown = open * fade
		local reach = R * (0.5 + 0.5 * open) * (1 - 0.25 * (1 - fade))
		local glow = (if erupting then 0.9 else 0.55) * shown
		layoutCircle(shade, reach * 0.5, shown * 0.45, 0.98 * reach / R)
		layoutCircle(outer, reach, shown)
		layoutCircle(outerGlow, reach, glow)
		layoutCircle(inner, reach * 0.72, shown)
		layoutCircle(innerGlow, reach * 0.72, glow * 0.8)
		for i, s in ipairs(runes) do
			local t = (i - 1) * math.pi / 6
			layoutArc(s, reach * 0.86, t, t + math.rad(16), shown)
		end
		spin += dt * (if erupting then 2.4 else 0.7)
		innerHost.CFrame = ringFrame * CFrame.Angles(0, spin, 0)
		runeHost.CFrame = ringFrame * CFrame.Angles(0, -spin * 0.6, 0)
		-- The pentagram draws itself in one continuous stroke.
		local drawing = false
		local scale = reach / R
		for i = 1, 5 do
			local p = Kit.ramp(elapsed, 0.25 + (i - 1) * 0.1, 0.25 + i * 0.1)
			local from = vertex(2 * (i - 1)) * scale
			local reached = from:Lerp(vertex(2 * i) * scale, p)
			layoutLine(star[i], from, reached, if p > 0 then shown else 0)
			layoutLine(starGlow[i], from, reached, if p > 0 then glow else 0)
			if p > 0 and p < 1 then
				drawing = true
				tip.Position = reached + Vector3.new(0, 0.3, 0)
			end
		end
		if tipGlow.Enabled ~= drawing then tipGlow.Enabled = drawing end
		-- The pull, the eye and the crackle while the gate opens.
		Kit.setEnabled(suction, elapsed > 0.1 and elapsed < openAt)
		local eyeOn = elapsed < openAt
		if eye.Enabled ~= eyeOn then eye.Enabled = eyeOn end
		if eyeOn then eye.Size = ns(1 + 3 * Kit.smooth(elapsed / openAt)) end
		local floating = elapsed < collapseAt
		if motes.Enabled ~= floating then motes.Enabled = floating end
		if elapsed >= nextBolt and elapsed < collapseAt then
			if erupting then
				pillarBolts[rng:NextInteger(1, #pillarBolts)]:Emit(1)
				nextBolt = elapsed + 0.05
			else
				bolts[rng:NextInteger(1, #bolts)]:Emit(1)
				nextBolt = elapsed + 0.2 - 0.13 * Kit.ramp(elapsed, 0, openAt)
			end
		end
		-- The pillar shoots up, swells, shimmers, and is sucked back down.
		local rise = Kit.smooth((elapsed - openAt) / 0.12)
		local sink = Kit.ramp(elapsed, collapseAt - 0.14, collapseAt)
		local height = T.PillarHeight * rise * (1 - 0.8 * sink * sink)
		local swell = if elapsed < openAt then 0 else (1 + 0.45 * math.exp(-(elapsed - openAt) * 10)) * (1 - sink)
		local shimmer = 1 + 0.06 * math.sin(elapsed * 47)
		top.WorldPosition = centre + up * math.max(height, 0.1)
		for i, col in ipairs(pillar) do
			local width = col.width * swell * shimmer
			if col.crackle then width *= 0.6 + 0.8 * math.abs(math.noise(elapsed * 9, i)) * 2 end
			col.beam.Width0, col.beam.Width1 = width, width * 1.25
			local on = erupting and width > 0.05
			if col.beam.Enabled ~= on then col.beam.Enabled = on end
		end
		Kit.setEnabled(stream, erupting and sink < 0.5)
		local after = elapsed - collapseAt
		light.Brightness = if erupting then 1.5 * (1 - sink) elseif after >= 0 then 5 * math.exp(-after * 6) else 0
		-- Ground rings: black out of the eruption, white out of the implosion.
		local w1 = (elapsed - openAt) / 0.5
		local w1On = w1 >= 0 and w1 <= 1
		local r1 = R * (0.6 + 1.8 * outward(w1))
		layoutCircle(eruptWave, r1, if w1On then 1 - w1 else 0, 1 - 0.6 * math.clamp(w1, 0, 1))
		layoutCircle(eruptGlow, r1, if w1On then 0.5 * (1 - w1) else 0)
		local w2 = after / 0.55
		local w2On = w2 >= 0 and w2 <= 1
		local r2 = R * (0.3 + 2.6 * outward(w2))
		layoutCircle(implodeWave, r2, if w2On then 1 - w2 else 0, 1 - 0.5 * math.clamp(w2, 0, 1))
		layoutCircle(implodeShadow, r2 * 0.92, if w2On then 0.8 * (1 - w2) else 0)
	end, {folder})

	timeline.at(0, function()
		Kit.burst(call)
		Kit.sound(callHost, SOUND_CALL, 0.45, 0.55)
		ImpactFX.shake(origin.Position, 0.3, 0.2, 40)
	end)
	timeline.at(openAt, function()
		Kit.burst(erupt)
		Kit.sound(pillarHost, SOUND_BOOM, 0.65, 0.7)
		ImpactFX.hit(centre + up * 3, {tint = PALE, pattern = "double", shake = 1.8, shakeDuration = 0.5, punch = 6, radius = 90})
		ImpactFX.shake(centre, 0.5, T.Erupt, 80)
	end)
	timeline.at(collapseAt, function()
		Kit.burst(implode)
		Kit.sound(pillarHost, SOUND_BOOM, 0.7, 1.1)
		Kit.sound(pillarHost, SOUND_HIT, 0.5, 0.7)
		ImpactFX.hit(centre + up * 3, {tint = PALE, pattern = "triple", shake = 2.6, shakeDuration = 0.7, punch = 10, radius = 100})
	end)
	return true
end

return VFX
