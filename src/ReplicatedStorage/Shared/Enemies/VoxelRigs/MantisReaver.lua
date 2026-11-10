--[[
	Mantis Reaver: scuttles on four legs in diagonal pairs, scythes held up
	in prayer, the head swivelling and tilting the way a mantis's does.

	  xslash  scythes cocked high, wings flared, then crossed down at `hit`
	  pounce  crouched and flared (the hop lunge carries it); scythes strike
	          as it flies
	  whirl   arms flung wide, wings buzzing, spun round by the server: cuts
	          at `hit1` and `hit2`
]]

local P = require(script.Parent.Player)
local add, both, clip = P.add, P.addBoth, P.clip
local V = Vector3.new

local Mantis = { voxel = 0.2 }

Mantis.sockets = {
	rightBlade = { part = "RightScythe", at = V(7, 34, -23), pivot = V(7, 46, -17) },
	leftBlade = { part = "LeftScythe", at = V(-7, 34, -23), pivot = V(-7, 46, -17) },
	head = { part = "Head", at = V(0, 45, -15), pivot = V(0, 42, -10) },
}

function Mantis.base(rig, ctx, out)
	local t = ctx.t
	local s, moving = P.gait(rig, ctx, 7, 9)
	-- Diagonal pairs: right fore with left hind.
	-- Right fore and left hind share phase a; left fore and right hind, b.
	-- +ry swings a right leg forward and a left one back, so lefts negate.
	local a, b = s, s + math.pi
	local rf, lh = math.sin(a) * 22 * moving, math.sin(a) * 22 * moving
	local lf, rh = math.sin(b) * 22 * moving, math.sin(b) * 22 * moving
	add(out, "RightForeThigh", { 0, rf, math.max(0, math.cos(a)) * 16 * moving })
	add(out, "LeftHindThigh", { 0, -lh, -math.max(0, math.cos(a)) * 16 * moving })
	add(out, "LeftForeThigh", { 0, -lf, -math.max(0, math.cos(b)) * 16 * moving })
	add(out, "RightHindThigh", { 0, rh, math.max(0, math.cos(b)) * 16 * moving })
	both(out, "ForeShin", { 0, 0, -math.sin(t * 2.1) * 2 })
	both(out, "HindShin", { 0, 0, -math.sin(t * 2.1 + 1) * 2 })

	add(out, "Root", { 0, 0, 0, 0, math.abs(math.sin(s)) * 0.15 * moving, 0 })
	add(out, "Chest", { math.sin(t * 1.3) * 3 - 6 * moving, 0, 0 })
	-- The head swivels and cocks, now and then.
	local look = math.sin(t * 0.7) * 16 + math.sin(t * 2.3) * 3
	local cock = math.sin(t * 0.45) * 12
	add(out, "Head", { math.sin(t * 1.3 + 0.5) * 3, look, cock })
	both(out, "Arm", { math.sin(t * 1.3 + 0.3) * 4, 0, 0 })
	both(out, "Scythe", { math.sin(t * 1.3 + 0.8) * 5 })
	add(out, "Abdomen", { math.sin(t * 1.1) * 4, math.sin(t * 0.8) * 5, 0 })
	both(out, "Wing", { 0, 0, if moving > 0.5 then math.sin(t * 50) * 3 else 0 })
end

local REST = {}

Mantis.moves = {
	xslash = clip({
		marks = { hit = 0.42 },
		keys = {
			{ 0, REST },
			{ 0.3, {
				Root = { 0, 0, 0, 0, 0.3, 0.6 },
				Chest = { 14, 0, 0 },
				Head = { 10, 0, 0 },
				["*Arm"] = { 32, 0, -14 },
				["*Scythe"] = { -70 },
				["*Wing"] = { 0, 0, 34 },
			}, "io" },
			{ 0.42, {
				Root = { 0, 0, 0, 0, -0.2, -1.4 },
				Chest = { -18, 0, 0 },
				Head = { -8, 0, 0 },
				["*Arm"] = { -38, 0, 16 },
				["*Scythe"] = { 75 },
				["*Wing"] = { 0, 0, 20 },
			}, "snap" },
			{ 0.62, {
				Root = { 0, 0, 0, 0, -0.2, -1.2 },
				Chest = { -20, 0, 0 },
				Head = { -6, 0, 0 },
				["*Arm"] = { -44, 0, 26 },
				["*Scythe"] = { 82 },
				["*Wing"] = { 0, 0, 10 },
			}, "out" },
			{ 0.95, REST, "io" },
		},
	}),

	pounce = clip({
		marks = {},
		keys = {
			{ 0, REST },
			{ 0.38, {
				Root = { 0, 0, 0, 0, -0.9, 0.5 },
				Chest = { 22, 0, 0 },
				Head = { 12, 0, 0 },
				["*Arm"] = { 38, 0, 10 },
				["*Scythe"] = { -55 },
				["*Wing"] = { -10, 0, 48 },
				["*ForeThigh"] = { 0, 0, -14 },
				["*HindThigh"] = { 0, 0, -14 },
			}, "io" },
			{ 0.55, {
				Root = { 0, 0, 0, 0, 0.2, 0 },
				Chest = { -12, 0, 0 },
				Head = { -6, 0, 0 },
				["*Arm"] = { -22, 0, -8 },
				["*Scythe"] = { 62 },
				["*Wing"] = { -10, 0, 40 },
				["*ForeThigh"] = { 0, -20, 10 },
				["*HindThigh"] = { 0, 20, 10 },
			}, "snap" },
		},
		extra = function(out, t)
			if t > 0.4 then
				local buzz = math.sin(t * 70) * 18
				add(out, "RightWing", { 0, 0, buzz })
				add(out, "LeftWing", { 0, 0, -buzz })
			end
		end,
	}),

	whirl = clip({
		marks = { hit1 = 0.55, hit2 = 0.95 },
		keys = {
			{ 0, REST },
			{ 0.3, {
				Root = { 0, 0, 0, 0, 0.5, 0 },
				Chest = { 6, 0, 0 },
				["*Arm"] = { -10, 0, -62 },
				["*Scythe"] = { 30, 0, 20 },
				["*Wing"] = { 0, 0, 42 },
			}, "back" },
			{ 1.15, {
				Root = { 0, 0, 0, 0, 0.5, 0 },
				Chest = { 2, 0, 0 },
				["*Arm"] = { -14, 0, -66 },
				["*Scythe"] = { 36, 0, 24 },
				["*Wing"] = { 0, 0, 40 },
			}, "lin" },
			{ 1.45, REST, "io" },
		},
		extra = function(out, t)
			if t < 1.2 then
				local buzz = math.sin(t * 70) * 14
				add(out, "RightWing", { 0, 0, buzz })
				add(out, "LeftWing", { 0, 0, -buzz })
			end
		end,
	}),
}

return Mantis
