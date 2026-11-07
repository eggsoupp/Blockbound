--[[
	WingAnimator

	Moves the joints of every worn pair of wings (WingService puts a WornWings
	model on the wearer's back), on every client, and gives them their particle
	effects (Shared.Flight.WingParticles), from two things everyone can see:
	the character's Flying attribute (set by the server) and how the body is
	moving.

	  resting     open, much as built, breathing slowly with a little sway
	  take-off    one big, deep beat
	  hovering    full, quick strokes
	  cruising    slower strokes, swept a little back
	  boosting    tucked back for speed, barely beating
	  sinking     held up and spread: a glide

	THE STROKE

	A beat is not just up and down: that would push air sideways, not down. The
	wing traces a figure of eight. It sweeps forward as it comes down and back
	as it rises (sweep follows cos of the phase while flap follows sin), and
	it twists along its length, leading edge down on the downstroke and up on
	the way back, so it bites the air going down and slices it coming up. The
	outer wing (fan) lags the arm and folds on the upstroke; every feather,
	plume, crystal, leaf, claw or thorn trails a little more.

	Each pair has a Style (an attribute on its model, set by BuildWings):

	  Feather   angel, flame, frost and leaf
	  Membrane  bat and demon: the fan closes harder on the upstroke, like
	            fingers, and claws and thorns flick
	  Fairy     four lobes that clap behind the back, insect-fast in the air,
	            with a small rise and fall and a twist of their own

	Joints are found by name: L_ / R_ picks the side, the rest the role. All
	rotations are in the frame's axes (X across the back, Y up, Z rearward):
	flap is about Z, sweep about Y, twist about X. The state's numbers are eased
	rather than switched, and the stroke runs on a phase that only ever
	advances, so a change of state never jumps a wing.

	EFFECTS

	Each wing's outer piece carries the pair's trail emitters, their Rate eased
	between rest, flight and speed. The bottom of every full downstroke pushes
	a swirl of air down from each wing. Take-off throws a ring of air and a
	swirl at the feet, and dust if there is ground close below.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WingParticles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Flight"):WaitForChild("WingParticles"))

local MODEL_NAME = "WornWings"
local CULL_DISTANCE = 250 -- studs from the camera beyond which wings are left still
local TWO_PI = 2 * math.pi

-- Per state: rate (beats/s), amp (degrees of flap), lift (flap angle the beat
-- centres on), sweep (degrees swept back at the shoulder), swing (fore-aft
-- sweep through the beat), twist (degrees of twist through the beat), fold
-- (fan folded back), upFold (extra fan fold on the upstroke), trail
-- (secondary lag, degrees), fx (trail rate: 0 rest, 1 flight, 2 speed).
local STATES = {
	rest = { rate = 0.25, amp = 3, lift = 2, sweep = 6, swing = 2, twist = 1, fold = 3, upFold = 0, trail = 2, fx = 0 },
	takeoff = { rate = 2.2, amp = 46, lift = 6, sweep = 12, swing = 26, twist = 14, fold = 2, upFold = 28, trail = 10, fx = 1 },
	hover = { rate = 1.7, amp = 32, lift = 8, sweep = 14, swing = 22, twist = 12, fold = 4, upFold = 24, trail = 8, fx = 1 },
	cruise = { rate = 1.15, amp = 22, lift = 4, sweep = 20, swing = 14, twist = 9, fold = 8, upFold = 16, trail = 7, fx = 1.5 },
	boost = { rate = 0.6, amp = 6, lift = 2, sweep = 48, swing = 4, twist = 3, fold = 22, upFold = 4, trail = 4, fx = 2 },
	glide = { rate = 0.35, amp = 4, lift = 14, sweep = 10, swing = 2, twist = 2, fold = 0, upFold = 0, trail = 3, fx = 1 },
}

-- Fairy lobes clap about the vertical axis: a sweep that oscillates, with a
-- smaller rise and fall (rise) and twist on top.
local FAIRY = {
	rest = { rate = 0.35, amp = 4, sweep = 10, rise = 2, twist = 1, fx = 0 },
	takeoff = { rate = 9, amp = 34, sweep = 30, rise = 10, twist = 10, fx = 1 },
	hover = { rate = 8, amp = 30, sweep = 32, rise = 9, twist = 9, fx = 1 },
	cruise = { rate = 7, amp = 24, sweep = 40, rise = 7, twist = 7, fx = 1.5 },
	boost = { rate = 6, amp = 12, sweep = 60, rise = 4, twist = 4, fx = 2 },
	glide = { rate = 2, amp = 8, sweep = 24, rise = 3, twist = 2, fx = 1 },
}

local MEMBRANE_UPFOLD = 1.5 -- membrane fans close harder on the upstroke
local EASE = 4 -- 1/s, how quickly a state's numbers are reached
local TAKEOFF_TIME = 0.55
local GUST_STATES = { takeoff = true, hover = true, cruise = true }

-- model -> rig { joints, style, params, phase, flying, flyingSince, fx }
local rigs = setmetatable({}, { __mode = "k" })

local function roleOf(name)
	local side = if name:sub(1, 2) == "L_" then -1 elseif name:sub(1, 2) == "R_" then 1 else 0
	local rest = if side ~= 0 then name:sub(3) else name
	local role, index = rest:match("^(%a+)(%d*)$")
	return side, role or rest, tonumber(index) or 0
end

-- The particle emitters: trails and gusts on each wing's outer pieces,
-- take-off ring, swirl and dust on the wearer's root.
local function buildFx(model, character)
	local style = WingParticles.Styles[model:GetAttribute("ItemName")]
	if not style then
		return nil
	end
	local fx = { trails = {}, gusts = {}, cycle = nil }
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			local _, role = roleOf(part.Name)
			if role == "Fan" or role == "Upper" or role == "Lower" then
				for _, trail in ipairs(style.trails) do
					local emitter = WingParticles.make(trail[1], { Color = trail[2], Rate = trail[3] })
					emitter.Parent = part
					table.insert(fx.trails, { emitter = emitter, rest = trail[3], fly = trail[4], rate = trail[3] })
				end
				if style.gust and role == "Fan" then
					local gust = WingParticles.make("Gust", { Color = ColorSequence.new(style.gust), Enabled = false })
					gust.Parent = part
					table.insert(fx.gusts, gust)
				end
			end
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local feet = Instance.new("Attachment")
		feet.Name = "WingTakeoffFx"
		feet.Position = Vector3.new(0, -2.6, 0)
		feet.Parent = root
		fx.feet = feet
		fx.ring = WingParticles.make("Ring", { Enabled = false })
		fx.ring.Parent = feet
		fx.swirl = WingParticles.make("Swirl", { Enabled = false })
		fx.swirl.Parent = feet
		fx.puff = WingParticles.make("Puff", { Enabled = false })
		fx.puff.Parent = feet
		-- The attachment goes with the wings, not the character.
		model.Destroying:Connect(function()
			feet:Destroy()
		end)
	end
	return fx
end

local function rigFor(model, character)
	local rig = rigs[model]
	if rig then
		return rig
	end
	rig = { joints = {}, style = model:GetAttribute("Style") or "Feather", phase = math.random() * 10, params = nil }
	for _, joint in ipairs(model:GetDescendants()) do
		if joint:IsA("Motor6D") then
			local side, role, index = roleOf(joint.Name)
			if side ~= 0 then
				table.insert(rig.joints, { joint = joint, side = side, role = role, index = index })
			end
		end
	end
	rig.fx = buildFx(model, character)
	rigs[model] = rig
	return rig
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function takeoffFx(rig, character)
	local fx = rig.fx
	if not fx or not fx.feet then
		return
	end
	fx.ring:Emit(2)
	fx.swirl:Emit(2)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		groundParams.FilterDescendantsInstances = { character }
		if Workspace:Raycast(root.Position, Vector3.new(0, -6, 0), groundParams) then
			fx.puff:Emit(10)
		end
	end
	for _, trail in ipairs(fx.trails) do
		trail.emitter:Emit(4)
	end
end

local function stateOf(character, rig, now)
	local flying = character:GetAttribute("Flying") == true
	if flying and not rig.flying then
		rig.flyingSince = now
		takeoffFx(rig, character)
	end
	rig.flying = flying
	if not flying then
		return "rest"
	end
	if now - (rig.flyingSince or 0) < TAKEOFF_TIME then
		return "takeoff"
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
	local flat = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if velocity.Y < -6 and flat < 40 then
		return "glide"
	end
	if flat > 40 then
		return "boost"
	end
	if flat > 14 then
		return "cruise"
	end
	return "hover"
end

local function ease(rig, target, dt)
	local params = rig.params
	if not params then
		rig.params = table.clone(target)
		return rig.params
	end
	local k = 1 - math.exp(-EASE * dt)
	for key, value in pairs(target) do
		params[key] += (value - params[key]) * k
	end
	return params
end

local rad = math.rad

local function joint(j, flap, sweep, twist)
	-- Flap (Z) and sweep (Y) mirror between the wings; twist, about the wing's
	-- own length (X), does not: a mirror leaves rotation about its normal alone.
	-- Positive twist raises the leading (forward, -Z) edge.
	j.joint.Transform = CFrame.Angles(rad(twist), -j.side * rad(sweep), j.side * rad(flap))
end

local function poseFeather(rig, p)
	local phase = rig.phase
	local stroke = math.sin(phase) -- +1 top of the stroke, -1 bottom
	local travel = math.cos(phase) -- < 0 on the downstroke, > 0 rising
	local upstroke = math.max(0, travel)
	local upFold = p.upFold * (if rig.style == "Membrane" then MEMBRANE_UPFOLD else 1)
	for _, j in ipairs(rig.joints) do
		local role = j.role
		if role == "Arm" then
			-- Forward on the way down, back on the way up; leading edge down
			-- while it bites, up while it returns.
			joint(j, p.lift + p.amp * stroke, p.sweep + p.swing * travel, p.twist * travel)
		elseif role == "Fan" then
			-- The outer wing lags the arm and closes as it rises.
			local lagged = phase - 0.6
			joint(j, p.amp * 0.35 * math.sin(lagged), p.fold + upFold * upstroke + p.swing * 0.4 * math.cos(lagged), p.twist * 0.6 * math.cos(lagged))
		else
			-- Feathers, plumes, crystals, leaves, claws, thorns: follow-through.
			local lag = 1.0 + j.index * 0.18
			local amount = if role == "Claw" or role == "Thorn" then p.trail * 1.6 else p.trail
			joint(j, amount * math.sin(phase - lag), amount * 0.6 * math.sin(phase - lag - 0.8), amount * 0.5 * math.cos(phase - lag))
		end
	end
end

local function poseFairy(rig, p)
	local phase = rig.phase
	for _, j in ipairs(rig.joints) do
		local lower = j.role == "Lower"
		local local_ = phase - (if lower then 0.5 else 0)
		local beat = math.sin(local_)
		local sweep = (p.sweep + p.amp * beat) * (if lower then 0.9 else 1)
		local flap = (if lower then -4 else 4) + p.rise * math.cos(local_) * (if lower then -1 else 1)
		joint(j, flap, sweep, p.twist * math.cos(local_))
	end
end

local function updateFx(rig, p, state, dt)
	local fx = rig.fx
	if not fx then
		return
	end
	-- Trails: ease the Rate, but only write it when it really changes - an
	-- emitter whose Rate is rewritten every frame can stop emitting.
	local k = 1 - math.exp(-3 * dt)
	for _, trail in ipairs(fx.trails) do
		local target = if p.fx < 0.5 then trail.rest else trail.fly * p.fx
		trail.rate += (target - trail.rate) * k
		local rounded = math.floor(trail.rate + 0.5)
		if trail.emitter.Rate ~= rounded then
			trail.emitter.Rate = rounded
		end
	end
	-- Gusts: one swirl per wing at the bottom of each full downstroke.
	if #fx.gusts > 0 then
		local cycle = math.floor((rig.phase - 1.5 * math.pi) / TWO_PI)
		if fx.cycle and cycle ~= fx.cycle and GUST_STATES[state] then
			for _, gust in ipairs(fx.gusts) do
				gust:Emit(1)
			end
		end
		fx.cycle = cycle
	end
end

-- PreSimulation, not RenderStepped: the character's Animator rewrites the
-- Transform of every Motor6D under the character in its animation step, which
-- runs after RenderStepped and before PreSimulation.
RunService.PreSimulation:Connect(function(dt)
	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local model = character and character:FindFirstChild(MODEL_NAME)
		local frame = model and model.PrimaryPart
		if frame and (frame.Position - eye).Magnitude < CULL_DISTANCE then
			local rig = rigFor(model, character)
			local state = stateOf(character, rig, now)
			local p = ease(rig, (if rig.style == "Fairy" then FAIRY else STATES)[state], dt)
			rig.phase += p.rate * TWO_PI * dt
			if rig.style == "Fairy" then
				poseFairy(rig, p)
			else
				poseFeather(rig, p)
			end
			updateFx(rig, p, state, dt)
		end
	end
end)
