--[[
	Abyssal Kraken: hovers and pulses like something underwater - the mantle
	breathes, the body bobs, and every tentacle curls in a slow wave that
	runs root to tip, each one out of step with its neighbours. Moving, the
	lower tentacles stream back.

	  slam  the two front tentacles reared high, then slammed down ahead at `hit`
	  grab  the right front tentacle lashes out at `lash`, hauls back at
	        `pull`, and the beak bites at `bite`
	  ink   everything drawn in tight, then flung wide as the ink bursts at `burst`
]]

local P = require(script.Parent.Player)
local add, both, clip = P.add, P.addBoth, P.clip
local V = Vector3.new

local Kraken = { voxel = 0.2 }

Kraken.sockets = {
	beak = { part = "Beak", at = V(0, 27, -4), pivot = V(0, 31, -3) },
	mantle = { part = "Mantle", at = V(0, 70, 10), pivot = V(0, 44, 0) },
	grabTip = { part = "RightFrontTentacleTip", at = V(7.5, 60, -13), pivot = V(14.13, 39, -7.51) },
	eyes = { part = "Head", at = V(0, 40, -9), pivot = V(0, 40, -1) },
}

local TENTACLES = { "FrontTentacle", "SideTentacle", "BackTentacle" }

function Kraken.base(rig, ctx, out)
	local t = ctx.t
	local _, moving = P.gait(rig, ctx, 10, 5.5)
	local pulse = math.sin(t * 1.1)
	add(out, "Root", { pulse * 3 - 8 * moving, 0, math.sin(t * 0.5) * 2, 0, 0.3 + pulse * 0.6, 0 })
	add(out, "Head", { math.sin(t * 1.1 + 0.6) * 2, math.sin(t * 0.4) * 6, 0 })
	add(out, "Beak", { math.max(0, math.sin(t * 2.3)) * 6 })
	for k, name in ipairs(TENTACLES) do
		for side = 1, 2 do
			local phase = t * 1.5 + k * 1.3 + side * 2.1
			local sign = if side == 1 then 1 else -1
			local trail = if name == "FrontTentacle" then 0 else -14 * moving
			add(out, (if side == 1 then "Right" else "Left") .. name, {
				math.sin(phase) * 9 + trail, 0, (math.cos(phase) * 7 - pulse * 3) * sign,
			})
			add(out, (if side == 1 then "Right" else "Left") .. name .. "Tip", {
				math.sin(phase - 1.0) * 16 + trail * 0.6, 0, math.cos(phase - 1.0) * 12 * sign,
			})
		end
	end
end

local REST = {}

Kraken.moves = {
	slam = clip({
		marks = { hit = 0.7 },
		keys = {
			{ 0, REST },
			{ 0.5, {
				Root = { 10, 0, 0, 0, 1.4, 0.6 },
				Head = { 8, 0, 0 },
				["*FrontTentacle"] = { 30, 0, 24 },
				["*FrontTentacleTip"] = { 46, 0, 10 },
				["*SideTentacle"] = { 0, 0, 14 },
			}, "io" },
			{ 0.7, {
				Root = { -14, 0, 0, 0, -0.4, -0.8 },
				Head = { -12, 0, 0 },
				["*FrontTentacle"] = { -62, -18, -26 },
				["*FrontTentacleTip"] = { -40, 0, -8 },
				["*SideTentacle"] = { 0, 0, -6 },
			}, "snap" },
			{ 1.0, {
				Root = { -10, 0, 0, 0, -0.3, -0.6 },
				Head = { -8, 0, 0 },
				["*FrontTentacle"] = { -56, -16, -22 },
				["*FrontTentacleTip"] = { -34, 0, -6 },
			}, "out" },
			{ 1.4, REST, "io" },
		},
	}),

	grab = clip({
		marks = { lash = 0.55, pull = 0.8, bite = 1.15 },
		keys = {
			{ 0, REST },
			{ 0.4, {
				Root = { 4, -16, 0, 0, 0.6, 0.4 },
				RightFrontTentacle = { 36, -10, 30 },
				RightFrontTentacleTip = { 50, 0, 20 },
			}, "io" },
			{ 0.55, {
				Root = { -10, 10, 0, 0, 0, -0.6 },
				RightFrontTentacle = { -52, 40, -12 },
				RightFrontTentacleTip = { -70, 0, 0 },
			}, "snap" },
			{ 0.8, {
				Root = { -6, 6, 0, 0, 0, -0.4 },
				RightFrontTentacle = { -40, 34, -10 },
				RightFrontTentacleTip = { -55, 0, 0 },
			}, "lin" },
			{ 1.0, {
				Root = { 8, 0, 0, 0, 0.6, 0.6 },
				Head = { 10, 0, 0 },
				Beak = { 28 },
				RightFrontTentacle = { 30, 0, 26 },
				RightFrontTentacleTip = { 60, 0, 10 },
			}, "out" },
			{ 1.15, {
				Root = { -16, 0, 0, 0, -0.6, -1.0 },
				Head = { -16, 0, 0 },
				Beak = { -6 },
				RightFrontTentacle = { 0, 0, 10 },
				RightFrontTentacleTip = { 20, 0, 0 },
			}, "snap" },
			{ 1.6, REST, "io" },
		},
	}),

	ink = clip({
		marks = { burst = 0.8 },
		keys = {
			{ 0, REST },
			{ 0.6, {
				Root = { 0, 0, 0, 0, -0.8, 0 },
				Head = { -4, 0, 0 },
				["*FrontTentacle"] = { 10, 0, -10 },
				["*FrontTentacleTip"] = { 40, 0, 0 },
				["*SideTentacle"] = { 0, 0, -18 },
				["*SideTentacleTip"] = { 0, 0, 30 },
				["*BackTentacle"] = { -12, 0, -10 },
				["*BackTentacleTip"] = { -30, 0, 0 },
			}, "io" },
			{ 0.8, {
				Root = { 0, 0, 0, 0, 1.6, 0 },
				Head = { 8, 0, 0 },
				["*FrontTentacle"] = { 10, 0, 34 },
				["*FrontTentacleTip"] = { -10, 0, 20 },
				["*SideTentacle"] = { 0, 0, 36 },
				["*SideTentacleTip"] = { 0, 0, -10 },
				["*BackTentacle"] = { 18, 0, 30 },
				["*BackTentacleTip"] = { 10, 0, -6 },
			}, "back" },
			{ 1.6, REST, "io" },
		},
		extra = function(out, t)
			if t > 0.15 and t < 0.75 then
				add(out, "Root", { math.sin(t * 45) * 2, 0, math.sin(t * 37) * 2 })
			end
		end,
	}),
}

return Kraken
