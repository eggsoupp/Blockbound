--[[
	WingAnimator

	Moves the joints of every worn pair of wings (WingService puts a WornWings
	model on the wearer's back), on every client, from two things everyone can
	see: the character's Flying attribute (set by the server) and how the body
	is moving.

	  resting     folded back into a V behind the shoulders, breathing slowly
	  take-off    one big, deep beat
	  hovering    full, quick strokes
	  cruising    slower, wider strokes, swept a little back
	  boosting    tucked back for speed, barely beating
	  sinking     held up and spread: a glide

	Each pair has a Style (an attribute on its model, set by BuildWings):

	  Feather   angel, flame, frost and leaf: arm flaps at the shoulder, the
	            fan folds on the upstroke, and every feather, plume, crystal
	            or leaf trails the stroke a little, one after another
	  Membrane  bat and demon: as Feather, but the fan folds harder on the
	            upstroke, like fingers closing, and claws and thorns flick
	  Fairy     four lobes that clap behind the back, insect-fast in the air

	Joints are found by name: L_ / R_ picks the side, the rest the role. All
	rotations are in the frame's axes (X across the back, Y up, Z rearward):
	flap is about Z, sweep about Y. The state's numbers are eased rather than
	switched, and the stroke runs on a phase that only ever advances, so a
	change of state never jumps a wing.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MODEL_NAME = "WornWings"
local CULL_DISTANCE = 250 -- studs from the camera beyond which wings are left still

-- Per state: rate (beats/s), amp (degrees of flap), lift (resting flap angle),
-- sweep (degrees swept back at the shoulder), fold (fan folded back), upFold
-- (extra fan fold on the upstroke), trail (secondary lag, degrees).
local STATES = {
	rest = { rate = 0.22, amp = 3, lift = -10, sweep = 42, fold = 28, upFold = 0, trail = 2 },
	takeoff = { rate = 2.2, amp = 48, lift = 6, sweep = 4, fold = 2, upFold = 30, trail = 10 },
	hover = { rate = 1.7, amp = 34, lift = 8, sweep = 8, fold = 4, upFold = 26, trail = 8 },
	cruise = { rate = 1.15, amp = 24, lift = 4, sweep = 22, fold = 8, upFold = 18, trail = 7 },
	boost = { rate = 0.6, amp = 6, lift = 2, sweep = 50, fold = 22, upFold = 4, trail = 4 },
	glide = { rate = 0.35, amp = 4, lift = 14, sweep = 10, fold = 0, upFold = 0, trail = 3 },
}

-- Fairy lobes clap about the vertical axis instead: a sweep that oscillates.
local FAIRY = {
	rest = { rate = 0.35, amp = 4, sweep = 46 },
	takeoff = { rate = 9, amp = 34, sweep = 36 },
	hover = { rate = 8, amp = 30, sweep = 38 },
	cruise = { rate = 7, amp = 24, sweep = 44 },
	boost = { rate = 6, amp = 12, sweep = 62 },
	glide = { rate = 2, amp = 8, sweep = 30 },
}

local MEMBRANE_UPFOLD = 1.5 -- membrane fans close harder on the upstroke
local EASE = 4 -- 1/s, how quickly a state's numbers are reached
local TAKEOFF_TIME = 0.55

-- model -> rig { joints = {...}, style, params, phase, flying, flyingSince }
local rigs = setmetatable({}, { __mode = "k" })

local function roleOf(name)
	local side = if name:sub(1, 2) == "L_" then -1 elseif name:sub(1, 2) == "R_" then 1 else 0
	local rest = if side ~= 0 then name:sub(3) else name
	local role, index = rest:match("^(%a+)(%d*)$")
	return side, role or rest, tonumber(index) or 0
end

local function rigFor(model)
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
	rigs[model] = rig
	return rig
end

local function stateOf(character, rig, now)
	local flying = character:GetAttribute("Flying") == true
	if flying and not rig.flying then
		rig.flyingSince = now
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

local function poseFeather(rig, p)
	local phase = rig.phase
	local stroke = math.sin(phase) -- +1 top of the stroke, -1 bottom
	local upstroke = math.max(0, math.cos(phase)) -- rising half
	local upFold = p.upFold * (if rig.style == "Membrane" then MEMBRANE_UPFOLD else 1)
	for _, j in ipairs(rig.joints) do
		local s, role = j.side, j.role
		local flap, sweep = 0, 0
		if role == "Arm" then
			flap = p.lift + p.amp * stroke
			sweep = p.sweep
		elseif role == "Fan" then
			-- The outer wing lags the arm and closes as it rises.
			flap = p.amp * 0.35 * math.sin(phase - 0.6)
			sweep = p.fold + upFold * upstroke
		else
			-- Feathers, plumes, crystals, leaves, claws, thorns: trailing follow-through.
			local lag = 1.0 + j.index * 0.18
			local amount = if role == "Claw" or role == "Thorn" then p.trail * 1.6 else p.trail
			flap = amount * math.sin(phase - lag)
			sweep = amount * 0.5 * math.sin(phase - lag - 0.8)
		end
		j.joint.Transform = CFrame.Angles(0, -s * rad(sweep), s * rad(flap))
	end
end

local function poseFairy(rig, p)
	local phase = rig.phase
	for _, j in ipairs(rig.joints) do
		local lower = j.role == "Lower"
		local beat = math.sin(phase - (if lower then 0.5 else 0))
		local sweep = p.sweep + p.amp * beat
		local flap = (if lower then -6 else 6) + p.amp * 0.15 * beat
		j.joint.Transform = CFrame.Angles(0, -j.side * rad(sweep * (if lower then 0.9 else 1)), j.side * rad(flap))
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
			local rig = rigFor(model)
			local state = stateOf(character, rig, now)
			if rig.style == "Fairy" then
				local p = ease(rig, FAIRY[state], dt)
				rig.phase += p.rate * 2 * math.pi * dt
				poseFairy(rig, p)
			else
				local p = ease(rig, STATES[state], dt)
				rig.phase += p.rate * 2 * math.pi * dt
				poseFeather(rig, p)
			end
		end
	end
end)
