--[[
	Tempest Djinn - a four-armed storm spirit of the Desert (rig Shared.
	Enemies.VoxelRigs.TempestDjinn, moves on VoxelMoves).

	STORM ORB (8-42). The crackling orb in its upper hand, hurled: it bursts
	in a thunderclap where it lands.
	STORMCALL (6-38). All four arms raised: four marks open round the target
	and lightning strikes each one.
	FLURRY (within 8). Four punches, one from each arm, driving forward.
	CYCLONE (within 15). It spins with its storm, dragging everyone in, then
	throws them out in a blast.
]]

local VoxelMoves = require(script.Parent.VoxelMoves)
local V = Vector3.new

local Tuning = {
	walkSpeed = 7,
	orbSpeed = 55,
	orbRadius = 6,
	orbDamage = 14,
	boltRadius = 4,
	boltDamage = 16,
	bolts = 4,
	punchReach = 8,
	punchDamage = 6,
	pullRadius = 16,
	blastRadius = 9,
	blastDamage = 13,
}

return VoxelMoves.trait({
	rig = "TempestDjinn",
	walkSpeed = Tuning.walkSpeed,
	closeTo = 6,
	gap = 0.5,
	moves = {
		{
			name = "orb", range = { 8, 42 }, cooldown = 4.5, weight = 1.8,
			track = 0.55, turnRate = 5,
			start = function(entry)
				VoxelMoves.fx("cast", "storm", entry.model, "TempestDjinn", "orb", 0.6)
			end,
			events = {
				throw = function(entry, move)
					local from = VoxelMoves.point(entry, V(18, 58, -16))
					local aim = (move.targetPosition or move.aim or from + VoxelMoves.look(entry) * 20) + Vector3.yAxis
					VoxelMoves.projectile({
						origin = from, velocity = (aim - from).Unit * Tuning.orbSpeed, gravity = 0, radius = 2.4, maxLife = 1.4,
						style = "stormOrb",
						onHit = function(at)
							VoxelMoves.fx("burst", "thunderclap", at, 1.2)
							VoxelMoves.hit(entry, VoxelMoves.inCircle(at, Tuning.orbRadius, 7), Tuning.orbDamage, {
								knock = { from = at, speed = 30, lift = 25 },
							})
						end,
					})
				end,
			},
		},
		{
			name = "storm", range = { 6, 38 }, cooldown = 9, weight = 1.3,
			start = function(entry, move)
				local center = move.aim or VoxelMoves.ahead(entry, 12)
				move.spots = { VoxelMoves.ground(center) }
				for i = 2, Tuning.bolts do
					local a = i / Tuning.bolts * math.pi * 2 + math.random()
					table.insert(move.spots, VoxelMoves.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * (5 + math.random() * 4)))
				end
				for _, at in ipairs(move.spots) do
					VoxelMoves.fx("mark", "storm", at, Tuning.boltRadius, 1.15)
				end
				VoxelMoves.fx("cast", "stormCall", entry.model, "TempestDjinn", "head", 0.9)
			end,
			events = {
				call = function(entry, move)
					for i, at in ipairs(move.spots) do
						task.delay((i - 1) * 0.12, function()
							VoxelMoves.fx("bolt", "storm", at)
							VoxelMoves.hit(entry, VoxelMoves.inCircle(at, Tuning.boltRadius, 9), Tuning.boltDamage)
						end)
					end
				end,
			},
		},
		{
			name = "flurry", range = { 0, 8 }, cooldown = 4.5, weight = 1.8,
			track = 1.0, turnRate = 4,
			tick = function(entry, move, t, dt)
				if t > 0.3 and t < 1.1 then
					VoxelMoves.rush(entry, 4, dt)
				end
			end,
			events = (function()
				local events = {}
				for i = 1, 4 do
					events["hit" .. i] = function(entry)
						local feet = VoxelMoves.Kit.feet(entry)
						VoxelMoves.fx("burst", "stormPunch", VoxelMoves.ahead(entry, 6) + Vector3.yAxis * (5 + (i % 2) * 2), 0.8)
						VoxelMoves.hit(entry, VoxelMoves.inCone(feet, VoxelMoves.look(entry), Tuning.punchReach, 50, 9), Tuning.punchDamage, {
							knock = if i == 4 then { from = feet, speed = 45, lift = 20 } else nil,
						})
					end
				end
				return events
			end)(),
		},
		{
			name = "whirl", range = { 0, 15 }, cooldown = 11, weight = 1,
			start = function(entry)
				VoxelMoves.fx("zone", "cyclone", VoxelMoves.Kit.feet(entry), Tuning.pullRadius, 1.4)
			end,
			tick = function(entry, move, t)
				if t > 0.3 and t < 1.3 and t >= (move.nextPull or 0) then
					move.nextPull = t + 0.25
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.hit(entry, VoxelMoves.inCircle(feet, Tuning.pullRadius, 10), 0, { pull = { to = feet, speed = 28, lift = 6 } })
				end
			end,
			events = {
				blast = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("burst", "thunderclap", feet + Vector3.yAxis * 5, 1.6)
					VoxelMoves.fx("ring", "storm", feet, Tuning.blastRadius)
					VoxelMoves.fx("shake", feet, 0.8, 45)
					VoxelMoves.hit(entry, VoxelMoves.inCircle(feet, Tuning.blastRadius, 9), Tuning.blastDamage, {
						knock = { from = feet, speed = 65, lift = 40 },
					})
				end,
			},
		},
	},
})
