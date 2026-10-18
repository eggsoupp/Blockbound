--[[
	EnemyAnimator

	Plays authored animations on an enemy rigged with an AnimationController:
	Motor6Ds hanging off an anchored RootPart, ArticulatedRig = true. See
	EnemyService.prepareModel and assets/signus-hallow/roblox/README.md.

		local animator = EnemyAnimator.new(entry.model, EnemyConfig.Animations.Signus)

		animator:play("Hover")                        -- in the behaviour's start
		animator:play("Lunge", { fadeTime = 0.08 })   -- a one-shot restarts each call
		animator:stop("Hover", 0.3)
		animator:length("Cast")                       -- seconds, to time an attack by
		animator:destroy()                            -- in the behaviour's finish

	Tracks: Hover, Lunge, Cast, Hurt, Death. How each one loops and layers is
	fixed here (TRACK_SETTINGS) rather than trusted to the published asset.

	ON THE SERVER, ON PURPOSE. A track loaded through the model's own Animator
	on the server replicates to every client, so everybody sees the same lunge
	at the same moment and a player who joins mid-fight sees the hover already
	running. Clients load nothing. Only Animator:LoadAnimation is used;
	AnimationController:LoadAnimation and Humanoid:LoadAnimation are deprecated.

	THE ROOT IS NOT ANIMATED. Animations only write Motor6D.Transform, and the
	root is the Part0 of CoreJoint and never a Part1, so nothing an animator
	authors can move it. Where the boss is stays its behaviour's business,
	through PivotTo. `new` refuses a rig whose root hangs off a joint.

	CLEANUP. `destroy` stops every track and destroys it. Call it from the
	behaviour's finish(); it also runs by itself when the model is destroyed,
	so a behaviour that forgets does not leak tracks.

	DEATH. EnemyService destroys the model straight after finish(), so a Death
	played there is never seen. A behaviour that wants it has to play it
	before the killing blow is dealt, or hold the model until it ends.

	MISSING IDS. An id still at its placeholder in EnemyConfig.Animations is
	skipped with one warning naming it, and play/stop on it do nothing: a boss
	without a Cast animation still casts.
]]

local RunService = game:GetService("RunService")

local EnemyAnimator = {}
EnemyAnimator.__index = EnemyAnimator

EnemyAnimator.TrackNames = { "Hover", "Lunge", "Cast", "Hurt", "Death" }

-- Set on each track as it loads. Author the published assets the same way, so
-- the server and every client agree on them whatever replicates.
local TRACK_SETTINGS = {
	Hover = { looped = true, priority = Enum.AnimationPriority.Idle },
	Lunge = { looped = false, priority = Enum.AnimationPriority.Action },
	Cast = { looped = false, priority = Enum.AnimationPriority.Action },
	Hurt = { looped = false, priority = Enum.AnimationPriority.Action2 },
	Death = { looped = false, priority = Enum.AnimationPriority.Action4 },
}

local DEFAULT_FADE = 0.1

-- An asset id as a number, "123" or "rbxassetid://123"; anything else is a
-- placeholder for an animation not published yet.
local function assetUri(value: any): string?
	if type(value) == "number" and value > 0 and value % 1 == 0 then
		return string.format("rbxassetid://%d", value)
	end
	if type(value) == "string" then
		if string.match(value, "^rbxassetid://%d+$") then
			return value
		end
		if string.match(value, "^%d+$") then
			return "rbxassetid://" .. value
		end
	end
	return nil
end

--[[
	Loads every named track the rig has an id for. Returns nil and a reason
	when the model is not a rig this can drive, which a behaviour should report
	and carry on without.
]]
function EnemyAnimator.new(model: Model, ids: { [string]: any }?)
	assert(RunService:IsServer(), "EnemyAnimator runs on the server, so that its tracks replicate")

	local controller = model:FindFirstChildOfClass("AnimationController")
	local animator = controller and controller:FindFirstChildOfClass("Animator")
	if not animator then
		return nil, string.format("%s has no AnimationController with an Animator", model:GetFullName())
	end

	local root = model.PrimaryPart
	if not root then
		return nil, string.format("%s has no PrimaryPart to hold still", model:GetFullName())
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Part1 == root then
			return nil, string.format(
				"%s is the Part1 of %s, so an animation could move it", root.Name, descendant:GetFullName()
			)
		end
	end

	local self = setmetatable({
		model = model,
		tracks = {},
		animations = {},
		destroyed = false,
	}, EnemyAnimator)

	local missing = {}
	for _, name in ipairs(EnemyAnimator.TrackNames) do
		local uri = assetUri(ids and ids[name])
		if not uri then
			table.insert(missing, name)
			continue
		end

		local animation = Instance.new("Animation")
		animation.Name = name
		animation.AnimationId = uri

		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		if ok and track then
			local settings = TRACK_SETTINGS[name]
			track.Looped = settings.looped
			track.Priority = settings.priority
			self.tracks[name] = track
			self.animations[name] = animation
		else
			animation:Destroy()
			warn(string.format(
				"[EnemyAnimator] %s could not load %s (%s): %s", model.Name, name, uri, tostring(track)
			))
		end
	end

	if #missing > 0 then
		warn(string.format(
			"[EnemyAnimator] %s has no published animation for %s yet; see EnemyConfig.Animations.",
			model.Name, table.concat(missing, ", ")
		))
	end

	-- The safety net. Deferred events may run this after the model is gone,
	-- which destroy() tolerates.
	self.destroyingConnection = model.Destroying:Connect(function()
		self:destroy()
	end)

	return self
end

--[[
	Starts a track, or nil if it was never loaded.

	`options`: fadeTime (seconds), weight, speed. A looped track that is
	already playing is adjusted rather than restarted, so a state machine can
	ask for the hover every tick without it stuttering.
]]
function EnemyAnimator:play(name: string, options: { fadeTime: number?, weight: number?, speed: number? }?)
	local track = not self.destroyed and self.tracks[name]
	if not track then
		return nil
	end

	local fadeTime = options and options.fadeTime or DEFAULT_FADE
	local weight = options and options.weight
	local speed = options and options.speed

	if track.IsPlaying and track.Looped then
		if speed then
			track:AdjustSpeed(speed)
		end
		if weight then
			track:AdjustWeight(weight, fadeTime)
		end
		return track
	end

	track:Play(fadeTime, weight or 1, speed or 1)
	return track
end

function EnemyAnimator:stop(name: string, fadeTime: number?)
	local track = not self.destroyed and self.tracks[name]
	if track and track.IsPlaying then
		track:Stop(fadeTime or DEFAULT_FADE)
	end
end

function EnemyAnimator:stopAll(fadeTime: number?)
	for name in pairs(self.tracks) do
		self:stop(name, fadeTime)
	end
end

function EnemyAnimator:isPlaying(name: string): boolean
	local track = not self.destroyed and self.tracks[name]
	return track and track.IsPlaying or false
end

-- Whether a track loaded for this name at all. A behaviour uses it to fall
-- back to a procedural pose for a move whose animation is not published yet.
function EnemyAnimator:has(name: string): boolean
	return not self.destroyed and self.tracks[name] ~= nil
end

-- Seconds at speed 1, or 0 until the asset has loaded (or if it never will).
function EnemyAnimator:length(name: string): number
	local track = not self.destroyed and self.tracks[name]
	return track and track.Length or 0
end

-- Stops and destroys every track. Safe to call more than once.
function EnemyAnimator:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true

	if self.destroyingConnection then
		self.destroyingConnection:Disconnect()
		self.destroyingConnection = nil
	end

	for _, track in pairs(self.tracks) do
		pcall(function()
			track:Stop(0)
		end)
		pcall(function()
			track:Destroy()
		end)
	end
	for _, animation in pairs(self.animations) do
		animation:Destroy()
	end

	table.clear(self.tracks)
	table.clear(self.animations)
end

return EnemyAnimator
