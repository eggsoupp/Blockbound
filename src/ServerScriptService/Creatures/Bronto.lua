--[[
	Bronto - a long-necked giant of the Swamp. An animal, and a gentle one
	until you hurt it (EnemyConfig `passive`). Then: it rears up and stomps
	the ground, a quake that hurts and slows everyone around it; it sweeps its
	great tail through anyone behind or beside it; and it bites from the end of
	its long neck. (Creatures.Beast; rig Shared.Enemies.CreatureRigs.Bronto.)
]]

local Beast = require(script.Parent.Beast)

return Beast.trait({
	rig = "Bronto",
	walkSpeed = 4.5,
	closeEnough = 4,
	moves = {
		{
			pose = "sweep", windup = 0.45, seconds = 1.1, cooldown = 3, where = "behind", range = 7,
			hit = { shape = "behind", radius = 8, damage = 14 },
		},
		{
			pose = "stomp", windup = 0.9, seconds = 1.5, cooldown = 6, where = "near", range = 6, lean = 0.35,
			hit = { shape = "around", radius = 7, damage = 12, slow = { 0.5, 1.5 }, fx = "slam" },
		},
		{
			pose = "bite", windup = 0.35, seconds = 0.8, cooldown = 1.6, where = "front", range = 6,
			hit = { shape = "reach", radius = 3, damage = 10, fx = "cut" },
		},
	},
})
