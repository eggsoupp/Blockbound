local CombatAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.CombatAudio)
-- Deluge, drawn from one message:
--   gather  water spirals into a swelling orb over the caster
--   flight  the orb arcs to the target, shedding spray and a wet ribbon
--   splash  a towering burst of toon water, spray thrown high, rings on the
--           ground, and impact frames, a shake and a punch for anyone close
--   surge   three widening rings of geysers race out from the splash
-- Every visible effect is an authored particle, trail or flipbook; Parts are
-- invisible emitter hosts only.
local Plan = require(script.Parent.Parent.DelugePlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Library = require(script.Parent.DelugeParticles)

local VFX = {}
local T = Plan.Tuning
local DEEP = Color3.fromRGB(18, 96, 220)
local SEA = Color3.fromRGB(40, 165, 255)
local TEAL = Color3.fromRGB(70, 225, 240)
local FOAM = Color3.fromRGB(215, 245, 255)
local ns, curve, colors = Kit.ns, Kit.curve, Kit.colors
local live = 0
local preloaded = false

-- VFX :D flipbook sheets the curated library does not carry.
local Sheets = {
	-- VFX :D.12 Images/waterWave: a swirling water ring on black, so additive.
	Swirl = {
		Texture = "rbxassetid://74684319694540",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		LightEmission = 1,
	},
	-- VFX :D.165 Images/Mist1.
	Mist = {
		Texture = "rbxassetid://15398191874",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D.111 Images/Water_ripple: a ring of foam.
	Foam = {
		Texture = "rbxassetid://15011478368",
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
	},
}

local SOUND_GATHER = CombatAudio.ids.bubbles
local SOUND_SPLASH = "impact.water"
local SOUND_BOOM = CombatAudio.ids.boom_deep1

function VFX.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload(Kit.textures(Library, Sheets), {SOUND_GATHER, SOUND_SPLASH, SOUND_BOOM})
end

function VFX.duration()
	return Plan.duration()
end

local function emitter(kind, parent, props)
	return Kit.emitter(if Sheets[kind] then Sheets else Library, kind, parent, props)
end

function VFX.play(payload, scope)
	if typeof(payload.from) ~= "Vector3" or typeof(payload.landing) ~= "Vector3" or typeof(payload.normal) ~= "Vector3"
		or type(payload.startedAt) ~= "number" then
		return false
	end
	local total = Plan.surgeAt(#T.SurgeRings) + T.Aftermath
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 4 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local from, landing, normal = payload.from, payload.landing, payload.normal
	local hitAt = Plan.hitAt()
	local random = Random.new(payload.seed or 11)
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "Deluge"
	folder.Parent = workspace

	-- Orb ---------------------------------------------------------------------
	-- One host for the gather and the flight: a sphere-shaped part, so the
	-- gathering water starts on its surface and closes in.
	local orb = Kit.host(folder, "Orb", CFrame.new(from), Vector3.one * 9)
	local core = Kit.attachment(orb)
	local swirl = emitter("Swirl", core, {
		Size = ns(2), Lifetime = NumberRange.new(0.35, 0.45), Rate = 22, Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), Color = colors(SEA, DEEP),
		Brightness = 0.7, FlipbookFramerate = NumberRange.new(40), LockedToPart = true, ZOffset = 0.5,
	})
	local blob = emitter("LiquidColor", core, {
		Size = ns(2), Lifetime = NumberRange.new(0.3, 0.4), Rate = 12, Rotation = NumberRange.new(0, 360),
		Color = colors(SEA, DEEP), LightInfluence = 0, Brightness = 1, LockedToPart = true,
	})
	local inflow = emitter("Spray", orb, {
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Speed = NumberRange.new(14, 22), Lifetime = NumberRange.new(0.22, 0.3),
		Acceleration = Vector3.zero, Size = curve({0, 1.4, 0.3}, {1, 0}), Color = ColorSequence.new(FOAM),
		Transparency = curve({0, 1}, {0.3, 0.2}, {1, 0.6}), LightEmission = 0.5, LightInfluence = 0, Rate = 60, LockedToPart = true,
	})
	local pops = emitter("BubblePop", orb, {
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Size = ns(1.4), Color = ColorSequence.new(FOAM), Rate = 12, LightInfluence = 0, LockedToPart = true,
	})
	local spray = emitter("Spray", core, {
		EmissionDirection = Enum.NormalId.Back, SpreadAngle = Vector2.new(35, 35), Speed = NumberRange.new(4, 12),
		Acceleration = Vector3.new(0, -60, 0), Size = curve({0, 1.2, 0.3}, {1, 0}), Color = colors(FOAM, SEA),
		Transparency = curve({0, 0.2}, {1, 1}), LightInfluence = 0, LightEmission = 0.4, Lifetime = NumberRange.new(0.3, 0.55), Rate = 70,
	})
	local mist = emitter("SprayMist", core, {
		EmissionDirection = Enum.NormalId.Back, Speed = NumberRange.new(2, 6), Acceleration = Vector3.new(0, -8, 0),
		Size = curve({0, 1.5}, {1, 3.5, 0.5}), Color = ColorSequence.new(FOAM), LightInfluence = 0, Rate = 14,
	})
	local top = Kit.attachment(orb); top.Position = Vector3.new(0, 1.6, 0)
	local bottom = Kit.attachment(orb); bottom.Position = Vector3.new(0, -1.6, 0)
	local ribbon = Kit.trail(orb, top, bottom, {
		Texture = Library.Trail.Texture, TextureMode = Library.Trail.TextureMode, TextureLength = Library.Trail.TextureLength,
		Color = colors(FOAM, SEA, DEEP), Transparency = curve({0, 0.2}, {1, 1}), WidthScale = curve({0, 1}, {1, 0.3}),
		Lifetime = 0.22, LightEmission = 0.8, Brightness = 1.6, FaceCamera = true, Enabled = false,
	})
	local orbLight = Kit.light(orb, SEA, 16)

	-- Splash ------------------------------------------------------------------
	local splashFrame = CFrame.lookAt(landing, landing + normal)
	local base = Kit.host(folder, "Splash", splashFrame)
	-- Front along the normal: flat rings lie on the ground.
	local flat = Kit.attachment(base, splashFrame * CFrame.new(0, 0, -0.15))
	local up = Kit.attachment(base, CFrame.new(landing + normal * 0.5) * CFrame.fromMatrix(Vector3.zero, normal:Cross(Vector3.zAxis).Magnitude > 0.1 and normal:Cross(Vector3.zAxis).Unit or Vector3.xAxis, normal))
	local high = Kit.attachment(base, CFrame.new(landing + normal * 6))
	local splash = {
		-- The tower: toon water thrown straight up, slowing as it climbs.
		{emitter("LiquidAlpha", up, {Size = curve({0, 6}, {1, 11}), Rotation = NumberRange.new(-25, 25), Color = colors(FOAM, TEAL),
			LightInfluence = 0, Lifetime = NumberRange.new(0.55, 0.75), Speed = NumberRange.new(14, 30), SpreadAngle = Vector2.new(8, 8),
			Acceleration = Vector3.new(0, -22, 0), Drag = 1.5, ZOffset = 1}), 5},
		{emitter("LiquidColor", high, {Size = curve({0, 9}, {1, 15}), Rotation = NumberRange.new(0, 360), Color = colors(SEA, DEEP),
			LightInfluence = 0, Lifetime = NumberRange.new(0.65, 0.8), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(60, 60)}), 2},
		{emitter("LiquidAlpha", high, {Size = curve({0, 8}, {1, 13}), Rotation = NumberRange.new(0, 360), Color = colors(TEAL, SEA),
			LightInfluence = 0, Lifetime = NumberRange.new(0.6, 0.75), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(60, 60)}), 2},
		{emitter("PixelBurst", up, {Size = curve({0, 10}, {1, 14}), Rotation = NumberRange.new(0, 360), Color = colors(FOAM, SEA), LightInfluence = 0}), 2},
		{emitter("Spray", up, {SpreadAngle = Vector2.new(55, 55), Speed = NumberRange.new(40, 78), Acceleration = Vector3.new(0, -95, 0),
			Size = curve({0, 2, 0.6}, {1, 0}), Color = colors(FOAM, SEA), LightInfluence = 0, LightEmission = 0.3,
			Lifetime = NumberRange.new(0.6, 1), Transparency = curve({0, 0}, {0.8, 0.2}, {1, 1})}), 70},
		{emitter("SprayMist", up, {SpreadAngle = Vector2.new(70, 70), Speed = NumberRange.new(16, 34), Acceleration = Vector3.new(0, -30, 0),
			Size = curve({0, 2}, {1, 6, 1}), Color = ColorSequence.new(FOAM), LightInfluence = 0, Lifetime = NumberRange.new(0.8, 1.3)}), 24},
		{emitter("BubblePop", up, {Shape = Enum.ParticleEmitterShape.Sphere, Size = ns(2), Color = ColorSequence.new(FOAM), LightInfluence = 0,
			Speed = NumberRange.new(8, 18), SpreadAngle = Vector2.new(80, 80), Lifetime = NumberRange.new(0.5, 0.7)}), 12},
		{emitter("Shockwave", flat, {Size = curve({0, 4}, {0.5, 24}, {1, 30}), Color = ColorSequence.new(TEAL), Brightness = 1.5,
			Transparency = curve({0, 0.1}, {1, 1}), Lifetime = NumberRange.new(0.5)}), 1},
		{emitter("GroundRing", flat, {Color = ColorSequence.new(FOAM), Size = curve({0, 6, 1}, {0.4, 20, 1}, {1, 26, 1})}), 2},
		{emitter("Foam", flat, {Size = curve({0, 8}, {1, 26}), Lifetime = NumberRange.new(0.7), FlipbookFramerate = NumberRange.new(22),
			Color = colors(FOAM, SEA), LightInfluence = 0, Speed = NumberRange.new(0.01), Transparency = curve({0, 0}, {0.7, 0.2}, {1, 1})}), 1},
		{emitter("Ripple", flat, {Size = ns(26), Color = colors(FOAM, SEA), LightInfluence = 0, EmissionDirection = Enum.NormalId.Front}), 1},
	}
	local splashLight = Kit.light(base, SEA, 40)
	local lingering = {
		emitter("Mist", high, {Size = curve({0, 6}, {1, 12}), Lifetime = NumberRange.new(1, 1.4), Rate = 7, Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(180, 180), Color = ColorSequence.new(FOAM), Transparency = curve({0, 1}, {0.3, 0.6}, {1, 1}),
			LightInfluence = 0.5, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20)}),
		emitter("Sparkle", up, {Color = ColorSequence.new(FOAM), Rate = 14, Speed = NumberRange.new(4, 14), SpreadAngle = Vector2.new(70, 70),
			Lifetime = NumberRange.new(0.4, 0.8)}),
		emitter("Spray", up, {SpreadAngle = Vector2.new(25, 25), Speed = NumberRange.new(14, 26), Acceleration = Vector3.new(0, -70, 0),
			Size = curve({0, 1.2, 0.3}, {1, 0}), Color = colors(FOAM, SEA), LightInfluence = 0, Rate = 30, Lifetime = NumberRange.new(0.5, 0.8)}),
	}

	-- Surge ---------------------------------------------------------------------
	-- Geyser spots on each ring, dropped onto whatever ground is under them.
	local params = Kit.rayParams({folder})
	local rings = {}
	for index, radius in ipairs(T.SurgeRings) do
		local count = math.round(radius * 0.75)
		local spin = random:NextNumber(0, math.pi * 2)
		local spots = {}
		for i = 1, count do
			local angle = spin + (i / count) * math.pi * 2 + random:NextNumber(-0.12, 0.12)
			local around = landing + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
			local hit = workspace:Raycast(around + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), params)
			if hit then
				-- Flipbooks are centred on their emitter, so the splash sits raised.
				table.insert(spots, {
					ground = Kit.attachment(base, CFrame.new(hit.Position + Vector3.new(0, 0.3, 0))),
					raised = Kit.attachment(base, CFrame.new(hit.Position + Vector3.new(0, 4.5, 0))),
				})
			end
		end
		local ringFlat = Kit.attachment(base, splashFrame * CFrame.new(0, 0, -0.1))
		rings[index] = {
			spots = spots,
			column = emitter("LiquidAlpha", base, {Size = curve({0, 3.5}, {1, 6.5}), Rotation = NumberRange.new(-20, 20), Color = colors(FOAM, TEAL),
				LightInfluence = 0, Lifetime = NumberRange.new(0.45, 0.6), Speed = NumberRange.new(10, 18), SpreadAngle = Vector2.new(6, 6),
				Acceleration = Vector3.new(0, -26, 0), Drag = 1.5}),
			toon = emitter("SplashToon", base, {Size = ns(7), Color = colors(TEAL, SEA), LightInfluence = 0, Rotation = NumberRange.new(-20, 20),
				EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(0.01), Orientation = Enum.ParticleOrientation.FacingCameraWorldUp}),
			jet = emitter("Spray", base, {SpreadAngle = Vector2.new(18, 18), Speed = NumberRange.new(24, 40), Acceleration = Vector3.new(0, -90, 0),
				Size = curve({0, 1.5, 0.4}, {1, 0}), Color = colors(FOAM, SEA), LightInfluence = 0, Lifetime = NumberRange.new(0.4, 0.7)}),
			foam = emitter("Foam", ringFlat, {Size = curve({0, radius * 1.6}, {1, radius * 2.3}), Lifetime = NumberRange.new(0.6),
				FlipbookFramerate = NumberRange.new(24), Color = colors(FOAM, TEAL), LightInfluence = 0, Speed = NumberRange.new(0.01),
				Transparency = curve({0, 0.1}, {0.7, 0.3}, {1, 1})}),
		}
	end

	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		if elapsed < hitAt then
			local position
			if elapsed < T.Gather then
				position = from
				local k = Kit.smooth(elapsed / T.Gather)
				swirl.Size = ns(2 + 3.5 * k)
				blob.Size = ns(1.5 + 3 * k)
			else
				local t = (elapsed - T.Gather) / T.Flight
				position = Plan.arc(from, landing, t)
				local ahead = Plan.arc(from, landing, math.min(t + 0.05, 1))
				local heading = if (ahead - position).Magnitude > 0.05 then ahead else position + Vector3.new(0, -1, 0)
				orb.CFrame = CFrame.lookAt(position, heading)
				swirl.Size, blob.Size = ns(5.5), ns(4.5)
			end
			if elapsed < T.Gather then orb.CFrame = CFrame.new(position) end
		end
		local gathering = elapsed < T.Gather
		local flying = elapsed >= T.Gather and elapsed < hitAt
		swirl.Enabled = elapsed < hitAt
		blob.Enabled = elapsed < hitAt
		inflow.Enabled = gathering
		pops.Enabled = gathering
		spray.Enabled = flying
		mist.Enabled = flying
		ribbon.Enabled = flying
		orbLight.Brightness = if elapsed < hitAt then 0.8 + Kit.smooth(elapsed / T.Gather) else 0
		local age = elapsed - hitAt
		splashLight.Brightness = if age >= 0 then math.exp(-age * 5) * 3 else 0
		Kit.setEnabled(lingering, age >= 0.1 and age < T.Aftermath - 0.5)
	end, {folder})

	timeline.at(0, function()
		Kit.sound(orb, SOUND_GATHER, 0.5, 1.35)
	end)
	timeline.at(hitAt, function()
		Kit.burst(splash)
		Kit.sound(base, SOUND_SPLASH, 0.9, 0.9)
		Kit.sound(base, SOUND_BOOM, 0.35, 0.75)
		ImpactFX.hit(landing, {tint = SEA, pattern = "double", shake = 1.7, shakeDuration = 0.5, punch = 6, radius = 75})
	end)
	for index, ring in ipairs(rings) do
		timeline.at(Plan.surgeAt(index), function()
			-- Emit places particles where the emitter is when the frame simulates,
			-- so every geyser has its own copies rather than one moved around.
			for _, spot in ipairs(ring.spots) do
				local column, toon, jet = ring.column:Clone(), ring.toon:Clone(), ring.jet:Clone()
				column.Parent, toon.Parent, jet.Parent = spot.ground, spot.raised, spot.ground
				column:Emit(2)
				toon:Emit(1)
				jet:Emit(5)
			end
			ring.foam:Emit(1)
			Kit.sound(base, SOUND_SPLASH, 0.35, 1.15 + index * 0.1)
			ImpactFX.shake(landing, 0.55, 0.25, 60)
		end)
	end
	return true
end

return VFX
