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
	    ctx.blend  0..1, how far into the current pose (eases each change)

	Walking is driven by real speed, so a creature that is pushed, knocked or
	sliding steps at the pace it moves, and stands still when it does.
]]

local Rigs = {}

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

		if ctx.pose == "paw" then
			-- Head down; the right front foot scrapes back and forth.
			headPitch += (0.35 - headPitch) * b
			headYaw *= 1 - b
			fr = fr + (math.sin(ctx.t * 11) * 0.7 - 0.2 - fr) * b
			tailPitch = 0.3 * b
		elseif galloping then
			headPitch += (0.3 - headPitch) * b
			headYaw *= 0.3
			tailPitch = 0.25 * b
		elseif ctx.pose == "stunned" then
			headYaw = math.sin(ctx.t * 13) * 0.35 * b
			headPitch = 0.2 * b
			fl, fr = -0.25 * b, 0.25 * b
			bl, br = 0.15 * b, -0.15 * b
		elseif ctx.pose == "gore" then
			local k = math.sin(math.min(1, b * 1.3) * math.pi)
			headPitch = -0.7 * k
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
			-- The right arm swung out and across.
			local k = math.sin(math.min(1, b * 1.2) * math.pi)
			right = right:Lerp(CFrame.Angles(1.2, -0.9, -1.1 + 1.6 * b), k)
		end

		j.LeftArm.Transform = left
		j.RightArm.Transform = right
		j.LeftLeg.Transform = CFrame.Angles(-legSwing, 0, 0)
		j.RightLeg.Transform = CFrame.Angles(legSwing, 0, 0)
		j.Head.Transform = head
	end,
}

return Rigs
