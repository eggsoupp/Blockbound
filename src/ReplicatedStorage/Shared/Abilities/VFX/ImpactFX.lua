-- Camera shake, FOV punch and impact frames for ability hits, shared by every
-- ability VFX module. All three are mixed in one render-step pair, so hits
-- that overlap add up instead of fighting: before the camera script runs, the
-- offset applied last frame is taken back off (only if nothing else moved the
-- camera since), and after everything has run it is applied again. Aim is
-- never taken away from the player.
--
-- Impact frames are the anime kind: two or three frames where the world goes
-- monochrome and the fighters near the hit turn to flat silhouettes, black on
-- white and then white on black, before colour floods back tinted.
--
-- Players with the ReducedMotion attribute get no shake, punch or frames.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local EnemyConfig = require(script.Parent.Parent.Parent.Enemies.EnemyConfig)

local ImpactFX = {}

local MAX_SHAKE = 3.2
local MAX_SILHOUETTES = 8
local shakes, punches, sequences = {}, {}, {}
local bound = false
local applied

local function reduced()
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("ReducedMotion") == true
end

-- How close the local player is to `centre`, 1 at it and 0 past `radius`.
local function nearness(centre, radius)
	if typeof(centre) ~= "Vector3" then return 1 end
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local from = if root then root.Position elseif camera then camera.CFrame.Position else centre
	return math.clamp(1 - (from - centre).Magnitude / radius, 0, 1)
end

local function restore()
	if applied then
		local camera = applied.camera
		if camera == workspace.CurrentCamera then
			if camera.CFrame == applied.cframe then camera.CFrame = applied.base end
			if camera.FieldOfView == applied.fov then camera.FieldOfView = applied.baseFov end
		end
	end
	applied = nil
end

-- Monochrome looks for the frames. Brightness and contrast push the world to
-- near-white or near-black; the silhouettes take the opposite value.
-- Highlights are drawn after colour correction, so they stay pure.
local LOOKS = {
	light = {brightness = 0.42, contrast = 1.4, saturation = -1, fill = Color3.new(0, 0, 0)},
	dark = {brightness = -0.85, contrast = 0.6, saturation = -1, fill = Color3.new(1, 1, 1)},
}

local function stepSequence(entry, now)
	local age = now - entry.started
	local frame
	for _, step in ipairs(entry.pattern) do
		if age >= step[1] then frame = step[2] end
	end
	local look = LOOKS[frame]
	local cc = entry.correction
	local strength = entry.strength
	if look and age < entry.framesEnd then
		cc.Brightness = look.brightness * strength
		cc.Contrast = look.contrast * strength
		cc.Saturation = look.saturation * strength
		cc.TintColor = if frame == "dark" then Color3.new(1, 1, 1):Lerp(entry.tint, 0.55 * strength) else Color3.new(1, 1, 1)
		for _, highlight in ipairs(entry.highlights) do
			highlight.Enabled = true
			highlight.FillColor = look.fill
		end
		return true
	end
	for _, highlight in ipairs(entry.highlights) do highlight.Enabled = false end
	-- Colour floods back, oversaturated and tinted, then settles.
	local t = math.clamp((age - entry.framesEnd) / entry.recover, 0, 1)
	local fade = (1 - t) * (1 - t) * strength
	cc.Brightness = 0.08 * fade
	cc.Contrast = 0.25 * fade
	cc.Saturation = 0.35 * fade
	cc.TintColor = Color3.new(1, 1, 1):Lerp(entry.tint, 0.35 * fade)
	return t < 1
end

local function apply()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local now = os.clock()
	local amount, kick = 0, 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local t = (now - s.started) / s.duration
		if t >= 1 then
			table.remove(shakes, i)
		else
			amount += s.strength * (1 - t) * (1 - t)
		end
	end
	for i = #punches, 1, -1 do
		local p = punches[i]
		local t = (now - p.started) / p.duration
		if t >= 1 then
			table.remove(punches, i)
		else
			-- Snaps out in the first eighth, eases home over the rest.
			local shape = if t < 0.125 then t / 0.125 else (1 - (t - 0.125) / 0.875) ^ 2
			kick += p.amount * shape
		end
	end
	for i = #sequences, 1, -1 do
		local entry = sequences[i]
		if not stepSequence(entry, now) then
			entry.correction:Destroy()
			for _, highlight in ipairs(entry.highlights) do highlight:Destroy() end
			table.remove(sequences, i)
		end
	end
	if #shakes == 0 and #punches == 0 and #sequences == 0 then
		RunService:UnbindFromRenderStep("AbilityImpactBefore")
		RunService:UnbindFromRenderStep("AbilityImpactAfter")
		bound = false
		return
	end
	amount = math.min(amount, MAX_SHAKE)
	local t = now % 512
	local x = math.noise(t * 17, 1.7) + math.sin(t * 43) * 0.3
	local y = math.noise(2.3, t * 19) + math.sin(t * 51) * 0.3
	local z = math.noise(t * 13, 5.1)
	local offset = CFrame.new(x * amount * 0.22, y * amount * 0.22, 0)
		* CFrame.Angles(math.rad(y * amount * 1.1), math.rad(x * amount * 1.1), math.rad(z * amount * 0.8))
	applied = {camera = camera, base = camera.CFrame, baseFov = camera.FieldOfView}
	camera.CFrame = camera.CFrame * offset
	camera.FieldOfView = math.clamp(camera.FieldOfView + kick, 1, 120)
	applied.cframe, applied.fov = camera.CFrame, camera.FieldOfView
end

local function ensureBound()
	if bound then return end
	bound = true
	RunService:BindToRenderStep("AbilityImpactBefore", Enum.RenderPriority.Camera.Value - 3, restore)
	RunService:BindToRenderStep("AbilityImpactAfter", Enum.RenderPriority.Last.Value + 12, apply)
end

--[[
	A decaying shake. `strength` is roughly degrees of wobble at the centre:
	0.6 is a thud, 1.5 a heavy hit, 2.5+ an explosion on top of you. It fades
	out to nothing `radius` studs from `centre` (nil centre: full strength).
]]
function ImpactFX.shake(centre, strength, duration, radius)
	if not RunService:IsClient() or reduced() then return end
	local scaled = strength * nearness(centre, radius or 90)
	if scaled <= 0.03 then return end
	table.insert(shakes, {started = os.clock(), strength = scaled, duration = duration or 0.4})
	ensureBound()
end

-- A field-of-view kick: positive widens (a blast pushing out), negative
-- narrows (a zoom onto the hit).
function ImpactFX.punch(centre, amount, duration, radius)
	if not RunService:IsClient() or reduced() then return end
	local scaled = amount * nearness(centre, radius or 80)
	if math.abs(scaled) <= 0.1 then return end
	table.insert(punches, {started = os.clock(), amount = scaled, duration = duration or 0.35})
	ensureBound()
end

-- Enemy models and player characters within `radius` of `centre`, nearest
-- first, for silhouettes.
function ImpactFX.fightersNear(centre, radius, extra)
	local found, seen = {}, {}
	local function consider(model, position)
		if seen[model] then return end
		seen[model] = true
		local distance = (position - centre).Magnitude
		if distance <= radius then table.insert(found, {model = model, distance = distance}) end
	end
	local folder = workspace:FindFirstChild(EnemyConfig.WorldFolder)
	if folder then
		for _, model in ipairs(folder:GetChildren()) do
			if model:IsA("Model") then consider(model, model:GetPivot().Position) end
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then consider(player.Character, root.Position) end
	end
	table.sort(found, function(a, b) return a.distance < b.distance end)
	local models = {}
	for _, model in ipairs(extra or {}) do
		if typeof(model) == "Instance" and not table.find(models, model) then table.insert(models, model) end
	end
	for _, item in ipairs(found) do
		if not table.find(models, item.model) then table.insert(models, item.model) end
	end
	return models
end

--[[
	Impact frames at `centre`, seen by anyone within `options.radius` (70).

	  tint         Color3 the dark frame and the recovery lean towards
	  silhouettes  Models to flatten; defaults to fighters near the centre
	  pattern      "double" (light, dark: default) or "triple" (light, dark, light)
	  strength     0..1, scales every value (default 1)
]]
function ImpactFX.frames(centre, options)
	if not RunService:IsClient() or reduced() then return end
	options = options or {}
	local near = nearness(centre, options.radius or 70)
	if near <= 0.05 then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local strength = math.clamp((options.strength or 1) * math.min(1, near * 1.6), 0, 1)
	local pattern = if options.pattern == "triple"
		then {{0, "light"}, {0.05, "dark"}, {0.1, "light"}}
		else {{0, "light"}, {0.055, "dark"}}
	local framesEnd = if options.pattern == "triple" then 0.145 else 0.115
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "AbilityImpactFrame"
	correction.Parent = camera
	local highlights = {}
	local models = options.silhouettes or ImpactFX.fightersNear(centre, options.silhouetteRadius or 28)
	for i = 1, math.min(#models, MAX_SILHOUETTES) do
		local model = models[i]
		if typeof(model) == "Instance" and model.Parent then
			local highlight = Instance.new("Highlight")
			highlight.Name = "AbilityImpactSilhouette"
			highlight.Adornee = model
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.FillTransparency = 0
			highlight.OutlineTransparency = 1
			highlight.Enabled = false
			highlight.Parent = camera
			table.insert(highlights, highlight)
		end
	end
	table.insert(sequences, {
		started = os.clock(),
		pattern = pattern,
		framesEnd = framesEnd,
		recover = options.recover or 0.28,
		strength = strength,
		tint = options.tint or Color3.new(1, 1, 1),
		correction = correction,
		highlights = highlights,
	})
	ensureBound()
end

-- The usual trio for a big hit: frames, a shake and a punch outwards.
function ImpactFX.hit(centre, options)
	options = options or {}
	ImpactFX.frames(centre, options)
	ImpactFX.shake(centre, options.shake or 1.6, options.shakeDuration or 0.5, options.shakeRadius)
	if options.punch ~= 0 then
		ImpactFX.punch(centre, options.punch or 6, options.punchDuration or 0.4, options.shakeRadius)
	end
end

return ImpactFX
