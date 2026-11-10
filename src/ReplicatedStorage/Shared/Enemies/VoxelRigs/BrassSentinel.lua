--[[
	Brass Sentinel: a heavy, deliberate walk - the pelvis rocks over each
	planted boot, the torso counter-twists and the back gear never stops.

	  hammer  fist hauled overhead, then brought down on the ground ahead at `hit`
	  bash    crouched behind the shield (`charge` starts the rush, `stop` ends it)
	  furnace chest thrown open and the gear racing: fire from `open` to `close`
]]

local P = require(script.Parent.Player)
local add, both, clip = P.add, P.addBoth, P.clip
local V = Vector3.new

local Sentinel = { voxel = 0.2 }

Sentinel.sockets = {
	fist = { part = "RightForearm", at = V(17, 23, -2), pivot = V(17, 39, 0) },
	core = { part = "Torso", at = V(0, 43, -7), pivot = V(0, 33, 0) },
	shield = { part = "Shield", at = V(-21, 30, -10), pivot = V(-17, 31, -3) },
	lens = { part = "Head", at = V(0, 60.5, -8), pivot = V(0, 55, -1) },
	stacks = { part = "Torso", at = V(0, 64, 7), pivot = V(0, 33, 0) },
}

function Sentinel.base(rig, ctx, out)
	local t = ctx.t
	local s, moving = P.gait(rig, ctx, 9, 5.5)
	local swing = math.sin(s) * moving
	local lift = math.max(0, math.cos(s))
	local liftL = math.max(0, -math.cos(s))
	add(out, "Root", { -3 * moving, 0, math.sin(s) * 3 * moving, 0, (math.abs(math.cos(s)) - 1) * 0.45 * moving, 0 })
	add(out, "Torso", { math.sin(t * 1.2) * 1.5 - 3 * moving, -math.sin(s) * 7 * moving, -math.sin(s) * 2 * moving })
	add(out, "Head", { math.sin(t * 1.2 + 0.6) * 1.5, math.sin(t * 0.4) * 14 * (1 - moving), 0 })
	add(out, "RightThigh", { swing * 24 })
	add(out, "LeftThigh", { -swing * 24 })
	add(out, "RightShin", { -lift * 30 * moving })
	add(out, "LeftShin", { -liftL * 30 * moving })
	add(out, "RightUpperArm", { -swing * 14, 0, 3 })
	add(out, "LeftUpperArm", { swing * 10, 0, -3 })
	both(out, "Forearm", { 6 + math.sin(t * 1.2) * 2 })
	add(out, "BackGear", { 0, 0, (t * 70) % 360 })
end

local REST = {}

Sentinel.moves = {
	hammer = clip({
		marks = { hit = 0.8 },
		keys = {
			{ 0, REST },
			{ 0.55, {
				Root = { 4, 0, 0, 0, 0.3, 0.4 },
				Torso = { 10, 18, 0 },
				Head = { 10, -10, 0 },
				RightUpperArm = { 165, 0, 12 },
				RightForearm = { 25 },
				LeftUpperArm = { 40, 0, -10 },
				LeftForearm = { 45 },
				RightThigh = { 8 },
				LeftThigh = { -12 },
			}, "io" },
			{ 0.8, {
				Root = { -6, 0, 0, 0, -0.9, -1.0 },
				Torso = { -26, -12, 0 },
				Head = { -14, 6, 0 },
				RightUpperArm = { 58, 0, 6 },
				RightForearm = { 30 },
				LeftUpperArm = { 20, 0, -18 },
				LeftForearm = { 30 },
				RightThigh = { 30 },
				RightShin = { -34 },
				LeftThigh = { -18 },
				LeftShin = { -8 },
			}, "snap" },
			{ 1.1, {
				Root = { -5, 0, 0, 0, -0.8, -0.9 },
				Torso = { -22, -10, 0 },
				Head = { -10, 4, 0 },
				RightUpperArm = { 55, 0, 6 },
				RightForearm = { 30 },
				LeftUpperArm = { 18, 0, -16 },
				LeftForearm = { 30 },
				RightThigh = { 26 },
				RightShin = { -30 },
				LeftThigh = { -16 },
				LeftShin = { -8 },
			}, "out" },
			{ 1.5, REST, "io" },
		},
	}),

	bash = clip({
		marks = { charge = 0.45, stop = 0.9 },
		keys = {
			{ 0, REST },
			{ 0.45, {
				Root = { -10, 0, 0, 0, -0.7, 0 },
				Torso = { -14, -22, 0 },
				Head = { -6, 14, 0 },
				LeftUpperArm = { 72, 0, -6 },
				LeftForearm = { 38 },
				RightUpperArm = { -20, 0, 10 },
				RightForearm = { 30 },
				RightThigh = { -10 },
				LeftThigh = { 26 },
				LeftShin = { -24 },
			}, "back" },
			{ 0.9, {
				Root = { -16, 0, 0, 0, -0.6, 0 },
				Torso = { -18, -26, 0 },
				Head = { -2, 16, 0 },
				LeftUpperArm = { 78, 0, -4 },
				LeftForearm = { 34 },
				RightUpperArm = { -30, 0, 12 },
				RightForearm = { 34 },
			}, "lin" },
			{ 1.4, REST, "io" },
		},
		-- Legs pumping through the rush.
		extra = function(out, t)
			if t > 0.45 and t < 0.95 then
				local s = (t - 0.45) * 20
				add(out, "RightThigh", { math.sin(s) * 35 })
				add(out, "LeftThigh", { -math.sin(s) * 35 })
				add(out, "RightShin", { -math.max(0, math.cos(s)) * 40 })
				add(out, "LeftShin", { -math.max(0, -math.cos(s)) * 40 })
				add(out, "Root", { 0, 0, 0, 0, math.abs(math.sin(s)) * 0.5, 0 })
			end
		end,
	}),

	furnace = clip({
		marks = { open = 0.8, close = 1.9 },
		keys = {
			{ 0, REST },
			{ 0.7, {
				Root = { 6, 0, 0, 0, -0.3, 0.6 },
				Torso = { 14, 0, 0 },
				Head = { 16, 0, 0 },
				["*UpperArm"] = { -24, 0, 38 },
				["*Forearm"] = { 40 },
				["*Thigh"] = { 10 },
				["*Shin"] = { -16 },
			}, "io" },
			{ 0.85, {
				Root = { -6, 0, 0, 0, -0.5, -0.3 },
				Torso = { -10, 0, 0 },
				Head = { -6, 0, 0 },
				["*UpperArm"] = { -32, 0, 30 },
				["*Forearm"] = { 30 },
				RightThigh = { 18 },
				RightShin = { -18 },
				LeftThigh = { -10 },
			}, "snap" },
			{ 1.9, {
				Root = { -5, 0, 0, 0, -0.5, -0.3 },
				Torso = { -8, 0, 0 },
				Head = { -4, 0, 0 },
				["*UpperArm"] = { -30, 0, 28 },
				["*Forearm"] = { 30 },
				RightThigh = { 16 },
				RightShin = { -16 },
				LeftThigh = { -10 },
			}, "lin" },
			{ 2.3, REST, "io" },
		},
		extra = function(out, t)
			-- The gear races while the furnace roars, and the body shudders.
			if t < 2.0 then
				add(out, "BackGear", { 0, 0, (t * 900) % 360 })
				local shake = if t < 0.8 then t / 0.8 * 2 else 1.5
				add(out, "Torso", { math.sin(t * 57) * shake, math.sin(t * 41) * shake, 0 })
			end
		end,
	}),
}

return Sentinel
