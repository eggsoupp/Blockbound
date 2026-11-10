--[[
	Mantis Reaver - a jade mantis of the Plains, fast and relentless (rig
	Shared.Enemies.VoxelRigs.MantisReaver, moves on VoxelMoves).

	CROSS SLASH (within 8). Both scythes crossed down through the space in
	front of it: a deep cut that bleeds.
	POUNCE (9-22). Wings flared, it leaps at you - the hop's lunge - and
	lands slashing.
	WHIRL (within 7). Arms flung wide, it spins twice, cutting everything
	around it.
]]

local VoxelMoves = require(script.Parent.VoxelMoves)

local Tuning = {
	walkSpeed = 9,
	slashReach = 8.5,
	slashArc = 70,
	slashDamage = 13,
	bleedTicks = 3,
	bleedDamage = 2,
	whirlRadius = 8,
	whirlDamage = 10,
	whirlSpin = 9,
}

return VoxelMoves.trait({
	rig = "MantisReaver",
	walkSpeed = Tuning.walkSpeed,
	closeTo = 5,
	gap = 0.35,
	moves = {
		{
			name = "xslash", range = { 0, 8 }, cooldown = 2.2, weight = 2,
			track = 0.3, turnRate = 6,
			events = {
				hit = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("slash", "jadeCross", entry.model, "MantisReaver", "rightBlade", 0.3)
					VoxelMoves.fx("slash", "jadeCross", entry.model, "MantisReaver", "leftBlade", 0.3)
					VoxelMoves.hit(entry, VoxelMoves.inCone(feet, VoxelMoves.look(entry), Tuning.slashReach, Tuning.slashArc), Tuning.slashDamage, {
						dot = { Tuning.bleedTicks, Tuning.bleedDamage, 0.7, "bleed" }, hitFx = "jadeHit",
					})
				end,
			},
		},
		{
			name = "pounce", range = { 9, 22 }, cooldown = 6, weight = 1.3,
			lunge = true,
			start = function(entry)
				VoxelMoves.fx("cast", "jade", entry.model, "MantisReaver", "head", 0.4)
			end,
		},
		{
			name = "whirl", range = { 0, 7 }, cooldown = 7, weight = 1,
			tick = function(entry, move, t, dt)
				if t > 0.3 and t < 1.15 then
					local look = VoxelMoves.look(entry)
					VoxelMoves.face(entry, CFrame.Angles(0, Tuning.whirlSpin * dt, 0):VectorToWorldSpace(look))
				end
			end,
			start = function(entry)
				VoxelMoves.fx("trail", "jadeWhirl", entry.model, "MantisReaver", "rightBlade", 0.9)
				VoxelMoves.fx("trail", "jadeWhirl", entry.model, "MantisReaver", "leftBlade", 0.9)
			end,
			events = {
				hit1 = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("ring", "jade", feet, Tuning.whirlRadius)
					VoxelMoves.hit(entry, VoxelMoves.inCircle(feet, Tuning.whirlRadius, 7), Tuning.whirlDamage, { hitFx = "jadeHit" })
				end,
				hit2 = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("ring", "jade", feet, Tuning.whirlRadius)
					VoxelMoves.hit(entry, VoxelMoves.inCircle(feet, Tuning.whirlRadius, 7), Tuning.whirlDamage, {
						hitFx = "jadeHit", knock = { from = feet, speed = 40, lift = 20 },
					})
				end,
			},
		},
	},
})
