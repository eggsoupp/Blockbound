--[[
	EnemyService

	Spawns enemies, moves them, and hurts anyone they touch.

	  EnemyService.init()
	  EnemyService.spawn(name, position) -> model, reason
	  EnemyService.spawnNear(player, name, count) -> spawned, reason
	  EnemyService.despawnAll() -> count
	  EnemyService.damage(model, amount) -> alive
	  EnemyService.getStats()

	It owns the plumbing. What each enemy IS lives in
	ReplicatedStorage.Shared.Enemies.EnemyConfig, and what each one LOOKS like
	lives in ReplicatedStorage.EnemyAssets - so adding a third enemy is a config
	entry and a model, never a change here.

	NOT HUMANOIDS. Every part is anchored and the server sets the model's
	position outright on a fixed tick. Both enemies exist to close the distance
	and touch you; neither opens a door or takes cover, so this costs no physics
	simulation, imposes nothing on the art (rigged, loose or a single mesh all
	work), and makes "walks through walls" a property of the movement kind
	rather than an argument with the collision system.

	  Fly   straight at the target through anything, bobbing
	  Hop   arcs along the terrain surface, reading ground height from
	        TerrainManager so it climbs hills and drops into dug holes

	Positions, damage, death and the hit feedback all happen here. Clients are
	told nothing and asked nothing - an enemy is a replicated model that moves,
	flashes when it is hit, and bursts when it dies.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))

local EnemyDrops = require(ReplicatedStorage:WaitForChild("EnemyDrops"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local BossService = require(ServerScriptService:WaitForChild("BossService"))

--[[
	"Something dropped, and here is where it came from." Sent only to the player
	who earned it; a drop is a private event and everyone else's client has
	nothing to draw.
]]
local DropFlight = Remotes.ensure("EnemyDropFlight", "RemoteEvent")

-- Its own source, so the drop rolls cannot be shifted by anything else pulling
-- numbers out of a shared generator - the spawner, the size jitter.
local dropRandom = Random.new()

local STUD_SIZE = TerrainConfig.StudSize

--[[
	The floating damage number.

	`life` is short on purpose. It is a receipt, not a label - it has to be
	readable and then out of the way before the next swing lands, and Sacred
	Rain lands fifteen of them.
]]
local DAMAGE_TEXT = {
	width = 90,
	height = 28,
	size = 24,
	rise = 3.4,
	spread = 2.2,
	life = 0.85,
	maxDistance = 110,
}

-- Name plate geometry. Offset pixels, so it stays the same size on screen at
-- any distance rather than growing as you approach.
local PLATE = {
	width = 140,
	height = 18,
	barHeight = 6,
	gap = 2,
	rise = 2.2, -- studs above the model's own top
	maxDistance = 120,
}

local EnemyService = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local isInitialized = false

local assetsFolder = nil
local worldFolder = nil

--[[
	model -> entry.

	Deliberately a strong table. Weak keys would look tidier, but aliveCount
	is what enforces MaxAlive and what the tick skips on, and an entry collected
	out from under it would leave that number permanently too high - a cap that
	silently tightens over a session is a worse bug than a leak. Every exit is
	explicit instead: removeEntry, or the parent check at the top of the tick.
]]
local entries = {}
local aliveCount = 0

local tickAccumulator = 0

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function findAssets()
	if assetsFolder and assetsFolder.Parent then
		return assetsFolder
	end

	assetsFolder = ReplicatedStorage:FindFirstChild(EnemyConfig.AssetsFolder)
	return assetsFolder
end

local function ensureWorldFolder()
	if worldFolder and worldFolder.Parent then
		return worldFolder
	end

	worldFolder = workspace:FindFirstChild(EnemyConfig.WorldFolder)
	if not worldFolder then
		worldFolder = Instance.new("Folder")
		worldFolder.Name = EnemyConfig.WorldFolder
		worldFolder.Parent = workspace
	end

	return worldFolder
end

--[[
	Prepares a freshly cloned model to be driven by the server.

	Anchoring everything is what makes PivotTo the single source of truth for
	where an enemy is. A stray unanchored part would fall away from the rest of
	the model on the first tick, and it is the kind of thing that looks like a
	physics bug rather than a missing property.
]]
local function prepareModel(model)
	local root = model.PrimaryPart

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = EnemyConfig.Collides
			descendant.CanTouch = false

			if not root then
				root = descendant
			end
		end
	end

	if root and not model.PrimaryPart then
		model.PrimaryPart = root
	end

	-- A Humanoid is not needed and is not used for movement, but if the artist
	-- rigged one it stays: it gives the model a name tag and a health bar, and
	-- it is where a future player attack would land.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.AutoRotate = false

		-- Its built-in name tag and health bar are switched off: this service
		-- draws its own, from displayName rather than the asset name, and two
		-- stacked bars saying the same thing is worse than either alone.
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	return root, humanoid
end

--[[
	The name plate: what it is called, and how much life it has left.

	A BillboardGui built here on the server rather than by each client. It is a
	handful of frames that only change when something takes a hit, so the
	replication is negligible - and building it here means it exists for anything
	that spawns an enemy, including a future spawner, with no client to keep in
	step.

	Sized in offset rather than scale so it stays legible at distance instead of
	swelling as you walk up to it, and studs-offset above the model's own height
	so it clears a tall enemy as readily as a short one.
]]
local function buildNamePlate(model, def, height)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NamePlate"
	billboard.Size = UDim2.fromOffset(PLATE.width, PLATE.height + PLATE.gap + PLATE.barHeight)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height * 0.5 + PLATE.rise, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = PLATE.maxDistance
	billboard.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.new(1, 0, 0, PLATE.height)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.BodyBold
	label.TextSize = Theme.TextSize.Small
	label.TextColor3 = Theme.Color.Text
	label.TextStrokeTransparency = 0.4
	-- displayName, not the asset name: "Blue Slime" rather than "BlueSlime".
	label.Text = def.displayName or model.Name
	label.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, 0)
	track.Size = UDim2.fromOffset(PLATE.width - 16, PLATE.barHeight)
	track.BackgroundColor3 = Theme.Color.Panel
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Stroke
	stroke.Thickness = 1
	stroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Theme.Color.Good
	fill.BorderSizePixel = 0
	fill.Parent = track

	billboard.Parent = model
	return billboard, fill
end

-- ---------------------------------------------------------------------------
-- Hit feedback
-- ---------------------------------------------------------------------------

local HIT_FLASH_SECONDS = 0.09
local HIT_FLASH_COLOR = Color3.fromRGB(255, 236, 236)

--[[
	Whitens an enemy for a moment, then puts its colours back.

	The resting colours are captured on the FIRST hit and reused after that, so
	a second hit landing mid-flash restores the real colour rather than the
	flash colour. `flashUntil` means a rapid series of hits extends one flash
	instead of racing several restores against each other.
]]
local function flashHit(entry)
	local model = entry.model
	if not model.Parent then
		return
	end

	if not entry.baseColors then
		local colors = {}
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				colors[part] = part.Color
			end
		end
		entry.baseColors = colors
	end

	for part in pairs(entry.baseColors) do
		if part.Parent then
			part.Color = HIT_FLASH_COLOR
		end
	end

	local until_ = os.clock() + HIT_FLASH_SECONDS
	entry.flashUntil = until_

	task.delay(HIT_FLASH_SECONDS, function()
		if entry.flashUntil ~= until_ or not model.Parent then
			return
		end

		for part, color in pairs(entry.baseColors) do
			if part.Parent then
				part.Color = color
			end
		end
	end)
end

-- The colour of the biggest part in a model: near enough "what colour is this
-- thing" for a shower of debris, without averaging anything.
local function dominantColor(model)
	local best, bestVolume = Color3.fromRGB(180, 180, 180), -1

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local size = part.Size
			local volume = size.X * size.Y * size.Z
			if volume > bestVolume then
				best, bestVolume = part.Color, volume
			end
		end
	end

	return best
end

--[[
	The number that floats off a hit.

	MADE HERE, LIKE THE FLASH AND THE BURST, for the same reason those are:
	everyone standing nearby sees the same figure come off the same hit. A
	client drawing its own would show one number to the player who swung and
	nothing to the player next to them, and two players hitting the same slime
	would each be watching a private fight.

	It is the RAW damage, not the health actually removed. Hitting a slime with
	four life left for seventy-five says seventy-five, because the question the
	number answers is "what does my weapon do", and an answer that shrinks as
	things die would be useless for exactly the comparison it exists to serve.

	One part, one label, gone in under a second. The rise is a tween on the part
	rather than on StudsOffset so the text drifts in world space and hits from
	two directions do not stack into an unreadable pile.
]]
local function damageNumber(position, amount, height)
	local anchor = Instance.new("Part")
	anchor.Name = "DamageNumber"
	anchor.Size = Vector3.one * 0.2
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true

	-- Jittered sideways, so a flurry of hits reads as several numbers rather
	-- than one number flickering.
	local spread = DAMAGE_TEXT.spread
	anchor.CFrame = CFrame.new(position + Vector3.new(
		(math.random() - 0.5) * spread,
		(height or 4) * 0.5,
		(math.random() - 0.5) * spread
	))
	anchor.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(DAMAGE_TEXT.width, DAMAGE_TEXT.height)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = DAMAGE_TEXT.maxDistance
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Number
	label.TextSize = DAMAGE_TEXT.size
	label.TextColor3 = Theme.Color.Text
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Text = tostring(math.max(1, math.floor(amount + 0.5)))
	label.Parent = billboard

	local rise = TweenInfo.new(DAMAGE_TEXT.life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(anchor, rise, {
		CFrame = anchor.CFrame + Vector3.new(0, DAMAGE_TEXT.rise, 0),
	}):Play()

	-- Held at full for the first part of the life and then faded, so the number
	-- is READ before it starts disappearing.
	TweenService:Create(label, TweenInfo.new(
		DAMAGE_TEXT.life * 0.45,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		0,
		false,
		DAMAGE_TEXT.life * 0.55
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	Debris:AddItem(anchor, DAMAGE_TEXT.life + 0.1)
end

--[[
	The behaviour module an enemy is driven by, or nil for one that is not.

	`behaviour` on a definition names a ModuleScript in ServerScriptService.Bosses,
	the same way an ability's `server` field names one in .Abilities. A creature
	with one is handed the whole tick and does its own moving and attacking;
	everything else goes down the Fly/Hop path in the heartbeat below.

	LOADED ON DEMAND, AND THAT IS LOAD-BEARING. A behaviour module needs to call
	back into this one - to find the ground, to spawn its adds - and a require
	at the top of this file would be a cycle. Deferring it to the first spawn
	means this module has long since finished loading and `require` hands the
	behaviour a finished table.
]]
local behaviours = {}

--[[
	ServerScriptService.SlimeBody, loaded the first time something asks for a
	bounce and never again.

	Lazy for exactly the reason behaviourFor is: SlimeBody requires THIS module
	back - it calls `remeasure` every time it changes shape - so a require at
	the top of this file would be a cycle. `false` is the cached "it is not
	there", so a missing module warns once rather than once per spawn.
]]
local slimeBodyModule = nil

local function slimeBodyClass()
	if slimeBodyModule ~= nil then
		return slimeBodyModule or nil
	end

	local moduleScript = ServerScriptService:FindFirstChild("SlimeBody")

	if not (moduleScript and moduleScript:IsA("ModuleScript")) then
		warn("[EnemyService] no ServerScriptService.SlimeBody; `bounce` enemies will not deform.")
		slimeBodyModule = false
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if not ok or type(result) ~= "table" or type(result.new) ~= "function" then
		warn(string.format(
			"[EnemyService] SlimeBody did not load: %s - the real error is the line above this.",
			tostring(result)
		))
		slimeBodyModule = false
		return nil
	end

	slimeBodyModule = result
	return result
end

--[[
	The squash and stretch that turns a hop into a body throwing itself.

	Every call is guarded here rather than at the three transitions that use it,
	because most enemies have no body and the state machine should not have to
	keep saying so. A ghost flies; nothing about that is a slime.
]]
local function bounceCrouch(entry, seconds)
	if entry.body then
		entry.body:crouch(seconds)
	end
end

local function bounceStretch(entry, seconds)
	if entry.body then
		entry.body:stretch(seconds)
	end
end

local function bounceLand(entry, seconds, amplitude)
	if entry.body then
		entry.body:wobble(seconds, amplitude)
	end
end

local function behaviourFor(def)
	local name = def.behaviour
	if type(name) ~= "string" then
		return nil
	end

	local cached = behaviours[name]
	if cached ~= nil then
		return cached or nil
	end

	local folder = ServerScriptService:FindFirstChild("Bosses")
	local moduleScript = folder and folder:FindFirstChild(name)

	if not (moduleScript and moduleScript:IsA("ModuleScript")) then
		warn(string.format(
			"[EnemyService] no behaviour module '%s' in ServerScriptService.Bosses; '%s' will "
				.. "stand still.",
			name, tostring(def.displayName or name)
		))
		behaviours[name] = false
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if not ok or type(result) ~= "table" or type(result.step) ~= "function" then
		-- pcall only ever reports "experienced an error while loading"; Roblox
		-- prints the real message on its own line just above this one.
		warn(string.format(
			"[EnemyService] '%s' did not load as a behaviour module (needs a `step` function): "
				.. "%s - the real error is the line above this one.",
			name, tostring(result)
		))
		behaviours[name] = false
		return nil
	end

	behaviours[name] = result
	return result
end

--[[
	Hands the killer whatever the thing was carrying, and tells them it is
	coming.

	THE ITEM ARRIVES LATE, ON PURPOSE

	The client flies a projectile from the corpse to the player, and the grant
	is held back for exactly as long as that takes. So the item lands in the bag
	at the moment the projectile lands on the player, the inventory watcher
	notices and writes the line, and all three agree without any of them being
	told about the others.

	The alternative - grant now, and have the client hold its own notification
	back - needs the two messages to arrive in a known order, which nothing
	guarantees across two remotes. Here the only shared fact is a constant they
	both read.

	The wait is why the player is re-checked before granting: half a second is
	long enough to leave in. An item lost that way is lost, which is the right
	outcome for somebody who is not there.
]]
local function awardDrops(entry, position)
	local dealer = entry.dealer
	if not dealer or not dealer.Parent then
		return
	end

	local rolled = EnemyDrops.roll(entry.name, dropRandom)

	for _, drop in ipairs(rolled) do
		DropFlight:FireClient(dealer, position, drop.item, drop.amount)

		task.delay(EnemyConfig.DropFlightSeconds, function()
			if dealer.Parent then
				InventoryService.AddItemByName(dealer, drop.item, drop.amount)
			end
		end)
	end
end

--[[
	A short shower of cubes where something died.

	Blocky rather than a ParticleEmitter, matching the mining and chopping
	debris, and for the same reasons: it suits the game and needs no texture.
	Massless and non-colliding, so it cannot shove anybody around.
]]
local function burst(position, color, height)
	local spread = math.max(1, height or 4) * 0.5

	for _ = 1, 10 do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.one * (0.4 + math.random() * 0.3)
		chunk.Color = color
		chunk.Material = Enum.Material.SmoothPlastic
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.Massless = true
		chunk.CFrame = CFrame.new(position + Vector3.new(
			(math.random() - 0.5) * spread,
			(math.random() - 0.5) * spread,
			(math.random() - 0.5) * spread
		)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Parent = workspace

		-- After parenting: an unparented part has no assembly for the physics
		-- engine to apply a velocity to, so setting it first does nothing.
		chunk.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 18,
			math.random() * 12 + 4,
			(math.random() - 0.5) * 18
		)

		Debris:AddItem(chunk, 1.3)
	end
end

--[[
	Redraws one enemy's bar. Colour shifts as it drops, so how hurt something is
	is readable without reading the bar's length.
]]
local function refreshNamePlate(entry)
	local fill = entry.healthFill
	if not fill or not fill.Parent then
		return
	end

	local fraction = math.clamp(entry.health / math.max(1, entry.def.health), 0, 1)
	fill.Size = UDim2.fromScale(fraction, 1)

	fill.BackgroundColor3 = if fraction > 0.5
		then Theme.Color.Good
		else Theme.Color.Good:Lerp(Theme.Color.Bad, 1 - fraction * 2)
end

--[[
	The player an enemy should be going after: the closest one that is alive and
	inside its aggro range.
]]
local function findTarget(entry, position)
	local best, bestDistance = nil, entry.def.aggroRange

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if hrp and humanoid and humanoid.Health > 0 then
			local distance = (hrp.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end

	return best, bestDistance
end

-- ---------------------------------------------------------------------------
-- Movement
-- ---------------------------------------------------------------------------

--[[
	Straight at the target, through whatever is in the way.

	The bob is what stops it reading as a sliding decal: a constant-height chase
	looks like a bug even when it is working perfectly.
]]
local function stepFly(entry, position, targetPosition, dt)
	entry.phase += dt

	-- The bob is folded into the point being chased rather than added to the
	-- result. Adding it afterwards would feed last tick's bob back in as this
	-- tick's starting height, and the oscillation would fight the chase instead
	-- of riding on top of it.
	local bob = math.sin(entry.phase * (2 * math.pi) / entry.def.bobPeriod)
		* entry.def.bobAmplitude

	local desired = targetPosition + Vector3.new(0, entry.def.hoverHeight + bob, 0)
	local delta = desired - position
	local distance = delta.Magnitude

	if distance <= 0.05 then
		return position
	end

	local step = math.min(entry.def.speed * dt, distance)
	return position + delta.Unit * step
end

--[[
	Where the ground is under a point, counting EVERY solid block.

	GetSupportY asks the same "is this cell solid" test that mining and placement
	use, so a slime stands on player-placed blocks, structure blocks and
	generated terrain alike, and drops into anything that has been mined out.
	GetSurfaceY - the terrain column height - would only see the last of those,
	which is what previously let slimes hop straight through walls.
]]
local function supportAt(entry, x, z, referenceY)
	return TerrainManager:GetSupportY(
		x, z, referenceY, entry.def.scanUpBlocks, entry.def.scanDownBlocks
	)
end

--[[
	Is there a solid block at this exact point? One lookup, no scan.

	Used for the mid-air collision test, which has to be a point question rather
	than a column one: a hopper passing OVER a wall is fine and expected, and a
	column scan could not tell that apart from running into it.
]]
local function blockedAt(x, y, z)
	return TerrainManager:IsSolidAt(
		math.floor(x / STUD_SIZE),
		math.floor(y / STUD_SIZE),
		math.floor(z / STUD_SIZE)
	)
end

--[[
	A hopper's state machine.

	  Grounded  sitting still on the ground. Genuinely still - it does not creep
	            toward you. It turns to face you and waits.
	  Windup    the telegraph. Facing you, committed to jumping, not yet moving.
	            A lunge gets a longer one, which is the only warning you get and
	            the only reason a lunge is dodgeable.
	  Airborne  a projectile. Takeoff set a velocity; gravity does the rest and
	            it cannot steer. Landing returns it to Grounded.
]]
local HOP_GROUNDED = "Grounded"
local HOP_WINDUP = "Windup"
local HOP_AIRBORNE = "Airborne"

--[[
	How the landing splat is sized.

	The amplitude is the DOWNWARD speed measured against the enemy's own
	`jumpPower`, so an ordinary hop - which lands at roughly the speed it left
	at - rings at BOUNCE_LAND_SCALE, a lunge off a bigger jumpPower rings
	harder, and a half-height drop off a ledge barely ripples.

	Scaling it off the enemy's own number rather than a global one is what lets
	a bigger, heavier hopper be added later without any of this being retuned:
	its landing is loud relative to ITS jump, which is what a landing is.
]]
local BOUNCE_LAND_SECONDS = 0.45
local BOUNCE_LAND_SCALE = 0.3
local BOUNCE_LAND_MIN = 0.12
local BOUNCE_LAND_MAX = 0.45

--[[
	Commits to a jump, aiming it at where the target is standing.

	The horizontal speed is SOLVED for rather than picked: airtime falls out of
	the takeoff speed and gravity, so dividing the distance we want to cover by
	that airtime gives the speed that lands us there. Capped, so a distant
	target means a hop in the right direction rather than a rocket.

	That is what makes hops look aimed. A fixed speed would overshoot anything
	close and fall short of anything far.
]]
local function beginJump(entry, position, targetPosition, isLunge)
	local def = entry.def

	local power = if isLunge then def.lungeJumpPower else def.jumpPower
	local maxDistance = if isLunge then def.lungeMaxDistance else def.maxHopDistance
	local maxSpeed = if isLunge then def.lungeMaxSpeed else def.maxHopSpeed

	local flat = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z)
	local distance = flat.Magnitude
	local direction = if distance > 0.01 then flat.Unit else entry.facing

	local airTime = (2 * power) / def.gravity
	local reach = math.min(distance, maxDistance)
	local speed = math.min(reach / math.max(airTime, 0.01), maxSpeed)

	entry.velocity = Vector3.new(direction.X * speed, power, direction.Z * speed)
	entry.facing = direction
	entry.state = HOP_AIRBORNE
	entry.lunging = isLunge

	--[[
		And it stretches as it leaves.

		Over the first third of the flight, not the whole of it: the shape says
		"I have just been thrown", and a body still elongating at the top of its
		arc reads as being pulled rather than as having jumped. Airtime is the
		one already solved for above.
	]]
	bounceStretch(entry, (2 * power) / def.gravity * 0.35)

	Profiler.count(if isLunge then "Enemy.lunge" else "Enemy.hop")
end

--[[
	One step of the hopper.

	Returns the new position and, when it should change, a facing direction. In
	flight it returns no facing: a thing in mid-air cannot turn, and letting it
	track the player through the arc is exactly what would make the lunge feel
	unfair rather than committed.
]]
local function stepHop(entry, position, targetPosition, dt, now)
	local def = entry.def

	if entry.state == HOP_AIRBORNE then
		local velocity = entry.velocity
		velocity = Vector3.new(velocity.X, velocity.Y - def.gravity * dt, velocity.Z)

		local x = position.X + velocity.X * dt
		local z = position.Z + velocity.Z * dt
		local y = position.Y + velocity.Y * dt

		--[[
			Ran into something side on. Horizontal motion stops and it drops,
			which is what hitting a wall mid-jump should do. Tested at the feet,
			so clearing the top of a wall still counts as clearing it.

			The second test is what makes this safe. A single "is the destination
			solid?" question cannot tell a wall ahead from the enemy already
			being inside geometry - and if the probe ever reads solid where the
			enemy currently IS, it fires every tick, cancels every hop, and the
			enemy bounces on the spot forever. That is not hypothetical: a
			mismeasured pivot, a spawn inside a block, or a player placing a
			block onto it all produce it.

			So a wall only counts as a wall if the cell being entered is solid
			AND the cell being left is not. When both read solid the question is
			meaningless, and doing nothing lets the enemy hop back out instead of
			trapping it.
		]]
		local feetY = y - entry.feetOffset + 0.1
		if blockedAt(x, feetY, z) and not blockedAt(position.X, feetY, position.Z) then
			x, z = position.X, position.Z
			velocity = Vector3.new(0, velocity.Y, 0)
		end

		-- Only look for ground on the way down. Half the arc costs no scan at
		-- all, which is what pays for running this at 30Hz.
		if velocity.Y <= 0 then
			local support = supportAt(entry, x, z, y)
			if support and y - entry.feetOffset <= support then
				--[[
					The splat, and how hard it was.

					Amplitude off the DOWNWARD speed rather than a constant, so
					a short shuffle barely ripples and a lunge from height lands
					with a proper wallop. That is the whole difference between a
					deformation that is playing and one that is reacting.
				]]
				bounceLand(
					entry,
					BOUNCE_LAND_SECONDS,
					math.clamp(
						-velocity.Y / def.jumpPower * BOUNCE_LAND_SCALE,
						BOUNCE_LAND_MIN,
						BOUNCE_LAND_MAX
					)
				)

				entry.velocity = Vector3.zero
				entry.state = HOP_GROUNDED
				entry.stateUntil = now + def.groundedSeconds
				entry.lunging = false
				entry.groundY = support
				entry.nextGroundCheck = now + 0.25
				return Vector3.new(x, support + entry.feetOffset, z), nil
			end
		end

		entry.velocity = velocity
		return Vector3.new(x, y, z), nil
	end

	-- On the ground: still, but not asleep. Face the target and decide.
	local flat = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z)
	local distance = flat.Magnitude
	local facing = if distance > 0.05 then flat.Unit else nil

	--[[
		The ground can be mined out from under it. Checked on a slow timer
		rather than every tick: nothing is moving, so the only thing that can
		change the answer is somebody digging, and four times a second is far
		faster than anyone can dig.
	]]
	if now >= (entry.nextGroundCheck or 0) then
		entry.nextGroundCheck = now + 0.25

		local support = supportAt(entry, position.X, position.Z, position.Y)
		if not support or position.Y - entry.feetOffset > support + 0.5 then
			-- Nothing underneath any more. Fall.
			entry.velocity = Vector3.zero
			entry.state = HOP_AIRBORNE
			entry.lunging = false
			return position, facing
		end

		entry.groundY = support
	end

	if entry.state == HOP_WINDUP then
		if now >= entry.stateUntil then
			beginJump(entry, position, targetPosition, entry.pendingLunge == true)
		end
		return position, facing
	end

	if now >= entry.stateUntil then
		-- Close enough, and off cooldown, means commit to the big one.
		local canLunge = distance <= def.lungeRange and now >= (entry.nextLungeAt or 0)

		entry.pendingLunge = canLunge
		entry.state = HOP_WINDUP

		local windup = if canLunge then def.lungeWindup else def.windupSeconds
		entry.stateUntil = now + windup

		-- Gathering itself, over exactly the telegraph. The squash IS the tell:
		-- a slime that is about to jump is visibly compressed for as long as
		-- the player has to react to it, which is more honest than a windup you
		-- can only see by counting.
		bounceCrouch(entry, windup)

		if canLunge then
			entry.nextLungeAt = now + def.lungeCooldown
		end
	end

	return position, facing
end

-- ---------------------------------------------------------------------------
-- Contact damage
-- ---------------------------------------------------------------------------

--[[
	Hurts every player standing in the enemy, at most once per contactInterval
	each.

	The cooldown is per PLAYER, not per enemy: two slimes on the same person
	should hurt twice as fast, and one slime should not hurt twice as fast just
	because the tick rate went up.
]]
local function applyContactDamage(entry, position, now, damage)
	local def = entry.def
	local rangeSquared = def.contactRange * def.contactRange
	damage = damage or def.contactDamage

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if hrp and humanoid and humanoid.Health > 0 then
			local offset = hrp.Position - position
			if offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z <= rangeSquared then
				local last = entry.lastHitAt[player]
				if not last or now - last >= def.contactInterval then
					entry.lastHitAt[player] = now

					-- Raw damage. What it costs after armour is CombatService's
					-- business, not the slime's - the enemy only knows how hard
					-- it hit, never how much that hurt.
					CombatService.applyDamage(player, damage, entry.name)
					Profiler.count("Enemy.contactHit")
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function removeEntry(model, reason)
	local entry = entries[model]
	if not entry then
		return
	end

	entries[model] = nil
	aliveCount -= 1

	-- Before the model goes, so a behaviour still has something to tidy up
	-- against - a telegraph on the ground, a projectile in the air.
	if entry.behaviour and entry.behaviour.finish then
		local ok, err = pcall(entry.behaviour.finish, entry, reason)
		if not ok then
			warn(string.format(
				"[EnemyService] %s behaviour finish errored: %s", tostring(entry.name), tostring(err)
			))
		end
	end

	if entry.def.boss then
		BossService.ended(entry)
	end

	if model.Parent then
		model:Destroy()
	end

	Profiler.count("Enemy.despawned")
	if reason == "died" then
		Profiler.count("Enemy.died")
	end
end

--[[
	Puts one enemy in the world.

	Returns the model, or nil plus a reason - callers are commands and future
	spawners, both of which want to say why rather than fail silently.
]]
function EnemyService.spawn(name, position)
	local def = EnemyConfig.Definitions[name]
	if not def then
		return nil, string.format("no enemy called '%s'", tostring(name))
	end

	if aliveCount >= EnemyConfig.MaxAlive then
		return nil, string.format("already at the cap of %d enemies", EnemyConfig.MaxAlive)
	end

	local folder = findAssets()
	if not folder then
		return nil, string.format(
			"ReplicatedStorage.%s does not exist", EnemyConfig.AssetsFolder
		)
	end

	local template = folder:FindFirstChild(def.asset)
	if not template then
		return nil, string.format(
			"no model called '%s' in ReplicatedStorage.%s", def.asset, EnemyConfig.AssetsFolder
		)
	end
	local model
	if template:IsA("Model") then
		model = template:Clone()
	elseif template:IsA("BasePart") then
		-- A one-piece mesh export. Wrapped rather than refused: PivotTo and
		-- GetExtentsSize both want a Model, and asking somebody to go and make
		-- one by hand is a round trip for something worth ten lines.
		model = Instance.new("Model")
		local part = template:Clone()
		part.Parent = model
		model.PrimaryPart = part
	else
		return nil, string.format(
			"'%s' is a %s; enemy assets must be a Model or a single part",
			def.asset, template.ClassName
		)
	end

	local root, humanoid = prepareModel(model)

	if not root then
		model:Destroy()
		return nil, string.format("'%s' has no BasePart in it", def.asset)
	end

	--[[
		A little variation in size, so a group does not read as one model
		duplicated.

		Rolled freshly per spawn rather than hashed from position: unlike a tree,
		an enemy is not regenerated from the world seed, so there is nothing to
		stay consistent with.

		Scaled BEFORE the bounding box is measured below, because feetOffset -
		and therefore where this thing stands, lands and tests for walls - comes
		out of that measurement.
	]]
	local sizeVariance = def.sizeVariance or EnemyConfig.SizeVariance or 0
	if sizeVariance > 0 then
		-- Multiplied by the scale the model ALREADY has, not set outright.
		-- ScaleTo is absolute: an asset scaled up after importing reports that
		-- factor from GetScale, and setting the scale to ~1 here would throw
		-- the artist's sizing away and shrink every enemy back to its import
		-- size. The authored size is what the variation happens around.
		model:ScaleTo(model:GetScale() * (1 + (math.random() * 2 - 1) * sizeVariance))
	end

	--[[
		How far the model's feet are BELOW the point movement steers by.

		Everything here - spawn placement, landing height, the ground check and
		the mid-air wall probe - works in terms of "where are its feet". That is
		only half the model's height if the pivot happens to sit at the centre of
		the bounding box, which is true of a plain cube and false of most rigged
		or hand-built models: a slime with eyes on top, or a mesh whose origin is
		at its base, puts the pivot somewhere else entirely.

		Measured against the pivot, exactly the way StructureRegistry seats trees
		on the ground, so it is right for any model.
	]]
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local height = boundsSize.Y
	local feetOffset = model:GetPivot().Position.Y - (boundsCFrame.Position.Y - height * 0.5)

	local entry = {
		name = name,
		def = def,
		model = model,
		root = root,
		humanoid = humanoid,
		height = height,
		feetOffset = feetOffset,
		health = def.health,
		phase = math.random() * 100, -- so a batch does not bob in lockstep

		-- Hopper state. Started grounded with a staggered first wait, so a
		-- batch spawned together does not jump as one block of slimes.
		state = "Grounded",
		stateUntil = os.clock() + math.random() * (def.groundedSeconds or 1),
		velocity = Vector3.zero,
		facing = Vector3.new(0, 0, 1),
		lunging = false,
		nextGroundCheck = 0,
		lastSeenPlayerAt = os.clock(),
		-- Weak, so a player leaving cannot keep their own record alive.
		lastHitAt = setmetatable({}, { __mode = "k" }),
	}

	if humanoid then
		humanoid.MaxHealth = def.health
		humanoid.Health = def.health
	end

	entry.behaviour = behaviourFor(def)

	--[[
		The asset's own idea of which way is up, corrected once, here.

		`modelRotation` is degrees (pitch, yaw, roll) baked into every placement
		this service makes. It exists because an imported model is oriented
		however the artist left it, and a slime exported lying on its side is
		not a bug in the fight - it is a fact about the file, and the fight is
		the worst possible place to compensate for it. Every PivotTo below goes
		through placeModel, so setting this once fixes standing, walking,
		leaping and everything a behaviour module does.
	]]
	local rotation = def.modelRotation
	entry.orient = if typeof(rotation) == "Vector3"
		then CFrame.Angles(
			math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)
		)
		else CFrame.identity

	if def.boss then
		BossService.engaged(entry)
	end

	model.Name = name

	-- Through the same door everything else uses, so a model with a rotation
	-- correction is already standing up on the frame it appears.
	EnemyService.placeModel(entry, position, entry.facing)

	model.Parent = ensureWorldFolder()

	-- Told after it is in the world, because the state machine only exists once
	-- it is. Physics state is how you say "I am driving this, stop trying to
	-- stand it up" to a Humanoid whose root is anchored.
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	--[[
		A deformable body, for anything that says it wants one.

		AFTER placement and parenting, and after the size variance above, for
		the same reason the boss builds his in `start`: SlimeBody records the
		resting shape from the part in front of it, and recording it any earlier
		would capture the import size - every squash would then snap the enemy
		back to a size the artist did not choose.

		Not for a behaviour-driven enemy. A boss owns its whole tick, builds its
		own body and would end up with two of them fighting over one part.
	]]
	if def.bounce and not def.behaviour then
		local SlimeBody = slimeBodyClass()

		if SlimeBody then
			local ok, body = pcall(SlimeBody.new, entry, def.bodyPart, nil)

			if ok then
				entry.body = body
			else
				warn(string.format(
					"[EnemyService] could not give %s a body: %s", tostring(name), tostring(body)
				))
			end
		end
	end

	local _, healthFill = buildNamePlate(model, def, height)
	entry.healthFill = healthFill

	entries[model] = entry
	aliveCount += 1
	-- After it is in the world and has a state machine, because a behaviour's
	-- first act is very often to move or to put something on the ground.
	if entry.behaviour and entry.behaviour.start then
		local ok, err = pcall(entry.behaviour.start, entry)
		if not ok then
			warn(string.format(
				"[EnemyService] %s behaviour start errored: %s", tostring(name), tostring(err)
			))
		end
	end

	Profiler.count("Enemy.spawned")

	return model
end

--[[
	The height something dropped at (x, z) would come to rest at.

	Support, not terrain height, so anything spawned near a player standing on
	something they BUILT lands on it rather than inside the ground beneath it.
	`referenceY` is the height to search around and the answer when there is no
	ground at all - off the edge of a generated area, mostly.
]]
local function groundAt(x, z, referenceY)
	local groundY = TerrainManager:GetSupportY(x, z, referenceY, 4, 12)
		or TerrainManager:GetSurfaceY(x, z)

	return if groundY then groundY else referenceY
end

--[[
	The same thing, for behaviour modules.

	Public because a boss has to put its own feet, its own shockwaves and its
	own adds on the ground, and reimplementing this over there would be a second
	answer to "what is the height here" that drifts from the first.
]]
function EnemyService.groundAt(x: number, z: number, referenceY: number): number
	return groundAt(x, z, referenceY)
end

--[[
	Stands an enemy on the ground at a point, facing a direction.

	THE ONE PLACE A MODEL IS PUT ANYWHERE, and the reason it is public: a boss
	that leaps, flattens and bounces needs to place itself dozens of times a
	second, and three things have to be right every single time.

	  - the FEET go where you asked, not the pivot. feetOffset is measured from
	    the model's own bounding box at spawn, so this is correct for a pivot
	    sitting anywhere in the mesh.
	  - both arguments to lookAt come from the SAME point. Mixing the raised eye
	    with a ground-level target puts a drop of feetOffset into the look
	    direction, which on a large model points it nearly straight down, makes
	    lookAt degenerate against its default up vector, and rolls the thing
	    onto its side.
	  - the asset's own orientation correction is applied last. See modelRotation.

	`facing` may be nil, which keeps whatever rotation it already had - what a
	hopper wants in mid-air, and what anything deforming in place wants.
]]
function EnemyService.placeModel(entry, ground: Vector3, facing: Vector3?)
	local eye = ground + Vector3.new(0, entry.feetOffset, 0)
	local orient = entry.orient or CFrame.identity

	if facing and facing.Magnitude > 0.001 then
		entry.facing = facing.Unit
	end

	local look = entry.facing

	if look and look.Magnitude > 0.001 then
		entry.model:PivotTo(CFrame.lookAt(eye, eye + look.Unit) * orient)
	else
		entry.model:PivotTo(CFrame.new(eye) * orient)
	end
end

--[[
	Re-measures the feet after a model changes shape.

	A boss made of slime resizes its own body, and every number above is
	measured from a bounding box that has just changed. Called by whatever did
	the resizing; nothing here can know when that happened.
]]
function EnemyService.remeasure(entry, bottomY: number?)
	local boundsCFrame, boundsSize = entry.model:GetBoundingBox()

	entry.height = boundsSize.Y

	--[[
		`bottomY` overrides where the feet are.

		A boss made of slime carries a crown, and the crown is INSIDE the
		model's bounding box. Flatten him and the crown ends up level with or
		below the body's underside, at which point the box's bottom is the hat -
		so the feet move, so the placement moves, so the box moves. That loop
		runs once a frame while he breathes and comes out as a vertical twitch.

		The caller knows which part is actually his feet. When it says so, that
		wins over the box.
	]]
	local bottom = bottomY
		or (boundsCFrame.Position.Y - boundsSize.Y * 0.5)

	entry.feetOffset = entry.model:GetPivot().Position.Y - bottom
end

--[[
	Spawns a group AT A PLACE, scattered around it.

	This is what the ambient spawner uses. It takes a point rather than a player
	because where a group belongs is a property of the world - a hollow, a patch
	of Corruption - and not of who happens to be nearby; the spawner picks the
	place and this fills it.

	`spread` is how loosely they are scattered. Randomly, not on a ring: a ring
	of four slimes reads as an arrangement, and the point of a pack is that
	nobody arranged it.
]]
function EnemyService.spawnPack(name, center, count, spread)
	if typeof(center) ~= "Vector3" then
		return 0, "no position to spawn at"
	end

	count = math.clamp(math.floor(tonumber(count) or 1), 1, 25)
	spread = tonumber(spread) or 8

	local spawned, lastReason = 0, nil

	for _ = 1, count do
		local x = center.X + (math.random() - 0.5) * 2 * spread
		local z = center.Z + (math.random() - 0.5) * 2 * spread
		local y = groundAt(x, z, center.Y)

		local model, reason = EnemyService.spawn(name, Vector3.new(x, y, z))
		if model then
			spawned += 1
		else
			lastReason = reason
		end
	end

	return spawned, lastReason
end

--[[
	Spawns a batch in a ring around a player, on the ground where there is
	ground.

	A ring rather than a point so a count of five is five visible enemies
	instead of one enemy with four inside it. That is what a COMMAND wants -
	/spawn 5 should show you five things - and is why this is still separate
	from spawnPack, which deliberately does the opposite.
]]
function EnemyService.spawnNear(player, name, count, radius)
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return 0, "no character to spawn near"
	end

	count = math.clamp(math.floor(tonumber(count) or 1), 1, 25)
	radius = tonumber(radius) or 14

	local origin = hrp.Position
	local spawned, lastReason = 0, nil

	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local x = origin.X + math.cos(angle) * radius
		local z = origin.Z + math.sin(angle) * radius
		local y = groundAt(x, z, origin.Y)

		local model, reason = EnemyService.spawn(name, Vector3.new(x, y, z))
		if model then
			spawned += 1
		else
			lastReason = reason
		end
	end

	return spawned, lastReason
end

--[[
	Applies damage from outside - today, WeaponServer. Returns whether it is
	still alive, so a caller can react to a kill.

	The flash and the death burst are made HERE rather than by the swinging
	client, so everyone standing nearby sees the same hit land on the same
	enemy. Both are ordinary replicated parts; neither needs a remote.
]]
--[[
	`dealer` is the player who gets the credit, and may be nil.

	Remembered rather than used immediately, because the hit that kills is very
	often not the hit that matters: Sacred Rain lands fifteen times and the
	fifteenth is the one that happens to finish it. Keeping the LAST player to
	do damage is the simplest rule that gets the drops to the right person in
	every case anybody has complained about, and it costs one field.

	A kill by something with no dealer - a future trap, one enemy hurting
	another - drops nothing, which is correct rather than a gap: there is nobody
	for it to drop TO.
]]
function EnemyService.damage(model, amount, dealer)
	local entry = entries[model]
	if not entry then
		return false
	end

	local dealt = math.max(0, tonumber(amount) or 0)
	entry.health -= dealt
	refreshNamePlate(entry)

	if dealt > 0 and dealer then
		entry.dealer = dealer
	end

	if entry.def.boss and dealt > 0 then
		BossService.update(entry)
	end

	-- Before the death check, so the blow that kills something still says what
	-- it hit for. A killing hit that shows nothing is the one hit a player most
	-- wants the number from.
	if dealt > 0 then
		damageNumber(model:GetPivot().Position, dealt, entry.height)
	end

	if entry.humanoid then
		entry.humanoid.Health = math.max(0, entry.health)
	end

	if entry.health <= 0 then
		local where = model:GetPivot().Position

		burst(where, dominantColor(model), entry.height)

		-- Before removeEntry, which is what forgets whose kill it was.
		awardDrops(entry, where)

		removeEntry(model, "died")
		return false
	end

	flashHit(entry)
	return true
end

--[[
	Calls `visit(model, position)` for every live enemy within `range` studs of
	a point.

	A direct walk of the live set rather than a workspace query. There are never
	more than EnemyConfig.MaxAlive of them, so this is a few dozen distance
	checks - cheaper than a spatial query, and it cannot be fooled by an
	enemy's parts having the wrong CanQuery or by something else being in the
	way. Position comes from the pivot, which is what the movement code writes.

	Allocation free: the caller is handed each enemy as it is found rather than a
	list, because a swing usually keeps one of them and throws the rest away.
]]
function EnemyService.forEachNear(position, range, visit)
	local rangeSquared = range * range

	for model in pairs(entries) do
		if model.Parent then
			local enemyPosition = model:GetPivot().Position
			local offset = enemyPosition - position

			if offset:Dot(offset) <= rangeSquared then
				visit(model, enemyPosition)
			end
		end
	end
end

--[[
	The registered enemy an instance belongs to, or nil.

	Walks up from a part, because a hit almost never lands on the model itself -
	it lands on some part inside it, which may be nested under other parts or
	folders depending on how the asset was built. Bounded by the world folder so
	a stray instance cannot send this walking to the DataModel root.
]]
function EnemyService.modelFor(instance)
	if typeof(instance) ~= "Instance" then
		return nil
	end

	local current = instance
	while current and current ~= worldFolder do
		if entries[current] then
			return current
		end
		current = current.Parent
	end

	return nil
end

--[[
	What kind of enemy a model is, and how much life it has left, or nil if it is
	not a live enemy. Lets a caller report a hit without holding onto the entry.
]]
function EnemyService.describe(model)
	local entry = entries[model]
	if not entry then
		return nil
	end

	return entry.name, entry.health, entry.def.health
end

--[[
	Removes one enemy, without it counting as a kill.

	`despawnAll` already did this for the whole world; a boss that eats its own
	children needed it for one. The reason it is not just `removeEntry` made
	public is the REASON string: "absorbed" is not "died", so nothing downstream
	rolls a drop table or counts it toward a kill statistic. A slime the boss
	reabsorbed did not die, and the player who has to fight it again should not
	have been paid for it.
]]
function EnemyService.despawn(model, reason: string?)
	if not entries[model] then
		return false
	end

	removeEntry(model, reason or "absorbed")
	return true
end

--[[
	Gives health back.

	Clamped to the definition's maximum, so nothing can inflate an enemy past
	the bar that is drawn for it, and it refreshes the plate and the boss bar
	the same way damage does - a boss that healed silently would be a boss whose
	health bar lies.
]]
function EnemyService.heal(model, amount: number)
	local entry = entries[model]
	if not entry then
		return 0
	end

	local before = entry.health
	entry.health = math.min(entry.def.health, entry.health + math.max(0, amount))

	local given = entry.health - before
	if given <= 0 then
		return 0
	end

	refreshNamePlate(entry)

	if entry.humanoid then
		entry.humanoid.Health = entry.health
	end

	if entry.def.boss then
		BossService.update(entry)
	end

	return given
end

--[[
	Every live model of one kind. For commands that want to act on a species
	rather than on one creature.
]]
function EnemyService.allOf(name: string): { Model }
	local found = {}

	for model, entry in pairs(entries) do
		if entry.name == name then
			table.insert(found, model)
		end
	end

	return found
end

--[[
	Changes an enemy's model orientation correction, live.

	Only useful behind /bbface. The correction is normally read once at spawn
	from the definition, because it is a property of the ASSET and does not
	change - this exists so that finding the right value does not require a
	rebuild per guess.
]]
function EnemyService.reorient(model, rotation: Vector3)
	local entry = entries[model]
	if not entry or typeof(rotation) ~= "Vector3" then
		return false
	end

	entry.orient = CFrame.Angles(
		math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)
	)

	-- Applied immediately, so the answer is visible before the next hop.
	EnemyService.placeModel(
		entry, model:GetPivot().Position - Vector3.new(0, entry.feetOffset, 0), nil
	)

	return true
end

function EnemyService.despawnAll()
	local removed = 0

	for model in pairs(entries) do
		removeEntry(model, "cleared")
		removed += 1
	end

	return removed
end

function EnemyService.getStats()
	local perType = {}
	for _, entry in pairs(entries) do
		perType[entry.name] = (perType[entry.name] or 0) + 1
	end

	return {
		alive = aliveCount,
		cap = EnemyConfig.MaxAlive,
		perType = perType,
	}
end

-- ---------------------------------------------------------------------------
-- The tick
-- ---------------------------------------------------------------------------

local function stepAll(dt)
	local now = os.clock()

	for model, entry in pairs(entries) do
		if not model.Parent or not entry.root.Parent then
			-- Something else destroyed it. Drop the record rather than moving a
			-- part that is no longer in the world.
			entries[model] = nil
			aliveCount -= 1
			continue
		end

		--[[
			The jelly, BEFORE anything reads where it is.

			Changing shape moves the model - SlimeBody lifts the pivot by
			however far the underside travelled, so the feet stay planted - and
			it rewrites `feetOffset` while it is there. Stepping it after the
			position had been read would place the enemy from a measurement
			taken of a different shape, once per tick, forever.

			It costs nothing when nothing is animating, which for a hopper is
			the middle of a hop and the wait between them.

			Not for a behaviour-driven one. A boss builds its own body and steps
			it itself, and stepping it here as well would do every shape change
			twice a tick - two bounding box measurements and two PivotTos for
			one frame of animation.
		]]
		if entry.body and not entry.behaviour then
			entry.body:step()
		end

		-- The PIVOT, not the root part. PivotTo writes the pivot, feetOffset is
		-- measured from the pivot, and a model whose pivot is not its root would
		-- otherwise be read in one frame of reference and written in another -
		-- which drifts a little further every tick.
		local position = model:GetPivot().Position

		--[[
			A creature with a behaviour module owns its whole tick.

			Everything below - the aggro/give-up dance, Fly, Hop, contact damage,
			the despawn timer - is the default creature, and a boss is not one:
			it does not lose interest, it does not wander off, and what it does
			when a player is in range is the entire point of it. Handing it the
			tick outright is cheaper to reason about than a movement kind with
			six flags on it, and it cannot be broken by a later change to how
			slimes decide to jump.
		]]
		if entry.behaviour then
			local ok, err = pcall(entry.behaviour.step, entry, dt, now)
			if not ok then
				warn(string.format(
					"[EnemyService] %s behaviour errored: %s", tostring(entry.name), tostring(err)
				))
			end
			continue
		end

		local target = findTarget(entry, position)

		if target then
			entry.lastSeenPlayerAt = now
			entry.chasing = target
		elseif entry.chasing then
			-- Keep chasing past aggro range, up to giveUpRange, so a player does
			-- not shed a pursuer by stepping one stud too far.
			local character = entry.chasing.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - position).Magnitude <= entry.def.giveUpRange then
				target = entry.chasing
				entry.lastSeenPlayerAt = now
			else
				entry.chasing = nil
			end
		end

		if target then
			local hrp = target.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local targetPosition = hrp.Position
				local moved

				local facing

				if entry.def.movement == "Fly" then
					moved = stepFly(entry, position, targetPosition, dt)

					local flat = Vector3.new(
						targetPosition.X - moved.X, 0, targetPosition.Z - moved.Z
					)
					facing = if flat.Magnitude > 0.05 then flat.Unit else nil
				else
					moved, facing = stepHop(entry, position, targetPosition, dt, now)
				end

				--[[
					A nil facing means "hold the one you have", which is what a
					hopper returns in mid-air: it committed to a direction at
					takeoff and cannot turn until it lands. placeModel takes
					that reading of nil directly.

					`moved` is a PIVOT position and placeModel wants FEET, so
					the offset comes back off before handing it over - the two
					have to be in the same frame of reference or an enemy sinks
					by its own height the moment it moves.
				]]
				EnemyService.placeModel(
					entry, moved - Vector3.new(0, entry.feetOffset, 0), facing
				)

				-- A lunge hits harder than a bump. The enemy still only reports
				-- raw damage; which number it reports is the whole difference
				-- between a slime brushing past you and one landing on you.
				local damage = if entry.lunging and entry.def.lungeDamage
					then entry.def.lungeDamage
					else entry.def.contactDamage

				applyContactDamage(entry, moved, now, damage)
			end
		elseif entry.state == HOP_AIRBORNE then
			--[[
				Losing sight of a player mid-jump must not stop the jump. Only
				the target is gone; gravity is not, and freezing a hopper in the
				air the instant somebody steps out of range is exactly the kind
				of thing that makes a creature look like a puppet.

				Stepped against its own position, so it finishes the arc it
				committed to and then sits down, rather than aiming a new one.
			]]
			local moved = stepHop(entry, position, position, dt, now)

			-- No facing: it is finishing an arc it already committed to, and
			-- turning it now would be steering a jump nobody is aiming.
			EnemyService.placeModel(
				entry, moved - Vector3.new(0, entry.feetOffset, 0), nil
			)
		elseif now - entry.lastSeenPlayerAt >= entry.def.despawnSeconds then
			removeEntry(model, "abandoned")
			continue
		end
	end

	Profiler.sample("Enemy.alive", aliveCount, "enemies")
end

local function onHeartbeat(dt)
	tickAccumulator += dt
	if tickAccumulator < EnemyConfig.TickInterval then
		return
	end

	local step = tickAccumulator
	tickAccumulator = 0

	if aliveCount == 0 then
		return
	end

	Profiler.enter("Enemy.tick")
	stepAll(step)
	Profiler.leave("Enemy.tick")
end

function EnemyService.init()
	if isInitialized then
		return
	end
	isInitialized = true

	EnemyConfig.validate()
	ensureWorldFolder()

	if not findAssets() then
		warn(string.format(
			"[EnemyService] ReplicatedStorage.%s does not exist yet. Enemies cannot spawn "
				.. "until it does, holding a Model for each asset named in EnemyConfig.",
			EnemyConfig.AssetsFolder
		))
	end

	Players.PlayerRemoving:Connect(function(player)
		-- The per-player damage cooldowns are weak-keyed, so they clear
		-- themselves; anything still CHASING the player is released here so it
		-- picks a new target on its next tick instead of holding a dead one.
		for _, entry in pairs(entries) do
			if entry.chasing == player then
				entry.chasing = nil
			end
		end
	end)

	RunService.Heartbeat:Connect(onHeartbeat)
end

return EnemyService
