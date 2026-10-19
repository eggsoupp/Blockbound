-- Blockbound's base lighting. The existing Day/Night Cycle owns the clock.
-- LightingStyle and PrioritizeLightingQuality are also set in the Rojo project
-- because some Studio versions restrict changing them from gameplay scripts.
local Lighting = game:GetService("Lighting")

local DAY_AMBIENT = Color3.fromRGB(70, 70, 75)
local DAY_OUTDOOR = Color3.fromRGB(110, 110, 115)
local NIGHT_AMBIENT = Color3.fromRGB(30, 35, 55)
local NIGHT_OUTDOOR = Color3.fromRGB(45, 55, 80)

local function configureStudioProperty(property, value)
	local ok = pcall(function()
		if Lighting[property] ~= value then
			Lighting[property] = value
		end
	end)
	if not ok then
		warn("[LightingPreset] Set Lighting." .. property .. " to " .. tostring(value) .. " in Studio (or sync the Rojo project).")
	end
end

configureStudioProperty("LightingStyle", Enum.LightingStyle.Soft)
configureStudioProperty("PrioritizeLightingQuality", true)
Lighting.GlobalShadows = true
Lighting.Brightness = 2.2
Lighting.ExposureCompensation = 0
Lighting.EnvironmentDiffuseScale = 0.7
-- Pixel-textured blocks should read as matte rather than glossy plastic.
Lighting.EnvironmentSpecularScale = 0
Lighting.ShadowSoftness = 0.25

-- Reuse the existing default effects rather than stacking extra bloom/haze.
-- Color correction has its own name so boss tints remain independent.
local function effect(className, name, reuseClass)
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	if reuseClass then
		existing = Lighting:FindFirstChildOfClass(className)
		if existing then
			return existing
		end
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created
end

local correction = effect("ColorCorrectionEffect", "BlockboundColor", false)
-- Gently temper the vivid block palette, especially grass and foliage.
correction.Saturation = -0.1
correction.Contrast = 0
correction.Brightness = 0
correction.TintColor = Color3.new(1, 1, 1)
correction.Enabled = true

local atmosphere = effect("Atmosphere", "Atmosphere", true)
atmosphere.Density = 0.22
atmosphere.Offset = 0.15
atmosphere.Color = Color3.fromRGB(220, 225, 235)
atmosphere.Decay = Color3.fromRGB(125, 130, 140)
atmosphere.Haze = 0.7
atmosphere.Glare = 0.05

local bloom = effect("BloomEffect", "Bloom", true)
bloom.Intensity = 0.08
bloom.Size = 24
bloom.Threshold = 2
bloom.Enabled = false

local rays = effect("SunRaysEffect", "SunRays", true)
rays.Intensity = 0.01
rays.Spread = 0.8
rays.Enabled = true

for _, child in Lighting:GetChildren() do
	if child:IsA("DepthOfFieldEffect") then
		child.Enabled = false
	end
end

local function updateAmbient()
	local hour = Lighting.ClockTime
	-- Smooth sunrise from 05:00–08:00 and sunset from 17:00–20:00.
	local daylight = math.clamp(math.min((hour - 5) / 3, (20 - hour) / 3), 0, 1)
	daylight = daylight * daylight * (3 - 2 * daylight)
	Lighting.Ambient = NIGHT_AMBIENT:Lerp(DAY_AMBIENT, daylight)
	Lighting.OutdoorAmbient = NIGHT_OUTDOOR:Lerp(DAY_OUTDOOR, daylight)
end

Lighting:GetPropertyChangedSignal("ClockTime"):Connect(updateAmbient)
updateAmbient()
