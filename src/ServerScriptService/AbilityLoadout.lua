--[[
	AbilityLoadout

	Which abilities a player is carrying. Three slots, server-owned.

	  AbilityLoadout.add(player, name)      -> ok, message, slot
	  AbilityLoadout.remove(player, name)   -> ok, message
	  AbilityLoadout.get(player)            -> array of names, in slot order
	  AbilityLoadout.has(player, name)      -> boolean
	  AbilityLoadout.clear(player)          -> how many were removed
	  AbilityLoadout.reorder(player, a, b)  -> ok

	THIS IS THE PERMISSION CHECK

	Abilities used to hang off a weapon, and holding it was what let you cast.
	Now this table is the only thing that does: AbilityService asks `has` before
	it will run anything, so a modified client naming an ability it has not
	added gets nothing. It lives on the server for exactly that reason.

	PERSISTED ALONGSIDE THE INVENTORY

	Not in a DataStore of its own. It registers as a SECTION of the record
	InventoryStore already keeps, so it inherits that module's session lock,
	retries, autosave and shutdown save for nothing - and, more importantly,
	cannot end up racing a second lock for the same player. Two locks
	disagreeing about which server owns somebody is how a rejoin saves half a
	session and loses the other half.

	Nothing here calls save(). A change marks the player dirty through the same
	path an inventory change does, and the next autosave carries it.

	THE ORDER OF THE ARRAY IS THE ORDER OF THE KEYS

	Slot 1 is the first key in AbilityConfig.SlotKeys, and removing the middle
	ability shuffles the third one down into its place. That is what makes the
	readout honest: the panel is drawn from this array, so what it shows and
	what the keys do cannot disagree.

	It is also why `reorder` moves rather than swaps, and why it cannot leave a
	gap. The array is DENSE - three abilities always occupy slots 1..3 and two
	always occupy 1..2 - so "put this one on V and leave X empty" is not a state
	this module can hold. Reordering is a permutation of what is already carried,
	which is exactly what the Tab menu's drag does.

	REORDERING IS A REQUEST FROM THE CLIENT, AND IS STILL CHECKED

	Shared.UI.AbilityPanel fires RequestAbilityReorder with two slot numbers.
	There is nothing to escalate - it is a permutation of the player's own
	loadout, so the worst a modified client achieves is rearranging its own keys
	- but the numbers are still validated and the rate is still capped, because
	every one of them costs a push and a dirty mark.

	Every request is answered with a push, including a refused one. The panel
	moves the card on drop and waits to be corrected rather than snapping back
	over a round trip, and that only works if the server always says something.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AbilityConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))

local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

local AbilityLoadout = {}

local LoadoutChanged = Remotes.ensure("AbilityLoadoutChanged", "RemoteEvent")
local RequestReorder = Remotes.ensure("RequestAbilityReorder", "RemoteEvent")
local RequestDrop = Remotes.ensure("RequestAbilityDrop", "RemoteEvent")

local SLOT_COUNT = AbilityConfig.SlotCount

--[[
	Reorder requests per player per second, before they are dropped.

	Generous next to what a hand can do - a drag takes most of a second and ends
	in exactly one request - and small enough that a client firing in a loop
	cannot turn a free action into a stream of pushes to itself and a dirty mark
	per frame on the record.
]]
local REORDERS_PER_SECOND = 4

--[[
	player -> array of ability names.

	WEAK-KEYED, AND NOTHING CLEARS IT ON PlayerRemoving. Not an oversight - the
	leave save runs through InventoryStore.release, which serialises every
	registered section, and the order two server scripts connect to
	PlayerRemoving in is undefined. Clear this on leave and about half the time
	the save reads an empty loadout and writes it over a real one.

	So the entry outlives the player until the save has read it, and the weak
	key collects it afterwards. `stored`, further down, works the same way for
	exactly the same reason.
]]
local loadouts = setmetatable({}, { __mode = "k" })

local function loadoutFor(player: Player): { string }
	local entry = loadouts[player]
	if not entry then
		entry = {}
		loadouts[player] = entry
	end
	return entry
end

local function markDirty(player: Player)
	-- The loadout rides on the inventory's record, so a change here is a change
	-- to that record; the next autosave picks it up.
	InventoryStore.markDirty(player)
end

--[[
	Tells the client what it is carrying.

	A copy, not the live table: the array is handed to FireClient, and passing
	the one this module mutates would be a table the caller could still be
	holding a reference to when it next changes.

	`reason` is "restore" for the saved loadout arriving on join. The client
	would otherwise compare it with the empty one it was sent first, see an
	ability appear, and open the Tab menu to celebrate a pickup that never
	happened.
]]
local function push(player: Player, reason: string?)
	local entry = loadoutFor(player)

	local copy = table.create(#entry)
	for index, name in ipairs(entry) do
		copy[index] = name
	end

	LoadoutChanged:FireClient(player, copy, reason)
end

function AbilityLoadout.get(player: Player): { string }
	return loadoutFor(player)
end

function AbilityLoadout.has(player: Player, abilityName: string?): boolean
	if type(abilityName) ~= "string" then
		return false
	end

	for _, name in ipairs(loadoutFor(player)) do
		if name == abilityName then
			return true
		end
	end

	return false
end

--[[
	Adds an ability, if there is room and it is not already carried.

	Returns ok, message, slot. The message is written to be shown to the player
	as it is - this is reached from a chat command, and "there is no ability
	called that" is more use than a boolean.
]]
function AbilityLoadout.add(player: Player, abilityName: string)
	local definition = AbilityConfig.get(abilityName)
	if not definition then
		return false, string.format("There is no ability called '%s'.", tostring(abilityName))
	end

	local entry = loadoutFor(player)

	for slot, name in ipairs(entry) do
		if name == abilityName then
			return false, string.format(
				"%s is already in slot %d.", definition.displayName or abilityName, slot
			)
		end
	end

	if #entry >= SLOT_COUNT then
		return false, string.format(
			"All %d slots are full. Remove one first.", SLOT_COUNT
		)
	end

	table.insert(entry, abilityName)
	push(player)
	markDirty(player)

	local slot = #entry
	local key = AbilityConfig.keyForSlot(slot)

	return true, string.format(
		"%s added to slot %d%s.",
		definition.displayName or abilityName,
		slot,
		if key then " (" .. key.Name .. ")" else ""
	), slot
end

--[[
	Removes an ability. Everything after it moves up a slot, so the keys stay
	contiguous - see the note at the top about why that matters.
]]
function AbilityLoadout.remove(player: Player, abilityName: string)
	local definition = AbilityConfig.get(abilityName)
	if not definition then
		return false, string.format("There is no ability called '%s'.", tostring(abilityName))
	end

	local entry = loadoutFor(player)

	for slot, name in ipairs(entry) do
		if name == abilityName then
			table.remove(entry, slot)
			push(player)
			markDirty(player)
			return true, string.format("%s removed.", definition.displayName or abilityName)
		end
	end

	return false, string.format(
		"You are not carrying %s.", definition.displayName or abilityName
	)
end

--[[
	Moves the ability in slot `from` to slot `to`, sliding the rest along.

	A move rather than a swap, which is what a list being dragged does: pulling
	slot 3 up to slot 1 pushes 1 and 2 down a place, it does not send 1 to the
	bottom. Both ends are clamped into the filled range, so a drop past the last
	ability lands on it instead of opening a gap - see the note at the top about
	the array being dense.

	Returns whether anything actually moved. A request that resolves to no
	change is not an error and is not refused; it just has nothing to save.
]]
function AbilityLoadout.reorder(player: Player, from: number, to: number): boolean
	local entry = loadoutFor(player)
	local count = #entry

	if count < 2 then
		return false
	end

	if type(from) ~= "number" or type(to) ~= "number" then
		return false
	end

	-- Rounded before clamping: a client is free to send 2.5, and math.clamp
	-- would happily leave it there for table.remove to reject later.
	from = math.clamp(math.floor(from + 0.5), 1, count)
	to = math.clamp(math.floor(to + 0.5), 1, count)

	if from == to then
		return false
	end

	table.insert(entry, to, table.remove(entry, from))
	push(player)
	markDirty(player)

	return true
end

--[[
	Drops whatever is in a slot, by SLOT rather than by name.

	The Tab menu's bin is the only caller, and what it has is a position in a
	list. Taking the slot instead of the name also means there is no name to
	check against the loadout - a number either indexes something the player is
	carrying or it does not - so the whole class of "asked to remove an ability
	somebody else has" cannot be expressed.

	Everything after it shuffles up, exactly as `remove` does; see the note at
	the top about the array being dense.

	Returns whether anything went, and the display name of what did, so the
	caller can say so.
]]
function AbilityLoadout.dropSlot(player: Player, slot: number): (boolean, string?)
	if type(slot) ~= "number" then
		return false, nil
	end

	local entry = loadoutFor(player)
	slot = math.floor(slot + 0.5)

	if slot < 1 or slot > #entry then
		return false, nil
	end

	local abilityName = table.remove(entry, slot)
	push(player)
	markDirty(player)

	local definition = AbilityConfig.get(abilityName)
	return true, (definition and definition.displayName) or abilityName
end

function AbilityLoadout.clear(player: Player): number
	local entry = loadoutFor(player)
	local count = #entry

	if count > 0 then
		table.clear(entry)
		push(player)
		markDirty(player)
	end

	return count
end

-- ===========================================================================
-- THE REORDER REQUEST
-- ===========================================================================

-- player -> { budget, budgetAt }. Weak-keyed; PlayerRemoving clears it too.
local reorderBudgets = setmetatable({}, { __mode = "k" })

--[[
	One token per request, refilled continuously.

	The same shape as AbilityService's cast limiter, and for the same reason: a
	bucket lets a burst through - a player really can drag twice in a second -
	while a fixed "one every 250ms" would refuse the second drag of a pair that
	a human genuinely did.
]]
local function takeReorderToken(player: Player): boolean
	local now = os.clock()

	local entry = reorderBudgets[player]
	if not entry then
		entry = { budget = REORDERS_PER_SECOND, budgetAt = now }
		reorderBudgets[player] = entry
	end

	entry.budget = math.min(
		REORDERS_PER_SECOND,
		entry.budget + (now - entry.budgetAt) * REORDERS_PER_SECOND
	)
	entry.budgetAt = now

	if entry.budget < 1 then
		return false
	end

	entry.budget -= 1
	return true
end

RequestReorder.OnServerEvent:Connect(function(player, from, to)
	if not takeReorderToken(player) then
		return
	end

	--[[
		Answered whether or not anything moved, and whether or not the numbers
		made sense.

		The panel moves the card the moment it is dropped and relies on being
		corrected. Staying silent on a refusal is what would leave a client
		showing an order the server never agreed to, which is the one outcome
		worth spending a push to avoid. A successful reorder has already pushed
		for itself, which is why this one is only for the other case.
	]]
	if not AbilityLoadout.reorder(player, from, to) then
		push(player)
	end
end)

--[[
	The bin. Same budget as a reorder, and answered the same way whatever
	happens, because the panel has already taken the card off screen.

	Sharing one budget between the two is deliberate: they are the same gesture
	from the same panel, and a client that has spent its allowance dragging
	cards about has spent it.
]]
RequestDrop.OnServerEvent:Connect(function(player, slot)
	if not takeReorderToken(player) then
		return
	end

	local dropped, name = AbilityLoadout.dropSlot(player, slot)

	if dropped then
		-- Neutral, not "bad": the player meant to do this. The line exists
		-- because a card vanishing off a panel is not, on its own, proof that
		-- the server agreed - and this is sent only when it did.
		CommandFeedback.tell(player, string.format("%s dropped.", name))
	else
		push(player)
	end
end)

-- ===========================================================================
-- PERSISTENCE
-- ===========================================================================

--[[
	Stored as a plain array of names. The array order IS the slot order, so
	there is nothing else to write down.
]]
local function saveSection(player: Player)
	local entry = loadouts[player]
	if not entry or #entry == 0 then
		-- nil rather than an empty array: nothing to say, and the record stays
		-- one field smaller.
		return nil
	end

	local copy = table.create(#entry)
	table.move(entry, 1, #entry, 1, copy)
	return copy
end

--[[
	Restores a stored loadout, re-checking it on the way in.

	A save outlives the code that wrote it. An ability that has since been
	renamed or removed leaves a name in somebody's record that means nothing
	now, and SlotCount could come down - so names are looked up again,
	duplicates dropped, and the cap re-applied. A slot handed back is better
	than a slot holding a ghost.

	Anything unreadable leaves the player on the empty loadout they already
	have, which is a correct starting state rather than a lost one.
]]
local function loadSection(player: Player, value)
	if type(value) ~= "table" then
		return
	end

	local entry = loadoutFor(player)
	table.clear(entry)

	for _, name in ipairs(value) do
		if #entry >= SLOT_COUNT then
			break
		end

		if type(name) == "string" and AbilityConfig.get(name) then
			local seen = false
			for _, existing in ipairs(entry) do
				if existing == name then
					seen = true
					break
				end
			end
			if not seen then
				table.insert(entry, name)
			end
		end
	end

	-- The client was told "nothing" a moment ago by onPlayerAdded; this is what
	-- corrects it. Unconditional, because dropping every stored name is still a
	-- change worth sending.
	push(player, "restore")
end

InventoryStore.registerSection("abilities", saveSection, loadSection)

-- ===========================================================================
-- PAID STORAGE
-- ===========================================================================

--[[
	Three extra slots an ability can be parked in instead of thrown away, sold
	as a gamepass.

	TWO DIFFERENT THINGS PERSIST, AND ONLY ONE OF THEM IS OURS.

	The CONTENTS of the slots are ours, and they go in the same locked save
	record as everything else, as an InventoryStore section. Everything that
	protects the inventory therefore protects these too: one key, one session
	lock, one autosave, and a read-only session that refuses to write rather
	than writing a guess over good data.

	OWNERSHIP is Roblox's, and is deliberately NOT stored. It is asked of
	MarketplaceService once per session and cached for that session, because a
	gamepass belongs to the account rather than to our save file - a player who
	buys it on one server owns it on the next, and a refund has to be able to
	take it away again. Writing "owned" into the save would make a refund
	un-actionable and a duped record into free product.

	What that means for a player who stops owning it: the slots stay exactly as
	they were, the contents are still saved, and the panel locks. Nothing is
	destroyed. Re-buying gives it all back.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local StorageConfig = require(Shared.Abilities.StorageConfig)

local StorageRequest = Remotes.ensure("AbilityStorageRequest", "RemoteEvent")
local StorageChanged = Remotes.ensure("AbilityStorageChanged", "RemoteEvent")

-- How many the pass buys. Named because it is asserted in three places -
-- the loader, the store path, and the client's panel.
local STORAGE_SLOTS = 3

-- The shortest gap between two storage requests from one player, and how long
-- a "does not own it" answer is trusted before MarketplaceService is asked
-- again. Ownership can only ever change through the purchase flow below, which
-- clears the cache itself, so this only ever delays noticing a purchase made
-- somewhere else entirely.
local STORAGE_COOLDOWN = 0.3
local OWNERSHIP_RECHECK = 30

--[[
	The contents, per player.

	WEAK-KEYED, AND NOT CLEARED ON PlayerRemoving. That is deliberate and it is
	load-bearing: InventoryManager saves on leave through InventoryStore.release,
	which serialises every registered section - and the order two server scripts
	connect to PlayerRemoving in is undefined. Clear this there and roughly half
	the time the section save reads an empty table and writes it over a paying
	player's stored abilities.

	So the entry outlives the player until the save has read it, and the weak key
	is what collects it afterwards. `loadouts` above works the same way for the
	same reason.
]]
local stored = setmetatable({}, { __mode = "k" })
local storageReady = {}
local storageOwned = {}
local storageChecked = {}
local storageBusy = {}
local storageLast = {}

local function storagePush(player)
	StorageChanged:FireClient(player, {
		slots = table.clone(stored[player] or {}),
		owned = storageOwned[player] == true,
		ready = storageReady[player] == true,
		capacity = STORAGE_SLOTS,
		passId = StorageConfig.AbilityStoragePassId,
	})
end

--[[
	The contents, as a section of the one save record.

	Re-validated on the way in against AbilityConfig, the same as the active
	loadout is: a name that stopped existing between sessions is dropped rather
	than carried around as a slot nobody can use. Duplicates are dropped too,
	since the same ability cannot be in two places.

	The loader runs ONLY when a real record came back - see InventoryStore - so
	storageReady stays false on every failure path, and the request handler
	below refuses to touch anything until it is true. That is what stops a
	read-only session presenting an empty store as if it were saved state and
	then being asked to overwrite it.
]]
InventoryStore.registerSection("abilityStorage", function(player)
	return table.clone(stored[player] or {})
end, function(player, value)
	local entry = {}

	if type(value) == "table" then
		for _, name in ipairs(value) do
			if #entry >= STORAGE_SLOTS then
				break
			end
			if type(name) == "string" and AbilityConfig.get(name) and not table.find(entry, name) then
				table.insert(entry, name)
			end
		end
	end

	stored[player] = entry
	storageReady[player] = true
	storagePush(player)
end)

function AbilityLoadout.isStored(player, name)
	return table.find(stored[player] or {}, name) ~= nil
end

--[[
	Does this player own the pass?

	Returns true, false, or NIL for "could not find out", which the caller has
	to tell them about rather than treating as a no - a MarketplaceService
	outage must not read as "you did not buy this".

	A positive is cached for the session and a negative for OWNERSHIP_RECHECK,
	because the panel sends a sync on every open and this would otherwise be a
	web call per click on an API Roblox rate-limits.
]]
local function verifyStorage(player)
	if storageOwned[player] then
		return true
	end

	if StorageConfig.AbilityStoragePassId <= 0 then
		return false
	end

	local checked = storageChecked[player]
	if checked and os.clock() - checked < OWNERSHIP_RECHECK then
		return false
	end

	local ok, owns = pcall(
		MarketplaceService.UserOwnsGamePassAsync,
		MarketplaceService,
		player.UserId,
		StorageConfig.AbilityStoragePassId
	)

	if not ok then
		return nil
	end

	if owns then
		storageOwned[player] = true
		storageChecked[player] = nil
		return true
	end

	storageChecked[player] = os.clock()
	return false
end

StorageRequest.OnServerEvent:Connect(function(player, action, name, other)
	if storageBusy[player] or os.clock() - (storageLast[player] or -10) < STORAGE_COOLDOWN then
		return
	end

	storageLast[player] = os.clock()
	storageBusy[player] = true

	local ok, err = pcall(function()
		local owns = verifyStorage(player)

		-- verifyStorage yields on the web call, so the player may be gone.
		if not player.Parent then
			return
		end

		--[[
			A sync is a pure read and answers whatever is known, including
			"could not find out" - which reads as locked until a later request
			resolves it.

			Before the ownership test on purpose. This is the request the client
			sends on join and on every open, so failing it during a
			MarketplaceService wobble would leave a paying player looking at a
			panel that never drew, rather than at one that locked.
		]]
		if action == "sync" then
			storagePush(player)
			return
		end

		if owns == nil then
			CommandFeedback.tell(player, "Could not check gamepass ownership. Please try again.", "bad")
			return
		end

		if not storageReady[player] or InventoryStore.isReadOnly(player) then
			CommandFeedback.tell(player, "Your save is not ready. Please try again.", "bad")
			return
		end

		if not owns then
			if StorageConfig.AbilityStoragePassId > 0 then
				MarketplaceService:PromptGamePassPurchase(player, StorageConfig.AbilityStoragePassId)
			else
				CommandFeedback.tell(player, "+3 ability storage is not on sale yet.", "bad")
			end
			return
		end

		local active = loadoutFor(player)
		local bank = stored[player]

		if action == "store" then
			local index = table.find(active, name)
			if not index then
				return
			end
			if #bank >= STORAGE_SLOTS then
				CommandFeedback.tell(player, "Storage is full. Open it to swap an ability.", "bad")
				return
			end
			if table.find(bank, name) then
				CommandFeedback.tell(player, "That ability is already stored.", "bad")
				return
			end
			table.remove(active, index)
			table.insert(bank, name)
		elseif action == "retrieve" then
			local index = table.find(bank, name)
			if not index then
				return
			end
			if #active >= SLOT_COUNT or table.find(active, name) then
				CommandFeedback.tell(player, "Choose an active ability to swap, or free a slot.", "bad")
				return
			end
			table.remove(bank, index)
			table.insert(active, name)
		elseif action == "swap" then
			local from = table.find(bank, name)
			local to = table.find(active, other)
			if not from or not to or table.find(active, name) or table.find(bank, other) then
				return
			end
			active[to], bank[from] = bank[from], active[to]
		else
			return
		end

		markDirty(player)
		push(player)
		storagePush(player)
	end)

	storageBusy[player] = nil

	if not ok then
		warn("[AbilityStorage]", err)
		CommandFeedback.tell(player, "Storage is unavailable. Please try again.", "bad")
	end
end)

--[[
	The purchase landed.

	`purchased` from this event is the authority and is TRUSTED, rather than
	turned round into another UserOwnsGamePassAsync. That call is cached by
	Roblox and routinely still answers false in the seconds after a purchase -
	so asking it here is how a player pays and stays locked out until they
	rejoin, which is the one failure this feature cannot afford.

	The event is server-side, so there is nothing for a client to forge.
]]
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, purchased)
	if id ~= StorageConfig.AbilityStoragePassId or not purchased then
		return
	end

	storageOwned[player] = true
	storageChecked[player] = nil
	storagePush(player)

	CommandFeedback.tell(
		player,
		"Three ability storage slots unlocked. Drag an ability there to store it.",
		"good"
	)
end)

Players.PlayerRemoving:Connect(function(player)
	-- Everything EXCEPT the contents, which the leave save has not necessarily
	-- read yet. See the note on `stored`.
	storageReady[player] = nil
	storageOwned[player] = nil
	storageChecked[player] = nil
	storageBusy[player] = nil
	storageLast[player] = nil
end)

-- ===========================================================================
-- LIFECYCLE
-- ===========================================================================

local function onPlayerAdded(player: Player)
	-- Created rather than reset: if this module is required late the stored
	-- loadout can already have arrived, and clearing it here would undo it.
	loadoutFor(player)

	-- Deferred for the same reason SettingsServer defers its first reply: the
	-- client's own scripts are still starting, and a push that lands before the
	-- ability panel is listening leaves it blank until something changes.
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
	-- Weak keys retain the loadout until InventoryStore finishes its leave save.
	reorderBudgets[player] = nil
end)

return AbilityLoadout
