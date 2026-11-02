--[[
	QuestBook

	The quest tree behind the Tab menu's QUESTS page: every quest, what it
	asks, what it needs first, and where it sits on the map. The server
	(ServerScriptService.QuestService) decides when one is complete and saves
	it; the client (Shared.UI.QuestWindow) draws the tree and the progress.

	A QUEST

	  id        stable key; it is what gets saved, so never rename one
	  title     a name, not an instruction
	  text      a line of flavour that hints rather than explains
	  icon      an item whose picture stands for it
	  at        { column, row } on the map
	  needs     quests that must be complete before this one can be
	  tasks     ALL must be met at once:
	              { item = "CopperOre", count = 1 }   carried in the bag
	              { items = { "A", "B" } }            any one of them
	                                                  (`label` names the set)
	              { kill = "SlimeEmperor", count = 1 } killed, ever
	              { discover = 10 }                   bestiary entries
	              { slay = 25 }                       kills of anything

	Kills and discoveries come from the bestiary, so they count from whenever
	the bestiary started counting. Items are checked in the bag as it is; once
	a quest is complete it stays complete, whatever is spent afterwards. A
	quest completed proves the ones it needs (see advance).

	The map reads left to right: tools along the middle, curiosities above,
	fighting and bosses below. Lanes cross where one craft feeds another.
]]

local QuestBook = {}

QuestBook.Quests = {
	-- The trunk.
	{ id = "first_light", title = "First Light", icon = "Wood", at = { 0, 0 },
		text = "Every world starts with something to hold.",
		tasks = { { item = "Wood" } } },
	{ id = "workbench", title = "Workbench", icon = "CraftingTable", at = { 1, 0 }, needs = { "first_light" },
		text = "Shape the wood into something that shapes things.",
		tasks = { { item = "CraftingTable" } } },
	{ id = "splinters", title = "Splinters", icon = "WoodPickaxe", at = { 2, 0 }, needs = { "workbench" },
		text = "A crude edge, but an edge.",
		tasks = { { item = "WoodPickaxe" } } },
	{ id = "stone_age", title = "Stone Age", icon = "Cobblestone", at = { 3, 0 }, needs = { "splinters" },
		text = "The ground is harder than it looks. So are you.",
		tasks = { { item = "StonePickaxe" } } },
	{ id = "copper_vein", title = "Copper Vein", icon = "CopperOre", at = { 4, 0 }, needs = { "stone_age" },
		text = "A warm colour where there should only be grey.",
		tasks = { { item = "CopperOre" } } },
	{ id = "smelter", title = "Smelter", icon = "CopperIngot", at = { 5, 0 }, needs = { "copper_vein", "embers", "heat" },
		text = "Rock goes in. Something better comes out.",
		tasks = { { item = "CopperIngot" } } },
	{ id = "bright_edge", title = "Bright Edge", icon = "CopperPickaxe", at = { 6, 0 }, needs = { "smelter" },
		text = "Deeper rock has been waiting for this.",
		tasks = { { item = "CopperPickaxe" } } },
	{ id = "iron_will", title = "Iron Will", icon = "IronOre", at = { 7, 0 }, needs = { "bright_edge" },
		text = "Further down, the stone turns stubborn.",
		tasks = { { item = "IronOre" } } },
	{ id = "anvil", title = "Anvil", icon = "Anvil", at = { 8, 0 }, needs = { "iron_will" },
		text = "Some things can only be made by hitting them.",
		tasks = { { item = "Anvil" } } },
	{ id = "tempered", title = "Tempered", icon = "IronPickaxe", at = { 9, 0 }, needs = { "anvil" },
		text = "Heavier in the hand, lighter on the arm.",
		tasks = { { item = "IronPickaxe" } } },
	{ id = "glint", title = "Glint", icon = "GoldOre", at = { 10, 0 }, needs = { "tempered" },
		text = "Far below, something catches the light.",
		tasks = { { item = "GoldOre" } } },
	{ id = "gilded", title = "Gilded", icon = "GoldPickaxe", at = { 11, 0 }, needs = { "glint" },
		text = "Soft metal, sharp results.",
		tasks = { { item = "GoldPickaxe" } } },
	{ id = "deep_blue", title = "Deep Blue", icon = "MythrilOre", at = { 12, 0 }, needs = { "gilded" },
		text = "It glows. Rock should not glow.",
		tasks = { { item = "MythrilOre" } } },
	{ id = "mythril", title = "Mythril", icon = "MythrilPickaxe", at = { 13, 0 }, needs = { "deep_blue", "arcane_forge" },
		text = "Old metal, older fire.",
		tasks = { { item = "MythrilPickaxe" } } },
	{ id = "the_void", title = "The Void", icon = "VoidCrystal", at = { 14, 0 }, needs = { "mythril" },
		text = "At the bottom of everything, nothing. Take some.",
		tasks = { { item = "VoidCrystal" } } },
	{ id = "abyssal", title = "Abyssal", icon = "VoidPickaxe", at = { 15, 0 }, needs = { "the_void", "enchanting" },
		text = "A tool that remembers where it came from.",
		tasks = { { item = "VoidPickaxe" } } },

	-- Fire and making, just off the trunk.
	{ id = "embers", title = "Embers", icon = "Coal", at = { 4, -1 }, needs = { "stone_age" },
		text = "Black stone that burns.",
		tasks = { { item = "Coal" } } },
	{ id = "heat", title = "Heat", icon = "Furnace", at = { 4, 1 }, needs = { "stone_age" },
		text = "Stone, stacked so it holds a fire.",
		tasks = { { item = "Furnace" } } },
	{ id = "hoard", title = "Hoard", icon = "BasicChest", at = { 2, 1 }, needs = { "workbench" },
		text = "Somewhere to put what you cannot carry.",
		tasks = { { item = "BasicChest" } } },
	{ id = "arcane_forge", title = "Arcane Forge", icon = "ArcaneForge", at = { 11, 1 }, needs = { "glint" },
		text = "A forge that burns more than coal.",
		tasks = { { item = "ArcaneForge" } } },
	{ id = "enchanting", title = "Enchanting", icon = "EnchantingTable", at = { 13, 1 }, needs = { "mythril" },
		text = "Write on the world, and it listens.",
		tasks = { { item = "EnchantingTable" } } },

	-- Glass and remedies.
	{ id = "glass", title = "Glass", icon = "Bottle", at = { 6, -1 }, needs = { "heat" },
		text = "Sand, given patience and a fire.",
		tasks = { { item = "Bottle" } } },
	{ id = "brewer", title = "Brewer", icon = "AlchemyBench", at = { 7, -1 }, needs = { "glass" },
		text = "A bench for things that bubble.",
		tasks = { { item = "AlchemyBench" } } },
	{ id = "remedy", title = "Remedy", icon = "HealthPotion", at = { 8, -1 }, needs = { "brewer" },
		text = "Bitter, red and worth it.",
		tasks = { { item = "HealthPotion" } } },
	{ id = "essence", title = "Essence", icon = "EssenceShard", at = { 13, -1 }, needs = { "deep_blue", "brewer" },
		text = "Mythril, dissolved into something stranger.",
		tasks = { { item = "EssenceShard" } } },
	{ id = "wellspring", title = "Wellspring", icon = "ManaPotion", at = { 14, -1 }, needs = { "essence" },
		text = "Power, bottled.",
		tasks = { { item = "ManaPotion" } } },

	-- The bestiary, along the top.
	{ id = "naturalist", title = "Naturalist", icon = "Herb", at = { 1, -3 }, needs = { "first_light" },
		text = "Look closer at what moves.",
		tasks = { { discover = 5 } } },
	{ id = "field_notes", title = "Field Notes", icon = "Herb", at = { 3, -3 }, needs = { "naturalist" },
		text = "Every land keeps its own.",
		tasks = { { discover = 15 } } },
	{ id = "zoologist", title = "Zoologist", icon = "Herb", at = { 5, -3 }, needs = { "field_notes" },
		text = "Most things here want to eat you. Take notes anyway.",
		tasks = { { discover = 30 } } },
	{ id = "menagerie", title = "Menagerie", icon = "Herb", at = { 7, -3 }, needs = { "zoologist" },
		text = "Nothing left unseen.",
		tasks = { { discover = 45 } } },

	-- Fighting.
	{ id = "first_blood", title = "First Blood", icon = "WoodSword", at = { 1, 2 }, needs = { "first_light" },
		text = "It started it.",
		tasks = { { slay = 1 } } },
	{ id = "sharpened", title = "Sharpened", icon = "CopperSword", at = { 3, 2 }, needs = { "first_blood", "splinters" },
		text = "A blade worth the name.",
		tasks = { { label = "Any blade of stone or better", items = { "CopperSword", "StoneSword", "IronSword", "GoldSword", "MythrilSword" } } } },
	{ id = "hunter", title = "Hunter", icon = "Leather", at = { 4, 3 }, needs = { "first_blood" },
		text = "Twenty-five fewer things in the dark.",
		tasks = { { slay = 25 } } },
	{ id = "hide", title = "Hide", icon = "LeatherArmor", at = { 5, 3 }, needs = { "hunter" },
		text = "Wear what you have earned.",
		tasks = { { item = "LeatherArmor" } } },
	{ id = "bronze_arm", title = "Bright Blade", icon = "CopperSword", at = { 6, 2 }, needs = { "sharpened", "smelter" },
		text = "It even shines in the dark.",
		tasks = { { item = "CopperSword" } } },
	{ id = "slayer", title = "Slayer", icon = "IronSword", at = { 7, 3 }, needs = { "hunter" },
		text = "They have started to remember you.",
		tasks = { { slay = 250 } } },
	{ id = "steel_resolve", title = "Steel Resolve", icon = "IronSword", at = { 9, 2 }, needs = { "anvil", "bronze_arm" },
		text = "Hit harder. Get hit less.",
		tasks = { { item = "IronSword" } } },
	{ id = "plated", title = "Plated", icon = "IronArmor", at = { 9, 3 }, needs = { "anvil", "hide" },
		text = "Walk into it instead of away.",
		tasks = { { item = "IronArmor" } } },
	{ id = "golden_blade", title = "Golden Blade", icon = "GoldSword", at = { 11, 2 }, needs = { "steel_resolve", "glint" },
		text = "Heavy, bright and unforgiving.",
		tasks = { { item = "GoldSword" } } },
	{ id = "mythril_blade", title = "Mythril Blade", icon = "MythrilSword", at = { 14, 2 }, needs = { "golden_blade", "mythril" },
		text = "It hums when something is near.",
		tasks = { { item = "MythrilSword" } } },

	-- Bosses, along the bottom.
	{ id = "ooze", title = "Ooze", icon = "Gel", at = { 3, 4 }, needs = { "first_blood" },
		text = "Slimes leave something behind. Keep it.",
		tasks = { { item = "Gel", count = 25 } } },
	{ id = "crown", title = "A Crown of Gel", icon = "GelatinousCrown", at = { 9, 4 }, needs = { "ooze", "anvil" },
		text = "Something wants it back. Offer it where the old stones stand.",
		tasks = { { item = "GelatinousCrown" } } },
	{ id = "regicide", title = "Regicide", icon = "GelatinousCrown", at = { 10, 4 }, needs = { "crown" },
		text = "Every kingdom falls eventually.",
		tasks = { { kill = "SlimeEmperor" } } },
	{ id = "unblinking", title = "Unblinking", icon = "EssenceShard", at = { 11, 4 }, needs = { "regicide" },
		text = "Something watches the night. Close its eye.",
		tasks = { { kill = "AllSeeingEye" } } },
	{ id = "eclipse", title = "Eclipse", icon = "MythrilIngot", at = { 12, 4 }, needs = { "unblinking" },
		text = "When the sun goes out, it comes down.",
		tasks = { { kill = "Signus" } } },
	{ id = "rot_below", title = "Rot Below", icon = "VoidCrystal", at = { 13, 4 }, needs = { "eclipse" },
		text = "The ground is hollow, and the hollow is hungry.",
		tasks = { { kill = "Blightborer" } } },
}

QuestBook.byId = {}
for order, quest in ipairs(QuestBook.Quests) do
	quest.order = order
	quest.needs = quest.needs or {}
	QuestBook.byId[quest.id] = quest
end

--[[
	What a task stands at for a player:
		current, needed = QuestBook.taskProgress(task, context)
	where context is
		held      { [item] = count } in the bag
		kills     { [enemy] = kills } from the bestiary
		met       bestiary entries
		slain     kills of anything
]]
function QuestBook.taskProgress(task, context): (number, number)
	if task.item then
		local needed = task.count or 1
		return math.min(context.held[task.item] or 0, needed), needed
	elseif task.items then
		for _, item in ipairs(task.items) do
			if (context.held[item] or 0) > 0 then
				return 1, 1
			end
		end
		return 0, 1
	elseif task.kill then
		local needed = task.count or 1
		return math.min(context.kills[task.kill] or 0, needed), needed
	elseif task.discover then
		return math.min(context.met, task.discover), task.discover
	elseif task.slay then
		return math.min(context.slain, task.slay), task.slay
	end
	return 0, 1
end

function QuestBook.tasksMet(quest, context): boolean
	for _, task in ipairs(quest.tasks) do
		local current, needed = QuestBook.taskProgress(task, context)
		if current < needed then
			return false
		end
	end
	return true
end

-- Whether everything a quest needs first is done.
function QuestBook.unlocked(quest, done: { [string]: boolean }): boolean
	for _, id in ipairs(quest.needs) do
		if not done[id] then
			return false
		end
	end
	return true
end

-- A context from a bag ({ name, count } per slot) and a bestiary record.
function QuestBook.context(bag, record)
	local held = {}
	for _, slot in pairs(bag or {}) do
		if type(slot) == "table" and slot.name and (slot.count or 0) > 0 then
			held[slot.name] = (held[slot.name] or 0) + slot.count
		end
	end
	local met, slain = 0, 0
	for _, kills in pairs(record or {}) do
		met += 1
		slain += kills
	end
	return { held = held, kills = record or {}, met = met, slain = slain }
end

--[[
	Marks everything newly complete in `done` and returns the ids, in tree
	order.

	A quest whose tasks are met is complete even if what it needs is not, and
	it completes what it needs on its way: holding a gold pickaxe proves the
	copper one and the furnace before it. That is what lets a player who
	played before quests existed, or found something in a chest, open the map
	to find it filled in as far as they have really got, rather than stuck at
	First Light because there is no wood in their bag.
]]
function QuestBook.advance(done: { [string]: boolean }, context): { string }
	local fresh = {}

	local function complete(id: string)
		if done[id] then
			return
		end
		done[id] = true
		fresh[id] = true
		for _, need in ipairs(QuestBook.byId[id].needs) do
			complete(need)
		end
	end

	for _, quest in ipairs(QuestBook.Quests) do
		if not done[quest.id] and QuestBook.tasksMet(quest, context) then
			complete(quest.id)
		end
	end

	local completed = {}
	for _, quest in ipairs(QuestBook.Quests) do
		if fresh[quest.id] then
			table.insert(completed, quest.id)
		end
	end
	return completed
end

return QuestBook
