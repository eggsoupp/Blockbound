--[[
	ItemDefinitions

	Every item in the game. One entry, one item.

	FIELDS THE SYSTEMS ACTUALLY READ
	  classification  "Block" is what makes an item placeable; "Pickaxe" is what
	                  makes a tool able to mine; "Workbench" is what makes an
	                  item a placeable crafting station (see Shared.Crafting).
	  maxStack        stack size. 1 means the item never merges.
	  miningTime      ON A BLOCK: how long that block takes to break, in
	                  MILLISECONDS, with a CopperPickaxe - the reference tool at
	                  speed 1.0. Read through Shared.Blocks.BlockConfig, which
	                  does the ms -> s conversion in one place.

	                  The scale, so a new block lands somewhere sensible:
	                      450-600    snow, sand, dirt, grass, planks
	                      1200-1500  sandstone, stone
	                      1700-2000  worked stone, the biome stones
	                      2500+      magma brick and anything meant to hurt
	                  Ores are not here - OreConfig carries their breakSeconds
	                  and registers it with BlockConfig, and every one of them
	                  is harder than the rock it is embedded in.

	  miningSpeed     ON A PICKAXE: DIVIDES the break time. 2.0 mines everything
	                  in half the time. The ladder:
	                      0.60  wood      2.70  gold
	                      1.00  copper    3.60  mythril
	                      1.40  stone     5.00  void
	                      2.00  iron      5.50  skybreaker
	                  and 40.0 for TestPickaxe, which is not on the ladder and
	                  is not meant to be - see its entry. Also how fast the
	                  mining swing plays (ToolConfig.miningAnimationRate).
	  miningPower     ON A PICKAXE: WHAT it can mine, where miningSpeed is how
	                  FAST. A block whose power (BlockConfig; ores set theirs
	                  in OreConfig) is above this refuses to break. The ladder:
	                      1  wood            4  gold
	                      2  copper, stone   5  mythril
	                      3  iron            6  void, skybreaker
	                  and 99 for TestPickaxe. Missing means 1.
	  weaponClass     ON A WEAPON: its main class, a key of Shared.Combat.
	                  WeaponClasses - Sword, HeavySword or Lance. Decides the
	                  walk it is carried with (ToolConfig.WalkAnimations) and
	                  heads its description in the UI.
	  weaponSubclass  ON A WEAPON: what kind within the class - Longsword,
	                  Katana, Broadsword, Spear. Shown after the class:
	                  "Sword -> Katana".
	  rarity          drives the colour of the name in the UI. The ladder, and
	                  which tier is the top one, live in Shared.UI.Theme.
	  animation       an rbxassetid:// played on the wielder when this item is
	                  used. Optional, and only for the odd item that should not
	                  swing like the rest of its kind - the normal place to put a
	                  swing is ToolConfig.Animations, which does every tool of a
	                  classification at once. See StarterPlayerScripts.ToolFeedback.
	HOW AN ITEM IS DRAWN IN THE INVENTORY

	  By default it is not drawn from any of these fields at all: an item with a
	  model in ReplicatedStorage.Tools or TerrainAssets.Blocks gets a LIVE
	  render of that model, turned to a readable angle and framed to fill the
	  slot. See Shared.UI.ItemPreview. Roblox's own uploaded-model thumbnails
	  are not used for this, because their camera angle is fixed by Roblox and
	  cannot be edited, and for these tools it produces something unidentifiable.

	  iconPose        "tool" or "block", overruling the shape rule that picks
	                  between them. A tool is laid along the frame's diagonal
	                  with its head up and to the right; a block is turned to
	                  the three-quarter cube view.
	  iconAngle       a Vector3 of degrees applied on top of that pose, about the
	                  item's OWN axes rather than the screen's - so it survives
	                  any later change to the pose it is correcting. The common
	                  one is Vector3.new(0, 90, 0), which turns a blade that came
	                  out edge-on to face the camera; Vector3.new(0, 0, 180) puts
	                  the item on its head.

	  THE FLAT-IMAGE FIELDS, for items with no model - materials, ingots, and
	  anything else that has only ever been a picture:

	  thumbnail       an explicit image content string. The deliberate override:
	                  an item with one gets it instead of a render.
	  modelId         an uploaded Model or Mesh asset id, drawn through Roblox's
	                  thumbnail service. Same angle caveat as above, so this is
	                  a fallback rather than the plan.
	  icon            a hand-drawn image. Most of the ids currently in this file
	                  are 3000000xxx placeholders from before there was any art;
	                  they do not resolve, and the resolver skips anything that
	                  fails to load rather than drawing an empty square.
	  description, value, buffs  presentation and future systems.
]]

local ItemDefinitions = {

	-- === Basic Materials & Components ===
	Stone = {
		icon = "rbxassetid://135294244542357",
		description = "A simple stone. Used for crafting basic tools.",
		rarity = "Common",
		maxStack = 999,
		classification = "Block",
		value = 1,
		miningTime = 1500,           -- 1.5s with a copper pickaxe
	},
	

	WoodPlank = {
		icon = "rbxassetid://82387679070340",
		description = "Processed wood, used in many recipes.",
		rarity = "Common",
		maxStack = 999,
		classification = "Block",
		value = 2,
		miningTime = 500,
	},


	Wood = {
		icon = "rbxassetid://82387679070340",
		description = "Wood, used in many recipes.",
		rarity = "Common",
		maxStack = 999,
		classification = "Material",
		value = 2,
	},
	Stick = {
		icon = "rbxassetid://3000000005",
		description = "A wooden stick. Essential crafting component.",
		rarity = "Common",
		maxStack = 999,
		classification = "Material",
		value = 1,
	},
	Leather = {
		icon = "rbxassetid://3000000006",
		description = "Treated hide. Used for basic armor.",
		rarity = "Uncommon",
		maxStack = 99,
		classification = "Material",
		value = 5,
	},
	Herb = {
		icon = "rbxassetid://3000000007",
		description = "A medicinal herb. Used in potions.",
		rarity = "Common",
		maxStack = 99,
		classification = "Material",
		value = 3,
	},
	Bottle = {
		icon = "rbxassetid://3000000008",
		description = "Empty glass bottle. Holds liquids.",
		rarity = "Common",
		maxStack = 99,
		classification = "Material",
		value = 2,
	},

	-- === Basic Tools, Pickaxes & Weapons ===
	-- NOTE: items that should allow mining must have classification == "Pickaxe".
	TestSword = {
		icon = "rbxassetid://79477131719769",
		description = "test",
		rarity = "Unobtainable",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "Sword",
		weaponSubclass = "Longsword",
		value = 999,
	},
	TestPickaxe = {
		icon = "rbxassetid://78053200894485",
		description = "test",
		rarity = "Unobtainable",
		maxStack = 1,
		classification = "Pickaxe",
		value = 999,
		-- DELIBERATELY ABSURD, and it has to be: block hardness is now real, so
		-- the old 4.0 would make this a slightly-better-than-void pickaxe rather
		-- than the development tool it is for. At 40 every ordinary block hits
		-- BlockConfig.MinBreakSeconds and the deepest ore is a fifth of a second.
		miningSpeed = 40.0,
		miningPower = 99,
	},
	TestAxe = {
		icon = "rbxassetid://15599043650",
		description = "test",
		rarity = "Unobtainable",
		maxStack = 1,
		classification = "Tool",
		value = 999,
	},

	CopperPickaxe = {
		icon = "rbxassetid://3000000000",
		description = "A basic pickaxe used for mining copper ore.",
		rarity = "Common",
		maxStack = 1,
		classification = "Pickaxe",
		value = 5,
		-- The reference tool: every block hardness in the game is written as
		-- "how long this should take with a copper pickaxe".
		miningSpeed = 1.00,
		miningPower = 2,
	},
	CopperSword = {
		icon = "rbxassetid://3000000001",
		description = "A simple copper sword. Better than fists.",
		rarity = "Common",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "Sword",
		weaponSubclass = "Longsword",
		value = 8,
	},
	-- The wood tier. Weakest of everything, and the first tools a player can
	-- make from what the world hands them without smelting anything.
	WoodAxe = {
		icon = "rbxassetid://3000000002",
		description = "A crude axe for chopping down trees.",
		rarity = "Common",
		maxStack = 1,
		classification = "Tool",
		value = 3,
		iconAngle = Vector3.new(25, 270, 35),
	},
	WoodPickaxe = {
		-- PLACEHOLDER ICON, in the same made-up series as its neighbours.
		icon = "rbxassetid://3000000013",
		description = "A crude pickaxe. It will break stone, slowly.",
		rarity = "Common",
		maxStack = 1,
		-- "Pickaxe" is not decoration: MiningServer refuses to mine with
		-- anything else, and ToolConfig picks the fallback shape from it.
		classification = "Pickaxe",
		value = 2,
		-- Below CopperPickaxe, so the copper tier is still an upgrade.
		miningSpeed = 0.60,
		miningPower = 1,
		iconAngle = Vector3.new(170, 0, 0),
	},
	WoodSword = {
		-- PLACEHOLDER ICON.
		icon = "rbxassetid://3000000014",
		description = "A blunt wooden sword. Barely better than fists.",
		rarity = "Common",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "Sword",
		weaponSubclass = "Longsword",
		value = 3,
		iconAngle = Vector3.new(0, 0, 0),
	},
	StonePickaxe = {
		icon = "rbxassetid://3000000009",
		description = "A sturdy pickaxe made of stone. More durable than copper.",
		rarity = "Common",
		maxStack = 1,
		classification = "Pickaxe",
		value = 10,
		miningSpeed = 1.40,
		miningPower = 2,
	},
	StoneSword = {
		icon = "rbxassetid://3000000010",
		description = "A basic sword carved from stone.",
		rarity = "Common",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "Sword",
		weaponSubclass = "Longsword",
		value = 12,
	},

	-- === Consumables ===
 ScrollChest = {
  displayName = "Scroll Chest", icon = "", rarity = "Rare", maxStack = 10,
  classification = "Consumable", value = 60,
  description = "Select in your hotbar and click to open. Drops one random unowned ability scroll, visible only to you.",
 },
	HealthPotion = {
		icon = "rbxassetid://3000000011",
		description = "Restores a moderate amount of health.",
		rarity = "Common",
		maxStack = 20,
		classification = "Consumable",
		value = 15,
	},
	ManaPotion = {
		icon = "rbxassetid://3000000012",
		description = "Restores a moderate amount of mana.",
		rarity = "Common",
		maxStack = 20,
		classification = "Consumable",
		value = 15,
	},

	--[[
		=== There are no scrolls here any more ===

		ScrollOfSacredRain and ScrollOfEclipse used to sit in this file, with a
		`grantsAbility` field, a "Scroll" classification and a placeholder tube
		in ToolConfig so they could be held. All of it is gone.

		A scroll is an object in the WORLD now - you walk up to it and hold the
		prompt. See ServerScriptService.ScrollService, which is the whole
		feature: no item, no stack, no tool template, no equip.

		Left as a note rather than deleted silently because the shape of the old
		one is the argument for the new one. Almost everything those two entries
		carried was inventory plumbing that had nothing to do with abilities,
		and an item whose only purpose is to be consumed the moment you use it
		is an object that wanted to be in the world.
	]]

	-- === Ores ===
	-- One entry per Terrain.OreConfig ore. The ore's DEPTH and RARITY live in
	-- OreConfig; this is only what the item looks like in the bag. Adding an ore
	-- means one row here and one row there.
	--
	-- Icons on the ores and ingots below are placeholders, in the same style the
	-- rest of this file already uses. Swap them for real asset ids when the art
	-- exists; nothing else has to change.
	Coal = {
		icon = "rbxassetid://3000000410",
		description = "Sooty black rock. Fuel for every furnace.",
		rarity = "Common",
		maxStack = 999,
		classification = "Material",
		value = 2,
	},
	CopperOre = {
		icon = "rbxassetid://3000000411",
		description = "Raw copper. Smelt it into an ingot.",
		rarity = "Common",
		maxStack = 999,
		classification = "Material",
		value = 3,
	},
	IronOre = {
		icon = "rbxassetid://3000000412",
		description = "Raw iron. Smelt it into an ingot.",
		rarity = "Uncommon",
		maxStack = 999,
		classification = "Material",
		value = 6,
	},
	GoldOre = {
		icon = "rbxassetid://3000000413",
		description = "Raw gold, found only well below the surface.",
		rarity = "Rare",
		maxStack = 999,
		classification = "Material",
		value = 18,
	},
	MythrilOre = {
		icon = "rbxassetid://3000000414",
		description = "Faintly humming ore from the deep rock.",
		rarity = "Rare",
		maxStack = 999,
		classification = "Material",
		value = 40,
	},
	VoidCrystal = {
		icon = "rbxassetid://3000000415",
		description = "A shard of nothing, pulled from the bottom of the world.",
		rarity = "Legendary",
		maxStack = 99,
		classification = "Material",
		value = 150,
	},

	-- === Mid-Game Materials & Ores ===
	CopperIngot = {
		icon = "rbxassetid://3000000406",
		description = "A refined bar of copper. The first real tool metal.",
		rarity = "Common",
		maxStack = 999,
		classification = "Material",
		value = 5,
	},
	IronIngot = {
		icon = "rbxassetid://3000000400",
		description = "A refined bar of iron. Used for stronger tools.",
		rarity = "Uncommon",
		maxStack = 999,
		classification = "Material",
		value = 10,
	},
	GoldIngot = {
		icon = "rbxassetid://3000000407",
		description = "A refined bar of gold. Soft, valuable, and a little vain.",
		rarity = "Rare",
		maxStack = 999,
		classification = "Material",
		value = 35,
	},
	MagmaOre = {
		icon = "rbxassetid://117405535919969",
		description = "Burning-hot ore. Requires a strong pickaxe to mine.",
		rarity = "Epic",
		maxStack = 999,
		classification = "Material",
		value = 2,
		miningTime = 2000,            -- 2000 ms (2.0s) because it's tougher
	},
	Cobblestone = {
		icon = "rbxassetid://3000000403",
		description = "Rough stone. Useful for crafting and building.",
		rarity = "Common",
		maxStack = 999,
		classification = "Material",
		value = 2,
		miningTime = 1300,
	},

	-- === Mid-Game Tools & Weapons ===
	IronPickaxe = {
		icon = "rbxassetid://3000000401",
		description = "Stronger than copper, used to mine tougher ores.",
		rarity = "Uncommon",
		maxStack = 1,
		classification = "Pickaxe",
		value = 15,
		miningSpeed = 2.00,
		miningPower = 3,
	},
	IronSword = {
		icon = "rbxassetid://3000000402",
		description = "A sharp iron sword. Deals good melee damage.",
		rarity = "Uncommon",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "Sword",
		weaponSubclass = "Longsword",
		value = 30,
	},
	LeatherArmor = {
		icon = "rbxassetid://3000000404",
		description = "Basic armor made from leather. Provides light protection.",
		rarity = "Uncommon",
		maxStack = 1,
		classification = "Armor",
		value = 40,
		buffs = { defense = 5 },
	},
	IronArmor = {
		icon = "rbxassetid://3000000405",
		description = "Heavy iron armor. Greatly increases defense.",
		rarity = "Rare",
		maxStack = 1,
		classification = "Armor",
		value = 120,
		buffs = { defense = 15 },
	},

	-- === Accessories ===
	-- Worn in the accessory column at the bottom right of the screen. Only
	-- count while worn there, and every worn copy counts, so the same accessory
	-- twice gives its bonus twice - see GearService, which reads `buffs`:
	--   maxHealth / maxMana             flat amounts
	--   abilityDamage / weaponDamage    fractions: 0.15 is +15%
	-- No art exists yet, so `look` has Shared.UI.ItemModels build a simple
	-- model in code for the slot and the tooltip to show.
	VitalityAmulet = {
		displayName = "Vitality Amulet",
		description = "+25 max health while worn.",
		rarity = "Uncommon",
		maxStack = 1,
		classification = "Accessory",
		value = 60,
		buffs = { maxHealth = 25 },
		look = { shape = "Amulet", metal = Color3.fromRGB(214, 176, 82), gem = Color3.fromRGB(222, 54, 66) },
		iconPose = "block",
	},
	ManaAmulet = {
		displayName = "Mana Amulet",
		description = "+25 max mana while worn.",
		rarity = "Uncommon",
		maxStack = 1,
		classification = "Accessory",
		value = 60,
		buffs = { maxMana = 25 },
		look = { shape = "Amulet", metal = Color3.fromRGB(196, 200, 214), gem = Color3.fromRGB(66, 128, 255) },
		iconPose = "block",
	},
	SpellRing = {
		displayName = "Spell Ring",
		description = "+15% ability damage while worn.",
		rarity = "Rare",
		maxStack = 1,
		classification = "Accessory",
		value = 90,
		buffs = { abilityDamage = 0.15 },
		look = { shape = "Ring", metal = Color3.fromRGB(196, 200, 214), gem = Color3.fromRGB(176, 86, 255) },
		iconPose = "block",
	},
	BattleRing = {
		displayName = "Battle Ring",
		description = "+15% weapon damage while worn.",
		rarity = "Rare",
		maxStack = 1,
		classification = "Accessory",
		value = 90,
		buffs = { weaponDamage = 0.15 },
		look = { shape = "Ring", metal = Color3.fromRGB(214, 176, 82), gem = Color3.fromRGB(255, 136, 40) },
		iconPose = "block",
	},

	-- === Workbenches ===
	CraftingTable = {
		icon = "rbxassetid://3000000500",
		description = "Used to craft basic tools and items.",
		rarity = "Common",
		maxStack = 1,
		classification = "Workbench",
		value = 15,
	},
	Furnace = {
		icon = "rbxassetid://3000000501",
		description = "Smelts ores into ingots.",
		rarity = "Common",
		maxStack = 1,
		classification = "Workbench",
		value = 25,
	},
	Anvil = {
		icon = "rbxassetid://3000000502",
		description = "Used to forge weapons and armor.",
		rarity = "Uncommon",
		maxStack = 1,
		classification = "Workbench",
		value = 50,
	},
	ArcaneForge = {
		icon = "rbxassetid://3000000503",
		description = "Fuses magic into equipment. Required for enchanted gear.",
		rarity = "Rare",
		maxStack = 1,
		classification = "Workbench",
		value = 100,
	},
	AlchemyBench = {
		icon = "rbxassetid://3000000607",
		description = "Used to craft potions and magical consumables.",
		rarity = "Uncommon",
		maxStack = 1,
		classification = "Workbench",
		value = 80,
	},
	EnchantingTable = {
		icon = "rbxassetid://3000000608",
		description = "Used to enchant weapons, tools, and armor.",
		rarity = "Rare",
		maxStack = 1,
		classification = "Workbench",
		value = 150,
	},

	-- === Late-Game Tools & Weapons ===
	-- Gold sits between iron and mythril: fast, but you have to get to depth 72
	-- for the ore. Every one of these is a working tool - Tools.ToolConfig builds
	-- a template for anything holdable, so they equip and mine like the rest.
	GoldPickaxe = {
		icon = "rbxassetid://3000000420",
		description = "Soft metal, sharp edge. Cuts stone quickly but not gently.",
		rarity = "Rare",
		maxStack = 1,
		classification = "Pickaxe",
		value = 55,
		miningSpeed = 2.70,
		miningPower = 4,
	},
	GoldSword = {
		icon = "rbxassetid://3000000421",
		description = "More ceremony than weapon, but it swings fast.",
		rarity = "Rare",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "Sword",
		weaponSubclass = "Longsword",
		value = 60,
	},
	MythrilPickaxe = {
		icon = "rbxassetid://3000000422",
		description = "Hums as it cuts. Shrugs off the deep rock.",
		rarity = "Rare",
		maxStack = 1,
		classification = "Pickaxe",
		value = 140,
		miningSpeed = 3.60,
		miningPower = 5,
	},
	VoidPickaxe = {
		icon = "rbxassetid://3000000423",
		description = "Built around a fragment of nothing. Stone barely registers.",
		rarity = "Legendary",
		maxStack = 1,
		classification = "Pickaxe",
		value = 400,
		miningSpeed = 5.00,
		miningPower = 6,
	},

	-- === Building Blocks ===
	-- Placeable and mineable like any terrain block. TerrainManager builds their
	-- parts from Blocks.BlockConfig.Generated, so they need no authored asset.
	StoneBricks = {
		icon = "rbxassetid://3000000430",
		description = "Cut and squared. For building something that lasts.",
		rarity = "Common",
		maxStack = 999,
		classification = "Block",
		value = 3,
		miningTime = 1700,
	},
	MagmaBrick = {
		icon = "rbxassetid://3000000431",
		description = "Fired with magma ore. Glows faintly, warm to the touch.",
		rarity = "Uncommon",
		maxStack = 999,
		classification = "Block",
		value = 8,
		miningTime = 2500,
	},

	-- === High-End Materials ===
	MythrilIngot = {
		icon = "rbxassetid://3000000600",
		description = "A rare, glowing metal that hums with energy.",
		rarity = "Rare",
		maxStack = 999,
		classification = "Material",
		value = 50,
	},
	EssenceShard = {
		icon = "rbxassetid://3000000610",
		description = "Crystallized magic used in high-end crafting.",
		rarity = "Rare",
		maxStack = 99,
		classification = "Material",
		value = 75,
	},
	VoidCore = {
		icon = "rbxassetid://3000000601",
		description = "A fragment of the void. Used to craft ultimate gear.",
		rarity = "Legendary",
		maxStack = 20,
		classification = "Material",
		value = 200,
	},

	-- === High-End Gear (Craftable) ===
	MythrilSword = {
		icon = "rbxassetid://3000000602",
		description = "An elegant blade of Mythril. Fast and deadly.",
		rarity = "Rare",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "Sword",
		weaponSubclass = "Longsword",
		value = 120,
		buffs = { attackSpeed = 0.2 },
	},


	LightLance = {
		description = "A lance of hardened light. Calls a rain of blades down on a marked place, "
			.. "or collapses a black star at its bearer's feet.",
		rarity = "Legendary",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "Lance",
		weaponSubclass = "Spear",
		dropOnly = true,
		iconAngle = Vector3.new(0, 0, -100),
	},
	Thunderveil = {
		description = "A sword of crackling thunder. Deals high damage and has a chance to stun enemies.",
		rarity = "Legendary",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "HeavySword",
		weaponSubclass = "Broadsword",
		dropOnly = true,
		iconAngle = Vector3.new(0, 0, 0),
	},
	Bloodfang = { 
		description = "A sword that bleeds. Deals high damage and life steal.",
		rarity = "Epic",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "Sword",
		weaponSubclass = "Katana",
		dropOnly = true,
		iconAngle = Vector3.new(0, 0, 0),
	},

	-- === High-End Gear (Drop-Only) ===
	VoidReaver = {
		icon = "rbxassetid://3000000603",
		description = "A cursed blade that deals high damage and life steal.",
		rarity = "Legendary",
		maxStack = 1,
		classification = "Weapon",
		weaponClass = "Sword",
		weaponSubclass = "Longsword",
		value = 300,
		buffs = { lifesteal = 0.1, damage = 50 },
		dropOnly = true,
	},
	SkybreakerPick = {
		icon = "rbxassetid://3000000604",
		description = "A celestial pickaxe that breaks multiple blocks at once.",
		rarity = "Legendary",
		maxStack = 1,
		classification = "Pickaxe",
		value = 250,
		buffs = { breakRadius = 1 },
		miningSpeed = 5.50,
		miningPower = 6,
		dropOnly = true,
	},
	BuilderWand = {
		icon = "rbxassetid://3000000605",
		description = "Places multiple blocks at once when building.",
		rarity = "Epic",
		maxStack = 1,
		classification = "Tool",
		value = 150,
		dropOnly = true,
	},
	FlameHammer = {
		icon = "rbxassetid://3000000606",
		description = "Smelts ores instantly on impact. Can be used as a weapon.",
		rarity = "Rare",
		maxStack = 1,
		classification = "Tool",
		value = 180,
		buffs = { fireDamage = 10 },
		dropOnly = true,
	},

	-- === Basic terrain block items (if you want them placeable / droppable as items) ===
	Dirt = {
		icon = "rbxassetid://3000000700",
		description = "Loose earth.",
		rarity = "Common",
		maxStack = 999,
		classification = "Block",
		value = 0,
		miningTime = 550,
	},
	Grass = {
		icon = "rbxassetid://3000000701",
		description = "Surface grass block.",
		rarity = "Common",
		maxStack = 999,
		classification = "Block",
		value = 0,
		miningTime = 600,
	},
	Sand = {
		icon = "rbxassetid://3000000702",
		description = "Loose sand. Flows into gaps.",
		rarity = "Common",
		maxStack = 999,
		classification = "Block",
		value = 0,
		miningTime = 500,
	},
	Sandstone = {
		icon = "rbxassetid://3000000703",
		description = "Compact sand turned to stone.",
		rarity = "Common",
		maxStack = 999,
		classification = "Block",
		value = 1,
		miningTime = 1200,
	},
	Snow = {
		icon = "rbxassetid://3000000704",
		description = "Packed snow block.",
		rarity = "Common",
		maxStack = 999,
		classification = "Block",
		value = 0,
		miningTime = 450,
	},

	-- === New biome/placeable blocks ===
	CorruptedStone = {
		icon = "rbxassetid://3000000800",
		description = "Dark, twisted stone infused with corruption.",
		rarity = "Uncommon",
		maxStack = 999,
		classification = "Block",
		value = 2,
		miningTime = 1800,
	},
	CorruptedDirt = {
		icon = "rbxassetid://3000000801",
		description = "Soil tainted by corruption.",
		rarity = "Uncommon",
		maxStack = 999,
		classification = "Block",
		value = 1,
		miningTime = 700,
	},
	CrimsonStone = {
		icon = "rbxassetid://3000000802",
		description = "A blood-red stone from the crimson lands.",
		rarity = "Uncommon",
		maxStack = 999,
		classification = "Block",
		value = 2,
		miningTime = 1800,
	},
	CrimsonDirt = {
		icon = "rbxassetid://3000000803",
		description = "Soil from the crimson biome.",
		rarity = "Uncommon",
		maxStack = 999,
		classification = "Block",
		value = 1,
		miningTime = 700,
	},
	HallowedStone = {
		icon = "rbxassetid://3000000804",
		description = "Holy stone radiating light.",
		rarity = "Rare",
		maxStack = 999,
		classification = "Block",
		value = 3,
		miningTime = 2000,
	},
	HallowedDirt = {
		icon = "rbxassetid://3000000805",
		description = "Blessed soil glowing faintly.",
		rarity = "Rare",
		maxStack = 999,
		classification = "Block",
		value = 2,
		miningTime = 750,
	},
}

return ItemDefinitions
