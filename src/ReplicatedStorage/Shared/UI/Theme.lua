--[[
	Theme

	The game's UI vocabulary in one place: the inventory's own slot art, fonts,
	rarity colours and timings, so anything built against this matches it.
	Reskinning the UI means editing this file.
]]

local Theme = {}

-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------

-- The framed square itself is the pixel kit's "slot" sprite, put on through
-- UI.SlotArt; its asset id is Theme.Pixel's, below.

-- What a slot measures on a 1080p screen. The inventory scales these to the
-- real screen (see UI.InventoryLayout); the gap between slots is the difference.
Theme.SlotSize = 64
Theme.SlotPitch = 68

-- ---------------------------------------------------------------------------
-- Pixel art
-- ---------------------------------------------------------------------------

--[[
	The wood-and-parchment pixel-art kit every window except the Tab menu is
	drawn with: assets/pixel-ui, put on through Shared.UI.PixelUI.

	THE ART HAS TO BE UPLOADED, AND THESE ARE WHERE ITS IDS GO. Until then, or
	if an upload ever goes missing, PixelUI draws plain frames in the same
	colours instead and says so once in Output - nothing vanishes.

	Atlas is the easy way: assets/pixel-ui/atlas/pixel_ui_atlas.png, one upload
	holding every sprite. Images is per sprite, by name (the file names in
	assets/pixel-ui/sprites), and wins over the atlas for any sprite it lists -
	so if a sliced sprite ever draws wrongly off the atlas, uploading just that
	file and listing it here fixes it alone.

	Both want IMAGE ids. A Decal id will not display: paste it into any
	ImageLabel's Image in Studio, and Studio swaps it for the image id.
]]
Theme.Pixel = {
	-- assets/pixel-ui/atlas/pixel_ui_atlas.png, group-owned Image. Replaced
	-- 79592529682718 when the HUD sprites were added; every older sprite sits in
	-- the same place on both, so either id draws the windows.
	Atlas = "rbxassetid://107667103182017",
	Images = {
		-- button_green = "rbxassetid://...",
	},

	-- How many screen pixels one texel of the art covers, on a 1080p screen.
	Scale = 3,
}

-- Text drawn on the pixel panels. Parchment is light, so its text is dark ink;
-- wood is dark, so its text is cream.
Theme.PixelColor = {
	Ink = Color3.fromRGB(58, 36, 20),
	InkSoft = Color3.fromRGB(107, 74, 44),
	InkFaint = Color3.fromRGB(150, 118, 82),
	Heading = Color3.fromRGB(47, 85, 82),
	OnWood = Color3.fromRGB(246, 231, 193),
	OnWoodDim = Color3.fromRGB(205, 178, 138),
	OnGreen = Color3.fromRGB(18, 48, 31),
	Good = Color3.fromRGB(42, 133, 83),
	Bad = Color3.fromRGB(184, 64, 44),
	-- Good and bad on the dark pills and tooltips.
	GoodLight = Color3.fromRGB(158, 230, 176),
	BadLight = Color3.fromRGB(242, 160, 138),

	-- The selection highlight's tint: a warm gold that sits with the wood.
	Selection = Color3.fromRGB(255, 216, 74),

	-- ImageColor3 for a slot or picture that cannot be used right now. Lighter
	-- than Theme.Color.Disabled, which would turn parchment to mud.
	Disabled = Color3.fromRGB(178, 170, 160),

	-- The HUD bars' fills: one white sprite, painted with these as ImageColor3.
	-- Brighter than the colour they end up, since the sprite's body is a light
	-- grey and multiplying darkens it.
	HealthFill = Color3.fromRGB(120, 220, 110),
	HealthLow = Color3.fromRGB(255, 110, 90),
	ManaFill = Color3.fromRGB(110, 170, 255),
	ManaLow = Color3.fromRGB(140, 150, 230),
	BossFill = Color3.fromRGB(255, 96, 86),
	-- The streak a hit leaves behind the fill, and the red of a refused cast.
	BarGhost = Color3.fromRGB(255, 225, 180),
	BarFlash = Color3.fromRGB(255, 90, 80),
	-- A bar's wooden frame, tinted for a moment when it is hit.
	HitFlash = Color3.fromRGB(255, 140, 120),
	-- Text drawn over the bars: cream, outlined in the frame's dark brown.
	Outline = Color3.fromRGB(43, 24, 16),
}

-- Rarity colours are tuned for dark panels; on parchment the light ones (gold,
-- grey) wash out, so text there takes them a shade darker.
function Theme.rarityInk(rarity)
	return Theme.rarityColor(rarity):Lerp(Color3.new(0, 0, 0), 0.35)
end

--[[
	THE GAME'S FONT. Put your uploaded font family's asset id here and every
	piece of text in the game changes with it - this line is the whole job.

		Theme.FontFamily = "rbxassetid://1234567890"

	It has to be a FONT FAMILY asset, which is what Roblox gives you when you
	upload a font, not a plain image or mesh id.

	Two things read it. The four fonts below are built from it, which covers
	everything the game draws in code. StarterPlayerScripts.FontController
	covers the rest: it rewrites the family on every label authored in Studio -
	the inventory, the volume slider - and on anything created later, keeping
	each one's own weight. So "every text in the game" really is every text.

	Left empty, nothing happens at all and the built-in fonts below stay - so
	clearing this line is how you get Roblox's own fonts back.
]]
Theme.FontFamily = "rbxassetid://12187371840"

--[[
	Built from FontFamily when there is one, and from Roblox's own fonts when
	there is not.

	Two families deliberately, and the distinction survives a custom font
	because it is carried by WEIGHT rather than by family: Number and Heading
	are bold, Body is regular. A single-weight upload will simply render them
	all the same, which is fine and is Roblox's own fallback behaviour.
]]
local function themeFont(builtIn: string, weight: Enum.FontWeight): Font
	if Theme.FontFamily ~= "" then
		return Font.new(Theme.FontFamily, weight)
	end
	return Font.new(builtIn, weight)
end

local HIGHWAY = "rbxasset://fonts/families/HighwayGothic.json"
local SOURCE_SANS = "rbxasset://fonts/families/SourceSansPro.json"

Theme.Fonts = {
	Number = themeFont(HIGHWAY, Enum.FontWeight.Bold),
	Heading = themeFont(HIGHWAY, Enum.FontWeight.Bold),
	Body = themeFont(SOURCE_SANS, Enum.FontWeight.Regular),
	BodyBold = themeFont(SOURCE_SANS, Enum.FontWeight.SemiBold),
}

Theme.TextSize = {
	Count = 16,
	Small = 14,
	Body = 16,
	Subheading = 18,
	Heading = 22,
}

-- ---------------------------------------------------------------------------
-- Colour
-- ---------------------------------------------------------------------------

Theme.Color = {
	-- Panel stack, darkest at the back.
	Backdrop = Color3.fromRGB(0, 0, 0),
	Panel = Color3.fromRGB(24, 24, 28),
	PanelRaised = Color3.fromRGB(34, 34, 40),
	Stroke = Color3.fromRGB(72, 72, 82),
	Divider = Color3.fromRGB(52, 52, 60),

	Text = Color3.fromRGB(238, 238, 238),
	TextDim = Color3.fromRGB(152, 152, 160),
	TextFaint = Color3.fromRGB(104, 104, 112),

	Good = Color3.fromRGB(126, 208, 130),
	Bad = Color3.fromRGB(226, 92, 92),

	-- The mana bar. Blue because health is already green and the two sit one
	-- above the other - they have to be told apart at a glance, in peripheral
	-- vision, while something is trying to kill you. Low is the same warning
	-- the health bar gives, kept a shade cooler so it does not read as damage.
	Mana = Color3.fromRGB(86, 152, 232),
	ManaLow = Color3.fromRGB(96, 108, 168),

	-- The hotbar highlight colour. Selection anywhere should read the same.
	Accent = Color3.fromRGB(255, 242, 0),

	-- Applied as ImageColor3 to grey out something unavailable.
	Disabled = Color3.fromRGB(92, 92, 98),

	-- The pause menu's backdrop art. See UI.MenuBackdrop. The wireframe is
	-- nearly white with a green cast rather than green outright - a saturated
	-- line over a blurred world reads as a UI element, a pale one as light.
	MenuWash = Color3.fromRGB(7, 20, 14),
	MenuWire = Color3.fromRGB(206, 236, 214),
	MenuStreak = Color3.fromRGB(226, 240, 230),
	MenuGlint = Color3.fromRGB(245, 255, 248),
}

Theme.Transparency = {
	Backdrop = 0.45,
	Panel = 0.06,
	Selection = 0.35, -- matches the hotbar highlight
}

-- Grey, green, blue, purple, gold: the ladder players already know from other
-- games. Ground drops glow in these, so each step has to be told apart at a
-- glance on the floor as well as in the bag.
Theme.Rarity = {
	Common = Color3.fromRGB(163, 163, 163),
	Uncommon = Color3.fromRGB(120, 190, 120),
	Rare = Color3.fromRGB(52, 132, 236),
	Epic = Color3.fromRGB(128, 53, 182),
	Legendary = Color3.fromRGB(255, 204, 0),
	Unobtainable = Color3.fromRGB(0, 0, 0),
}

-- The ladder, weakest first. Unobtainable is NOT on it: it marks the Test
-- items as outside progression, not as a tier above Legendary.
Theme.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

function Theme.rarityColor(rarity)
	return Theme.Rarity[rarity] or Theme.Rarity.Common
end

function Theme.highestRarity()
	return Theme.RarityOrder[#Theme.RarityOrder]
end

-- Where a rarity sits, or 0 if it is not on the ladder.
function Theme.rarityRank(rarity)
	for index, name in ipairs(Theme.RarityOrder) do
		if name == rarity then
			return index
		end
	end
	return 0
end

-- ---------------------------------------------------------------------------
-- Motion
-- ---------------------------------------------------------------------------
-- Short and consistent. UI that takes a quarter second to acknowledge a click
-- feels broken however pretty it is.

Theme.Tween = {
	Hover = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Press = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Open = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Fade = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

Theme.Spacing = {
	Edge = 14, -- panel padding
	Gap = 10, -- between related elements
	Section = 18, -- between sections
}

return Theme
