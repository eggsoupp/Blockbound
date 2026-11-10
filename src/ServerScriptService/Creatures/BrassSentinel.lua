--[[
	Brass Sentinel - a clockwork colossus of the Desert (rig Shared.Enemies.
	VoxelRigs.BrassSentinel, moves on VoxelMoves).

	HAMMER (within 8). The piston fist comes down on the ground ahead: a
	shockwave knocks everyone near the blow up and away.
	SHIELD BASH (5-16). Crouched behind the tower shield it rushes forward,
	battering and shoving whoever is in the way.
	FURNACE (5-16). The chest grille opens and the furnace roars: a cone of
	fire in front of it, burning for as long as you stand in it.
]]

local VoxelMoves = require(script.Parent.VoxelMoves)
local V = Vector3.new

local Tuning = {
	walkSpeed = 5.5,
	hammerReach = 7,
	hammerRadius = 7,
	hammerDamage = 18,
	bashSpeed = 30,
	bashDamage = 13,
	fireRange = 17,
	fireAngle = 26,
	fireDamage = 5,
	fireEvery = 0.25,
}

return VoxelMoves.trait({
	rig = "BrassSentinel",
	walkSpeed = Tuning.walkSpeed,
	closeTo = 6,
	gap = 0.7,
	moves = {
		{
			name = "hammer", range = { 0, 8 }, cooldown = 3.4, weight = 2,
			track = 0.5,
			start = function(entry)
				VoxelMoves.fx("cast", "ember", entry.model, "BrassSentinel", "fist", 0.8)
			end,
			events = {
				hit = function(entry)
					local at = VoxelMoves.ground(VoxelMoves.ahead(entry, Tuning.hammerReach))
					VoxelMoves.fx("burst", "quake", at, 1.3)
					VoxelMoves.fx("ring", "dust", at, Tuning.hammerRadius)
					VoxelMoves.fx("shake", at, 1.0, 50)
					VoxelMoves.hit(entry, VoxelMoves.inCircle(at, Tuning.hammerRadius, 6), Tuning.hammerDamage, {
						knock = { from = at, speed = 35, lift = 55 },
					})
				end,
			},
		},
		{
			name = "bash", range = { 5, 16 }, cooldown = 6.5, weight = 1.2,
			track = 0.4,
			start = function(entry)
				VoxelMoves.fx("cast", "brassShield", entry.model, "BrassSentinel", "shield", 0.9)
			end,
			tick = function(entry, move, t, dt)
				local marks = move.clip.marks
				if t >= marks.charge and t < marks.stop and not move.stopped then
					if not VoxelMoves.rush(entry, Tuning.bashSpeed, dt) then
						move.stopped = true
					end
					local front = VoxelMoves.point(entry, V(0, 25, -14))
					for _, player in ipairs(VoxelMoves.inCircle(front, 6, 8)) do
						if not move.hitSet[player] then
							move.hitSet[player] = true
							VoxelMoves.fx("burst", "clang", front, 1)
							VoxelMoves.hit(entry, { player }, Tuning.bashDamage, {
								knock = { from = VoxelMoves.Kit.feet(entry), speed = 60, lift = 25 },
							})
						end
					end
				end
			end,
			events = {
				charge = function(entry)
					VoxelMoves.fx("trail", "dust", entry.model, "BrassSentinel", "shield", 0.45)
				end,
			},
		},
		{
			name = "furnace", range = { 5, 16 }, cooldown = 9, weight = 1,
			track = 1.6, turnRate = 1.2,
			start = function(entry)
				VoxelMoves.fx("cast", "furnace", entry.model, "BrassSentinel", "core", 0.8)
			end,
			events = {
				open = function(entry, move)
					VoxelMoves.fx("cone", "fire", entry.model, "BrassSentinel", "core", Tuning.fireRange, Tuning.fireAngle, 1.1)
				end,
			},
			tick = function(entry, move, t)
				local marks = move.clip.marks
				if t >= marks.open and t <= marks.close and t >= (move.nextBurn or 0) then
					move.nextBurn = t + Tuning.fireEvery
					local origin = VoxelMoves.point(entry, V(0, 43, -8))
					VoxelMoves.hit(entry, VoxelMoves.inCone(origin, VoxelMoves.look(entry), Tuning.fireRange, Tuning.fireAngle, 12), Tuning.fireDamage)
				end
			end,
		},
	},
})
