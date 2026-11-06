--[[
	SignusRig

	Client half of Signus's body: its joints, eyes and aura, for every model
	tagged "SignusRig". Started by SignusVisuals.

	JOINTS. The server plans each move as a retargeted pack clip
	(Shared.Enemies.SignusClips) and writes the plan to the model's
	SignusClip attribute; every client plays the same plan from the server
	clock, so a release lands on the frame the damage does. Between moves the
	rig breathes in a procedural idle chosen by SignusStance: "hover" (phase
	one), "flight" (sleeves swept back like wings), "spent" (hood bowed,
	sleeves hanging: a recovery window). Transform is written in
	PreSimulation, after any Animator, and eased so a new plan never snaps.

	APPEARANCE. SignusPhase picks the colourway of one authored aura
	(SignusEclipseLibrary AuraViolet, SoulShroud character aura #152, violet
	over black; phase two recolours its bright layers a darker purple and
	thickens it). Each limb's emitter set goes onto the matching piece of the
	robe, scaled from an R6 limb to Signus. The eyes carry the pack's flare
	(#46): pearl and steady in phase one, burning violet and trailing in phase
	two.

	DECOYS. Mirror Veil's images (SignusDecoy = the phase they were cast in)
	are the same rig. Phase one's are easy to tell: no aura and no eyes.
	Phase two's carry the full aura and the eyes.
]]

local Collection = game:GetService("CollectionService")
local Run = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clips = require(ReplicatedStorage.Shared.Enemies.SignusClips)
local Scope = require(script.Parent.Parent.AbilityScope)

local Rig = {}

local JOINTS = { core = "CoreJoint", hood = "HoodJoint", left = "LeftSleeveJoint", right = "RightSleeveJoint" }
local FADE_IN, FADE_OUT = 0.1, 0.3
local DRAW_DISTANCE = 420

-- R6 limb -> Signus piece, for the aura's per-limb emitter sets.
local LIMBS = {
	Torso = "Core",
	Head = "Hood",
	["Left Arm"] = "LeftSleeve",
	["Right Arm"] = "RightSleeve",
	["Left Leg"] = "CoreLower",
	["Right Leg"] = "CoreLower",
}
-- Signus is about three times an R6 character.
local AURA_SCALE = { 2.6, 3 }
local AURA_RATE = { 0.55, 1 }
-- Phase two's aura: the violet aura's bright layers, darker.
local DUSK = { main = Color3.fromRGB(88, 16, 170), edge = Color3.fromRGB(150, 54, 255) }

-- The eyes in RootPart space at rest (build_signus.py eye voxels through the
-- exporter's axes), a little proud of the face.
local EYES = { Vector3.new(-0.75, 5.95, -1.4), Vector3.new(0.75, 5.95, -1.4) }

local pearl = Color3.fromRGB(255, 226, 246)
local dusk = Color3.fromRGB(196, 72, 255)

local rigs = {}
local started = false

local function library()
	return ReplicatedStorage:FindFirstChild("SignusEclipseLibrary")
end

local function ns(a: number, b: number?)
	return NumberSequence.new(a, b or a)
end

local function scaleSequence(sequence: NumberSequence, factor: number): NumberSequence
	local keys = {}
	for _, key in sequence.Keypoints do
		table.insert(keys, NumberSequenceKeypoint.new(key.Time, key.Value * factor, key.Envelope * factor))
	end
	return NumberSequence.new(keys)
end

-- Rest frames of each piece relative to the root, from the joints themselves.
local function restFrames(rig)
	local frames = {}
	local core = rig.motors.core
	if core then
		frames.Core = core.C0 * core.C1:Inverse()
		for _, key in { "hood", "left", "right" } do
			local motor = rig.motors[key]
			if motor then
				frames[motor.Part1.Name] = frames.Core * motor.C0 * motor.C1:Inverse()
			end
		end
	end
	return frames
end

local function mountAura(rig, phase: number)
	if rig.auraScope then
		rig.auraScope:destroy()
	end
	local scope = Scope.new()
	rig.auraScope = scope
	if phase == 0 then -- a husk: no aura
		return
	end
	local lib = library()
	local template = lib and lib:FindFirstChild("AuraViolet")
	if not template then
		return
	end
	local rate = AURA_RATE[phase] or 1
	local size = AURA_SCALE[phase] or AURA_SCALE[1]
	-- Through a see-through robe the aura's dark smoke swallows the figure.
	if rig.model:GetAttribute("SignusDecoy") == 1 then
		return
	end
	for _, limb in template:GetChildren() do
		local pieceName = LIMBS[limb.Name]
		local piece = pieceName and rig.model:FindFirstChild(pieceName, true)
		if piece and limb:IsA("BasePart") then
			for _, source in limb:GetChildren() do
				if source:IsA("ParticleEmitter") then
					local emitter = scope:add(source:Clone())
					emitter.Name = "SignusAura"
					emitter.Size = scaleSequence(source.Size, size)
					emitter.Speed = NumberRange.new(source.Speed.Min * size, source.Speed.Max * size)
					emitter.Acceleration = source.Acceleration * size
					emitter.Rate = source.Rate * rate
					emitter.LightInfluence = 0
					if phase == 2 then
						-- Bright keys take the darker purple; the black backing stays black.
						local keys = {}
						for _, key in source.Color.Keypoints do
							local c = key.Value
							local lum = math.max(c.R, c.G, c.B)
							local color = if lum < 0.25 then c elseif lum >= 0.9 then DUSK.edge else DUSK.main
							table.insert(keys, ColorSequenceKeypoint.new(key.Time, color))
						end
						emitter.Color = ColorSequence.new(keys)
					end
					emitter.Parent = piece
				end
			end
		end
	end
end

local function mountEyes(rig, phase: number)
	if rig.eyeScope then
		rig.eyeScope:destroy()
	end
	local scope = Scope.new()
	rig.eyeScope = scope
	if phase == 0 or rig.model:GetAttribute("SignusDecoy") == 1 then
		return
	end
	local lib = library()
	local flare = lib and lib:FindFirstChild("EyeFlare")
	local source = flare and flare:FindFirstChildWhichIsA("ParticleEmitter", true)
	local hood = rig.model:FindFirstChild("Hood", true)
	local rest = rig.rest.Hood
	if not (source and hood and rest) then
		return
	end
	local strong = phase == 2
	for _, eye in EYES do
		local attachment = scope:add(Instance.new("Attachment"))
		attachment.Name = "SignusEye"
		attachment.CFrame = rest:Inverse() * CFrame.new(eye)
		attachment.Parent = hood
		-- The steady glow, locked to the hood.
		local glow = source:Clone()
		glow.Name = "SignusEyeGlow"
		glow.LockedToPart = true
		glow.Size = scaleSequence(source.Size, if strong then 0.6 else 0.3)
		glow.Speed = NumberRange.new(0)
		glow.Rate = if strong then 40 else 24
		glow.Color = ColorSequence.new(if strong then dusk else pearl)
		glow.Brightness = if strong then 4 else 1.8
		glow.LightInfluence = 0
		glow.Parent = attachment
		if strong then
			-- Free particles left behind as it moves: the eyes streak.
			local streak = source:Clone()
			streak.Name = "SignusEyeStreak"
			streak.LockedToPart = false
			streak.Size = scaleSequence(source.Size, 0.3)
			streak.Speed = NumberRange.new(0)
			streak.Lifetime = NumberRange.new(0.35)
			streak.Rate = 60
			streak.Color = ColorSequence.new(dusk)
			streak.Brightness = 2.4
			streak.LightInfluence = 0
			streak.Parent = attachment
		end
	end
end

-- Procedural rest poses between moves.
local function idle(stance: string?, t: number, phase: number)
	local breath = math.sin(t * 1.9)
	local sway = math.sin(t * 1.3 + 0.7)
	if stance == "spent" then
		return {
			core = CFrame.Angles(0.12 + breath * 0.02, 0, 0),
			hood = CFrame.Angles(0.38, 0, 0),
			left = CFrame.Angles(0.15, 0, -0.45 - breath * 0.04),
			right = CFrame.Angles(0.15, 0, 0.45 + breath * 0.04),
		}
	elseif stance == "flight" then
		-- Sleeves swept back and out: a silhouette of wings.
		local beat = math.sin(t * 3.1)
		return {
			core = CFrame.Angles(0.1, 0, 0),
			hood = CFrame.Angles(-0.08, 0, 0),
			left = CFrame.Angles(0.55 + beat * 0.08, 0.25, -0.7 - beat * 0.12),
			right = CFrame.Angles(0.55 + beat * 0.08, -0.25, 0.7 + beat * 0.12),
		}
	end
	local spread = if phase == 2 then 0.32 else 0.18
	return {
		core = CFrame.Angles(breath * 0.015, 0, 0),
		hood = CFrame.Angles(-0.04 + breath * 0.025, sway * 0.04, 0),
		left = CFrame.Angles(-0.05 + sway * 0.05, 0, -spread - breath * 0.05),
		right = CFrame.Angles(-0.05 - sway * 0.05, 0, spread + breath * 0.05),
	}
end

local function track(model: Instance)
	if rigs[model] or not model:IsA("Model") then
		return
	end
	local motors = {}
	for key, name in JOINTS do
		local motor = model:FindFirstChild(name, true)
		if motor and motor:IsA("Motor6D") then
			motors[key] = motor
		end
	end
	if not motors.core then
		return
	end
	local rig = { model = model, motors = motors, current = {}, clock = math.random() * 10 }
	for key in motors do
		rig.current[key] = CFrame.identity
	end
	rig.rest = restFrames(rig)
	rigs[model] = rig
end

local function untrack(model: Instance)
	local rig = rigs[model]
	if not rig then
		return
	end
	rigs[model] = nil
	if rig.auraScope then
		rig.auraScope:destroy()
	end
	if rig.eyeScope then
		rig.eyeScope:destroy()
	end
	for _, motor in rig.motors do
		if motor.Parent then
			motor.Transform = CFrame.identity
		end
	end
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local now = workspace:GetServerTimeNow()
	for model, rig in rigs do
		if not model:IsDescendantOf(workspace) then
			untrack(model)
			continue
		end
		local phase = model:GetAttribute("SignusPhase") or 1
		if rig.phase ~= phase then
			rig.phase = phase
			mountAura(rig, phase)
			mountEyes(rig, phase)
		end
		local pivot = model:GetPivot().Position
		if camera and (camera.CFrame.Position - pivot).Magnitude > DRAW_DISTANCE then
			continue
		end
		rig.clock += dt

		local raw = model:GetAttribute("SignusClip")
		if raw ~= rig.raw then
			rig.raw = raw
			rig.plan, rig.started = Clips.decode(raw)
		end
		local base = idle(model:GetAttribute("SignusStance"), rig.clock, phase)
		local target = base
		if rig.plan and rig.started then
			local elapsed = now - rig.started
			local t, done = Clips.clipTime(rig.plan, elapsed)
			local weight = math.clamp(elapsed / FADE_IN, 0, 1)
			if done then
				weight *= 1 - math.clamp((elapsed - rig.plan.marks.finish) / FADE_OUT, 0, 1)
			end
			if weight > 0 then
				local pose = Clips.pose(rig.plan.name, t)
				target = {}
				for key, cf in base do
					target[key] = cf:Lerp(pose[key], weight)
				end
			end
		end
		-- Ease toward the target, quickly: a release must still read as a snap.
		local ease = 1 - math.exp(-dt * 28)
		for key, motor in rig.motors do
			local goal = target[key] or CFrame.identity
			rig.current[key] = rig.current[key]:Lerp(goal, ease)
			motor.Transform = rig.current[key]
		end
	end
end

function Rig.start()
	if started then
		return
	end
	started = true
	Collection:GetInstanceAddedSignal("SignusRig"):Connect(track)
	Collection:GetInstanceRemovedSignal("SignusRig"):Connect(untrack)
	for _, model in Collection:GetTagged("SignusRig") do
		track(model)
	end
	Run.PreSimulation:Connect(step)
end

return Rig
