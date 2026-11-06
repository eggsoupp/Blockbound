local CombatAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.CombatAudio)
local ImportedAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.DownloadedSounds)
-- Azure Comet, built from complete pack assemblies. Reference: a heavy blue
-- comet out of the sky, then a white-cyan lightning detonation.
--   gather  a ring of light opens high over the caster (Impact #10) and the
--           BZ1 Fireball, turned ice blue, swells inside it, spitting lightning
--   dive    it falls at the aim with Ki Blast 4's beams as its long tail, while
--           a warning glow sharpens on the ground
--   impact  a white flash, a star (Impact #12, #37), long horizontal streaks of
--           Ki Blast beam, Stylized Thunder's lightning crashing round the
--           crater and a ground ring (Impact #36) on the server's hit
--   pulses  each damage tick is a smaller crack of lightning and a ring
-- The comet's body is the pack's mesh fireball; other Parts are invisible hosts.
local Plan = require(script.Parent.Parent.CometPlan)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Pack = require(script.Parent.PackAssembly)

local VFX = {}
local T = Plan.Tuning
local ICE = Color3.fromRGB(232, 250, 255)
local CYAN = Color3.fromRGB(64, 215, 255)
local AZURE = Color3.fromRGB(20, 96, 240)
local TINT = {deep = AZURE, main = CYAN, hot = ICE}
local BOLT = {deep = CYAN, main = ICE, hot = Color3.new(1, 1, 1)}
local BODY = {deep = CYAN, main = ICE, hot = Color3.new(1, 1, 1)}
local VIEW_HEIGHT, VIEW_BEYOND = 38, 34
local live = 0
local preloaded = false

local SOUND_SWISH = CombatAudio.ids.plasma_trail
local SOUND_BOOM = CombatAudio.ids.blast_short
local SOUND_HIT = CombatAudio.ids.ice_chunk

function VFX.preload()
	Pack.preload()
	if preloaded then return end
	preloaded = true
	Kit.preload({}, {SOUND_SWISH, SOUND_BOOM, SOUND_HIT})
end

function VFX.duration()
	return Plan.duration()
end

function VFX.play(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.sky) ~= "Vector3" or typeof(payload.impact) ~= "Vector3"
		or typeof(payload.normal) ~= "Vector3" or type(payload.startedAt) ~= "number" or type(payload.seed) ~= "number" then
		return false
	end
	local total = Plan.duration()
	if workspace:GetServerTimeNow() - payload.startedAt >= total or live >= 3 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()

	local origin, impact, normal = payload.origin, payload.impact, payload.normal
	-- Drawn from the sky beyond the aim, on screen and coming at the caster,
	-- rather than from the cast's own sky point overhead where the camera never
	-- sees it. It lands on the server's point at the server's moment either way.
	local toward = (impact - origin.Position) * Vector3.new(1, 0, 1)
	toward = if toward.Magnitude > 0.1 then toward.Unit else origin.LookVector
	local sky = impact + Vector3.yAxis * VIEW_HEIGHT + toward * VIEW_BEYOND
	local impactAt = Plan.impactAt()
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "AzureComet"
	folder.Parent = workspace
	local function mount(name, cframe, scale, budget)
		return Pack.mount(scope, folder, name, {cframe = cframe, scale = scale, budget = budget, tint = TINT, brightness = 2.5})
	end

	-- A dead caster's comet never lands on the server, so it stops here too.
	Pack.endWithCaster(scope, payload.caster)

	local heading = if (impact - sky).Magnitude > 0.1 then (impact - sky).Unit else -Vector3.yAxis
	local aim = CFrame.lookAt(sky, sky + heading)

	local cometHost = Kit.host(folder, "Comet", aim)
	local comet = Pack.mount(scope, folder, "BZ1Fireball", {cframe = aim, scale = 0.5, budget = 200, tint = TINT, meshTint = BODY, brightness = 2.5, visible = true})
	comet:trailBeams("EFFECTS HOLDER")
	comet:slim(0.42)
	comet:place(aim)
	comet:stream(true)
	comet:beamsOn(true)
	local halo = mount("Impact10", aim, 1.1, 120)
	halo:stream(true)
	halo:beamsOn(true)
	local crackle = mount("LightningSurge", aim, 2.2, 40)
	crackle:stream(true)
	local tail = mount("KiBlast4", aim, 0.6)
	tail:taper(0.15)
	local cometLight = Kit.light(cometHost, CYAN, 30)

	-- The landing, shown the moment the comet leaves the sky.
	local crater = CFrame.lookAt(impact + normal * 1.5, impact + normal * 10)
	local craterHost = Kit.host(folder, "Crater", crater)
	local craterLight = Kit.light(craterHost, CYAN, 55)
	local warning = mount("LightningSurge", crater, 3, 40)

	local across = normal:Cross(heading)
	across = if across.Magnitude > 0.1 then across.Unit else Vector3.xAxis
	local forward = across:Cross(normal).Unit
	local flat = impact + normal * 3
	local streaks = {mount("KiBlast4", crater, 0.9), mount("KiBlast4", crater, 0.55)}
	for _, streak in ipairs(streaks) do streak:taper(0.05) end
	streaks[1]:stretch(flat + across * 45, flat - across * 45)
	streaks[2]:stretch(flat + forward * 26, flat - forward * 26)
	local embers

	local timeline = Kit.drive(scope, payload.startedAt, total, function(elapsed)
		local swell = 0.3 + 0.7 * Kit.smooth(elapsed / T.Charge)
		comet:rescale(math.round(swell * 10) / 10 * 1.5)
		local position, along = Plan.flight(sky, impact, elapsed)
		if elapsed < impactAt then
			local frame = CFrame.lookAt(position, position + heading)
			comet:place(frame)
			halo:place(frame)
			crackle:place(frame)
			cometHost.CFrame = frame
		end
		local flying = elapsed >= T.Charge and elapsed < impactAt
		tail:beamsOn(flying)
		if flying then
			tail:stretch(position, position - heading * (14 + 40 * along))
		end
		cometLight.Brightness = if elapsed < impactAt then 0.3 + 0.7 * swell else 0
		local age = elapsed - impactAt
		craterLight.Brightness = if age >= 0 then 2.5 * math.exp(-age * 5) else 1.2 * Kit.ramp(elapsed, T.Charge, impactAt)
		local beam = age >= 0 and age < 0.14
		for _, streak in ipairs(streaks) do streak:beamsOn(beam) end
	end, {folder})

	timeline.at(0, function()
		Kit.sound(cometHost, SOUND_SWISH, 0.5, 0.5)
		ImpactFX.shake(origin.Position, 0.25, T.Charge, 50)
	end)
	timeline.at(T.Charge, function()
		mount("Impact12", aim, 1.4):burst(1)
		warning:stream(true)
		Kit.sound(cometHost, SOUND_SWISH, 0.7, 1.1)
		ImpactFX.shake(origin.Position, 0.6, 0.25, 50)
	end)
	timeline.at(impactAt, function()
		comet:clear()
		comet:fade(0)
		halo:clear()
		crackle:clear()
		tail:clear()
		warning:stream(false)
		mount("Impact12", crater, 4.4):burst(1)
		mount("Impact37", crater, 4):burst(1)
		mount("Impact36", crater, 4):burst(1)
		mount("Impact45", crater, 1.3):burst(0.9)
		Pack.bolt(scope, folder, impact, {tint = BOLT, scale = 7, height = 15, width = 26, duration = 0.45})
		embers = mount("LightningSurge", crater, 3, 50)
		embers:stream(true)
		Kit.sound(craterHost, SOUND_BOOM, 0.9, 0.9)
		Kit.sound(craterHost, SOUND_HIT, 0.5, 0.8)
		ImpactFX.hit(impact + normal * 3, {tint = CYAN, pattern = "triple", shake = 2.6, shakeDuration = 0.7, punch = 9, radius = 100})
	end)
	for i = 1, T.Pulses do
		timeline.at(Plan.pulseAt(i), function()
			mount("Impact36", crater, 3):burst(0.9)
			mount("Impact12", crater, 1.5):burst(0.7)
			Pack.bolt(scope, folder, impact, {tint = BOLT, scale = 4.5, height = 10, width = 24, duration = 0.22})
			Kit.sound(craterHost, SOUND_HIT, 0.35, 0.6 + i * 0.1)
			ImpactFX.shake(impact, 0.8, 0.2, 60)
		end)
	end
	timeline.at(Plan.pulseAt(T.Pulses) + 0.25, function()
		if embers then embers:stream(false) end
	end)
	return true
end

return VFX
