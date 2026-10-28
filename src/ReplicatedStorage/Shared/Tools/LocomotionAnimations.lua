--[[
	LocomotionAnimations

	The six walks and runs ToolWalk plays: one pair each for swords, lances and
	heavy swords. The sword pair is also the default, for a pickaxe, an axe or
	empty hands. Each is written as a gait - cadence, stride, knee lift, bob,
	lean, twist and how the arms carry the weapon - and sampled into an R15
	KeyframeSequence, so tuning one is changing a number here rather than
	dragging keyframes.

		LocomotionAnimations.build("SwordWalk")      -> KeyframeSequence
		LocomotionAnimations.nameFor("Walk", class)  -> "LanceWalk"
		LocomotionAnimations.preview("LanceWalk")    -> temporary id, Studio only

	PUBLISHING

	A KeyframeSequence is not playable outside Studio until it is uploaded as an
	Animation. Build the six into ServerStorage.LocomotionAnimations, right-click
	each one, Save to Roblox under the group that owns the game, and put the ids
	in ToolConfig.WalkAnimations and RunAnimations. Until then ToolWalk asks
	preview() for a temporary id in Studio, and plays nothing elsewhere.

	CONVENTIONS

	Angles are degrees, applied to each joint as CFrame.Angles(pitch, yaw, roll).
	Positive pitch swings a limb forward; a knee flexes negative, an elbow
	positive; positive roll on an arm lifts it outward (mirrored for the left).
	One cycle is phase 0..1: at 0 the right leg passes under the body moving
	forward, at 0.25 it is fully forward, and the left leg runs half a cycle
	behind.
]]

local LocomotionAnimations = {}

local SAMPLES = 20

--[[
	Arms: pitch/roll/yaw/elbow are the carry pose, swing is how far the arm
	swings forward and back about it, elbowSwing how much more the elbow bends
	at the front of the swing, wrist/wristYaw a fixed hand angle.

	The weapon arm poses were solved against the real weapons on an R15 rig
	(Bloodfang, LightLance, Thunderveil): the held tool points along the
	hand's grip, so the whole chain decides where a blade ends up, and these
	numbers put the sword low and forward, the lance level with the left hand
	on the shaft, and the heavy blade resting on the right shoulder.
]]
local function arm(pose)
	return {
		pitch = pose.pitch or 0,
		roll = pose.roll or 0,
		yaw = pose.yaw or 0,
		elbow = pose.elbow or 0,
		swing = pose.swing or 0,
		elbowSwing = pose.elbowSwing or 0,
		wrist = pose.wrist or 0,
		wristYaw = pose.wristYaw or 0,
		wristRoll = pose.wristRoll or 0,
	}
end

LocomotionAnimations.Gaits = {
	-- Swords, and everything without a carry of its own (pickaxes, axes, empty
	-- hands): an easy walk with the blade low and forward, the sword arm
	-- swinging less than the free arm; running, the blade trails behind.
	SwordWalk = {
		period = 0.82, run = false,
		legSwing = 28, kneeBase = 6, kneeLift = 42, heel = 10, toe = 22,
		bob = 0.12, crouch = -0.04, lean = 4, chestLean = 2,
		hipYaw = 6, chestYaw = 9, sway = 2.5, stance = 1,
		right = arm({pitch = -7, roll = -0.5, yaw = 33.3, elbow = 2.3, swing = 14, elbowSwing = 14, wrist = -4.7, wristYaw = -43.2}),
		left = arm({pitch = 0, roll = 5, elbow = 14, swing = 26, elbowSwing = 20}),
	},
	SwordRun = {
		period = 0.62, run = true,
		legSwing = 46, kneeBase = 14, kneeLift = 88, heel = 8, toe = 34,
		bob = 0.24, crouch = -0.18, lean = 14, chestLean = 6,
		hipYaw = 9, chestYaw = 14, sway = 2, stance = 1,
		right = arm({pitch = 40, roll = 4, yaw = -20, elbow = 100, swing = 26, elbowSwing = 10, wrist = 45, wristYaw = -33.2}),
		left = arm({pitch = 0, roll = 8, elbow = 82, swing = 52, elbowSwing = 12}),
	},

	-- Lances: carried level at the hip, point forward, the left hand forward on
	-- the shaft and the chest turned behind it. The arms barely move; the legs
	-- do the walking. Running, the point dips into a charge.
	LanceWalk = {
		period = 0.84, run = false,
		legSwing = 26, kneeBase = 9, kneeLift = 40, heel = 9, toe = 20,
		bob = 0.1, crouch = -0.1, lean = 6, chestLean = 3,
		hipYaw = 5, chestYaw = 4, sway = 2, stance = 1.5, chestTurn = -35,
		right = arm({pitch = -60, roll = 11, yaw = 39.3, elbow = 102.5, swing = 4, wrist = -45.2, wristYaw = 15.3}),
		left = arm({pitch = 63.5, roll = -51.2, yaw = 45.8, elbow = 9.3, swing = 4}),
	},
	LanceRun = {
		period = 0.64, run = true,
		legSwing = 44, kneeBase = 16, kneeLift = 84, heel = 8, toe = 32,
		bob = 0.2, crouch = -0.22, lean = 18, chestLean = 7,
		hipYaw = 8, chestYaw = 5, sway = 2, stance = 1.5, chestTurn = -35,
		right = arm({pitch = -60, roll = 3.5, yaw = 35.5, elbow = 110, swing = 9, elbowSwing = 6, wrist = -43.7, wristYaw = 26.5}),
		left = arm({pitch = 75.3, roll = -54, yaw = 55.8, elbow = 14.5, swing = 8, elbowSwing = 5}),
	},

	-- Heavy swords: the blade rides on the right shoulder, so the right arm is
	-- raised and still while the body works under the weight - a slower, wider,
	-- deeper step, more bob and side-to-side roll, the free arm swinging wide.
	HeavySwordWalk = {
		period = 0.98, run = false,
		legSwing = 24, kneeBase = 12, kneeLift = 38, heel = 8, toe = 18,
		bob = 0.17, crouch = -0.14, lean = 3, chestLean = 1,
		hipYaw = 5, chestYaw = 6, sway = 5, stance = 4, chestTilt = 4,
		right = arm({pitch = -6.7, roll = -21.7, yaw = 50.8, elbow = 125, swing = 3, wrist = 53.3, wristYaw = 43}),
		left = arm({pitch = 2, roll = 9, elbow = 18, swing = 24, elbowSwing = 18}),
	},
	HeavySwordRun = {
		period = 0.72, run = true,
		legSwing = 40, kneeBase = 18, kneeLift = 76, heel = 6, toe = 28,
		bob = 0.28, crouch = -0.26, lean = 15, chestLean = 5,
		hipYaw = 7, chestYaw = 9, sway = 4, stance = 4, chestTilt = 4,
		right = arm({pitch = 14.8, roll = -22.5, yaw = 49.5, elbow = 126, swing = 6, elbowSwing = 3, wrist = 53.3, wristYaw = 43.5}),
		left = arm({pitch = 2, roll = 10, elbow = 78, swing = 48, elbowSwing = 12}),
	},
}

-- Weapon class (WeaponClasses) -> gait prefix. Anything else walks like a sword.
local PREFIX = {Sword = "Sword", Lance = "Lance", HeavySword = "HeavySword"}

function LocomotionAnimations.nameFor(kind, class)
	return (PREFIX[class] or "Sword") .. kind
end

local TAU = math.pi * 2
local rad = math.rad

local function angles(pitch, yaw, roll)
	return CFrame.Angles(rad(pitch), rad(yaw), rad(roll))
end

-- One leg at phase p: hip, knee and ankle angles.
local function leg(g, p, side)
	local swing = math.sin(TAU * p)
	local forward = math.cos(TAU * p) -- positive while the leg moves forward
	local thigh = g.legSwing * swing + g.lean * 0.3
	local knee = -(g.kneeBase + g.kneeLift * math.max(0, forward) ^ 1.6)
	if g.run then
		-- Running lands on a bent knee and absorbs into it.
		knee -= g.kneeBase * 1.2 * math.max(0, math.sin(TAU * (p - 0.3))) ^ 2
	end
	local toeOff = math.max(0, -math.sin(TAU * p - 0.5)) ^ 3
	local heelStrike = math.max(0, swing) ^ 4
	local ankle = -(thigh + knee) * 0.8 - g.toe * toeOff + g.heel * heelStrike
	-- A wider stance turns the thighs out and the feet back in.
	local spread = g.stance * side
	return angles(thigh, 0, spread), angles(knee, 0, 0), angles(ankle, 0, -spread)
end

-- One arm at the leg phase it swings against.
local function armPose(a, p, side)
	local swing = -math.sin(TAU * p) -- forward as the opposite leg is
	local pitch = a.pitch + a.swing * swing
	local elbow = a.elbow + a.elbowSwing * math.max(0, swing)
	return angles(pitch, a.yaw * side, a.roll * side), angles(elbow, 0, 0),
		angles(a.wrist, a.wristYaw * side, a.wristRoll * side)
end

-- Every joint's transform at time phase t (0..1).
function LocomotionAnimations.sample(g, t)
	local s, c = math.sin(TAU * t), math.cos(TAU * t)
	local bob = if g.run then -math.cos(2 * TAU * t) else math.cos(2 * TAU * t)
	local pelvis = CFrame.new(0, g.crouch + g.bob * bob, 0)
		* angles(-g.lean * 0.3, g.hipYaw * s, g.sway * c)
	local chest = angles(-(g.lean * 0.7 + g.chestLean), -(g.hipYaw + g.chestYaw) * s + (g.chestTurn or 0), -g.sway * 0.6 * c + (g.chestTilt or 0))
	local head = angles((g.lean + g.chestLean) * 0.6, g.chestYaw * 0.8 * s - (g.chestTurn or 0) * 0.7, g.sway * 0.3 * c - (g.chestTilt or 0))

	local rHip, rKnee, rAnkle = leg(g, t, 1)
	local lHip, lKnee, lAnkle = leg(g, t + 0.5, -1)
	local rShoulder, rElbow, rWrist = armPose(g.right, t, 1)
	local lShoulder, lElbow, lWrist = armPose(g.left, t + 0.5, -1)

	return {
		LowerTorso = pelvis, UpperTorso = chest, Head = head,
		RightUpperLeg = rHip, RightLowerLeg = rKnee, RightFoot = rAnkle,
		LeftUpperLeg = lHip, LeftLowerLeg = lKnee, LeftFoot = lAnkle,
		RightUpperArm = rShoulder, RightLowerArm = rElbow, RightHand = rWrist,
		LeftUpperArm = lShoulder, LeftLowerArm = lElbow, LeftHand = lWrist,
	}
end

-- The R15 pose tree, parent before child.
local TREE = {
	{"LowerTorso", "HumanoidRootPart"},
	{"UpperTorso", "LowerTorso"}, {"Head", "UpperTorso"},
	{"RightUpperArm", "UpperTorso"}, {"RightLowerArm", "RightUpperArm"}, {"RightHand", "RightLowerArm"},
	{"LeftUpperArm", "UpperTorso"}, {"LeftLowerArm", "LeftUpperArm"}, {"LeftHand", "LeftLowerArm"},
	{"RightUpperLeg", "LowerTorso"}, {"RightLowerLeg", "RightUpperLeg"}, {"RightFoot", "RightLowerLeg"},
	{"LeftUpperLeg", "LowerTorso"}, {"LeftLowerLeg", "LeftUpperLeg"}, {"LeftFoot", "LeftLowerLeg"},
}

function LocomotionAnimations.build(name)
	local g = LocomotionAnimations.Gaits[name]
	assert(g, "[LocomotionAnimations] no gait named " .. tostring(name))
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = true
	sequence.Priority = Enum.AnimationPriority.Movement
	for i = 0, SAMPLES do
		local joints = LocomotionAnimations.sample(g, (i % SAMPLES) / SAMPLES)
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = g.period * i / SAMPLES
		local poses = {}
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		root.Parent = keyframe
		poses.HumanoidRootPart = root
		for _, link in ipairs(TREE) do
			local pose = Instance.new("Pose")
			pose.Name = link[1]
			pose.CFrame = joints[link[1]] or CFrame.identity
			pose.EasingStyle = Enum.PoseEasingStyle.Linear
			pose.Weight = 1
			pose.Parent = poses[link[2]]
			poses[link[1]] = pose
		end
		keyframe.Parent = sequence
	end
	return sequence
end

-- name -> temporary id, so each is registered once per session.
local previews = {}

--[[
	A temporary id for a gait, for playtesting before it is published. Studio
	only (KeyframeSequenceProvider refuses elsewhere); nil if it cannot.
]]
function LocomotionAnimations.preview(name)
	if previews[name] ~= nil then
		return previews[name] or nil
	end
	local ok, id = pcall(function()
		return game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(LocomotionAnimations.build(name))
	end)
	previews[name] = ok and id or false
	if not ok then
		warn("[LocomotionAnimations] could not preview " .. name .. ": " .. tostring(id))
	end
	return previews[name] or nil
end

return LocomotionAnimations
