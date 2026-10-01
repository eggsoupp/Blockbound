-- Golden annihilation column: authored mesh body, helical ribbons, beam cage,
-- moving filaments, pressure rings and separately timed particle layers.
local Plan = require(script.Parent.Parent.AnnihilationPlan)
local BeamVFX = {}
local GOLD = Color3.fromRGB(255, 235, 0)
local WHITE = Color3.fromRGB(255, 255, 130)
local ORANGE = Color3.fromRGB(255, 220, 0)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function sequence(points)
	local keys = {}
	for _, point in ipairs(points) do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keys)
end

local function attachment(parent, position)
	local a = Instance.new("Attachment")
	a.Position = position
	a.Parent = parent
	return a
end

local function beam(parent, a, b, width, color)
	local value = Instance.new("Beam")
	value.Attachment0, value.Attachment1 = a, b
	value.FaceCamera = true
	value.LightEmission = 1
	value.LightInfluence = 0
	value.Brightness = 3
	value.Segments = 12
	value.Width0, value.Width1 = width, width
	value.Color = ColorSequence.new(color)
	value.Transparency = sequence({ {0, 1}, {0.04, 0.15}, {0.85, 0.05}, {1, 1} })
	value.Enabled = false
	value.Parent = parent
	return value
end

local function particles(parent, name, texture, rate, speed, lifetime, size)
	local p = Instance.new("ParticleEmitter")
	p.Name = name
	p.Texture = texture
	p.Enabled = false
	p.Rate = rate
	p.Speed = NumberRange.new(speed * 0.7, speed)
	p.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	p.Size = sequence({ {0, size * 0.3}, {0.15, size}, {0.7, size * 0.6}, {1, 0} })
	p.Transparency = sequence({ {0, 1}, {0.08, 0.05}, {0.55, 0.2}, {1, 1} })
	p.Color = ColorSequence.new(WHITE, GOLD)
	p.LightEmission = 1
	p.LightInfluence = 0
	p.Brightness = 3
	p.EmissionDirection = Enum.NormalId.Top
	p.SpreadAngle = Vector2.new(18, 18)
	p.Rotation = NumberRange.new(0, 360)
	p.RotSpeed = NumberRange.new(-100, 100)
	p.Parent = parent
	return p
end

function BeamVFX.create(origin, folder, templates, scope)
	local height, radius = Plan.Tuning.BeamHeight, Plan.Tuning.BeamRadius
	local crownHeight = Plan.Tuning.Circles[#Plan.Tuning.Circles].height
	local cageRadius = Plan.Tuning.CageRadius
	local function mesh(name, color)
		local part = templates[name].part:Clone()
		part.Name = "Annihilation" .. name
		part.Color = color
		part.Parent = folder
		return part
	end
	-- Invisible custom mesh carries stationary world-space attachments. No primitive Parts.
	local host = mesh("Rim", GOLD)
	host.Size = Vector3.new(0.1, 0.05, 0.1)
	host.CFrame = origin
	local body = {
		{ part = mesh("Column", WHITE), radius = radius * 0.52, opacity = 0.65 },
		{ part = mesh("Column", Color3.fromRGB(255, 245, 40)), radius = radius, opacity = 0.2 },
		{ part = mesh("Column", GOLD), radius = radius * 1.2, opacity = 0.1 },
		{ part = mesh("Column", ORANGE), radius = radius * 1.42, opacity = 0.045 },
	}
	local spirals = {}
	for i = 1, 3 do spirals[i] = mesh("Helix", if i == 1 then WHITE else GOLD) end
	local pressure = {}
	for i = 1, 6 do pressure[i] = mesh("Shockwave", if i % 2 == 0 then WHITE else GOLD) end
	local collars = {}
	for i = 1, 5 do collars[i] = mesh("Rim", WHITE) end

	local cage, filaments, emitters, charge = {}, {}, {}, {}
	for i = 1, 20 do
		local angle = i * math.pi * 2 / 20
		local r = cageRadius
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		local a = attachment(host, Vector3.new(x, 0.3, z))
		local b = attachment(host, Vector3.new(x, crownHeight, z))
		local line = beam(host, a, b, 0.09, GOLD)
		table.insert(cage, { beam = line, top = b, angle = angle })
		if i % 2 == 0 then
			local sparks = particles(a, "AscendingGoldSparks", SPARK, 24, 55, 1.05, 0.65)
			sparks.Acceleration = Vector3.new(0, 26, 0)
			sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
			sparks.Squash = NumberSequence.new(-0.65)
			table.insert(emitters, sparks)
			local motes = particles(b, "SigilChargeMotes", SPARK, 1, 2, 0.5, 0.15)
			motes.EmissionDirection = Enum.NormalId.Bottom
			table.insert(charge, motes)
		end
	end
	for i = 1, 16 do
		local angle = i * math.pi * 2 / 16
		local a = attachment(host, Vector3.zero)
		local b = attachment(host, Vector3.zero)
		local line = beam(host, a, b, 0.16 + (i % 3) * 0.12, if i % 3 == 0 then WHITE else GOLD)
		line.CurveSize0, line.CurveSize1 = 2, -2
		table.insert(filaments, { beam = line, a = a, b = b, angle = angle })
	end
	local base = attachment(host, Vector3.new(0, 0.4, 0))
	local crown = attachment(host, Vector3.new(0, crownHeight, 0))
	local flare = particles(base, "IgnitionStarburst", SPARK, 0, 70, 0.85, 2.5)
	flare.SpreadAngle = Vector2.new(80, 80)
	flare.Drag = 5
	local fountain = particles(base, "WhiteHotFountain", SPARK, 110, 86, 0.95, 1.25)
	fountain.SpreadAngle = Vector2.new(9, 9)
	fountain.Acceleration = Vector3.new(0, 35, 0)
	fountain.Orientation = Enum.ParticleOrientation.VelocityParallel
	fountain.Squash = NumberSequence.new(-0.8)
	table.insert(emitters, fountain)
	local crownBurst = particles(crown, "CrownDischarge", SPARK, 35, 32, 1.1, 1.1)
	crownBurst.SpreadAngle = Vector2.new(85, 85)
	table.insert(emitters, crownBurst)
	local dusts = {}
	for i = 1, 8 do
		local angle = i * math.pi / 4
		local a = attachment(host, Vector3.new(math.cos(angle)*10, 0.3, math.sin(angle)*10))
		local dust = particles(a, "GroundPressureVapor", SMOKE, 6, 5, 1.2, 5)
		dust.Acceleration = Vector3.new(math.cos(angle)*22, 2, math.sin(angle)*22)
		dust.Color = ColorSequence.new(Color3.fromRGB(255, 235, 0), Color3.fromRGB(210, 190, 0))
		dust.LightEmission = 0.15
		dust.Brightness = 1
		dust.Transparency = sequence({ {0, 1}, {0.2, 0.72}, {1, 1} })
		table.insert(emitters, dust)
		table.insert(dusts, dust)
	end
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 55
	light.Brightness = 0
	light.Shadows = false
	light.Parent = base
	local bloom = scope:add(Instance.new("BloomEffect"))
	bloom.Name = "AnnihilationBloom"
	bloom.Intensity = 0
	bloom.Size = 38
	bloom.Threshold = 1.6
	bloom.Parent = workspace.CurrentCamera
	local fired, lastEmission, lastCharge = false, false, false
	return function(elapsed)
		local power, travel = Plan.beamSample(elapsed)
		local age = elapsed - Plan.fireAt()
		local active = age >= 0 and elapsed < Plan.fadeAt()
		local charging = elapsed > Plan.fireAt()-0.5 and age < 0
		if active ~= lastEmission then
			for _, p in ipairs(emitters) do p.Enabled = active end
			lastEmission = active
		end
		if charging ~= lastCharge then
			for _, p in ipairs(charge) do p.Enabled = charging end
			lastCharge = charging
		end
		if not fired and age >= 0 then
			fired = true
			-- Never replay the initial flash when receiving an already-running cast.
			if age < 0.35 then
				flare:Emit(85)
				crownBurst:Emit(55)
				for _, dust in ipairs(dusts) do dust:Emit(10) end
			end
		end
		local pulse = 1 + 0.06 * math.sin(age * 43) + 0.035 * math.sin(age * 71) + 0.16 * Plan.impactPulse(elapsed)
		for _, entry in ipairs(body) do
			local r = entry.radius * (0.35 + 0.65 * power) * pulse
			local length = math.max(0.05, height * travel)
			entry.part.Size = Vector3.new(r * 2, length, r * 2)
			-- The leading edge travels downward from the sky in 0.12 seconds.
			entry.part.CFrame = origin * CFrame.new(0, height - length / 2, 0)
			entry.part.Transparency = 1 - power * entry.opacity
		end
		for i, part in ipairs(spirals) do
			local r = radius * (1.18 + i * 0.09)
			part.Size = Vector3.new(r*2, height, r*2)
			part.CFrame = origin * CFrame.new(0, height/2, 0) * CFrame.Angles(0, age * (1.6 + i*.3) + i*2.1, 0)
			part.Transparency = 1 - power * 0.7
		end
		for i, entry in ipairs(cage) do
			local reveal = math.clamp((elapsed - 0.28 - (i % 5)*0.07) / 1.35, 0, 1)
			entry.top.Position = Vector3.new(math.cos(entry.angle)*cageRadius, math.max(0.35,crownHeight*reveal), math.sin(entry.angle)*cageRadius)
			entry.beam.Enabled = elapsed > 0.28 and elapsed < Plan.circlesEnd()
			entry.beam.Width0 = 0.06 + power * 0.16
			entry.beam.Width1 = entry.beam.Width0
			entry.beam.LocalTransparencyModifier = 1 - reveal * (1 - math.clamp((elapsed-Plan.fadeAt())/Plan.Tuning.Fade,0,1))
		end
		for i, entry in ipairs(filaments) do
			local y = ((age * (27+i) + i*8) % (height+24)) - 12
			local angle = entry.angle + age * 0.65
			local r = radius * (1.2 + 0.2*math.sin(age*9+i))
			entry.a.Position = Vector3.new(math.cos(angle)*r, math.clamp(y,0,height), math.sin(angle)*r)
			entry.b.Position = Vector3.new(math.cos(angle+.12)*r, math.clamp(y+14,0.05,height), math.sin(angle+.12)*r)
			entry.beam.Enabled = power > 0.01
			entry.beam.LocalTransparencyModifier = 1-power
		end
		for i, part in ipairs(pressure) do
			local ringAge = Plan.pressureAge(i, elapsed)
			local t = math.clamp(ringAge/0.84,0,1)
			local r = radius + 40*(1-(1-t)^2)
			part.Size = Vector3.new(r*2, 0.18 + (1-t)*1.4, r*2)
			part.CFrame = origin * CFrame.new(0, 0.25+i*.035, 0)
			part.Transparency = if ringAge < 0 then 1 else 1-(1-t)^2*0.8
		end
		for i, part in ipairs(collars) do
			local cycle = (math.max(age,0)*0.65+i/5)%1
			local r = radius * (1.25 + .45*cycle)
			part.Size = Vector3.new(r*2, .05, r*2)
			part.CFrame = origin * CFrame.new(0,cycle*height,0) * CFrame.Angles(0,age*.6+i,0)
			part.Transparency = 1-power*math.sin(cycle*math.pi)*.8
		end
		light.Brightness = power * 8
		local camera = workspace.CurrentCamera
		local distance = if camera then (camera.CFrame.Position-origin.Position).Magnitude else 300
		bloom.Intensity = power * .45 * math.clamp(1-distance/300,0,1)
	end
end

return BeamVFX
