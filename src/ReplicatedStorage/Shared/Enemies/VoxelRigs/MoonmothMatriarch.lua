--[[
	Moonmoth Matriarch: always on the wing. Four wings beat slow and wide,
	the hindwings a beat behind the fore; the body rises on each downstroke,
	the antennae feel the air and the glowing abdomen sways below.

	  moonbeam  rises with wings held high, arms raised to the moon, then
	            sweeps down at `call` and the beams fall
	  gale      wings drawn far back, then swept forward in one gust at `gust`
	  eyespot   wings folded tight, then snapped open at `flash`
]]

local P = require(script.Parent.Player)
local add, both, clip = P.add, P.addBoth, P.clip
local V = Vector3.new

local Moth = { voxel = 0.18 }

Moth.sockets = {
	head = { part = "Head", at = V(0, 58, -9), pivot = V(0, 54, -3) },
	tail = { part = "Abdomen", at = V(0, 19, 11.5), pivot = V(0, 40, 2) },
	rightSpot = { part = "RightForewing", at = V(31, 64, 3), pivot = V(5, 50, 3) },
	leftSpot = { part = "LeftForewing", at = V(-31, 64, 3), pivot = V(-5, 50, 3) },
}

function Moth.base(rig, ctx, out)
	local t = ctx.t
	local _, moving = P.gait(rig, ctx, 12, 7)
	rig.beat = (rig.beat or 0) + ctx.dt * (1.1 + 0.6 * moving) * math.pi * 2
	local w = rig.beat
	-- Downstroke fast, upstroke slower: a skewed sine.
	local stroke = math.sin(w + 0.35 * math.sin(w))
	both(out, "Forewing", { 0, -6 * moving, 26 * stroke + 6 })
	both(out, "Hindwing", { 0, -8 * moving, 20 * math.sin(w - 0.6 + 0.35 * math.sin(w - 0.6)) - 4 })
	add(out, "Root", { -8 * moving, 0, math.sin(t * 0.6) * 3, 0, 1.6 - stroke * 0.45, 0 })
	add(out, "Head", { math.sin(w + 1) * 2, math.sin(t * 0.5) * 10, 0 })
	both(out, "Antenna", { math.sin(t * 2.0) * 6, 0, math.sin(t * 1.7) * 7 })
	add(out, "Abdomen", { math.sin(w + 2) * 5 + 8 * moving, math.sin(t * 0.7) * 6, 0 })
	both(out, "Arm", { 10 + math.sin(t * 1.3) * 6, 0, 0 })
end

local REST = {}

Moth.moves = {
	moonbeam = clip({
		marks = { call = 0.9 },
		keys = {
			{ 0, REST },
			{ 0.65, {
				Root = { 6, 0, 0, 0, 2.4, 0 },
				Head = { 26, 0, 0 },
				["*Antenna"] = { 20, 0, 12 },
				["*Forewing"] = { 0, 0, 44 },
				["*Hindwing"] = { 0, 0, 28 },
				["*Arm"] = { 125, 0, 18 },
				Abdomen = { 14 },
			}, "io" },
			{ 0.9, {
				Root = { -4, 0, 0, 0, 1.3, 0 },
				Head = { -12, 0, 0 },
				["*Antenna"] = { -10, 0, 4 },
				["*Forewing"] = { 0, 0, -22 },
				["*Hindwing"] = { 0, 0, -26 },
				["*Arm"] = { 70, 0, 10 },
				Abdomen = { -6 },
			}, "snap" },
			{ 1.4, {
				Root = { -3, 0, 0, 0, 1.2, 0 },
				Head = { -8, 0, 0 },
				["*Forewing"] = { 0, 0, -10 },
				["*Hindwing"] = { 0, 0, -16 },
				["*Arm"] = { 62, 0, 10 },
			}, "out" },
			{ 2.0, REST, "io" },
		},
		extra = function(out, t)
			if t > 0.1 and t < 0.85 then
				local shimmer = math.sin(t * 40) * 3
				add(out, "RightForewing", { 0, 0, shimmer })
				add(out, "LeftForewing", { 0, 0, -shimmer })
			end
		end,
	}),

	gale = clip({
		marks = { gust = 0.75 },
		keys = {
			{ 0, REST },
			{ 0.6, {
				Root = { 12, 0, 0, 0, 0.8, 0.9 },
				Head = { 10, 0, 0 },
				["*Forewing"] = { 0, -28, 56 },
				["*Hindwing"] = { 0, -22, 46 },
				["*Arm"] = { -20 },
				Abdomen = { -10 },
			}, "io" },
			{ 0.75, {
				Root = { -14, 0, 0, 0, 0.3, -0.7 },
				Head = { -10, 0, 0 },
				["*Forewing"] = { 0, 36, -18 },
				["*Hindwing"] = { 0, 26, -24 },
				["*Arm"] = { 40 },
				Abdomen = { 18 },
			}, "snap" },
			{ 1.05, {
				Root = { -10, 0, 0, 0, 0.3, -0.5 },
				["*Forewing"] = { 0, 30, -12 },
				["*Hindwing"] = { 0, 22, -18 },
				["*Arm"] = { 30 },
				Abdomen = { 12 },
			}, "out" },
			{ 1.6, REST, "io" },
		},
	}),

	eyespot = clip({
		marks = { flash = 0.7 },
		keys = {
			{ 0, REST },
			{ 0.5, {
				Root = { 0, 0, 0, 0, 0.2, 0.3 },
				Head = { -14, 0, 0 },
				["*Forewing"] = { 0, -42, 70 },
				["*Hindwing"] = { 0, -40, 55 },
				["*Arm"] = { 60, 0, -10 },
				Abdomen = { 22 },
			}, "io" },
			{ 0.7, {
				Root = { 4, 0, 0, 0, 0.6, 0 },
				Head = { 8, 0, 0 },
				["*Forewing"] = { 0, 14, 14 },
				["*Hindwing"] = { 0, 12, -6 },
				["*Arm"] = { -10, 0, 20 },
				Abdomen = { -8 },
			}, "back" },
			{ 1.0, {
				Root = { 3, 0, 0, 0, 0.5, 0 },
				["*Forewing"] = { 0, 12, 12 },
				["*Hindwing"] = { 0, 10, -6 },
			}, "out" },
			{ 1.4, REST, "io" },
		},
	}),
}

return Moth
