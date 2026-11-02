local ImportedAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.DownloadedSounds)
-- Blossom Road, drawn from one message:
--   gust    a ribbon of petals runs out along the lane from the caster's feet
--   blooms  flowers burst up behind it one after another, each throwing
--           petals and sparkles, with a rising chime
--   finale  the last flower blooms huge: a petal storm, a ring and a glow,
--           with impact frames, a shake and a punch
--   road    the lane stays as a soft pink road edged in light, petals and
--           mending sparkles drifting up from it, then fades
-- Every visible effect is an authored particle, trail or textured Beam; Parts
-- are invisible emitter hosts only.
local Plan = require(script.Parent.Parent.BlossomPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.BlossomParticles)

local VFX = {}
local T = Plan.Tuning
local SAKURA = Color3.fromRGB(255, 172, 206)
local BLUSH = Color3.fromRGB(255, 112, 166)
local CREAM = Color3.fromRGB(255, 240, 246)
local POLLEN = Color3.fromRGB(255, 226, 140)
local MEND = Color3.fromRGB(150, 255, 170)
local ns, curve, colors = Kit.ns, Kit.curve, Kit.colors
local live = 0
local preloaded = false

-- VFX :D flipbook sheets and pack textures the curated library does not carry.
local Sheets = {
	-- VFX :D.20 Images/flowerflip: a blossom opening.
	Flower = {
		Texture = "rbxassetid://16940454301",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D.1 Images/sparkle_flip: four-point sparkles.
	Sparkle = {
		Texture = "rbxassetid://115317702570755",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		LightEmission = 1,
	},
	-- Slash VFX Trail2: a soft band, the road and its glowing edges.
	Band = {Texture = "rbxassetid://16892374733"},
}

local SOUND_GUST = ImportedAudio.ability_magic_cast
local SOUND_BLOOM = ImportedAudio.ability_magic_glow
local SOUND_FINALE = ImportedAudio.ability_magic_poof

function VFX.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload(Kit.textures(Library, Sheets), {SOUND_GUST, SOUND_BLOOM, SOUND_FINALE})
end

function VFX.duration()
	return Plan.duration()
end

local function emitter(kind, parent, props)
	return Kit.emitter(if Sheets[kind] then Sheets else Library, kind, parent, props)
end

-- Petals tumbling: the toon petal flipbook loops so each petal flutters.
local function petals(parent, props)
	local base = {
		Color = colors(SAKURA, BLUSH), Size = curve({0, 0}, {0.1, 1.1, 0.4}, {0.85, 0.9, 0.3}, {1, 0}),
		Lifetime = NumberRange.new(1.2, 1.9), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, -5, 0), Drag = 2, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-220, 220),
		LightInfluence = 0, LightEmission = 0, Brightness = 1, FlipbookMode = Enum.ParticleFlipbookMode.Loop,
		FlipbookFramerate = NumberRange.new(10, 18), EmissionDirection = Enum.NormalId.Top, LockedToPart = false,
	}
	for key, value in pairs(props or {}) do base[key] = value end
	return emitter("Petal", parent, base)
end

-- A flat ribbon on the ground between two points (width runs across the lane).
local function groundRibbon(parent, from, to, width, color, emission)
	local forward = Kit.flat(to - from)
	local side = forward:Cross(Vector3.yAxis).Unit
	local a0 = Kit.attachment(parent, CFrame.fromMatrix(from, forward, side))
	local a1 = Kit.attachment(parent, CFrame.fromMatrix(to, forward, side))
	return Kit.beam(parent, a0, a1, {
		Texture = Sheets.Band.Texture, TextureMode = Enum.TextureMode.Stretch, TextureLength = 1, FaceCamera = false,
		Segments = 2, Width0 = width, Width1 = width, Color = ColorSequence.new(color), LightEmission = emission,
		Brightness = 1.6, ZOffset = 0.1, Transparency = ns(1), Enabled = false,
	})
end

function VFX.play(payload, scope)
	if typeof(payload.feet) ~= "Vector3" or typeof(payload.direction) ~= "Vector3" or type(payload.points) ~= "table"
		or #payload.points == 0 or type(payload.startedAt) ~= "number" then
		return false
	end
	local points = {}
	for i, p in ipairs(payload.points) do
		if typeof(p) ~= "Vector3" or i > T.Blooms then return false end
		points[i] = p
	end
	local finaleAt = Plan.finaleAt(#points)
	local roadEnd = finaleAt + T.Road
	local total = roadEnd + 0.4
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 3 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local feet, direction = payload.feet, Plan.flat(payload.direction)
	local up = Vector3.yAxis
	local last = points[#points]
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "BlossomRoad"
	folder.Parent = workspace

	-- Cast ---------------------------------------------------------------------
	local castHost = Kit.host(folder, "Cast", CFrame.new(feet))
	local castAt = Kit.attachment(castHost, CFrame.new(feet + up * 1.5))
	local cast = {
		{petals(castAt, {Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(75, 75)}), 24},
		{emitter("Sparkle", castAt, {Color = colors(CREAM, SAKURA), Size = ns(3), Lifetime = NumberRange.new(0.5),
			FlipbookFramerate = NumberRange.new(30), Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(90, 90), LightInfluence = 0}), 4},
		{emitter("StarLight", castAt, {Color = ColorSequence.new(SAKURA), Size = curve({0, 4}, {1, 9}), Lifetime = NumberRange.new(0.5), Brightness = 1}), 1},
	}

	-- Gust: runs along the lane just ahead of the blooms.
	local gust = Kit.host(folder, "Gust", CFrame.new(feet + up * 1.4))
	local gustTop = Kit.attachment(gust); gustTop.Position = Vector3.new(0, 1.1, 0)
	local gustBottom = Kit.attachment(gust); gustBottom.Position = Vector3.new(0, -1.1, 0)
	local gustTrail = Kit.trail(gust, gustTop, gustBottom, {
		Texture = Library.Trail.Texture, TextureMode = Library.Trail.TextureMode, TextureLength = Library.Trail.TextureLength,
		Color = colors(CREAM, SAKURA, BLUSH), Transparency = curve({0, 0.2}, {1, 1}), WidthScale = curve({0, 1}, {1, 0.4}),
		Lifetime = 0.35, LightEmission = 0.6, Brightness = 1.5, FaceCamera = true, Enabled = false,
	})
	local gustAt = Kit.attachment(gust)
	local gustEmitters = {
		petals(gustAt, {Rate = 80, Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(0.9, 1.5)}),
		emitter("Pollen", gustAt, {Color = ColorSequence.new(POLLEN), Rate = 30, Speed = NumberRange.new(2, 6), Lifetime = NumberRange.new(0.5, 0.9),
			Size = curve({0, 0}, {1, 0.5}), LockedToPart = false}),
	}
	local function lanePoint(t)
		-- Feet to first bloom to last, by distance travelled.
		local path = {feet, table.unpack(points)}
		local lengths, sum = {}, 0
		for i = 1, #path - 1 do
			lengths[i] = (path[i + 1] - path[i]).Magnitude
			sum += lengths[i]
		end
		local want = t * sum
		for i = 1, #path - 1 do
			if want <= lengths[i] or i == #path - 1 then
				return path[i]:Lerp(path[i + 1], math.clamp(want / math.max(lengths[i], 1e-3), 0, 1))
			end
			want -= lengths[i]
		end
		return last
	end

	-- Blooms -------------------------------------------------------------------
	local blooms = {}
	for index, point in ipairs(points) do
		local host = Kit.host(folder, "Bloom" .. index, CFrame.new(point))
		local at = Kit.attachment(host, CFrame.new(point + up * 2.4))
		local low = Kit.attachment(host, CFrame.new(point + up * 0.6))
		local size = 7.5 + index * 0.3
		blooms[index] = {
			host = host,
			layers = {
				{emitter("Flower", at, {Color = colors(SAKURA, BLUSH), Size = curve({0, size * 0.5}, {0.3, size}, {1, size * 1.1}),
					Lifetime = NumberRange.new(0.9), FlipbookFramerate = NumberRange.new(30), LightInfluence = 0, LightEmission = 0, ZOffset = 0.5,
					Rotation = NumberRange.new(-25, 25), Speed = NumberRange.new(0.01), Transparency = curve({0, 0}, {0.75, 0}, {1, 1})}), 1},
				{emitter("Flower", at, {Color = ColorSequence.new(CREAM), Size = curve({0, size * 0.25}, {1, size * 0.55}),
					Lifetime = NumberRange.new(0.75), FlipbookFramerate = NumberRange.new(36), LightInfluence = 0, LightEmission = 0.3,
					Rotation = NumberRange.new(20, 70), Speed = NumberRange.new(0.01), ZOffset = 0.8}), 1},
				{petals(low, {Speed = NumberRange.new(10, 20), SpreadAngle = Vector2.new(55, 55)}), 14},
				{emitter("Sparkle", at, {Color = colors(CREAM, SAKURA), Size = ns(2.2), Lifetime = NumberRange.new(0.45, 0.6),
					FlipbookFramerate = NumberRange.new(30), Speed = NumberRange.new(5, 10), SpreadAngle = Vector2.new(120, 120), LightInfluence = 0}), 3},
				{emitter("StarLight", at, {Color = ColorSequence.new(SAKURA), Size = curve({0, 4}, {1, 8}), Lifetime = NumberRange.new(0.45), Brightness = 0.8}), 1},
				{emitter("Pollen", at, {Color = ColorSequence.new(POLLEN), Speed = NumberRange.new(8, 16), Lifetime = NumberRange.new(0.4, 0.7),
					Size = curve({0, 0}, {1, 0.6}), LockedToPart = false}), 8},
			},
		}
	end

	-- Finale -------------------------------------------------------------------
	local finaleHost = Kit.host(folder, "Finale", CFrame.new(last))
	local crown = Kit.attachment(finaleHost, CFrame.new(last + up * 4))
	local base = Kit.attachment(finaleHost, CFrame.new(last + up * 0.8))
	local finale = {
		{emitter("Flower", crown, {Color = colors(SAKURA, BLUSH), Size = curve({0, 6}, {0.3, 18}, {1, 20}), Lifetime = NumberRange.new(1.1),
			FlipbookFramerate = NumberRange.new(24), LightInfluence = 0, LightEmission = 0, ZOffset = 0.5, Speed = NumberRange.new(0.01),
			Transparency = curve({0, 0}, {0.75, 0}, {1, 1})}), 1},
		{emitter("Flower", crown, {Color = ColorSequence.new(CREAM), Size = curve({0, 4}, {1, 10}), Lifetime = NumberRange.new(0.9),
			FlipbookFramerate = NumberRange.new(28), LightInfluence = 0, LightEmission = 0.3, Rotation = NumberRange.new(30, 60),
			Speed = NumberRange.new(0.01), ZOffset = 0.8}), 1},
		{petals(base, {Speed = NumberRange.new(18, 36), SpreadAngle = Vector2.new(80, 80), Lifetime = NumberRange.new(1.4, 2.2),
			Size = curve({0, 0}, {0.08, 1.4, 0.5}, {0.85, 1.1, 0.4}, {1, 0})}), 60},
		{emitter("Shockwave", crown, {Color = ColorSequence.new(SAKURA), Orientation = Enum.ParticleOrientation.FacingCamera,
			Size = curve({0, 4}, {0.5, 22}, {1, 28}), Brightness = 1.5, Lifetime = NumberRange.new(0.55), Transparency = curve({0, 0}, {1, 1})}), 1},
		{emitter("HitGlow", crown, {Color = ColorSequence.new(SAKURA), Size = curve({0, 0}, {0.3, 9}, {1, 12}), Brightness = 0.7}), 1},
		{emitter("HitStar", crown, {Color = colors(CREAM, SAKURA), Size = curve({0, 10, 2}, {1, 3}), Brightness = 1.6,
			Lifetime = NumberRange.new(0.15, 0.3)}), 4},
		{emitter("Sparkle", crown, {Color = colors(CREAM, SAKURA), Size = ns(3.5), Lifetime = NumberRange.new(0.6, 0.8),
			FlipbookFramerate = NumberRange.new(24), Speed = NumberRange.new(12, 22), SpreadAngle = Vector2.new(180, 180),
			Drag = 3, LightInfluence = 0}), 10},
		{emitter("Glints", crown, {Color = ColorSequence.new(SAKURA), EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(180, 180), Speed = NumberRange.new(20, 50), Brightness = 2}), 20},
		{emitter("StarLight", crown, {Color = ColorSequence.new(SAKURA), Size = curve({0, 10}, {1, 22}), Lifetime = NumberRange.new(0.7), Brightness = 0.5}), 1},
	}
	local finaleLight = Kit.light(finaleHost, SAKURA, 36)

	-- Road ---------------------------------------------------------------------
	local road = Kit.host(folder, "Road", CFrame.new(feet))
	local ribbons = {}
	local path = {feet, table.unpack(points)}
	for i = 1, #path - 1 do
		local a, b = path[i] + up * 0.15, path[i + 1] + up * 0.15
		local side = Kit.flat(b - a):Cross(up).Unit
		table.insert(ribbons, {beam = groundRibbon(road, a, b, T.RoadWidth * 1.8, SAKURA, 0.6), opacity = 0.35})
		table.insert(ribbons, {beam = groundRibbon(road, a + side * T.RoadWidth * 0.85, b + side * T.RoadWidth * 0.85, 1.6, SAKURA, 1), opacity = 0.85})
		table.insert(ribbons, {beam = groundRibbon(road, a - side * T.RoadWidth * 0.85, b - side * T.RoadWidth * 0.85, 1.6, SAKURA, 1), opacity = 0.85})
	end
	-- One box-shaped host per segment, so drift rises from the whole road.
	local drift = {}
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local mid = (a + b) / 2 + up * 0.4
		local segment = Kit.host(folder, "RoadSegment" .. i, CFrame.lookAt(mid, mid + Kit.flat(b - a)),
			Vector3.new(T.RoadWidth * 1.6, 0.3, math.max((b - a).Magnitude, 1)))
		table.insert(drift, petals(segment, {Rate = 5, Speed = NumberRange.new(1, 3), Acceleration = Vector3.new(0, 1.5, 0),
			Lifetime = NumberRange.new(1.4, 2), Shape = Enum.ParticleEmitterShape.Box, Size = curve({0, 0}, {0.15, 0.8, 0.3}, {0.85, 0.7}, {1, 0})}))
		table.insert(drift, emitter("Sparkle", segment, {Color = colors(MEND, CREAM), Size = ns(1.4), Rate = 2.5, Lifetime = NumberRange.new(0.7, 1),
			FlipbookFramerate = NumberRange.new(18), Speed = NumberRange.new(1.5, 3), EmissionDirection = Enum.NormalId.Top,
			Shape = Enum.ParticleEmitterShape.Box, LightInfluence = 0}))
		table.insert(drift, emitter("Health", segment, {Color = ColorSequence.new(MEND), Size = curve({0, 0}, {0.2, 0.7}, {0.8, 0.7}, {1, 0}),
			Rate = 1.2, Speed = NumberRange.new(2, 4), Lifetime = NumberRange.new(0.9, 1.2), EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(10, 10), LightEmission = 0.4, Brightness = 1.5, LockedToPart = false, Shape = Enum.ParticleEmitterShape.Box}))
	end

	local gustEnd = Plan.bloomAt(#points)
	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local running = elapsed < gustEnd + 0.05
		if running then
			gust.CFrame = CFrame.lookAt(lanePoint(math.clamp(elapsed / gustEnd, 0, 1)) + up * 1.4, lanePoint(1) + up * 1.4)
		end
		gustTrail.Enabled = running
		Kit.setEnabled(gustEmitters, running)
		-- The road fades in behind the gust and out at the end.
		local shown = Kit.ramp(elapsed, 0.1, finaleAt) * (1 - Kit.ramp(elapsed, roadEnd - 0.7, roadEnd))
		for _, ribbon in ipairs(ribbons) do
			Kit.opacity(ribbon.beam, shown * ribbon.opacity * (0.85 + 0.15 * math.sin(elapsed * 4)))
		end
		Kit.setEnabled(drift, elapsed >= finaleAt and elapsed < roadEnd - 0.6)
		local age = elapsed - finaleAt
		finaleLight.Brightness = if age >= 0 then math.exp(-age * 4) * 3 else 0
	end, {folder})

	timeline.at(0, function()
		Kit.burst(cast)
		Kit.sound(castHost, SOUND_GUST, 0.45, 1.5)
	end)
	for index, bloom in ipairs(blooms) do
		timeline.at(Plan.bloomAt(index), function()
			Kit.burst(bloom.layers)
			Kit.sound(bloom.host, SOUND_BLOOM, 0.22, 0.9 + index * 0.07)
			ImpactFX.shake(points[index], 0.25, 0.15, 45)
		end)
	end
	timeline.at(finaleAt, function()
		Kit.burst(finale)
		Kit.sound(finaleHost, SOUND_FINALE, 0.5, 1.4)
		ImpactFX.hit(last, {tint = BLUSH, pattern = "double", shake = 1.5, shakeDuration = 0.45, punch = 5, radius = 75})
	end)
	return true
end

return VFX
