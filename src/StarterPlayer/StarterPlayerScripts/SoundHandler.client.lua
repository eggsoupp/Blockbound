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

	The first track arrives a few seconds after joining, then the soundtrack
	runs itself: tracks with silence between them, and boss themes when a fight
	starts. See Shared.Audio.Music.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Music = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("Music")
)

Music.start()

local Ambience = require(ReplicatedStorage.Shared.Audio:WaitForChild("Ambience"))
Ambience.start()
