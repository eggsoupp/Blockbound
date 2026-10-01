-- All six presentation templates extracted from the three supplied packs.
-- Original textures, flipbooks, sequences and intra-template attachment links survive.
local ContentProvider = game:GetService("ContentProvider")
local Plan = require(script.Parent.Parent.AnnihilationPlan)
local Packs = script.Parent:WaitForChild("AnnihilationPacks")
local Imported = {}
local YELLOW = Color3.fromRGB(255, 235, 0)
local preloading = false

local function numberAttribute(instance, name, fallback)
	local value = instance:GetAttribute(name)
	return if type(value) == "number" and value == value and math.abs(value) < 1e6 then value else fallback
end

function Imported.preload()
	if preloading then return end
	preloading = true
	task.spawn(function()
		local failed = {}
		local ok, message = pcall(function()
			ContentProvider:PreloadAsync(Packs:GetDescendants(), function(asset, status)
				if status ~= Enum.AssetFetchStatus.Success then failed[asset] = true end
			end)
		end)
		local list = {}
		for asset in pairs(failed) do table.insert(list, asset) end
		if not ok or #list > 0 then
			warn("[Annihilation] Supplied VFX textures could not all load; check asset access: "
				.. table.concat(list, ", ") .. (if not ok then tostring(message) else ""))
		end
	end)
end

local function scaledSequence(value, scale)
	local points = {}
	for _, key in ipairs(value.Keypoints) do
		table.insert(points, NumberSequenceKeypoint.new(key.Time, key.Value * scale, key.Envelope * scale))
	end
	return NumberSequence.new(points)
end

function Imported.create(origin, folder)
	local phases = {
		{ name = "ElectricCharge", start = Plan.fireAt(), stop = Plan.fadeAt(), scale = 0.8, height = 0 },
		{ name = "Constellation", start = Plan.hitAt(), stop = Plan.fadeAt(), scale = 1.25, height = 0.4 },
		{ name = "Halftone", start = Plan.fireAt(), stop = Plan.fadeAt(), scale = 1.25, height = Plan.Tuning.Circles[#Plan.Tuning.Circles].height },
		{ name = "LaserFire", start = Plan.fireAt(), stop = Plan.fadeAt(), scale = 1.35, height = 0 },
		{ name = "BeamImpact", start = Plan.fireAt(), stop = Plan.fadeAt(), scale = 1.3, height = 0 },
		{ name = "Explode", start = Plan.hitAt(), stop = Plan.fadeAt() + 0.2, scale = 1.35, height = 0.3 },
	}
	local effects = {}
	for _, phase in ipairs(phases) do
		local root = Packs:WaitForChild(phase.name):Clone()
		root.Name = "Annihilation_" .. phase.name
		root.Anchored, root.CanCollide, root.CanTouch, root.CanQuery = true, false, false, false
		root.CastShadow, root.Transparency = false, 1
		-- ParticleEmitters directly on a Part sample its volume. The demo's
		-- 50-stud explosion carrier and 35-stud arm carrier spread effects too far.
		root.Size = if phase.name == "Explode" then Vector3.new(24,0.25,24) else Vector3.new(4,0.25,4)
		root.CFrame = origin * CFrame.new(0, phase.height, 0)
		root.Parent = folder
		local effect = {root = root, phase = phase, particles = {}, beams = {}, lights = {}}
		-- All imported Parts are invisible carriers; the circles remain original meshes.
		for _, item in ipairs(root:GetDescendants()) do
			if item:IsA("Attachment") then
				item.Position *= phase.scale
			elseif item:IsA("ParticleEmitter") then
				-- Remove the star sprites that outlasted the column in the supplied packs.
				if string.find(string.lower(item.Name),"star",1,true) then item:Destroy(); continue end
				item.Enabled = false
				item.Color = ColorSequence.new(YELLOW)
				-- Source packs contain large camera-depth offsets; these misplaced the VFX.
				item.ZOffset = 0
				local maximumSize = 0
				for _, key in ipairs(item.Size.Keypoints) do maximumSize = math.max(maximumSize,key.Value+key.Envelope) end
				local sizeLimit = if phase.name == "Explode" then 48 else 32
				item.Size = scaledSequence(item.Size,math.min(phase.scale,sizeLimit/math.max(maximumSize,0.001)))
				-- Tail must finish before scope cleanup, even for slow-motion source emitters.
				item.TimeScale = 1
				item.Lifetime = NumberRange.new(math.min(item.Lifetime.Min,2.5),math.min(item.Lifetime.Max,2.5))
				-- Fit motion to the actual effect footprint, instead of inheriting the
				-- source demo's 500–850 stud/second launches and enormous acceleration.
				local travel = if phase.name == "LaserFire" then 40 elseif phase.name == "Explode" then 22 else 12
				local speedLimit = travel/math.max(item.Lifetime.Max,0.1)
				local speedScale = math.min(phase.scale,speedLimit/math.max(item.Speed.Max,0.001))
				item.Speed = NumberRange.new(item.Speed.Min*speedScale,item.Speed.Max*speedScale)
				item.Acceleration = Vector3.zero
				local authoredCount = numberAttribute(item, "EmitCount", -1)
				local delay = math.clamp(numberAttribute(item, "EmitDelay", 0),0,0.85)
				local duration = math.clamp(numberAttribute(item,"EmitDuration",phase.stop-phase.start),0,phase.stop-phase.start)
				item.Rate = math.min(item.Rate, 40)
				table.insert(effect.particles, {
					item = item, start = phase.start + delay,
					stop = math.min(phase.stop,phase.start+delay+duration),
					count = math.clamp(if authoredCount >= 0 then authoredCount else math.max(4,item.Rate*0.22),1,80),
					continuous = authoredCount < 0 or numberAttribute(item,"EmitDuration",0) > 0,
					fired = false,
				})
			elseif item:IsA("Beam") then
				item.Enabled = false
				item.Color = ColorSequence.new(YELLOW)
				item.ZOffset = 0
				item.Segments = math.clamp(item.Segments,10,40)
				item.Width0 *= phase.scale
				item.Width1 *= phase.scale
				item.CurveSize0 *= phase.scale
				item.CurveSize1 *= phase.scale
				table.insert(effect.beams,item)
			elseif item:IsA("PointLight") then
				item.Enabled = false
				item.Color = YELLOW
				item.Range = math.min(item.Range * phase.scale,60)
				table.insert(effect.lights,item)
			end
		end
		local crownHeight = Plan.Tuning.Circles[#Plan.Tuning.Circles].height
		if phase.name == "LaserFire" then
			-- Keep particle sources on the crown/ground, independent of beam endpoints.
			root.Start.CFrame = CFrame.new(0,crownHeight,0) * CFrame.Angles(-math.pi/2,0,0)
			root.End.CFrame = CFrame.new(0,0.4,0) * CFrame.Angles(-math.pi/2,0,0)
			root.StartDarkness.CFrame = CFrame.new(0,crownHeight,0)
		elseif phase.name == "BeamImpact" then
			root.attachment1.Position = Vector3.new(0,0.4,0)
			root.attachment2.Position = Vector3.new(0,crownHeight,0)
		elseif phase.name == "ElectricCharge" then
			root.Start.CFrame = CFrame.new(0,crownHeight,0)
			root.End.CFrame = CFrame.new(0,0.4,0)
		elseif phase.name == "Explode" then
			local decorative = root:FindFirstChild("TransparentBeams")
			if decorative then decorative.Position = Vector3.zero end
		end
		-- Explicit world-aligned endpoints replace the source packs' horizontal
		-- arm-to-hand links and offset/curved demo beams.
		for index, beam in ipairs(effect.beams) do
			local a,b = Instance.new("Attachment"),Instance.new("Attachment")
			a.Name,b.Name = "AlignedBeamStart", "AlignedBeamEnd"
			if phase.name == "Explode" then
				local angle = (index-1)*math.pi*2/#effect.beams
				a.Position = Vector3.new(0,0.4,0)
				b.Position = Vector3.new(math.cos(angle)*12,0.4,math.sin(angle)*12)
				beam.Width0,beam.Width1 = math.min(beam.Width0,3),math.min(beam.Width1,6)
			else
				a.Position = Vector3.new(0,if phase.name == "ElectricCharge" then crownHeight else Plan.Tuning.BeamHeight,0)
				b.Position = Vector3.new(0,0.4,0)
			end
			a.Parent,b.Parent = root,root
			beam.Attachment0,beam.Attachment1 = a,b
			beam.CurveSize0,beam.CurveSize1 = 0,0
		end
		table.insert(effects,effect)
	end
	return function(elapsed)
		for _, effect in ipairs(effects) do
			local phase = effect.phase
			local active = elapsed >= phase.start and elapsed < phase.stop
			local fading = math.clamp((elapsed-phase.stop)/0.45,0,1)
			for _, entry in ipairs(effect.particles) do
				entry.item.Enabled = entry.continuous and elapsed >= entry.start and elapsed < entry.stop
				if not entry.fired and elapsed >= entry.start then
					entry.fired = true
					if elapsed-entry.start < 0.3 then entry.item:Emit(math.floor(entry.count)) end
				end
			end
			for _, item in ipairs(effect.beams) do
				item.Enabled = elapsed >= phase.start and fading < 1
				item.LocalTransparencyModifier = fading
			end
			for _, item in ipairs(effect.lights) do item.Enabled = active end
			if phase.name == "Constellation" or phase.name == "Halftone" then
				local direction = if phase.name == "Constellation" then -1 else 1
				effect.root.CFrame = origin * CFrame.new(0,phase.height,0) * CFrame.Angles(0,elapsed*.55*direction,0)
			end
		end
	end
end

return Imported
