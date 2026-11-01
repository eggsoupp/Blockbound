-- Thunderhead, built from complete pack assemblies:
--   gather  the Storm Cloud rolls in over the aim, the world darkens, and
--           Lightning Surge crackles at each spot about to be struck
--   bolts   Stylized Thunder's lightning drops on each spot with a spiky
--           ground splash (Impact #12, #37) and a ring (Impact #36), exactly
--           when the server's hit lands
--   final   the biggest strike in the middle, with impact frames and a shake
--   decay   the cloud thins, the light returns, lightning fades off the ground
local Lighting = game:GetService("Lighting")
local Plan = require(script.Parent.Parent.ThunderPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Pack = require(script.Parent.PackAssembly)

local VFX = {}
local T = Plan.Tuning
local ICE = Color3.fromRGB(235, 252, 255)
local CYAN = Color3.fromRGB(60, 225, 255)
local AZURE = Color3.fromRGB(16, 120, 225)
local TINT = {deep = AZURE, main = CYAN, hot = ICE}
-- White-hot bolts edged cyan; the storm cloud stays a heavy steel blue.
local BOLT = {deep = CYAN, main = ICE, hot = Color3.new(1, 1, 1)}
local STORM = {deep = Color3.fromRGB(128, 132, 146), main = Color3.fromRGB(128, 132, 146), hot = Color3.fromRGB(168, 172, 184)}
local live = 0
local preloaded = false

local SOUND_RUMBLE = "rbxassetid://12222208"
local SOUND_BOOM = "rbxassetid://5540424854"
local SOUND_HIT = "rbxasset://sounds/hit.wav"

function VFX.preload()
	Pack.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload({}, {SOUND_RUMBLE, SOUND_BOOM, SOUND_HIT})
end

function VFX.duration()
	return Plan.duration()
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.centre) ~= "Vector3" or typeof(payload.normal) ~= "Vector3"
		or type(payload.points) ~= "table" or type(payload.startedAt) ~= "number" then
		return false
	end
	local total = Plan.duration()
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 3 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local centre = payload.centre
	local up = Vector3.yAxis
	local finalAt = Plan.finalAt()
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "Thunderhead"
	folder.Parent = workspace
	Pack.endWithCaster(scope, payload.caster)
	local function mount(name, cframe, scale, budget)
		return Pack.mount(scope, folder, name, {cframe = cframe, scale = scale, budget = budget, tint = TINT, brightness = 2.5})
	end

	-- The storm ------------------------------------------------------------------
	local cloudAt = CFrame.new(centre + up * T.CloudHeight)
	local cloud = Pack.mount(scope, folder, "StormCloud", {cframe = cloudAt, scale = 0.4, visible = true, tint = STORM, hide = {Wind = true}})
	cloud:centreOn("Soul Cloud")
	cloud:place(cloudAt)
	cloud:fade(0)
	local gloom = mount("Thunder", CFrame.new(centre + up * T.CloudHeight * 0.5), 0.6, 40)
	gloom:only("Clouds"):stream(true)
	local grade = scope:add(Instance.new("ColorCorrectionEffect"))
	grade.Name = "ThunderheadGloom"
	grade.Parent = Lighting
	local light = Kit.light(Kit.host(folder, "Glow", CFrame.new(centre + up * 6)), CYAN, 60)

	local sparks = {}
	for i, point in ipairs(payload.points) do
		sparks[i] = mount("LightningSurge", CFrame.new(point + up), 1.2, 30)
	end
	local rim = mount("LightningSurge", CFrame.new(centre + up), 2.6, 50)
	rim:stream(true)

	local flash = 0
	local function strike(point, scale, grand)
		local frame = CFrame.lookAt(point + up * 1.5, point + up * 10)
		Pack.bolt(scope, folder, point, {tint = BOLT, scale = 5.5 * scale, height = 14 * scale, width = 7 * scale})
		-- A solid column for the instant the bolt connects.
		local column = mount("KiBlast4", CFrame.new(point), 0.75 * scale)
		column:taper(0.55)
		column:stretch(point + up * T.CloudHeight, point)
		column:beamsOn(true)
		scope:delay(0.13, function() column:beamsOn(false) end)
		mount("Impact45", frame, 0.95 * scale):burst(0.8)
		mount("Impact12", frame, 2.6 * scale):burst(1)
		mount("Impact37", frame, 2.2 * scale):burst(1)
		mount("Impact36", frame, 3.2 * scale):burst(1)
		flash = if grand then 1 else 0.7
		Kit.sound(folder, SOUND_BOOM, if grand then 0.8 else 0.5, if grand then 0.8 else 1.1 + scale * 0.1)
		Kit.sound(folder, SOUND_HIT, 0.4, 0.7)
	end

	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local arrive = Kit.smooth(elapsed / (T.Gather * 0.8))
		local leave = 1 - Kit.smooth((elapsed - finalAt - 0.35) / 0.8)
		local presence = arrive * leave
		cloud:fade(presence)
		cloud:place(cloudAt * CFrame.Angles(0, elapsed * 0.25, 0) + up * (8 * (1 - arrive)))
		grade.Brightness = -0.1 * presence + 0.2 * flash
		grade.Contrast = 0.12 * presence
		grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(205, 222, 240), presence)
		flash = math.max(flash - 0.09, 0)
		light.Brightness = 2.5 * flash
	end, {folder})

	timeline.at(0, function()
		Kit.sound(folder, SOUND_RUMBLE, 0.5, 0.4)
		ImpactFX.shake(centre, 0.4, T.Gather, 70)
	end)
	for i, point in ipairs(payload.points) do
		timeline.at(math.max(Plan.boltAt(i) - 0.35, 0), function() sparks[i]:stream(true) end)
		timeline.at(Plan.boltAt(i), function()
			sparks[i]:stream(false)
			strike(point, 1, false)
			ImpactFX.shake(point, 1.2, 0.3, 70)
		end)
	end
	timeline.at(finalAt, function()
		strike(centre, 1.6, true)
		ImpactFX.hit(centre + up * 3, {tint = CYAN, pattern = "double", shake = 2.4, shakeDuration = 0.6, punch = 8, radius = 100})
	end)
	timeline.at(finalAt + 0.4, function()
		rim:stream(false)
		gloom:stream(false)
	end)
	return true
end

return VFX
