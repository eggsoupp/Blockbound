--[[
	Music

	The background playlist, and the one thing that owns how loud it is.

		Music.start()               -- once, from SoundHandler
		Music.setVolume(0.4)        -- 0..1
		Music.getVolume()
		Music.Changed.Event:Connect(function(volume) ... end)

	This is the ONLY thing that writes Sound.Volume. The playlist and the slider
	used to be two scripts that each believed they owned it: track changes faded
	back up to a hard-coded 1 and threw the player's choice away, and the
	slider's writes landed in the path of that fade and were overwritten on the
	next frame. Both now ask this module rather than each other.

	MUTED BY DEFAULT. DefaultVolume is 0, and while the volume is zero the Sound
	is PAUSED rather than played silently - a muted player is not streaming and
	decoding audio they cannot hear. Raising the slider resumes it.

	Persistence is Shared.UI.PlayerSettings': it calls setVolume with the
	player's saved volume once their save loads, and saves what the settings
	window sets. Until then - and for a player who has never moved the slider -
	it is DefaultVolume.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Music = {}

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

--[[
	Where the volume starts for a player who has never moved the slider.

	Zero. A player's own choice is saved (see above), so this is what someone
	who has never moved the slider hears - and the "DEFAULT" the settings
	window shows under it.
]]
Music.DefaultVolume = 0

-- The playlist, unchanged from the SoundHandler this replaces.
Music.Playlist = {
	"rbxassetid://106300420036875",
	"rbxassetid://71048743922450",
	"rbxassetid://115689743309993",
}

-- How long a track takes to fade in. Only ever fades UP to the current volume,
-- never to a hard-coded one.
Music.FadeTime = 0.5

-- The instance's name and home, kept exactly as they were so anything else
-- looking for PlayerGui.BackgroundMusic still finds it.
local SOUND_NAME = "BackgroundMusic"

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

Music.Changed = Instance.new("BindableEvent")

local volume = Music.DefaultVolume
local sound: Sound? = nil
local fade: Tween? = nil
local started = false
-- Whether a track has ever actually been loaded and played. Distinct from
-- `started`: a muted player has the Ended handler connected but no track, and
-- Resume on a Sound that has never played does nothing.
local playing = false
local lastIndex: number? = nil

local function cancelFade()
	if fade then
		fade:Cancel()
		fade:Destroy()
		fade = nil
	end
end

--[[
	Creates the Sound, or adopts one that is already there.

	Adopted rather than replaced because the old SoundHandler put one in
	PlayerGui and a place file that has been running may still have it; two
	Sounds both called BackgroundMusic playing different tracks is the exact
	failure this module exists to end.
]]
local function ensureSound(): Sound?
	if sound and sound.Parent then
		return sound
	end

	local player = Players.LocalPlayer
	if not player then
		return nil
	end

	local playerGui = player:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild(SOUND_NAME)
	if existing and existing:IsA("Sound") then
		sound = existing
	else
		local created = Instance.new("Sound")
		created.Name = SOUND_NAME
		created.Parent = playerGui
		sound = created
	end

	local instance = sound :: Sound
	instance.Looped = false
	-- Not parented to a part, so it is already 2D; kept from the original for
	-- the case where somebody reparents it.
	instance.RollOffMinDistance = 999
	instance.Volume = volume

	return instance
end

--[[
	Applies the current volume, and pauses or resumes to match it.
]]
local function applyVolume()
	local instance = sound
	if not instance then
		return
	end

	cancelFade()
	instance.Volume = volume

	if volume <= 0 then
		if instance.IsPlaying then
			instance:Pause()
		end
	elseif playing and not instance.IsPlaying then
		instance:Resume()
	end
end

-- A track index that is not the one that just played.
local function nextIndex(): number
	local count = #Music.Playlist
	if count <= 1 then
		return 1
	end

	local index
	repeat
		index = math.random(1, count)
	until index ~= lastIndex

	lastIndex = index
	return index
end

local function playTrack(index: number)
	local instance = ensureSound()
	if not instance or not Music.Playlist[index] then
		return
	end

	cancelFade()

	instance.SoundId = Music.Playlist[index]
	instance.TimePosition = 0
	instance.Volume = 0
	instance:Play()
	playing = true

	-- Fades to the CURRENT volume, which is the whole point.
	fade = TweenService:Create(
		instance,
		TweenInfo.new(Music.FadeTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Volume = volume }
	)
	;(fade :: Tween):Play()
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function Music.getVolume(): number
	return volume
end

--[[
	Sets the music volume, 0..1.

	Direct, not tweened: this is called while somebody is dragging a slider, and
	a fade would mean the sound lags behind the knob. Any fade in progress is
	cancelled, which is what stops a track change stamping over the choice.
]]
function Music.setVolume(value: number)
	value = math.clamp(tonumber(value) or 0, 0, 1)
	if value == volume then
		return
	end

	local wasSilent = volume <= 0
	volume = value

	applyVolume()

	-- Coming off mute before the first track has ever played: start one.
	if wasSilent and volume > 0 and not playing then
		Music.start()
	end

	Music.Changed:Fire(volume)
end

--[[
	Starts the playlist. Safe to call more than once.

	Does nothing audible while muted - it registers the Ended handler and waits.
	The first track begins when the volume first goes above zero, so a player who
	never touches the slider never fetches a track at all.
]]
function Music.start()
	if not RunService:IsClient() then
		return
	end

	local instance = ensureSound()
	if not instance then
		return
	end

	if not started then
		started = true

		instance.Ended:Connect(function()
			if volume > 0 then
				playTrack(nextIndex())
			end
		end)
	end

	if volume > 0 and not instance.IsPlaying then
		playTrack(nextIndex())
	end
end

return Music
