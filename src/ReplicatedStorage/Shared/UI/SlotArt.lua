--[[
	SlotArt

	Puts the game's slot frame on a tile or button: the parchment slot from the
	pixel-art kit, or its darker wooden twin.

		SlotArt.apply(tile)          -- an ImageButton or ImageLabel
		SlotArt.apply(tile, "dark")  -- the wooden slot, for gear and ingredients

	The art, its slicing and the plain frame drawn if it cannot load are all
	Shared.UI.PixelUI's; this stays so the inventory and the crafting window ask
	for "a slot" rather than for a sprite name, and agree on what one is.

	Tints scripts put on a tile's ImageColor3 - hover, drop target, disabled -
	show on the art, and on the stand-in frame if the art is missing.
]]

local PixelUI = require(script.Parent:WaitForChild("PixelUI"))

local SlotArt = {}

function SlotArt.apply(tile: GuiObject, variant: string?)
	PixelUI.apply(tile, if variant == "dark" then "slot_dark" else "slot")
end

return SlotArt
