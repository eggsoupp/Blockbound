--[[
	Sporeking: a ponderous waddle on stubby legs, rolling side to side; the
	long arms knuckle-swing and the great cap wobbles a beat late.

	  smash   both fists hauled overhead, brought down at `hit`
	  spores  hunched and shaking, then the cap heaves up at `puff`
	  mortar  reaches back for a spore pod, lobs it overhand at `throw`
]]

local P = require(script.Parent.Player)
local add, both, clip = P.add, P.addBoth, P.clip
local V = Vector3.new

local King = { voxel = 0.2 }

King.sockets = {
	rightFist = { part = "RightForearm", at = V(16.5, 10, -3.5), pivot = V(15, 27, -1) },
	leftFist = { part = "LeftForearm", at = V(-16.5, 10, -3.5), pivot = V(-15, 27, -1) },
	cap = { part = "Head", at = V(0, 58, 0), pivot = V(0, 40, 0) },
	face = { part = "Head", at = V(0, 44, -9), pivot = V(0, 40, 0) },
}

function King.base(rig, ctx, out)
	local t = ctx.t
	local s, moving = P.gait(rig, ctx, 8, 5)
	local swing = math.sin(s) * moving
	add(out, "Root", { -2 * moving, 0, math.sin(s) * 4 * moving, 0, (math.abs(math.cos(s)) - 1) * 0.5 * moving + math.sin(t * 1.1) * 0.08, 0 })
	add(out, "Head", { math.sin(t * 1.1 + 0.6) * 2 + math.sin(s * 2 - 0.8) * 3 * moving, math.sin(t * 0.35) * 10 * (1 - moving), -math.sin(s - 0.6) * 4 * moving })
	add(out, "RightThigh", { swing * 22 })
	add(out, "LeftThigh", { -swing * 22 })
	add(out, "RightShin", { -math.max(0, math.cos(s)) * 24 * moving })
	add(out, "LeftShin", { -math.max(0, -math.cos(s)) * 24 * moving })
	add(out, "RightUpperArm", { -swing * 16 + math.sin(t * 1.1) * 2, 0, 2 })
	add(out, "LeftUpperArm", { swing * 16 + math.sin(t * 1.1) * 2, 0, -2 })
	both(out, "Forearm", { 6 + math.sin(t * 1.1 + 0.4) * 2 })
end

local REST = {}

King.moves = {
	smash = clip({
		marks = { hit = 0.85 },
		keys = {
			{ 0, REST },
			{ 0.6, {
				Root = { 10, 0, 0, 0, 0.6, 0.6 },
				Head = { 16, 0, 0 },
				["*UpperArm"] = { 168, 0, 8 },
				["*Forearm"] = { 22 },
				["*Thigh"] = { -6 },
			}, "io" },
			{ 0.85, {
				Root = { -20, 0, 0, 0, -1.0, -0.8 },
				Head = { -16, 0, 0 },
				["*UpperArm"] = { 62, 0, -4 },
				["*Forearm"] = { 32 },
				["*Thigh"] = { 18 },
				["*Shin"] = { -22 },
			}, "snap" },
			{ 1.15, {
				Root = { -17, 0, 0, 0, -0.9, -0.7 },
				Head = { -12, 0, 0 },
				["*UpperArm"] = { 58, 0, -4 },
				["*Forearm"] = { 30 },
				["*Thigh"] = { 16 },
				["*Shin"] = { -20 },
			}, "out" },
			{ 1.6, REST, "io" },
		},
	}),

	spores = clip({
		marks = { puff = 0.9 },
		keys = {
			{ 0, REST },
			{ 0.65, {
				Root = { -10, 0, 0, 0, -1.2, 0 },
				Head = { -18, 0, 0 },
				["*UpperArm"] = { 30, 0, -6 },
				["*Forearm"] = { 40 },
				["*Thigh"] = { 20 },
				["*Shin"] = { -28 },
			}, "io" },
			{ 0.9, {
				Root = { 6, 0, 0, 0, 1.3, 0 },
				Head = { 22, 0, 0 },
				["*UpperArm"] = { -10, 0, 52 },
				["*Forearm"] = { 10 },
				["*Thigh"] = { -4 },
			}, "back" },
			{ 1.3, {
				Root = { 4, 0, 0, 0, 0.6, 0 },
				Head = { 14, 0, 0 },
				["*UpperArm"] = { -6, 0, 40 },
				["*Forearm"] = { 12 },
			}, "out" },
			{ 1.8, REST, "io" },
		},
		extra = function(out, t)
			if t > 0.2 and t < 0.85 then
				local shake = (t - 0.2) / 0.65 * 4
				add(out, "Head", { math.sin(t * 47) * shake, 0, math.sin(t * 59) * shake })
			end
		end,
	}),

	mortar = clip({
		marks = { throw = 0.75 },
		keys = {
			{ 0, REST },
			{ 0.5, {
				Root = { 6, 26, 0, 0, -0.2, 0.3 },
				Head = { 10, -14, 0 },
				RightUpperArm = { -50, 0, 34 },
				RightForearm = { 50 },
				LeftUpperArm = { 40, 0, -20 },
				LeftForearm = { 20 },
				RightThigh = { -10 },
				LeftThigh = { 14 },
			}, "io" },
			{ 0.75, {
				Root = { -12, -18, 0, 0, -0.4, -0.6 },
				Head = { -6, 10, 0 },
				RightUpperArm = { 140, 0, 8 },
				RightForearm = { 10 },
				LeftUpperArm = { -20, 0, -14 },
				LeftForearm = { 20 },
				RightThigh = { 18 },
				RightShin = { -16 },
				LeftThigh = { -12 },
			}, "snap" },
			{ 1.0, {
				Root = { -10, -14, 0, 0, -0.3, -0.5 },
				RightUpperArm = { 115, 0, 8 },
				RightForearm = { 20 },
				LeftUpperArm = { -14, 0, -12 },
				RightThigh = { 14 },
				LeftThigh = { -10 },
			}, "out" },
			{ 1.5, REST, "io" },
		},
	}),
}

return King
