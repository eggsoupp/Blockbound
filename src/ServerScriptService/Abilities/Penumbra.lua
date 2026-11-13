--[[
	Penumbra (Celestial, F): a teleport through the ground. Timing, reach and
	the caster's path are PenumbraPlan's; the bursts, shrouds and poses are
	drawn by PenumbraVFX, and the caster's own client moves their body along
	Plan.rootAt (PenumbraMotion), since it owns the character's physics.

	The server owns:
	  - where they come up: the aim, or the nearest place back toward the
	    caster with ground under it (or, flying, open air) and room to stand.
	    No such place refuses the cast before it is paid for.
	  - whether it is the flying version (the character's Flying attribute,
	    which WingService keeps)
	  - the caster's cover: they cannot be hurt from the first burst until
	    they are out of the ground
	  - the hits: each burst hits what is in it and throws it out; the
	    arrival shroud nicks what is still inside a few times
	  - the landing itself: if the caster is not where they should be once
	    they have risen (their client dropped the effect, or never ran it),
	    the server puts them there
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Plan = require(RS.Shared.Abilities.PenumbraPlan)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local EnemyService = require(SSS.EnemyService)
local CombatService = require(SSS.CombatService)
local PhysicsService = game:GetService("PhysicsService")
local Penumbra = {}

local T = Plan.Tuning

-- The group a caster's body passes through the ground in: collides with no
-- group at all, including ones registered after this.
local function ghost()
	local ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(Plan.GhostGroup) then
			PhysicsService:RegisterCollisionGroup(Plan.GhostGroup)
		end
		for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
			PhysicsService:CollisionGroupSetCollidable(Plan.GhostGroup, group.name, false)
		end
	end)
	if not ok then warn("[Penumbra] could not set up the " .. Plan.GhostGroup .. " collision group") end
end
ghost()

function Penumbra.duration()
	return Plan.duration()
end

local function rayParams(character)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {character}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclude, player.Character) end
	end
	local enemies = workspace:FindFirstChild(EnemyConfig.WorldFolder)
	if enemies then table.insert(exclude, enemies) end
	p.FilterDescendantsInstances = exclude
	p.RespectCanCollide = true
	return p
end

local function clear(position, character)
	local p = OverlapParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = {character}
	p.RespectCanCollide = true
	return #workspace:GetPartBoundsInBox(CFrame.new(position), T.Body, p) == 0
end

-- The root's height over the floor when standing.
local function standing(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return if root and humanoid then humanoid.HipHeight + root.Size.Y * 0.5 else 3
end

--[[
	Where the caster comes up, searching from the aim back toward them. On the
	ground: a walkable floor under the spot with room to stand on it. Flying:
	open air.
]]
local function landing(context, air)
	local from = context.origin.Position
	local aim = context.target
	local offset = aim - from
	if offset.Magnitude > T.Range then
		aim = from + offset.Unit * T.Range
		offset = aim - from
	end
	local params = rayParams(context.character)
	local height = standing(context.character)
	local length = offset.Magnitude
	local step = 0
	while step <= length do
		local spot = aim - (if length > 0.01 then offset.Unit * step else Vector3.zero)
		if air then
			if clear(spot, context.character) then return spot end
		else
			local hit = workspace:Raycast(spot + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), params)
			if hit and hit.Normal.Y > 0.6 then
				local root = hit.Position + Vector3.new(0, height + 0.15, 0)
				if clear(root, context.character) then return root end
			end
		end
		step += T.SearchStep
	end
	return nil
end

function Penumbra.validate(context)
	local air = context.character:GetAttribute("Flying") == true
	local destination = landing(context, air)
	if not destination then
		return false, "Nowhere to come up there."
	end
	return true, nil, {destination = destination, air = air}
end

local function burst(context, centre, air, damage, fallback)
	EnemyService.forEachNear(centre, T.Radius + T.Reach, function(model, position)
		if Plan.inside(centre, position, air) then
			context.damage(model, damage)
			EnemyService.knockback(model, Plan.away(centre, position, false, fallback), T.BurstPush, T.BurstLift)
		end
	end)
	for _, victim in ipairs(Players:GetPlayers()) do
		local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		if root and Plan.inside(centre, root.Position, air) then
			CombatService.applyDamage(victim, damage, context.abilityName)
			local away = Plan.away(centre, root.Position, air, fallback)
			root:ApplyImpulse((away * T.BurstPush + Vector3.new(0, T.BurstLift, 0)) * root.AssemblyMass)
		end
	end
end

function Penumbra.cast(context)
	-- Groups registered since start-up must not catch the body either.
	ghost()
	local origin = context.origin
	local from = origin.Position
	local to = context.prepared.destination
	local air = context.prepared.air
	local heading = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local fallback = if heading.Magnitude > 0.1 then heading.Unit else origin.LookVector

	context.broadcast({
		origin = origin,
		destination = to,
		air = air,
		startedAt = workspace:GetServerTimeNow(),
		seed = context.seed,
	})

	local scope = context.scope
	scope:delay(Plan.departAt(), function()
		CombatService.shield(context.player, Plan.risenAt() - Plan.departAt() + 0.15)
		burst(context, from, air, T.DepartDamage, fallback)
	end)
	scope:delay(Plan.arriveAt(), function()
		burst(context, to, air, T.ArriveDamage, fallback)
	end)
	for _, at in ipairs(T.Ticks) do
		scope:delay(Plan.arriveAt() + at, function()
			EnemyService.forEachNear(to, T.Radius + T.Reach, function(model, position)
				if Plan.inside(to, position, air) then context.damage(model, T.TickDamage) end
			end)
			for _, victim in ipairs(Players:GetPlayers()) do
				local root = victim ~= context.player and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
				if root and Plan.inside(to, root.Position, air) then
					CombatService.applyDamage(victim, T.TickDamage, context.abilityName)
				end
			end
		end)
	end
	-- The landing, made sure of.
	scope:delay(Plan.risenAt() + 0.3, function()
		local root = context.character.Parent and context.character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - to).Magnitude > 8 then
			context.character:PivotTo(CFrame.new(to) * context.character:GetPivot().Rotation)
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)
	return true
end

return Penumbra
