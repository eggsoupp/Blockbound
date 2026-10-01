--[[
	CombatService

	The one place damage to a player is worked out and applied.

	  CombatService.init()
	  CombatService.applyDamage(player, amount, source) -> dealt
	  CombatService.getDefense(player) -> number
	  CombatService.heal(player, amount) -> healed
	  CombatService.getStats()

	THE SPLIT, AND WHY IT IS THIS WAY ROUND

	Whatever hits you says only how hard it hit - a slime says 5, a fall would
	say however far. It does not know or care about armour. This module turns
	that into what you actually lose, using CombatConfig's curve and whatever
	you are wearing.

	That separation is the useful part: adding a trap, a projectile or a boss
	means calling applyDamage, never reimplementing mitigation, and rebalancing
	armour means editing CombatConfig and nothing else.

	IT HAS TO BE THE SERVER THAT DOES IT

	The natural way to describe this is "tell a script how much I was hit for
	and let it work out the rest", and that is exactly right - as long as the
	script is this one. A client cannot be trusted with the subtraction: a
	client that computes its own damage is a client that can compute zero, and
	the enemies become decorative. So the server sends the RESULT to the
	interface, never the question.

	WHERE DEFENSE COMES FROM

	Summed from `buffs.defense` on whatever sits in the player's gear slots -
	the armour and accessory slots defined by InventoryConstants. That is the
	shape the item table already used (LeatherArmor 5, IronArmor 15), so
	nothing here invents a second one, and a new piece of armour is an item
	entry rather than a code change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("Combat"):WaitForChild("CombatConfig"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local InventoryConstants = require(ReplicatedStorage:WaitForChild("InventoryConstants"))

local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))

local CombatStatsRE = Remotes.ensure("CombatStats", "RemoteEvent")

local CombatService = {}

local isInitialized = false

-- player -> os.clock() of their last hit, for the grace period.
local lastHitAt = setmetatable({}, { __mode = "k" })

-- player -> the defense last pushed to that client, so a 1Hz sweep can send
-- only what changed rather than a heartbeat of identical numbers.
local sentDefense = setmetatable({}, { __mode = "k" })

-- player -> true while applyDamage is mid-write and will send a better message
-- itself. See the comment where it is set.
local suppressPush = setmetatable({}, { __mode = "k" })

-- Players who take no damage at all. Set by /god; see setInvulnerable. Weak,
-- so leaving the server clears it whether or not anything remembered to.
local invulnerable = setmetatable({}, { __mode = "k" })

-- ---------------------------------------------------------------------------
-- Stats
-- ---------------------------------------------------------------------------

--[[
	Total defense from equipped gear.

	Computed on demand rather than cached. It is a walk of the gear slots -
	single figures of table lookups - and a cache would need invalidating from
	every path that can move an item, which is a much better way to end up
	showing somebody the armour they took off ten minutes ago.
]]
function CombatService.getDefense(player)
	local defense = CombatConfig.BaseDefense

	local inventory = InventoryService.GetInventory(player)
	if not inventory then
		return defense
	end

	local slots = inventory:GetAll()

	for index = 1, #slots do
		-- Only slots that are gear. A sword in the hotbar is not armour, even
		-- though ItemDefinitions would happily give it a buffs table.
		if InventoryConstants.getSlotRestriction(index) ~= nil then
			local slot = slots[index]
			local name = slot and slot.name

			if name then
				local definition = ItemDefinitions[name]
				local buffs = definition and definition.buffs
				local bonus = buffs and tonumber(buffs.defense)

				if bonus then
					defense += bonus
				end
			end
		end
	end

	return defense
end

local function getHumanoid(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

--[[
	Pushes the numbers the interface needs.

	The RESULT of the mitigation, never the inputs to it - the client is being
	told what is true, not asked to work it out.
]]
local function pushStats(player, defense)
	if suppressPush[player] then
		return
	end

	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end

	defense = defense or CombatService.getDefense(player)
	sentDefense[player] = defense

	CombatStatsRE:FireClient(player, {
		health = humanoid.Health,
		maxHealth = humanoid.MaxHealth,
		defense = defense,
		reduction = CombatConfig.reductionFor(defense),
	})
end

-- ---------------------------------------------------------------------------
-- Damage
-- ---------------------------------------------------------------------------

--[[
	Hurts a player, after armour.

	`amount` is RAW damage - what the source would do to somebody wearing
	nothing. `source` is a free-form label used for logging and for telling the
	client what hit it; it never affects the arithmetic.

	Returns how much was actually taken, so a caller can react to a hit that
	was fully absorbed or that killed.
]]
function CombatService.applyDamage(player, amount, source)
	local humanoid = getHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	--[[
		Invulnerability, for testing.

		HERE and nowhere else, because this is the one funnel every point of
		damage in the game goes through - enemies, contact, the boss, fall
		damage, anything added later. A godmode implemented by topping the
		player's health back up would be a different thing wearing the same
		name: it would still flash the hit, still interrupt, and still lose a
		race with anything that read Health in between.

		Returning 0 also means nothing downstream believes it landed a hit, so
		the damage numbers, the screen flash and the combat stats all stay
		honest about it.
	]]
	if invulnerable[player] then
		return 0
	end

	local now = os.clock()
	if CombatConfig.InvulnerableSeconds > 0 then
		local last = lastHitAt[player]
		if last and now - last < CombatConfig.InvulnerableSeconds then
			return 0
		end
	end

	local defense = CombatService.getDefense(player)
	local dealt = CombatConfig.mitigate(amount, defense)
	if dealt <= 0 then
		return 0
	end

	lastHitAt[player] = now

	--[[
		TakeDamage fires HealthChanged synchronously, and that handler pushes the
		stats too - so without this every hit sent two near-identical packets,
		one plain and one carrying the hit. Suppressed across the write, because
		the richer message below is the one worth sending.
	]]
	suppressPush[player] = true
	humanoid:TakeDamage(dealt)
	suppressPush[player] = nil

	Profiler.count("Combat.hit")
	Profiler.sample("Combat.damageDealt", dealt, "hp")

	CombatStatsRE:FireClient(player, {
		health = humanoid.Health,
		maxHealth = humanoid.MaxHealth,
		defense = defense,
		reduction = CombatConfig.reductionFor(defense),
		-- Present only on a hit, which is what tells the interface to react
		-- rather than just redraw.
		hit = dealt,
		source = source,
	})
	sentDefense[player] = defense

	return dealt
end

--[[
	Turns damage off for one player, and reports what it is now.

	Deliberately not persisted and not saved anywhere: it is cleared by leaving,
	and there is no way to switch it on that is not an admin typing a command.
]]
function CombatService.setInvulnerable(player, on: boolean): boolean
	invulnerable[player] = if on then true else nil
	-- Replicated UI hint; server gameplay still uses the private table above.
	player:SetAttribute("GodMode", on == true)
	return invulnerable[player] == true
end

function CombatService.isInvulnerable(player): boolean
	return invulnerable[player] == true
end

function CombatService.heal(player, amount)
	local humanoid = getHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	amount = math.max(0, tonumber(amount) or 0)
	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, before + amount)

	local healed = humanoid.Health - before
	if healed > 0 then
		pushStats(player)
	end

	return healed
end

function CombatService.getStats()
	local rows = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local humanoid = getHumanoid(player)
		rows[player.Name] = {
			health = if humanoid then math.floor(humanoid.Health + 0.5) else 0,
			maxHealth = if humanoid then humanoid.MaxHealth else 0,
			defense = CombatService.getDefense(player),
		}
	end

	return rows
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	-- The game's own number, not Roblox's default. Set before Health, or the
	-- new maximum would clamp a full bar down to the old one.
	humanoid.MaxHealth = CombatConfig.BaseMaxHealth
	humanoid.Health = CombatConfig.BaseMaxHealth

	humanoid.HealthChanged:Connect(function()
		pushStats(player)
	end)

	-- Deferred: the client's own scripts are still starting when the character
	-- appears, and a stats push that arrives before the interface is listening
	-- is a bar that stays empty until the first hit lands.
	task.delay(1, function()
		if player.Parent and player.Character == character then
			pushStats(player)
		end
	end)
end

function CombatService.init()
	if isInitialized then
		return
	end
	isInitialized = true

	local function bind(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)

		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(bind)
	for _, player in ipairs(Players:GetPlayers()) do
		bind(player)
	end

	--[[
		Defense changes when gear moves, and gear moves through the inventory,
		which already has its single change listener spoken for by the
		persistence layer. Rather than contend for it, this sweeps once a second
		and pushes only when the number actually differs - a cost of one gear
		walk per player per second, and no coupling to the inventory at all.
	]]
	task.spawn(function()
		while true do
			task.wait(1)

			for _, player in ipairs(Players:GetPlayers()) do
				local defense = CombatService.getDefense(player)
				if sentDefense[player] ~= defense then
					pushStats(player, defense)
				end
			end
		end
	end)
end

return CombatService
