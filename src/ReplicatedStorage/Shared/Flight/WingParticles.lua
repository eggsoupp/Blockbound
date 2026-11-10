--[[
	WingParticles

	What flight looks like besides the wings themselves. Used by
	StarterPlayerScripts.WingAnimator (every client, every wearer) and
	FlightClient (the terminal velocity).

	WING AURAS - from the VFX library

	Each pair's effect is one or two complete assemblies from the game's VFX
	library (ReplicatedStorage.AbilityVFXLibrary / WeaponShotLibrary, built
	from the SoulShroud pack: assets/vfx-library), mounted through
	Shared.Abilities.VFX.PackAssembly on each wing's outer piece and welded
	there, so the authored layers, curves and flipbooks are kept and only
	scale, tint and budget change. They stream while flying.
	WingAnimator draws them a stud nearer the camera (ZOffset), or the wing
	they sit inside hides them; `budget` is particles per second for the
	whole assembly, shared between its layers by their authored rates.

	  { assembly, library, scale, tint = {deep, main, hot}, budget }

	TAKE-OFF - kept as it was

	A ring of air and a swirl at the feet, and dust if there is ground below:
	single SoulShroud emitters copied into the templates here (T.Ring, T.Swirl,
	T.Puff) and built with WingParticles.make.

	FALLING - terminal velocity

	Roblox has no air resistance, so nothing stops a fall speeding up. A
	falling character (not flying) is held at Fall.terminal studs/s by
	FlightClient, and anyone falling that fast - seen from every client by
	their velocity alone - streams the library's speed lines around them, with
	a ring of air the moment they reach it, and a ribbon of wind behind them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local WingParticles = {}

-- ---------------------------------------------------------------------------
-- Wing auras
-- ---------------------------------------------------------------------------

local function palette(deep, main, hot)
	return { deep = deep, main = main, hot = hot }
end

-- Resolved when first used: the libraries are big and may replicate after
-- the scripts start.
local LIBRARIES = {
	ability = "AbilityVFXLibrary",
	shot = "WeaponShotLibrary",
	legend = "LegendaryAbilitySources",
}

function WingParticles.template(entry)
	local folder = ReplicatedStorage:FindFirstChild(LIBRARIES[entry[2]])
	return folder and folder:FindFirstChild(entry[1])
end

WingParticles.Styles = {
	-- ValhallaOrb: drifting spirit glitter, warmed to gold.
	AngelWings = {
		{ "ValhallaOrb", "shot", 0.2, palette(rgb(150, 110, 40), rgb(255, 220, 140), rgb(255, 252, 235)), 30 },
	},
	-- VoidOrb: a slow dark swirl in plum.
	BatWings = {
		{ "VoidOrb", "shot", 0.16, palette(rgb(30, 14, 40), rgb(110, 60, 150), rgb(200, 170, 230)), 40 },
	},
	-- VoidOrb in crimson, with FireVFX6 embers.
	DemonWings = {
		{ "VoidOrb", "shot", 0.16, palette(rgb(40, 6, 10), rgb(170, 30, 40), rgb(255, 150, 120)), 36 },
		{ "FireVFX6", "ability", 0.22, palette(rgb(90, 10, 10), rgb(230, 50, 30), rgb(255, 200, 150)), 40 },
	},
	-- ValhallaOrb glitter in lavender and turquoise: pixie dust.
	FairyWings = {
		{ "ValhallaOrb", "shot", 0.18, palette(rgb(70, 60, 150), rgb(170, 160, 255), rgb(170, 255, 240)), 30 },
	},
	-- FlameCore: real flame on the plumes.
	FlameWings = {
		{ "FlameCore", "ability", 0.2, nil, 160 },
	},
	-- ValhallaOrb as authored is a cold cyan: kept, whitened at the hot end.
	FrostWings = {
		{ "ValhallaOrb", "shot", 0.2, palette(rgb(40, 90, 150), rgb(150, 215, 255), rgb(240, 252, 255)), 30 },
	},
	-- Droplets69 in green: dew and pollen shaken from the leaves.
	LeafWings = {
		{ "Droplets69", "ability", 0.16, palette(rgb(30, 70, 30), rgb(120, 200, 80), rgb(230, 245, 170)), 50 },
	},
}

-- ---------------------------------------------------------------------------
-- Falling
-- ---------------------------------------------------------------------------

WingParticles.Fall = {
	terminal = 120, -- studs/s: the fastest a falling (not flying) body goes
	trailFrom = 0.92, -- share of terminal at which the speed lines start
	trailTo = 0.8, -- and below which they stop again
	-- LegendLines: tall streaks of air, whitened, riding the body so they rush
	-- up past it. Unlocked, a fall this fast scatters them far above.
	lines = { "LegendLines", "legend", 0.5, palette(rgb(120, 140, 170), rgb(220, 232, 255), rgb(255, 255, 255)), 120, locked = true },
	-- A ribbon of wind left behind the body (the slash pack's wind texture,
	-- as the dash streak), shoulder to shoulder.
	trail = {
		texture = "rbxassetid://16892374733",
		textureLength = 5.14,
		color = ColorSequence.new(rgb(240, 246, 255), rgb(200, 220, 255)),
		transparency = seq({ 0, 0.35 }, { 0.6, 0.75 }, { 1, 1 }),
		widthScale = seq({ 0, 1 }, { 1, 0.3 }),
		lifetime = 0.22,
		lightEmission = 0.6,
		span = Vector3.new(0.9, 0.8, 0),
	},
	-- On reaching it: the take-off ring of air (T.Ring), at the waist.
}

-- ---------------------------------------------------------------------------
-- Take-off templates (single emitters from the SoulShroud pack)
-- ---------------------------------------------------------------------------

local T = {}

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

WingParticles.Templates = T

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
