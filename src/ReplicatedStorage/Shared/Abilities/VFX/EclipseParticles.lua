-- Curated from the SoulShroud Ultimate VFX Pack place for Eclipse Prison.
-- Every entry copies one authored emitter (its pack path is above it); the VFX
-- module recolours (PackAssembly's tint rule), places and times it. Code-backed
-- because the auras are not in AbilityVFXLibrary.
--
-- Workspace.Auras, child #6 (an R6 StarterCharacter): an energy aura of seven
-- layer kinds spread over the body. `Aura` lists where each one sits on the
-- R6 body; EclipseVFX maps those parts onto an R15 character.
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

-- The aura's shared curves.
local PULSE = seq({0, 0.05}, {0.125, 0.171}, {0.25, 0.17}, {0.375, 0.099}, {0.5, 0.05}, {0.625, 0.001}, {0.75, 0}, {0.875, 0}, {1, 0.05})
local BLINK = seq({0, 1}, {0.5, 0}, {1, 1})
local SHEEN = cseq({0, rgb(110, 164, 255)}, {0.2, rgb(169, 201, 255)}, {0.4, rgb(219, 235, 255)}, {0.6, rgb(255, 255, 255)},
	{0.8, rgb(224, 242, 255)}, {1, rgb(110, 164, 255)})
local STRETCH = seq({0, 0}, {1, 1.012})
local PARALLEL = Enum.ParticleOrientation.VelocityParallel

local Particles = {
	-- Auras/#6/BZ1-FX-PART (4x5x1, under the torso): a slow turning disc
	Disc = {
		Texture = "rbxassetid://124575715459183", Color = SHEEN,
		Size = seq({0, 5}, {1, 0}), Transparency = seq({0, 0.05}, {0.125, 0.195}, {0.25, 0.194}, {0.375, 0.109}, {0.5, 0.05}, {0.625, 0}, {1, 0.05}),
		Lifetime = NumberRange.new(3), Speed = NumberRange.new(0.001), SpreadAngle = Vector2.new(35, 35),
		Rotation = NumberRange.new(345), RotSpeed = NumberRange.new(110), Acceleration = Vector3.new(0, 2, 0), Drag = 0.2,
		LightEmission = 1, LightInfluence = 0, Orientation = Enum.ParticleOrientation.VelocityPerpendicular, LockedToPart = true, Rate = 5,
	},
	-- Auras/#6/Left Arm (and every limb): spark streaks thrown out and up
	Sparks = {
		Texture = "rbxassetid://121218359242060", Color = SHEEN, Transparency = PULSE,
		Lifetime = NumberRange.new(0.4, 0.5), Speed = NumberRange.new(3.24, 3.96), SpreadAngle = Vector2.new(360, 360),
		Acceleration = Vector3.new(0, 25, 0), Drag = 4.25, LightEmission = 1, LightInfluence = 0, Orientation = PARALLEL,
		ZOffset = 2, Squash = STRETCH, LockedToPart = true, Rate = 10,
	},
	-- Auras/#6/Left Arm: soft wisps that swell and lift
	Wisps = {
		Texture = "rbxassetid://77829879675935", Color = SHEEN, Size = seq({0, 0}, {0.6, 0.75}, {1, 0}), Transparency = PULSE,
		Lifetime = NumberRange.new(0.5), Speed = NumberRange.new(3.24, 3.96), SpreadAngle = Vector2.new(360, 360),
		Acceleration = Vector3.new(0, 35, 0), Drag = 4.25, LightEmission = 1, LightInfluence = 0, Orientation = PARALLEL,
		Squash = STRETCH, LockedToPart = true, Rate = 10,
	},
	-- Auras/#6/Left Arm: long streaks shot down and pulled back up
	Streaks = {
		Texture = "rbxassetid://83706713700040", Color = SHEEN, Transparency = PULSE,
		Lifetime = NumberRange.new(0.75), Speed = NumberRange.new(5.4, 6.6), SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 25, 0), Drag = 0.2, LightEmission = 1, LightInfluence = 0, Orientation = PARALLEL,
		EmissionDirection = Enum.NormalId.Bottom, LockedToPart = true, Rate = 10,
	},
	-- Auras/#6/Torso/Attachment: a turning flare that swells from the chest
	Flare = {
		Texture = "rbxassetid://95881978144183", Color = ColorSequence.new(rgb(255, 47, 47)),
		Size = seq({0, 0}, {1, 7.75}), Transparency = BLINK, Lifetime = NumberRange.new(1), Speed = NumberRange.new(0.001),
		Rotation = NumberRange.new(-360, 360), RotSpeed = NumberRange.new(-100, 100), LightEmission = 1, LightInfluence = 0,
		LockedToPart = true, Rate = 3,
	},
	-- Auras/#6/Torso/Attachment: a ring that swells from the chest
	Ring = {
		Texture = "rbxassetid://103425775786682", Color = ColorSequence.new(rgb(255, 47, 47)),
		Size = seq({0, 0}, {1, 3.625}), Transparency = BLINK, Lifetime = NumberRange.new(1), Speed = NumberRange.new(0.001),
		LightEmission = 1, LightInfluence = 0, LockedToPart = true, Rate = 3,
	},
	-- Auras/#6/Torso/Attachment: a fast faint shock round the body
	Shock = {
		Texture = "rbxassetid://119476357519075", Color = ColorSequence.new(rgb(255, 47, 47)),
		Size = seq({0, 2.25}, {1, 7}), Transparency = seq({0, 1}, {0.497, 0.929}, {1, 1}), Lifetime = NumberRange.new(0.5),
		Speed = NumberRange.new(0.001), SpreadAngle = Vector2.new(360, 360), LightEmission = 1, LightInfluence = 0,
		Orientation = PARALLEL, ZOffset = 1, LockedToPart = true, Rate = 5,
	},
}

--[[
	The aura as authored: {kind, R6 part, attachment offset (studs), host part
	size}. A `host` entry rode its own invisible part in the pack; the rest sat
	on the limb (or on an attachment in it).
]]
Particles.Aura = {
	{"Disc", "Torso", Vector3.new(0, -0.5, 0), Vector3.new(4, 5, 1)},
	{"Sparks", "Torso", Vector3.new(0, 1.5, 0), Vector3.one},
	{"Wisps", "Torso", Vector3.new(0, 1.5, 0), Vector3.one},
	{"Streaks", "Torso", Vector3.new(0, 1.5, 0), Vector3.one},
	{"Sparks", "Torso"}, {"Wisps", "Torso"}, {"Streaks", "Torso"},
	{"Flare", "Torso", Vector3.zero}, {"Ring", "Torso", Vector3.zero}, {"Shock", "Torso", Vector3.zero},
	{"Sparks", "Left Arm"}, {"Wisps", "Left Arm"}, {"Streaks", "Left Arm"},
	{"Sparks", "Right Arm"}, {"Wisps", "Right Arm"}, {"Streaks", "Right Arm"},
	{"Sparks", "Left Leg"}, {"Wisps", "Left Leg"}, {"Streaks", "Left Leg"},
	{"Sparks", "Right Leg"}, {"Wisps", "Right Leg"}, {"Streaks", "Right Leg"},
}

return Particles
