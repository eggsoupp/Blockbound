--[[
	AbilityService

	The one door abilities come through, and the only thing that decides whether
	a cast is allowed to happen.

		AbilityService.init()

	A cast is, from the client's side, "run some code that deals damage where I
	chose" - exactly the request a modified client would most like to make. So
	it may say only two things (which ability, where it aims) and both are
	checked against what the server already knows. It cannot cast an ability it
	is not CARRYING (AbilityLoadout, which lives here and can only be changed
	through it), skip the cooldown, aim past castRange (clamped, not rejected,
	so a lag spike still produces a cast), ask for unbounded work (rate limited
	independently of the cooldown, with a cap on casts in flight), or deal
	damage at all - the ability module does that through CombatService and
	EnemyService.

	It no longer says what it is HOLDING either. That used to be the permission
	and is now only presentation, so the server reads it for itself rather than
	being told; see castWeaponFor.

	Back out comes one broadcast per cast, to the players near enough to see it.
	Not the positions of the fifteen strikes: a SEED, which SacredRainPlan
	expands into the same fifteen on both sides. Nothing about the effect
	itself replicates.

	ADDING AN ABILITY is nothing in this file - an AbilityConfig entry and a
	module of the same name in ServerScriptService.Abilities. The contract is:

		function Ability.cast(context) -> boolean, reason?

	where context carries the player, their character, the sanitised origin and
	target, the ability's tuning table, a scope destroyed when the cast ends,
	and a broadcast function.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local AbilitiesShared = Shared:WaitForChild("Abilities")
local AbilityConfig = require(AbilitiesShared:WaitForChild("AbilityConfig"))
local AbilityScope = require(AbilitiesShared:WaitForChild("AbilityScope"))

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local AbilityLoadout = require(ServerScriptService:WaitForChild("AbilityLoadout"))
local ManaService = require(ServerScriptService:WaitForChild("ManaService"))
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local GearService = require(ServerScriptService:WaitForChild("GearService"))

local AbilityService = {}

local DEBUG = false
local function log(...)
	if DEBUG then
		print("[AbilityService]", ...)
	end
end

local RequestAbility = Remotes.ensure("RequestAbility", "RemoteEvent")
local AbilityEffect = Remotes.ensure("AbilityEffect", "RemoteEvent")
local AbilityTerrain = Remotes.ensure("AbilityTerrain", "RemoteEvent")

local isInitialized = false

-- Server ability modules, required once each on first use.
local modules: { [string]: any } = {}

--[[
	Per-player state. Weak-keyed so a player who leaves takes their entry with
	them even if a disconnect path is ever missed.

	  cooldowns  ability name -> os.clock() of the last successful cast
	  active     scope -> the ability name it belongs to, for every cast still
	             running
	  counts     ability name -> how many of ITS casts are running
	  budget     leaky-bucket token count for the request rate limit
	  budgetAt   when the bucket was last refilled

	COUNTED PER ABILITY, NOT PER PLAYER

	`maxConcurrent` is a field on an ability, so the number it is checked
	against has to be that ability's own. It used to be a single per-player
	total, which meant one ability's casts filled up every other ability's cap:
	a Sacred Rain stays active for its whole duration - about twelve seconds,
	most of it the swords' pooled lifetime - so for those twelve seconds every
	ability with maxConcurrent = 1 was refused. Silently, because a refusal is
	not an error: the player pressed the key and nothing whatsoever happened.

	That is a real bug and it was invisible while there was only one ability in
	the game.
]]
local state = setmetatable({}, { __mode = "k" })

local function stateFor(player: Player)
	local entry = state[player]
	if not entry then
		entry = {
			cooldowns = {},
			active = {},
			counts = {},
			budget = AbilityConfig.RequestsPerSecond,
			budgetAt = os.clock(),
		}
		state[player] = entry
	end
	return entry
end

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

--[[
	Is this a real position, rather than something that would poison every
	CFrame it touches?

	NaN is the one that matters. It propagates silently through arithmetic, and
	a NaN CFrame assigned to a part can take physics down with it - so it is
	checked here rather than trusted to be impossible.
]]
local function isSanePosition(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end

	-- x ~= x is only true for NaN.
	if value.X ~= value.X or value.Y ~= value.Y or value.Z ~= value.Z then
		return false
	end

	local limit = 1e6
	return math.abs(value.X) < limit and math.abs(value.Y) < limit and math.abs(value.Z) < limit
end

--[[
	The name of the item a player is actually holding, or nil.

	The CHARACTER, not the Backpack. EquipServer is what moves a Tool into the
	character, and it only does that for a template it found itself, so this is
	a fact the server established rather than something the client asserted.
]]
local function heldItemName(character: Model?): string?
	if not character then
		return nil
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end

	local attribute = tool:GetAttribute("ItemName")
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end

	local value = tool:FindFirstChild("ItemName")
	if value and value:IsA("StringValue") and value.Value ~= "" then
		return value.Value
	end

	return tool.Name
end

--[[
	The weapon an effect should be drawn with.

	The held tool if it is genuinely a weapon, and the configured stand-in
	otherwise - including when a pickaxe is out, because raining pickaxes is
	funnier than it is right.

	Nothing about this decides whether a cast happens; see the note where it is
	called.
]]
local function castWeaponFor(character: Model?): string
	local held = heldItemName(character)
	local definition = held and ItemDefinitions[held]

	if definition and definition.classification == "Weapon" then
		return held
	end

	return AbilityConfig.DefaultCastWeapon
end

--[[
	Leaky bucket, refilled continuously. Costs one token per request whether or
	not the request turns out to be legal, because the expensive part of an
	abusive client is the asking.
]]
local function takeToken(entry): boolean
	local now = os.clock()
	local rate = AbilityConfig.RequestsPerSecond

	entry.budget = math.min(rate, entry.budget + (now - entry.budgetAt) * rate)
	entry.budgetAt = now

	if entry.budget < 1 then
		return false
	end

	entry.budget -= 1
	return true
end

-- ---------------------------------------------------------------------------
-- Broadcast
-- ---------------------------------------------------------------------------

--[[
	Sends one effect message to the players who could see it.

	This is the whole optimisation. An effect nobody is near costs one distance
	check per player and nothing else; the reference's version of the same
	effect replicates several thousand instances to everybody in the server
	regardless of where they are standing.

	The caster always receives it, even if their character has moved on since -
	they pressed the key, and an ability that does not visibly fire for the
	person who cast it reads as broken input.
]]
local function broadcast(caster: Player, centre: Vector3, payload, remote)
	local radius = AbilityConfig.BroadcastRadius
	local sent = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local send = player == caster

		if not send then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - centre).Magnitude <= radius then
				send = true
			end
		end

		if send then
			(remote or AbilityEffect):FireClient(player, payload)
			sent += 1
		end
	end

	Profiler.sample("Ability.broadcastRecipients", sent, "players")
end

-- ---------------------------------------------------------------------------
-- Casting
-- ---------------------------------------------------------------------------

local function moduleFor(definition)
	local name = definition.server
	if type(name) ~= "string" then
		return nil
	end

	local cached = modules[name]
	if cached ~= nil then
		return cached or nil
	end

	local folder = ServerScriptService:FindFirstChild("Abilities")
	local moduleScript = folder and folder:FindFirstChild(name)

	if not (moduleScript and moduleScript:IsA("ModuleScript")) then
		warn(string.format(
			"[AbilityService] no module '%s' in ServerScriptService.Abilities; the ability "
				.. "cannot run.",
			name
		))
		modules[name] = false
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if not ok or type(result) ~= "table" or type(result.cast) ~= "function" then
		-- pcall only ever reports "experienced an error while loading"; Roblox
		-- prints the real message on its own line just above this one.
		warn(string.format(
			"[AbilityService] '%s' did not load as an ability module (needs a `cast` function): %s "
				.. "- the real error is the line above this one.",
			name, tostring(result)
		))
		modules[name] = false
		return nil
	end

	modules[name] = result
	return result
end

--[[
	Ends a cast: takes it off the player's active list and destroys its scope,
	which is what stops everything it started.
]]
local function endCast(player: Player, scope)
	local entry = state[player]
	local abilityName = entry and entry.active[scope]

	if entry and abilityName then
		entry.active[scope] = nil
		entry.counts[abilityName] = math.max(0, (entry.counts[abilityName] or 1) - 1)
	end

	scope:destroy()
end

--[[
	Cancels everything a player has running. Called on death, respawn and
	disconnect - the three ways a cast can outlive the thing that cast it.
]]
function AbilityService.cancelAll(player: Player)
	local entry = state[player]
	if not entry then
		return
	end

	for scope in pairs(entry.active) do
		scope:destroy()
	end

	table.clear(entry.active)
	table.clear(entry.counts)
end

local function onRequest(player: Player, abilityName: any, target: any)
	local entry = stateFor(player)

	if not takeToken(entry) then
		log(player.Name, "rate limited")
		return
	end

	if type(abilityName) ~= "string" then
		return
	end

	local definition = AbilityConfig.get(abilityName)
	if not definition then
		return
	end

	--[[
		THE permission check, and the only one.

		Abilities used to be gated on holding the weapon that owned them. They
		are universal now, so what a client may cast is exactly what it has put
		in its loadout - which lives on the server and can only be changed
		through AbilityLoadout. A modified client naming an ability it has not
		added gets nothing.
	]]
	if not AbilityLoadout.has(player, abilityName) then
		log(player.Name, "asked for", abilityName, "without carrying it")
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not (character and humanoid and root) or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local lastCast = entry.cooldowns[abilityName]
	local godMode = CombatService.isInvulnerable(player)
	if not godMode and lastCast and now - lastCast < (definition.cooldown or 0) then
		return
	end

	local maxConcurrent = if godMode then math.max(3,definition.maxConcurrent or 1) else (definition.maxConcurrent or 1)
	local running = entry.counts[abilityName] or 0
	if running >= maxConcurrent then
		log(player.Name, "already has", running, abilityName, "casts running")
		return
	end

	local origin = root.CFrame
	local point = origin.Position

	if definition.requiresTarget then
		if not isSanePosition(target) then
			return
		end

		-- Clamped, not refused: the client is aiming with a mouse ray and the
		-- server is a few frames behind it.
		local offset = (target :: Vector3) - origin.Position
		local range = definition.castRange or 100
		if offset.Magnitude > range then
			point = origin.Position + offset.Unit * range
		else
			point = target :: Vector3
		end
	end

	local module = moduleFor(definition)
	if not module then
		return
	end

	--[[
		Paid for LAST, after every other reason to refuse has been ruled out.

		Everything above this line can turn a cast down, and mana taken before
		one of them did would be mana gone for a cast that never happened -
		including the missing-module case immediately above, which is a bug on
		our side and should not cost the player anything.

		Nothing below can refuse, so this is the last safe moment and the first
		one at which spending is honest.
	]]
	if not ManaService.spend(player, definition.manaCost) then
		log(player.Name, "could not afford", abilityName)
		return
	end

	-- God-mode casts do not leave a cooldown behind when god mode is disabled.
	entry.cooldowns[abilityName] = if godMode then nil else now

	local scope = AbilityScope.new()
	entry.active[scope] = abilityName
	entry.counts[abilityName] = running + 1

	--[[
		The weapon the effect is DRAWN with.

		Sacred Rain rains the caster's weapon, which was well defined back when
		the ability belonged to one. A universal ability can be cast
		bare-handed, so the server picks: whatever weapon they are holding, or
		AbilityConfig.DefaultCastWeapon when that is nothing.

		Presentation only. Nothing above this line consulted it, and nothing
		below it may - what a player is holding stopped being a permission a
		while ago and this is the last place it could quietly become one again.
	]]
	local itemName = castWeaponFor(character)

	local context = {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,

		itemName = itemName,
		abilityName = abilityName,
		definition = definition,
		tuning = definition.tuning,

		origin = origin,
		target = point,
		-- The whole cast in one number; see SacredRainPlan for why.
		seed = math.random(1, 2147483647),

		scope = scope,

		--[[
			How an ability hurts an enemy. Every ability goes through this
			rather than calling EnemyService itself, so anything that scales a
			player's ability damage - a Spell Ring, for now - applies to every
			ability, including the ones not written yet. Read at the moment of
			each hit, so it matches what the player is wearing then.
		]]
		damage = function(model, amount)
			return EnemyService.damage(model, amount * GearService.abilityMultiplier(player), player)
		end,

		broadcast = function(payload)
			payload.ability = abilityName
			payload.item = itemName
			-- Who cast it, so every client can play the ability's animation on
			-- the right character rather than only the caster seeing it.
			payload.caster = player
			broadcast(player, point, payload)
		end,
		broadcastDebris = function(blocks, centre)
			broadcast(player,point,{blocks=blocks,centre=centre,startedAt=workspace:GetServerTimeNow()},AbilityTerrain)
		end,
	}

	Profiler.count("Ability.cast")

	local ok, err = pcall(module.cast, context)
	if not ok then
		warn(string.format("[AbilityService] %s errored: %s", abilityName, tostring(err)))
		endCast(player, scope)
		return
	end

	--[[
		Every cast ends, whatever the ability thinks. The ability may finish
		earlier by destroying its own scope; this is the backstop that
		guarantees no scope is ever left holding connections and delayed
		threads because a module forgot.
	]]
	local lifetime = (definition.duration or (type(module.duration) == "function" and module.duration()) or 15)
	task.delay(lifetime, function()
		endCast(player, scope)
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function bind(player: Player)
	local function watch(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				AbilityService.cancelAll(player)
			end)
		end
	end

	player.CharacterAdded:Connect(function(character)
		-- A new body means the old one's effects belong to nobody.
		AbilityService.cancelAll(player)
		watch(character)
	end)

	player.CharacterRemoving:Connect(function()
		AbilityService.cancelAll(player)
	end)

	if player.Character then
		watch(player.Character)
	end
end

function AbilityService.init()
	if isInitialized then
		return
	end
	isInitialized = true

	-- Catches a slot with no key, or a definition missing the module name it
	-- would be required by, at start-up rather than on the first cast.
	AbilityConfig.validate()

	RequestAbility.OnServerEvent:Connect(onRequest)

	Players.PlayerAdded:Connect(bind)
	Players.PlayerRemoving:Connect(function(player)
		AbilityService.cancelAll(player)
		state[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		bind(player)
	end
end

return AbilityService
