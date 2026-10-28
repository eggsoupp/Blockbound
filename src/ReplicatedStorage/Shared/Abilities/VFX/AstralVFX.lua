-- Astral Verdict, drawn from one message:
--   chart    stars pop into the sky over the aim one by one and are joined
--            into a constellation in the shape of a sword, while a star seal
--            draws itself on the ground below
--   forge    the constellation fades into a blade of starlight
--   verdict  the blade turns point-down, rises, and drops into the seal: a
--            star burst, a galaxy on the ground, impact frames, a shake and
--            a punch
--   shatter  after a moment the blade breaks into stars that arc out and
--            rain down round the seal
-- Every visible effect is an authored particle, Beam or Trail; Parts are
-- invisible emitter hosts only.
local Plan = require(script.Parent.Parent.AstralPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.AstralParticles)

local VFX = {}
local T = Plan.Tuning
local STAR = Color3.fromRGB(245, 245, 255)
local ASTRAL = Color3.fromRGB(150, 175, 255)
local VIOLET = Color3.fromRGB(165, 110, 255)
local NIGHT = Color3.fromRGB(25, 18, 60)
local ns, curve, colors = Kit.ns, Kit.curve, Kit.colors
local live = 0
local preloaded = false

local Sheets = {
	-- Slash VFX Trail2: a soft-edged band, for glows and the seal's strokes.
	Band = {Texture = "rbxassetid://16892374733"},
}

local SOUND_CHIME = "rbxasset://sounds/electronicpingshort.wav"
local SOUND_SWISH = "rbxassetid://12222208"
local SOUND_BOOM = "rbxassetid://5540424854"
local SOUND_HIT = "rbxasset://sounds/hit.wav"

function VFX.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload(Kit.textures(Library, Sheets), {SOUND_CHIME, SOUND_SWISH, SOUND_BOOM, SOUND_HIT})
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
		Kit.opacity(s.beam, if radius > 0.1 then opacity else 0)
	end
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

local function outward(t)
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

-- A beam between two attachments the update loop places in the world.
local function span(host, a0, a1, props)
	local all = {TextureMode = Enum.TextureMode.Stretch, TextureLength = 1, FaceCamera = true, Segments = 1, Enabled = false}
	for key, value in pairs(props) do all[key] = value end
	return Kit.beam(host, a0, a1, all)
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
	local look, side = Plan.frame(origin)
	local middle = centre + up * T.Height
	local L = T.Length
	local turnAt, dropAt, impactAt, shatterAt, rainAt = Plan.turnAt(), Plan.dropAt(), Plan.impactAt(), Plan.shatterAt(), Plan.rainAt()
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "AstralVerdict"
	folder.Parent = workspace

	-- The raised hand ----------------------------------------------------------------
	local caster = payload.caster
	local character = caster and caster.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local handPoint = if hand then hand.Position else (origin * CFrame.new(1.2, 1, -0.6)).Position
	local handHost = Kit.host(folder, "Hand", CFrame.new(handPoint))
	local handAt = Kit.attachment(handHost, CFrame.new(handPoint))
	local call = {
		{emitter("StarFlare", handAt, {Color = ColorSequence.new(STAR), Size = curve({0, 6}, {1, 0}), Lifetime = NumberRange.new(0.3)}), 1},
		{emitter("Sparkle", handAt, {Color = colors(STAR, ASTRAL), Size = ns(5), Lifetime = NumberRange.new(0.6), LightEmission = 1}), 1},
		{emitter("SlashStar", handAt, {Color = colors(STAR, VIOLET), Speed = NumberRange.new(40, 70)}), 6},
	}

	-- The constellation ------------------------------------------------------------------
	local skyHost = Kit.host(folder, "Sky", CFrame.new(middle))
	local stars = Plan.stars(payload.seed, middle, side)
	local appear = {}
	local points, pops, twinkles = {}, {}, {}
	for i, star in ipairs(stars) do
		appear[i] = 0.05 + (i - 1) * 0.07
		local at = Kit.attachment(skyHost, CFrame.new(star))
		points[i] = at
		pops[i] = {
			{emitter("StarFlare", at, {Color = ColorSequence.new(STAR), Size = curve({0, 8}, {1, 0}), Lifetime = NumberRange.new(0.35)}), 1},
			{emitter("Sparkle", at, {Color = colors(STAR, ASTRAL), Size = ns(6), Lifetime = NumberRange.new(0.6), LightEmission = 1}), 1},
		}
		twinkles[i] = {
			emitter("Twinkle", at, {Color = colors(ASTRAL, VIOLET), Size = ns(if i == 7 or i == 1 then 4.5 else 3.5), Lifetime = NumberRange.new(0.6),
				LightEmission = 0.5, Rotation = NumberRange.new(0, 90), Rate = 3, LockedToPart = true}),
			emitter("StarLight", at, {Color = ColorSequence.new(VIOLET), Size = ns(5), Rate = 3, Brightness = 2}),
		}
	end
	local links = {}
	for i, link in ipairs(Plan.links) do
		local a0, a1 = Kit.attachment(skyHost), Kit.attachment(skyHost)
		links[i] = {
			a0 = a0, a1 = a1, from = link[1], to = link[2],
			start = math.max(appear[link[1]], appear[link[2]]) + 0.04,
			-- Alpha-blended blue so the lines hold up against a daytime sky.
			beams = {
				span(skyHost, a0, a1, {Texture = "", Color = ColorSequence.new(Color3.fromRGB(110, 120, 240)), LightEmission = 0.3,
					Width0 = 0.35, Width1 = 0.35, ZOffset = 0.1}),
				span(skyHost, a0, a1, {Texture = Sheets.Band.Texture, Color = ColorSequence.new(VIOLET), LightEmission = 0.3, Brightness = 1.5,
					Width0 = 1.8, Width1 = 1.8}),
			},
		}
	end

	-- The blade ------------------------------------------------------------------------
	local swordHost = Kit.host(folder, "Sword", CFrame.new(middle))
	local hilt, tip = Kit.attachment(swordHost), Kit.attachment(swordHost)
	local guardL, guardR, pommel = Kit.attachment(swordHost), Kit.attachment(swordHost), Kit.attachment(swordHost)
	-- A solid astral-blue blade in a violet aura, with a white-hot edge down
	-- the middle. Additive layers bleach on a daytime sky, so the body is
	-- alpha-blended and only the edge glows.
	local blade = {
		{beam = span(swordHost, hilt, tip, {Texture = Library.Streak.Texture, Color = colors(VIOLET, ASTRAL), LightEmission = 0.4, Brightness = 1.5,
			Transparency = curve({0, 0.35}, {1, 0.65})}), w0 = 7.5, w1 = 1.6},
		{beam = span(swordHost, hilt, tip, {Texture = "", Color = colors(Color3.fromRGB(110, 120, 240), ASTRAL), LightEmission = 0.15, ZOffset = 0.1}),
			w0 = 3, w1 = 0.15},
		{beam = span(swordHost, hilt, tip, {Texture = Library.Spike.Texture, Color = ColorSequence.new(ASTRAL), LightEmission = 1, Brightness = 1.5,
			ZOffset = 0.15}), w0 = 2.6, w1 = 0.4},
		{beam = span(swordHost, hilt, tip, {Texture = "", Color = ColorSequence.new(STAR), LightEmission = 1, ZOffset = 0.2}), w0 = 0.45, w1 = 0.03},
	}
	local fittings = {
		span(swordHost, guardL, guardR, {Texture = "", Color = ColorSequence.new(Color3.fromRGB(110, 120, 240)), LightEmission = 0.15,
			Width0 = 1.1, Width1 = 1.1, ZOffset = 0.1}),
		span(swordHost, guardL, guardR, {Texture = Sheets.Band.Texture, Color = ColorSequence.new(VIOLET), LightEmission = 0.5, Brightness = 1.5,
			Width0 = 3, Width1 = 3}),
		span(swordHost, hilt, pommel, {Texture = "", Color = ColorSequence.new(Color3.fromRGB(80, 70, 160)), LightEmission = 0.3,
			Width0 = 0.8, Width1 = 0.7, ZOffset = 0.05}),
	}
	local gleam = {
		emitter("Orb", pommel, {Color = colors(STAR, VIOLET), Size = ns(2.4), Lifetime = NumberRange.new(0.5), LightEmission = 1, Rate = 6,
			LockedToPart = true}),
		emitter("StarFlare", hilt, {Color = ColorSequence.new(STAR), Size = curve({0, 3.5}, {1, 1}), Lifetime = NumberRange.new(0.3), Rate = 8,
			LockedToPart = true}),
	}
	local sparkles = {}
	for i = 1, 3 do
		local at = Kit.attachment(swordHost)
		sparkles[i] = {at = at, along = i / 4, emitter = emitter("Twinkle", at, {Color = colors(STAR, ASTRAL), Size = ns(2.6),
			Lifetime = NumberRange.new(0.5), LightEmission = 1, Rate = 4, Rotation = NumberRange.new(0, 90)})}
	end
	local smear = Kit.trail(swordHost, hilt, tip, {Texture = Library.Streak.Texture, Color = colors(STAR, VIOLET), LightEmission = 1,
		Brightness = 2, FaceCamera = true, Lifetime = 0.18, Transparency = curve({0, 0.2}, {1, 1}), Enabled = false})
	local tipAt = Kit.attachment(swordHost)
	local streaks = emitter("Lines", tipAt, {Color = colors(STAR, VIOLET), Speed = NumberRange.new(60, 100), EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(8, 8), Rate = 60, LockedToPart = false})
	local forge = {
		{emitter("StarFlare", hilt, {Color = ColorSequence.new(STAR), Size = curve({0, 10}, {1, 0}), Lifetime = NumberRange.new(0.3)}), 1},
		{emitter("Sparkle", hilt, {Color = colors(ASTRAL, VIOLET), Size = ns(8), Lifetime = NumberRange.new(0.6), LightEmission = 0.6}), 2},
	}
	local swordLight = Kit.light(swordHost, ASTRAL, 30)

	-- The seal --------------------------------------------------------------------------
	local sideFlat = normal:Cross(Vector3.zAxis)
	sideFlat = if sideFlat.Magnitude > 0.1 then sideFlat.Unit else Vector3.xAxis
	local sealFrame = CFrame.fromMatrix(centre + normal * 0.2, sideFlat, normal)
	local sealHost = Kit.host(folder, "Seal", sealFrame)
	local R = T.SealRadius
	local shade = circle(sealHost, R, NIGHT, 0, -0.1, "")
	local rim = circle(sealHost, 1, ASTRAL, 0.6, 0.1)
	local rimGlow = circle(sealHost, 3.5, VIOLET, 1, 0)
	local inner = circle(sealHost, 0.6, STAR, 0.8, 0.1)
	local octagram = {}
	for i = 1, 8 do octagram[i] = stroke(sealHost, 0.5, STAR, 0.8, 0.1) end
	local octaGlow = {}
	for i = 1, 8 do octaGlow[i] = stroke(sealHost, 2, VIOLET, 1, 0) end
	local sealLight = Kit.light(sealHost, ASTRAL, 26)

	-- The impact ------------------------------------------------------------------------
	local blastAt = Kit.attachment(sealHost, CFrame.new(centre + normal * 2))
	local groundAt = Kit.attachment(sealHost, CFrame.new(centre + normal * 0.6))
	local impact = {
		-- One white flash; the rest stays blue and violet so the layers do not
		-- bleach each other out.
		{emitter("StarFlare", blastAt, {Color = ColorSequence.new(STAR), Size = curve({0, 26}, {1, 0}), Lifetime = NumberRange.new(0.25)}), 1},
		{emitter("StarBurst", blastAt, {Color = colors(ASTRAL, VIOLET), Size = ns(22), Lifetime = NumberRange.new(0.45), LightEmission = 0.4}), 1},
		{emitter("HitFlash", blastAt, {Color = ColorSequence.new(ASTRAL), Size = curve({0, 12}, {1, 0}), Lifetime = NumberRange.new(0.15)}), 1},
		{emitter("HitRing", blastAt, {Color = ColorSequence.new(VIOLET), Size = curve({0, 4}, {0.5, 24}, {1, 30}), Lifetime = NumberRange.new(0.35),
			Brightness = 1, LightEmission = 0.5}), 1},
		{emitter("HitLines", blastAt, {Color = ColorSequence.new(STAR), Speed = NumberRange.new(80, 140), Size = curve({0, 6, 1}, {1, 0}),
			LockedToPart = false}), 16},
		{emitter("Lines", blastAt, {Color = colors(STAR, VIOLET), Speed = NumberRange.new(70, 120), EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(60, 60)}), 14},
		{emitter("Sparks", blastAt, {Color = colors(ASTRAL, VIOLET), Speed = NumberRange.new(60, 110), EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(70, 70), Lifetime = NumberRange.new(0.4, 0.7)}), 30},
		{emitter("SlashStar", blastAt, {Color = colors(STAR, VIOLET)}), 12},
		{emitter("Galaxy", groundAt, {Color = colors(ASTRAL, VIOLET), Size = ns(24), Lifetime = NumberRange.new(1.1), LightEmission = 0.4,
			Rotation = NumberRange.new(0, 360)}), 1},
		{emitter("Smoke", groundAt, {Color = ColorSequence.new(NIGHT), Size = curve({0, 0}, {0.15, 6, 1}, {1, 8}), Speed = NumberRange.new(25, 50),
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(90, 20), LockedToPart = false}), 14},
	}
	local shock = circle(sealHost, 2.5, STAR, 1, 0.2)
	local shockGlow = circle(sealHost, 7, VIOLET, 1, 0.1)

	-- The shatter -----------------------------------------------------------------------
	local tipEnd = centre - up * T.Bury
	local breakAt = Kit.attachment(swordHost)
	local shatter = {
		{emitter("StarFlare", breakAt, {Color = ColorSequence.new(STAR), Size = curve({0, 24}, {1, 0}), Lifetime = NumberRange.new(0.3)}), 1},
		{emitter("Sparkle", breakAt, {Color = colors(ASTRAL, VIOLET), Size = ns(9), Lifetime = NumberRange.new(0.6), LightEmission = 0.6}), 2},
		{emitter("HitFlash", breakAt, {Color = ColorSequence.new(STAR), Size = curve({0, 14}, {1, 0}), Lifetime = NumberRange.new(0.15)}), 1},
		{emitter("SlashStar", breakAt, {Color = colors(STAR, VIOLET)}), 12},
	}
	local params = Kit.rayParams({folder})
	local shards = Plan.shards(payload.seed)
	for i, shard in ipairs(shards) do
		local point = centre + shard.offset
		local hit = workspace:Raycast(point + up * 8, -up * 24, params)
		shard.landing = if hit then hit.Position else point
		shard.start = tipEnd + up * (L * shard.along)
		local host = Kit.host(folder, "Shard" .. i, CFrame.new(shard.start))
		local core = Kit.attachment(host)
		local top, bottom = Kit.attachment(host), Kit.attachment(host)
		top.Position, bottom.Position = Vector3.new(0, 0.35, 0), Vector3.new(0, -0.35, 0)
		shard.host = host
		shard.body = {
			emitter("StarFlare", core, {Color = ColorSequence.new(STAR), Size = curve({0, 3}, {1, 1.5}), Lifetime = NumberRange.new(0.15), Rate = 30,
				LockedToPart = true}),
		}
		shard.trail = Kit.trail(host, top, bottom, {Texture = Library.Streak.Texture, Color = colors(STAR, VIOLET), LightEmission = 1,
			Brightness = 2, FaceCamera = true, Lifetime = 0.2, Transparency = curve({0, 0}, {1, 1}), Enabled = false})
		local land = Kit.attachment(host)
		shard.landAt = land
		shard.burst = {
			{emitter("StarBurst", land, {Color = colors(STAR, ASTRAL), Size = ns(7), Lifetime = NumberRange.new(0.4), LightEmission = 1}), 1},
			{emitter("StarFlare", land, {Color = ColorSequence.new(STAR), Size = curve({0, 7}, {1, 0}), Lifetime = NumberRange.new(0.25)}), 1},
			{emitter("Sparkle", land, {Color = colors(STAR, ASTRAL), Size = ns(5), Lifetime = NumberRange.new(0.6), LightEmission = 1}), 1},
		}
	end

	-- The blade's pose at `elapsed`: hilt, axis (hilt to tip), how much of it
	-- has formed, and whether it is there at all.
	local function pose(elapsed)
		if elapsed < T.Draw or elapsed >= shatterAt then return nil end
		if elapsed < turnAt then
			return middle - up * (L / 2), up, Kit.smooth((elapsed - T.Draw) / T.Forge)
		end
		if elapsed < turnAt + T.Turn then
			local theta = math.pi * Kit.smooth((elapsed - turnAt) / T.Turn)
			local axis = up * math.cos(theta) + look * math.sin(theta)
			return middle - axis * (L / 2), axis, 1
		end
		if elapsed < dropAt then
			local lift = T.Rise * Kit.smooth((elapsed - turnAt - T.Turn) / T.Windup)
			return middle + up * (L / 2 + lift), -up, 1
		end
		if elapsed < impactAt then
			local d = math.clamp((elapsed - dropAt) / T.Drop, 0, 1)
			local from = middle + up * (T.Rise - L / 2)
			return from:Lerp(tipEnd, d * d) + up * L, -up, 1
		end
		local age = elapsed - impactAt
		local quiver = side * (math.sin(age * 70) * 0.35 * math.exp(-age * 6))
		return tipEnd + up * L + quiver, -up, 1
	end

	local spin = 0
	local last
	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local dt = if last then math.max(elapsed - last, 0) else 0
		last = elapsed
		-- The constellation draws, then fades into the blade.
		local chartFade = 1 - Kit.ramp(elapsed, T.Draw, T.Draw + T.Forge * 0.8)
		for i, at in ipairs(points) do
			local shown = elapsed >= appear[i] and chartFade > 0.05
			Kit.setEnabled(twinkles[i], shown)
		end
		for _, link in ipairs(links) do
			local p = Kit.ramp(elapsed, link.start, link.start + 0.12)
			link.a0.WorldPosition = stars[link.from]
			link.a1.WorldPosition = stars[link.from]:Lerp(stars[link.to], p)
			for _, beam in ipairs(link.beams) do Kit.opacity(beam, if p > 0 then chartFade * (if beam.Texture == "" then 1 else 0.6) else 0) end
		end
		-- The blade.
		local h, axis, grow = pose(elapsed)
		local shown = h ~= nil
		if shown then
			local reach = L * grow
			hilt.WorldPosition = h
			tip.WorldPosition = h + axis * math.max(reach, 0.1)
			tipAt.WorldPosition = h + axis * reach
			pommel.WorldPosition = h - axis * 3 * grow
			guardL.WorldPosition = h - side * 3.2 * grow
			guardR.WorldPosition = h + side * 3.2 * grow
			breakAt.WorldPosition = h + axis * (L / 2)
			for _, s in ipairs(sparkles) do s.at.WorldPosition = h + axis * (reach * s.along) end
			for _, layer in ipairs(blade) do
				layer.beam.Width0, layer.beam.Width1 = layer.w0, layer.w1
			end
		end
		for _, layer in ipairs(blade) do
			if layer.beam.Enabled ~= shown then layer.beam.Enabled = shown end
		end
		for _, beam in ipairs(fittings) do
			if beam.Enabled ~= shown then beam.Enabled = shown end
		end
		Kit.setEnabled(gleam, shown)
		for _, s in ipairs(sparkles) do
			local on = shown and grow == 1
			if s.emitter.Enabled ~= on then s.emitter.Enabled = on end
		end
		local turning = elapsed >= turnAt and elapsed < dropAt
		if smear.Enabled ~= turning then smear.Enabled = turning end
		local falling = elapsed >= dropAt and elapsed < impactAt
		if streaks.Enabled ~= falling then streaks.Enabled = falling end
		swordLight.Brightness = if shown then 1.5 else 0
		-- The seal turns under it, flaring at the impact.
		local open = outward((elapsed - 0.1) / 0.5)
		local fade = 1 - Kit.ramp(elapsed, rainAt, rainAt + 0.7)
		local flare = if elapsed >= impactAt then 1 + 1.5 * math.exp(-(elapsed - impactAt) * 5) else 1
		local reach = R * open
		local glow = 0.5 * open * fade * flare
		layoutCircle(shade, reach * 0.5, 0.35 * open * fade, 0.98 * open)
		layoutCircle(rim, reach, open * fade)
		layoutCircle(rimGlow, reach, glow)
		layoutCircle(inner, reach * 0.55, open * fade)
		spin += dt * (if elapsed >= impactAt then 0.4 else 1.2)
		for i = 1, 8 do
			local p = Kit.ramp(elapsed, 0.15 + (i - 1) * 0.05, 0.3 + (i - 1) * 0.05)
			local t0 = spin + (i - 1) * math.pi / 4
			local from = radial(t0) * reach * 0.92
			local to = from:Lerp(radial(t0 + 3 * math.pi / 4) * reach * 0.92, p)
			layoutLine(octagram[i], from, to, if p > 0 then open * fade else 0)
			layoutLine(octaGlow[i], from, to, if p > 0 then glow * 0.8 else 0)
		end
		sealLight.Brightness = 1.2 * open * fade * flare
		-- Shock rings out of the impact.
		local wave = (elapsed - impactAt) / 0.45
		local waveOn = wave >= 0 and wave <= 1
		layoutCircle(shock, 2 + 22 * outward(wave), if waveOn then 1 - wave else 0, 1 - 0.7 * math.clamp(wave, 0, 1))
		layoutCircle(shockGlow, 2 + 20 * outward(wave), if waveOn then 0.5 * (1 - wave) else 0)
		-- The shards of the shattered blade arc out and fall.
		for _, shard in ipairs(shards) do
			local t = (elapsed - shatterAt) / shard.flight
			local flying = t >= 0 and t < 1
			if flying then
				local control = (shard.start + shard.landing) / 2 + up * shard.lift
				local position = shard.start:Lerp(control, t):Lerp(control:Lerp(shard.landing, t), t)
				shard.host.CFrame = CFrame.new(position)
			end
			Kit.setEnabled(shard.body, flying)
			if shard.trail.Enabled ~= flying then shard.trail.Enabled = flying end
		end
	end, {folder})

	timeline.at(0, function()
		Kit.burst(call)
		Kit.sound(handHost, SOUND_SWISH, 0.35, 1.4)
	end)
	for i in ipairs(stars) do
		timeline.at(appear[i], function()
			Kit.burst(pops[i])
			Kit.sound(skyHost, SOUND_CHIME, 0.15, 0.8 + i * 0.08)
		end)
	end
	timeline.at(T.Draw, function()
		Kit.burst(forge)
		Kit.sound(swordHost, SOUND_SWISH, 0.5, 0.7)
	end)
	timeline.at(turnAt, function()
		Kit.sound(swordHost, SOUND_SWISH, 0.5, 1.1)
		ImpactFX.shake(centre, 0.4, 0.2, 60)
	end)
	timeline.at(impactAt, function()
		Kit.burst(impact)
		Kit.sound(sealHost, SOUND_BOOM, 0.8, 1.05)
		Kit.sound(sealHost, SOUND_HIT, 0.5, 0.8)
		ImpactFX.hit(centre + normal * 3, {tint = ASTRAL, pattern = "triple", shake = 2.4, shakeDuration = 0.6, punch = 9, radius = 90})
	end)
	timeline.at(shatterAt, function()
		Kit.burst(shatter)
		Kit.sound(swordHost, SOUND_CHIME, 0.4, 0.6)
		ImpactFX.shake(centre, 0.7, 0.2, 60)
	end)
	for i, shard in ipairs(shards) do
		timeline.at(shatterAt + shard.flight, function()
			shard.landAt.WorldPosition = shard.landing + up * 0.8
			Kit.burst(shard.burst)
			if i % 4 == 0 then Kit.sound(shard.host, SOUND_CHIME, 0.2, 1.2 + i * 0.03) end
		end)
	end
	timeline.at(rainAt, function()
		ImpactFX.shake(centre, 0.8, 0.25, 60)
	end)
	return true
end

return VFX
