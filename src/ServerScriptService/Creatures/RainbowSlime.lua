--[[
	Rainbow Slime - the Hallow's rare giant slime. It moves and lunges like
	any slime, only bigger, tougher and harder-hitting; everything about it
	that is a slime is its EnemyConfig entry.

	What this adds is the colour. The model is the blue slime's textured mesh,
	and a texture cannot be tinted, so the rainbow is drawn by every client
	over the top (StarterPlayerScripts.CreatureFX): a hue-cycling sheen and a
	trail of rainbow glints. This only marks the model for it.
]]

local Trait = {}

function Trait.start(entry)
	entry.model:SetAttribute("Rainbow", true)
end

function Trait.step()
	return false
end

return Trait
