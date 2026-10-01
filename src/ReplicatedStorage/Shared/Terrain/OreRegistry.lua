--[[
	OreRegistry

	Answers one question: "is there an ore at this block, and which?"

		OreRegistry.init(seed)
		OreRegistry.blockAt(blockX, blockY, blockZ, baseBlock, depth) -> name?

	WHY IT IS A LOOKUP AND NOT A GENERATION PASS
	--------------------------------------------
	The obvious design - walk every block of every column at generation time and
	stamp ores in - costs ChunkSize^2 * worldDepth samples per chunk. With the
	world now ~190 blocks deep that is ~48,000 samples per chunk, an order of
	magnitude more work than the rest of chunk generation put together, and
	almost all of it thrown away: the overwhelming majority of underground blocks
	are never rendered and never mined.

	So ore is resolved lazily instead. Because the answer is a pure function of
	(position, world seed) it can be computed the moment it is actually needed -
	when a block gets a part, or when a block is broken - and it gives the same
	answer every time. That is also what makes it seamless across chunk borders
	and stable across streaming: there is no state to disagree.

	Cost per query is a depth test per ore, which rejects nearly all of them
	immediately since ore bands barely overlap, plus two hashes for the one or
	two ores actually in band.

	DETERMINISM
	-----------
	Both hashes are the same position-hash family StructureRegistry uses, offset
	by the world seed. No RNG object, no ordering dependence, no allocation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TerrainFolder = script.Parent
local OreConfig = require(TerrainFolder:WaitForChild("OreConfig"))
local StrataConfig = require(TerrainFolder:WaitForChild("StrataConfig"))
local BlockConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Blocks"):WaitForChild("BlockConfig")
)

local OreRegistry = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
-- Flattened into parallel arrays: the inner loop touches every field of every
-- ore, and array reads beat hash lookups in Luau by enough to matter here.

local oreCount = 0
local oreBlock = {}
local oreMinDepth = {}
local orePeakDepth = {}
local oreMaxDepth = {}
local oreCellChance = {}
local oreInvVeinSize = {}
local oreFillRatio = {}
local oreHosts = {}
local oreSalt = {}

-- Widest band any ore covers, so a block outside it is rejected before the
-- per-ore loop is entered at all. This is the check that makes surface
-- rendering - the common case - cost essentially nothing.
local globalMinDepth = math.huge
local globalMaxDepth = -math.huge

local hashSeed = 0
local isReady = false

-- ---------------------------------------------------------------------------
-- Hashing
-- ---------------------------------------------------------------------------

--[[
	Deterministic [0, 1) from four integers. Same construction as
	StructureRegistry.hashUnit, extended to a fourth axis for depth.

	Two sine terms rather than one: a single linear-combination hash correlates
	along planes, which shows up as diagonal striping in a 3D scatter. Two
	decorrelate it.
]]
local function hashUnit(a, b, c, salt)
	local x = a * 127.1 + b * 311.7 + c * 74.7 + salt * 269.5 + hashSeed
	local y = a * 269.5 + b * 183.3 + c * 246.1 + salt * 113.5 + hashSeed
	local v = math.sin(x) * 43758.5453 + math.sin(y) * 28001.8384
	return v - math.floor(v)
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

local function buildTables()
	oreCount = 0
	table.clear(oreBlock)
	table.clear(oreMinDepth)
	table.clear(orePeakDepth)
	table.clear(oreMaxDepth)
	table.clear(oreCellChance)
	table.clear(oreInvVeinSize)
	table.clear(oreFillRatio)
	table.clear(oreHosts)
	table.clear(oreSalt)

	globalMinDepth = math.huge
	globalMaxDepth = -math.huge

	if not OreConfig.Enabled then
		return
	end

	-- Rarest first. The first ore that claims a block wins, so ordering by
	-- descending priority is what stops a common ore masking a rare one.
	local order = table.clone(OreConfig.Order)
	table.sort(order, function(a, b)
		local defA = OreConfig.Definitions[a]
		local defB = OreConfig.Definitions[b]
		if (defA.priority or 0) ~= (defB.priority or 0) then
			return (defA.priority or 0) > (defB.priority or 0)
		end
		return a < b
	end)

	local defaultHost = StrataConfig.getDeepBlock()
	local multiplier = OreConfig.GlobalDensityMultiplier

	local generateOnly = OreConfig.GenerateOnly

	for rank, name in ipairs(order) do
		local def = OreConfig.Definitions[name]

		-- An ore block is not named after the item it yields, and is tougher than
		-- the rock around it. Tell BlockConfig both, rather than making mining
		-- special-case ores.
		BlockConfig.registerBlock(def.block, {
			drop = def.item,
			breakSeconds = def.breakSeconds,
		})

		-- Ores usually have no authored part; hand BlockConfig a description so
		-- one gets built. An authored part in TerrainAssets.Blocks still wins.
		if def.appearance then
			BlockConfig.registerGenerated(def.block, def.appearance)
		end

		-- Registered above either way, so an ore that does not generate here is
		-- still a real block if one is carried in. See OreConfig.GenerateOnly.
		if generateOnly and not generateOnly[name] then
			continue
		end

		oreCount += 1
		oreBlock[oreCount] = def.block
		oreMinDepth[oreCount] = def.minDepth
		orePeakDepth[oreCount] = def.peakDepth
		oreMaxDepth[oreCount] = def.maxDepth
		oreCellChance[oreCount] = math.min(1, def.cellChance * multiplier)
		oreInvVeinSize[oreCount] = 1 / def.veinSize
		oreFillRatio[oreCount] = def.fillRatio
		oreHosts[oreCount] = def.hosts or { [defaultHost] = true }

		-- Distinct salt per ore so two ores never share a vein layout. The
		-- stride of 2 leaves room for the fill hash at salt + 1. Keyed on the
		-- ore's rank in the full list, so filtering ores out never moves the
		-- veins of the ones that remain.
		oreSalt[oreCount] = 1000 + rank * 2

		if def.minDepth < globalMinDepth then
			globalMinDepth = def.minDepth
		end
		if def.maxDepth > globalMaxDepth then
			globalMaxDepth = def.maxDepth
		end
	end
end

--[[
	Must be called before blockAt. Safe to call again to reseed.
]]
function OreRegistry.init(seed)
	OreConfig.validate()
	StrataConfig.validate()

	hashSeed = (seed or 0) % 4096 * 2.3999632297
	buildTables()
	isReady = true
end

-- ---------------------------------------------------------------------------
-- Lookup
-- ---------------------------------------------------------------------------

--[[
	The ore block at a position, or nil for plain rock.

	  blockX/Y/Z  absolute block coordinates
	  baseBlock   what the strata say is here; ores only replace their hosts
	  depth       blocks below this column's surface

	Returns nil for every block outside every ore's depth band, which is the
	overwhelming majority of what gets asked about.
]]
function OreRegistry.blockAt(blockX, blockY, blockZ, baseBlock, depth)
	if not isReady or depth < globalMinDepth or depth > globalMaxDepth then
		return nil
	end

	for i = 1, oreCount do
		if depth >= oreMinDepth[i] and depth <= oreMaxDepth[i] and oreHosts[i][baseBlock] then
			local chance = oreCellChance[i]

			-- Ramp in between minDepth and peakDepth so an ore starts appearing
			-- rather than switching on at a hard line.
			local peak = orePeakDepth[i]
			if depth < peak then
				local minDepth = oreMinDepth[i]
				local span = peak - minDepth
				if span > 0 then
					chance *= (depth - minDepth) / span
				end
			end

			if chance > 0 then
				local salt = oreSalt[i]
				local inverseVein = oreInvVeinSize[i]

				local cellHit = hashUnit(
					math.floor(blockX * inverseVein),
					math.floor(blockY * inverseVein),
					math.floor(blockZ * inverseVein),
					salt
				)

				if
					cellHit < chance
					and hashUnit(blockX, blockY, blockZ, salt + 1) < oreFillRatio[i]
				then
					return oreBlock[i]
				end
			end
		end
	end

	return nil
end

--[[
	Every ore block name, for the missing-template check at startup.
]]
function OreRegistry.getBlockNames()
	local names = table.create(oreCount)
	for i = 1, oreCount do
		names[i] = oreBlock[i]
	end
	return names
end

function OreRegistry.getStats()
	return {
		ores = oreCount,
		minDepth = if oreCount > 0 then globalMinDepth else 0,
		maxDepth = if oreCount > 0 then globalMaxDepth else 0,
	}
end

return OreRegistry
