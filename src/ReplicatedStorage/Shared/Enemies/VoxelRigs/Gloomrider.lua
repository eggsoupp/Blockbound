--[[
	Gloomrider: the steed trots in diagonal pairs and stretches into a
	gallop as the speed rises; the rider sits the bounce, the ghost-fire tail
	streams, and the horse tosses its head now and then.

	  charge  the horse half-rears as the lance comes down to the couch; at
	          `go` the server drives it forward, the gallop running off its
	          real speed, until `stop`
	  sweep   lance lowered and the rider twisted back, then swept across at `hit`
	  stomp   the horse rears high, forehooves pawing, and crashes down at `hit`
]]

local P = require(script.Parent.Player)
local add, both, clip = P.add, P.addBoth, P.clip
local V = Vector3.new

local Rider = { voxel = 0.2 }

Rider.sockets = {
	lanceTip = { part = "Lance", at = V(9.5, 88, -26), pivot = V(9, 42.5, -9) },
	visor = { part = "RiderHead", at = V(0, 60, -4), pivot = V(0, 56, 0) },
	chest = { part = "Steed", at = V(0, 31, -18), pivot = V(0, 30, 0) },
	rightHoof = { part = "RightForehoof", at = V(5, 1, -12), pivot = V(5, 14, -13) },
	leftHoof = { part = "LeftForehoof", at = V(-5, 1, -12), pivot = V(-5, 14, -13) },
}

function Rider.base(rig, ctx, out)
	local t = ctx.t
	local s, moving = P.gait(rig, ctx, 13, 10)
	local a, b = s, s + math.pi
	local function leg(name, phase, sign)
		local swing = math.sin(phase) * (if name == "Fore" then 30 else 24) * moving
		local fold = math.max(0, math.cos(phase)) * (if name == "Fore" then 55 else 30) * moving
		add(out, sign .. name .. "leg", { swing })
		add(out, sign .. name .. "hoof", { -fold })
	end
	leg("Fore", a, "Right")
	leg("Hind", a, "Left")
	leg("Fore", b, "Left")
	leg("Hind", b, "Right")

	-- Now and then, standing, a forehoof paws the ground.
	local paw = (1 - moving) * math.max(0, math.sin(t * 0.7)) ^ 10
	add(out, "RightForeleg", { paw * 40 })
	add(out, "RightForehoof", { -paw * 60 })

	local bounce = math.abs(math.sin(s)) * moving
	add(out, "Root", { math.sin(s * 2) * 2 * moving - 2 * moving, 0, 0, 0, bounce * 0.6 + math.sin(t * 1.0) * 0.05, 0 })
	add(out, "SteedNeck", { math.sin(s * 2 + 0.4) * 5 * moving + math.sin(t * 0.9) * 3 * (1 - moving), math.sin(t * 0.35) * 8 * (1 - moving), 0 })
	add(out, "SteedHead", { -math.sin(s * 2 + 0.4) * 3 * moving + math.max(0, math.sin(t * 0.6)) ^ 8 * 16 })
	add(out, "SteedTail", { -20 * moving + math.sin(t * 1.4) * 4, math.sin(t * 2.2) * 12, 0 })

	add(out, "RiderTorso", { -math.sin(s * 2 + 0.6) * 4 * moving - 6 * moving + math.sin(t * 1.1) * 1.5, math.sin(t * 0.3) * 6, 0 })
	add(out, "RiderHead", { math.sin(t * 1.1 + 0.4) * 2, math.sin(t * 0.5) * 12, 0 })
	add(out, "RightUpperArm", { math.sin(t * 1.1) * 2, 0, 0 })
	add(out, "LeftUpperArm", { 8 + math.sin(t * 1.1 + 1) * 2, 0, 0 })
end

local REST = {}

Rider.moves = {
	charge = clip({
		marks = { go = 0.8, stop = 1.9 },
		keys = {
			{ 0, REST },
			{ 0.7, {
				RiderTorso = { -16, 0, 0 },
				RiderHead = { -6, 0, 0 },
				RightUpperArm = { 18, 0, 6 },
				RightForearm = { 10 },
				Lance = { -100 },
				LeftUpperArm = { 30, 0, -10 },
				LeftForearm = { 30 },
				SteedNeck = { -16 },
				SteedHead = { -10 },
			}, "io" },
			{ 1.9, {
				RiderTorso = { -20, 0, 0 },
				RiderHead = { -4, 0, 0 },
				RightUpperArm = { 18, 0, 6 },
				RightForearm = { 10 },
				Lance = { -100 },
				LeftUpperArm = { 30, 0, -10 },
				LeftForearm = { 30 },
				SteedNeck = { -22 },
				SteedHead = { -12 },
			}, "lin" },
			{ 2.3, REST, "io" },
		},
		-- A half-rear while the lance comes down, laid over the gait so the
		-- legs keep galloping off the real speed afterwards.
		extra = function(out, t)
			if t < 0.8 then
				local up = math.sin(math.clamp(t / 0.8, 0, 1) * math.pi)
				add(out, "Root", { 14 * up, 0, 0, 0, 1.2 * up, 0.8 * up })
				add(out, "RightForeleg", { 50 * up })
				add(out, "RightForehoof", { -70 * up })
				add(out, "LeftForeleg", { 35 * up })
				add(out, "LeftForehoof", { -60 * up })
			end
		end,
	}),

	sweep = clip({
		marks = { hit = 0.5 },
		keys = {
			{ 0, REST },
			{ 0.32, {
				RiderTorso = { -6, -48, 0 },
				RiderHead = { 0, 30, 0 },
				RightUpperArm = { 30, 0, 30 },
				RightForearm = { 10 },
				Lance = { -105 },
				SteedNeck = { 0, 10, 0 },
			}, "io" },
			{ 0.5, {
				RiderTorso = { -10, 46, 0 },
				RiderHead = { 0, -24, 0 },
				RightUpperArm = { 40, 0, 10 },
				RightForearm = { 10 },
				Lance = { -105 },
				SteedNeck = { 0, -12, 0 },
			}, "snap" },
			{ 0.7, {
				RiderTorso = { -8, 54, 0 },
				RiderHead = { 0, -20, 0 },
				RightUpperArm = { 36, 0, 8 },
				RightForearm = { 10 },
				Lance = { -100 },
			}, "out" },
			{ 1.1, REST, "io" },
		},
	}),

	stomp = clip({
		marks = { hit = 0.85 },
		keys = {
			{ 0, REST },
			{ 0.6, {
				Root = { 18, 0, 0, 0, 2.2, 1.6 },
				SteedNeck = { 22, 0, 0 },
				SteedHead = { 10, 0, 0 },
				SteedTail = { 20 },
				["*Foreleg"] = { 62 },
				["*Forehoof"] = { -85 },
				["*Hindleg"] = { -16 },
				["*Hindhoof"] = { -10 },
				RiderTorso = { -24, 0, 0 },
				RightUpperArm = { 40, 0, 0 },
				Lance = { -20 },
				LeftUpperArm = { 20, 0, -20 },
			}, "io" },
			{ 0.85, {
				Root = { -6, 0, 0, 0, -0.5, -0.6 },
				SteedNeck = { -20, 0, 0 },
				SteedHead = { -12, 0, 0 },
				["*Foreleg"] = { -14 },
				["*Forehoof"] = { 0 },
				["*Hindleg"] = { 8 },
				RiderTorso = { 8, 0, 0 },
				RightUpperArm = { 10, 0, 0 },
				Lance = { 0 },
				LeftUpperArm = { 10, 0, -10 },
			}, "in" },
			{ 1.1, {
				Root = { -4, 0, 0, 0, -0.3, -0.4 },
				SteedNeck = { -14, 0, 0 },
				["*Foreleg"] = { -10 },
				RiderTorso = { 4, 0, 0 },
			}, "out" },
			{ 1.5, REST, "io" },
		},
		extra = function(out, t)
			-- Forehooves paw the air at the top of the rear.
			if t > 0.35 and t < 0.75 then
				local paw = math.sin((t - 0.35) * 22)
				add(out, "RightForeleg", { paw * 14 })
				add(out, "LeftForeleg", { -paw * 14 })
			end
		end,
	}),
}

return Rider
