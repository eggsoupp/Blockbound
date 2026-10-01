--[[
	Sounds

	Plays the things SoundConfig describes, without letting them pile up.

		Sounds.play("ui.click")                     -- 2D, at the listener
		Sounds.playAt("mine.break.stone", position) -- 3D, in the world

	Three things keep it pleasant: every play jitters PlaybackSpeed within the
	sound's `pitchVary` (identical repetition is what the ear notices), a key
	with a `throttle` refuses to replay inside that window, and 2D sounds reuse
	one instance per key rather than allocating per play.

	Calling it on the server is a no-op rather than an error, so shared code can
	call it without guarding.
]]

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SoundConfig = require(script.Parent:WaitForChild("SoundConfig"))

local Sounds = {}

local IS_CLIENT = RunService:IsClient()

-- Master volume, so everything can be ducked at once later.
Sounds.MasterVolume = 1

local pool = {} -- key -> Sound, for non-positional playback
local lastPlayed = {} -- key -> os.clock() of the previous play
local warned = {} -- key -> true, so an unknown key complains only once

local container = nil

local function getContainer()
	if container then
		return container
	end

	container = SoundService:FindFirstChild("GameSounds")
	if not container then
		container = Instance.new("Folder")
		container.Name = "GameSounds"
		container.Parent = SoundService
	end

	return container
end

-- Complains once for a typo rather than on every frame that hits it.
local function definitionFor(key)
	local definition = SoundConfig.Sounds[key]
	if definition then
		return definition
	end

	if not warned[key] then
		warned[key] = true
		warn(string.format("[Sounds] no sound configured for '%s'", tostring(key)))
	end

	return nil
end

local function isThrottled(key, definition)
	local gap = definition.throttle
	if not gap then
		return false
	end

	local now = os.clock()
	local previous = lastPlayed[key]
	if previous and now - previous < gap then
		return true
	end

	lastPlayed[key] = now
	return false
end

local function randomPitch(definition)
	local vary = definition.pitchVary or 0
	local base = definition.pitch or 1
	if vary <= 0 then
		return base
	end
	return base + (math.random() * 2 - 1) * vary
end

-- A definition's optional second layer. Layering a thud under a crack is most
-- of what makes a placeholder sound designed rather than stock. Layers never
-- throttle or pool; they live and die with the play that triggered them.
local function playLayer(layer, position, volumeScale)
	if not layer then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = layer.id
	sound.Volume = (layer.volume or 0.3) * Sounds.MasterVolume * (volumeScale or 1)
	sound.PlaybackSpeed = randomPitch(layer)

	if position then
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.CFrame = CFrame.new(position)
		anchor.Parent = workspace

		sound.RollOffMaxDistance = layer.range or 90
		sound.Parent = anchor
		sound:Play()
		Debris:AddItem(anchor, 4)
	else
		sound.Parent = getContainer()
		sound:Play()
		Debris:AddItem(sound, 4)
	end
end

-- Non-positional. One Sound per key: replaying restarts it, which is what you
-- want for UI anyway.
function Sounds.play(key, volumeScale)
	if not IS_CLIENT then
		return
	end

	local definition = definitionFor(key)
	if not definition or isThrottled(key, definition) then
		return
	end

	local sound = pool[key]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = key
		sound.SoundId = definition.id
		sound.Parent = getContainer()
		pool[key] = sound
	end

	sound.Volume = (definition.volume or 0.5) * Sounds.MasterVolume * (volumeScale or 1)
	sound.PlaybackSpeed = randomPitch(definition)
	sound.TimePosition = 0
	sound:Play()

	playLayer(definition.layer, nil, volumeScale)
end

-- Positional, on a throwaway part so it attenuates with distance. Overlapping
-- plays are fine: two blocks breaking should sound like two blocks breaking.
function Sounds.playAt(key, position, volumeScale)
	if not IS_CLIENT then
		return
	end

	local definition = definitionFor(key)
	if not definition or isThrottled(key, definition) then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "SoundAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = definition.id
	sound.Volume = (definition.volume or 0.5) * Sounds.MasterVolume * (volumeScale or 1)
	sound.PlaybackSpeed = randomPitch(definition)
	sound.RollOffMaxDistance = definition.range or 90
	sound.Parent = anchor
	sound:Play()

	Debris:AddItem(anchor, 4)

	playLayer(definition.layer, position, volumeScale)
end

-- The right variant of an action for a block's material:
--   Sounds.playBlock("mine.break", "CoalOre", position)
function Sounds.playBlock(prefix, blockName, position, volumeScale)
	local key = SoundConfig.keyFor(prefix, blockName)

	if position then
		Sounds.playAt(key, position, volumeScale)
	else
		Sounds.play(key, volumeScale)
	end
end

return Sounds
