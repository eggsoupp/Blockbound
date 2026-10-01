--[[
	VFXPalette

	Recolours an effect as it is built, without touching the data it is built
	from.

		VFXPalette.apply(value)   -- Color3 or ColorSequence in, recoloured out

	WHY NOT JUST EDIT THE COLOURS IN THE DATA

	SacredRainData is generated - its header says so, and regenerating it from
	the reference is a supported thing to do. Hand-editing three thousand lines
	of it would be undone by the next regeneration, and there is no way to tell
	by looking which of those colours somebody meant and which came out of the
	extractor.

	Applying the change at BUILD time instead means the data stays a faithful
	record of what was extracted, the palette stays one small file that says what
	it is doing, and turning it off is one word.

	WHAT IT CANNOT DO

	A ParticleEmitter's Color TINTS its texture; it does not replace it. So a
	sprite that is itself gold stays gold no matter what this does. Most VFX
	sprites are drawn white or grey precisely so they can be tinted, which is why
	this works at all - but if something still reads warm after this, that colour
	is baked into the image and only a different image will move it.
]]

local VFXPalette = {}

-- ===========================================================================
-- CONFIGURATION
-- ===========================================================================

--[[
	Off restores whatever the data says, which for Sacred Rain is the
	reference's gold.
]]
VFXPalette.Enabled = true

--[[
	Contrast applied to brightness after the colour is removed.

	Straight luminance leaves everything a flat mid-grey, because that is what
	desaturating a saturated colour honestly gives you. Pushing the result away
	from the middle is what turns "grey" into "black and white": highlights go to
	white, shadows go to black, and the effect keeps the shape it had.

	1.0 is plain desaturation. Above about 2.5 it starts clipping to pure black
	and pure white and losing the shape.
]]
VFXPalette.Contrast = 1.8

--[[
	Brightness floor and ceiling, after contrast.

	The floor is not zero on purpose: a particle at pure black is invisible
	against the night sky, and the darkest parts of this effect are smoke, which
	should read as dark rather than as absent.
]]
VFXPalette.Floor = 0.05
VFXPalette.Ceiling = 1.0

--[[
	Nudges the whole thing brighter.

	Zero, because the reference's own colours already span the full range - they
	run from pure black to a near-white cream, and the gold blade sits at 0.77
	luma, which the contrast above takes to white on its own. Lifting on top of
	that only drags the midtones up and turns black-and-white into white-on-grey.

	Raise it if the effect reads too dark against a night sky.
]]
VFXPalette.Lift = 0.0

-- ===========================================================================
-- CONVERSION
-- ===========================================================================

-- Rec. 709 luma. Weighted rather than a flat average because the eye reads
-- green as far brighter than blue, and a flat average turns gold into a muddier
-- grey than it looks.
local LUMA_R = 0.2126
local LUMA_G = 0.7152
local LUMA_B = 0.0722

local function toMono(color: Color3): Color3
	local luma = color.R * LUMA_R + color.G * LUMA_G + color.B * LUMA_B

	luma = 0.5 + (luma - 0.5) * VFXPalette.Contrast + VFXPalette.Lift
	luma = math.clamp(luma, VFXPalette.Floor, VFXPalette.Ceiling)

	return Color3.new(luma, luma, luma)
end

--[[
	Recolours a Color3 or a ColorSequence. Anything else is returned untouched,
	so this can be applied blindly to every property value without the caller
	having to know which ones are colours.
]]
function VFXPalette.apply(value: any): any
	if not VFXPalette.Enabled then
		return value
	end

	local kind = typeof(value)

	if kind == "Color3" then
		return toMono(value)
	end

	if kind == "ColorSequence" then
		local points = {}
		for index, keypoint in ipairs(value.Keypoints) do
			points[index] = ColorSequenceKeypoint.new(keypoint.Time, toMono(keypoint.Value))
		end
		return ColorSequence.new(points)
	end

	return value
end

return VFXPalette
