--[[
	Ashen Lich: floats, so it bobs rather than walks; the robe leans into
	the drift and the arms trail. Its jaw never quite stops chattering.

	  cast   staff drawn back over the shoulder, then thrust: soul bolts leave
	         the gem at `release`
	  grave  staff hoisted high with the body rising, then driven into the
	         ground at `slam`: graves open under the marks
	  nova   arms flung wide, ribcage blazing, trembling - the soul fire
	         bursts out at `blast`
	  claw   the free left hand rakes across at `hit`
]]

local P = require(script.Parent.Player)
local add, both, clip = P.add, P.addBoth, P.clip
local V = Vector3.new

local Lich = { voxel = 0.2 }

Lich.sockets = {
	gem = { part = "Staff", at = V(14, 68.5, -10), pivot = V(14, 32.5, -10) },
	chest = { part = "Torso", at = V(0, 42, -4), pivot = V(0, 34, 0) },
	hand = { part = "LeftLowerArm", at = V(-14, 32.5, -9.5), pivot = V(-14, 38, -1) },
	staffFoot = { part = "Staff", at = V(14, 2, -10), pivot = V(14, 32.5, -10) },
	eyes = { part = "Head", at = V(0, 57, -6), pivot = V(0, 51, 0.5) },
}

function Lich.base(rig, ctx, out)
	local t = ctx.t
	local _, moving = P.gait(rig, ctx, 10, 6)
	local breath = math.sin(t * 1.7)
	add(out, "Root", { -4 * moving, 0, math.sin(t * 0.8) * 1.5, 0, 0.4 + breath * 0.3, 0 })
	add(out, "Torso", { breath * 2 - 6 * moving, math.sin(t * 0.6) * 4, 0 })
	add(out, "Head", { 2 + math.sin(t * 1.7 + 0.8) * 2 + 6 * moving, math.sin(t * 0.45) * 10, math.sin(t * 0.7) * 3 })
	add(out, "Jaw", { -2 - math.max(0, math.sin(t * 2.6)) * 4 })
	both(out, "UpperArm", { math.sin(t * 1.7 + 0.4) * 3 - 16 * moving, 0, 5 + breath * 2 })
	both(out, "LowerArm", { 6 + math.sin(t * 1.7 + 1) * 3 + 6 * moving, 0, 0 })
end

local REST = {}

Lich.moves = {
	cast = clip({
		marks = { release = 0.62 },
		keys = {
			{ 0, REST },
			{ 0.45, {
				Root = { 0, 0, 0, 0, 0.6, 0.4 },
				Torso = { 10, 22, -4 },
				Head = { 6, -14, 0 },
				Jaw = { -12 },
				RightUpperArm = { 150, 0, 12 },
				RightLowerArm = { 20 },
				Staff = { -155 },
				LeftUpperArm = { 25, 0, -30 },
				LeftLowerArm = { 30 },
			}, "io" },
			{ 0.62, {
				Root = { 0, 0, 0, 0, 0.2, -0.8 },
				Torso = { -14, -14, 2 },
				Head = { -6, 8, 0 },
				Jaw = { -22 },
				RightUpperArm = { 85, 0, 4 },
				RightLowerArm = { 10 },
				Staff = { -151 },
				LeftUpperArm = { -15, 0, -20 },
				LeftLowerArm = { 15 },
			}, "snap" },
			{ 0.95, {
				Root = { 0, 0, 0, 0, 0.2, -0.6 },
				Torso = { -10, -10, 2 },
				Head = { -4, 6, 0 },
				Jaw = { -14 },
				RightUpperArm = { 78, 0, 6 },
				RightLowerArm = { 12 },
				Staff = { -140 },
				LeftUpperArm = { -10, 0, -18 },
				LeftLowerArm = { 15 },
			}, "out" },
			{ 1.35, REST, "io" },
		},
	}),

	grave = clip({
		marks = { slam = 0.85 },
		keys = {
			{ 0, REST },
			{ 0.55, {
				Root = { 0, 0, 0, 0, 1.6, 0 },
				Torso = { 14, 0, 0 },
				Head = { 18, 0, 0 },
				Jaw = { -24 },
				RightUpperArm = { 60, 0, 10 },
				RightLowerArm = { 60 },
				Staff = { -134 },
				LeftUpperArm = { 20, 0, -55 },
				LeftLowerArm = { 25 },
			}, "io" },
			{ 0.85, {
				Root = { 0, 0, 0, 0, -0.9, -0.4 },
				Torso = { -22, 0, 0 },
				Head = { -14, 0, 0 },
				Jaw = { -30 },
				RightUpperArm = { 40, 0, 4 },
				RightLowerArm = { 10 },
				Staff = { -40 },
				LeftUpperArm = { 10, 0, -45 },
				LeftLowerArm = { 20 },
			}, "snap" },
			{ 1.25, {
				Root = { 0, 0, 0, 0, -0.7, -0.3 },
				Torso = { -18, 0, 0 },
				Head = { -10, 0, 0 },
				Jaw = { -16 },
				RightUpperArm = { 38, 0, 4 },
				RightLowerArm = { 12 },
				Staff = { -36 },
				LeftUpperArm = { 8, 0, -38 },
				LeftLowerArm = { 20 },
			}, "out" },
			{ 1.7, REST, "io" },
		},
	}),

	nova = clip({
		marks = { blast = 0.75 },
		keys = {
			{ 0, REST },
			{ 0.6, {
				Root = { 0, 0, 0, 0, 1.0, 0.3 },
				Torso = { 16, 0, 0 },
				Head = { 22, 0, 0 },
				Jaw = { -34 },
				["*UpperArm"] = { -10, 0, 72 },
				["*LowerArm"] = { 35 },
			}, "io" },
			{ 0.75, {
				Root = { 0, 0, 0, 0, 0.4, -0.3 },
				Torso = { -10, 0, 0 },
				Head = { -4, 0, 0 },
				Jaw = { -40 },
				["*UpperArm"] = { 55, 0, 50 },
				["*LowerArm"] = { 5 },
			}, "snap" },
			{ 1.0, {
				Root = { 0, 0, 0, 0, 0.4, -0.2 },
				Torso = { -8, 0, 0 },
				Jaw = { -20 },
				["*UpperArm"] = { 45, 0, 42 },
				["*LowerArm"] = { 10 },
			}, "out" },
			{ 1.3, REST, "io" },
		},
		-- The build-up trembles.
		extra = function(out, t)
			if t > 0.15 and t < 0.75 then
				local shake = (t - 0.15) / 0.6 * 3
				add(out, "Torso", { math.sin(t * 61) * shake, math.sin(t * 47) * shake, 0 })
				add(out, "Head", { math.sin(t * 53) * shake, 0, math.sin(t * 43) * shake })
			end
		end,
	}),

	claw = clip({
		marks = { hit = 0.38 },
		keys = {
			{ 0, REST },
			{ 0.26, {
				Torso = { 4, -24, 0 },
				Head = { 0, 12, 0 },
				Jaw = { -10 },
				LeftUpperArm = { 40, 0, -75 },
				LeftLowerArm = { 45 },
			}, "io" },
			{ 0.38, {
				Root = { 0, 0, 0, 0, 0, -0.5 },
				Torso = { -10, 26, 0 },
				Head = { -4, -10, 0 },
				Jaw = { -26 },
				LeftUpperArm = { 80, 0, 15 },
				LeftLowerArm = { 20 },
			}, "snap" },
			{ 0.55, {
				Torso = { -8, 22, 0 },
				Jaw = { -12 },
				LeftUpperArm = { 70, 0, 25 },
				LeftLowerArm = { 25 },
			}, "out" },
			{ 0.85, REST, "io" },
		},
	}),
}

return Lich
