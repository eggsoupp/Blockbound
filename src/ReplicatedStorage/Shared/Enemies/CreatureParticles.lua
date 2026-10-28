-- Curated from ReplicatedStorage["assets(VFX for use)"] (and the retired
-- Annihilation LaserFire pack) for the voxel creatures' moves. Each entry
-- copies one authored emitter or beam (its pack path is above it) and
-- StarterPlayerScripts.CreatureFX recolours, resizes and times it.
-- Code-backed so a Rojo install does not depend on the demo packs.
-- `count` is the pack's EmitCount.
local function seq(...)
	local points = {}
	for _, p in ipairs({...}) do table.insert(points, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0)) end
	return NumberSequence.new(points)
end
local rgb = Color3.fromRGB

return {
	-- Explosions/Boom 1/sparks
	BoomSparks = {
		Texture = "rbxassetid://7451822955",
		Color = ColorSequence.new(rgb(255, 100, 0)),
		Size = seq({0, 1}, {1, 0}),
		Transparency = seq({0, 0}, {1, 1}),
		Lifetime = NumberRange.new(1.5),
		Speed = NumberRange.new(64),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -32, 0),
		Drag = 2.375,
		LightEmission = 1,
		Squash = seq({0, -2}, {1, -1.5}),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		ZOffset = -1,
		count = 10,
	},
	-- Explosions/Boom 1/glow
	BoomGlow = {
		Texture = "rbxassetid://8120666025",
		Color = ColorSequence.new(rgb(255, 75, 0)),
		Size = seq({0, 10}, {1, 0}),
		Transparency = NumberSequence.new(0),
		Lifetime = NumberRange.new(0.375),
		Speed = NumberRange.new(0),
		LightEmission = 1,
		Brightness = 50,
		ZOffset = 3,
		count = 1,
	},
	-- Explosions/Boom 1/shockwave
	-- Anime/Charge-01/Main/Energy1 (inward rings)
	ChargeEnergy = {
		Texture = "rbxassetid://15041986621",
		Color = ColorSequence.new(rgb(255, 255, 255)),
		Size = seq({0, 3.687}, {1, 1.125}),
		Transparency = NumberSequence.new(0),
		Lifetime = NumberRange.new(0.3),
		Speed = NumberRange.new(0.001),
		Rotation = NumberRange.new(-360, 360),
		SpreadAngle = Vector2.new(75, 75),
		LightEmission = 1,
		Brightness = 25,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		ZOffset = 1,
		count = 1,
	},
	-- Anime/Charge-01/Main/Core1 (bright core)
	ChargeCore = {
		Texture = "rbxassetid://1084982817",
		Color = ColorSequence.new(rgb(255, 255, 255)),
		Size = NumberSequence.new(0.5),
		Transparency = NumberSequence.new(0),
		Lifetime = NumberRange.new(0.4),
		Speed = NumberRange.new(0.001),
		LightEmission = 1,
		Brightness = 5,
		LockedToPart = true,
		count = 1,
	},
	-- Anime/Fire-01/Main/FireSpecs1
	-- Anime/Smoke-01/Main/Smoke1
	Puff = {
		Texture = "rbxassetid://16669188960",
		Color = ColorSequence.new(rgb(182, 182, 182)),
		Size = NumberSequence.new(3),
		Transparency = seq({0, 1}, {0.09963, 0}, {1, 0}),
		Lifetime = NumberRange.new(0.8),
		Speed = NumberRange.new(0.001),
		Rotation = NumberRange.new(-360, 360),
		RotSpeed = NumberRange.new(-50, 50),
		SpreadAngle = Vector2.new(0, 360),
		LightEmission = 0.1,
		EmissionDirection = Enum.NormalId.Front,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		ZOffset = 1,
		count = 3,
	},
	-- Anime/Stars-01/Main/Stars
	Glints = {
		Texture = "rbxassetid://1851669703",
		Color = ColorSequence.new(rgb(255, 212, 57)),
		Size = seq({0, 2, 1}, {1, 2, 1}),
		Transparency = seq({0, 1}, {0.4994, 0}, {1, 1}),
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		Rotation = NumberRange.new(-360, 360),
		LightEmission = 2,
		Brightness = 10,
		EmissionDirection = Enum.NormalId.Front,
		count = 6,
	},
	-- Anime/Slash-01/Main/Slash1
	Slash = {
		Texture = "rbxassetid://16939611858",
		Color = ColorSequence.new(rgb(255, 255, 255)),
		Size = NumberSequence.new(6),
		Transparency = seq({0, 1}, {0.04115, 0.4648}, {0.09476, 0}, {0.8965, 0}, {0.9564, 0.4225}, {1, 1}),
		Lifetime = NumberRange.new(0.2),
		Speed = NumberRange.new(0.01),
		Rotation = NumberRange.new(180),
		SpreadAngle = Vector2.new(5, 5),
		Drag = 5,
		LightEmission = 1,
		Brightness = 2,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		ZOffset = 1.5,
		LockedToPart = true,
		count = 1,
	},
	-- Anime/Shiny-01/Main/Core1
	Flare = {
		Texture = "rbxassetid://1075864321",
		Color = ColorSequence.new(rgb(255, 216, 76)),
		Size = NumberSequence.new(1.5),
		Transparency = seq({0, 1}, {0.5, 0}, {1, 1}),
		Lifetime = NumberRange.new(0.5),
		Speed = NumberRange.new(0.001),
		LightEmission = 1,
		Brightness = 5,
		ZOffset = 1,
		LockedToPart = true,
		count = 1,
	},
	-- AnnihilationPacks/LaserFire/End/BeamFire beam 2 (beam; Width scaled by the caller)
	LaserCore = {
		Texture = "rbxassetid://15937996601",
		TextureMode = Enum.TextureMode.Stretch,
		TextureLength = 1,
		TextureSpeed = -3,
		Brightness = 4,
		Segments = 10,
	},
	-- AnnihilationPacks/LaserFire/End/Beam11 (beam)
	LaserGlow = {
		Texture = "rbxassetid://16892453445",
		TextureMode = Enum.TextureMode.Stretch,
		TextureLength = 1,
		TextureSpeed = -2,
		Brightness = 1,
		Segments = 20,
	},
	-- Slash VFX Trail2: a soft-edged band, for swoop and dart trails.
	Band = {
		Texture = "rbxassetid://16892374733",
	},
}
