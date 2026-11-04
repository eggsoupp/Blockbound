--[[
	CameraFacing

	Tells the server which way this player's camera is pointing, so the
	ambient spawner (ServerScriptService.EnemySpawner) can keep packs out of
	sight. The server cannot see the camera, and the character's own facing
	is wrong whenever the player looks around without walking.

	Twice a second at most, and only when the view has turned by more than a
	few degrees since the last report. Unreliable: a lost report is replaced
	by the next one, and the server falls back to the character's facing if
	reports stop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

-- The island never spawns anything on its own, and has no such remote.
if require(Shared:WaitForChild("PlaceConfig")).isIsland() then
	return
end

local CameraFacing = Remotes.wait("CameraFacing", 30)
if not CameraFacing then
	return
end

local INTERVAL = 0.5
-- Sent again after turning this far, or after HEARTBEAT seconds regardless,
-- so the server's copy never goes stale while the player stands still.
local TURN_COSINE = math.cos(math.rad(8))
local HEARTBEAT = 2

local lastSent = nil
local lastSentAt = 0

while true do
	task.wait(INTERVAL)

	local camera = workspace.CurrentCamera
	if camera then
		local look = camera.CFrame.LookVector
		local now = os.clock()
		if not lastSent or look:Dot(lastSent) < TURN_COSINE or now - lastSentAt >= HEARTBEAT then
			CameraFacing:FireServer(look)
			lastSent = look
			lastSentAt = now
		end
	end
end
