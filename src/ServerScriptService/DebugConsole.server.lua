--[[
	DebugConsole

	Chat commands for looking inside the running game. Restricted to the place
	owner (or high-rank group members), and inert
	for everyone else.

	  /bbstats            terrain, ore, edit, station and recipe counts
	  /bbprof on          start measuring
	  /bbprof off         stop measuring
	  /bbprof             print what has been measured since it was turned on
	  /bbprof reset       clear the accumulators, keep measuring
	  /bbinv              inventory persistence state, and what would be saved
	  /bbinv save         force a save right now instead of waiting for autosave
	  /bbinv wipe         delete this player's save AND reset their live bag, so
	                      the next join exercises the "never played before" path
	  /bbart              what each item draws in its inventory slot: its model,
	                      a flat image, or nothing at all
	  /give <item> [n]    put items in your own bag; /give list to see the names
	  /spawn <enemy> [n]  drop enemies in a ring around you; /spawn list for names
	  /despawn            remove every spawned enemy
	  /god                invulnerable, unlimited mana and no ability cooldowns
	                      or leave. For testing a boss without dying to it
	  /bbface <enemy> <n> turn an enemy's model n degrees about Y, live, on
	                      everything of that kind already in the world. For
	                      finding the right EnemyConfig `modelRotation` without
	                      a rebuild: try 0, 90, 180, 270 and keep the one that
	                      faces you
	  /bbvd <n>           set terrain view distance for everyone, now, without a
	                      restart. Discards any per-player choice made in the
	                      options menu
	  /bbbench            sweep view distance 2..5 and report what each costs
	  /bbbench quick      the same sweep with shorter windows
	  /bbbench 2 4        only those view distances
	  /bbcaves            audit the cave generator on this seed: determinism,
	                      chunk borders, spawn protection, cover and floor
	                      thickness, small-vs-large rarity. See CaveAudit
	  /bbcaves here       what cave you are in, or where the nearest one is
	  /tp <biome>         teleport to the nearest dry ground of that biome;
	                      /tp list for the names
	  /tp cave [large|small]  teleport to the nearest cave mouth (or nearest
	                      plan origin when it has no mouth), for a look inside
	  /coords             your position in blocks, relative to spawn
	  /bbcaves edit       standing in a cave: place, mine and refill through
	                      the real terrain API and confirm it is all recorded

	Every one of them answers on screen through CommandFeedback as well as in the
	output window - a command that printed into Studio and showed nothing in the
	game looked exactly like one that silently did nothing. The long reports
	still only print; what comes back on screen is the headline.

	The profiler is off by default and every instrumented call site is a single
	boolean test when it is, so leaving this in a shipped game costs nothing. It
	is the intended way to find the next bottleneck rather than guessing: turn it
	on, play for a minute, read the table.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))
local Permissions = require(Shared:WaitForChild("Permissions"))
local RecipeBook = require(Shared:WaitForChild("Crafting"):WaitForChild("RecipeBook"))
local WeaponConfig = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))

local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
-- Required at startup rather than on first use: requiring it is what creates the
-- BenchTelemetry remote, and the client half waits for that remote as it loads.
local TerrainBench = require(ServerScriptService:WaitForChild("TerrainBench"))
local CaveAudit = require(ServerScriptService:WaitForChild("CaveAudit"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local BiomeConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("BiomeConfig"))
local BiomeMap = require(Shared:WaitForChild("Terrain"):WaitForChild("BiomeMap"))
local PlaceConfig = require(Shared:WaitForChild("PlaceConfig"))
local CaveMap = require(Shared:WaitForChild("Terrain"):WaitForChild("CaveMap"))
local StationService = require(ServerScriptService:WaitForChild("StationService"))
local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

--[[
	Says the same thing twice: once to the output window and once on the
	player's screen.

	Every command answers, even the ones whose real output is a table dump - a
	command that printed into Studio and showed nothing in game was
	indistinguishable from one that silently did nothing.

	The dumps themselves stay in the output window. What comes back on screen is
	the receipt: what ran, and how it went.
]]
local function reply(player, prefix, text, tone)
	print(string.format("[%s] %s", prefix, text))
	CommandFeedback.tell(player, text, tone)
end

local function describe(label, value, indent)
	indent = indent or ""

	if type(value) ~= "table" then
		print(string.format("%s%-22s %s", indent, label, tostring(value)))
		return
	end

	print(string.format("%s%s:", indent, label))

	local keys = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	for _, key in ipairs(keys) do
		describe(tostring(key), value[key], indent .. "  ")
	end
end

local function printStats()
	print("======== blockbound stats ========")
	describe("terrain", TerrainManager:GetStats())
	describe("stations", StationService.getStats())
	describe("enemies", EnemyService.getStats())
	describe("combat", CombatService.getStats())
	describe("recipes", RecipeBook.getStats())
	describe("weapons", WeaponConfig.describe())
	print("==================================")
end

--[[
	Prints where a player's inventory persistence currently stands, plus the
	exact record that would be written if it saved this instant.
]]
local function printInventory(player)
	print("======== inventory persistence: " .. player.Name .. " ========")
	describe("session", InventoryStore.describe(player))

	local inv = InventoryService.GetInventory(player)
	if not inv then
		local why = if InventoryService.IsLoading(player)
			then "still loading from the DataStore"
			else "no inventory registered"
		print("  (" .. why .. ")")
		print("=========================================")
		return nil, why
	end

	local record = InventoryStore.preview(inv)
	print(string.format("  would save %d occupied slot(s):", #record.slots))
	for _, entry in ipairs(record.slots) do
		print(string.format("    slot %-3d %-16s x%d", entry.s, entry.n, entry.c))
	end
	print("=========================================")

	-- Returned so the caller can put the headline on screen; the slot-by-slot
	-- listing is only worth reading in Studio.
	return #record.slots
end

--[[
	Item names, indexed by their lowercased form.

	The chat handler lowercases the whole message before splitting it, so
	"IronOre" arrives as "ironore" and a direct lookup into ItemDefinitions
	always misses. Built once, on first use, because ItemDefinitions never
	changes at runtime.
]]
local itemNameByLower = nil

local function buildItemIndex()
	itemNameByLower = {}
	for name in pairs(ItemDefinitions) do
		if type(name) == "string" then
			itemNameByLower[string.lower(name)] = name
		end
	end
end

--[[
	Resolves what the player typed to a real item name.

	Falls back to a unique prefix match, so "/give iron" finds IronOre without
	anyone having to remember the exact casing. An ambiguous prefix is reported
	rather than guessed at - picking one of several silently is how you end up
	debugging why you were handed the wrong thing.
]]
local function resolveItemName(query)
	if not itemNameByLower then
		buildItemIndex()
	end

	local exact = itemNameByLower[query]
	if exact then
		return exact
	end

	local matches = {}
	for lower, actual in pairs(itemNameByLower) do
		if string.sub(lower, 1, #query) == query then
			table.insert(matches, actual)
		end
	end

	if #matches == 1 then
		return matches[1]
	end

	if #matches > 1 then
		table.sort(matches)
		return nil, "ambiguous: " .. table.concat(matches, ", ")
	end

	return nil, "no item matching '" .. query .. "'"
end

local function printItemList()
	if not itemNameByLower then
		buildItemIndex()
	end

	local names = {}
	for _, actual in pairs(itemNameByLower) do
		table.insert(names, actual)
	end
	table.sort(names)

	print(string.format("======== %d items ========", #names))
	for index = 1, #names, 4 do
		print("  " .. table.concat({
			names[index] or "",
			names[index + 1] or "",
			names[index + 2] or "",
			names[index + 3] or "",
		}, "   "))
	end
	print("=========================")
end

--[[
	Grants items to the caller.

	Goes through InventoryService like every other grant in the game, so the
	item is stack-limited, saved and synced exactly as a mined one would be -
	a debug command that wrote to the bag directly would be testing a path the
	real game never uses.
]]
local function giveItem(player, query, amount)
	local itemName, problem = resolveItemName(query)
	if not itemName then
		reply(player, "give", problem, "bad")
		return
	end

	amount = math.clamp(math.floor(tonumber(amount) or 1), 1, 999)

	local granted = 0
	for _ = 1, amount do
		local ok = InventoryService.AddItemByName(player, itemName, 1)
		if not ok then
			break
		end
		granted += 1
	end

	if granted == amount then
		reply(player, "give", string.format("%d x %s", granted, itemName), "good")
	elseif granted > 0 then
		reply(player, "give", string.format(
			"%d x %s - bag filled up, %d could not fit",
			granted, itemName, amount - granted
		), "good")
	else
		reply(player, "give", string.format("No room for %s.", itemName), "bad")
	end
end

--[[
	What each item will actually draw in its inventory slot.

	The inventory renders an item's own model wherever there is one, and falls
	back to a flat image where there is not - so the useful question is no
	longer "which items have art" but "which items have neither a model nor a
	picture", because those are the ones that come out empty.

	Grouped by what they will draw, most in need of attention last.
]]
local function printThumbnailReport()
	local rendered, imaged, empty = {}, {}, {}

	local toolsFolder = ReplicatedStorage:FindFirstChild("Tools")
	local terrainAssets = ReplicatedStorage:FindFirstChild("TerrainAssets")
	local blocksFolder = terrainAssets and terrainAssets:FindFirstChild("Blocks")

	for name, definition in pairs(ItemDefinitions) do
		if type(definition) == "table" then
			local model = (toolsFolder and toolsFolder:FindFirstChild(name))
				or (blocksFolder and blocksFolder:FindFirstChild(name))

			local override = definition.thumbnail
			local hasOverride = type(override) == "string" and override ~= ""

			local id = definition.modelId
			local hasId = (type(id) == "number" and id > 0) or (type(id) == "string" and id ~= "")

			local pose = definition.iconPose

			if hasOverride then
				table.insert(imaged, string.format("%s  <- thumbnail (forced)", name))
			elseif model then
				table.insert(rendered, if pose then string.format("%s (%s)", name, pose) else name)
			elseif hasId then
				table.insert(imaged, string.format("%s  <- modelId", name))
			elseif definition.icon then
				-- Listed as a maybe: most of the icon ids in this project are
				-- placeholders that do not resolve. The client checks each one
				-- and skips it when it fails; the server cannot check from here.
				table.insert(imaged, string.format("%s  <- icon (may not load)", name))
			else
				table.insert(empty, name)
			end
		end
	end

	table.sort(rendered)
	table.sort(imaged)
	table.sort(empty)

	print(string.format(
		"======== inventory art: %d rendered, %d flat, %d with nothing ========",
		#rendered, #imaged, #empty
	))

	if #rendered > 0 then
		print("  drawn from their model:")
		for index = 1, #rendered, 4 do
			print("    " .. table.concat({
				rendered[index] or "",
				rendered[index + 1] or "",
				rendered[index + 2] or "",
				rendered[index + 3] or "",
			}, "   "))
		end
	end

	if #imaged > 0 then
		print("  drawn from a flat image:")
		for _, line in ipairs(imaged) do
			print("    " .. line)
		end
	end

	if #empty > 0 then
		print("  NOTHING to draw - these need a model, an icon or a thumbnail:")
		for index = 1, #empty, 4 do
			print("    " .. table.concat({
				empty[index] or "", empty[index + 1] or "", empty[index + 2] or "", empty[index + 3] or "",
			}, "   "))
		end
	end

	print("==============================================================")

	return #rendered, #imaged, #empty
end

local BIOME_SEARCH_RADIUS = 4000 -- blocks
local BIOME_SEARCH_STEP = 16 -- blocks between samples on each ring

local function teleportToBlock(root, x, z)
	local studs = TerrainConfig.StudSize
	local worldX, worldZ = x * studs + studs * 0.5, z * studs + studs * 0.5
	local surfaceY = TerrainManager:GetSurfaceY(worldX, worldZ) or 0
	root.CFrame = CFrame.new(worldX, surfaceY + 6, worldZ)
end

--[[
	Nearest column of a biome, searched in square rings outward from the
	player. Dry land wins; a column under water is only kept as a fallback so
	a biome that is mostly lake still has an answer. Yields every few hundred
	samples - the far rings are tens of thousands of columns.
]]
local function findNearestBiome(biomeName, fromX, fromZ)
	local wet = nil
	local samples = 0
	local step = BIOME_SEARCH_STEP

	local function visit(x, z)
		local _, name, _, _, _, waterTop = BiomeMap.sampleColumn(x, z)
		samples += 1
		if samples % 400 == 0 then
			task.wait()
		end
		if name ~= biomeName then
			return false
		end
		if waterTop == 0 then
			return true
		end
		wet = wet or { x, z }
		return false
	end

	for ring = 0, BIOME_SEARCH_RADIUS // step do
		local r = ring * step
		-- The square ring at this radius: top and bottom rows in full, the
		-- side columns without their corners.
		local cells = {}
		if ring == 0 then
			cells[1] = { 0, 0 }
		else
			for i = -ring, ring do
				table.insert(cells, { i, -ring })
				table.insert(cells, { i, ring })
			end
			for i = -ring + 1, ring - 1 do
				table.insert(cells, { -ring, i })
				table.insert(cells, { ring, i })
			end
		end
		for _, cell in ipairs(cells) do
			local x, z = fromX + cell[1] * step, fromZ + cell[2] * step
			if visit(x, z) then
				return x, z, r
			end
		end
		if wet then
			return wet[1], wet[2], r
		end
	end
	return nil
end

local function onChatted(player, message)
	local words = string.split(string.lower(message), " ")
	local command = words[1]

	if command == "/bbstats" then
		printStats()
		reply(player, "bbstats", "Stats written to the output window.")
	elseif command == "/bbprof" then
		local argument = words[2]

		if argument == "on" then
			Profiler.setEnabled(true)
			reply(player, "Profiler", "Measuring.", "good")
		elseif argument == "off" then
			Profiler.setEnabled(false)
			reply(player, "Profiler", "Stopped.", "good")
		elseif argument == "reset" then
			Profiler.reset()
			reply(player, "Profiler", "Reset.", "good")
		else
			print(Profiler.format())
			reply(player, "Profiler", "Timings written to the output window.")
		end
	elseif command == "/give" then
		local query = words[2]
		if not query or query == "" then
			reply(player, "give", "Usage: /give <item> [count] - /give list for the names.", "bad")
		elseif query == "list" then
			printItemList()
			reply(player, "give", "Item names written to the output window.")
		else
			giveItem(player, query, words[3])
		end
	elseif command == "/bbart" then
		local rendered, imaged, empty = printThumbnailReport()
		reply(player, "bbart", string.format(
			"%d items drawn from a model, %d from an image, %d with nothing.",
			rendered, imaged, empty
		), (if empty > 0 then "bad" else "good"))
	elseif command == "/spawn" then
		local query = words[2]

		if not query or query == "" or query == "list" then
			reply(player, "spawn", "Usage: /spawn <enemy> [count].", "bad")
			reply(player, "spawn", "Available: " .. table.concat(EnemyConfig.Order, ", "))
		else
			-- Chat arrives lowercased, so "blueslime" has to find "BlueSlime".
			local resolved = nil
			for _, name in ipairs(EnemyConfig.Order) do
				if string.lower(name) == query then
					resolved = name
					break
				end
			end

			if not resolved then
				reply(player, "spawn", string.format(
					"No enemy called '%s'. Available: %s",
					query, table.concat(EnemyConfig.Order, ", ")
				), "bad")
			else
				local count, reason = EnemyService.spawnNear(player, resolved, words[3])
				if count > 0 then
					reply(player, "spawn", string.format("%d x %s", count, resolved), "good")
				else
					reply(player, "spawn", "Nothing spawned: " .. tostring(reason), "bad")
				end
			end
		end
	elseif command == "/bbface" then
		--[[
			The yaw dial.

			An imported model faces whichever way the artist left it, and
			working out which of four right angles corrects it by editing a
			config and waiting for a sync is four rebuilds. This writes the
			definition AND re-orients everything of that kind already standing
			in the world, so the answer is four chat messages instead.

			It writes EnemyConfig at runtime, which is exactly as temporary as
			it sounds: the number that survives a restart is the one you then
			put in `modelRotation`, and the reply says so.
		]]
		-- Chat arrives lowercased, so "slimeemperor" has to find "SlimeEmperor",
		-- exactly as /spawn does above.
		local query = words[2]
		local name = nil

		for _, candidate in ipairs(EnemyConfig.Order) do
			if query and string.lower(candidate) == query then
				name = candidate
				break
			end
		end

		local degrees = tonumber(words[3])
		local definition = name and EnemyConfig.Definitions[name]

		if not definition or not degrees then
			reply(player, "bbface", string.format(
				"Usage: /bbface <enemy> <degrees>. Available: %s",
				table.concat(EnemyConfig.Order, ", ")
			), "bad")
		else
			definition.modelRotation = Vector3.new(0, degrees, 0)

			local turned = 0
			for _, model in ipairs(EnemyService.allOf(name)) do
				EnemyService.reorient(model, definition.modelRotation)
				turned += 1
			end

			reply(player, "bbface", string.format(
				"%s turned to %d degrees on %d in the world. Keep it by putting "
					.. "modelRotation = Vector3.new(0, %d, 0) in EnemyConfig.",
				name, degrees, turned, degrees
			), "good")
		end
	elseif command == "/god" then
		--[[
			Toggled rather than set, and reported either way.

			An invulnerability you can turn on but have to remember the syntax
			to turn off is one you leave on by accident and then wonder why the
			boss feels easy. It also clears itself when the player leaves - see
			CombatService.setInvulnerable.
		]]
		local on = CombatService.setInvulnerable(player, not CombatService.isInvulnerable(player))

		reply(player, "god", if on
			then "God mode: invulnerable, unlimited mana and no ability cooldowns. Type /god again to switch it off."
			else "Mortal again.", if on then "good" else nil)
	elseif command == "/despawn" then
		local removed = EnemyService.despawnAll()
		reply(player, "despawn", string.format(
			"Removed %d enem%s.", removed, if removed == 1 then "y" else "ies"
		), (if removed > 0 then "good" else nil))
	elseif command == "/bbvd" then
		local requested = tonumber(words[2])
		if not requested then
			reply(player, "bbvd", string.format(
				"Default view distance is %d. Pass a number to change it for everyone.",
				TerrainManager:GetViewDistance()
			))
		else
			local applied = TerrainManager:SetViewDistance(requested)
			reply(player, "bbvd", string.format(
				"View distance now %d - %d chunks around each player.",
				applied, (2 * applied + 1) ^ 2
			), "good")
		end
	elseif command == "/bbbench" then
		if TerrainBench.isRunning() then
			reply(player, "bbbench", "Already running.", "bad")
			return
		end

		local options = {}
		local distances = {}

		for index = 2, #words do
			local word = words[index]
			if word == "quick" then
				options.quick = true
			else
				local number = tonumber(word)
				if number then
					table.insert(distances, math.clamp(math.floor(number), 0, 12))
				end
			end
		end

		if #distances > 0 then
			options.viewDistances = distances
		end

		-- Spawned, not called: the sweep takes minutes and yields constantly,
		-- and the chat handler is not somewhere to block for that long.
		task.spawn(TerrainBench.run, options)
		reply(player, "bbbench", "Started. Results land in the output window.", "good")
	elseif command == "/coords" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			reply(player, "coords", "No character.", "bad")
		else
			-- Spawn sits on the world origin, so blocks from spawn is just the
			-- position in blocks.
			local studs = TerrainConfig.StudSize
			local p = root.Position
			local x, y, z = math.floor(p.X / studs), math.floor(p.Y / studs), math.floor(p.Z / studs)
			reply(player, "coords", string.format(
				"X %d, Y %d, Z %d (blocks). %d blocks from spawn.",
				x, y, z, math.floor(math.sqrt(x * x + z * z))
			))
		end
	elseif command == "/tp" then
		local argument = words[2]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local studs = TerrainConfig.StudSize

		local biomeName = nil
		for _, candidate in ipairs(BiomeConfig.Order) do
			if argument and string.lower(candidate) == argument then
				biomeName = candidate
				break
			end
		end

		if not root then
			reply(player, "tp", "No character.", "bad")
		elseif argument == "cave" or argument == "caves" then
			if not TerrainManager:CavesEnabled() then
				reply(player, "tp", "Caves are off in this place.", "bad")
				return
			end
			local category = if words[3] == "large" then "Large" elseif words[3] == "small" then "Small" else nil
			local plan = CaveMap.findNearestPlan(
				math.floor(root.Position.X / studs), math.floor(root.Position.Z / studs), 1500, category
			)
			if not plan then
				reply(player, "tp", "No cave plan within 1500 blocks.", "bad")
			else
				local x, z = plan.originX, plan.originZ
				if plan.entrance then
					x, z = plan.entrance.x, plan.entrance.z
				end
				teleportToBlock(root, x, z)
				reply(player, "tp", string.format(
					"Teleported to %s cave %s (%s), %s.", string.lower(plan.category), plan.id, plan.biome,
					if plan.entrance then "at its mouth" else "above its origin (no mouth; dig down)"
				), "good")
			end
		elseif biomeName then
			if PlaceConfig.isIsland() then
				reply(player, "tp", "There are no biomes to search in the Island place.", "bad")
				return
			end
			reply(player, "tp", "Searching for " .. biomeName .. "...")
			-- Spawned: a far biome is thousands of samples, too long to block chat.
			task.spawn(function()
				local fromX = math.floor(root.Position.X / studs)
				local fromZ = math.floor(root.Position.Z / studs)
				local x, z, distance = findNearestBiome(biomeName, fromX, fromZ)
				if not x then
					reply(player, "tp", string.format(
						"No %s within %d blocks.", biomeName, BIOME_SEARCH_RADIUS
					), "bad")
				elseif root.Parent then
					teleportToBlock(root, x, z)
					reply(player, "tp", string.format(
						"Teleported to %s at X %d, Z %d (about %d blocks away).", biomeName, x, z, distance
					), "good")
				end
			end)
		else
			reply(player, "tp", string.format(
				"Usage: /tp <biome> or /tp cave [large|small]. Biomes: %s",
				table.concat(BiomeConfig.Order, ", ")
			), if argument == "list" then nil else "bad")
		end
	elseif command == "/bbcaves" then
		local argument = words[2]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if not TerrainManager:CavesEnabled() then
			reply(player, "bbcaves", "Caves are off in this place.", "bad")
		elseif argument == "here" then
			if not root then
				reply(player, "bbcaves", "No character.", "bad")
			else
				reply(player, "bbcaves", CaveAudit.describe(root.Position))
			end
		elseif argument == "edit" then
			local ok, outcome = CaveAudit.editRoundTrip(player)
			reply(player, "bbcaves", outcome, if ok then "good" else "bad")
		else
			-- Spawned: the audit carves a few dozen chunks and walks every
			-- plan cell in the world, which is a second or two of work.
			task.spawn(function()
				local report = CaveAudit.printReport()
				reply(player, "bbcaves", CaveAudit.summarise(report), if report.errors == 0 then "good" else "bad")
			end)
		end
	elseif command == "/bbinv" then
		local argument = words[2]

		if argument == "save" then
			local inv = InventoryService.GetInventory(player)
			if not inv then
				reply(player, "bbinv", "No inventory registered yet.", "bad")
				return
			end

			local ok, err = InventoryStore.save(player, inv, "manual")
			if ok then
				reply(player, "bbinv", "Saved.", "good")
			else
				reply(player, "bbinv", "Save refused: " .. tostring(err), "bad")
			end
		elseif argument == "wipe" then
			local ok, err = InventoryStore.wipe(player)
			if not ok then
				reply(player, "bbinv", "Wipe failed: " .. tostring(err), "bad")
				return
			end

			-- Reset the live bag too. Wiping only the record would be undone by
			-- the next save, which writes whatever is still in memory.
			local fresh = InventoryStore.buildDefault()
			InventoryService.Register(player, fresh)
			InventoryService.SaveAndSync(player)
			reply(player, "bbinv", "Save deleted and inventory reset to default.", "good")
		else
			local slots, why = printInventory(player)
			if slots then
				reply(player, "bbinv", string.format(
					"%d occupied slot(s) would be written. Detail in the output window.", slots
				))
			else
				reply(player, "bbinv", "Nothing to save: " .. why .. ".", "bad")
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	if not Permissions.isAdmin(player) then
		return
	end

	player.Chatted:Connect(function(message)
		local ok, err = pcall(onChatted, player, message)
		if not ok then
			warn("[DebugConsole]", err)
		end
	end)
end)
