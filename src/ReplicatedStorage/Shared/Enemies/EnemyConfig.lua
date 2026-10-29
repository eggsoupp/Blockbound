--[[
	EnemyConfig

	Every enemy in the game, and how it behaves. EnemyService knows how to fly,
	how to hop and how to hurt somebody standing too close; this table decides
	which of those an enemy does and how hard, so adding one never touches the
	service.

	NOT HUMANOIDS. Nothing here pathfinds or takes cover, so a Humanoid's state
	machine, physics and rig requirements would buy nothing. The server owns
	their position outright: anchored parts moved with PivotTo on a fixed tick.
	That costs no physics, works with any model rigged or not, and makes "goes
	through blocks" a property of the movement kind rather than a fight with the
	collision system.

	  asset            Model inside ReplicatedStorage.EnemyAssets
	  displayName      what a player would call it
	  health           hit points
	  movement         "Fly" or "Hop" - the whole behaviour split
	  speed            studs/second toward the target
	  aggroRange       how far away it notices a player
	  giveUpRange      how far a player must get for it to stop chasing
	  despawnSeconds   with nobody in giveUpRange, how long before it vanishes
	  contactRange     how close counts as touching, in studs
	  contactDamage    damage per hit
	  contactInterval  seconds before it can hurt the SAME player again

	FLY: hoverHeight above the target's centre, bobAmplitude and bobPeriod for
	the drift while hovering.

	HOP: a state machine - sit, wind up, jump, land - where the JUMP is what
	moves it. On the ground it is genuinely still; airborne it is a projectile
	that cannot steer, which is what reads as a creature deciding to jump at you
	rather than a sprite sliding along with a bounce animation.

	  gravity          studs/s^2; Roblox's own is ~196, lower is more readable
	  jumpPower        takeoff speed, setting both height and airtime
	  maxHopDistance   how far it aims a normal hop
	  maxHopSpeed      ceiling on horizontal takeoff speed
	  groundedSeconds  how long it sits between hops
	  windupSeconds    the telegraph before launch
	  stepUpBlocks     how tall a ledge it can land on; taller is a wall
	  scanUpBlocks     how far above itself to look for ground
	  scanDownBlocks   how far below itself to look before giving up

	LUNGE: a committed, longer, faster jump with its own telegraph and damage,
	used when you are close enough to be worth it - lungeRange, lungeJumpPower,
	lungeMaxDistance, lungeMaxSpeed, lungeWindup, lungeDamage, lungeCooldown.

	BOUNCE: the squash and stretch that turns a hop into a body throwing
	itself, rather than a model translating along an arc.

	  bounce           true to give it a deformable body
	  bodyPart         optional name of the part to deform; defaults to the
	                   model's PrimaryPart, which every enemy has already

	EnemyService builds a ServerScriptService.SlimeBody for it and drives three
	shapes off the state machine it already had - squashed for the whole of the
	windup, stretched out of the launch, and a damped splat on landing sized to
	how hard it came down. It is the same layer the Slime Emperor uses, so
	retuning the crouch retunes it for the king and his subjects at once.

	Only for a body that is ONE BasePart. A multi-part model can only be scaled
	uniformly, so it will pulse rather than flatten - which still reads far
	better than not moving, and needs no special case.
]]

local EnemyConfig = {}

-- Folder under ReplicatedStorage holding the authored models.
EnemyConfig.AssetsFolder = "EnemyAssets"

-- Where spawned enemies live in the world.
EnemyConfig.WorldFolder = "Enemies"

-- 30Hz, not frame rate and not 10Hz. An anchored part replicates as discrete
-- updates rather than being smoothed, so a ballistic arc sampled ten times a
-- second arrives as a series of teleports. Tripling it costs less than it
-- looks: the terrain scan is state-dependent, and a grounded hopper never
-- scans at all.
EnemyConfig.TickInterval = 1 / 30

-- A hard ceiling, so a stuck spawn loop or an enthusiastic /spawn cannot take
-- the server down. Refused spawns say so rather than failing quietly.
EnemyConfig.MaxAlive = 60

-- Anchored enemies with collision on would shove a player through the ground
-- when they move, since the server sets their position outright rather than
-- pushing them. Contact damage is measured by distance, so nothing needs the
-- collision anyway.
EnemyConfig.Collides = false

--[[
	Default size jitter as a fraction, rolled once per spawn, so a group of
	slimes is slightly different slimes rather than one model printed six times.
	A definition may override it with its own `sizeVariance`.

	Only appearance changes - a big slime is not a harder slime, which keeps
	what a player learns about an enemy true of every one of them. Past about
	0.25 it stops reading as variation and starts reading as two creatures.
]]
EnemyConfig.SizeVariance = 0.12

--[[
	How long a dropped item takes to fly from a corpse to the player who earned
	it.

	Read by BOTH sides and that is the entire point. StarterPlayerScripts.DropFlight
	spends this long on the curve; EnemyService waits exactly this long before
	putting the item in the bag. Neither tells the other anything - they agree
	because they are reading the same number - and that is what makes the item
	land in the inventory on the frame the projectile lands on the player.

	Long enough to see the arc and read its colour, short enough that nobody
	waits for their loot.
]]
EnemyConfig.DropFlightSeconds = 0.55

--[[
	AMBIENT SPAWNING - what ServerScriptService.EnemySpawner does with all this.

	An enemy is spawned in a biome named by its own `spawnBiomes`, so where a
	creature lives is a line in its own entry rather than a table somewhere else
	that has to be kept in step with this one. An enemy with no `spawnBiomes`
	never spawns on its own and can only be placed by a command, which is the
	right default for anything added mid-build.

	  interval        seconds between attempts, per server
	  chance          how often an eligible player gets one
	  perPlayerCap    living enemies within `countRadius` before it stops
	  countRadius     what counts as "near this player" for that cap
	  minRadius       nearest it will put one, in studs
	  maxRadius       furthest
	  groupMin/Max    how many are in a pack
	  packSpread      how loosely a pack is scattered, in studs

	IT HAS TO NOT LOOK LIKE THIS

	The honest description above - "every few seconds, near a player" - is also
	exactly what it must never FEEL like. The first version spawned one or two
	at a fixed distance band on a metronome, and it read as the world producing
	monsters because you were standing there, which is the opposite of coming
	across something.

	Three things hide it, and they are the three fields below the line.

	  cellSize / emptyCells
	    The world is diced into cells and a fixed hash decides which of them
	    hold life at all. Getting on for half do not, and it is always the SAME
	    half: an empty stretch is empty when you walk back through it. This is
	    the important one - it makes emptiness a property of the PLACE rather
	    than of a dice roll, which is the whole difference between "nothing
	    spawned" and "nothing lives here".

	  hiddenAngle / hiddenWithin
	    Nothing appears in the cone you are looking down unless it is far
	    enough away not to be seen arriving. You find things by turning round
	    or cresting a rise, never by watching them fade in.

	  groupMin / groupMax
	    Packs, scattered, at one point - not a ring, and not one at a time. Four
	    slimes together and then nothing for a minute reads as a world; a
	    steady drip of singletons reads as a spawner.

	DELIBERATELY UNAMBITIOUS OTHERWISE. No day/night cycle, no difficulty curve,
	no pack composition, no spawn-blocking on lit areas. It exists so the world
	is not empty, and each of those is a decision better made once there is
	something to balance it against.
]]
EnemyConfig.Spawning = {
	interval = 6,
	chance = 0.65,
	perPlayerCap = 8,
	countRadius = 150,
	minRadius = 70,
	maxRadius = 150,
	groupMin = 2,
	groupMax = 4,
	packSpread = 9,

	-- How many placements it will try before giving up for this interval. More
	-- than one because the checks below reject rather than nudge, and exactly
	-- one try would make looking around a way to turn spawning off.
	tries = 3,

	-- The masking. See above.
	cellSize = 110,
	emptyCells = 0.45,
	hiddenAngle = 55,
	hiddenWithin = 120,

	--[[
		Blocks around the world spawn (the origin) that stay free of wild
		enemies, so the tutorial - and anybody's first minute - is not a slime
		landing on them mid-craft. Nothing is spawned inside it, and a wild
		enemy will not chase anybody standing in it. Enemies put there on
		purpose - the tutorial's training slime, /spawn, a boss - are not wild
		and ignore it.
	]]
	safeBlocks = 50,
}

--[[
	Which way EnemyAssets.DemonEye faces, shared by the two enemies drawn with
	it. The model is built looking along +Z, the opposite of Roblox's forward,
	so it flew at you backwards until this was 180.
]]
local DEMON_EYE_ROTATION = Vector3.new(0, 180, 0)

EnemyConfig.Definitions = {
	-- Passes through terrain, which falls out of the movement kind rather than
	-- being a special case: Fly moves straight at the target through anything,
	-- because nothing asks the collision system for permission.
	Ghost = {
		asset = "Ghost",
		displayName = "Ghost",
		health = 40,
		movement = "Fly",

		-- Corruption's own, and only Corruption's. A biome that reaches for a
		-- thing that passes through walls is a biome you leave.
		spawnBiomes = { "Corruption" },

		-- Slower than a running player: it is a threat you can walk away from,
		-- but not one you can ignore while standing still and mining.
		speed = 10,
		aggroRange = 90,
		giveUpRange = 150,
		despawnSeconds = 30,

		contactRange = 5,
		contactDamage = 8,
		contactInterval = 1.0,

		hoverHeight = 2.5,
		bobAmplitude = 1.2,
		bobPeriod = 2.4,
	},

	--[[
		The Crimson's eye. Flies straight at you through anything, like the
		Ghost, but quicker and frailer: it keeps up with a walk, not a sprint.

		The model is EnemyAssets.DemonEye. The All Seeing Eye summons this same
		eye - see ServantEye below for the lighter version it sends.
	]]
	DemonEye = {
		asset = "DemonEye",
		displayName = "Demon Eye",
		health = 30,
		movement = "Fly",

		spawnBiomes = { "Crimson" },

		speed = 13,
		aggroRange = 100,
		giveUpRange = 160,
		despawnSeconds = 30,

		contactRange = 4,
		contactDamage = 8,
		contactInterval = 1.0,

		hoverHeight = 1.5,
		bobAmplitude = 0.9,
		bobPeriod = 1.8,

		modelRotation = DEMON_EYE_ROTATION,
	},

	-- The arc IS the movement, not decoration on it: a slime is at ground level
	-- only for an instant between hops. Ground height comes from the terrain, so
	-- it follows hills and drops into anything the player has dug out.
	BlueSlime = {
		asset = "BlueSlime",
		displayName = "Blue Slime",
		health = 25,
		movement = "Hop",

		spawnBiomes = { "Plains" },

		speed = 9,
		aggroRange = 70,
		giveUpRange = 120,
		despawnSeconds = 30,

		contactRange = 5,
		contactDamage = 5,
		contactInterval = 1.0,

		-- Well under Roblox's ~196, so hops hang long enough to read as a
		-- decision and to be dodged.
		gravity = 115,
		jumpPower = 40,
		maxHopDistance = 13,
		maxHopSpeed = 15,

		-- The rhythm. Roughly two seconds a hop: sit, tell you it is coming,
		-- commit. Slow enough that you can walk away from one and have to
		-- respect three.
		groundedSeconds = 0.85,
		windupSeconds = 0.35,

		-- It is made of slime, so it moves like it. See BOUNCE above.
		bounce = true,

		-- One block up is a step; two is a wall. That is what makes a player's
		-- hastily-stacked pillar actually work as a defence.
		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		-- Close enough to be worth committing to. The longer windup is the
		-- whole point: it is the tell that lets a paying-attention player step
		-- aside, which is what makes the hit land as a mistake rather than as
		-- bad luck.
		lungeRange = 20,
		lungeJumpPower = 52,
		lungeMaxDistance = 26,
		lungeMaxSpeed = 32,
		lungeWindup = 0.6,
		lungeDamage = 12,
		lungeCooldown = 3.5,
	},

	--[[
		A blue slime in a different colour. Every number is BlueSlime's,
		deliberately - a player who has learned to read one has learned to read
		the other, which is the point of a palette swap.

		The model is the one thing not shared. EnemyAssets.GreenSlime has to
		exist or EnemyService refuses to spawn it rather than substituting;
		point `asset` at "BlueSlime" to borrow the blue model meanwhile.
	]]
	--[[
		THE FIRST BOSS.

		Almost nothing here is read. A definition with a `behaviour` gets the
		whole tick handed to it (see EnemyService), so `movement`, `speed`,
		`aggroRange` and the whole hop state machine are not consulted at all -
		ServerScriptService.Bosses.SlimeEmperor does its own moving, and the
		numbers that matter are its Tuning table.

		What IS read: `health`, because EnemyService owns the health pool and
		the bar; `displayName`; `boss`, which is what puts the bar up; and
		`asset`, the model in ReplicatedStorage.EnemyAssets.

		NO `spawnBiomes`, deliberately. It must never turn up in the ambient
		spawner - see EnemyConfig.Spawning. It is placed, or summoned, or
		nothing: a Gelatinous Crown used on an altar (ServerScriptService.
		AltarSummon), or `/spawn SlimeEmperor`.

		`sizeVariance = 0` because a boss is a landmark. Every other creature
		here is jittered so a group reads as individuals; there is only ever one
		of this, and "how big is it" should mean something.
	]]
	SlimeEmperor = {
		asset = "SlimeEmperor",
		displayName = "Slime Emperor",
		boss = true,
		behaviour = "SlimeEmperor",

		--[[
			About a minute against an iron or gold sword.

			Down from 2200. Ninety seconds was a correct number
			for a boss with nine attacks and turned out to be a long time to
			spend on six - the fight was showing the player everything it had
			twice before it ended.

			See the BALANCE note in the behaviour module for the calculation.
			Nothing else moved with it EXCEPT healPerAbsorb, which is a fraction
			of this and had to be halved too or letting him reabsorb would have
			gone from costing 4% of the fight to costing 8%.
		]]
		health = 1500,

		sizeVariance = 0,

		--[[
			WHICH WAY UP THE ASSET IS, corrected once, for every placement.

			Degrees, as (pitch, yaw, roll), applied by EnemyService.placeModel -
			so it fixes him standing still, oozing, leaping, flattening and
			every frame of every attack, because all of those go through that
			one function.

			ZERO IS "THE ARTIST BUILT HIM UPRIGHT AND FACING -Z", which is what
			Roblox treats as forward. If he stands up but faces sideways, put 90
			or -90 in the MIDDLE number. If he is lying on his side, put 90 or
			-90 in the THIRD. If he is face-down, the first. One number at a
			time, ninety at a time, and there are only six answers.

			IT IS 180 ON Y because this model is built facing the other way:
			he moved correctly and looked like he was travelling backwards the
			whole time. That is a fact about the file, not about the fight, and
			this is the only place it should ever be corrected.

			To check it yourself: stand still and let him hop to you. He should
			arrive looking AT you. If he arrives looking away, this number is
			wrong - change 180 to 0. If he arrives sideways, use 90 or -90.

			This is deliberately not solved in the fight code. An imported model
			is oriented however the artist left it; that is a fact about the
			file, and a boss module compensating for it would leave every other
			enemy to discover the same problem again.
		]]
		modelRotation = Vector3.new(0, 180, 0),

		--[[
			And nothing else.

			No movement, no speed, no aggro or contact numbers: EnemyService
			reads none of them for a creature with a behaviour, and validate()
			knows not to ask. Inventing values to fill the shape would put
			numbers in this file that look tuned and are never read, which is
			worse than their absence - the Tuning table in the behaviour module
			is where every number that matters actually lives.
		]]
	},

	--[[
		THE ALL SEEING EYE - a boss after Terraria's Eye of Cthulhu. Everything
		it does, and every number that tunes it, is in
		ServerScriptService.Bosses.AllSeeingEye.

		TWO MODELS, both in ReplicatedStorage.EnemyAssets:
		  AllSeeingEye        the floating eyeball (phase one)
		  AllSeeingEyeMouth   the eye with a mouth (phase two)
		The second is fitted to the first's size automatically.

		Like the Slime Emperor: no spawnBiomes, so it never appears on its own.
		/spawn AllSeeingEye. If it arrives at night it leaves at dawn.
	]]
	AllSeeingEye = {
		asset = "AllSeeingEye",
		displayName = "The All Seeing Eye",
		boss = true,
		behaviour = "AllSeeingEye",

		-- About a minute and a half against an iron or gold sword; see the
		-- BALANCE note in the behaviour module.
		health = 2200,

		sizeVariance = 0,

		--[[
			WHICH WAY THE MODELS FACE, as (pitch, yaw, roll) in degrees.

			Zero means the PUPIL points along -Z, the model's front - which is
			what "looking at you" is measured from. If it hovers over you
			looking somewhere else, find the number the way the Slime
			Emperor's notes describe: 90 at a time, one axis at a time. Try
			the middle number first (180, then 90, then -90); if the pupil
			points up or down instead, the first. /bbface AllSeeingEye <n>
			turns it live for the middle number.

			`mouthRotation` is the same, for the mouthed model, measured
			relative to the eye: zero if the two were built facing the same
			way, which they usually are.

			IT IS 180 ON Y because, like the Demon Eye, this model is built
			with its pupil along +Z: at 0 it hovered, chased and charged with
			the back of its head toward you. Only the model is turned - where
			it aims and moves is worked out from its own look direction, so
			nothing about the fight changes. The mouth is placed on the eye's
			turned pivot, so it gets the same correction and stays at zero.
		]]
		modelRotation = Vector3.new(0, 180, 0),
		mouthRotation = Vector3.new(0, 0, 0),
	},

	--[[
		What the All Seeing Eye summons: Demon Eyes, the same model and name as
		the Crimson's, but lighter and faster, because the boss sends them three
		or four at a time while it is fighting you. Only the boss makes these;
		its own Tuning caps how many are out at once.
	]]
	ServantEye = {
		asset = "DemonEye",
		displayName = "Demon Eye",
		health = 14,
		movement = "Fly",

		speed = 17,
		aggroRange = 160,
		giveUpRange = 220,
		despawnSeconds = 25,

		contactRange = 3.5,
		contactDamage = 6,
		contactInterval = 0.8,

		hoverHeight = 1,
		bobAmplitude = 0.6,
		bobPeriod = 1.4,

		sizeVariance = 0.12,

		modelRotation = DEMON_EYE_ROTATION,
	},

	--[[
		SIGNUS - the Hallowed Eclipse. A hooded lunar spellcaster that fights
		from range: crescents, a falling moon, ground that tears open, and in
		its second phase an eclipse nova that only cover stops. Everything it
		does, and every number that tunes it, is in
		ServerScriptService.Bosses.Signus.

		The model is ReplicatedStorage.EnemyAssets.Signus, the Motor6D rig
		built by assets/signus-hallow/roblox/CreateSignusRig.server.lua: an
		anchored RootPart and four jointed MeshParts, ArticulatedRig = true.
		Its RootPart's front is already -Z, so modelRotation is zero.

		No spawnBiomes: /spawn Signus, or nothing.

		`hitFlash = "Highlight"` because tinting a textured MeshPart's Color
		shows nothing; EnemyService flashes it with a Highlight instead.
		`burstColor` is the death burst, which would otherwise be whatever
		colour the importer left the largest mesh.
	]]
	Signus = {
		asset = "Signus",
		displayName = "Signus",
		boss = true,
		behaviour = "Signus",

		-- A little under the Eye's: it is in melee reach more of the time,
		-- but holds still less often. See the BALANCE note in the module.
		health = 2000,

		sizeVariance = 0,
		modelRotation = Vector3.new(0, 0, 0),

		hitFlash = "Highlight",
		hitFlashColor = Color3.fromRGB(255, 236, 246),
		burstColor = Color3.fromRGB(150, 70, 225),
	},

	--[[
		THE BLIGHTBORER - the Corruption's worm, after Terraria's Eater of
		Worlds. It swims through the ground, erupts under you, tears trenches,
		spits ichor that eats blocks, opens sinkholes, and splits into more
		worms as its segments break. Everything it does, and every number
		that tunes it, is in ServerScriptService.Bosses.Blightborer.

		THREE MODELS in ReplicatedStorage.EnemyAssets: `head` (the asset
		below), `body_segment` and `tail`. The behaviour builds the body out
		of the other two. If a piece faces the wrong way, it is corrected with
		a WormRotation attribute on that model, not with modelRotation here -
		see the module's notes.

		No spawnBiomes: the ambient spawner never makes it. For now it is
		/spawn Blightborer or nothing; how it comes up in the Corruption on
		its own is still to be decided.

		`hitFlash = "Highlight"` so a hit lights the whole body, textured or
		not, with one instance.
	]]
	Blightborer = {
		asset = "head",
		displayName = "The Blightborer",
		boss = true,
		behaviour = "Blightborer",

		-- A bit more than Signus: it is underground and out of reach for a
		-- good part of the fight. See the BALANCE note in the module.
		health = 2400,

		sizeVariance = 0,
		modelRotation = Vector3.new(0, 0, 0),

		hitFlash = "Highlight",
		hitFlashColor = Color3.fromRGB(214, 255, 150),
		burstColor = Color3.fromRGB(96, 70, 110),
	},

	GreenSlime = {
		asset = "GreenSlime",
		displayName = "Green Slime",
		health = 25,
		movement = "Hop",

		-- Plains has both slimes, so the open country has a little variety in
		-- it without either of them being the rare one you go looking for.
		spawnBiomes = { "Plains" },

		speed = 9,
		aggroRange = 70,
		giveUpRange = 120,
		despawnSeconds = 30,

		contactRange = 5,
		contactDamage = 5,
		contactInterval = 1.0,

		gravity = 115,
		jumpPower = 40,
		maxHopDistance = 13,
		maxHopSpeed = 15,

		groundedSeconds = 0.85,
		windupSeconds = 0.35,

		bounce = true,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 20,
		lungeJumpPower = 52,
		lungeMaxDistance = 26,
		lungeMaxSpeed = 32,
		lungeWindup = 0.6,
		lungeDamage = 12,
		lungeCooldown = 3.5,
	},

	--[[
		What the Blightborer spills when a segment bursts, hatches from its
		spit and retches up: small, quick flying things that come straight at
		you through anything, like the Corruption's Ghost but frailer. Only
		the boss makes these, and its own Tuning caps how many are out.

		The model is EnemyAssets.Blightling, which does not exist yet. Until
		it does the boss sends Ghosts in its place (and says so once in the
		output), so the fight works now and gets its own minion the moment
		the model is added - no change here needed.
	]]
	Blightling = {
		asset = "Blightling",
		displayName = "Blightling",
		health = 16,
		movement = "Fly",

		speed = 15,
		aggroRange = 150,
		giveUpRange = 220,
		despawnSeconds = 25,

		contactRange = 3.5,
		contactDamage = 6,
		contactInterval = 0.8,

		hoverHeight = 1.5,
		bobAmplitude = 0.7,
		bobPeriod = 1.3,

		sizeVariance = 0.15,
	},

	--[[
		THE VOXEL CREATURES - five rig-free creatures from the voxel creature
		pack (assets/voxel-creatures), each a single coloured union, so none
		of them needs a joint: they hop, float, slither and swoop as rigid
		bodies, and squash, sway and bank in code.

		Each moves with an ordinary Fly or Hop and carries a `trait`, a module
		in ServerScriptService.Creatures that adds its one signature move on
		top - see EnemyService.traitFor. The move's own numbers are in that
		module's Tuning table; the numbers here are the plain creature.
		Between them they give Swamp, Desert, Snow and Hallow their first
		creatures.
	]]

	--[[
		A heavy blob that lumbers in slow, high hops and fights with its eye:
		a raking sweep up close, a locked lance from range.

		The hop is HIGH rather than long - a jumpPower of 36 under 115 gravity
		peaks at about 5.6 studs, clear of one block (4) where the old 22
		peaked at 2.1 and walked it into every step.
	]]
	Lasereye = {
		asset = "Lasereye",
		displayName = "Lasereye",
		health = 70,
		movement = "Hop",
		trait = "Lasereye",

		spawnBiomes = { "Swamp" },

		speed = 6,
		aggroRange = 55,
		giveUpRange = 90,
		despawnSeconds = 30,

		contactRange = 4.5,
		contactDamage = 8,
		contactInterval = 1.0,

		gravity = 115,
		jumpPower = 36,
		maxHopDistance = 8,
		maxHopSpeed = 9,
		groundedSeconds = 1.1,
		windupSeconds = 0.4,

		bounce = true,
		sizeVariance = 0.08,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 36,
		lungeMaxDistance = 8,
		lungeMaxSpeed = 9,
		lungeWindup = 0.6,
		lungeDamage = 8,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(48, 112, 80),
	},

	--[[
		Skates rather than hops - see its trait. The Hop numbers below are only
		for climbing a step it cannot glide up; there is no bounce and no
		lunge, which is what made the old one read as a slime.
	]]
	Snowman = {
		asset = "Snowman",
		displayName = "Snowman",
		health = 45,
		movement = "Hop",
		trait = "Snowman",

		spawnBiomes = { "Snow" },

		speed = 7,
		aggroRange = 60,
		giveUpRange = 100,
		despawnSeconds = 30,

		contactRange = 4.5,
		contactDamage = 6,
		contactInterval = 1.0,

		gravity = 130,
		jumpPower = 36,
		maxHopDistance = 6,
		maxHopSpeed = 9,
		groundedSeconds = 0.2,
		windupSeconds = 0.15,

		sizeVariance = 0.1,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 36,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 9,
		lungeWindup = 0.5,
		lungeDamage = 6,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(240, 245, 255),
	},

	-- Buzzes after you and darts in to sting.
	GreenWasp = {
		asset = "GreenWasp",
		displayName = "Green Wasp",
		health = 22,
		movement = "Fly",
		trait = "Wasp",

		spawnBiomes = { "Desert", "Plains" },

		speed = 14,
		aggroRange = 80,
		giveUpRange = 130,
		despawnSeconds = 30,

		contactRange = 3.5,
		contactDamage = 6,
		contactInterval = 0.9,

		hoverHeight = 3,
		bobAmplitude = 0.8,
		bobPeriod = 1.1,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(84, 180, 20),
	},

	-- Circles overhead and swoops.
	Shrike = {
		asset = "Shrike",
		displayName = "Yellow-billed Shrike",
		health = 35,
		movement = "Fly",
		trait = "Shrike",

		spawnBiomes = { "Hallow", "Snow" },

		speed = 16,
		aggroRange = 85,
		giveUpRange = 140,
		despawnSeconds = 30,

		contactRange = 4.5,
		contactDamage = 14,
		contactInterval = 1.2,

		hoverHeight = 8,
		bobAmplitude = 1.2,
		bobPeriod = 2.6,

		sizeVariance = 0.1,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(128, 104, 88),
	},

	-- Slithers after you and strikes.
	Cobra = {
		asset = "Cobra",
		displayName = "Cobra",
		health = 32,
		movement = "Hop",
		trait = "Cobra",

		spawnBiomes = { "Desert" },

		speed = 6.5,
		aggroRange = 50,
		giveUpRange = 90,
		despawnSeconds = 30,

		contactRange = 3.5,
		contactDamage = 5,
		contactInterval = 1.0,

		-- Only used to climb a step, drop off a ledge or take a knockback.
		gravity = 120,
		jumpPower = 30,
		maxHopDistance = 5,
		maxHopSpeed = 8,
		groundedSeconds = 0.15,
		windupSeconds = 0.1,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 30,
		lungeMaxDistance = 5,
		lungeMaxSpeed = 8,
		lungeWindup = 0.5,
		lungeDamage = 5,
		lungeCooldown = 99,

		-- Built facing -Z already. The markings on the BACK of its hood read
		-- like a face, which is how 180 got in here once.
		modelRotation = Vector3.new(0, 0, 0),

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(252, 176, 28),
	},

	--[[
		A swamp hunter on eight jointed legs: scuttles in bursts, spits a
		slowing web, rears and pounces. See its trait. The Hop numbers are for
		the pounce (the lunge, which the trait winds up itself - lungeRange 0
		keeps the plain hop from ever choosing one) and for climbing a step.
	]]
	GreenSpider = {
		asset = "GreenSpider",
		displayName = "Green Spider",
		health = 40,
		movement = "Hop",
		trait = "GreenSpider",

		spawnBiomes = { "Swamp" },

		speed = 11,
		aggroRange = 60,
		giveUpRange = 100,
		despawnSeconds = 30,

		contactRange = 4,
		contactDamage = 6,
		contactInterval = 0.9,

		gravity = 120,
		jumpPower = 34,
		maxHopDistance = 6,
		maxHopSpeed = 10,
		groundedSeconds = 0.15,
		windupSeconds = 0.12,

		sizeVariance = 0.1,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 34,
		lungeMaxDistance = 14,
		lungeMaxSpeed = 30,
		lungeWindup = 0.55,
		lungeDamage = 14,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(56, 136, 4),
	},

	--[[
		The Crimson's vermin: packs of small, quick rats that dart in, bite and
		scurry off again (see its trait). Frail on purpose - a pack is the
		threat. The Hop numbers are only for climbing a step.
	]]
	EvilRat = {
		asset = "EvilRat",
		displayName = "Evil Rat",
		health = 18,
		movement = "Hop",
		trait = "EvilRat",

		spawnBiomes = { "Crimson" },
		packSize = NumberRange.new(3, 5),

		speed = 15,
		aggroRange = 60,
		giveUpRange = 100,
		despawnSeconds = 30,

		contactRange = 3,
		contactDamage = 5,
		contactInterval = 0.8,

		gravity = 120,
		jumpPower = 32,
		maxHopDistance = 6,
		maxHopSpeed = 12,
		groundedSeconds = 0.1,
		windupSeconds = 0.08,

		sizeVariance = 0.12,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 32,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 12,
		lungeWindup = 0.3,
		lungeDamage = 5,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(56, 56, 56),
	},

	--[[
		A plains brute: knuckle-walks, swipes up close, and from range pounds
		its chest and leaps into a ground slam (see its trait). Uncommon and
		alone. The lunge numbers ARE the leap - the trait winds it up itself,
		lungeRange 0 keeps the plain hop from choosing one - and the rest of
		the Hop numbers are for climbing.
	]]
	Gorilla = {
		asset = "Gorilla",
		displayName = "Gorilla",
		health = 140,
		movement = "Hop",
		trait = "Gorilla",

		spawnBiomes = { "Plains" },
		spawnWeight = 0.25,
		packSize = NumberRange.new(1, 1),

		speed = 8,
		aggroRange = 55,
		giveUpRange = 95,
		despawnSeconds = 40,

		contactRange = 4.5,
		contactDamage = 10,
		contactInterval = 1.2,

		gravity = 120,
		jumpPower = 36,
		maxHopDistance = 6,
		maxHopSpeed = 9,
		groundedSeconds = 0.2,
		windupSeconds = 0.15,

		sizeVariance = 0.06,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 50,
		lungeMaxDistance = 22,
		lungeMaxSpeed = 30,
		lungeWindup = 1.1,
		lungeDamage = 10,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(56, 56, 56),
	},

	--[[
		A young horned dinosaur of the desert: paws the ground, then charges in
		a straight line it cannot steer, and stands stunned if it hits a wall
		(see its trait). The Hop numbers are only for climbing a step.
	]]
	Pentasaurus = {
		asset = "Pentasaurus",
		displayName = "Pentasaurus",
		health = 90,
		movement = "Hop",
		trait = "Pentasaurus",

		spawnBiomes = { "Desert" },
		spawnWeight = 0.6,
		packSize = NumberRange.new(1, 2),

		speed = 6,
		aggroRange = 60,
		giveUpRange = 100,
		despawnSeconds = 35,

		contactRange = 4,
		contactDamage = 8,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 36,
		maxHopDistance = 6,
		maxHopSpeed = 9,
		groundedSeconds = 0.2,
		windupSeconds = 0.15,

		sizeVariance = 0.08,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 36,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 9,
		lungeWindup = 0.5,
		lungeDamage = 8,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(160, 40, 30),
	},

	--[[
		The Corruption's stalker on four long legs: walks slowly, spits a
		burning ichor, and rears to impale whatever is in front of it (see its
		trait). The Hop numbers are only for climbing a step.
	]]
	WormyHorror = {
		asset = "WormyHorror",
		displayName = "Wormy Horror",
		health = 110,
		movement = "Hop",
		trait = "WormyHorror",

		spawnBiomes = { "Corruption" },
		spawnWeight = 0.7,
		packSize = NumberRange.new(1, 1),

		speed = 6.5,
		aggroRange = 60,
		giveUpRange = 100,
		despawnSeconds = 40,

		contactRange = 4,
		contactDamage = 8,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 38,
		maxHopDistance = 7,
		maxHopSpeed = 10,
		groundedSeconds = 0.2,
		windupSeconds = 0.15,

		sizeVariance = 0.08,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 38,
		lungeMaxDistance = 7,
		lungeMaxSpeed = 10,
		lungeWindup = 0.5,
		lungeDamage = 8,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		hitFlashColor = Color3.fromRGB(210, 160, 255),
		burstColor = Color3.fromRGB(32, 40, 56),
	},

	--[[
		A robed rabbit priest of the Hallow and a SUPPORT enemy: it bounds
		about at a distance, looses homing holy orbs and heals every hurt
		creature near it (see its trait). Frail - kill it first. The Hop
		numbers are only the fallback when every way it could bound is blocked.
	]]
	RabbicCleric = {
		asset = "RabbicCleric",
		displayName = "Rabbic Cleric",
		health = 45,
		movement = "Hop",
		trait = "RabbicCleric",

		spawnBiomes = { "Hallow" },
		spawnWeight = 0.8,
		packSize = NumberRange.new(1, 2),

		speed = 9,
		aggroRange = 60,
		giveUpRange = 100,
		despawnSeconds = 35,

		contactRange = 3.5,
		contactDamage = 4,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 34,
		maxHopDistance = 6,
		maxHopSpeed = 10,
		groundedSeconds = 0.3,
		windupSeconds = 0.15,

		sizeVariance = 0.08,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 34,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 10,
		lungeWindup = 0.5,
		lungeDamage = 4,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(240, 176, 96),
	},

	--[[
		A small swamp fish on eight legs, in little schools: scurries in,
		snapping, and leaps the last few blocks jaws-first; a missed leap
		leaves it flopping (see its trait). The lunge numbers ARE the leap -
		the trait winds it up itself - and the hop is for climbing a step.
	]]
	FootedPiranha = {
		asset = "FootedPiranha",
		displayName = "Footed Piranha",
		health = 16,
		movement = "Hop",
		trait = "FootedPiranha",

		spawnBiomes = { "Swamp" },
		packSize = NumberRange.new(2, 4),

		speed = 13,
		aggroRange = 55,
		giveUpRange = 95,
		despawnSeconds = 30,

		contactRange = 2.6,
		contactDamage = 4,
		contactInterval = 0.8,

		gravity = 120,
		jumpPower = 32,
		maxHopDistance = 6,
		maxHopSpeed = 12,
		groundedSeconds = 0.1,
		windupSeconds = 0.08,

		sizeVariance = 0.15,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 30,
		lungeMaxDistance = 11,
		lungeMaxSpeed = 22,
		lungeWindup = 0.3,
		lungeDamage = 8,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(40, 104, 208),
	},

	--[[
		A robed bear mage of the snow: holds the middle distance, raises its
		staff and erupts frost spikes under and beside you, and bonks you with
		the staff up close (see its trait). Tough and slow. The Hop numbers
		are only for climbing a step.
	]]
	BearidWizard = {
		asset = "BearidWizard",
		displayName = "Bearid Wizard",
		health = 100,
		movement = "Hop",
		trait = "BearidWizard",

		spawnBiomes = { "Snow" },
		spawnWeight = 0.7,
		packSize = NumberRange.new(1, 1),

		speed = 5.5,
		aggroRange = 60,
		giveUpRange = 100,
		despawnSeconds = 40,

		contactRange = 4,
		contactDamage = 6,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 36,
		maxHopDistance = 6,
		maxHopSpeed = 9,
		groundedSeconds = 0.2,
		windupSeconds = 0.15,

		sizeVariance = 0.06,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 36,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 9,
		lungeWindup = 0.5,
		lungeDamage = 6,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(120, 80, 44),
	},

	--[[
		PIT DEVIL - the Crimson's duelist: blinks to your side in a burst of
		fire and cleaves with its halberd, hurls spears of fire from range
		(ServerScriptService.Creatures.PitDevil; its rig is
		Shared.Enemies.CreatureRigs.PitDevil). Hop movement is only for steps
		its walk cannot take.
	]]
	PitDevil = {
		asset = "PitDevil",
		displayName = "Pit Devil",
		health = 85,
		movement = "Hop",
		trait = "PitDevil",

		spawnBiomes = { "Crimson" },
		spawnWeight = 0.6,
		packSize = NumberRange.new(1, 1),

		speed = 8,
		aggroRange = 60,
		giveUpRange = 100,
		despawnSeconds = 40,

		contactRange = 3.5,
		contactDamage = 5,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 36,
		maxHopDistance = 6,
		maxHopSpeed = 10,
		groundedSeconds = 0.15,
		windupSeconds = 0.1,

		sizeVariance = 0.06,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 36,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 10,
		lungeWindup = 0.5,
		lungeDamage = 5,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(200, 50, 40),
	},

	--[[
		CRAB MONSTER - the Swamp's wall: claws up in a guard that takes most of
		a blow from in front, scuttling sideways as it closes, and a pinch that
		holds you (ServerScriptService.Creatures.CrabMonster; its rig is
		Shared.Enemies.CreatureRigs.CrabMonster). Tough, slow, few: hit it from
		the side, or when it opens its claws.
	]]
	CrabMonster = {
		asset = "CrabMonster",
		displayName = "Crab Monster",
		health = 110,
		movement = "Hop",
		trait = "CrabMonster",

		spawnBiomes = { "Swamp" },
		spawnWeight = 0.5,
		packSize = NumberRange.new(1, 1),

		speed = 5,
		aggroRange = 50,
		giveUpRange = 90,
		despawnSeconds = 40,

		contactRange = 3.5,
		contactDamage = 5,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 34,
		maxHopDistance = 5,
		maxHopSpeed = 8,
		groundedSeconds = 0.2,
		windupSeconds = 0.15,

		sizeVariance = 0.06,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 34,
		lungeMaxDistance = 5,
		lungeMaxSpeed = 8,
		lungeWindup = 0.5,
		lungeDamage = 5,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(150, 60, 110),
	},

	--[[
		LONGLEG - the Corruption's stalker: frozen while anyone faces it,
		loping fast the moment nobody does, and done waiting after a few
		seconds of being stared at - it shrieks and dashes in. Its long-necked
		strike reaches well past arm's length
		(ServerScriptService.Creatures.Longleg; its rig is
		Shared.Enemies.CreatureRigs.Longleg).
	]]
	Longleg = {
		asset = "Longleg",
		displayName = "Longleg",
		health = 70,
		movement = "Hop",
		trait = "Longleg",

		spawnBiomes = { "Corruption" },
		spawnWeight = 0.5,
		packSize = NumberRange.new(1, 1),

		speed = 10,
		aggroRange = 60,
		giveUpRange = 110,
		despawnSeconds = 40,

		contactRange = 3.5,
		contactDamage = 5,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 38,
		maxHopDistance = 7,
		maxHopSpeed = 12,
		groundedSeconds = 0.1,
		windupSeconds = 0.1,

		sizeVariance = 0.08,

		stepUpBlocks = 2,
		scanUpBlocks = 3,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 38,
		lungeMaxDistance = 7,
		lungeMaxSpeed = 12,
		lungeWindup = 0.5,
		lungeDamage = 5,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(70, 90, 130),
	},

	--[[
		OGRE BRUTE - the Desert's heavy: a two-axe overhead chop, a whirlwind
		that leaves it dizzy, and its own axe thrown out and caught again
		(ServerScriptService.Creatures.OgreBrute; its rig is
		Shared.Enemies.CreatureRigs.OgreBrute). Slow and very tough.
	]]
	OgreBrute = {
		asset = "OgreBrute",
		displayName = "Ogre Brute",
		health = 160,
		movement = "Hop",
		trait = "OgreBrute",

		spawnBiomes = { "Desert" },
		spawnWeight = 0.5,
		packSize = NumberRange.new(1, 1),

		speed = 5,
		aggroRange = 55,
		giveUpRange = 95,
		despawnSeconds = 40,

		contactRange = 3.8,
		contactDamage = 6,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 34,
		maxHopDistance = 5,
		maxHopSpeed = 8,
		groundedSeconds = 0.25,
		windupSeconds = 0.15,

		sizeVariance = 0.05,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 34,
		lungeMaxDistance = 5,
		lungeMaxSpeed = 8,
		lungeWindup = 0.5,
		lungeDamage = 6,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(90, 100, 50),
	},

	--[[
		BLACK CAT MAGICIAN - the Hallow's trickster: keeps its distance and
		fires wand bolts, vanishes in smoke when you close in, and splits into
		three round you with smoke and mirrors - two of them decoys
		(ServerScriptService.Creatures.CatMagician; its rig is
		Shared.Enemies.CreatureRigs.CatMagician).
	]]
	CatMagician = {
		asset = "CatMagician",
		displayName = "Black Cat Magician",
		health = 60,
		movement = "Hop",
		trait = "CatMagician",

		spawnBiomes = { "Hallow" },
		spawnWeight = 0.5,
		packSize = NumberRange.new(1, 1),

		speed = 7,
		aggroRange = 50,
		giveUpRange = 90,
		despawnSeconds = 40,

		contactRange = 3,
		contactDamage = 4,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 36,
		maxHopDistance = 6,
		maxHopSpeed = 10,
		groundedSeconds = 0.15,
		windupSeconds = 0.1,

		sizeVariance = 0,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 36,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 10,
		lungeWindup = 0.5,
		lungeDamage = 4,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(60, 70, 120),
	},

	--[[
		GOAT SHAMAN - the Snow's weather-worker: lobs fire orbs from range and
		calls a blizzard down where you stand, chanting while it lasts; hit it
		hard enough and the chant breaks (ServerScriptService.Creatures.
		GoatShaman; its rig is Shared.Enemies.CreatureRigs.GoatShaman).
	]]
	GoatShaman = {
		asset = "GoatShaman",
		displayName = "Goat Shaman",
		health = 75,
		movement = "Hop",
		trait = "GoatShaman",

		spawnBiomes = { "Snow" },
		spawnWeight = 0.6,
		packSize = NumberRange.new(1, 1),

		speed = 6,
		aggroRange = 50,
		giveUpRange = 90,
		despawnSeconds = 40,

		contactRange = 3.2,
		contactDamage = 4,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 36,
		maxHopDistance = 6,
		maxHopSpeed = 9,
		groundedSeconds = 0.15,
		windupSeconds = 0.1,

		sizeVariance = 0.06,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 36,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 9,
		lungeWindup = 0.5,
		lungeDamage = 4,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(150, 70, 50),
	},

	--[[
		TIGER BLADEMASTER - the Plains' swordsman: a counter stance that
		parries any blow and answers with a dash through you, a dash slash
		from range, and a double cut up close
		(ServerScriptService.Creatures.TigerBlademaster; its rig is
		Shared.Enemies.CreatureRigs.TigerBlademaster).
	]]
	TigerBlademaster = {
		asset = "TigerBlademaster",
		displayName = "Tiger Blademaster",
		health = 95,
		movement = "Hop",
		trait = "TigerBlademaster",

		spawnBiomes = { "Plains" },
		spawnWeight = 0.4,
		packSize = NumberRange.new(1, 1),

		speed = 8,
		aggroRange = 55,
		giveUpRange = 95,
		despawnSeconds = 40,

		contactRange = 3.2,
		contactDamage = 5,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 38,
		maxHopDistance = 6,
		maxHopSpeed = 11,
		groundedSeconds = 0.1,
		windupSeconds = 0.1,

		sizeVariance = 0.05,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 38,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 11,
		lungeWindup = 0.5,
		lungeDamage = 11,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(220, 124, 12),
	},

	--[[
		ZOMBIE RAT - the Corruption's pack vermin that will not stay dead: a
		rotting bite that keeps hurting, and a first death that does not take
		- it collapses, then gets back up unless finished while it is down
		(ServerScriptService.Creatures.ZombieRat; its rig is
		Shared.Enemies.CreatureRigs.ZombieRat).
	]]
	ZombieRat = {
		asset = "ZombieRat",
		displayName = "Zombie Rat",
		health = 22,
		movement = "Hop",
		trait = "ZombieRat",

		spawnBiomes = { "Corruption" },
		spawnWeight = 0.8,
		packSize = NumberRange.new(2, 4),

		speed = 6.5,
		aggroRange = 45,
		giveUpRange = 85,
		despawnSeconds = 40,

		contactRange = 2.5,
		contactDamage = 3,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 34,
		maxHopDistance = 5,
		maxHopSpeed = 8,
		groundedSeconds = 0.2,
		windupSeconds = 0.1,

		sizeVariance = 0.1,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 34,
		lungeMaxDistance = 5,
		lungeMaxSpeed = 8,
		lungeWindup = 0.5,
		lungeDamage = 3,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(90, 110, 60),
	},

	--[[
		LAVA GOLEM - the Crimson's walking hazard: slow and enormously tough,
		it leaves burning magma pools in its tracks and sends a line of
		eruptions across the ground at you
		(ServerScriptService.Creatures.LavaGolem; its rig is
		Shared.Enemies.CreatureRigs.LavaGolem).
	]]
	LavaGolem = {
		asset = "LavaGolem",
		displayName = "Lava Golem",
		health = 200,
		movement = "Hop",
		trait = "LavaGolem",

		spawnBiomes = { "Crimson" },
		spawnWeight = 0.35,
		packSize = NumberRange.new(1, 1),

		speed = 4.5,
		aggroRange = 50,
		giveUpRange = 90,
		despawnSeconds = 40,

		contactRange = 3.8,
		contactDamage = 7,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 32,
		maxHopDistance = 4,
		maxHopSpeed = 7,
		groundedSeconds = 0.3,
		windupSeconds = 0.2,

		sizeVariance = 0.05,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 32,
		lungeMaxDistance = 4,
		lungeMaxSpeed = 7,
		lungeWindup = 0.5,
		lungeDamage = 7,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(255, 110, 30),
	},

	--[[
		BAT MUTANT - the Desert's skirmisher: erratic bounds off to one side or
		the other, a screech in a cone that hurts and slows, and a bite
		(ServerScriptService.Creatures.BatMutant; its rig is
		Shared.Enemies.CreatureRigs.BatMutant).
	]]
	BatMutant = {
		asset = "BatMutant",
		displayName = "Bat Mutant",
		health = 45,
		movement = "Hop",
		trait = "BatMutant",

		spawnBiomes = { "Desert" },
		spawnWeight = 0.7,
		packSize = NumberRange.new(1, 2),

		speed = 7,
		aggroRange = 50,
		giveUpRange = 90,
		despawnSeconds = 40,

		contactRange = 2.8,
		contactDamage = 4,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 38,
		maxHopDistance = 6,
		maxHopSpeed = 10,
		groundedSeconds = 0.1,
		windupSeconds = 0.1,

		sizeVariance = 0.08,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 38,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 10,
		lungeWindup = 0.5,
		lungeDamage = 4,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(150, 90, 60),
	},

	--[[
		ROOSTER - the Plains' rabble-rouser: its crow makes every creature
		nearby hit half again as hard for a while; on its own it pecks and
		flutters at you - once you have hit it: it is an animal, and
		passive until provoked (ServerScriptService.Creatures.Rooster; its rig is
		Shared.Enemies.CreatureRigs.Rooster). Fragile - kill it first.
	]]
	Rooster = {
		asset = "Rooster",
		displayName = "Rooster",
		health = 30,
		movement = "Hop",
		trait = "Rooster",
		-- An animal: it leaves you alone until you hit it.
		passive = true,

		spawnBiomes = { "Plains" },
		spawnWeight = 0.6,
		packSize = NumberRange.new(1, 1),

		speed = 9,
		aggroRange = 45,
		giveUpRange = 85,
		despawnSeconds = 40,

		contactRange = 2.4,
		contactDamage = 3,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 40,
		maxHopDistance = 8,
		maxHopSpeed = 13,
		groundedSeconds = 0.1,
		windupSeconds = 0.1,

		sizeVariance = 0.08,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 40,
		lungeMaxDistance = 10,
		lungeMaxSpeed = 15,
		lungeWindup = 0.3,
		lungeDamage = 5,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(140, 72, 28),
	},

	--[[
		AUROCH - a wild bull of the Plains, in herds. An animal, so passive
		until hurt; hurt one and the whole herd near it comes for you, pawing
		and charging like the Pentasaurus (ServerScriptService.Creatures.
		Auroch; its rig is the Pentasaurus's, Shared.Enemies.CreatureRigs).
	]]
	Auroch = {
		asset = "Auroch",
		displayName = "Auroch",
		health = 80,
		movement = "Hop",
		trait = "Auroch",
		-- An animal: it leaves you alone until you hit it.
		passive = true,

		spawnBiomes = { "Plains" },
		spawnWeight = 0.7,
		packSize = NumberRange.new(2, 4),

		speed = 6,
		aggroRange = 50,
		giveUpRange = 90,
		despawnSeconds = 40,

		contactRange = 3.5,
		contactDamage = 6,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 36,
		maxHopDistance = 6,
		maxHopSpeed = 9,
		groundedSeconds = 0.2,
		windupSeconds = 0.15,

		sizeVariance = 0.08,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 36,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 9,
		lungeWindup = 0.5,
		lungeDamage = 6,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(110, 70, 40),
	},

	--[[
		LIZARD WARRIOR - the Swamp's duellist: a two-blade combo in front, a
		tail lash for anyone at its back or flank, and a leaping strike
		(ServerScriptService.Creatures.LizardWarrior; its rig is
		Shared.Enemies.CreatureRigs.LizardWarrior).
	]]
	LizardWarrior = {
		asset = "LizardWarrior",
		displayName = "Lizard Warrior",
		health = 85,
		movement = "Hop",
		trait = "LizardWarrior",

		spawnBiomes = { "Swamp" },
		spawnWeight = 0.5,
		packSize = NumberRange.new(1, 2),

		speed = 7.5,
		aggroRange = 50,
		giveUpRange = 90,
		despawnSeconds = 40,

		contactRange = 3,
		contactDamage = 5,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 38,
		maxHopDistance = 7,
		maxHopSpeed = 11,
		groundedSeconds = 0.12,
		windupSeconds = 0.1,

		sizeVariance = 0.06,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 38,
		lungeMaxDistance = 10,
		lungeMaxSpeed = 15,
		lungeWindup = 0.35,
		lungeDamage = 9,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(96, 128, 72),
	},

	--[[
		The magician's smoke-and-mirrors copy. Conjured by the real one only
		(no spawnBiomes, not in Order), the same model, name and size so it
		cannot be told apart, but harmless: no contact damage, its bolts do
		nothing, and any blow pops it (the trait's `guard`). No drops.
	]]
	CatMagicianDecoy = {
		asset = "CatMagician",
		displayName = "Black Cat Magician",
		health = 60,
		movement = "Hop",
		trait = "CatMagician",
		decoy = true,

		speed = 7,
		aggroRange = 50,
		giveUpRange = 90,
		despawnSeconds = 40,

		contactRange = 3,
		contactDamage = 0,
		contactInterval = 1.0,

		gravity = 120,
		jumpPower = 36,
		maxHopDistance = 6,
		maxHopSpeed = 10,
		groundedSeconds = 0.15,
		windupSeconds = 0.1,

		sizeVariance = 0,

		stepUpBlocks = 1,
		scanUpBlocks = 2,
		scanDownBlocks = 8,

		lungeRange = 0,
		lungeJumpPower = 36,
		lungeMaxDistance = 6,
		lungeMaxSpeed = 10,
		lungeWindup = 0.5,
		lungeDamage = 0,
		lungeCooldown = 99,

		hitFlash = "Highlight",
		burstColor = Color3.fromRGB(60, 70, 120),
	},

	--[[
		THE RAINBOW SLIME - the Hallow's rare giant. A slime in every way that
		moves, only far tougher and harder-hitting, and drawn in shifting
		rainbow colours by every client (its trait marks it; see
		ServerScriptService.Creatures.RainbowSlime).

		RARE: `spawnWeight` is its share of the Hallow's rolls against the
		Shrike's 1, so about one Hallow pack in forty is this, and `packSize`
		makes it always come alone. A biome with nothing else in it would roll
		it every time, which is why the weight is relative.

		The model is EnemyAssets.RainbowSlime, the blue slime's mesh scaled up.
		It is already the size it should be, so no size jitter.
	]]
	RainbowSlime = {
		asset = "RainbowSlime",
		displayName = "Rainbow Slime",
		health = 450,
		movement = "Hop",
		trait = "RainbowSlime",

		spawnBiomes = { "Hallow" },
		spawnWeight = 0.025,
		packSize = NumberRange.new(1, 1),

		speed = 10,
		aggroRange = 80,
		giveUpRange = 140,
		despawnSeconds = 45,

		contactRange = 7.5,
		contactDamage = 18,
		contactInterval = 1.0,

		gravity = 110,
		jumpPower = 48,
		maxHopDistance = 18,
		maxHopSpeed = 18,
		groundedSeconds = 0.9,
		windupSeconds = 0.4,

		bounce = true,
		sizeVariance = 0,

		stepUpBlocks = 2,
		scanUpBlocks = 3,
		scanDownBlocks = 8,

		lungeRange = 26,
		lungeJumpPower = 62,
		lungeMaxDistance = 30,
		lungeMaxSpeed = 34,
		lungeWindup = 0.7,
		lungeDamage = 34,
		lungeCooldown = 3.5,

		hitFlash = "Highlight",
		hitFlashColor = Color3.fromRGB(255, 255, 255),
		burstColor = Color3.fromRGB(255, 150, 230),
	},
}

--[[
	AUTHORED ANIMATIONS, for an enemy rigged with an AnimationController
	(ArticulatedRig = true; see EnemyService.prepareModel). Played on the
	server by ServerScriptService.EnemyAnimator.

	Each entry is a placeholder until its animation is published. Publish it
	from the Animation Editor UNDER THE GROUP THAT OWNS THE GAME - an animation
	owned by anyone else will not play here - and replace the placeholder with
	the number from its rbxassetid:// link. A placeholder is skipped with one
	warning, so the enemy still works, just without that move.

	  Hover   looped idle float         priority Idle
	  Lunge   the charge                priority Action
	  Cast    spell windup and release  priority Action
	  Hurt    flinch when hit           priority Action2
	  Death   collapse                  priority Action4

	None of them moves RootPart: animate CoreJoint for a bob or a lean, and
	leave where the boss actually is to its behaviour and PivotTo.
	assets/signus-hallow/roblox/README.md has the publishing steps.
]]
EnemyConfig.Animations = {
	Signus = {
		Hover = "PUBLISH_SIGNUS_HOVER_AND_PASTE_ID",
		Lunge = "PUBLISH_SIGNUS_LUNGE_AND_PASTE_ID",
		Cast = "PUBLISH_SIGNUS_CAST_AND_PASTE_ID",
		Hurt = "PUBLISH_SIGNUS_HURT_AND_PASTE_ID",
		Death = "PUBLISH_SIGNUS_DEATH_AND_PASTE_ID",
	},
}

-- Stable order for anything that lists enemies to a human. The boss last,
-- because /spawn prints this and it is the one you scroll to on purpose.
EnemyConfig.Order = {
	"Ghost", "DemonEye", "BlueSlime", "GreenSlime",
	"SlimeEmperor", "AllSeeingEye", "Signus", "Blightborer",
	"ServantEye", "Blightling",
	"Lasereye", "Snowman", "GreenWasp", "Shrike", "Cobra", "RainbowSlime", "GreenSpider", "EvilRat", "Gorilla", "Pentasaurus", "WormyHorror", "RabbicCleric", "FootedPiranha", "BearidWizard", "PitDevil", "CrabMonster", "Longleg", "OgreBrute", "CatMagician", "GoatShaman", "TigerBlademaster", "ZombieRat", "LavaGolem", "BatMutant", "Rooster", "Auroch", "LizardWarrior",
}

--[[
	The model in `folder` for an `asset` name: the exact name, or failing that
	one that differs only in spaces and capitals - so "Demon Eye" in the
	Explorer still answers to "DemonEye" here.
]]
function EnemyConfig.findAsset(folder: Instance, asset: string): Instance?
	local exact = folder:FindFirstChild(asset)
	if exact then
		return exact
	end

	local wanted = string.lower((string.gsub(asset, "%s", "")))
	for _, child in ipairs(folder:GetChildren()) do
		if string.lower((string.gsub(child.Name, "%s", ""))) == wanted then
			return child
		end
	end
	return nil
end

-- Fails loudly at require time rather than leaving you to work out at runtime
-- why a spawned enemy is sitting still.
function EnemyConfig.validate()
	assert(
		type(EnemyConfig.SizeVariance) == "number"
			and EnemyConfig.SizeVariance >= 0 and EnemyConfig.SizeVariance < 1,
		"[EnemyConfig] SizeVariance must be a fraction between 0 and 1"
	)

	for _, name in ipairs(EnemyConfig.Order) do
		local def = EnemyConfig.Definitions[name]
		assert(def, string.format("[EnemyConfig] '%s' is in Order but has no definition", name))
	end

	for name, def in pairs(EnemyConfig.Definitions) do
		local label = string.format("[EnemyConfig] '%s'", name)

		assert(type(def.asset) == "string" and def.asset ~= "", label .. " needs an asset name")
		assert(type(def.health) == "number" and def.health > 0, label .. " needs positive health")

		--[[
			A creature with a behaviour module is checked no further.

			Everything below this is the built-in movement, and EnemyService
			consults none of it for one that drives itself. Demanding a hop
			speed and a contact interval off a boss that has neither would be
			this file insisting on answers to questions nobody asks - and the
			numbers invented to satisfy it would then look like real ones.
		]]
		if def.behaviour ~= nil then
			assert(
				type(def.behaviour) == "string" and def.behaviour ~= "",
				label .. " has a behaviour that is not a module name"
			)
			continue
		end

		assert(
			def.movement == "Fly" or def.movement == "Hop",
			label .. " has movement '" .. tostring(def.movement) .. "'; expected Fly or Hop"
		)
		assert(type(def.speed) == "number" and def.speed > 0, label .. " needs a positive speed")
		-- Checked before giveUpRange, which compares against it.
		assert(
			type(def.aggroRange) == "number" and def.aggroRange > 0,
			label .. " needs a positive aggroRange"
		)
		assert(
			type(def.contactRange) == "number" and def.contactRange > 0,
			label .. " needs a positive contactRange"
		)
		assert(
			type(def.contactInterval) == "number" and def.contactInterval > 0,
			label .. " needs a positive contactInterval, or it would hit every tick"
		)
		assert(
			def.giveUpRange == nil or def.giveUpRange >= def.aggroRange,
			label .. " gives up closer than it aggros, so it would flicker in and out of chasing"
		)
		-- Below -1 a scale would flip the model inside out; the sane range is
		-- far narrower than that, but this is the bound that matters.
		assert(
			def.sizeVariance == nil
				or (type(def.sizeVariance) == "number" and def.sizeVariance >= 0 and def.sizeVariance < 1),
			label .. " sizeVariance must be a fraction between 0 and 1"
		)

		--[[
			`bounce` on a FLYER is refused rather than ignored.

			The three shapes it drives are crouch, launch and land, and a thing
			that never touches the ground has none of them. Silently doing
			nothing would leave somebody adding the flag to a ghost and staring
			at it, waiting.
		]]
		if def.bounce ~= nil then
			assert(
				type(def.bounce) == "boolean",
				label .. " bounce must be true or false"
			)
			assert(
				not def.bounce or def.movement == "Hop" or def.behaviour ~= nil,
				label .. " has bounce but does not hop; the squash and stretch are a JUMP"
			)
		end

		assert(
			def.bodyPart == nil or type(def.bodyPart) == "string",
			label .. " bodyPart must be the name of a part in the model"
		)
		assert(
			def.trait == nil or (type(def.trait) == "string" and def.trait ~= ""),
			label .. " trait must name a module in ServerScriptService.Creatures"
		)

		if def.movement == "Hop" then
			assert(
				type(def.gravity) == "number" and def.gravity > 0,
				label .. " is a Hop enemy and needs positive gravity, or it never lands"
			)
			assert(
				type(def.jumpPower) == "number" and def.jumpPower > 0,
				label .. " needs a positive jumpPower; the jump is what moves it"
			)
			assert(
				type(def.groundedSeconds) == "number" and def.groundedSeconds >= 0,
				label .. " needs groundedSeconds"
			)
			assert(
				type(def.lungeDamage) == "number" and def.lungeDamage >= def.contactDamage,
				label .. " lunges for less than it does by touch, which makes the lunge a "
					.. "downgrade and the telegraph a lie"
			)
			assert(
				type(def.lungeWindup) == "number" and def.lungeWindup > def.windupSeconds,
				label .. " telegraphs its lunge no longer than an ordinary hop, so there is "
					.. "nothing to read and nothing to dodge"
			)
			assert(
				type(def.stepUpBlocks) == "number" and def.stepUpBlocks >= 0,
				label .. " needs stepUpBlocks, or it cannot decide what is a wall"
			)
			assert(
				type(def.scanUpBlocks) == "number" and def.scanUpBlocks >= def.stepUpBlocks,
				label .. " must scan at least as far up as it can step, or it would never "
					.. "see the ledge it is allowed to climb"
			)
			assert(
				type(def.scanDownBlocks) == "number" and def.scanDownBlocks > 0,
				label .. " needs scanDownBlocks, or it has no ground to find below itself"
			)
		end
	end
end

return EnemyConfig
