--[[
	BossService

	Who the boss is, how much of it is left, and telling everyone.

		BossService.engaged(entry)   -- it exists; put the bar up
		BossService.update(entry)    -- its health moved
		BossService.ended(entry)     -- it died or despawned; take the bar down

	EnemyService calls all three, off `boss = true` on the definition. Nothing
	else needs to know a boss is a boss.

	ONE AT A TIME, AND ON PURPOSE

	A boss bar is a claim about what the fight IS, and two of them is a claim
	nobody can act on. If a second boss appears while one is up, the newest owns
	the bar - it is the one that just happened, and the older one's bar comes
	back when it takes its next hit anyway.

	IT GOES TO EVERYONE, NOT TO THE FIGHT

	There is no such thing as being "in" the fight to test for: a player who
	walked over the hill to watch, or who is running away to heal, is as
	entitled to see how it is going as the one hitting it. The bar is one
	message per health change, to a server that has a handful of people in it.

	THROTTLED, BECAUSE HEALTH CHANGES A LOT

	Sacred Rain lands fifteen times in four seconds. Every one of those is a
	health change and none of them individually matters, so updates are rate
	limited and the LAST value always gets through - a bar that stopped a few
	percent short of the truth would be worse than one that lags a tenth of a
	second.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local BossService = {}

local BossState = Remotes.ensure("BossState", "RemoteEvent")

--[[
	Also owned here, so it exists from server start: the remote a boss uses to
	tell clients which blocks it swallowed (see Bosses.SlimeEmperor and
	StarterPlayerScripts.BossTerrainClient). A behaviour module is only
	required when its boss first spawns, so a client waiting on a remote that
	module created would wait - with an infinite-yield warning - until the
	first boss of the session. Ensuring it here makes it exist with the bar.
]]
Remotes.ensure("BossTerrain", "RemoteEvent")

-- The same, for one-shot boss effects drawn on the client (particle bursts,
-- camera kicks): Bosses.Signus fires it, StarterPlayerScripts.BossEffectClient
-- listens. See those for the payload.
Remotes.ensure("BossEffect", "RemoteEvent")

-- Seconds between pushes while health is falling. The trailing send below is
-- what guarantees the final value arrives whatever this is set to.
local UPDATE_INTERVAL = 0.1

local active = nil
local lastSentAt = 0
local trailing = nil

local function payloadFor(entry)
	return {
		name = (entry.def and entry.def.displayName) or entry.name,
		health = math.max(0, entry.health),
		maxHealth = (entry.def and entry.def.health) or entry.health,

		-- The behaviour module's own word for what it is doing. Optional, and
		-- the bar simply shows nothing when there is none.
		phase = entry.bossPhase,
	}
end

local function send(entry)
	lastSentAt = os.clock()
	trailing = nil
	BossState:FireAllClients(payloadFor(entry))
end

function BossService.engaged(entry)
	active = entry
	send(entry)
end

function BossService.update(entry)
	-- A stale boss still taking damage somewhere is not the one on the bar.
	if entry ~= active then
		return
	end

	local now = os.clock()

	if now - lastSentAt >= UPDATE_INTERVAL then
		send(entry)
		return
	end

	--[[
		Too soon. Remember it and send it when the window is up - once,
		regardless of how many changes land inside the window.

		`trailing` being non-nil is also the flag that a send is already
		scheduled, which is what stops fifteen strikes queueing fifteen threads.
	]]
	if trailing then
		return
	end

	trailing = entry

	task.delay(UPDATE_INTERVAL - (now - lastSentAt), function()
		if trailing == entry and active == entry then
			send(entry)
		end
	end)
end

function BossService.ended(entry)
	if entry ~= active then
		return
	end

	active = nil
	trailing = nil

	BossState:FireAllClients(nil)
end

--[[
	Whoever joins mid-fight gets the bar too.

	Deferred for the same reason AbilityLoadout defers its first push: their
	scripts are still starting, and a message that lands before the bar is
	listening is a message that never happened.
]]
Players.PlayerAdded:Connect(function(player)
	task.delay(1, function()
		if active and player.Parent then
			BossState:FireClient(player, payloadFor(active))
		end
	end)
end)

return BossService
