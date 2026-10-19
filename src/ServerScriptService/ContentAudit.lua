--[[
	ContentAudit

	A read-only check of the game's content against its own code: does every
	item, tool, enemy, drop, recipe, sound and ability that the data describes
	actually exist and actually do something?

		local report = ContentAudit.run()
		ContentAudit.printReport(report)      -- the whole thing, to Output
		ContentAudit.summarise(report)        -- a few lines for a player

	From the Studio command bar, with a server running:

		require(game.ServerScriptService.ContentAudit).printReport()

	In game, the owner types /contentaudit (see ContentAuditCommand).

	FOUR KINDS OF FINDING

	  Errors                 broken: something a player can hit, or content that
	                         can never be reached
	  Warnings               works, but wrong-looking or fragile
	  Placeholder Content    standing in for art or assets that do not exist yet
	  Intentional Exceptions looks like a gap, and is a documented decision

	Each finding names the check, the exact instance or module it is about, and
	what is wrong.

	IT CHANGES NOTHING

	Safe to run on a live server. It never creates, renames, moves or welds an
	instance - in particular it does NOT call ToolFactory.ensure, which wraps
	and repairs tools as a side effect; it reads ReplicatedStorage.Tools exactly
	as the server left it at startup. It never requires an ability's server or
	VFX module, only checks they exist. Every module it requires is configuration
	or an already-running service, and requiring them changes nothing in the game.

	WHAT IT CANNOT SEE

	Whether an asset id actually LOADS, or whether this game is allowed to use
	it: that is a question for Roblox's asset service, and asking it from here
	would mean web calls from a live server. Ids are checked for presence and
	format only. The Output window still reports the ones that fail to load.

	ADDING TO IT

	The tables under DOCUMENTED KNOWLEDGE below are the facts the audit cannot
	work out for itself: which items are test-only, which consumables have use
	code, which assets each VFX module loads. When one of those changes, change
	it here - that is the "explicitly documented" in "intentional exception".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ContentAudit = {}

-- ===========================================================================
-- DOCUMENTED KNOWLEDGE
-- ===========================================================================

--[[
	Items that exist for testing and are only ever handed out by an admin
	(/give) or a development dispenser. Not reporting them as unobtainable is
	the whole point of listing them; each needs its reason.
]]
ContentAudit.TestOnlyItems = {
	TestSword = "Developer weapon (150 damage). Also AbilityConfig.DefaultCastWeapon, the blade Sacred Rain draws when the caster holds nothing.",
	TestPickaxe = "Developer pickaxe (miningSpeed 40); stands in for an end-game pickaxe while tuning mining.",
	TestAxe = "Developer axe for testing tree harvesting.",
}

--[[
	Consumables whose USE is implemented, and where. A consumable not listed
	here can be owned but does nothing when used. `script` is a direct child of
	ServerScriptService and `remote` a child of ReplicatedStorage.Remotes; both
	are checked to exist. Add a row when a consumable gets its use code.
]]
ContentAudit.UseHandlers = {
	ScrollChest = { script = "ScrollChest", remote = "ScrollChestRequest" },
	GelatinousCrown = { script = "AltarSummon", remote = "AltarUseRequest" },
}

--[[
	Assets each ability VFX module loads, relative to Shared.Abilities.VFX.
	Read off the modules themselves (Packs:FindFirstChild / Packs.Name); a
	module the audit cannot see inside at runtime, so it is written down here.
]]
ContentAudit.VfxAssets = {
	CataclysmVFX = {"CataclysmParticles", "CataclysmCamera"},
	StarterVFX = {"StarterParticles", "CataclysmParticles"},
	SignusVFX = {"SignusFX", "SignusParticles", "SignusVisuals", "SignusChoreography", "CataclysmParticles", "StarterParticles"},
}

-- Swing animations ToolConfig leaves blank on purpose (see ToolConfig.Animations).
ContentAudit.BlankAnimationsByDesign = true

-- Abilities whose AbilityConfig entry explains why they have no cast
-- animation. Any other ability without one is reported as placeholder content.
ContentAudit.NoCastAnimationByDesign = {
	Cataclysm = "cast and impact are communicated by authored particles",
	Fireball = "particle charge and release",
	WindBurst = "particle gather and directional pressure fan",
	WaterBlade = "particle charge and water crescent",
	EchoStep = "departure, travel ribbon and arrival particles",
	BlockWall = "physical terrain movement and dust particles",
}

-- Every field ItemDefinitions documents or a system reads. Anything else is
-- reported, and one a letter or two off a real field is reported as a typo.
ContentAudit.KnownItemFields = {
	classification = true, maxStack = true, miningTime = true, miningSpeed = true,
	miningPower = true, weaponClass = true, weaponSubclass = true, rarity = true, animation = true, iconPose = true, iconAngle = true, thumbnail = true,
	modelId = true, icon = true, description = true, value = true, buffs = true,
	displayName = true, look = true, dropOnly = true,
}

-- Ids in this range were typed in as placeholders before there was any art;
-- none of them resolve.
local PLACEHOLDER_ID_LOW = 3000000000
local PLACEHOLDER_ID_HIGH = 3000000999

-- ===========================================================================
-- Report plumbing
-- ===========================================================================

local CATEGORIES = { "Errors", "Warnings", "Placeholders", "Exceptions" }

local CATEGORY_TITLES = {
	Errors = "ERRORS",
	Warnings = "WARNINGS",
	Placeholders = "PLACEHOLDER CONTENT",
	Exceptions = "INTENTIONAL EXCEPTIONS",
}

-- Report order within a category: most fundamental first.
local CHECK_ORDER = {
	"Setup", "Items", "Acquisition", "Consumables", "Tools", "Abilities", "Enemies",
	"Drops", "Recipes", "Blocks", "Stations", "Buffs", "Icons", "Audio", "Animations",
}

local function newReport()
	local report = { startedAt = os.clock() }
	for _, category in ipairs(CATEGORIES) do
		report[category] = {}
	end
	return report
end

local function add(report, category, check, subject, message)
	table.insert(report[category], { check = check, subject = subject, message = message })
end

-- A module the game has already loaded, or nil (and an error finding) if it
-- will not load. Never lets one broken module stop the audit.
local function load(report, container, name, label)
	local module = container and container:FindFirstChild(name)
	if not (module and module:IsA("ModuleScript")) then
		add(report, "Errors", "Setup", label, "module not found, so the checks that need it were skipped")
		return nil
	end

	local ok, result = pcall(require, module)
	if not ok then
		add(report, "Errors", "Setup", label, "module errors when required: " .. tostring(result))
		return nil
	end
	return result
end

local function sortedKeys(map)
	local keys = {}
	for key in pairs(map) do
		if type(key) == "string" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

-- Levenshtein distance, for telling a typo ("classigication") from a field
-- nobody has heard of. Short strings only.
local function editDistance(a, b)
	local la, lb = #a, #b
	local previous = {}
	for j = 0, lb do
		previous[j] = j
	end
	for i = 1, la do
		local current = { [0] = i }
		for j = 1, lb do
			local cost = if string.sub(a, i, i) == string.sub(b, j, j) then 0 else 1
			current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
		end
		previous = current
	end
	return previous[lb]
end

local function closestField(field)
	local best, bestDistance = nil, math.huge
	for known in pairs(ContentAudit.KnownItemFields) do
		local distance = editDistance(string.lower(field), string.lower(known))
		if distance < bestDistance then
			best, bestDistance = known, distance
		end
	end
	return best, bestDistance
end

local function fullName(instance)
	return if instance then instance:GetFullName() else "(missing)"
end

local function findPath(root, path)
	local current = root
	for segment in string.gmatch(path, "[^/]+") do
		current = current and current:FindFirstChild(segment)
	end
	return current
end

--[[
	Checks an asset id's FORMAT. Returns "ok", "legacy", "empty" or "bad".

	  rbxassetid://123           uploaded asset
	  rbxasset://sounds/x.wav    built into the Roblox client
	  http(s)://www.roblox.com/asset/?id=123   legacy; still loads
]]
local function idFormat(id)
	if id == nil or id == "" then
		return "empty"
	end
	if type(id) ~= "string" then
		return "bad"
	end
	if string.match(id, "^rbxassetid://%d+$") then
		return "ok"
	end
	if string.match(id, "^rbxasset://[%w_/%.%-]+$") then
		return "ok"
	end
	if string.match(id, "^https?://www%.roblox%.com/asset/%?id=%d+$") then
		return "legacy"
	end
	return "bad"
end

local function numericId(id)
	return type(id) == "string" and tonumber(string.match(id, "^rbxassetid://(%d+)$")) or nil
end

local function isPlaceholderId(id)
	local number = numericId(id)
	return number ~= nil and number >= PLACEHOLDER_ID_LOW and number <= PLACEHOLDER_ID_HIGH
end

local function checkId(report, check, subject, id, what)
	local format = idFormat(id)
	if format == "empty" then
		add(report, "Warnings", check, subject, what .. " is empty")
	elseif format == "bad" then
		add(report, "Errors", check, subject, string.format("%s %q is not a valid asset id", what, tostring(id)))
	elseif format == "legacy" then
		add(report, "Warnings", check, subject, string.format(
			"%s %q uses the legacy roblox.com/asset URL; prefer rbxassetid://", what, id
		))
	elseif isPlaceholderId(id) then
		add(report, "Placeholders", check, subject, string.format("%s %s is a placeholder id", what, id))
	end
end

-- ===========================================================================
-- The audit
-- ===========================================================================

function ContentAudit.run()
	local report = newReport()

	-- --------------------------------------------------------------- modules
	local ItemDefinitions = load(report, ReplicatedStorage, "ItemDefinitions", "ReplicatedStorage.ItemDefinitions")
	local CraftingRecipes = load(report, ReplicatedStorage, "CraftingRecipes", "ReplicatedStorage.CraftingRecipes")
	local EnemyDrops = load(report, ReplicatedStorage, "EnemyDrops", "ReplicatedStorage.EnemyDrops")
	local InventoryConstants = load(report, ReplicatedStorage, "InventoryConstants", "ReplicatedStorage.InventoryConstants")
	local PromptItemMappings = load(report, ReplicatedStorage, "PromptItemMappings", "ReplicatedStorage.PromptItemMappings")

	local ToolConfig = load(report, Shared:FindFirstChild("Tools"), "ToolConfig", "Shared.Tools.ToolConfig")
	local EnemyConfig = load(report, Shared:FindFirstChild("Enemies"), "EnemyConfig", "Shared.Enemies.EnemyConfig")
	local AbilityConfig = load(report, Shared:FindFirstChild("Abilities"), "AbilityConfig", "Shared.Abilities.AbilityConfig")
	local SoundConfig = load(report, Shared:FindFirstChild("Audio"), "SoundConfig", "Shared.Audio.SoundConfig")
	local Music = load(report, Shared:FindFirstChild("Audio"), "Music", "Shared.Audio.Music")
	local BlockConfig = load(report, Shared:FindFirstChild("Blocks"), "BlockConfig", "Shared.Blocks.BlockConfig")
	local StationConfig = load(report, Shared:FindFirstChild("Crafting"), "StationConfig", "Shared.Crafting.StationConfig")
	local WeaponConfig = load(report, Shared:FindFirstChild("Combat"), "WeaponConfig", "Shared.Combat.WeaponConfig")

	local TerrainShared = Shared:FindFirstChild("Terrain")
	local BiomeConfig = load(report, TerrainShared, "BiomeConfig", "Shared.Terrain.BiomeConfig")
	local LandformConfig = load(report, TerrainShared, "LandformConfig", "Shared.Terrain.LandformConfig")
	local StrataConfig = load(report, TerrainShared, "StrataConfig", "Shared.Terrain.StrataConfig")
	local OreConfig = load(report, TerrainShared, "OreConfig", "Shared.Terrain.OreConfig")
	local StructureConfig = load(report, TerrainShared, "StructureConfig", "Shared.Terrain.StructureConfig")
	local IslandConfig = load(report, TerrainShared, "IslandConfig", "Shared.Terrain.IslandConfig")

	local GearService = load(report, ServerScriptService, "GearService", "ServerScriptService.GearService")
	local InventoryStore = load(report, ServerScriptService, "InventoryStore", "ServerScriptService.InventoryStore")

	if not ItemDefinitions then
		-- Nothing below means anything without the item table.
		report.finishedAt = os.clock()
		return report
	end

	local itemNames = sortedKeys(ItemDefinitions)
	local toolsFolder = ReplicatedStorage:FindFirstChild("Tools")
	local terrainAssets = ReplicatedStorage:FindFirstChild("TerrainAssets")
	local blockAssets = terrainAssets and terrainAssets:FindFirstChild("Blocks")

	local function itemLabel(name)
		return "ItemDefinitions." .. name
	end

	local function isHoldable(definition)
		return ToolConfig ~= nil and ToolConfig.isHoldable(definition.classification)
	end

	-- --------------------------------------------------------------- Items
	-- The schema itself: a field the systems do not read is a field that does
	-- nothing, and one a letter off a real one is a silent bug.
	for _, name in ipairs(itemNames) do
		local definition = ItemDefinitions[name]
		local subject = itemLabel(name)

		if type(definition) ~= "table" then
			add(report, "Errors", "Items", subject, "is not a table")
			continue
		end

		for field in pairs(definition) do
			if type(field) == "string" and not ContentAudit.KnownItemFields[field] then
				local closest, distance = closestField(field)
				if distance <= 2 then
					add(report, "Errors", "Items", subject .. "." .. field, string.format(
						"unknown field - almost certainly a typo for '%s', so the real '%s' is unset", closest, closest
					))
				else
					add(report, "Warnings", "Items", subject .. "." .. field, "unknown field; nothing reads it")
				end
			end
		end

		if type(definition.classification) ~= "string" or definition.classification == "" then
			add(report, "Errors", "Items", subject, "has no classification, so no system knows what it is (not holdable, placeable or wearable)")
		end
		if type(definition.rarity) ~= "string" then
			add(report, "Warnings", "Items", subject, "has no rarity; its name draws in the default colour")
		end
		if type(definition.maxStack) ~= "number" or definition.maxStack < 1 then
			add(report, "Errors", "Items", subject, "maxStack must be a number of at least 1")
		end
	end

	-- --------------------------------------------------------------- Tools
	if toolsFolder and ToolConfig then
		for _, name in ipairs(itemNames) do
			local definition = ItemDefinitions[name]
			if type(definition) ~= "table" then
				continue
			end

			local template = toolsFolder:FindFirstChild(name)
			local path = "ReplicatedStorage.Tools." .. name

			if isHoldable(definition) then
				if not template then
					add(report, "Errors", "Tools", path, string.format(
						"missing: %s '%s' is holdable but has no Tool template, so it cannot be equipped",
						tostring(definition.classification), name
					))
					continue
				end

				if not template:IsA("Tool") then
					add(report, "Errors", "Tools", path, string.format(
						"is a %s, not a Tool - ToolFactory did not wrap it at startup, so it cannot be equipped",
						template.ClassName
					))
					continue
				end

				-- Handle: Roblox welds exactly the direct child named Handle.
				local handle = template:FindFirstChild("Handle")
				if template.RequiresHandle and not (handle and handle:IsA("BasePart")) then
					add(report, "Errors", "Tools", path, "has no direct child BasePart named Handle; it cannot be held")
				end

				-- ItemName mapping, which equip, mining and combat all read.
				local mapped = template:GetAttribute("ItemName") or template:GetAttribute("itemName")
				local value = template:FindFirstChild("ItemName") or template:FindFirstChild("itemName")
				if value and value:IsA("StringValue") then
					mapped = mapped or value.Value
				end
				if mapped ~= nil and mapped ~= name then
					add(report, "Errors", "Tools", path, string.format(
						"ItemName is '%s' but the item is '%s'; systems will treat it as the wrong item", tostring(mapped), name
					))
				elseif mapped == nil then
					add(report, "Warnings", "Tools", path, "has no ItemName attribute; systems fall back to the Tool's Name")
				end

				-- Physics safety.
				local anchored, colliding, parts = {}, {}, 0
				for _, descendant in ipairs(template:GetDescendants()) do
					if descendant:IsA("BasePart") then
						parts += 1
						if descendant.Anchored then
							table.insert(anchored, descendant.Name)
						end
						if descendant.CanCollide then
							table.insert(colliding, descendant.Name)
						end
					end
				end
				if parts == 0 then
					add(report, "Errors", "Tools", path, "contains no BaseParts")
				end
				if #anchored > 0 then
					add(report, "Errors", "Tools", path, "has anchored parts (" .. table.concat(anchored, ", ") .. "); the wielder will be frozen in place")
				end
				if #colliding > 0 then
					add(report, "Warnings", "Tools", path, "has colliding parts (" .. table.concat(colliding, ", ") .. "); they can shove or fling the wielder")
				end

				-- Grip: the hand sits at Grip.Position in the Handle's space. A
				-- grip far outside the handle holds the tool by thin air.
				if handle and handle:IsA("BasePart") then
					local reach = math.max(handle.Size.X, handle.Size.Y, handle.Size.Z)
					if template.Grip.Position.Magnitude > reach * 0.75 + 0.5 then
						add(report, "Warnings", "Tools", path, string.format(
							"Grip is %.1f studs from the Handle's centre but the Handle is only %.1f long; it will be held outside itself",
							template.Grip.Position.Magnitude, reach
						))
					end
					if reach > 12 then
						add(report, "Warnings", "Tools", path, string.format("Handle is %.1f studs long; check its scale", reach))
					end
				end
			elseif template then
				if template:IsA("Tool") then
					add(report, "Warnings", "Tools", path, string.format(
						"is a Tool, but '%s' %s, which cannot be held; the template is never used",
						name, if definition.classification then "is a " .. tostring(definition.classification) else "has no classification"
					))
				else
					add(report, "Exceptions", "Tools", path, string.format(
						"%s used only as the inventory preview model for a %s",
						template.ClassName, tostring(definition.classification)
					))
				end
			end
		end

		for _, child in ipairs(toolsFolder:GetChildren()) do
			if ItemDefinitions[child.Name] == nil then
				add(report, "Warnings", "Tools", fullName(child), "has no ItemDefinitions entry; nothing can grant it")
			end
		end
	elseif not toolsFolder then
		add(report, "Errors", "Tools", "ReplicatedStorage.Tools", "folder missing; no item can be equipped")
	end

	-- --------------------------------------------------------------- Icons
	for _, name in ipairs(itemNames) do
		local definition = ItemDefinitions[name]
		if type(definition) ~= "table" then
			continue
		end

		local subject = itemLabel(name) .. ".icon"
		local icon = definition.icon
		local hasModel = (toolsFolder and toolsFolder:FindFirstChild(name) ~= nil)
			or (blockAssets and blockAssets:FindFirstChild(name) ~= nil)
			or type(definition.look) == "table"
		local hasThumbnail = type(definition.thumbnail) == "string" and definition.thumbnail ~= ""

		if icon == nil or icon == "" then
			if hasThumbnail then
				-- Fine: the thumbnail is the image.
			elseif hasModel then
				add(report, "Exceptions", "Icons", subject, "empty; the inventory draws a live render of its model instead")
			else
				add(report, "Errors", "Icons", subject, "empty, and there is no model or thumbnail: the item is invisible in the inventory")
			end
		elseif idFormat(icon) == "bad" then
			add(report, "Errors", "Icons", subject, string.format("%q is not a valid asset id", tostring(icon)))
		elseif isPlaceholderId(icon) then
			add(report, "Placeholders", "Icons", subject, string.format(
				"%s is a placeholder that does not resolve%s",
				icon, if hasModel then " (hidden by the live model render)" else "; the item shows as an empty slot"
			))
		end

		if hasThumbnail then
			checkId(report, "Icons", itemLabel(name) .. ".thumbnail", definition.thumbnail, "thumbnail")
		end
	end

	-- --------------------------------------------------------------- Enemies
	if EnemyConfig then
		local assetsFolder = ReplicatedStorage:FindFirstChild(EnemyConfig.AssetsFolder or "EnemyAssets")
		local definitions = EnemyConfig.Definitions or {}

		for _, name in ipairs(sortedKeys(definitions)) do
			local definition = definitions[name]
			local subject = "EnemyConfig.Definitions." .. name
			local assetName = definition.asset
			local asset = assetsFolder and type(assetName) == "string" and EnemyConfig.findAsset(assetsFolder, assetName)

			if not asset then
				add(report, "Errors", "Enemies", subject, string.format(
					"asset '%s' not found in ReplicatedStorage.%s; it cannot spawn",
					tostring(assetName), tostring(EnemyConfig.AssetsFolder)
				))
			elseif not (asset:IsA("Model") or asset:IsA("BasePart")) then
				add(report, "Errors", "Enemies", fullName(asset), "is a " .. asset.ClassName .. "; an enemy asset must be a Model or BasePart")
			else
				if asset:IsA("Model") and not asset.PrimaryPart then
					add(report, "Warnings", "Enemies", fullName(asset), "has no PrimaryPart; EnemyService picks the first part it finds as the body, which may not be the centre")
				end
				if type(definition.bodyPart) == "string" and not asset:FindFirstChild(definition.bodyPart, true) then
					add(report, "Errors", "Enemies", fullName(asset), "has no part named '" .. definition.bodyPart .. "' (EnemyConfig bodyPart)")
				end
				if asset:IsA("Model") and assetName ~= name then
					add(report, "Exceptions", "Enemies", subject, string.format("borrows the '%s' model (asset = %q)", assetName, assetName))
				end
			end

			local drops = EnemyDrops and EnemyDrops.Tables and EnemyDrops.Tables[name]
			if drops == nil then
				add(report, "Warnings", "Enemies", subject, "has no EnemyDrops.Tables entry; add one, even an empty one, so 'drops nothing' is a decision")
			elseif #drops == 0 then
				add(report, "Exceptions", "Enemies", "EnemyDrops.Tables." .. name, "deliberately empty: drops nothing")
			end
		end
	end

	-- --------------------------------------------------------------- Drops
	if EnemyDrops and EnemyDrops.Tables then
		local definitions = EnemyConfig and EnemyConfig.Definitions or {}

		for _, enemy in ipairs(sortedKeys(EnemyDrops.Tables)) do
			local subject = "EnemyDrops.Tables." .. enemy
			if EnemyConfig and definitions[enemy] == nil then
				add(report, "Warnings", "Drops", subject, "names no enemy in EnemyConfig.Definitions; it never rolls")
			end

			for index, line in ipairs(EnemyDrops.Tables[enemy]) do
				local lineSubject = string.format("%s[%d]", subject, index)
				if type(line.item) ~= "string" or ItemDefinitions[line.item] == nil then
					add(report, "Errors", "Drops", lineSubject, string.format("drops '%s', which is not an item", tostring(line.item)))
				end
				local chance = tonumber(line.chance)
				if not chance or chance <= 0 or chance > 1 then
					add(report, "Errors", "Drops", lineSubject, "chance must be in (0, 1]")
				end
				local low, high = tonumber(line.min), tonumber(line.max)
				if not low or not high or low < 1 or high < low then
					add(report, "Errors", "Drops", lineSubject, "min/max must be whole numbers with 1 <= min <= max")
				end
			end
		end

		-- The placeholder state of the table is itself worth knowing.
		local onlyWood = true
		for _, lines in pairs(EnemyDrops.Tables) do
			for _, line in ipairs(lines) do
				if line.item ~= "Wood" then
					onlyWood = false
				end
			end
		end
		if onlyWood then
			add(report, "Placeholders", "Drops", "EnemyDrops.Tables", "every enemy drops only Wood - the testing table EnemyDrops describes as placeholder")
		end
	end

	-- --------------------------------------------------------------- Recipes
	local recipes = {}

	if CraftingRecipes then
		local stationDefinitions = StationConfig and StationConfig.Definitions or {}

		for _, id in ipairs(sortedKeys(CraftingRecipes)) do
			local recipe = CraftingRecipes[id]
			local subject = "CraftingRecipes." .. id
			local output = if type(recipe.output) == "table" then recipe.output.item else id
			local valid = true

			if type(output) ~= "string" or ItemDefinitions[output] == nil then
				add(report, "Errors", "Recipes", subject, string.format("makes '%s', which is not an item", tostring(output)))
				valid = false
			end

			if type(recipe.ingredients) ~= "table" or next(recipe.ingredients) == nil then
				add(report, "Errors", "Recipes", subject, "has no ingredients")
				valid = false
			else
				for ingredient, count in pairs(recipe.ingredients) do
					if ItemDefinitions[ingredient] == nil then
						add(report, "Errors", "Recipes", subject, string.format("needs '%s', which is not an item", tostring(ingredient)))
						valid = false
					end
					if type(count) ~= "number" or count < 1 then
						add(report, "Errors", "Recipes", subject, string.format("needs %s x '%s'; a count must be at least 1", tostring(count), tostring(ingredient)))
					end
				end
			end

			if recipe.station ~= nil and stationDefinitions[recipe.station] == nil then
				add(report, "Errors", "Recipes", subject, string.format("is made at '%s', which is not a station in StationConfig", tostring(recipe.station)))
				valid = false
			end

			if valid then
				table.insert(recipes, { id = id, output = output, ingredients = recipe.ingredients, station = recipe.station })
			end
		end
	end

	-- --------------------------------------------------------------- Blocks
	if BlockConfig then
		local generated = BlockConfig.Generated or {}
		for _, name in ipairs(itemNames) do
			local definition = ItemDefinitions[name]
			if type(definition) == "table" and definition.classification == "Block" then
				local authored = blockAssets and blockAssets:FindFirstChild(name)
				if authored then
					-- Fine.
				elseif generated[name] then
					add(report, "Placeholders", "Blocks", "Shared.Blocks.BlockConfig.Generated." .. name,
						"drawn as a generated coloured stand-in; no authored block in ReplicatedStorage.TerrainAssets.Blocks")
				else
					add(report, "Errors", "Blocks", "ReplicatedStorage.TerrainAssets.Blocks." .. name,
						"missing, and no BlockConfig.Generated entry: placing it fails with 'Missing template'")
				end
			end
		end
	end

	-- --------------------------------------------------------------- Stations
	if StationConfig then
		local modelFolder = terrainAssets and terrainAssets:FindFirstChild(StationConfig.ModelFolderName or "Stations")
		for _, name in ipairs(itemNames) do
			local definition = ItemDefinitions[name]
			if type(definition) == "table" and definition.classification == "Workbench" then
				if not (StationConfig.Definitions and StationConfig.Definitions[name]) then
					add(report, "Errors", "Stations", itemLabel(name), "is a Workbench with no StationConfig entry; it cannot be placed")
				elseif not (modelFolder and modelFolder:FindFirstChild(name)) then
					add(report, "Placeholders", "Stations", "ReplicatedStorage.TerrainAssets." .. tostring(StationConfig.ModelFolderName) .. "." .. name,
						"no authored model; placed as StationService's two-box stand-in")
				end
			end
		end
	end

	-- --------------------------------------------------------------- Acquisition
	--[[
		Where can each item come from? Every source the game has, then recipes
		resolved to a fixed point - a recipe only counts once its station and
		every ingredient can themselves be had.
	]]
	local sources = {}
	local function addSource(item, description)
		if type(item) ~= "string" then
			return
		end
		sources[item] = sources[item] or {}
		table.insert(sources[item], description)
	end

	local naturalBlocks = {}
	local function natural(block, where)
		if type(block) == "string" and block ~= "" then
			naturalBlocks[block] = naturalBlocks[block] or where
		end
	end

	if BiomeConfig and BiomeConfig.Definitions then
		for biome, definition in pairs(BiomeConfig.Definitions) do
			natural(definition.topBlock, "the " .. biome .. " surface")
			natural(definition.underBlock, "under " .. biome)
		end
	end
	if LandformConfig then
		natural(LandformConfig.RockBlock, "bare rock")
		natural(LandformConfig.SnowBlock, "snow caps")
		natural(LandformConfig.ShoreBlock, "shores")
	end
	if StrataConfig and StrataConfig.Layers then
		for _, layer in ipairs(StrataConfig.Layers) do
			natural(layer.block, "the underground")
		end
	end
	if IslandConfig then
		natural(IslandConfig.TopBlock, "player islands")
		natural(IslandConfig.UnderBlock, "player islands")
	end
	if StructureConfig and StructureConfig.Definitions then
		for _, structure in ipairs(StructureConfig.Definitions) do
			if structure.enabled ~= false then
				for _, entry in ipairs(structure.blocks or {}) do
					natural(entry[4], tostring(structure.id) .. " structures")
				end
				local harvest = structure.harvest
				if type(harvest) == "table" then
					addSource(harvest.item, "harvested from " .. tostring(structure.id))
					if type(harvest.bonus) == "table" then
						addSource(harvest.bonus.item, "bonus from harvesting " .. tostring(structure.id))
					end
				end
			end
		end
	end
	if BlockConfig then
		for block, where in pairs(naturalBlocks) do
			local drop = BlockConfig.getDrop(block)
			if drop then
				addSource(drop, "mined from " .. block .. " (" .. where .. ")")
			end
		end
	end
	if OreConfig and OreConfig.Enabled ~= false and OreConfig.Order then
		for _, ore in ipairs(OreConfig.Order) do
			local definition = OreConfig.Definitions and OreConfig.Definitions[ore]
			if definition then
				addSource(definition.item, "mined from " .. tostring(definition.block) .. " ore")
			end
		end
	end
	if EnemyDrops and EnemyDrops.Tables then
		for enemy, lines in pairs(EnemyDrops.Tables) do
			for _, line in ipairs(lines) do
				addSource(line.item, "dropped by " .. enemy)
			end
		end
	end
	if InventoryStore and type(InventoryStore.DefaultInventory) == "table" then
		for _, entry in ipairs(InventoryStore.DefaultInventory) do
			addSource(type(entry) == "table" and entry.name, "starter inventory")
		end
	end

	-- Development dispensers count as test-only, never as a player source.
	local dispensed = {}
	if PromptItemMappings then
		for prompt, items in pairs(PromptItemMappings) do
			if typeof(prompt) == "Instance" and type(items) == "table" then
				for _, entry in ipairs(items) do
					if type(entry) == "table" and type(entry.name) == "string" then
						dispensed[entry.name] = fullName(prompt)
					end
				end
			end
		end
	end

	local obtainable = {}
	for item in pairs(sources) do
		obtainable[item] = true
	end

	local changed = true
	while changed do
		changed = false
		for _, recipe in ipairs(recipes) do
			if not obtainable[recipe.output] then
				local ready = recipe.station == nil or obtainable[recipe.station] == true
				if ready then
					for ingredient in pairs(recipe.ingredients) do
						if not obtainable[ingredient] then
							ready = false
							break
						end
					end
				end
				if ready then
					obtainable[recipe.output] = true
					addSource(recipe.output, "crafted" .. (if recipe.station then " at " .. recipe.station else " by hand"))
					changed = true
				end
			end
		end
	end

	for _, name in ipairs(itemNames) do
		local definition = ItemDefinitions[name]
		if type(definition) ~= "table" or obtainable[name] then
			continue
		end

		local subject = itemLabel(name)
		local testOnly = ContentAudit.TestOnlyItems[name]

		if testOnly then
			add(report, "Exceptions", "Acquisition", subject, "admin/test-only: " .. testOnly
				.. (if dispensed[name] then " Also dispensed by " .. dispensed[name] .. "." else ""))
			continue
		end

		-- Recipes that make it, and what is stopping them.
		local blockers = {}
		for _, recipe in ipairs(recipes) do
			if recipe.output == name then
				local missing = {}
				if recipe.station and not obtainable[recipe.station] then
					table.insert(missing, "station " .. recipe.station)
				end
				for ingredient in pairs(recipe.ingredients) do
					if not obtainable[ingredient] then
						table.insert(missing, ingredient)
					end
				end
				table.sort(missing)
				table.insert(blockers, "CraftingRecipes." .. recipe.id .. " needs unobtainable " .. table.concat(missing, ", "))
			end
		end

		local message
		if #blockers > 0 then
			message = "unobtainable: " .. table.concat(blockers, "; ")
		elseif definition.dropOnly then
			message = "unobtainable: marked dropOnly, but no EnemyDrops table drops it"
		else
			message = "unobtainable: no recipe, drop, mining, harvest, starter or scroll source"
		end
		if dispensed[name] then
			message ..= " (only the development dispenser " .. dispensed[name] .. " hands it out)"
		end
		add(report, "Errors", "Acquisition", subject, message)
	end

	-- --------------------------------------------------------------- Consumables
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	for _, name in ipairs(itemNames) do
		local definition = ItemDefinitions[name]
		if type(definition) == "table" and definition.classification == "Consumable" then
			local handler = ContentAudit.UseHandlers[name]
			local subject = itemLabel(name)

			if not handler then
				add(report, "Errors", "Consumables", subject, "is a Consumable with no use behaviour registered; using it does nothing (add one, then list it in ContentAudit.UseHandlers)")
			else
				local handlerScript = ServerScriptService:FindFirstChild(handler.script)
				if not (handlerScript and handlerScript:IsA("Script")) then
					add(report, "Errors", "Consumables", subject, "use handler ServerScriptService." .. handler.script .. " is missing")
				end
				if handler.remote and not (remotes and remotes:FindFirstChild(handler.remote)) then
					add(report, "Errors", "Consumables", subject, "use remote ReplicatedStorage.Remotes." .. handler.remote .. " is missing")
				end
			end
		end
	end

	-- --------------------------------------------------------------- Buffs
	--[[
		Who reads which buff, and from what. Gear stats come from GearService
		itself, read from the gear slots; weapon stats from WeaponConfig, read
		from Weapons only.
	]]
	local consumers = {}

	if GearService and type(GearService.Stats) == "table" and InventoryConstants then
		local gearClasses = {}
		for index = 1, InventoryConstants.SlotCount or 0 do
			local restriction = InventoryConstants.getSlotRestriction(index)
			if restriction then
				gearClasses[restriction] = true
			end
		end
		for _, stat in ipairs(GearService.Stats) do
			consumers[stat] = { system = "ServerScriptService.GearService (worn gear)", classes = gearClasses }
		end
	end
	if WeaponConfig and type(WeaponConfig.BuffsRead) == "table" then
		for _, stat in ipairs(WeaponConfig.BuffsRead) do
			consumers[stat] = { system = "Shared.Combat.WeaponConfig", classes = { Weapon = true } }
		end
	end

	for _, name in ipairs(itemNames) do
		local definition = ItemDefinitions[name]
		local buffs = type(definition) == "table" and definition.buffs
		if type(buffs) == "table" then
			for _, buff in ipairs(sortedKeys(buffs)) do
				local subject = itemLabel(name) .. ".buffs." .. buff
				local consumer = consumers[buff]

				if type(buffs[buff]) ~= "number" then
					add(report, "Errors", "Buffs", subject, "is not a number")
				elseif not consumer then
					add(report, "Warnings", "Buffs", subject, "declared, but no gameplay system reads it - the item's description promises something that does not happen")
				elseif not consumer.classes[definition.classification] then
					local classes = sortedKeys(consumer.classes)
					add(report, "Warnings", "Buffs", subject, string.format(
						"%s only reads it from %s items, and this is a %s",
						consumer.system, table.concat(classes, "/"), tostring(definition.classification)
					))
				end
			end
		end
	end

	-- --------------------------------------------------------------- Audio
	if SoundConfig and type(SoundConfig.Sounds) == "table" then
		for _, key in ipairs(sortedKeys(SoundConfig.Sounds)) do
			local sound = SoundConfig.Sounds[key]
			local subject = string.format("Shared.Audio.SoundConfig.Sounds[%q]", key)
			checkId(report, "Audio", subject, sound.id, "id")
			if type(sound.layer) == "table" then
				checkId(report, "Audio", subject .. ".layer", sound.layer.id, "layer id")
			end
		end
	end
	if Music and type(Music.Playlist) == "table" then
		if #Music.Playlist == 0 then
			add(report, "Warnings", "Audio", "Shared.Audio.Music.Playlist", "is empty; there is no music")
		end
		for index, id in ipairs(Music.Playlist) do
			checkId(report, "Audio", string.format("Shared.Audio.Music.Playlist[%d]", index), id, "track")
		end
	end

	-- Sound and Animation instances authored into the place.
	local scanned = { ReplicatedStorage, StarterGui, StarterPlayer, SoundService, workspace }
	for _, root in ipairs(scanned) do
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("Sound") then
				local id = descendant.SoundId
				-- An empty SoundId on a Sound that scripts fill in at runtime
				-- (BackgroundMusic, a sound anchor) is normal, so only a bad one
				-- is reported.
				local format = idFormat(id)
				if format == "bad" then
					add(report, "Errors", "Audio", fullName(descendant), string.format("SoundId %q is not a valid asset id", id))
				elseif format == "legacy" then
					add(report, "Warnings", "Audio", fullName(descendant), string.format("SoundId %q uses the legacy roblox.com/asset URL", id))
				elseif isPlaceholderId(id) then
					add(report, "Placeholders", "Audio", fullName(descendant), "SoundId is a placeholder id")
				end
			elseif descendant:IsA("Animation") then
				checkId(report, "Animations", fullName(descendant), descendant.AnimationId, "AnimationId")
			end
		end
	end

	-- --------------------------------------------------------------- Animations
	if ToolConfig and type(ToolConfig.Animations) == "table" then
		for _, classification in ipairs(sortedKeys(ToolConfig.Animations)) do
			local id = ToolConfig.Animations[classification]
			local subject = "Shared.Tools.ToolConfig.Animations." .. classification
			if (id == nil or id == "") and ContentAudit.BlankAnimationsByDesign then
				add(report, "Exceptions", "Animations", subject, "blank by design: no swing animation exists yet (see ToolConfig.Animations)")
			else
				checkId(report, "Animations", subject, id, "animation")
			end
		end
	end
	for _, name in ipairs(itemNames) do
		local definition = ItemDefinitions[name]
		if type(definition) == "table" and definition.animation ~= nil then
			checkId(report, "Animations", itemLabel(name) .. ".animation", definition.animation, "animation")
		end
	end

	-- --------------------------------------------------------------- Abilities
	if AbilityConfig and type(AbilityConfig.Definitions) == "table" then
		local serverFolder = ServerScriptService:FindFirstChild("Abilities")
		local abilitiesShared = Shared:FindFirstChild("Abilities")
		local vfxFolder = abilitiesShared and abilitiesShared:FindFirstChild("VFX")

		for _, name in ipairs(sortedKeys(AbilityConfig.Definitions)) do
			local definition = AbilityConfig.Definitions[name]
			local subject = "AbilityConfig.Definitions." .. name

			local server = definition.server
			local serverModule = serverFolder and type(server) == "string" and serverFolder:FindFirstChild(server)
			if not (serverModule and serverModule:IsA("ModuleScript")) then
				add(report, "Errors", "Abilities", subject, string.format(
					"server module ServerScriptService.Abilities.%s is missing; casting it does nothing", tostring(server)
				))
			end

			local vfx = definition.vfx
			if vfx == nil then
				add(report, "Exceptions", "Abilities", subject, "has no VFX module (vfx = nil is allowed: no visuals)")
			else
				local vfxModule = vfxFolder and vfxFolder:FindFirstChild(vfx)
				if not (vfxModule and vfxModule:IsA("ModuleScript")) then
					add(report, "Errors", "Abilities", subject, "VFX module Shared.Abilities.VFX." .. tostring(vfx) .. " is missing")
				end

				local needs = ContentAudit.VfxAssets[vfx]
				if needs then
					for _, path in ipairs(needs) do
						if not findPath(vfxFolder, path) then
							add(report, "Errors", "Abilities", "Shared.Abilities.VFX." .. string.gsub(path, "/", "."),
								string.format("missing; %s loads it, so %s's effect will error", vfx, name))
						end
					end
				else
					add(report, "Warnings", "Abilities", subject, string.format(
						"VFX module %s has no entry in ContentAudit.VfxAssets, so the assets it loads are not checked", tostring(vfx)
					))
				end
			end

			if definition.animation == nil then
				local why = ContentAudit.NoCastAnimationByDesign[name]
				if why then
					add(report, "Exceptions", "Abilities", subject .. ".animation", "none by design: " .. why)
				else
					add(report, "Placeholders", "Abilities", subject .. ".animation", "no cast animation yet; the caster does not move when it fires")
				end
			else
				checkId(report, "Abilities", subject .. ".animation", definition.animation, "cast animation")
			end
		end

		local weapon = AbilityConfig.DefaultCastWeapon
		local subject = "AbilityConfig.DefaultCastWeapon"
		if type(weapon) ~= "string" or ItemDefinitions[weapon] == nil then
			add(report, "Errors", "Abilities", subject, string.format("'%s' is not an item", tostring(weapon)))
		else
			local template = toolsFolder and toolsFolder:FindFirstChild(weapon)
			if not (template and template:IsA("Tool")) then
				add(report, "Errors", "Abilities", subject, string.format(
					"'%s' has no Tool in ReplicatedStorage.Tools; Sacred Rain has nothing to draw when cast bare-handed", weapon
				))
			elseif ContentAudit.TestOnlyItems[weapon] then
				add(report, "Exceptions", "Abilities", subject, string.format(
					"is the test-only '%s'; swap it for a real weapon once one has a model", weapon
				))
			end
		end
	end

	report.finishedAt = os.clock()
	return report
end

-- ===========================================================================
-- Output
-- ===========================================================================

local function checkRank(check)
	return table.find(CHECK_ORDER, check) or #CHECK_ORDER + 1
end

local function sortFindings(list)
	table.sort(list, function(a, b)
		local rankA, rankB = checkRank(a.check), checkRank(b.check)
		if rankA ~= rankB then
			return rankA < rankB
		end
		return a.subject < b.subject
	end)
end

function ContentAudit.counts(report)
	local counts = {}
	for _, category in ipairs(CATEGORIES) do
		counts[category] = #report[category]
	end
	return counts
end

-- The whole report as lines, grouped and sorted, with the totals last.
function ContentAudit.format(report)
	local lines = { "===== BlockBound content audit =====" }

	for _, category in ipairs(CATEGORIES) do
		local list = report[category]
		sortFindings(list)

		table.insert(lines, "")
		table.insert(lines, string.format("---- %s (%d) ----", CATEGORY_TITLES[category], #list))
		for _, finding in ipairs(list) do
			table.insert(lines, string.format("[%s] %s - %s", finding.check, finding.subject, finding.message))
		end
	end

	local counts = ContentAudit.counts(report)
	table.insert(lines, "")
	table.insert(lines, string.format(
		"TOTALS: %d errors, %d warnings, %d placeholder, %d intentional exceptions (%.0f ms)",
		counts.Errors, counts.Warnings, counts.Placeholders, counts.Exceptions,
		((report.finishedAt or os.clock()) - report.startedAt) * 1000
	))
	table.insert(lines, "Not checked: whether each asset id actually loads or is permitted for this game - see Output for load failures.")

	return lines
end

-- Prints the whole report to Output, one finding per line so the dev console
-- does not truncate it. Runs the audit first if not given one.
function ContentAudit.printReport(report)
	report = report or ContentAudit.run()
	for _, line in ipairs(ContentAudit.format(report)) do
		print(line)
	end
	return report
end

-- A few lines for a player's screen: totals, and the first errors.
function ContentAudit.summarise(report, maxErrors)
	local counts = ContentAudit.counts(report)
	local lines = {
		string.format(
			"Content audit: %d errors, %d warnings, %d placeholder, %d intentional",
			counts.Errors, counts.Warnings, counts.Placeholders, counts.Exceptions
		),
	}

	sortFindings(report.Errors)
	for index = 1, math.min(maxErrors or 3, #report.Errors) do
		local finding = report.Errors[index]
		table.insert(lines, string.format("[%s] %s - %s", finding.check, finding.subject, finding.message))
	end

	return lines
end

return ContentAudit
