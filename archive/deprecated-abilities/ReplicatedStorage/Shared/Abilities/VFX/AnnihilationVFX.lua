local RunService = game:GetService("RunService")
local Plan = require(script.Parent.Parent.AnnihilationPlan)
local Meshes = require(script.Parent.AnnihilationMeshes)
local BeamVFX = require(script.Parent.AnnihilationBeam)
local Imported = require(script.Parent.AnnihilationImported)
local CameraFX = require(script.Parent.AnnihilationCamera)
require(script.Parent.AnnihilationDebris)
Imported.preload()

local VFX = {}

function VFX.preload()
	Imported.preload()
	Meshes.get()
end
local layers = {
	{ name = "Rim", color = Color3.fromRGB(255, 220, 0), speed = 1 },
	{ name = "Glyphs", color = Color3.fromRGB(255, 240, 0), speed = -0.7 },
	{ name = "Core", color = Color3.fromRGB(255, 255, 110), speed = 0.5 },
}

function VFX.duration(): number
	return Plan.duration()
end

function VFX.play(payload, scope): boolean
	if typeof(payload.origin) ~= "CFrame" then
		return false
	end
	local templates = Meshes.get()
	if not templates or scope:isDead() then
		return false
	end
	local start = if type(payload.startedAt) == "number" then payload.startedAt else workspace:GetServerTimeNow()
	if workspace:GetServerTimeNow() - start >= Plan.duration() then
		return false
	end
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "AnnihilationVFX"
	folder.Parent = workspace
	local circles = {}
	for index, spec in ipairs(Plan.Tuning.Circles) do
		local circle = {}
		for layerIndex, layer in ipairs(layers) do
			local template = templates[layer.name]
			local part = template.part:Clone()
			part.Name = string.format("Circle%02d_%s", index, layer.name)
			part.Color = layer.color
			part.Parent = folder
			table.insert(circle, { part = part, template = template, layer = layer, height = (layerIndex - 1) * 0.025 })
		end
		circles[index] = circle
	end
	-- Custom mesh seal sits at the column's actual upper origin.
	local summoning = {}
	for layerIndex, layer in ipairs(layers) do
		local template = templates[layer.name]
		local part = template.part:Clone()
		part.Name = "SummoningSeal_" .. layer.name
		part.Color = layer.color
		part.Parent = folder
		table.insert(summoning, { part = part, template = template, layer = layer, height = (layerIndex - 1) * 0.08 })
	end
	local updateBeam = BeamVFX.create(payload.origin, folder, templates, scope)
	local updateImported = Imported.create(payload.origin, folder)
	CameraFX.start(payload.origin, start, scope, payload.caster)
	local clearedParticles=false
	local function update()
		local elapsed = workspace:GetServerTimeNow() - start
		if elapsed >= Plan.duration() then
			scope:destroy()
			return
		end
		updateBeam(elapsed)
		updateImported(elapsed)
		if not clearedParticles and elapsed>=Plan.circlesEnd() then
			clearedParticles=true
			for _,item in ipairs(folder:GetDescendants()) do
				if item:IsA("ParticleEmitter") then item.Enabled=false; item:Clear() end
			end
		end
		local power = Plan.beamSample(elapsed)
		for index, spec in ipairs(Plan.Tuning.Circles) do
			local scale, opacity = Plan.sample(index, elapsed)
			local age = math.max(0, elapsed - Plan.revealAt(index))
			local radius = spec.radius * math.max(scale, 0.001)
			for _, entry in ipairs(circles[index]) do
				local spin = Plan.rotation(age, elapsed - Plan.fireAt()) * spec.speed * entry.layer.speed + index * 0.27
				entry.part.Size = Vector3.new(entry.template.size.X * radius, 0.05, entry.template.size.Z * radius)
				entry.part.CFrame = payload.origin
					* CFrame.new(0, spec.height + entry.height, 0)
					* CFrame.Angles(0, spin, 0)
					* CFrame.new(entry.template.offset * radius)
				entry.part.Transparency = 1 - opacity * (0.93 + 0.07 * math.sin(age * 6 + index))
				entry.part.Color = entry.layer.color:Lerp(Color3.fromRGB(255, 255, 130), power * 0.75)
			end
		end
		local sealScale, sealOpacity = Plan.summoningSample(elapsed)
		local sealAge = math.max(0, elapsed - Plan.fireAt() + Plan.Tuning.SummoningReveal)
		local sealRadius = Plan.Tuning.SummoningRadius * math.max(sealScale, 0.001)
		for _, entry in ipairs(summoning) do
			local spin = Plan.rotation(sealAge, elapsed - Plan.fireAt()) * 0.45 * entry.layer.speed
			entry.part.Size = Vector3.new(entry.template.size.X * sealRadius, 0.08, entry.template.size.Z * sealRadius)
			entry.part.CFrame = payload.origin
				* CFrame.new(0, Plan.Tuning.BeamHeight + entry.height, 0)
				* CFrame.Angles(0, spin, 0)
				* CFrame.new(entry.template.offset * sealRadius)
			entry.part.Transparency = 1 - sealOpacity
			entry.part.Color = entry.layer.color:Lerp(Color3.fromRGB(255, 255, 130), power * 0.65)
		end
	end
	update()
	if not scope:isDead() then
		scope:add(RunService.Heartbeat:Connect(update))
	end
	return true
end

return VFX
