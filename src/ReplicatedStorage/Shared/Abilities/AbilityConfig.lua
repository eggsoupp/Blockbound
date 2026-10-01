--[[
	AbilityConfig

	The catalogue of abilities, and the rules the server enforces about casting
	them.

	ABILITIES ARE UNIVERSAL, NOT ITEM-BOUND

	They used to hang off a weapon: an item listed its abilities and holding it
	was what let you cast them. They are now a per-player LOADOUT of
	AbilityConfig.SlotCount slots, held by ServerScriptService.AbilityLoadout and
	filled with the /add and /remove chat commands. What you are holding no
	longer decides what you can cast - only what the effect is drawn with.

	THE CHAIN

	    /add SacredRain     ->  AbilityLoadout, three slots, server-owned
	         |
	    AbilityConfig.Definitions.SacredRain     what it costs to cast
	         |
	         +-- server = "SacredRain"    ServerScriptService.Abilities.SacredRain
	         |                            authority: cooldown, damage, hit detection
	         |
	         +-- vfx    = "SacredRainVFX" Shared.Abilities.VFX.SacredRainVFX
	                                      presentation: particles, sounds, tweens

	Adding an ability is one entry here, one server module and one VFX module.
	Nothing in AbilityService, AbilityLoadout or AbilityClient needs to know it
	exists - they all work from this table.

	WHY THE SPLIT IS SERVER MODULE / VFX MODULE AND NOT ONE FILE

	The two halves run on different machines and are trusted differently. The
	server module decides what happened; the VFX module decides what it looked
	like. A single file would inevitably grow a `if RunService:IsServer()` down
	the middle of it, and the first time somebody moved a damage number to the
	wrong side of that branch the ability would become client-authoritative.

	Anything both halves have to agree on - where the fifteen strikes land, and
	when - lives in a third, shared module (see SacredRainPlan). That is the
	only way the visuals can line up with the damage without either side telling
	the other where things are.

	FIELDS

	  displayName   what the player is shown; falls back to the internal name.
	  rarity        which tier the ability sits at. It colours the ability's name
	                in the UI and it is the colour the Tab menu's solid flashes
	                when the ability is equipped. The ladder, and which tier is
	                the top one, live in Shared.UI.Theme - the SAME ladder the
	                items are on, so a Legendary ability and a Legendary pickaxe
	                read as the same thing.
	  server        module name under ServerScriptService.Abilities
	  vfx           module name under Shared.Abilities.VFX; nil for an ability
	                with no presentation of its own
	  animation     an rbxassetid:// played on the CASTER when the ability fires,
	                or nil for one that does not animate. Played by every client
	                that receives the effect, so everyone sees the wind-up, and
	                played from the broadcast rather than from the keypress so a
	                refused cast does not animate.
	  cooldown      seconds between casts, enforced BY THE SERVER
	  manaCost      what it takes out of the pool, also enforced by the server.
	                The cooldown rations ONE ability against itself; the cost
	                rations every ability against all the others. See MaxMana.
	  castRange     how far from the caster a target point may be. The server
	                clamps rather than refuses, so a laggy aim still fires.
	  requiresTarget  whether the client must supply a target position at all
	  maxConcurrent   safety cap on simultaneous casts per player. NOT a balance
	                  dial - see the note on SacredRain.
	  tuning        free-form table handed to both halves. Ability-specific
	                numbers live here rather than in either module, so the server
	                and the VFX cannot disagree about them.
]]

local SacredRainPlan = require(script.Parent:WaitForChild("SacredRainPlan"))
local EclipsePlan = require(script.Parent:WaitForChild("EclipsePlan"))
local AnnihilationPlan = require(script.Parent:WaitForChild("AnnihilationPlan"))

local AbilityConfig = {}

-- ---------------------------------------------------------------------------
-- Global limits
-- ---------------------------------------------------------------------------

--[[
	Casts per player per second, across every ability, before requests are
	dropped outright.

	Separate from any ability's own cooldown on purpose: the cooldown is a game
	rule and is meant to be tuned, this is a guard against a client that has
	been modified to ignore it. A legitimate player never reaches it.
]]
AbilityConfig.RequestsPerSecond = 8

--[[
	The mana pool, and how fast it fills.

	A HUNDRED, flat, for everyone. There is no stat that raises it and nothing
	that spends it but abilities, so it is a budget rather than a resource: the
	interesting number is what a cast costs as a FRACTION of it, and writing the
	pool as 100 makes every cost read as that percentage directly.

	WHY BOTH THIS AND COOLDOWNS

	They ration different things. A cooldown rations one ability against itself
	and is what stops Sacred Rain being held down. Mana rations every ability
	against all the others, and is what stops the answer to "which do I press"
	always being "both". With the costs below, a full pool pays for one of each
	back to back and leaves nothing; after that you are choosing.

	REGEN IS CONTINUOUS AND MUCH SLOWER THAN THE COOLDOWNS

	Two a second is a full pool in fifty seconds, against cooldowns of six and
	twelve. So mana, not the cooldown, is what actually decides how often you
	cast: Sacred Rain comes off cooldown in six seconds and is affordable again
	after fifteen, Eclipse in twelve and affordable after twenty-eight.

	It started at five, which made the pool a formality - twelve seconds of
	Eclipse cooldown regenerated its whole cost. At two the pool is the limit
	and the cooldowns are the floor under it, which is the right way round.

	There is no pause after a cast before it starts filling again; if that is
	wanted later it belongs in ManaService, not here.

	Mana is NOT persisted. It fills on join and on respawn, because a player who
	logs in empty is a player who cannot do anything for twenty seconds, and
	that punishes nothing anybody did.
]]
AbilityConfig.MaxMana = 100
AbilityConfig.ManaRegenPerSecond = 2

--[[
	How many abilities a player may carry, and the key each slot answers to.

	The keys are a property of the SLOT, not of the ability. When abilities hung
	off a weapon each one could name its own key, because the only way two could
	collide was to put both on one item. Now that any three can be carried
	together, a per-ability key is a collision waiting to happen - so the slot
	owns it, and an ability plays from whichever slot it was put in.

	Z and X are the two the abilities already used, kept so the muscle memory
	survives. V is the third free key: C is crouch, E is the inventory, B is
	crafting, Tab is the menu and 1-9 are the hotbar.

	Changing SlotCount means changing SlotKeys to match; validate() checks it.
]]
AbilityConfig.SlotCount = 3
AbilityConfig.SlotKeys = {
	Enum.KeyCode.Z,
	Enum.KeyCode.X,
	Enum.KeyCode.V,
}

--[[
	The weapon an effect is drawn with when the caster is holding nothing.

	Sacred Rain rains the caster's own weapon, which was well defined when the
	ability belonged to one. Now that it can be cast bare-handed something has
	to fly, and this is it.

	It has to name a Tool in ReplicatedStorage.Tools. TestSword is the only
	authored weapon in the project today, which is exactly why this is a named
	setting rather than a string buried in the VFX: change it here the moment
	there is something better.
]]
AbilityConfig.DefaultCastWeapon = "TestSword"

--[[
	How far an ability's effect is broadcast. Beyond this the effect is simply
	not sent, which is the single biggest saving available: a barrage nobody can
	see costs nothing to the clients that cannot see it.

	Sized against Workspace.StreamingTargetRadius (384) plus the reach of the
	widest effect, so nothing pops in half-drawn at the edge.
]]
AbilityConfig.BroadcastRadius = 520

-- ---------------------------------------------------------------------------
-- Abilities
-- ---------------------------------------------------------------------------

AbilityConfig.Definitions = {
	AstralCollapse = {
		displayName = "Shard Burst", rarity = "Rare",
		server = "AstralCollapse", vfx = "AstralCollapseVFX",
		cooldown = 22, manaCost = 40, requiresTarget = true, castRange = 130, maxConcurrent = 1,
	},
	StormWell = {
		displayName = "Storm Well", rarity = "Epic",
		server = "StormWell", vfx = "StormWellVFX",
		cooldown = 20, manaCost = 35, requiresTarget = true, castRange = 120, maxConcurrent = 1,
	},
	Windburst = {
		displayName = "Windburst", rarity = "Common",
		server = "ElementalAttack", vfx = "ElementalVFX",
		cooldown = 5, manaCost = 12, requiresTarget = true, castRange = 110, maxConcurrent = 2,
	},
	ArcBurst = {
		displayName = "Arc Burst", rarity = "Uncommon",
		server = "ElementalAttack", vfx = "ElementalVFX",
		cooldown = 6, manaCost = 15, requiresTarget = true, castRange = 110, maxConcurrent = 2,
	},
	LightningStrike = {
		displayName = "Lightning Strike", rarity = "Epic",
		server = "ElementalAttack", vfx = "ElementalVFX",
		cooldown = 16, manaCost = 35, requiresTarget = true, castRange = 140, maxConcurrent = 1,
	},
	Annihilation = {
		displayName = "Annihilation",
		rarity = "Legendary",
		server = "Annihilation",
		vfx = "AnnihilationVFX",
		cooldown = 60,
		manaCost = 90,
		requiresTarget = true,
		castRange = 250,
		maxConcurrent = 1,
		tuning = AnnihilationPlan.Tuning,
	},
	--[[
		SacredRain

		The barrage from the SacredSwords reference place, with the reference's
		own weapon swapped for whatever the caster is holding.

		COOLDOWN IS THE REFERENCE'S OWN

		One second, which is what the reference's input script uses (`cds = 1`).
		It is aggressive for an effect that runs for four and a half seconds and
		it is deliberately not "fixed" here, because it is a balance decision
		rather than a bug. maxConcurrent is what keeps it safe regardless: a
		second cast may start on the reference's schedule, a fifteenth may not.

		castRange is the distance the reference's own mouse target can plausibly
		be at - it aims with Mouse.Hit, which lands on whatever the camera can
		see - rounded to something the server can check cheaply.
	]]
	SacredRain = {
		displayName = "Sacred Rain",

		--[[
			Legendary, because there is nothing under it to be.

			Both abilities in the game today are endgame buttons handed out by
			an admin command, so the ladder currently has one rung standing on
			it. That is a fact about how early this is rather than a claim that
			every ability belongs at the top - the moment there is one a player
			finds rather than is given, this is the field that says so.
		]]
		rarity = "Legendary",

		server = "SacredRain",
		vfx = "SacredRainVFX",

		--[[
			NO ANIMATION, because the reference has none to copy.

			SacredSwords.rbxlx contains exactly one Animation instance -
			rbxassetid://11841488210, named "Punch", parented under the script -
			and nothing in the place ever loads or plays it. The caster stands
			still for the whole barrage. Rather than invent a cast animation or
			guess that the orphaned "Punch" was meant to be it, this is left
			empty: put an id here and every client will play it on the caster.
		]]
		animation = nil,

		--[[
			Six seconds, not the reference's one.

			The reference fires this every second, which for a four-and-a-half
			second effect means three of them overlapping at all times. At 75
			damage a strike that is also most of a fight. Six seconds makes it
			something you spend rather than something you hold down, and leaves
			the melee swing as what fills the gap.

			maxConcurrent stays at 2: it is the safety cap, not the balance dial,
			and a cast can still be in flight when the next comes off cooldown.
		]]
		cooldown = 6,

		-- Just under a third of the pool. It is the one you open with and the
		-- one you can afford twice; Eclipse is the one you have to save for.
		manaCost = 30,

		castRange = 250,
		requiresTarget = true,
		maxConcurrent = 2,

		tuning = SacredRainPlan.Tuning,
	},

	--[[
		Eclipse

		Not from any reference: designed here, for this weapon, to be the other
		thing the lance does.

		WHY IT EXISTS ALONGSIDE SACRED RAIN

		A second ability is only worth its key if pressing it is a different
		DECISION, not a different animation. Sacred Rain is aimed, slow to
		arrive, scattered over forty studs and best used on something that is
		not yet near you. Eclipse takes no target, resolves in under a second,
		cannot miss, and clears forty-four studs in every direction - so it is
		what you press when the thing you were shooting at has reached you.

		IT IS THE ENDGAME WEAPON'S ENDGAME BUTTON

		140 damage at the caster's feet, 77 at the rim, on everything at once.
		That is deliberately enormous, and it is the reward for a drop-only
		Legendary that takes hours to see: the wind-up is long enough for
		everyone nearby to know what is coming, and then it does exactly what it
		looked like it was going to do. The falloff (see EclipsePlan) is the
		counterplay - being caught at the edge is nearly half the punishment of
		standing on top of it.

		COOLDOWN

		Twelve seconds, twice Sacred Rain's. It is the reliable one - it never
		misses and it always catches everything nearby - so it is the one that
		has to be rationed. Six and twelve also means the two abilities come off
		cooldown together every other Sacred Rain, which gives the weapon a beat
		rather than two unrelated timers.

		NO ANIMATION, for the same reason Sacred Rain has none: there is no
		cast animation in this project to point at, and inventing an id would
		be inventing an asset. The VFX starts at the caster's chest, which reads
		as deliberate on its own.
	]]
	Eclipse = {
		displayName = "Eclipse",

		-- The endgame weapon's endgame button, on a drop-only Legendary. See
		-- SacredRain's note for why both abilities sit at the top today.
		rarity = "Legendary",

		server = "Eclipse",
		vfx = "EclipseVFX",

		animation = nil,

		cooldown = 12,

		--[[
			Over half the pool, which is the point.

			At two mana a second that is twenty-eight seconds of standing
			around, more than twice its own cooldown. Eclipse is the button you
			spend an engagement on, and opening with Sacred Rain is a decision
			to wait a good while longer for it.
		]]
		manaCost = 55,

		--[[
			No target, so no range to check. The blast is centred on the caster's
			own root, which the server reads for itself - the client cannot
			nominate where it goes off, which makes this the one ability here
			with nothing at all for the server to sanitise.
		]]
		requiresTarget = false,

		--[[
			One at a time, which is free: the cast is over in 2.7 seconds and
			the cooldown is twelve.

			Worth knowing that this number USED to be unsafe. AbilityService
			counted casts per player rather than per ability, so a Sacred Rain
			still in flight - and one of those stays counted for about twelve
			seconds, most of it the swords' pooled lifetime - filled this cap
			and made Eclipse do nothing at all, silently, for that whole window.
			That was a bug in the service and is fixed there.
		]]
		maxConcurrent = 1,

		tuning = EclipsePlan.Tuning,
	},
}

-- ---------------------------------------------------------------------------
-- Lookup
-- ---------------------------------------------------------------------------

function AbilityConfig.get(abilityName: string?)
	if type(abilityName) ~= "string" then
		return nil
	end
	return AbilityConfig.Definitions[abilityName]
end

--[[
	Every ability name, alphabetically.

	Built fresh rather than cached: it is asked for by the /add command and by
	the error message that lists what a player could have typed instead, neither
	of which is a hot path.
]]
function AbilityConfig.names(): { string }
	local names = {}

	for name in pairs(AbilityConfig.Definitions) do
		table.insert(names, name)
	end

	table.sort(names)
	return names
end

--[[
	The real name behind whatever a player typed, or nil.

	Case-insensitive, and it ignores spaces, so "sacred rain", "SacredRain" and
	"sacredrain" all find the same ability. That is the whole reason this is
	here: a chat command that only accepts the exact internal spelling is a
	command that mostly reports failure.
]]
function AbilityConfig.resolve(text: string?): string?
	if type(text) ~= "string" then
		return nil
	end

	local wanted = string.gsub(string.lower(text), "%s", "")
	if wanted == "" then
		return nil
	end

	for name in pairs(AbilityConfig.Definitions) do
		local displayName = AbilityConfig.Definitions[name].displayName or name
		if string.lower(name) == wanted or string.gsub(string.lower(displayName), "%s", "") == wanted then
			return name
		end
	end

	return nil
end

--[[
	The key that casts slot `index`, or nil for a slot that has none.

	Slots without a key are not an error - SlotCount could be raised past the
	keys someone has bound - but the readout says so rather than showing a blank
	where a key should be.
]]
function AbilityConfig.keyForSlot(index: number)
	return AbilityConfig.SlotKeys[index]
end

--[[
	Fails loudly at require time rather than leaving a slot nobody can press.
]]
function AbilityConfig.validate()
	assert(
		type(AbilityConfig.SlotCount) == "number" and AbilityConfig.SlotCount >= 1,
		"[AbilityConfig] SlotCount must be at least 1"
	)
	assert(
		#AbilityConfig.SlotKeys == AbilityConfig.SlotCount,
		string.format(
			"[AbilityConfig] SlotCount is %d but SlotKeys has %d entries; every slot needs a "
				.. "key or it can never be cast",
			AbilityConfig.SlotCount, #AbilityConfig.SlotKeys
		)
	)

	local seen = {}
	for index, key in ipairs(AbilityConfig.SlotKeys) do
		assert(
			typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode,
			string.format("[AbilityConfig] SlotKeys[%d] must be an Enum.KeyCode", index)
		)
		assert(
			not seen[key],
			string.format("[AbilityConfig] SlotKeys[%d] repeats %s", index, key.Name)
		)
		seen[key] = true
	end

	for name, definition in pairs(AbilityConfig.Definitions) do
		assert(
			type(definition.server) == "string" and definition.server ~= "",
			string.format("[AbilityConfig] '%s' needs a server module name", name)
		)
		assert(
			type(definition.cooldown) == "number" and definition.cooldown >= 0,
			string.format("[AbilityConfig] '%s' needs a non-negative cooldown", name)
		)
	end
end

return AbilityConfig
