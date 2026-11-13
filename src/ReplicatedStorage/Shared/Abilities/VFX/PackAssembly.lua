-- Complete SoulShroud assemblies from ReplicatedStorage.AbilityVFXLibrary
-- (assets/vfx-library), as the ability VFX modules use them. A clone keeps its
-- authored emitters, attachments, beams, curves and flipbooks; only scale,
-- colour, emission and placement are adapted here. Parts stay invisible hosts:
-- a visible part in the source is hidden unless a module asks for it with
-- `visible`, as Fireball and Water Blade do for their bodies.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Pack = {}
local Handle = {}
Handle.__index = Handle

local library = ReplicatedStorage:WaitForChild("AbilityVFXLibrary", 10)
local preloaded = false

function Pack.preload()
	if preloaded or not library then return end
	preloaded = true
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({library}) end)
	end)
end

-- Authored hue is replaced and authored value kept: white stays the hot end,
-- dim stays the deep end, and black smoke layers stay black.
local function tintColor(c, tint)
	local top, low = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	return if top < 0.1 then c else tint.main:Lerp(tint.hot, low):Lerp(tint.deep, 1 - top)
end

local function tinted(sequence, tint)
	local points = {}
	for _, key in ipairs(sequence.Keypoints) do
		table.insert(points, ColorSequenceKeypoint.new(key.Time, tintColor(key.Value, tint)))
	end
	return ColorSequence.new(points)
end

-- The same recolouring for emitters a module builds from curated data
-- (an "<Ability>Particles" table) rather than from a mounted assembly.
Pack.tint = tinted

--[[
	mount(scope, parent, name, options) clones an assembly, silent until asked.
	options: cframe, scale, tint = {deep, main, hot}, brightness (a cap),
	budget (the most particles per second it may stream), locked (particles ride
	the host, for a compact body in flight), billboard (flat discs always face
	the viewer), faceCamera (ribbon beams always face the viewer), visible (keep
	the source's meshes on show, tinted by meshTint or tint) and hide (names of parts to keep hidden).
]]
function Pack.mount(scope, parent, name, options)
	options = options or {}
	local template = options.template or (library and library:FindFirstChild(name))
	if not template then warn("[PackAssembly] Missing assembly " .. name) end
	local model = Instance.new("Model")
	if template and template:IsA("Model") then
		model = template:Clone()
	elseif template then
		template:Clone().Parent = model
	end
	model.Name = name
	scope:add(model)

	local self = setmetatable({model = model, emitters = {}, beams = {}, meshes = {}, scale = 1, base = model:GetScale()}, Handle)
	local total = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery, d.CastShadow = true, false, false, false, false
			if options.visible and d.Transparency < 1 and not (options.hide and options.hide[d.Name]) then
				table.insert(self.meshes, {v = d, alpha = d.Transparency})
				if options.meshTint or options.tint then d.Color = tintColor(d.Color, options.meshTint or options.tint) end
			else
				d.Transparency = 1
			end
		elseif d:IsA("ParticleEmitter") then
			table.insert(self.emitters, {v = d, authored = d.Enabled, rate = d.Rate})
			if d.Enabled then total += d.Rate end
			d.Enabled = false
			d.LightInfluence = 0
			if options.tint then d.Color = tinted(d.Color, options.tint) end
			if options.brightness then d.Brightness = math.min(d.Brightness, options.brightness) end
			if options.locked then d.LockedToPart = true end
			if options.billboard and d.Orientation ~= Enum.ParticleOrientation.FacingCamera then
				d.Orientation = Enum.ParticleOrientation.FacingCamera
			end
		elseif d:IsA("Beam") then
			table.insert(self.beams, d)
			d.Enabled = false
			if options.faceCamera then d.FaceCamera = true end
			if options.tint then d.Color = tinted(d.Color, options.tint) end
			if options.brightness then d.Brightness = math.min(d.Brightness, options.brightness) end
		elseif d:IsA("Light") then
			-- Off for good: pack lights are tuned for a dark showcase and bleach
			-- a daylit character. The VFX modules place their own soft lights.
			d.Enabled = false
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	local factor = if options.budget then math.min(1, options.budget / math.max(total, 1)) else 1
	for _, e in ipairs(self.emitters) do
		e.rate *= factor
		e.v.Rate = e.rate
	end
	self:rescale(options.scale or 1)
	if options.cframe then model:PivotTo(options.cframe) end
	model.Parent = parent
	return self
end

-- Scales sizes, speeds and beam widths together, relative to the size the
-- source was authored at: some pack models already carry a scale of their own.
function Handle:rescale(scale)
	if scale ~= self.scale and #self.model:GetChildren() > 0 then
		self.model:ScaleTo(self.base * scale)
		self.scale = scale
	end
end

-- Makes `place` line the assembly up by its beams: `head` lands on the CFrame
-- given, and the beams stream straight out behind it.
function Handle:trailBeams(head)
	local from = self.model:FindFirstChild(head, true)
	if not from then return end
	local flow = Vector3.zero
	for _, beam in ipairs(self.beams) do
		flow += beam.Attachment1.WorldPosition - beam.Attachment0.WorldPosition
	end
	self.offset = CFrame.lookAt(from.Position, from.Position - flow):ToObjectSpace(self.model:GetPivot())
end

-- Narrows the beams' wide ends, leaving their length.
function Handle:slim(ratio)
	for _, beam in ipairs(self.beams) do
		beam.Width0, beam.Width1 = beam.Width0 * ratio, beam.Width1 * ratio
	end
end

-- Makes `place` centre the assembly on one part, for models whose pivot sits
-- far from what shows.
function Handle:centreOn(name)
	local part = self.model:FindFirstChild(name, true)
	if part then self.offset = CFrame.new(part:GetPivot().Position):ToObjectSpace(self.model:GetPivot()) end
end

-- Makes `place` put one part at `relative` to the CFrame given, whatever the
-- model's pivot or the part's authored rotation.
function Handle:alignPart(name, relative)
	local part = self.model:FindFirstChild(name, true)
	if part then self.offset = relative * part.CFrame:ToObjectSpace(self.model:GetPivot()) end
end

-- Keeps only the additive layers, each lasting `life` times as long.
function Handle:bright(life)
	for i = #self.emitters, 1, -1 do
		local e = self.emitters[i]
		if e.v.LightEmission < 1 then
			table.remove(self.emitters, i)
		else
			local span = e.v.Lifetime
			e.v.Lifetime = NumberRange.new(span.Min * life, span.Max * life)
		end
	end
	return self
end

-- Puts a part at a world position, leaving the rest of the assembly alone.
function Handle:anchor(name, position)
	local part = self.model:FindFirstChild(name, true)
	if part then part.Position = position end
	return self
end

function Handle:place(cframe)
	self.model:PivotTo(if self.offset then cframe * self.offset else cframe)
end

-- Silences everything but the named part, whose layers then answer `burst`
-- and `stream` alone.
function Handle:only(name)
	for i = #self.emitters, 1, -1 do
		local e = self.emitters[i]
		local part = e.v:FindFirstAncestorWhichIsA("BasePart")
		if not part or part.Name ~= name then table.remove(self.emitters, i) end
	end
	return self
end

-- Squeezes a part's emission area, to aim layers authored to fall anywhere
-- across a wide patch.
function Handle:narrow(name, width)
	local part = self.model:FindFirstChild(name, true)
	if part then part.Size = Vector3.new(width, part.Size.Y, width) end
	return self
end

-- Shown meshes, 0 to 1 of their authored opacity.
function Handle:fade(alpha)
	for _, m in ipairs(self.meshes) do
		m.v.Transparency = 1 - (1 - m.alpha) * alpha
	end
end

-- Swells to `scale` while the shown meshes fade out.
function Handle:grow(scope, scale, duration)
	local from, started = self.scale, os.clock()
	local connection
	connection = scope:add(game:GetService("RunService").Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - started) / duration, 0, 1)
		self:rescale(from + (scale - from) * (1 - (1 - t) ^ 3))
		self:fade(1 - t * t)
		if t >= 1 then connection:Disconnect() end
	end))
end

-- Runs the emitters the source left on; `skip` names parts to leave silent.
function Handle:stream(on, skip)
	for _, e in ipairs(self.emitters) do
		local run = on and e.authored and not (skip and skip[e.v.Parent.Name] or (skip and e.v.Parent.Parent and skip[e.v.Parent.Parent.Name]))
		if e.v.Enabled ~= run then e.v.Enabled = run end
	end
end

-- One shot of everything, authored rates setting each layer's share.
function Handle:burst(strength)
	strength = strength or 1
	for _, e in ipairs(self.emitters) do
		local fast = e.v.Speed.Max / math.max(self.scale, 0.01) > 30
		local count = if fast then math.clamp(e.rate * 0.05, 4, 24) else math.clamp(e.rate * 0.03, 1, 4)
		e.v:Emit(math.max(1, math.round(count * strength)))
	end
end

function Handle:clear()
	for _, e in ipairs(self.emitters) do
		e.v.Enabled = false
		e.v:Clear()
	end
	self:beamsOn(false)
end

function Handle:beamsOn(on)
	for _, beam in ipairs(self.beams) do
		if beam.Enabled ~= on then beam.Enabled = on end
	end
end

-- Thins the far end and fades it out, so the authored beams read as a tail.
function Handle:taper(ratio)
	for _, beam in ipairs(self.beams) do
		beam.Width1 = beam.Width0 * ratio
		beam.Transparency = NumberSequence.new(beam.Transparency.Keypoints[1].Value, 1)
	end
end

-- Moves a beam assembly's two ends so its authored beams stretch from `head`
-- to `tail`: whole parts when the beams span two, else their attachments.
function Handle:stretch(head, tail)
	local beam = self.beams[1]
	if not beam then return end
	local near, far = beam.Attachment0, beam.Attachment1
	if near.Parent == far.Parent then
		near.WorldPosition, far.WorldPosition = head, tail
		return
	end
	local look = head - tail
	local frame = if look.Magnitude > 0.05 then CFrame.lookAt(head, head + look) else CFrame.new(head)
	for _, part in ipairs(self.model:GetChildren()) do
		if part:IsA("BasePart") then
			part.CFrame = if part == far.Parent then frame.Rotation + tail else frame
		end
	end
end

--[[
	One lightning strike from Stylized Thunder: its six bolt layers alone, at
	their authored Brightness 33, strobing on the spot. Their 0.05s life is
	stretched so a strike holds on screen. options: tint, scale, height (of the
	bolts' middle), width (of the patch they fall in) and duration.
]]
function Pack.bolt(scope, parent, ground, options)
	local bolt = Pack.mount(scope, parent, "Thunder", {cframe = CFrame.new(ground), scale = options.scale, tint = options.tint})
	bolt:only("Lightning"):bright(3):narrow("Lightning", options.width)
		:anchor("Lightning", ground + Vector3.yAxis * options.height)
	bolt:stream(true)
	scope:delay(options.duration or 0.3, function() bolt:stream(false) end)
	return bolt
end

-- Ending the cast's visuals with the caster: the server stops a cast's damage
-- on death, reset and leaving, so what it was drawing must stop too.
function Pack.endWithCaster(scope, caster)
	local character = caster and caster.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local function finish() scope:destroy() end
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	scope:add(humanoid.Died:Connect(finish))
	scope:add(caster.CharacterRemoving:Connect(finish))
	scope:add(character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then finish() end
	end))
end

return Pack
