--[[
	Eclipse Prison (Celestial), drawn on EclipsePlan's clock:
	  call     the caster lights up in a pack aura (EclipseParticles: SoulShroud
	           aura #6), a splash at their feet; the world dims for whoever
	           stands near
	  mark     the ground breaks at the aim (splash, ring, rocks, smoke) and a
	           turning sigil draws itself round the cage's footprint
	  build    the cage rises LAYER BY LAYER out of the ground - each ring of
	           blocks slides up from below into place, glowing magenta and
	           cooling to black, sparks bursting round it as it lands - then the
	           lid slams shut. Its edges are particles and beams: a beam up every
	           corner and seam with sparks and streaks pouring off it, glowing
	           rims round its foot and top; smoke rolls out of the ground and
	           sparks rise round it
	  hold     a glowing magenta haze licks round its foot, lightning crackles over its
	           faces and lid, rings pulse out along the ground
	  barrage  thin black blades of light (beams) gather in the air out of smoke
	           and a glint and stab in one after another, each with a slash, a
	           star and sparks
	  charge   the cage glows from within, its edges swell and crackle, the world
	           darkens further, and crackling bursts (Lightning Surge) hit the
	           ground round it, faster and faster
	  flare    the cage burns solid magenta (two dark slits a face) and blows
	           apart: a full explosion (Impact #1, #44, #9, Explosion), bursts
	           at every top corner, shockwave rings racing out along the ground,
	           debris, the pack explosion's own shock shells swelling far past
	           the tower, more lightning, impact frames, a heavy shake and punch
	           - the server's big hit; its blocks fly outwards as streaks
	Every stage has a CombatRecipes eclipse.* sound stack.
	  after    an aftershock of streaks, droplets, lightning and sparks, a second
	           ring, and dark smoke hanging where it stood
	Only the cage blocks are cosmetic voxel parts (client-only, no collision, no
	queries); the swords are beams, and every glow, edge, spark and smoke is a
	SoulShroud emitter or beam (PackAssembly assemblies, EclipseParticles).
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Plan = require(script.Parent.Parent.EclipsePlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Pack = require(script.Parent.PackAssembly)
local Library = require(script.Parent.EclipseParticles)
local Audio = require(script.Parent.Parent.Parent.Audio.CombatAudio)

local VFX = {}
local T = Plan.Tuning

-- The reference's neon magenta, a white-pink hot end and a deep violet.
local MAGENTA = Color3.fromRGB(255, 40, 236)
-- Neon parts glow brighter than their colour, so the blocks use a deeper
-- magenta that lands on the reference once it blooms.
local NEON = Color3.fromRGB(196, 14, 206)
local HOT = Color3.fromRGB(255, 205, 250)
local PINK = Color3.fromRGB(255, 150, 248)
local DEEP = Color3.fromRGB(64, 6, 104)
local VOID = Color3.fromRGB(7, 4, 13)
local TINT = {deep = DEEP, main = MAGENTA, hot = HOT}
local SMOKE = {deep = VOID, main = Color3.fromRGB(120, 24, 170), hot = MAGENTA}
-- The aura's and edges' authored colours are mostly near-white, which the tint
-- rule maps to the hot end; a pink hot end keeps them magenta.
local SPARK_TINT = {deep = DEEP, main = MAGENTA, hot = Color3.fromRGB(255, 120, 245)}
-- Light, so a full-screen tint does not turn the magenta violet; most of the
-- dimming is brightness and contrast.
local DUSK = Color3.fromRGB(190, 186, 255)
-- Pack streak (Abyss's pillar core): edge beams, sword glow, sigil and rings.
local STREAK = "http://www.roblox.com/asset/?id=3517446796"

-- The aura was authored on an R6 body; these are the R15 parts that stand in.
local R15 = {
	Torso = {"UpperTorso", "Torso"},
	["Left Arm"] = {"LeftLowerArm", "Left Arm"},
	["Right Arm"] = {"RightLowerArm", "Right Arm"},
	["Left Leg"] = {"LeftLowerLeg", "Left Leg"},
	["Right Leg"] = {"RightLowerLeg", "Right Leg"},
}
local CORNERS = {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
local FACES = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

local live = 0

function VFX.preload()
	Pack.preload()
end

function VFX.duration()
	return Plan.duration()
end

local function ease(t)
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

-- Overshoots a little and settles: a layer landing in its place.
local function settle(t)
	t = math.clamp(t, 0, 1)
	local c = 1.5
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

local function block(parent, size, color)
	local p = Instance.new("Part")
	p.Size, p.Color, p.Material = size, color, Enum.Material.Neon
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Transparency = 1
	p.Parent = parent
	return p
end

-- A curated pack emitter, recoloured to the cast, at its authored rate unless
-- `props` give another (Kit.emitter leaves every rate at 0).
local function emitter(kind, parent, props)
	local e = Kit.emitter(Library, kind, parent, props)
	e.Color = Pack.tint(e.Color, SPARK_TINT)
	e.Rate = (props and props.Rate) or Library[kind].Rate or 0
	return e
end

local function beam(host, a0, a1, props)
	props.TextureMode = Enum.TextureMode.Stretch
	props.TextureLength = 1
	props.Transparency = Kit.ns(1)
	props.Enabled = false
	return Kit.beam(host, a0, a1, props)
end

-- A straight glowing line between two points: a wide soft magenta beam and
-- a thin hot core over it.
local function edgeBeam(host, width)
	local a0, a1 = Kit.attachment(host), Kit.attachment(host)
	local glow = beam(host, a0, a1, {Texture = STREAK, FaceCamera = true, Segments = 1, Width0 = width, Width1 = width,
		Color = ColorSequence.new(MAGENTA), LightEmission = 1, Brightness = 3})
	local core = beam(host, a0, a1, {Texture = STREAK, FaceCamera = true, Segments = 1, Width0 = width * 0.32,
		Width1 = width * 0.32, Color = ColorSequence.new(PINK), LightEmission = 1, Brightness = 4, ZOffset = 0.5})
	return {a0 = a0, a1 = a1, glow = glow, core = core, width = width}
end

local function layoutEdge(edge, from, to, alpha, swell)
	edge.a0.WorldPosition, edge.a1.WorldPosition = from, to
	local w = edge.width * (swell or 1)
	if edge.glow.Width0 ~= w then
		edge.glow.Width0, edge.glow.Width1 = w, w
		edge.core.Width0, edge.core.Width1 = w * 0.32, w * 0.32
	end
	Kit.opacity(edge.glow, alpha * 0.85)
	Kit.opacity(edge.core, alpha)
end

-- Flat strokes on the ground, drawn in beams (flat particles do not show on
-- this ground; see AbyssVFX). The host stands with Y up.
local function stroke(host, width, color, emission, z)
	local a0, a1 = Kit.attachment(host), Kit.attachment(host)
	local b = beam(host, a0, a1, {Texture = if emission > 0 then STREAK else "", FaceCamera = false, Segments = 12,
		Width0 = width, Width1 = width, Color = ColorSequence.new(color), LightEmission = emission,
		Brightness = if emission > 0 then 3 else 1, ZOffset = z or 0})
	return {beam = b, a0 = a0, a1 = a1, width = width}
end

local function radial(theta)
	return Vector3.new(math.cos(theta), 0, math.sin(theta))
end

local function tangent(theta)
	return Vector3.new(-math.sin(theta), 0, math.cos(theta))
end

-- A cubic arc is circular when its control points sit (4/3)tan(sweep/4) of
-- the radius along each end's tangent.
local function layoutArc(s, radius, t0, t1, opacity, widthScale)
	s.a0.CFrame = CFrame.fromMatrix(radial(t0) * radius, tangent(t0), radial(t0))
	s.a1.CFrame = CFrame.fromMatrix(radial(t1) * radius, tangent(t1), radial(t1))
	local k = 4 / 3 * math.tan((t1 - t0) / 4) * radius
	s.beam.CurveSize0, s.beam.CurveSize1 = k, k
	local width = s.width * (widthScale or 1)
	if s.beam.Width0 ~= width then s.beam.Width0, s.beam.Width1 = width, width end
	Kit.opacity(s.beam, opacity)
end

local function circle(host, width, color, emission, z)
	local arcs = {}
	for q = 1, 4 do arcs[q] = stroke(host, width, color, emission, z) end
	return arcs
end

local function layoutCircle(arcs, radius, opacity, widthScale)
	for q, s in ipairs(arcs) do
		layoutArc(s, radius, (q - 1) * math.pi / 2, q * math.pi / 2, opacity, widthScale)
	end
end

--[[
	A sword of beams, pointing down its host's -Z: a black blade tapering to a
	needle point over a soft magenta glow, a thin black grip and a crossguard.
	Beams face the camera, so it reads as a thin dark blade from any side.
]]
local SWORD_LENGTH = 34
local BLADE = SWORD_LENGTH * 0.78

local function makeSword(parent)
	local host = Kit.host(parent, "Sword", CFrame.new())
	local function at(x, z)
		local a = Kit.attachment(host)
		a.Position = Vector3.new(x, 0, z)
		return a
	end
	local guard, tip, pommel = at(0, 0), at(0, -BLADE), at(0, SWORD_LENGTH - BLADE)
	local glowTip, glowBack = at(0, -BLADE - 1.5), at(0, 0.8)
	local left, right = at(-2.2, 0), at(2.2, 0)
	local parts = {
		{beam = beam(host, glowBack, glowTip, {Texture = STREAK, FaceCamera = true, Segments = 1, Width0 = 2.6, Width1 = 0.3,
			Color = ColorSequence.new(MAGENTA), LightEmission = 1, Brightness = 3, ZOffset = -0.5}), alpha = 0.55},
		{beam = beam(host, guard, tip, {Texture = "", FaceCamera = true, Segments = 1, Width0 = 1.05, Width1 = 0.05,
			Color = ColorSequence.new(VOID), LightEmission = 0}), alpha = 1},
		{beam = beam(host, guard, pommel, {Texture = "", FaceCamera = true, Segments = 1, Width0 = 0.45, Width1 = 0.6,
			Color = ColorSequence.new(VOID), LightEmission = 0}), alpha = 1},
		{beam = beam(host, left, right, {Texture = "", FaceCamera = true, Segments = 1, Width0 = 0.55, Width1 = 0.55,
			Color = ColorSequence.new(VOID), LightEmission = 0}), alpha = 1},
	}
	-- A streak behind it while it flies, across the blade.
	local trail = Kit.trail(host, at(-0.6, -BLADE * 0.5), at(0.6, -BLADE * 0.5), {Texture = STREAK,
		Color = ColorSequence.new(MAGENTA), LightEmission = 1, Lifetime = 0.16, MinLength = 0.05, FaceCamera = true,
		WidthScale = NumberSequence.new(1, 0.2), Transparency = NumberSequence.new(0.1, 1), Enabled = false})
	return {host = host, parts = parts, trail = trail}
end

local function placeSword(sword, frame, alpha)
	sword.host.CFrame = frame
	if sword.alpha ~= alpha then
		sword.alpha = alpha
		for _, piece in ipairs(sword.parts) do Kit.opacity(piece.beam, alpha * piece.alpha) end
	end
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.centre) ~= "Vector3"
		or type(payload.startedAt) ~= "number" or type(payload.seed) ~= "number" then
		return false
	end
	local total = Plan.duration()
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 3 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local origin, centre = payload.origin, payload.centre
	local frame = Plan.frame(centre, origin.Position)
	local up = Vector3.yAxis
	local random = Random.new(payload.seed)
	local cell, size, height = T.Cell, Plan.size(), Plan.height()
	local half = size * 0.5
	local buildAt, closedAt, flareAt = Plan.buildAt(), Plan.closedAt(), Plan.flareAt()
	local chargeAt = flareAt - T.Settle + 0.05
	local markAt = buildAt - 0.1

	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "EclipsePrison"
	folder.Parent = workspace

	local caster = payload.caster
	Pack.endWithCaster(scope, caster)
	local character = caster and caster.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local feet = Plan.ground(origin.Position, Kit.rayParams({character}))

	local function mount(name, cframe, scale, options)
		options = options or {}
		return Pack.mount(scope, folder, name, {cframe = cframe, scale = scale, budget = options.budget,
			tint = options.tint or TINT, brightness = options.brightness or 3, billboard = options.billboard,
			faceCamera = options.faceCamera, visible = options.visible, meshTint = options.meshTint, hide = options.hide})
	end
	-- CombatRecipes' eclipse.* stacks, from where the thing happened.
	local function sound(key, position, volume, pitch)
		Audio.play(key, position, volume or 0.6, pitch or 1)
	end
	-- A crackling burst on the ground round the tower. (No ray out of the sky:
	-- the user found the beam strikes did not belong.)
	local function strike(point, power)
		mount("LightningSurge", CFrame.new(point + up * 3), 2.6 * power, {budget = 30}):burst(1)
		mount("Impact37", CFrame.new(point + up * 0.4), 2.6 * power):burst(0.8)
		mount("Impact45", CFrame.new(point + up), 1.8 * power):burst(0.7)
		ImpactFX.shake(point, 0.6 * power, 0.15, 140)
		sound("eclipse.bolt", point, 0.55 * power)
	end
	-- A few clones of one assembly, burst round-robin: for effects that fire
	-- many times (every sword, every landing row) without a clone each time.
	local function pool(name, count, scale, options)
		local handles, index = {}, 0
		for i = 1, count do handles[i] = mount(name, frame, scale, options) end
		return function(cframe, strength)
			index = index % count + 1
			handles[index]:place(cframe)
			handles[index]:burst(strength)
		end
	end

	-- The dimming --------------------------------------------------------------
	local grade = scope:add(Instance.new("ColorCorrectionEffect"))
	grade.Name = "EclipsePrisonDim"
	grade.Parent = Lighting
	local function nearness()
		local own = Players.LocalPlayer and Players.LocalPlayer.Character
		local ownRoot = own and own:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		local from = if ownRoot then ownRoot.Position elseif camera then camera.CFrame.Position else centre
		return math.clamp(1.7 - (from - centre).Magnitude / 140, 0, 1)
	end

	-- The aura -----------------------------------------------------------------
	local aura, auraHosts = {}, {}
	if character then
		for _, entry in ipairs(Library.Aura) do
			local kind, r6, offset, hostSize = entry[1], entry[2], entry[3], entry[4]
			local limb
			for _, name in ipairs(R15[r6] or {r6}) do
				limb = limb or character:FindFirstChild(name)
			end
			if limb and limb:IsA("BasePart") then
				local parent = limb
				if hostSize then
					local host = Kit.host(folder, "AuraHost", limb.CFrame * CFrame.new(offset), hostSize)
					table.insert(auraHosts, {host = host, limb = limb, offset = CFrame.new(offset)})
					parent = host
				elseif offset then
					parent = scope:add(Kit.attachment(limb))
					parent.Position = offset
				end
				-- Denser than the idle aura it was authored as: this is a cast.
				local layer = scope:add(emitter(kind, parent))
				layer.Rate *= 1.5
				table.insert(aura, layer)
			end
		end
	end

	-- The ground sigil -----------------------------------------------------------
	local sigilFrame = CFrame.new(centre + up * 0.25)
	local sigilHost = Kit.host(folder, "Sigil", sigilFrame)
	local runeHost = Kit.host(folder, "Runes", sigilFrame)
	local outerR, innerR = half * 1.45, half * 1.18
	local outerInk, outerGlow = circle(sigilHost, 1.4, VOID, 0, 0.1), circle(sigilHost, 4.5, MAGENTA, 1)
	local innerInk, innerGlow = circle(sigilHost, 0.9, VOID, 0, 0.1), circle(sigilHost, 3.2, MAGENTA, 1)
	-- A third, widest ring and eight spokes joining the inner two.
	local rimR = half * 1.85
	local rimInk, rimGlow = circle(runeHost, 1, VOID, 0, 0.1), circle(runeHost, 3.4, MAGENTA, 1)
	local spokes, spokeGlows = {}, {}
	for i = 1, 8 do
		spokes[i] = stroke(sigilHost, 0.9, VOID, 0, 0.1)
		spokeGlows[i] = stroke(sigilHost, 3, MAGENTA, 1)
	end
	local function layoutLine(s, from, to, opacity)
		local along = to - from
		local across = Vector3.yAxis:Cross(along).Unit
		s.a0.CFrame = CFrame.fromMatrix(from, along.Unit, across)
		s.a1.CFrame = CFrame.fromMatrix(to, along.Unit, across)
		s.beam.CurveSize0, s.beam.CurveSize1 = 0, 0
		Kit.opacity(s.beam, opacity)
	end
	local runes, runeGlows = {}, {}
	for i = 1, 24 do
		runes[i] = stroke(runeHost, 1.6, VOID, 0, 0.1)
		runeGlows[i] = stroke(runeHost, 3.6, MAGENTA, 1)
	end
	-- Shockwaves out of the flare, along the ground.
	local waveHost = Kit.host(folder, "Waves", sigilFrame)
	local waves = {}
	for i = 1, 2 do
		waves[i] = {glow = circle(waveHost, 9, MAGENTA, 1, 0.2), core = circle(waveHost, 3, PINK, 1, 0.3),
			at = flareAt + (i - 1) * 0.16, span = 0.7 + (i - 1) * 0.25, reach = half * (5.2 - (i - 1) * 1.4)}
	end

	-- The cage -----------------------------------------------------------------
	-- Rows 0 (buried, so a slope never shows a gap) to Layers-1 are rings of
	-- wall; the top row is the lid. Each row rises as one from a cell and a
	-- half below its place, one after another, and the lid drops onto it.
	local rows = {}
	local rowStep = (T.Build - 0.34) / T.Layers
	for layer = 0, T.Layers do
		local lid = layer == T.Layers
		local row = {
			lid = lid, layer = layer,
			startAt = if lid then buildAt + T.Layers * rowStep + 0.02 else buildAt + layer * rowStep,
			blocks = {},
		}
		row.landAt = row.startAt + (if lid then 0.24 else 0.2)
		row.coolAt = row.landAt + 0.2
		row.from = if lid then up * cell * 2.4 else -up * cell * 1.6
		for i = 1, T.Cells do
			for k = 1, T.Cells do
				local wall = i == 1 or i == T.Cells or k == 1 or k == T.Cells
				if wall or lid then
					local x = (i - (T.Cells + 1) / 2) * cell
					local z = (k - (T.Cells + 1) / 2) * cell
					local y = (layer - 0.5) * cell
					local out = if wall and random:NextNumber() < 0.3 then random:NextNumber(0.1, 0.8) else 0
					local outward = Vector3.new(if i == 1 then -out elseif i == T.Cells then out else 0, 0,
						if k == 1 then -out elseif k == T.Cells then out else 0)
					local along = if i == 1 or i == T.Cells then k else i
					local home = frame * CFrame.new(Vector3.new(x, y, z) + outward)
					local flat = Vector3.new(home.Position.X - centre.X, 0, home.Position.Z - centre.Z)
					flat = if flat.Magnitude > 0.1 then flat.Unit else frame.LookVector
					table.insert(row.blocks, {
						part = block(folder, Vector3.one * cell * random:NextNumber(1, 1.05), NEON), home = home,
						tone = NEON:Lerp(DEEP, random:NextNumber(0, 0.5)),
						-- Two dark slits down each face stay black through the flare.
						window = wall and not lid and (along == 2 or along == T.Cells - 1) and layer >= 2 and layer <= T.Layers - 2,
						lag = random:NextNumber(0, 0.035),
						-- Where it flies when the cage blows: out, and up or down.
						blast = flat * random:NextNumber(10, 30) + up * (if lid then random:NextNumber(10, 26) else random:NextNumber(-4, 14)),
						spin = CFrame.Angles(random:NextNumber(-3, 3), random:NextNumber(-3, 3), random:NextNumber(-3, 3)),
						-- It burns whole for a beat before it blows.
						shatterAt = flareAt + 0.16 + random:NextNumber(0, 0.12),
					})
				end
			end
		end
		table.insert(rows, row)
	end
	local lidAt = rows[#rows].landAt

	-- The edges: particles and beams ---------------------------------------------
	local edgeHalf = half + 0.15
	local edges = {}
	local function addEdge(x, z, corner)
		local host = Kit.host(folder, "Edge", frame * CFrame.new(x, 0, z), Vector3.new(0.8, 0.2, 0.8))
		local edge = edgeBeam(host, if corner then 3.4 else 2.2)
		edge.x, edge.z, edge.host, edge.corner = x, z, host, corner
		edge.sparks = scope:add(emitter("Sparks", host, {LockedToPart = false, Rate = if corner then 110 else 45, Brightness = 2,
			Speed = NumberRange.new(5, 9), Lifetime = NumberRange.new(0.5, 0.9)}))
		edge.streaks = scope:add(emitter("Streaks", host, {LockedToPart = false, Rate = if corner then 40 else 16,
			EmissionDirection = Enum.NormalId.Top, Size = NumberSequence.new(2.2), Brightness = 2}))
		edge.wisps = scope:add(emitter("Wisps", host, {LockedToPart = false, Rate = if corner then 30 else 12,
			Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 1.8), NumberSequenceKeypoint.new(1, 0)})}))
		table.insert(edges, edge)
	end
	for _, c in ipairs(CORNERS) do
		addEdge(c[1] * edgeHalf, c[2] * edgeHalf, true)
	end
	for face = 1, 4 do
		for _, along in ipairs({-half * 0.42, half * 0.42}) do
			local x, z = along, along
			if face == 1 then z = -edgeHalf elseif face == 2 then z = edgeHalf elseif face == 3 then x = -edgeHalf else x = edgeHalf end
			addEdge(x, z, false)
		end
	end
	local rimHost = Kit.host(folder, "Rim", frame)
	local foot, top = {}, {}
	for i = 1, 4 do
		foot[i], top[i] = edgeBeam(rimHost, 3.4), edgeBeam(rimHost, 3)
	end
	local cornersAt = {}
	for i, c in ipairs(CORNERS) do
		cornersAt[i] = Vector3.new(c[1] * edgeHalf, 0, c[2] * edgeHalf)
	end
	-- Corners and face middles round the foot.
	local around = {}
	for i = 1, 4 do
		table.insert(around, cornersAt[i])
		table.insert(around, Vector3.new(FACES[i][1] * edgeHalf, 0, FACES[i][2] * edgeHalf))
	end

	-- Streams round the cage.
	local sparks, smokes, flames, crackles = {}, {}, {}, {}
	for i, spot in ipairs(around) do
		local foot0 = frame * CFrame.new(spot + up * 0.5)
		sparks[i] = mount("Impact48", foot0, 1.1, {budget = 22})
		smokes[i] = mount("SmokeDense", foot0, 1.5, {budget = 10, tint = SMOKE})
		-- A glowing magenta haze licking round its foot.
		flames[i] = mount("SmokeDense", foot0 + up * 1.5, 1.2, {budget = 16})
	end
	for i, c in ipairs(FACES) do
		crackles[i] = mount("LightningSurge", frame * CFrame.new(c[1] * (half + 0.6), height * 0.5, c[2] * (half + 0.6)), 2, {budget = 18})
		crackles[i + 4] = mount("LightningSurge", frame * CFrame.new(c[1] * half * 0.5, height + 1, c[2] * half * 0.5), 1.8, {budget = 14})
	end
	local rowBurst = pool("Impact41", 8, 1.6)
	local rowDust = pool("Impact37", 8, 1.8)
	local bite = pool("SlashImpact1", 10, 1.4)
	local biteStar = pool("Impact12", 10, 0.9)
	local biteSparks = pool("Impact41", 10, 1.1)
	local glint = pool("Impact10", 8, 0.5)
	local puff = pool("SmokePuff", 8, 0.6, {tint = SMOKE})

	-- The swords ---------------------------------------------------------------
	local swords = {}
	for i = 1, T.Swords do
		local face = random:NextInteger(1, 5)
		local u, v = random:NextNumber(-0.8, 0.8), random:NextNumber(0.2, 0.92)
		local localHit, normal
		if face == 5 then
			localHit, normal = Vector3.new(u * half, height, (v * 2 - 1) * half), Vector3.yAxis
		else
			local sideways = ({Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0)})[face]
			local across = Vector3.yAxis:Cross(sideways)
			localHit = sideways * half + across * u * half + Vector3.yAxis * v * height
			normal = sideways
		end
		-- In from outside, mostly from above, never square on.
		local dir = (normal + Vector3.yAxis * random:NextNumber(0.35, 1.1)
			+ Vector3.new(random:NextNumber(-0.5, 0.5), 0, random:NextNumber(-0.5, 0.5))).Unit
		local hit = frame * localHit
		local worldDir = frame:VectorToWorldSpace(dir)
		local bury = BLADE * random:NextNumber(0.25, 0.4)
		-- The host's frame is the guard; the point is BLADE down its -Z.
		local stuck = CFrame.lookAt(hit + worldDir * (BLADE - bury), hit - worldDir * bury)
		local sword = makeSword(folder)
		sword.stuck, sword.start, sword.hit, sword.dir = stuck, stuck + worldDir * T.SwordDistance, hit, worldDir
		sword.launchAt, sword.landAt = Plan.launchAt(i), Plan.swordAt(i)
		sword.appearAt = sword.launchAt - 0.4
		sword.fadeAt = flareAt + random:NextNumber(0, 0.1)
		sword.fling = worldDir * random:NextNumber(14, 26) + up * random:NextNumber(4, 12)
		table.insert(swords, sword)
	end

	local light = Kit.light(Kit.host(folder, "Light", CFrame.new(centre + up * height * 0.5)), MAGENTA, 60)

	-- The timeline -------------------------------------------------------------
	local moving, moveTo = {}, {}
	local spin, last = 0, nil
	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local dt = if last then math.max(elapsed - last, 0) else 0
		last = elapsed
		local charge = Kit.ramp(elapsed, chargeAt, flareAt)
		local dim = Kit.smooth(elapsed / 0.6) * (1 - Kit.ramp(elapsed, flareAt + 0.3, total - 0.1)) * nearness()
		-- Darker while it charges; a hot pink pop on the flare itself.
		-- Short and soft: ImpactFX's frames already flash, and in daylight a
		-- long bright pop on top of them whites out the screen.
		local pop = if elapsed >= flareAt then math.exp(-(elapsed - flareAt) * 16) else 0
		grade.TintColor = Color3.new(1, 1, 1):Lerp(DUSK, dim):Lerp(Color3.fromRGB(255, 190, 250), pop * 0.4)
		grade.Brightness = -0.14 * dim - 0.14 * charge * dim + 0.06 * pop
		grade.Contrast = 0.2 * dim + 0.15 * charge
		grade.Saturation = 0.25 * dim + 0.3 * pop

		for _, h in ipairs(auraHosts) do
			if h.limb.Parent then h.host.CFrame = h.limb.CFrame * h.offset end
		end

		-- Sigil: draws itself out from the middle, turns, and goes in the flare.
		local open = ease((elapsed - markAt) / 0.4)
		local sigilShown = if elapsed >= markAt then open * (1 - Kit.ramp(elapsed, flareAt, flareAt + 0.25)) else 0
		local glowAlpha = sigilShown * (0.65 + 0.35 * charge + 0.1 * math.sin(elapsed * 9))
		spin += dt * (0.5 + 2.5 * charge)
		runeHost.CFrame = sigilFrame * CFrame.Angles(0, spin, 0)
		sigilHost.CFrame = sigilFrame * CFrame.Angles(0, -spin * 0.4, 0)
		layoutCircle(outerInk, outerR * open, sigilShown)
		layoutCircle(outerGlow, outerR * open, glowAlpha)
		layoutCircle(innerInk, innerR * open, sigilShown)
		layoutCircle(innerGlow, innerR * open, glowAlpha * 0.8)
		layoutCircle(rimInk, rimR * open, sigilShown)
		layoutCircle(rimGlow, rimR * open, glowAlpha * 0.7)
		for i = 1, 8 do
			local theta = (i - 1) * math.pi / 4 + math.pi / 8
			local drawn = Kit.ramp(elapsed, markAt + 0.15, markAt + 0.4)
			local from = radial(theta) * innerR * open
			local to = from:Lerp(radial(theta) * rimR * open, math.max(drawn, 0.02))
			layoutLine(spokes[i], from, to, if drawn > 0 then sigilShown else 0)
			layoutLine(spokeGlows[i], from, to, if drawn > 0 then glowAlpha * 0.8 else 0)
		end
		local runeR = (outerR + innerR) * 0.5 * open
		for i = 1, #runes do
			local t0 = (i - 1) * math.pi * 2 / #runes
			local drawn = Kit.ramp(elapsed, markAt + 0.1 + i * 0.012, markAt + 0.2 + i * 0.012)
			layoutArc(runes[i], runeR, t0, t0 + math.rad(7) * math.max(drawn, 0.01), if drawn > 0 then sigilShown else 0)
			layoutArc(runeGlows[i], runeR, t0, t0 + math.rad(7) * math.max(drawn, 0.01), if drawn > 0 then glowAlpha else 0)
		end
		for _, wave in ipairs(waves) do
			local t = (elapsed - wave.at) / wave.span
			if t >= 0 and t <= 1 then
				local r = half + (wave.reach - half) * ease(t)
				layoutCircle(wave.glow, r, (1 - t) * 0.9, 1 - 0.5 * t)
				layoutCircle(wave.core, r, 1 - t, 1 - 0.6 * t)
			else
				layoutCircle(wave.glow, half, 0)
				layoutCircle(wave.core, half, 0)
			end
		end

		-- Rows rise, settle and cool; glow from within as it charges; burn in
		-- the flare; then blow outwards as stretched streaks.
		table.clear(moving)
		table.clear(moveTo)
		local builtTop = 0
		local inner = NEON:Lerp(DEEP, 0.45)
		for _, row in ipairs(rows) do
			for _, b in ipairs(row.blocks) do
				local p = b.part
				local startAt = row.startAt + b.lag
				if elapsed < startAt then
					if p.Transparency ~= 1 then p.Transparency = 1 end
				elseif elapsed < b.shatterAt then
					local t = (elapsed - startAt) / (row.landAt - row.startAt)
					if t < 1 then
						table.insert(moving, p)
						table.insert(moveTo, b.home + row.from * (1 - settle(t)))
					elseif not b.placed then
						b.placed = true
						table.insert(moving, p)
						table.insert(moveTo, b.home)
					end
					p.Transparency = if t < 1 then math.max(0, 0.7 - t * 1.4) else 0
					local color
					if elapsed < flareAt then
						color = b.tone:Lerp(VOID, Kit.ramp(elapsed, row.coolAt, row.coolAt + 0.3))
						if charge > 0 and not b.window then color = color:Lerp(inner, charge * charge) end
					else
						color = if b.window then VOID else NEON:Lerp(HOT, 1 - Kit.ramp(elapsed, flareAt, flareAt + 0.06))
					end
					if p.Color ~= color then p.Color = color end
				else
					local t = math.clamp((elapsed - b.shatterAt) / 0.7, 0, 1)
					local e = ease(t)
					local stretch = 1 + 3.5 * e
					local thin = 1 - 0.75 * e
					p.Size = Vector3.new(cell * thin, cell * stretch, cell * thin)
					table.insert(moving, p)
					table.insert(moveTo, CFrame.new(b.home.Position + b.blast * e) * b.home.Rotation:Lerp(b.home.Rotation * b.spin, e * 0.3))
					p.Transparency = t ^ 0.7
					local streakColor = if b.window then VOID else NEON
					if p.Color ~= streakColor then p.Color = streakColor end
				end
			end
			if not row.lid and elapsed >= row.startAt then
				local landed = math.clamp((elapsed - row.startAt) / (row.landAt - row.startAt), 0, 1)
				builtTop = math.max(builtTop, row.layer * cell * landed)
			end
		end
		if #moving > 0 then
			workspace:BulkMoveTo(moving, moveTo, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- Edges climb with the rows, swell as it charges, and go in the flare.
		local edgeTop = if elapsed >= lidAt then height else builtTop
		local gone = Kit.ramp(elapsed, flareAt, flareAt + 0.2)
		local shown = if elapsed >= buildAt then 1 - gone else 0
		local flicker = 0.8 + 0.2 * math.sin(elapsed * 41)
		local swell = 1 + 1.4 * charge * (0.8 + 0.2 * math.sin(elapsed * 60))
		local streaming = shown > 0 and elapsed < flareAt
		for _, edge in ipairs(edges) do
			local tall = math.max(edgeTop, 0.2)
			edge.host.Size = Vector3.new(0.8, tall, 0.8)
			edge.host.CFrame = frame * CFrame.new(edge.x, tall * 0.5, edge.z)
			layoutEdge(edge, frame * Vector3.new(edge.x, -0.2, edge.z), frame * Vector3.new(edge.x, tall + 0.4, edge.z),
				shown * flicker * (if edge.corner then 1 else 0.75), swell)
			if edge.sparks.Enabled ~= streaming then
				edge.sparks.Enabled, edge.streaks.Enabled, edge.wisps.Enabled = streaming, streaming, streaming
			end
		end
		for i = 1, 4 do
			local a, b = frame * cornersAt[i], frame * cornersAt[i % 4 + 1]
			layoutEdge(foot[i], a + up * 0.15, b + up * 0.15, shown * flicker, swell)
			layoutEdge(top[i], a + up * (height + 0.15), b + up * (height + 0.15),
				if elapsed >= lidAt then shown * flicker else 0, swell)
		end

		local building = elapsed >= buildAt and elapsed < flareAt
		local held = elapsed >= lidAt and elapsed < flareAt
		for i = 1, #around do
			sparks[i]:stream(building)
			smokes[i]:stream(building)
			flames[i]:stream(held)
		end
		for i = 1, #crackles do
			crackles[i]:stream(held)
		end

		-- Swords: gather, draw back, stab, sit; in the flare they are flung out.
		for _, sword in ipairs(swords) do
			if elapsed < sword.appearAt then
				placeSword(sword, sword.start, 0)
			elseif elapsed < sword.launchAt then
				local t = (elapsed - sword.appearAt) / (sword.launchAt - sword.appearAt)
				placeSword(sword, sword.start + sword.dir * 3 * Kit.smooth(t), ease(t * 1.6))
			elseif elapsed < sword.landAt then
				local t = (elapsed - sword.launchAt) / (sword.landAt - sword.launchAt)
				placeSword(sword, (sword.start + sword.dir * 3):Lerp(sword.stuck, t * t), 1)
				if not sword.trail.Enabled then sword.trail.Enabled = true end
			elseif elapsed < sword.fadeAt then
				-- Quivering a little in the charge.
				local shake = charge * 0.35
				-- math.random, not the cast's seeded stream: frame counts differ
				-- between viewers, and the strikes below draw from that stream.
				placeSword(sword, sword.stuck + Vector3.new((math.random() * 2 - 1) * shake, (math.random() * 2 - 1) * shake, 0), 1)
				if sword.trail.Enabled and elapsed > sword.landAt + 0.06 then sword.trail.Enabled = false end
			else
				local out = ease((elapsed - sword.fadeAt) / 0.45)
				placeSword(sword, sword.stuck + sword.fling * out, 1 - out)
			end
		end

		local after = elapsed - flareAt
		light.Brightness = if after >= 0 then 12 * math.exp(-after * 4.5) else 0.4 * shown + 2.5 * charge
	end, {folder})

	-- One-off bursts and sounds -------------------------------------------------
	local feetFrame = CFrame.new(feet + up * 0.3)
	local ground = CFrame.new(centre + up * 0.4)
	local mid = CFrame.new(centre + up * height * 0.5)
	local lid = CFrame.new(centre + up * (height + 0.5))
	-- A spot on the ground round the tower, `out` of its half-width away.
	local function outside(out)
		local theta = random:NextNumber(0, math.pi * 2)
		return centre + radial(theta) * half * out
	end
	timeline.at(0, function()
		local handPoint = if hand then hand.Position else (origin * CFrame.new(1.2, 0.8, -1)).Position
		mount("Impact48", CFrame.new(handPoint), 0.7):burst(0.9)
		mount("Impact37", feetFrame, 1.3):burst(1)
		mount("Impact36", feetFrame, 1.4):burst(1)
		Kit.setEnabled(aura, true)
		ImpactFX.shake(origin.Position, 0.35, 0.25, 50)
		sound("eclipse.call", origin.Position, 0.6)
	end)
	-- The ground breaks where the cage will stand.
	timeline.at(markAt, function()
		mount("Impact37", ground, 7):burst(1)
		mount("Impact36", ground, 8):burst(1)
		mount("Rocks", ground, 2.4, {tint = SMOKE}):burst(1)
		mount("SmokeDense", ground, 3.5, {tint = SMOKE}):burst(0.8)
		mount("Droplets69", ground, 1.8):burst(0.5)
		mount("LightningSurge", ground, 3, {budget = 30}):burst(1)
		ImpactFX.shake(centre, 1, 0.45, 150)
		sound("eclipse.ground", centre, 0.7)
	end)
	-- Each landing row throws sparks and dust round its foot, a little higher
	-- in pitch than the one before.
	local ringDust = pool("Impact36", 4, 5)
	for _, row in ipairs(rows) do
		if not row.lid and row.layer > 0 then
			timeline.at(row.landAt, function()
				local y = (row.layer - 0.5) * cell
				for i, spot in ipairs(around) do
					rowBurst(frame * CFrame.new(spot + Vector3.new(0, y, 0)), 0.55)
					if i % 2 == 1 then rowDust(frame * CFrame.new(spot + Vector3.new(0, y - cell * 0.5, 0)), 0.45) end
				end
				if row.layer % 3 == 1 then ringDust(ground, 0.6) end
				ImpactFX.shake(centre, 0.3, 0.08, 120)
				sound("eclipse.row", centre + up * y, 0.5, 0.75 + row.layer * 0.035)
			end)
		end
	end
	-- The lid slams shut.
	timeline.at(lidAt, function()
		mount("Impact44", lid, 4.5):burst(1)
		mount("Impact36", lid, 6):burst(1)
		mount("Impact37", lid, 5):burst(1)
		mount("SmokeDense", lid, 3.2, {tint = SMOKE}):burst(0.7)
		mount("Impact36", ground, 8):burst(1)
		mount("Rocks", ground, 2, {tint = SMOKE}):burst(0.6)
		ImpactFX.shake(centre, 1.4, 0.4, 160)
		sound("eclipse.lid", centre + up * height, 0.75)
	end)
	-- While it holds: rings pulse out along the ground with a crackle, and
	-- glints flash over its faces.
	do
		local pulse = pool("Impact36", 4, 7)
		local at = lidAt + 0.3
		while at < chargeAt do
			timeline.at(at, function()
				pulse(ground, 0.8)
				sound("eclipse.hum", centre, 0.35)
			end)
			at += 0.35
		end
		local spark = pool("Impact10", 6, 0.8)
		at = lidAt + 0.1
		while at < flareAt do
			timeline.at(at, function()
				local face = FACES[random:NextInteger(1, 4)]
				local across = Vector3.new(face[2], 0, -face[1]) * random:NextNumber(-half, half)
				local point = Vector3.new(face[1] * (half + 0.4), random:NextNumber(0.1, 0.95) * height, face[2] * (half + 0.4)) + across
				spark(frame * CFrame.new(point), 0.7)
			end)
			at += 0.09
		end
	end
	for _, sword in ipairs(swords) do
		timeline.at(sword.appearAt, function()
			local at = CFrame.new(sword.start.Position)
			puff(at, 0.6)
			glint(at, 0.7)
			sound("eclipse.swordAppear", sword.start.Position, 0.4, random:NextNumber(0.9, 1.15))
		end)
		timeline.at(sword.landAt, function()
			local at = CFrame.lookAt(sword.hit, sword.hit + sword.dir)
			bite(at, 1)
			biteStar(at, 0.7)
			biteSparks(at, 0.7)
			ImpactFX.shake(sword.hit, 0.4, 0.1, 120)
			sound("eclipse.sword", sword.hit, 0.5, random:NextNumber(0.85, 1.1))
		end)
	end
	-- The charge: lightning bursts over the faces, the ground pulls, and bolts
	-- start striking round the tower, faster and faster.
	timeline.at(chargeAt, function()
		for i = 1, #crackles do crackles[i]:burst(1) end
		mount("Impact36", ground, 9):burst(1)
		mount("LightningSurge", mid, 4.5, {budget = 40}):burst(1)
		ImpactFX.shake(centre, 0.7, T.Settle, 160)
		sound("eclipse.charge", centre + up * height * 0.5, 0.75)
	end)
	for i, at in ipairs({0.05, 0.2, 0.32, 0.41, 0.47}) do
		timeline.at(chargeAt + at, function()
			strike(outside(random:NextNumber(1.25, 1.9)), 0.8 + i * 0.06)
		end)
	end
	-- The flare: the cage burns, and blows apart.
	timeline.at(flareAt, function()
		Kit.setEnabled(aura, false)
		for i = 1, #around do sparks[i]:clear() flames[i]:clear() end
		for i = 1, #crackles do crackles[i]:clear() end
		-- Grey-scale layers only: the Fire VFX flipbooks are coloured, and
		-- magenta over orange reads red.
		mount("Impact1", mid, 7):burst(1)
		mount("Impact44", mid, 7):burst(1)
		mount("Impact9", mid, 6):burst(1)
		mount("Explosion", mid, 4.5):burst(1)
		mount("Impact44", lid, 6):burst(1)
		mount("Impact48", lid, 7):burst(1)
		mount("Impact37", ground, 12):burst(1)
		mount("Impact36", ground, 13):burst(1)
		mount("Rocks", ground, 4, {tint = SMOKE}):burst(1)
		mount("Droplets69", mid, 3.5):burst(1)
		for i, c in ipairs(cornersAt) do
			mount("Impact48", frame * CFrame.new(c + up * height), 3.6):burst(1)
			mount("Impact44", frame * CFrame.new(c + up * height * 0.5), 3):burst(0.8)
			mount("Impact45", frame * CFrame.new(c + up), 2.8):burst(0.9)
			mount("Impact12", frame * CFrame.new(cornersAt[i] + up * height * 0.75), 2.6):burst(0.8)
			mount("Rocks", frame * CFrame.new(c + up), 1.8, {tint = SMOKE}):burst(0.7)
		end
		-- The pack explosion's own dome and wind shells (about 155 studs across
		-- at full scale), swelling from the tower's size to far past it.
		local shell = mount("Explosion", ground, 0.35, {visible = true, meshTint = TINT, hide = {Rocks = true}})
		shell:grow(scope, 1.15, 1.1)
		local high = mount("Explosion", mid, 0.25, {visible = true, meshTint = TINT, hide = {Rocks = true}})
		high:grow(scope, 0.8, 0.8)
		for _ = 1, 4 do strike(outside(random:NextNumber(1.1, 2.2)), 1.25) end
		ImpactFX.hit(mid.Position, {tint = MAGENTA, pattern = "triple", shake = 4.5, shakeDuration = 1.2, punch = 18,
			radius = 240, silhouetteRadius = 80})
		sound("eclipse.flare", mid.Position, 0.9)
	end)
	-- The aftershock.
	timeline.at(flareAt + 0.18, function()
		for face = 0, 3 do
			local side = frame * CFrame.Angles(0, face * math.pi / 2, 0)
			for _, along in ipairs({-0.7, -0.35, 0, 0.35, 0.7}) do
				mount("Impact45", side * CFrame.new(along * half, 1, -half), 2.6):burst(0.7)
			end
		end
		mount("Droplets69", mid, 4):burst(0.9)
		mount("LightningSurge", mid, 6, {budget = 50}):burst(1)
		mount("Impact41", mid, 6):burst(1)
		mount("SmokeDense", ground, 6, {tint = SMOKE}):burst(1)
		ImpactFX.shake(centre, 1.8, 0.6, 200)
		sound("eclipse.aftershock", mid.Position, 0.75)
	end)
	timeline.at(flareAt + 0.45, function()
		mount("Impact37", ground, 8):burst(0.8)
		mount("Impact36", ground, 10):burst(0.7)
		mount("SmokePuff", CFrame.new(centre + up * height * 0.3), 4.5, {tint = SMOKE}):burst(1)
		mount("SmokePuff", CFrame.new(centre + up * height * 0.7), 4, {tint = SMOKE}):burst(0.8)
		for _ = 1, 2 do strike(outside(random:NextNumber(1.3, 2.4)), 0.8) end
		sound("eclipse.settle", centre, 0.6)
	end)
	return true
end

return VFX
