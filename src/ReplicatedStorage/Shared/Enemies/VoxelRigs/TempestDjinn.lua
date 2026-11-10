--[[
	Tempest Djinn: drifts on its storm, which turns endlessly beneath it and
	whips at the tip. Arms flex and rest crossed; the head turns slowly,
	watching.

	  orb      upper right arm drawn back with a twist, the orb hurled at `throw`
	  storm    all four arms raised to the sky, trembling, then brought down
	           at `call`: lightning falls on the marks
	  flurry   four punches, one per arm: `hit1` to `hit4`
	  whirl    arms flung out and spinning, dragging everything in, then a
	           blast at `blast`
]]

local P = require(script.Parent.Player)
local add, both, clip = P.add, P.addBoth, P.clip
local V = Vector3.new

local Djinn = { voxel = 0.2 }

Djinn.sockets = {
	orb = { part = "RightForearm", at = V(21, 41, -15), pivot = V(17, 49, -2) },
	chest = { part = "Torso", at = V(0, 52, -6), pivot = V(0, 46, 0) },
	head = { part = "Head", at = V(0, 66, -4), pivot = V(0, 60, 0) },
	tip = { part = "VortexTip", at = V(0, 3, 9), pivot = V(0, 24, 3) },
}

function Djinn.base(rig, ctx, out)
	local t = ctx.t
	local _, moving = P.gait(rig, ctx, 10, 7)
	local breath = math.sin(t * 1.3)
	add(out, "Root", { -10 * moving, 0, math.sin(t * 0.7) * 2, 0, 0.5 + breath * 0.5, 0 })
	add(out, "Vortex", { math.sin(t * 1.3) * 5 - 10 * moving, (t * 120) % 360, math.cos(t * 1.1) * 4 })
	add(out, "VortexTip", { math.sin(t * 1.7) * 9 - 8 * moving, (t * 200) % 360, math.cos(t * 1.3) * 7 })
	add(out, "Head", { math.sin(t * 1.3 + 0.4) * 2, math.sin(t * 0.5) * 14, 0 })
	both(out, "UpperArm", { 12 + breath * 3 - 8 * moving, 0, 8 })
	both(out, "Forearm", { 24 + breath * 4 })
	both(out, "LowerArm", { 16 + math.sin(t * 1.3 + 1) * 3, 0, 4 })
	both(out, "LowerForearm", { 34 + math.sin(t * 1.3 + 1.4) * 4 })
end

local REST = {}

local function punch(arm, lower)
	local up, fore = if lower then "LowerArm" else "UpperArm", if lower then "LowerForearm" else "Forearm"
	return { [arm .. up] = { 88, 0, if arm == "Right" then -6 else 6 }, [arm .. fore] = { -8 } }
end

local function merged(...)
	local out = {}
	for _, t in ipairs({ ... }) do
		for k, v in pairs(t) do out[k] = v end
	end
	return out
end

local GUARD = {
	Root = { -6, 0, 0, 0, 0, -0.8 },
	["*UpperArm"] = { 40, 0, -4 },
	["*Forearm"] = { 70 },
	["*LowerArm"] = { 30, 0, -4 },
	["*LowerForearm"] = { 70 },
}

Djinn.moves = {
	orb = clip({
		marks = { throw = 0.6 },
		keys = {
			{ 0, REST },
			{ 0.42, {
				Root = { 6, 28, 0, 0, 0.4, 0.4 },
				Head = { 0, -20, 0 },
				RightUpperArm = { -55, 0, 30 },
				RightForearm = { 45 },
				LeftUpperArm = { 50, 0, -20 },
				LeftForearm = { 30 },
			}, "io" },
			{ 0.6, {
				Root = { -12, -22, 0, 0, 0, -1.0 },
				Head = { -6, 14, 0 },
				RightUpperArm = { 115, 0, 8 },
				RightForearm = { 0 },
				LeftUpperArm = { -20, 0, -16 },
				LeftForearm = { 20 },
			}, "snap" },
			{ 0.85, {
				Root = { -10, -18, 0, 0, 0, -0.8 },
				RightUpperArm = { 95, 0, 8 },
				RightForearm = { 8 },
				LeftUpperArm = { -14, 0, -14 },
			}, "out" },
			{ 1.3, REST, "io" },
		},
	}),

	storm = clip({
		marks = { call = 0.9 },
		keys = {
			{ 0, REST },
			{ 0.7, {
				Root = { 8, 0, 0, 0, 2.2, 0 },
				Head = { 28, 0, 0 },
				["*UpperArm"] = { 165, 0, -24 },
				["*Forearm"] = { 8 },
				["*LowerArm"] = { 100, 0, -34 },
				["*LowerForearm"] = { 16 },
			}, "io" },
			{ 0.9, {
				Root = { -4, 0, 0, 0, 1.6, 0 },
				Head = { -8, 0, 0 },
				["*UpperArm"] = { 110, 0, -40 },
				["*Forearm"] = { 0 },
				["*LowerArm"] = { 70, 0, -40 },
				["*LowerForearm"] = { 10 },
			}, "snap" },
			{ 1.4, {
				Root = { -3, 0, 0, 0, 1.4, 0 },
				["*UpperArm"] = { 100, 0, -36 },
				["*LowerArm"] = { 62, 0, -36 },
			}, "out" },
			{ 2.0, REST, "io" },
		},
		extra = function(out, t)
			if t > 0.2 and t < 0.88 then
				local shake = 3
				add(out, "RightUpperArm", { math.sin(t * 61) * shake, 0, math.sin(t * 47) * shake })
				add(out, "LeftUpperArm", { math.sin(t * 53) * shake, 0, math.sin(t * 43) * shake })
				add(out, "Head", { 0, 0, math.sin(t * 37) * 2 })
			end
		end,
	}),

	flurry = clip({
		marks = { hit1 = 0.45, hit2 = 0.65, hit3 = 0.85, hit4 = 1.05 },
		keys = {
			{ 0, REST },
			{ 0.3, GUARD, "io" },
			{ 0.45, merged(GUARD, punch("Right", true), { Root = { -10, -12, 0, 0, 0, -1.2 } }), "snap" },
			{ 0.55, GUARD, "io" },
			{ 0.65, merged(GUARD, punch("Left", true), { Root = { -10, 12, 0, 0, 0, -1.2 } }), "snap" },
			{ 0.75, GUARD, "io" },
			{ 0.85, merged(GUARD, punch("Right", false), { Root = { -12, -16, 0, 0, 0, -1.4 } }), "snap" },
			{ 0.95, GUARD, "io" },
			{ 1.05, merged(GUARD, punch("Left", false), { Root = { -14, 16, 0, 0, 0, -1.6 } }), "snap" },
			{ 1.2, merged(GUARD, punch("Left", false), { Root = { -10, 12, 0, 0, 0, -1.2 } }), "out" },
			{ 1.6, REST, "io" },
		},
	}),

	whirl = clip({
		marks = { blast = 1.4 },
		keys = {
			{ 0, REST },
			{ 0.35, {
				Root = { 0, 0, 0, 0, 1.2, 0 },
				Head = { 10, 0, 0 },
				["*UpperArm"] = { 10, 0, 74 },
				["*Forearm"] = { 10 },
				["*LowerArm"] = { 0, 0, 62 },
				["*LowerForearm"] = { 10 },
				Vortex = { 0, 0, 0 },
			}, "back" },
			{ 1.25, {
				Root = { 0, 0, 0, 0, 1.4, 0 },
				Head = { 10, 0, 0 },
				["*UpperArm"] = { 10, 0, 78 },
				["*Forearm"] = { 10 },
				["*LowerArm"] = { 0, 0, 66 },
				["*LowerForearm"] = { 10 },
			}, "lin" },
			{ 1.4, {
				Root = { -10, 0, 0, 0, 0.6, -0.6 },
				Head = { -6, 0, 0 },
				["*UpperArm"] = { 80, 0, 40 },
				["*Forearm"] = { 0 },
				["*LowerArm"] = { 70, 0, 30 },
				["*LowerForearm"] = { 0 },
			}, "snap" },
			{ 2.0, REST, "io" },
		},
		-- The whole body spins with the storm until the blast.
		extra = function(out, t)
			if t < 1.4 then
				local spin = t * t * 260
				add(out, "Root", { 0, spin % 360, 0 })
			end
		end,
	}),
}

return Djinn
