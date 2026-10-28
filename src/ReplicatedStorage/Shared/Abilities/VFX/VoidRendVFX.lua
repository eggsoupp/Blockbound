-- Void Rend, drawn in two halves that the server sends separately:
--   leap    takeoff crater, a violet aura while hovering, and for the caster
--           their own flight, a live claw preview and the second-press input
--   strike  a crescent slash along the dive, the three-claw impact, and the
--           scars that glow, smoke and cool
-- Every visible effect is an authored particle, trail or textured Beam; Parts
-- are invisible emitter hosts only.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(script.Parent.Parent.VoidRendPlan)
local AbilityConfig = require(script.Parent.Parent.AbilityConfig)
local Library = require(script.Parent.VoidRendParticles)

local VFX = {}
local T = Plan.Tuning
local VIOLET = Color3.fromRGB(170, 92, 255)
local DEEP = Color3.fromRGB(92, 28, 190)
local PINK = Color3.fromRGB(255, 92, 196)
local HOT = Color3.fromRGB(255, 196, 242)
local WARN = Color3.fromRGB(255, 34, 64)
local INK = Color3.fromRGB(22, 8, 34)
local SHARD = Color3.fromRGB(226, 200, 255)
local live = 0
local preloaded = false
-- cast id -> true once its strike has arrived, which ends the leap's hover
local struck = {}
-- cast id -> the humanoid settings the caster's leap changed
local flights = {}

local function ns(a, b) return NumberSequence.new(a, b or a) end
local function curve(...)
	local points = {}
	for _, p in ipairs({...}) do table.insert(points, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0)) end
	return NumberSequence.new(points)
end
local function ramp(t, a, b) return math.clamp((t - a) / (b - a), 0, 1) end

local function host(parent, name, cframe, size)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Transparency = name, size or Vector3.one * 0.2, 1
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.CFrame, p.Parent = cframe, parent
	return p
end

local function attachment(parent, worldCFrame)
	local a = Instance.new("Attachment")
	a.Parent = parent
	a.WorldCFrame = worldCFrame
	return a
end

-- Flipbooks whose background is black (opaque or a dark haze): only fully
-- additive blending hides it, anything less draws a dark box.
local BLACK_BACKGROUND = {
	VoidFireA = true, VoidFireB = true, VoidFireC = true, GlowCrack = true, RayColumn = true, Rays = true,
}

--[[
	Toned on the way in. A dozen additive layers stacked over bright grass sum
	to white, so brightness is capped at 1.5.
]]
local function emitter(kind, parent, props)
	local data = Library[kind]
	local p = Instance.new("ParticleEmitter")
	p.Name = kind
	-- Layout before dependent flipbook properties; table iteration is unordered.
	p.Texture, p.FlipbookLayout = data.Texture, data.FlipbookLayout
	for key, value in pairs(data) do p[key] = value end
	p.Enabled, p.Rate, p.TimeScale = false, 0, 1
	for key, value in pairs(props or {}) do p[key] = value end
	p.Brightness = math.min(p.Brightness, 1.5)
	if BLACK_BACKGROUND[kind] then p.LightEmission = 1 end
	p.Parent = parent
	return p
end

-- Where a flat ribbon's end sits: a beam's width runs along its
-- attachments' Y axis, so Y is the horizontal side vector, not up.
local function flatFrame(position, forward)
	return CFrame.fromMatrix(position, forward, forward:Cross(Vector3.yAxis).Unit)
end

-- A ribbon lying flat on the ground between two points.
local function groundBeam(parent, from, to, width, texture, color, emission, brightness)
	local forward = (to - from).Unit
	local a0 = attachment(parent, flatFrame(from, forward))
	local a1 = attachment(parent, flatFrame(to, forward))
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Texture = texture
	beam.TextureMode, beam.TextureLength = Enum.TextureMode.Stretch, 1
	beam.FaceCamera, beam.Segments = false, 1
	beam.Width0, beam.Width1 = width, width
	beam.Color = ColorSequence.new(color)
	beam.LightEmission, beam.LightInfluence, beam.Brightness = emission, 1 - emission, brightness
	beam.Transparency = ns(1)
	beam.Enabled = false
	beam.ZOffset = 0.05
	beam.Parent = parent
	return beam, a0, a1
end

local function opacity(beam, value)
	local transparency = 1 - math.clamp(value, 0, 1)
	if beam.Transparency.Keypoints[1].Value ~= transparency then beam.Transparency = ns(transparency) end
	beam.Enabled = transparency < 0.99
end

local function sound(parent, id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed = id, volume, pitch
	s.RollOffMinDistance, s.RollOffMaxDistance = 10, 160
	s.Parent = parent
	s:Play()
end

local function flash(parent, range)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = VIOLET, range, 0, false
	light.Parent = parent
	return light
end

-- A short decaying camera kick for anyone close enough to feel it.
local function shake(scope, centre, strength)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local distance = if root then (root.Position - centre).Magnitude else 0
	local amount = strength * math.clamp(1 - distance / 70, 0, 1)
	if amount <= 0.05 then return end
	local name = "VoidRendShake" .. tostring(math.random(1, 1e9))
	local started = os.clock()
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - started
		if t > 0.45 then RunService:UnbindFromRenderStep(name); return end
		local a = amount * (1 - t / 0.45)
		local camera = workspace.CurrentCamera
		camera.CFrame *= CFrame.Angles(math.rad(math.noise(t * 30, 1) * a), math.rad(math.noise(t * 30, 2) * a), 0)
	end)
	scope:add(function() pcall(RunService.UnbindFromRenderStep, RunService, name) end)
end

local function rayParams()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclude, player.Character) end
	end
	p.FilterDescendantsInstances = exclude
	p.RespectCanCollide = true
	return p
end

-- Studio-only inspection: workspace.VoidRendFreeze (strike) or
-- VoidRendFreezeLeap (leap) holds that half at that many seconds. The frame
-- is moved out of the scope so it outlives the cast; whoever set the
-- attribute clears the "VoidRendFrozen" folder.
local function frozen(attribute, elapsed)
	local at = RunService:IsStudio() and workspace:GetAttribute(attribute)
	return type(at) == "number" and elapsed >= at
end
local function freezeFrame(folder, root)
	local frame = Instance.new("Folder")
	frame.Name = "VoidRendFrozen"
	frame.Parent = workspace
	for _, child in ipairs(folder:GetChildren()) do child.Parent = frame end
	for _, d in ipairs(frame:GetDescendants()) do
		if d:IsA("ParticleEmitter") then d.TimeScale = 0 end
	end
	if root then root.Anchored = true end
end

function VFX.preload()
	if preloaded then return end
	preloaded = true
	task.spawn(function()
		local assets = {Library.ClawTexture, Library.ScorchTexture, Library.Trail.Texture}
		for _, data in pairs(Library) do
			if type(data) == "table" and data.Texture then table.insert(assets, data.Texture) end
		end
		local sounds = {}
		for _, id in ipairs({"rbxassetid://12222208", "rbxassetid://5540424854"}) do
			local s = Instance.new("Sound"); s.SoundId = id
			table.insert(sounds, s); table.insert(assets, s)
		end
		pcall(function() ContentProvider:PreloadAsync(assets) end)
		for _, s in ipairs(sounds) do s:Destroy() end
	end)
end

function VFX.duration() return Plan.effectDuration() end

-- The key that casts this ability for the local player, from the loadout
-- AbilityClient mirrors onto the player.
local function slotKey(abilityName)
	local loadout = string.split(Players.LocalPlayer:GetAttribute("AbilityLoadout") or "", ",")
	local slot = table.find(loadout, abilityName)
	return slot and AbilityConfig.keyForSlot(slot)
end

local function cameraFacing()
	return Plan.flat(workspace.CurrentCamera.CFrame.LookVector)
end

-- ---------------------------------------------------------------------------
-- Leap
-- ---------------------------------------------------------------------------

local function renderLeap(payload, scope)
	if typeof(payload.origin) ~= "CFrame" or typeof(payload.takeoff) ~= "Vector3"
		or type(payload.startedAt) ~= "number" or type(payload.id) ~= "string" then
		return false
	end
	local hoverEnd = T.Rise + T.MaxHover + 0.4
	local initialAge = workspace:GetServerTimeNow() - payload.startedAt
	if initialAge >= hoverEnd then return false end
	VFX.preload()

	local id = payload.id
	local origin, takeoff = payload.origin.Position, payload.takeoff
	local apex = Plan.apex(origin)
	local caster = payload.caster
	local character = caster and caster.Character
	local casterRoot = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local isCaster = caster == Players.LocalPlayer and casterRoot and humanoid
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "VoidRendLeap"
	folder.Parent = workspace

	-- Takeoff, layered: a dark crater with cracks and an ink scorch, a violet
	-- shockwave, a magenta spike burst, violet streaks, shards, sparks, dark
	-- smoke and pale dust.
	local base = host(folder, "Takeoff", CFrame.new(takeoff + Vector3.new(0, 0.2, 0)))
	local flat = attachment(base, CFrame.new(takeoff + Vector3.new(0, 0.2, 0)))
	local air = attachment(base, CFrame.new(takeoff + Vector3.new(0, 2.5, 0)))
	local layers = {
		{emitter("DarkRing", flat, {
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular, EmissionDirection = Enum.NormalId.Top,
			Speed = NumberRange.new(0.01), SpreadAngle = Vector2.zero, Size = curve({0, 4}, {0.4, 13}, {1, 15}),
			Lifetime = NumberRange.new(0.55), FlipbookFramerate = NumberRange.new(28), Color = ColorSequence.new(DEEP, INK),
			LightEmission = 0.2, Brightness = 1.5, Transparency = curve({0, 0}, {0.7, 0.2}, {1, 1}), Rotation = NumberRange.new(0, 360),
		}), 1},
		{emitter("InkSplat", flat, {
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular, EmissionDirection = Enum.NormalId.Top,
			Speed = NumberRange.new(0.01), SpreadAngle = Vector2.zero, Size = curve({0, 5}, {0.12, 10}, {1, 11}),
			Lifetime = NumberRange.new(1.5), FlipbookFramerate = NumberRange.new(12), Color = ColorSequence.new(INK),
			LightEmission = 0, Brightness = 1, Transparency = curve({0, 0.1}, {0.6, 0.25}, {1, 1}), Rotation = NumberRange.new(0, 360),
		}), 1},
		{emitter("GlowCrack", flat, {
			Size = curve({0, 4}, {0.1, 6.5}, {1, 7}), Lifetime = NumberRange.new(0.6), Color = ColorSequence.new(VIOLET, DEEP),
			Brightness = 0.8, Transparency = curve({0, 1}, {0.06, 0.35}, {0.5, 0.6}, {1, 1}),
		}), 1},
		{emitter("Shockwave", flat, {
			Size = curve({0, 3}, {1, 20}), Lifetime = NumberRange.new(0.38), Color = ColorSequence.new(VIOLET),
			Brightness = 2, Transparency = curve({0, 0.1}, {1, 1}),
		}), 1},
		{emitter("SpikeBurst", air, {
			Orientation = Enum.ParticleOrientation.FacingCameraWorldUp, Size = ns(9), Lifetime = NumberRange.new(0.32),
			FlipbookFramerate = NumberRange.new(48), Color = ColorSequence.new(PINK, WARN), LightEmission = 1, Brightness = 2.5,
			Transparency = curve({0, 0}, {0.8, 0.1}, {1, 1}), Speed = NumberRange.new(0.01), ZOffset = 1,
		}), 2},
		{emitter("VioletStreak", air, {Color = ColorSequence.new(VIOLET), LightEmission = 1, Brightness = 2, SpreadAngle = Vector2.new(30, 30)}), 10},
		{emitter("Shards", air, {
			Size = curve({0, 1.1}, {1, 0.4}), Lifetime = NumberRange.new(0.55, 0.85), Speed = NumberRange.new(24, 42),
			SpreadAngle = Vector2.new(55, 55), Acceleration = Vector3.new(0, -70, 0), Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300), FlipbookMode = Enum.ParticleFlipbookMode.Random,
			Color = ColorSequence.new(SHARD), LightEmission = 0.6, Brightness = 2, Transparency = curve({0, 0}, {0.8, 0}, {1, 1}),
		}), 10},
		{emitter("Sparks", air, {EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(60, 60)}), 16},
		{emitter("DarkSmoke", flat, {
			Size = curve({0, 3}, {1, 8}), Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(8, 14),
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(85, 85), Drag = 3,
			Color = ColorSequence.new(DEEP, INK), LightEmission = 0.1, Brightness = 1, Transparency = curve({0, 0.3}, {1, 1}),
		}), 7},
		{emitter("Dust", flat, {
			Size = curve({0, 3}, {1, 7}), Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(90, 10),
			EmissionDirection = Enum.NormalId.Top, Drag = 3, Color = ColorSequence.new(Color3.fromRGB(215, 210, 225)),
			Transparency = curve({0, 1}, {0.1, 0.35}, {1, 1}),
		}), 5},
	}
	local liftLight = flash(base, 26)

	-- The aura around the caster while airborne: violet flame licks, motes,
	-- flat crackles and charge rings, plus a thin trail.
	local aura, trail = {}, nil
	if casterRoot then
		local core = scope:add(Instance.new("Attachment")); core.Parent = casterRoot
		table.insert(aura, scope:add(emitter("VoidFireA", core, {
			Size = curve({0, 2.2}, {1, 3.4}), Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180),
			EmissionDirection = Enum.NormalId.Top, Lifetime = NumberRange.new(0.3, 0.45), Brightness = 2,
			LockedToPart = false, Rate = 16,
		})))
		table.insert(aura, scope:add(emitter("Specs", core, {Speed = NumberRange.new(4, 12), SpreadAngle = Vector2.new(180, 180), Rate = 10})))
		table.insert(aura, scope:add(emitter("CrackleA", core, {Size = ns(4.5), Rate = 4, LockedToPart = true})))
		table.insert(aura, scope:add(emitter("Energy", core, {Color = ColorSequence.new(VIOLET), Size = curve({0, 5}, {1, 1.5}), Brightness = 4, Rate = 3, LockedToPart = true})))
		local top = scope:add(Instance.new("Attachment")); top.Position = Vector3.new(0, 1.1, 0); top.Parent = casterRoot
		local bottom = scope:add(Instance.new("Attachment")); bottom.Position = Vector3.new(0, -1.1, 0); bottom.Parent = casterRoot
		trail = scope:add(Instance.new("Trail"))
		for key, value in pairs(Library.Trail) do trail[key] = value end
		trail.Lifetime, trail.LightEmission, trail.Brightness = 0.25, 1, 3
		trail.Transparency = curve({0, 0.15}, {1, 1})
		trail.Attachment0, trail.Attachment1 = top, bottom
		trail.Parent = casterRoot
	end

	-- Latched: once the strike has taken over, the hover is finished for good.
	local over = false
	local function hovering(elapsed)
		if struck[id] then over = true end
		return not over and elapsed < hoverEnd
	end

	-- The caster's own half: flight, an aim preview and the second press.
	local preview, sent = {}, false
	if isCaster then
		local state = {autoRotate = humanoid.AutoRotate}
		flights[id] = state
		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
		caster:SetAttribute("AbilityFollowUp", payload.ability)
		scope:add(function()
			if caster:GetAttribute("AbilityFollowUp") == payload.ability then caster:SetAttribute("AbilityFollowUp", nil) end
			-- Only when no strike took over the landing.
			if not over and humanoid.Parent then
				humanoid.PlatformStand = false
				humanoid.AutoRotate = state.autoRotate
				flights[id] = nil
			end
		end)

		local previewHost = host(folder, "AimPreview", CFrame.new(apex))
		for i = 1, T.ClawCount do
			local from, to = attachment(previewHost, CFrame.new()), attachment(previewHost, CFrame.new())
			local beam = Instance.new("Beam")
			beam.Attachment0, beam.Attachment1 = from, to
			beam.Texture, beam.TextureMode, beam.TextureLength = Library.ClawTexture, Enum.TextureMode.Stretch, 1
			beam.FaceCamera, beam.Segments = false, 1
			beam.Width0, beam.Width1 = 10, 10
			beam.Color, beam.LightEmission, beam.Brightness = ColorSequence.new(WARN), 1, 2
			beam.Transparency, beam.Enabled = ns(0.35), false
			beam.Parent = previewHost
			preview[i] = {beam = beam, from = from, to = to}
		end
		local params, standing = rayParams(), humanoid.HipHeight + casterRoot.Size.Y * 0.5
		local nextAim = 0
		local function aim(elapsed)
			if os.clock() < nextAim then return end
			nextAim = os.clock() + 0.05
			local _, ground = Plan.findLanding(apex, cameraFacing(), params, standing)
			local lines = ground and Plan.claws(ground + Vector3.new(0, 0.15, 0), cameraFacing())
			local pulse = 0.25 + 0.15 * math.sin(elapsed * 14)
			for i, p in ipairs(preview) do
				local line = lines and lines[i]
				if line then
					local forward = (line.to - line.from).Unit
					p.from.WorldCFrame = flatFrame(line.from, forward)
					p.to.WorldCFrame = flatFrame(line.to, forward)
					p.beam.Transparency = ns(pulse)
				end
				p.beam.Enabled = line ~= nil and not sent
			end
		end
		scope:add(function() for _, p in ipairs(preview) do p.beam.Enabled = false end end)

		local remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("VoidRendStrike")
		local function send()
			if sent or not remote then return end
			sent = true
			remote:FireServer(cameraFacing())
			ContextActionService:UnbindAction("VoidRendStrike")
			caster:SetAttribute("AbilityFollowUp", nil)
		end
		local inputs = {Enum.UserInputType.MouseButton1}
		local key = slotKey(payload.ability)
		if key then table.insert(inputs, key) end
		ContextActionService:BindActionAtPriority("VoidRendStrike", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				send()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.ContextActionPriority.High.Value + 50, table.unpack(inputs))
		scope:add(function() ContextActionService:UnbindAction("VoidRendStrike") end)

		local last = casterRoot.Position
		scope:add(RunService.Heartbeat:Connect(function(dt)
			local elapsed = workspace:GetServerTimeNow() - payload.startedAt
			if frozen("VoidRendFreezeLeap", elapsed) then return end
			if not hovering(elapsed) or humanoid.Health <= 0 then
				for _, p in ipairs(preview) do p.beam.Enabled = false end
				return
			end
			local position = Plan.hover(origin, math.max(elapsed, 0))
			local facing = CFrame.lookAt(position, position + cameraFacing())
			local frame = if elapsed < T.Rise then facing * Plan.flip(elapsed) else facing
			casterRoot.CFrame = frame
			casterRoot.AssemblyLinearVelocity = (position - last) / math.max(dt, 1 / 240)
			casterRoot.AssemblyAngularVelocity = Vector3.zero
			last = position
			if elapsed >= T.Rise * 0.6 then aim(elapsed) end
		end))
	end

	local fired = false
	local heartbeat
	local function update(elapsed)
		if elapsed >= hoverEnd + 0.9 then scope:destroy(); return end
		if heartbeat and frozen("VoidRendFreezeLeap", elapsed) then
			heartbeat:Disconnect()
			freezeFrame(folder, casterRoot)
			return
		end
		if not fired then
			fired = true
			if elapsed < 0.3 then
				for _, layer in ipairs(layers) do layer[1]:Emit(layer[2]) end
				sound(base, "rbxassetid://12222208", 0.45, 1.25)
			end
		end
		liftLight.Brightness = math.exp(-math.max(elapsed, 0) * 8) * 2.5
		local airborne = hovering(elapsed)
		for _, e in ipairs(aura) do
			local on = airborne and elapsed >= T.Rise * 0.5
			if e.Enabled ~= on then e.Enabled = on end
		end
		if trail then trail.Enabled = airborne end
	end

	update(math.max(initialAge, 0))
	if not scope:isDead() then
		heartbeat = scope:add(RunService.Heartbeat:Connect(function() update(workspace:GetServerTimeNow() - payload.startedAt) end))
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Strike
-- ---------------------------------------------------------------------------

local function renderStrike(payload, scope)
	if typeof(payload.apex) ~= "Vector3" or typeof(payload.landing) ~= "Vector3" or typeof(payload.ground) ~= "Vector3"
		or typeof(payload.direction) ~= "Vector3" or type(payload.startedAt) ~= "number" or type(payload.id) ~= "string" then
		return false
	end
	local total = T.Dive + T.Aftermath
	local initialAge = workspace:GetServerTimeNow() - payload.startedAt
	if initialAge >= total or live >= 4 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	struck[payload.id] = true
	scope:add(function() struck[payload.id] = nil end)
	VFX.preload()

	local hit = T.Dive
	local forward = Plan.flat(payload.direction)
	local right = forward:Cross(Vector3.yAxis).Unit
	local apex, landing, ground = payload.apex, payload.landing, payload.ground
	local random = Random.new(payload.seed or 7)
	local caster = payload.caster
	local character = caster and caster.Character
	local casterRoot = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "VoidRendStrike"
	folder.Parent = workspace

	-- The caster dives from wherever their hover left them.
	local held = false
	if caster == Players.LocalPlayer and casterRoot and humanoid and initialAge < hit then
		local state = flights[payload.id] or {autoRotate = true}
		flights[payload.id] = nil
		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
		local from = casterRoot.Position
		local done = false
		local function land()
			if done or held then return end
			done = true
			if casterRoot.Parent then
				casterRoot.CFrame = CFrame.lookAt(landing, landing + forward)
				casterRoot.AssemblyLinearVelocity = Vector3.zero
				casterRoot.AssemblyAngularVelocity = Vector3.zero
			end
			if humanoid.Parent then
				humanoid.PlatformStand = false
				humanoid.AutoRotate = state.autoRotate
				humanoid:ChangeState(Enum.HumanoidStateType.Landed)
			end
		end
		scope:add(land)
		local connection
		connection = scope:add(RunService.Heartbeat:Connect(function()
			local elapsed = workspace:GetServerTimeNow() - payload.startedAt
			if frozen("VoidRendFreeze", elapsed) then return end
			if elapsed >= hit or humanoid.Health <= 0 then connection:Disconnect(); land(); return end
			local position = Plan.dive(from, landing, math.max(elapsed, 0))
			casterRoot.CFrame = CFrame.lookAt(position, position + forward) * CFrame.Angles(-math.rad(40), 0, 0)
			casterRoot.AssemblyLinearVelocity = (landing - from) / hit
			casterRoot.AssemblyAngularVelocity = Vector3.zero
		end))
	end

	local bursts = {}
	local function at(time, fn) table.insert(bursts, {at = time, fn = fn}) end

	-- The dive: a crescent in the dive's vertical plane, violet slash streaks
	-- and flame along the dive, and a trail off the caster.
	local diveVector = landing - apex
	local diveDir = if diveVector.Magnitude > 0.1 then diveVector.Unit else -Vector3.yAxis
	local arcFrame = CFrame.fromMatrix(apex + diveDir * 2, forward, right)
	local arcHost = host(folder, "Crescent", arcFrame)
	local arc = attachment(arcHost, arcFrame)
	local streakAt = attachment(arcHost, CFrame.lookAt(apex, apex - diveDir))
	local sideL = attachment(arcHost, CFrame.lookAt(apex - right * 2, apex - right * 2 - diveDir))
	local sideR = attachment(arcHost, CFrame.lookAt(apex + right * 2, apex + right * 2 - diveDir))
	local diveLayers = {
		{emitter("CrescentShadow", arc, {Size = ns(12), Lifetime = NumberRange.new(0.32)}), 5},
		{emitter("Crescent", arc, {Size = ns(10), Lifetime = NumberRange.new(0.22, 0.28), Brightness = 2}), 6},
		{emitter("CrescentFlash", arc, {Size = ns(9), LightEmission = 0.6, Brightness = 1.5}), 3},
		{emitter("SlashAlpha", arc, {Size = curve({0, 7}, {1, 10}), Color = ColorSequence.new(VIOLET), LightEmission = 0.5, Brightness = 2}), 2},
		{emitter("SlashStreak", streakAt, {Size = curve({0, 0}, {0.1, 0}, {0.29, 0.6}, {0.46, 0.4}, {1, 0})}), 30},
		{emitter("SlashLines", streakAt, {}), 12},
		{emitter("FrontFlame", streakAt, {Brightness = 1.6}), 8},
		{emitter("VoidFireB", streakAt, {Size = ns(7)}), 2},
		{emitter("SideSlash", sideL, {}), 1},
		{emitter("SideSlash", sideR, {}), 1},
	}
	at(0, function()
		for _, layer in ipairs(diveLayers) do layer[1]:Emit(layer[2]) end
		sound(arcHost, "rbxassetid://12222208", 0.4, 1.7)
	end)
	local trail
	if casterRoot then
		local top = scope:add(Instance.new("Attachment")); top.Position = Vector3.new(0, 1.2, 0); top.Parent = casterRoot
		local bottom = scope:add(Instance.new("Attachment")); bottom.Position = Vector3.new(0, -1.2, 0); bottom.Parent = casterRoot
		trail = scope:add(Instance.new("Trail"))
		for key, value in pairs(Library.Trail) do trail[key] = value end
		trail.Lifetime, trail.LightEmission, trail.Brightness = 0.3, 1, 4
		trail.Transparency = curve({0, 0}, {1, 1})
		trail.Attachment0, trail.Attachment1 = top, bottom
		trail.Parent = casterRoot
	end

	-- Three claws, each layered flat on the ground: a red warning slash while
	-- the caster dives; on impact a white-hot core, a violet glow and a deep
	-- bloom that rake out from the near end, slash streaks shooting down the
	-- line, and a ragged scorch the glow cools into.
	local RAKE = 0.07
	local claws = {}
	for index, line in ipairs(Plan.claws(ground + Vector3.new(0, 0.12, 0), forward)) do
		local length = (line.to - line.from).Magnitude
		local centre = (line.from + line.to) / 2
		local claw = host(folder, "Claw" .. index, CFrame.lookAt(centre, line.to), Vector3.new(0.4, 0.2, length))
		local near = attachment(claw, CFrame.lookAt(line.from + Vector3.new(0, 0.4, 0), line.from + Vector3.new(0, 0.4, 0) + forward))
		local lift = Vector3.new(0, 0.04, 0)
		-- The spike art tapers to nothing at both ends and fills only a tenth
		-- of the texture's width, so the lit ribbons overhang the line and are
		-- far wider than the claw they draw.
		local from, to = line.from - forward * 1.5, line.to + forward * 2.5
		local c = {from = from, to = to, ends = {}}
		local function layer(width, texture, color, emission, brightness, rise, raking)
			local beam, _, tip = groundBeam(claw, from + rise, to + rise, width, texture, color, emission, brightness)
			if raking then table.insert(c.ends, {tip = tip, rise = rise}) end
			return beam
		end
		c.warn = layer(10, Library.ClawTexture, WARN, 1, 2, lift * 1, false)
		c.scorch = layer(3, Library.ScorchTexture, INK, 0, 1, lift * 0, false)
		c.bloom = layer(24, Library.ClawTexture, Color3.fromRGB(110, 30, 220), 0.5, 1, lift * 2, true)
		c.glow = layer(13, Library.ClawTexture, VIOLET, 0.6, 1.1, lift * 3, true)
		c.core = layer(3.5, Library.ClawTexture, Color3.fromRGB(255, 215, 250), 1, 1.8, lift * 4, true)
		c.strike = {
			{emitter("SlashStreak", near, {
				EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(3, 3), Speed = NumberRange.new(60, 110),
				Size = curve({0, 0}, {0.1, 0}, {0.29, 0.9}, {0.46, 0.6}, {1, 0}), Drag = 4,
			}), 10},
			{emitter("SlashLines", near, {EmissionDirection = Enum.NormalId.Front, Speed = NumberRange.new(60, 100)}), 5},
		}
		c.burst = {
			{emitter("RayColumn", claw, {
				Orientation = Enum.ParticleOrientation.FacingCameraWorldUp, Size = curve({0, 7}, {1, 12}),
				Lifetime = NumberRange.new(0.35, 0.5), FlipbookFramerate = NumberRange.new(36), Speed = NumberRange.new(0.01),
				Color = ColorSequence.new(VIOLET, DEEP), Brightness = 1.2, ZOffset = -1,
				Transparency = curve({0, 0.25}, {0.7, 0.45}, {1, 1}),
			}), 1},
			{emitter("VoidFireA", claw, {
				Size = curve({0, 2}, {1, 3.2}), Speed = NumberRange.new(2, 6), EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(30, 30), Lifetime = NumberRange.new(0.3, 0.4), LockedToPart = false,
				Color = ColorSequence.new(VIOLET, DEEP), Brightness = 1,
			}), 2},
			{emitter("SlashFireA", claw, {EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(25, 25)}), 3},
			{emitter("Sparks", claw, {EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(70, 70)}), 10},
			{emitter("Glints", claw, {EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(80, 80),
				Speed = NumberRange.new(8, 22), Brightness = 4}), 4},
			{emitter("Star", claw, {Speed = NumberRange.new(10, 30), Size = curve({0, 0}, {0.4, 0.3}, {0.5, 2}, {0.6, 0.3}, {1, 0})}), 3},
		}
		c.lingering = {
			emitter("Wisp", claw, {
				Orientation = Enum.ParticleOrientation.FacingCameraWorldUp, Size = curve({0, 3}, {1, 7.5}),
				Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(5, 9), EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(8, 8), Acceleration = Vector3.new(0, 5, 0), Drag = 0.5,
				Color = ColorSequence.new(VIOLET, DEEP), LightEmission = 0.7, Brightness = 2,
				Transparency = curve({0, 1}, {0.15, 0.4}, {0.7, 0.7}, {1, 1}), Rotation = NumberRange.new(-8, 8), Rate = 12,
			}),
			emitter("VoidFireC", claw, {
				Size = curve({0, 1.4}, {1, 2.2}), Speed = NumberRange.new(1, 3), EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(20, 20), Lifetime = NumberRange.new(0.3, 0.45), LockedToPart = false, Brightness = 2.5, Rate = 7,
			}),
			emitter("Glints", claw, {
				EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(25, 25), Speed = NumberRange.new(3, 8),
				Drag = 1, Acceleration = Vector3.new(0, 3, 0), Brightness = 3, Lifetime = NumberRange.new(0.6, 1), Rate = 4,
			}),
			emitter("CrackleB", claw, {Size = ns(3.2), Rate = 2.5, LockedToPart = false}),
		}
		table.insert(claws, c)
	end

	-- The impact centre: lightning, a flat shockwave, dark cracks, shards,
	-- violet streaks, low dark smoke and dust.
	local centre = ground + forward * (T.ClawStart + T.ClawLength * 0.4)
	local impact = host(folder, "Impact", CFrame.new(centre + Vector3.new(0, 0.25, 0)))
	local impactFlat = attachment(impact, CFrame.new(centre + Vector3.new(0, 0.25, 0)))
	local impactAir = attachment(impact, CFrame.new(centre + Vector3.new(0, 2.5, 0)))
	local landFlat = attachment(impact, CFrame.new(ground + Vector3.new(0, 0.25, 0)))
	-- Violet crackle flashes from the Slash VFX pack, popping along the claws.
	local bolt = emitter("CrackleA", impactAir, {Size = ns(5.5), LockedToPart = false})
	local impactLayers = {
		{emitter("Shockwave", impactFlat, {
			Size = curve({0, 4}, {1, 22}), Lifetime = NumberRange.new(0.38), Color = ColorSequence.new(DEEP),
			Brightness = 1.2, Transparency = curve({0, 0.35}, {1, 1}),
		}), 1},
		{emitter("GlowCrack", landFlat, {
			Size = curve({0, 4}, {0.08, 7}, {1, 7.5}), Lifetime = NumberRange.new(0.7), Color = ColorSequence.new(VIOLET, DEEP),
			Brightness = 0.8, Transparency = curve({0, 1}, {0.05, 0.35}, {0.5, 0.6}, {1, 1}),
		}), 1},
		{emitter("SpikeBurst", impactAir, {
			Orientation = Enum.ParticleOrientation.FacingCameraWorldUp, Size = ns(9), Lifetime = NumberRange.new(0.3),
			FlipbookFramerate = NumberRange.new(52), Color = ColorSequence.new(PINK, DEEP), Brightness = 1.2,
			Speed = NumberRange.new(0.01), Transparency = curve({0, 0.2}, {1, 1}),
		}), 1},
		{emitter("Shards", impactAir, {
			Size = curve({0, 1.3}, {1, 0.4}), Lifetime = NumberRange.new(0.6, 0.95), Speed = NumberRange.new(28, 55),
			SpreadAngle = Vector2.new(70, 70), Acceleration = Vector3.new(0, -60, 0), Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300), FlipbookMode = Enum.ParticleFlipbookMode.Random,
			Color = ColorSequence.new(SHARD), LightEmission = 0.6, Brightness = 2, Transparency = curve({0, 0}, {0.8, 0}, {1, 1}),
		}), 18},
		{emitter("VioletStreak", impactAir, {Color = ColorSequence.new(VIOLET), LightEmission = 1, Brightness = 3, SpreadAngle = Vector2.new(25, 25)}), 10},
		{emitter("DarkSmoke", impactFlat, {
			Size = curve({0, 4}, {1, 10}), Lifetime = NumberRange.new(0.9, 1.4), Speed = NumberRange.new(10, 18),
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(85, 85), Drag = 3,
			Color = ColorSequence.new(DEEP, INK), LightEmission = 0.15, Brightness = 1, Transparency = curve({0, 0.35}, {1, 1}),
		}), 8},
		{emitter("Dust", impactFlat, {
			Size = curve({0, 2}, {1, 5}), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(90, 10),
			EmissionDirection = Enum.NormalId.Top, Drag = 3, Color = ColorSequence.new(Color3.fromRGB(150, 130, 175)),
			Transparency = curve({0, 1}, {0.1, 0.55}, {1, 1}),
		}), 4},
	}
	local light = flash(impact, 40)

	at(hit, function()
		for _, c in ipairs(claws) do
			for _, layer in ipairs(c.strike) do layer[1]:Emit(layer[2]) end
			for _, layer in ipairs(c.burst) do layer[1]:Emit(layer[2]) end
		end
		for _, layer in ipairs(impactLayers) do layer[1]:Emit(layer[2]) end
		sound(impact, "rbxassetid://5540424854", 0.45, 1.6)
		shake(scope, centre, 2.2)
	end)
	for i = 0, 3 do
		at(hit + i * 0.05, function()
			impactAir.WorldCFrame = CFrame.new(ground + forward * (T.ClawStart + random:NextNumber(2, T.ClawLength - 1))
				+ right * random:NextNumber(-3.5, 3.5) + Vector3.new(0, 1, 0))
			bolt:Emit(2)
		end)
	end

	local heartbeat
	local function update(elapsed)
		if elapsed >= total then scope:destroy(); return end
		if heartbeat and frozen("VoidRendFreeze", elapsed) then
			heartbeat:Disconnect()
			held = true
			freezeFrame(folder, casterRoot)
			return
		end
		local age = elapsed - hit
		if trail then trail.Enabled = age < 0.1 end
		local warning = if age < 0 then 0.25 + 0.6 * ramp(elapsed, 0, hit) else 0
		local core = if age < 0 then 0 else 1 - ramp(age, 0.06, 0.45)
		local flicker = 0.92 + 0.08 * math.sin(elapsed * 40)
		local glow = if age < 0 then 0 else (1 - ramp(age, T.Glow * 0.7, T.Glow + 0.35)) * flicker
		local bloom = if age < 0 then 0 else (1 - ramp(age, 0.05, 0.55)) * 0.7
		local burn = if age < 0 then 0 else ramp(age, 0.3, 0.9) * (1 - ramp(age, 1.7, 2.35)) * 0.9
		local reach = if age < 0 then 0 else ramp(age, 0, RAKE)
		local lingering = age >= 0 and age < T.Glow + 0.2
		for _, c in ipairs(claws) do
			-- The lit layers draw out from the near end, so the claws visibly rake.
			local tip = c.from:Lerp(c.to, 0.15 + 0.85 * reach)
			for _, e in ipairs(c.ends) do
				e.tip.WorldCFrame = flatFrame(tip + e.rise, forward)
			end
			opacity(c.warn, warning)
			opacity(c.core, core)
			opacity(c.glow, glow)
			opacity(c.bloom, bloom)
			opacity(c.scorch, burn)
			for _, e in ipairs(c.lingering) do
				if e.Enabled ~= lingering then e.Enabled = lingering end
			end
		end
		light.Brightness = if age >= 0 then math.exp(-age * 7) * 3 else 0
		for _, entry in ipairs(bursts) do
			if not entry.fired and elapsed >= entry.at then
				entry.fired = true
				if elapsed - entry.at < 0.3 then entry.fn() end
			end
		end
	end

	update(math.max(initialAge, 0))
	if not scope:isDead() then
		heartbeat = scope:add(RunService.Heartbeat:Connect(function() update(workspace:GetServerTimeNow() - payload.startedAt) end))
	end
	return true
end

function VFX.play(payload, scope)
	if payload.phase == "leap" then return renderLeap(payload, scope) end
	if payload.phase == "strike" then return renderStrike(payload, scope) end
	return false
end

return VFX
