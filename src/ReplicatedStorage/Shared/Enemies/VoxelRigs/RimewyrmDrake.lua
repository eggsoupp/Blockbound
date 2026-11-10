--[[
	Rimewyrm Drake: a stalking, heavy-footed wyvern. The neck counters each
	step so the head stays level and hunting; the tail waves in a travelling
	S, each segment a beat behind the last; half-folded wings breathe.

	  bite    neck reared, jaws wide, then struck down at `hit`
	  breath  a long inhale with wings lifting, then frost from `start` to
	          `stop` while the neck sweeps across
	  sweep   body wound one way, tail whipped round at `hit`
	  gust    crouch, leap and two great wingbeats (`beat`), landing at `land`
]]

local P = require(script.Parent.Player)
local add, both, clip = P.add, P.addBoth, P.clip
local V = Vector3.new

local Drake = { voxel = 0.2 }

Drake.sockets = {
	mouth = { part = "Head", at = V(0, 57, -35), pivot = V(0, 56, -20) },
	tail = { part = "Tail3", at = V(0, 19, 53), pivot = V(0, 22, 39) },
	chest = { part = "Body", at = V(0, 30, -12), pivot = V(0, 30, 2) },
}

function Drake.base(rig, ctx, out)
	local t = ctx.t
	local s, moving = P.gait(rig, ctx, 10, 7)
	local swing = math.sin(s) * moving
	local breath = math.sin(t * 1.2)
	add(out, "Root", { -3 * moving, 0, math.sin(s) * 3 * moving, 0, (math.abs(math.cos(s)) - 1) * 0.5 * moving, 0 })
	add(out, "RightThigh", { swing * 28 })
	add(out, "LeftThigh", { -swing * 28 })
	add(out, "RightShin", { -math.max(0, math.cos(s)) * 32 * moving })
	add(out, "LeftShin", { -math.max(0, -math.cos(s)) * 32 * moving })
	add(out, "Neck", { breath * 3 - math.sin(s * 2) * 4 * moving, math.sin(t * 0.4) * 12 * (1 - moving), 0 })
	add(out, "Head", { math.sin(t * 1.2 + 0.8) * 2 + math.sin(s * 2) * 4 * moving, math.sin(t * 0.6) * 8, math.sin(t * 0.5) * 4 })
	add(out, "Jaw", { -3 - math.max(0, math.sin(t * 0.9)) ^ 6 * 10 })
	both(out, "Wing", { 0, 0, breath * 3 + math.sin(s) * 5 * moving })
	both(out, "WingTip", { 0, 0, breath * 2 })
	local wave = t * 1.3 + s * 0.5
	add(out, "Tail1", { -2 * moving, math.sin(wave) * 8, 0 })
	add(out, "Tail2", { math.sin(t * 0.9) * 3, math.sin(wave - 0.8) * 12, 0 })
	add(out, "Tail3", { math.sin(t * 0.9 - 0.5) * 4, math.sin(wave - 1.6) * 18, 0 })
end

local REST = {}

Drake.moves = {
	bite = clip({
		marks = { hit = 0.45 },
		keys = {
			{ 0, REST },
			{ 0.3, {
				Root = { 4, 0, 0, 0, 0.3, 0.6 },
				Neck = { 26, 0, 0 },
				Head = { 18, 0, 0 },
				Jaw = { -38 },
				["*Wing"] = { 0, 0, 14 },
			}, "io" },
			{ 0.45, {
				Root = { -8, 0, 0, 0, -0.3, -1.4 },
				Neck = { -42, 0, 0 },
				Head = { -12, 0, 0 },
				Jaw = { -2 },
				["*Wing"] = { 0, 0, 6 },
			}, "snap" },
			{ 0.65, {
				Root = { -6, 0, 0, 0, -0.2, -1.0 },
				Neck = { -36, 0, 0 },
				Head = { -8, 0, 0 },
				Jaw = { -4 },
			}, "out" },
			{ 1.0, REST, "io" },
		},
	}),

	breath = clip({
		marks = { start = 1.0, stop = 2.2 },
		keys = {
			{ 0, REST },
			{ 0.9, {
				Root = { 6, 0, 0, 0, 0.4, 0.5 },
				Neck = { 34, 0, 0 },
				Head = { 24, 0, 0 },
				Jaw = { -12 },
				["*Wing"] = { 0, 0, 30 },
				["*WingTip"] = { 0, 0, 10 },
			}, "io" },
			{ 1.05, {
				Root = { -6, 0, 0, 0, -0.2, -0.4 },
				Neck = { -14, 0, 0 },
				Head = { -22, 0, 0 },
				Jaw = { -46 },
				["*Wing"] = { 0, 0, 18 },
				["*WingTip"] = { 0, 0, 6 },
			}, "snap" },
			{ 2.2, {
				Root = { -6, 0, 0, 0, -0.2, -0.4 },
				Neck = { -12, 0, 0 },
				Head = { -20, 0, 0 },
				Jaw = { -44 },
				["*Wing"] = { 0, 0, 18 },
				["*WingTip"] = { 0, 0, 6 },
			}, "lin" },
			{ 2.6, REST, "io" },
		},
		extra = function(out, t)
			if t < 0.9 then
				local shake = t / 0.9 * 2
				add(out, "Neck", { math.sin(t * 50) * shake, 0, 0 })
			elseif t < 2.2 then
				-- The frost sweeps across: right, then left.
				local a = (t - 1.0) / 1.2
				add(out, "Neck", { 0, 22 - 44 * a, 0 })
				add(out, "Head", { 0, 8 - 16 * a, 0 })
				add(out, "Jaw", { math.sin(t * 40) * 2 })
			end
		end,
	}),

	sweep = clip({
		marks = { hit = 0.7 },
		keys = {
			{ 0, REST },
			{ 0.45, {
				Root = { 0, 40, 0, 0, -0.3, 0 },
				Neck = { 6, -20, 0 },
				Tail1 = { -6, 36, 0 },
				Tail2 = { 0, 26, 0 },
				Tail3 = { 0, 18, 0 },
				["*Wing"] = { 0, 0, 20 },
			}, "io" },
			{ 0.7, {
				Root = { 0, -60, 0, 0, -0.2, 0 },
				Neck = { 0, 26, 0 },
				Tail1 = { -10, -52, 0 },
				Tail2 = { 0, -40, 0 },
				Tail3 = { 0, -34, 0 },
				["*Wing"] = { 0, 0, 10 },
			}, "snap" },
			{ 0.95, {
				Root = { 0, -50, 0, 0, -0.1, 0 },
				Neck = { 0, 20, 0 },
				Tail1 = { -6, -40, 0 },
				Tail2 = { 0, -44, 0 },
				Tail3 = { 0, -40, 0 },
			}, "out" },
			{ 1.4, REST, "io" },
		},
	}),

	gust = clip({
		marks = { lift = 0.55, beat = 1.0, land = 1.55 },
		keys = {
			{ 0, REST },
			{ 0.4, {
				Root = { 4, 0, 0, 0, -1.0, 0 },
				Neck = { 14, 0, 0 },
				["*Wing"] = { 0, -10, 62 },
				["*WingTip"] = { 0, 0, 24 },
				["*Thigh"] = { 24 },
				["*Shin"] = { -36 },
			}, "io" },
			{ 0.6, {
				Root = { -4, 0, 0, 0, 3.0, 0 },
				Neck = { 6, 0, 0 },
				["*Wing"] = { 0, 10, -30 },
				["*WingTip"] = { 0, 0, -10 },
				["*Thigh"] = { -10 },
				["*Shin"] = { -20 },
				Tail1 = { 14 },
			}, "out" },
			{ 0.85, {
				Root = { 0, 0, 0, 0, 4.2, 0 },
				Neck = { 18, 0, 0 },
				Head = { -14, 0, 0 },
				["*Wing"] = { 0, -14, 58 },
				["*WingTip"] = { 0, 0, 22 },
				["*Thigh"] = { -6 },
				["*Shin"] = { -24 },
				Tail1 = { 18 },
			}, "io" },
			{ 1.0, {
				Root = { -6, 0, 0, 0, 4.4, 0 },
				Neck = { -8, 0, 0 },
				Head = { -18, 0, 0 },
				Jaw = { -30 },
				["*Wing"] = { 0, 14, -36 },
				["*WingTip"] = { 0, 0, -12 },
				["*Thigh"] = { -10 },
				["*Shin"] = { -20 },
				Tail1 = { 14 },
			}, "snap" },
			{ 1.3, {
				Root = { 0, 0, 0, 0, 3.0, 0 },
				Neck = { 8, 0, 0 },
				["*Wing"] = { 0, -6, 40 },
				["*WingTip"] = { 0, 0, 14 },
				["*Thigh"] = { 10 },
				["*Shin"] = { -10 },
			}, "io" },
			{ 1.55, {
				Root = { -6, 0, 0, 0, -0.9, 0 },
				Neck = { -10, 0, 0 },
				["*Wing"] = { 0, 0, 20 },
				["*Thigh"] = { 26 },
				["*Shin"] = { -38 },
			}, "in" },
			{ 2.0, REST, "io" },
		},
	}),
}

return Drake
