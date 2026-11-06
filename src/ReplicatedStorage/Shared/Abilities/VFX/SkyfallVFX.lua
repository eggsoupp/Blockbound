local CombatAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.CombatAudio)
-- Skyfall Volley, drawn from one message:
--   draw    jade energy gathers at the caster's bow hand
--   loose   a signal arrow streaks straight up off a burst at their feet
--   mark    two jade rings open on the target, the inner one turning
--   rain    light-arrows streak down inside them, each landing in a small burst
--   finale  a great arrow pins the centre: a jade blast, cubes and a ground
--           shockwave, with impact frames, a shake and a punch
-- Every visible effect is an authored particle or textured Beam; Parts are
-- invisible emitter hosts only.
local Plan = require(script.Parent.Parent.SkyfallPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.SkyfallParticles)

local VFX = {}
local T = Plan.Tuning
local JADE = Color3.fromRGB(60, 230, 140)
local MINT = Color3.fromRGB(185, 255, 215)
local WHITE = Color3.fromRGB(240, 255, 245)
local ns, curve, colors = Kit.ns, Kit.curve, Kit.colors
local live = 0
local preloaded = false
local POOL = 8

local Sheets = {
	-- Explosions.FinalExplosion "changee": a sharp tapered glow. Along a Beam
	-- it is a streak of light, the hot core of every arrow.
	Spike = {Texture = "rbxassetid://18245342832"},
	-- Slash VFX Trail2: a soft-edged band, laid flat along the circle's beams.
	Band = {Texture = "rbxassetid://16892374733"},
	-- VFX :D.177 Images/circle2: an energetic ring that pulses in the circle.
	Rune = {
		Texture = "rbxassetid://114089808533551",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		LightEmission = 1,
	},
}

local SOUND_DRAW = CombatAudio.ids.charge_short
local SOUND_THUNK = "impact.light"
local SOUND_FINALE = "impact.heavy"

function VFX.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload(Kit.textures(Library, Sheets), {SOUND_DRAW, SOUND_THUNK, SOUND_FINALE})
end

function VFX.duration()
	return Plan.duration()
end

local function emitter(kind, parent, props)
	return Kit.emitter(if Sheets[kind] then Sheets else Library, kind, parent, props)
end

-- An arrow of light: a solid jade taper fading towards its tail, a hot
-- white streak over it and a glow at the tip, between a head and a tail
-- attachment that the update loop places.
local function arrowRig(folder, name, width, length)
	local host = Kit.host(folder, name, CFrame.new())
	local head = Kit.attachment(host)
	local tail = Kit.attachment(host)
	local function streak(texture, color, w, brightness, z, fade)
		return Kit.beam(host, tail, head, {
			Texture = texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1,
			FaceCamera = true, Segments = 1, Color = ColorSequence.new(color), Width0 = w * 0.2, Width1 = w,
			LightEmission = 1, Brightness = brightness, ZOffset = z, Enabled = false, Transparency = fade or ns(0),
		})
	end
	local tip = emitter("Core", head, {Color = ColorSequence.new(JADE), Size = ns(math.min(width, 1.4) * 1.2), Lifetime = NumberRange.new(0.08),
		Brightness = 2, Rate = 60, LockedToPart = true})
	return {host = host, head = head, tail = tail, length = length, tip = tip,
		beams = {streak("", JADE, width * 1.1, 1.5, 0, curve({0, 1}, {0.6, 0.6}, {1, 0.15})), streak(Sheets.Spike.Texture, WHITE, width * 1.3, 3, 0.1)}}
end

-- A flat ring of four curved beams. A cubic quarter arc is circular when its
-- control points sit 0.5523 of the radius along each end's tangent. Flat
-- particles do not show on this ground, so the circle is drawn in beams.
local function ringBeams(host, width, color, emission)
	local arcs = {}
	for q = 0, 3 do
		local a0, a1 = Kit.attachment(host), Kit.attachment(host)
		local beam = Kit.beam(host, a0, a1, {
			Texture = Sheets.Band.Texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1, FaceCamera = false,
			Segments = 16, Width0 = width, Width1 = width, Color = ColorSequence.new(color), LightEmission = emission,
			Brightness = 2.5, Transparency = ns(1), Enabled = false,
		})
		table.insert(arcs, {beam = beam, a0 = a0, a1 = a1, q = q})
	end
	return arcs
end

local function layoutRing(arcs, radius, opacity)
	for _, arc in ipairs(arcs) do
		local t0, t1 = arc.q * math.pi / 2, (arc.q + 1) * math.pi / 2
		local p0 = Vector3.new(math.cos(t0), 0, math.sin(t0)) * radius
		local p1 = Vector3.new(math.cos(t1), 0, math.sin(t1)) * radius
		-- A beam's width runs along its attachments' Y: radial keeps it flat.
		arc.a0.CFrame = CFrame.fromMatrix(p0, Vector3.new(-math.sin(t0), 0, math.cos(t0)), p0.Unit)
		arc.a1.CFrame = CFrame.fromMatrix(p1, Vector3.new(-math.sin(t1), 0, math.cos(t1)), p1.Unit)
		arc.beam.CurveSize0, arc.beam.CurveSize1 = radius * 0.5523, radius * 0.5523
		Kit.opacity(arc.beam, opacity)
	end
end

local function placeArrow(rig, tip, up, visible)
	rig.head.WorldPosition = tip
	rig.tail.WorldPosition = tip + up * rig.length
	for _, beam in ipairs(rig.beams) do
		if beam.Enabled ~= visible then beam.Enabled = visible end
	end
	if rig.tip.Enabled ~= visible then rig.tip.Enabled = visible end
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.centre) ~= "Vector3" or typeof(payload.normal) ~= "Vector3"
		or type(payload.startedAt) ~= "number" or type(payload.seed) ~= "number" then
		return false
	end
	local total = T.FinaleAt + T.Aftermath
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 3 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local origin, centre, normal = payload.origin, payload.centre, payload.normal
	local up = Vector3.yAxis
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "SkyfallVolley"
	folder.Parent = workspace
	local caster = payload.caster
	local character = caster and caster.Character
	local hand = character and (character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm"))
	local handPoint = if hand then hand.Position else (origin * CFrame.new(-1.2, 0.8, -1)).Position

	-- Draw and loose -----------------------------------------------------------
	local drawHost = Kit.host(folder, "Draw", CFrame.new(handPoint))
	local drawAt = Kit.attachment(drawHost, CFrame.lookAt(handPoint, handPoint + up))
	local charge = {
		emitter("Energy", drawAt, {Color = colors(MINT, JADE), Size = curve({0, 5}, {1, 0.8}), Brightness = 2.5, Rate = 9,
			LockedToPart = true, EmissionDirection = Enum.NormalId.Top}),
		emitter("Core", drawAt, {Color = ColorSequence.new(JADE), Size = curve({0, 0.8}, {1, 1.4}), Brightness = 1.5, Rate = 12}),
		emitter("CastStar", drawAt, {Color = colors(WHITE, JADE), Size = curve({0, 3, 0.4}, {1, 1}), Brightness = 2, Rate = 10}),
	}
	local feet = origin.Position - Vector3.new(0, 2.6, 0)
	local feetFlat = Kit.attachment(drawHost, CFrame.lookAt(feet, feet + up))
	local loose = {
		{emitter("CastRing", feetFlat, {Color = colors(MINT, JADE), Size = curve({0, 2}, {0.5, 10}, {1, 14}), Brightness = 2,
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular}), 1},
		{emitter("WindRing", feetFlat, {Color = ColorSequence.new(MINT), Size = curve({0, 2}, {1, 12}), Brightness = 1.5,
			EmissionDirection = Enum.NormalId.Front}), 2},
		{emitter("SlashLines", drawAt, {Color = colors(WHITE, JADE), EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(60, 110),
			SpreadAngle = Vector2.new(6, 6), Brightness = 2}), 10},
		{emitter("CastStar", drawAt, {Color = colors(WHITE, JADE), Size = curve({0, 3.5, 0.5}, {1, 1}), Brightness = 2}), 3},
		{emitter("Glints", drawAt, {Color = ColorSequence.new(MINT), EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(20, 60),
			SpreadAngle = Vector2.new(40, 40), Brightness = 2}), 12},
	}
	local signal = arrowRig(folder, "Signal", 1.4, 9)

	-- The circle ---------------------------------------------------------------
	local circleFrame = CFrame.lookAt(centre + normal * 0.15, centre + normal * 1.15)
	local circleHost = Kit.host(folder, "Circle", circleFrame)
	local flat = Kit.attachment(circleHost, circleFrame)
	local span = T.Radius * 2 + 2
	-- Two crisp rings: the outer one holds still, the inner one turns. Their
	-- hosts stand with Y along the ground normal.
	local side = normal:Cross(Vector3.zAxis)
	side = if side.Magnitude > 0.1 then side.Unit else Vector3.xAxis
	local ringFrame = CFrame.fromMatrix(centre + normal * 0.2, side, normal)
	local outerHost = Kit.host(folder, "OuterRing", ringFrame)
	local innerHost = Kit.host(folder, "InnerRing", ringFrame)
	local outer = ringBeams(outerHost, 1.6, MINT, 0.7)
	local outerGlow = ringBeams(outerHost, 4.5, JADE, 1)
	local inner = ringBeams(innerHost, 0.9, WHITE, 0.6)
	local rune = emitter("Rune", flat, {Color = colors(MINT, JADE), Size = curve({0, span * 0.7}, {1, span * 1.05}), Lifetime = NumberRange.new(0.7),
		FlipbookFramerate = NumberRange.new(22), Speed = NumberRange.new(0.01), EmissionDirection = Enum.NormalId.Front, Brightness = 1.4,
		Transparency = curve({0, 0.2}, {1, 1}), Rate = 2.5, LockedToPart = true, Rotation = NumberRange.new(0, 360)})
	local glow = emitter("StarLight", flat, {Color = ColorSequence.new(JADE), Size = ns(span * 0.7), Lifetime = NumberRange.new(0.9),
		Rate = 2, Brightness = 0.6, Transparency = curve({0, 1}, {0.5, 0.85}, {1, 1})})
	local circleLight = Kit.light(circleHost, JADE, T.Radius * 2)

	-- The rain -----------------------------------------------------------------
	local params = Kit.rayParams({folder})
	local arrows = Plan.volley(payload.seed)
	for _, arrow in ipairs(arrows) do
		local column = centre + arrow.offset
		local hit = workspace:Raycast(column + up * 10, -up * 24, params)
		arrow.ground = if hit then hit.Position else column
	end
	local rigs = {}
	for i = 1, POOL do
		local rig = arrowRig(folder, "Arrow" .. i, 1.3, 12)
		local impact = Kit.attachment(rig.host)
		rig.impact = impact
		rig.burst = {
			{emitter("ImpactStar", impact, {Color = colors(WHITE, JADE), Size = curve({0, 4, 0.6}, {1, 1}), Brightness = 2}), 3},
			{emitter("ImpactSparks", impact, {Color = colors(MINT, JADE), Speed = NumberRange.new(14, 28), Brightness = 2,
				EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(70, 70), LockedToPart = false}), 8},
			{emitter("HitFlash", impact, {Color = ColorSequence.new(JADE), Size = curve({0, 3.5}, {1, 0}), Brightness = 1.5}), 1},
			{emitter("Dust", impact, {Color = ColorSequence.new(Color3.fromRGB(200, 215, 200)), Size = curve({0, 1.5}, {1, 3}),
				Lifetime = NumberRange.new(0.5), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(90, 10),
				EmissionDirection = Enum.NormalId.Top, Transparency = curve({0, 1}, {0.15, 0.5}, {1, 1})}), 2},
		}
		rigs[i] = rig
	end

	-- The finale ---------------------------------------------------------------
	local great = arrowRig(folder, "GreatArrow", 3.2, 30)
	local finaleHost = Kit.host(folder, "Finale", CFrame.new(centre))
	local core = Kit.attachment(finaleHost, CFrame.new(centre + normal * 1.5))
	local ground = Kit.attachment(finaleHost, circleFrame)
	local finale = {
		{emitter("HitFlash", core, {Color = ColorSequence.new(MINT), Size = curve({0, 16}, {1, 0}), Lifetime = NumberRange.new(0.2), Brightness = 1.5}), 1},
		{emitter("HitRing", core, {Color = ColorSequence.new(JADE), Size = curve({0, 3}, {0.55, 18}, {1, 22}), Brightness = 1.6, LightEmission = 1}), 2},
		{emitter("HitEffectRing", core, {Color = colors(WHITE, JADE), Size = curve({0, 4}, {1, 20, 4}), Lifetime = NumberRange.new(0.2)}), 4},
		{emitter("HitLines", core, {Color = colors(WHITE, JADE), Speed = NumberRange.new(60, 120), Size = curve({0, 5, 1}, {1, 0})}), 10},
		{emitter("ImpactStar", core, {Color = ColorSequence.new(WHITE), Size = curve({0, 14, 2}, {1, 4}), Brightness = 2, Lifetime = NumberRange.new(0.15, 0.3)}), 4},
		{emitter("ImpactSparks", core, {Color = colors(MINT, JADE), Speed = NumberRange.new(45, 85), Size = curve({0, 1.6, 0.6}, {1, 0}),
			Brightness = 2, EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(80, 80), LockedToPart = false}), 40},
		{emitter("Cubes", core, {Color = colors(MINT, JADE), Speed = NumberRange.new(35, 60), Size = curve({0, 0}, {0.2, 1.3, 0.5}, {1, 0}),
			Brightness = 1.5, Acceleration = Vector3.new(0, -45, 0), LockedToPart = false}), 30},
		{emitter("GroundShock", ground, {Color = ColorSequence.new(JADE), Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			EmissionDirection = Enum.NormalId.Front, Size = curve({0, 8}, {0.3, 24}, {1, 28})}), 2},
		{emitter("WindRing", ground, {Color = ColorSequence.new(MINT), Size = curve({0, 4}, {1, 24}), Brightness = 1.5,
			EmissionDirection = Enum.NormalId.Front}), 3},
		{emitter("Dust", ground, {Color = ColorSequence.new(Color3.fromRGB(205, 220, 205)), Size = curve({0, 3}, {1, 7}), Speed = NumberRange.new(10, 18),
			SpreadAngle = Vector2.new(90, 10), EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(0.8, 1.1),
			Transparency = curve({0, 1}, {0.1, 0.4}, {1, 1})}), 10},
		{emitter("StarLight", core, {Color = ColorSequence.new(JADE), Size = curve({0, 10}, {1, 22}), Brightness = 1.2, Lifetime = NumberRange.new(0.6)}), 2},
	}
	local finaleLight = Kit.light(finaleHost, JADE, 40)

	local landed = {}
	local nextRig = 1
	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		-- The rings open out, turn while the rain falls, and fade after the finale.
		local open = Kit.smooth((elapsed - T.MarkAt) / 0.25)
		local shown = if elapsed < T.MarkAt then 0 else open * (1 - Kit.ramp(elapsed, T.FinaleAt + 0.15, T.FinaleAt + 0.55))
		local reach = T.Radius * (0.45 + 0.55 * open)
		layoutRing(outer, reach, shown)
		layoutRing(outerGlow, reach, shown * 0.45)
		layoutRing(inner, reach * 0.72, shown * 0.9)
		innerHost.CFrame = ringFrame * CFrame.Angles(0, elapsed * 1.4, 0)
		-- The draw, then the signal arrow climbing out of sight.
		Kit.setEnabled(charge, elapsed < T.Draw)
		local rising = elapsed >= T.Draw and elapsed < T.Draw + T.Rise
		if rising then
			local p = (elapsed - T.Draw) / T.Rise
			placeArrow(signal, handPoint + up * (4 + 70 * p * p), -up, true)
		else
			placeArrow(signal, handPoint, -up, false)
		end
		local marking = elapsed >= T.MarkAt and elapsed < T.FinaleAt + 0.2
		rune.Enabled, glow.Enabled = marking, marking
		circleLight.Brightness = if marking then 0.6 + 0.25 * math.sin(elapsed * 9) else 0
		-- Arrows in flight take a rig each; landing frees it with a burst.
		for index, arrow in ipairs(arrows) do
			if elapsed >= arrow.at and not landed[index] then
				if not arrow.rig then
					arrow.rig = rigs[nextRig]
					nextRig = nextRig % POOL + 1
				end
				local p = math.clamp((elapsed - arrow.at) / T.Fall, 0, 1)
				if p >= 1 then
					landed[index] = true
					placeArrow(arrow.rig, arrow.ground, up, false)
					arrow.rig.impact.WorldPosition = arrow.ground + up * 0.4
					if elapsed - arrow.lands < 0.25 then
						Kit.burst(arrow.rig.burst)
						if index % 3 == 0 then Kit.sound(arrow.rig.host, SOUND_THUNK, 0.22, 0.9 + (index % 5) * 0.08) end
						ImpactFX.shake(arrow.ground, 0.18, 0.12, 40)
					end
				else
					placeArrow(arrow.rig, arrow.ground + up * T.DropHeight * (1 - p) * (1 - p * 0.3), up, true)
				end
			end
		end
		-- The great arrow.
		local fall = (elapsed - T.FinaleAt) / T.FinaleFall
		if fall >= 0 and fall < 1 then
			placeArrow(great, centre + up * (60 * (1 - fall * fall)), up, true)
		else
			placeArrow(great, centre, up, false)
		end
		local age = elapsed - T.FinaleAt - T.FinaleFall
		finaleLight.Brightness = if age >= 0 then math.exp(-age * 4) * 4 else 0
	end, {folder})

	timeline.at(0, function()
		Kit.sound(drawHost, SOUND_DRAW, 0.35, 0.75)
	end)
	timeline.at(T.Draw, function()
		Kit.burst(loose)
		Kit.sound(drawHost, SOUND_DRAW, 0.5, 1.3)
		ImpactFX.shake(origin.Position, 0.4, 0.2, 40)
	end)
	timeline.at(T.FinaleAt + T.FinaleFall, function()
		Kit.burst(finale)
		Kit.sound(finaleHost, SOUND_FINALE, 0.6, 1.05)
		ImpactFX.hit(centre, {tint = JADE, pattern = "triple", shake = 2, shakeDuration = 0.55, punch = 7, radius = 85})
	end)
	return true
end

return VFX
