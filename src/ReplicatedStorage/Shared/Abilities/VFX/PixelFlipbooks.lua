--[[
	PixelFlipbooks

	Pixel-art flipbook textures for ParticleEmitters, from the user's pixelVFX
	pack. assets/pixel-vfx/source/build_flipbooks.ps1 crops each sheet and
	repacks it into a 1024 px Grid8x8 of exactly 64 frames, so an emitter's
	FlipbookMode spans the whole animation.

	  Texture     group-owned Image id of the repacked PNG (the Decals the
	              group uploaded are flame 74719923713730, ring 112117687874283,
	              burst 78733676756112)
	  Loop        true: a looping animation (play with FlipbookMode Loop and
	              FlipbookFramerate); false: a one-shot over the lifetime
	  Up          which way the art points in its frame, for emitters that
	              orient particles along their velocity
]]

return {
	-- 9.png: a single tall flickering flame, tip at the top of the frame.
	FireFlame = { Texture = "rbxassetid://82723440850695", Loop = true, Up = "Top" },
	-- 7.png: a ring of fire chasing its own tail.
	FireRing = { Texture = "rbxassetid://139859698123667", Loop = true },
	-- 6.png: a crescent of flame swelling into a ring and scattering as cinders.
	FireBurst = { Texture = "rbxassetid://113218805499890", Loop = false },
}
