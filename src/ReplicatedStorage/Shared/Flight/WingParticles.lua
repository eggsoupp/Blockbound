--[[
	WingParticles

	The particle effects worn wings give off, curated from the SoulShroud
	Ultimate VFX Pack (Studio place "SoulShroud Ultimate VFX Pack V1.9", folder
	Workspace["SoulShroud VFX Packs"]["SoulShroud VFX Pack #2"]
	["Spellcasting + Small Impact VFX"]). Each template copies one authored
	emitter (its pack path above it); the textures are the pack's own, and only
	colour, size, speed and rate are changed to fit a 2-stud wing.
	Code-backed so a Rojo install does not depend on the pack.

	StarterPlayerScripts.WingAnimator uses them three ways:

	  trail     on each wing's outer piece (the Fan, or a fairy's lobes), an
	            emitter whose Rate follows the wings: a little at rest for the
	            magical pairs, more in the air, most at speed
	  gust      a soft swirl of air pushed down from each wing at the bottom of
	            a full stroke (hover, take-off, cruise)
	  takeoff   a ring of air and a swirl at the feet, and a puff of dust, on
	            take-off

	WingParticles.make(name, overrides) builds an emitter from a template;
	WingParticles.Styles[itemName] picks the trails and tints per pair.
]]

local function seq(...)
	local points = {}
	for _, p in ipairs({ ... }) do
		table.insert(points, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
	end
	return NumberSequence.new(points)
end
local rgb = Color3.fromRGB
local function tint(a, b)
	return ColorSequence.new(a, b or a)
end

local T = {}

-- Aura.ParticleEmitter (126447607395557): rising motes, retuned to drift.
T.Mote = {
	Texture = "rbxassetid://126447607395557",
	Size = seq({ 0, 0 }, { 0.2, 0.48, 0.12 }, { 0.8, 0.27 }, { 1, 0 }),
	ZOffset = 0.8,
	Transparency = seq({ 0, 1 }, { 0.25, 0 }, { 1, 1 }),
	Lifetime = NumberRange.new(0.7, 1.1),
	Speed = NumberRange.new(0.5, 2),
	Rotation = NumberRange.new(-90, -90),
	SpreadAngle = Vector2.new(360, 360),
	Acceleration = Vector3.new(0, 3, 0),
	Drag = 2,
	LightEmission = 1,
	LightInfluence = 0,
	Brightness = 1.6,
	Orientation = Enum.ParticleOrientation.FacingCamera,
}

-- Aura.ParticleEmitter (81480496984776): the second mote, for falling dust.
T.Dust = {
	Texture = "rbxassetid://81480496984776",
	Size = seq({ 0, 0 }, { 0.2, 0.4, 0.12 }, { 1, 0 }),
	ZOffset = 0.8,
	Transparency = seq({ 0, 1 }, { 0.2, 0 }, { 1, 1 }),
	Lifetime = NumberRange.new(0.8, 1.3),
	Speed = NumberRange.new(0.3, 1.2),
	Rotation = NumberRange.new(-90, -90),
	SpreadAngle = Vector2.new(360, 360),
	Acceleration = Vector3.new(0, -3, 0),
	Drag = 1.5,
	LightEmission = 1,
	LightInfluence = 0,
	Brightness = 1.6,
	Orientation = Enum.ParticleOrientation.FacingCamera,
}

-- Fire.ParticleEmitter (123446605457490): bright embers.
T.Ember = {
	Texture = "rbxassetid://123446605457490",
	Size = seq({ 0, 0.42, 0.12 }, { 0.6, 0.24, 0.08 }, { 1, 0 }),
	ZOffset = 1,
	Transparency = seq({ 0, 1 }, { 0.2, 0 }, { 0.7, 0 }, { 1, 1 }),
	Lifetime = NumberRange.new(0.5, 0.9),
	Speed = NumberRange.new(1, 3),
	RotSpeed = NumberRange.new(-115, 55),
	SpreadAngle = Vector2.new(60, 60),
	Acceleration = Vector3.new(0, 7, 0),
	Drag = 1,
	LightEmission = 1,
	LightInfluence = 0,
	Brightness = 6,
	Orientation = Enum.ParticleOrientation.FacingCamera,
}

-- Fire.ParticleEmitter (72672945547891): flame licks.
T.Flame = {
	Texture = "rbxassetid://72672945547891",
	Size = seq({ 0, 0.5 }, { 1, 1.8 }),
	Transparency = seq({ 0, 1 }, { 0.5, 0.15 }, { 1, 1 }),
	Lifetime = NumberRange.new(0.35, 0.5),
	Speed = NumberRange.new(1.5, 3),
	Rotation = NumberRange.new(-360, 360),
	SpreadAngle = Vector2.new(15, 23),
	Acceleration = Vector3.new(0, 6, 0),
	LightEmission = 1,
	LightInfluence = 0,
	Brightness = 2,
	Orientation = Enum.ParticleOrientation.FacingCamera,
	ZOffset = 0.6,
}

-- Snow .ParticleEmitter (121114307164171): snowflakes.
T.Snow = {
	Texture = "rbxassetid://121114307164171",
	Size = seq({ 0, 0.34 }, { 1, 0.24 }),
	ZOffset = 0.8,
	Transparency = seq({ 0, 0 }, { 0.8, 0 }, { 1, 1 }),
	Lifetime = NumberRange.new(0.9, 1.3),
	Speed = NumberRange.new(0.5, 2),
	Rotation = NumberRange.new(-360, 360),
	RotSpeed = NumberRange.new(-60, 60),
	SpreadAngle = Vector2.new(360, 360),
	Acceleration = Vector3.new(0, -4, 0),
	Drag = 2,
	LightEmission = 0.6,
	LightInfluence = 0.4,
	Orientation = Enum.ParticleOrientation.FacingCamera,
}

-- Smoke.Attachment.ParticleEmitter (115360600857654): dark wisps.
T.Smoke = {
	Texture = "rbxassetid://115360600857654",
	Size = seq({ 0, 0.4 }, { 0.6, 1.1 }, { 1, 1.6 }),
	Transparency = seq({ 0, 1 }, { 0.2, 0.55 }, { 1, 1 }),
	Lifetime = NumberRange.new(0.7, 1),
	Speed = NumberRange.new(0.2, 0.6),
	Rotation = NumberRange.new(0, 300),
	RotSpeed = NumberRange.new(10, 30),
	SpreadAngle = Vector2.new(360, 360),
	Acceleration = Vector3.new(0, 0.5, 0),
	LightEmission = 0,
	LightInfluence = 0.6,
	Orientation = Enum.ParticleOrientation.FacingCamera,
}

-- Wind Swirls.Attachment.ParticleEmitter (102358170561426): the gust swirl.
-- The pack's is nearly invisible (transparency 0.95 at best); made readable.
T.Gust = {
	Texture = "rbxassetid://102358170561426",
	Color = tint(rgb(235, 242, 255)),
	Size = seq({ 0, 0.8 }, { 0.46, 1.6 }, { 1, 1.2 }),
	Transparency = seq({ 0, 1 }, { 0.35, 0.55 }, { 1, 1 }),
	Lifetime = NumberRange.new(0.45, 0.6),
	Speed = NumberRange.new(0, 0),
	Rotation = NumberRange.new(-180, 180),
	Acceleration = Vector3.new(0, -22, 0),
	LightEmission = 1,
	LightInfluence = 0,
	Brightness = 1.4,
	Orientation = Enum.ParticleOrientation.FacingCamera,
	FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
	FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
}

-- Stylized Wind.Attachment.ParticleEmitter (80077917507961): the take-off ring,
-- lying flat under the feet (VelocityPerpendicular to a downward emission).
T.Ring = {
	Texture = "rbxassetid://80077917507961",
	Color = tint(rgb(255, 255, 255)),
	Size = seq({ 0, 0 }, { 0.3, 4.5, 0.4 }, { 1, 7.5, 1 }),
	Transparency = seq({ 0, 1 }, { 0.25, 0.55 }, { 1, 1 }),
	Lifetime = NumberRange.new(0.35, 0.55),
	Speed = NumberRange.new(4, 4),
	Rotation = NumberRange.new(-360, 360),
	SpreadAngle = Vector2.new(0, 0),
	LightEmission = 0.6,
	LightInfluence = 0,
	Brightness = 3,
	Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
	EmissionDirection = Enum.NormalId.Bottom,
	ZOffset = 1,
}

-- Wind Swirls.Attachment.ParticleEmitter (124968973303786): the take-off swirl.
T.Swirl = {
	Texture = "rbxassetid://124968973303786",
	Color = tint(rgb(255, 255, 255)),
	Size = seq({ 0, 0 }, { 1, 4.5 }),
	Transparency = seq({ 0, 1 }, { 0.15, 0.6 }, { 1, 1 }),
	Lifetime = NumberRange.new(0.55, 0.55),
	Speed = NumberRange.new(0, 0),
	Rotation = NumberRange.new(-360, 360),
	RotSpeed = NumberRange.new(150, 150),
	LightEmission = 1,
	LightInfluence = 0,
	Brightness = 2,
	Orientation = Enum.ParticleOrientation.FacingCamera,
	FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8,
	FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
}

-- Dust.Attachment.ParticleEmitter (128684894488003): kicked-up dust.
T.Puff = {
	Texture = "rbxassetid://128684894488003",
	Color = tint(rgb(230, 222, 205)),
	Size = seq({ 0, 0.8 }, { 0.6, 1.5, 0.5 }, { 1, 3.2, 0.5 }),
	Transparency = seq({ 0, 0.6 }, { 1, 1 }),
	Lifetime = NumberRange.new(0.4, 0.7),
	Speed = NumberRange.new(9, 13),
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(40, 40),
	SpreadAngle = Vector2.new(80, 80),
	Acceleration = Vector3.new(0, 1, 0),
	Drag = 5,
	LightEmission = 0.2,
	LightInfluence = 0,
	Brightness = 3,
	Orientation = Enum.ParticleOrientation.FacingCamera,
	EmissionDirection = Enum.NormalId.Top,
}

local WingParticles = { Templates = T }

--[[
	Per pair: `trails` are { template, color, rest, fly } - Rate at rest and in
	flight (doubled at speed). `gust` tints the downstroke swirl.
]]
WingParticles.Styles = {
	AngelWings = {
		trails = { { "Mote", tint(rgb(255, 250, 230), rgb(255, 214, 140)), 2, 12 } },
		gust = rgb(255, 250, 235),
	},
	BatWings = {
		trails = { { "Smoke", tint(rgb(92, 60, 120), rgb(40, 28, 60)), 0, 6 } },
		gust = rgb(210, 190, 235),
	},
	DemonWings = {
		trails = {
			{ "Smoke", tint(rgb(110, 30, 34), rgb(40, 12, 16)), 0, 5 },
			{ "Ember", tint(rgb(255, 120, 60), rgb(220, 40, 30)), 1, 8 },
		},
		gust = rgb(255, 200, 190),
	},
	FairyWings = {
		trails = { { "Dust", tint(rgb(200, 190, 255), rgb(130, 240, 225)), 3, 18 } },
		gust = nil, -- insect wings make no gusts
	},
	FlameWings = {
		trails = {
			{ "Ember", tint(rgb(255, 225, 120), rgb(255, 110, 30)), 4, 18 },
			{ "Flame", tint(rgb(255, 170, 60), rgb(230, 60, 20)), 1, 7 },
		},
		gust = rgb(255, 225, 190),
	},
	FrostWings = {
		trails = { { "Snow", tint(rgb(240, 252, 255), rgb(170, 220, 245)), 2, 12 } },
		gust = rgb(225, 245, 255),
	},
	LeafWings = {
		trails = { { "Dust", tint(rgb(200, 235, 120), rgb(110, 180, 70)), 1, 8 } },
		gust = rgb(235, 255, 220),
	},
}

function WingParticles.make(name, overrides)
	local template = T[name]
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Wing" .. name
	for key, value in pairs(template) do
		emitter[key] = value
	end
	for key, value in pairs(overrides or {}) do
		emitter[key] = value
	end
	return emitter
end

return WingParticles
