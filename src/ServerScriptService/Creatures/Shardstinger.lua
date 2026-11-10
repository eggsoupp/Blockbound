--[[
	Shardstinger - a crystal-backed scorpion of the Hallow (rig Shared.Enemies.
	VoxelRigs.Shardstinger, moves on VoxelMoves).

	PINCH (within 7). Both pincers scissored shut on whatever is in front.
	STING (within 10). The tail driven forward over its back: a heavy stab
	that leaves crystal venom working in you.
	SHARD ERUPTION (6-28). The stinger stabbed into the ground: crystals
	tear up out of it one after another along a line toward you.
]]

local VoxelMoves = require(script.Parent.VoxelMoves)

local Tuning = {
	walkSpeed = 8,
	pinchReach = 8,
	pinchDamage = 12,
	stingReach = 10,
	stingDamage = 15,
	venomTicks = 3,
	venomDamage = 3,
	shardRadius = 3.5,
	shardDamage = 14,
	shardStep = 4,
	shardCount = 6,
	shardEvery = 0.09,
}

return VoxelMoves.trait({
	rig = "Shardstinger",
	walkSpeed = Tuning.walkSpeed,
	closeTo = 6,
	gap = 0.45,
	moves = {
		{
			name = "pinch", range = { 0, 7 }, cooldown = 2, weight = 2,
			track = 0.25, turnRate = 6,
			events = {
				hit = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("burst", "crystalSnap", VoxelMoves.ahead(entry, 7) + Vector3.yAxis * 3, 1)
					VoxelMoves.hit(entry, VoxelMoves.inCone(feet, VoxelMoves.look(entry), Tuning.pinchReach, 55, 6), Tuning.pinchDamage)
				end,
			},
		},
		{
			name = "sting", range = { 0, 10 }, cooldown = 5, weight = 1.4,
			track = 0.38, turnRate = 5,
			start = function(entry)
				VoxelMoves.fx("cast", "crystal", entry.model, "Shardstinger", "stinger", 0.55)
			end,
			events = {
				hit = function(entry)
					local at = VoxelMoves.ahead(entry, 8) + Vector3.yAxis * 2.5
					VoxelMoves.fx("burst", "venom", at, 1)
					local feet = VoxelMoves.Kit.feet(entry)
					local look = VoxelMoves.look(entry)
					VoxelMoves.hit(entry, VoxelMoves.along(feet + look * 3 + Vector3.yAxis * 2, feet + look * Tuning.stingReach + Vector3.yAxis * 2, 3), Tuning.stingDamage, {
						dot = { Tuning.venomTicks, Tuning.venomDamage, 0.7, "venom" },
					})
				end,
			},
		},
		{
			name = "erupt", range = { 6, 28 }, cooldown = 8.5, weight = 1.2,
			track = 0.6,
			start = function(entry, move)
				local feet = VoxelMoves.Kit.feet(entry)
				local toward = VoxelMoves.Kit.flat((move.aim or feet) - feet)
				move.line = if toward.Magnitude > 0.1 then toward else VoxelMoves.look(entry)
				VoxelMoves.fx("cast", "crystal", entry.model, "Shardstinger", "stinger", 0.75)
			end,
			events = {
				slam = function(entry, move)
					local feet = VoxelMoves.Kit.feet(entry)
					local line = VoxelMoves.look(entry)
					VoxelMoves.fx("shake", feet, 0.6, 40)
					for i = 1, Tuning.shardCount do
						task.delay(i * Tuning.shardEvery, function()
							if not entry.model.Parent then
								return
							end
							local at = VoxelMoves.ground(feet + line * (5 + i * Tuning.shardStep))
							VoxelMoves.fx("spike", "crystal", at, Tuning.shardRadius)
							VoxelMoves.hit(entry, VoxelMoves.inCircle(at, Tuning.shardRadius, 6), Tuning.shardDamage, {
								knock = { from = at, speed = 10, lift = 50 },
							})
						end)
					end
				end,
			},
		},
	},
})
