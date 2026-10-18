--[[
	CraftingRecipes

	Every recipe in the game. Shared.Crafting.RecipeBook validates and indexes
	this; the server and the GUI both read it from there.

		<OutputItemName> = {
			ingredients = { <ItemName> = <count>, ... },
			station     = "CraftingTable",          -- omit for hand crafting
			output      = { item = "X", count = 4 } -- omit for 1x the key
		}

	The key is the recipe id and, by default, the item it produces. `station`
	must name a StationConfig entry; leaving it out makes the recipe craftable
	anywhere. Adding a recipe is one row - no server or GUI change - and a row
	naming something that does not exist is dropped with a warning at startup.
]]

local CraftingRecipes = {
	-- =======================================================================
	-- Hand crafting. Available anywhere, and the route to your first station.
	-- =======================================================================
	WoodPlank = {
		ingredients = { Wood = 1 },
		output = { item = "WoodPlank", count = 4 },
	},
	Stick = {
		ingredients = { WoodPlank = 2 },
		output = { item = "Stick", count = 4 },
	},
	CraftingTable = {
		ingredients = { WoodPlank = 4 },
	},

	-- =======================================================================
	-- Crafting table. Basic tools, and the rest of the stations.
	-- =======================================================================
	Cobblestone   = { ingredients = { Stone = 1 }, station = "CraftingTable" },
	StoneBricks   = {
		ingredients = { Cobblestone = 4 },
		output = { item = "StoneBricks", count = 4 },
		station = "CraftingTable",
	},
	Furnace       = { ingredients = { Cobblestone = 8 }, station = "CraftingTable" },
	Chest         = { ingredients = { WoodPlank = 8 }, station = "CraftingTable" },
	Anvil         = { ingredients = { IronIngot = 5, Stone = 3 }, station = "CraftingTable" },
	AlchemyBench  = { ingredients = { WoodPlank = 4, Bottle = 2 }, station = "CraftingTable" },

	-- Basic Tools
	CopperPickaxe = { ingredients = { CopperIngot = 3, Stick = 2 }, station = "CraftingTable" },
	CopperSword   = { ingredients = { CopperIngot = 2, Stick = 1 }, station = "CraftingTable" },
	WoodAxe       = { ingredients = { WoodPlank = 3, Stick = 2 }, station = "CraftingTable" },
	WoodPickaxe   = { ingredients = { WoodPlank = 3, Stick = 2 }, station = "CraftingTable" },
	WoodSword     = { ingredients = { WoodPlank = 2, Stick = 1 }, station = "CraftingTable" },
	StonePickaxe  = { ingredients = { Cobblestone = 3, Stick = 2 }, station = "CraftingTable" },
	StoneSword    = { ingredients = { Cobblestone = 2, Stick = 1 }, station = "CraftingTable" },

	-- Armor
	LeatherArmor  = { ingredients = { Leather = 6 }, station = "CraftingTable" },

	-- =======================================================================
	-- Furnace. Ore in, metal out - this is what the depth progression feeds.
	-- =======================================================================
	CopperIngot  = { ingredients = { CopperOre = 2, Coal = 1 }, station = "Furnace" },
	IronIngot    = { ingredients = { IronOre = 2, Coal = 1 }, station = "Furnace" },
	GoldIngot    = { ingredients = { GoldOre = 2, Coal = 1 }, station = "Furnace" },
	MythrilIngot = { ingredients = { MythrilOre = 2, Coal = 2 }, station = "Furnace" },
	Bottle       = { ingredients = { Sand = 3 }, station = "Furnace" },
	Sandstone    = {
		ingredients = { Sand = 4 },
		output = { item = "Sandstone", count = 4 },
		station = "Furnace",
	},

	-- The only thing magma ore is for. Fired, not smelted.
	MagmaBrick   = {
		ingredients = { MagmaOre = 1, Stone = 2 },
		output = { item = "MagmaBrick", count = 2 },
		station = "Furnace",
	},

	-- =======================================================================
	-- Anvil. Iron-tier gear, and the gateway to the arcane bench.
	-- =======================================================================
	IronPickaxe = { ingredients = { IronIngot = 3, Stick = 2 }, station = "Anvil" },
	IronSword   = { ingredients = { IronIngot = 2, Stick = 1 }, station = "Anvil" },
	IronArmor   = { ingredients = { IronIngot = 8 }, station = "Anvil" },
	GoldPickaxe = { ingredients = { GoldIngot = 3, Stick = 2 }, station = "Anvil" },
	GoldSword   = { ingredients = { GoldIngot = 2, Stick = 1 }, station = "Anvil" },
	ArcaneForge = { ingredients = { Stone = 8, GoldIngot = 2 }, station = "Anvil" },

	-- Accessories, worn in the accessory column. See ItemDefinitions.
	VitalityAmulet = { ingredients = { GoldIngot = 2, Herb = 4 }, station = "Anvil" },
	ManaAmulet     = { ingredients = { GoldIngot = 2, Bottle = 2 }, station = "Anvil" },
	SpellRing      = { ingredients = { GoldIngot = 3, IronIngot = 1 }, station = "Anvil" },
	BattleRing     = { ingredients = { IronIngot = 4, GoldIngot = 1 }, station = "Anvil" },

	-- =======================================================================
	-- Alchemy bench. Consumables, and the essence the deep recipes need.
	-- =======================================================================
	HealthPotion = { ingredients = { Herb = 3, Bottle = 1 }, station = "AlchemyBench" },
	ManaPotion   = { ingredients = { EssenceShard = 1, Bottle = 1 }, station = "AlchemyBench" },
	EssenceShard = { ingredients = { MythrilOre = 1, Bottle = 1 }, station = "AlchemyBench" },

	-- =======================================================================
	-- Arcane forge. Endgame, and only reachable from the bottom of the world.
	-- =======================================================================
	MythrilSword    = { ingredients = { MythrilIngot = 5, Stick = 1 }, station = "ArcaneForge" },
	MythrilPickaxe  = { ingredients = { MythrilIngot = 4, Stick = 2 }, station = "ArcaneForge" },
	VoidCore        = { ingredients = { VoidCrystal = 4, EssenceShard = 2 }, station = "ArcaneForge" },
	EnchantingTable = {
		ingredients = { Stone = 6, MythrilIngot = 2, EssenceShard = 3 },
		station = "ArcaneForge",
	},

	-- =======================================================================
	-- Enchanting table. One recipe, and it is the end of the line: the only
	-- thing a VoidCore is for, and the only pickaxe worth the walk to the
	-- bottom of the world.
	-- =======================================================================
	VoidPickaxe = {
		ingredients = { VoidCore = 1, MythrilIngot = 4, Stick = 2 },
		station = "EnchantingTable",
	},
}

return CraftingRecipes
