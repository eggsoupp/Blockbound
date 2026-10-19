--[[
	SacredRain (server)

	What actually happens when a Sacred Rain cast lands.

	This module is the authority and nothing else: it decides when each of the
	fifteen strikes arrives, works out what was standing there, and applies the
	damage. It creates no particles, no parts and no sounds - every client near
	enough to see the cast draws it for itself from the seed this broadcasts.

	WHY THE DAMAGE IS NOT WHERE THE REFERENCE PUT IT

	The reference calls `humanoid:TakeDamage(20)` directly, on whatever it
	found. This game has one place that decides what a hit costs a player -
	CombatService, which applies armour - and one place that owns enemy health -
	EnemyService. Going around either of them would mean the barrage ignored
	armour, and that enemies killed by it never ran their death or drop logic.

	The amount is no longer the reference's twenty - see SacredRainPlan.Damage -
	but where it is sent is still this game's business rather than the
	reference's.

	HOW A TARGET IS FOUND

	Two questions, asked separately, because they have different right answers.
	Enemies are asked of EnemyService, which knows exactly where all of them are;
	players are found with a box query, which is what a spatial query is good at.
	Anything that is neither is left alone - damaging a model no system claims is
	how you end up with a half-dead something nothing will ever clean up.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SacredRainPlan = require(Shared:WaitForChild("Abilities"):WaitForChild("SacredRainPlan"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))

local Tuning = SacredRainPlan.Tuning

local SacredRain = {}

--[[
	How long after the strike is cast the sword arrives.

	portal opens -> 0.5s -> weapon appears -> 1.0s -> 0.4s flight. The reference
	does this with three sequential task.wait calls inside a task.defer; adding
	them up is the same schedule with one timer instead of three.
]]
local IMPACT_DELAY = Tuning.PortalBurstDelay + Tuning.SwordFadeInTime + Tuning.TravelTime

--[[
	A ceiling on how much the server will look at per strike.

	The reference's box is twenty studs on a side and it looks at everything in
	it. In a world made of blocks that box is mostly terrain, and terrain has no
	Humanoid, so capping the result costs nothing real and puts a hard bound on
	the work one keypress can ask for.
]]
local MAX_PARTS_PER_STRIKE = 40

function SacredRain.duration(): number
	return SacredRainPlan.duration()
end

--[[
	Applies one strike's damage.

	`hitCFrame` is where the sword ended up: the flight orientation, at the
	landing position - which is exactly what the reference tests, because it
	queries the sword's own CFrame the moment its Position tween completes.
]]
local function resolveStrike(context, hitCFrame: CFrame, params: OverlapParams, damage: number)
	-- One hit per victim per strike. A 20-stud box catches several parts of the
	-- same body, and the reference keeps the same list for the same reason.
	local struck = {}

	--[[
		ENEMIES, asked of EnemyService rather than of the world.

		This used to go through the box query with everything else, and took two
		bugs at once for it. A part only comes back from a spatial query if it
		is CanQuery, which nothing guarantees for an imported enemy asset; and
		the damage was gated on the model having a Humanoid, which EnemyService
		explicitly does not require ("a Humanoid is not needed and is not used
		for movement"). Between them, an enemy built the ordinary way took no
		damage from this ability at all.

		Asking the service is also immune to the third problem below.

		The sphere is inscribed in the reference's box rather than matching it
		exactly. Derived from HitBoxSize so retuning the box still moves this.
	]]
	local reach = math.min(Tuning.HitBoxSize.X, Tuning.HitBoxSize.Y, Tuning.HitBoxSize.Z) * 0.5

	EnemyService.forEachNear(hitCFrame.Position, reach, function(model)
		if not struck[model] then
			struck[model] = true
			context.damage(model, damage)
			Profiler.count("Ability.sacredRain.hit")
		end
	end)

	--[[
		PLAYERS, still by box query - a character is a known shape with a known
		Humanoid, which is exactly the case the query is good at.

		`params` excludes the terrain: in a world made of blocks a 20-stud box is
		mostly terrain, and MaxParts is a cap on what comes back, not a filter on
		what is worth returning. Left unfiltered, a hundred-odd terrain blocks
		could fill the cap before the engine ever reached a player standing in
		the middle of it.
	]]
	local hits = workspace:GetPartBoundsInBox(hitCFrame, Tuning.HitBoxSize, params)

	for _, part in ipairs(hits) do
		local model = part.Parent
		local victim = model and Players:GetPlayerFromCharacter(model)

		if victim and model ~= context.character and not struck[model] then
			struck[model] = true

			-- Raw damage in; CombatService decides what it costs after armour.
			CombatService.applyDamage(victim, damage, context.abilityName)
			Profiler.count("Ability.sacredRain.hit")
		end
	end
end

function SacredRain.cast(context)
	local plan = SacredRainPlan.build(context.seed, context.origin, context.target)

	-- One packet for the whole cast. Everything the clients need to draw all
	-- fifteen strikes is in here; see SacredRainPlan.
	context.broadcast({
		seed = context.seed,
		origin = context.origin,
		target = context.target,
	})

	--[[
		Built once and reused by all fifteen queries rather than per strike.
		The caster is excluded here rather than filtered afterwards so the
		engine never returns their own body in the first place.
	]]
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	--[[
		The caster, and the entire terrain.

		Excluding the terrain here rather than skipping it in the loop is the
		point: MaxParts caps what the engine RETURNS, so anything filtered
		afterwards has already used up a slot. A 20-stud box holds a hundred and
		twenty-odd block cells, so terrain could fill the cap on its own and the
		query would come back without ever having looked at the player standing
		in the middle of it.

		Trees and other structures live under the same folder, so this excludes
		those too - which is correct, since neither is something a blade can hurt.
	]]
	local excluded = { context.character }

	local terrainRoot = workspace:FindFirstChild("GeneratedTerrain")
	if terrainRoot then
		table.insert(excluded, terrainRoot)
	end

	params.FilterDescendantsInstances = excluded
	params.MaxParts = MAX_PARTS_PER_STRIKE

	for _, strike in ipairs(plan.strikes) do
		-- The sword keeps its flight orientation and ends at the landing point.
		local hitCFrame = CFrame.new(strike.endPosition) * strike.startCFrame.Rotation

		-- The finale hits harder; every other strike scales by 1. Resolved here
		-- so the damage number travels with the strike that earned it.
		local damage = Tuning.Damage * (strike.damageScale or 1)

		context.scope:delay(strike.castAt + IMPACT_DELAY, function()
			resolveStrike(context, hitCFrame, params, damage)
		end)
	end

	return true
end

return SacredRain
