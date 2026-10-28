-- Curated from ReplicatedStorage["assets(VFX for use)"] for Astral Verdict. Each entry
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
	-- Yona VFX Pack/Combat-VFX/Golden-Sparks-01/Main/Star (a big four-point star)
	StarFlare = {
		Texture = "rbxassetid://1084970835",
		Color = ColorSequence.new(rgb(255, 235, 83)),
		Size = seq({0, 1.562, 0.125}, {1, 0.5, 0.125}),
		Transparency = seq({0, 1}, {0.5, 0}, {1, 1}),
		Lifetime = NumberRange.new(0.25, 0.5),
		Speed = NumberRange.new(0),
		LightEmission = 1,
		Squash = seq({0, -1}, {1, 0.4875}),
		ZOffset = 4,
		count = 25,
	},
	-- VFX :D/46#2/VFX_Attachment (Images/marble star: a turning galaxy)
	Galaxy = {
		Texture = "rbxassetid://13922098740",
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D/7#4/VFX_Attachment (Images/FlaringStar)
	Twinkle = {
		Texture = "rbxassetid://117506898436985",
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D/1#4/VFX_Attachment (Images/sparkle_flip: a cluster of twinkles)
	Sparkle = {
		Texture = "rbxassetid://115317702570755",
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D/118#4/VFX_Attachment (Images/star_flipbook: a spiky star ring)
	StarBurst = {
		Texture = "rbxassetid://13580358178",
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX :D/14#10/VFX_Attachment (Images/star (1) (1): a round glow)
	Orb = {
		Texture = "rbxassetid://110324134347385",
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.001),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- Slash VFX/Workspace/Slash/star
	SlashStar = {
		Texture = "rbxassetid://17062426399",
		Color = ColorSequence.new(rgb(193, 94, 255)),
		Size = seq({0, 0}, {0.4, 0.3581}, {0.5012, 2.732}, {0.6, 0.3581}, {1, 0}),
		Lifetime = NumberRange.new(0.17, 0.9),
		Speed = NumberRange.new(89.52),
		Rotation = NumberRange.new(90),
		RotSpeed = NumberRange.new(-11, 11),
		SpreadAngle = Vector2.new(360, 360),
		Drag = 22,
		LightEmission = 1,
		Brightness = 6,
		EmissionDirection = Enum.NormalId.Front,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.InAndOut,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		ZOffset = 0.3232,
		count = 12,
	},
	-- Slash VFX/Workspace/Slash/Lines1
	Lines = {
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
	-- Slash VFX/Workspace/Slash/Sparks
	Sparks = {
		Texture = "rbxassetid://11197917329",
		Color = ColorSequence.new(rgb(193, 94, 255)),
		Size = seq({0, 0.7032, 0.2661}, {1, 0}),
		Lifetime = NumberRange.new(0.2, 0.35),
		Speed = NumberRange.new(31.48, 81.86),
		Rotation = NumberRange.new(90),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, -147.3, 0),
		LightEmission = 1,
		Brightness = 10,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Back,
		FlipbookFramerate = NumberRange.new(3.842),
		Squash = seq({0, 0.7125}, {1, 1.913}),
		count = 20,
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
	-- Yona VFX Pack/Explosion-VFX/Blast-Explosion-01/Smoke3
	Smoke = {
		Texture = "rbxassetid://10180479311",
		Color = ColorSequence.new(rgb(0, 0, 0)),
		Size = seq({0, 0}, {0.15, 3, 0.189}, {1, 3.5, 0.5}),
		Transparency = seq({0, 0.4}, {0.45, 0.95}, {1, 1}),
		Lifetime = NumberRange.new(1.25),
		Speed = NumberRange.new(10, 75),
		Rotation = NumberRange.new(-360, 360),
		RotSpeed = NumberRange.new(-100, 100),
		SpreadAngle = Vector2.new(-360, 360),
		Drag = 12.5,
		Brightness = 0,
		ZOffset = 1,
		LockedToPart = true,
		count = 65,
	},
	-- Explosions/FinalExplosion/Attachment/changee (a sharp tapered glow, laid along beams)
	Spike = {
		Texture = "rbxassetid://18244349088",
		Color = ColorSequence.new(rgb(47, 0, 140)),
		Size = seq({0, 10, 5}, {1, 0}),
		Lifetime = NumberRange.new(0.01, 0.11),
		Speed = NumberRange.new(250, 400),
		SpreadAngle = Vector2.new(360, 360),
		Brightness = 40,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = seq({0, 0}, {1, -1.967}),
		count = 1,
	},
	-- Model/Model#7/Beam Holder/Attachment/Beam (a soft streak)
	Streak = {
		Texture = "http://www.roblox.com/asset/?id=3517446796",
		Transparency = seq({0, 0}, {1, 1}),
		Width0 = 4,
		Width1 = 4,
		LightEmission = 1,
		LightInfluence = 1,
	},
}
