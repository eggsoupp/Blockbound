--[[
	OreConfig

	Every ore in the game, and the only place any of them is described.

	The generator never names an ore. It asks OreRegistry "what, if anything, is
	at this block?" and OreRegistry answers from this table, so adding an ore is
	one entry here plus one ItemDefinitions entry - no generator, mining,
	inventory or GUI change.

	===========================================================================
	HOW AN ORE IS DISTRIBUTED
	===========================================================================

	Two deterministic hashes per ore per block, both derived from the world seed:

	  1. VEIN CELL. Space is diced into cubes veinSize blocks on a side. A cell
	     "contains" this ore when its hash falls under cellChance scaled by the
	     depth curve. This is what makes ore appear in clumps rather than as
	     evenly sprinkled single blocks.

	  2. FILL. Inside a chosen cell, each block independently passes with
	     probability fillRatio. This gives veins ragged edges instead of solid
	     cubes.

	So the fraction of eligible stone that becomes this ore, at its peak depth,
	is roughly cellChance * fillRatio. That product is the number to reason
	about when tuning; the comment on each entry states it.

	Nothing is precomputed or stored: the answer for a block is a pure function
	of (position, world seed), which is what makes ore identical every time a
	chunk is streamed back in and consistent across chunk borders.

	===========================================================================
	FIELD REFERENCE
	===========================================================================

	  id           unique. Also the model/log name.
	  block        block name written into the world. Needs either an authored
	               part in TerrainAssets.Blocks or an `appearance` below.
	  item         item granted when mined. Must exist in ItemDefinitions.
	  minDepth     shallowest depth (blocks below the surface) it can appear.
	  peakDepth    depth at which it is at full cellChance. Between minDepth and
	               peakDepth the chance ramps up linearly, which is what makes an
	               ore "start appearing" rather than switch on.
	  maxDepth     deepest it appears. Past this it is gone.
	  cellChance   vein-cell probability at peak depth.
	  veinSize     vein cell edge, in blocks. Bigger = fewer, chunkier veins.
	  fillRatio    fraction of blocks inside a chosen cell that become ore.
	  breakSeconds how long it takes to mine with a CopperPickaxe, the speed-1.0
	               reference tool. Registered with BlockConfig at init, so mining
	               reads it the same way it reads any other block hardness.

	               Keep every ore ABOVE the 1.5s of the stone hosting it, and
	               scale with depth: each of these is about two to two and a half
	               seconds with the pickaxe tier that can realistically reach that
	               depth, which is what keeps the progression flat in FEEL while
	               the numbers climb. Void at 8.00 is at BlockConfig.MaxBreakSeconds
	               deliberately - with a wooden pickaxe it clamps, and it should.
	  priority     higher wins when two ores claim the same block. Keep rare ores
	               above common ones so a mythril vein is not eaten by coal.
	  hosts        set of base block names it may replace. Defaults to the
	               deepest stratum (Stone).
	  appearance   used to build a stand-in part when TerrainAssets.Blocks has no
	               authored part of that name. Authored parts always win.

	===========================================================================
	ADDING AN ORE
	===========================================================================
	  1. Add a row to Definitions and its id to Order.
	  2. Add its `item` to ReplicatedStorage.ItemDefinitions.
	  3. Optionally add a smelting/crafting recipe in CraftingRecipes.
	That is the whole procedure.
]]

local OreConfig = {}

-- Master switch, and one dial for "more/less ore everywhere".
OreConfig.Enabled = true
OreConfig.GlobalDensityMultiplier = 1.0

OreConfig.Definitions = {
	Coal = {
		id = "Coal",
		block = "CoalOre",
		item = "Coal",
		minDepth = 4,
		peakDepth = 22,
		maxDepth = 120,
		cellChance = 0.045, -- x0.58 fill ~= 2.6% of stone in band
		veinSize = 3,
		fillRatio = 0.58,
		breakSeconds = 2.00,
		priority = 10,
		appearance = { color = Color3.fromRGB(58, 58, 62), material = Enum.Material.Slate },
	},

	Copper = {
		id = "Copper",
		block = "CopperOre",
		item = "CopperOre",
		minDepth = 8,
		peakDepth = 34,
		maxDepth = 110,
		cellChance = 0.036, -- ~2.0%
		veinSize = 3,
		fillRatio = 0.55,
		breakSeconds = 2.40,
		priority = 20,
		appearance = { color = Color3.fromRGB(196, 118, 66), material = Enum.Material.Metal },
	},

	Iron = {
		id = "Iron",
		block = "IronOre",
		item = "IronOre",
		minDepth = 24,
		peakDepth = 66,
		maxDepth = 165,
		cellChance = 0.024, -- ~1.25%
		veinSize = 3,
		fillRatio = 0.52,
		breakSeconds = 3.20,
		priority = 30,
		appearance = { color = Color3.fromRGB(206, 190, 176), material = Enum.Material.Metal },
	},

	Gold = {
		id = "Gold",
		block = "GoldOre",
		item = "GoldOre",
		minDepth = 72,
		peakDepth = 118,
		maxDepth = 190,
		cellChance = 0.008, -- ~0.36%
		veinSize = 2,
		fillRatio = 0.45,
		breakSeconds = 4.20,
		priority = 40,
		appearance = { color = Color3.fromRGB(226, 184, 62), material = Enum.Material.Metal },
	},

	Magma = {
		id = "Magma",
		block = "MagmaOre",
		item = "MagmaOre",
		minDepth = 104,
		peakDepth = 136,
		maxDepth = 190,
		cellChance = 0.006, -- ~0.25%
		veinSize = 2,
		fillRatio = 0.42,
		breakSeconds = 5.50,
		priority = 50,
		appearance = { color = Color3.fromRGB(214, 82, 38), material = Enum.Material.Neon },
	},

	Mythril = {
		id = "Mythril",
		block = "MythrilOre",
		item = "MythrilOre",
		minDepth = 128,
		peakDepth = 152,
		maxDepth = 190,
		cellChance = 0.007, -- ~0.28% of stone in band
		veinSize = 2,
		fillRatio = 0.40,
		breakSeconds = 6.50,
		priority = 60,
		appearance = { color = Color3.fromRGB(104, 214, 206), material = Enum.Material.Foil },
	},

	Void = {
		id = "Void",
		block = "VoidOre",
		item = "VoidCrystal",
		minDepth = 152,
		peakDepth = 168,
		maxDepth = 190,
		cellChance = 0.009, -- ~0.29% inside its band; still a genuine find
		veinSize = 2,
		fillRatio = 0.32,
		breakSeconds = 8.00,
		priority = 70,
		appearance = { color = Color3.fromRGB(96, 52, 148), material = Enum.Material.Neon },
	},
}

-- Evaluation order. Sorted rarest-first at init from `priority`, so this is
-- only the set of ores that exist, not a precedence list.
OreConfig.Order = { "Coal", "Copper", "Iron", "Gold", "Magma", "Mythril", "Void" }

--[[
	Set of ore ids allowed to GENERATE, or nil for all of them. Ores left out
	are still registered as blocks - one carried in from elsewhere still mines
	and drops normally - they just never appear in the ground.

	nil in the open world. The Island place sets it from IslandConfig.Ores, so
	rare ores stay something you go out into the world for.
]]
OreConfig.GenerateOnly = nil

do
	local PlaceConfig = require(script.Parent.Parent:WaitForChild("PlaceConfig"))
	if PlaceConfig.isIsland() then
		OreConfig.GenerateOnly = require(script.Parent:WaitForChild("IslandConfig")).Ores
	end
end

--[[
	Structural sanity check. Runs at init.
]]
function OreConfig.validate()
	local seenBlock = {}

	for _, name in ipairs(OreConfig.Order) do
		local def = OreConfig.Definitions[name]
		local label = string.format("[OreConfig] '%s'", name)

		assert(def, label .. " is in Order but has no definition")
		assert(type(def.block) == "string" and def.block ~= "", label .. " needs a block name")
		assert(type(def.item) == "string" and def.item ~= "", label .. " needs an item name")
		assert(not seenBlock[def.block], label .. " reuses block name " .. tostring(def.block))
		seenBlock[def.block] = true

		assert(
			type(def.minDepth) == "number" and type(def.maxDepth) == "number"
				and def.maxDepth > def.minDepth,
			label .. " needs minDepth < maxDepth"
		)
		assert(
			type(def.peakDepth) == "number"
				and def.peakDepth >= def.minDepth and def.peakDepth <= def.maxDepth,
			label .. " needs minDepth <= peakDepth <= maxDepth"
		)
		assert(
			type(def.cellChance) == "number" and def.cellChance > 0 and def.cellChance <= 1,
			label .. " needs a cellChance in (0, 1]"
		)
		assert(
			type(def.fillRatio) == "number" and def.fillRatio > 0 and def.fillRatio <= 1,
			label .. " needs a fillRatio in (0, 1]"
		)
		assert(
			type(def.veinSize) == "number" and def.veinSize >= 1,
			label .. " needs a veinSize of at least 1"
		)
	end

	for name in pairs(OreConfig.Definitions) do
		if not table.find(OreConfig.Order, name) then
			warn(string.format(
				"[OreConfig] '%s' is defined but missing from Order, so it will never generate.",
				name
			))
		end
	end
end

return OreConfig
