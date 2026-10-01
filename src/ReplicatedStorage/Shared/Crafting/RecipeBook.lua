--[[
	RecipeBook

	Turns the hand-written ReplicatedStorage.CraftingRecipes into the validated,
	ordered, indexed form the crafting server and GUI both read - one table, one
	reader, so "the client showed me a recipe the server never heard of" cannot
	happen.

		{
			id          = "CopperPickaxe",
			output      = { item = "CopperPickaxe", count = 1 },
			ingredients = { { item = "CopperIngot", count = 3 }, ... },  -- sorted
			station     = "CraftingTable" | nil,  -- nil = craftable by hand
		}

	Ingredients are sorted by name so the list is stable between sessions;
	`pairs` order is not. A row naming an item or station that does not exist is
	dropped with a warning rather than taking the rest down.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CraftingRecipes = require(ReplicatedStorage:WaitForChild("CraftingRecipes"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local StationConfig = require(script.Parent:WaitForChild("StationConfig"))

local RecipeBook = {}

local recipesById = {}
local orderedRecipes = {}
local recipesByStation = {} -- stationId (or HandStation) -> array

local isBuilt = false

local function normalize(id, source)
	if type(source) ~= "table" then
		warn(string.format("[RecipeBook] '%s' is not a table; skipped.", tostring(id)))
		return nil
	end

	-- Output defaults to "one of the thing the key is named after", which is
	-- what every existing recipe means.
	local outputItem = id
	local outputCount = 1

	if type(source.output) == "table" then
		outputItem = source.output.item or id
		outputCount = tonumber(source.output.count) or 1
	elseif type(source.output) == "string" then
		outputItem = source.output
	end

	outputCount = math.max(1, math.floor(outputCount))

	if not ItemDefinitions[outputItem] then
		warn(string.format(
			"[RecipeBook] '%s' produces unknown item '%s'; skipped.", id, tostring(outputItem)
		))
		return nil
	end

	if type(source.ingredients) ~= "table" or next(source.ingredients) == nil then
		warn(string.format("[RecipeBook] '%s' has no ingredients; skipped.", id))
		return nil
	end

	local ingredients = {}
	for itemName, count in pairs(source.ingredients) do
		if not ItemDefinitions[itemName] then
			warn(string.format(
				"[RecipeBook] '%s' needs unknown item '%s'; skipped.", id, tostring(itemName)
			))
			return nil
		end

		local amount = math.floor(tonumber(count) or 0)
		if amount <= 0 then
			warn(string.format(
				"[RecipeBook] '%s' asks for %s x%s; skipped.", id, tostring(itemName), tostring(count)
			))
			return nil
		end

		table.insert(ingredients, { item = itemName, count = amount })
	end

	table.sort(ingredients, function(a, b)
		return a.item < b.item
	end)

	local station = source.station
	if station ~= nil and not StationConfig.get(station) then
		warn(string.format(
			"[RecipeBook] '%s' needs unknown station '%s'; skipped.", id, tostring(station)
		))
		return nil
	end

	return {
		id = id,
		output = { item = outputItem, count = outputCount },
		ingredients = ingredients,
		station = station,
	}
end

local function build()
	table.clear(recipesById)
	table.clear(orderedRecipes)
	table.clear(recipesByStation)

	for id, source in pairs(CraftingRecipes) do
		local recipe = normalize(id, source)
		if recipe then
			recipesById[id] = recipe
			table.insert(orderedRecipes, recipe)
		end
	end

	-- Stable presentation order: hand recipes first, then by station in the
	-- order StationConfig lists them, then alphabetically. That reads as a
	-- progression rather than as whatever `pairs` felt like today.
	local stationRank = { [StationConfig.HandStation] = 0 }
	for index, id in ipairs(StationConfig.Order) do
		stationRank[id] = index
	end

	table.sort(orderedRecipes, function(a, b)
		local rankA = stationRank[a.station or StationConfig.HandStation] or 999
		local rankB = stationRank[b.station or StationConfig.HandStation] or 999
		if rankA ~= rankB then
			return rankA < rankB
		end
		return a.id < b.id
	end)

	for _, recipe in ipairs(orderedRecipes) do
		local key = recipe.station or StationConfig.HandStation
		local list = recipesByStation[key]
		if not list then
			list = {}
			recipesByStation[key] = list
		end
		table.insert(list, recipe)
	end

	isBuilt = true
end

local function ensureBuilt()
	if not isBuilt then
		build()
	end
end

function RecipeBook.get(recipeId)
	ensureBuilt()
	if type(recipeId) ~= "string" then
		return nil
	end
	return recipesById[recipeId]
end

--[[
	Recipes usable at a given station. Pass nil (or StationConfig.HandStation)
	for the ones that need no station at all.
]]
function RecipeBook.getForStation(stationId)
	ensureBuilt()
	return recipesByStation[stationId or StationConfig.HandStation] or {}
end

function RecipeBook.getStats()
	ensureBuilt()

	local perStation = {}
	for station, list in pairs(recipesByStation) do
		perStation[station] = #list
	end

	return {
		recipes = #orderedRecipes,
		perStation = perStation,
	}
end

return RecipeBook
