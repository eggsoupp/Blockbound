--[[
	Beisa Oryx - a long-horned antelope of the Desert. An animal: it grazes
	until you hurt it (EnemyConfig `passive`), and calls the rest of its small
	herd when you do. In front it gores with its horns; get behind it and it
	kicks. (Creatures.Beast; rig Shared.Enemies.CreatureRigs.BeisaOryx.)
]]

local Beast = require(script.Parent.Beast)

return Beast.trait({
	rig = "BeisaOryx",
	walkSpeed = 9,
	closeEnough = 2.4,
	herd = { radius = 28, pose = "gore", seconds = 0.5 },
	moves = {
		{
			pose = "kick", windup = 0.25, seconds = 0.6, cooldown = 1.8, where = "behind", range = 3.2,
			hit = { shape = "behind", radius = 3.6, damage = 8, fx = "slam" },
		},
		{
			pose = "gore", windup = 0.3, seconds = 0.6, cooldown = 1.4, where = "front", range = 3.4,
			hit = { shape = "reach", radius = 2.4, damage = 9, fx = "cut" },
		},
	},
})
