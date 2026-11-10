--[[
	Abyssal Kraken - a hovering deep-sea horror of the Swamp (rig Shared.
	Enemies.VoxelRigs.AbyssalKraken, moves on VoxelMoves).

	TENTACLE SLAM (within 13). Both front tentacles reared high and slammed
	down in a line ahead: a crushing wave.
	GRAB (6-20). A tentacle lashes straight out; whoever it catches is hauled
	in, and the beak bites if they are still close.
	INK BURST (within 13). It pulls everything in, then bursts a cloud of ink
	round itself: it blinds, slows and stings anyone inside.
]]

local VoxelMoves = require(script.Parent.VoxelMoves)
local V = Vector3.new

local Tuning = {
	walkSpeed = 5.5,
	slamLength = 13,
	slamWidth = 3.5,
	slamDamage = 15,
	grabRange = 20,
	grabDamage = 7,
	biteReach = 7,
	biteDamage = 12,
	inkRadius = 13,
	inkSeconds = 4,
	inkDamage = 3,
}

return VoxelMoves.trait({
	rig = "AbyssalKraken",
	walkSpeed = Tuning.walkSpeed,
	closeTo = 6,
	gap = 0.6,
	moves = {
		{
			name = "slam", range = { 0, 13 }, cooldown = 3.6, weight = 2,
			track = 0.5,
			events = {
				hit = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					local look = VoxelMoves.look(entry)
					local a, b = feet + look * 3, feet + look * Tuning.slamLength
					VoxelMoves.fx("wave", "tide", a, b)
					VoxelMoves.fx("shake", b, 0.8, 45)
					VoxelMoves.hit(entry, VoxelMoves.along(a + Vector3.yAxis * 2, b + Vector3.yAxis * 2, Tuning.slamWidth), Tuning.slamDamage, {
						knock = { from = feet, speed = 40, lift = 35 },
					})
				end,
			},
		},
		{
			name = "grab", range = { 6, 20 }, cooldown = 9, weight = 1.2,
			track = 0.5, turnRate = 5,
			events = {
				lash = function(entry, move)
					local from = VoxelMoves.point(entry, V(6, 32, -6))
					local look = VoxelMoves.look(entry)
					local to = from + look * Tuning.grabRange
					local target = move.targetPosition
					if target and (target - from).Magnitude < Tuning.grabRange then
						to = target
					end
					VoxelMoves.fx("lash", "abyss", from, to)
					local caught = VoxelMoves.along(from, to, 3)
					move.caught = caught
					VoxelMoves.hit(entry, caught, Tuning.grabDamage, { pull = { to = VoxelMoves.ahead(entry, 4), speed = 85, lift = 18 } })
				end,
				pull = function(entry, move)
					if move.caught and #move.caught > 0 then
						VoxelMoves.hit(entry, move.caught, 0, { pull = { to = VoxelMoves.ahead(entry, 4), speed = 60, lift = 10 } })
					end
				end,
				bite = function(entry)
					local beak = VoxelMoves.point(entry, V(0, 22, -12))
					VoxelMoves.fx("burst", "abyssBite", beak, 1)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.hit(entry, VoxelMoves.inCone(feet, VoxelMoves.look(entry), Tuning.biteReach, 60, 8), Tuning.biteDamage)
				end,
			},
		},
		{
			name = "ink", range = { 0, 13 }, cooldown = 10, weight = 1,
			start = function(entry)
				VoxelMoves.fx("cast", "abyss", entry.model, "AbyssalKraken", "mantle", 0.8)
			end,
			events = {
				burst = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("burst", "inkBurst", VoxelMoves.point(entry, V(0, 34, 0)), 1.5)
					for _, player in ipairs(VoxelMoves.inCircle(feet, Tuning.inkRadius, 10)) do
						VoxelMoves.fxTo(player, "ink", 2.5)
					end
					VoxelMoves.zone(entry, feet, Tuning.inkRadius, Tuning.inkSeconds, 0.5, Tuning.inkDamage, "inkCloud", { 0.55, 1 })
				end,
			},
		},
	},
})
