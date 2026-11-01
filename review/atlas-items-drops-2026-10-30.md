# Atlas entries and enemy drops — 30 October 2026

Applied to BlockBound in Studio and mirrored into the source files.

- 432 item definitions: 80 existing and 352 new.
- All 408 atlas sprites have exactly one item entry.
- 51 enemy tables, 141 loot rows; CatMagicianDecoy intentionally has none.
- 35 new atlas materials have enemy sources; 317 new entries are intentionally reserved.
- Reserved items retain normal tier rarities. catalogOnly marks availability separately.
- No new recipes, equipment effects, consumable handlers, enemy behavior, VFX, or acquisition sources for previously withheld weapons.

## Validation

Fresh ModuleScript loads passed in Studio edit mode. Checked descriptions, display names, valid rarity colors, integer stack sizes, atlas coverage, enemy coverage, item references, reserved-item exclusion, duplicate loot rows, probability/quantity bounds, forced minimum drops, guaranteed maximum drops, unknown enemies, and decoy drops. No problems found. Source diff whitespace checks passed.

Read the live EnemyService → EnemyDrops.roll → GroundDrops.spawn integration. No kill/pickup gameplay playtest was performed in this pass.

## Enemy loot

| Enemy | Drops (quantity / independent probability) |
| --- | --- |
| AllSeeingEye | Gold Ore ×10–18 / 100%; Essence Shard ×4–8 / 100%; Mythril Ore ×2–5 / 50%; Soul of Sight ×1–2 / 100%; Black Lens ×1 / 30% |
| Auroch | Leather ×2–4 / 100%; Horns ×1 / 40% |
| AxeGolem | Wood ×2–4 / 100%; Stick ×1–3 / 50%; Essence Shard ×1–2 / 30% |
| BatMutant | Bat Wing ×1–2 / 65%; Fang ×1 / 25%; Essence Shard ×1 / 15% |
| Beagle | Pelt ×1 / 60% |
| BearidWizard | Leather ×1–3 / 100%; Pelt ×1–2 / 50%; Essence Shard ×1–2 / 30%; Mana Potion ×1 / 10% |
| BeisaOryx | Leather ×1–2 / 100%; Horns ×1 / 35% |
| Blightborer | Mythril Ore ×6–12 / 100%; Essence Shard ×5–9 / 100%; Void Crystal ×1–2 / 35%; Green Scale ×4–8 / 100% |
| Blightling | Green Scale ×1 / 20%; Essence Shard ×1 / 4% |
| BlueSlime | Gel ×1–2 / 100% |
| Bronto | Leather ×3–6 / 100%; Bone ×2–4 / 50%; Essence Shard ×1–2 / 30% |
| Cannon | Coal ×2–4 / 100%; Iron Ore ×1–2 / 40% |
| CatMagician | Mana Potion ×1 / 40%; Purple Cloth ×1–2 / 50%; Essence Shard ×1–2 / 30% |
| CatMagicianDecoy | None — illusion |
| CatMonk | Blue Cloth ×1–2 / 50%; Mana Potion ×1 / 20%; Essence Shard ×1–2 / 25% |
| Cobra | Green Scale ×1–2 / 70%; Fang ×1 / 35%; Venom Sac ×1 / 20% |
| CrabMonster | Crab Shell ×1–3 / 100%; Claws ×1 / 40%; Essence Shard ×1–2 / 20% |
| DemonEye | Lens ×1 / 65%; Essence Shard ×1 / 6% |
| EvilRat | Pelt ×1 / 30%; Fang ×1 / 15% |
| FootedPiranha | Green Scale ×1 / 60%; Fang ×1 / 30% |
| Ghost | Ectoplasm ×1–2 / 65% |
| GoatShaman | Wool ×1–3 / 80%; Mana Potion ×1 / 30%; Shiverthorn ×1–2 / 40%; Essence Shard ×1–2 / 25% |
| Gorilla | Leather ×2–4 / 100%; Dark Pelt ×1–2 / 40%; Essence Shard ×1 / 15% |
| GreenRaptor | Green Scale ×1 / 70%; Claws ×1 / 25% |
| GreenSlime | Gel ×1–2 / 100%; Green Gel ×1 / 35% |
| GreenSpider | Silk ×1–2 / 100%; Cobweb ×1–2 / 40%; Venom Sac ×1 / 25%; Essence Shard ×1 / 5% |
| GreenWasp | Stinger ×1 / 70%; Venom Sac ×1 / 20%; Essence Shard ×1 / 5% |
| HandlessNorg | Purple Gel ×1–3 / 60%; Rotten Chunk ×1–2 / 50%; Essence Shard ×1–2 / 25% |
| Lasereye | Lens ×1 / 100%; Gel ×1–2 / 50%; Essence Shard ×1 / 12% |
| LavaGolem | Coal ×3–6 / 100%; Ember Dust ×1–3 / 70%; Essence Shard ×1–3 / 40% |
| LemurianWarrior | Pelt ×1–2 / 80%; Leather ×1–2 / 40%; Essence Shard ×1–2 / 25% |
| LizardWarrior | Leather ×1–2 / 100%; Green Scale ×1–2 / 65%; Essence Shard ×1–2 / 25% |
| Longleg | Leather ×1–2 / 70%; Rotten Chunk ×1–2 / 50%; Essence Shard ×1–2 / 35% |
| OgreBrute | Leather ×2–4 / 100%; Iron Ore ×1–2 / 30%; Essence Shard ×1–2 / 20% |
| Pentasaurus | Leather ×1–3 / 100%; Horns ×1 / 40%; Essence Shard ×1 / 8% |
| PinkyDemon | Flesh Chunk ×2–4 / 100%; Dark Horns ×1 / 40%; Essence Shard ×1–3 / 60%; Gold Ore ×1–3 / 30% |
| PitDevil | Leather ×1–2 / 100%; Dark Horns ×1 / 35%; Flesh Chunk ×1–2 / 50%; Essence Shard ×1–2 / 25% |
| RabbicCleric | Herb ×1–3 / 70%; Hallowlily ×1 / 30%; Essence Shard ×1–2 / 25% |
| RainbowSlime | Gel ×12–20 / 100%; Pink Gel ×2–4 / 100%; Essence Shard ×2–4 / 100%; Gold Ore ×2–5 / 50% |
| Rooster | Feather ×1–2 / 100%; Egg ×1 / 20% |
| ServantEye | Lens ×1 / 15% |
| Shrike | Feather ×1–2 / 100%; Claws ×1 / 20%; Essence Shard ×1 / 8% |
| Signus | Mythril Ore ×5–9 / 100%; Essence Shard ×5–8 / 100%; Soul of Fright ×1–2 / 100%; Void Lens ×1 / 25% |
| SlimeEmperor | Gel ×40–60 / 100%; Pink Gel ×3–6 / 100% |
| Snowman | Snow ×2–4 / 100%; Coal ×1–2 / 60%; Stick ×1–2 / 40% |
| SpottedDemon | Leather ×1–2 / 100%; Dark Horns ×1 / 35%; Essence Shard ×1–2 / 30% |
| TigerBlademaster | Leather ×1–3 / 100%; Claws ×1 / 40%; Gold Ore ×1–2 / 25%; Essence Shard ×1–2 / 30% |
| VampireDuck | Black Feather ×1–2 / 60%; Blood Sac ×1 / 30% |
| WerewolfLord | Leather ×2–3 / 100%; Dark Pelt ×1–2 / 75%; Claws ×1 / 40%; Essence Shard ×1–2 / 35% |
| WormyHorror | Rotten Chunk ×1–3 / 80%; Corrupted Dirt ×1–2 / 30%; Essence Shard ×1–2 / 20% |
| ZombieRat | Rotten Chunk ×1 / 50%; Bone ×1 / 25% |

## Item catalog

Reserved means deliberately without a source. Existing means the prior recipe, mining, harvest or other acquisition policy is preserved; it does not imply obtainable.

| Item ID | Display name | Rarity | Status | Description |
| --- | --- | --- | --- | --- |
| AlchemyBench | Alchemy Bench | Uncommon | Existing | Used to craft potions and magical consumables. |
| Ale | Ale | Common | Reserved | A bottle of dark, foamy ale. |
| AltarCore | Altar Core | Rare | Existing | The heart of an altar, where offerings call powerful creatures. |
| AltarStone | Altar Stone | Rare | Existing | Dark carved stone, older than anything around it. The body of an altar. |
| Amber | Amber | Uncommon | Reserved | Golden tree resin with tiny shapes trapped inside. |
| Amethyst | Amethyst | Rare | Reserved | A cut amethyst with bright, glassy facets. |
| AncientDust | Ancient Dust | Rare | Reserved | Powder shaken from something far older than it looks. |
| AngelWings | Angel Wings | Epic | Reserved | A pair of angel wings mounted on a wearable frame. |
| Ankh | Ankh | Rare | Reserved | An ancient looped cross worn smooth at the edges. |
| Anvil | Anvil | Uncommon | Existing | Used to forge weapons and armor. |
| Apple | Apple | Common | Reserved | A crisp red apple. |
| ApplePie | Apple Pie | Common | Reserved | A small pie filled with sweet apple pieces. |
| ArcaneForge | Arcane Forge | Rare | Existing | Fuses magic into equipment. Required for enchanted gear. |
| ArcaneScroll | Scroll Arcane | Uncommon | Reserved | A sealed scroll covered in intricate magical script. |
| ArcaneTome | Arcane Tome | Rare | Reserved | A bound volume of arcane lore, covered in careful annotations. |
| Arrows | Arrows | Common | Reserved | Straight wooden arrows tipped with sharpened metal. |
| ArrowsFlame | Flame Arrows | Uncommon | Reserved | Arrows with ember-red heads and dark shafts. |
| ArrowsFrost | Frost Arrows | Uncommon | Reserved | Arrows tipped with pale, icy crystals. |
| ArrowsHoly | Holy Arrows | Rare | Reserved | Bright arrows with finely worked golden heads. |
| AvengerEmblem | Avenger Emblem | Epic | Reserved | An engraved emblem bearing the symbol of the avenger. |
| BasicChest | Basic Chest | Common | Existing | Holds 27 stacks. Place it on your island and open it to store things. |
| BatWing | Bat Wing | Uncommon | Enemy loot | A leathery wing stretched between fine bones. |
| BatWings | Bat Wings | Rare | Reserved | A pair of bat wings mounted on a wearable frame. |
| BattlePotion | Battle Potion | Uncommon | Reserved | A dark crimson brew with a pungent scent. |
| BattleRing | Battle Ring | Rare | Existing | A fiery-gem ring that increases weapon damage by 15% while worn. |
| Bell | Bell | Uncommon | Reserved | A small brass bell with a rounded lip. |
| BellSilver | Bell Silver | Uncommon | Reserved | A polished silver bell with a slender handle. |
| Berries | Berries | Common | Reserved | A handful of ripe woodland berries. |
| BerryPie | Berry Pie | Common | Reserved | A golden pastry filled with dark berries. |
| BirchPlankBlock | Birch Plank Block | Common | Reserved | A sample of birch plank with a firm, even shape. |
| BlackCape | Black Cape | Uncommon | Reserved | A long black cape fastened with a simple clasp. |
| BlackFeather | Black Feather | Uncommon | Enemy loot | A glossy black feather from a dark-winged creature. |
| BlackLens | Black Lens | Rare | Enemy loot | A dark lens that catches almost no light. |
| BlankScroll | Scroll | Uncommon | Reserved | A rolled sheet of parchment tied with cord. |
| BlightborerPouch | Blightborer Pouch | Epic | Reserved | An earth-stained pouch marked with a burrowing creature. |
| Blinkroot | Blinkroot | Uncommon | Reserved | A knotted root with tiny golden buds. |
| BloodFlask | Blood Flask | Rare | Reserved | A sealed flask of dark blood. |
| BloodSac | Blood Sac | Uncommon | Enemy loot | A swollen sac filled with dark blood. |
| BloodTome | Blood Tome | Epic | Reserved | A bound volume of blood lore, covered in careful annotations. |
| Bloodfang | Bloodfang | Epic | Existing | A crimson katana with a cruel, fang-like edge. |
| BlueCape | Blue Cape | Uncommon | Reserved | A long blue cape fastened with a simple clasp. |
| BlueCloth | Blue Cloth | Common | Enemy loot | A neatly folded piece of blue cloth. |
| BlueScale | Blue Scale | Uncommon | Reserved | A tough blue scale from a creature's hide. |
| Bomb | Bomb | Uncommon | Reserved | A round iron casing packed tightly around a short fuse. |
| Bone | Bone | Common | Enemy loot | A weathered bone, stripped clean of flesh. |
| BoneKey | Bone Key | Epic | Reserved | A bone key with an intricate, unfamiliar cut. |
| Bottle | Bottle | Common | Existing | Empty glass bottle. Holds liquids. |
| Bread | Bread | Common | Reserved | A small loaf with a crisp golden crust. |
| BronzeArmor | Bronze Armor | Uncommon | Reserved | A suit of bronze plates. |
| BronzeTrophy | Bronze Trophy | Uncommon | Reserved | A polished bronze trophy on a solid pedestal. |
| BuilderWand | Builder Wand | Epic | Existing | An ornate wand shaped for a master builder's hand. |
| Bullet | Bullet | Common | Reserved | A small metal round with a blunt nose. |
| BulletSilver | Silver Bullet | Uncommon | Reserved | A polished silver round. |
| Cake | Cake | Common | Reserved | A slice of soft cake topped with icing. |
| CalmingPotion | Calming Potion | Uncommon | Reserved | A pale green brew scented with gentle herbs. |
| Candle | Candle | Uncommon | Reserved | A short wax candle with a dark wick. |
| CandlePurple | Candle Purple | Uncommon | Reserved | A violet candle with a smooth wax finish. |
| CandleRed | Candle Red | Uncommon | Reserved | A deep red candle with a braided wick. |
| Carrot | Carrot | Common | Reserved | A crunchy orange root with a leafy top. |
| Chain | Chain | Uncommon | Reserved | Linked metal rings, heavy and difficult to snap. |
| Cheese | Cheese | Common | Reserved | A wedge of firm yellow cheese. |
| Cherries | Cherries | Common | Reserved | Sweet red cherries joined at the stem. |
| Claws | Claws | Uncommon | Enemy loot | Curved claws with edges worn sharp by hunting. |
| ClothArmor | Cloth Armor | Common | Reserved | A suit of cloth. |
| Cloud | Cloud | Uncommon | Reserved | A small tuft of strangely solid cloud. |
| CloudInBottle | Cloud In Bottle | Rare | Reserved | A drifting cloud sealed inside a glass bottle. |
| Coal | Coal | Common | Enemy loot | A black mineral used as fuel when smelting ore. |
| CoalOreBlock | Coal Ore Block | Common | Reserved | A stone sample threaded with coal ore. |
| CobaltArmor | Cobalt Armor | Epic | Reserved | A suit of cobalt plates. |
| CobaltGreaves | Cobalt Greaves | Epic | Reserved | A pair of greaves made from cobalt plates. |
| CobaltHelmet | Cobalt Helmet | Epic | Reserved | A shaped helmet of cobalt plates. |
| CobaltIngot | Cobalt Ingot | Epic | Reserved | A refined bar of cobalt, ready for a smith's work. |
| CobaltOre | Cobalt Ore | Epic | Reserved | Raw cobalt ore with veins running through the stone. |
| CobaltShield | Cobalt Shield | Epic | Reserved | A cobalt shield with a solid central boss. |
| Cobblestone | Cobblestone | Common | Existing | Rough stone. Useful for crafting and building. |
| Cobweb | Cobweb | Common | Enemy loot | A sticky tangle of spider silk. |
| CoinPurse | Coin Purse | Uncommon | Reserved | A small purse that jingles when shaken. |
| Compass | Compass | Uncommon | Reserved | A brass compass with a finely balanced needle. |
| CookedMeat | Cooked Meat | Common | Reserved | A browned cut of meat with a crisp outer edge. |
| Cookie | Cookie | Common | Reserved | A crisp cookie dotted with chocolate. |
| CopperArmor | Copper Armor | Common | Reserved | A suit of copper plates. |
| CopperCoin | Copper Coin | Common | Reserved | A stamped copper coin with a worn rim. |
| CopperGreaves | Copper Greaves | Common | Reserved | A pair of greaves made from copper plates. |
| CopperHelmet | Copper Helmet | Common | Reserved | A shaped helmet of copper plates. |
| CopperIngot | Copper Ingot | Common | Existing | A refined bar of copper. The first real tool metal. |
| CopperOre | Copper Ore | Common | Existing | Raw copper. Smelt it into an ingot. |
| CopperOreBlock | Copper Ore Block | Common | Reserved | A stone sample threaded with copper ore. |
| CopperPickaxe | Copper Pickaxe | Common | Existing | A copper-headed pickaxe for early mining. |
| CopperSword | Copper Sword | Common | Existing | A light copper blade with a dependable edge. |
| CorruptedArmor | Corrupted Armor | Rare | Reserved | A suit of corrupted plates. |
| CorruptedDirt | Corrupted Dirt | Uncommon | Enemy loot | Soil tainted by corruption. |
| CorruptedGreaves | Corrupted Greaves | Rare | Reserved | A pair of greaves made from corrupted plates. |
| CorruptedHelmet | Corrupted Helmet | Rare | Reserved | A shaped helmet of corrupted plates. |
| CorruptedIngot | Corrupted Ingot | Rare | Reserved | A refined bar of corrupted, ready for a smith's work. |
| CorruptedOre | Corrupted Ore | Rare | Reserved | Raw corrupted ore with veins running through the stone. |
| CorruptedShard | Corrupted Shard | Rare | Reserved | A jagged fragment of corrupted energy. |
| CorruptedStone | Corrupted Stone | Uncommon | Existing | Dark, twisted stone infused with corruption. |
| CrabShell | Crab Shell | Uncommon | Enemy loot | A hard piece of shell from a clawed creature. |
| CraftingTable | Crafting Table | Common | Existing | Used to craft basic tools and items. |
| Crimbloom | Crimbloom | Uncommon | Reserved | A red blossom rooted in crimson soil. |
| CrimsonArmor | Crimson Armor | Rare | Reserved | A suit of crimson plates. |
| CrimsonCrate | Crimson Crate | Rare | Reserved | A sealed crimson crate with reinforced corners. |
| CrimsonDirt | Crimson Dirt | Uncommon | Existing | Soil from the crimson biome. |
| CrimsonGreaves | Crimson Greaves | Rare | Reserved | A pair of greaves made from crimson plates. |
| CrimsonHelmet | Crimson Helmet | Rare | Reserved | A shaped helmet of crimson plates. |
| CrimsonIngot | Crimson Ingot | Rare | Reserved | A refined bar of crimson, ready for a smith's work. |
| CrimsonKey | Crimson Key | Epic | Reserved | A crimson key with an intricate, unfamiliar cut. |
| CrimsonOrb | Crimson Orb | Rare | Reserved | A smooth orb holding a flicker of crimson energy. |
| CrimsonOre | Crimson Ore | Rare | Reserved | Raw crimson ore with veins running through the stone. |
| CrimsonShard | Crimson Shard | Rare | Reserved | A jagged fragment of crimson energy. |
| CrimsonShield | Crimson Shield | Rare | Reserved | A crimson shield with a solid central boss. |
| CrimsonStone | Crimson Stone | Uncommon | Existing | A blood-red stone from the crimson lands. |
| CrystalBall | Crystal Ball | Uncommon | Reserved | A clear sphere resting on an ornate stand. |
| CrystalBallBlood | Crystal Ball Blood | Rare | Reserved | A crimson sphere with dark shapes beneath its surface. |
| CrystalBallFrost | Crystal Ball Frost | Uncommon | Reserved | A glass sphere clouded with delicate frost. |
| CrystalBallNature | Crystal Ball Nature | Uncommon | Reserved | A green sphere filled with leaf-like patterns. |
| CursedFlask | Cursed Flask | Rare | Reserved | A sealed flask of sickly green liquid. |
| DarkHorns | Dark Horns | Rare | Enemy loot | Dark horns ridged with signs of age. |
| DarkPelt | Dark Pelt | Uncommon | Enemy loot | A dark pelt with coarse, dense fur. |
| Daybloom | Daybloom | Common | Reserved | A small golden flower that opens toward the sun. |
| Deathweed | Deathweed | Uncommon | Reserved | A wiry herb that thrives in tainted soil. |
| DemonWings | Demon Wings | Epic | Reserved | A pair of demon wings mounted on a wearable frame. |
| DesertKey | Desert Key | Epic | Reserved | A desert key with an intricate, unfamiliar cut. |
| Diamond | Diamond | Epic | Reserved | A cut diamond with bright, glassy facets. |
| Dirt | Dirt | Common | Existing | Loose earth. |
| Donut | Donut | Common | Reserved | A sweet ring of dough with a smooth glaze. |
| Dreamcatcher | Dreamcatcher | Uncommon | Reserved | A woven hoop decorated with thread and feathers. |
| Ectoplasm | Ectoplasm | Uncommon | Enemy loot | A cold, translucent residue left behind by restless spirits. |
| EctoplasmFlask | Ectoplasm Flask | Rare | Reserved | A sealed flask of pale spirit residue. |
| EctoplasmShard | Ectoplasm Shard | Rare | Reserved | A jagged fragment of condensed spirit residue. |
| Egg | Egg | Common | Enemy loot | A pale egg in a fragile shell. |
| EmberDust | Ember Dust | Uncommon | Enemy loot | Warm red dust with a faint ember glow. |
| Emerald | Emerald | Rare | Reserved | A cut emerald with bright, glassy facets. |
| EmeraldArmor | Emerald Armor | Rare | Reserved | A suit of emerald plates. |
| EmperorPouch | Emperor Pouch | Epic | Reserved | A regal pouch marked with a slime crown. |
| EnchantingTable | Enchanting Table | Epic | Existing | Used to enchant weapons, tools, and armor. |
| EndurancePotion | Endurance Potion | Uncommon | Reserved | A dense amber tonic with a bitter scent. |
| EssenceShard | Essence Shard | Rare | Enemy loot | Crystallized magic used in high-end crafting. |
| EyePouch | Eye Pouch | Epic | Reserved | A sealed pouch bearing a watchful eye. |
| FairyWings | Fairy Wings | Rare | Reserved | A pair of fairy wings mounted on a wearable frame. |
| FallenStar | Fallen Star | Rare | Reserved | A fragment of starlight, cool enough to hold. |
| Fang | Fang | Uncommon | Enemy loot | A sharp tooth pulled from a predator's jaws. |
| Feather | Feather | Common | Enemy loot | A light bird feather with a sturdy quill. |
| FeatherfallPotion | Featherfall Potion | Uncommon | Reserved | A pale brew with a feather suspended inside. |
| FeralGlove | Feral Glove | Rare | Reserved | A feral glove with reinforced fingers. |
| FireTome | Fire Tome | Rare | Reserved | A bound volume of fire lore, covered in careful annotations. |
| Fireblossom | Fireblossom | Uncommon | Reserved | A bright flower that flourishes near intense heat. |
| FlameHammer | Flame Hammer | Epic | Existing | A heavy hammer with a head shaped like a rising flame. |
| FlameWings | Flame Wings | Epic | Reserved | A pair of flame wings mounted on a wearable frame. |
| FleshChunk | Flesh Chunk | Uncommon | Enemy loot | A dense lump of crimson flesh. |
| FrostAmulet | Frost Amulet | Rare | Reserved | An amulet set around a frost centerpiece. |
| FrostArmor | Frost Armor | Rare | Reserved | A suit of frost plates. |
| FrostBoots | Frost Boots | Rare | Reserved | A pair of frost boots with reinforced soles. |
| FrostCrate | Frost Crate | Rare | Reserved | A sealed frost crate with reinforced corners. |
| FrostDust | Frost Dust | Uncommon | Reserved | Pale powder that stays cold to the touch. |
| FrostGreaves | Frost Greaves | Rare | Reserved | A pair of greaves made from frost plates. |
| FrostHelmet | Frost Helmet | Rare | Reserved | A shaped helmet of frost plates. |
| FrostIngot | Frost Ingot | Rare | Reserved | A refined bar of frost, ready for a smith's work. |
| FrostKey | Frost Key | Epic | Reserved | A frost key with an intricate, unfamiliar cut. |
| FrostOrb | Frost Orb | Rare | Reserved | A smooth orb holding a flicker of frost energy. |
| FrostOre | Frost Ore | Rare | Reserved | Raw frost ore with veins running through the stone. |
| FrostRing | Frost Ring | Rare | Reserved | A frost ring with carefully worked markings. |
| FrostShard | Frost Shard | Rare | Reserved | A jagged fragment of frost energy. |
| FrostTome | Frost Tome | Rare | Reserved | A bound volume of frost lore, covered in careful annotations. |
| FrostWings | Frost Wings | Rare | Reserved | A pair of frost wings mounted on a wearable frame. |
| Furnace | Furnace | Common | Existing | Smelts ores into ingots. |
| Gel | Gel | Common | Enemy loot | A wobbling lump of slime. Sticky, faintly sweet, and oddly warm. |
| GelatinousCrown | Gelatinous Crown | Epic | Existing | A crown of gel, gold, and iron. Offer it at an altar to summon the Slime Emperor. |
| GillsPotion | Gills Potion | Uncommon | Reserved | A sea-green brew with tiny drifting bubbles. |
| GoldArmor | Gold Armor | Rare | Reserved | A suit of gold plates. |
| GoldBoots | Gold Boots | Rare | Reserved | A pair of gold boots with reinforced soles. |
| GoldCoin | Gold Coin | Rare | Reserved | A stamped gold coin with a worn rim. |
| GoldCrate | Gold Crate | Rare | Reserved | A sealed gold crate with reinforced corners. |
| GoldGlove | Golden Glove | Rare | Reserved | A gold glove with reinforced fingers. |
| GoldGreaves | Gold Greaves | Rare | Reserved | A pair of greaves made from gold plates. |
| GoldHelmet | Gold Helmet | Rare | Reserved | A shaped helmet of gold plates. |
| GoldIngot | Gold Ingot | Rare | Existing | A refined bar of gold. Soft, valuable, and a little vain. |
| GoldKey | Gold Key | Rare | Reserved | A gold key with an intricate, unfamiliar cut. |
| GoldOre | Gold Ore | Rare | Enemy loot | Raw gold, found only well below the surface. |
| GoldOreBlock | Gold Ore Block | Rare | Reserved | A stone sample threaded with gold ore. |
| GoldPickaxe | Gold Pickaxe | Rare | Existing | A finely edged gold pickaxe for fast mining. |
| GoldRing | Gold Ring | Rare | Reserved | A gold ring with carefully worked markings. |
| GoldScale | Gold Scale | Rare | Reserved | A tough golden scale from a creature's hide. |
| GoldSword | Gold Sword | Rare | Existing | A bright gold longsword with a keen edge. |
| GoldTrophy | Gold Trophy | Epic | Reserved | A polished gold trophy on a solid pedestal. |
| GoldenApple | Golden Apple | Rare | Reserved | A golden apple with a brilliant, unblemished skin. |
| Grapes | Grapes | Common | Reserved | A bunch of juicy purple grapes. |
| Grass | Grass | Common | Existing | Surface grass block. |
| GreaterHealingPotion | Greater Healing Potion | Rare | Reserved | A large bottle of concentrated red tonic. |
| GreaterManaPotion | Greater Mana Potion | Rare | Reserved | A large bottle of concentrated blue essence. |
| GreenCape | Green Cape | Uncommon | Reserved | A long green cape fastened with a simple clasp. |
| GreenGel | Green Gel | Uncommon | Enemy loot | A springy lump of green slime, still trying to hold its shape. |
| GreenGrapes | Green Grapes | Common | Reserved | A bunch of fresh green grapes. |
| GreenScale | Green Scale | Uncommon | Enemy loot | A tough green scale from a creature's hide. |
| HallowedArmor | Hallowed Armor | Epic | Reserved | A suit of hallowed plates. |
| HallowedDirt | Hallowed Dirt | Uncommon | Existing | Pale soil from the Hallow. |
| HallowedGreaves | Hallowed Greaves | Epic | Reserved | A pair of greaves made from hallowed plates. |
| HallowedHelmet | Hallowed Helmet | Epic | Reserved | A shaped helmet of hallowed plates. |
| HallowedIngot | Hallowed Ingot | Epic | Reserved | A refined bar of hallowed, ready for a smith's work. |
| HallowedKey | Hallowed Key | Epic | Reserved | A hallowed key with an intricate, unfamiliar cut. |
| HallowedOre | Hallowed Ore | Epic | Reserved | Raw hallowed ore with veins running through the stone. |
| HallowedShard | Hallowed Shard | Epic | Reserved | A jagged fragment of hallowed energy. |
| HallowedStone | Hallowed Stone | Uncommon | Existing | Bright stone found beneath the Hallow. |
| Hallowlily | Hallowlily | Uncommon | Enemy loot | A delicate lily with an unusually bright sheen. |
| HarpyFeather | Harpy Feather | Rare | Reserved | A long, stiff feather from a powerful flying creature. |
| HealthPotion | Health Potion | Common | Existing | A bottle of red medicinal tonic. |
| HeartGolden | Heart Golden | Rare | Reserved | A golden heart polished to a mirror shine. |
| Herb | Herb | Common | Enemy loot | A medicinal herb. Used in potions. |
| HolyShield | Holy Shield | Epic | Reserved | A holy shield with a solid central boss. |
| HolyTome | Holy Tome | Epic | Reserved | A bound volume of sacred lore, covered in careful annotations. |
| HoneyBottle | Honey Bottle | Common | Reserved | Thick golden honey sealed in a glass bottle. |
| Horns | Horns | Uncommon | Enemy loot | A pair of sturdy, curved horns. |
| HorseshoeIron | Horseshoe Iron | Uncommon | Reserved | A worn iron horseshoe with square nail holes. |
| HorseshoeLucky | Horseshoe Lucky | Uncommon | Reserved | A polished horseshoe kept as a token of good fortune. |
| Hourglass | Hourglass | Uncommon | Reserved | An hourglass with a fine stream of golden sand. |
| HunterPotion | Hunter Potion | Uncommon | Reserved | An amber brew with a clear, bright center. |
| IchorFlask | Ichor Flask | Rare | Reserved | A sealed flask of golden ichor. |
| IdolBlood | Idol Blood | Epic | Reserved | A crimson idol carved with jagged markings. |
| IdolFrost | Idol Frost | Epic | Reserved | A pale idol etched with frost-like patterns. |
| IdolGold | Idol Gold | Epic | Reserved | A small golden figure worn smooth by countless hands. |
| IdolVoid | Idol Void | Legendary | Reserved | A dark idol whose face is lost in shadow. |
| InvisibilityPotion | Invisibility Potion | Uncommon | Reserved | A nearly transparent brew in a frosted bottle. |
| IronArmor | Iron Armor | Rare | Existing | Heavy iron armor. Greatly increases defense. |
| IronCrate | Iron Crate | Uncommon | Reserved | A sealed iron crate with reinforced corners. |
| IronGreaves | Iron Greaves | Uncommon | Reserved | A pair of greaves made from iron plates. |
| IronHelmet | Iron Helmet | Uncommon | Reserved | A shaped helmet of iron plates. |
| IronIngot | Iron Ingot | Uncommon | Existing | A refined bar of iron. Used for stronger tools. |
| IronKey | Iron Key | Uncommon | Reserved | A iron key with an intricate, unfamiliar cut. |
| IronOre | Iron Ore | Uncommon | Enemy loot | Raw iron. Smelt it into an ingot. |
| IronOreBlock | Iron Ore Block | Common | Reserved | A stone sample threaded with iron ore. |
| IronPickaxe | Iron Pickaxe | Uncommon | Existing | An iron-headed pickaxe strong enough for tougher ores. |
| IronShield | Iron Shield | Uncommon | Reserved | A iron shield with a solid central boss. |
| IronSword | Iron Sword | Uncommon | Existing | A sturdy iron longsword for reliable close combat. |
| IronskinPotion | Ironskin Potion | Uncommon | Reserved | A gray tonic as thick as liquid metal. |
| JadeArmor | Jade Armor | Rare | Reserved | A suit of jade plates. |
| Juice | Juice | Common | Reserved | Sweet fruit juice in a small bottle. |
| JungleKey | Jungle Key | Epic | Reserved | A jungle key with an intricate, unfamiliar cut. |
| Lantern | Lantern | Uncommon | Reserved | A small lamp protected by a sturdy metal frame. |
| LavaBoots | Lava Boots | Uncommon | Reserved | A pair of lava boots with reinforced soles. |
| LeadGreaves | Lead Greaves | Uncommon | Reserved | A pair of greaves made from lead plates. |
| LeadHelmet | Lead Helmet | Uncommon | Reserved | A shaped helmet of lead plates. |
| LeadIngot | Lead Ingot | Uncommon | Reserved | A refined bar of lead, ready for a smith's work. |
| LeadOre | Lead Ore | Uncommon | Reserved | Raw lead ore with veins running through the stone. |
| LeafWings | Leaf Wings | Rare | Reserved | A pair of leaf wings mounted on a wearable frame. |
| Leather | Leather | Common | Enemy loot | Tough animal hide used to make basic armor. |
| LeatherArmor | Leather Armor | Uncommon | Existing | Basic armor made from leather. Provides light protection. |
| LeatherBoots | Leather Boots | Common | Reserved | A pair of leather boots with reinforced soles. |
| LeatherGreaves | Leather Greaves | Common | Reserved | A pair of greaves made from leather. |
| LeatherHelmet | Leather Helmet | Common | Reserved | A shaped helmet of leather. |
| LegendaryChest | Legendary Chest | Legendary | Existing | Holds 54 stacks. Twice a basic chest, and a good deal finer. |
| Lens | Lens | Uncommon | Enemy loot | A clear lens taken from a watchful eye. |
| LesserHealingPotion | Lesser Healing Potion | Common | Reserved | A small vial of mild red tonic. |
| LesserManaPotion | Lesser Mana Potion | Common | Reserved | A small vial of pale blue essence. |
| LifeCrystal | Life Crystal | Rare | Reserved | A heart-shaped crystal with a warm red glow. |
| LifeFruit | Life Fruit | Epic | Reserved | A rare golden fruit wrapped in fresh green leaves. |
| LifeforcePotion | Lifeforce Potion | Rare | Reserved | A vivid crimson brew with a pulsing glow. |
| LightLance | Light Lance | Legendary | Existing | A radiant spear that channels Sacred Rain and Event Horizon. |
| LightOrb | Light Orb | Rare | Reserved | A smooth orb holding a flicker of light energy. |
| LightningTome | Lightning Tome | Rare | Reserved | A bound volume of lightning lore, covered in careful annotations. |
| LuckPotion | Luck Potion | Rare | Reserved | A green brew with a tiny clover tied to the neck. |
| LuckyClover | Lucky Clover | Uncommon | Reserved | A rare four-leaf clover pressed flat for safekeeping. |
| MageArmor | Mage Armor | Rare | Reserved | A suit of rich, embroidered cloth. |
| MagicMirror | Magic Mirror | Rare | Reserved | A silver mirror with an unfamiliar landscape in its glass. |
| MagicPowerPotion | Magic Power Potion | Rare | Reserved | A violet brew bright with suspended sparks. |
| MagmaArmor | Magma Armor | Epic | Reserved | A suit of magma plates. |
| MagmaBrick | Magma Brick | Rare | Existing | Dense brick fired with magma ore. |
| MagmaGreaves | Magma Greaves | Epic | Reserved | A pair of greaves made from magma plates. |
| MagmaHelmet | Magma Helmet | Epic | Reserved | A shaped helmet of magma plates. |
| MagmaIngot | Magma Ingot | Epic | Reserved | A refined bar of magma, ready for a smith's work. |
| MagmaOrb | Magma Orb | Rare | Reserved | A smooth orb holding a flicker of magma energy. |
| MagmaOre | Magma Ore | Epic | Existing | Heat-scarred ore used to fire magma bricks. |
| MagmaOreBlock | Magma Ore Block | Epic | Reserved | A stone sample threaded with magma ore. |
| MagmaShard | Magma Shard | Rare | Reserved | A jagged fragment of magma energy. |
| ManaAmulet | Mana Amulet | Uncommon | Existing | A blue-gem amulet that grants 25 maximum mana while worn. |
| ManaCrystal | Mana Crystal | Rare | Reserved | A blue crystal filled with a quiet magical glow. |
| ManaPotion | Mana Potion | Common | Enemy loot | A bottle of concentrated blue magical essence. |
| ManaRegenPotion | Mana Regeneration Potion | Uncommon | Reserved | A blue tonic with slowly circling flecks of light. |
| ManaRing | Mana Ring | Rare | Reserved | A mana ring with carefully worked markings. |
| Milk | Milk | Common | Reserved | Fresh milk in a stoppered bottle. |
| MoonCharm | Moon Charm | Uncommon | Reserved | A small silver charm shaped like a crescent moon. |
| MoonCharmGold | Moon Charm Gold | Rare | Reserved | A golden crescent suspended from a fine loop. |
| Moonglow | Moonglow | Uncommon | Reserved | A blue flower with petals as pale as moonlight. |
| Mushroom | Mushroom | Common | Reserved | A stout mushroom with a broad cap. |
| MushroomGlowing | Mushroom Glowing | Uncommon | Reserved | A luminous mushroom from a dark, damp place. |
| MythrilArmor | Mythril Armor | Epic | Reserved | A suit of mythril plates. |
| MythrilGreaves | Mythril Greaves | Epic | Reserved | A pair of greaves made from mythril plates. |
| MythrilHelmet | Mythril Helmet | Epic | Reserved | A shaped helmet of mythril plates. |
| MythrilIngot | Mythril Ingot | Epic | Existing | A rare, glowing metal that hums with energy. |
| MythrilOre | Mythril Ore | Epic | Enemy loot | Faintly humming ore from the deep rock. |
| MythrilOreBlock | Mythril Ore Block | Epic | Reserved | A stone sample threaded with mythril ore. |
| MythrilPickaxe | Mythril Pickaxe | Epic | Existing | A powerful mythril pickaxe made for the deep rock. |
| MythrilShard | Mythril Shard | Epic | Reserved | A jagged fragment of mythril energy. |
| MythrilSword | Mythril Sword | Epic | Existing | A finely forged mythril blade with a quick swing. |
| NatureAmulet | Nature Amulet | Rare | Reserved | An amulet set around a nature centerpiece. |
| NatureOrb | Nature Orb | Rare | Reserved | A smooth orb holding a flicker of verdant energy. |
| NatureRing | Nature Ring | Rare | Reserved | A nature ring with carefully worked markings. |
| NatureTome | Nature Tome | Rare | Reserved | A bound volume of nature lore, covered in careful annotations. |
| NightOwlPotion | Night Owl Potion | Uncommon | Reserved | A dark blue brew with a faint silver shine. |
| ObsidianShield | Obsidian Shield | Rare | Reserved | A obsidian shield with a solid central boss. |
| ObsidianSkinPotion | Obsidian Skin Potion | Uncommon | Reserved | A black tonic with a glossy, stone-like sheen. |
| Pelt | Pelt | Common | Enemy loot | A thick animal hide with its fur intact. |
| Pineapple | Pineapple | Common | Reserved | A spiky tropical fruit with golden flesh. |
| PinkGel | Pink Gel | Uncommon | Enemy loot | Soft pink gel with an unusually elastic texture. |
| PixieDust | Pixie Dust | Rare | Reserved | Fine golden dust that glitters as it settles. |
| PlatinumArmor | Platinum Armor | Rare | Reserved | A suit of platinum plates. |
| PlatinumCoin | Platinum Coin | Rare | Reserved | A stamped platinum coin with a worn rim. |
| PlatinumGreaves | Platinum Greaves | Rare | Reserved | A pair of greaves made from platinum plates. |
| PlatinumHelmet | Platinum Helmet | Rare | Reserved | A shaped helmet of platinum plates. |
| PlatinumIngot | Platinum Ingot | Rare | Reserved | A refined bar of platinum, ready for a smith's work. |
| PlatinumOre | Platinum Ore | Rare | Reserved | Raw platinum ore with veins running through the stone. |
| PowerGlove | Power Glove | Rare | Reserved | A power glove with reinforced fingers. |
| Pumpkin | Pumpkin | Common | Reserved | A round orange pumpkin with a thick rind. |
| PurpleCape | Purple Cape | Uncommon | Reserved | A long purple cape fastened with a simple clasp. |
| PurpleCloth | Purple Cloth | Common | Enemy loot | A neatly folded piece of purple cloth. |
| PurpleGel | Purple Gel | Uncommon | Enemy loot | Dark violet gel flecked with strange residue. |
| RagePotion | Rage Potion | Rare | Reserved | A fiery red brew with a harsh, smoky scent. |
| RangerEmblem | Ranger Emblem | Rare | Reserved | An engraved emblem bearing the symbol of the ranger. |
| RareChest | Rare Chest | Rare | Existing | Holds 36 stacks. Iron-bound, and a row bigger than a basic chest. |
| RawMeat | Raw Meat | Common | Reserved | A fresh cut of uncooked meat. |
| RedCape | Red Cape | Uncommon | Reserved | A long red cape fastened with a simple clasp. |
| RedCloth | Red Cloth | Common | Reserved | A neatly folded piece of red cloth. |
| RedFeather | Red Feather | Uncommon | Reserved | A bright red feather with a dark quill. |
| RedScale | Red Scale | Uncommon | Reserved | A tough red scale from a creature's hide. |
| RegenerationPotion | Regeneration Potion | Uncommon | Reserved | A rose-colored brew with a slow, steady shimmer. |
| RegenerationRing | Regeneration Ring | Rare | Reserved | A regeneration ring with carefully worked markings. |
| RocketBoots | Rocket Boots | Epic | Reserved | A pair of rocket boots with reinforced soles. |
| Rope | Rope | Common | Reserved | Twisted cord for tying things together. |
| RottenChunk | Rotten Chunk | Uncommon | Enemy loot | A foul scrap of decaying flesh. |
| Ruby | Ruby | Rare | Reserved | A cut ruby with bright, glassy facets. |
| Sand | Sand | Common | Existing | Loose golden grains, useful for glassmaking and building. |
| Sandstone | Sandstone | Common | Existing | Compact sand turned to stone. |
| Sapphire | Sapphire | Rare | Reserved | A cut sapphire with bright, glassy facets. |
| ScrollChest | Scroll Chest | Rare | Existing | Select in your hotbar and click to open. Drops one random unowned ability scroll, visible only to you. |
| ShadowKey | Shadow Key | Epic | Reserved | A shadow key with an intricate, unfamiliar cut. |
| ShadowOrb | Shadow Orb | Epic | Reserved | A smooth orb holding a flicker of shadow energy. |
| ShadowTome | Shadow Tome | Epic | Reserved | A bound volume of shadow lore, covered in careful annotations. |
| ShinePotion | Shine Potion | Uncommon | Reserved | A golden brew that glows inside its bottle. |
| Shiverthorn | Shiverthorn | Uncommon | Enemy loot | A thorny plant dusted with frost. |
| SignusPouch | Signus Pouch | Epic | Reserved | A dark sealed pouch bearing the mark of Signus. |
| SignusSigil | Signus Sigil | Epic | Reserved | An ominous sigil bearing the mark of Signus. |
| Silk | Silk | Uncommon | Enemy loot | Smooth thread gathered from tangled spider webs. |
| SilverArmor | Silver Armor | Uncommon | Reserved | A suit of silver plates. |
| SilverCoin | Silver Coin | Uncommon | Reserved | A stamped silver coin with a worn rim. |
| SilverGreaves | Silver Greaves | Uncommon | Reserved | A pair of greaves made from silver plates. |
| SilverHelmet | Silver Helmet | Uncommon | Reserved | A shaped helmet of silver plates. |
| SilverIngot | Silver Ingot | Uncommon | Reserved | A refined bar of silver, ready for a smith's work. |
| SilverOre | Silver Ore | Uncommon | Reserved | Raw silver ore with veins running through the stone. |
| SilverTrophy | Silver Trophy | Rare | Reserved | A polished silver trophy on a solid pedestal. |
| Skull | Skull | Uncommon | Reserved | A bleached skull with empty, watchful sockets. |
| SkullCrimson | Skull Crimson | Uncommon | Reserved | A red skull with deep cracks across its brow. |
| SkullFrost | Skull Frost | Uncommon | Reserved | A pale skull crusted with frost. |
| SkullObsidian | Skull Obsidian | Uncommon | Reserved | A skull carved from glossy black stone. |
| SkybreakerPick | Skybreaker Pick | Legendary | Existing | A celestial pickaxe with exceptional mining speed and power. |
| SlimePouch | Slime Pouch | Epic | Reserved | A sticky pouch marked with a slime emblem. |
| Snow | Snow | Common | Enemy loot | Packed snow block. |
| SnowPelt | Snow Pelt | Uncommon | Reserved | A pale pelt that kept its owner warm in the snow. |
| Soda | Soda | Common | Reserved | A bright, fizzy bottled drink. |
| SorcererEmblem | Sorcerer Emblem | Rare | Reserved | An engraved emblem bearing the symbol of the sorcerer. |
| SoulofFlight | Soul of Flight | Rare | Reserved | A restless wisp that never quite settles. |
| SoulofFright | Soul of Fright | Epic | Enemy loot | A shivering spirit fragment steeped in dread. |
| SoulofLight | Soul of Light | Rare | Reserved | A radiant wisp of life, bright even in shadow. |
| SoulofMight | Soul of Might | Epic | Reserved | A dense spirit fragment left by an immense creature. |
| SoulofNight | Soul of Night | Rare | Reserved | A dark wisp that curls away from the light. |
| SoulofSight | Soul of Sight | Epic | Enemy loot | A watchful spirit fragment with a shifting inner glow. |
| Soup | Soup | Common | Reserved | A warm bowl of simple vegetable broth. |
| SpeedBoots | Speed Boots | Uncommon | Reserved | A pair of speed boots with reinforced soles. |
| SpellRing | Spell Ring | Rare | Existing | A violet-gem ring that increases ability damage by 15% while worn. |
| SpelunkerPotion | Spelunker Potion | Uncommon | Reserved | A golden tonic with glittering mineral flecks. |
| Spores | Spores | Uncommon | Reserved | A pouch of tiny spores gathered from damp growth. |
| Stew | Stew | Common | Reserved | A hearty bowl of meat and vegetables. |
| Stick | Stick | Common | Enemy loot | A straight wooden handle used in tools and other simple crafts. |
| Stinger | Stinger | Uncommon | Enemy loot | A barbed insect stinger with a hollow tip. |
| Stone | Stone | Common | Existing | Solid stone for basic tools, furnaces, and building. |
| StoneBricks | Stone Bricks | Common | Existing | Cut and squared. For building something that lasts. |
| StonePickaxe | Stone Pickaxe | Common | Existing | A heavy stone pickaxe that mines faster than copper. |
| StoneSword | Stone Sword | Common | Existing | A rough stone blade with a heavy edge. |
| StrengthPotion | Strength Potion | Uncommon | Reserved | A dark red tonic with a sharp, earthy scent. |
| String | String | Common | Reserved | A length of fine thread for binding small components. |
| SummonerEmblem | Summoner Emblem | Rare | Reserved | An engraved emblem bearing the symbol of the summoner. |
| SummoningPotion | Summoning Potion | Rare | Reserved | A cloudy purple brew with shifting shapes inside. |
| SunCharm | Sun Charm | Uncommon | Reserved | A golden charm with rays around its center. |
| SuperHealingPotion | Super Healing Potion | Epic | Reserved | A brilliant red tonic in an ornate bottle. |
| SuspiciousEye | Suspicious Eye | Epic | Reserved | An unsettling eye that seems to follow movement. |
| SwiftnessPotion | Swiftness Potion | Uncommon | Reserved | A light blue brew with bubbles that race to the surface. |
| Tea | Tea | Common | Reserved | A fragrant brew of steeped leaves. |
| TestAxe | Test Axe | Unobtainable | Existing | A developer axe for testing tree harvesting. Not part of normal progression. |
| TestPickaxe | Test Pickaxe | Unobtainable | Existing | A developer pickaxe for rapid mining tests. Not part of normal progression. |
| TestSword | Test Sword | Unobtainable | Existing | A developer blade for testing combat. Not part of normal progression. |
| ThornsPotion | Thorns Potion | Uncommon | Reserved | A green tonic steeped with thorny stems. |
| Thunderveil | Thunderveil | Legendary | Existing | A broad, thunder-themed sword with a formidable edge. |
| TinGreaves | Tin Greaves | Common | Reserved | A pair of greaves made from tin plates. |
| TinHelmet | Tin Helmet | Common | Reserved | A shaped helmet of tin plates. |
| TinIngot | Tin Ingot | Common | Reserved | A refined bar of tin, ready for a smith's work. |
| TinOre | Tin Ore | Common | Reserved | Raw tin ore with veins running through the stone. |
| TitanGlove | Titan Glove | Epic | Reserved | A titan glove with reinforced fingers. |
| Topaz | Topaz | Rare | Reserved | A cut topaz with bright, glassy facets. |
| TurtleShell | Turtle Shell | Uncommon | Reserved | A broad shell covered in overlapping plates. |
| VenomFlask | Venom Flask | Rare | Reserved | A sealed flask of cloudy venom. |
| VenomSac | Venom Sac | Uncommon | Enemy loot | A fragile sac of venom. Handle it with care. |
| VitalityAmulet | Vitality Amulet | Uncommon | Existing | A red-gem amulet that grants 25 maximum health while worn. |
| VoidAmulet | Void Amulet | Legendary | Reserved | An amulet set around a void centerpiece. |
| VoidArmor | Void Armor | Legendary | Reserved | A suit of void plates. |
| VoidCore | Void Core | Legendary | Existing | Condensed void crystals used to forge a void pickaxe. |
| VoidCrystal | Void Crystal | Epic | Enemy loot | A dark crystal found in the deepest rock and carried by the Blightborer. |
| VoidGreaves | Void Greaves | Legendary | Reserved | A pair of greaves made from void plates. |
| VoidHelmet | Void Helmet | Legendary | Reserved | A shaped helmet of void plates. |
| VoidIngot | Void Ingot | Legendary | Reserved | A refined bar of void, ready for a smith's work. |
| VoidLens | Void Lens | Epic | Enemy loot | An eerie lens with a depth that is difficult to judge. |
| VoidOre | Void Ore | Legendary | Reserved | Raw void ore with veins running through the stone. |
| VoidOreBlock | Void Ore Block | Legendary | Reserved | A stone sample threaded with void ore. |
| VoidPickaxe | Void Pickaxe | Legendary | Existing | A pickaxe shaped around void crystals, built for the toughest deposits. |
| VoidReaver | Void Reaver | Legendary | Existing | A dark longsword with a brutal cutting edge. |
| VoidRing | Void Ring | Legendary | Reserved | A void ring with carefully worked markings. |
| VoidTome | Void Tome | Legendary | Reserved | A bound volume of void lore, covered in careful annotations. |
| WarmthPotion | Warmth Potion | Uncommon | Reserved | An orange tonic that warms the glass around it. |
| WarriorEmblem | Warrior Emblem | Rare | Reserved | An engraved emblem bearing the symbol of the warrior. |
| WaterBottle | Water Bottle | Common | Reserved | A clear glass bottle filled with water. |
| WaterOrb | Water Orb | Rare | Reserved | A smooth orb holding a flicker of water energy. |
| WaterTome | Water Tome | Rare | Reserved | A bound volume of water lore, covered in careful annotations. |
| Waterleaf | Waterleaf | Uncommon | Reserved | A succulent herb with water-heavy leaves. |
| Watermelon | Watermelon | Common | Reserved | A striped melon with sweet red flesh. |
| WhitePumpkin | White Pumpkin | Common | Reserved | A pale pumpkin with a firm white rind. |
| Wine | Wine | Common | Reserved | A bottle of deep red fruit wine. |
| Wood | Wood | Common | Enemy loot | A length of harvested timber, ready to cut into planks. |
| WoodAxe | Wood Axe | Common | Existing | A crude axe for chopping down trees. |
| WoodCrate | Wood Crate | Common | Reserved | A sealed wooden crate with reinforced corners. |
| WoodPickaxe | Wood Pickaxe | Common | Existing | A crude pickaxe. It will break stone, slowly. |
| WoodPlank | Wood Plank | Common | Existing | Sawn wooden planks for building and basic crafting. |
| WoodShield | Wood Shield | Common | Reserved | A wood shield with a solid central boss. |
| WoodSword | Wood Sword | Common | Existing | A simple wooden blade for a beginner's first fights. |
| Wool | Wool | Common | Enemy loot | A soft bundle of wool from a shaggy coat. |
| WrathPotion | Wrath Potion | Rare | Reserved | A deep violet tonic with restless swirls. |
