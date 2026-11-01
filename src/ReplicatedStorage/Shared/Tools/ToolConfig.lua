--[[
	ToolConfig

	What a tool looks like when the game has to build one, and how it swings.

	Nothing is listed per item. "GoldPickaxe" resolves as:
	  shape     from the item's classification (Pickaxe/Weapon/Tool)
	  material  from the longest Materials key that prefixes the name -> "Gold"

	So a new tier is an ItemDefinitions entry plus, for a new metal, one
	Materials row. Units are studs; the handle is centred on the grip.
]]

local RunService = game:GetService("RunService")

local SwingAnimations = require(script.Parent:WaitForChild("SwingAnimations"))

local ToolConfig = {}
local WeaponAnimations = require(script.Parent.Parent:WaitForChild("Combat"):WaitForChild("WeaponAnimations"))

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
	Swing animation per classification, played on the wielder: the name of one
	of Shared.Tools.SwingAnimations' swings (resolved by swingId below), or an
	rbxassetid. An item can overrule its class with `animation` in its own
	ItemDefinitions entry.

	The pickaxe's is the mining swing, and it is played differently: not per
	click by ToolFeedback but by MiningClient, LOOPED for as long as the button
	is held, at ToolConfig.miningAnimationRate of the pickaxe's miningSpeed.

	The axe ("Tool") chops once per StructureConfig.ChopSeconds, played by
	HarvestClient.

	Weapon is blank here because a weapon does not have A swing: it has the
	four-swing combo in Shared.Combat.SwordCombo, played by WeaponClient.
]]
local MINING_SWING = "rbxassetid://95795656805717"

ToolConfig.Animations = {
	Pickaxe = "PickaxeSwing",
	Weapon = "",
	Tool = "AxeChop",
}

--[[
	The published Animation for each SwingAnimations swing; "" until it is
	published (see SwingAnimations, PUBLISHING). Unpublished, Studio plays a
	preview of it and a live server plays its fallback below, if any.
]]
ToolConfig.SwingIds = {
	SwordSlash1 = "",
	SwordSlash2 = "",
	SwordSlash3 = "",
	SwordSlash4 = "",
	PickaxeSwing = "rbxassetid://87021460185064",
	AxeChop = "",
}

-- What a live server plays for a swing not yet published: the old mining
-- swing, so a pickaxe and an axe never stop moving. The sword has none.
ToolConfig.SwingFallbacks = {
	PickaxeSwing = MINING_SWING,
	AxeChop = MINING_SWING,
}

-- The id to play for a SwingAnimations swing: published, else a Studio
-- preview (client only, which is where animations are played), else the
-- fallback. nil plays nothing.
function ToolConfig.swingId(name)
	local published = ToolConfig.SwingIds[name]
	if type(published) == "string" and published ~= "" then
		return published
	end

	if RunService:IsStudio() and RunService:IsClient() then
		local preview = SwingAnimations.preview(name)
		if preview then
			return preview
		end
	end

	return ToolConfig.SwingFallbacks[name]
end

--[[
	How a pickaxe's miningSpeed becomes the mining swing's playback rate.

	A square root rather than straight across: speed runs from 0.6 (wood) to 5.5
	(skybreaker), and a swing played five times faster stops reading as a swing.
	This keeps the ladder visible - every tier swings a little quicker than the
	one before - inside a range that still looks like arms.

	    wood 0.77  copper 1.00  stone 1.18  iron 1.41  gold 1.64
	    mythril 1.90  void 2.24  skybreaker 2.25 (capped)
]]
ToolConfig.MiningSwing = {
	exponent = 0.5,
	minRate = 0.75,
	maxRate = 2.25,
}

function ToolConfig.miningAnimationRate(miningSpeed)
	local speed = tonumber(miningSpeed) or 1
	if speed <= 0 then
		speed = 1
	end

	local swing = ToolConfig.MiningSwing
	return math.clamp(speed ^ swing.exponent, swing.minRate, swing.maxRate)
end

--[[
	How a held tool is carried while WALKING, played by StarterPlayerScripts.
	ToolWalk in place of the ordinary walk for as long as the player walks.
	Weapons go by their ItemDefinitions `weaponClass` (see Shared.Combat.
	WeaponClasses); a pickaxe, an axe, empty hands or anything else use
	Default, which is the sword walk.

	The six walks and runs are Shared.Tools.LocomotionAnimations. Each id here
	is the published Animation for one of them; "" means not published yet, and
	ToolWalk then previews that gait in Studio and plays nothing in a live
	server. To publish: Save to Roblox each KeyframeSequence in
	ServerStorage.LocomotionAnimations, under the group that owns the game.
]]
local SWORD_WALK = "" -- SwordWalk
ToolConfig.WalkAnimations = {
	Default = SWORD_WALK,
	Sword = SWORD_WALK,
	HeavySword = "", -- HeavySwordWalk
	Lance = "", -- LanceWalk
}

-- The walking speed the walks were made for. Played at (speed / this), so a
-- crouch-walk at 8 strides at half pace instead of skating.
ToolConfig.WalkReferenceSpeed = 16

function ToolConfig.walkAnimationFor(definition)
	local class = definition and definition.weaponClass
	local profile = WeaponAnimations.Classes[class]
	if profile and profile.walk then return profile.walk end
	return (type(class) == "string" and ToolConfig.WalkAnimations[class]) or ToolConfig.WalkAnimations.Default
end

--[[
	The same, for SPRINTING with a tool out: ToolWalk plays these in place of the
	walks once the player is sprinting (spring-crouch-walk raises WalkSpeed past
	WalkReferenceSpeed) and actually moving at a run. Swords, pickaxes, axes and
	anything else (empty hands included) share the sword run; heavy swords and
	lances have their own. Ids as for WalkAnimations.
]]
local SWORD_RUN = "" -- SwordRun

ToolConfig.RunAnimations = {
	Default = SWORD_RUN,
	Sword = SWORD_RUN,
	HeavySword = "", -- HeavySwordRun
	Lance = "", -- LanceRun
}

-- The sprinting speed the runs were made for: spring-crouch-walk's RUN_SPEED.
ToolConfig.RunReferenceSpeed = 25

-- Below this, a sprinting player is not actually running (pushing into a wall,
-- slowed on a slope) and walks instead - spring-crouch-walk's own threshold
-- for its run, so the two always agree on which one the player is doing.
ToolConfig.RunMinimumSpeed = 10

-- Standing still with a tool out. Only classes listed here get one; the rest
-- keep the default idle.
ToolConfig.IdleAnimations = {
	Lance = "rbxassetid://82133398926621",
}

function ToolConfig.idleAnimationFor(definition)
	local class = definition and definition.weaponClass
	local profile = WeaponAnimations.Classes[class]
	if profile and profile.idle then return profile.idle end
	return type(class) == "string" and ToolConfig.IdleAnimations[class] or nil
end

function ToolConfig.runAnimationFor(definition)
	local class = definition and definition.weaponClass
	local profile = WeaponAnimations.Classes[class]
	if profile and profile.run then return profile.run end
	return (type(class) == "string" and ToolConfig.RunAnimations[class]) or ToolConfig.RunAnimations.Default
end

function ToolConfig.animationFor(classification, definition)
	local own = definition and definition.animation
	if type(own) ~= "string" or own == "" then
		own = ToolConfig.Animations[classification]
	end

	if type(own) ~= "string" or own == "" then
		return nil
	end

	-- A swing's name rather than an id.
	if ToolConfig.SwingIds[own] ~= nil then
		return ToolConfig.swingId(own)
	end

	return own
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
