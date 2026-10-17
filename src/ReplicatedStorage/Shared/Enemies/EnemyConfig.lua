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
		nothing: `/spawn SlimeEmperor` today.

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
}

-- Stable order for anything that lists enemies to a human. The boss last,
-- because /spawn prints this and it is the one you scroll to on purpose.
EnemyConfig.Order = { "Ghost", "DemonEye", "BlueSlime", "GreenSlime", "SlimeEmperor", "AllSeeingEye", "ServantEye" }

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
