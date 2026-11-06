-- Shared spatial playback for authored ability stages and authoritative boss cues.
-- One-shots own their hosts so a short VFX teardown cannot cut off an impact tail.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Bank = require(script.Parent.CombatSoundBank)
local Recipes = require(script.Parent.CombatRecipes)
local Sounds = require(script.Parent.Sounds)
local Audio = {ids = {}, Bank = Bank, Recipes = Recipes}
-- The deepest the music dips under a recipe whose duck is 1.
local DUCK_DEPTH = 0.55
-- Within this many studs of the camera an impact ducks the music fully; it
-- fades to nothing by twice that.
local DUCK_NEAR = 70
local byId, active, recent = {}, {}, {}
local voices, preloaded = 0, false
-- At the cap a new sound takes the oldest one-shot's voice: a tail ringing
-- out matters less than the hit landing now.
local MAX_VOICES = 48
local started = {}
local templates = {}

local function stealVoice()
	for i, sound in ipairs(started) do
		if active[sound] ~= nil and not sound.Looped then
			table.remove(started, i)
			sound:Destroy()
			return true
		end
	end
	return false
end
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

local playRecipe

function Audio.play(key, target, volume, pitch, looped, options)
	if not RunService:IsClient() then return nil end
	if Recipes[key] and not looped then
		return playRecipe(Recipes[key], target, volume, pitch, options)
	end
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
	if now-(recent[bucket] or -math.huge) < (options.throttle or .055) then return nil end
	if voices >= MAX_VOICES and not stealVoice() then return nil end
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
	-- A clone of a loaded template plays on this frame; a fresh Sound spends
	-- its first ~0.3 s loading, which is the impact landing late.
	local template = templates[id]
	local sound = if template and template.IsLoaded then template:Clone() else Instance.new("Sound")
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
	table.insert(started, sound)
	local cleaned = false
	local function cleanup()
		if cleaned then return end
		cleaned = true
		active[sound] = nil
		voices -= 1
		local index = table.find(started, sound)
		if index then table.remove(started, index) end
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
	-- Past the clip's leading silence, so the hit lands on the frame it is played.
	local start = definition and definition.start or 0
	local lifetime = if looped then (options.lifetime or 15)
		else ((clip or (definition and definition.duration or 7) - start)/sound.PlaybackSpeed + .15)
	Debris:AddItem(sound, math.min(lifetime, 30))
	if start > 0 and not looped then sound.TimePosition = start end
	sound:Play()
	return sound
end

-- A recipe: its layers at their offsets, each pitched a little differently
-- every time. The caller's volume scales the whole stack (0.6 as written) and
-- its pitch multiplies each layer's. Returns the first layer's Sound.
function playRecipe(recipe, target, volume, pitch, options)
	local position = positionOf(target)
	if not position then return nil end
	local scale = math.clamp((volume or .6)/.6, .2, 1.8)
	local layerOptions = {range = recipe.range or (options and options.range), near = recipe.near or (options and options.near)}
	local first
	for _, layer in ipairs(recipe.layers) do
		local vary = layer[5] or .04
		local p = (pitch or 1) * (layer[3] or 1) * (1 + (math.random()*2-1)*vary)
		local v = (layer[2] or .5) * scale
		local delay = layer[4] or 0
		if delay > 0 then
			task.delay(delay, Audio.play, layer[1], position, v, p, false, layerOptions)
		else
			first = Audio.play(layer[1], position, v, p, false, layerOptions) or first
		end
	end
	if recipe.duck then
		local camera = workspace.CurrentCamera
		local distance = if camera then (camera.CFrame.Position-position).Magnitude else 0
		local closeness = math.clamp(2 - distance/DUCK_NEAR, 0, 1)
		if closeness > 0 then
			local Music = require(script.Parent.Music)
			Music.duck(recipe.duck*DUCK_DEPTH*closeness*math.min(scale, 1), .25 + .35*recipe.duck)
		end
	end
	return first
end

-- Fetches every clip and keeps one silent, loaded Sound of each in
-- SoundService, so every play is a clone that starts at once (see play).
function Audio.preload()
	if preloaded or not RunService:IsClient() then return end
	preloaded = true
	task.spawn(function()
		local folder = Instance.new("Folder")
		folder.Name = "CombatAudioTemplates"
		folder.Parent = game:GetService("SoundService")
		local batch = {}
		local function flush()
			pcall(function() game:GetService("ContentProvider"):PreloadAsync(batch) end)
			batch = {}
			task.wait()
		end
		for _, definition in pairs(Bank) do
			if type(definition) == "table" and definition.id and not templates[definition.id] then
				local sound = Instance.new("Sound")
				sound.Name, sound.SoundId, sound.Volume = "Template", definition.id, 0
				sound.Parent = folder
				templates[definition.id] = sound
				table.insert(batch, sound)
				if #batch == 8 then flush() end
			end
		end
		flush()
	end)
end

-- The asset ids behind a recipe name, a bank key or an id.
function Audio.idsOf(key)
	local recipe = Recipes[key]
	if recipe then
		local ids = {}
		for _, layer in ipairs(recipe.layers) do
			local definition = Bank[layer[1]]
			if definition then table.insert(ids, definition.id) end
		end
		return ids
	end
	local definition = Bank[key] or byId[key]
	local id = definition and definition.id or key
	return if type(id) == "string" and string.find(id, "://", 1, true) then {id} else {}
end

function Audio.stats()
	return {voices=voices}
end

-- Persistent choreography can animate a loop without bypassing the SFX slider.
function Audio.setVolume(sound, volume)
	if not sound or active[sound] == nil or not sound.Parent then return end
	local definition = Bank[sound.Name] or byId[sound.SoundId]
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
