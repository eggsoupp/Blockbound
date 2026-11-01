--[[
	TutorialSteps

	What the tutorial says. The WORDS live here and nowhere else:
	Shared.UI.TutorialPanel and TutorialChoice draw what they are handed,
	StarterPlayerScripts.TutorialClient decides which step that is, and
	ServerScriptService.TutorialService decides when a step is finished.

		TutorialSteps.Steps             the guide's steps, in order
		TutorialSteps.byId("tree")      one step, or nil
		TutorialSteps.Choices           the Tab menu's three cards

	A step is

		{
			id = "tree",                 -- the server's step name
			title = "CHOP A TREE",
			body = "Hold your axe [{axe}] and click a tree.",
			goals = { "Chop down a tree" },
			action = "GO TO MY ISLAND",  -- optional button
		}

	Text in [square brackets] is drawn as a key. {braces} are filled in by
	TutorialClient from what the player is actually carrying: {axe} and
	{sword} are hotbar numbers, {key} is the chosen ability's key and {ability}
	its name, and {cast} is the chosen card's own `cast` line - a gust is not
	aimed the way a fireball is. Keep bodies to a line or two - the whole
	tutorial is meant to take a minute, and the guide is read while playing.
]]

local TutorialSteps = {}

TutorialSteps.Speaker = "THE WORLDKEEPER"

TutorialSteps.Steps = {
	{
		id = "tree",
		title = "CHOP A TREE",
		body = "Welcome to Blockbound. Hold your axe [{axe}] and click a tree to chop it down.",
		touchBody = "Welcome to Blockbound. Tap your axe [{axe}] in the hotbar, then tap a tree to chop it down.",
		goals = { "Chop down a tree" },
	},
	{
		id = "table",
		title = "CRAFT A TABLE",
		body = "Press [B] to craft. Turn your wood into planks, then build a table.",
		touchBody = "Tap [Craft] to craft. Turn your wood into planks, then build a table.",
		goals = { "Craft Wood Planks", "Craft a Crafting Table" },
	},
	{
		id = "ability",
		title = "CHOOSE YOUR POWER",
		body = "Something is coming. Press [Tab] to open your menu - your abilities live there - and pick one.",
		touchBody = "Something is coming. Tap [Menu] to open your menu - your abilities live there - and pick one.",
		goals = { "Choose an ability" },
	},
	{
		id = "fight",
		title = "DEFEAT THE SLIME",
		body = "{cast} Finish it with your sword [{sword}].",
		touchBody = "{cast} Finish it with your sword [{sword}] and the [ATTACK] button.",
		goals = { "Defeat the slime" },
	},
	{
		id = "island",
		title = "YOUR ISLAND AWAITS",
		body = "Well fought. Your island is yours to build on - take your crafting table home.",
		goals = { "Travel to your island" },
		action = "GO TO MY ISLAND",
	},
	{
		id = "done",
		title = "WELCOME HOME",
		body = "Place your crafting table and press [E] beside it for more recipes. [B] crafts by hand, [Tab] holds your powers.",
		touchBody = "Place your crafting table and tap its prompt for more recipes. [Craft] crafts by hand, [Menu] holds your powers.",
		goals = {},
	},
}

-- Said instead of a step's body while something is in the way of it.
TutorialSteps.Waits = {
	-- The table was made inside the crafting window, which has to close
	-- before the Tab menu can open.
	closeCrafting = "Nice work. Close the crafting window [B], then press [Tab] to choose a power.",
}

-- On the island step's button while the trip is starting, in place of its
-- label - the card keeps its words, so it does not jump under the cursor.
TutorialSteps.Travelling = "OPENING THE WAY..."

-- {cast} for a pick with no `cast` line of its own.
TutorialSteps.DefaultCast = "Press [{key}] to cast {ability} at it."

--[[
	The Tab menu's three cards, in the order they are laid out. `name` is the
	AbilityConfig key; everything else is how the card looks and reads.
	`color` is the element's, for the card's edge and its glyph. `cast` is
	how the fight step says to use it.
]]
TutorialSteps.Choices = {
	{
		name = "Fireball",
		blurb = "Hurls a ball of flame that bursts on impact.",
		cast = "Aim at it and press [{key}] to throw {ability}.",
		touchCast = "Face it and tap [{ability}] to throw it.",
		tags = "RANGED  ·  SPLASH",
		glyph = "fire",
		color = Color3.fromRGB(255, 132, 52),
		light = Color3.fromRGB(255, 220, 110),
	},
	{
		name = "WindBurst",
		blurb = "A gust that throws nearby enemies back.",
		cast = "Let it get close, then press [{key}] to blow it back with {ability}.",
		touchCast = "Let it get close, then tap [{ability}] to blow it back.",
		tags = "CLOSE  ·  KNOCKBACK",
		glyph = "wind",
		color = Color3.fromRGB(170, 232, 212),
		light = Color3.fromRGB(240, 255, 250),
	},
	{
		name = "WaterBlade",
		blurb = "A fast blade of water that cuts deep.",
		cast = "Aim at it and press [{key}] to loose {ability}.",
		touchCast = "Face it and tap [{ability}] to loose it.",
		tags = "RANGED  ·  HEAVY HIT",
		glyph = "water",
		color = Color3.fromRGB(70, 158, 255),
		light = Color3.fromRGB(180, 224, 255),
	},
}

TutorialSteps.ChoiceTitle = "CHOOSE YOUR POWER"
TutorialSteps.ChoiceSubtitle = "A slime is on its way. Pick a power to face it with - it's yours to keep."
TutorialSteps.ChosenTitle = "%s IS YOURS"
TutorialSteps.ChosenSubtitle = "Cast it with [%s]. The slime is waiting."

--[[
	A touch screen has no keys, so the lines that name one have a touch twin:
	a step's `touchBody`, a card's `touchCast`, and these. Buttons are named
	the way TouchControls labels them - [Craft], [Menu], [ATTACK], and each
	ability button by the ability's name. TutorialClient picks one or the other.
]]
TutorialSteps.Touch = {
	closeCrafting = "Nice work. Close the crafting window [Craft], then tap [Menu] to choose a power.",
	DefaultCast = "Face it and tap [{ability}] to cast it.",
	ChosenSubtitle = "Cast it with its button, bottom right. The slime is waiting.",
}

local byId = {}
for index, step in ipairs(TutorialSteps.Steps) do
	assert(type(step.id) == "string" and step.id ~= "", "[TutorialSteps] step " .. index .. " has no id")
	assert(byId[step.id] == nil, "[TutorialSteps] two steps share the id " .. step.id)
	step.index = index
	byId[step.id] = step
end

-- The steps the pips count: everything before "done".
TutorialSteps.Count = #TutorialSteps.Steps - 1

function TutorialSteps.byId(id: string?)
	return id and byId[id]
end

return TutorialSteps
