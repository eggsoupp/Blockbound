--[[
	CreatureRigs

	Procedural animation for the jointed voxel creatures, run every frame on
	each client by StarterPlayerScripts.CreatureFX for any model in
	workspace.Enemies with a Rig attribute naming an entry here.

	A creature's model is unions on Motor6Ds (assets/voxel-creatures/source/
	BuildWinged.lua, buildJointed), all hinged off an anchored body. Each
	entry gets:

	  setup(rig)        once: rig.joints is name -> Motor6D, rig.body the root;
	                    work out anything per joint (which way a leg points)
	  animate(rig, ctx) every frame; set each joint's Transform
	    ctx.t      seconds, offset per creature so a pack is not in step
	    ctx.dt     frame time
	    ctx.speed  horizontal studs/second the creature is actually moving
	    ctx.pose   the Pose attribute the server sets ("walk", "rear", ...)
	    ctx.blend  0..1 over the pose's first 0.18s: a WEIGHT for easing a
	               held pose in, never a clock for a move
	    ctx.elapsed  seconds since the pose began: the clock for a timed move
	               (see phases)

	Walking is driven by real speed, so a creature that is pushed, knocked or
	sliding steps at the pace it moves, and stands still when it does.

	CreatureFX smooths every joint toward what animate sets, so a pose may
	jump between frames - entering or leaving one - without the model doing.
]]

local Rigs = {}

--[[
	How far into a timed attack a pose is, as two 0..1 phases: `wind` over the
	first `windup` seconds (eased), then `hit` over the `strike` seconds after
	it. `windup` is the trait's own wind-up, so the blow visibly lands at the
	moment the damage does; `strike` is kept short, so it reads as a blow.
]]
local function phases(ctx, windup: number, strike: number): (number, number)
	local elapsed = ctx.elapsed or ctx.blend * 0.18
	local wind = math.clamp(elapsed / windup, 0, 1)
	wind = wind * wind * (3 - 2 * wind)
	return wind, math.clamp((elapsed - windup) / strike, 0, 1)
end

-- The direction from a joint's hinge to the middle of its part, in the
-- body's frame, flattened: which way a leg reaches.
local function reach(rig, joint): Vector3
	local hinge = (rig.body.CFrame * joint.C0).Position
	local offset = rig.body.CFrame:VectorToObjectSpace(joint.Part1.Position - hinge)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
end

-- A leg's pose: `lift` raises it about the axis across it, `swing` turns it
-- forward or back about the vertical.
local function legTransform(direction: Vector3, lift: number, swing: number): CFrame
	local across = direction:Cross(Vector3.yAxis)
	return CFrame.fromAxisAngle(across, lift) * CFrame.Angles(0, swing, 0)
end

--[[
	GREEN SPIDER. Eight legs in two alternating sets - L1, R2, L3, R4 against
	R1, L2, R3, L4 - each set swinging forward raised while the other pushes
	back on the ground. The stride runs off speed; standing, the legs only
	shift a little. Rearing lifts the front pair high and the second pair a
	little (the pounce and web tell); leaping stretches every leg back.
]]
Rigs.GreenSpider = {
	setup = function(rig)
		rig.legs = {}
		for name, joint in pairs(rig.joints) do
			local side = string.sub(name, 1, 1)
			local index = tonumber(string.sub(name, 2))
			if index then
				local set = if (side == "L") == (index % 2 == 1) then 0 else math.pi
				table.insert(rig.legs, { joint = joint, index = index, side = side, set = set, direction = reach(rig, joint) })
			end
		end
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local moving = math.clamp(ctx.speed / 8, 0, 1)
		-- Studs per full step cycle: shorter than you would think, so it scurries.
		rig.stride += ctx.dt * ctx.speed / 2.2 * math.pi * 2

		for _, leg in ipairs(rig.legs) do
			local phase = rig.stride + leg.set
			local swing = math.sin(phase) * 0.38 * moving
			local lift = math.max(0, math.cos(phase)) * 0.5 * moving
			-- Standing: a slow, uneven shifting so it never looks dead.
			lift += math.sin(ctx.t * 2.3 + leg.index * 1.7 + leg.set) * 0.04 * (1 - moving)

			if ctx.pose == "rear" then
				local raised = if leg.index == 1 then 1.0 elseif leg.index == 2 then 0.45 else -0.08
				local reachOut = if leg.index == 1 then 0.25 else 0
				lift = lift + (raised - lift) * ctx.blend + math.sin(ctx.t * 22 + leg.index) * 0.05 * ctx.blend
				swing = swing + (reachOut - swing) * ctx.blend
			elseif ctx.pose == "leap" then
				lift = lift + (0.25 - lift) * ctx.blend
				swing = swing + ((if leg.index <= 2 then -0.35 else 0.35) - swing) * ctx.blend
			end

			-- Left and right legs swing the opposite way about the vertical
			-- for the same step, since they point opposite ways.
			local mirrored = if leg.side == "L" then -swing else swing
			leg.joint.Transform = legTransform(leg.direction, lift, mirrored)
		end
	end,
}

--[[
	EVIL RAT. A trot: diagonal pairs (front-left with back-right) swing
	together about the hip, the head nods twice a stride and the tail whips
	side to side behind. Standing, it sniffs - quick little head lifts - and
	the tail curls lazily. Biting drives the head down and forward;
	scurrying off ("flee") is just a faster trot with the tail held high.
	Legs hang down from their hips, so a positive pitch about X swings the
	foot forward (the model faces -Z).
]]
Rigs.EvilRat = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local moving = math.clamp(ctx.speed / 7, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 1.6 * math.pi * 2
		local s = rig.stride

		local swing = math.sin(s) * 0.75 * moving
		j.FL.Transform = CFrame.Angles(swing, 0, 0)
		j.BR.Transform = CFrame.Angles(swing, 0, 0)
		j.FR.Transform = CFrame.Angles(-swing, 0, 0)
		j.BL.Transform = CFrame.Angles(-swing, 0, 0)

		local nod = math.sin(s * 2) * 0.08 * moving
		local sniff = (1 - moving) * math.max(0, math.sin(ctx.t * 9)) * 0.12 * (if math.sin(ctx.t * 0.7) > 0.3 then 1 else 0)
		local headPitch = nod + sniff
		local headYaw = (1 - moving) * math.sin(ctx.t * 1.3) * 0.25
		if ctx.pose == "bite" then
			headPitch += (-0.55 - headPitch) * ctx.blend
			headYaw *= 1 - ctx.blend
		end
		j.Head.Transform = CFrame.Angles(headPitch, headYaw, 0)

		local whip = math.sin(s * 1 + 1) * 0.45 * moving + math.sin(ctx.t * 1.8) * 0.3 * (1 - moving)
		local raise = if ctx.pose == "flee" then 0.35 else 0.1 * moving
		j.Tail.Transform = CFrame.Angles(raise, whip, 0)
	end,
}

--[[
	PIT DEVIL. A horned imp carrying a halberd crossways at its waist. It
	prowls on quick short steps, head cocked, the halberd bobbing. Its moves:
	  swing  the halberd turned about the vertical so the blade sweeps from
	         its side round to the front - a cleave
	  throw  the right arm hauled back and flung forward (the spear it throws
	         is fire, drawn separately)
	The halberd hangs off the right hand on its own joint: yaw about Y turns
	its blade end (+X) toward the front (-Z).
]]
Rigs.PitDevil = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 6, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 2.2 * math.pi * 2
		local s = rig.stride

		local step = math.sin(s) * 0.5 * moving
		j.LeftLeg.Transform = CFrame.Angles(step, 0, 0)
		j.RightLeg.Transform = CFrame.Angles(-step, 0, 0)

		local left = CFrame.Angles(-step * 0.5, 0, 0)
		local right = CFrame.Angles(step * 0.3, 0, 0)
		local weapon = CFrame.Angles(0, 0, math.sin(s * 2) * 0.04 * moving)
		-- A twitchy head: short jerks rather than a smooth sway.
		local head = CFrame.Angles(0, math.sin(math.floor(ctx.t * 2.5) * 1.7) * 0.25, math.sin(ctx.t * 1.1) * 0.12)

		if ctx.pose == "swing" then
			-- Both hands on the shaft: the halberd hauled up overhead, level,
			-- then chopped down in front. It rides the arms; turning it about
			-- the right fist would only swing the shaft, the blade being right
			-- there at the fist.
			local wind, hit = phases(ctx, 0.26, 0.12)
			local raise = 2.5 * wind - 1.7 * hit
			right = CFrame.Angles(raise, 0, 0)
			left = CFrame.Angles(raise, 0, -0.1 * wind)
			weapon = CFrame.Angles(0, 0, -0.15 * wind * (1 - hit))
			head = CFrame.Angles(-0.25 * wind + 0.35 * hit, 0, 0)
		elseif ctx.pose == "throw" then
			-- The right arm cocked back over the shoulder and flung forward;
			-- the fire spear leaves at the fling (Creatures.PitDevil).
			local wind, hit = phases(ctx, 0.45, 0.12)
			right = CFrame.Angles(2.6 * wind - 2.2 * hit, 0, 0.2 * wind)
			left = CFrame.Angles(0.7 * wind - 0.3 * hit, 0, -0.3 * wind)
			head = CFrame.Angles(-0.15 * wind + 0.2 * hit, 0, 0)
		elseif ctx.pose == "blink" then
			right = CFrame.Angles(0.4, 0, 0.4)
			left = CFrame.Angles(0.4, 0, -0.4)
		end

		j.LeftArm.Transform = left
		j.RightArm.Transform = right
		j.Weapon.Transform = weapon
		j.Head.Transform = head
	end,
}

--[[
	BEARID WIZARD. A heavy, robed bear: a short-stepping waddle with the
	head rolling side to side, arms swinging a little. Its moves:
	  channel  staff (right arm) raised overhead, left paw lifted - the
	           frost-spike tell
	  slam     the staff driven down to set the spikes off
	  bonk     the staff swung over and down at whoever is close
	Arms and legs hang from their joints: positive pitch swings them forward
	(far enough, up and over the head).
]]
Rigs.BearidWizard = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 4, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 2.4 * math.pi * 2
		local s = rig.stride

		local step = math.sin(s) * 0.35 * moving
		j.LeftLeg.Transform = CFrame.Angles(step, 0, 0)
		j.RightLeg.Transform = CFrame.Angles(-step, 0, 0)

		local left = CFrame.Angles(-step * 0.6 + math.sin(ctx.t * 1.2) * 0.04, 0, 0)
		local right = CFrame.Angles(step * 0.4, 0, 0)
		local head = CFrame.Angles(math.sin(ctx.t * 0.9) * 0.05, 0, math.sin(s) * 0.08 * moving)

		if ctx.pose == "channel" then
			right = right:Lerp(CFrame.Angles(2.7, 0, -0.15), b)
			left = left:Lerp(CFrame.Angles(1.6 + math.sin(ctx.t * 9) * 0.06, 0, 0.35), b)
			head = head:Lerp(CFrame.Angles(-0.3, 0, 0), b)
		elseif ctx.pose == "slam" then
			right = right:Lerp(CFrame.Angles(0.5, 0, 0), math.min(1, b * 2))
			left = left:Lerp(CFrame.Angles(0.8, 0, 0.2), b)
			head = head:Lerp(CFrame.Angles(0.25, 0, 0), b)
		elseif ctx.pose == "bonk" then
			-- Up over the shoulder through the wind-up, then over and down.
			local wind, hit = phases(ctx, 0.32, 0.1)
			right = CFrame.Angles(0.2 + 2.3 * wind - 2.1 * hit, 0, 0)
			head = CFrame.Angles(-0.1 * wind + 0.2 * hit, 0, 0)
		end

		j.LeftArm.Transform = left
		j.RightArm.Transform = right
		j.Head.Transform = head
	end,
}

--[[
	FOOTED PIRANHA. An upright fish on eight stubby legs that patter in two
	alternating sets (L1, R2, L3, R4 against the rest), its tail fin
	waggling side to side the whole time. Its moves:
	  chomp  the jaw snapping, close to you
	  leap   jaw wide open, legs trailing, tail flicked up
	  flop   a landing on its side - the body is placed by the server; here
	         the legs kick and the jaw gapes
	Legs hang from their joints (positive pitch swings them forward); the
	jaw hinges at the back of the mouth (positive pitch opens it).
]]
Rigs.FootedPiranha = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 6, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 1.2 * math.pi * 2

		for i = 1, 4 do
			local set = if i % 2 == 1 then 0 else math.pi
			local left = math.sin(rig.stride + set) * 0.7 * moving
			local right = math.sin(rig.stride + set + math.pi) * 0.7 * moving
			if ctx.pose == "leap" then
				left += (-0.6 - left) * b
				right += (-0.6 - right) * b
			elseif ctx.pose == "flop" then
				left = math.sin(ctx.t * 30 + i) * 0.6
				right = math.sin(ctx.t * 30 + i + 1) * 0.6
			end
			j["L" .. i].Transform = CFrame.Angles(left, 0, 0)
			j["R" .. i].Transform = CFrame.Angles(right, 0, 0)
		end

		local waggle = math.sin(ctx.t * (6 + 8 * moving)) * (0.25 + 0.2 * moving)
		local flick = if ctx.pose == "leap" then 0.4 * b else 0
		j.Tail.Transform = CFrame.Angles(flick, waggle, 0)

		local jaw = 0.05 + math.max(0, math.sin(ctx.t * 4)) * 0.08
		if ctx.pose == "chomp" then
			jaw = math.max(0, math.sin(ctx.t * 22)) * 0.55
		elseif ctx.pose == "leap" then
			jaw += (0.7 - jaw) * b
		elseif ctx.pose == "flop" then
			jaw = 0.35 + math.sin(ctx.t * 12) * 0.2
		end
		j.Jaw.Transform = CFrame.Angles(jaw, 0, 0)
	end,
}

--[[
	RABBIC CLERIC. A robed rabbit that bounds rather than walks: its legs
	tuck while it is in the air and its great ears stream back as it rises
	and flop up as it falls (worked out here from how fast the model is
	actually going up or down). Standing, the ears twitch now and then and
	the head tilts. Its moves:
	  cast   the staff (right arm) thrust forward, left hand raised
	  heal   both arms up, staff held high
	Arms and legs hang from their joints: positive pitch about X swings them
	forward. The ears stick out sideways: rolling the left one by -angle and
	the right by +angle lifts both tips.
]]
Rigs.RabbicCleric = {
	setup = function(rig)
		rig.lastY = rig.body.Position.Y
		rig.vertical = 0
		rig.twitchAt = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local y = rig.body.Position.Y
		local rise = (y - rig.lastY) / math.max(ctx.dt, 1e-3)
		rig.lastY = y
		rig.vertical += (rise - rig.vertical) * math.min(1, ctx.dt * 12)
		local airborne = math.abs(rig.vertical) > 1.5

		-- Ears: back and down while rising, up while falling, and a twitch now and then.
		local earLift = math.clamp(-rig.vertical * 0.05, -0.5, 0.6)
		if ctx.t > rig.twitchAt then
			rig.twitchAt = ctx.t + 1.5 + (ctx.t * 7.3 % 2.5)
			rig.twitchUntil = ctx.t + 0.18
		end
		local twitch = if rig.twitchUntil and ctx.t < rig.twitchUntil then 0.25 else 0
		j.LeftEar.Transform = CFrame.Angles(0, 0, -(earLift + twitch))
		j.RightEar.Transform = CFrame.Angles(0, 0, earLift + twitch * 0.4)

		local tuck = if airborne then 0.7 else 0
		j.LeftLeg.Transform = CFrame.Angles(tuck, 0, 0)
		j.RightLeg.Transform = CFrame.Angles(tuck * 0.85, 0, 0)

		local left = CFrame.Angles(math.sin(ctx.t * 1.4) * 0.05 + (if airborne then -0.3 else 0), 0, 0)
		local right = CFrame.Angles(math.sin(ctx.t * 1.4 + 1) * 0.05, 0, 0)
		local head = CFrame.Angles(0, 0, math.sin(ctx.t * 0.7) * 0.12)
		if ctx.pose == "cast" then
			right = right:Lerp(CFrame.Angles(1.1, 0, 0), b)
			left = left:Lerp(CFrame.Angles(0.9, 0, 0.2), b)
			head = head:Lerp(CFrame.Angles(-0.1, 0, 0), b)
		elseif ctx.pose == "heal" then
			right = right:Lerp(CFrame.Angles(2.6, 0, -0.2), b)
			left = left:Lerp(CFrame.Angles(2.4, 0, 0.3), b)
			head = head:Lerp(CFrame.Angles(-0.35, 0, 0), b)
		end
		j.LeftArm.Transform = left
		j.RightArm.Transform = right
		j.Head.Transform = head
	end,
}

--[[
	WORMY HORROR. Four long arched legs off a hanging body: a slow stilt-walk
	on diagonal pairs (front-left with back-right), each leg lifted as it
	swings forward, and a mouth that never quite stops working. Its moves:
	  rear   the two front legs raised high and reaching - the impale tell
	  stab   the front legs driven down and forward
	  spit   the mouth thrown up, then forward
]]
Rigs.WormyHorror = {
	setup = function(rig)
		rig.legs = {}
		for name, set in pairs({ FL = 0, BR = 0, FR = math.pi, BL = math.pi }) do
			local joint = rig.joints[name]
			if joint then
				table.insert(rig.legs, {
					joint = joint, set = set, front = string.sub(name, 1, 1) == "F",
					left = string.sub(name, 2, 2) == "L", direction = reach(rig, joint),
				})
			end
		end
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local moving = math.clamp(ctx.speed / 5, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 4.5 * math.pi * 2
		local b = ctx.blend

		for _, leg in ipairs(rig.legs) do
			local phase = rig.stride + leg.set
			local swing = math.sin(phase) * 0.3 * moving
			local lift = math.max(0, math.cos(phase)) * 0.35 * moving
			lift += math.sin(ctx.t * 1.3 + leg.set + (if leg.front then 0 else 2)) * 0.03 * (1 - moving)

			if leg.front and ctx.pose == "rear" then
				lift += (0.85 + math.sin(ctx.t * 18) * 0.05 - lift) * b
				swing += (0.35 - swing) * b
			elseif leg.front and ctx.pose == "stab" then
				lift += (-0.3 - lift) * b
				swing += (0.45 - swing) * b
			end

			leg.joint.Transform = legTransform(leg.direction, lift, if leg.left then -swing else swing)
		end

		local head = rig.joints.Head
		if head then
			local gnash = math.sin(ctx.t * 5) * 0.08
			local pitch = gnash
			if ctx.pose == "spit" then
				pitch += (-0.45 - pitch) * b
			elseif ctx.pose == "stab" then
				pitch += (0.2 - pitch) * b
			end
			head.Transform = CFrame.Angles(pitch, math.sin(ctx.t * 0.8) * 0.15, 0)
		end
	end,
}

--[[
	PENTASAURUS. A heavy four-legged walk on diagonal pairs, the frilled head
	swinging a little and the tail swaying behind. Its moves:
	  paw      head down, one front foot scraping at the ground - the charge tell
	  charge   a fast gallop, head lowered, horns forward
	  stunned  after a wall: head shaking, legs splayed, swaying
	  gore     the head tossed up hard, horns first
]]
Rigs.Pentasaurus = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local galloping = ctx.pose == "charge"
		local moving = math.clamp(ctx.speed / 5, 0, 1)
		rig.stride += ctx.dt * ctx.speed / (if galloping then 5 else 3) * math.pi * 2
		local s = rig.stride

		local swing = math.sin(s) * (if galloping then 0.8 else 0.45) * moving
		local fl, fr, bl, br = swing, -swing, -swing, swing
		if galloping then
			-- A gallop pairs the front legs and the back legs.
			fl, fr, bl, br = swing, swing * 0.8, -swing, -swing * 0.8
		end

		local headPitch = math.sin(s * 2) * 0.05 * moving
		local headYaw = math.sin(s) * 0.08 * moving + math.sin(ctx.t * 0.9) * 0.12 * (1 - moving)
		local tailYaw = math.sin(s + 1) * 0.3 * moving + math.sin(ctx.t * 1.4) * 0.2 * (1 - moving)
		local tailPitch = 0

		-- The head hangs forward of its hinge, so a negative pitch lowers it.
		if ctx.pose == "paw" then
			-- Head down; the right front foot scrapes back and forth.
			headPitch += (-0.35 - headPitch) * b
			headYaw *= 1 - b
			fr = fr + (math.sin(ctx.t * 11) * 0.7 - 0.2 - fr) * b
			tailPitch = 0.3 * b
		elseif galloping then
			headPitch += (-0.3 - headPitch) * b
			headYaw *= 0.3
			tailPitch = 0.25 * b
		elseif ctx.pose == "stunned" then
			headYaw = math.sin(ctx.t * 13) * 0.35 * b
			headPitch = 0.2 * b
			fl, fr = -0.25 * b, 0.25 * b
			bl, br = 0.15 * b, -0.15 * b
		elseif ctx.pose == "gore" then
			-- Head dipped, then the horns tossed up through you.
			local wind, hit = phases(ctx, 0.14, 0.1)
			headPitch = -0.4 * wind + 1.0 * hit
		end

		local splay = if ctx.pose == "stunned" then 0.18 * b else 0
		j.FL.Transform = CFrame.Angles(fl, 0, -splay)
		j.FR.Transform = CFrame.Angles(fr, 0, splay)
		j.BL.Transform = CFrame.Angles(bl, 0, -splay)
		j.BR.Transform = CFrame.Angles(br, 0, splay)
		j.Head.Transform = CFrame.Angles(headPitch, headYaw, 0)
		j.Tail.Transform = CFrame.Angles(tailPitch, tailYaw, 0)
	end,
}

--[[
	GORILLA. A knuckle-walk: each arm swings with the opposite leg, big and
	slow, the head rolling a little with the gait. Standing it breathes - the
	arms sway out and in. Its moves:
	  pound   arms up in front, beating the chest in turn - the warning
	  leap    both arms flung up overhead, in the air
	  slam    both fists driven down in front, on landing
	  swipe   one arm swung across, up close
	Arms and legs hang from their joints, so a positive pitch about X swings
	the hand or foot forward; roll about Z swings an arm out or in.
]]
Rigs.Gorilla = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local moving = math.clamp(ctx.speed / 6, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 4 * math.pi * 2
		local s = rig.stride
		local b = ctx.blend

		local armSwing = math.sin(s) * 0.55 * moving
		local legSwing = math.sin(s) * 0.45 * moving
		local breathe = math.sin(ctx.t * 1.6) * 0.06 * (1 - moving)

		local left = CFrame.Angles(armSwing, 0, -breathe)
		local right = CFrame.Angles(-armSwing, 0, breathe)
		local head = CFrame.Angles(math.sin(s * 2) * 0.05 * moving, math.sin(s) * 0.12 * moving, 0)

		if ctx.pose == "pound" then
			-- Raised in front and beating the chest in turn.
			local beat = math.sin(ctx.t * 14)
			left = left:Lerp(CFrame.Angles(1.5 + beat * 0.35, 0.3, 0.55), b)
			right = right:Lerp(CFrame.Angles(1.5 - beat * 0.35, -0.3, -0.55), b)
			head = head:Lerp(CFrame.Angles(-0.35, 0, 0), b)
		elseif ctx.pose == "leap" then
			left = left:Lerp(CFrame.Angles(2.8, 0, -0.25), b)
			right = right:Lerp(CFrame.Angles(2.8, 0, 0.25), b)
			head = head:Lerp(CFrame.Angles(-0.2, 0, 0), b)
		elseif ctx.pose == "slam" then
			left = left:Lerp(CFrame.Angles(0.9, 0, 0.2), b)
			right = right:Lerp(CFrame.Angles(0.9, 0, -0.2), b)
			head = head:Lerp(CFrame.Angles(0.25, 0, 0), b)
		elseif ctx.pose == "swipe" then
			-- The right arm drawn up and out to the side, then swung across.
			local wind, hit = phases(ctx, 0.27, 0.12)
			right = CFrame.Angles(1.2 * wind, -0.9 * wind + 1.3 * hit, -1.1 * wind + 1.8 * hit)
			head = CFrame.Angles(0, -0.2 * wind + 0.3 * hit, 0)
		end

		j.LeftArm.Transform = left
		j.RightArm.Transform = right
		j.LeftLeg.Transform = CFrame.Angles(-legSwing, 0, 0)
		j.RightLeg.Transform = CFrame.Angles(legSwing, 0, 0)
		j.Head.Transform = head
	end,
}

--[[
	CRAB MONSTER. A crab-man on two legs with a pincer on each forearm. Its
	moves:
	  scuttle  sideways, the legs rocking out to the sides instead of striding
	  guard    both claws raised crossed in front of its face - the shell it
	           hides behind (ServerScriptService.Creatures.CrabMonster)
	  pinch    claws thrown wide, then snapped together in front
	  hold     claws clamped together forward, shaking whoever is in them
	Idle, the claws clack now and then.
]]
Rigs.CrabMonster = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 5, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 2.5 * math.pi * 2
		local s = rig.stride

		local legL, legR
		if ctx.pose == "scuttle" then
			local rock = math.sin(s) * 0.35 * moving
			legL = CFrame.Angles(0, 0, -math.max(0, rock))
			legR = CFrame.Angles(0, 0, math.max(0, -rock))
		else
			local step = math.sin(s) * 0.4 * moving
			legL = CFrame.Angles(step, 0, 0)
			legR = CFrame.Angles(-step, 0, 0)
		end

		-- A clack every couple of seconds: both claws twitch up together.
		local clack = math.max(0, math.sin(ctx.t * 3)) ^ 12 * 0.35
		local armL = CFrame.Angles(0.15 + math.sin(s) * 0.15 * moving, 0, 0)
		local armR = CFrame.Angles(0.15 - math.sin(s) * 0.15 * moving, 0, 0)
		local clawL = CFrame.Angles(clack, 0, 0)
		local clawR = CFrame.Angles(clack, 0, 0)
		local head = CFrame.Angles(0, math.sin(ctx.t * 0.9) * 0.15, 0)
		local tail = CFrame.Angles(0, math.sin(ctx.t * 2 + s) * 0.3, 0)

		if ctx.pose == "guard" or ctx.pose == "scuttle" then
			-- Raised and turned in so the pincers cross in front of the face.
			local k = if ctx.pose == "guard" then b else 1
			armL = armL:Lerp(CFrame.Angles(0.9, 0, 0), k)
			armR = armR:Lerp(CFrame.Angles(0.9, 0, 0), k)
			clawL = clawL:Lerp(CFrame.Angles(0.5, -0.55, 0), k)
			clawR = clawR:Lerp(CFrame.Angles(0.5, 0.55, 0), k)
			head = head:Lerp(CFrame.Angles(0.2, 0, 0), k)
		elseif ctx.pose == "pinch" then
			-- Thrown wide through the wind-up, then snapped shut in front.
			local open, snap = phases(ctx, 0.5, 0.08)
			armL = CFrame.Angles(0.4 + 0.4 * snap, 0, 0)
			armR = CFrame.Angles(0.4 + 0.4 * snap, 0, 0)
			clawL = CFrame.Angles(0.2, 0.8 * open - 1.1 * snap, 0)
			clawR = CFrame.Angles(0.2, -0.8 * open + 1.1 * snap, 0)
			head = CFrame.Angles(-0.25 * open + 0.3 * snap, 0, 0)
		elseif ctx.pose == "hold" then
			local shake = math.sin(ctx.t * 30) * 0.08
			armL = CFrame.Angles(0.8 + shake, 0, 0)
			armR = CFrame.Angles(0.8 - shake, 0, 0)
			clawL = CFrame.Angles(0.2, -0.3, 0)
			clawR = CFrame.Angles(0.2, 0.3, 0)
			head = CFrame.Angles(0.3, 0, 0)
		end

		j.LeftLeg.Transform = legL
		j.RightLeg.Transform = legR
		j.LeftArm.Transform = armL
		j.RightArm.Transform = armR
		j.LeftClaw.Transform = clawL
		j.RightClaw.Transform = clawR
		j.Head.Transform = head
		j.Tail.Transform = tail
	end,
}

--[[
	LONGLEG. A hunched thing on four stilts with its head slung low in front.
	It lopes on diagonal pairs (front-left with back-right), the long legs
	swinging wide. Its moves:
	  frozen  dead still - being watched - except for the odd sudden twitch
	          of the head, snapped to a new angle rather than turned
	  shriek  head thrown up and legs braced wide
	  dash    legs stretched fore and aft, head low
	  strike  head reared up, then lashed forward and down
	The head's hinge sits at the neck, so +pitch lifts it and -pitch dips it.
]]
Rigs.Longleg = {
	setup = function(rig)
		rig.stride = 0
		rig.twitch = CFrame.identity
		rig.twitchAt = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 8, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 6 * math.pi * 2
		local s = rig.stride

		local swing = math.sin(s) * 0.55 * moving
		local fl, br = CFrame.Angles(swing, 0, 0), CFrame.Angles(swing, 0, 0)
		local fr, bl = CFrame.Angles(-swing, 0, 0), CFrame.Angles(-swing, 0, 0)
		local head = CFrame.Angles(math.sin(s * 2) * 0.12 * moving - 0.05, math.sin(ctx.t * 0.7) * 0.2 * (1 - moving), 0)

		if ctx.pose == "frozen" then
			if ctx.t >= rig.twitchAt then
				rig.twitchAt = ctx.t + 0.6 + math.random() * 1.6
				rig.twitch = CFrame.Angles((math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.9, (math.random() - 0.5) * 0.8)
			end
			fl, fr, bl, br = CFrame.identity, CFrame.identity, CFrame.identity, CFrame.identity
			head = rig.twitch
		elseif ctx.pose == "shriek" then
			local shake = math.sin(ctx.t * 40) * 0.06
			head = CFrame.Angles(0.9 * b + shake, 0, shake)
			fl = CFrame.Angles(0.15, 0, 0.25 * b)
			fr = CFrame.Angles(0.15, 0, -0.25 * b)
			bl = CFrame.Angles(-0.15, 0, 0.25 * b)
			br = CFrame.Angles(-0.15, 0, -0.25 * b)
		elseif ctx.pose == "dash" then
			local gallop = math.sin(ctx.t * 22) * 0.35
			fl = CFrame.Angles(0.7 + gallop, 0, 0)
			fr = CFrame.Angles(0.7 - gallop, 0, 0)
			bl = CFrame.Angles(-0.7 - gallop, 0, 0)
			br = CFrame.Angles(-0.7 + gallop, 0, 0)
			head = CFrame.Angles(-0.3, 0, 0)
		elseif ctx.pose == "strike" then
			-- Reared up through the wind-up, then lashed down.
			local rear, lash = phases(ctx, 0.42, 0.1)
			head = CFrame.Angles(0.7 * rear - 1.3 * lash, 0, 0)
			fl = CFrame.Angles(-0.2 * rear + 0.4 * lash, 0, 0)
			fr = CFrame.Angles(-0.2 * rear + 0.4 * lash, 0, 0)
		end

		j.FrontLeftLeg.Transform = fl
		j.FrontRightLeg.Transform = fr
		j.BackLeftLeg.Transform = bl
		j.BackRightLeg.Transform = br
		j.Head.Transform = head
	end,
}

--[[
	OGRE BRUTE. A broad ogre with a double axe hanging from each fist. It
	lumbers, the axes swinging heavy. Its moves:
	  chop     both axes hauled up overhead, then brought down together
	  windup   arms flung out to the sides, axes level - the whirlwind's tell
	  spin     the same, held, while the server turns the whole body
	  dizzy    arms hanging slack, head lolling
	  throw    right arm cocked back, then flung forward; the axe itself
	           leaves the hand (ServerScriptService.Creatures.OgreBrute)
	A sideways raise is a roll about Z: negative for the left arm, positive for
	the right.
]]
Rigs.OgreBrute = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 5, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 3.5 * math.pi * 2
		local s = rig.stride

		local swing = math.sin(s) * 0.4 * moving
		local left = CFrame.Angles(-swing, 0, -0.08)
		local right = CFrame.Angles(swing, 0, 0.08)
		local axeL = CFrame.Angles(swing * 0.4, 0, 0)
		local axeR = CFrame.Angles(-swing * 0.4, 0, 0)
		local head = CFrame.Angles(0, 0, math.sin(s) * 0.06 * moving)

		if ctx.pose == "chop" then
			-- Hauled up overhead through the wind-up, then down hard.
			local up, down = phases(ctx, 0.6, 0.12)
			local raise = 2.8 * up - 2.3 * down
			left = CFrame.Angles(raise, 0, 0.15 * up)
			right = CFrame.Angles(raise, 0, -0.15 * up)
			axeL = CFrame.Angles(0.4 * up, 0, 0)
			axeR = CFrame.Angles(0.4 * up, 0, 0)
			head = CFrame.Angles(-0.2 * up + 0.35 * down, 0, 0)
		elseif ctx.pose == "windup" or ctx.pose == "spin" then
			local k = if ctx.pose == "windup" then b else 1
			local wobble = if ctx.pose == "spin" then math.sin(ctx.t * 20) * 0.05 else 0
			left = left:Lerp(CFrame.Angles(0, 0, -1.45 + wobble), k)
			right = right:Lerp(CFrame.Angles(0, 0, 1.45 - wobble), k)
			axeL = axeL:Lerp(CFrame.Angles(0, 0, 0.3), k)
			axeR = axeR:Lerp(CFrame.Angles(0, 0, -0.3), k)
			head = head:Lerp(CFrame.Angles(-0.3, 0, 0), k)
		elseif ctx.pose == "dizzy" then
			left = CFrame.Angles(-0.1, 0, 0.1)
			right = CFrame.Angles(-0.1, 0, -0.1)
			head = CFrame.Angles(0.25, math.sin(ctx.t * 3) * 0.3, math.cos(ctx.t * 3) * 0.25)
		elseif ctx.pose == "throw" then
			local back, fling = phases(ctx, 0.5, 0.12)
			right = CFrame.Angles(2.7 * back - 2.0 * fling, 0, 0.3 * back)
			left = CFrame.Angles(0.5 * back, 0, -0.2)
			head = CFrame.Angles(-0.15 * back + 0.2 * fling, 0, 0)
		elseif ctx.pose == "catch" then
			right = CFrame.Angles(1.1, 0, 0.2)
			head = CFrame.Angles(-0.1, 0, 0)
		end

		local step = math.sin(s) * 0.35 * moving
		j.LeftLeg.Transform = CFrame.Angles(step, 0, 0)
		j.RightLeg.Transform = CFrame.Angles(-step, 0, 0)
		j.LeftArm.Transform = left
		j.RightArm.Transform = right
		j.LeftAxe.Transform = axeL
		j.RightAxe.Transform = axeR
		j.Head.Transform = head
	end,
}

--[[
	BLACK CAT MAGICIAN. A cat in a top hat with a long wand through its right
	fist. It walks on dainty steps, tail swaying. Its moves:
	  cast   the wand arm raised to point, a little flourish, then held level
	  trick  both arms flung up and out, head back - the smoke and mirrors
	The decoys it conjures are the same model and the same animation.
]]
Rigs.CatMagician = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 5, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 2 * math.pi * 2
		local s = rig.stride

		local step = math.sin(s) * 0.5 * moving
		local left = CFrame.Angles(-step * 0.6, 0, -0.1)
		local right = CFrame.Angles(0.3, 0, 0.05)
		local wand = CFrame.Angles(math.sin(ctx.t * 1.3) * 0.1, 0, 0)
		local head = CFrame.Angles(0, math.sin(ctx.t * 0.8) * 0.2, math.sin(ctx.t * 1.6) * 0.08)
		local tail = CFrame.Angles(math.sin(ctx.t * 2.2) * 0.15, 0, math.sin(ctx.t * 1.4 + s) * 0.35)

		if ctx.pose == "cast" then
			-- The wand raised to point through the wind-up, then flicked
			-- forward as the bolt leaves.
			local wind, hit = phases(ctx, 0.4, 0.12)
			local flourish = math.sin(hit * math.pi) * 0.4
			right = CFrame.Angles(0.3 + 1.0 * wind + flourish, 0, 0.1)
			wand = CFrame.Angles(-0.3 * wind + 0.5 * hit, 0, 0)
			head = CFrame.Angles(0.1 * wind, 0, 0)
		elseif ctx.pose == "trick" then
			local k = math.min(1, b * 2)
			left = CFrame.Angles(0.3 * k, 0, -2.2 * k)
			right = CFrame.Angles(0.3 * k, 0, 2.2 * k)
			head = CFrame.Angles(-0.35 * k, 0, 0)
			tail = CFrame.Angles(0.4 * k, 0, math.sin(ctx.t * 12) * 0.3)
		end

		j.LeftLeg.Transform = CFrame.Angles(step, 0, 0)
		j.RightLeg.Transform = CFrame.Angles(-step, 0, 0)
		j.LeftArm.Transform = left
		j.RightArm.Transform = right
		j.Wand.Transform = wand
		j.Head.Transform = head
		j.Tail.Transform = tail
	end,
}

--[[
	GOAT SHAMAN. A robed goat with a long staff held level in its right hand,
	an orange orb at the tip. It shuffles, the staff bobbing. Its moves:
	  lob    the staff swung up and forward, flinging the orb's fire
	  chant  the staff raised upright and shaken, head thrown back, the other
	         arm up - calling the blizzard, and held as long as it lasts
	  jab    the staff thrust straight forward
	The staff's hinge is the right fist: +pitch tips its tip (forward, -Z)
	upward.
]]
Rigs.GoatShaman = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 5, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 2.2 * math.pi * 2
		local s = rig.stride

		local step = math.sin(s) * 0.35 * moving
		local left = CFrame.Angles(-step * 0.5, 0, -0.05)
		local right = CFrame.Angles(0.1, 0, 0.05)
		local staff = CFrame.Angles(math.sin(s * 2) * 0.05 * moving, 0, 0)
		local head = CFrame.Angles(math.sin(ctx.t * 1.1) * 0.06, math.sin(ctx.t * 0.6) * 0.2, 0)

		if ctx.pose == "lob" then
			-- The staff tipped up through the wind-up, then whipped forward
			-- past level as the orb's fire is flung.
			local up, fling = phases(ctx, 0.45, 0.14)
			right = CFrame.Angles(0.7 * up - 0.2 * fling, 0, 0)
			staff = CFrame.Angles(1.3 * up - 1.6 * fling, 0, 0)
			head = CFrame.Angles(-0.15 * up + 0.15 * fling, 0, 0)
		elseif ctx.pose == "chant" then
			local k = math.min(1, b * 2.5)
			local shake = math.sin(ctx.t * 18) * 0.06
			right = CFrame.Angles(0.9 * k + shake, 0, 0.15 * k)
			staff = CFrame.Angles(1.45 * k, 0, shake)
			left = CFrame.Angles(1.6 * k, 0, -0.5 * k)
			head = CFrame.Angles(-0.45 * k, math.sin(ctx.t * 4) * 0.15, 0)
		elseif ctx.pose == "jab" then
			-- Drawn back, then thrust straight out.
			local wind, hit = phases(ctx, 0.22, 0.1)
			right = CFrame.Angles(-0.25 * wind + 0.55 * hit, 0, 0)
			staff = CFrame.new(0, 0, 0.5 * wind - 1.3 * hit)
		end

		j.LeftLeg.Transform = CFrame.Angles(step, 0, 0)
		j.RightLeg.Transform = CFrame.Angles(-step, 0, 0)
		j.LeftArm.Transform = left
		j.RightArm.Transform = right
		j.Staff.Transform = staff
		j.Head.Transform = head
	end,
}

--[[
	TIGER BLADEMASTER. A caped tiger whose crossed arms and crossed swords
	are one piece, hinged at the chest. It stalks upright. Its moves:
	  stance  the crossed blades lifted level, an X held out across its chest,
	          utterly still but for a slow breath - the counter stance
	  crouch  low, blades drawn back, before a dash
	  dash    leaning in, blades back
	  slash   the crossed blades swept across, side to side
	+pitch on the blades lifts them toward its face; yaw sweeps them across.
]]
Rigs.TigerBlademaster = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 6, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 3 * math.pi * 2
		local s = rig.stride

		local step = math.sin(s) * 0.45 * moving
		local legL, legR = CFrame.Angles(step, 0, 0), CFrame.Angles(-step, 0, 0)
		local blades = CFrame.Angles(math.sin(ctx.t * 1.5) * 0.04, math.sin(s) * 0.08 * moving, 0)
		local head = CFrame.Angles(0, math.sin(ctx.t * 0.7) * 0.15, 0)

		if ctx.pose == "stance" then
			local k = math.min(1, b * 3)
			-- Lifted level and held out, the crossed blades an X across its
			-- chest.
			blades = CFrame.new(0, 0.3 * k, -0.2 * k) * CFrame.Angles(1.5 * k + math.sin(ctx.t * 2) * 0.03, 0, 0)
			head = CFrame.Angles(0.1 * k, 0, 0)
			legL = CFrame.Angles(0.35 * k, 0, 0)
			legR = CFrame.Angles(-0.35 * k, 0, 0)
		elseif ctx.pose == "crouch" then
			local k = math.min(1, b * 3)
			blades = CFrame.Angles(-0.6 * k, 0, 0)
			head = CFrame.Angles(0.25 * k, 0, 0)
			legL = CFrame.Angles(0.6 * k, 0, 0)
			legR = CFrame.Angles(-0.5 * k, 0, 0)
		elseif ctx.pose == "dash" then
			local stride = math.sin(ctx.t * 26) * 0.7
			blades = CFrame.Angles(-0.8, 0, 0)
			head = CFrame.Angles(0.2, 0, 0)
			legL = CFrame.Angles(stride, 0, 0)
			legR = CFrame.Angles(-stride, 0, 0)
		elseif ctx.pose == "slash" then
			-- The crossed blades lifted level in front and drawn to its right,
			-- swept across to the left (the first cut, at 0.25s), then back
			-- across to the right (the second, at 0.55s) - Creatures.
			-- TigerBlademaster's cutTimes.
			local e = ctx.elapsed or 0
			local lift = math.clamp(e / 0.15, 0, 1)
			local yaw
			if e < 0.17 then
				yaw = -0.9 * lift
			elseif e < 0.29 then
				yaw = -0.9 + 1.9 * (e - 0.17) / 0.12
			elseif e < 0.47 then
				yaw = 1.0
			elseif e < 0.59 then
				yaw = 1.0 - 1.9 * (e - 0.47) / 0.12
			else
				yaw = -0.9
			end
			blades = CFrame.Angles(0, yaw, 0) * CFrame.Angles(1.35 * lift, 0, 0)
			head = CFrame.Angles(0, yaw * 0.3, 0)
		end

		j.LeftLeg.Transform = legL
		j.RightLeg.Transform = legR
		j.Blades.Transform = blades
		j.Head.Transform = head
	end,
}

--[[
	ZOMBIE RAT. A hunched, rotting rat on its hind legs, front paws dangling.
	It shambles - a lurching, uneven gait, head lolling - and its moves are:
	  bite  head lunged forward and down, paws up
	  down  collapsed: everything slack, the head on the ground, the odd
	        twitch (its first death, which does not take)
	  rise  dragged back up, jerking
]]
Rigs.ZombieRat = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 6, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 1.8 * math.pi * 2
		local s = rig.stride

		-- A lurch: the stride's halves are not even.
		local lurch = (math.sin(s) + 0.4 * math.sin(s * 2)) * 0.55 * moving
		local back = CFrame.Angles(lurch, 0, 0)
		local backR = CFrame.Angles(-lurch, 0, 0)
		local paws = CFrame.Angles(0.2 + math.sin(ctx.t * 2.3) * 0.15, 0, 0)
		local pawsR = CFrame.Angles(0.2 + math.sin(ctx.t * 2.3 + 1) * 0.15, 0, 0)
		local head = CFrame.Angles(math.sin(s) * 0.1 * moving, 0, math.sin(ctx.t * 1.1) * 0.3)
		local tail = CFrame.Angles(-0.1, math.sin(ctx.t * 1.6 + s) * 0.35, 0)

		if ctx.pose == "bite" then
			-- Head pulled back, paws up, then lunged forward and down.
			local wind, hit = phases(ctx, 0.27, 0.08)
			head = CFrame.Angles(0.3 * wind - 0.9 * hit, 0, 0)
			paws = CFrame.Angles(0.9 * wind, 0, 0)
			pawsR = paws
		elseif ctx.pose == "down" then
			local twitch = if math.sin(ctx.t * 7) > 0.92 then 0.2 else 0
			head = CFrame.Angles(-0.7 + twitch, 0, 0.5)
			paws = CFrame.Angles(-0.6, 0, 0.3)
			pawsR = CFrame.Angles(-0.5 + twitch, 0, -0.3)
			back = CFrame.Angles(0.6, 0, 0.3)
			backR = CFrame.Angles(0.6, 0, -0.3)
			tail = CFrame.Angles(-0.4, 0.3, 0)
		elseif ctx.pose == "rise" then
			local jerk = math.sin(ctx.t * 25) * 0.15
			head = CFrame.Angles(0.4 + jerk, jerk, 0)
			paws = CFrame.Angles(1.2, 0, 0.4)
			pawsR = CFrame.Angles(1.2, 0, -0.4)
		end

		j.BL.Transform = back
		j.BR.Transform = backR
		j.FL.Transform = paws
		j.FR.Transform = pawsR
		j.Head.Transform = head
		j.Tail.Transform = tail
	end,
}

--[[
	LAVA GOLEM. A hulking block of cooled rock with lava in the cracks. It
	plods - short heavy steps, arms swinging stiffly - and its moves are:
	  slam   both fists raised high, then driven down into the ground
	  punch  the right fist drawn back and thrown
]]
Rigs.LavaGolem = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 4, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 3 * math.pi * 2
		local s = rig.stride

		local step = math.sin(s) * 0.3 * moving
		local left = CFrame.Angles(-step, 0, -0.05)
		local right = CFrame.Angles(step, 0, 0.05)
		local head = CFrame.Angles(math.sin(ctx.t * 0.8) * 0.05, math.sin(ctx.t * 0.5) * 0.12, 0)

		if ctx.pose == "slam" then
			local up, down = phases(ctx, 0.85, 0.12)
			left = CFrame.Angles(2.9 * up - 2.6 * down, 0, 0.25 * up)
			right = CFrame.Angles(2.9 * up - 2.6 * down, 0, -0.25 * up)
			head = CFrame.Angles(-0.2 * up + 0.35 * down, 0, 0)
		elseif ctx.pose == "punch" then
			local back, throw = phases(ctx, 0.5, 0.1)
			right = CFrame.Angles(-0.6 * back + 2.1 * throw, 0, 0)
			left = CFrame.Angles(0.3 * back, 0, -0.1)
			head = CFrame.Angles(0.1 * throw, 0, 0)
		end

		j.LeftLeg.Transform = CFrame.Angles(step, 0, 0)
		j.RightLeg.Transform = CFrame.Angles(-step, 0, 0)
		j.LeftArm.Transform = left
		j.RightArm.Transform = right
		j.Head.Transform = head
	end,
}

--[[
	BAT MUTANT. A wingless bat on two short legs, all ears and teeth, with
	stub arms. It scurries, ears twitching. Its moves:
	  crouch   squatting before a bound
	  bound    legs tucked, arms flung out, in the air
	  screech  head thrown back, then thrust forward with the arms spread
	  bite     head snapped forward and down
]]
Rigs.BatMutant = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 6, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 1.4 * math.pi * 2
		local s = rig.stride

		local step = math.sin(s) * 0.6 * moving
		local legL, legR = CFrame.Angles(step, 0, 0), CFrame.Angles(-step, 0, 0)
		local left = CFrame.Angles(-step * 0.4, 0, -0.1)
		local right = CFrame.Angles(step * 0.4, 0, 0.1)
		-- Ears twitch: the head flicks now and then.
		local flick = if math.sin(ctx.t * 5.3) > 0.95 then 0.15 else 0
		local head = CFrame.Angles(flick, math.sin(ctx.t * 1.2) * 0.2, math.sin(ctx.t * 0.9) * 0.08)

		if ctx.pose == "crouch" then
			local k = math.min(1, b * 3)
			legL = CFrame.Angles(0.7 * k, 0, 0)
			legR = CFrame.Angles(0.7 * k, 0, 0)
			head = CFrame.Angles(0.2 * k, 0, 0)
		elseif ctx.pose == "bound" then
			legL = CFrame.Angles(-0.6, 0, 0)
			legR = CFrame.Angles(-0.6, 0, 0)
			left = CFrame.Angles(0.3, 0, -1.2)
			right = CFrame.Angles(0.3, 0, 1.2)
		elseif ctx.pose == "screech" then
			local back, thrust = phases(ctx, 0.45, 0.1)
			local shake = math.sin(ctx.t * 45) * 0.05 * thrust
			head = CFrame.Angles(-0.6 * back + 0.9 * thrust + shake, 0, shake)
			left = CFrame.Angles(0.5 * thrust, 0, -1.3 * thrust)
			right = CFrame.Angles(0.5 * thrust, 0, 1.3 * thrust)
		elseif ctx.pose == "bite" then
			local wind, hit = phases(ctx, 0.17, 0.08)
			head = CFrame.Angles(-0.25 * wind + 0.6 * hit, 0, 0)
		end

		j.LeftLeg.Transform = legL
		j.RightLeg.Transform = legR
		j.LeftArm.Transform = left
		j.RightArm.Transform = right
		j.Head.Transform = head
	end,
}

--[[
	ROOSTER. A big, belligerent cockerel. It struts - the head jerking
	forward and back with each step, the way a bird's does - and its moves:
	  crow     chest out, head thrown up, wings spread and beating
	  peck     the head stabbing down and forward, fast, over and over
	  flutter  wings flapping hard, legs tucked - a flapping leap
	Wings hinge along the flank: a roll about Z lifts them away from the body
	(negative for the left, positive for the right).
]]
Rigs.Rooster = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local b = ctx.blend
		local moving = math.clamp(ctx.speed / 6, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 1.6 * math.pi * 2
		local s = rig.stride

		local step = math.sin(s) * 0.6 * moving
		local legL, legR = CFrame.Angles(step, 0, 0), CFrame.Angles(-step, 0, 0)
		-- The bob: head thrust forward on one half of the stride, back on the
		-- other, sharply rather than smoothly.
		local bob = (if math.sin(s * 2) > 0 then 1 else -1) * 0.12 * moving
		local head = CFrame.new(0, 0, -bob) * CFrame.Angles(0, math.sin(ctx.t * 1.7) * 0.3 * (1 - moving), 0)
		local wingL, wingR = CFrame.identity, CFrame.identity
		local tail = CFrame.Angles(math.sin(ctx.t * 1.3) * 0.05, 0, 0)

		if ctx.pose == "crow" then
			local k = math.min(1, b * 3)
			local beat = math.sin(ctx.t * 22) * 0.4 * k
			head = CFrame.Angles(0.7 * k, 0, 0)
			wingL = CFrame.Angles(0, 0, -(0.9 * k + beat))
			wingR = CFrame.Angles(0, 0, 0.9 * k + beat)
			tail = CFrame.Angles(0.3 * k, 0, 0)
		elseif ctx.pose == "peck" then
			local stab = math.max(0, math.sin(ctx.t * 24))
			head = CFrame.new(0, -0.2 * stab, -0.35 * stab) * CFrame.Angles(-0.8 * stab, 0, 0)
		elseif ctx.pose == "flutter" then
			local beat = math.sin(ctx.t * 30) * 0.6
			wingL = CFrame.Angles(0, 0, -(0.8 + beat))
			wingR = CFrame.Angles(0, 0, 0.8 + beat)
			legL = CFrame.Angles(-0.5, 0, 0)
			legR = CFrame.Angles(-0.5, 0, 0)
			head = CFrame.Angles(0.2, 0, 0)
		end

		j.LeftLeg.Transform = legL
		j.RightLeg.Transform = legR
		j.LeftWing.Transform = wingL
		j.RightWing.Transform = wingR
		j.Head.Transform = head
		j.Tail.Transform = tail
	end,
}


--[[
	LIZARD WARRIOR. A lizard on two legs with a sickle raised in its right
	hand, a second blade low in its left, and a long tail. It stalks, tail
	swaying. Its moves:
	  combo  the right sickle hooked back over the shoulder through the wind-up
	         and chopped down (Creatures.LizardWarrior comboWindup), then the
	         left blade swept across low (comboSecond)
	  sweep  the tail lashed round behind it
	  leap   both blades raised, legs tucked, in the air
	The right arm is held UP, so on it +pitch draws the sickle back over the
	shoulder and -pitch brings it forward and down; the left hangs, the other
	way round.
]]
Rigs.LizardWarrior = {
	setup = function(rig)
		rig.stride = 0
	end,

	animate = function(rig, ctx)
		local j = rig.joints
		local moving = math.clamp(ctx.speed / 6, 0, 1)
		rig.stride += ctx.dt * ctx.speed / 2.4 * math.pi * 2
		local s = rig.stride

		local step = math.sin(s) * 0.55 * moving
		local legL, legR = CFrame.Angles(step, 0, 0), CFrame.Angles(-step, 0, 0)
		local right = CFrame.Angles(math.sin(ctx.t * 1.4) * 0.05, 0, 0)
		local left = CFrame.Angles(-step * 0.4, 0, 0)
		local head = CFrame.Angles(0, math.sin(ctx.t * 0.8) * 0.25, 0)
		local tail = CFrame.Angles(0, math.sin(ctx.t * 1.7 + s) * 0.35, 0)

		if ctx.pose == "combo" then
			local wind, hit = phases(ctx, 0.35, 0.1)
			local second = math.clamp(((ctx.elapsed or 0) - 0.62) / 0.12, 0, 1)
			right = CFrame.Angles(0.7 * wind - 2.3 * hit, 0, 0)
			left = CFrame.Angles(0.5 * wind, -0.9 * wind + 1.8 * second, 0)
			head = CFrame.Angles(0.15 * hit, -0.3 * second, 0)
		elseif ctx.pose == "sweep" then
			local wind, hit = phases(ctx, 0.25, 0.15)
			tail = CFrame.Angles(0.15, -0.9 * wind + 2.6 * hit, 0)
			head = CFrame.Angles(0, 0.4 * wind - 0.4 * hit, 0)
		elseif ctx.pose == "leap" then
			right = CFrame.Angles(0.5, 0, 0)
			left = CFrame.Angles(1.2, 0, -0.3)
			legL = CFrame.Angles(0.6, 0, 0)
			legR = CFrame.Angles(-0.4, 0, 0)
			tail = CFrame.Angles(0.35, 0, 0)
		end

		j.LeftLeg.Transform = legL
		j.RightLeg.Transform = legR
		j.RightArm.Transform = right
		j.LeftArm.Transform = left
		j.Head.Transform = head
		j.Tail.Transform = tail
	end,
}

-- The auroch is a bull built like the Pentasaurus - four legs on the same
-- joints, a horned head, a tail - and fights the same way
-- (Creatures.Auroch), so it moves the same way too.
Rigs.Auroch = Rigs.Pentasaurus

return Rigs
