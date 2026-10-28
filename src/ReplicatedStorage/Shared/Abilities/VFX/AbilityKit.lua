-- Building blocks shared by the ability VFX modules: invisible emitter hosts,
-- emitters built from curated library entries, beams, trails, lights, sounds
-- and a timeline driven by the server clock.
--
-- Every visible effect made here is a ParticleEmitter, Beam or Trail. Parts
-- are anchored, invisible, non-colliding hosts only.
local RunService = game:GetService("RunService")

local Kit = {}

function Kit.ns(a, b)
	return NumberSequence.new(a, b or a)
end

-- curve({time, value, envelope?}, ...)
function Kit.curve(...)
	local points = {}
	for _, p in ipairs({...}) do
		table.insert(points, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
	end
	return NumberSequence.new(points)
end

-- colors(a, b, ...) spreads the colours evenly from 0 to 1.
function Kit.colors(...)
	local list = {...}
	if #list == 1 then return ColorSequence.new(list[1]) end
	local points = {}
	for i, color in ipairs(list) do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#list - 1), color))
	end
	return ColorSequence.new(points)
end

function Kit.ramp(t, a, b)
	return math.clamp((t - a) / (b - a), 0, 1)
end

function Kit.smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function Kit.flat(direction)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

function Kit.host(parent, name, cframe, size)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Transparency = name, size or Vector3.one * 0.2, 1
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.CFrame, p.Parent = cframe, parent
	return p
end

function Kit.attachment(parent, worldCFrame)
	local a = Instance.new("Attachment")
	a.Parent = parent
	if worldCFrame then a.WorldCFrame = worldCFrame end
	return a
end

-- Library fields that are not emitter properties.
local META = {count = true, delay = true}

--[[
	A disabled emitter built from `library[kind]`, with `props` laid over it.
	Layout is set first because flipbook properties depend on it, and table
	iteration is unordered. Rate and Enabled are off unless props turn them on.
]]
function Kit.emitter(library, kind, parent, props)
	local data = library[kind]
	assert(data, "no library entry " .. tostring(kind))
	local p = Instance.new("ParticleEmitter")
	p.Name = kind
	p.Texture = data.Texture
	if data.FlipbookLayout then p.FlipbookLayout = data.FlipbookLayout end
	for key, value in pairs(data) do
		if not META[key] then p[key] = value end
	end
	p.Enabled, p.Rate, p.TimeScale = false, 0, 1
	if props then
		if props.FlipbookLayout then p.FlipbookLayout = props.FlipbookLayout end
		for key, value in pairs(props) do p[key] = value end
	end
	p.Parent = parent
	return p
end

-- Emits every {emitter, count} pair.
function Kit.burst(layers, scale)
	for _, layer in ipairs(layers) do
		layer[1]:Emit(math.max(1, math.round(layer[2] * (scale or 1))))
	end
end

function Kit.setEnabled(emitters, on)
	for _, e in ipairs(emitters) do
		if e.Enabled ~= on then e.Enabled = on end
	end
end

function Kit.beam(parent, a0, a1, props)
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.LightInfluence = 0
	for key, value in pairs(props or {}) do beam[key] = value end
	beam.Parent = parent
	return beam
end

function Kit.trail(parent, a0, a1, props)
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.LightInfluence = 0
	for key, value in pairs(props or {}) do trail[key] = value end
	trail.Parent = parent
	return trail
end

-- Beam transparency without rebuilding the sequence every frame.
function Kit.opacity(beam, value)
	local transparency = 1 - math.clamp(value, 0, 1)
	if beam.Transparency.Keypoints[1].Value ~= transparency then
		beam.Transparency = NumberSequence.new(transparency)
	end
	local on = transparency < 0.99
	if beam.Enabled ~= on then beam.Enabled = on end
end

function Kit.light(parent, color, range)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = color, range, 0, false
	light.Parent = parent
	return light
end

function Kit.sound(parent, id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed = id, volume or 0.5, pitch or 1
	s.RollOffMinDistance, s.RollOffMaxDistance = 12, 180
	s.Parent = parent
	s:Play()
	return s
end

function Kit.rayParams(extra)
	local Players = game:GetService("Players")
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclude, player.Character) end
	end
	for _, item in ipairs(extra or {}) do table.insert(exclude, item) end
	p.FilterDescendantsInstances = exclude
	p.RespectCanCollide = true
	return p
end

-- Every texture in the given libraries (entry tables or bare ids).
function Kit.textures(...)
	local list = {}
	for _, library in ipairs({...}) do
		for _, data in pairs(library) do
			if type(data) == "table" and type(data.Texture) == "string" then table.insert(list, data.Texture) end
			if type(data) == "string" and string.find(data, "rbxasset") then table.insert(list, data) end
		end
	end
	return list
end

-- Fetches textures and sounds in the background. Bare content strings do not
-- reliably fetch images, so each id goes in through a Decal or a Sound.
function Kit.preload(textures, sounds)
	task.spawn(function()
		local assets = {}
		for _, id in ipairs(textures) do
			local decal = Instance.new("Decal")
			decal.Texture = id
			table.insert(assets, decal)
		end
		for _, id in ipairs(sounds or {}) do
			local sound = Instance.new("Sound")
			sound.SoundId = id
			table.insert(assets, sound)
		end
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(assets) end)
		for _, asset in ipairs(assets) do asset:Destroy() end
	end)
end

-- Studio-only inspection: set workspace attribute AbilityFreeze to a number
-- of seconds and every cast drawn through Kit.drive holds still at that age.
-- The held frame is moved into workspace.AbilityFrozen so it outlives the
-- cast; whoever set the attribute clears that folder.
local function frozenAt(elapsed)
	if not RunService:IsStudio() then return false end
	local at = workspace:GetAttribute("AbilityFreeze")
	return type(at) == "number" and elapsed >= at
end

local function freeze(folders)
	local frame = workspace:FindFirstChild("AbilityFrozen")
	if not frame then
		frame = Instance.new("Folder")
		frame.Name = "AbilityFrozen"
		frame.Parent = workspace
	end
	-- The children move, not the folder: the cast's scope destroys the folder.
	for _, folder in ipairs(folders) do
		for _, child in ipairs(folder:GetChildren()) do child.Parent = frame end
	end
	for _, d in ipairs(frame:GetDescendants()) do
		if d:IsA("ParticleEmitter") then d.TimeScale = 0 end
	end
end

--[[
	Runs `update(elapsed)` every frame on the server clock from `startedAt`
	until `total`, then destroys the scope. The returned timeline's
	`at(time, fn)` fires fn once when the cast reaches `time`; a client that
	joins later than `late` (0.3s) after it skips the burst instead of playing
	it out of time. `folders` are what a Studio freeze holds on to.
]]
function Kit.drive(scope, startedAt, total, update, folders)
	local events = {}
	local timeline = {}
	function timeline.at(time, fn, late)
		table.insert(events, {at = time, fn = fn, late = late or 0.3})
	end
	local connection
	local function step()
		if scope:isDead() then return end
		local elapsed = workspace:GetServerTimeNow() - startedAt
		if folders and frozenAt(elapsed) then
			connection:Disconnect()
			freeze(folders)
			return
		end
		for _, event in ipairs(events) do
			if not event.done and elapsed >= event.at then
				event.done = true
				if elapsed - event.at <= event.late then event.fn(elapsed - event.at) end
			end
		end
		if update then update(elapsed) end
		if elapsed >= total then scope:destroy() end
	end
	connection = scope:add(RunService.Heartbeat:Connect(step))
	-- First step on the next frame, after the caller has registered events.
	return timeline
end

return Kit
