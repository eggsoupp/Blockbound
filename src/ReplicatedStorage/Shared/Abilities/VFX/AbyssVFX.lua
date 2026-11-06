local CombatAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.CombatAudio)
-- Abyss Gate, built from complete pack assemblies round its ground sigil:
--   call     Impact #48 flares at the caster's hand
--   sigil    two rings, a turning band of runes and a pentagram draw
--            themselves on the ground at the aim, showing the gate's reach,
--            while the Portals rift opens flat over them and drinks in light
--   erupt    Impact #44 and #48 blast out and Alternate #29's beams tear up
--            into a dark column, with impact frames, a shake and a punch
--   implode  the column is sucked back down and Impact #37 and #44 burst on
--            the server's collapse hit
-- The sigil is textured Beams; Parts are invisible emitter hosts only.
local Plan = require(script.Parent.Parent.AbyssPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.AbyssParticles)
local Pack = require(script.Parent.PackAssembly)

local VFX = {}
local T = Plan.Tuning
local VOID = Color3.new(0, 0, 0)
local INK = Color3.fromRGB(30, 16, 52)
local DUSK = Color3.fromRGB(125, 95, 210)
local PALE = Color3.fromRGB(236, 230, 255)
local VIOLET = Color3.fromRGB(150, 70, 255)
local TINT = {deep = INK, main = VIOLET, hot = PALE}
local ns, curve = Kit.ns, Kit.curve
local live = 0
local preloaded = false

local Sheets = {
	-- Slash VFX Trail2: a soft-edged band, laid flat for the sigil's strokes.
	Band = {Texture = "rbxassetid://16892374733"},
}

local SOUND_CALL = "cast.dark"
local SOUND_BOOM = "impact.dark"
local SOUND_HIT = "impact.heavy"

function VFX.preload()
	Pack.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload({Library.PillarCore.Texture, Sheets.Band.Texture}, {SOUND_CALL, SOUND_BOOM, SOUND_HIT})
end

function VFX.duration()
	return Plan.duration()
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
	local function mount(name, cframe, scale, budget)
		return Pack.mount(scope, folder, name, {cframe = cframe, scale = scale, budget = budget, tint = TINT, brightness = 2})
	end
	-- A dead caster's gate does no more damage on the server, so it closes here.
	Pack.endWithCaster(scope, caster)

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
	local tipGlow = mount("Impact37", ringFrame, 0.2, 30)

	-- The rift hangs over the sigil, its flat layers turned to whoever watches.
	local rift = Pack.mount(scope, folder, "PortalRift", {cframe = CFrame.new(centre + normal * R * 0.6), scale = 0.6, budget = 160, brightness = 3,
		billboard = true, tint = {deep = VOID, main = VIOLET, hot = PALE}})
	rift:stream(true)

	-- The column: Alternate #29's beams run along X, stood up the gate.
	local pillarHost = Kit.host(folder, "Pillar", CFrame.new(centre))
	local column = Pack.mount(scope, folder, "Column29", {cframe = CFrame.fromMatrix(centre + up * T.PillarHeight * 0.5, up, side, up:Cross(side)),
		scale = 1.2, faceCamera = true, tint = TINT, brightness = 2})
	local light = Kit.light(pillarHost, PALE, 45)
	local burstFrame = CFrame.new(centre + up * 2)

	local waveHost = Kit.host(folder, "Wave", ringFrame)
	local eruptWave = circle(waveHost, 2.6, VOID, 0, 0.1)
	local eruptGlow = circle(waveHost, 6, DUSK, 1)
	local implodeWave = circle(waveHost, 1.8, PALE, 1, 0.2)
	local implodeShadow = circle(waveHost, 4, VOID, 0, 0.1)

	local spin = 0
	local last
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
		local tipAt = Vector3.zero
		local scale = reach / R
		for i = 1, 5 do
			local p = Kit.ramp(elapsed, 0.25 + (i - 1) * 0.1, 0.25 + i * 0.1)
			local from = vertex(2 * (i - 1)) * scale
			local reached = from:Lerp(vertex(2 * i) * scale, p)
			layoutLine(star[i], from, reached, if p > 0 then shown else 0)
			layoutLine(starGlow[i], from, reached, if p > 0 then glow else 0)
			if p > 0 and p < 1 then
				drawing = true
				tipAt = reached + Vector3.new(0, 0.3, 0)
			end
		end
		tipGlow:stream(drawing)
		if drawing then tipGlow:place(innerHost.CFrame * CFrame.new(tipAt)) end
		-- The rift swells as the sigil opens, and goes when the gate implodes.
		rift:rescale(math.round((0.6 + 1.9 * Kit.smooth(elapsed / openAt)) * 8) / 8)
		-- The column shoots up and is sucked back down.
		local rise = Kit.smooth((elapsed - openAt) / 0.12)
		local sink = Kit.ramp(elapsed, collapseAt - 0.14, collapseAt)
		local height = T.PillarHeight * rise * (1 - 0.8 * sink * sink)
		column:beamsOn(erupting and height > 0.5)
		if erupting then
			column:stretch(centre, centre + up * math.max(height, 0.5))
		end
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
		mount("Impact48", CFrame.new(handPoint), 0.5):burst(0.7)
		Kit.sound(callHost, SOUND_CALL, 0.45, 0.55)
		ImpactFX.shake(origin.Position, 0.3, 0.2, 40)
	end)
	timeline.at(openAt, function()
		mount("Impact44", burstFrame, 2.2):burst(1)
		mount("Impact48", burstFrame, 2.4):burst(1)
		column:stream(true)
		Kit.sound(pillarHost, SOUND_BOOM, 0.65, 0.7)
		ImpactFX.hit(centre + up * 3, {tint = PALE, pattern = "double", shake = 1.8, shakeDuration = 0.5, punch = 6, radius = 90})
		ImpactFX.shake(centre, 0.5, T.Erupt, 80)
	end)
	timeline.at(collapseAt, function()
		rift:clear()
		column:clear()
		mount("Impact37", burstFrame, 3):burst(1)
		mount("Impact44", burstFrame, 2.8):burst(1)
		Kit.sound(pillarHost, SOUND_BOOM, 0.7, 1.1)
		Kit.sound(pillarHost, SOUND_HIT, 0.5, 0.7)
		ImpactFX.hit(centre + up * 3, {tint = PALE, pattern = "triple", shake = 2.6, shakeDuration = 0.7, punch = 10, radius = 100})
	end)
	return true
end

return VFX
