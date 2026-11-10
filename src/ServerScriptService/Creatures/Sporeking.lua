--[[
	Sporeking - a mushroom titan of the Swamp (rig Shared.Enemies.VoxelRigs.
	Sporeking, moves on VoxelMoves).

	SMASH (within 8). Both root fists hauled overhead and brought down: a
	crushing blow and a burst of spores.
	SPORE CLOUD (within 12). It shakes its cap and a choking cloud spreads
	round it, poisoning anyone who stays in.
	SPORE MORTAR (9-36). It lobs three spore pods high; each bursts where it
	lands, poisoning whoever it catches.
]]

local VoxelMoves = require(script.Parent.VoxelMoves)
local V = Vector3.new

local Tuning = {
	walkSpeed = 5,
	smashReach = 6,
	smashRadius = 7,
	smashDamage = 17,
	cloudRadius = 12,
	cloudSeconds = 4.5,
	cloudDamage = 3,
	podDamage = 11,
	podRadius = 5,
	podGravity = 80,
	podFlight = 1.2,
}

return VoxelMoves.trait({
	rig = "Sporeking",
	walkSpeed = Tuning.walkSpeed,
	closeTo = 6,
	gap = 0.7,
	moves = {
		{
			name = "smash", range = { 0, 8 }, cooldown = 3.2, weight = 2,
			track = 0.55,
			events = {
				hit = function(entry)
					local at = VoxelMoves.ground(VoxelMoves.ahead(entry, Tuning.smashReach))
					VoxelMoves.fx("burst", "mudQuake", at, 1.2)
					VoxelMoves.fx("ring", "spore", at, Tuning.smashRadius)
					VoxelMoves.fx("shake", at, 0.9, 45)
					VoxelMoves.hit(entry, VoxelMoves.inCircle(at, Tuning.smashRadius, 6), Tuning.smashDamage, {
						knock = { from = at, speed = 30, lift = 40 },
					})
				end,
			},
		},
		{
			name = "spores", range = { 0, 12 }, cooldown = 10, weight = 1,
			start = function(entry)
				VoxelMoves.fx("cast", "spore", entry.model, "Sporeking", "cap", 0.9)
			end,
			events = {
				puff = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("burst", "sporePuff", VoxelMoves.point(entry, V(0, 52, 0)), 1.4)
					VoxelMoves.zone(entry, feet, Tuning.cloudRadius, Tuning.cloudSeconds, 0.5, Tuning.cloudDamage, "sporeCloud")
				end,
			},
		},
		{
			name = "mortar", range = { 9, 36 }, cooldown = 6.5, weight = 1.4,
			track = 0.6,
			events = {
				throw = function(entry, move)
					local from = VoxelMoves.point(entry, V(14, 62, -6))
					local center = move.targetPosition or move.aim or VoxelMoves.ahead(entry, 16)
					for i = 1, 3 do
						local spread = if i == 1 then Vector3.zero else Vector3.new(math.random() * 10 - 5, 0, math.random() * 10 - 5)
						local goal = VoxelMoves.ground(center + spread)
						local flight = Tuning.podFlight * (0.9 + i * 0.1)
						local g = Tuning.podGravity
						local velocity = (goal - from) / flight + Vector3.new(0, 0.5 * g * flight, 0)
						VoxelMoves.projectile({
							origin = from, velocity = velocity, gravity = g, radius = 2, maxLife = flight + 0.4,
							style = "sporePod",
							onHit = function(at, players)
								VoxelMoves.fx("burst", "sporePuff", at, 1)
								local caught = VoxelMoves.inCircle(at, Tuning.podRadius, 6)
								VoxelMoves.hit(entry, caught, Tuning.podDamage, { dot = { 3, 2, 0.6, "poison" } })
							end,
						})
					end
				end,
			},
		},
	},
})
