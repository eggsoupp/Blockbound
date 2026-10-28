-- Curated from ReplicatedStorage["assets(VFX for use)"] for Deluge. Each entry
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
	-- VFX PACK/Kit/Area#7/WaterBurst/Attachment/ToonLiquidColor
	LiquidColor = {
		Texture = "rbxassetid://11845644255",
		Color = cseq({0, rgb(19, 172, 255)}, {0.327, rgb(85, 190, 255)}, {0.7422, rgb(128, 215, 255)}, {1, rgb(77, 191, 252)}),
		Size = NumberSequence.new(6),
		Lifetime = NumberRange.new(0.8),
		Speed = NumberRange.new(0.1),
		LightEmission = 0.05,
		LightInfluence = 0.3,
		Brightness = 2,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(32),
		count = 2,
	},
	-- VFX PACK/Kit/Area#7/WaterBurst/Attachment/ToonLiquidAlpha
	LiquidAlpha = {
		Texture = "rbxassetid://11845281419",
		Color = cseq({0, rgb(19, 172, 255)}, {0.327, rgb(85, 190, 255)}, {0.7422, rgb(54, 208, 255)}, {1, rgb(77, 191, 252)}),
		Size = NumberSequence.new(6),
		Lifetime = NumberRange.new(0.8),
		Speed = NumberRange.new(0.1),
		LightEmission = 0.35,
		LightInfluence = 0.4,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(32),
		count = 2,
	},
	-- VFX PACK/Kit/Area#7/WaterBurst/Attachment/PixelBurst
	PixelBurst = {
		Texture = "rbxassetid://11866495294",
		Color = cseq({0, rgb(19, 172, 255)}, {0.327, rgb(85, 190, 255)}, {0.7422, rgb(54, 208, 255)}, {1, rgb(77, 191, 252)}),
		Size = NumberSequence.new(6),
		Lifetime = NumberRange.new(0.8),
		Speed = NumberRange.new(0.1),
		LightEmission = 0.35,
		LightInfluence = 0.4,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(32),
		count = 2,
	},
	-- VFX PACK/Kit/Area#7/WaterBurst#2/Attachment/PixelBubblePop
	BubblePop = {
		Texture = "rbxassetid://11868250246",
		Size = NumberSequence.new(2),
		Lifetime = NumberRange.new(0.6),
		Speed = NumberRange.new(0.1),
		LightEmission = 0.4,
		LightInfluence = 0.2,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(32),
		count = 2,
	},
	-- VFX PACK/Kit/Area#7/WaterRipple/Attachment/ToonRippleLoop
	Ripple = {
		Texture = "rbxassetid://11864614229",
		Size = NumberSequence.new(6),
		Lifetime = NumberRange.new(2.15),
		Speed = NumberRange.new(0.01),
		Rotation = NumberRange.new(90),
		LightEmission = 0.35,
		LightInfluence = 0.4,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(15),
		count = 2,
	},
	-- VFX PACK/Kit/Area#7/WaterRipple/Attachment/PixelRipple
	PixelRipple = {
		Texture = "rbxassetid://11865130475",
		Size = seq({0, 5}, {1, 7.437}),
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0.1),
		LightEmission = 1,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(15),
		count = 1,
	},
	-- VFX PACK/Kit/Area#5/Water_Dissolve_5/Attachment/Toon
	SplashToon = {
		Texture = "rbxassetid://13795304468",
		Size = NumberSequence.new(6),
		Lifetime = NumberRange.new(0.8),
		Speed = NumberRange.new(0.1),
		Rotation = NumberRange.new(-120),
		LightEmission = 0.3,
		EmissionDirection = Enum.NormalId.Right,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(32),
		ZOffset = 1,
		count = 1,
	},
	-- VFX PACK/Kit/Waterfalls Ripple/Splash1
	Splash = {
		Texture = "rbxassetid://12356442287",
		Size = seq({0, 0, 0.5}, {0.1, 1.092, 0.5}, {0.2, 1.809, 0.5}, {0.3, 2.195, 0.5}, {0.4, 2.415, 0.5}, {0.5, 2.561, 0.5}, {0.6, 2.67, 0.5}, {0.7, 2.762, 0.5}, {0.8, 2.845, 0.5}, {0.9, 2.923, 0.5}, {1, 3, 0.5}),
		Lifetime = NumberRange.new(0.1, 0.2),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(-360, 360),
		Brightness = 5,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		ZOffset = 1,
	},
	-- VFX PACK/Kit/Waterfalls Ripple/Splash2
	SplashWide = {
		Texture = "rbxassetid://12350056117",
		Size = seq({0, 0, 0.5}, {0.1, 1.092, 0.5}, {0.2, 1.809, 0.5}, {0.3, 2.195, 0.5}, {0.4, 2.415, 0.5}, {0.5, 2.561, 0.5}, {0.6, 2.67, 0.5}, {0.7, 2.762, 0.5}, {0.8, 2.845, 0.5}, {0.9, 2.923, 0.5}, {1, 3, 0.5}),
		Lifetime = NumberRange.new(0.1, 0.2),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(-360, 360),
		Brightness = 5,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		ZOffset = 1,
	},
	-- VFX PACK/Kit/Waterfalls Ripple/Sparkle
	Sparkle = {
		Texture = "http://www.roblox.com/asset/?id=13711999895",
		Size = seq({0, 0}, {0.1936, 0.627, 0.2267}, {0.5836, 0.5037, 0.26}, {1, 0}),
		Lifetime = NumberRange.new(0.2, 0.5),
		Speed = NumberRange.new(5, 25),
		SpreadAngle = Vector2.new(90, 90),
		Acceleration = Vector3.new(0, 2, 0),
		Drag = 5,
		Brightness = 5,
		ZOffset = 1,
	},
	-- Model/C - STRONG WATER SPRAY/MIDDLE/MAIN SPRAY
	Spray = {
		Texture = "rbxassetid://6763809313",
		Color = ColorSequence.new(rgb(181, 217, 255)),
		Size = seq({0, 1, 0.25}, {1, 0}),
		Transparency = seq({0, 1}, {0.25, 0.5}, {1, 1}),
		Lifetime = NumberRange.new(0.25, 0.5),
		Speed = NumberRange.new(10, 15),
		Rotation = NumberRange.new(90),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -25, 0),
		Drag = 1,
		LightInfluence = 1,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	},
	-- Model/C - STRONG WATER SPRAY/WATER SPRAY
	SprayMist = {
		Texture = "rbxassetid://241576804",
		Color = ColorSequence.new(rgb(181, 217, 255)),
		Size = seq({0, 0.5}, {1, 2, 0.25}),
		Transparency = seq({0, 1}, {0.5, 0.75}, {1, 1}),
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(10, 15),
		Rotation = NumberRange.new(-360, 360),
		RotSpeed = NumberRange.new(-45, 45),
		SpreadAngle = Vector2.new(15, 15),
		Acceleration = Vector3.new(0, -25, 0),
		LightInfluence = 1,
	},
	-- Anime/Shoot-01/Shockwave1
	Shockwave = {
		Texture = "rbxassetid://16477162837",
		Size = seq({0, 0.4375}, {0.4975, 3.75}, {1, 5.125}),
		Lifetime = NumberRange.new(0.5),
		Speed = NumberRange.new(0.01),
		Rotation = NumberRange.new(-360, 360),
		LightEmission = 1,
		Brightness = 5,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Front,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		ZOffset = 1,
		LockedToPart = true,
		count = 1,
	},
	-- Yona VFX Pack/Explosion-VFX/Electricity Impact/Ground-ShockWave-02
	GroundRing = {
		Texture = "rbxassetid://13108003178",
		Size = seq({0, 12.6, 1.575}, {0.4, 24.07, 1.574}, {1, 26.77, 1.575}),
		Transparency = seq({0, 1}, {0.1062, 0.4098}, {0.2595, 0.6375}, {0.4239, 0.8438}, {0.65, 0.919}, {1, 1}),
		Lifetime = NumberRange.new(0.3, 0.4),
		Speed = NumberRange.new(0.02916),
		Rotation = NumberRange.new(-360, 360),
		Drag = 25,
		LightEmission = 1,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(25),
		ZOffset = 6.299,
		LockedToPart = true,
		count = 5,
	},
	-- Slash VFX/Workspace/Slash/Attachment1/Trail2
	Trail = {
		Texture = "rbxassetid://16892374733",
		Color = cseq({0, rgb(193, 94, 255)}, {1, rgb(0, 0, 0)}),
		Transparency = NumberSequence.new(0),
		WidthScale = seq({0, 1}, {1, 0}),
		Lifetime = 0.7,
		MinLength = 0,
		TextureMode = Enum.TextureMode.Static,
		TextureLength = 5.139,
		Brightness = 20,
	},
}
