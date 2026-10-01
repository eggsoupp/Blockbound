--[[
	SlimeEmperor

	A gigantic blob of slime that can reshape itself, wearing a crown.

	THE ONE IDEA THIS FIGHT IS BUILT ON: HIS BODY IS THE WEAPON, AND IT IS FINITE

	He has MASS. Everything he throws is made of him and costs mass; everything
	he takes back returns it. Mass is his size, his reach, his contact hitbox
	and how hard he is to fight - all of it read live off the body part rather
	than from numbers written down beside it.

	So the fight has an economy the player can play against:

	    CANNON / RAIN            spend mass. He visibly shrinks - and so does
	                             his crown, because there is less king.
	    REABSORB                 takes it back, and HEALS him for it.

	Killing the slimes he sheds is not busywork - it is the difference between
	a boss who gets smaller all fight and one who keeps rebuilding himself. That
	is the strategic layer, and it exists because he is made of slime.

	EVERY ATTACK USES A PROPERTY OF BEING A BLOB

	  PANCAKE      loses shape entirely and spreads. The damage area IS his
	               flattened body, measured off the part. Then flows away as a
	               puddle and stands back up somewhere else.
	  CANNON       rears back, gathers a mass of himself on the far side, and
	               throws it. It arcs, sheds droplets, and bursts into pools.
	  RAIN         hauls his mass upward and throws it over the arena in
	               handfuls - and SOME OF THEM GET UP. This is how he breeds.
	  REABSORB     ropes a survivor back in on a tether of slime, shrinking it
	               as it comes, and swells as it lands. He heals for it.
	  CORONATION   flattens, fires the crown straight up, flows under wherever
	               it is going to land, and erupts around it as it comes down.
	  RICOCHET     compresses and becomes the projectile. Three bounces, each
	               landing marked before he leaves for it.

	SIX, AND FOUR WERE CUT TO GET THERE

	DIVIDE was a windup and then some slimes, which is every summon in every
	game - SLIME RAIN took its job, so the attack you dodge and the attack that
	fills the room are one attack. SURGE threw a wall across the floor, which a
	dragon could do with its tail. PLUMMET was a good attack that did not earn
	its slot next to Ricochet.

	ENGULF was cut for a reason worth writing down: its whole content was
	RESTRAINING the player, and a Roblox server cannot hold a character still -
	movement is client-owned. So "you are caught" could only ever be a box
	appearing and some damage, with an escape nobody could see the rules of. An
	attack whose core verb the engine will not let you perform is not an attack
	that needs another pass.

	None of these is an ability a knight could perform. Take away "is made of
	slime" and there is no attack left in the list.

	WHY THERE IS NO GENERIC SLAM

	There was, in the version before this one, along with a projectile volley, a
	charge and a spinning ring. They were fine and they were anybody's. The test
	applied to every attack here was: could a dragon do this? If yes, it was cut
	or rebuilt until the answer was no.

	SHAPE-BASED ATTACKS NEED A DEFORMABLE BODY

	SlimeBody can only truly deform a body that is ONE BasePart. If the artist
	built him from several, it falls back to uniform scaling and the attacks
	whose whole content is a SHAPE - pancake and coronation - are dropped
	from the deck rather than played invisibly. See `deckFor`.

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
		-- PER SLIME, not per attack: a three-way split really does cost him
		-- three times as much as a two-way one. Small, because it is charged
		-- several times at once - at 0.11 a single division took a third of
		-- him and two of them put him on the floor for the rest of the fight.
		perCannon = 0.06,
		perRain = 0.05,
		-- Charged again for each handful that lands alive. A slime that gets up
		-- and walks off really is a piece of him that left.
		perSlime = 0.05,
		perAbsorb = 0.13,
		-- Four per cent of his health, which is about two seconds of swinging
		-- at him. Enough that letting him do it four times over costs a
		-- noticeable stretch of the fight, and not so much that one missed
		-- slime undoes a phase. Halved with his health; it is a FRACTION of it,
		-- not an absolute.
		healPerAbsorb = 60,
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

	cannon = {
		gather = 0.95,     -- he rears back, then whips through
		-- How high the shot arcs on its way over. It is thrown, not rolled.
		arc = 26,
		speed = 62,
		damage = 24,
		blobRadius = 5,
		splashes = 3,
		splashRadius = 5,
		splashSeconds = 3.5,
		splashDamage = 6,
		splashInterval = 0.9,
		range = 90,
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
		RICOCHET, and the problem it had.

		Once he HOPS to get about - which he now does - a bounce attack is the
		same verb as walking, only faster, and it read as a dash rather than as
		an attack. Everything here is set to make the difference obvious at a
		glance rather than after being hit by it:

		  compress  more than twice as long as a hop's crouch. He visibly winds
		            up, and the first landing is marked before he leaves.
		  height    three times a hop's arc, so he goes genuinely overhead.
		  stride    nearly three times a hop, so he crosses the arena rather
		            than shuffling toward you.
		  bounces   three, not four. It was a chase; now it is a sequence with
		            an end you can count.

		If it still reads as a dash it is one line in `deckFor` to remove - the
		fight has eight other attacks and loses nothing structural without it.
	]]
	ricochet = {
		compress = 0.55,
		mark = 0.45,       -- each landing is marked this long before he arrives
		bounces = 3,
		flight = 0.62,
		-- Also a control height, and also measured against him: three times
		-- his own height of control, so he peaks at about one and a half times
		-- it - comfortably over a hop, which is the point.
		lift = 6,
		minLift = 40,
		stride = 34,
		-- Degrees he may re-aim per bounce. Wider than a hop's 55, because a
		-- committed attack is allowed to track harder than a stroll.
		turn = 75,
		radius = 12,
		damage = 26,
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
	task.wait(P.rear)

	body:ease(SlimeBody.Pancake.width, SlimeBody.Pancake.height, P.fall)
	task.wait(P.fall)

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
	task.wait(P.spread)


	--[[
		HE LEAVES NOTHING BEHIND.

		There used to be a slick here - a wide pale disc dropped at the spot he
		had just flowed away from. It was the worst-looking thing in the fight:
		by the time it appeared he was somewhere else, so it read as an
		unexplained circle rather than as a mark he had made, and it outlived
		the attack, so the boss bar had already cleared the name and it looked
		like a move of its own that nobody had announced.

		The rule it broke is worth keeping: a hazard has to be attached to the
		thing that made it, in time and in space. Cannon splashes and rain drops
		still leave slicks and both are fine, because they land where you
		watched them land and while the attack is still happening.
	]]

	body:ease(1, 1, 0.35)
	task.wait(0.35)
	body:wobble(0.5, 0.28)
end

--[[
	SLIME CANNON

	He gathers a mass of himself into a bulge reaching AT you - a real stretch
	along his facing, because his body part is turned to look at whoever he is
	fighting - then fires it. He is measurably smaller afterwards.

	The shot travels along the ground and splatters into pools where it stops.

	Dodge: the bulge is nearly a second of him visibly aiming, and the shot goes
	in a straight line. Step out of it.
]]
local function slimeCannon(entry, target: Player)
	local C = Tuning.cannon
	local root = rootOf(target)
	if not root then
		return
	end

	local body = entry.body
	local from = feetOf(entry)

	local offset = root.Position - from
	local direction = Vector3.new(offset.X, 0, offset.Z)
	if direction.Magnitude < 1 then
		return
	end
	direction = direction.Unit

	--[[
		THE WIND-UP: he comes round to face you, leaning away and swelling on
		the far side.

		The turn happens DURING the lean rather than before it, so the aim is
		part of the tell - watching him rotate toward you is the earliest
		warning the attack gives, and it is the same speed he turns at
		everywhere else.

		Rearing BACK is the shape that says a throw is coming - it is the same
		reason a person steps back before pitching - and the sideways swell is
		the mass visibly gathering somewhere before it leaves. An earlier
		version pulled thin and poked forward, which read as a nudge.
	]]
	body:ease(1.32, 1.12, C.gather * 0.7, 0.66)
	turnOver(entry, direction, C.gather * 0.7)

	-- Then whips through: thin across, long toward them.
	body:ease(0.72, 0.8, C.gather * 0.3, 1.9)
	task.wait(C.gather * 0.3)

	spendMass(entry, Tuning.mass.perCannon)
	body:ease(1, 1, 0.35)

	--[[
		THE SHOT: an arc, not a slide, and stretched along its own flight.

		A sphere skimming the floor at constant height was the worst-looking
		thing in the fight - it read as a marble rolling, and nothing about it
		said it had come out of a body. This is a teardrop: scaled long on the
		axis it is travelling, turned to face where it is going, tumbling, and
		on a real ballistic arc so it rises out of him and falls onto the floor.
	]]
	local flight = C.range / C.speed

	local shot = newPart(
		Vector3.new(C.blobRadius * 1.5, C.blobRadius * 1.5, C.blobRadius * 3.2),
		Theme.Color.Good, 0.05
	)
	shot.Material = Enum.Material.SmoothPlastic
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shot
	projectileTrail(shot, Theme.Color.Good, C.blobRadius)
	shot.Parent = workspace
	Debris:AddItem(shot, flight + 0.5)

	local from3 = from + Vector3.new(0, entry.height * 0.55, 0) + direction * 4
	local landed = groundUnder(from + direction * C.range)
	local apex = (from3 + landed) * 0.5 + Vector3.new(0, C.arc, 0)
	-- Announce every pool at its actual location before the projectile lands.
	local splashSpots = table.create(C.splashes)
	for index = 1, C.splashes do
		local angle = index / C.splashes * math.pi * 2
		local spot = groundUnder(landed + Vector3.new(
			math.cos(angle) * C.splashRadius, 0, math.sin(angle) * C.splashRadius
		))
		splashSpots[index] = spot
		telegraph(spot, C.splashRadius, flight, Theme.Color.Bad)
	end

	local hit = {}
	local start = os.clock()

	while os.clock() - start < flight do
		if entry.slimeFinished then
			shot:Destroy()
			return
		end
		local alpha = (os.clock() - start) / flight
		local inverse = 1 - alpha

		local at = from3 * (inverse * inverse)
			+ apex * (2 * inverse * alpha)
			+ landed * (alpha * alpha)

		-- Aimed along its own velocity, which is what makes a stretched blob
		-- read as flying rather than as a sausage sliding sideways.
		shot.CFrame = CFrame.lookAt(at, at + direction + Vector3.new(0, -alpha, 0))
			* CFrame.Angles(0, 0, os.clock() * 6)

		for _, player in ipairs(livingPlayers()) do
			local victim = rootOf(player)

			if victim and not hit[player] then
				if (victim.Position - at).Magnitude <= C.blobRadius * 1.6 then
					hit[player] = true
					CombatService.applyDamage(player, C.damage, SOURCE)
				end
			end
		end

		task.wait()
	end

	shot:Destroy()
	if entry.slimeFinished then return end

	ripple(landed, C.splashRadius, 0.42, Theme.Color.Good)
	splatter(landed, C.blobRadius * 2, 10)

	-- It bursts into smaller pools rather than simply vanishing: the shot was
	-- made of him, and it is still made of him where it stopped.
	for index = 1, C.splashes do
		local spot = splashSpots[index]
		slick(entry, spot, C.splashRadius, C.splashSeconds, C.splashDamage, C.splashInterval)
	end

	body:ease(1, 1, 0.3)
end



--[[
	REABSORB

	He drags one of his surviving children back and takes it into himself. He
	swells, and he HEALS.

	THIS IS THE STRATEGIC LAYER OF THE FIGHT. Everything else can be beaten by
	dodging well; this can only be beaten by having killed the slimes. It is
	also the only thing in the fight that undoes damage the player has already
	done, which is what makes ignoring the adds a decision rather than an
	oversight.

	It is deliberately slow and loud - a second of him reaching, then the add
	visibly flying in - so that the answer ("kill them next time") is legible.
]]
local function reabsorb(entry)
	local A = Tuning.absorb
	local body = entry.body
	local centre = feetOf(entry)

	-- The nearest of his own children. Nil is the good outcome for the player
	-- and simply ends the attack.
	local prey, preyDistance = nil, math.huge

	EnemyService.forEachNear(centre, A.reach, function(model, position)
		if model.Name == SPAWN_NAME then
			local distance = (position - centre).Magnitude
			if distance < preyDistance then
				prey, preyDistance = model, distance
			end
		end
	end)

	if not prey then
		return
	end

	local mouth = centre + Vector3.new(0, entry.height * 0.45, 0)

	--[[
		THE TETHER IS THE WHOLE READABILITY OF THIS ATTACK.

		Without it, a slime slid across the floor and vanished and the boss got
		a bit bigger, and nobody could tell what had happened or that it had
		cost them anything. A visible rope of slime between the two says
		"these are connected, that one is going into this one" in the first
		frame - and it thickens as the slime gets closer, so the moment of
		arrival is the moment it is thickest.

		A part stretched between two points, re-laid every frame. Cheap, and it
		is made of the same slime as everything else he throws.
	]]
	local tether = newPart(Vector3.new(A.tether, A.tether, 1), Theme.Color.Accent, 0.25)
	tether.Parent = workspace

	local function layTether(at: Vector3, thickness: number)
		local span = (at - mouth).Magnitude
		local middle = (at + mouth) * 0.5

		tether.Size = Vector3.new(thickness, thickness, math.max(1, span))
		tether.CFrame = CFrame.lookAt(middle, at)
	end

	--[[
		A mark on HIM, not a disc the width of the arena.

		It was sized to the distance to the prey, which with a reach of seventy
		meant a hundred-and-forty-stud circle across the whole floor whenever he
		reached for something far away. The thing being communicated is "he is
		pulling something in", and that is the tether's job - this only needs to
		say where he is while he does it.
	]]
	telegraph(centre, math.max(10, entry.body:radius() * 1.6), A.windup, Theme.Color.Accent)

	-- Reaching: he opens out toward it, and the rope goes taut.
	body:ease(1.15, 0.9, A.windup)

	local reach = os.clock()
	while os.clock() - reach < A.windup do
		if not prey.Parent then
			break
		end

		local alpha = (os.clock() - reach) / A.windup
		layTether(prey:GetPivot().Position, A.tether * (0.35 + alpha * 0.65))
		task.wait()
	end

	local from = prey:GetPivot().Position
	local preyScale = if prey:IsA("Model") then prey:GetScale() else 1
	local start = os.clock()

	while os.clock() - start < A.pull do
		if not prey.Parent then
			break
		end

		local alpha = (os.clock() - start) / A.pull
		local at = from:Lerp(mouth, alpha)

		prey:PivotTo(CFrame.new(at))

		--[[
			It shrinks as it goes in, which is the second half of the reading:
			the slime is not being teleported, it is being consumed. By the time
			it reaches him it is a third of its size and the swallow is over.
		]]
		if prey:IsA("Model") then
			prey:ScaleTo(preyScale * (1 - alpha * 0.7))
		end

		-- Thickening, and shortening on its own as the two ends converge.
		layTether(at, A.tether * (1 + alpha * 1.4))
		task.wait()
	end

	tether:Destroy()

	if prey.Parent then
		-- Through the service, so its own bookkeeping - the alive count, the
		-- name plate, the drop tables - all happen exactly as they would for a
		-- kill. It is gone from the world either way.
		EnemyService.despawn(prey)
	end

	--[[
		And he visibly takes it in: a hard swell, a flash of his own colour and
		a burst of slime at the mouth, all on the same frame.

		The swell overshoots and settles rather than easing to the new size,
		because a body absorbing something bulges and then recovers. It is the
		clearest signal in the fight that the player just lost something.
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

	local ok = pcall(function()
		local from = feetOf(entry)

		body:ease(SlimeBody.Pancake.width, SlimeBody.Pancake.height, C.flatten)
		task.wait(C.flatten)

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
			local alpha = (os.clock() - rise) / C.rise
			body:moveCrown(CFrame.new(crownStart:Lerp(apex, alpha))
				* CFrame.Angles(0, alpha * 12, 0))
			task.wait()
		end

		task.wait(C.hang)

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
		task.wait(0.12)

		damageCircle(landing, C.radius, C.damage)
		ripple(landing, C.radius, 0.45, Theme.Color.Accent)
		splatter(landing, C.radius, 18)

		body:ease(1, 1, 0.3)
		task.wait(0.3)
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
	task.wait(R.draw)
	if entry.slimeFinished then return end

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

		task.wait(R.spacing)
	end

	-- The last flight finishes before recovery and the next attack's tell.
	task.wait(math.max(0, R.flight - R.spacing))
	if entry.slimeFinished then return end
	body:ease(1, 1, 0.35)
	task.wait(0.35)
	body:wobble(0.5, 0.3)
end

--[[
	RICOCHET

	He compresses himself into a disc and becomes the projectile: four bounces
	across the arena, stretching in the air and splatting flat on every landing.

	The player is dodging THE BOSS, not a hitbox he emitted. Each landing is
	marked one bounce ahead, so the whole sequence is readable from the first
	compression - and the first bounce goes where you are standing, so standing
	still is the one thing that never works.
]]
local function ricochet(entry, target: Player)
	local R = Tuning.ricochet
	local body = entry.body

	local root = rootOf(target)
	if not root then
		return
	end

	local offset = root.Position - feetOf(entry)
	local direction = Vector3.new(offset.X, 0, offset.Z)
	direction = if direction.Magnitude > 1 then direction.Unit else entry.facing

	body:ease(SlimeBody.SquashJump.width, SlimeBody.SquashJump.height, R.compress)
	task.wait(R.compress)

	for bounce = 1, R.bounces do
		local here = feetOf(entry)

		-- Toward whoever is nearest, re-aimed each bounce, but only by so much:
		-- a bounce that turned to follow perfectly would be undodgeable.
		local chase = nearestPlayer(here)
		if chase then
			local chaseRoot = rootOf(chase)
			if chaseRoot then
				local want = chaseRoot.Position - here
				local flat = Vector3.new(want.X, 0, want.Z)
				--[[
					Capped, like every other turn he makes.

					A blend of the old and new headings looks like steering, but
					it can still swing him a long way in one bounce when the
					player has run round behind him. Going through turnToward
					means a bounce sequence curves rather than kinking, and it
					is the same rule his hops obey.
				]]
				if flat.Magnitude > 1 then
					direction = turnToward(direction, flat.Unit, R.turn)
				end
			end
		end

		local landing = groundUnder(here + direction * R.stride)

		--[[
			The mark goes down BEFORE he leaves, and he sits compressed on it
			for a moment.

			That pause is what separates this from his walk: a hop happens, this
			is announced. It also means the whole three-bounce sequence can be
			read one landing ahead the entire way through.
		]]
		telegraph(landing, R.radius, R.mark + R.flight, Theme.Color.Bad)
		task.wait(R.mark)

		local lift = math.max(R.minLift, entry.height * R.lift)
		local apex = (here + landing) * 0.5 + Vector3.new(0, lift, 0)
		local start = os.clock()

		body:ease(SlimeBody.StretchFly.width, SlimeBody.StretchFly.height, R.flight * 0.4)
		body:setTrail(true)

		while os.clock() - start < R.flight do
			if entry.slimeFinished then return end
			local alpha = (os.clock() - start) / R.flight
			local inverse = 1 - alpha

			place(entry, here * (inverse * inverse)
				+ apex * (2 * inverse * alpha)
				+ landing * (alpha * alpha), direction)

			task.wait()
		end

		place(entry, landing, direction)
		body:setTrail(false)

		body:shape(SlimeBody.SquashJump.width * 1.1, SlimeBody.SquashJump.height * 0.9)
		damageCircle(landing, R.radius, R.damage)
		ripple(landing, R.radius, 0.32, Theme.Color.Bad)
		splatter(landing, R.radius, 10)

		body:wobble(0.28, 0.4)
		task.wait(0.28)
	end

	body:ease(1, 1, 0.3)
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
	task.wait(S.swell * 0.45)

	body:ease(1.34, 1.3, S.swell * 0.55)
	body:flash(Theme.Color.Accent, S.swell * 0.55)
	task.wait(S.swell * 0.55)

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

	task.wait(S.burst)
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

	PHASE 1 - A STABLE BLOB. He holds one shape and changes it deliberately.
	Pancake, Cannon, Rain, Ricochet: four ways of using a body that keeps its
	volume. This phase teaches the vocabulary - flatten, gather, throw, become
	the projectile - and every later attack is built out of those verbs.

	PHASE 2 - UNSTABLE. He starts coming apart and putting himself back
	together. Slime Rain starts landing LIVING handfuls and Reabsorb arrives to
	take them back, and between them they are the mass economy: from here the
	arena has slimes in it, and whether it still does in thirty seconds is the
	player's decision.

	PHASE 3 - VOLATILE. He stops holding a shape at all. Ricochet turns his
	whole body into the projectile and Coronation takes him apart and rebuilds
	him around his own crown. Nothing hits harder than it did in phase one; the
	transformations simply stop pausing.

	The attacks whose entire content is a SHAPE are dropped if the model cannot
	deform - see SlimeBody. Better a smaller deck than an attack that plays as a
	sphere sitting still.
]]
local function deckFor(entry, phase: number, distance: number): { string }
	local deformable = entry.body.deformable
	--[[
		RICOCHET IS THE FLOOR, not cannon.

		Something has to be in the deck at every range and in every phase, and
		it has to be an attack that works from anywhere. The cannon needs room
		to throw and is filtered out up close, so it cannot be the fallback -
		which is what it was, propped up by an Engulf that no longer exists.
	]]
	local deck = { "cannon", "ricochet" }

	if deformable then
		table.insert(deck, "pancake")
	end

	--[[
		Rain is in from the START now.

		It was held back to phase two when there were nine attacks and phase one
		had four of its own. With Engulf and Plummet cut it had two, which
		alternate visibly, so the attack that already had a phase-one count in
		its table takes the slot. It sheds one living slime in phase one against
		three in phase three - so the arena starts filling immediately and
		REABSORB, which is still phase two, arrives to a room that already has
		something in it.
	]]
	table.insert(deck, "rain")

	if phase >= 2 then
		-- Only worth reaching for if there is something out there to reach.
		local children = 0
		EnemyService.forEachNear(feetOf(entry), Tuning.absorb.reach, function(model)
			if model.Name == SPAWN_NAME then
				children += 1
			end
		end)

		if children > 0 then
			table.insert(deck, "absorb")
		end
	end

	if phase >= 3 and deformable then
		table.insert(deck, "coronation")
	end

	-- The cannon wants somewhere to throw; up close it is a whiff. Ricochet is
	-- always in the deck, so this can never empty it.
	if distance < Tuning.standoff * 1.4 then
		for index = #deck, 1, -1 do
			if deck[index] == "cannon" then
				table.remove(deck, index)
			end
		end
	end

	return deck
end

--[[
	Never the same attack twice running.

	Exclude the last move outright and discourage an A/B/A loop. Surviving
	children make reabsorption more tempting after rain, without a fixed combo.
]]
local function chooseAttack(entry, deck: { string }): string
	local weights = table.create(#deck, 0)
	local total = 0
	for index, pick in ipairs(deck) do
		if pick ~= entry.lastAttack or #deck == 1 then
			local weight = if pick == entry.previousAttack then 0.35 else 1
			-- Reclaiming mass matters most after shedding it; killing the adds
			-- removes this option through deckFor before the lottery runs.
			if pick == "absorb" and entry.lastAttack == "rain" then
				weight *= 2
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
	cannon = "Slime Cannon",
	absorb = "Reabsorb",
	coronation = "Coronation",
	rain = "Slime Rain",
	ricochet = "Ricochet",
}

local ATTACKS = {
	shift = function(entry, phase) phaseShift(entry, phase) end,
	pancake = function(entry) pancake(entry) end,
	cannon = function(entry, phase, target) slimeCannon(entry, target) end,
	absorb = function(entry) reabsorb(entry) end,
	coronation = function(entry) coronation(entry) end,
	rain = function(entry, phase) slimeRain(entry, phase) end,
	ricochet = function(entry, phase, target) ricochet(entry, target) end,
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
local function performAttack(entry, phase: number, target: Player, distance: number)
	--[[
		A phase change pre-empts whatever he was going to do.

		`seenPhase` is the last phase he actually ACTED in, so this fires once
		per threshold and cannot fire twice if he is healed back over one by a
		reabsorb - crossing 65% downward is an event, crossing it upward is not.
	]]
	local shifting = phase > (entry.seenPhase or 1)
	entry.seenPhase = math.max(entry.seenPhase or 1, phase)

	local pick = if shifting then "shift" else chooseAttack(entry, deckFor(entry, phase, distance))

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

	task.spawn(function()
		local ok, err = pcall(ATTACKS[pick], entry, phase, target)
		if entry.slimeFinished then
			return
		end

		if not ok then
			warn("[SlimeEmperor]", pick, "failed:", err)

			-- Whatever it was doing to his shape and his streaks, it is not
			-- doing any more. An attack that throws him and dies mid-flight
			-- would otherwise leave a ribbon hanging off him for the rest of
			-- the fight, which is the sort of thing that outlives the bug that
			-- caused it and gets reported as its own.
			pcall(function()
				entry.body:ease(1, 1, 0.2)
				entry.body:setTrail(false)
				entry.body:setCrownTrail(false)
			end)
		end

		local rest = math.random() * (Tuning.restMax[phase] - Tuning.restMin[phase])
			+ Tuning.restMin[phase]

		-- And sometimes he simply stops for a while. See breatherChance.
		if math.random() < Tuning.breatherChance then
			rest += Tuning.breatherExtra
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
		performAttack(entry, phase, target, distance)
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
	-- Everything he makes is on a Debris timer already, so there is nothing to
	-- tear down: the flag is only so a thread still in flight when he dies
	-- stops as soon as it looks.
	entry.busy = false

	-- Only a death gets a death. Despawning, or the world being cleared, should
	-- leave nothing behind at all.
	if reason == "died" then
		pcall(dissolve, entry)
	end
end

return SlimeEmperor
