-- Curated from ReplicatedStorage["assets(VFX for use)"] for Abyss Gate. Each entry
-- copies one authored emitter, beam or trail (its pack path is above it) and
-- the VFX module recolours, resizes and times it. Code-backed so a Rojo
-- install does not depend on the demo packs. `count` is the pack's EmitCount.
local function seq(...)
	local points = {}
	for _, p in ipairs({...}) do table.insert(points, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0)) end
	return NumberSequence.new(points)
end
local function cseq(...)
	local points = {}
	for _, p in ipairs({...}) do table.insert(points, ColorSequenceKeypoint.new(p[1], p[2])) end
	return ColorSequence.new(points)
end
local rgb = Color3.fromRGB

return {
	-- Beams/Waterfall-01/Start/Beam (solid flow with ragged edges)
	PillarFlow = {
		Texture = "rbxassetid://12781828706",
		Color = ColorSequence.new(rgb(16, 151, 255)),
		Transparency = seq({0, 1}, {0.01122, 0}, {0.9913, 0}, {1, 1}),
		Width0 = 2.5,
		Width1 = 2.5,
		TextureLength = 0.5,
		TextureSpeed = 1.5,
		Brightness = 2,
		FaceCamera = true,
		ZOffset = 0.1,
	},
	-- Model/Model#7/Beam Holder/Attachment/Beam (soft streak, the pillar's core)
	PillarCore = {
		Texture = "http://www.roblox.com/asset/?id=3517446796",
		Transparency = seq({0, 0}, {1, 1}),
		Width0 = 4,
		Width1 = 4,
		LightEmission = 1,
		LightInfluence = 1,
	},
	-- Model/Model#5/Beam Holder/Attachment/Beam (a crackling filament)
	PillarArc = {
		Texture = "rbxassetid://5830549480",
		Transparency = seq({0, 0}, {1, 1}),
		Width0 = 4,
		Width1 = 4,
		LightEmission = 1,
		LightInfluence = 1,
	},
	-- VFX :D/13#2/VFX_Attachment (Texture: a swirling void)
	VoidOrb = {
		Texture = "rbxassetid://124749291708895",
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D/40#2/VFX_Attachment (Images/darker_spin)
	DarkSpin = {
		Texture = "rbxassetid://132135386324823",
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D/177/VFX_Attachment (Images/blackflash (1))
	BlackFlash = {
		Texture = "rbxassetid://16034333422",
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D/185/VFX_Attachment (Images/black_lighting_1)
	BlackBolt = {
		Texture = "rbxassetid://75688281086717",
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D/12#9/VFX_Attachment (Images/CricleSlashV2.Shadow4x4)
	Shadow = {
		Texture = "rbxassetid://17612096503",
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- Big/Big-Crack-01/Main/Ash1
	Ash = {
		Texture = "rbxassetid://16955854038",
		Color = ColorSequence.new(rgb(0, 0, 0)),
		Size = seq({0, 0}, {0.2524, 0}, {0.4584, 3.446}, {1, 0}),
		Lifetime = NumberRange.new(0.5),
		Speed = NumberRange.new(30, 50),
		Rotation = NumberRange.new(-360, 360),
		SpreadAngle = Vector2.new(0, 360),
		Drag = 2,
		Brightness = 5,
		EmissionDirection = Enum.NormalId.Front,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookStartRandom = true,
		ZOffset = 0.6,
		LockedToPart = true,
	},
	-- Explosions/FinalExplosion/Attachment/changee#2
	Star = {
		Texture = "rbxassetid://18244403399",
		Color = ColorSequence.new(rgb(47, 0, 140)),
		Size = seq({0, 260}, {0.3333, 175.1}, {0.6667, 90.13}, {1, 5.2}),
		Transparency = seq({0, 0}, {1, 1}),
		Lifetime = NumberRange.new(0.06),
		Speed = NumberRange.new(0.0052),
		LightEmission = 1,
		Brightness = 100,
		ZOffset = 10,
		count = 1,
	},
	-- Anime/Charge-01/Energy1
	Energy = {
		Texture = "rbxassetid://15041986621",
		Size = seq({0, 3.687}, {1, 1.125}),
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
		count = 0,
	},
	-- Yona VFX Pack/Combat-VFX/Hit-04/HitEffect
	HitFlash = {
		Texture = "http://www.roblox.com/asset/?id=7919757890",
		Size = seq({0, 5.269}, {1, 0}),
		Lifetime = NumberRange.new(0.15),
		Speed = NumberRange.new(0.0014),
		Rotation = NumberRange.new(-360, 360),
		SpreadAngle = Vector2.new(-360, 360),
		LightEmission = 0.3,
		Brightness = 2,
		count = 5,
	},
	-- Yona VFX Pack/Combat-VFX/Hit-04/Ring
	HitRing = {
		Texture = "http://www.roblox.com/asset/?id=7919579655",
		Size = seq({0, 0.725}, {0.5523, 4.397, 0.1726}, {1, 5.269, 0.2773}),
		Transparency = seq({0, 0}, {0.5026, 0}, {1, 1}),
		Lifetime = NumberRange.new(0.25),
		Speed = NumberRange.new(0.000725),
		Brightness = 15,
		count = 5,
	},
	-- Yona VFX Pack/Combat-VFX/Hit-04/Lines
	HitLines = {
		Texture = "rbxassetid://7845168136",
		Size = seq({0, 2.852, 0.9904}, {1, 0}),
		Transparency = seq({0, 0}, {0.8695, 0}, {1, 1}),
		Lifetime = NumberRange.new(0.2, 0.4),
		Speed = NumberRange.new(36.25, 90.62),
		SpreadAngle = Vector2.new(360, 360),
		Drag = 12,
		LightEmission = 0.5,
		Brightness = 3,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		ZOffset = 1.45,
		LockedToPart = true,
		count = 5,
	},
	-- Anime/Stars-01/Light
	StarLight = {
		Texture = "rbxassetid://1075864321",
		Color = ColorSequence.new(rgb(255, 212, 57)),
		Size = NumberSequence.new(4.5),
		Transparency = seq({0, 1}, {0.4995, 0.7358}, {1, 1}),
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		Rotation = NumberRange.new(-360, 360),
		LightEmission = 1,
		Brightness = 10,
		EmissionDirection = Enum.NormalId.Front,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		LockedToPart = true,
		count = 10,
	},
	-- Anime/Wind-01/Wind1
	Wind = {
		Texture = "rbxassetid://16950679789",
		Size = seq({0, 0}, {0.1, 2.286}, {0.2, 3.942}, {0.3, 5.226}, {0.4, 6.25}, {0.5, 7.076}, {0.6, 7.739}, {0.7, 8.26}, {0.8, 8.649}, {0.9, 8.903}, {1, 9}),
		Transparency = seq({0, 1}, {0.08717, 0.8062}, {1, 1}),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(0.001),
		Rotation = NumberRange.new(-360, 360),
		RotSpeed = NumberRange.new(-30, 30),
		SpreadAngle = Vector2.new(10, 10),
		Drag = 3,
		LightEmission = 1,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		count = 5,
	},
	-- Yona VFX Pack/Explosion-VFX/Explosion-02/ShardsDark
	ShardsDark = {
		Texture = "rbxassetid://10439119562",
		Color = ColorSequence.new(rgb(0, 0, 0)),
		Size = seq({0, 0}, {0.25, 2.468, 2.468}, {1, 0}),
		Transparency = NumberSequence.new(0.2),
		Lifetime = NumberRange.new(0.45, 0.7),
		Speed = NumberRange.new(138.8, 277.7),
		Rotation = NumberRange.new(90),
		SpreadAngle = Vector2.new(-360, 360),
		Drag = 8,
		Brightness = 0,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = seq({0, 0}, {1, -0.6375}),
		ZOffset = 6.171,
	},
	-- Yona VFX Pack/Explosion-VFX/Explosion-02/SpecsDark
	SpecsDark = {
		Texture = "rbxassetid://10632727506",
		Color = ColorSequence.new(rgb(0, 0, 0)),
		Size = seq({0, 0}, {0.25, 2.777, 2.777}, {1, 0}),
		Transparency = NumberSequence.new(0.15),
		Lifetime = NumberRange.new(0.45, 0.8),
		Speed = NumberRange.new(138.8, 277.7),
		Rotation = NumberRange.new(-360, 360),
		SpreadAngle = Vector2.new(-360, 360),
		Drag = 8,
		Brightness = 0,
		ZOffset = 6.171,
		count = 35,
	},
	-- Big/Explosion-01/SmokeDark1
	SmokeDark = {
		Texture = "rbxassetid://10180479311",
		Color = ColorSequence.new(rgb(0, 0, 0)),
		Size = seq({0, 13.5}, {0.25, 27, 0.5}, {1, 27}),
		Transparency = seq({0, 0.1688, 0.09375}, {1, 1}),
		Lifetime = NumberRange.new(2, 4),
		Rotation = NumberRange.new(-360, 360),
		RotSpeed = NumberRange.new(-18, 18),
		SpreadAngle = Vector2.new(-360, 360),
		Drag = 1,
		LightEmission = 0.5,
		Brightness = 4,
	},
	-- Slash VFX/Workspace/Slash/Lines1
	SlashLines = {
		Texture = "http://www.roblox.com/asset/?id=14480500149",
		Color = ColorSequence.new(rgb(193, 94, 255)),
		Size = seq({0, 0}, {0.3203, 0.07494}, {0.4273, 0.6781}, {0.5263, 1.642}, {0.6153, 0.8208}, {0.7983, 0.1499}, {0.9, 0.01561}, {1, 0}),
		Lifetime = NumberRange.new(0.1, 0.4),
		Speed = NumberRange.new(42.82, 85.65),
		Rotation = NumberRange.new(-90),
		Drag = 5,
		LightEmission = 1,
		Brightness = 4.59,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Back,
		Squash = seq({0, 4.7}, {0.1, 4.699}, {0.2, 4.694}, {0.3, 4.675}, {0.4, 4.627}, {0.5, 4.518}, {0.6, 4.285}, {0.7, 3.833}, {0.8, 3.086}, {0.9, 2.1}, {1, 1}),
		ZOffset = 1,
		count = 15,
	},
}
