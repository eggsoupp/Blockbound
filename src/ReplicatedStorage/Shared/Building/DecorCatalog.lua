--[[
	DecorCatalog

	The furniture and props a player can put down: doors, lights, seats,
	tables, shelves, yard pieces. One row per piece. StationConfig,
	ItemDefinitions and CraftingRecipes each fold this list in.

	Every piece is a MagicaVoxel model in assets/voxel-decor (source/designs,
	built by source/build.pl), turned into ReplicatedStorage.TerrainAssets.
	Decor.<id> in Studio by assets/voxel-decor/roblox/BuildDecor.lua. What the
	model needs from code - hinge, seat, flames, lights, ladder rungs, the
	height of its top - is in the generated Shared.Building.DecorShapes.

	They are stations in everything but name: StationService puts them on the
	block grid, saves them with an island and hands them back when struck.

	  kind     "plain"  nothing to do with it, no prompt
	           "door"   opens and shuts (DecorServer swings its Leaf)
	           "light"  lit when placed; the prompt douses and relights it
	           "seat"   the prompt sits you down
	  footprint  every piece fills whole 4-stud grid cells (DecorShapes `cells`):
	             a door is 1x2x1, a sofa 2x1x1, a tent 2x1x2. The placed cell is
	             its front-left; it reaches right, up and back from there.
	  recipe   { ingredients, station, count }; no station = hand crafted

	Every piece faces whoever put it down (its +Z front toward them), a quarter
	turn at a time, and keeps that facing in the save.

	`sprite` reuses an icon already in the item atlas; anything without one is
	drawn in the bag from its own model.
]]

local DecorCatalog = {}

local function row(id, name, rarity, kind, description, recipe, extra)
	local entry = { id = id, name = name, rarity = rarity, kind = kind, description = description, recipe = recipe }
	for key, value in pairs(extra or {}) do
		entry[key] = value
	end
	return entry
end

local CT, ANVIL, FORGE = "CraftingTable", "Anvil", "ArcaneForge"

DecorCatalog.Entries = {
	-- Doors, gates, windows ---------------------------------------------------
	row("WoodenDoor", "Wooden Door", "Common", "door", "A plank door, two blocks tall. Opens and shuts.",
		{ ingredients = { WoodPlank = 6 }, station = CT }),
	row("IronDoor", "Iron Door", "Uncommon", "door", "A riveted iron door with a barred window.",
		{ ingredients = { IronIngot = 6 }, station = ANVIL }),
	row("FenceGate", "Fence Gate", "Common", "door", "A swinging gate for a fence line.",
		{ ingredients = { Stick = 4, WoodPlank = 2 }, station = CT }),
	row("Window", "Window", "Common", "plain", "A four-pane window in a dark oak frame.",
		{ ingredients = { WoodPlank = 2, Bottle = 2 }, station = CT }),

	-- Lights ------------------------------------------------------------------
	row("Campfire", "Campfire", "Common", "light", "Crossed logs in a ring of stones. Warm light for a camp.",
		{ ingredients = { Wood = 3, Stick = 2, Coal = 1 } }),
	row("StandingTorch", "Standing Torch", "Common", "light", "A torch on a post. Lights a path.",
		{ ingredients = { Stick = 2, Coal = 1 }, count = 2 }),
	row("Lantern", "Lantern", "Uncommon", "light", "A small lamp in a sturdy metal frame. Sits on a floor or a table.",
		{ ingredients = { IronIngot = 2, Coal = 1, Bottle = 1 }, station = CT }, { sprite = "lantern" }),
	row("LampPost", "Lamp Post", "Uncommon", "light", "An iron post with a lantern on top, two blocks tall.",
		{ ingredients = { IronIngot = 4, Lantern = 1 }, station = ANVIL }),
	row("Brazier", "Brazier", "Uncommon", "light", "An iron bowl of burning coals on three legs.",
		{ ingredients = { IronIngot = 3, Coal = 2 }, station = ANVIL }),
	row("Candle", "Candles", "Common", "light", "Three wax candles on a dish. A soft light for a table.",
		{ ingredients = { Gel = 2, Stick = 1 }, station = CT }, { sprite = "candle" }),
	row("StoneFireplace", "Stone Fireplace", "Uncommon", "light", "A stone-brick hearth with a wooden mantel and a fire inside.",
		{ ingredients = { StoneBricks = 8, Wood = 2, Coal = 1 }, station = CT }),
	row("JackOLantern", "Jack-o'-Lantern", "Common", "light", "A carved pumpkin with a candle inside.",
		{ ingredients = { Herb = 3, Coal = 1 }, station = CT }),
	row("StoneLantern", "Stone Lantern", "Uncommon", "light", "A tiered stone lantern for a garden path.",
		{ ingredients = { Cobblestone = 6, Coal = 1 }, station = CT }),
	row("CrystalLamp", "Crystal Lamp", "Rare", "light", "Glowing crystals on a gilded stone base.",
		{ ingredients = { EssenceShard = 2, GoldIngot = 1, StoneBricks = 2 }, station = FORGE }),
	row("MushroomLamp", "Mushroom Lamp", "Uncommon", "light", "A cluster of glowing mushrooms.",
		{ ingredients = { Herb = 2, Gel = 3 }, station = CT }),

	-- Seats -------------------------------------------------------------------
	row("WoodenChair", "Wooden Chair", "Common", "seat", "A plain chair with a slatted back.",
		{ ingredients = { WoodPlank = 4, Stick = 2 }, station = CT }),
	row("Stool", "Stool", "Common", "seat", "A round stool. Nothing to lean on.",
		{ ingredients = { WoodPlank = 2, Stick = 2 }, station = CT }),
	row("WoodenBench", "Wooden Bench", "Common", "seat", "A long bench. Place a row of them for a hall.",
		{ ingredients = { WoodPlank = 5, Stick = 2 }, station = CT }),
	row("Throne", "Throne", "Epic", "seat", "Gilded, high-backed and cushioned in red. For whoever owns the island.",
		{ ingredients = { GoldIngot = 6, WoodPlank = 4, Wool = 4 }, station = ANVIL }),
	row("Bed", "Bed", "Common", "seat", "A wooden bed with a wool blanket.",
		{ ingredients = { WoodPlank = 3, Wool = 3 }, station = CT }, { actionText = "Rest" }),
	row("Armchair", "Armchair", "Uncommon", "seat", "A deep green armchair with a wool cushion.",
		{ ingredients = { WoodPlank = 4, Wool = 3 }, station = CT }),
	row("Sofa", "Sofa", "Uncommon", "seat", "A long red sofa, two blocks wide.",
		{ ingredients = { WoodPlank = 4, Wool = 6 }, station = CT }),
	row("StoneBench", "Stone Bench", "Common", "seat", "A slab of stone on two stone-brick legs.",
		{ ingredients = { Cobblestone = 5 }, station = CT }),
	row("RockingChair", "Rocking Chair", "Common", "seat", "A slatted chair on curved runners.",
		{ ingredients = { WoodPlank = 5, Stick = 3 }, station = CT }),

	-- Fences and ladders --------------------------------------------------------
	row("Ladder", "Ladder", "Common", "plain", "Climbable. Stack them to go up a wall.",
		{ ingredients = { Stick = 7 }, station = CT, count = 3 }),
	row("WoodFence", "Wood Fence", "Common", "plain", "A post and rails. Runs join up into a fence line.",
		{ ingredients = { Stick = 4, WoodPlank = 2 }, station = CT, count = 3 }),
	row("IronFence", "Iron Fence", "Uncommon", "plain", "Wrought-iron railings with gold finials.",
		{ ingredients = { IronIngot = 2 }, station = ANVIL, count = 3 }),

	-- Furniture -------------------------------------------------------------------
	row("WoodenTable", "Wooden Table", "Common", "plain", "A sturdy table. Lanterns and candles sit on top of it.",
		{ ingredients = { WoodPlank = 6, Stick = 4 }, station = CT }),
	row("Bookshelf", "Bookshelf", "Uncommon", "plain", "Three shelves of cloth- and leather-bound books.",
		{ ingredients = { WoodPlank = 6, Leather = 3 }, station = CT }),
	row("Barrel", "Barrel", "Common", "plain", "An iron-hooped barrel.",
		{ ingredients = { WoodPlank = 6, IronIngot = 1 }, station = CT }),
	row("SupplyCrate", "Supply Crate", "Common", "plain", "A braced wooden crate. Stack them in a storeroom.",
		{ ingredients = { WoodPlank = 6 }, station = CT }, { sprite = "crate_wood" }),
	row("IronCrate", "Iron Crate", "Uncommon", "plain", "A sealed iron crate with a gold lock plate.",
		{ ingredients = { SupplyCrate = 1, IronIngot = 2 }, station = ANVIL }, { sprite = "crate_iron" }),
	row("Wardrobe", "Wardrobe", "Uncommon", "plain", "A tall two-door wardrobe, two blocks high.",
		{ ingredients = { WoodPlank = 10, IronIngot = 1 }, station = CT }),
	row("Dresser", "Dresser", "Common", "plain", "Three drawers with gold pulls.",
		{ ingredients = { WoodPlank = 8 }, station = CT }),
	row("Nightstand", "Nightstand", "Common", "plain", "A small bedside table with a drawer.",
		{ ingredients = { WoodPlank = 4, Stick = 1 }, station = CT }),
	row("Desk", "Desk", "Common", "plain", "A writing desk with drawers, an open book and a quill.",
		{ ingredients = { WoodPlank = 6, Leather = 1, Feather = 1 }, station = CT }),
	row("GrandfatherClock", "Grandfather Clock", "Rare", "plain", "A tall clock with a gold pendulum, two blocks high.",
		{ ingredients = { WoodPlank = 8, GoldIngot = 2, IronIngot = 1 }, station = ANVIL }),
	row("PotionShelf", "Potion Shelf", "Uncommon", "plain", "Two shelves of glowing potion bottles.",
		{ ingredients = { WoodPlank = 4, Bottle = 4 }, station = CT }),
	row("Globe", "Globe", "Uncommon", "plain", "A world globe on a gilded stand.",
		{ ingredients = { WoodPlank = 2, GoldIngot = 1, BlueCloth = 1 }, station = ANVIL }),

	-- Yard, farm and garden -----------------------------------------------------
	row("FlowerPot", "Flower Pot", "Common", "plain", "A clay pot of red flowers.",
		{ ingredients = { Cobblestone = 2, Herb = 1 }, station = CT }),
	row("Rug", "Rug", "Common", "plain", "A red rug with a gold pattern.",
		{ ingredients = { Wool = 4 }, station = CT }),
	row("Banner", "Banner", "Uncommon", "plain", "A blue cloth banner on a standing pole.",
		{ ingredients = { Stick = 3, BlueCloth = 2 }, station = CT }),
	row("Scarecrow", "Scarecrow", "Common", "plain", "A straw-stuffed sentry for a field.",
		{ ingredients = { Stick = 4, Wood = 1, Herb = 2 }, station = CT }),
	row("Well", "Well", "Uncommon", "plain", "A cobblestone well under a little roof.",
		{ ingredients = { Cobblestone = 12, WoodPlank = 4, IronIngot = 1 }, station = CT }),
	row("WeaponRack", "Weapon Rack", "Uncommon", "plain", "A stand of three swords. For show.",
		{ ingredients = { WoodPlank = 4, IronIngot = 3 }, station = ANVIL }),
	row("HayBale", "Hay Bale", "Common", "plain", "A tied bale of straw.",
		{ ingredients = { Herb = 6 }, station = CT }),
	row("FirewoodPile", "Firewood Pile", "Common", "plain", "Split logs stacked between two stakes.",
		{ ingredients = { Wood = 6 }, station = CT }),
	row("TrainingDummy", "Training Dummy", "Common", "plain", "A sackcloth dummy on a post, with a target on its chest.",
		{ ingredients = { Stick = 3, Wool = 2, Leather = 1 }, station = CT }),
	row("ArcheryTarget", "Archery Target", "Common", "plain", "A painted straw target on a tripod.",
		{ ingredients = { WoodPlank = 3, Wool = 3 }, station = CT }),
	row("WaterTrough", "Water Trough", "Common", "plain", "An iron-banded wooden trough of water.",
		{ ingredients = { WoodPlank = 5, IronIngot = 1 }, station = CT }),
	row("Fountain", "Fountain", "Rare", "plain", "A two-tier stone-brick fountain.",
		{ ingredients = { StoneBricks = 8, Bottle = 2 }, station = CT }),
	row("Gravestone", "Gravestone", "Common", "plain", "A weathered headstone with a carved cross.",
		{ ingredients = { Cobblestone = 4 }, station = CT }),
	row("Signpost", "Signpost", "Common", "plain", "A post with two arrow boards.",
		{ ingredients = { WoodPlank = 3, Stick = 2 }, station = CT }),

	-- Curios: odd, fun finds. Many want a drop or two from a creature, so
	-- they turn up as a player explores rather than all at once.
	row("MushroomChair", "Mushroom Chair", "Uncommon", "seat", "A toadstool to sit on, with a little one growing up behind for a back.",
		{ ingredients = { Herb = 3, WoodPlank = 2 }, station = CT }),
	row("FrogStool", "Frog Stool", "Uncommon", "seat", "A big green frog that doesn't mind being sat on.",
		{ ingredients = { Gel = 4, Herb = 2 }, station = CT }),
	row("PumpkinSeat", "Pumpkin Seat", "Common", "seat", "A pumpkin with the top sliced flat.",
		{ ingredients = { Herb = 4, Wood = 1 }, station = CT }),
	row("CloudCushion", "Cloud Cushion", "Rare", "seat", "A heap of cloud, somehow solid enough to sit in.",
		{ ingredients = { Wool = 6, Feather = 4 }, station = CT }),
	row("Hammock", "Hammock", "Uncommon", "seat", "A striped hammock slung between two posts, two blocks wide.",
		{ ingredients = { Silk = 4, Wood = 2 }, station = CT }),
	row("MelonStool", "Melon Stool", "Common", "seat", "Half a watermelon, cut side up.",
		{ ingredients = { Herb = 4, Gel = 1 }, station = CT }),
	row("Cauldron", "Cauldron", "Rare", "light", "An iron cauldron of something green and glowing.",
		{ ingredients = { IronIngot = 5, Gel = 3 }, station = ANVIL }),
	row("CrystalCluster", "Amethyst Cluster", "Epic", "light", "Glowing amethyst growing out of a rock.",
		{ ingredients = { EssenceShard = 3, Stone = 4 }, station = FORGE }),
	row("FairyLantern", "Fairy Jar", "Rare", "light", "A glass jar full of fireflies.",
		{ ingredients = { Bottle = 2, Gel = 2, Herb = 1 }, station = "AlchemyBench" }),
	row("SkullCandle", "Skull Candle", "Uncommon", "light", "A candle melting on top of a skull.",
		{ ingredients = { Bone = 4, Gel = 1 }, station = CT }),
	row("LavaLamp", "Lava Lamp", "Rare", "light", "Slow blobs of lava rising in a brass lamp.",
		{ ingredients = { Bottle = 2, CopperIngot = 2, Coal = 2 }, station = "AlchemyBench" }),
	row("GlowShroom", "Giant Glowshroom", "Rare", "light", "A mushroom two blocks tall with glowing spots.",
		{ ingredients = { Herb = 6, Gel = 4 }, station = "AlchemyBench" }),
	row("MushroomTable", "Mushroom Table", "Common", "plain", "A wide flat toadstool. Things sit on top of it.",
		{ ingredients = { Herb = 4, WoodPlank = 3 }, station = CT }),
	row("CatBed", "Cat Bed", "Uncommon", "plain", "A round cushion with a ginger cat asleep in it.",
		{ ingredients = { Wool = 4, Pelt = 2 }, station = CT }),
	row("Fishbowl", "Fishbowl", "Uncommon", "plain", "A goldfish in a glass bowl on a little stand.",
		{ ingredients = { Bottle = 3, Sand = 2 }, station = CT }),
	row("Piano", "Piano", "Epic", "plain", "An upright piano, two blocks wide. Bone keys.",
		{ ingredients = { WoodPlank = 12, Bone = 4, IronIngot = 2 }, station = CT }),
	row("Aquarium", "Aquarium", "Rare", "plain", "A long fish tank with weed, rocks and three fish.",
		{ ingredients = { Bottle = 6, WoodPlank = 4, Sand = 4 }, station = CT }),
	row("Easel", "Easel", "Common", "plain", "A painting of hills, a lake and the sun, still on its easel.",
		{ ingredients = { Stick = 4, Wool = 2 }, station = CT }),
	row("MagicMirror", "Magic Mirror", "Epic", "plain", "A tall gilded mirror with a faint glow.",
		{ ingredients = { GoldIngot = 3, Bottle = 2, EssenceShard = 1 }, station = FORGE }),
	row("Telescope", "Telescope", "Rare", "plain", "A brass telescope on a tripod, pointed at the sky.",
		{ ingredients = { CopperIngot = 4, Bottle = 1, Stick = 3 }, station = ANVIL }),
	row("Bathtub", "Bathtub", "Rare", "plain", "A clawfoot tub full of bubbles. There's a duck in it.",
		{ ingredients = { IronIngot = 6, GoldIngot = 1 }, station = ANVIL }),
	row("TreasurePile", "Treasure Pile", "Legendary", "plain", "A heap of gold and gems with a crown on top.",
		{ ingredients = { GoldIngot = 8, EssenceShard = 1 }, station = ANVIL }),
	row("DragonSkull", "Dragon Skull", "Legendary", "plain", "The horned skull of something enormous. Two blocks by two.",
		{ ingredients = { Bone = 20, Coal = 2 }, station = CT }),
	row("SnowmanStatue", "Snowman", "Common", "plain", "A snowman with a top hat and a scarf, two blocks tall.",
		{ ingredients = { Snow = 8, Coal = 2, Stick = 2 }, station = CT }),
	row("Beehive", "Beehive", "Common", "plain", "A straw skep on a stand, dripping honey.",
		{ ingredients = { Herb = 4, WoodPlank = 3 }, station = CT }),
	row("Tent", "Tent", "Uncommon", "plain", "A canvas tent, two blocks by two, with a blanket inside.",
		{ ingredients = { Wool = 8, Stick = 6 }, station = CT }),
	row("ArmorStand", "Armor Stand", "Rare", "plain", "A full suit of iron armour with a plumed helm and a shield.",
		{ ingredients = { IronIngot = 8, WoodPlank = 2 }, station = ANVIL }),
	row("TotemPole", "Totem Pole", "Rare", "plain", "Three painted faces and a winged top, two blocks tall.",
		{ ingredients = { Wood = 6, BlueCloth = 1, PurpleCloth = 1 }, station = CT }),
	row("GiantRubberDuck", "Giant Rubber Duck", "Uncommon", "plain", "A rubber duck the size of a block.",
		{ ingredients = { Gel = 8 }, station = CT }),
	row("TeddyBear", "Teddy Bear", "Common", "plain", "A big teddy with a red bow.",
		{ ingredients = { Pelt = 3, Wool = 2 }, station = CT }),
}

DecorCatalog.ById = {}
for index, entry in ipairs(DecorCatalog.Entries) do
	entry.order = index
	DecorCatalog.ById[entry.id] = entry
end

local ACTION_TEXT = {
	door = "Open",
	light = "Douse",
	seat = "Sit",
}

function DecorCatalog.get(id)
	return DecorCatalog.ById[id]
end

-- The prompt's verb for a piece, or nil for one that has no prompt at all.
function DecorCatalog.actionText(entry)
	return entry.actionText or ACTION_TEXT[entry.kind]
end

return DecorCatalog
