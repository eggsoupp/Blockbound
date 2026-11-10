--[[
	Gloomrider - a death knight on a skeletal warhorse, of the Crimson (rig
	Shared.Enemies.VoxelRigs.Gloomrider, moves on VoxelMoves).

	CHARGE (10-40). The lance comes down to the couch and the horse rears;
	then it gallops straight through, skewering and flinging anyone in the
	way, trailing ghost fire.
	LANCE SWEEP (within 10). The lance swept flat across in front of it.
	REARING STOMP (within 9). The horse rears high and crashes down: a
	shockwave, and a ring of ghost fire that keeps burning.
]]

local VoxelMoves = require(script.Parent.VoxelMoves)
local V = Vector3.new

local Tuning = {
	walkSpeed = 9,
	chargeSpeed = 38,
	chargeDamage = 18,
	sweepReach = 11,
	sweepArc = 80,
	sweepDamage = 13,
	stompRadius = 8,
	stompDamage = 15,
	fireSeconds = 3,
	fireDamage = 3,
}

return VoxelMoves.trait({
	rig = "Gloomrider",
	walkSpeed = Tuning.walkSpeed,
	closeTo = 7,
	gap = 0.6,
	moves = {
		{
			name = "charge", range = { 10, 40 }, cooldown = 8, weight = 1.6,
			track = 0.75, turnRate = 3,
			start = function(entry)
				VoxelMoves.fx("cast", "ghost", entry.model, "Gloomrider", "visor", 0.8)
			end,
			events = {
				go = function(entry)
					VoxelMoves.fx("trail", "ghostCharge", entry.model, "Gloomrider", "chest", 1.1)
				end,
			},
			tick = function(entry, move, t, dt)
				local marks = move.clip.marks
				if t >= marks.go and t < marks.stop and not move.stopped then
					if not VoxelMoves.rush(entry, Tuning.chargeSpeed, dt) then
						move.stopped = true
						VoxelMoves.fx("burst", "ghostImpact", VoxelMoves.point(entry, V(0, 30, -24)), 1.2)
					end
					local front = VoxelMoves.point(entry, V(0, 30, -26))
					for _, player in ipairs(VoxelMoves.inCircle(front, 6, 9)) do
						if not move.hitSet[player] then
							move.hitSet[player] = true
							VoxelMoves.fx("burst", "ghostImpact", front, 1)
							VoxelMoves.hit(entry, { player }, Tuning.chargeDamage, {
								knock = { from = VoxelMoves.Kit.feet(entry), speed = 70, lift = 45 },
							})
						end
					end
				end
			end,
		},
		{
			name = "sweep", range = { 0, 10 }, cooldown = 2.8, weight = 2,
			track = 0.3, turnRate = 5,
			events = {
				hit = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("arc", "ghost", feet + Vector3.yAxis * 7, VoxelMoves.look(entry), Tuning.sweepReach)
					VoxelMoves.hit(entry, VoxelMoves.inCone(feet, VoxelMoves.look(entry), Tuning.sweepReach, Tuning.sweepArc, 9), Tuning.sweepDamage, {
						knock = { from = feet, speed = 35, lift = 15 }, hitFx = "ghostImpact",
					})
				end,
			},
		},
		{
			name = "stomp", range = { 0, 9 }, cooldown = 8, weight = 1.1,
			start = function(entry)
				VoxelMoves.fx("cast", "ghost", entry.model, "Gloomrider", "visor", 0.85)
			end,
			events = {
				hit = function(entry)
					local at = VoxelMoves.ground(VoxelMoves.ahead(entry, 4))
					VoxelMoves.fx("burst", "ghostStomp", at, 1.3)
					VoxelMoves.fx("ring", "ghost", at, Tuning.stompRadius)
					VoxelMoves.fx("shake", at, 0.9, 45)
					VoxelMoves.hit(entry, VoxelMoves.inCircle(at, Tuning.stompRadius, 6), Tuning.stompDamage, {
						knock = { from = at, speed = 40, lift = 40 },
					})
					VoxelMoves.zone(entry, at, Tuning.stompRadius, Tuning.fireSeconds, 0.5, Tuning.fireDamage, "ghostFire")
				end,
			},
		},
	},
})
