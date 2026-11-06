-- Shared spatial playback for authored ability stages and authoritative boss cues.
-- One-shots own their hosts so a short VFX teardown cannot cut off an impact tail.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Bank = require(script.Parent.CombatSoundBank)
local Sounds = require(script.Parent.Sounds)
local Audio = {ids = {}, Bank = Bank}
local byId, active, recent = {}, {}, {}
local voices, preloaded = 0, false
for key, definition in pairs(Bank) do
	Audio.ids[key] = definition.id
	byId[definition.id] = definition
end

local function positionOf(target)
	if typeof(target) == "Vector3" then return target end
	if typeof(target) ~= "Instance" then return nil end
	if target:IsA("Attachment") then return target.WorldPosition end
	if target:IsA("BasePart") then return target.Position end
	if target:IsA("Model") then return target:GetPivot().Position end
	local part = target:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position
end

function Audio.play(key, target, volume, pitch, looped, options)
	if not RunService:IsClient() then return nil end
	local definition = Bank[key] or byId[key]
	local id = definition and definition.id or key
	if type(id) ~= "string" then return nil end
	local position = positionOf(target)
	if not position then return nil end
	options = options or {}
	local range = options.range or 230
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position-position).Magnitude > range then return nil end
	local now = os.clock()
	local bucket = id .. ":" .. math.floor(position.X/16) .. ":" .. math.floor(position.Y/16) .. ":" .. math.floor(position.Z/16)
	if now-(recent[bucket] or -math.huge) < (options.throttle or .055) or voices >= 40 then return nil end
	recent[bucket] = now
	for name, at in pairs(recent) do if now-at > 3 then recent[name] = nil end end
	local attached = looped and typeof(target)=="Instance" and (target:IsA("BasePart") or target:IsA("Attachment"))
	local host
	if not attached then
		host = Instance.new("Part")
		host.Name = "CombatSoundAnchor"
		host.Anchored, host.CanCollide, host.CanTouch, host.CanQuery = true, false, false, false
		host.Transparency, host.Size, host.Position = 1, Vector3.one, position
		host.Parent = workspace
	end
	local sound = Instance.new("Sound")
	sound.Name, sound.SoundId = key, id
	sound.PlaybackSpeed = math.clamp(pitch or 1, .3, 2.5)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance, sound.RollOffMaxDistance = options.near or 12, range
	sound.Looped = looped == true
	local base = math.min(volume or .45, 1) * (definition and definition.gain or 1)
	sound.Volume = Sounds.volume(base)
	sound:SetAttribute("CombatAudio", true)
	sound.Parent = if attached then target else host
	active[sound] = base
	voices += 1
	local cleaned = false
	local function cleanup()
		if cleaned then return end
		cleaned = true
		active[sound] = nil
		voices -= 1
		if host then host:Destroy() end
	end
	sound.Destroying:Once(cleanup)
	sound.Ended:Once(function() sound:Destroy() end)
	local clip = options.clip or (definition and definition.clip)
	if clip then
		task.delay(math.max(0, clip/sound.PlaybackSpeed-.1), function()
			if sound.Parent then TweenService:Create(sound, TweenInfo.new(.1), {Volume=0}):Play() end
		end)
	end
	local lifetime = if looped then (options.lifetime or 15)
		else ((clip or (definition and definition.duration) or 7)/sound.PlaybackSpeed + .15)
	Debris:AddItem(sound, math.min(lifetime, 30))
	sound:Play()
	return sound
end

function Audio.preload()
	if preloaded or not RunService:IsClient() then return end
	preloaded = true
	task.spawn(function()
		local batch = {}
		for _, definition in pairs(Bank) do
			local sound = Instance.new("Sound"); sound.SoundId = definition.id
			table.insert(batch, sound)
			if #batch == 8 then
				pcall(function() game:GetService("ContentProvider"):PreloadAsync(batch) end)
				for _, item in ipairs(batch) do item:Destroy() end
				batch = {}; task.wait()
			end
		end
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(batch) end)
		for _, item in ipairs(batch) do item:Destroy() end
	end)
end

function Audio.stats()
	return {voices=voices}
end

-- Persistent choreography can animate a loop without bypassing the SFX slider.
function Audio.setVolume(sound, volume)
	if not sound or active[sound] == nil or not sound.Parent then return end
	local definition = byId[sound.SoundId]
	local base = math.clamp(volume, 0, 1) * (definition and definition.gain or 1)
	active[sound] = base
	sound.Volume = Sounds.volume(base)
end

-- Existing SFX settings apply to sounds already ringing out as well as new plays.
if RunService:IsClient() then
	task.defer(function()
		local settings = require(game.ReplicatedStorage.Shared.UI.PlayerSettings)
		settings.Changed.Event:Connect(function(key)
			if key ~= "sfxVolume" then return end
			for sound, base in pairs(active) do
				if sound.Parent then sound.Volume = Sounds.volume(base) end
			end
		end)
	end)
end

return Audio
