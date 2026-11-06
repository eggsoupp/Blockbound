--[[
	SignusSky

	The dusk over a phase-two Signus, client side. While any SignusRig model
	with SignusPhase 2 is within reach of the camera the air turns a deep
	purple: a thin violet haze and a cooler, harder grade. Nothing hangs in
	the sky. None of it touches the clock or the server's SignusSky tint.

	It is a look, not a darkening: by day the exposure comes down a touch so
	the purple reads as purple rather than lilac, but at night and in the
	hours round dawn and dusk - when the world is already dark - it lights the
	ground with a moonlit violet ambient and thins and lightens the haze, so
	the arena and every telegraph stay readable whatever the clock says. The
	ambient, not the exposure, does the lifting: exposure would brighten the
	spells' glow along with the ground and wash the screen out. When the last
	one goes (or dies) everything eases back to what it was.
]]

local Collection = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Run = game:GetService("RunService")

local Sky = {}

local REACH = 520

-- The haze by day, and at night: lighter and thinner in the dark, where a
-- dense dark haze is what swallows the terrain.
local DayAir = {
	Color = Color3.fromRGB(96, 54, 150),
	Decay = Color3.fromRGB(38, 12, 72),
	Density = 0.32,
	Haze = 1.7,
	Glare = 0,
}
local NightAir = {
	Color = Color3.fromRGB(150, 112, 214),
	Decay = Color3.fromRGB(92, 60, 150),
	Density = 0.24,
	Haze = 1.1,
	Glare = 0,
}

-- Exposure the dusk takes away by day, and the little it adds at night.
-- Exposure brightens the spells' glow as much as the ground, so the dark is
-- lifted mostly through the ambient light, which reaches only lit surfaces.
local DAY_EXPOSURE = -0.12
local NIGHT_EXPOSURE = 0.35
-- The ambient a phase-two night is lit by: moonlit violet, bright enough to
-- read terrain and telegraphs by.
local NIGHT_AMBIENT = Color3.fromRGB(118, 100, 160)
local NIGHT_OUTDOOR = Color3.fromRGB(150, 128, 196)

local started = false
local weight = 0
local base -- the atmosphere as it was, captured when the dusk begins
local baseExposure
local grade
-- LightingPreset owns the ambient and changes it with the clock: what it last
-- set, and what this module last wrote over it, so a change from it is seen.
local ambientBase, outdoorBase
local wroteAmbient, wroteOutdoor

local function nearDusk(camera: Camera): boolean
	for _, model in Collection:GetTagged("SignusRig") do
		if model:GetAttribute("SignusPhase") == 2 and not model:GetAttribute("SignusDecoy")
			and model:IsDescendantOf(workspace) then
			local ok, pivot = pcall(model.GetPivot, model)
			if ok and (pivot.Position - camera.CFrame.Position).Magnitude <= REACH then
				return true
			end
		end
	end
	return false
end

local function atmosphere(): Atmosphere?
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

-- How much daylight there is, as LightingPreset reckons it for the ambient:
-- 0 at night, 1 from 08:00 to 17:00, eased through dawn and dusk.
local function daylight(): number
	local hour = Lighting.ClockTime
	local d = math.clamp(math.min((hour - 5) / 3, (20 - hour) / 3), 0, 1)
	return d * d * (3 - 2 * d)
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local want = if nearDusk(camera) then 1 else 0
	-- In quickly with the ignition, out slowly as the dusk passes.
	local rate = if want > weight then 2.4 else 0.6
	weight = if want > weight then math.min(want, weight + dt * rate) else math.max(want, weight - dt * rate)

	local air = atmosphere()
	if weight > 0 and not grade then
		baseExposure = Lighting.ExposureCompensation
		if air then
			base = { Color = air.Color, Decay = air.Decay, Density = air.Density, Haze = air.Haze, Glare = air.Glare }
		end
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "SignusDuskGrade"
		grade.Parent = Lighting
	end
	if not grade then
		return
	end

	local w = weight * weight * (3 - 2 * weight)
	local day = daylight()
	if air and base then
		local color = NightAir.Color:Lerp(DayAir.Color, day)
		local decay = NightAir.Decay:Lerp(DayAir.Decay, day)
		local density = NightAir.Density + (DayAir.Density - NightAir.Density) * day
		local haze = NightAir.Haze + (DayAir.Haze - NightAir.Haze) * day
		air.Color = base.Color:Lerp(color, w)
		air.Decay = base.Decay:Lerp(decay, w)
		air.Density = base.Density + (density - base.Density) * w
		air.Haze = base.Haze + (haze - base.Haze) * w
		air.Glare = base.Glare + (DayAir.Glare - base.Glare) * w
	end
	local exposure = NIGHT_EXPOSURE + (DAY_EXPOSURE - NIGHT_EXPOSURE) * day
	Lighting.ExposureCompensation = baseExposure + exposure * w
	if Lighting.Ambient ~= wroteAmbient then
		ambientBase = Lighting.Ambient
	end
	if Lighting.OutdoorAmbient ~= wroteOutdoor then
		outdoorBase = Lighting.OutdoorAmbient
	end
	local lift = (1 - day) * w
	Lighting.Ambient = ambientBase:Lerp(NIGHT_AMBIENT, lift)
	Lighting.OutdoorAmbient = outdoorBase:Lerp(NIGHT_OUTDOOR, lift)
	wroteAmbient, wroteOutdoor = Lighting.Ambient, Lighting.OutdoorAmbient
	grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(232, 220, 252), w)
	grade.Contrast = 0.1 * w * day
	grade.Saturation = -0.08 * w

	if weight <= 0 then
		if air and base then
			for key, value in base do
				air[key] = value
			end
		end
		base = nil
		Lighting.ExposureCompensation = baseExposure
		Lighting.Ambient, Lighting.OutdoorAmbient = ambientBase, outdoorBase
		wroteAmbient, wroteOutdoor = nil, nil
		grade:Destroy()
		grade = nil
	end
end

function Sky.start()
	if started then
		return
	end
	started = true
	Run.RenderStepped:Connect(step)
end

return Sky
