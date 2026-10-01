--[[
	SoundHandler

	Starts the background playlist.

	The playlist, the fades and the Sound instance all live in
	Shared.Audio.Music, which is the only thing that writes Sound.Volume - the
	settings panel's slider asks that module too, so the two cannot disagree.
	This
	script exists because starting the music is a decision about WHEN, and that
	belongs to StarterPlayerScripts rather than to a module somebody might
	require for an unrelated reason.

	Music.DefaultVolume is 0, so this makes no sound. It creates the Sound and
	connects the track-advance handler, so a track is ready the moment the
	player raises the slider.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Music = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("Music")
)

Music.start()
