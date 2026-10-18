--[[
	StationConfig

	The crafting stations that exist in the world. Which recipes each unlocks is
	CraftingRecipes' business, so adding a station is this table plus an
	ItemDefinitions entry, and adding recipes touches nothing here.

	  id           must match the ItemDefinitions key for the placeable item.
	  displayName  crafting window title and interaction prompt.
	  actionText   verb on the ProximityPrompt.
	  useRange     studs. Enforced on the SERVER; the prompt's own
	               MaxActivationDistance only makes the label appear.
	  modelSource  optional child of TerrainAssets.Stations to clone; wins over
	               `appearance` entirely.
	  appearance   stand-in built when there is no authored model.

	A STORAGE STATION is one with `storage`: the number of slots it holds.
	It is placed, picked up and saved like any other station, but it crafts
	nothing - the crafting window never sees it - and its prompt opens it
	(StarterPlayerScripts.ChestClient, ServerScriptService.ChestServer).
	Its contents are saved with the island, on the station's own record.

	  storage      slots it holds
	  islandOnly   refuses to be placed outside an island. The open world
	               saves nothing across servers, so a chest out there would
	               lose everything in it the moment the server closed.

	Recipes with no `station` are craftable anywhere; HandStation is the
	internal name for that and is deliberately not a placeable definition.
]]

local StationConfig = {}

StationConfig.HandStation = "Hand"

-- Folder under ReplicatedStorage.TerrainAssets searched for authored models.
StationConfig.ModelFolderName = "Stations"

-- Where placed stations live in the workspace.
StationConfig.WorldFolderName = "CraftingStations"

StationConfig.Definitions = {
	CraftingTable = {
		id = "CraftingTable",
		displayName = "Crafting Table",
		actionText = "Craft",
		useRange = 20,
		appearance = {
			color = Color3.fromRGB(129, 94, 57),
			topColor = Color3.fromRGB(163, 124, 78),
			material = Enum.Material.WoodPlanks,
		},
	},

	Furnace = {
		id = "Furnace",
		displayName = "Furnace",
		actionText = "Smelt",
		useRange = 20,
		appearance = {
			color = Color3.fromRGB(96, 96, 100),
			topColor = Color3.fromRGB(72, 72, 76),
			material = Enum.Material.Cobblestone,
		},
	},

	Anvil = {
		id = "Anvil",
		displayName = "Anvil",
		actionText = "Forge",
		useRange = 20,
		appearance = {
			color = Color3.fromRGB(70, 72, 78),
			topColor = Color3.fromRGB(104, 107, 114),
			material = Enum.Material.Metal,
		},
	},

	AlchemyBench = {
		id = "AlchemyBench",
		displayName = "Alchemy Bench",
		actionText = "Brew",
		useRange = 20,
		appearance = {
			color = Color3.fromRGB(74, 108, 88),
			topColor = Color3.fromRGB(126, 196, 154),
			material = Enum.Material.Glass,
		},
	},

	ArcaneForge = {
		id = "ArcaneForge",
		displayName = "Arcane Forge",
		actionText = "Fuse",
		useRange = 20,
		appearance = {
			color = Color3.fromRGB(64, 48, 102),
			topColor = Color3.fromRGB(148, 108, 226),
			material = Enum.Material.Neon,
		},
	},

	EnchantingTable = {
		id = "EnchantingTable",
		displayName = "Enchanting Table",
		actionText = "Enchant",
		useRange = 20,
		appearance = {
			color = Color3.fromRGB(48, 46, 74),
			topColor = Color3.fromRGB(96, 132, 220),
			material = Enum.Material.Marble,
		},
	},

	-- Three rows of nine, the bag's width. The model is
	-- TerrainAssets.Stations.Chest; until there is one it is a wooden box.
	Chest = {
		id = "Chest",
		displayName = "Chest",
		actionText = "Open",
		useRange = 12,
		storage = 27,
		islandOnly = true,
		appearance = {
			color = Color3.fromRGB(122, 84, 46),
			topColor = Color3.fromRGB(150, 106, 60),
			material = Enum.Material.WoodPlanks,
		},
	},
}

StationConfig.Order = {
	"CraftingTable",
	"Furnace",
	"Anvil",
	"AlchemyBench",
	"ArcaneForge",
	"EnchantingTable",
	"Chest",
}

function StationConfig.get(stationId)
	if type(stationId) ~= "string" then
		return nil
	end
	return StationConfig.Definitions[stationId]
end

--[[
	Human-readable name for a station id, including the hand-crafting
	pseudo-station. Used by the GUI and by error messages.
]]
function StationConfig.getDisplayName(stationId)
	if stationId == nil or stationId == StationConfig.HandStation then
		return "Hand"
	end

	local def = StationConfig.Definitions[stationId]
	return (def and def.displayName) or stationId
end

-- Whether a station holds items rather than crafting them. See the header.
function StationConfig.isStorage(stationId)
	local def = StationConfig.get(stationId)
	return def ~= nil and def.storage ~= nil
end

function StationConfig.validate()
	for _, id in ipairs(StationConfig.Order) do
		local def = StationConfig.Definitions[id]
		assert(def, string.format("[StationConfig] '%s' is in Order but has no definition", id))
		assert(def.id == id, string.format("[StationConfig] '%s' has a mismatched id field", id))
		assert(
			type(def.useRange) == "number" and def.useRange > 0,
			string.format("[StationConfig] '%s' needs a positive useRange", id)
		)
		assert(
			def.storage == nil
				or (type(def.storage) == "number" and def.storage >= 1 and def.storage <= 99 and def.storage % 1 == 0),
			string.format("[StationConfig] '%s' storage must be a whole number of slots, 1 to 99", id)
		)
	end
end

return StationConfig
