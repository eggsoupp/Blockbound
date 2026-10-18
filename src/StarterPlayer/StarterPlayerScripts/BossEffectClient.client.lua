--[[
	BossEffectClient

	Draws the one-shot effects a boss asks for: particle bursts, flashes and
	camera kicks, which are presentation and belong on the client. The server
	keeps the geometry that promises something (telegraph rings, cracks,
	projectiles) because those replicate as ordinary instances; what it cannot
	do is call ParticleEmitter:Emit on a client's behalf, so bursts come here.

	Listens to the `BossEffect` remote, which BossService ensures at server
	start. The payload names the boss, and the boss's VFX module in
	Shared.Abilities.VFX draws it:

		{
			boss      = "Signus",          -- Shared.Abilities.VFX.<boss>VFX
			kind      = "impact",          -- what to draw; the module decides
			position  = Vector3,
			startedAt = number,            -- workspace:GetServerTimeNow() when sent
			...                            -- anything else the kind needs
		}

	Nothing here decides anything. A bad payload is dropped, a late one is
	drawn where it was asked, and a flood of them is bounded by
	MAX_CONCURRENT: past that, bursts are skipped rather than queued, because
	a burst drawn a second late is a burst drawn in the wrong place.

	Every effect runs inside an AbilityScope that is destroyed when the module
	says it is done, with a backstop a second later, so an effect that errors
	halfway leaves nothing behind.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AbilityScope = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityScope"))
local VFXFolder = Shared:WaitForChild("Abilities"):WaitForChild("VFX")

local BossEffect = Remotes.wait("BossEffect")

local MAX_CONCURRENT = 14
local DEFAULT_DURATION = 3

local active = 0
local modules = {}

local function moduleFor(boss: string)
	local cached = modules[boss]
	if cached ~= nil then
		return cached or nil
	end

	local moduleScript = VFXFolder:FindFirstChild(boss .. "VFX")
	if not (moduleScript and moduleScript:IsA("ModuleScript")) then
		warn(string.format("[BossEffectClient] no VFX module '%sVFX' in Shared.Abilities.VFX", boss))
		modules[boss] = false
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if not ok or type(result) ~= "table" or type(result.play) ~= "function" then
		warn(string.format(
			"[BossEffectClient] '%sVFX' did not load as a VFX module (needs a `play` function): %s",
			boss, tostring(result)
		))
		modules[boss] = false
		return nil
	end

	modules[boss] = result
	return result
end

BossEffect.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or type(payload.boss) ~= "string" or type(payload.kind) ~= "string" then
		return
	end
	if typeof(payload.position) ~= "Vector3" then
		return
	end

	if active >= MAX_CONCURRENT then
		return
	end

	local vfx = moduleFor(payload.boss)
	if not vfx then
		return
	end

	local scope = AbilityScope.new()
	active += 1

	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		active -= 1
		scope:destroy()
	end

	local ok, duration = pcall(vfx.play, payload, scope)
	if not ok then
		warn(string.format("[BossEffectClient] %s %s errored: %s", payload.boss, payload.kind, tostring(duration)))
		finish()
		return
	end

	if type(duration) ~= "number" then
		duration = DEFAULT_DURATION
	end

	task.delay(duration + 1, finish)
end)
