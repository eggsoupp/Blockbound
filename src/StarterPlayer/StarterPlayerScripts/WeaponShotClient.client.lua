--[[
	WeaponShotClient

	Listens for legendary weapon shots (WeaponShotService) and hands them to
	Shared.Abilities.VFX.WeaponShotVFX. When one of this player's own shots
	hits, it marks the moment (WeaponShotHitAt) so TargetFeedback does not also
	play the blade's hit sound for the shot's damage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local VFX = require(Shared:WaitForChild("Abilities"):WaitForChild("VFX"):WaitForChild("WeaponShotVFX"))

local player = Players.LocalPlayer
local WeaponShot = Remotes.wait("WeaponShot")

-- id -> true for this player's own shots still in flight.
local mine = {}

VFX.preload()

WeaponShot.OnClientEvent:Connect(function(packet)
	if type(packet) ~= "table" or type(packet.id) ~= "string" then
		return
	end
	if packet.event == "launch" then
		if packet.shooter == player then
			mine[packet.id] = true
		end
		local ok, err = pcall(VFX.launch, packet)
		if not ok then
			warn("[WeaponShotClient] launch failed: " .. tostring(err))
		end
		return
	end
	if mine[packet.id] and (packet.event == "hit" or packet.event == "pierce") then
		player:SetAttribute("WeaponShotHitAt", workspace:GetServerTimeNow())
	end
	if packet.event ~= "pierce" then
		mine[packet.id] = nil
	end
	local ok, err = pcall(VFX.event, packet)
	if not ok then
		warn("[WeaponShotClient] " .. tostring(packet.event) .. " failed: " .. tostring(err))
	end
end)
