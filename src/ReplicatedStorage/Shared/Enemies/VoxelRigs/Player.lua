--[[
	VoxelRigs.Player

	Animation for the code-modelled voxel rigs (assets/voxel-enemies): the
	ten big creatures whose models are unions on chains of Motor6Ds hanging
	off an anchored root (HumanoidRootPart, renamed RootPart in EnemyAssets).

	Each creature module next to this one returns a spec:

	  base(rig, ctx, out)  every frame: the idle and locomotion layer, written
	                       into `out` as joint name -> pose value
	  moves                Pose attribute -> clip: keyframed attacks played
	                       over the base, on ctx.elapsed
	  sockets              named points on parts (a staff tip, a mouth) that
	                       effects follow; see Player.socket

	A POSE VALUE is { rx, ry, rz, px, py, pz }: degrees about the joint's
	axes (applied yaw, then pitch, then roll) and an offset in studs.
	Joint axes are the model's own at rest: +X the creature's right, +Y up,
	front -Z. So +rx swings a hanging limb forward and tips a forward-pointing
	head up; +ry turns toward the creature's left; +rz rolls a right-hand
	limb outward and up. "Root" is the root part's joint to RootPart: its
	offset moves the whole body (a hover bob, a leap's crouch).

	A CLIP is { duration, marks, keys = { { t, pose, ease }, ... }, extra }.
	`ease` shapes the approach to that key: "lin", "in", "out", "io", "back"
	(overshoots, then settles) or "snap" (most of the way at once). Joints a
	clip names are taken over by it; the rest keep the base layer, so a tail
	still sways while the jaws bite. `marks` are the clip's own times for its
	beats (the hit, the release) and the server trait reads the same numbers,
	so damage lands on the frame the blow does. `extra(out, t, ctx, rig)` may
	add a tremble or a spin on top.

	Poses are written with a mirror shorthand: a key starting with "*" is the
	right-hand joint as written and the left-hand one mirrored (ry, rz and px
	negated), so "*UpperArm" covers both arms.
]]

local Player = {}

local RAD = math.pi / 180
local ZERO = { 0, 0, 0, 0, 0, 0 }

local function value(v)
	return { v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0, v[5] or 0, v[6] or 0 }
end

local function mirrored(v)
	return { v[1], -v[2], -v[3], -v[4], v[5], v[6] }
end

-- Expands the "*" shorthand into a plain joint -> value table.
function Player.pose(spec)
	local out = {}
	for name, v in pairs(spec) do
		local full = value(v)
		if string.sub(name, 1, 1) == "*" then
			local joint = string.sub(name, 2)
			out["Right" .. joint] = full
			out["Left" .. joint] = mirrored(full)
		else
			out[name] = full
		end
	end
	return out
end

-- Shapes 0..1 progress into a key.
local EASE = {
	lin = function(a) return a end,
	["in"] = function(a) return a * a * a end,
	out = function(a) return 1 - (1 - a) ^ 3 end,
	io = function(a) return a * a * (3 - 2 * a) end,
	snap = function(a) return 1 - (1 - a) ^ 6 end,
	back = function(a)
		local c = 1.9
		return 1 + (c + 1) * (a - 1) ^ 3 + c * (a - 1) ^ 2
	end,
}
Player.ease = EASE

function Player.clip(spec)
	for _, key in ipairs(spec.keys) do
		key[2] = Player.pose(key[2])
	end
	-- Every joint any key names, so a key leaving one out means "at rest".
	local joints = {}
	for _, key in ipairs(spec.keys) do
		for name in pairs(key[2]) do
			joints[name] = true
		end
	end
	spec.joints = joints
	spec.duration = spec.duration or spec.keys[#spec.keys][1]
	spec.marks = spec.marks or {}
	return spec
end

local function lerp(a, b, t)
	return {
		a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t,
		a[4] + (b[4] - a[4]) * t, a[5] + (b[5] - a[5]) * t, a[6] + (b[6] - a[6]) * t,
	}
end
Player.lerp = lerp

-- The clip's pose at time t (held at the last key once past it).
function Player.sample(clip, t)
	local keys = clip.keys
	local out = {}
	if t <= keys[1][1] then
		for name in pairs(clip.joints) do
			out[name] = keys[1][2][name] or ZERO
		end
		return out
	end
	for i = 2, #keys do
		local prev, key = keys[i - 1], keys[i]
		if t <= key[1] then
			local span = key[1] - prev[1]
			local a = if span > 0 then (t - prev[1]) / span else 1
			local shaped = (EASE[key[3] or "io"] or EASE.io)(a)
			for name in pairs(clip.joints) do
				out[name] = lerp(prev[2][name] or ZERO, key[2][name] or ZERO, shaped)
			end
			return out
		end
	end
	local last = keys[#keys][2]
	for name in pairs(clip.joints) do
		out[name] = last[name] or ZERO
	end
	return out
end

-- Adds b into a (both pose values), in place.
function Player.add(out, name, v)
	local a = out[name]
	if not a then
		out[name] = value(v)
		return
	end
	for i = 1, 6 do
		a[i] += v[i] or 0
	end
end

-- Mirrored add: the right joint as given, the left mirrored.
function Player.addBoth(out, name, v)
	local full = value(v)
	Player.add(out, "Right" .. name, full)
	Player.add(out, "Left" .. name, mirrored(full))
end

local function toCFrame(v, scale)
	return CFrame.new(v[4] * scale, v[5] * scale, v[6] * scale)
		* CFrame.fromEulerAnglesYXZ(v[1] * RAD, v[2] * RAD, v[3] * RAD)
end

--[[
	Locomotion clock: advances rig.stride by the distance actually moved over
	`length` studs per full cycle (scaled with the model), and says how much
	it is moving (0 standing, 1 at `full` studs/second).
]]
function Player.gait(rig, ctx, length, full)
	local scale = rig.scale or 1
	rig.stride = (rig.stride or 0) + ctx.dt * ctx.speed / (length * scale) * math.pi * 2
	return rig.stride, math.clamp(ctx.speed / ((full or 6) * scale), 0, 1)
end

--[[
	A point on a part, from its rest-pose voxel position: `socket` is
	{ part, at = voxel position, pivot = that part's joint pivot (voxels) }.
	World position now, however the rig is posed.
]]
function Player.socket(model, socket, voxel)
	local part = model:FindFirstChild(socket.part)
	if not part then
		return model:GetPivot().Position
	end
	local joint = part:FindFirstChildWhichIsA("Motor6D")
	local scale = model:GetScale()
	local delta = (socket.at - socket.pivot) * voxel * scale
	if joint then
		return (part.CFrame * joint.C1 * CFrame.new(delta)).Position
	end
	return part.Position + delta
end

-- The CreatureRigs entry for a spec.
function Player.rig(spec)
	return {
		setup = function(rig)
			local model = rig.body and rig.body:FindFirstAncestorWhichIsA("Model")
			rig.model = model
			rig.scale = if model then model:GetScale() else 1
			rig.out = {}
			if spec.setup then
				spec.setup(rig)
			end
		end,

		animate = function(rig, ctx)
			local out = rig.out
			table.clear(out)
			spec.base(rig, ctx, out)

			local clip = spec.moves and spec.moves[ctx.pose]
			if clip then
				local t = ctx.elapsed or 0
				local weight = math.clamp(t / (clip.blendIn or 0.1), 0, 1)
				local sampled = Player.sample(clip, t)
				for name, v in pairs(sampled) do
					out[name] = lerp(out[name] or ZERO, v, weight)
				end
				if clip.extra then
					clip.extra(out, t, ctx, rig)
				end
			end

			local scale = rig.scale
			for name, joint in pairs(rig.joints) do
				local v = out[name]
				joint.Transform = if v then toCFrame(v, scale) else CFrame.identity
			end
		end,
	}
end

-- Every creature module in this folder, by name.
function Player.all()
	local found = {}
	for _, module in ipairs(script.Parent:GetChildren()) do
		if module:IsA("ModuleScript") and module ~= script and module.Name ~= "Effects" then
			local ok, spec = pcall(require, module)
			if ok and type(spec) == "table" and spec.base then
				found[module.Name] = spec
			elseif not ok then
				warn("[VoxelRigs] " .. module.Name .. ": " .. tostring(spec))
			end
		end
	end
	return found
end

return Player
