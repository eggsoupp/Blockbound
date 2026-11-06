--[[
	Music

	The soundtrack, and the one thing that owns how loud it is.

		Music.start()               -- once, from SoundHandler
		Music.setVolume(0.4)        -- 0..1, the player's slider
		Music.getVolume()
		Music.Changed.Event:Connect(function(volume) ... end)

	HOW IT BEHAVES

	Exploration music is not wallpaper. A track plays through once, then the
	world goes quiet for a while (Music.Gap) before the next one - never the same
	track twice running, and every track before any repeats. The first comes a
	little after joining rather than on the loading screen.

	What plays depends on where and when (Music.Exploration): underground the
	cave theme, at night the night theme, otherwise the adventure tracks. Going
	into or out of a cave fades what is playing and brings the new place's
	music in after a short quiet; dusk and dawn only change the next track.

	A boss with a theme (Music.BossThemes, keyed by its EnemyConfig name) takes
	over the moment its fight engages: whatever is playing crossfades out and the
	boss track fades in. A boss track plays its intro once and then loops the
	section after it (the track's `loop`), so a long fight never hears the intro
	again. When the fight ends - won, lost or abandoned - it fades out slowly and
	exploration resumes after a shorter silence.

	Every change of track is a fade; nothing cuts.

	VOLUME

	This is the ONLY thing that writes Sound.Volume: each channel's volume is
	the player's volume times that channel's own fade. The slider is applied
	directly so it never lags the knob, and a fade in progress keeps fading
	underneath it. While the volume is zero both channels are PAUSED rather
	than played silently, and no new track is ever started - a player who has
	muted the music fetches nothing.

	Persistence is Shared.UI.PlayerSettings': it calls setVolume with the
	player's saved volume once their save loads, and saves what the settings
	window sets. Until then - and for a player who has never moved the slider -
	it is DefaultVolume.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Music = {}

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- Where the volume starts for a player who has never moved the slider.
Music.DefaultVolume = 0.5

--[[
	Every track. `loop` is the section a looping track repeats, in seconds:
	the Allseeingeye drop lands on beat 16 at 92 BPM (10.435 s) and the piece
	ends 176 beats later at 186 BPM (67.209 s), 44 whole bars, so the loop is
	seamless. Its reverb tail past that point is only heard when it fades out.
]]
Music.Tracks = {
	adventure1 = { id = "rbxassetid://124484841544677" },
	adventure2 = { id = "rbxassetid://73106278929619" },
	adventure3 = { id = "rbxassetid://83951189797632" },
	allseeingeye = {
		id = "rbxassetid://126221652271522",
		loop = NumberRange.new(16 * 60 / 92, 16 * 60 / 92 + 176 * 60 / 186),
	},
	-- assets/music/homeward_themes/night.wav and cave.wav. A track whose id is
	-- "" (not uploaded yet) is skipped; its place falls back to the daytime
	-- rotation, and a boss without one fights in whatever was playing.
	night = { id = "rbxassetid://140042284197785" },
	cave = { id = "rbxassetid://103728479047935" },
	-- assets/music/homeward_themes/compose_bosses.py. Each loops from its drop
	-- (beat 16 of the intro tempo) to the end of 32 bars at the body tempo.
	slimeemperor = { id = "", loop = NumberRange.new(16 * 60 / 100, 16 * 60 / 100 + 128 * 60 / 152) },
	signus = { id = "rbxassetid://97568865562147", loop = NumberRange.new(16 * 60 / 76, 16 * 60 / 76 + 128 * 60 / 168) },
	blightborer = { id = "rbxassetid://107733233221013", loop = NumberRange.new(16 * 60 / 66, 16 * 60 / 66 + 128 * 60 / 138) },
}

--[[
	The exploration rotation for each place and time. Underground wins over
	night; anything with no playable track falls back to `day`.
]]
Music.Exploration = {
	day = { "adventure1", "adventure2", "adventure3" },
	night = { "night" },
	cave = { "cave" },
}

-- EnemyConfig boss name -> its track. A boss not listed here fights in
-- whatever the world was already playing.
Music.BossThemes = {
	AllSeeingEye = "allseeingeye",
	SlimeEmperor = "slimeemperor",
	Signus = "signus",
	Blightborer = "blightborer",
}

-- Seconds of silence, as {min, max}: before the first track after joining,
-- between exploration tracks, and after a boss fight before music returns.
Music.FirstDelay = { 6, 15 }
Music.Gap = { 70, 160 }
Music.AfterBoss = { 20, 40 }
-- After moving somewhere the music belongs to a different place (into a
-- cave, out of one, nightfall): the old track fades over ContextOut and the
-- new place's music starts after this much quiet.
Music.ContextGap = { 6, 14 }
Music.ContextOut = 4

-- How long the player has to stay somewhere before it counts, so ducking
-- under a ledge or running through a short tunnel changes nothing.
Music.ContextSettle = 4

-- Fade lengths in seconds.
Music.FadeIn = 2.5 -- an exploration track arriving out of silence
Music.Crossfade = 1.5 -- whatever was playing, giving way to a boss
Music.BossIn = 0.6 -- the boss intro is quiet piano; it should not swell in
Music.BossOut = 5 -- the fight is over

-- Every id, for ContentAudit, which checks them.
Music.Playlist = {}
for _, track in pairs(Music.Tracks) do
	if track.id ~= "" then
		table.insert(Music.Playlist, track.id)
	end
end
table.sort(Music.Playlist)

local SOUND_NAMES = { "BackgroundMusic", "BackgroundMusicB" }

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

Music.Changed = Instance.new("BindableEvent")

local volume = Music.DefaultVolume
local started = false

--[[
	Two channels, so one can fade out while the other fades in.

	  sound   the Sound
	  track   the key of what is loaded, or nil
	  gain    0..1, this channel's fade
	  target  where gain is heading
	  rate    gain per second toward target
	  live    playing (or paused only for mute) and not yet finished
]]
local channels = {}

-- What the world wants to hear: a boss track key, or nil for exploration.
local bossTrack: string? = nil

-- When the next exploration track may start (os.clock()).
local nextAt = math.huge

-- Where the player is, as an Exploration key, once it has settled.
local context = "day"

-- Each place's order: shuffled, dealt one at a time, reshuffled when empty
-- so the last of one round is never the first of the next.
local bags = {}
local lastExploration: string? = nil

local function between(range)
	return range[1] + math.random() * (range[2] - range[1])
end

local function playable(key: string): boolean
	local track = Music.Tracks[key]
	return track ~= nil and track.id ~= ""
end

-- The rotation for a place, with unpublished tracks left out; day if none.
local function poolFor(place: string)
	local pool = {}
	for _, key in ipairs(Music.Exploration[place] or {}) do
		if playable(key) then
			table.insert(pool, key)
		end
	end
	if #pool == 0 and place ~= "day" then
		return poolFor("day"), "day"
	end
	return pool, place
end

local function deal(): string?
	local pool, place = poolFor(context)
	if #pool == 0 then
		return nil
	end
	local bag = bags[place]
	if not bag or #bag == 0 then
		bag = table.clone(pool)
		for i = #bag, 2, -1 do
			local j = math.random(1, i)
			bag[i], bag[j] = bag[j], bag[i]
		end
		if #bag > 1 and bag[#bag] == lastExploration then
			bag[1], bag[#bag] = bag[#bag], bag[1]
		end
		bags[place] = bag
	end
	lastExploration = table.remove(bag)
	return lastExploration
end

-- ---------------------------------------------------------------------------
-- Where the player is
-- ---------------------------------------------------------------------------

local roofParams = RaycastParams.new()
roofParams.FilterType = Enum.RaycastFilterType.Exclude
roofParams.RespectCanCollide = true

local ROOF_OFFSETS = {
	Vector3.zero, Vector3.new(7, 0, 0), Vector3.new(-7, 0, 0), Vector3.new(0, 0, 7), Vector3.new(0, 0, -7),
}

-- Trees are terrain-chunk children too, and standing under one is not a cave.
local function isTree(instance: Instance): boolean
	local node = instance
	while node and node ~= workspace do
		if string.find(node.Name, "Tree") or string.find(node.Name, "Leaves") then
			return true
		end
		node = node.Parent
	end
	return false
end

local function roofAbove(origin: Vector3, ignore): boolean
	local exclude = table.clone(ignore)
	for _ = 1, 4 do
		roofParams.FilterDescendantsInstances = exclude
		local hit = workspace:Raycast(origin, Vector3.new(0, 50, 0), roofParams)
		if not hit then
			return false
		end
		if not isTree(hit.Instance) then
			return true
		end
		table.insert(exclude, hit.Instance)
	end
	return false
end

-- Underground: solid rock over most of a small circle around the head.
local function underground(): boolean
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return false
	end
	local ignore = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local covered = 0
	for _, offset in ipairs(ROOF_OFFSETS) do
		if roofAbove(head.Position + offset, ignore) then
			covered += 1
		end
	end
	return covered >= 4
end

local function sensePlace(): string
	if underground() then
		return "cave"
	end
	local clock = game:GetService("Lighting").ClockTime
	if clock < 6 or clock >= 18 then
		return "night"
	end
	return "day"
end

-- ---------------------------------------------------------------------------
-- Channels
-- ---------------------------------------------------------------------------

--[[
	The channels live in SoundService, NOT PlayerGui: respawning clears
	PlayerGui, which used to take both Sounds with it, so dying to a boss left
	the soundtrack silent for the rest of the session. A Sound this client
	creates in SoundService is its own, survives respawns, and plays 2D.
]]
local function newSound(name: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.Volume = 0
	sound.Parent = SoundService
	return sound
end

local function makeChannel(name: string)
	local channel = { name = name, track = nil, gain = 0, target = 0, rate = 1, live = false }

	local function onEnded()
		if channel.live then
			local track = Music.Tracks[channel.track]
			if track and track.loop and not channel.regions then
				-- No playback regions on this engine: loop by hand.
				channel.sound.TimePosition = track.loop.Min
				channel.sound:Play()
				return
			end
			channel.live = false
			channel.track = nil
			if not bossTrack then
				nextAt = os.clock() + between(Music.Gap)
			end
		end
	end

	-- (Re)builds the Sound. Called again if anything ever destroys it, so
	-- the soundtrack cannot be silenced by losing an instance.
	function channel.ensure()
		if channel.sound and channel.sound.Parent then
			return
		end
		channel.sound = newSound(name)
		channel.sound.Ended:Connect(onEnded)
		if channel.live then
			-- It was playing: start it again rather than leave a gap.
			channel.restart = true
		end
	end
	channel.ensure()

	return channel
end

-- Ducking: a heavy hit dips the music for a moment (CombatAudio recipes). It
-- holds for `hold` seconds and comes back over DUCK_RELEASE. A deeper duck
-- arriving during a shallower one takes over; a shallower one is ignored.
local DUCK_RELEASE = 0.8
local duck = { depth = 0, at = -math.huge, hold = 0 }

local function duckFactor(): number
	local t = os.clock() - duck.at
	local depth = duck.depth
	if t > duck.hold then
		depth *= math.max(0, 1 - (t - duck.hold) / DUCK_RELEASE)
	end
	return 1 - depth
end

local function applyVolume(channel)
	local level = volume * channel.gain * duckFactor()
	if channel.sound.Volume ~= level then
		channel.sound.Volume = level
	end
	if volume <= 0 then
		if channel.sound.IsPlaying then
			channel.sound:Pause()
		end
	elseif channel.live and not channel.sound.IsPlaying then
		channel.sound:Resume()
	end
end

local function fadeTo(channel, target: number, seconds: number)
	channel.target = target
	channel.rate = math.abs(target - channel.gain) / math.max(seconds, 0.05)
end

local function play(channel, key: string, fadeSeconds: number)
	local track = Music.Tracks[key]
	local sound = channel.sound
	sound:Stop()
	sound.SoundId = track.id
	sound.Looped = track.loop ~= nil

	channel.regions = false
	if track.loop then
		channel.regions = pcall(function()
			sound.PlaybackRegionsEnabled = true
			sound.LoopRegion = track.loop
		end)
		if not channel.regions then
			sound.Looped = false
		end
	else
		pcall(function()
			sound.PlaybackRegionsEnabled = false
		end)
	end

	sound.TimePosition = 0
	channel.track = key
	channel.live, channel.stopping = true, false
	channel.gain = 0
	fadeTo(channel, 1, fadeSeconds)
	applyVolume(channel)
	if volume > 0 then
		sound:Play()
	end
end

local function stop(channel, fadeSeconds: number)
	if channel.live then
		fadeTo(channel, 0, fadeSeconds)
		channel.stopping = true
	end
end

-- The channel playing `key`, or nil.
local function playing(key: string?)
	for _, channel in ipairs(channels) do
		if channel.live and not channel.stopping and (key == nil or channel.track == key) then
			return channel
		end
	end
	return nil
end

local function freeChannel()
	for _, channel in ipairs(channels) do
		if not channel.live then
			return channel
		end
	end
	-- Both busy (a fade-out still finishing): take the quieter one.
	local a, b = channels[1], channels[2]
	local quieter = if a.gain <= b.gain then a else b
	quieter.sound:Stop()
	quieter.live, quieter.stopping = false, false
	return quieter
end

-- ---------------------------------------------------------------------------
-- The director
-- ---------------------------------------------------------------------------

local sensedPlace, sensedSince, nextSense = "day", 0, 0

--[[
	Follows where the player is. Going into or out of a cave changes the music
	now: what is playing fades and the new place's music follows a short quiet.
	Dusk and dawn only change what comes NEXT; a track is never cut for the
	clock.
]]
local function updatePlace()
	local now = os.clock()
	if now < nextSense then
		return
	end
	nextSense = now + 0.5

	local place = sensePlace()
	if place ~= sensedPlace then
		sensedPlace, sensedSince = place, now
		return
	end
	if place == context or now - sensedSince < Music.ContextSettle then
		return
	end

	local underground = place == "cave" or context == "cave"
	context = place
	if bossTrack or not underground then
		return
	end

	local _, resolved = poolFor(place)
	local current = playing(nil)
	if current and not table.find(poolFor(resolved), current.track) then
		stop(current, Music.ContextOut)
		nextAt = now + Music.ContextOut + between(Music.ContextGap)
	elseif not current then
		nextAt = math.min(nextAt, now + between(Music.ContextGap))
	end
end

local function step(dt: number)
	for _, channel in ipairs(channels) do
		channel.ensure()
		if channel.restart then
			channel.restart = false
			local key = channel.track
			if key and not channel.stopping then
				play(channel, key, 0.5)
			else
				channel.live, channel.stopping, channel.track = false, false, nil
			end
		end
		if channel.gain ~= channel.target then
			local delta = channel.rate * dt
			if channel.gain < channel.target then
				channel.gain = math.min(channel.target, channel.gain + delta)
			else
				channel.gain = math.max(channel.target, channel.gain - delta)
			end
		end
		if channel.stopping and channel.gain <= 0 then
			channel.sound:Stop()
			channel.live, channel.stopping, channel.track = false, false, nil
		end
		applyVolume(channel)
	end

	updatePlace()

	if volume <= 0 then
		return
	end

	if bossTrack then
		if not playing(bossTrack) then
			for _, channel in ipairs(channels) do
				stop(channel, Music.Crossfade)
			end
			play(freeChannel(), bossTrack, Music.BossIn)
		end
		return
	end

	if not playing(nil) and os.clock() >= nextAt then
		local key = deal()
		if key then
			nextAt = math.huge
			play(freeChannel(), key, Music.FadeIn)
		end
	end
end

local function onBossState(state)
	local key = type(state) == "table" and state.key
	local theme = type(key) == "string" and Music.BossThemes[key] or nil
	if theme and not playable(theme) then
		theme = nil
	end

	if theme == bossTrack then
		return
	end

	local wasBoss = bossTrack ~= nil
	bossTrack = theme

	if not theme and wasBoss then
		for _, channel in ipairs(channels) do
			stop(channel, Music.BossOut)
		end
		nextAt = os.clock() + Music.BossOut + between(Music.AfterBoss)
	end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function Music.getVolume(): number
	return volume
end

-- Dips the music by `depth` (0..1 of its level) for `hold` seconds, then lets
-- it back. See duckFactor.
function Music.duck(depth: number, hold: number?)
	depth = math.clamp(tonumber(depth) or 0, 0, 0.9)
	if depth >= 1 - duckFactor() then
		duck.depth, duck.at, duck.hold = depth, os.clock(), hold or 0.3
	end
end

--[[
	Sets the music volume, 0..1. Applied at once, not tweened: this is called
	while somebody drags a slider.
]]
function Music.setVolume(value: number)
	value = math.clamp(tonumber(value) or 0, 0, 1)
	if value == volume then
		return
	end

	local wasSilent = volume <= 0
	volume = value

	for _, channel in ipairs(channels) do
		applyVolume(channel)
	end

	-- Unmuted with nothing to resume: music shortly, not after a full gap.
	if wasSilent and volume > 0 and not playing(nil) then
		nextAt = math.min(nextAt, os.clock() + 2)
	end

	Music.Changed:Fire(volume)
end

-- Starts the soundtrack. Safe to call more than once.
function Music.start()
	if started or not RunService:IsClient() then
		return
	end
	local player = Players.LocalPlayer
	if not player then
		return
	end
	started = true

	for _, name in ipairs(SOUND_NAMES) do
		table.insert(channels, makeChannel(name))
	end

	nextAt = os.clock() + between(Music.FirstDelay)
	RunService.Heartbeat:Connect(step)

	task.spawn(function()
		local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Remotes"))
		Remotes.wait("BossState").OnClientEvent:Connect(onBossState)
	end)
end

return Music
