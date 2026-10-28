-- Azure Comet, drawn from one message:
--   gather  lightning crackles off the caster's raised hand while a blue
--           comet swells high above them, drawing sparks in and throwing
--           rings of flame off itself
--   dive    the comet streaks down at the aim trailing a ribbon of blue fire
--   impact  a white-blue blast with shockwaves, sparks and rolling smoke;
--           glowing fissures split the ground; impact frames, a shake and
--           a punch
--   pulses  three pressure rings slam down onto the crater, each kicking up
--           flame
-- Every visible effect is an authored particle, Beam or Trail; Parts are
-- invisible emitter hosts only.
local Plan = require(script.Parent.Parent.CometPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.CometParticles)

local VFX = {}
local T = Plan.Tuning
local ICE = Color3.fromRGB(225, 245, 255)
local CYAN = Color3.fromRGB(80, 200, 255)
local AZURE = Color3.fromRGB(30, 110, 255)
local DEEP = Color3.fromRGB(12, 28, 70)
local ns, curve, colors = Kit.ns, Kit.curve, Kit.colors
local live = 0
local preloaded = false

local Sheets = {
	-- Slash VFX Trail2: a soft-edged band, laid flat for rings and fissures.
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

-- A stroke lying flat in its host's XZ plane (the host stands with Y along
-- the ground normal). A beam bends along its attachments' X axes and spreads
-- its width along their Y axes, so Y points across the stroke on the ground.
local function stroke(host, width, color, emission, z)
	local a0, a1 = Kit.attachment(host), Kit.attachment(host)
	local beam = Kit.beam(host, a0, a1, {
		Texture = Sheets.Band.Texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1, FaceCamera = false,
		Segments = 12, Width0 = width, Width1 = width, Color = ColorSequence.new(color), LightEmission = emission,
		Brightness = if emission > 0 then 2 else 1, Transparency = ns(1), Enabled = false, ZOffset = z or 0,
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
		Kit.opacity(s.beam, opacity)
	end
end

local function layoutLine(s, from, to, opacity, width0, width1)
	local along = to - from
	if along.Magnitude < 0.05 then
		Kit.opacity(s.beam, 0)
		return
	end
	local across = Vector3.yAxis:Cross(along).Unit
	s.a0.CFrame = CFrame.fromMatrix(from, along.Unit, across)
	s.a1.CFrame = CFrame.fromMatrix(to, along.Unit, across)
	s.beam.Width0, s.beam.Width1 = width0, width1
	Kit.opacity(s.beam, opacity)
end

-- Resizes a looping emitter by `scale` without rebuilding its sequence
-- every frame.
local function rescale(e, base, scale)
	local key = math.round(scale * 30)
	if e:GetAttribute("Scale") ~= key then
		e:SetAttribute("Scale", key)
		local points = {}
		for _, p in ipairs(base.Keypoints) do
			table.insert(points, NumberSequenceKeypoint.new(p.Time, p.Value * scale, p.Envelope * scale))
		end
		e.Size = NumberSequence.new(points)
	end
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.sky) ~= "Vector3" or typeof(payload.impact) ~= "Vector3"
		or typeof(payload.normal) ~= "Vector3" or type(payload.startedAt) ~= "number" or type(payload.seed) ~= "number" then
		return false
	end
	local total = Plan.duration()
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 3 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local origin, sky, impact, normal = payload.origin, payload.sky, payload.impact, payload.normal
	local up = Vector3.yAxis
	local rng = Random.new(payload.seed)
	local impactAt = Plan.impactAt()
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "AzureComet"
	folder.Parent = workspace

	-- The raised hand -----------------------------------------------------------
	local caster = payload.caster
	local character = caster and caster.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local handPoint = if hand then hand.Position else (origin * CFrame.new(1.2, 1, -0.6)).Position
	local handHost = Kit.host(folder, "Hand", CFrame.new(handPoint))
	local handAt = Kit.attachment(handHost, CFrame.new(handPoint))
	local handCrackle = emitter("Bolt", handAt, {Color = colors(ICE, CYAN), Size = ns(3.5), Lifetime = NumberRange.new(0.3), LockedToPart = true})
	local handGlow = emitter("Glow", handAt, {Color = ColorSequence.new(CYAN), Size = ns(5), Speed = NumberRange.new(0), Drag = 0,
		Lifetime = NumberRange.new(0.2), Transparency = curve({0, 0.5}, {1, 1}), Rate = 20})

	-- The comet ------------------------------------------------------------------
	local cometHost = Kit.host(folder, "Comet", CFrame.new(sky))
	local core = Kit.attachment(cometHost)
	local trailTop = Kit.attachment(cometHost)
	local trailBottom = Kit.attachment(cometHost)
	trailTop.Position, trailBottom.Position = Vector3.new(0, 2.4, 0), Vector3.new(0, -2.4, 0)
	-- Additive layers bleach to white against a daytime sky, so the comet's
	-- body is alpha-blended blue fire round a small additive core.
	local sizes = {
		glow = curve({0, 8}, {1, 6}),
		flare = curve({0, 6}, {1, 2.5}),
		wisp = curve({0, 7, 1}, {1, 0}),
		puff = curve({0, 0}, {0.4, 6}, {1, 6.5}),
	}
	local cometGlow = emitter("Glow", core, {Color = ColorSequence.new(AZURE), Size = sizes.glow, Speed = NumberRange.new(0), Drag = 0,
		Lifetime = NumberRange.new(0.25), Transparency = curve({0, 0.55}, {1, 1}), Rate = 24})
	local cometFlare = emitter("Glare", core, {Color = ColorSequence.new(ICE), Size = sizes.flare, Lifetime = NumberRange.new(0.2),
		Brightness = 3, Rotation = NumberRange.new(0, 360), Rate = 10, LockedToPart = true})
	local cometWisps = emitter("Wisp", core, {Color = colors(CYAN, AZURE), Size = sizes.wisp, Lifetime = NumberRange.new(0.45),
		Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Brightness = 2, LightEmission = 0.3, LightInfluence = 0,
		LockedToPart = false, Rate = 45})
	local cometPuffs = emitter("Puff", core, {Color = colors(CYAN, AZURE, DEEP), Size = sizes.puff, Lifetime = NumberRange.new(0.5),
		Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Brightness = 1.5, LightEmission = 0, LightInfluence = 0,
		LockedToPart = false, Rate = 28})
	local cometBolt = emitter("Bolt", core, {Color = colors(ICE, CYAN), Size = ns(9), Lifetime = NumberRange.new(0.35), LockedToPart = true})
	local comet = {cometGlow, cometFlare, cometWisps, cometPuffs}
	local trail = Kit.trail(cometHost, trailTop, trailBottom, {
		Texture = Library.TailFlow.Texture, Color = colors(ICE, CYAN, AZURE), LightEmission = 1, Brightness = 3, FaceCamera = true,
		Lifetime = 0.3, Transparency = curve({0, 0}, {0.6, 0.4}, {1, 1}), WidthScale = curve({0, 1}, {1, 0.2}), Enabled = false,
	})
	local tailEnd = Kit.attachment(cometHost)
	local tail = {
		Kit.beam(cometHost, core, tailEnd, {Texture = Library.Spike.Texture, Color = colors(ICE, CYAN), LightEmission = 1, Brightness = 4,
			FaceCamera = true, Segments = 1, Width0 = 5, Width1 = 1, Transparency = curve({0, 0}, {1, 0.6}), Enabled = false, ZOffset = 0.2}),
		Kit.beam(cometHost, core, tailEnd, {Texture = Library.TailFlow.Texture, Color = colors(CYAN, AZURE), LightEmission = 0.3, Brightness = 2,
			FaceCamera = true, Segments = 1, Width0 = 7, Width1 = 2, TextureSpeed = 3, Transparency = curve({0, 0.1}, {1, 1}), Enabled = false}),
	}
	-- Sparks drawn in from a sphere round the comet while it gathers.
	local gatherHost = Kit.host(folder, "Gather", CFrame.new(sky), Vector3.one * 18)
	local gather = emitter("Embers", gatherHost, {Color = colors(ICE, CYAN), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Speed = NumberRange.new(22, 30),
		Lifetime = NumberRange.new(0.35), Size = curve({0, 0}, {0.3, 1}, {1, 0}), LightEmission = 1, LockedToPart = false, Rate = 40})
	local tether = Kit.beam(handHost, handAt, core, {Texture = Library.Spike.Texture, Color = colors(ICE, CYAN), LightEmission = 1,
		Brightness = 2, FaceCamera = true, Segments = 1, Width0 = 0.4, Width1 = 2.2, Transparency = ns(1), Enabled = false})
	local launch = {
		{emitter("Shockwave", core, {Color = colors(CYAN, AZURE), Size = curve({0, 0}, {1, 20}), Brightness = 1.5, LightInfluence = 0,
			Transparency = curve({0, 0.2}, {1, 1})}), 2},
		{emitter("Burst", core, {Color = colors(ICE, CYAN), Size = curve({0, 0}, {1, 18}), Brightness = 3}), 2},
		{emitter("Glare", core, {Color = ColorSequence.new(ICE), Size = curve({0, 26}, {1, 0}), Brightness = 4}), 1},
		{emitter("Sparks", core, {Color = colors(ICE, CYAN), Speed = NumberRange.new(60, 100), Size = curve({0, 1.6}, {1, 0}),
			Lifetime = NumberRange.new(0.6), LightInfluence = 0}), 16},
	}
	local pulseRing = emitter("Shockwave", core, {Color = colors(CYAN, AZURE), Size = curve({0, 2}, {1, 16}), Brightness = 1, LightInfluence = 0,
		Lifetime = NumberRange.new(0.35), Transparency = curve({0, 0.3}, {1, 1})})
	local cometLight = Kit.light(cometHost, CYAN, 40)

	-- The crater -----------------------------------------------------------------
	local side = normal:Cross(Vector3.zAxis)
	side = if side.Magnitude > 0.1 then side.Unit else Vector3.xAxis
	local ringFrame = CFrame.fromMatrix(impact + normal * 0.2, side, normal)
	local craterHost = Kit.host(folder, "Crater", ringFrame)
	local blastAt = Kit.attachment(craterHost, CFrame.new(impact + normal * 2))
	local groundAt = Kit.attachment(craterHost, CFrame.new(impact + normal * 0.6))
	local blast = {
		-- One white flash; everything after it stays blue so the blast is not
		-- bleached by stacked additive layers.
		{emitter("Glare", blastAt, {Color = ColorSequence.new(ICE), Size = curve({0, 28}, {1, 0}), Lifetime = NumberRange.new(0.25), Brightness = 2}), 1},
		{emitter("Burst", blastAt, {Color = colors(CYAN, AZURE), Size = curve({0, 0}, {1, 30}), Lifetime = NumberRange.new(0.2), Brightness = 2}), 2},
		{emitter("Shockwave", blastAt, {Color = colors(CYAN, AZURE), Size = curve({0, 0}, {1, 44}), Lifetime = NumberRange.new(0.4),
			Brightness = 1.2, LightInfluence = 0, Transparency = curve({0, 0.3}, {1, 1})}), 2},
		{emitter("Billow", blastAt, {Color = colors(CYAN, AZURE, DEEP), Size = curve({0, 0}, {0.15, 20}, {1, 15}), LightInfluence = 0,
			LightEmission = 0.2, Brightness = 1.5, Speed = NumberRange.new(-90, 90)}), 14},
		{emitter("Puff", blastAt, {Color = colors(CYAN, AZURE), Size = curve({0, 0}, {0.4, 8}, {1, 9}), Speed = NumberRange.new(30, 60),
			SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(0.7), LightEmission = 0.1, Drag = 3, LockedToPart = false}), 16},
		{emitter("Sparks", blastAt, {Color = colors(ICE, CYAN), Speed = NumberRange.new(80, 160), Size = curve({0, 2}, {1, 0}),
			Acceleration = Vector3.new(0, -60, 0), LightInfluence = 0, Lifetime = NumberRange.new(0.8, 1.2)}), 40},
		{emitter("Glint", blastAt, {Color = ColorSequence.new(CYAN), Size = curve({0, 6}, {0.2, 18}, {1, 0}), Brightness = 2, LockedToPart = false}), 2},
		{emitter("Shards", blastAt, {Color = colors(CYAN, AZURE), LightEmission = 0.5, LockedToPart = false, Speed = NumberRange.new(90, 170),
			Size = curve({0, 0}, {0.25, 6, 2}, {1, 0})}), 24},
		{emitter("Bolt", blastAt, {Color = colors(ICE, CYAN), Size = ns(16), Lifetime = NumberRange.new(0.4), LockedToPart = false}), 4},
		{emitter("Smoke", groundAt, {Color = ColorSequence.new(DEEP), Size = curve({0, 0}, {0.12, 18}, {1, 16}), Lifetime = NumberRange.new(2, 2.8),
			Speed = NumberRange.new(20, 40), Acceleration = Vector3.new(0, 10, 0), LightInfluence = 0, Transparency = curve({0, 1}, {0.12, 0.5}, {1, 1})}), 8},
	}
	local shock = circle(craterHost, 3, ICE, 1, 0.2)
	local shockGlow = circle(craterHost, 8, CYAN, 1, 0.1)
	local rim = circle(craterHost, 4, DEEP, 0, 0)
	-- Glowing fissures splitting out of the crater.
	local fissures = {}
	for i = 1, 7 do
		local angle = (i - 1) / 7 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local length = rng:NextNumber(7, 13)
		local bend = rng:NextNumber(-0.35, 0.35)
		fissures[i] = {
			from = radial(angle) * 1.5,
			mid = radial(angle + bend) * length * 0.55,
			to = radial(angle + bend * 0.4) * length,
			dark = {stroke(craterHost, 1, DEEP, 0, 0.1), stroke(craterHost, 1, DEEP, 0, 0.1)},
			glow = {stroke(craterHost, 1, CYAN, 1, 0.15), stroke(craterHost, 1, CYAN, 1, 0.15)},
		}
	end
	local floor = Kit.host(folder, "Floor", ringFrame * CFrame.new(0, 0.5, 0), Vector3.new(10, 0.2, 10))
	local flames = emitter("Wisp", floor, {Color = colors(ICE, CYAN, AZURE), Size = curve({0, 3.5, 1}, {1, 0}), Lifetime = NumberRange.new(0.6),
		Speed = NumberRange.new(4, 9), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(15, 15), Brightness = 2,
		LockedToPart = false, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Rate = 30})
	local craterLight = Kit.light(craterHost, CYAN, 45)

	-- The pressure rings -----------------------------------------------------------
	local pressureHost = Kit.host(folder, "Pressure", ringFrame)
	local pressure = circle(pressureHost, 1.6, ICE, 1, 0.2)
	local pressureGlow = circle(pressureHost, 5, CYAN, 1, 0.1)
	local stomp = {
		{emitter("Shockwave", groundAt, {Color = colors(ICE, CYAN), Size = curve({0, 4}, {1, 26}), Lifetime = NumberRange.new(0.3),
			Brightness = 2, LightInfluence = 0}), 1},
		{emitter("Puff", groundAt, {Color = colors(CYAN, AZURE), Size = curve({0, 0}, {0.4, 5}, {1, 6}), Speed = NumberRange.new(25, 40),
			SpreadAngle = Vector2.new(90, 10), EmissionDirection = Enum.NormalId.Top, Lifetime = NumberRange.new(0.5), LightEmission = 0.6,
			Drag = 4, LockedToPart = false}), 10},
		{emitter("Wisp", groundAt, {Color = colors(ICE, CYAN), Size = curve({0, 5, 1}, {1, 0}), Speed = NumberRange.new(10, 18),
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(30, 30), Lifetime = NumberRange.new(0.4), LockedToPart = false}), 6},
	}

	local nextCrackle = 0.1
	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		-- The gather: the comet swells and the hand crackles.
		local gathering = elapsed < T.Charge
		local swell = 0.35 + 0.65 * Kit.smooth(elapsed / T.Charge)
		local beat = 1 + 0.12 * math.sin(elapsed * 30) * (if gathering then 1 else 0.3)
		rescale(cometGlow, sizes.glow, swell * beat)
		rescale(cometFlare, sizes.flare, swell * beat)
		rescale(cometWisps, sizes.wisp, swell)
		rescale(cometPuffs, sizes.puff, swell)
		local flying = elapsed >= T.Charge and elapsed < impactAt
		Kit.setEnabled(comet, elapsed < impactAt)
		gather.Enabled = gathering and elapsed > 0.1
		handGlow.Enabled = gathering
		if gathering and elapsed >= nextCrackle then
			handCrackle:Emit(1)
			cometBolt:Emit(1)
			nextCrackle = elapsed + 0.12
		end
		local tetherOn = gathering and elapsed > 0.15
		Kit.opacity(tether, if tetherOn then 0.55 + 0.35 * math.abs(math.noise(elapsed * 12, 1)) * 2 else 0)
		-- The dive.
		local position, along = Plan.flight(sky, impact, elapsed)
		local heading = impact - sky
		heading = if heading.Magnitude > 0.1 then heading.Unit else -up
		if elapsed < impactAt then
			cometHost.CFrame = CFrame.lookAt(position, position + heading)
		end
		if trail.Enabled ~= flying then trail.Enabled = flying end
		tailEnd.WorldPosition = position - heading * (8 + 18 * along)
		for _, beam in ipairs(tail) do
			if beam.Enabled ~= flying then beam.Enabled = flying end
		end
		cometLight.Brightness = if elapsed < impactAt then 1 + 2 * swell else 0
		-- The crater.
		local age = elapsed - impactAt
		local landed = age >= 0
		local wave = age / 0.4
		local waveOn = wave >= 0 and wave <= 1
		local reach = 2 + 24 * (1 - (1 - math.clamp(wave, 0, 1)) ^ 3)
		layoutCircle(shock, reach, if waveOn then 1 - wave else 0, 1 - 0.8 * math.clamp(wave, 0, 1))
		layoutCircle(shockGlow, reach * 0.92, if waveOn then 0.6 * (1 - wave) else 0)
		local fade = 1 - Kit.ramp(elapsed, total - 0.9, total - 0.1)
		layoutCircle(rim, 7, if landed then 0.6 * fade else 0)
		local split = Kit.smooth(age / 0.15)
		for i, crack in ipairs(fissures) do
			local glowing = if landed then fade * (0.75 + 0.25 * math.noise(elapsed * 6, i)) else 0
			local first = math.clamp(split * 2, 0, 1)
			local second = math.clamp(split * 2 - 1, 0, 1)
			local mid = crack.from:Lerp(crack.mid, first)
			local tip = crack.mid:Lerp(crack.to, second)
			layoutLine(crack.dark[1], crack.from, mid, if landed then fade else 0, 1.6, 1.2)
			layoutLine(crack.dark[2], crack.mid, tip, if second > 0 then fade else 0, 1.2, 0.3)
			layoutLine(crack.glow[1], crack.from, mid, glowing, 3.6, 2.8)
			layoutLine(crack.glow[2], crack.mid, tip, if second > 0 then glowing else 0, 2.8, 0.8)
		end
		local burning = landed and elapsed < total - 0.6
		if flames.Enabled ~= burning then flames.Enabled = burning end
		craterLight.Brightness = if landed then 5 * math.exp(-age * 5) + 0.8 * fade else 0
		-- Each pressure ring drops out of the sky onto the crater, widening.
		local shown, height, radius = 0, 0, 8
		for i = 1, T.Pulses do
			local p = (elapsed - (Plan.pulseAt(i) - 0.27)) / 0.27
			if p >= 0 and p <= 1 then
				shown = math.min(1, p * 3)
				height = 18 * (1 - p * p)
				radius = 8 + 8 * p * p
			end
		end
		pressureHost.CFrame = ringFrame + normal * height
		layoutCircle(pressure, radius, shown)
		layoutCircle(pressureGlow, radius, shown * 0.6)
	end, {folder})

	timeline.at(0, function()
		Kit.sound(handHost, SOUND_SWISH, 0.4, 0.5)
		Kit.burst({{pulseRing, 1}})
	end)
	timeline.at(T.Charge * 0.5, function()
		Kit.burst({{pulseRing, 1}})
	end)
	timeline.at(T.Charge, function()
		Kit.burst(launch)
		Kit.sound(cometHost, SOUND_SWISH, 0.6, 1.1)
		ImpactFX.shake(origin.Position, 0.5, 0.25, 50)
	end)
	timeline.at(impactAt, function()
		Kit.burst(blast)
		Kit.sound(craterHost, SOUND_BOOM, 0.8, 0.9)
		Kit.sound(craterHost, SOUND_HIT, 0.5, 0.8)
		ImpactFX.hit(impact + normal * 3, {tint = CYAN, pattern = "triple", shake = 2.2, shakeDuration = 0.6, punch = 8, radius = 90})
	end)
	for i = 1, T.Pulses do
		timeline.at(Plan.pulseAt(i), function()
			Kit.burst(stomp)
			Kit.sound(craterHost, SOUND_HIT, 0.35, 0.6 + i * 0.1)
			ImpactFX.shake(impact, 0.7, 0.2, 60)
		end)
	end
	return true
end

return VFX
