--[[
	ToolConfig

	What a tool looks like when the game has to build one, and how it swings.

	Nothing is listed per item. "GoldPickaxe" resolves as:
	  shape     from the item's classification (Pickaxe/Weapon/Tool)
	  material  from the longest Materials key that prefixes the name -> "Gold"

	So a new tier is an ItemDefinitions entry plus, for a new metal, one
	Materials row. Units are studs; the handle is centred on the grip.
]]

local ToolConfig = {}

--[[
	Build stand-in Tools out of coloured boxes for holdable items with no
	authored asset in ReplicatedStorage.Tools?

	OFF, because a generated tool looks exactly like a real asset that failed to
	load, hiding the one thing you need to notice. With it off, an item without
	a model is not equippable and says so by name in the server log.

	Everything below feeds only those stand-ins and is inert while this is
	false. Kept so flipping it back is one word.
]]
ToolConfig.GenerateMissingTools = false

-- Matched as a PREFIX of the item name, longest first. Heads take the metal;
-- handles are wood throughout, which groups them as one family.
ToolConfig.Materials = {
	Wood = { color = Color3.fromRGB(146, 106, 62), material = Enum.Material.WoodPlanks },
	Stone = { color = Color3.fromRGB(126, 126, 126), material = Enum.Material.Slate },
	Copper = { color = Color3.fromRGB(196, 118, 66), material = Enum.Material.Metal },
	Iron = { color = Color3.fromRGB(206, 206, 206), material = Enum.Material.Metal },
	Gold = { color = Color3.fromRGB(226, 184, 62), material = Enum.Material.Metal },
	Mythril = { color = Color3.fromRGB(104, 214, 206), material = Enum.Material.Foil },
	Void = { color = Color3.fromRGB(128, 72, 196), material = Enum.Material.Neon },
	Test = { color = Color3.fromRGB(180, 180, 180), material = Enum.Material.SmoothPlastic },
}

ToolConfig.DefaultMaterial = {
	color = Color3.fromRGB(160, 160, 160),
	material = Enum.Material.SmoothPlastic,
}

ToolConfig.Handle = {
	size = Vector3.new(0.35, 3.0, 0.35),
	color = Color3.fromRGB(122, 88, 54),
	material = Enum.Material.WoodPlanks,
}

-- Boxes offset from the handle's centre. Deliberately chunky: the game is
-- voxel, and a blocky silhouette reads better in hand than a detailed mesh.
ToolConfig.Shapes = {
	Pickaxe = {
		{ size = Vector3.new(2.2, 0.42, 0.42), offset = Vector3.new(0, 1.5, 0) },
		{ size = Vector3.new(0.5, 0.38, 0.38), offset = Vector3.new(-0.95, 1.2, 0) },
		{ size = Vector3.new(0.5, 0.38, 0.38), offset = Vector3.new(0.95, 1.2, 0) },
	},
	Sword = {
		{ size = Vector3.new(0.28, 2.6, 0.14), offset = Vector3.new(0, 2.0, 0) },
		{ size = Vector3.new(1.1, 0.26, 0.26), offset = Vector3.new(0, 0.75, 0) },
	},
	Axe = {
		{ size = Vector3.new(1.0, 1.1, 0.34), offset = Vector3.new(0.55, 1.35, 0) },
		{ size = Vector3.new(0.42, 0.6, 0.3), offset = Vector3.new(0.05, 1.35, 0) },
	},

	--[[
		There is no Scroll shape any more.

		There was: a rolled tube for the two ScrollOf* items, which were held,
		clicked and consumed. Scrolls are objects in the world now
		(ServerScriptService.ScrollService), so nothing carries one and nothing
		needs a hand-held shape for it. The stand-in tube moved there, where it
		is a thing on the floor rather than a thing in a fist.
	]]
}

--[[
	Which classifications can be HELD at all.

	This table is the answer to that question, not just a lookup of what shape
	to build: ToolFactory refuses to make a template for anything not in it, and
	an item with no template cannot be equipped. So a classification that is not
	in here is one a player can own but never take out - which is the right
	answer for a material and the wrong one for a tool.
]]
ToolConfig.ShapeByClassification = {
	Pickaxe = "Pickaxe",
	Weapon = "Sword",
	Tool = "Axe",
}

ToolConfig.DefaultShape = "Pickaxe"

--[[
	Swing animation per classification: one rbxassetid, played on the wielder
	when they click. An item can overrule its class with `animation` in its own
	ItemDefinitions entry.

	Blank on purpose - there is no swing animation in this project, and an
	invented id would either fail to load or play something nobody chose. A tool
	with none still makes its sound and still hits; it just does not move. See
	ToolFeedback for why a procedural swing is not the fallback.
]]
ToolConfig.Animations = {
	Pickaxe = "",
	Weapon = "",
	Tool = "",
}

function ToolConfig.animationFor(classification, definition)
	local own = definition and definition.animation
	if type(own) == "string" and own ~= "" then
		return own
	end

	local shared = ToolConfig.Animations[classification]
	if type(shared) == "string" and shared ~= "" then
		return shared
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

function ToolConfig.materialFor(itemName)
	if type(itemName) ~= "string" then
		return ToolConfig.DefaultMaterial
	end

	local bestName, bestLength = nil, 0
	for name in pairs(ToolConfig.Materials) do
		if #name > bestLength and string.sub(itemName, 1, #name) == name then
			bestName, bestLength = name, #name
		end
	end

	return (bestName and ToolConfig.Materials[bestName]) or ToolConfig.DefaultMaterial
end

function ToolConfig.shapeFor(classification)
	local shapeName = ToolConfig.ShapeByClassification[classification] or ToolConfig.DefaultShape
	return ToolConfig.Shapes[shapeName] or ToolConfig.Shapes[ToolConfig.DefaultShape]
end

function ToolConfig.isHoldable(classification)
	return ToolConfig.ShapeByClassification[classification] ~= nil
end

return ToolConfig
