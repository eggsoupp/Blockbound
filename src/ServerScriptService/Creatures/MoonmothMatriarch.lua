--[[
	Moonmoth Matriarch - a moth queen of the Hallow (rig Shared.Enemies.
	VoxelRigs.MoonmothMatriarch, moves on VoxelMoves).

	MOONBEAM (6-38). She rises, wings high, and calls the moon: three circles
	open round the target and beams of moonlight fall into them.
	GALE (within 18). Wings drawn back, then one great beat: glittering dust
	streams ahead of her, hurting and slowing.
	EYESPOT (within 14). Wings folded, then snapped open: the eyespots flare,
	and anyone in front of her is dazzled - slowed hard - and hurt.
]]

local VoxelMoves = require(script.Parent.VoxelMoves)
local V = Vector3.new

local Tuning = {
	walkSpeed = 7,
	beamRadius = 4.5,
	beamDamage = 15,
	beamDelay = 0.9,
	galeRange = 18,
	galeAngle = 30,
	galeDamage = 9,
	flashRange = 14,
	flashAngle = 60,
	flashDamage = 7,
}

return VoxelMoves.trait({
	rig = "MoonmothMatriarch",
	walkSpeed = Tuning.walkSpeed,
	closeTo = 7,
	gap = 0.6,
	moves = {
		{
			name = "moonbeam", range = { 6, 38 }, cooldown = 7.5, weight = 1.6,
			start = function(entry, move)
				local center = move.aim or VoxelMoves.ahead(entry, 12)
				local spots = { VoxelMoves.ground(center) }
				for i = 1, 2 do
					local a = math.random() * math.pi * 2
					table.insert(spots, VoxelMoves.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * (6 + math.random() * 3)))
				end
				move.spots = spots
				for _, at in ipairs(spots) do
					VoxelMoves.fx("mark", "moon", at, Tuning.beamRadius, 0.9 + Tuning.beamDelay)
				end
				VoxelMoves.fx("cast", "moon", entry.model, "MoonmothMatriarch", "head", 0.9)
			end,
			events = {
				[1.8] = function(entry, move)
					for _, at in ipairs(move.spots) do
						VoxelMoves.fx("pillar", "moon", at, Tuning.beamRadius)
						VoxelMoves.hit(entry, VoxelMoves.inCircle(at, Tuning.beamRadius, 10), Tuning.beamDamage)
					end
				end,
			},
		},
		{
			name = "gale", range = { 0, 18 }, cooldown = 8, weight = 1.2,
			track = 0.6,
			events = {
				gust = function(entry)
					local origin = VoxelMoves.point(entry, V(0, 40, -6))
					VoxelMoves.fx("cone", "gale", entry.model, "MoonmothMatriarch", "head", Tuning.galeRange, Tuning.galeAngle, 0.6)
					VoxelMoves.hit(entry, VoxelMoves.inCone(origin, VoxelMoves.look(entry), Tuning.galeRange, Tuning.galeAngle, 12), Tuning.galeDamage, {
						slow = { 0.5, 3 }, knock = { from = origin, speed = 45, lift = 15 },
					})
				end,
			},
		},
		{
			name = "eyespot", range = { 0, 14 }, cooldown = 10, weight = 1,
			track = 0.5,
			events = {
				flash = function(entry)
					local origin = VoxelMoves.point(entry, V(0, 50, 0))
					VoxelMoves.fx("burst", "eyespot", VoxelMoves.point(entry, V(28, 64, 2)), 1)
					VoxelMoves.fx("burst", "eyespot", VoxelMoves.point(entry, V(-28, 64, 2)), 1)
					local caught = VoxelMoves.inCone(origin, VoxelMoves.look(entry), Tuning.flashRange, Tuning.flashAngle, 14)
					for _, player in ipairs(caught) do
						VoxelMoves.fxTo(player, "dazzle", 1.2)
					end
					VoxelMoves.hit(entry, caught, Tuning.flashDamage, { slow = { 0.3, 1.6 } })
				end,
			},
		},
	},
})
