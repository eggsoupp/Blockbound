--[[
	Ashen Lich - a floating skeleton sorcerer-king of the Corruption
	(rig Shared.Enemies.VoxelRigs.AshenLich, moves on VoxelMoves).

	SOUL BOLTS (8-40 studs). Staff thrust: three soul skulls fan out from the
	gem at the target.
	GRAVE RISE (5-34). Staff driven into the ground; soul sigils open under
	the target and two flanking spots, and pillars of soul fire burst from
	them a second later. They slow.
	SOUL NOVA (within 10). Arms flung wide, the soul fire in its ribs bursts
	out all round, throwing players back.
	CLAW (within 6). A raking swipe of the free hand.
]]

local VoxelMoves = require(script.Parent.VoxelMoves)
local V = Vector3.new

local Tuning = {
	walkSpeed = 6,
	boltSpeed = 46,
	boltDamage = 10,
	boltSpread = 14,
	graveDamage = 16,
	graveRadius = 4.5,
	graveDelay = 1.0,
	novaRadius = 11,
	novaDamage = 13,
	clawDamage = 9,
}

local function gem(entry)
	return VoxelMoves.point(entry, V(14, 68.5, -18))
end

return VoxelMoves.trait({
	rig = "AshenLich",
	walkSpeed = Tuning.walkSpeed,
	closeTo = 5,
	gap = 0.6,
	moves = {
		{
			name = "cast", range = { 8, 40 }, cooldown = 3.6, weight = 2,
			track = 0.55,
			start = function(entry)
				VoxelMoves.fx("cast", "soul", entry.model, "AshenLich", "gem", 0.62)
			end,
			events = {
				release = function(entry, move)
					local from = gem(entry)
					local aim = (move.targetPosition or move.aim or from + VoxelMoves.look(entry) * 20) + Vector3.yAxis * 0.5
					local base = (aim - from).Unit
					for i = -1, 1 do
						local dir = CFrame.Angles(0, math.rad(i * Tuning.boltSpread), 0):VectorToWorldSpace(base)
						VoxelMoves.projectile({
							origin = from, velocity = dir * Tuning.boltSpeed, gravity = 0, radius = 2.2, maxLife = 1.6,
							style = "soulBolt",
							onHit = function(at, players)
								VoxelMoves.fx("burst", "soulHit", at, 1)
								VoxelMoves.hit(entry, players, Tuning.boltDamage)
							end,
						})
					end
					VoxelMoves.fx("burst", "soulCast", from, 1)
				end,
			},
		},
		{
			name = "grave", range = { 5, 34 }, cooldown = 9, weight = 1.4,
			start = function(entry, move)
				local center = move.aim or VoxelMoves.ahead(entry, 10)
				local look = VoxelMoves.look(entry)
				local side = look:Cross(Vector3.yAxis)
				move.graves = {
					VoxelMoves.ground(center),
					VoxelMoves.ground(center + side * 7 - look * 3),
					VoxelMoves.ground(center - side * 7 - look * 3),
				}
				for _, at in ipairs(move.graves) do
					VoxelMoves.fx("mark", "soul", at, Tuning.graveRadius, 0.85 + Tuning.graveDelay * 0.6)
				end
				VoxelMoves.fx("cast", "soul", entry.model, "AshenLich", "gem", 0.85)
			end,
			events = {
				slam = function(entry, move)
					VoxelMoves.fx("burst", "soulSlam", VoxelMoves.point(entry, V(14, 0, -18)), 1)
					VoxelMoves.fx("shake", VoxelMoves.point(entry, V(0, 0, 0)), 0.5, 40)
				end,
				[1.45] = function(entry, move)
					for _, at in ipairs(move.graves) do
						VoxelMoves.fx("pillar", "soul", at, Tuning.graveRadius)
						VoxelMoves.hit(entry, VoxelMoves.inCircle(at, Tuning.graveRadius, 8), Tuning.graveDamage, { slow = { 0.55, 2 } })
					end
				end,
			},
		},
		{
			name = "nova", range = { 0, 10 }, cooldown = 7, weight = 1.2,
			start = function(entry)
				VoxelMoves.fx("cast", "soulNova", entry.model, "AshenLich", "chest", 0.75)
			end,
			events = {
				blast = function(entry)
					local center = VoxelMoves.point(entry, V(0, 30, 0))
					VoxelMoves.fx("ring", "soul", center, Tuning.novaRadius)
					VoxelMoves.fx("shake", center, 0.6, 40)
					VoxelMoves.hit(entry, VoxelMoves.inCircle(center, Tuning.novaRadius, 9), Tuning.novaDamage, {
						knock = { from = center, speed = 55, lift = 30 },
					})
				end,
			},
		},
		{
			name = "claw", range = { 0, 6 }, cooldown = 1.8, weight = 1.5,
			track = 0.25,
			events = {
				hit = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("slash", "soulClaw", entry.model, "AshenLich", "hand", 0.25)
					VoxelMoves.hit(entry, VoxelMoves.inCone(feet, VoxelMoves.look(entry), 7, 70), Tuning.clawDamage, { hitFx = "soulHit" })
				end,
			},
		},
	},
})
