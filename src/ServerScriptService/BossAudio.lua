-- Audio-only cues use the existing boss presentation remote and broadcast radius.
local RS = game:GetService("ReplicatedStorage")
local Remotes = require(RS.Shared.Net.Remotes)
local Remote = Remotes.ensure("BossEffect", "RemoteEvent")
local BossAudio = {}
function BossAudio.emit(boss, kind, position)
	local payload = {boss=boss, kind=kind, position=position, audioOnly=true, startedAt=workspace:GetServerTimeNow()}
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position-position).Magnitude <= 420 then Remote:FireClient(player, payload) end
	end
end
return BossAudio
