local CombatAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.CombatAudio)
-- Sumi Whirl, drawn from one message:
--   stroke  one brushstroke paints a ring of ink around the caster, thick
--           where it starts and flicking thin at the tail, spattering drops
--   cut     the ring flashes paper-white and cuts outward: halftone slashes,
--           white slash lines, ink splatter and black shards all the way
--           round, with monochrome impact frames, a shake and a punch
--   bleed   the ink smudges, drips and fades
-- Every visible effect is an authored particle or textured Beam; Parts are
-- invisible emitter hosts only.
local Plan = require(script.Parent.Parent.SumiPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.SumiParticles)

local VFX = {}
local T = Plan.Tuning
local INK = Color3.fromRGB(14, 12, 20)
local WASH = Color3.fromRGB(52, 48, 64)
local PAPER = Color3.fromRGB(248, 244, 232)
local SEAL = Color3.fromRGB(196, 28, 44)
local ns, curve, colors = Kit.ns, Kit.curve, Kit.colors
local live = 0
local preloaded = false
local ARCS = 12
local CUTS = 8

-- VFX :D flipbook sheets and pack textures the curated library does not carry.
local Sheets = {
	-- Slash VFX Beams texture: a ragged scorch. Tinted black it is a brushstroke.
	Stroke = {Texture = "rbxassetid://15253860988"},
	-- Slash VFX Trail2: a soft band for the stroke's wash and its white flash.
	Band = {Texture = "rbxassetid://16892374733"},
	-- VFX :D.8 Images/HalftoneSlashFB1: a manga halftone slash.
	Halftone = {
		Texture = "rbxassetid://132195635518865",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D.12 Images/darkSlash.
	DarkSlash = {
		Texture = "rbxassetid://83313093336922",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D.153 Images/Drops_01: falling drops.
	Drops = {
		Texture = "rbxassetid://82581730437358",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
		FlipbookMode = Enum.ParticleFlipbookMode.Random,
	},
	-- VFX :D.73: an ink splat.
	InkSplat = {
		Texture = "rbxassetid://113434257545313",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
}

local SOUND_SWISH = CombatAudio.ids.sword_swing
local SOUND_CUT = CombatAudio.ids.plasma_cut
local SOUND_HIT = CombatAudio.ids.punch_heavy1

function VFX.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload(Kit.textures(Library, Sheets), {SOUND_SWISH, SOUND_CUT, SOUND_HIT})
end

function VFX.duration()
	return Plan.duration()
end

local function emitter(kind, parent, props)
	return Kit.emitter(if Sheets[kind] then Sheets else Library, kind, parent, props)
end

-- A cubic arc spanning `sweep` radians is circular when its control points
-- sit (4/3)tan(sweep/4) of the radius along each end's tangent.
local function control(sweep, radius)
	return 4 / 3 * math.tan(sweep / 4) * radius
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or type(payload.startedAt) ~= "number" then
		return false
	end
	local total = T.CutAt + T.Aftermath
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 4 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local origin = payload.origin
	local facing = Kit.flat(origin.LookVector)
	local centre = origin.Position + Vector3.new(0, T.Height, 0)
	local R = T.Radius
	local random = Random.new(payload.seed or 3)
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "SumiWhirl"
	folder.Parent = workspace
	local host = Kit.host(folder, "Ring", CFrame.new(centre))

	-- The ring ----------------------------------------------------------------
	-- Twelve arcs, each a band standing upright (an attachment's Y is the
	-- beam's width), so the stroke reads as a wall of ink from any side.
	-- Widths taper along the stroke like a brush lifting off the page.
	local sweep = math.pi * 2 / ARCS
	local arcs = {}
	for i = 1, ARCS do
		local a0, a1 = Kit.attachment(host), Kit.attachment(host)
		local from, to = (i - 1) / ARCS, i / ARCS
		local w0, w1 = 3.4 * (1 - 0.62 * from), 3.4 * (1 - 0.62 * to)
		local arc = {a0 = a0, a1 = a1, from = from, to = to, beams = {}}
		local function band(texture, color, scale, emission, z)
			local beam = Kit.beam(host, a0, a1, {
				Texture = texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1, FaceCamera = false,
				Segments = 10, Width0 = w0 * scale, Width1 = w1 * scale, Color = ColorSequence.new(color),
				LightEmission = emission, Brightness = 1, ZOffset = z, Transparency = ns(1), Enabled = false,
			})
			table.insert(arc.beams, beam)
			return beam
		end
		arc.wash = band(Sheets.Band.Texture, WASH, 1.9, 0, 0)
		arc.ink = band(Sheets.Stroke.Texture, INK, 1.35, 0, 0.05)
		-- An untextured beam is a solid band: the stroke's dense middle.
		arc.core = band("", INK, 0.24, 0, 0.1)
		arc.flash = band(Sheets.Band.Texture, PAPER, 0.7, 1, 0.15)
		arcs[i] = arc
	end
	local function place(attachment, along)
		local a = Plan.angle(facing, along)
		local radial = Vector3.new(math.cos(a), 0, -math.sin(a))
		-- Tangent in the direction the stroke runs.
		local tangent = Vector3.new(math.sin(a), 0, math.cos(a))
		attachment.CFrame = CFrame.fromMatrix(radial * R, tangent, Vector3.yAxis)
		return radial, tangent
	end

	-- The brush ---------------------------------------------------------------
	local brush = Kit.attachment(host)
	local spatter = {
		emitter("SplatterWild", brush, {Color = colors(INK, WASH), Size = curve({0, 0.4}, {1, 2.4, 0.3}), Rate = 70,
			Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(35, 35), Acceleration = Vector3.new(0, -60, 0),
			LightInfluence = 0, EmissionDirection = Enum.NormalId.Right, Transparency = curve({0, 0}, {0.7, 0.2}, {1, 1})}),
		emitter("Blob", brush, {Color = ColorSequence.new(INK), Size = curve({0, 0.4}, {1, 0.7, 0.2}), Rate = 50,
			Speed = NumberRange.new(14, 26), SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, -55, 0),
			LightInfluence = 0, EmissionDirection = Enum.NormalId.Right, Lifetime = NumberRange.new(0.3, 0.5), Transparency = ns(0)}),
		emitter("SpecsDark", brush, {Speed = NumberRange.new(16, 34), SpreadAngle = Vector2.new(40, 40), Rate = 40,
			Size = curve({0, 0}, {0.25, 0.9, 0.4}, {1, 0}), EmissionDirection = Enum.NormalId.Right, Drag = 4}),
	}

	-- The cut -----------------------------------------------------------------
	local cutLayers = {}
	for i = 1, CUTS do
		local along = (i - 0.5) / CUTS
		local a = Plan.angle(facing, along)
		local radial = Vector3.new(math.cos(a), 0, -math.sin(a))
		local at = Kit.attachment(host)
		-- Front points outward, so directional emitters throw away from the caster.
		at.CFrame = CFrame.lookAt(radial * R, radial * (R + 1))
		local high = Kit.attachment(host)
		high.CFrame = CFrame.lookAt(radial * R + Vector3.new(0, 1.6, 0), radial * (R + 1) + Vector3.new(0, 1.6, 0))
		local spin = NumberRange.new(math.deg(a) + random:NextNumber(-25, 25))
		table.insert(cutLayers, {emitter("Halftone", high, {Color = ColorSequence.new(INK), Size = curve({0, 9}, {1, 12}), Lifetime = NumberRange.new(0.32),
			FlipbookFramerate = NumberRange.new(40), LightInfluence = 0, Speed = NumberRange.new(0.01), Rotation = spin, ZOffset = 1}), 1})
		table.insert(cutLayers, {emitter("DarkSlash", at, {Color = ColorSequence.new(INK), Size = curve({0, 5}, {1, 7}), Lifetime = NumberRange.new(0.3),
			FlipbookFramerate = NumberRange.new(44), LightInfluence = 0, Speed = NumberRange.new(0.01),
			Rotation = NumberRange.new(-30, 30)}), 1})
		table.insert(cutLayers, {emitter("SlashLines", at, {Color = ColorSequence.new(PAPER), EmissionDirection = Enum.NormalId.Front,
			SpreadAngle = Vector2.new(12, 12), Speed = NumberRange.new(55, 95), Brightness = 2}), 4})
		table.insert(cutLayers, {emitter("Splatter", at, {Color = ColorSequence.new(INK), Size = curve({0, 3}, {1, 6, 0.6}), Lifetime = NumberRange.new(0.6, 0.8),
			Orientation = Enum.ParticleOrientation.FacingCamera, LightInfluence = 0, Speed = NumberRange.new(4, 9),
			EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, -14, 0)}), 2})
		table.insert(cutLayers, {emitter("ShardsDark", at, {Color = ColorSequence.new(INK), EmissionDirection = Enum.NormalId.Front,
			SpreadAngle = Vector2.new(25, 25), Speed = NumberRange.new(70, 130), Size = curve({0, 0}, {0.25, 2, 2}, {1, 0})}), 5})
		table.insert(cutLayers, {emitter("SplatterWild", at, {Color = if i % 3 == 0 then colors(SEAL, INK) else colors(INK, WASH),
			EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(45, 45), Speed = NumberRange.new(16, 30),
			Size = curve({0, 0.6}, {1, 3, 0.3}), LightInfluence = 0, Transparency = curve({0, 0}, {0.7, 0.2}, {1, 1})}), 8})
		table.insert(cutLayers, {emitter("Smoke", at, {Color = colors(WASH, INK), Size = curve({0, 0}, {0.15, 4, 0.5}, {1, 5.5, 0.5}),
			Speed = NumberRange.new(6, 20), Transparency = curve({0, 0.5}, {0.5, 0.85}, {1, 1}), LockedToPart = false,
			EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(60, 60)}), 4})
	end
	local core = Kit.attachment(host)
	core.CFrame = CFrame.new(0, 1.2, 0)
	table.insert(cutLayers, {emitter("HitFlash", core, {Color = ColorSequence.new(PAPER), Size = curve({0, 4.5}, {1, 0}), Brightness = 1.5, LightEmission = 0.6}), 1})
	table.insert(cutLayers, {emitter("HitLines", core, {Color = colors(PAPER, INK), Speed = NumberRange.new(70, 120), Size = curve({0, 5, 1}, {1, 0}),
		SpreadAngle = Vector2.new(180, 10), LightEmission = 0.3}), 14})
	table.insert(cutLayers, {emitter("Splatter", core, {Color = ColorSequence.new(SEAL), Size = curve({0, 1.5}, {1, 3}), Lifetime = NumberRange.new(0.5),
		Orientation = Enum.ParticleOrientation.FacingCamera, LightInfluence = 0}), 1})

	-- The bleed: drops falling off the ring and wash rising.
	local bleed = {}
	for i = 1, 4 do
		local at = Kit.attachment(host)
		place(at, (i - 0.5) / 4)
		at.Position = at.Position + Vector3.new(0, 0.6, 0)
		table.insert(bleed, emitter("Drops", at, {Color = ColorSequence.new(INK), Size = curve({0, 0.9}, {1, 0.6}), Rate = 9,
			Lifetime = NumberRange.new(0.6, 0.9), Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -40, 0), LightInfluence = 0,
			Shape = Enum.ParticleEmitterShape.Box}))
	end
	local mist = emitter("Smoke", core, {Color = ColorSequence.new(WASH), Size = curve({0, 4}, {1, 9}), Rate = 6, Speed = NumberRange.new(2, 5),
		Lifetime = NumberRange.new(1, 1.3), Transparency = curve({0, 0.7}, {1, 1}), Drag = 1, LockedToPart = false,
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(60, 60), Acceleration = Vector3.new(0, 2, 0)})

	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local painted = Plan.painted(elapsed)
		local age = elapsed - T.CutAt
		-- Ink holds until the cut, flashes white for a beat, then fades out
		-- while the band swells a little, the ink running.
		local flash = if age >= 0 then 1 - Kit.ramp(age, 0.03, 0.14) else 0
		local fade = if age >= 0 then 1 - Kit.ramp(age, 0.35, T.Aftermath - 0.2) else 1
		local swell = 1 + (if age >= 0 then Kit.smooth(age / 1.2) * 0.35 else 0)
		for _, arc in ipairs(arcs) do
			local shown = math.clamp((painted - arc.from) / (arc.to - arc.from), 0, 1)
			if shown > 0 then
				local endAlong = arc.from + (arc.to - arc.from) * shown
				place(arc.a0, arc.from)
				place(arc.a1, endAlong)
				local k = control(sweep * shown, R)
				-- Both ends' tangents run along the stroke, so both sizes are positive.
				for _, beam in ipairs(arc.beams) do
					beam.CurveSize0, beam.CurveSize1 = k, k
				end
			end
			local visible = if shown > 0 then 1 else 0
			Kit.opacity(arc.ink, visible * fade * 0.97)
			Kit.opacity(arc.core, visible * fade * 0.92)
			Kit.opacity(arc.wash, visible * fade * 0.4)
			Kit.opacity(arc.flash, visible * flash)
			arc.ink.Width0, arc.ink.Width1 = 4.6 * (1 - 0.62 * arc.from) * swell, 4.6 * (1 - 0.62 * arc.to) * swell
		end
		local radial = place(brush, painted)
		brush.CFrame = CFrame.fromMatrix(radial * R + Vector3.new(0, 0.4, 0), radial, Vector3.yAxis)
		Kit.setEnabled(spatter, elapsed >= T.Windup and painted < 0.98)
		Kit.setEnabled(bleed, age >= 0.15 and age < T.Aftermath - 0.6)
		mist.Enabled = age >= 0.1 and age < T.Aftermath - 0.7
	end, {folder})

	timeline.at(0, function()
		Kit.sound(host, SOUND_SWISH, 0.5, 0.85)
	end)
	timeline.at(T.Windup + T.Stroke * 0.5, function()
		Kit.sound(host, SOUND_SWISH, 0.4, 1.15)
	end)
	timeline.at(T.CutAt, function()
		Kit.burst(cutLayers)
		Kit.sound(host, SOUND_CUT, 0.55, 1.35)
		Kit.sound(host, SOUND_HIT, 0.5, 0.8)
		ImpactFX.hit(centre, {tint = Color3.fromRGB(70, 60, 90), pattern = "triple", shake = 1.8, shakeDuration = 0.45,
			punch = -6, punchDuration = 0.35, radius = 70, silhouetteRadius = T.Reach + 6})
	end)
	return true
end

return VFX
