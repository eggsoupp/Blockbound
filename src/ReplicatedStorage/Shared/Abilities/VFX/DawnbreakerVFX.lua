local CombatAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.CombatAudio)
-- Dawnbreaker, drawn from one message:
--   swing   a golden swipe at the caster's chest as the crescent leaves
--   flight  a wide crescent of light (three layered curved beams) leaving a
--           ribbon afterimage, with slash lines, sparks and flame streaming off
--   burst   a sun-dome where it lands: expanding gold rings round a white
--           core, star flares, rays, gold cubes and shards, a ground ring, and
--           impact frames, a shake and a camera punch for anyone close
-- Every visible effect is an authored particle, trail or textured Beam; Parts
-- are invisible emitter hosts only.
local Plan = require(script.Parent.Parent.DawnbreakerPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.DawnbreakerParticles)

local VFX = {}
local T = Plan.Tuning
local GOLD = Color3.fromRGB(255, 190, 60)
local SUN = Color3.fromRGB(255, 228, 130)
local WHITE = Color3.fromRGB(255, 251, 235)
local AMBER = Color3.fromRGB(255, 128, 32)
local SKY = Color3.fromRGB(130, 225, 255)
local ns, curve, colors = Kit.ns, Kit.curve, Kit.colors
local live = 0
local preloaded = false

-- VFX :D flipbook sheets the curated library does not carry.
local Sheets = {
	-- VFX :D.77: rising light rays. Black background, so fully additive.
	Rays = {
		Texture = "rbxassetid://97915247852729",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		LightEmission = 1,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
	},
}

local SOUND_SWING = CombatAudio.ids.energy_sword
local SOUND_BURST = CombatAudio.ids.punch_heavy2

function VFX.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload(Kit.textures(Library, Sheets), {SOUND_SWING, SOUND_BURST})
end

function VFX.duration()
	return Plan.duration()
end

local function emitter(kind, parent, props)
	return Kit.emitter(if Sheets[kind] then Sheets else Library, kind, parent, props)
end

-- The crescent's frame at `reach`: middle on the line, flat side up.
local function crescentFrame(from, direction, reach)
	local position = from + direction * reach
	local up = if math.abs(direction.Y) > 0.95 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + direction, up)
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.finish) ~= "Vector3" or typeof(payload.normal) ~= "Vector3"
		or type(payload.distance) ~= "number" or type(payload.startedAt) ~= "number" then
		return false
	end
	local distance = math.clamp(payload.distance, 0, T.Range)
	local hitAt = Plan.hitAt(distance)
	local total = hitAt + T.Aftermath
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 4 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local from = payload.origin.Position
	local direction = payload.origin.LookVector
	local finish, normal = payload.finish, payload.normal
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "Dawnbreaker"
	folder.Parent = workspace

	-- Swing ------------------------------------------------------------------
	local swingFrame = crescentFrame(from, direction, 0)
	local swingHost = Kit.host(folder, "Swing", swingFrame)
	-- Top up: VelocityPerpendicular flipbooks lie flat, in the swing's plane.
	local swingFlat = Kit.attachment(swingHost, swingFrame)
	local swingLayers = {
		{emitter("Crescent", swingFlat, {Size = ns(9), Color = ColorSequence.new(SUN), Brightness = 2, EmissionDirection = Enum.NormalId.Top, Lifetime = NumberRange.new(0.2, 0.26)}), 5},
		{emitter("CrescentFlash", swingFlat, {Size = ns(9), Color = ColorSequence.new(WHITE), LightEmission = 0.8, Brightness = 2, EmissionDirection = Enum.NormalId.Top}), 2},
		{emitter("SlashAlpha", swingFlat, {Size = curve({0, 7}, {1, 10}), Color = ColorSequence.new(GOLD), LightEmission = 0.6, Brightness = 2, EmissionDirection = Enum.NormalId.Top}), 2},
		{emitter("Glints", swingFlat, {Color = ColorSequence.new(SUN), EmissionDirection = Enum.NormalId.Front, Brightness = 3, Speed = NumberRange.new(20, 50)}), 10},
		{emitter("Specs", swingFlat, {Color = ColorSequence.new(SUN), LightEmission = 1, Brightness = 3}), 8},
	}

	-- Flight -------------------------------------------------------------------
	-- The crescent stands across its flight, an arch facing whoever threw it:
	-- one curved beam per layer from tip to tip, both control points lifted
	-- (and led forward) so the crown peaks over the line. The host is the
	-- arch's middle; emitters on the part itself spread across its width.
	local width, arch, bow = T.Width, T.Arch, T.Bow
	local body = Kit.host(folder, "Crescent", crescentFrame(from, direction, 0), Vector3.new(width * 0.8, arch * 0.6, 0.6))
	local tipL = Kit.attachment(body)
	local tipR = Kit.attachment(body)
	local crown = Kit.attachment(body)
	-- A cubic's middle lands 3/4 of the way to its control points.
	local lift = Vector3.new(0, arch / 0.75, -bow / 0.75)
	local liftAxis, liftSize = lift.Unit, lift.Magnitude
	local liftUp = liftAxis:Cross(Vector3.xAxis)
	local function layer(kind, color, beamWidth, brightness, zOffset)
		return Kit.beam(body, tipL, tipR, {
			Texture = Library[kind].Texture,
			TextureMode = Enum.TextureMode.Stretch,
			TextureLength = 1,
			FaceCamera = true,
			Segments = 40,
			Color = ColorSequence.new(color),
			Width0 = beamWidth,
			Width1 = beamWidth,
			CurveSize0 = liftSize,
			CurveSize1 = -liftSize,
			LightEmission = 1,
			Brightness = brightness,
			ZOffset = zOffset,
			Enabled = false,
		})
	end
	local arcs = {
		layer("ArcGlow", AMBER, 12, 1.5, 0),
		layer("ArcBody", GOLD, 7.5, 2, 0.1),
		layer("ArcCore", WHITE, 3.6, 2.5, 0.2),
	}
	-- Two ribbons, tip to crown to tip, leave the arch's afterimage.
	local function afterimage(a0, a1)
		return Kit.trail(body, a0, a1, {
			Texture = Library.Trail.Texture,
			TextureMode = Library.Trail.TextureMode,
			TextureLength = Library.Trail.TextureLength,
			Color = colors(SUN, GOLD, AMBER),
			Transparency = curve({0, 0.3}, {0.5, 0.65}, {1, 1}),
			WidthScale = curve({0, 1}, {1, 0.4}),
			Lifetime = 0.16,
			LightEmission = 1,
			Brightness = 2.5,
			FaceCamera = false,
			Enabled = false,
		})
	end
	local trails = {afterimage(tipL, crown), afterimage(crown, tipR)}
	local streaming = {
		emitter("SlashLines", body, {Color = ColorSequence.new(SUN), Rate = 45, Brightness = 1.5, Speed = NumberRange.new(40, 80)}),
		emitter("Sparks", body, {Color = colors(WHITE, GOLD), Rate = 70, Brightness = 2, Acceleration = Vector3.new(0, -60, 0)}),
		emitter("FrontFlame", body, {Color = ColorSequence.new(GOLD), Rate = 26, Brightness = 1.4, Size = curve({0, 4}, {1, 6})}),
		emitter("Glints", body, {Color = ColorSequence.new(SUN), Rate = 22, Brightness = 2.5, Speed = NumberRange.new(10, 30)}),
		emitter("Embers", body, {Color = ColorSequence.new(SUN), Rate = 30, Speed = NumberRange.new(4, 10), Lifetime = NumberRange.new(0.3, 0.5), Size = curve({0, 0}, {0.25, 0.5}, {1, 0})}),
	}
	local flightLight = Kit.light(body, GOLD, 18)

	-- Burst --------------------------------------------------------------------
	local burstFrame = CFrame.lookAt(finish, finish + normal)
	local burstHost = Kit.host(folder, "Burst", burstFrame)
	local core = Kit.attachment(burstHost, burstFrame)
	-- Front along the surface normal: flat rings lie on the surface.
	local surface = Kit.attachment(burstHost, burstFrame)
	local burst = {
		{emitter("HitGlow", core, {Size = curve({0, 0}, {0.3, 12}, {1, 16}), Color = ColorSequence.new(SUN), Brightness = 1.2, Lifetime = NumberRange.new(0.3)}), 1},
		{emitter("GoldLight", core, {Size = curve({0, 10}, {1, 26}), Color = ColorSequence.new(GOLD), Brightness = 1, Transparency = curve({0, 0.3}, {1, 1})}), 2},
		{emitter("GoldRing", core, {Size = curve({0, 2}, {0.45, 20}, {1, 26}), Lifetime = NumberRange.new(0.55), Color = ColorSequence.new(SUN), Brightness = 2, Transparency = curve({0, 0}, {0.7, 0.2}, {1, 1})}), 1},
		{emitter("GoldRingWide", core, {Size = curve({0, 0}, {0.35, 12}, {1, 30}), Color = ColorSequence.new(GOLD), Brightness = 1.5, Lifetime = NumberRange.new(0.5)}), 1},
		{emitter("HitRing", core, {Size = curve({0, 0}, {0.5, 11}, {1, 15}), Color = ColorSequence.new(SKY), Brightness = 2, Lifetime = NumberRange.new(0.4)}), 2},
		{emitter("HitStar", core, {Size = curve({0, 10, 2}, {1, 3, 1}), Color = ColorSequence.new(SUN), Brightness = 1.5, Lifetime = NumberRange.new(0.12, 0.3)}), 4},
		{emitter("GoldStar", core, {Size = curve({0, 9, 2}, {1, 3}), Color = ColorSequence.new(SUN), Brightness = 2, Lifetime = NumberRange.new(0.25, 0.5)}), 6},
		{emitter("Stars", core, {Size = curve({0, 3, 1}, {1, 3, 1}), Color = ColorSequence.new(SUN), Brightness = 2, Speed = NumberRange.new(14, 26), SpreadAngle = Vector2.new(180, 180), Drag = 4, Lifetime = NumberRange.new(0.7, 1.1)}), 8},
		{emitter("GoldSparks", core, {Color = colors(SUN, GOLD), Speed = NumberRange.new(55, 95), Size = curve({0, 1.6, 0.6}, {1, 0}), Brightness = 2, Drag = 4, LockedToPart = false}), 40},
		{emitter("GoldCubes", core, {Color = colors(SUN, AMBER), Speed = NumberRange.new(40, 70), Size = curve({0, 0}, {0.2, 1.3, 0.5}, {1, 0}), Brightness = 1.5, Acceleration = Vector3.new(0, -50, 0), LockedToPart = false}), 30},
		{emitter("Shards", core, {Color = colors(SUN, AMBER), Size = curve({0, 0}, {0.25, 5, 1.5}, {1, 0}), Brightness = 1.2, LightEmission = 1, LockedToPart = false}), 20},
		{emitter("Embers", core, {Color = ColorSequence.new(SUN), Speed = NumberRange.new(20, 40), Size = curve({0, 0}, {0.25, 0.7}, {1, 0}), Lifetime = NumberRange.new(0.5, 0.9), LockedToPart = false}), 30},
		{emitter("Rays", core, {Size = curve({0, 10}, {1, 16}), Lifetime = NumberRange.new(0.45), FlipbookFramerate = NumberRange.new(32), Color = ColorSequence.new(GOLD), Brightness = 1.5, Speed = NumberRange.new(0.01), Transparency = curve({0, 0.1}, {0.7, 0.3}, {1, 1}), ZOffset = -1}), 1},
		{emitter("Smoke", core, {Color = colors(AMBER, Color3.fromRGB(90, 50, 25)), Size = curve({0, 0}, {0.15, 6, 1}, {1, 8, 1}), Transparency = curve({0, 0.35}, {0.5, 0.75}, {1, 1}), Speed = NumberRange.new(12, 40), Brightness = 1, LightEmission = 0, LockedToPart = false}), 16},
		{emitter("Shockwave", surface, {Size = curve({0, 2}, {0.5, 22}, {1, 30}), Color = ColorSequence.new(SUN), Brightness = 2, Lifetime = NumberRange.new(0.5), Transparency = curve({0, 0}, {1, 1})}), 1},
		{emitter("BlastWind", surface, {Size = curve({0, 0}, {0.3, 18, 1}, {1, 26, 2}), Color = ColorSequence.new(WHITE), Brightness = 1, LightEmission = 1, Transparency = curve({0, 1}, {0.2, 0.6}, {1, 1}), SpreadAngle = Vector2.zero}), 4},
		{emitter("WindRing", surface, {Size = curve({0, 2}, {0.5, 12}, {1, 16}), Color = ColorSequence.new(SUN), Brightness = 1.5, Transparency = curve({0, 1}, {0.1, 0.4}, {1, 1}), EmissionDirection = Enum.NormalId.Front}), 3},
	}
	local burstLight = Kit.light(burstHost, GOLD, 45)
	local lingering = {
		emitter("Embers", core, {Color = ColorSequence.new(SUN), Rate = 22, Speed = NumberRange.new(3, 9), Acceleration = Vector3.new(0, 6, 0),
			Size = curve({0, 0}, {0.25, 0.45}, {1, 0}), Lifetime = NumberRange.new(0.8, 1.3), SpreadAngle = Vector2.new(180, 180), LockedToPart = false}),
		emitter("GoldSpecs", core, {Color = ColorSequence.new(SUN), Rate = 12, Speed = NumberRange.new(4, 10), Lifetime = NumberRange.new(0.5, 0.9), Size = curve({0, 0}, {1, 0.6})}),
	}

	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local reach = Plan.reach(elapsed, distance)
		local flying = elapsed >= T.Windup and elapsed < hitAt
		if flying then
			-- Unfolds from half size over its first few studs.
			local s = 0.5 + 0.5 * Kit.smooth((elapsed - T.Windup) / 0.07)
			local half, low = width * 0.5 * s, -arch * 0.5 * s
			tipL.CFrame = CFrame.fromMatrix(Vector3.new(-half, low, bow * s), liftAxis, liftUp)
			tipR.CFrame = CFrame.fromMatrix(Vector3.new(half, low, bow * s), liftAxis, liftUp)
			crown.Position = Vector3.new(0, arch * 0.5 * s, 0)
			for _, arc in ipairs(arcs) do
				arc.CurveSize0, arc.CurveSize1 = liftSize * s, -liftSize * s
			end
			body.CFrame = crescentFrame(from, direction, reach)
		end
		for _, arc in ipairs(arcs) do
			if arc.Enabled ~= flying then arc.Enabled = flying end
		end
		for _, trail in ipairs(trails) do trail.Enabled = flying end
		Kit.setEnabled(streaming, flying)
		flightLight.Brightness = if flying then 2.2 else 0
		local age = elapsed - hitAt
		burstLight.Brightness = if age >= 0 then math.exp(-age * 5) * 4 else 0
		Kit.setEnabled(lingering, age >= 0.15 and age < T.Aftermath - 0.6)
	end, {folder})

	timeline.at(0, function()
		Kit.burst(swingLayers)
		Kit.sound(swingHost, SOUND_SWING, 0.45, 1.35)
		ImpactFX.shake(from, 0.35, 0.22, 40)
	end)
	timeline.at(hitAt, function()
		Kit.burst(burst)
		Kit.sound(burstHost, SOUND_BURST, 0.6, 1.15)
		ImpactFX.hit(finish, {tint = GOLD, pattern = "triple", shake = 1.9, shakeDuration = 0.55, punch = 7, radius = 80})
	end)
	return true
end

return VFX
