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

return Rigs
