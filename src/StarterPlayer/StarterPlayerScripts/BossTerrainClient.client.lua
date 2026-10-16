--[[
	BossTerrainClient

	Draws the ground a boss has eaten being swallowed.

	Listens to the `BossTerrain` remote, which ServerScriptService.Bosses
	fires AFTER the server has removed the blocks it names: the payload is a
	capped sample of `{ position, block }` records for cells that are really
	gone, the point they are being pulled into, and the server clock the pull
	started on. Everything here is a copy; the ground was already changed.

		{
			blocks    = { { position = Vector3, block = "Stone" }, ... },
			centre    = Vector3,   -- where they are going (the boss's mouth)
			startedAt = number,    -- workspace:GetServerTimeNow() on the server
			seconds   = number,    -- how long the pull takes
		}

	Nothing in this file decides anything. A bad payload is dropped, a late
	one is skipped, and a flood of them is bounded by TerrainDebris's caps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local TerrainDebris = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainDebris"))

local BossTerrain = Remotes.wait("BossTerrain")

BossTerrain.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.blocks) ~= "table" or typeof(payload.centre) ~= "Vector3" then
		return
	end
	if type(payload.startedAt) ~= "number" or type(payload.seconds) ~= "number" then
		return
	end

	TerrainDebris.suction(payload.blocks, payload.centre, payload.seconds, payload.startedAt)
end)
