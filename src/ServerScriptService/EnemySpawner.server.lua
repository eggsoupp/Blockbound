--[[
	EnemySpawner

	Puts enemies in the world around players, in the biomes those enemies
	belong to.

		EnemyConfig.Definitions.Ghost.spawnBiomes = { "Corruption" }
		         |
		    a hidden point in a living cell, every few seconds
		         |
		    EnemyService.spawnPack

	Every number it uses is EnemyConfig.Spawning, and every enemy's territory is
	its own `spawnBiomes`. So this file never names a creature or a biome, and
	adding either is a line over there.

	IT SPAWNS AROUND PLAYERS, AND MUST NOT LOOK LIKE IT

	There is nothing to gain from populating chunks nobody is standing in: they
	would be a tick's work each and a despawn timer nobody ever sees expire. So
	this works outward from players, and then spends most of its effort hiding
	that fact - see the long note on EnemyConfig.Spawning for the three things
	that do the hiding and why each is there.

	The one worth repeating here is the CELL. Whether a patch of world holds
	anything at all is a hash of its coordinates, not a roll: the same stretch
	is barren every time you cross it, and the next valley over is not. Nothing
	else in this file would stop a player concluding that mobs appear because
	they are standing there, because without it that is precisely what happens.

	THE BIOME IS READ AT THE SPAWN, NOT UNDER THE PLAYER

	It reaches a hundred and fifty studs now, which is far enough to be over a
	border, and putting a Ghost in the Plains because the player is standing in
	Corruption would undo the point of having biomes own their creatures. One
	extra BiomeMap.sampleColumn per accepted placement.

	NOTHING IS GUARANTEED

	Every spawn goes through EnemyService.spawn, which enforces MaxAlive and can
	refuse - and an attempt is abandoned if the terrain is not ready to be asked
	what biome it is. A refusal is not an error here; it is a busy server saying
	no, and the next attempt is six seconds away.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local BiomeMap = require(Shared.Terrain:WaitForChild("BiomeMap"))

local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))

local DEBUG = false
local function log(...)
	if DEBUG then
		print("[EnemySpawner]", ...)
	end
end

local S = EnemyConfig.Spawning
local STUD_SIZE = TerrainConfig.StudSize

--[[
	biome name -> the enemies that live there, built once from the definitions.

	Inverted at startup rather than searched per spawn: the search is small
	either way, but building it here means an enemy naming a biome that does not
	exist shows up as an empty list rather than as silence.
]]
local byBiome: { [string]: { string } } = {}

for name, definition in pairs(EnemyConfig.Definitions) do
	local biomes = definition.spawnBiomes

	if type(biomes) == "table" then
		for _, biome in ipairs(biomes) do
			local list = byBiome[biome]
			if not list then
				list = {}
				byBiome[biome] = list
			end
			table.insert(list, name)
		end
	end
end

-- Sorted, so which slime a given roll produces does not depend on the order
-- pairs() happened to walk the definitions in this session.
for _, list in pairs(byBiome) do
	table.sort(list)
end

local random = Random.new()

--[[
	Whether a patch of world holds anything at all.

	A hash of the cell's coordinates, so it is FIXED: the same clearing is
	lifeless every time you walk through it and the wood beyond it is not. That
	is the whole trick - a roll would give the same overall rate and none of the
	meaning, because a place that is empty only until you look again is not a
	place that is empty.

	Random.new(seed) rather than arithmetic hashing because Luau's numbers are
	doubles and the usual multiply-and-xor overflows 2^53 long before it has
	finished mixing; seeding a real generator is exact, obviously uniform, and
	this runs once per attempt rather than once per block.
]]
local CELL_SEED = 8675309

local function cellIsAlive(x: number, z: number): boolean
	local cx = math.floor(x / S.cellSize)
	local cz = math.floor(z / S.cellSize)

	local value = Random.new(cx * 73856093 + cz * 19349663 + CELL_SEED):NextNumber()
	return value >= S.emptyCells
end

--[[
	Whether a point is somewhere the player could watch something arrive at.

	True if it is inside the cone they are facing AND close enough to see
	clearly. Far things are allowed in front, because at that distance a spawn
	is a dot on a hillside rather than a monster fading in at arm's length.

	The character's facing, not the camera's - the server does not have the
	camera, and the two rarely disagree enough to matter for this.
]]
local function inPlainSight(origin: Vector3, look: Vector3, point: Vector3): boolean
	local offset = point - origin
	local distance = offset.Magnitude

	if distance >= S.hiddenWithin or distance <= 0 then
		return false
	end

	local flat = Vector3.new(offset.X, 0, offset.Z)
	local facing = Vector3.new(look.X, 0, look.Z)

	if flat.Magnitude <= 0 or facing.Magnitude <= 0 then
		return false
	end

	local cosine = flat.Unit:Dot(facing.Unit)
	return cosine >= math.cos(math.rad(S.hiddenAngle))
end

--[[
	The biome at a position, or nil if the terrain cannot answer yet.

	pcall because BiomeMap wants init() to have been called and server script
	order is undefined - this can genuinely run first. Nothing spawns until the
	terrain is up, which is correct: there would be no ground to stand on.
]]
local function biomeAt(x: number, z: number): string?
	local ok, _, biomeName = pcall(
		BiomeMap.sampleColumn,
		math.floor(x / STUD_SIZE),
		math.floor(z / STUD_SIZE)
	)

	if not ok or type(biomeName) ~= "string" then
		return nil
	end

	return biomeName
end

local function nearbyCount(position: Vector3): number
	local count = 0

	EnemyService.forEachNear(position, S.countRadius, function()
		count += 1
	end)

	return count
end

local function attempt(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	-- Nothing spawns around a corpse, or around somebody still loading in.
	if not (root and humanoid) or humanoid.Health <= 0 then
		return
	end

	local position = root.Position
	local look = root.CFrame.LookVector

	if nearbyCount(position) >= S.perPlayerCap then
		return
	end

	--[[
		Is this a place that holds anything?

		Tested on the PLAYER, before anything else, and it is not retried. That
		is the difference between a mask and a decoration: testing the candidate
		instead would let the retries below shop around until one of them landed
		in a living cell, which is a fixed hash producing exactly the same
		steady drip it was supposed to break up.

		Here it means a barren stretch is barren while you are standing in it,
		for as long as you stand there, every time you come back.
	]]
	if not cellIsAlive(position.X, position.Z) then
		return
	end

	if random:NextNumber() > S.chance then
		return
	end

	--[[
		Several throws at the dartboard, and the first one out of sight wins.
		Each is an independent angle AND distance across the whole band - not a
		fixed radius - so nothing arrives at a recognisable range.

		The retries exist only to stop LOOKING AROUND being a way to switch
		spawning off; whether anything spawns here at all was already decided,
		above, and is not up for a second opinion.

		The check rejects rather than nudges. A rejected point shuffled into a
		legal one would sit exactly on the edge of the cone, and a player would
		learn that edge very quickly.
	]]
	for _ = 1, S.tries do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(S.minRadius, S.maxRadius)

		local point = position + Vector3.new(
			math.cos(angle) * distance,
			0,
			math.sin(angle) * distance
		)

		if not inPlainSight(position, look, point) then
			local biome = biomeAt(point.X, point.Z)
			local candidates = biome and byBiome[biome]

			if candidates and #candidates > 0 then
				local name = candidates[random:NextInteger(1, #candidates)]
				local count = random:NextInteger(S.groupMin, S.groupMax)

				local spawned, reason =
					EnemyService.spawnPack(name, point, count, S.packSpread)

				if spawned > 0 then
					log(string.format(
						"%d %s at %d,%d in %s", spawned, name, point.X, point.Z, biome
					))
				elseif reason then
					log("could not spawn", name, "-", reason)
				end

				-- One pack per interval whatever happened. A second throw after
				-- a successful one is how a clearing fills up.
				return
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(S.interval)

		--[[
			One attempt per player, and the cap is counted per player too, so a
			server of ten does not become ten times as dangerous for each of
			them. Two players standing together share the enemies around them,
			which is the behaviour that falls out of counting by distance
			rather than by owner.
		]]
		for _, player in ipairs(Players:GetPlayers()) do
			-- Isolated: one player's character going away mid-attempt should
			-- not stop the loop for everybody else, and this runs forever.
			local ok, err = pcall(attempt, player)
			if not ok then
				warn("[EnemySpawner] attempt failed:", err)
			end
		end
	end
end)
