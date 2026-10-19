--[[
	SlimeEmperor

	A monarch made entirely of living slime, wearing a crown.

	FOUR THINGS HE IS, AND EVERY ATTACK IS ONE OF THEM

	  HIS BODY IS THE WEAPON, AND IT IS FINITE.  He has MASS. Everything he
	    throws is made of him and costs mass; everything he takes back returns
	    it. Mass is his size, his reach, his contact hitbox and how hard he is
	    to fight - all read live off the body part, never from a number
	    written beside it.

	  HE RULES LESSER SLIMES.  The handfuls he sheds get up and walk. They are
	    his subjects: he can command them down a lane at you (ROYAL DECREE) or
	    take them back into himself and heal (REABSORB). The player decides
	    whether a slime dies now or becomes an attack and a heal later.

	  THE CROWN IS HIS AUTHORITY.  It burns when he commands, it leans toward
	    ground he is about to take, and in CORONATION it leaves his head and
	    he rebuilds himself around where it lands.

	  HE EATS THE WORLD.  CLAIM THE REALM sends veins of him through the
	    terrain and bites the floor out at their ends. The blocks are swallowed
	    and he grows. The arena is a second source of mass, which is the one
	    thing a slime king could do in THIS game and nowhere else.

	THE ECONOMY

	    RAIN / DECREE BLOBS      spend mass. He visibly shrinks, crown and all.
	    CLAIM THE REALM          gains a little mass from the ground. Never health.
	    REABSORB                 gains mass AND HEALS. The only heal he has.

	So his subjects are a three-way relationship the player has to manage:
	Slime Rain produces them, Royal Decree weaponises them, Reabsorb reclaims
	them. Killing them is the difference between a boss who gets smaller all
	fight and one who keeps rebuilding himself - and killing the one he is
	reaching for, mid-reach, interrupts him outright.

	THE DECK

	  BODY COLLAPSE    loses shape entirely and spreads. The damage area IS
	                   his flattened body, measured off the part.
	  CLAIM THE REALM  plants; veins spread toward you along the floor, bite
	                   the ground at their ends, and the ground is pulled back
	                   through them and swallowed. He swells.
	  SLIME RAIN       hauls himself up and throws handfuls over the arena.
	                   Some get up. This is how he breeds.
	  REABSORB         ropes a survivor back in on a tether, shrinking it as it
	                   comes, and swells and heals as it lands. Kill the slime
	                   on the rope and nothing lands: no mass, no heal.
	  ROYAL DECREE     rises tall, crown burning, links up to three subjects
	                   and sends each down a marked lane as a surge of slime. A
	                   subject killed before the command loses its lane. With
	                   no subjects he tears one or two small blobs off himself
	                   instead - weaker, and it costs him.
	  CORONATION       flattens, fires the crown straight up, flows under where
	                   it will land, and erupts around it as it comes down.

	WHAT WAS CUT, AND WHY

	SLIME CANNON was a projectile: ninety studs in a straight line, step
	sideways. A dragon could do it. RICOCHET was three big hops with landing
	circles, and since he hops to get about anyway it was his walk, louder,
	and it carried him out of the fight. Neither used a property of being
	slime that something else here did not use better, and neither was fixed
	by a bigger number. Claim the Realm and Royal Decree took their slots.

	Hopping stays as LOCOMOTION. The problem was never that he hops; it was
	that a series of hops was an attack.

	SHAPE-BASED ATTACKS NEED A DEFORMABLE BODY

	SlimeBody can only truly deform a body that is ONE BasePart. If the artist
	built him from several it falls back to uniform scaling, and the attacks
	whose whole content is a SHAPE - Body Collapse and Coronation - are dropped
	from the deck rather than played invisibly. See `deckFor`. Claim, Rain,
	Reabsorb and Decree do not depend on it, so the deck is never empty.

	TERRAIN

	The ground he eats goes through TerrainManager's own authority
	(PlanExcavation / ExecuteExcavation): natural, breakable, loaded, dry
	ground only - never a placed block, a structure, a cave wall or bedrock -
	under hard caps, with no loot, and with the cells frozen BEFORE the warning
	is drawn. Clients are then told which blocks really went and animate copies
	being swallowed. The terrain rules are documented over there; this file
	only chooses where to bite.

	CLEANUP

	Every attack runs inside an AbilityScope (`entry.scope`): temporary parts,
	tethers, tweens, delayed tasks, the grip on any slime he is commanding and
	the crown's pose all go into it, and performAttack destroys it when the
	attack ends however it ended. `finish` destroys it on death. Older helpers
	(telegraph discs, ripples, splatter) are on Debris timers measured in
	seconds and need nothing. Every wait goes through `pause`, which stops the
	moment `entry.slimeFinished` is set.

	IT DRIVES ITSELF

	EnemyService hands this the whole tick (see `behaviour` there), and every
	placement goes back through EnemyService.placeModel - so the model's
	orientation correction, its feet and its facing are the service's business,
	not this file's.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local WeaponConfig = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponConfig"))

local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local BossService = require(ServerScriptService:WaitForChild("BossService"))
local SlimeBody = require(ServerScriptService:WaitForChild("SlimeBody"))
local TerrainManager = require(ServerScriptService:WaitForChild("TerrainManager"))

local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AbilityScope = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityScope"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))

-- Told to clients AFTER the ground has changed, with what really went; see
-- claimRealm and StarterPlayerScripts.BossTerrainClient.
-- Ensured by BossService at server start as well, so it exists before any
-- boss does; ensure is idempotent and this is the one that names it here.
local BossTerrain = Remotes.ensure("BossTerrain", "RemoteEvent")

-- How far from him a client has to be to be told about swallowed ground.
-- Generous: it is a few dozen small parts, and watching from a hill is fine.
local DEBRIS_BROADCAST_RADIUS = 320

local STUD_SIZE = TerrainConfig.StudSize

local SlimeEmperor = {}

local SOURCE = "Slime Emperor"

-- The slime he sheds. An ordinary enemy, so it hops, aggros and dies like
-- every other one: he adds a wave, not a creature to learn.
local SPAWN_NAME = "BlueSlime"

--[[
	BALANCE

	A player has 100 health (CombatConfig.BaseMaxHealth). "Relatively decent
	gear" was taken as an iron or gold sword - 10 or 13 damage on a 0.55 second
	swing, so 18 to 24 damage a second - plus one ability every fifteen to
	thirty seconds, which is what the mana pool actually allows.

	At 24 a second his 1500 health is about a minute: twelve or thirteen
	attacks, which shows the whole deck twice with the phases changing under it.
	Ninety seconds was right when there were nine attacks and turned out to be
	long for six - it showed the player everything it had, twice, before it
	ended. Void gear halves it, which is what better gear is for. TestSword is
	273 a second and kills him in four; that is a testing number, and nothing
	here is tuned against it.

	Damage is in fractions of a health bar, chosen so that ONE mistake is always
	survivable from full and THREE in a row is a death. Nothing here hits for
	more than 34, and the two attacks that do have the longest tells in the
	fight.

	NOTHING GETS BIGGER NUMBERS IN LATER PHASES. See `deckFor`.
]]
local Tuning = {
	-- Between attacks, by phase. The lower bound is what a player is actually
	-- given to reposition in, so it is the number that decides whether this is
	-- fair rather than merely busy.
	restMin = { 3.6, 3.0, 2.4 },
	restMax = { 5.2, 4.4, 3.6 },

	--[[
		And sometimes he just stops.

		A boss on a metronome is a boss you can count. The long breather also
		does something for the fight that no attack can: it is the only time the
		player gets to look at the arena, deal with the slimes he has shed and
		decide what to do next, rather than reacting. `chance` of the rests are
		this much longer again.
	]]
	breatherChance = 0.25,
	breatherExtra = 2.6,

	-- Added to the rest after Coronation, whatever the phase. The centrepiece
	-- gets a beat of silence after it rather than the next tell on top of it.
	afterCoronation = 1.4,

	--[[
		HOW HE MOVES: he hops, like the slime he is.

		Not a slide. He was oozing across the floor at a constant speed, which
		is the one movement a giant blob should never make - it read as a model
		being dragged rather than a creature travelling. Now he squashes, throws
		himself, stretches in the air and splats on landing, which is the same
		vocabulary every attack in the fight is built from.

		The timings multiply out to about ten studs a second, which is what the
		constant slide was doing - slower than a walking player on purpose, so
		distance is always available and the fight is about what you do with it.
	]]
	hop = {
		crouch = 0.26,
		air = 0.5,
		land = 0.32,
		pause = 0.35,
		stride = 15,

		--[[
			HOW HIGH, AS A MULTIPLE OF HIS OWN HEIGHT.

			It was a flat nine studs, which is a reasonable hop for a rabbit and
			a shuffle for something the size of a house - he barely cleared his
			own bottom third. Measured against `entry.height` it is right at any
			size the artist builds him, and it stays right as his mass changes
			over the fight.

			This is the CONTROL point of the arc, not the apex. A quadratic
			bezier only reaches half its control height, so the number he
			actually clears is half of this: 2.4 gives a peak of about one and a
			fifth times his own height, which is what a heavy thing throwing
			itself looks like.
		]]
		--[[
			HOW HIGH, as a multiple of his own height.

			1.1 of control, so an actual apex of about 0.55 of his own height -
			a quadratic bezier only reaches half its control point. That is a
			slime bouncing. It was 2.4 and he was launching himself clean over
			his own head, which read as a superball rather than as something
			heavy.
		]]
		lift = 1.1,
		minLift = 7,

		--[[
			HOW FAST HE TURNS, in degrees per second, applied every frame -
			on the ground and in the air alike.

			It was a cap of 55 degrees applied ONCE per hop, which had a bug in
			it: if his heading was badly off, one hop only corrected 55 degrees
			of it and he spent the rest of that hop travelling the wrong way.
			Two of those in a row and he had visibly hopped away from you.

			A continuous rate has no such failure mode. He is always coming
			round, he simply cannot do it instantly - which is the difference
			between a heavy thing turning and a turret snapping.
		]]
		turnRate = 110,

		--[[
			SIDEWAYS, when somebody is already on top of him.

			Between these two angles off the line to the player, left or right.
			Never a free choice of bearing: the old version rolled anywhere
			within 126 degrees, which includes "directly away", and that is
			exactly what it looked like. At most a hundred there is barely any
			backward component at all - he circles you, he does not flee.
		]]
		idleStride = 0.5,
		sideMin = 60,
		sideMax = 100,
	},

	standoff = 13,

	--[[
		MASS - the economy the whole fight runs on.

		`rest` is where he starts. Attacks that throw part of him away subtract;
		reabsorbing adds back. The floor is not zero because a boss the size of
		a football is not a boss, and the ceiling stops a player who ignores the
		adds entirely from facing something that fills the arena.

		`healPerAbsorb` is why killing the adds matters: he does not merely get
		his size back, he gets HEALTH back, and it is a real fraction of a
		fight's worth of swings.
	]]
	mass = {
		rest = 1,
		min = 0.55,
		max = 1.25,
		-- Rain is charged once for the throw and then again PER handful that
		-- lands alive: a slime that gets up and walks off really is a piece of
		-- him that left. Small, because it is charged several times at once.
		perRain = 0.05,
		perSlime = 0.05,
		perAbsorb = 0.13,
		-- Four per cent of his health, which is about two seconds of swinging
		-- at him. Enough that letting him do it four times over costs a
		-- noticeable stretch of the fight, and not so much that one missed
		-- slime undoes a phase. It is a FRACTION of his health, not an
		-- absolute; retune it with EnemyConfig.
		healPerAbsorb = 60,
		-- A decree blob is a piece of him torn off to stand in for a subject
		-- he does not have. It costs nearly as much as a shed slime and gives
		-- nothing back: that is the price of having let the room be emptied.
		perDecreeBlob = 0.04,
		--[[
			THE GROUND, per block swallowed, and the ceiling per cast.

			A full three-vein bite into solid ground is about thirty blocks,
			so the cap sits right where a full bite lands: a complete claim is
			worth a little less than one reabsorb (0.13), a half bite into
			mined-out ground is worth half that, and a bite into nothing is
			worth nothing and still hurt. It can never heal him. That is the
			whole difference between the world and his children as a resource.
		]]
		perClaimBlock = 0.004,
		claimCap = 0.12,
	},

	--[[
		Standing INSIDE him.

		The radius is HIS BODY, live - a pancake really does have a wider
		contact area than a column, because the contact area is the body. It is
		capped so there is always a ring you can reach him from without being
		in him: melee reach minus a stud of margin. Contact damage that
		swallowed melee range would not be a mechanic, it would be a tax on
		choosing a sword.
	]]
	contact = {
		damage = 9,
		interval = 1,
		margin = 3,
	},

	pancake = {
		rear = 0.75,       -- he draws himself up: the tell
		fall = 0.16,       -- and drops. The gap between these is the reaction.
		spread = 0.9,      -- how long he lies there as a puddle
		damage = 30,
	},

	--[[
		CLAIM THE REALM - he eats the floor.

		He plants, the crown leans toward you, and two or three veins of him
		spread along the ground to spots around where you are standing. The
		whole path of every vein and the bite at its end are drawn for
		`warning` seconds before anything happens; then the veins surge, the
		ends bite one or two blocks out of the ground, and the ground is
		pulled back through the veins and swallowed. He swells by what he ate.

		Why it exists: it is the one attack a slime king could only have in a
		game where the ground is made of blocks, and it makes the world a
		second source of mass - a player who kills every slime still faces a
		boss who can grow, and a player who watches the floor knows where he
		is about to grow from.

		Dodge: do not stand on a vein when it surges, do not stand at its end
		when it bites. Every vein is drawn full length before it moves.
	]]
	claim = {
		settle = 0.55,       -- he plants and the crown leans: the first tell
		warning = 1.35,      -- veins drawn to full length, ends ringed
		surge = 0.4,         -- the veins thicken and run; crossing one hurts
		swallow = 0.9,       -- the ground flies back along them and goes in
		veins = { 2, 3, 3 }, -- by phase
		reach = 58,          -- furthest a vein end may be from him
		ringRadius = 9,      -- vein ends sit this far from the target, around them
		width = 5,           -- how wide a vein is, which is what it hits
		biteRadius = 6,      -- the eruption and the bite footprint at a vein end
		veinDamage = 14,
		biteDamage = 16,
		-- A player who crosses two veins and stands in a bite is clipped
		-- once or twice, not three times. Per player, per cast.
		capPerCast = 24,
	},

	absorb = {
		windup = 0.9,
		reach = 70,
		pull = 0.7,
		-- How thick the rope of slime between him and his child is, at rest.
		-- It grows while it reels in; see the note in the function.
		tether = 2.2,
	},

	coronation = {
		flatten = 0.6,
		rise = 1.1,        -- crown up
		hang = 0.35,
		fall = 1.1,        -- crown down: the whole of the reaction window
		height = 60,
		radius = 17,
		damage = 34,
		flowSpeed = 26,
	},

	--[[
		SLIME RAIN, which is also how he reproduces.

		It used to rain damage and leave puddles, and a separate DIVIDE attack
		tore slimes off him. Divide was the weaker of the two - a windup and
		then some slimes, which is every summon in every game - so it is gone
		and this took over its job: the handfuls he throws LAND AS SLIMES.

		That merge is what makes it good. The attack you dodge and the attack
		that fills the room are the same attack, the mass leaves his body in
		front of you, and Reabsorb now has something to reach for without a
		second move existing purely to provide it.

		`becomeSlime` of them turn into a creature; the rest are just weight.
		Not all, because a wall of eight slimes is a different fight, and
		because a blob that lands and stays a blob is what tells the player the
		living ones were a choice.
	]]
	rain = {
		draw = 0.9,        -- he hauls himself up into a column
		drops = { 3, 5, 7 },
		becomeSlime = { 1, 2, 3 },
		spacing = 0.24,
		flight = 0.85,
		radius = 6,
		damage = 16,
		spread = 46,
		maxAdds = 7,
		lingerSeconds = 3,
		lingerDamage = 6,
		lingerInterval = 0.9,
	},

	--[[
		ROYAL DECREE - the crown commands.

		He rises tall and the crown lifts and burns. Up to `subjects` of his
		surviving slimes are linked to it by gold tethers and ringed, and each
		is given a lane - drawn full length toward a player - for `warning`
		seconds. On the command every linked slime still alive flattens into
		a surge, runs its lane, and stands back up at the end, where it stays
		and can later be reabsorbed.

		KILL A LINKED SLIME AND ITS LANE IS GONE. That is the point: the
		slimes were already a reason to clear the room before Reabsorb; now
		they are a reason in the other direction too, and a slime with a ring
		over it is a target the player has been handed.

		With no subjects alive he tears `fallbackBlobs` small blobs off
		himself at a mass cost and sends those instead: shorter lanes, less
		damage, and they dissolve afterwards rather than becoming slimes. It
		is visibly the lesser version, so having cleared the room still paid.
	]]
	decree = {
		rise = 0.7,
		warning = 1.5,
		surge = 0.55,
		reform = 0.35,
		subjects = 3,
		reach = 70,          -- how far away a subject may be
		laneMin = 14,
		laneMax = 46,
		overshoot = 8,       -- a lane runs this far past where you were
		width = 5,
		damage = 16,
		fallbackBlobs = { 0, 1, 2 }, -- by phase; it is not in the phase-one deck
		fallbackLane = 24,
		fallbackDamage = 9,
		-- Two lanes converging on one player are one and a half hits, not
		-- two. Per player, per cast. Lanes are also dealt round the room,
		-- so three lanes only all point at one person when there is one.
		capPerCast = 24,
	},

	--[[
		THE MOMENT A PHASE CHANGES.

		The fight had phases you could measure and not feel: the deck quietly
		got bigger and the gaps quietly got shorter, and nothing ever said so.
		A boss that changes without announcing it is a boss whose difficulty
		looks like variance.

		So he convulses. It costs nothing to dodge - it does no damage at all -
		and that is the point: it is a beat of pure theatre in the one place the
		fight most needs the player to notice something.
	]]
	shift = {
		swell = 0.55,
		burst = 0.35,
		sheds = { 0, 2, 3 },   -- slimes thrown out by the change itself
		throw = 24,
	},

	--[[
		DYING.

		He does not fall over, because he has nothing to fall over with. He
		loses cohesion: the crown drops, he spreads out across the floor, and
		what is left of him sinks and goes.
	]]
	death = {
		shudder = 0.5,
		collapse = 0.9,
		sink = 1.1,
	},

	-- Health fractions the phases change at.
	phaseAt = { 0.65, 0.3 },
}

local TELEGRAPH_HEIGHT = 0.2
local TELEGRAPH_TRANSPARENCY = 0.45

-- The outline under a growing mark. Faint enough to read as "this is where it
-- ENDS" rather than as a second attack landing at the same time.
local TELEGRAPH_EDGE_TRANSPARENCY = 0.82

-- Blobs in one impact wave. Ten is enough to read as a ring from above and
-- from a player's own eye level; more is a wall.
local RIPPLE_BLOBS = 10

-- How far apart stacked ground markers sit. Flat discs at the same height are
-- coplanar and flicker; this is the smallest gap that reliably stops it while
-- still reading as one mark on the floor.
local DISC_STACK = 0.06

--[[
	How close he is allowed to make his contact hitbox.

	Derived from the weapon range rather than written down, so the promise -
	"there is always somewhere you can stand and hit him from" - survives
	somebody retuning weapons.
]]
local CONTACT_CAP = WeaponConfig.DefaultRange - Tuning.contact.margin

-- ---------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------

local function livingPlayers(): { Player }
	local list = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if humanoid and root and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end

	return list
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

--[[
	The nearest living player, and how far away they are.

	Nearest rather than "whoever hit him last": a boss that chases its damage
	dealer walks away from everyone else, and in a fight this long that is how
	one player ends up doing all of it while the others watch.
]]
local function nearestPlayer(position: Vector3): (Player?, number)
	local best, bestDistance = nil, math.huge

	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end

	return best, bestDistance
end

--[[
	Hurts everyone standing inside a circle on the ground.

	Flat, not spherical: height is not part of any of these attacks, and testing
	it in three dimensions would make a pancake miss somebody standing on a rock
	inside it, which is not a dodge anybody could have understood.
]]
local function damageCircle(centre: Vector3, radius: number, amount: number)
	local squared = radius * radius

	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root then
			local offset = root.Position - centre
			local flat = Vector3.new(offset.X, 0, offset.Z)

			if flat:Dot(flat) <= squared then
				CombatService.applyDamage(player, amount, SOURCE)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Slime on the ground
-- ---------------------------------------------------------------------------

local function newPart(size: Vector3, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- A tapered ribbon makes direction and speed readable without spawning
-- physics debris every frame. Attachments die with their projectile.
local function projectileTrail(part: Part, color: Color3, width: number)
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(-width * 0.5, 0, 0)
	a.Parent = part
	local b = Instance.new("Attachment")
	b.Position = Vector3.new(width * 0.5, 0, 0)
	b.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a
	trail.Attachment1 = b
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Lifetime = 0.22
	trail.FaceCamera = true
	trail.LightEmission = 0.4
	trail.Parent = part
end

--[[
	A disc laid flat on the ground.

	A Cylinder's length runs along its X axis, so it has to be turned on its
	side to be a disc at all - the single most commonly missed thing about using
	one as a ground marker.
]]
local function newDisc(centre: Vector3, radius: number, color: Color3, transparency: number): Part
	local disc = newPart(Vector3.one, color, transparency)
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(TELEGRAPH_HEIGHT, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = workspace
	return disc
end

--[[
	A mark that fills up over `seconds` and then goes.

	It GROWS rather than appearing at full size and changing colour, because
	size is readable in peripheral vision and colour is not - and the player is
	looking at him, not at their feet.

	Under the growing fill there is a FAINT DISC AT THE FINAL SIZE, which the
	fill catches up to. The growth alone says "something is coming and it is
	getting closer"; it does not say where the edge will be until the moment it
	arrives there, which is exactly too late to walk out of it. With the outline
	the player can pick their spot at the start of the tell and then watch the
	boss instead of their feet, which is the whole difference between a fight
	that is hard and one that is unfair.
]]
local function telegraph(centre: Vector3, radius: number, seconds: number, color: Color3)
	local edge = newDisc(centre, radius, color, TELEGRAPH_EDGE_TRANSPARENCY)
	Debris:AddItem(edge, seconds + 0.3)

	-- A hair above the outline. Two discs of the same thickness at the same
	-- height are coplanar, and coplanar faces flicker against each other from
	-- every angle the player can look at them from.
	local disc = newDisc(centre + Vector3.new(0, DISC_STACK, 0), 0.5, color, TELEGRAPH_TRANSPARENCY)

	TweenService:Create(disc, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
		Size = Vector3.new(TELEGRAPH_HEIGHT, radius * 2, radius * 2),
	}):Play()

	-- Both fade out together, so the mark leaves as one thing rather than as a
	-- disc vanishing off a ring.
	local out = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(seconds, function()
		if disc.Parent then
			TweenService:Create(disc, out, { Transparency = 1 }):Play()
		end
		if edge.Parent then
			TweenService:Create(edge, out, { Transparency = 1 }):Play()
		end
	end)

	Debris:AddItem(disc, seconds + 0.3)
	return disc
end

--[[
	The wave of him that runs outward from an impact.

	Slime racing away along the floor, spreading and thinning as it goes and
	gone by the time it reaches the edge of what the impact actually hit. Two
	things at once, both of which the fight needed:

	  it is a HITBOX, drawn. The ring arrives at the rim at the same moment the
	  damage stops, so a player who was clipped can see how close they were and
	  a player who was not can see they read it right.

	  it is HIM. A shockwave ring would be the same effect any boss in any game
	  gets on a slam. Slime thrown outward and pulled flat is the same event
	  told in the material he is made of, and it costs no more.

	Deliberately cheap: a handful of anchored neon parts on one tween each,
	cleaned up by Debris. This fires on every heavy landing in the fight, and an
	effect that fires that often has to be something the server does not notice.
]]
local function ripple(centre: Vector3, radius: number, seconds: number, color: Color3)
	local out = TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local size = math.max(1.2, radius * 0.2)

	--[[
		Each one is a flat disc rather than a ball, and it matters.

		A Ball part does not scale per axis the way a block does, so a blob that
		was supposed to flatten as it travelled would just be a smaller sphere -
		and a ring of shrinking spheres reads as debris being thrown, not as a
		surface spreading. A disc lying on the floor is unambiguous about what
		it is doing, and newDisc already knows the one awkward thing about
		Cylinders: their length runs along X, so they have to be turned on their
		side to lie flat at all.
	]]
	local flat = CFrame.Angles(0, 0, math.rad(90))

	for index = 1, RIPPLE_BLOBS do
		local angle = (index / RIPPLE_BLOBS) * math.pi * 2 + math.random() * 0.35
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))

		local blob = newDisc(
			centre + direction * (radius * 0.2) + Vector3.new(0, TELEGRAPH_HEIGHT, 0),
			size * 0.45,
			color,
			0.3
		)

		-- Out and thinning. It arrives at the rim as the damage stops and is
		-- gone a fraction later, so what is left on the floor afterwards is the
		-- slicks an attack meant to leave and nothing else.
		TweenService:Create(blob, out, {
			CFrame = CFrame.new(centre + direction * radius + Vector3.new(0, TELEGRAPH_HEIGHT, 0))
				* flat,
			Size = Vector3.new(TELEGRAPH_HEIGHT, size * 1.6, size * 1.6),
			Transparency = 1,
		}):Play()

		Debris:AddItem(blob, seconds + 0.1)
	end
end

--[[
	Slime he left behind, which is still him and still hurts.

	Every one of these is on a timer measured in a few seconds. The arena gets
	messier during a phase and cleans itself up between attacks: a floor that
	filled permanently would end the fight by attrition rather than by either
	side winning it.
]]
local function slick(
	entry,
	centre: Vector3,
	radius: number,
	seconds: number,
	damage: number,
	interval: number
)
	-- Above the mark that announced it, not level with it: an attack that
	-- telegraphs a circle and then leaves a pool in the same circle would have
	-- the two flickering through each other for as long as both are up.
	local pool = newDisc(centre + Vector3.new(0, DISC_STACK * 2, 0), radius, Theme.Color.Good, 0.4)
	Debris:AddItem(pool, seconds)

	task.spawn(function()
		for _ = 1, math.floor(seconds / interval) do
			task.wait(interval)
			if entry.slimeFinished then
				pool:Destroy()
				return
			end
			if not pool.Parent then
				return
			end
			damageCircle(centre, radius, damage)
		end
	end)
end

-- Blobs of him thrown loose by an impact.
local function splatter(centre: Vector3, spread: number, count: number)
	for _ = 1, count do
		local chunk = newPart(Vector3.one * (0.5 + math.random() * 0.5), Theme.Color.Good, 0.15)
		chunk.Shape = Enum.PartType.Ball
		chunk.Material = Enum.Material.SmoothPlastic
		chunk.Anchored = false
		chunk.Massless = true
		chunk.CFrame = CFrame.new(centre + Vector3.new(
			(math.random() - 0.5) * spread, 1.5, (math.random() - 0.5) * spread
		))
		chunk.Parent = workspace
		chunk.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 32, math.random() * 22 + 8, (math.random() - 0.5) * 32
		)
		Debris:AddItem(chunk, 1.5)
	end
end

-- ---------------------------------------------------------------------------
-- Where he is
-- ---------------------------------------------------------------------------

--[[
	Turns `from` toward `to`, by at most `limit` degrees.

	The whole of "he does not swivel". A heavy thing changes direction slowly
	and in discrete decisions, not by continuously tracking whatever it is
	looking at - and a boss that snaps to face you every frame reads as a turret
	however good its animation is.

	Flattened first: he only ever turns on the ground plane, and a target above
	or below him must not tip him over.
]]
local function turnToward(from: Vector3, to: Vector3, limit: number): Vector3
	local a = Vector3.new(from.X, 0, from.Z)
	local b = Vector3.new(to.X, 0, to.Z)

	if b.Magnitude < 0.001 then
		return if a.Magnitude > 0.001 then a.Unit else Vector3.new(0, 0, 1)
	end

	if a.Magnitude < 0.001 then
		return b.Unit
	end

	a, b = a.Unit, b.Unit

	local dot = math.clamp(a:Dot(b), -1, 1)
	local angle = math.acos(dot)
	local cap = math.rad(limit)

	if angle <= cap then
		return b
	end

	--[[
		Rotate `a` by the cap, the short way round.

		THE SIGN HERE WAS INVERTED and it is worth saying exactly what that
		looked like, because it did not look like a rotation bug. Whenever the
		angle to the target exceeded the cap, this turned him AWAY from it by
		the cap instead of toward it - so the only way he ever came round was
		the long way, through 360 degrees. With a continuous turn and a moving
		player he could stay facing away indefinitely, which reads as "the model
		is backwards", not as "the maths is backwards".

		The formula below rotates by +angle in the XZ plane as
		(x cos - z sin, x sin + z cos). Against that convention a cross product
		Y of NEGATIVE means `b` is the +angle way round. The two have to be read
		together; either one alone is meaningless.
	]]
	local side = if a:Cross(b).Y >= 0 then -1 else 1
	local turn = cap * side
	local cos, sin = math.cos(turn), math.sin(turn)

	return Vector3.new(a.X * cos - a.Z * sin, 0, a.X * sin + a.Z * cos).Unit
end


local function feetOf(entry): Vector3
	return entry.model:GetPivot().Position - Vector3.new(0, entry.feetOffset, 0)
end

local function groundUnder(position: Vector3): Vector3
	return Vector3.new(
		position.X, EnemyService.groundAt(position.X, position.Z, position.Y), position.Z
	)
end

-- Every placement he makes goes through the service, so his orientation
-- correction and his feet are handled in one place for the whole game.
local function place(entry, ground: Vector3, facing: Vector3?)
	EnemyService.placeModel(entry, ground, facing)
end

--[[
	Turns him to face a direction over `seconds`, smoothly, in place.

	The attacks that AIM used to snap: `place(entry, from, direction)` on the
	first frame, then a long wind-up spent already pointing at you. That is a
	turret movement, and it undid the whole point of capping his turn rate
	between hops - he would sit perfectly still all fight and then rotate
	instantly the moment he decided to throw something.

	Turning while he gathers is also just better tell: the aim IS part of the
	wind-up, and watching him come round to face you is the earliest warning the
	attack gives.
]]
local function turnOver(entry, direction: Vector3, seconds: number)
	local from = entry.facing
	local start = os.clock()

	while os.clock() - start < seconds do
		if entry.slimeFinished then
			return
		end
		local alpha = (os.clock() - start) / seconds
		local eased = alpha * alpha * (3 - 2 * alpha)

		-- turnToward with a growing cap, so he eases round rather than
		-- rotating at a constant rate and stopping dead on arrival.
		EnemyService.placeModel(
			entry, feetOf(entry), turnToward(from, direction, 180 * eased)
		)

		task.wait()
	end

	EnemyService.placeModel(entry, feetOf(entry), direction)
end

-- ---------------------------------------------------------------------------
-- Mass
-- ---------------------------------------------------------------------------

--[[
	Spends or restores mass, and shows it.

	The flash is the feedback: white when he loses some, his own colour when he
	takes it back. Without it a division reads as "three slimes appeared" rather
	than as "he tore himself apart", which is the whole difference.
]]
local function spendMass(entry, amount: number)
	local M = Tuning.mass
	local body = entry.body

	body:setMass(math.clamp(body:getMass() - amount, M.min, M.max))
	body:flash(Color3.new(1, 1, 1), 0.12)
end

local function gainMass(entry, amount: number)
	local M = Tuning.mass
	local body = entry.body

	body:setMass(math.clamp(body:getMass() + amount, M.min, M.max))
	body:flash(Theme.Color.Accent, 0.2)
end

-- ---------------------------------------------------------------------------
-- Attack plumbing
-- ---------------------------------------------------------------------------

--[[
	Waits, unless he is finished.

	Returns false if the fight ended during the wait, so a caller stops in one
	line. Every wait inside an attack goes through this rather than task.wait,
	which is what makes "every coroutine stops when slimeFinished is set" a
	property of the file rather than a thing each attack remembers to check.
]]
local function pause(entry, seconds: number): boolean
	local deadline = os.clock() + seconds
	repeat
		if entry.slimeFinished then
			return false
		end
		task.wait()
	until os.clock() >= deadline
	return not entry.slimeFinished
end

--[[
	Who an aimed attack goes for.

	Not the nearest, and not whoever hit him last: the one he has gone for
	LEAST RECENTLY, with enough randomness that he is not a round robin you can
	count. In a group this spreads the pressure; alone it is simply you.
	Movement still chases the nearest player (see step), so where he aims and
	where he walks can differ, which is what a room full of people should feel
	like.

	`from` and `within` restrict it to players an attack can actually reach.
]]
local function pickTarget(entry, from: Vector3?, within: number?): Player?
	local now = os.clock()
	local best, bestScore = nil, -math.huge

	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)
		if root and not (from and within and (root.Position - from).Magnitude > within) then
			local since = math.min(20, now - (entry.pressure[player] or -math.huge))
			local score = since + math.random() * 6
			if score > bestScore then
				best, bestScore = player, score
			end
		end
	end

	if best then
		entry.pressure[best] = now
	end
	return best
end

--[[
	Damage with a memory.

	`ledger` is one cast's record of who it has hurt and for how much. Each
	`key` - a vein, a lane, a bite - hits a player once, and the whole cast
	never deals more than `cap` to anyone. Returns what was actually dealt.

	"Crossing a tendril damages once, not every frame" and "overlapping lanes
	have a sensible combined cap" are the same rule, so they are one function.
]]
local function hitOnce(ledger, key, player: Player, amount: number, cap: number): number
	local hits = ledger[player]
	if not hits then
		hits = { total = 0 }
		ledger[player] = hits
	end
	if hits[key] then
		return 0
	end
	hits[key] = true

	local dealt = math.min(amount, math.max(0, cap - hits.total))
	if dealt <= 0 then
		return 0
	end
	hits.total += dealt
	CombatService.applyDamage(player, dealt, SOURCE)
	return dealt
end

-- Is this position on the flat strip from `from` to `to`? Flat, like every
-- other hit test here: height is not part of any of these attacks.
local function onLane(position: Vector3, from: Vector3, to: Vector3, halfWidth: number): boolean
	local lane = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = lane.Magnitude
	if length < 0.01 then
		return false
	end
	local direction = lane / length
	local offset = Vector3.new(position.X - from.X, 0, position.Z - from.Z)
	local along = offset:Dot(direction)
	if along < -halfWidth or along > length + halfWidth then
		return false
	end
	local across = (offset - direction * along).Magnitude
	return across <= halfWidth
end

-- Where things he swallows go in.
local function mouthOf(entry): Vector3
	return feetOf(entry) + Vector3.new(0, entry.height * 0.45, 0)
end

--[[
	A rope of slime between two points, re-laid by the caller every frame.

	Reabsorb's whole readability and Decree's "these are his" are the same
	object in two colours: a part stretched between two points says "these are
	connected" in its first frame, and it is made of the same slime as
	everything else he throws.
]]
local function newTether(scope, color: Color3, thickness: number): Part
	local part = scope:add(newPart(Vector3.new(thickness, thickness, 1), color, 0.25))
	part.Parent = workspace
	return part
end

local function layTether(part: Part, from: Vector3, to: Vector3, thickness: number)
	if not part.Parent then
		return
	end
	local span = (to - from).Magnitude
	part.Size = Vector3.new(thickness, thickness, math.max(1, span))
	part.CFrame = CFrame.lookAt((from + to) * 0.5, to)
end

-- A ring hanging over something he has chosen. Repositioned by the caller.
local function newRing(scope, radius: number, color: Color3): Part
	local ring = scope:add(newPart(Vector3.one, color, 0.3))
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(TELEGRAPH_HEIGHT, radius * 2, radius * 2)
	ring.Parent = workspace
	return ring
end

local function layRing(ring: Part, over: Vector3)
	if ring.Parent then
		ring.CFrame = CFrame.new(over) * CFrame.Angles(0, 0, math.rad(90))
	end
end

--[[
	A LANE on the ground: a strip from `from` to `to`, drawn as a faint
	full-length outline at once and a brighter fill that runs its length over
	`seconds`. The same promise a disc telegraph makes, stretched: where it
	ENDS is visible from the first frame, and the fill is how long you have.

	Laid in short segments that each sit on their own ground height, so a lane
	across a slope follows the slope rather than knifing through it. Everything
	goes into `scope`. `surge` thickens it into the vein or running slime it
	announced; `fade` takes it away.
]]
local LANE_SEGMENT = 9

local function laneTelegraph(scope, from: Vector3, to: Vector3, width: number, seconds: number, color: Color3)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = flat.Magnitude
	if length < 1 then
		return nil
	end
	local direction = flat / length
	local count = math.max(1, math.ceil(length / LANE_SEGMENT))
	local step = length / count
	local each = seconds / count
	local up = Vector3.new(0, TELEGRAPH_HEIGHT * 0.5, 0)

	local lane = { from = from, to = to, width = width, edges = {}, fills = {} }

	for index = 1, count do
		local a = from + direction * (step * (index - 1))
		local b = from + direction * (step * index)
		local middle = groundUnder((a + b) * 0.5)
		-- lookAt points the part's -Z at the far end, so "toward `to`" is
		-- negative Z in the part's own frame below.
		local look = CFrame.lookAt(middle + up, middle + up + direction)

		local edge = scope:add(newPart(Vector3.new(width, TELEGRAPH_HEIGHT, step), color, TELEGRAPH_EDGE_TRANSPARENCY))
		edge.CFrame = look
		edge.Parent = workspace
		lane.edges[index] = edge

		-- The fill starts as nothing at the NEAR end of its segment and grows
		-- to cover it, each segment in turn, so the lane fills from `from`
		-- toward `to` over `seconds`.
		local fill = scope:add(newPart(Vector3.new(width, TELEGRAPH_HEIGHT, 0.05), color, TELEGRAPH_TRANSPARENCY))
		fill.CFrame = look * CFrame.new(0, DISC_STACK, step * 0.5)
		fill.Parent = workspace
		lane.fills[index] = fill

		scope:delay(each * (index - 1), function()
			scope:tween(fill, TweenInfo.new(each, Enum.EasingStyle.Linear), {
				Size = Vector3.new(width, TELEGRAPH_HEIGHT, step),
				CFrame = look * CFrame.new(0, DISC_STACK, 0),
			})
		end)
	end

	-- The announced thing arriving: the fill rises into a solid strip.
	function lane:surge(height: number, transparency: number, over: number)
		for _, fill in ipairs(self.fills) do
			if fill.Parent then
				scope:tween(fill, TweenInfo.new(over, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = Vector3.new(self.width, height, step),
					CFrame = fill.CFrame * CFrame.new(0, (height - TELEGRAPH_HEIGHT) * 0.5, 0),
					Transparency = transparency,
				})
			end
		end
	end

	-- Gone, over `over` seconds. The parts are destroyed at the end of the
	-- fade and again by the scope, whichever comes first.
	function lane:fade(over: number)
		local out = TweenInfo.new(over, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, list in ipairs({ self.edges, self.fills }) do
			for _, part in ipairs(list) do
				if part.Parent then
					scope:tween(part, out, { Transparency = 1 })
				end
			end
		end
		scope:delay(over, function()
			for _, list in ipairs({ self.edges, self.fills }) do
				for _, part in ipairs(list) do
					part:Destroy()
				end
			end
		end)
	end

	return lane
end

--[[
	Tells nearby clients which blocks the server just took, so they can draw
	copies being swallowed.

	After the fact and only what really went: `blocks` is the sample
	TerrainManager.ExecuteExcavation returned, never something this file made
	up, and a client that ignores the message is simply a client that did not
	see some cubes fly. See TerrainDebris for the other half.
]]
local function broadcastDebris(mouth: Vector3, blocks, seconds: number)
	if #blocks == 0 then
		return
	end

	local payload = {
		blocks = blocks,
		centre = mouth,
		startedAt = workspace:GetServerTimeNow(),
		seconds = seconds,
	}

	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and (root.Position - mouth).Magnitude <= DEBRIS_BROADCAST_RADIUS then
			BossTerrain:FireClient(player, payload)
		end
	end
end

-- ---------------------------------------------------------------------------
-- The attacks
-- ---------------------------------------------------------------------------

--[[
	PANCAKE

	He draws himself up tall, loses cohesion, and spreads across the floor. The
	damage area is HIS BODY - measured off the part after it has spread - so the
	thing you are dodging is the shape you can see, not a circle drawn under it.

	Then he stays a puddle for a moment, flows somewhere else along the ground,
	and stands back up. That relocation is the second half of the attack: melee
	players who were on him are now not.

	Dodge: the rear-up is three quarters of a second of him standing tall and
	thin, and the mark shows exactly how far he will reach. Walk out.
]]
local function pancake(entry)
	local P = Tuning.pancake
	local body = entry.body
	local here = feetOf(entry)

	-- How wide he will be once flat, worked out from the shape he is about to
	-- take rather than guessed: this is the promise the mark makes.
	local reach = body:radius() * (SlimeBody.Pancake.width / math.max(body.width, 0.05))

	telegraph(here, reach, P.rear, Theme.Color.Bad)

	body:ease(SlimeBody.Column.width, SlimeBody.Column.height, P.rear)
	if not pause(entry, P.rear) then
		return
	end

	body:ease(SlimeBody.Pancake.width, SlimeBody.Pancake.height, P.fall)
	if not pause(entry, P.fall) then
		return
	end

	damageCircle(here, body:radius(), P.damage)

	-- The wave runs to `reach`, which is the width he is about to BE and not
	-- the width he is - the same number the mark promised at the start of the
	-- rear-up. Everything about this attack agrees on one radius.
	ripple(here, reach, 0.5, Theme.Color.Bad)
	splatter(here, reach, 14)
	body:wobble(0.4, 0.35)

	--[[
		HE STAYS WHERE HE LANDED.

		There used to be a relocation here: he held the pancake for a beat and
		then FLOWED to a new spot before standing up. It looked wrong for a
		reason that has nothing to do with how fast it was - he was travelling
		along the ground without hopping, and by this point in the fight
		hopping is the only way the player has ever seen him move. A slide is
		not a slower hop, it is a different creature.

		The attack loses nothing. The interesting part was always the rear-up
		and the flatten; the move afterwards was a second idea bolted to the
		end of a finished one.
	]]
	if not pause(entry, P.spread) then
		return
	end

	--[[
		HE LEAVES NOTHING BEHIND.

		There used to be a slick here - a wide pale disc dropped at the spot he
		had just flowed away from. It was the worst-looking thing in the fight:
		by the time it appeared he was somewhere else, so it read as an
		unexplained circle rather than as a mark he had made, and it outlived
		the attack, so the boss bar had already cleared the name and it looked
		like a move of its own that nobody had announced.

		The rule it broke is worth keeping: a hazard has to be attached to the
		thing that made it, in time and in space. Rain drops still leave
		slicks and that is fine, because they land where you watched them land
		and while the attack is still happening.
	]]

	body:ease(1, 1, 0.35)
	task.wait(0.35)
	body:wobble(0.5, 0.28)
end

--[[
	CLAIM THE REALM

	He settles low and plants himself; the crown leans toward you and burns.
	Two or three veins of him spread along the floor to spots around where you
	were standing when he committed, drawn full length with their bites ringed
	at the ends. Then they surge, the ends bite the ground, the bitten blocks
	fly back along the veins into him, and he swells by what he ate. The veins
	drain away and he sits back up.

	THE GROUND IS CHOSEN BEFORE THE WARNING. The exact cells each bite will
	take are resolved by TerrainManager.PlanExcavation at the moment he
	commits, so the mark on the floor is a promise about THOSE cells; nothing
	re-aims after you have read it. Execution re-checks every cell - the world
	is allowed to have changed in the meantime - and removes nothing the plan
	did not name.

	WHAT HE WILL NOT EAT: placed blocks, structures, cave walls, bedrock, wet
	ground, ground that is not loaded, and the ground under his own feet.
	The first six rules live in TerrainManager and are not this file's to
	get wrong. The last is here: no vein ends inside his own footprint, so he
	cannot dig the floor out from under himself - and he re-reads his footing
	afterwards regardless, because the ground is the ground as it now is.

	NO LOOT, NO HEALING. The ground is mass only, capped per cast; health is
	Reabsorb's alone. A bite into nothing earns nothing and still hurts.

	Dodge: step off a vein before it surges; step out of a ring before it
	bites. Both are drawn for well over a second.
]]
local function claimRealm(entry, phase: number)
	local C = Tuning.claim
	local M = Tuning.mass
	local body = entry.body
	local scope = entry.scope

	local here = feetOf(entry)
	local target = pickTarget(entry, here, C.reach + 40) or nearestPlayer(here)
	local root = target and rootOf(target)
	if not root then
		return
	end

	-- WHERE THE VEINS END, frozen now: a ring of spots around where you are,
	-- pulled in to his reach if you are further than that.
	local aim = root.Position
	local toAim = Vector3.new(aim.X - here.X, 0, aim.Z - here.Z)
	if toAim.Magnitude > C.reach then
		aim = here + toAim.Unit * C.reach
	end
	local facing = if toAim.Magnitude > 1 then toAim.Unit else entry.facing

	local veinCount = C.veins[phase] or 2
	local ends = {}
	local base = math.random() * math.pi * 2
	local ownFootprint = body:radius() + C.biteRadius + 2
	for index = 1, veinCount do
		local angle = base + (index - 1) / veinCount * math.pi * 2
		local spot = aim + Vector3.new(math.cos(angle), 0, math.sin(angle)) * C.ringRadius

		-- Never within his own footprint; see above.
		local fromHim = Vector3.new(spot.X - here.X, 0, spot.Z - here.Z)
		if fromHim.Magnitude < ownFootprint then
			local outward = if fromHim.Magnitude > 0.1 then fromHim.Unit else facing
			spot = here + outward * ownFootprint
		end
		ends[index] = groundUnder(spot)
	end

	-- THE CELLS, frozen now. The centre column of each bite goes two blocks
	-- down and its ring one: shallow and readable, a trench not a crater,
	-- and the floor stays walkable. The caps are TerrainManager's.
	local columns = {}
	for _, spot in ipairs(ends) do
		for dx = -1, 1 do
			for dz = -1, 1 do
				table.insert(columns, {
					x = spot.X + dx * STUD_SIZE,
					z = spot.Z + dz * STUD_SIZE,
					y = spot.Y,
					depth = if dx == 0 and dz == 0 then 2 else 1,
				})
			end
		end
	end
	local plan = TerrainManager:PlanExcavation(columns)

	-- SETTLE: low and wide, planted, coming round to face you. The crown
	-- leans toward the ground he has chosen and starts to burn. The pose is
	-- in the scope, so it is cleared however this ends.
	scope:add(function()
		body:setCrownPose(nil, nil)
		body:setCrownGlow(false)
	end)
	body:ease(1.35, 0.62, C.settle)
	body:setCrownGlow(true, Theme.Color.Accent)
	body:setCrownPose(0.6, CFrame.Angles(math.rad(22), 0, 0))
	turnOver(entry, facing, C.settle)
	if entry.slimeFinished then
		return
	end

	-- THE WARNING: every vein drawn full length from his feet, every bite
	-- ringed, nothing moving yet.
	-- `lanes` is keyed by vein index and may have holes: a vein end that
	-- somehow sits on top of him has no lane to draw and nothing to hit with,
	-- so everything below walks it with pairs.
	local origin = feetOf(entry)
	local lanes = {}
	for index, spot in ipairs(ends) do
		lanes[index] = laneTelegraph(scope, origin, spot, C.width, C.warning, Theme.Color.Bad)
		telegraph(spot, C.biteRadius, C.warning, Theme.Color.Bad)
	end
	if not pause(entry, C.warning) then
		return
	end

	-- THE SURGE: the veins thicken into running slime. Standing on one is a
	-- hit, once per vein, under the cast's cap.
	local ledger = {}
	for _, lane in pairs(lanes) do
		lane:surge(1.1, 0.1, C.surge * 0.5)
	end
	body:flash(Theme.Color.Good, C.surge)

	local surgeStart = os.clock()
	while os.clock() - surgeStart < C.surge do
		if entry.slimeFinished then
			return
		end
		for _, player in ipairs(livingPlayers()) do
			local victim = rootOf(player)
			if victim then
				for index, lane in pairs(lanes) do
					if onLane(victim.Position, lane.from, lane.to, C.width * 0.5) then
						hitOnce(ledger, "vein" .. index, player, C.veinDamage, C.capPerCast)
					end
				end
			end
		end
		task.wait()
	end
	if entry.slimeFinished then
		return
	end

	-- THE BITE: every end erupts, and the ground under it goes.
	for index, spot in ipairs(ends) do
		for _, player in ipairs(livingPlayers()) do
			local victim = rootOf(player)
			if victim then
				local offset = victim.Position - spot
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= C.biteRadius then
					hitOnce(ledger, "bite" .. index, player, C.biteDamage, C.capPerCast)
				end
			end
		end
		ripple(spot, C.biteRadius, 0.4, Theme.Color.Good)
		splatter(spot, C.biteRadius, 6)
	end

	local removed, samples = TerrainManager:ExecuteExcavation(plan)

	-- His footing first, on the ground as it now is: the next thing he does
	-- starts from the real floor, whatever just happened to it.
	place(entry, groundUnder(feetOf(entry)))

	local mouth = mouthOf(entry)
	broadcastDebris(mouth, samples, C.swallow)

	-- The veins drain back toward him while the ground flies in along them.
	for _, lane in pairs(lanes) do
		lane:fade(C.swallow)
	end
	if not pause(entry, C.swallow) then
		return
	end

	-- AND HE EATS IT. Mass only, capped, scaled by what actually went.
	local gained = math.min(M.claimCap, removed * M.perClaimBlock)
	if gained > 0 then
		gainMass(entry, gained)
		body:shape(1.2, 1.16)
		body:wobble(0.6, 0.35)
		splatter(mouth, entry.height * 0.6, 10)
	else
		body:ease(1, 1, 0.3)
	end

	body:setCrownPose(nil, nil)
	body:setCrownGlow(false)
	if not pause(entry, 0.35) then
		return
	end
	body:ease(1, 1, 0.3)
end

--[[
	REABSORB

	He drags one of his surviving children back and takes it into himself. He
	swells, and he HEALS.

	THIS IS THE STRATEGIC LAYER OF THE FIGHT. Everything else can be beaten by
	dodging well; this can only be beaten by having killed the slimes - or by
	killing THIS one, now. It is the only thing in the fight that undoes damage
	the player has already done, which is what makes ignoring the adds a
	decision rather than an oversight.

	IT CAN BE INTERRUPTED, AND THAT IS THE POINT. He gains nothing until the
	slime physically arrives at his mouth. Kill it on the rope - during the
	reach or during the pull - and the rope snaps, he sits back up, and there
	is no mass and no heal. The tether is drawn precisely so a player can see
	which slime to hit; the second of reaching is the window to hit it in.

	It is deliberately slow and loud so that both answers - "kill them next
	time" and "kill that one now" - are legible.
]]
local function reabsorb(entry)
	local A = Tuning.absorb
	local body = entry.body
	local scope = entry.scope
	local centre = feetOf(entry)

	-- The nearest FREE child: never one Royal Decree is commanding. Nil is
	-- the good outcome for the player and simply ends the attack.
	local prey, preyDistance = nil, math.huge

	EnemyService.forEachNear(centre, A.reach, function(model, position)
		if model.Name == SPAWN_NAME and EnemyService.heldBy(model) == nil then
			local distance = (position - centre).Magnitude
			if distance < preyDistance then
				prey, preyDistance = model, distance
			end
		end
	end)

	if not prey then
		return
	end

	--[[
		HELD for the whole reach. Its own brain is off while he has it - it
		cannot hop away, and Decree cannot take it - and the grip goes dead
		the instant it dies, which is the interruption below. Released by the
		scope whatever happens, so an error cannot leave a slime frozen.
	]]
	local grip = EnemyService.hold(prey, entry)
	if not grip then
		return
	end
	scope:add(function()
		grip:release()
	end)

	local mouth = mouthOf(entry)

	--[[
		THE TETHER IS THE WHOLE READABILITY OF THIS ATTACK.

		A visible rope of slime between the two says "these are connected,
		that one is going into this one" in the first frame - and it thickens
		as the slime gets closer, so the moment of arrival is the moment it is
		thickest. It is also the thing that tells a player which slime to hit.
	]]
	local tether = newTether(scope, Theme.Color.Accent, A.tether)

	-- A mark on HIM, not a disc the width of the arena: the tether says what
	-- is being pulled; this only says where he is while he pulls.
	telegraph(centre, math.max(10, body:radius() * 1.6), A.windup, Theme.Color.Accent)

	-- Reaching: he opens out toward it, and the rope goes taut.
	body:ease(1.15, 0.9, A.windup)

	--[[
		THE INTERRUPTION. If the slime on the rope is no longer his - dead,
		despawned - at any moment before it arrives, the rope snaps, he
		flinches back to his resting shape, and this returns having given him
		NOTHING. The grip is the single source of truth for "still his".
	]]
	local function interrupted(): boolean
		if entry.slimeFinished then
			return true
		end
		if grip:alive() then
			return false
		end
		tether:Destroy()
		body:ease(1, 1, 0.3)
		body:flash(Color3.new(1, 1, 1), 0.15)
		body:wobble(0.45, 0.25)
		return true
	end

	local reach = os.clock()
	while os.clock() - reach < A.windup do
		if interrupted() then
			return
		end
		local alpha = (os.clock() - reach) / A.windup
		layTether(tether, mouth, grip:feet() + Vector3.new(0, grip.height * 0.5, 0), A.tether * (0.35 + alpha * 0.65))
		task.wait()
	end
	if interrupted() then
		return
	end

	local from = prey:GetPivot().Position
	local preyScale = prey:GetScale()
	local start = os.clock()

	while os.clock() - start < A.pull do
		if interrupted() then
			return
		end

		local alpha = (os.clock() - start) / A.pull
		local at = from:Lerp(mouth, alpha)

		-- Through the air, straight at his mouth. The hold keeps its own
		-- hopping off, so this is the only thing moving it.
		prey:PivotTo(CFrame.new(at))

		-- It shrinks as it goes in: the slime is not being teleported, it is
		-- being consumed. By the time it reaches him it is a third of its
		-- size and the swallow is over.
		prey:ScaleTo(preyScale * (1 - alpha * 0.7))

		-- Thickening, and shortening on its own as the two ends converge.
		layTether(tether, mouth, at, A.tether * (1 + alpha * 1.4))
		task.wait()
	end

	-- ARRIVED. Only now, and only because it is still his.
	if interrupted() then
		return
	end

	tether:Destroy()

	-- Through the service, so its own bookkeeping - the alive count, the
	-- name plate - happens exactly as for a kill, without the drop table:
	-- "absorbed" is not "died".
	EnemyService.despawn(prey)

	--[[
		And he visibly takes it in: a hard swell, a flash of his own colour
		and a burst of slime at the mouth, all on the same frame. The swell
		overshoots and settles rather than easing to the new size, because a
		body absorbing something bulges and then recovers. It is the clearest
		signal in the fight that the player just lost something.
	]]
	gainMass(entry, Tuning.mass.perAbsorb)
	EnemyService.heal(entry.model, Tuning.mass.healPerAbsorb)

	body:shape(1.3, 1.22)
	body:wobble(0.9, 0.5)

	splatter(mouth, entry.height * 0.8, 22)
end

--[[
	CORONATION

	He flattens completely, fires the crown straight up out of himself, flows
	across the floor to wherever it is going to come down, and erupts around it
	as it lands - re-forming with the crown back on his head.

	THE CROWN IS THE TELEGRAPH. Its shadow shrinks toward the ground for over a
	second, and the player can read the whole attack off one object: where he is
	going, and when he gets there. The puddle flowing under it is the second
	tell, and it is him, moving, in plain sight.

	This is the crown attack because it is the only one where the crown does
	something a crown can do to a body that can reshape itself around it.
]]
local function coronation(entry)
	local C = Tuning.coronation
	local body = entry.body

	local restore = body:detachCrown()
	if not restore then
		return
	end

	-- In the scope as well as called below: if he dies with the crown in the
	-- air, the scope is torn down and the crown is back on his head before
	-- the corpse is drawn. Calling it twice is harmless.
	entry.scope:add(restore)

	local ok = pcall(function()
		local from = feetOf(entry)

		body:ease(SlimeBody.Pancake.width, SlimeBody.Pancake.height, C.flatten)
		if not pause(entry, C.flatten) then
			return
		end

		-- Where it will come down: near a player, but not on them - they are
		-- given a place to run to rather than a coin flip.
		local target = nearestPlayer(from)
		local landing = from

		if target then
			local root = rootOf(target)
			if root then
				local angle = math.random() * math.pi * 2
				landing = groundUnder(root.Position + Vector3.new(
					math.cos(angle), 0, math.sin(angle)
				) * (C.radius * 0.7))
			end
		end

		local apex = landing + Vector3.new(0, C.height, 0)
		local crownStart = from + Vector3.new(0, entry.height, 0)

		-- The crown draws its own line through the air. It is the only thing in
		-- the fight that is not made of slime, so it is the only thing allowed
		-- to look like metal.
		body:setCrownTrail(true)

		local rise = os.clock()
		while os.clock() - rise < C.rise do
			if entry.slimeFinished then
				return
			end
			local alpha = (os.clock() - rise) / C.rise
			body:moveCrown(CFrame.new(crownStart:Lerp(apex, alpha))
				* CFrame.Angles(0, alpha * 12, 0))
			task.wait()
		end

		if not pause(entry, C.hang) then
			return
		end

		-- The shadow: a mark that CLOSES as the crown falls, so the countdown
		-- and the danger zone are the same object.
		local shadow = newDisc(landing, C.radius, Theme.Color.Bad, TELEGRAPH_TRANSPARENCY)
		TweenService:Create(shadow, TweenInfo.new(C.fall, Enum.EasingStyle.Linear), {
			Size = Vector3.new(TELEGRAPH_HEIGHT, C.radius * 0.5, C.radius * 0.5),
		}):Play()
		Debris:AddItem(shadow, C.fall + 0.2)

		-- He flows under it while it comes down. Flat the whole way.
		local flowFrom = feetOf(entry)
		local fall = os.clock()

		while os.clock() - fall < C.fall do
			if entry.slimeFinished then
				return
			end
			local alpha = (os.clock() - fall) / C.fall

			body:moveCrown(CFrame.new(apex:Lerp(landing + Vector3.new(0, 2, 0), alpha * alpha))
				* CFrame.Angles(0, alpha * 20, 0))

			place(entry, groundUnder(flowFrom:Lerp(landing, math.min(1, alpha * 1.2))))
			task.wait()
		end

		place(entry, landing)
		body:setCrownTrail(false)

		-- And erupts around it.
		body:ease(SlimeBody.Column.width, SlimeBody.Column.height, 0.12)
		if not pause(entry, 0.12) then
			return
		end

		damageCircle(landing, C.radius, C.damage)
		ripple(landing, C.radius, 0.45, Theme.Color.Accent)
		splatter(landing, C.radius, 18)

		body:ease(1, 1, 0.3)
		if not pause(entry, 0.3) then
			return
		end
		body:wobble(0.6, 0.4)
	end)

	-- Whatever happened, the crown goes back on his head.
	restore()

	if not ok then
		error("coronation failed", 0)
	end
end

--[[
	SLIME RAIN

	He hauls his own mass upward into a tall column and throws handfuls of
	himself over the arena. He is visibly thinner while he does it and lighter
	afterwards.

	The attack communicates its source: everything that falls came off the top
	of him, and he is the tall thin thing in the middle of the room while it
	happens.

	Dodge: each handful is marked before it lands, and they arrive in sequence
	rather than together. Keep walking.
]]
local function slimeRain(entry, phase: number)
	local R = Tuning.rain
	local drops = R.drops[phase] or 0

	if drops <= 0 then
		return
	end

	local body = entry.body
	local centre = feetOf(entry)

	body:ease(SlimeBody.Column.width, SlimeBody.Column.height, R.draw)
	if not pause(entry, R.draw) then
		return
	end

	--[[
		Which of the handfuls come down alive.

		Chosen up front and shuffled into the sequence rather than rolled per
		drop, so the count is exactly what the phase says it is - a per-drop
		chance would occasionally produce none at all, and Reabsorb would then
		have a phase with nothing to reach for through no decision of anybody's.

		Capped against what is already out there, so a slow fight does not
		become a slime flood.
	]]
	local alive = 0
	EnemyService.forEachNear(centre, R.spread * 2, function(model)
		if model.Name == SPAWN_NAME then
			alive += 1
		end
	end)

	local living = math.clamp(R.becomeSlime[phase] or 0, 0, math.max(0, R.maxAdds - alive))

	local hatches = {}
	for index = 1, drops do
		hatches[index] = index <= living
	end
	for index = drops, 2, -1 do
		local swap = math.random(1, index)
		hatches[index], hatches[swap] = hatches[swap], hatches[index]
	end

	spendMass(entry, Tuning.mass.perRain)

	for index = 1, drops do
		if entry.slimeFinished then return end
		local players = livingPlayers()
		if #players == 0 then
			break
		end

		local victim = players[math.random(1, #players)]
		local root = rootOf(victim)

		-- Alternate a committed aimed drop with a modest movement intercept.
		-- Aim freezes before the marker appears; changing direction beats it.
		local aim = if root then root.Position else centre
		if root and phase >= 2 and index % 2 == 0 then
			local velocity = root.AssemblyLinearVelocity
			local lead = Vector3.new(velocity.X, 0, velocity.Z) * 0.3
			if lead.Magnitude > 10 then
				lead = lead.Unit * 10
			end
			aim += lead
		end
		local spot = groundUnder(aim)
		local hatchesHere = hatches[index]
		local color = if hatchesHere then Theme.Color.Good else Theme.Color.Bad
		telegraph(spot, R.radius, R.flight, Theme.Color.Bad)
		task.spawn(function()
			local top = centre + Vector3.new(0, entry.height * 1.4, 0)

			local blob = newPart(Vector3.one * 3, color, 0.1)
			-- Living drops pulse as well as changing colour, so their identity
			-- is readable even when the arena lighting washes the tint out.
			if hatchesHere then
				TweenService:Create(blob, TweenInfo.new(0.18, Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut, -1, true), { Size = Vector3.one * 3.8 }):Play()
			end
			blob.Shape = Enum.PartType.Ball
			blob.Material = Enum.Material.SmoothPlastic
			projectileTrail(blob, color, 2)
			Debris:AddItem(blob, R.flight + 0.5)
			blob.CFrame = CFrame.new(top)
			blob.Parent = workspace

			local lift = math.max(10, (spot - top).Magnitude * 0.35)
			local control = (top + spot) * 0.5 + Vector3.new(0, lift, 0)

			local start = os.clock()
			while os.clock() - start < R.flight do
				if entry.slimeFinished then
					blob:Destroy()
					return
				end
				local alpha = (os.clock() - start) / R.flight
				local inverse = 1 - alpha

				blob.Position = top * (inverse * inverse)
					+ control * (2 * inverse * alpha)
					+ spot * (alpha * alpha)

				task.wait()
			end

			blob:Destroy()
			if entry.slimeFinished then return end
			damageCircle(spot, R.radius, R.damage)
			ripple(spot, R.radius, 0.34, color)
			splatter(spot, R.radius, 8)

			--[[
				And some of them get up.

				The slick goes down either way - the ground he landed on is
				slime whether or not it is alive - so a living drop reads as
				"that one kept moving" rather than as a different kind of
				object arriving.
			]]
			slick(entry, spot, R.radius, R.lingerSeconds, R.lingerDamage, R.lingerInterval)

			if hatchesHere then
				EnemyService.spawn(SPAWN_NAME, spot)
				spendMass(entry, Tuning.mass.perSlime)
			end
		end)

		if not pause(entry, R.spacing) then
			return
		end
	end

	-- The last flight finishes before recovery and the next attack's tell.
	if not pause(entry, math.max(0, R.flight - R.spacing)) then
		return
	end
	body:ease(1, 1, 0.35)
	if not pause(entry, 0.35) then
		return
	end
	body:wobble(0.5, 0.3)
end

--[[
	ROYAL DECREE

	He rises into a tall royal posture and the crown lifts off his head and
	burns gold. Up to three of his surviving slimes are linked to it by
	tethers and ringed, and each is given a lane toward a player - drawn full
	length, filling over the warning. On the command every linked slime still
	alive flattens into a fast surge of slime, runs its lane, and stands back
	up at the far end, where it stays - and can later be reabsorbed.

	A SUBJECT KILLED BEFORE THE COMMAND LOSES ITS LANE. Its tether snaps and
	its lane fades the moment it dies. The adds were already a reason to clear
	the room before Reabsorb; now they are a reason in the other direction as
	well, and a ringed slime is a target the player has been handed.

	WITH NO SUBJECTS he tears one or two small blobs off himself at a visible
	mass cost and sends those instead: shorter lanes, less damage, and they
	dissolve afterwards rather than becoming slimes. Visibly the lesser
	version - clearing the room still paid.

	THE CROWN NEVER LEAVES HIM here; it is posed, not detached, so there is
	nothing to restore. Subjects are HELD through EnemyService for the whole
	attack, which is what stops Reabsorb and Decree ever choosing the same
	slime and what stops a commanded slime hopping off its own lane.

	Dodge: a lane is drawn full length for a second and a half. Step off it,
	or kill the slime at the start of it.
]]
local function royalDecree(entry, phase: number)
	local D = Tuning.decree
	local body = entry.body
	local scope = entry.scope
	local here = feetOf(entry)

	local players = livingPlayers()
	if #players == 0 then
		return
	end

	-- RISE: tall and royal, the crown lifting and burning. Pose and glow are
	-- in the scope, so they are cleared however this ends.
	scope:add(function()
		body:setCrownPose(nil, nil)
		body:setCrownGlow(false)
	end)
	body:ease(SlimeBody.Column.width * 1.35, SlimeBody.Column.height * 0.8, D.rise)
	body:setCrownPose(2.5, nil)
	body:setCrownGlow(true, Theme.Color.Accent)
	if not pause(entry, D.rise) then
		return
	end

	--[[
		WHO EACH LANE GOES FOR: the players shuffled once and dealt round the
		subjects, so three lanes go to three people where there are three
		people and only all point at one person when there is one. Aim is
		frozen here, before anything is drawn.
	]]
	for index = #players, 2, -1 do
		local swap = math.random(1, index)
		players[index], players[swap] = players[swap], players[index]
	end
	local dealt = 0
	local function nextAim(): Vector3?
		for _ = 1, #players do
			dealt += 1
			local root = rootOf(players[(dealt - 1) % #players + 1])
			if root then
				return root.Position
			end
		end
		return nil
	end

	local function laneEnd(from: Vector3, aim: Vector3, maxLength: number): Vector3
		local flat = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z)
		local distance = flat.Magnitude
		local direction = if distance > 1 then flat.Unit else entry.facing
		local length = math.clamp(distance + D.overshoot, D.laneMin, maxLength)
		return groundUnder(from + direction * length)
	end

	-- THE SUBJECTS: the nearest free children, up to the count.
	local candidates = {}
	EnemyService.forEachNear(here, D.reach, function(model, position)
		if model.Name == SPAWN_NAME and EnemyService.heldBy(model) == nil then
			table.insert(candidates, { model = model, distance = (position - here).Magnitude })
		end
	end)
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)

	local links = {}
	for _, candidate in ipairs(candidates) do
		if #links >= D.subjects then
			break
		end
		local aim = nextAim()
		if not aim then
			break
		end
		local grip = EnemyService.hold(candidate.model, entry)
		if grip then
			scope:add(function()
				grip:release()
			end)
			local from = grip:feet()
			local to = laneEnd(from, aim, D.laneMax)
			table.insert(links, {
				grip = grip,
				from = from,
				to = to,
				lane = laneTelegraph(scope, from, to, D.width, D.warning, Theme.Color.Accent),
				tether = newTether(scope, Theme.Color.Accent, 0.9),
				ring = newRing(scope, math.max(2, grip.height * 0.6), Theme.Color.Accent),
				damage = D.damage,
			})
		end
	end

	-- NO SUBJECTS: pieces of himself instead. Fewer, shorter, weaker, and
	-- each one is a visible cost.
	if #links == 0 then
		local count = D.fallbackBlobs[phase] or 1
		local base = math.random() * math.pi * 2
		for index = 1, count do
			local aim = nextAim()
			if not aim then
				break
			end
			local angle = base + (index - 1) * math.pi
			local side = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local from = groundUnder(here + side * (body:radius() + 3))

			local blob = scope:add(newPart(Vector3.one * 3.2, Theme.Color.Good, 0.1))
			blob.Shape = Enum.PartType.Ball
			blob.Material = Enum.Material.SmoothPlastic
			blob.CFrame = CFrame.new(mouthOf(entry))
			blob.Parent = workspace
			scope:tween(blob, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(from + Vector3.new(0, 1.6, 0)),
			})
			spendMass(entry, Tuning.mass.perDecreeBlob)

			local to = laneEnd(from, aim, D.fallbackLane)
			table.insert(links, {
				blob = blob,
				from = from,
				to = to,
				lane = laneTelegraph(scope, from, to, D.width, D.warning, Theme.Color.Accent),
				tether = newTether(scope, Theme.Color.Accent, 0.6),
				damage = D.fallbackDamage,
			})
		end
	end

	if #links == 0 then
		body:ease(1, 1, 0.3)
		return
	end

	-- THE WARNING: tethers held from the crown, rings over the subjects,
	-- lanes filling. A linked subject that dies loses everything the moment
	-- it does.
	local function crownPoint(): Vector3
		return mouthOf(entry) + Vector3.new(0, entry.height * 0.65, 0)
	end

	local function cancel(link)
		link.cancelled = true
		link.tether:Destroy()
		if link.ring then
			link.ring:Destroy()
		end
		if link.lane then
			link.lane:fade(0.25)
		end
	end

	local warnStart = os.clock()
	while os.clock() - warnStart < D.warning do
		if entry.slimeFinished then
			return
		end
		local crown = crownPoint()
		for _, link in ipairs(links) do
			if link.cancelled then
				continue
			end
			if link.grip and not link.grip:alive() then
				cancel(link)
				continue
			end
			local at = if link.grip
				then link.grip:feet() + Vector3.new(0, link.grip.height * 0.5, 0)
				else link.blob.Position
			layTether(link.tether, crown, at, if link.grip then 0.9 else 0.6)
			if link.ring then
				layRing(link.ring, link.grip:feet() + Vector3.new(0, link.grip.height + 1.5, 0))
			end
		end
		task.wait()
	end
	if entry.slimeFinished then
		return
	end

	-- THE COMMAND. Every surviving link surges; the rest were cancelled.
	body:flash(Theme.Color.Accent, 0.2)

	local running = {}
	for _, link in ipairs(links) do
		if link.cancelled or (link.grip and not link.grip:alive()) then
			if not link.cancelled then
				cancel(link)
			end
			continue
		end
		link.tether:Destroy()
		if link.ring then
			link.ring:Destroy()
		end
		if link.lane then
			link.lane:surge(0.9, 0.15, D.surge * 0.4)
		end
		if link.grip and link.grip.body then
			-- Flattens into the surge as it leaves.
			link.grip.body:ease(1.7, 0.35, D.surge * 0.3)
		end
		local flat = Vector3.new(link.to.X - link.from.X, 0, link.to.Z - link.from.Z)
		link.direction = if flat.Magnitude > 0.01 then flat.Unit else entry.facing
		table.insert(running, link)
	end

	-- Every subject killed during the warning: the decree is over before it
	-- began, which is the player's reward for having done that.
	if #running == 0 then
		body:setCrownPose(nil, nil)
		body:setCrownGlow(false)
		body:ease(1, 1, 0.35)
		return
	end

	local ledger = {}
	local start = os.clock()
	while os.clock() - start < D.surge do
		if entry.slimeFinished then
			return
		end
		local alpha = (os.clock() - start) / D.surge
		local eased = alpha * alpha * (3 - 2 * alpha)

		for _, link in ipairs(running) do
			local at = groundUnder(link.from:Lerp(link.to, eased))

			if link.grip then
				-- Dead mid-lane: nothing more moves, and nothing more hits.
				if not link.grip:alive() then
					continue
				end
				link.grip:place(at, link.direction)
			elseif link.blob.Parent then
				link.blob.Size = Vector3.new(4.4, 1.5, 4.4)
				link.blob.CFrame = CFrame.new(at + Vector3.new(0, 0.9, 0))
			end

			-- The lane behind the head of the surge is where the slime has
			-- been; anybody on it has been run through. Once per lane, under
			-- the cast's cap.
			for _, player in ipairs(livingPlayers()) do
				local victim = rootOf(player)
				if victim and onLane(victim.Position, link.from, at, D.width * 0.5) then
					hitOnce(ledger, link, player, link.damage, D.capPerCast)
				end
			end
		end
		task.wait()
	end
	if entry.slimeFinished then
		return
	end

	-- REFORM at the end of the lane. Subjects stand back up and are handed
	-- back to themselves; blobs dissolve. The lanes go.
	for _, link in ipairs(running) do
		if link.grip then
			if link.grip:alive() then
				link.grip:place(link.to, link.direction)
				if link.grip.body then
					link.grip.body:wobble(D.reform + 0.2, 0.4)
				end
				link.grip:release()
			end
		elseif link.blob.Parent then
			scope:tween(link.blob, TweenInfo.new(D.reform, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
				Size = Vector3.new(5, 0.3, 5),
			})
		end
		ripple(link.to, D.width, 0.3, Theme.Color.Accent)
		if link.lane then
			link.lane:fade(D.reform)
		end
	end

	body:setCrownPose(nil, nil)
	body:setCrownGlow(false)
	body:ease(1, 1, 0.35)
	pause(entry, D.reform)
end

-- ---------------------------------------------------------------------------
-- Contact
-- ---------------------------------------------------------------------------

--[[
	Standing inside him.

	The radius is HIS BODY, live - so a pancake genuinely has a wider contact
	area than a column does, because the contact area IS the body. Capped at
	melee reach minus a margin so there is always a ring you can hit him from
	without being in him.

	Its own timer per player rather than one for him, so two players in contact
	are hurt on their own schedules; a shared one would let a second player's
	arrival reset the first player's clock.
]]
local function contactDamage(entry, now: number)
	local C = Tuning.contact

	if not entry.contactAt then
		entry.contactAt = setmetatable({}, { __mode = "k" })
	end

	local centre = feetOf(entry)
	local radius = math.min(entry.body:radius(), CONTACT_CAP)

	for _, player in ipairs(livingPlayers()) do
		local root = rootOf(player)

		if root and now - (entry.contactAt[player] or -math.huge) >= C.interval then
			local offset = root.Position - centre

			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius then
				entry.contactAt[player] = now
				CombatService.applyDamage(player, C.damage, SOURCE)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- The fight
-- ---------------------------------------------------------------------------

--[[
	THE PHASE CHANGE, as a thing that happens rather than a threshold that is
	crossed.

	He locks up, swells until he is visibly straining, and bursts - shedding
	slimes and flinging himself apart before pulling back together. Nothing here
	deals damage: the player has just done something good, and answering that
	with an unavoidable hit is how a fight teaches people to stop pushing.

	Run as an attack, through the same `busy` flag, so it cannot overlap
	anything and so the boss bar names it.
]]
local function phaseShift(entry, phase: number)
	local S = Tuning.shift
	local body = entry.body
	local centre = feetOf(entry)

	-- Straining: he pulls in tight and then swells past his own size.
	body:ease(0.82, 0.88, S.swell * 0.45)
	if not pause(entry, S.swell * 0.45) then
		return
	end

	body:ease(1.34, 1.3, S.swell * 0.55)
	body:flash(Theme.Color.Accent, S.swell * 0.55)
	if not pause(entry, S.swell * 0.55) then
		return
	end

	--[[
		And comes apart.

		The loudest thing in the fight, and the only place that is on purpose.
		A phase change is the fight telling the player the rules just moved, and
		it happens exactly twice - so it gets the wide wave, thrown far enough
		out to wash past wherever they are standing, and it gets to be the one
		effect they cannot miss.
	]]
	body:shape(1.5, 0.72)
	ripple(centre, entry.height * 3.2, 0.75, Theme.Color.Accent)
	splatter(centre + Vector3.new(0, entry.height * 0.4, 0), entry.height * 1.2, 30)
	body:wobble(S.burst * 2.4, 0.55)

	local sheds = S.sheds[phase] or 0
	local alive = 0

	EnemyService.forEachNear(centre, S.throw * 4, function(model)
		if model.Name == SPAWN_NAME then
			alive += 1
		end
	end)

	for index = 1, sheds do
		if alive + index > Tuning.rain.maxAdds then
			break
		end

		local angle = (index / sheds) * math.pi * 2 + math.random()
		local spot = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * S.throw

		EnemyService.spawn(SPAWN_NAME, groundUnder(spot))
		spendMass(entry, Tuning.mass.perSlime)
	end

	pause(entry, S.burst)
end

local function phaseOf(entry): number
	local fraction = entry.health / entry.def.health

	if fraction <= Tuning.phaseAt[2] then
		return 3
	elseif fraction <= Tuning.phaseAt[1] then
		return 2
	end

	return 1
end

--[[
	What he is capable of, by phase.

	Built around escalating INSTABILITY, not bigger numbers: nothing hits
	harder in a later phase than it did in the first. What changes is how much
	of the room he is using.

	PHASE 1 - THE BODY CLAIMS. Body Collapse, Claim the Realm, Slime Rain on
	its restrained counts. Teaches flattening, shedding mass, eating the
	ground, and that the handfuls get up.

	PHASE 2 - THE SUBJECTS OBEY. Everything above, plus Reabsorb when a free
	child exists and Royal Decree. The phase change itself sheds slimes so
	the subject mechanics have something to use. The player now has to manage
	the lesser slimes, not only dodge him.

	PHASE 3 - THE CROWN RULES. Everything above, plus Coronation. Shorter
	rests and wider targeting; the same damage.

	The attacks whose entire content is a SHAPE are dropped if the model cannot
	deform - see SlimeBody. Claim, Rain, Reabsorb and Decree are all playable
	on a rigid model, so the deck is never empty.
]]
local function deckFor(entry, phase: number): { string }
	local deformable = entry.body.deformable

	--[[
		CLAIM THE REALM IS THE FLOOR.

		Something has to be in the deck at every range, in every phase and on
		every body, and it has to be an attack that works from anywhere. The
		veins reach, a target past their reach is pulled in to it, a rigid
		model can play it, and it still attacks when there is nothing to eat.
	]]
	local deck = { "claim", "rain" }

	if deformable then
		table.insert(deck, "pancake")
	end

	if phase >= 2 then
		-- Only worth reaching for if there is a FREE child out there - one
		-- Decree is not already commanding.
		local children = 0
		EnemyService.forEachNear(feetOf(entry), Tuning.absorb.reach, function(model)
			if model.Name == SPAWN_NAME and EnemyService.heldBy(model) == nil then
				children += 1
			end
		end)

		if children > 0 then
			table.insert(deck, "absorb")
		end

		table.insert(deck, "decree")
	end

	if phase >= 3 and deformable then
		table.insert(deck, "coronation")
	end

	--[[
		CORONATION IS THE CENTREPIECE, and it is not chained straight into
		another big area attack: the move after it is drawn from the half of
		the deck that is about his subjects and his reach, not his footprint.
		Rain always survives this, so it can never empty the deck.
	]]
	if entry.lastAttack == "coronation" then
		for index = #deck, 1, -1 do
			if deck[index] == "pancake" or deck[index] == "claim" then
				table.remove(deck, index)
			end
		end
	end

	return deck
end

--[[
	Never the same attack twice running.

	Exclude the last move outright and discourage an A/B/A loop. Surviving
	children make reabsorption and a decree more tempting after rain, without
	a fixed combo.
]]
local function chooseAttack(entry, deck: { string }): string
	local weights = table.create(#deck, 0)
	local total = 0
	for index, pick in ipairs(deck) do
		if pick ~= entry.lastAttack or #deck == 1 then
			local weight = if pick == entry.previousAttack then 0.35 else 1
			-- Using what he just shed matters most right after shedding it;
			-- killing the adds removes these options through deckFor before
			-- the lottery runs.
			if (pick == "absorb" or pick == "decree") and entry.lastAttack == "rain" then
				weight *= 1.8
			end
			weights[index] = weight
			total += weight
		end
	end
	local roll = math.random() * total
	for index, pick in ipairs(deck) do
		if weights[index] > 0 then
			roll -= weights[index]
			if roll <= 0 then
				return pick
			end
		end
	end
	return deck[1]
end

-- What the boss bar calls each one while it is happening.
local ATTACK_NAMES = {
	shift = "Unstable",
	pancake = "Body Collapse",
	claim = "Claim the Realm",
	absorb = "Reabsorb",
	decree = "Royal Decree",
	coronation = "Coronation",
	rain = "Slime Rain",
}

local ATTACKS = {
	shift = function(entry, phase) phaseShift(entry, phase) end,
	pancake = function(entry) pancake(entry) end,
	claim = function(entry, phase) claimRealm(entry, phase) end,
	absorb = function(entry) reabsorb(entry) end,
	decree = function(entry, phase) royalDecree(entry, phase) end,
	coronation = function(entry) coronation(entry) end,
	rain = function(entry, phase) slimeRain(entry, phase) end,
}

--[[
	One attack, start to finish, in its own thread.

	A coroutine rather than a state machine spread across ticks because every
	one of these is a SEQUENCE - gather, commit, recover - and writing that as
	branches on a stored state is how the timing of a tell ends up depending on
	the frame rate.

	`entry.busy` stops the tick starting a second one. It is cleared in the same
	thread that set it, whatever happened, so an attack that errors does not
	leave him standing still forever.
]]
local function performAttack(entry, phase: number, target: Player)
	--[[
		A phase change pre-empts whatever he was going to do.

		`seenPhase` is the last phase he actually ACTED in, so this fires once
		per threshold and cannot fire twice if he is healed back over one by a
		reabsorb - crossing 65% downward is an event, crossing it upward is not.
	]]
	local shifting = phase > (entry.seenPhase or 1)
	entry.seenPhase = math.max(entry.seenPhase or 1, phase)

	local pick = if shifting then "shift" else chooseAttack(entry, deckFor(entry, phase))

	if not shifting then
		entry.previousAttack = entry.lastAttack
		entry.lastAttack = pick
	end
	entry.bossPhase = ATTACK_NAMES[pick]
	entry.busy = true

	--[[
		Pushed rather than waited for.

		The bar is otherwise only sent when he takes DAMAGE, which is nearly
		always but not reliably: a player who has backed off to survive a phase
		is exactly the player who most needs to read what is coming, and they
		are not hitting him. BossService throttles, so this is free.
	]]
	BossService.update(entry)

	--[[
		EVERYTHING THE ATTACK MAKES GOES IN HERE, and goes when it ends.

		Parts, tethers, lane marks, tweens, delayed tasks, the grip on any
		slime he is commanding, the crown's pose. Destroyed below whether the
		attack returned, errored or was cut short by his death (see finish),
		so no attack can leave anything behind by forgetting - the only way
		to leak is to not put something in the scope, and the helpers put
		things in it for you.
	]]
	local scope = AbilityScope.new()
	entry.scope = scope

	task.spawn(function()
		local ok, err = pcall(ATTACKS[pick], entry, phase, target)

		if entry.scope == scope then
			entry.scope = nil
		end
		scope:destroy()

		if entry.slimeFinished then
			return
		end

		if not ok then
			warn("[SlimeEmperor]", pick, "failed:", err)

			-- Whatever it was doing to his shape, his streaks and his crown,
			-- it is not doing any more. An attack that dies halfway would
			-- otherwise leave a ribbon hanging off him or his crown burning
			-- for the rest of the fight, which is the sort of thing that
			-- outlives the bug that caused it and gets reported as its own.
			pcall(function()
				entry.body:ease(1, 1, 0.2)
				entry.body:setTrail(false)
				entry.body:setCrownTrail(false)
				entry.body:setCrownPose(nil, nil)
				entry.body:setCrownGlow(false)
			end)
		end

		local rest = math.random() * (Tuning.restMax[phase] - Tuning.restMin[phase])
			+ Tuning.restMin[phase]

		-- And sometimes he simply stops for a while. See breatherChance.
		if math.random() < Tuning.breatherChance then
			rest += Tuning.breatherExtra
		end

		-- The centrepiece gets its own silence after it. See deckFor for the
		-- other half of that rule.
		if pick == "coronation" then
			rest += Tuning.afterCoronation
		end

		entry.nextAttackAt = os.clock() + rest
		entry.busy = false
		entry.bossPhase = nil

		--[[
			Put down, settled, and ready to hop again - never mid-air.

			An attack that moved him leaves the hop cycle believing it is
			somewhere it is not, and the next frame would arc him from a stale
			`from` to a stale `to`. Resetting to a grounded wait is what makes
			the seam between an attack ending and him moving again invisible.
		]]
		entry.hop.state = "wait"
		entry.hop.until_ = os.clock() + Tuning.hop.pause

		BossService.update(entry)
	end)
end

--[[
	One frame of him hopping about between attacks.

	A four-state cycle - wait, crouch, air, and back to wait through a landing -
	because that is what a slime does and because each state is a SHAPE: he is
	squashed while crouching, stretched in the air, and splatted on landing.
	The movement and the deformation are the same animation, which is why it
	reads as a body rather than as a model sliding with a bounce played over it.

	He only travels when he is further away than the standoff. Inside it he
	stays put and breathes, so he never shoulders into somebody standing next to
	him - and so melee has a place to stand.
]]
local function stepHop(entry, hop, facing: Vector3?, distance: number, now: number)
	local H = Tuning.hop
	local body = entry.body

	if hop.state == "air" then
		local alpha = math.clamp((now - hop.started) / H.air, 0, 1)

		if alpha >= 1 then
			-- Also nil. Landing is not a decision to turn; the next hop is.
			place(entry, hop.to, nil)
			body:setTrail(false)

			-- The splat, then the jelly settling out of it.
			body:shape(SlimeBody.SquashJump.width * 1.06, SlimeBody.SquashJump.height * 0.94)
			body:wobble(H.land, 0.36)

			--[[
				AND NOTHING ELSE. No wave, no splash.

				A ripple here was tried and taken out again. He lands like this
				every second and a half all fight, and an effect that fires on
				every ordinary hop stops being an effect - it becomes the
				background, and then the ripple on an actual slam has to compete
				with it instead of meaning something.

				The trail going out on the same frame is what marks the landing.
				That is enough for a footstep.
			]]

			hop.state = "wait"
			hop.until_ = now + H.land + H.pause
			return
		end

		-- A real arc, so he is genuinely off the ground in the middle of it -
		-- and scaled to him, so a bigger slime jumps higher. See H.lift.
		local inverse = 1 - alpha
		local lift = math.max(H.minLift, entry.height * H.lift)
		local apex = (hop.from + hop.to) * 0.5 + Vector3.new(0, lift, 0)

		-- nil facing: he committed to a direction at takeoff and a slime in
		-- mid-air cannot steer.
		place(entry, hop.from * (inverse * inverse)
			+ apex * (2 * inverse * alpha)
			+ hop.to * (alpha * alpha), nil)
		return
	end

	if hop.state == "crouch" then
		if now >= hop.until_ then
			hop.state = "air"
			hop.started = now
			-- Stretching as he leaves, over the first third of the flight.
			body:stretch(H.air * 0.35)
			body:setTrail(true)
		end
		return
	end

	--[[
		WAITING - and NOT turning.

		He used to be re-faced every single frame, which meant a slime sitting
		on the ground swivelling on the spot to track you: the single most
		artificial thing he did. A blob has no feet to turn on. It points where
		it last threw itself and it changes direction by throwing itself again.

		So facing is chosen ONCE, at the moment he commits to a hop, and held
		for the whole of it. Everything below passes nil, which placeModel reads
		as "keep the rotation you have".
	]]
	if not body:isAnimating() then
		local breath = 1 + math.sin(now * 1.6) * 0.035
		body:shape(breath, 2 - breath)
	end

	place(entry, feetOf(entry), nil)

	if now < (hop.until_ or 0) then
		return
	end

	local from = feetOf(entry)

	--[[
		HE ALWAYS HOPS, including with somebody standing on him.

		He used to stop dead inside the standoff, which made walking up to him
		the way to switch his animation off - stand on the boss and he becomes a
		statue. A slime does not stop bouncing because you are close; it bounces
		AROUND, which is what this does: near him the hop is short and aimed off
		to one side rather than at the player.

		That also solves the problem the standoff existed for. He is not
		refusing to approach any more, he is simply never aimed straight down
		your throat when he is already there.
	]]
	--[[
		WHERE THE HOP GOES is decided from the player, not from his heading.

		The old version started with his current facing and nudged it, which
		meant a bad heading propagated: he would hop along it, arrive still
		facing wrong, and hop along it again. Taking the direction to the player
		fresh every time means a hop is never worse aimed than the one before.

		His FACING is a separate matter and is handled continuously in step() -
		he turns toward what he is doing at a fixed rate rather than snapping to
		it here.
	]]
	local toPlayer = facing or entry.facing
	local direction = toPlayer
	local stride = H.stride

	if distance <= Tuning.standoff then
		-- Sideways, to realign, on whichever side he is not already drifting
		-- toward. See sideMin/sideMax.
		local side = if math.random() < 0.5 then 1 else -1
		local angle = math.rad(math.random(H.sideMin, H.sideMax)) * side
		local cos, sin = math.cos(angle), math.sin(angle)

		direction = Vector3.new(
			toPlayer.X * cos - toPlayer.Z * sin, 0, toPlayer.X * sin + toPlayer.Z * cos
		).Unit

		stride = H.stride * H.idleStride
	else
		-- Never further than the gap, so a full stride from the edge of the
		-- standoff does not land him on top of somebody.
		stride = math.min(
			H.stride, math.max(0, distance - Tuning.standoff) + H.stride * 0.35
		)
	end

	hop.from = from
	hop.to = groundUnder(from + direction * stride)
	hop.state = "crouch"
	hop.until_ = now + H.crouch

	body:crouch(H.crouch)
end

function SlimeEmperor.start(entry)
	entry.slimeFinished = false
	entry.previousAttack = nil
	entry.busy = false
	entry.lastAttack = nil
	entry.contactAt = setmetatable({}, { __mode = "k" })

	-- player -> when an aimed attack last went for them; see pickTarget. Weak,
	-- so a player leaving takes their record with them.
	entry.pressure = setmetatable({}, { __mode = "k" })

	-- The running attack's scope, if one is running; see performAttack.
	entry.scope = nil

	-- `until_` rather than `until`, which is a Lua keyword.
	entry.hop = { state = "wait", until_ = 0, from = Vector3.zero, to = Vector3.zero, started = 0 }

	-- The phase he last acted in; see performAttack.
	entry.seenPhase = 1

	--[[
		Built here rather than at require time, because it measures the model -
		and it has to happen after EnemyService has applied its size variance
		and parented him, or the resting shape it records is the import size.
	]]
	entry.body = SlimeBody.new(entry, "SlimeEmperor", "Crown")

	-- The light and the streak. Asked for rather than automatic: SlimeBody now
	-- also gives ordinary slimes their bounce, and twenty of those lighting a
	-- hillside is not what any of this was for.
	entry.body:lightUp()

	entry.body:setMass(Tuning.mass.rest)

	-- Arriving: he swells up out of nothing. Also the first thing that proves
	-- the deformation is working, before any attack has run.
	entry.body:shape(1.5, 0.35)
	entry.body:ease(1, 1, 0.6)

	-- A moment before he does anything, so a player who has just walked in gets
	-- to see what they walked into.
	entry.nextAttackAt = os.clock() + 2.2
end

function SlimeEmperor.step(entry, dt: number, now: number)
	local body = entry.body
	local hop = entry.hop

	-- Both are built in start(), which EnemyService runs inside a pcall. If it
	-- threw, he stands still rather than erroring once a frame forever.
	if not (body and hop) then
		return
	end

	-- The jelly, every frame, whatever else is happening.
	body:step()

	local position = entry.model:GetPivot().Position
	local target, distance = nearestPlayer(position)

	if not target then
		-- Nobody left. He waits in his own throne room rather than despawning:
		-- a boss that wanders off is a boss you cannot come back to.
		return
	end

	-- Always, including mid-attack. Being inside him is a mistake at every
	-- moment of the fight, not only between his moves.
	contactDamage(entry, now)

	if entry.busy then
		return
	end

	local phase = phaseOf(entry)
	local victim = rootOf(target)

	local facing = nil

	if victim then
		local offset = victim.Position - position
		local flat = Vector3.new(offset.X, 0, offset.Z)

		if flat.Magnitude > 0.1 then
			facing = flat.Unit
		end
	end

	--[[
		HE TURNS CONTINUOUSLY, AT A RATE, wherever he is and whatever he is
		doing - on the ground, mid-hop, between attacks.

		This replaced "turn once, at takeoff, capped at 55 degrees", which was
		put in to stop him swivelling like a turret and overcorrected into a
		different problem: a heading that was wrong stayed wrong for a whole
		hop, so he would visibly travel away from you before coming round.

		A rate fixes both. `dt` is what makes it a rate rather than a snap -
		turnRate degrees per SECOND, so it is the same speed at any frame rate.
		Only `entry.facing` is written here; every placement below passes nil,
		which placeModel reads as "use the facing he already has".
	]]
	if facing then
		entry.facing = turnToward(entry.facing, facing, Tuning.hop.turnRate * dt)
	end

	--[[
		An attack only ever starts from the GROUND.

		This is the whole of "smooth between moving and attacking": a hop
		finishes, he settles, and the next thing begins from a body at rest in a
		known shape. Interrupting mid-air would snap him out of a stretch into
		whatever the attack wanted, which is the exact seam that makes a boss
		look like a state machine rather than a creature.
	]]
	if now >= (entry.nextAttackAt or 0) and hop.state == "wait" then
		performAttack(entry, phase, target)
		return
	end

	stepHop(entry, hop, facing, distance, now)
end

--[[
	DYING.

	He does not fall over - he has nothing to fall over with. He shudders, loses
	cohesion, spreads across the floor, and what is left sinks and goes. The
	crown comes off and drops, because the last thing that should be true of a
	slime king is that he is still wearing it.

	IT IS DRAWN ON A COPY, not on him.

	EnemyService destroys the model the instant it removes the entry, and it is
	right to - the boss is dead, and nothing should be able to keep a live one
	around by animating it. So this clones the body, hands the clone to a
	coroutine, and lets the real model go on schedule. The clone is anchored,
	non-colliding and on a Debris timer, so the worst case if anything here
	throws is a puddle that fades on its own.
]]
local function dissolve(entry)
	local D = Tuning.death
	local body = entry.body

	if not (body and body.deformable and body.body) then
		return
	end

	local original = body.body :: BasePart

	local corpse = original:Clone()
	corpse.Anchored = true
	corpse.CanCollide = false
	corpse.CanQuery = false
	corpse.CanTouch = false
	corpse.Parent = workspace

	local crown = if body.crown then body.crown:Clone() else nil
	if crown then
		for _, part in ipairs(crown:IsA("BasePart") and { crown } or crown:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = true
			end
		end
		crown.Parent = workspace
	end

	Debris:AddItem(corpse, D.shudder + D.collapse + D.sink + 1)
	if crown then
		Debris:AddItem(crown, 12)
	end

	--[[
		The clone carries his light with it, which is what makes this work.

		The corpse is a copy of the body part, so the PointLight SlimeBody put
		inside him comes along - and that is worth having rather than stripping,
		because it means the room goes dark as he does. It is driven by hand
		below: up while he shudders, out as he sinks.
	]]
	local glow = corpse:FindFirstChildWhichIsA("PointLight")
	local litAt = if glow then glow.Brightness else 0

	task.spawn(function()
		local base = corpse.Size
		local bottom = corpse.Position.Y - base.Y * 0.5

		-- A last shudder: he goes rigid and shakes before he lets go, and burns
		-- brighter doing it. Anything about to go out flares first.
		local shudder = os.clock()
		while os.clock() - shudder < D.shudder do
			local jitter = 1 + (math.random() - 0.5) * 0.1
			corpse.Size = Vector3.new(base.X * jitter, base.Y * jitter, base.Z * jitter)
			corpse.Position = Vector3.new(
				corpse.Position.X, bottom + corpse.Size.Y * 0.5, corpse.Position.Z
			)

			if glow then
				glow.Brightness = litAt * (1 + 2.2 * ((os.clock() - shudder) / D.shudder))
			end

			task.wait()
		end

		local floor = Vector3.new(corpse.Position.X, bottom, corpse.Position.Z)
		ripple(floor, base.X * 2.2, 0.7, Theme.Color.Good)
		splatter(floor, base.X, 30)

		-- Losing cohesion: he spreads and flattens.
		local collapse = os.clock()
		while os.clock() - collapse < D.collapse do
			local alpha = (os.clock() - collapse) / D.collapse
			local eased = alpha * alpha * (3 - 2 * alpha)

			corpse.Size = Vector3.new(
				base.X * (1 + eased * 1.6),
				base.Y * (1 - eased * 0.88),
				base.Z * (1 + eased * 1.6)
			)
			corpse.Position = Vector3.new(
				corpse.Position.X, bottom + corpse.Size.Y * 0.5, corpse.Position.Z
			)
			task.wait()
		end

		-- And sinks. Transparency and height together, so he thins out rather
		-- than dropping through the floor as a solid object.
		local spread = corpse.Size
		local sink = os.clock()

		while os.clock() - sink < D.sink do
			local alpha = (os.clock() - sink) / D.sink

			corpse.Size = Vector3.new(
				spread.X * (1 + alpha * 0.35), spread.Y * (1 - alpha * 0.9), spread.Z * (1 + alpha * 0.35)
			)
			corpse.Position = Vector3.new(
				corpse.Position.X, bottom + corpse.Size.Y * 0.5, corpse.Position.Z
			)
			corpse.Transparency = alpha

			-- Out faster than he fades, so the last thing that happens is the
			-- room going dark rather than a lit puddle disappearing from a lit
			-- floor.
			if glow then
				glow.Brightness = litAt * 3.2 * math.max(0, 1 - alpha * 1.4)
			end

			task.wait()
		end

		corpse:Destroy()
	end)
end

function SlimeEmperor.finish(entry, reason: string?)
	entry.slimeFinished = true
	entry.busy = false

	--[[
		The attack in flight, if any, is torn down NOW rather than when its
		thread next looks: its tethers and lane marks go, any slime it was
		holding is handed back, and a thrown crown is put back on his head
		before the corpse below is cloned from him. The flag above is what
		stops the thread itself the next time it checks. Everything older is
		on a Debris timer measured in seconds.
	]]
	if entry.scope then
		entry.scope:destroy()
		entry.scope = nil
	end

	if entry.body then
		pcall(function()
			entry.body:setTrail(false)
			entry.body:setCrownTrail(false)
			entry.body:setCrownPose(nil, nil)
			entry.body:setCrownGlow(false)
		end)
	end

	-- Only a death gets a death. Despawning, or the world being cleared, should
	-- leave nothing behind at all.
	if reason == "died" then
		pcall(dissolve, entry)
	end
end

--[[
	FUTURE, NOT IMPLEMENTED: "USURPER'S CORONATION", a legendary boss drop.

	Kept here as a design note only, so the idea survives beside the attack it
	is learned from. Nothing below exists in code: it is not in AbilityConfig,
	has no server module, VFX module, plan module or scroll asset, and neither
	EnemyDrops nor this file's death logic know about it.

	A player-adapted Coronation:
	  - the player throws a spectral slime crown toward a server-validated
	    target point;
	  - the descending crown draws the same shrinking-shadow countdown the
	    boss's crown does;
	  - the caster briefly liquefies (visually) and reforms beside the crown
	    on a safe, valid surface;
	  - reformation is a slime eruption that damages nearby enemies;
	  - with no safe destination the caster stays put and the eruption still
	    happens at the validated target.
	Suggested opening balance: Legendary, 35-45 second cooldown, 55-65 mana,
	about 120 studs of cast range. It should feel recognisably learned from
	the Emperor without replaying his whole sequence.

	When it is built, the physical reward goes down through
	ScrollService.place(...): ability scrolls are world objects, not
	EnemyDrops inventory items.
]]

-- Where the fight changes, as health fractions, for the boss bar's markers
-- (BossService sends it): three stages.
SlimeEmperor.phases = Tuning.phaseAt

return SlimeEmperor
