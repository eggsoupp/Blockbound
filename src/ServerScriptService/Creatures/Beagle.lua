--[[
	Beagle - a hound of the Plains, in packs. An animal: it leaves you alone
	until you hurt it (EnemyConfig `passive`). Hurt one and it barks, and every
	beagle nearby comes for you too. Then they bite. (Creatures.Beast; rig
	Shared.Enemies.CreatureRigs.Beagle.)
]]

local Beast = require(script.Parent.Beast)

return Beast.trait({
	rig = "Beagle",
	walkSpeed = 10,
	closeEnough = 1.8,
	herd = { radius = 30, pose = "bark", seconds = 0.8 },
	moves = {
		{
			pose = "bite", windup = 0.2, seconds = 0.45, cooldown = 1.1, where = "front", range = 2.6,
			hit = { shape = "reach", radius = 1.8, damage = 5, fx = "cut" },
		},
	},
})
