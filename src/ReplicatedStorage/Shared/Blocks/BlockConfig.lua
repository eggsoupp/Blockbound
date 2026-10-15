--[[
	BlockConfig

	Block-level questions ItemDefinitions cannot answer: what a block drops, how
	long it takes to break, whether it can be broken, and what a generated
	stand-in part should look like when TerrainAssets.Blocks has none authored.

	ADDING A BLOCK
	  1. ItemDefinitions entry with classification "Block".
	  2. A part of the same name in TerrainAssets.Blocks, or a Generated entry.
	  3. An Overrides entry only if it drops something other than itself.

	Ores are not listed here; OreConfig registers its own through
	registerGenerated / registerBlock.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local BlockConfig = {}

--[[
	What a block costs to break when nothing says otherwise, in seconds, with a
	CopperPickaxe (ItemDefinitions.miningSpeed 1.0). Ordinary stone is 1.5s.

	0.35 before, against block miningTimes of 50-150ms - so the whole world
	broke faster than the 0.35 fallback and every pickaxe from wood upward
	mined everything in roughly one frame. That is what made mining feel free:
	not the tools, the hardness.
]]
BlockConfig.DefaultBreakSeconds = 1.0

--[[
	Clamped so a bad config cannot lock a player into an eight-minute mine.

	The FLOOR is not just a safety rail - it is what makes TestPickaxe work.
	At miningSpeed 40 every ordinary block divides down past it and lands here,
	so the test tool is one-tick on anything that is not deep ore, whatever the
	hardness table says. Do not raise it without checking that.
]]
BlockConfig.MinBreakSeconds = 0.05
BlockConfig.MaxBreakSeconds = 8

--[[
	The pickaxe miningPower a block asks for when nothing says otherwise, and
	the power a pickaxe has when its definition does not say. Every pickaxe
	mines ordinary ground; ores ask for more (OreConfig `power`).
]]
BlockConfig.DefaultRequiredPower = 1
BlockConfig.DefaultPickaxePower = 1

--[[
	drop          item granted on break; nil means the block's own name, false
	              means nothing.
	breakSeconds  overrides the item's miningTime.
	unbreakable   refuse mining entirely.
	power         the pickaxe miningPower needed to break it.
]]
BlockConfig.Overrides = {
	Water = { drop = false, unbreakable = true },
	Bedrock = { drop = false, unbreakable = true },
}

-- Built at run time when TerrainAssets.Blocks has nothing under that name.
-- Authored assets always win, so dropping a real part in later replaces these.
BlockConfig.Generated = {
	Bedrock = {
		color = Color3.fromRGB(38, 38, 42),
		material = Enum.Material.Slate,
	},
	StoneBricks = {
		color = Color3.fromRGB(138, 138, 132),
		material = Enum.Material.Brick,
	},
	MagmaBrick = {
		color = Color3.fromRGB(178, 74, 44),
		material = Enum.Material.CrackedLava,
	},
	Water = {
		color = Color3.fromRGB(38, 92, 148),
		material = Enum.Material.Water,
		transparency = 0.35,
	},
}

--[[
	Blocks that are not ordinary solid cubes.

	Applied to every rendered part of that name, authored or generated, because
	the renderer pools parts per block name and would otherwise stamp the usual
	solid-opaque defaults over whatever the template said.

	  collides     false for something you pass through
	  transparency 0 unless stated
	  query        false to make the mouse ray ignore it, so aiming at water
	               targets the bed underneath rather than the surface

	Water is the whole reason this exists: it has to be see-through so the bed
	reads through it, non-solid so you wade rather than walk on it, and
	invisible to the cursor so mining still works at a shoreline.
]]
BlockConfig.Surfaces = {
	Water = {
		collides = false,
		transparency = 0.35,
		query = false,
	},
}

-- The rendering properties for a block name, or nil for an ordinary solid one.
function BlockConfig.surfaceFor(blockName)
	return BlockConfig.Surfaces[blockName]
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

function BlockConfig.getDrop(blockName)
	if type(blockName) ~= "string" or blockName == "" then
		return nil
	end

	local override = BlockConfig.Overrides[blockName]
	if override then
		if override.drop == false then
			return nil
		end
		if type(override.drop) == "string" then
			return override.drop
		end
	end

	-- Identity by default, but only if the item exists: mining must not hand
	-- out something the inventory cannot describe.
	if ItemDefinitions[blockName] then
		return blockName
	end

	return nil
end

function BlockConfig.isUnbreakable(blockName)
	local override = BlockConfig.Overrides[blockName]
	return override ~= nil and override.unbreakable == true
end

-- The miningPower a block asks of a pickaxe.
function BlockConfig.getRequiredPower(blockName)
	local override = BlockConfig.Overrides[blockName]
	local power = override and tonumber(override.power)
	return power or BlockConfig.DefaultRequiredPower
end

-- The miningPower a pickaxe definition carries.
function BlockConfig.pickaxePower(definition)
	local power = definition and tonumber(definition.miningPower)
	return power or BlockConfig.DefaultPickaxePower
end

--[[
	Whether this pickaxe is strong enough for this block. Strength only -
	unbreakable blocks are asked about separately. MiningServer decides with
	this; MiningClient asks the same question only to colour its outline.
]]
function BlockConfig.canMine(blockName, pickaxeDefinition)
	return BlockConfig.pickaxePower(pickaxeDefinition) >= BlockConfig.getRequiredPower(blockName)
end

-- ItemDefinitions stores miningTime in MILLISECONDS; converted here so no call
-- site has to remember to.
function BlockConfig.getBreakSeconds(blockName)
	local seconds

	local override = BlockConfig.Overrides[blockName]
	if override and type(override.breakSeconds) == "number" then
		seconds = override.breakSeconds
	else
		local def = ItemDefinitions[blockName]
		local milliseconds = def and tonumber(def.miningTime)
		seconds = if milliseconds then milliseconds / 1000 else BlockConfig.DefaultBreakSeconds
	end

	return math.clamp(seconds, BlockConfig.MinBreakSeconds, BlockConfig.MaxBreakSeconds)
end

function BlockConfig.isPlaceable(itemName)
	local def = ItemDefinitions[itemName]
	return def ~= nil and def.classification == "Block"
end

function BlockConfig.registerGenerated(blockName, description)
	if type(blockName) == "string" and type(description) == "table" then
		BlockConfig.Generated[blockName] = description
	end
end

-- Lets OreConfig contribute block facts (CoalOre drops Coal, and is harder
-- than the rock around it) without BlockConfig knowing what an ore is.
-- Hand-written Overrides entries win, so nothing is quietly replaced.
function BlockConfig.registerBlock(blockName, facts)
	if type(blockName) ~= "string" or type(facts) ~= "table" then
		return
	end

	local override = BlockConfig.Overrides[blockName]
	if not override then
		override = {}
		BlockConfig.Overrides[blockName] = override
	end

	if override.drop == nil and facts.drop ~= nil then
		override.drop = facts.drop
	end
	if override.breakSeconds == nil and facts.breakSeconds ~= nil then
		override.breakSeconds = facts.breakSeconds
	end
	if override.unbreakable == nil and facts.unbreakable ~= nil then
		override.unbreakable = facts.unbreakable
	end
	if override.power == nil and facts.power ~= nil then
		override.power = facts.power
	end
end

return BlockConfig
