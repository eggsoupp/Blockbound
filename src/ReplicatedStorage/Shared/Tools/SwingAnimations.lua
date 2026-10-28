--[[
	SwingAnimations

	The swings a held tool makes: the sword's four-hit combo, the pickaxe's
	mining swing and the axe's chop. Each is a handful of key poses written as
	data and built into an R15 KeyframeSequence, so tuning a swing is changing a
	number here rather than dragging keyframes.

		SwingAnimations.build("SwordSlash1")    -> KeyframeSequence
		SwingAnimations.preview("SwordSlash1")  -> temporary id, Studio only
		SwingAnimations.Swings.SwordSlash1.hit  -> when the blow lands

	The timings are not decoration. `hit` is the moment the blade is in front of
	the body, and the server lands its damage then (Shared.Combat.SwordCombo);
	`trail` is when the sword's wind trail is drawn. Retime a swing and its hit
	moves with it.

	PUBLISHING

	As with LocomotionAnimations: a KeyframeSequence plays outside Studio only
	once it is uploaded as an Animation. Build them into ServerStorage.
	SwingAnimations, right-click each, Save to Roblox under the group that owns
	the game, and put the ids in ToolConfig.SwingIds. Until then ToolConfig.
	swingId asks preview() for a temporary id in Studio.

	CONVENTIONS

	Only the upper body is animated - no legs - so a swing plays over walking
	and running rather than freezing the feet. Directions are in the chest's
	own space: +X right, +Y up, -Z forward. Angles are degrees; `turn` is a yaw
	to the left, `lean` a pitch forward, `tilt` a roll.

	An arm is `aim` (where the upper arm points), `bend` (the elbow), `pole`
	(which way the elbow bends the forearm) and, for the hand holding the tool,
	`blade` and `edge`: where the tool's shaft points out of the fist, and which
	way its head or edge faces. The wrist is solved from those, so a pose says
	where the sword IS rather than how a wrist would have to twist to get it
	there. Every Blockbound tool grows along its handle's +Y with its head on
	the handle's Z, which is what makes `blade` and `edge` mean the same thing
	for a sword, a pickaxe and an axe.
]]

local SwingAnimations = {}

local function v(x, y, z)
	return Vector3.new(x, y, z).Unit
end

-- ---------------------------------------------------------------------------
-- Shared poses
-- ---------------------------------------------------------------------------

-- Where every sword swing comes to rest: blade up and forward, ready for the
-- next one. Chained swings fade out of this, so they all start from it.
local GUARD = {
	waist = { turn = 8, lean = 4 },
	right = { aim = v(0.2, -0.8, -0.55), bend = 65, pole = v(0, 0.3, -1), blade = v(-0.15, 0.55, -0.8), edge = v(0, 0.8, 0.55) },
	left = { aim = v(-0.2, -0.95, 0.05), bend = 20 },
}

-- ---------------------------------------------------------------------------
-- The swings
--
-- Each key is a pose at `t` seconds; `ease` shapes the move from it to the
-- next key ("In" accelerates, "Out" decelerates, "InOut" both). `hit` and
-- `trail` are seconds too.
-- ---------------------------------------------------------------------------

SwingAnimations.Swings = {
	-- 1: a forehand cut, high on the right down across to the low left.
	SwordSlash1 = {
		length = 0.5,
		hit = 0.13,
		trail = { 0.03, 0.24 },
		keys = {
			{
				t = 0, ease = "In",
				waist = { turn = -28, lean = -4 },
				right = { aim = v(0.6, 0.55, 0.3), bend = 95, pole = v(-0.4, 0.8, -0.2), blade = v(0.3, 0.45, 0.85), edge = v(-0.4, 0.2, -0.9) },
				left = { aim = v(-0.25, -0.75, -0.6), bend = 50 },
			},
			-- Straight up over the shoulder, so the blade comes over the top
			-- rather than swinging round behind the head.
			{
				t = 0.065, ease = "Linear",
				waist = { turn = -12, lean = 0 },
				right = { aim = v(0.65, 0.45, -0.45), bend = 45, pole = v(-0.5, 0.5, -0.5), blade = v(-0.15, 0.85, -0.5), edge = v(-0.4, -0.5, -0.75) },
				left = { aim = v(-0.3, -0.8, -0.4), bend = 45 },
			},
			{
				t = 0.13, ease = "Out",
				waist = { turn = 10, lean = 6 },
				right = { aim = v(0.35, -0.05, -0.95), bend = 10, pole = v(-1, 0, 0), blade = v(-0.65, -0.35, -0.65), edge = v(-0.7, -0.7, 0.2) },
				left = { aim = v(-0.3, -0.9, 0.3), bend = 30 },
			},
			{
				t = 0.24, ease = "InOut",
				waist = { turn = 32, lean = 10 },
				right = { aim = v(-0.35, -0.55, -0.75), bend = 15, pole = v(-1, 0, 0), blade = v(-0.7, -0.65, 0.2), edge = v(0.1, -0.4, 0.9) },
				left = { aim = v(-0.4, -0.85, 0.35), bend = 40 },
			},
			{ t = 0.5, pose = GUARD },
		},
	},

	-- 2: the backhand, a level sweep from the left across to the right.
	SwordSlash2 = {
		length = 0.5,
		hit = 0.13,
		trail = { 0.03, 0.24 },
		keys = {
			{
				t = 0, ease = "In",
				waist = { turn = 35, lean = 4 },
				right = { aim = v(-0.3, -0.2, -0.95), bend = 75, pole = v(-1, 0.2, 0.3), blade = v(-0.9, 0.05, 0.4), edge = v(-0.2, 0, -1) },
				left = { aim = v(-0.4, -0.85, 0.3), bend = 30 },
			},
			{
				t = 0.13, ease = "Out",
				waist = { turn = 0, lean = 6 },
				right = { aim = v(0.3, -0.1, -0.95), bend = 10, pole = v(1, 0, 0), blade = v(0.15, -0.05, -1), edge = v(1, 0, 0.1) },
				left = { aim = v(-0.35, -0.85, 0.1), bend = 35 },
			},
			{
				t = 0.24, ease = "InOut",
				waist = { turn = -35, lean = 6 },
				right = { aim = v(0.9, -0.2, 0.2), bend = 10, pole = v(0, 0, -1), blade = v(0.85, -0.1, 0.5), edge = v(0, 0, 1) },
				left = { aim = v(-0.5, -0.7, -0.5), bend = 50 },
			},
			{ t = 0.5, pose = GUARD },
		},
	},

	-- 3: overhead, straight down in front.
	SwordSlash3 = {
		length = 0.55,
		hit = 0.16,
		trail = { 0.06, 0.28 },
		keys = {
			{
				t = 0, ease = "Out",
				waist = { turn = -8, lean = -6 },
				right = { aim = v(0.25, 0.95, 0.1), bend = 30, pole = v(0, 0.2, 1), blade = v(0, 0.75, 0.65), edge = v(0, 0.65, -0.75) },
				left = { aim = v(-0.15, 0.95, -0.1), bend = 60 },
			},
			{
				t = 0.06, ease = "In",
				waist = { turn = -10, lean = -10 },
				right = { aim = v(0.25, 0.95, 0.2), bend = 45, pole = v(0, 0.2, 1), blade = v(0, 0.5, 0.87), edge = v(0, 0.87, -0.5) },
				left = { aim = v(-0.15, 0.95, 0), bend = 75 },
			},
			{
				t = 0.16, ease = "Out",
				waist = { turn = 0, lean = 15 },
				right = { aim = v(0.15, -0.15, -1), bend = 5, pole = v(0, 1, 0), blade = v(-0.1, 0, -1), edge = v(0, -1, 0) },
				left = { aim = v(-0.2, -0.6, -0.75), bend = 30 },
			},
			{
				t = 0.28, ease = "InOut",
				waist = { turn = 0, lean = 20 },
				right = { aim = v(0.1, -0.7, -0.7), bend = 5, pole = v(0, 1, 0), blade = v(-0.05, -0.85, -0.5), edge = v(0, -0.5, 0.85) },
				left = { aim = v(-0.2, -0.8, -0.55), bend = 30 },
			},
			{ t = 0.55, pose = GUARD },
		},
	},

	-- 4: the finisher, a full turn on the spot with the blade held out level.
	-- The whole body turns, so this one animates the LowerTorso too; each
	-- key is under half a turn from the last so it always spins the same way.
	SwordSlash4 = {
		length = 0.75,
		hit = 0.24,
		trail = { 0.08, 0.46 },
		keys = {
			{
				t = 0, ease = "In",
				root = { turn = -35, y = -0.15 },
				waist = { turn = -20, lean = 6 },
				right = { aim = v(0.95, -0.15, 0.2), bend = 20, pole = v(0, 0, -1), blade = v(0.95, -0.05, 0.3), edge = v(0.3, 0, -0.95) },
				left = { aim = v(-0.5, -0.7, -0.5), bend = 50 },
			},
			{
				t = 0.12, ease = "Linear",
				root = { turn = 60, y = -0.3 },
				waist = { turn = 10, lean = 8 },
				right = { aim = v(0.95, -0.1, -0.1), bend = 10, pole = v(0, 0, -1), blade = v(0.95, 0, -0.2), edge = v(0.2, 0, -1) },
				left = { aim = v(-0.9, -0.35, 0.2), bend = 20 },
			},
			{
				t = 0.22, ease = "Linear",
				root = { turn = 180, y = -0.3 },
				waist = { turn = 10, lean = 8 },
				right = { aim = v(0.95, -0.1, -0.1), bend = 10, pole = v(0, 0, -1), blade = v(0.95, 0, -0.2), edge = v(0.2, 0, -1) },
				left = { aim = v(-0.9, -0.35, 0.2), bend = 20 },
			},
			{
				t = 0.32, ease = "Linear",
				root = { turn = 300, y = -0.3 },
				waist = { turn = 10, lean = 8 },
				right = { aim = v(0.95, -0.1, -0.1), bend = 10, pole = v(0, 0, -1), blade = v(0.95, 0, -0.2), edge = v(0.2, 0, -1) },
				left = { aim = v(-0.9, -0.35, 0.2), bend = 20 },
			},
			{
				t = 0.42, ease = "Out",
				root = { turn = 360, y = -0.2 },
				waist = { turn = 20, lean = 6 },
				right = { aim = v(0.6, -0.5, -0.6), bend = 15, pole = v(0, 0, -1), blade = v(0.3, -0.3, -0.9), edge = v(-1, 0, 0) },
				left = { aim = v(-0.6, -0.7, 0.2), bend = 30 },
			},
			{ t = 0.75, root = { turn = 360 }, pose = GUARD },
		},
	},

	-- The pickaxe: up over the shoulder and down into the block, made to
	-- LOOP (MiningClient plays it for as long as the button is held), so the
	-- last key is the first.
	PickaxeSwing = {
		length = 0.7,
		loop = true,
		keys = {
			{
				t = 0, ease = "InOut",
				waist = { turn = -12, lean = -4 },
				right = { aim = v(0.45, 0.8, 0.35), bend = 85, pole = v(-0.3, 0.6, -0.6), blade = v(0.2, 0.5, 0.85), edge = v(0, 0.85, -0.5) },
				left = { aim = v(-0.25, -0.8, -0.5), bend = 45 },
			},
			{
				t = 0.22, ease = "In",
				waist = { turn = -15, lean = -8 },
				right = { aim = v(0.45, 0.85, 0.3), bend = 100, pole = v(-0.3, 0.6, -0.6), blade = v(0.15, 0.25, 0.95), edge = v(0, 1, -0.25) },
				left = { aim = v(-0.25, -0.8, -0.5), bend = 50 },
			},
			{
				t = 0.38, ease = "Out",
				waist = { turn = 5, lean = 18 },
				right = { aim = v(0.2, -0.35, -0.9), bend = 15, pole = v(0, 1, 0), blade = v(-0.1, -0.35, -0.95), edge = v(0, -0.95, 0.35) },
				left = { aim = v(-0.3, -0.85, 0.3), bend = 30 },
			},
			{
				t = 0.48, ease = "InOut",
				waist = { turn = 4, lean = 16 },
				right = { aim = v(0.2, -0.4, -0.88), bend = 20, pole = v(0, 1, 0), blade = v(-0.1, -0.2, -0.97), edge = v(0, -0.97, 0.2) },
				left = { aim = v(-0.3, -0.85, 0.3), bend = 30 },
			},
			{ t = 0.7, same = 1 },
		},
	},

	-- The axe: drawn back over the right shoulder and chopped in level with
	-- the chest, where a trunk is. Once per chop (HarvestClient).
	AxeChop = {
		length = 0.6,
		-- The axe's bit is on the handle's -Z, so `edge` is flipped to mean
		-- the way the bit faces, like everywhere else.
		headSide = -1,
		keys = {
			{
				t = 0, ease = "In",
				waist = { turn = -30, lean = -2 },
				right = { aim = v(0.75, 0.35, 0.55), bend = 100, pole = v(-0.3, 0.5, -0.8), blade = v(0.5, 0.35, 0.8), edge = v(-0.3, 0.1, -0.95) },
				left = { aim = v(-0.2, -0.8, -0.55), bend = 45 },
			},
			{
				t = 0.16, ease = "Out",
				waist = { turn = 15, lean = 8 },
				right = { aim = v(0.3, -0.15, -0.95), bend = 15, pole = v(-1, 0, 0), blade = v(-0.6, 0, -0.8), edge = v(-0.8, 0, 0.6) },
				left = { aim = v(-0.3, -0.9, 0.3), bend = 30 },
			},
			{
				t = 0.26, ease = "InOut",
				waist = { turn = 18, lean = 8 },
				right = { aim = v(0.2, -0.2, -0.95), bend = 20, pole = v(-1, 0, 0), blade = v(-0.7, -0.05, -0.7), edge = v(-0.7, 0, 0.7) },
				left = { aim = v(-0.3, -0.9, 0.3), bend = 30 },
			},
			{
				t = 0.6, ease = "InOut",
				waist = { turn = 4, lean = 2 },
				right = { aim = v(0.15, -0.9, -0.4), bend = 45, pole = v(0, 0, -1), blade = v(0, 0.2, -1), edge = v(0, 1, 0.2) },
				left = { aim = v(-0.2, -0.95, 0.05), bend = 20 },
			},
		},
	},
}

-- The sword combo, in the order it plays.
SwingAnimations.SwordCombo = { "SwordSlash1", "SwordSlash2", "SwordSlash3", "SwordSlash4" }

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

local rad = math.rad
local FORWARD = Vector3.new(0, 0, -1)
local UP = Vector3.new(0, 1, 0)

local function angles(pitch, yaw, roll)
	return CFrame.Angles(rad(pitch or 0), rad(yaw or 0), rad(roll or 0))
end

-- `a` with its component along `axis` removed, or nil if nothing is left.
local function across(a, axis)
	local rest = a - axis * a:Dot(axis)
	return if rest.Magnitude > 1e-3 then rest.Unit else nil
end

--[[
	Shoulder, elbow and wrist transforms for one arm.

	The upper arm hangs along its own -Y and the elbow bends the forearm
	toward its own -Z, so the shoulder is the rotation that points -Y along
	`aim` with -Z toward `pole`. The hand holds a tool along its -Z with the
	tool's head on its +Y (the R15 grip), so the hand's wanted rotation comes
	straight from `blade` and `edge`, and the wrist is whatever is left once
	the shoulder and elbow have had their say. Every R15 rig attachment is
	axis-aligned, which is what lets the chain be multiplied straight through.
]]
local function arm(spec, headSide)
	local aim = spec.aim
	local toward = across(spec.pole or FORWARD, aim) or across(FORWARD, aim) or across(UP, aim)
	local shoulder = CFrame.fromMatrix(Vector3.zero, (-aim):Cross(-toward), -aim, -toward)
	local elbow = angles(spec.bend or 0, 0, 0)

	local wrist = CFrame.identity
	if spec.blade then
		local blade = spec.blade
		local edge = across((spec.edge or UP) * (headSide or 1), blade) or across(UP, blade) or across(FORWARD, blade)
		local hand = CFrame.fromMatrix(Vector3.zero, edge:Cross(-blade), edge, -blade)
		wrist = (shoulder * elbow):Inverse() * hand
	end

	return shoulder, elbow, wrist
end

-- Every animated joint's transform for one key, by the name of the part it
-- moves. The head turns back against the chest so the eyes stay on the target.
-- `headSide` is the swing's own (see AxeChop).
function SwingAnimations.posed(key, headSide)
	local pose = key.pose or key
	local root = key.root or pose.root
	local waist = pose.waist or {}

	local joints = {}
	if root then
		joints.LowerTorso = CFrame.new(0, root.y or 0, 0) * angles(-(root.lean or 0), root.turn or 0, root.tilt or 0)
	end
	joints.UpperTorso = angles(-(waist.lean or 0), waist.turn or 0, waist.tilt or 0)
	joints.Head = angles((waist.lean or 0) * 0.6, -(waist.turn or 0) * 0.7, -(waist.tilt or 0) * 0.5)
	joints.RightUpperArm, joints.RightLowerArm, joints.RightHand = arm(pose.right, headSide)
	joints.LeftUpperArm, joints.LeftLowerArm, joints.LeftHand = arm(pose.left)
	return joints
end

-- The upper-body pose tree, parent before child. The legs are left out on
-- purpose (see CONVENTIONS).
local TREE = {
	{ "LowerTorso", "HumanoidRootPart" },
	{ "UpperTorso", "LowerTorso" }, { "Head", "UpperTorso" },
	{ "RightUpperArm", "UpperTorso" }, { "RightLowerArm", "RightUpperArm" }, { "RightHand", "RightLowerArm" },
	{ "LeftUpperArm", "UpperTorso" }, { "LeftLowerArm", "LeftUpperArm" }, { "LeftHand", "LeftLowerArm" },
}

local EASING = {
	Linear = { Enum.PoseEasingStyle.Linear, Enum.PoseEasingDirection.In },
	In = { Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.In },
	Out = { Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.Out },
	InOut = { Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.InOut },
}

function SwingAnimations.build(name)
	local swing = SwingAnimations.Swings[name]
	assert(swing, "[SwingAnimations] no swing named " .. tostring(name))

	-- Only a swing that moves the hips keys the LowerTorso; the rest leave it
	-- to the walk, the pose standing in only to hold the tree together.
	local movesRoot = false
	for _, key in ipairs(swing.keys) do
		if key.root or (key.pose and key.pose.root) then
			movesRoot = true
		end
	end

	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = swing.loop == true
	sequence.Priority = Enum.AnimationPriority.Action

	for _, key in ipairs(swing.keys) do
		local source = if key.same then swing.keys[key.same] else key
		local joints = SwingAnimations.posed(source, swing.headSide)
		local easing = EASING[source.ease or "InOut"] or EASING.InOut

		local keyframe = Instance.new("Keyframe")
		keyframe.Time = key.t

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
			pose.EasingStyle = easing[1]
			pose.EasingDirection = easing[2]
			pose.Weight = if link[1] == "LowerTorso" and not movesRoot then 0 else 1
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
	A temporary id for a swing, for playtesting before it is published. Studio
	only (KeyframeSequenceProvider refuses elsewhere); nil if it cannot.
]]
function SwingAnimations.preview(name)
	if previews[name] ~= nil then
		return previews[name] or nil
	end
	local ok, id = pcall(function()
		return game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(SwingAnimations.build(name))
	end)
	previews[name] = ok and id or false
	if not ok then
		warn("[SwingAnimations] could not preview " .. name .. ": " .. tostring(id))
	end
	return previews[name] or nil
end

return SwingAnimations
