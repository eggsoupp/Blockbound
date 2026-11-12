--[[
	AbilityLoadout

	What a player carries: ONE active aspect, its abilities on the three slot
	keys, and the aspects they keep in storage. Server-owned.

	  AbilityLoadout.aspect(player)                -> active aspect name, or nil
	  AbilityLoadout.get(player)                   -> slot abilities, in key order
	  AbilityLoadout.has(player, ability)          -> on a slot right now
	  AbilityLoadout.grantAspect(player, aspect, reason, overflow)
	                                               -> where, isNew, message | nil, message
	  AbilityLoadout.useAspect(player, aspect)     -> make a stored aspect the active one
	  AbilityLoadout.setAspect(player, aspect)     -> admin / tutorial: replace the active one
	  AbilityLoadout.clearAspect(player)           -> no active aspect
	  AbilityLoadout.owns(player, aspect)          -> active, stored or permanent
	  AbilityLoadout.grantPermanent(player, aspect) / ownsPermanent / revokePermanent

	PERMANENT ASPECTS are bought in the Aspect Shop (AspectShop, Game Passes).
	They are never used up and never destroyed: equipping one costs nothing,
	and replacing it leaves it in the inventory.

	ASPECTS (Shared.Abilities.AspectConfig)

	An aspect is a set of abilities. A player uses one at a time, and its
	abilities sit on Z / X / V in the aspect's own order - always, with nothing
	for the player to rearrange. Using a different aspect REPLACES the active
	one, and the one it replaced is gone - it does not go back to storage.
	Keeping a spare copy in storage is how a player keeps the option of
	switching back.

	STORAGE

	Free: one copy of each aspect. Bought (the Developer Product below, three
	slots a purchase): room for EXTRA copies of aspects already stored. So the
	number that capacity limits is "stored copies beyond the first of each".
	Wishes may overflow it (a wish is never lost), up to HELD_MAX in all.

	THIS IS THE PERMISSION CHECK

	AbilityService asks `has` before it runs anything, so a modified client
	naming an ability that is not on one of its slots gets nothing. The slots
	only ever hold abilities of the active aspect.

	PERSISTED ALONGSIDE THE INVENTORY

	Two sections of the record InventoryStore keeps, so they share its session
	lock, autosave and shutdown save:

	  "abilities"       { aspect = "Ember", slots = { "Fireball", ... } }
	  "abilityStorage"  { aspects = { ... }, purchases = n, receipts = { ... } }

	`slots` is written for reading a save by eye; on load the slots are rebuilt
	from the aspect, in its order. Saves from before aspects (an array of
	ability names in "abilities", and `slots` of ability names in
	"abilityStorage") are converted on load: the first carried ability's
	aspect becomes the active one and every other aspect the player had an
	ability of is stored, one copy each. Sections load in registration order,
	so the loadout section runs first and hands its leftovers to the storage
	section through `carry`.

	Nothing here calls save(). A change marks the record dirty and the next
	autosave carries it - except a purchase, which saves before it confirms.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AbilityConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))
local AspectConfig = require(Shared.Abilities:WaitForChild("AspectConfig"))

local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

local AbilityLoadout = {}

local LoadoutChanged = Remotes.ensure("AbilityLoadoutChanged", "RemoteEvent")

local SLOT_COUNT = AbilityConfig.SlotCount

--[[
	player -> active aspect name, and player -> slot abilities.

	WEAK-KEYED, AND NOTHING CLEARS THEM ON PlayerRemoving. The leave save runs
	through InventoryStore.release, which serialises every registered section,
	and the order two server scripts connect to PlayerRemoving in is
	undefined. Clear these on leave and about half the time the save reads an
	empty loadout and writes it over a real one. The weak key collects them
	once the save has read them. `stored` further down works the same way.
]]
local aspects = setmetatable({}, { __mode = "k" })
local loadouts = setmetatable({}, { __mode = "k" })

-- Aspects found in a pre-aspect loadout, waiting for the storage section.
local carry = setmetatable({}, { __mode = "k" })

local function loadoutFor(player: Player): { string }
	local entry = loadouts[player]
	if not entry then
		entry = {}
		loadouts[player] = entry
	end
	return entry
end

local function markDirty(player: Player)
	InventoryStore.markDirty(player)
end

--[[
	Tells the client what it is carrying: the slot abilities (a copy), why, and
	the active aspect.

	`reason` is "restore" for the saved loadout arriving on join and "wish" for
	a banner grant; the client does not celebrate either (the reveal does).
]]
local function push(player: Player, reason: string?)
	local entry = loadoutFor(player)
	local copy = table.create(#entry)
	for index, name in ipairs(entry) do
		copy[index] = name
	end
	LoadoutChanged:FireClient(player, copy, reason, aspects[player])
end

-- The slots: the aspect's abilities in its own order, as many as there are keys.
local function fillSlots(entry: { string }, aspectName: string?)
	table.clear(entry)
	for _, abilityName in ipairs(AspectConfig.abilitiesOf(aspectName)) do
		if #entry >= SLOT_COUNT then
			break
		end
		table.insert(entry, abilityName)
	end
end

-- Makes `aspectName` (or nothing) the active aspect, and refills the slots.
local function setActive(player: Player, aspectName: string?, reason: string?)
	aspects[player] = aspectName
	fillSlots(loadoutFor(player), aspectName)
	push(player, reason)
	markDirty(player)
end

function AbilityLoadout.aspect(player: Player): string?
	return aspects[player]
end

function AbilityLoadout.get(player: Player): { string }
	return loadoutFor(player)
end

function AbilityLoadout.has(player: Player, abilityName: string?): boolean
	if type(abilityName) ~= "string" then
		return false
	end
	return table.find(loadoutFor(player), abilityName) ~= nil
end

-- ===========================================================================
-- PERSISTENCE: THE ACTIVE ASPECT
-- ===========================================================================

local function saveSection(player: Player)
	local aspectName = aspects[player]
	if not aspectName then
		return nil
	end
	local entry = loadouts[player] or {}
	local copy = table.create(#entry)
	table.move(entry, 1, #entry, 1, copy)
	return { aspect = aspectName, slots = copy }
end

--[[
	Restores the active aspect, re-checking it: one that has since been removed
	leaves the player with none. The slots are rebuilt from the aspect rather
	than read back, so they always follow its order and pick up abilities
	added to it since.
]]
local function loadSection(player: Player, value)
	local entry = loadoutFor(player)
	table.clear(entry)
	aspects[player] = nil
	carry[player] = nil

	if type(value) ~= "table" then
		push(player, "restore")
		return
	end

	local aspectName
	if type(value.aspect) == "string" then
		aspectName = if AspectConfig.get(value.aspect) then value.aspect else nil
	else
		-- Before aspects: an array of ability names.
		local extras = {}
		for _, abilityName in ipairs(value) do
			local owner = type(abilityName) == "string" and AspectConfig.aspectOf(abilityName)
			if owner then
				if not aspectName then
					aspectName = owner
				elseif owner ~= aspectName and not table.find(extras, owner) then
					table.insert(extras, owner)
				end
			end
		end
		carry[player] = extras
	end

	aspects[player] = aspectName
	fillSlots(entry, aspectName)
	push(player, "restore")
end

InventoryStore.registerSection("abilities", saveSection, loadSection)

-- ===========================================================================
-- ASPECT STORAGE
-- ===========================================================================

--[[
	Aspects kept instead of used. One copy of each is free; extra copies need
	slots bought as a Developer Product, three at a time, as many times as a
	player likes up to StorageConfig.MaxSlots.

	A Developer Product, unlike a Game Pass, is not remembered by Roblox: each
	purchase is handed over once, through ProcessReceipt. So what a player has
	bought - the number of purchases and the recent PurchaseIds - goes in the
	same locked section as the stored aspects. A purchase is only confirmed to
	Roblox once that record has been SAVED (see grantPurchase).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local StorageConfig = require(Shared.Abilities.StorageConfig)
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local Purchases = require(ServerScriptService:WaitForChild("Purchases"))

local StorageRequest = Remotes.ensure("AbilityStorageRequest", "RemoteEvent")
local StorageChanged = Remotes.ensure("AbilityStorageChanged", "RemoteEvent")

local SLOTS_PER_PURCHASE = StorageConfig.SlotsPerPurchase
local MAX_SLOTS = StorageConfig.MaxSlots
-- The most aspects storage holds at all, bought or not: wishes overflow
-- bought capacity (see grantAspect), and this keeps the record bounded.
local HELD_MAX = 200
local PRODUCT_ID = StorageConfig.AbilityStorageProductId

-- The shortest gap between two storage requests from one player.
local STORAGE_COOLDOWN = 0.3

-- How many PurchaseIds are kept to recognise a receipt Roblox sends twice.
local RECEIPTS_KEPT = 20

-- Weak-keyed and not cleared on PlayerRemoving; see the note on `aspects`.
local stored = setmetatable({}, { __mode = "k" })
local purchases = setmetatable({}, { __mode = "k" })
local receipts = setmetatable({}, { __mode = "k" })
--[[
	player -> { [aspectName] = true }: PERMANENT aspects, bought in the Aspect
	Shop (ServerScriptService.AspectShop) or granted by an admin. Owned for
	good: equipping one never uses it up, and replacing it never destroys it.
	Saved with storage, and re-confirmed from Game Pass ownership on join.
]]
local permanent = setmetatable({}, { __mode = "k" })
--[[
	PERMANENT PASSES: what a Game Pass purchase turns into.

	  passes   player -> { aspectName, ... }  unredeemed permanent passes, one
	           entry per pass. A thing in the inventory: it can be TRADED
	           (ServerScriptService.Trade) or REDEEMED, which uses it up and
	           makes the aspect permanent. A redeemed aspect cannot be traded.
	  claimed  player -> { [aspectName] = true }  aspects whose Game Pass this
	           account has already been handed as a pass above. Roblox goes on
	           saying the account owns the Game Pass for ever, whatever became
	           of what it bought; this is what stops the join check handing it
	           out a second time. See claimPass.
]]
local passes = setmetatable({}, { __mode = "k" })
local claimed = setmetatable({}, { __mode = "k" })
local storageReady = {}
local storageBusy = {}
local storageLast = {}

-- Bought slots: room for extra copies.
local function capacityOf(player): number
	return math.min((purchases[player] or 0) * SLOTS_PER_PURCHASE, MAX_SLOTS)
end

-- Stored copies beyond the first of each aspect: what bought slots hold.
local function extrasOf(bank: { string }): number
	local distinct = {}
	local count = 0
	for _, name in ipairs(bank) do
		if not distinct[name] then
			distinct[name] = true
			count += 1
		end
	end
	return #bank - count
end

local function onSale(): boolean
	return PRODUCT_ID > 0
end

-- The permanent aspects as a list, in AspectConfig order.
local function permanentList(player): { string }
	local owned = permanent[player] or {}
	local list = {}
	for _, name in ipairs(AspectConfig.names()) do
		if owned[name] then
			table.insert(list, name)
		end
	end
	return list
end

-- The aspects whose Game Pass has been claimed, sorted so saves do not churn.
local function claimedList(player): { string }
	local list = {}
	for name in pairs(claimed[player] or {}) do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

local function storagePush(player)
	local capacity = capacityOf(player)
	local bank = stored[player] or {}
	StorageChanged:FireClient(player, {
		slots = table.clone(bank),
		permanent = permanentList(player),
		passes = table.clone(passes[player] or {}),
		claimed = claimedList(player),
		extras = extrasOf(bank),
		capacity = capacity,
		owned = capacity > 0,
		ready = storageReady[player] == true,
		maxSlots = MAX_SLOTS,
		perPurchase = SLOTS_PER_PURCHASE,
		productId = PRODUCT_ID,
		canBuy = onSale() and capacity + SLOTS_PER_PURCHASE <= MAX_SLOTS,
	})
end

--[[
	The section. Stored names are re-checked on the way in against
	AspectConfig. A save from before aspects stored ABILITY names in `slots`;
	those become one copy of each aspect they belong to. Aspects carried over
	from a pre-aspect loadout (see loadSection) are added the same way.

	The loader runs ONLY when a real record came back - see InventoryStore - so
	storageReady stays false on every failure path, and nothing that writes
	here runs until it is true.
]]
InventoryStore.registerSection("abilityStorage", function(player)
	return {
		aspects = table.clone(stored[player] or {}),
		-- Empty, and only for a server still running the pre-aspect code: it
		-- reads `purchases` only when `slots` is a table, so without this it
		-- would load (and then save) a paying player's storage as unbought.
		slots = {},
		purchases = purchases[player] or 0,
		receipts = table.clone(receipts[player] or {}),
		permanent = permanentList(player),
		passes = table.clone(passes[player] or {}),
		claimed = claimedList(player),
	}
end, function(player, value)
	local entry, bought, seen, owned = {}, 0, {}, {}

	local spent, held = {}, {}
	if type(value) == "table" then
		if type(value.claimed) == "table" then
			for _, name in ipairs(value.claimed) do
				if type(name) == "string" then
					spent[name] = true
				end
			end
		end
		if type(value.passes) == "table" then
			for _, name in ipairs(value.passes) do
				if type(name) == "string" and AspectConfig.get(name) and #held < HELD_MAX then
					table.insert(held, name)
				end
			end
		end
	end
	claimed[player] = spent
	passes[player] = held

	if type(value) == "table" and type(value.permanent) == "table" then
		for _, name in ipairs(value.permanent) do
			if type(name) == "string" and AspectConfig.get(name) then
				owned[name] = true
			end
		end
	end

	local function addOnce(aspectName)
		if aspectName and #entry < HELD_MAX and not table.find(entry, aspectName) then
			table.insert(entry, aspectName)
		end
	end

	if type(value) == "table" then
		if type(value.aspects) == "table" then
			-- Duplicates are kept: they are the bought extra copies.
			for _, name in ipairs(value.aspects) do
				if #entry >= HELD_MAX then
					break
				end
				if type(name) == "string" and AspectConfig.get(name) then
					table.insert(entry, name)
				end
			end
		else
			-- Before aspects: ability names, in `slots` or (older still) bare.
			local names = if type(value.slots) == "table" then value.slots else value
			for _, name in ipairs(names) do
				if type(name) == "string" then
					addOnce(AspectConfig.aspectOf(name))
				end
			end
		end

		if type(value.slots) == "table" or type(value.aspects) == "table" then
			bought = math.max(0, math.floor(tonumber(value.purchases) or 0))
			if type(value.receipts) == "table" then
				for _, id in ipairs(value.receipts) do
					if type(id) == "string" then
						table.insert(seen, id)
					end
				end
			end
		end
	end

	for _, aspectName in ipairs(carry[player] or {}) do
		addOnce(aspectName)
	end
	carry[player] = nil

	stored[player] = entry
	purchases[player] = bought
	receipts[player] = seen
	permanent[player] = owned
	storageReady[player] = true
	storagePush(player)
end)

-- Whether the player has this aspect active, stored or permanently.
function AbilityLoadout.owns(player, aspectName): boolean
	return aspects[player] == aspectName
		or table.find(stored[player] or {}, aspectName) ~= nil
		or (permanent[player] or {})[aspectName] == true
end

-- Whether storage has loaded from a real record (AspectShop waits for it).
function AbilityLoadout.isReady(player): boolean
	return storageReady[player] == true
end

function AbilityLoadout.ownsPermanent(player, aspectName): boolean
	return type(aspectName) == "string" and (permanent[player] or {})[aspectName] == true
end

--[[
	Makes an aspect permanently the player's (a shop purchase, a Game Pass
	found on join, or an admin). With no aspect in use it is also equipped.
	Returns whether it was new.
]]
function AbilityLoadout.grantPermanent(player, aspectName): boolean
	if not AspectConfig.get(aspectName) or not storageReady[player] then
		return false
	end
	local owned = permanent[player]
	if owned[aspectName] then
		return false
	end
	owned[aspectName] = true
	markDirty(player)
	if aspects[player] == nil then
		setActive(player, aspectName)
	end
	storagePush(player)
	return true
end

-- Whether this account's Game Pass for the aspect has already been handed over.
function AbilityLoadout.passClaimed(player, aspectName): boolean
	return (claimed[player] or {})[aspectName] == true
end

-- How many unredeemed permanent passes for the aspect the player holds.
function AbilityLoadout.passCount(player, aspectName): number
	local count = 0
	for _, name in ipairs(passes[player] or {}) do
		if name == aspectName then
			count += 1
		end
	end
	return count
end

-- Puts one permanent pass in the inventory (a claim, or a trade arriving).
function AbilityLoadout.addPass(player, aspectName): boolean
	local held = passes[player]
	if not AspectConfig.get(aspectName) or not storageReady[player] or not held or #held >= HELD_MAX then
		return false
	end
	table.insert(held, aspectName)
	markDirty(player)
	storagePush(player)
	return true
end

-- Takes one permanent pass out (a trade leaving). Returns whether one was there.
function AbilityLoadout.removePass(player, aspectName): boolean
	local held = passes[player]
	local index = held and table.find(held, aspectName)
	if not index then
		return false
	end
	table.remove(held, index)
	markDirty(player)
	storagePush(player)
	return true
end

--[[
	A Game Pass this account owns, handed over as a permanent pass in the
	inventory - once. Returns whether one was handed over.

	Nothing is equipped or made permanent here: the pass sits in the inventory
	until its owner either redeems it or trades it. Marking the claim and
	adding the pass happen together, in one section of one save, so there is no
	moment where the pass has been handed over but could be claimed again.
]]
function AbilityLoadout.claimPass(player, aspectName): boolean
	if not AspectConfig.get(aspectName) or not storageReady[player] or not claimed[player] then
		return false
	end
	if claimed[player][aspectName] then
		return false
	end
	if not AbilityLoadout.addPass(player, aspectName) then
		return false
	end
	claimed[player][aspectName] = true
	return true
end

--[[
	Uses up one permanent pass and makes its aspect permanently the player's.
	From here it is theirs for good and can no longer be traded. Returns ok and
	a line to show them.
]]
function AbilityLoadout.redeemPass(player, aspectName): (boolean, string)
	if type(aspectName) ~= "string" or not AspectConfig.get(aspectName) then
		return false, "There is no such aspect."
	end
	local label = AspectConfig.displayName(aspectName)
	if AbilityLoadout.ownsPermanent(player, aspectName) then
		return false, string.format("%s is already permanently yours. This pass can still be traded.", label)
	end
	if not AbilityLoadout.removePass(player, aspectName) then
		return false, "You have no permanent pass for that aspect."
	end
	AbilityLoadout.grantPermanent(player, aspectName)
	return true, string.format("%s is permanently yours. It can no longer be traded.", label)
end

-- Takes one away again (admin command only). Returns whether it was owned.
function AbilityLoadout.revokePermanent(player, aspectName): boolean
	local owned = permanent[player]
	if not (owned and owned[aspectName]) then
		return false
	end
	owned[aspectName] = nil
	markDirty(player)
	storagePush(player)
	return true
end

-- Kept for older callers: "is this stored", by aspect name.
function AbilityLoadout.isStored(player, aspectName): boolean
	return table.find(stored[player] or {}, aspectName) ~= nil
end

--[[
	Whether storage would take another copy of this aspect. `overflow` (wishes)
	ignores bought capacity; nothing ignores HELD_MAX.
]]
local function canStore(player, aspectName, overflow): (boolean, string?)
	local bank = stored[player]
	if not bank or #bank >= HELD_MAX then
		return false, "Aspect storage is full."
	end
	if overflow or not table.find(bank, aspectName) then
		return true
	end
	if extrasOf(bank) < capacityOf(player) then
		return true
	end
	if capacityOf(player) == 0 then
		return false, string.format(
			"You already have a %s aspect stored. Get storage slots to keep extra copies.",
			AspectConfig.displayName(aspectName)
		)
	end
	return false, "Your extra storage slots are full."
end

--[[
	Whether a wish can be granted right now: storage has loaded from a real
	record and the session can save. WishService asks before it spends.
]]
function AbilityLoadout.canReceive(player): boolean
	return storageReady[player] == true and not InventoryStore.isReadOnly(player)
		and #(stored[player] or {}) < HELD_MAX
end

--[[
	An aspect arrives (wish, scroll, chest, tutorial). With no active aspect it
	becomes the active one; otherwise it goes to storage, if storage takes it.

	Returns where it went ("active" or "storage"), whether the player owned no
	copy before, and a line to show them - or nil and why not.
]]
function AbilityLoadout.grantAspect(player, aspectName, reason: string?, overflow: boolean?)
	if not AspectConfig.get(aspectName) then
		return nil, string.format("There is no aspect called '%s'.", tostring(aspectName))
	end
	if not storageReady[player] then
		return nil, "Your save is not ready. Please try again."
	end

	local label = AspectConfig.displayName(aspectName)
	local isNew = not AbilityLoadout.owns(player, aspectName)

	if aspects[player] == nil then
		setActive(player, aspectName, reason)
		storagePush(player)
		return "active", isNew, string.format("%s is now your aspect.", label)
	end

	local ok, why = canStore(player, aspectName, overflow)
	if not ok then
		return nil, why
	end

	table.insert(stored[player], aspectName)
	markDirty(player)
	storagePush(player)
	return "storage", isNew, string.format("%s aspect sent to storage (Tab).", label)
end

-- The wishing banner's grant: storage overflows rather than lose a wish.
function AbilityLoadout.grantWished(player, aspectName)
	local where, isNew = AbilityLoadout.grantAspect(player, aspectName, "wish", true)
	return where, if where then isNew else nil
end

--[[
	Makes an aspect the active one: a PERMANENT one if the player owns it that
	way (nothing is used up), otherwise a stored copy (which is). The aspect it
	replaces is gone - unless that one is permanent, in which case it simply
	stays in the inventory to be equipped again. Returns ok, message.
]]
function AbilityLoadout.useAspect(player, aspectName)
	if type(aspectName) ~= "string" or not AspectConfig.get(aspectName) then
		return false, "There is no such aspect."
	end
	-- A spare copy of the aspect in use stays a spare; using it would only
	-- spend it. Equipping a permanent one twice does nothing.
	if aspects[player] == aspectName then
		return false, string.format("%s is already your aspect.", AspectConfig.displayName(aspectName))
	end

	local isPermanent = AbilityLoadout.ownsPermanent(player, aspectName)
	if not isPermanent then
		local bank = stored[player]
		local index = bank and table.find(bank, aspectName)
		if not index then
			return false, "That aspect is not in your inventory."
		end
		table.remove(bank, index)
	end

	local previous = aspects[player]
	setActive(player, aspectName)
	storagePush(player)

	local label = AspectConfig.displayName(aspectName)
	if previous and previous ~= aspectName then
		if AbilityLoadout.ownsPermanent(player, previous) then
			return true, string.format("%s is now your aspect. %s stays in your inventory.", label, AspectConfig.displayName(previous))
		end
		return true, string.format("%s is now your aspect. %s is gone.", label, AspectConfig.displayName(previous))
	end
	return true, string.format("%s is now your aspect.", label)
end

-- Replaces the active aspect outright (admin commands, the tutorial).
function AbilityLoadout.setAspect(player, aspectName, reason: string?)
	if not AspectConfig.get(aspectName) then
		return false
	end
	setActive(player, aspectName, reason)
	return true
end

function AbilityLoadout.clearAspect(player)
	if aspects[player] ~= nil then
		setActive(player, nil)
	end
end

-- Removes one stored copy (admin command). Returns whether one was there.
function AbilityLoadout.unstore(player, aspectName): boolean
	local bank = stored[player]
	local index = bank and table.find(bank, aspectName)
	if not index then
		return false
	end
	table.remove(bank, index)
	markDirty(player)
	storagePush(player)
	return true
end

function AbilityLoadout.stored(player): { string }
	return table.clone(stored[player] or {})
end

--[[
	For trading (ServerScriptService.Trade): could storage give up the copies
	in `removing` and then take the ones in `adding`? Changes nothing.

	The same rules as canStore, applied to the whole exchange at once: every
	copy given must be there, HELD_MAX holds, and copies beyond the first of
	each aspect need bought slots. A player already over their slots (wishes
	may overflow) is allowed to stay as far over as they are, not further.
	With no aspect in use the first one to arrive is equipped, not stored.
]]
function AbilityLoadout.canExchange(player, removing: { string }, adding: { string }): (boolean, string?)
	local bank = stored[player]
	if not storageReady[player] or not bank then
		return false, "the save is not ready"
	end

	local after = table.clone(bank)
	for _, aspectName in ipairs(removing) do
		local index = table.find(after, aspectName)
		if not index then
			return false, string.format("no spare %s aspect to give", AspectConfig.displayName(aspectName))
		end
		table.remove(after, index)
	end

	for index, aspectName in ipairs(adding) do
		if not AspectConfig.get(aspectName) then
			return false, "an aspect that does not exist"
		end
		if not (index == 1 and aspects[player] == nil) then
			table.insert(after, aspectName)
		end
	end

	if #after > HELD_MAX then
		return false, "aspect storage is full"
	end
	if extrasOf(after) > math.max(capacityOf(player), extrasOf(bank)) then
		return false, "no storage slots for another copy of an aspect already stored"
	end
	return true
end

--[[
	A purchase landed. Grants three more slots and saves them, then says true;
	anything short of a save says false, and Roblox offers the receipt again.
	Idempotent on the PurchaseId.
]]
local function grantPurchase(player, receipt)
	local purchaseId = tostring(receipt.PurchaseId)
	local seen = receipts[player]

	if not storageReady[player] or InventoryStore.isReadOnly(player) or not seen then
		return false
	end
	if table.find(seen, purchaseId) then
		return true
	end

	local inventory = InventoryService.GetInventory(player)
	if not inventory then
		return false
	end

	purchases[player] = (purchases[player] or 0) + 1
	table.insert(seen, purchaseId)
	while #seen > RECEIPTS_KEPT do
		table.remove(seen, 1)
	end

	local saved = InventoryStore.save(player, inventory, "purchase")
	if not saved then
		-- Taken back off, so the retry grants it once, not twice.
		purchases[player] -= 1
		table.remove(seen, table.find(seen, purchaseId))
		return false
	end

	if player.Parent then
		storagePush(player)
		CommandFeedback.tell(player, string.format(
			"+%d aspect storage slots. You now have %d.", SLOTS_PER_PURCHASE, capacityOf(player)
		), "good")
	end
	return true
end

Purchases.register(PRODUCT_ID, grantPurchase)

-- For DebugConsole's Studio-only /bbstorage. Studio's DataStore is the live
-- one, so a test purchase is a real change to that player's record.
AbilityLoadout.grantStoragePurchase = grantPurchase

function AbilityLoadout.resetStoragePurchases(player): boolean
	local inventory = InventoryService.GetInventory(player)
	if not storageReady[player] or InventoryStore.isReadOnly(player) or not inventory then
		return false
	end
	purchases[player] = 0
	receipts[player] = {}
	local saved = InventoryStore.save(player, inventory, "storage reset")
	storagePush(player)
	return saved
end

StorageRequest.OnServerEvent:Connect(function(player, action, name)
	if storageBusy[player] or os.clock() - (storageLast[player] or -10) < STORAGE_COOLDOWN then
		return
	end

	storageLast[player] = os.clock()
	storageBusy[player] = true

	local ok, err = pcall(function()
		-- A pure read: the client sends it on join and when the panel opens.
		if action == "sync" then
			storagePush(player)
			return
		end

		if action == "buy" then
			if not onSale() then
				CommandFeedback.tell(player, "Aspect storage is not on sale yet.", "bad")
			elseif capacityOf(player) + SLOTS_PER_PURCHASE > MAX_SLOTS then
				CommandFeedback.tell(player, "You have the most aspect storage there is.", "bad")
			elseif not storageReady[player] or InventoryStore.isReadOnly(player) then
				-- Bought now, it could not be saved; better not to take the money.
				CommandFeedback.tell(player, "Your save is not ready. Please try again.", "bad")
			else
				MarketplaceService:PromptProductPurchase(player, PRODUCT_ID)
			end
			return
		end

		if not storageReady[player] or InventoryStore.isReadOnly(player) then
			CommandFeedback.tell(player, "Your save is not ready. Please try again.", "bad")
			return
		end

		if action == "redeem" and type(name) == "string" then
			-- Confirmed on the client ("it can no longer be traded").
			local done, message = AbilityLoadout.redeemPass(player, name)
			CommandFeedback.tell(player, message, if done then "good" else "bad")
			if not done then
				storagePush(player)
			end
			return
		end

		if action == "use" and type(name) == "string" then
			-- Confirmed on the client ("the current aspect will be gone").
			local used, message = AbilityLoadout.useAspect(player, name)
			CommandFeedback.tell(player, message, if used then "good" else "bad")
			if not used then
				storagePush(player)
			end
			return
		end

		-- Anything else ("store", "swap", "move" from older clients): storage
		-- has one fixed order and the active aspect cannot be put back, so the
		-- request is answered with the real state and nothing else.
		storagePush(player)
		push(player)
	end)

	storageBusy[player] = nil

	if not ok then
		warn("[AspectStorage]", err)
		CommandFeedback.tell(player, "Storage is unavailable. Please try again.", "bad")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	-- Everything EXCEPT the contents and purchases, which the leave save has not
	-- necessarily read yet. See the note on `aspects`.
	storageReady[player] = nil
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

	-- Deferred: the client's scripts are still starting, and a push that lands
	-- before the ability panel is listening leaves it blank.
	task.delay(1, function()
		if player.Parent then
			push(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

return AbilityLoadout
