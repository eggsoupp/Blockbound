--[[
	Theme

	The game's UI vocabulary in one place: the inventory's own slot art, fonts,
	rarity colours and timings, so anything built against this matches it.
	Reskinning the UI means editing this file.
]]

local Theme = {}

-- ---------------------------------------------------------------------------
-- Assets taken from InventoryUI
-- ---------------------------------------------------------------------------

Theme.SlotImage = "rbxassetid://78805897944771"
Theme.SlotSize = 64
Theme.SlotPitch = 68

-- Slicing the framed square lets the same art stretch into wide buttons
-- without smearing the border.
Theme.SlotSlice = Rect.new(20, 20, 44, 44)

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

Theme.Rarity = {
	Common = Color3.fromRGB(163, 163, 163),
	Uncommon = Color3.fromRGB(120, 190, 120),
	Rare = Color3.fromRGB(63, 154, 48),
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
