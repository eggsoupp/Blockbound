-- Curated from ReplicatedStorage["assets(VFX for use)"] for Tidecaller. Each entry
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
	-- Anime/Water-01/Main/Water1 (a swirl of water)
	Swirl = {
		Texture = "rbxassetid://16664715772",
		Color = ColorSequence.new(rgb(0, 153, 255)),
		Size = seq({0, 0.1}, {0.1, 0.2939}, {0.2, 0.4623}, {0.3, 0.6207}, {0.4, 0.7766}, {0.5, 0.9353}, {0.6, 1.101}, {0.7, 1.28}, {0.8, 1.48}, {0.9, 1.711}, {1, 2}),
		Transparency = seq({0, 0}, {0.1, 0.0001227}, {0.2, 0.001119}, {0.3, 0.00436}, {0.4, 0.01214}, {0.5, 0.02847}, {0.6, 0.06076}, {0.7, 0.1238}, {0.8, 0.2496}, {0.9, 0.5078}, {1, 1}),
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(-360, 360),
		RotSpeed = NumberRange.new(-20, 20),
		SpreadAngle = Vector2.new(10, 10),
		LightEmission = 0.3,
		Brightness = 2,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(20),
		FlipbookStartRandom = true,
		ZOffset = 1.7,
	},
	-- VFX PACK/Kit/Area#7/WaterBurst/Attachment/RealisticBurst
	Spray = {
		Texture = "rbxassetid://11866455263",
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
	-- VFX PACK/Kit/Area#7/WaterBurst#2/Attachment/ToonBubblePop (a bubble that pops)
	Bubble = {
		Texture = "rbxassetid://11868043658",
		Size = NumberSequence.new(2),
		Lifetime = NumberRange.new(0.8),
		Speed = NumberRange.new(0.1),
		LightEmission = 0.4,
		LightInfluence = 0.2,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(32),
		count = 1,
	},
	-- VFX PACK/Kit/Area#5/Water_Dissolve_4/Attachment/Toon (a toon splash)
	Splash = {
		Texture = "rbxassetid://13794844031",
		Size = NumberSequence.new(3),
		Lifetime = NumberRange.new(0.8),
		Speed = NumberRange.new(0.1),
		LightEmission = 0.4,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(32),
		Squash = NumberSequence.new(0.3),
		ZOffset = 1,
		count = 1,
	},
	-- VFX PACK/Kit/IceMagichit/0/AnimatedCircle
	Ring = {
		Texture = "rbxassetid://13712004355",
		Color = ColorSequence.new(rgb(101, 155, 255)),
		Size = seq({0, 0, 0.2}, {0.1, 0.785, 0.2}, {0.2, 1.242, 0.2}, {0.3, 1.507, 0.2}, {0.4, 1.671, 0.2}, {0.5, 1.78, 0.2}, {0.6, 1.854, 0.2}, {0.7, 1.908, 0.2}, {0.8, 1.947, 0.2}, {0.9, 1.977, 0.2}, {1, 2, 0.2}),
		Lifetime = NumberRange.new(0.2),
		Speed = NumberRange.new(0),
		LightEmission = 1,
		Brightness = 5,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	},
	-- VFX PACK/Kit/IceMagichit/0/Wind
	Wind = {
		Texture = "rbxassetid://12506449597",
		Color = ColorSequence.new(rgb(112, 176, 255)),
		Size = seq({0, 0, 0.8}, {0.1, 0.7864, 0.8}, {0.2, 1.258, 0.8}, {0.3, 1.516, 0.8}, {0.4, 1.675, 0.8}, {0.5, 1.782, 0.8}, {0.6, 1.857, 0.8}, {0.7, 1.911, 0.8}, {0.8, 1.95, 0.8}, {0.9, 1.979, 0.8}, {1, 2, 0.8}),
		Transparency = seq({0, 1}, {0.09641, 0.4875}, {1, 1}),
		Lifetime = NumberRange.new(0.25, 0.75),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(-360, 360),
		SpreadAngle = Vector2.new(360, 360),
		LightEmission = 1,
		ZOffset = -0.8,
		LockedToPart = true,
	},
	-- VFX PACK/Kit/IceMagichit/0/Flare2
	Flare = {
		Texture = "rbxassetid://13887157156",
		Color = ColorSequence.new(rgb(110, 141, 255)),
		Size = seq({0, 5.5, 0.5}, {0.1, 5.555, 0.5}, {0.2, 5.612, 0.5}, {0.3, 5.668, 0.5}, {0.4, 5.723, 0.5}, {0.5, 5.774, 0.5}, {0.6, 5.822, 0.5}, {0.7, 5.868, 0.5}, {0.8, 5.913, 0.5}, {0.9, 5.957, 0.5}, {1, 6, 0.5}),
		Transparency = seq({0, 1}, {0.1418, 0.9125}, {1, 1}),
		Lifetime = NumberRange.new(0.2, 0.25),
		Speed = NumberRange.new(0),
		LightEmission = 1,
		Brightness = 5,
	},
	-- Beams/Waterfall-01/Start/Clouds (toon cloud puffs)
	Mist = {
		Texture = "http://www.roblox.com/asset/?id=275871881",
		Transparency = seq({0, 1}, {0.4988, 0}, {1, 1}),
		Lifetime = NumberRange.new(1.1),
		Speed = NumberRange.new(1),
		Rotation = NumberRange.new(-360, 360),
		SpreadAngle = Vector2.new(0, 360),
		Brightness = 5,
		EmissionDirection = Enum.NormalId.Front,
	},
	-- VFX PACK/Kit/Waterfalls Ripple/Dots
	Dots = {
		Texture = "rbxassetid://12942158384",
		Size = seq({0, 0}, {0.1976, 0.1937, 0.2267}, {0.4716, 0.1503, 0.26}, {1, 0}),
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(0, 15),
		Rotation = NumberRange.new(-30, 360),
		RotSpeed = NumberRange.new(-500, 500),
		SpreadAngle = Vector2.new(90, 90),
		Acceleration = Vector3.new(0, 2, 0),
		Drag = 5,
		Brightness = 5,
		ZOffset = 1,
	},
	-- Beams/Waterfall-01/Start/Beam#3 (a bright water stream)
	Stream = {
		Texture = "rbxassetid://12781828706",
		Transparency = seq({0, 1}, {0.01122, 0}, {0.9913, 0}, {1, 1}),
		Width0 = 3,
		Width1 = 3,
		TextureLength = 0.5,
		TextureSpeed = 1.5,
		Brightness = 2,
		FaceCamera = true,
	},
	-- Beams/Waterfall-01/Start/Beam#2
	StreamGlow = {
		Texture = "rbxassetid://9541055154",
		Transparency = seq({0, 1}, {0.01122, 0}, {0.9913, 0}, {1, 1}),
		Width0 = 3.5,
		Width1 = 3.5,
		TextureLength = 0.5,
		TextureSpeed = 1.5,
		LightEmission = 1,
		FaceCamera = true,
		ZOffset = 0.3,
	},
}
