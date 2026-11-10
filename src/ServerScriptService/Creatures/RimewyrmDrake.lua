--[[
	Rimewyrm Drake - a frost wyvern of the Snow (rig Shared.Enemies.VoxelRigs.
	RimewyrmDrake, moves on VoxelMoves).

	BITE (within 9). Neck reared back, then struck down: a heavy bite.
	FROST BREATH (6-24). A long inhale, then a stream of frost swept right to
	left across the ground ahead: it hurts and chills (slows) for as long as
	you stand in it.
	TAIL SWEEP (within 12). Body wound round, the tail whipped through
	everything nearby, flinging it away.
	WINTER GUST (10-30). It leaps and beats its wings: shards of ice rain on
	marked spots round the target.
]]

local VoxelMoves = require(script.Parent.VoxelMoves)
local V = Vector3.new

local Tuning = {
	walkSpeed = 7,
	biteReach = 9,
	biteDamage = 16,
	breathRange = 24,
	breathAngle = 22,
	breathDamage = 4,
	breathEvery = 0.2,
	sweepRadius = 12,
	sweepDamage = 14,
	shardRadius = 4,
	shardDamage = 12,
	shards = 5,
}

-- Which way the breath points at time t: swept from its right to its left.
local function breathLook(entry, move, t)
	local marks = move.clip.marks
	local a = math.clamp((t - marks.start) / (marks.stop - marks.start), 0, 1)
	local yaw = math.rad(-(22 - 44 * a)) * 0.9
	return CFrame.Angles(0, -yaw, 0):VectorToWorldSpace(move.breathBase)
end

return VoxelMoves.trait({
	rig = "RimewyrmDrake",
	walkSpeed = Tuning.walkSpeed,
	closeTo = 7,
	gap = 0.6,
	moves = {
		{
			name = "bite", range = { 0, 9 }, cooldown = 2.6, weight = 2,
			track = 0.3, turnRate = 5,
			events = {
				hit = function(entry)
					local mouth = VoxelMoves.point(entry, V(0, 16, -46))
					VoxelMoves.fx("burst", "frostBite", mouth, 1)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.hit(entry, VoxelMoves.inCone(feet, VoxelMoves.look(entry), Tuning.biteReach + 2, 40, 8), Tuning.biteDamage)
				end,
			},
		},
		{
			name = "breath", range = { 6, 24 }, cooldown = 9, weight = 1.3,
			track = 0.9, turnRate = 2,
			start = function(entry)
				VoxelMoves.fx("cast", "frost", entry.model, "RimewyrmDrake", "mouth", 1.0)
			end,
			events = {
				start = function(entry, move)
					move.breathBase = VoxelMoves.look(entry)
					VoxelMoves.fx("breath", "frost", entry.model, "RimewyrmDrake", "mouth", Tuning.breathRange, 1.2)
				end,
			},
			tick = function(entry, move, t)
				local marks = move.clip.marks
				if move.breathBase and t >= marks.start and t <= marks.stop and t >= (move.nextChill or 0) then
					move.nextChill = t + Tuning.breathEvery
					local origin = VoxelMoves.point(entry, V(0, 30, -30))
					local caught = VoxelMoves.inCone(origin, breathLook(entry, move, t), Tuning.breathRange, Tuning.breathAngle, 14)
					VoxelMoves.hit(entry, caught, Tuning.breathDamage, { slow = { 0.45, 2 } })
				end
			end,
		},
		{
			name = "sweep", range = { 0, 12 }, cooldown = 6.5, weight = 1.1,
			events = {
				hit = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("trail", "frostTail", entry.model, "RimewyrmDrake", "tail", 0.35)
					VoxelMoves.fx("ring", "frost", feet, Tuning.sweepRadius)
					VoxelMoves.hit(entry, VoxelMoves.inCircle(feet, Tuning.sweepRadius, 7), Tuning.sweepDamage, {
						knock = { from = feet, speed = 60, lift = 30 }, hitFx = "frostBite",
					})
				end,
			},
		},
		{
			name = "gust", range = { 10, 30 }, cooldown = 11, weight = 1,
			start = function(entry, move)
				local center = move.aim or VoxelMoves.ahead(entry, 15)
				move.spots = { VoxelMoves.ground(center) }
				for i = 2, Tuning.shards do
					local a = (i / Tuning.shards) * math.pi * 2 + math.random()
					table.insert(move.spots, VoxelMoves.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * (4 + math.random() * 6)))
				end
			end,
			events = {
				lift = function(entry)
					VoxelMoves.fx("burst", "snowGust", VoxelMoves.Kit.feet(entry), 1.4)
				end,
				beat = function(entry, move)
					for i, at in ipairs(move.spots) do
						VoxelMoves.fx("mark", "frost", at, Tuning.shardRadius, 0.55)
						task.delay(0.45 + i * 0.06, function()
							VoxelMoves.fx("fall", "iceShard", at)
						end)
					end
				end,
				[1.65] = function(entry, move)
					for _, at in ipairs(move.spots) do
						VoxelMoves.hit(entry, VoxelMoves.inCircle(at, Tuning.shardRadius, 7), Tuning.shardDamage, { slow = { 0.6, 1.5 } })
					end
				end,
				land = function(entry)
					local feet = VoxelMoves.Kit.feet(entry)
					VoxelMoves.fx("burst", "snowGust", feet, 1.2)
					VoxelMoves.fx("shake", feet, 0.7, 40)
				end,
			},
		},
	},
})
