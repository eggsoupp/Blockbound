--[[
	Shardstinger: a quick six-legged scuttle in alternating tripods, pincers
	held forward and idly snapping, the tail poised over the back and never
	quite still.

	  pinch  pincers spread wide and opened, then scissored shut at `hit`
	  sting  tail cocked back, then driven forward over the body at `hit`
	  erupt  tail and claws raised, then the stinger stabbed into the ground
	         at `slam`: crystals tear up the line toward the target
]]

local P = require(script.Parent.Player)
local add, both, clip = P.add, P.addBoth, P.clip
local V = Vector3.new

local Scorpion = { voxel = 0.2 }

Scorpion.sockets = {
	stinger = { part = "Stinger", at = V(0, 47.5, 6.5), pivot = V(0, 55, 23) },
	rightClaw = { part = "RightClaw", at = V(12, 16, -44), pivot = V(14, 15, -26) },
	leftClaw = { part = "LeftClaw", at = V(-12, 16, -44), pivot = V(-14, 15, -26) },
	back = { part = "Body", at = V(0, 24, 4), pivot = V(0, 14, 4) },
}

local LEGS = { { "Front", 0 }, { "Mid", math.pi }, { "Hind", 0 } }

function Scorpion.base(rig, ctx, out)
	local t = ctx.t
	local s, moving = P.gait(rig, ctx, 6, 8)
	for _, leg in ipairs(LEGS) do
		local name, offset = leg[1], leg[2]
		-- Tripods: right front, left mid, right hind against the others.
		local right, left = s + offset, s + offset + math.pi
		add(out, "Right" .. name .. "Leg", { 0, math.sin(right) * 18 * moving, math.max(0, math.cos(right)) * 14 * moving })
		add(out, "Left" .. name .. "Leg", { 0, -math.sin(left) * 18 * moving, -math.max(0, math.cos(left)) * 14 * moving })
		both(out, name .. "Foot", { 0, 0, -math.sin(t * 1.9 + offset) * 2 })
	end
	add(out, "Root", { 0, 0, math.sin(s) * 1.5 * moving, 0, math.abs(math.sin(s * 2)) * 0.12 * moving, 0 })
	-- The tail weaves, each segment a little behind the last.
	for i, name in ipairs({ "Tail1", "Tail2", "Tail3", "Tail4", "Stinger" }) do
		add(out, name, { math.sin(t * 1.5 - i * 0.5) * 3, if i == 1 then math.sin(t * 0.9) * 6 else 0, 0 })
	end
	add(out, "Stinger", { math.max(0, math.sin(t * 3.1)) ^ 8 * 10 })
	both(out, "Arm", { math.sin(t * 1.3) * 3, -math.sin(t * 0.8) * 4, 0 })
	both(out, "Claw", { 0, math.sin(t * 1.1) * 4, 0 })
	add(out, "RightClawFinger", { -(math.sin(t * 1.7) * 0.5 + 0.5) * 18 })
	add(out, "LeftClawFinger", { -(math.sin(t * 1.9 + 1) * 0.5 + 0.5) * 18 })
end

local REST = {}

Scorpion.moves = {
	pinch = clip({
		marks = { hit = 0.4 },
		keys = {
			{ 0, REST },
			{ 0.28, {
				Root = { 4, 0, 0, 0, 0.2, 0.4 },
				["*Arm"] = { 14, -26, 0 },
				["*Claw"] = { 0, -10, 0 },
				["*ClawFinger"] = { -38 },
			}, "io" },
			{ 0.4, {
				Root = { -4, 0, 0, 0, 0, -0.8 },
				["*Arm"] = { -4, 22, 0 },
				["*Claw"] = { 0, 12, 0 },
				["*ClawFinger"] = { 6 },
			}, "snap" },
			{ 0.6, {
				Root = { -3, 0, 0, 0, 0, -0.6 },
				["*Arm"] = { -2, 18, 0 },
				["*Claw"] = { 0, 10, 0 },
				["*ClawFinger"] = { 4 },
			}, "out" },
			{ 0.9, REST, "io" },
		},
	}),

	sting = clip({
		marks = { hit = 0.55 },
		keys = {
			{ 0, REST },
			{ 0.38, {
				Root = { 6, 0, 0, 0, 0.3, 0.5 },
				Tail1 = { 10 },
				Tail2 = { 12 },
				Tail3 = { 12 },
				Tail4 = { 16 },
				Stinger = { 24 },
				["*Arm"] = { 10, -10, 0 },
			}, "io" },
			{ 0.55, {
				Root = { -6, 0, 0, 0, -0.1, -0.9 },
				Tail1 = { -16 },
				Tail2 = { -24 },
				Tail3 = { -26 },
				Tail4 = { -24 },
				Stinger = { -18 },
				["*Arm"] = { -4, 8, 0 },
			}, "snap" },
			{ 0.75, {
				Root = { -4, 0, 0, 0, 0, -0.7 },
				Tail1 = { -14 },
				Tail2 = { -20 },
				Tail3 = { -22 },
				Tail4 = { -20 },
				Stinger = { -14 },
			}, "out" },
			{ 1.1, REST, "io" },
		},
	}),

	erupt = clip({
		marks = { slam = 0.75 },
		keys = {
			{ 0, REST },
			{ 0.55, {
				Root = { 8, 0, 0, 0, 0.6, 0.6 },
				Tail1 = { -4 },
				Tail2 = { 8 },
				Tail3 = { 10 },
				Tail4 = { 14 },
				Stinger = { 20 },
				["*Arm"] = { 34, -16, 0 },
				["*ClawFinger"] = { -30 },
			}, "io" },
			{ 0.75, {
				Root = { -10, 0, 0, 0, -0.5, -0.4 },
				Tail1 = { -22 },
				Tail2 = { -30 },
				Tail3 = { -34 },
				Tail4 = { -34 },
				Stinger = { -30 },
				["*Arm"] = { -18, 10, 0 },
				["*ClawFinger"] = { 4 },
			}, "snap" },
			{ 1.1, {
				Root = { -8, 0, 0, 0, -0.4, -0.3 },
				Tail1 = { -20 },
				Tail2 = { -28 },
				Tail3 = { -32 },
				Tail4 = { -30 },
				Stinger = { -26 },
				["*Arm"] = { -14, 8, 0 },
			}, "out" },
			{ 1.6, REST, "io" },
		},
	}),
}

return Scorpion
