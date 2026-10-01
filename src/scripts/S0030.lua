--[[
	PromptItemMappings

	Development item dispensers: a ProximityPrompt in the workspace, and what
	triggering it hands out.

	Keyed by the prompt INSTANCE, so the entries below have to resolve against
	whatever is actually in the place. They are looked up defensively rather than
	indexed directly - a missing part used to throw at require time and take the
	whole inventory server down with it, which is a harsh punishment for deleting
	a test part.

	To add a dispenser: give the part a ProximityPrompt and add a row to Sources
	with its path and payload.
]]

local PromptItemMappings = {}

--[[
	path  array of child names under Workspace, ending at the ProximityPrompt
	items what triggering it grants
]]
local Sources = {
	{
		path = { "SomePart", "ProximityPrompt" },
		items = {
			{ name = "Wood", amount = 9 },
			{ name = "WoodPlank", amount = 1 },
			{ name = "Stone", amount = 200 },
			{ name = "MagmaOre", amount = 10 },
			{ name = "TestSword", amount = 2 },
			{ name = "TestPickaxe", amount = 2 },
			{ name = "TestAxe", amount = 2 },
		},
	},
}

local function resolve(path)
	local current = workspace
	for _, name in ipairs(path) do
		current = current:FindFirstChild(name)
		if not current then
			return nil
		end
	end
	return current
end

for _, source in ipairs(Sources) do
	local prompt = resolve(source.path)
	if prompt then
		PromptItemMappings[prompt] = source.items
	else
		warn(string.format(
			"[PromptItemMappings] No prompt at Workspace.%s; that dispenser is inactive.",
			table.concat(source.path, ".")
		))
	end
end

return PromptItemMappings
