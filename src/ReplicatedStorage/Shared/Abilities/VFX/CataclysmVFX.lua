local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Plan = require(script.Parent.Parent.CataclysmPlan)
local Library = require(script.Parent.CataclysmParticles)
local CameraFX = require(script.Parent.CataclysmCamera)
local ItemModels = require(RS.Shared.UI.ItemModels)

local VFX = {}
local ORANGE = Color3.fromRGB(255, 102, 19)
local GOLD = Color3.fromRGB(255, 211, 117)
local ASH = Color3.fromRGB(61, 48, 41)
local live = 0
local preloaded = false

local function sequence(a, b)
	return NumberSequence.new({NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b)})
end

-- Invisible hosts only. Every visible effect is an authored particle; the
-- dirt/stone meteor is the sole visible physical object created by this VFX.
local function carrier(parent, name, position)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Transparency = name, Vector3.one * 0.1, 1
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.CastShadow = false
	p.Position, p.Parent = position, parent
	return p
end

local function attachment(parent, name, position, direction)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = if direction then CFrame.lookAt(position, position + direction) else CFrame.new(position)
	a.Parent = parent
	return a
end

local function particle(kind, parent, properties)
	local p = Instance.new("ParticleEmitter")
	p.Name = kind
	-- Set layout before dependent flipbook properties; table iteration is unordered.
	p.Texture = Library[kind].Texture
	p.FlipbookLayout = Library[kind].FlipbookLayout
	for key, value in pairs(Library[kind]) do p[key] = value end
	p.Enabled, p.Rate, p.TimeScale, p.ZOffset = false, 0, 1, 0
	for key, value in pairs(properties or {}) do p[key] = value end
	p.Parent = parent
	return p
end

local function block(parent, name, size)
	local source = ItemModels.find(name)
	if source and not source:IsA("BasePart") then source = source:FindFirstChildWhichIsA("BasePart", true) end
	local p
	if source then
		p = source:Clone()
		for _, child in ipairs(p:GetChildren()) do
			if not (child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance")) then child:Destroy() end
		end
	else
		p = Instance.new("Part")
		p.Material = if name == "Dirt" then Enum.Material.Ground else Enum.Material.Slate
		p.Color = if name == "Dirt" then Color3.fromRGB(107, 73, 48) else Color3.fromRGB(106, 103, 97)
	end
	p.Name = name
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.CastShadow, p.Transparency = true, 0
	p.Size = Vector3.one * size
	p.Parent = parent
	return p
end

local function opacity(p, transparency)
	if p.Transparency == transparency then return end
	p.Transparency = transparency
	-- Authored terrain blocks carry six face decals, which otherwise survive
	-- hiding the Part and leave ghost cubes after the meteor has hit.
	for _, child in ipairs(p:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") then child.Transparency = transparency end
	end
end

function VFX.preload()
	if preloaded then return end
	preloaded = true
	task.spawn(function()
		-- Preload audio as a Sound; a bare content string can be fetched as an image.
		local audio = Instance.new("Sound")
		audio.SoundId = "rbxassetid://5540424854"
		local assets = {audio}
		for _, data in pairs(Library) do table.insert(assets, data.Texture) end
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(assets, function(asset, status)
				if status ~= Enum.AssetFetchStatus.Success then warn("[Cataclysm] Asset unavailable: " .. asset) end
			end)
		end)
		audio:Destroy()
		if not ok then warn("[Cataclysm] Preload: " .. tostring(err)) end
	end)
end

function VFX.duration() return Plan.duration() end

local function render(payload, scope, previewAge)
	if typeof(payload.origin) ~= "CFrame" or type(payload.startedAt) ~= "number" then return false end
	local initialAge = previewAge or (workspace:GetServerTimeNow() - payload.startedAt)
	if initialAge >= Plan.duration() or live >= 3 then return false end
	live += 1
	scope:add(function() live -= 1 end)
	VFX.preload()
	local ground = payload.origin.Position
	local random = Random.new(payload.seed or 41)
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "CataclysmVFX"
	folder.Parent = workspace
	local casterCharacter = payload.caster and payload.caster.Character
	local meteor = Instance.new("Model")
	meteor.Name = "DirtAndStoneMeteor"
	meteor.Parent = folder
	local core = carrier(meteor, "MeteorCore", Vector3.zero)
	meteor.PrimaryPart = core
	local voxels = {}
	for x = -2, 2 do
		for y = -2, 2 do
			for z = -2, 2 do
				if x*x + y*y + z*z > 7 then continue end
				local name = if random:NextNumber() < 0.32 then "Dirt" else "Stone"
				local p = block(meteor, name, Plan.Tuning.BlockSize * random:NextNumber(0.94, 1.02))
				p.CFrame = CFrame.new(Vector3.new(x, y, z) * Plan.Tuning.BlockSize)
				table.insert(voxels, p)
			end
		end
	end
	local flightEmitters = {}
	-- Keep the wake world-up while the rocky core tumbles beneath it. Emitters
	-- inside the solid core would be occluded for most of the descent.
	local wake = carrier(folder, "FlamingWake", Vector3.zero)
	for i = 1, 4 do
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(math.cos(i * math.pi/2)*9, 1, math.sin(i * math.pi/2)*9)
		a.Parent = wake
		table.insert(flightEmitters, particle("Flame", a, {
			Rate = 30, Size = sequence(17, 6), Lifetime = NumberRange.new(.4, .7),
			Speed = NumberRange.new(18, 35), SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, 48, 0), LightEmission = .8, Brightness = 2,
			Color = ColorSequence.new(GOLD, ORANGE), Orientation = Enum.ParticleOrientation.FacingCamera,
			Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(.65,.2),NumberSequenceKeypoint.new(1,1)}),
		}))
	end
	table.insert(flightEmitters, particle("FireballA", wake, {
		Rate = 22, Size = sequence(22, 9), Lifetime = NumberRange.new(.45,.7),
		Speed = NumberRange.new(20,40), SpreadAngle = Vector2.new(15,15), EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0,25,0), Color = ColorSequence.new(GOLD,ORANGE), Brightness = 1.3,
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(.65,.35),NumberSequenceKeypoint.new(1,1)}),
	}))
	local tail = particle("Smoke", wake, {
		Rate = 24, Size = sequence(10, 25), Speed = NumberRange.new(6, 16),
		Lifetime = NumberRange.new(.8, 1.25), Acceleration = Vector3.new(0, 28, 0),
		Color = ColorSequence.new(ASH), LightEmission = .05, Brightness = 1,
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,.45),NumberSequenceKeypoint.new(.6,.65),NumberSequenceKeypoint.new(1,1)}),
	})
	table.insert(flightEmitters, tail)
	table.insert(flightEmitters, particle("Embers", wake, {
		Rate = 55, Size = sequence(.5, 0), Lifetime = NumberRange.new(.4,.9),
		Speed = NumberRange.new(12,30), Acceleration = Vector3.new(0,20,0), Color = ColorSequence.new(GOLD, ORANGE),
	}))
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = ORANGE, 38, 1.5, false
	glow.Parent = core
	-- A particle ring anchored to the ground; no segmented geometry.
	local impact = carrier(folder, "Impact", ground + Vector3.new(0, 1.2, 0))
	local warning = particle("WarningRing", impact, {
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(.001), SpreadAngle = Vector2.zero, Drag = 0,
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0,12),NumberSequenceKeypoint.new(.14,64),NumberSequenceKeypoint.new(1,64)}),
		Lifetime = NumberRange.new(Plan.hitAt()), Color = ColorSequence.new(ORANGE,GOLD),
		LightEmission = 1, Brightness = 1.5, RotSpeed = NumberRange.new(8),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,.5),NumberSequenceKeypoint.new(.18,.1),NumberSequenceKeypoint.new(.85,.12),NumberSequenceKeypoint.new(1,1)}),
	})
	local warningSwirl = particle("PressureRing", impact, {
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(.001), SpreadAngle = Vector2.zero, Drag = 0,
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0,10),NumberSequenceKeypoint.new(.16,57),NumberSequenceKeypoint.new(1,57)}),
		Lifetime = NumberRange.new(Plan.hitAt()), Color = ColorSequence.new(ORANGE),
		LightEmission = 1, Brightness = 1.1, RotSpeed = NumberRange.new(-28), Squash = NumberSequence.new(0),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.15,.55),NumberSequenceKeypoint.new(.9,.3),NumberSequenceKeypoint.new(1,1)}),
	})
	-- Particle speed lines from the supplied explosion pack replace neon rods.
	table.insert(flightEmitters, particle("Streaks", wake, {
		Rate = 28, Size = sequence(4,0), Squash = NumberSequence.new(3),
		Speed = NumberRange.new(45,80), Lifetime = NumberRange.new(.18,.4),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(30,30),
		LockedToPart = false, Color = ColorSequence.new(GOLD), Brightness = 2,
	}))
	local bursts = {}
	local function burst(kind, parent, at, count, props)
		local emitter = particle(kind, parent, props)
		table.insert(bursts, {emitter = emitter, at = at, count = count, fired = false})
	end
	local hit = Plan.hitAt()
	local crown = attachment(impact, "FireCrown", Vector3.new(0,12,0))
	-- White-hot contact, broad rolling fire, then a rising secondary fireball.
	burst("Flash", crown, hit, 1, {
		Size = sequence(95,22), Lifetime = NumberRange.new(.18), Speed = NumberRange.new(0),
		Transparency = sequence(.05,1), Color = ColorSequence.new(GOLD), Brightness = 2.2,
	})
	burst("FireballA", crown, hit, 3, {
		Size = sequence(35,70), Lifetime = NumberRange.new(.85,1.1), Speed = NumberRange.new(16,28),
		SpreadAngle = Vector2.new(25,25), Acceleration = Vector3.new(0,15,0), Drag = 1,
		Brightness = .9, Color = ColorSequence.new(Color3.fromRGB(255,199,119)),
	})
	local upper = attachment(impact, "RisingFireball", Vector3.new(0,26,0))
	burst("FireballC", upper, hit+.16, 3, {
		Size = sequence(24,57), Lifetime = NumberRange.new(.95,1.25), Speed = NumberRange.new(28,40),
		SpreadAngle = Vector2.new(20,20), Acceleration = Vector3.new(0,12,0), Drag = 1.5,
		Brightness = .8, Color = ColorSequence.new(Color3.fromRGB(255,183,96)),
	})
	for i = 1, 10 do
		local angle = i * math.pi * 2 / 10
		local radial = Vector3.new(math.cos(angle),0,math.sin(angle))
		local a = attachment(impact, "BlastLobe", radial*18+Vector3.new(0,5,0), radial+Vector3.new(0,.35,0))
		burst(({"FireballA","FireballB","FireballC"})[(i-1)%3+1], a, hit+(i%3)*.035, 2, {
			Size = sequence(22,40), Lifetime = NumberRange.new(.8,1.15), Speed = NumberRange.new(28,48),
			SpreadAngle = Vector2.new(15,15), EmissionDirection = Enum.NormalId.Front,
			Acceleration = Vector3.new(0,12,0), Drag = 2.5, Brightness = .8,
			Color = ColorSequence.new(Color3.fromRGB(255,199,119)), Orientation = Enum.ParticleOrientation.FacingCamera,
		})
		burst("Flame", a, hit+.55+(i%3)*.07, 3, {
			Size = sequence(14,4), Lifetime = NumberRange.new(.9,1.65), Speed = NumberRange.new(10,22),
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(25,25),
			Acceleration = Vector3.new(0,10,0), Drag = 1, LightEmission = 1, Brightness = 1.3,
			Color = ColorSequence.new(GOLD,ORANGE),
			Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(.5,.2),NumberSequenceKeypoint.new(1,1)}),
		})
		-- Low radial dust jets give the shockwave volume instead of a drawn outline.
		burst("Smoke", a, hit+.12+(i%3)*.025, 4, {
			Size = sequence(9,24), Lifetime = NumberRange.new(1.4,2.3), Speed = NumberRange.new(45,72),
			EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(14,14),
			Drag = 2.2, Acceleration = Vector3.new(0,4,0), LightEmission = .15, Brightness = 1.2,
			Color = ColorSequence.new(Color3.fromRGB(161,113,67),Color3.fromRGB(79,69,61)),
			Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(.35,.35),NumberSequenceKeypoint.new(1,1)}),
		})
		burst("Smoke", a, hit+.42+(i%3)*.06, 3, {
			Size = sequence(14,34), Lifetime = NumberRange.new(2.1,3.8), Speed = NumberRange.new(12,26),
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(35,35),
			Acceleration = Vector3.new(0,11,0), Drag = 1, LightEmission = .08, Brightness = 1,
			Color = ColorSequence.new(ASH,Color3.fromRGB(32,30,28)),
			Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(.35,.25),NumberSequenceKeypoint.new(1,1)}),
		})
	end
	burst("Smoke", upper, hit+.45, 8, {
		Size = sequence(20,49), Lifetime = NumberRange.new(2.4,4.2), Speed = NumberRange.new(22,38),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(24,24), Drag = 1.2,
		Acceleration = Vector3.new(0,8,0), Color = ColorSequence.new(ASH), LightEmission = .1, Brightness = 1,
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,.35),NumberSequenceKeypoint.new(.3,.2),NumberSequenceKeypoint.new(1,1)}),
	})
	for i = 1, 3 do
		burst("PressureRing", impact, hit+(i-1)*.11, 1, {
			Size = NumberSequence.new({NumberSequenceKeypoint.new(0,12),NumberSequenceKeypoint.new(.25,75),NumberSequenceKeypoint.new(1,138+(i-1)*12)}),
			Lifetime = NumberRange.new(.55+(i-1)*.1), Speed = NumberRange.new(.01), SpreadAngle = Vector2.zero,
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular, EmissionDirection = Enum.NormalId.Top,
			Squash = NumberSequence.new(0), Color = ColorSequence.new(if i==2 then ORANGE else GOLD),
			LightEmission = 1, Brightness = 1.6, Transparency = sequence(.08,1),
		})
	end
	burst("GroundBurst", impact, hit, 1, {
		Size = sequence(45,128), Lifetime = NumberRange.new(.5), Color = ColorSequence.new(GOLD),
		LightEmission = 1, Brightness = 1.5, Speed = NumberRange.new(.001), SpreadAngle = Vector2.zero,
	})
	burst("DustRing", impact, hit+.15, 2, {
		Size = sequence(30,155), Lifetime = NumberRange.new(.85,1.1), Speed = NumberRange.new(.001), SpreadAngle = Vector2.zero,
		EmissionDirection = Enum.NormalId.Top, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Color = ColorSequence.new(Color3.fromRGB(185,141,91)), Brightness = 1.2, LightEmission = .1,
		Transparency = sequence(.3,1),
	})
	burst("SmokeShock", impact, hit+.1, 1, {
		Size = sequence(45,125), Lifetime = NumberRange.new(1.2), Speed = NumberRange.new(.01),
		EmissionDirection = Enum.NormalId.Top, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Color = ColorSequence.new(Color3.fromRGB(205,163,113)), LightEmission = .15,
		Transparency = sequence(.2,1),
	})
	burst("Rock", crown, hit+.025, 75, {
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0,1.2,.5),NumberSequenceKeypoint.new(.15,2.2,1),NumberSequenceKeypoint.new(1,.2,.1)}),
		Speed = NumberRange.new(45,100), Lifetime = NumberRange.new(.9,2.1), Drag = .6,
		SpreadAngle = Vector2.new(80,80), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0,-80,0),
		Color = ColorSequence.new(Color3.fromRGB(91,69,49)), LightInfluence = .5, Brightness = 1,
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.7,0),NumberSequenceKeypoint.new(1,1)}),
	})
	burst("Embers", crown, hit, 150, {
		Size = sequence(.85,0), Speed = NumberRange.new(50,120), Lifetime = NumberRange.new(1,2.5), Drag = .8,
		SpreadAngle = Vector2.new(130,130), Acceleration = Vector3.new(0,-30,0), Color = ColorSequence.new(GOLD,ORANGE), LightEmission = 1,
	})
	burst("Streaks", crown, hit, 38, {
		Size = sequence(5,0), Speed = NumberRange.new(90,170), Lifetime = NumberRange.new(.2,.45),
		SpreadAngle = Vector2.new(160,160), Color = ColorSequence.new(GOLD), LockedToPart = false, Brightness = 2.5,
	})
	local flashLight = Instance.new("PointLight")
	flashLight.Range, flashLight.Color, flashLight.Brightness = 85, GOLD, 0
	flashLight.Parent = impact
	local sound = Instance.new("Sound")
	sound.Name, sound.SoundId = "MeteorImpact", "rbxassetid://5540424854"
	sound.Volume, sound.PlaybackSpeed = 1.3, .68
	sound.RollOffMinDistance, sound.RollOffMaxDistance = 35, 320
	sound.Parent = impact
	local impacted = false
	if initialAge < hit then
		local remaining = hit - math.max(0,initialAge)
		warning.Lifetime, warningSwirl.Lifetime = NumberRange.new(remaining), NumberRange.new(remaining)
		if initialAge > .45 then warning.Size=NumberSequence.new(64); warningSwirl.Size=NumberSequence.new(57) end
		warning:Emit(1); warningSwirl:Emit(1)
	end
	if previewAge == nil then CameraFX.start(ground, payload.startedAt, scope) end
	local function update(elapsed)
		if elapsed >= Plan.duration() then scope:destroy(); return end
		if elapsed < hit and payload.caster then
			local humanoid = casterCharacter and casterCharacter:FindFirstChildOfClass("Humanoid")
			if not payload.caster.Parent or payload.caster.Character ~= casterCharacter or not humanoid or humanoid.Health <= 0 then
				scope:destroy(); return
			end
		end
		local age = elapsed - hit
		local flying = elapsed >= .2 and age < 0
		local position = Plan.meteorPosition(ground, elapsed)
		wake.Position = position + Vector3.new(0, 12, 0)
		meteor:PivotTo(CFrame.new(position) * CFrame.Angles(elapsed*.42, elapsed*.65, elapsed*.18))
		for _, p in ipairs(voxels) do opacity(p, if flying then math.clamp(1-elapsed/.45,0,1) else 1) end
		for _, emitter in ipairs(flightEmitters) do
			if emitter.Enabled ~= flying then emitter.Enabled = flying end
		end
		glow.Enabled = flying
		if age >= 0 and not impacted then
			impacted = true
			warning:Clear(); warningSwirl:Clear()
			if age < .3 and previewAge == nil then sound:Play() end
		end
		flashLight.Brightness = if age >= 0 then math.exp(-age*8)*8 else 0
		for _, entry in ipairs(bursts) do
			if not entry.fired and elapsed>=entry.at then
				entry.fired=true
				local lateness=elapsed-entry.at
				if lateness<.3 or (previewAge ~= nil and lateness<entry.emitter.Lifetime.Max) then entry.emitter:Emit(entry.count) end
			end
		end
	end
	update(initialAge)
	if previewAge ~= nil then
		for _, emitter in ipairs(flightEmitters) do
			if emitter.Enabled then emitter:Emit(math.ceil(emitter.Rate*.45)) end
			emitter.Enabled=false
		end
		scope:delay(.2, function()
			for _, d in ipairs(folder:GetDescendants()) do if d:IsA("ParticleEmitter") then d.TimeScale=0 end end
		end)
	elseif not scope:isDead() then
		scope:add(RunService.Heartbeat:Connect(function() update(workspace:GetServerTimeNow()-payload.startedAt) end))
		scope:delay(Plan.duration()+.1, function() scope:destroy() end)
	end
	return true
end

function VFX.play(payload, scope) return render(payload, scope) end

-- Studio-only, frozen timeline snapshots for visual inspection. Never used by a remote.
function VFX.preview(ground, elapsed, scope)
	assert(RunService:IsStudio(), "Preview is Studio-only")
	return render({origin=CFrame.new(ground),startedAt=workspace:GetServerTimeNow(),seed=41},scope,elapsed)
end

return VFX
