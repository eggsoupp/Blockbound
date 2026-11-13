--[[
	CastPose: a short procedural pose on a caster's body, for abilities that
	have no published animation.

	A pose is { JointName = CFrame } in each joint's own frame (the joint's
	Transform), for the R15 joints by name (Root, Waist, Neck, LeftShoulder,
	LeftElbow, LeftHip, LeftKnee, ...). Joints a pose leaves out stay as the
	animation has them. Works on Motor6D and AnimationConstraint rigs alike.

	Keys are { at = seconds, w = 0..1, pose = pose }: between two keys the pose
	and its weight ease (smoothstep) from one to the next, and the result is
	laid over whatever the Animator wrote this frame by that weight. Before the
	first key and after the last, nothing is touched.

	Written in PreSimulation: the Animator sets Transform before that, and
	anything written there is what the frame shows. Every client runs the VFX
	module that calls this, so everyone sees the same pose on the caster.

	R15 directions, for authoring (the joint frames are the parts' own):
	  +X on a shoulder lifts the arm forward; +Z lifts the RIGHT arm out to
	  its side, -Z the left; +X on an elbow bends the forearm up; +X on a hip
	  lifts the knee; -X on a knee folds the shin back; +X on the waist or
	  neck leans back / looks up.
]]
local RunService = game:GetService("RunService")

local CastPose = {}

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function joints(character)
	local found = {}
	for _, d in ipairs(character:GetDescendants()) do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and found[d.Name] == nil then
			found[d.Name] = d
		end
	end
	return found
end

-- The pose and weight at `t`, or nil outside the keys.
function CastPose.sample(keys, t)
	local first, last = keys[1], keys[#keys]
	if not first or t < first.at or t > last.at then
		return nil, 0
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.at then
			local u = smooth((t - a.at) / math.max(b.at - a.at, 1e-3))
			return {a = a.pose, b = b.pose, u = u}, a.w + (b.w - a.w) * u
		end
	end
	return {a = last.pose, b = last.pose, u = 0}, last.w
end

-- Lays one sampled pose over `found` (from joints()) by `weight`.
function CastPose.apply(found, mix, weight)
	if not mix or weight <= 0 then return end
	local names = {}
	for name in pairs(mix.a) do names[name] = true end
	for name in pairs(mix.b) do names[name] = true end
	for name in pairs(names) do
		local joint = found[name]
		if joint then
			local target = (mix.a[name] or CFrame.identity):Lerp(mix.b[name] or CFrame.identity, mix.u)
			joint.Transform = if weight >= 1 then target else joint.Transform:Lerp(target, weight)
		end
	end
end

CastPose.joints = joints

--[[
	Plays `keys` on `character` on the clock `elapsed()` (seconds since the
	cast began) until the last key or the scope ends.
]]
function CastPose.play(scope, character, keys, elapsed)
	if not character then return end
	local found = joints(character)
	local connection
	connection = scope:add(RunService.PreSimulation:Connect(function()
		local t = elapsed()
		if t > keys[#keys].at or not character.Parent then
			connection:Disconnect()
			return
		end
		local mix, weight = CastPose.sample(keys, t)
		CastPose.apply(found, mix, weight)
	end))
end

-- Shorthands for authoring poses in degrees.
function CastPose.rot(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

-- Lift (about X) first, then swing (about Y): an arm raised forward and then
-- brought across the body.
function CastPose.swing(lift, across, out)
	return CFrame.Angles(0, math.rad(across or 0), 0) * CFrame.Angles(math.rad(lift or 0), 0, math.rad(out or 0))
end

return CastPose
