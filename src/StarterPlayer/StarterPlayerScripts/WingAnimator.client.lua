--[[
	WingAnimator

	Moves the joints of every worn pair of wings (WingService puts a WornWings
	model on the wearer's back), on every client, gives them their effects
	(Shared.Flight.WingParticles), and draws everyone's fall trail - all from
	what every client can see: the character's Flying attribute (set by the
	server) and how the body is moving.

	  resting     held a little closed behind the shoulders, breathing
	  take-off    big, quick beats
	  hovering    full, steady beats
	  cruising    two beats, then a glide on spread wings, and again
	  boosting    tucked back for speed
	  sinking     spread and held: a glide

	THE BEAT

	Shaped like a bird's, not a sine wave. The downstroke is the quicker part
	of the beat (`down`, under half) and the wing is fully open for it: that
	is the stroke that lifts. On the slower upstroke the outer wing folds back
	and its tip trails low, so it slips up through the air, then flicks open
	at the top, ready for the next downstroke. The shoulder barely sweeps:
	a touch forward while pushing down, a touch back while rising. The wing
	twists a little the same way (leading edge down on the push). Feathers,
	plumes, crystals, leaves, claws and thorns lag the stroke, and quiver in
	the airflow when the wings are held.

	Between beats - gliding, boosting, resting - the wing eases to a held pose,
	and the beat's weight eases in and out, so starting and stopping flapping
	is never a jump. The local player's beat is also published as the
	character's WingPulse attribute: FlightClient lifts the body a little on
	each downstroke, so the bob and the beat line up.

	Each pair has a Style (an attribute on its model, set by BuildWings):

	  Feather   angel, flame, frost and leaf
	  Membrane  bat and demon: the outer wing folds harder on the upstroke
	  Fairy     four lobes that clap behind the back, insect-fast in the air,
	            the lower pair a moment behind the upper

	Joints are found by name: L_ / R_ picks the side, the rest the role.
	Rotations are in the frame's axes (X across the back, Y up, Z rearward):
	flap about Z and sweep about Y mirror between the wings; twist, about the
	wing's own length (X), does not.

	EFFECTS

	  auras       the pair's library assemblies on each outer piece, streaming
	              in flight, with a burst at take-off
	  take-off    a ring of air and a swirl at the feet, dust on the ground
	  falling     for anyone falling at terminal velocity: a ribbon of wind
	              behind them, streaks of air rushing past, and a ring of air
	              when they reach it (every character, wings or not;
	              FlightClient holds the fall at that speed)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WingParticles = require(Shared:WaitForChild("Flight"):WaitForChild("WingParticles"))
local Pack = require(Shared:WaitForChild("Abilities"):WaitForChild("VFX"):WaitForChild("PackAssembly"))
local Scope = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityScope"))

local player = Players.LocalPlayer

local MODEL_NAME = "WornWings"
local CULL_DISTANCE = 250 -- studs from the camera beyond which nothing is animated
local TAKEOFF_TIME = 0.6
local EASE = 3.5 -- 1/s, how quickly a state's numbers are reached
local WEIGHT_EASE = 5 -- 1/s, how quickly flapping starts and stops
local MEMBRANE_FOLD = 1.4 -- membrane wings fold harder on the upstroke
local AURA_BRIGHTNESS = 3

--[[
	Per state (degrees unless said):

	  stroke   0-1, how much the beat drives the wing; 0 holds it
	  rate     beats per second
	  down     share of the beat spent pushing down
	  amp      half the beat's height, about `lift`
	  sweep    shoulder swept back through the beat; fwd / back the little
	           extra forward on the push and back on the rise
	  fold     outer wing folded back at mid-upstroke; droop, its tip lowered
	  twist    leading edge down on the push, up on the rise
	  trail    feather follow-through
	  hold*    the held pose: arm lift and sweep, outer wing fold and flap
	  breath   1 at rest: slow breathing instead of airflow quiver
	  beats / glide   flap-glide rhythm: this many beats, then glide this long
]]
local BASE = {
	stroke = 0, rate = 1, down = 0.45, amp = 0, lift = 0, sweep = 0, fwd = 0, back = 0,
	fold = 0, droop = 0, twist = 0, trail = 3,
	holdLift = 0, holdSweep = 0, holdFold = 0, holdFan = 0, breath = 0,
}

local function state(values)
	local full = table.clone(BASE)
	for key, value in pairs(values) do
		full[key] = value
	end
	return full
end

local STATES = {
	rest = state({ holdLift = -6, holdSweep = 22, holdFold = 18, holdFan = -8, trail = 2, breath = 1 }),
	takeoff = state({
		stroke = 1, rate = 1.9, down = 0.4, amp = 44, lift = 8, sweep = 6, fwd = 5, back = 9,
		fold = 30, droop = 18, twist = 7, trail = 10, holdLift = 8, holdSweep = 6, holdFold = 4,
	}),
	hover = state({
		stroke = 1, rate = 1.2, down = 0.44, amp = 36, lift = 10, sweep = 6, fwd = 5, back = 10,
		fold = 32, droop = 20, twist = 7, trail = 9, holdLift = 10, holdSweep = 8, holdFold = 4,
	}),
	cruise = state({
		stroke = 1, rate = 1.0, down = 0.42, amp = 28, lift = 6, sweep = 14, fwd = 4, back = 9,
		fold = 26, droop = 14, twist = 6, trail = 7, holdLift = 8, holdSweep = 14, holdFold = 6, holdFan = 2,
		beats = 2, glide = 1.3,
	}),
	boost = state({ holdLift = 4, holdSweep = 46, holdFold = 26, holdFan = -6, trail = 4 }),
	glide = state({ holdLift = 12, holdSweep = 8, holdFold = 2, holdFan = 3, trail = 5 }),
}

-- Fairy lobes clap about the vertical axis: a sweep that beats, with a rise
-- and twist in step with it.
local FAIRY_BASE = { stroke = 0, rate = 1, amp = 0, sweep = 0, rise = 0, twist = 0, holdSweep = 0, holdFlap = 0, breath = 0 }
local function fairy(values)
	local full = table.clone(FAIRY_BASE)
	for key, value in pairs(values) do
		full[key] = value
	end
	return full
end
local FAIRY = {
	rest = fairy({ holdSweep = 24, holdFlap = 2, breath = 1 }),
	takeoff = fairy({ stroke = 1, rate = 6.5, amp = 34, sweep = 30, rise = 8, twist = 8, holdSweep = 30 }),
	hover = fairy({ stroke = 1, rate = 5.5, amp = 30, sweep = 32, rise = 7, twist = 7, holdSweep = 30 }),
	cruise = fairy({ stroke = 1, rate = 5, amp = 24, sweep = 40, rise = 6, twist = 6, holdSweep = 40 }),
	boost = fairy({ stroke = 1, rate = 4.5, amp = 12, sweep = 58, rise = 3, twist = 3, holdSweep = 58 }),
	glide = fairy({ stroke = 0.4, rate = 2, amp = 10, sweep = 26, rise = 3, twist = 2, holdSweep = 26 }),
}

-- model -> rig; character -> fall trail. Strong tables, cleared when the model
-- or character goes: a weak table keyed by an Instance can lose the entry while
-- the Instance lives on (its Lua wrapper is collected), which rebuilt rigs - and
-- their effects - over and over.
local rigs = {}
local falls = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local rad = math.rad

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function easeInOut(s)
	return (1 - math.cos(math.pi * s)) / 2
end

--[[
	Where a beat is at `u` (0-1, starting at the top): position F (+1 top,
	-1 bottom), and how far into the push (Dn) or the rise (Up) it is, each a
	bell that is 0 at both ends of its half.
]]
local function beatAt(u, down)
	if u < down then
		local s = u / down
		return 1 - 2 * easeInOut(s), math.sin(math.pi * s), 0
	end
	local s = (u - down) / (1 - down)
	return -1 + 2 * easeInOut(s), 0, math.sin(math.pi * s)
end

local function roleOf(name)
	local side = if name:sub(1, 2) == "L_" then -1 elseif name:sub(1, 2) == "R_" then 1 else 0
	local rest = if side ~= 0 then name:sub(3) else name
	local role, index = rest:match("^(%a+)(%d*)$")
	return side, role or rest, tonumber(index) or 0
end

local function joint(j, flap, sweep, twist)
	j.joint.Transform = CFrame.Angles(rad(twist), -j.side * rad(sweep), j.side * rad(flap))
end

-- A mounted library assembly rides `part`: unanchored, weightless, welded.
local function weld(model, part)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = part
			w.Part1 = d
			w.Parent = d
		end
	end
end

local function mount(scope, parent, entry, host)
	local template = WingParticles.template(entry)
	if not template then
		return nil
	end
	local handle = Pack.mount(scope, parent, entry[1], {
		template = template,
		scale = entry[3],
		tint = entry[4],
		budget = entry[5],
		brightness = AURA_BRIGHTNESS,
		locked = entry.locked,
		cframe = host.CFrame,
	})
	weld(handle.model, host)
	if entry.zOffset then
		for _, e in ipairs(handle.emitters) do
			e.v.ZOffset += entry.zOffset
		end
	end
	return handle
end

-- ---------------------------------------------------------------------------
-- Rigs
-- ---------------------------------------------------------------------------

local function buildFx(rig, model, character)
	local scope = Scope.new()
	rig.scope = scope
	local function finish()
		scope:destroy()
		rigs[model] = nil
	end
	model.Destroying:Connect(finish)
	-- A respawn can drop the old character without destroying it.
	scope:add(model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			finish()
		end
	end))

	rig.auras = {}
	local style = WingParticles.Styles[model:GetAttribute("ItemName")]
	if style then
		for _, part in ipairs(model:GetChildren()) do
			if part:IsA("BasePart") then
				local _, role = roleOf(part.Name)
				if role == "Fan" or role == "Upper" or role == "Lower" then
					for _, entry in ipairs(style) do
						-- A stud nearer the camera, or the wing they sit inside hides them.
						entry.zOffset = entry.zOffset or 1
						local handle = mount(scope, model, entry, part)
						if handle then
							table.insert(rig.auras, handle)
						end
					end
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
		scope:add(feet)
		rig.ring = WingParticles.make("Ring", { Enabled = false })
		rig.ring.Parent = feet
		rig.swirl = WingParticles.make("Swirl", { Enabled = false })
		rig.swirl.Parent = feet
		rig.puff = WingParticles.make("Puff", { Enabled = false })
		rig.puff.Parent = feet
	end
end

local function rigFor(model, character)
	local rig = rigs[model]
	if rig then
		return rig
	end
	rig = {
		joints = {},
		style = model:GetAttribute("Style") or "Feather",
		u = math.random(),
		w = 0,
		beating = true,
		beats = 0,
		glideUntil = 0,
		params = nil,
		aurasOn = false,
	}
	for _, j in ipairs(model:GetDescendants()) do
		if j:IsA("Motor6D") then
			local side, role, index = roleOf(j.Name)
			if side ~= 0 then
				table.insert(rig.joints, { joint = j, side = side, role = role, index = index })
			end
		end
	end
	buildFx(rig, model, character)
	rigs[model] = rig
	return rig
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function takeOff(rig, character)
	-- Start on a full downstroke, already half committed to it.
	rig.u = 0
	rig.beating = true
	rig.beats = 0
	rig.w = math.max(rig.w, 0.6)
	if rig.ring then
		rig.ring:Emit(2)
		rig.swirl:Emit(2)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			groundParams.FilterDescendantsInstances = { character }
			if Workspace:Raycast(root.Position, Vector3.new(0, -6, 0), groundParams) then
				rig.puff:Emit(10)
			end
		end
	end
	for _, aura in ipairs(rig.auras) do
		aura:burst(0.5)
	end
end

local function stateOf(character, rig, now)
	local flying = character:GetAttribute("Flying") == true
	if flying and not rig.flying then
		rig.flyingSince = now
		takeOff(rig, character)
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
		if type(value) == "number" and type(params[key]) == "number" then
			params[key] += (value - params[key]) * k
		end
	end
	return params
end

-- Runs the beat clock and the flap-glide rhythm, and eases the beat's weight.
local function advance(rig, target, p, now, dt)
	if rig.beating then
		rig.u += p.rate * dt
		if rig.u >= 1 then
			rig.u -= 1
			rig.beats += 1
			if target.beats and rig.beats >= target.beats then
				rig.beating = false
				rig.beats = 0
				rig.glideUntil = now + (target.glide or 1)
			end
		end
	elseif not target.beats or now >= rig.glideUntil then
		rig.beating = true
		rig.beats = 0
		rig.u = 0
	end
	local want = if rig.beating then p.stroke else 0
	rig.w += (want - rig.w) * (1 - math.exp(-WEIGHT_EASE * dt))
end

local function poseFeather(rig, p, t)
	local F, Dn, Up = beatAt(rig.u, p.down)
	local w = rig.w
	local still = 1 - w
	local breath = p.breath * math.sin(t * 1.6)
	local sway = still * (1 - p.breath) * math.sin(t * 1.1)
	local fold = p.fold * (if rig.style == "Membrane" then MEMBRANE_FOLD else 1)
	local quiver = still * lerp(1.2, 0.35, p.breath)
	for _, j in ipairs(rig.joints) do
		local role = j.role
		if role == "Arm" then
			joint(
				j,
				lerp(p.holdLift, p.lift + p.amp * F, w) + breath * 1.5 + sway * 1.5,
				lerp(p.holdSweep, p.sweep + p.back * Up - p.fwd * Dn, w) + breath,
				w * p.twist * (Up - Dn)
			)
		elseif role == "Fan" then
			joint(
				j,
				lerp(p.holdFan, -p.droop * Up + 3 * Dn, w) + breath,
				lerp(p.holdFold, fold * Up, w),
				w * p.twist * 0.6 * (Up - Dn)
			)
		else
			local reach = 1 + j.index * 0.08
			local amount = p.trail * reach * (if role == "Claw" or role == "Thorn" then 1.5 else 1)
			local shiver = quiver * math.sin(t * 9 + j.index * 1.7 + j.side)
			joint(j, w * amount * (Dn - 0.6 * Up) + shiver, w * amount * 0.4 * Up, 0)
		end
	end
	return w * (Dn - p.down * 2 / math.pi)
end

local function poseFairy(rig, p, t)
	local w = rig.w
	for _, j in ipairs(rig.joints) do
		local lower = j.role == "Lower"
		local F = beatAt((rig.u - (if lower then 0.08 else 0)) % 1, 0.5)
		local breath = p.breath * math.sin(t * 1.6 + (if lower then 0.6 else 0))
		local sweep = lerp(p.holdSweep, p.sweep + p.amp * F, w) * (if lower then 0.9 else 1) + breath * 2
		local flap = lerp(p.holdFlap, p.rise * F, w) * (if lower then -1 else 1)
		joint(j, flap, sweep, w * p.twist * F)
	end
	return 0
end

local function updateAuras(rig)
	local on = rig.flying == true
	if rig.aurasOn ~= on then
		rig.aurasOn = on
		for _, aura in ipairs(rig.auras) do
			aura:stream(on)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Falling
-- ---------------------------------------------------------------------------

local Fall = WingParticles.Fall

local function fallFor(character, root)
	local fall = falls[character]
	if fall then
		return fall
	end
	fall = { on = false }
	falls[character] = fall
	local scope = Scope.new()
	fall.scope = scope
	scope:add(character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(Workspace) then
			scope:destroy()
			falls[character] = nil
		end
	end))
	fall.lines = mount(scope, character, Fall.lines, root)

	-- The ribbon: a Trail between the shoulders.
	local look = Fall.trail
	local left = Instance.new("Attachment")
	left.Name = "FallTrailLeft"
	left.Position = Vector3.new(-look.span.X, look.span.Y, look.span.Z)
	left.Parent = root
	local right = Instance.new("Attachment")
	right.Name = "FallTrailRight"
	right.Position = look.span
	right.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "FallTrail"
	trail.Texture = look.texture
	trail.TextureMode = Enum.TextureMode.Static
	trail.TextureLength = look.textureLength
	trail.Color = look.color
	trail.Transparency = look.transparency
	trail.WidthScale = look.widthScale
	trail.Lifetime = look.lifetime
	trail.LightEmission = look.lightEmission
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Attachment0 = left
	trail.Attachment1 = right
	trail.Enabled = false
	trail.Parent = root
	fall.trail = trail
	scope:add(left)
	scope:add(right)
	scope:add(trail)

	-- The ring of air on reaching terminal velocity.
	local waist = Instance.new("Attachment")
	waist.Name = "FallRing"
	waist.Parent = root
	scope:add(waist)
	fall.ring = WingParticles.make("Ring", { Enabled = false })
	fall.ring.Parent = waist
	return fall
end

local function updateFall(character, root)
	local sinking = -root.AssemblyLinearVelocity.Y
	local fall = falls[character]
	local on
	if character:GetAttribute("Flying") == true then
		on = false
	elseif fall and fall.on then
		on = sinking > Fall.terminal * Fall.trailTo
	else
		on = sinking > Fall.terminal * Fall.trailFrom
	end
	if on and not fall then
		fall = fallFor(character, root)
	end
	if fall and fall.on ~= on then
		fall.on = on
		if fall.lines then
			fall.lines:stream(on)
		end
		if fall.trail then
			if on then
				fall.trail:Clear()
			end
			fall.trail.Enabled = on
		end
		if on and fall.ring then
			fall.ring:Emit(2)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Each step
-- ---------------------------------------------------------------------------

-- PreSimulation, not RenderStepped: the character's Animator rewrites the
-- Transform of every Motor6D under the character in its animation step, which
-- runs after RenderStepped and before PreSimulation.
RunService.PreSimulation:Connect(function(dt)
	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	local now = os.clock()
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - eye).Magnitude < CULL_DISTANCE then
			updateFall(character, root)

			local model = character:FindFirstChild(MODEL_NAME)
			if model and model.PrimaryPart then
				local rig = rigFor(model, character)
				local name = stateOf(character, rig, now)
				local target = (if rig.style == "Fairy" then FAIRY else STATES)[name]
				local p = ease(rig, target, dt)
				advance(rig, target, p, now, dt)
				local pulse = if rig.style == "Fairy" then poseFairy(rig, p, now) else poseFeather(rig, p, now)
				updateAuras(rig)
				if other == player then
					character:SetAttribute("WingPulse", if rig.flying then pulse else 0)
				end
			end
		end
	end
end)
