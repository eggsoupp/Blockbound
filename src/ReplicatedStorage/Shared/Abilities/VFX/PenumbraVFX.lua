--[[
	Penumbra (Celestial, F), drawn on PenumbraPlan's clock, in Eclipse Prison's
	magenta, deep violet and black.

	  gather   the caster crouches (or, flying, tucks into a ball) in the
	           Eclipse aura; magenta streaks are pulled in to a white-hot
	           point at their chest and a dark ring closes on their feet
	  burst    a white-hot magenta dome flashes out round them (a whole sphere
	           in the air) with a glowing rim, and they vanish into it, flung
	           open (arms thrown up; in the air, spread like a star); crescent
	           slashes whip round the dome; pack flash, lightning, sparks,
	           impact frames; on the ground a black disc spreads under it
	  shroud   dark violet ribbons billow out from where they stood, curling
	           and turning, with a dark translucent dome inside them, smoke
	           rolling at the foot and crackles as the shroud nicks what is in
	           it; the caster steps back out of it
	  fade     the ribbons thin and lift, the disc fades, black wisps rise

	The dome, its rim and the dark dome are client-only sphere meshes drawn
	inside and out (a second shell with its faces turned in), so they still
	show with the camera inside them. The disc is a flat cylinder. Everything
	else is beams and pack emitters (PackAssembly, EclipseParticles).
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Plan = require(script.Parent.Parent.PenumbraPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Pack = require(script.Parent.PackAssembly)
local Library = require(script.Parent.EclipseParticles)
local CastPose = require(script.Parent.CastPose)
local Audio = require(script.Parent.Parent.Parent.Audio.CombatAudio)

local VFX = {}
local T = Plan.Tuning

-- Eclipse Prison's palette.
local MAGENTA = Color3.fromRGB(255, 40, 236)
local HOT = Color3.fromRGB(255, 205, 250)
local PINK = Color3.fromRGB(255, 150, 248)
local DEEP = Color3.fromRGB(64, 6, 104)
local VOID = Color3.fromRGB(7, 4, 13)
-- The shroud's ribbons, between the deep violet and black.
local SHROUD = Color3.fromRGB(42, 6, 58)
local SHROUD_EDGE = Color3.fromRGB(78, 8, 100)
-- The dark dome inside the ribbons: a see-through magenta-black.
local GLOOM = Color3.fromRGB(36, 3, 44)
local TINT = {deep = DEEP, main = MAGENTA, hot = HOT}
local SMOKE = {deep = VOID, main = Color3.fromRGB(70, 14, 110), hot = MAGENTA}
local SPARK_TINT = {deep = DEEP, main = MAGENTA, hot = Color3.fromRGB(255, 120, 245)}
local DUSK = Color3.fromRGB(205, 196, 255)
local STREAK = "http://www.roblox.com/asset/?id=3517446796"

local R15 = {
	Torso = {"UpperTorso", "Torso"},
	["Left Arm"] = {"LeftLowerArm", "Left Arm"},
	["Right Arm"] = {"RightLowerArm", "Right Arm"},
	["Left Leg"] = {"LeftLowerLeg", "Left Leg"},
	["Right Leg"] = {"RightLowerLeg", "Right Leg"},
}

-- The caster's poses (CastPose; see its header for the joint directions).
local rot, swing = CastPose.rot, CastPose.swing
local POSE = {
	-- Crouched, arms drawn in across the chest, head down.
	gather = {
		Root = CFrame.new(0, -0.55, 0), Waist = rot(-18), Neck = rot(-14),
		RightShoulder = swing(80, 38), LeftShoulder = swing(80, -38),
		RightElbow = rot(100), LeftElbow = rot(100),
		RightHip = rot(38), LeftHip = rot(38), RightKnee = rot(-62), LeftKnee = rot(-62),
	},
	-- Thrown open: up on the toes, chest up, arms flung up and out.
	burst = {
		Root = CFrame.new(0, 0.2, 0), Waist = rot(16), Neck = rot(20),
		RightShoulder = rot(-12, 0, 138), LeftShoulder = rot(-12, 0, -138),
		RightElbow = rot(12), LeftElbow = rot(12),
		RightHip = rot(0, 0, 10), LeftHip = rot(0, 0, -10),
	},
	-- Back out of the shroud low, one hand down, as from a landing.
	land = {
		Root = CFrame.new(0, -0.7, 0), Waist = rot(-14), Neck = rot(8),
		RightShoulder = rot(20, 0, 30), LeftShoulder = rot(-25, 0, -55),
		RightElbow = rot(25), LeftElbow = rot(15),
		RightHip = rot(45), LeftHip = rot(20, 0, -12), RightKnee = rot(-75), LeftKnee = rot(-40),
	},
	-- Flying: tucked into a ball, arms round the knees.
	tuck = {
		Root = rot(-14), Waist = rot(-30), Neck = rot(-26),
		RightShoulder = swing(62, 30), LeftShoulder = swing(62, -30),
		RightElbow = rot(85), LeftElbow = rot(85),
		RightHip = rot(88), LeftHip = rot(88), RightKnee = rot(-112), LeftKnee = rot(-112),
	},
	-- Flying: flung open like a star.
	star = {
		Root = rot(12), Waist = rot(14), Neck = rot(16),
		RightShoulder = rot(-8, 0, 108), LeftShoulder = rot(-8, 0, -108),
		RightElbow = rot(6), LeftElbow = rot(6),
		RightHip = rot(-6, 0, 32), LeftHip = rot(-6, 0, -32), RightKnee = rot(-12), LeftKnee = rot(-12),
	},
}
local burstAt = Plan.burstAt()
local GROUND_KEYS = {
	{at = 0, w = 0, pose = POSE.gather}, {at = 0.1, w = 1, pose = POSE.gather}, {at = burstAt - 0.02, w = 1, pose = POSE.gather},
	{at = burstAt + 0.06, w = 1, pose = POSE.burst}, {at = burstAt + 0.62, w = 1, pose = POSE.burst},
	{at = burstAt + 0.84, w = 1, pose = POSE.land}, {at = burstAt + 1.12, w = 1, pose = POSE.land},
	{at = burstAt + 1.5, w = 0, pose = POSE.land},
}
local AIR_KEYS = {
	{at = 0, w = 0, pose = POSE.tuck}, {at = 0.1, w = 1, pose = POSE.tuck}, {at = burstAt - 0.02, w = 1, pose = POSE.tuck},
	{at = burstAt + 0.05, w = 1, pose = POSE.star}, {at = burstAt + 0.72, w = 1, pose = POSE.star},
	{at = burstAt + 1.2, w = 0, pose = POSE.star},
}
VFX.Poses, VFX.GroundKeys, VFX.AirKeys = POSE, GROUND_KEYS, AIR_KEYS

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

--[[
	A smooth sphere seen from outside and from within, so the camera can sit
	in it: the pack Explosion's "Inner" shell (a double-sided mesh), or, if the
	library is missing, a sphere mesh drawn twice with one copy's faces turned
	in by a negative scale.
]]
local SphereMesh = (function()
	local library = game:GetService("ReplicatedStorage"):WaitForChild("AbilityVFXLibrary", 10)
	local explosion = library and library:FindFirstChild("Explosion")
	local inner = explosion and explosion:FindFirstChild("Inner", true)
	return if inner and inner:IsA("MeshPart") then inner else nil
end)()

local function bare(p, color, material)
	p.Color, p.Material, p.Transparency = color, material, 1
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	for _, child in ipairs(p:GetChildren()) do child:Destroy() end
	return p
end

local function sphere(parent, color, material)
	if SphereMesh then
		local p = bare(SphereMesh:Clone(), color, material)
		p.Parent = parent
		return {{part = p}}
	end
	local pair = {}
	for _, sign in ipairs({1, -1}) do
		local p = bare(Instance.new("Part"), color, material)
		p.Size = Vector3.one
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		p.Parent = parent
		table.insert(pair, {part = p, mesh = mesh, sign = sign})
	end
	return pair
end

local function setSphere(pair, centre, diameter, transparency, color)
	for _, s in ipairs(pair) do
		local p = s.part
		if transparency >= 0.995 or diameter <= 0.05 then
			if p.Transparency ~= 1 then p.Transparency = 1 end
		else
			if s.mesh then
				p.CFrame = CFrame.new(centre)
				s.mesh.Scale = Vector3.one * diameter * s.sign
			else
				p.Size = Vector3.one * diameter
				p.CFrame = CFrame.new(centre)
			end
			p.Transparency = transparency
			if color and p.Color ~= color then p.Color = color end
		end
	end
end

-- Flat strokes laid out as arcs (see EclipseVFX): a host with Y up, an arc
-- in its XZ plane.
local function stroke(host, width, color, emission, faceCamera, z)
	local a0, a1 = Kit.attachment(host), Kit.attachment(host)
	local b = beam(host, a0, a1, {Texture = if emission > 0 then STREAK else "", FaceCamera = faceCamera, Segments = 12,
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

local function layoutArc(s, radius, t0, t1, opacity, w0, w1)
	s.a0.CFrame = CFrame.fromMatrix(radial(t0) * radius, tangent(t0), radial(t0))
	s.a1.CFrame = CFrame.fromMatrix(radial(t1) * radius, tangent(t1), radial(t1))
	local k = 4 / 3 * math.tan((t1 - t0) / 4) * radius
	s.beam.CurveSize0, s.beam.CurveSize1 = k, k
	s.beam.Width0, s.beam.Width1 = s.width * (w0 or 1), s.width * (w1 or w0 or 1)
	Kit.opacity(s.beam, opacity)
end

local function circle(host, width, color, emission, z)
	local arcs = {}
	for q = 1, 4 do arcs[q] = stroke(host, width, color, emission, false, z) end
	return arcs
end

local function layoutCircle(arcs, radius, opacity)
	for q, s in ipairs(arcs) do
		layoutArc(s, radius, (q - 1) * math.pi / 2, q * math.pi / 2, opacity)
	end
end

-- A unit vector `elevation` above the horizontal at `azimuth`.
local function direction(azimuth, elevation)
	return Vector3.new(math.cos(azimuth) * math.cos(elevation), math.sin(elevation), math.sin(azimuth) * math.cos(elevation))
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or type(payload.startedAt) ~= "number" or type(payload.seed) ~= "number" then
		return false
	end
	local total = Plan.duration()
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 4 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local origin = payload.origin
	local up = Vector3.yAxis
	local random = Random.new(payload.seed)
	local radius = T.Radius
	local shroudEnd = Plan.shroudEnd()
	local returnAt = burstAt + T.Vanish

	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "Penumbra"
	folder.Parent = workspace

	local caster = payload.caster
	Pack.endWithCaster(scope, caster)
	local character = caster and caster.Character
	local core = origin.Position
	local floor = Plan.ground(core, Kit.rayParams({character}))
	-- Drawn in the air when flying, or when there is no ground close under.
	local air = payload.air == true or floor == nil
	-- The dome's middle: the ground under the caster, or the caster.
	local centre = if air then core else floor
	local mid = if air then core else floor + up * 3

	local startedAt = payload.startedAt
	local function elapsedNow()
		return workspace:GetServerTimeNow() - startedAt
	end
	CastPose.play(scope, character, if air then AIR_KEYS else GROUND_KEYS, elapsedNow)

	local function mount(name, cframe, scale, options)
		options = options or {}
		return Pack.mount(scope, folder, name, {cframe = cframe, scale = scale, budget = options.budget,
			tint = options.tint or TINT, brightness = options.brightness or 3, billboard = options.billboard})
	end
	local function sound(key, position, volume, pitch)
		Audio.play(key, position, volume or 0.6, pitch or 1)
	end

	-- The dimming, for whoever stands near ------------------------------------
	local grade = scope:add(Instance.new("ColorCorrectionEffect"))
	grade.Name = "PenumbraDim"
	grade.Parent = Lighting
	local function nearness()
		local own = Players.LocalPlayer and Players.LocalPlayer.Character
		local ownRoot = own and own:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		local from = if ownRoot then ownRoot.Position elseif camera then camera.CFrame.Position else core
		return math.clamp(1.6 - (from - core).Magnitude / 90, 0, 1)
	end

	-- The aura (Eclipse Prison's, on the caster) ---------------------------------
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
				local layer = scope:add(emitter(kind, parent))
				layer.Rate *= 1.3
				table.insert(aura, layer)
			end
		end
	end

	-- Vanishing into the flash ------------------------------------------------
	local hidden = false
	local function hide(on)
		if not character or hidden == on then return end
		hidden = on
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = if on then 1 else 0 end
		end
	end
	scope:add(function() hide(false) end)

	-- The gather: streaks pulled into the chest, a hot point, a closing ring ----
	local chest = core + up * 0.6
	local pullHost = Kit.host(folder, "Pull", CFrame.new(chest))
	local pulls = {}
	for i = 1, 12 do
		local dir = direction(random:NextNumber(0, math.pi * 2),
			if air then random:NextNumber(-1.1, 1.1) else random:NextNumber(-0.15, 1.0))
		local a0, a1 = Kit.attachment(pullHost), Kit.attachment(pullHost)
		pulls[i] = {
			dir = dir, a0 = a0, a1 = a1, delay = random:NextNumber(0, 0.12), length = random:NextNumber(3, 6),
			glow = beam(pullHost, a0, a1, {Texture = STREAK, FaceCamera = true, Segments = 1, Width0 = 0.08, Width1 = 0.55,
				Color = ColorSequence.new(MAGENTA), LightEmission = 1, Brightness = 2}),
			core = beam(pullHost, a0, a1, {Texture = STREAK, FaceCamera = true, Segments = 1, Width0 = 0.03, Width1 = 0.16,
				Color = ColorSequence.new(PINK), LightEmission = 1, Brightness = 2.5, ZOffset = 0.3}),
		}
	end
	local point = sphere(folder, HOT, Enum.Material.Neon)
	local ringHost = Kit.host(folder, "Ring", CFrame.new((floor or core) + up * 0.2))
	local ringInk, ringGlow = circle(ringHost, 1.4, VOID, 0, 0.1), circle(ringHost, 3.6, MAGENTA, 1)

	-- The burst: dome, rim, dark dome, disc ---------------------------------------
	local flash = sphere(folder, HOT, Enum.Material.Neon)
	local rim = sphere(folder, MAGENTA, Enum.Material.ForceField)
	-- Neon so the light round it does not turn it blue: a flat dark tint.
	local dark = sphere(folder, GLOOM, Enum.Material.Neon)
	local disc
	if not air then
		disc = Instance.new("Part")
		disc.Shape = Enum.PartType.Cylinder
		disc.Material, disc.Color, disc.Transparency = Enum.Material.Neon, VOID, 1
		disc.Anchored, disc.CanCollide, disc.CanTouch, disc.CanQuery, disc.CastShadow = true, false, false, false, false
		disc.CFrame = CFrame.new(floor + up * 0.12) * CFrame.Angles(0, 0, math.pi / 2)
		disc.Size = Vector3.new(0.2, 1, 1)
		disc.Parent = folder
	end
	local waveHost = Kit.host(folder, "Wave", CFrame.new((floor or core) + up * 0.3))
	local waveGlow, waveCore = circle(waveHost, 7, MAGENTA, 1, 0.2), circle(waveHost, 2.4, PINK, 1, 0.3)

	-- The crescents ------------------------------------------------------------
	local crescents = {}
	for i = 1, 9 do
		-- A plane through the dome's middle, tipped well off level so the
		-- crescents wrap round it rather than lying flat.
		local tilt = CFrame.Angles(random:NextNumber(-1.2, 1.2), random:NextNumber(0, math.pi * 2), random:NextNumber(-1.2, 1.2))
		local host = Kit.host(folder, "Crescent", CFrame.new(mid) * tilt)
		local c = {
			host = host, frame = CFrame.new(mid) * tilt,
			radius = radius * random:NextNumber(0.55, 1.0),
			from = random:NextNumber(0, math.pi * 2), span = random:NextNumber(2.4, 3.6) * (if random:NextNumber() < 0.5 then -1 else 1),
			length = random:NextNumber(1.1, 1.6),
			at = burstAt - 0.03 + (i - 1) * 0.035 + random:NextNumber(0, 0.03), life = random:NextNumber(0.26, 0.38),
			glow = {stroke(host, 3.4, MAGENTA, 1, true), stroke(host, 3.4, MAGENTA, 1, true)},
			core = {stroke(host, 1.1, HOT, 1, true, 0.4), stroke(host, 1.1, HOT, 1, true, 0.4)},
		}
		crescents[i] = c
	end
	local function layoutCrescent(c, elapsed)
		local t = (elapsed - c.at) / c.life
		if t < 0 or t > 1.25 then
			for k = 1, 2 do Kit.opacity(c.glow[k].beam, 0) Kit.opacity(c.core[k].beam, 0) end
			return
		end
		-- The head races round; the tail follows a crescent's length behind.
		local head = c.from + c.span * ease(math.min(t, 1))
		local tail = head - math.sign(c.span) * c.length * math.min(1, t * 3) * (1 - math.max(0, t - 1) * 3)
		local alpha = math.clamp(1 - (t - 0.7) / 0.55, 0, 1)
		local r = c.radius * (1 + 0.15 * t)
		local a, b = math.min(tail, head), math.max(tail, head)
		local m = (a + b) * 0.5
		-- Thick in the middle, needle-thin at both tips.
		local thinFirst = tail < head
		for k, s in ipairs({c.glow, c.core}) do
			local opacity = alpha * (if k == 1 then 0.8 else 1)
			layoutArc(s[1], r, a, m, opacity, if thinFirst then 0.08 else 0.25, 1)
			layoutArc(s[2], r, m, b, opacity, 1, if thinFirst then 0.25 else 0.08)
		end
	end

	-- The shroud: dark ribbons ------------------------------------------------
	local shroudHost = Kit.host(folder, "Shroud", CFrame.new(centre))
	local ribbons = {}
	local count = if air then 22 else 18
	for i = 1, count do
		local a0, a1 = Kit.attachment(shroudHost), Kit.attachment(shroudHost)
		local width = random:NextNumber(5, 10)
		local r = {
			a0 = a0, a1 = a1, width = width,
			azimuth = (i - 1) / count * math.pi * 2 + random:NextNumber(-0.2, 0.2),
			elevation = if air then random:NextNumber(-1.25, 1.25) else random:NextNumber(0.1, 1.2),
			length = radius * random:NextNumber(0.7, 1.05),
			spin = random:NextNumber(0.45, 0.9), twist = random:NextNumber(-2, 2), curl = if i % 2 == 0 then 1 else -1,
			at = burstAt + 0.04 + random:NextNumber(0, 0.12),
			sheet = beam(shroudHost, a0, a1, {Texture = "", FaceCamera = false, Segments = 16,
				Width0 = width * 0.3, Width1 = width, Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, VOID), ColorSequenceKeypoint.new(0.45, SHROUD), ColorSequenceKeypoint.new(1, SHROUD_EDGE)}),
				LightEmission = 0, Brightness = 1}),
			vein = beam(shroudHost, a0, a1, {Texture = STREAK, FaceCamera = true, Segments = 16,
				Width0 = 0.3, Width1 = 1.4, Color = ColorSequence.new(MAGENTA), LightEmission = 1, Brightness = 2.5, ZOffset = 0.2}),
		}
		ribbons[i] = r
	end
	local function ribbonAlpha(alpha)
		-- Soft at both ends, densest just past the middle.
		local base = 1 - 0.62 * alpha
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, base + 0.1),
			NumberSequenceKeypoint.new(0.6, base), NumberSequenceKeypoint.new(1, 1)})
	end
	local function layoutRibbon(r, elapsed, fade)
		local t = elapsed - r.at
		if t < 0 or fade >= 1 then
			if r.sheet.Enabled then r.sheet.Enabled, r.vein.Enabled = false, false end
			return
		end
		local grow = ease(t / 0.45)
		local azimuth = r.azimuth + r.spin * t * r.curl
		local dir = direction(azimuth, r.elevation)
		local reach = r.length * (0.2 + 0.8 * grow) * (1 + 0.12 * fade)
		local lift = up * fade * 5
		local base = dir * 1.2 + lift * 0.3
		local tip = dir * reach + lift
		local swirl = up:Cross(dir)
		if swirl.Magnitude < 0.05 then swirl = Vector3.xAxis end
		swirl = swirl.Unit * r.curl
		local out = (dir + up * 0.5).Unit
		local twist = r.twist * t
		local side0 = out:Cross(swirl).Unit
		local side1 = swirl:Cross(dir).Unit
		r.a0.CFrame = CFrame.fromMatrix(base, out, side0 * math.cos(twist) + swirl * math.sin(twist))
		r.a1.CFrame = CFrame.fromMatrix(tip, swirl, side1 * math.cos(twist * 0.6) + dir * math.sin(twist * 0.6))
		r.sheet.CurveSize0, r.sheet.CurveSize1 = reach * 0.55, reach * 0.45
		r.vein.CurveSize0, r.vein.CurveSize1 = reach * 0.55, reach * 0.45
		-- Thinning into strands as it fades.
		local w = r.width * (0.5 + 0.7 * grow) * (1 - 0.7 * fade)
		r.sheet.Width0, r.sheet.Width1 = w * 0.3, w
		local alpha = math.min(1, t / 0.12) * (1 - fade) ^ 1.5
		r.sheet.Transparency = ribbonAlpha(alpha)
		if not r.sheet.Enabled then r.sheet.Enabled = true end
		-- The magenta veins burn early and cool as the shroud darkens.
		Kit.opacity(r.vein, alpha * 0.55 * math.exp(-t * 1.6))
	end

	-- Smoke round the foot, black wisps rising at the end ------------------------
	local smokes = {}
	for i = 1, 6 do
		local theta = (i - 1) / 6 * math.pi * 2
		local at = centre + radial(theta) * radius * 0.55 + (if air then direction(theta, random:NextNumber(-0.8, 0.8)) * 4 else up * 0.6)
		smokes[i] = mount("SmokeDense", CFrame.new(at), 1.4, {budget = 10, tint = SMOKE})
	end
	local gatherSmoke = mount("SmokeDense", CFrame.new((floor or core) + up * 0.4), 0.9, {budget = 12, tint = SMOKE})
	local gatherSparks = mount("LightningSurge", CFrame.new(chest), 0.9, {budget = 16})
	local wispHost = Kit.host(folder, "Wisps", CFrame.new(centre + up * (if air then 0 else 2)), Vector3.new(radius, 2, radius))
	local wisps = {}
	for _, kind in ipairs({"Streaks", "Wisps", "Streaks"}) do
		local e = scope:add(emitter(kind, wispHost, {LockedToPart = false, Rate = 26, Brightness = 1, LightEmission = 0,
			EmissionDirection = Enum.NormalId.Top, Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.3, 2.6), NumberSequenceKeypoint.new(1, 0)})}))
		e.Color = ColorSequence.new(VOID)
		table.insert(wisps, e)
	end

	local light = Kit.light(Kit.host(folder, "Light", CFrame.new(mid)), MAGENTA, 34)

	-- The timeline -------------------------------------------------------------
	local timeline = Kit.drive(scope, startedAt, total, function(elapsed)
		for _, h in ipairs(auraHosts) do
			if h.limb.Parent then h.host.CFrame = h.limb.CFrame * h.offset end
		end
		local near = nearness()
		local since = elapsed - burstAt
		local fade = Kit.ramp(elapsed, shroudEnd - 0.25, total - 0.1)

		-- Gather.
		local g = Kit.ramp(elapsed, 0, burstAt)
		for _, p in ipairs(pulls) do
			local u = math.clamp((elapsed - p.delay) / (burstAt - p.delay), 0, 1)
			local r = 13 * (1 - u * u) + 0.3
			p.a1.WorldPosition = chest + p.dir * r
			p.a0.WorldPosition = chest + p.dir * (r + p.length * (1 - u * 0.6))
			local alpha = if elapsed < burstAt then math.min(1, u * 4) else 0
			Kit.opacity(p.glow, alpha * 0.9)
			Kit.opacity(p.core, alpha)
		end
		setSphere(point, chest, if elapsed < burstAt + 0.04 then 0.4 + 2.6 * g * g else 0, 0.05)
		local ringR = radius * 1.1 * (1 - ease(g)) + 1.2
		local ringA = if elapsed < burstAt then math.min(1, g * 5) else 0
		layoutCircle(ringInk, ringR, if air then 0 else ringA)
		layoutCircle(ringGlow, ringR, if air then 0 else ringA * 0.8)

		-- The dome flashes out, then burns down to magenta and goes; its rim
		-- lingers a little longer.
		if since >= 0 then
			local out = ease(since / T.Flash)
			local diameter = 2 * radius * (0.12 + 0.88 * out)
			local burn = Kit.ramp(since, T.Flash * 0.5, T.Flash + 0.26)
			setSphere(flash, centre, diameter, 0.22 + 0.78 * burn, HOT:Lerp(MAGENTA, math.min(1, burn * 1.6)))
			setSphere(rim, centre, diameter * 1.04, Kit.ramp(since, T.Flash, T.Flash + 0.5))
			-- The dark dome swells inside the ribbons, never more than a tint.
			local d = Kit.ramp(since, 0.06, 0.7)
			setSphere(dark, centre, 2 * radius * (0.5 + 0.3 * ease(d)) * (1 + 0.15 * fade),
				if since < 0.06 then 1 else 1 - 0.38 * math.min(1, (since - 0.06) / 0.2) * (1 - Kit.ramp(elapsed, shroudEnd - 0.5, shroudEnd + 0.2)))
			if disc then
				local spread = ease(since / 0.25)
				local diameterDisc = 2 * radius * 0.85 * spread
				disc.Size = Vector3.new(0.2, math.max(diameterDisc, 0.1), math.max(diameterDisc, 0.1))
				disc.Transparency = 0.42 + 0.58 * Kit.ramp(elapsed, shroudEnd - 0.4, total - 0.05)
			end
			-- A ring races out along the ground from the dome's foot.
			local w = since / 0.6
			if w <= 1 then
				layoutCircle(waveGlow, radius * (1 + 0.9 * ease(w)), (1 - w) * 0.9)
				layoutCircle(waveCore, radius * (1 + 0.9 * ease(w)), 1 - w)
			else
				layoutCircle(waveGlow, radius, 0)
				layoutCircle(waveCore, radius, 0)
			end
		else
			setSphere(flash, centre, 0, 1)
			setSphere(rim, centre, 0, 1)
			setSphere(dark, centre, 0, 1)
		end

		for _, c in ipairs(crescents) do layoutCrescent(c, elapsed) end
		for _, r in ipairs(ribbons) do layoutRibbon(r, elapsed, fade) end

		-- The caster is gone inside the flash.
		if elapsed >= burstAt + 0.02 and elapsed < returnAt then
			hidden = false
			hide(true)
		elseif hidden then
			hide(false)
		end

		local shrouded = since >= 0.08 and elapsed < shroudEnd - 0.2
		for _, s in ipairs(smokes) do s:stream(shrouded) end
		gatherSmoke:stream(elapsed < burstAt)
		gatherSparks:stream(elapsed < burstAt)
		Kit.setEnabled(wisps, elapsed >= shroudEnd - 0.55 and elapsed < total - 0.35)

		-- A little darker round the shroud; a short pink pop on the burst.
		local dim = Kit.ramp(elapsed, burstAt, burstAt + 0.25) * (1 - fade) * near
		local pop = if since >= 0 then math.exp(-since * 14) * near else 0
		grade.TintColor = Color3.new(1, 1, 1):Lerp(DUSK, dim):Lerp(Color3.fromRGB(255, 200, 250), pop * 0.35)
		grade.Brightness = -0.1 * dim + 0.05 * pop
		grade.Contrast = 0.15 * dim
		grade.Saturation = 0.2 * dim + 0.25 * pop

		light.Brightness = if since >= 0 then 5 * math.exp(-since * 5) + 0.3 * (1 - fade) else 0.8 * g
	end, {folder})

	-- One-off bursts and sounds -------------------------------------------------
	local ground = CFrame.new((floor or core) + up * 0.4)
	timeline.at(0, function()
		Kit.setEnabled(aura, true)
		mount("Impact37", ground, 1.4):burst(0.8)
		ImpactFX.shake(core, 0.3, 0.3, 50)
		sound("penumbra.gather", core, 0.6)
	end)
	timeline.at(burstAt, function()
		mount("Impact1", CFrame.new(mid), 2.4):burst(1)
		mount("Impact44", CFrame.new(mid), 2.6):burst(1)
		mount("Impact9", CFrame.new(mid), 2):burst(1)
		mount("Impact10", CFrame.new(chest), 1.4):burst(1)
		mount("LightningSurge", CFrame.new(mid), 3, {budget = 40}):burst(1)
		mount("Impact41", CFrame.new(mid), 2.2):burst(1)
		mount("Droplets69", CFrame.new(mid), 1.6):burst(0.8)
		if not air then
			mount("Impact36", ground, 5.5):burst(1)
			mount("Impact37", ground, 5):burst(1)
		else
			mount("Impact48", CFrame.new(core), 2.6):burst(1)
		end
		mount("SmokePuff", CFrame.new(mid), 3.4, {tint = SMOKE}):burst(1)
		ImpactFX.hit(mid, {tint = MAGENTA, shake = 2.2, shakeDuration = 0.5, punch = 9, radius = 120, silhouetteRadius = 30})
		sound("penumbra.burst", core, 0.85)
	end)
	for i, c in ipairs(crescents) do
		if i % 3 == 1 then
			timeline.at(c.at, function()
				sound("penumbra.crescent", mid, 0.45, random:NextNumber(0.9, 1.15))
			end)
		end
	end
	timeline.at(burstAt + 0.08, function()
		sound("penumbra.shroud", core, 0.55)
	end)
	timeline.at(returnAt, function()
		mount("Impact48", CFrame.new(core), 0.9):burst(0.8)
		mount("SmokePuff", CFrame.new(core), 1, {tint = SMOKE}):burst(0.6)
		sound("penumbra.return", core, 0.5)
	end)
	for _, at in ipairs(T.Ticks) do
		timeline.at(burstAt + at, function()
			for _ = 1, 2 do
				local spot = centre + direction(random:NextNumber(0, math.pi * 2),
					if air then random:NextNumber(-0.9, 0.9) else random:NextNumber(0.05, 0.6)) * radius * random:NextNumber(0.3, 0.8)
				mount("LightningSurge", CFrame.new(spot), 1.7, {budget = 20}):burst(0.8)
				mount("Impact45", CFrame.new(spot), 1.2):burst(0.6)
			end
			ImpactFX.shake(core, 0.4, 0.12, 90)
			sound("penumbra.tick", centre, 0.45)
		end)
	end
	timeline.at(shroudEnd - 0.25, function()
		Kit.setEnabled(aura, false)
		mount("SmokePuff", CFrame.new(mid + up * 2), 3, {tint = SMOKE}):burst(0.7)
		sound("penumbra.fade", core, 0.5)
	end)
	return true
end

return VFX
