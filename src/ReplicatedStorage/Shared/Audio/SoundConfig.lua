--[[
	SoundConfig

	Every sound the game plays, and which blocks map to which material.

	===========================================================================
	PALETTE
	===========================================================================
	Asset ids are declared ONCE, below, and referenced by name everywhere else.
	Swapping the game's audio is editing the Palette table, not hunting through
	thirty entries.

	  Palette.UiSoft / UiClick   yours
	  everything else            Roblox built-in rbxasset:// sounds

	The built-ins are used because they are guaranteed to exist in every place,
	so a bad id can never make the game silently mute. They are shaped rather
	than used raw - see SHAPING below - which is what carries most of the
	character. When you have real SFX, replace the Palette entry and every sound
	built on it follows.

	===========================================================================
	SHAPING
	===========================================================================
	The same source asset becomes a different sound depending on how it is used,
	and this is where the blocky-material feel actually comes from:

	  pitch      stone is slow and heavy, wood is mid, sand is fast and airy
	  volume     things that fire often are mixed well under things that do not
	  pitchVary  +/- jitter per play, so a repeated sound is never identical
	  throttle   minimum gap between two plays of the same key
	  layer      a second sound played on top, for weight - a break is a thud
	             AND a crack, which reads as one richer sound rather than two

	===========================================================================
	MATERIAL GROUPS
	===========================================================================
	Mining and placement pick their sound from the BLOCK's material group, so
	digging sand sounds different from chipping stone. Blocks match by exact name
	first, then by the suffix rules, then the default. Adding a block usually
	needs nothing here; adding an ore needs nothing at all, because "...Ore"
	already routes to the ore group.
]]

local SoundConfig = {}

-- ---------------------------------------------------------------------------
-- Palette
-- ---------------------------------------------------------------------------

local Palette = {
	-- A soft, short interface blip. Used for hovers and light interactions.
	UiSoft = "rbxassetid://421058925",

	-- The heavier click this project has always used for committing actions.
	UiClick = "rbxassetid://6895079853",

	-- A dry, short tap. The workhorse for block impacts: pitched right down it
	-- is stone, up it is wood.
	Tap = "rbxasset://sounds/action_footsteps_plastic.mp3",

	-- Airy and granular. Sand and snow.
	Granular = "rbxasset://sounds/action_swim.mp3",

	-- A short scrape with a tail, for a block finally giving way.
	Crumble = "rbxasset://sounds/action_get_up.mp3",

	-- Wet, soft. Snow and water.
	Soft = "rbxasset://sounds/impact_water.mp3",

	-- A clean metallic ping. Ore, and crafting confirmations.
	Chime = "rbxasset://sounds/electronicpingshort.wav",

	-- A low body thump. Refusals, and the bottom end of heavy sounds.
	Thump = "rbxasset://sounds/bass.wav",

	-- Mechanical clicks, for panels and placement.
	Clack = "rbxasset://sounds/switch3.wav",
	ClackLow = "rbxasset://sounds/switch.wav",

	-- Air moving. Tool swings.
	Swoosh = "rbxasset://sounds/swoosh.wav",
}

SoundConfig.Palette = Palette

-- ---------------------------------------------------------------------------
-- Library
-- ---------------------------------------------------------------------------
--
--   id         asset to play
--   volume     0-1
--   pitch      base PlaybackSpeed
--   pitchVary  +/- random jitter applied per play
--   throttle   minimum seconds between two plays of this key
--   layer      { id, volume, pitch, pitchVary } played simultaneously

SoundConfig.Sounds = {
	-- === UI ===============================================================
	-- Hover is the most-repeated sound in the game, so it is quiet, jittered
	-- and throttled hard. It should register without ever being noticed.
	["ui.hover"] = { id = Palette.UiSoft, volume = 0.12, pitch = 1.35, pitchVary = 0.07, throttle = 0.05 },

	["ui.click"] = { id = Palette.UiClick, volume = 0.4, pitch = 1.0, pitchVary = 0.04 },
	["ui.tab"] = { id = Palette.UiSoft, volume = 0.22, pitch = 1.0, pitchVary = 0.05 },

	["ui.open"] = {
		id = Palette.Clack,
		volume = 0.3,
		pitch = 1.1,
		pitchVary = 0.03,
		layer = { id = Palette.UiSoft, volume = 0.16, pitch = 0.9 },
	},
	["ui.close"] = { id = Palette.ClackLow, volume = 0.26, pitch = 0.92, pitchVary = 0.03 },

	-- Refusal: a low body thump, no top end. Reads as "no" without being shrill.
	["ui.denied"] = { id = Palette.Thump, volume = 0.32, pitch = 1.5, pitchVary = 0.03, throttle = 0.12 },

	-- === Crafting =========================================================
	-- Success is a chime over a clack, so it lands as a "made a thing" rather
	-- than a menu beep.
	["craft.success"] = {
		id = Palette.Chime,
		volume = 0.45,
		pitch = 1.45,
		pitchVary = 0.04,
		layer = { id = Palette.Clack, volume = 0.28, pitch = 0.8 },
	},
	["craft.fail"] = { id = Palette.Thump, volume = 0.34, pitch = 1.25, pitchVary = 0.03 },

	-- === Tools ============================================================
	["tool.swing"] = { id = Palette.Swoosh, volume = 0.22, pitch = 1.3, pitchVary = 0.14, throttle = 0.08 },
	["tool.equip"] = { id = Palette.ClackLow, volume = 0.22, pitch = 1.5, pitchVary = 0.06 },

	-- === Abilities ========================================================
	-- Not from the Palette: these two ids, both volumes and the 0.8-1.2 pitch
	-- jitter are the SacredSwords reference's own, created in code by the
	-- script under StarterPack.Gate.Event. Deliberately NOT throttled - a cast
	-- fires fifteen of each and the overlap is the sound.
	--
	-- The one number that is this game's rather than the reference's is `range`.
	-- The reference leaves rolloff at the engine default, which is effectively
	-- global; a barrage that lands eighty studs away should be audible without
	-- being audible across the whole world.
	["ability.sacredrain.portal"] = {
		id = "rbxassetid://137782657646699",
		volume = 1,
		pitch = 1.0,
		pitchVary = 0.2,
		range = 300,
	},
	["ability.sacredrain.impact"] = {
		id = "rbxassetid://105248065965594",
		volume = 2,
		pitch = 1.0,
		pitchVary = 0.2,
		range = 300,
	},

	--[[
		Eclipse: the same two ids, pitched down.

		Not laziness and not a placeholder. There are exactly two ability sounds
		in this project, both from the reference, and nothing else to point at
		that has been heard - so rather than invent ids that might be silence,
		might be a cough, and cannot be checked from here, the ability borrows
		the ones that are known to load and separates itself with pitch.

		Dropping the portal to 0.55 and the impact to 0.62 puts both well below
		anything Sacred Rain plays, which is what stops the two abilities
		sounding like the same event; the wide pitchVary on the burst is what
		stops repeated casts sounding mechanical. Put real ids here when there
		are real ids to put.
	]]
	["ability.eclipse.charge"] = {
		id = "rbxassetid://137782657646699",
		volume = 1.1,
		pitch = 0.5,
		pitchVary = 0.05,
		range = 320,
	},

	--[[
		The burst, layered with a second copy of itself an octave and a half
		down.

		Two things make a sound feel big, and only one of them is volume. The
		other is having a body under it: the same hit at 0.62 and again at 0.34
		reads as one impact with weight rather than as one impact played loudly,
		because the low copy arrives as pressure rather than as a noise.

		The range is nearly the whole broadcast radius - an endgame blast that
		can be seen from across the map should be audible from there too.
	]]
	["ability.eclipse.burst"] = {
		id = "rbxassetid://105248065965594",
		volume = 3,
		pitch = 0.62,
		pitchVary = 0.08,
		range = 480,
		-- The layer carries its own range: playLayer defaults to 90 studs, which
		-- would drop the body off long before the sound it belongs to.
		layer = { id = "rbxassetid://105248065965594", volume = 2.4, pitch = 0.34, range = 480 },
	},

	-- The second wave, half a second later: the same hit, quieter and lower
	-- still, so it reads as the blast settling rather than as another one.
	["ability.eclipse.aftershock"] = {
		id = "rbxassetid://105248065965594",
		volume = 1.3,
		pitch = 0.42,
		pitchVary = 0.06,
		range = 420,
	},

	-- === Placement ========================================================
	-- A block landing: the material's own tap, with a low thump under it for
	-- weight. This is the sound the player hears most while building.
	["place.stone"] = {
		id = Palette.Tap,
		volume = 0.5,
		pitch = 0.55,
		pitchVary = 0.07,
		layer = { id = Palette.Thump, volume = 0.16, pitch = 2.4 },
	},
	["place.soft"] = { id = Palette.Tap, volume = 0.42, pitch = 0.95, pitchVary = 0.09 },
	["place.sand"] = { id = Palette.Granular, volume = 0.34, pitch = 1.35, pitchVary = 0.1 },
	["place.wood"] = {
		id = Palette.Tap,
		volume = 0.46,
		pitch = 1.15,
		pitchVary = 0.07,
		layer = { id = Palette.Thump, volume = 0.12, pitch = 2.8 },
	},
	["place.ore"] = { id = Palette.Tap, volume = 0.5, pitch = 0.45, pitchVary = 0.06 },
	["place.station"] = {
		id = Palette.Clack,
		volume = 0.45,
		pitch = 0.75,
		pitchVary = 0.05,
		layer = { id = Palette.Tap, volume = 0.3, pitch = 0.9 },
	},

	-- === Mining: the tick while you are chipping away ======================
	-- Quiet and heavily jittered; several of these fire per block.
	["mine.hit.stone"] = { id = Palette.Tap, volume = 0.18, pitch = 0.5, pitchVary = 0.14, throttle = 0.05 },
	["mine.hit.soft"] = { id = Palette.Tap, volume = 0.15, pitch = 0.85, pitchVary = 0.16, throttle = 0.05 },
	["mine.hit.sand"] = { id = Palette.Granular, volume = 0.14, pitch = 1.5, pitchVary = 0.18, throttle = 0.05 },
	["mine.hit.wood"] = { id = Palette.Tap, volume = 0.18, pitch = 1.1, pitchVary = 0.13, throttle = 0.05 },
	["mine.hit.ore"] = { id = Palette.Tap, volume = 0.22, pitch = 0.4, pitchVary = 0.1, throttle = 0.05 },

	-- === Mining: the block giving way =====================================
	-- Each is a crumble plus the material's own colour on top.
	["mine.break.stone"] = {
		id = Palette.Crumble,
		volume = 0.42,
		pitch = 1.45,
		pitchVary = 0.08,
		layer = { id = Palette.Tap, volume = 0.3, pitch = 0.5 },
	},
	["mine.break.soft"] = {
		id = Palette.Crumble,
		volume = 0.36,
		pitch = 1.85,
		pitchVary = 0.09,
		layer = { id = Palette.Tap, volume = 0.2, pitch = 0.85 },
	},
	["mine.break.sand"] = {
		id = Palette.Granular,
		volume = 0.34,
		pitch = 1.0,
		pitchVary = 0.09,
		layer = { id = Palette.Soft, volume = 0.18, pitch = 1.6 },
	},
	["mine.break.wood"] = {
		id = Palette.Crumble,
		volume = 0.42,
		pitch = 1.65,
		pitchVary = 0.08,
		layer = { id = Palette.Tap, volume = 0.26, pitch = 1.1 },
	},
	-- Ore is the payoff, so it gets the chime the crafting success uses.
	["mine.break.ore"] = {
		id = Palette.Crumble,
		volume = 0.4,
		pitch = 1.3,
		pitchVary = 0.06,
		layer = { id = Palette.Chime, volume = 0.3, pitch = 1.15 },
	},
}

-- ---------------------------------------------------------------------------
-- Material groups
-- ---------------------------------------------------------------------------

SoundConfig.DefaultGroup = "stone"

-- Exact block name -> group.
SoundConfig.BlockGroups = {
	Grass = "soft",
	Dirt = "soft",
	CorruptedDirt = "soft",
	CrimsonDirt = "soft",
	HallowedDirt = "soft",

	Sand = "sand",
	Snow = "sand",

	Stone = "stone",
	Sandstone = "stone",
	Cobblestone = "stone",
	StoneBricks = "stone",
	MagmaBrick = "stone",
	CorruptedStone = "stone",
	CrimsonStone = "stone",
	HallowedStone = "stone",
	Bedrock = "stone",

	WoodPlank = "wood",
	Wood = "wood",

	Water = "sand",
}

-- Fallbacks applied when the exact name is unknown. Checked in order.
SoundConfig.SuffixGroups = {
	{ suffix = "Ore", group = "ore" },
	{ suffix = "Ingot", group = "ore" },
	{ suffix = "Stone", group = "stone" },
	{ suffix = "Brick", group = "stone" },
	{ suffix = "Bricks", group = "stone" },
	{ suffix = "Dirt", group = "soft" },
	{ suffix = "Plank", group = "wood" },
}

--[[
	Material group for a block name. Never returns nil.
]]
function SoundConfig.groupFor(blockName)
	if type(blockName) ~= "string" or blockName == "" then
		return SoundConfig.DefaultGroup
	end

	local exact = SoundConfig.BlockGroups[blockName]
	if exact then
		return exact
	end

	for _, rule in ipairs(SoundConfig.SuffixGroups) do
		if string.sub(blockName, -#rule.suffix) == rule.suffix then
			return rule.group
		end
	end

	return SoundConfig.DefaultGroup
end

--[[
	Convenience: the full sound key for an action on a block.
	  SoundConfig.keyFor("mine.hit", "CoalOre") -> "mine.hit.ore"
]]
function SoundConfig.keyFor(prefix, blockName)
	return prefix .. "." .. SoundConfig.groupFor(blockName)
end

return SoundConfig
