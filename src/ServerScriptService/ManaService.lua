--[[
	ManaService

	The pool every ability is paid for out of. Server-owned, like the loadout.

		ManaService.get(player)          -> current, max
		ManaService.spend(player, cost)  -> true if it was affordable
		ManaService.refill(player)       -> back to full, and says so

	The size of the pool and the rate it fills at are AbilityConfig.MaxMana and
	AbilityConfig.ManaRegenPerSecond, next to the costs they are balanced
	against.

	IT IS NOT TICKED

	Nothing here runs on Heartbeat. Regeneration is linear and the only thing
	that ever interrupts it is a cast, so the current value is a function of the
	last known one and the time since - worked out on the two occasions anybody
	asks. A server full of players idling costs exactly nothing.

	THE CLIENT DRAWS THE RAMP ITSELF

	Which is the other half of the same idea. A push carries the value, the
	maximum and the RATE, so StarterPlayerScripts.ManaClient can fill the bar in
	between messages instead of being sent one ten times a second. That means a
	push per cast rather than per frame per player, and a bar that is smooth at
	any frame rate and any ping.

	It also means the client's number is a prediction, so it can be wrong -
	which is why a REFUSED cast pushes too. Being told "no" is exactly the
	moment a client that thought it could afford something needs correcting, and
	it is one message on a path the request limiter already caps.

	NOT PERSISTED, ON PURPOSE

	It fills on join and on respawn. Storing it would mean logging in unable to
	do anything for twenty seconds as a punishment for having logged out, which
	is not a rule anybody would write down deliberately.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatService = require(game:GetService("ServerScriptService"):WaitForChild("CombatService"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AbilityConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))

local ManaService = {}

local ManaChanged = Remotes.ensure("ManaChanged", "RemoteEvent")

local MAX = AbilityConfig.MaxMana
local REGEN = AbilityConfig.ManaRegenPerSecond

-- player -> { mana, at }. Weak-keyed as a backstop; PlayerRemoving clears it.
local pools = setmetatable({}, { __mode = "k" })

local function poolFor(player: Player)
	local entry = pools[player]
	if not entry then
		entry = { mana = MAX, at = os.clock() }
		pools[player] = entry
	end
	return entry
end

--[[
	Brings a pool up to date and returns it.

	Every read goes through here, so there is no such thing as a stale value to
	be caught out by - the arithmetic is the same whether it was last touched a
	frame ago or ten minutes ago.
]]
local function refresh(player: Player)
	local entry = poolFor(player)
	local now = os.clock()

	if CombatService.isInvulnerable(player) then
		entry.mana = MAX
	elseif entry.mana < MAX then
		entry.mana = math.min(MAX, entry.mana + (now - entry.at) * REGEN)
	end

	entry.at = now
	return entry
end

--[[
	Tells the client where the pool is and how fast it is filling.

	The rate goes with it rather than being a constant the client reads for
	itself, so changing ManaRegenPerSecond is one edit and the bar cannot end up
	drawing a ramp the server is not honouring.
]]
local function push(player: Player)
	local entry = refresh(player)
	ManaChanged:FireClient(player, entry.mana, MAX, REGEN)
end

function ManaService.get(player: Player): (number, number)
	return refresh(player).mana, MAX
end

--[[
	Takes `cost` out of the pool if it is there.

	Returns false and takes nothing if it is not - and pushes either way, so a
	client that guessed wrong is corrected at the moment it finds out.

	A cost of zero always succeeds and is not worth a message: an ability with
	no manaCost is one that does not participate in this at all, and it should
	not be making the bar flicker on every cast.
]]
function ManaService.spend(player: Player, cost: number?): boolean
	if CombatService.isInvulnerable(player) then
		push(player)
		return true
	end
	if type(cost) ~= "number" or cost <= 0 then
		return true
	end

	local entry = refresh(player)

	if entry.mana < cost then
		push(player)
		return false
	end

	entry.mana -= cost
	push(player)
	return true
end

function ManaService.refill(player: Player)
	local entry = poolFor(player)
	entry.mana = MAX
	entry.at = os.clock()
	push(player)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	ManaService.refill(player)
	player:GetAttributeChangedSignal("GodMode"):Connect(function()
		push(player)
	end)

	-- Full again on respawn. Dying already costs the player everything they
	-- were in the middle of; making them wait out a regen on top of it is a
	-- second punishment for the same event.
	player.CharacterAdded:Connect(function()
		ManaService.refill(player)
	end)

	if player.Character then
		ManaService.refill(player)
	end

	--[[
		Deferred for the same reason AbilityLoadout defers its first push: the
		client's own scripts are still starting, and a push that lands before
		the bar is listening leaves it showing whatever it was built with until
		the first cast.
	]]
	task.delay(1, function()
		if player.Parent then
			push(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- PlayerAdded only fires for players who join after this module is first
-- required. In Studio the developer is usually already in.
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	pools[player] = nil
end)

return ManaService
