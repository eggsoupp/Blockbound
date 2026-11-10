--[[
	FlightClient

	Flight, for whoever is wearing a pair of wings. GearService mirrors the
	worn `flight` buff into the player's CanFly attribute; only one pair can be
	worn (InventoryConstants.gearGroupClash), so it is simply on or off.

	CONTROLS

	  Double-tap jump      take off (on the ground, or already in the air);
	                       double-tap again while flying to fold the wings and drop
	  Move                 fly the way the camera faces. Looking up or down while
	                       flying forward climbs or dives, so a thumbstick alone
	                       can steer in three dimensions
	  Hold jump            climb
	  Ctrl / C / L2        descend
	  Sprint (Shift, RUN)  boost while flying forward
	  Land                 descend (or dive) onto the ground

	Flight is limited: see STAMINA. Weapons cannot be swung while flying
	(WeaponClient reads the character's Flying attribute); abilities can.

	HOW IT FLIES

	The character is the client's to move, so the whole of flight lives here and
	replicates the way walking does. While flying the Humanoid is PlatformStand
	(it stops walking, rotating and falling the body itself) and two
	constraints on the root take over:

	  a LinearVelocity, fed a velocity that eases towards the one the input
	  asks for - quickly when you push, slowly when you let go - which is the
	  momentum: you coast to a hover rather than stopping dead;

	  an AlignOrientation that faces where you are going, leans into speed
	  (more on a boost or a dive, back when reversing) and banks into turns
	  and strafes.

	Hovering bobs gently. Take-off starts with a lift, so it reads as a wing
	beat rather than a switch. The field of view widens with speed, and two
	wind wisps (the slash pack's wind texture, as the dash streak uses) stream
	off the shoulders at cruising speed.

	The poses are Roblox's own Levitation pack idle and run clips, played at
	Movement priority and cross-faded by speed; held-tool and swing clips still
	play over them, so a weapon can be swung in the air.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local MenuState = require(Shared:WaitForChild("UI"):WaitForChild("MenuState"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local WingParticles = require(Shared:WaitForChild("Flight"):WaitForChild("WingParticles"))

local player = Players.LocalPlayer

-- Take-off and landing go to the server (WingService), which sets the
-- character's Flying attribute for everyone: wing flaps, no swings.
local FlightState = nil
task.spawn(function()
	FlightState = Remotes.wait("FlightState")
end)
local function report(flying)
	if FlightState then
		FlightState:FireServer(flying)
	end
end

local FLIGHT = {
	cruise = 30, -- studs/s flying forward
	boost = 54, -- flying forward while sprinting
	climb = 22, -- holding jump or descend
	response = 3.4, -- how quickly velocity reaches what the input asks (1/s)
	glide = 1.5, -- the same once the input lets go: a coast, not a stop
	pitchSteer = 0.9, -- how much looking up/down turns forward flight into a climb/dive
	pitchDeadzone = 0.18, -- camera look Y inside which forward flight stays level
	takeoffLift = 18, -- upward speed of the first wing beat, eased away
	doubleTap = 0.3, -- seconds between the two jump taps
	landGrace = 0.5, -- seconds after take-off before the ground can land you
	landProbe = 0.9, -- studs below the feet that count as touching down
	landSink = 3, -- studs/s downward that count as coming in to land, so
	-- cruising level over a hill, or the hover bob, never lands you
	flareHeight = 7, -- studs above the ground where a descent starts to slow
	maxLean = 40, -- degrees of forward lean at cruise
	boostLean = 68, -- at full boost
	diveLean = 18, -- extra lean diving, less climbing
	backLean = 14, -- leaning back while reversing
	maxBank = 34, -- degrees of roll in a hard turn or strafe
	bankPerTurn = 22, -- degrees of roll per radian/s of turning
	turnResponsiveness = 12,
	bobHeight = 0.35, -- studs, while hovering
	bobRate = 0.55, -- cycles per second
	fovBase = 70,
	fovBoost = 14, -- added at full boost
	beatLift = 3, -- studs/s of lift per unit of WingPulse: the body rises on each downstroke
	trailSpeed = 0.85, -- fraction of cruise above which the wisps show
	descendKeys = { Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonL2 },
	animations = {
		hover = "rbxassetid://616006778", -- Levitation idle
		fly = "rbxassetid://616010382", -- Levitation run
	},
}

local WISP = {
	texture = "rbxassetid://16892374733",
	textureLength = 5.14,
	color = ColorSequence.new(Color3.fromRGB(236, 244, 255), Color3.fromRGB(200, 222, 255)),
	transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	}),
	widthScale = NumberSequence.new(1, 0.2),
	lifetime = 0.32,
	lightEmission = 0.5,
	-- Root-space shoulder points; each wisp is a short vertical span there.
	shoulders = { Vector3.new(-1.35, 0.75, 0.3), Vector3.new(1.35, 0.75, 0.3) },
	span = 0.35,
}

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

--[[
	Whatever control scripts are running (keyboard, gamepad, the touch
	thumbstick and jump button) all end at the Humanoid: MoveDirection is the
	camera-relative move, and it keeps updating while PlatformStand, and Jump is
	set every frame the jump input is held. So flight reads those rather than
	any one control module.
]]
local function moveInput(humanoid, flatLook, flatRight)
	local direction = humanoid.MoveDirection
	return direction:Dot(flatLook), direction:Dot(flatRight)
end

local function jumpHeld(humanoid)
	if humanoid and humanoid.Jump then
		return true
	end
	return UserInputService:GetFocusedTextBox() == nil and UserInputService:IsKeyDown(Enum.KeyCode.Space)
end

local function descendHeld()
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	for _, key in ipairs(FLIGHT.descendKeys) do
		if key.Name:sub(1, 6) == "Button" then
			for _, gamepad in ipairs(UserInputService:GetConnectedGamepads()) do
				if UserInputService:IsGamepadButtonDown(gamepad, key) then
					return true
				end
			end
		elseif UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local flight = nil -- the live flight, or nil on the ground
local lastJumpTap = -math.huge
local wasJumpHeld = false

--[[
	STAMINA

	Wings carry a limited flight: the worn pair's `flight` buff is seconds in
	the air (12 for the plainest, 20 for the best), mirrored by GearService into
	FlightTime. Flying spends it a second a second; standing on the ground
	refills it. In the last couple of seconds the wings tire - climbing fades
	and the body starts to sink - so running out is a glide down, not a drop
	from the sky. Out of time, the wings fold.
]]
local STAMINA = {
	refillTime = 4, -- seconds on the ground from empty to full
	minimum = 1, -- seconds needed to take off at all
	tiring = 2.5, -- seconds left at which the wings start to tire
	tiredSink = 9, -- studs/s of sink when nearly spent
}
local stamina = 0 -- seconds of flight in hand

local function flightTime()
	return math.max(0, tonumber(player:GetAttribute("FlightTime")) or 0)
end

-- Dev Flight (GearService mirrors its infiniteFlight buff): no wings needed,
-- no stamina spent, no meter.
local function infinite()
	return player:GetAttribute("InfiniteFlight") == true
end

local function canFly()
	return player:GetAttribute("CanFly") == true and (infinite() or flightTime() > 0)
end

local function bodyOf()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or humanoid.Health <= 0 then
		return nil
	end
	return character, humanoid, root
end

local function flatten(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-3 then
		return fallback
	end
	return flat.Unit
end

local function yawOf(direction)
	return math.atan2(-direction.X, -direction.Z)
end

local function wrapAngle(angle)
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function loadTrack(animator, id)
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if not ok then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Movement
	track.Looped = true
	return track
end

local function makeWisps(root)
	local wisps = {}
	for index, shoulder in ipairs(WISP.shoulders) do
		local top = Instance.new("Attachment")
		top.Name = "FlightWispTop" .. index
		top.Position = shoulder + Vector3.new(0, WISP.span / 2, 0)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Name = "FlightWispBottom" .. index
		bottom.Position = shoulder - Vector3.new(0, WISP.span / 2, 0)
		bottom.Parent = root

		local trail = Instance.new("Trail")
		trail.Name = "FlightWisp" .. index
		trail.Texture = WISP.texture
		trail.TextureMode = Enum.TextureMode.Static
		trail.TextureLength = WISP.textureLength
		trail.Color = WISP.color
		trail.Transparency = WISP.transparency
		trail.WidthScale = WISP.widthScale
		trail.Lifetime = WISP.lifetime
		trail.LightEmission = WISP.lightEmission
		trail.LightInfluence = 0
		trail.FaceCamera = true
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Enabled = false
		trail.Parent = root
		table.insert(wisps, { trail = trail, top = top, bottom = bottom })
	end
	return wisps
end

local function easeFov(target)
	local camera = Workspace.CurrentCamera
	if camera then
		TweenService:Create(camera, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			FieldOfView = target,
		}):Play()
	end
end

-- ---------------------------------------------------------------------------
-- Take-off and landing
-- ---------------------------------------------------------------------------

local function stopFlight()
	local current = flight
	if not current then
		return
	end
	flight = nil

	for _, track in pairs(current.tracks) do
		track:Stop(0.25)
	end
	for _, wisp in ipairs(current.wisps) do
		wisp.trail.Enabled = false
		task.delay(WISP.lifetime + 0.1, function()
			wisp.trail:Destroy()
			wisp.top:Destroy()
			wisp.bottom:Destroy()
		end)
	end
	current.velocity:Destroy()
	current.align:Destroy()
	current.attachment:Destroy()

	local character, humanoid, root = current.character, current.humanoid, current.root
	if character.Parent then
		character:SetAttribute("Flying", false)
		report(false)
	end
	if humanoid.Parent and humanoid.Health > 0 then
		-- Stand the body back up before handing it to the Humanoid, which
		-- would otherwise flop over from a dive's lean.
		local facing = flatten(root.CFrame.LookVector, Vector3.new(0, 0, -1))
		root.CFrame = CFrame.lookAt(root.Position, root.Position + facing)
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	easeFov(if character:GetAttribute("Sprinting") == true then 80 else FLIGHT.fovBase)
end

local function startFlight()
	if flight or not canFly() or MenuState.isAnyOpen() or (stamina < STAMINA.minimum and not infinite()) then
		return
	end
	local character, humanoid, root = bodyOf()
	if not character or humanoid.Sit or humanoid.SeatPart then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = root

	local start = root.AssemblyLinearVelocity
	local initial = Vector3.new(start.X, math.max(start.Y, FLIGHT.takeoffLift), start.Z)

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "Flight"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = root.AssemblyMass * 1500
	velocity.VectorVelocity = initial
	velocity.Parent = root

	local facing = flatten(root.CFrame.LookVector, Vector3.new(0, 0, -1))
	local align = Instance.new("AlignOrientation")
	align.Name = "FlightTilt"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.Responsiveness = FLIGHT.turnResponsiveness
	align.MaxTorque = math.huge
	align.MaxAngularVelocity = math.huge
	align.CFrame = CFrame.lookAt(Vector3.zero, facing)
	align.Parent = root

	humanoid.PlatformStand = true
	character:SetAttribute("Flying", true)
	report(true)

	local tracks = {}
	if animator then
		for name, id in pairs(FLIGHT.animations) do
			local track = loadTrack(animator, id)
			if track then
				track:Play(0.3, if name == "hover" then 1 else 0.01)
				tracks[name] = track
			end
		end
	end

	flight = {
		character = character,
		humanoid = humanoid,
		root = root,
		attachment = attachment,
		velocity = velocity,
		align = align,
		tracks = tracks,
		wisps = makeWisps(root),
		wanted = initial,
		startedAt = os.clock(),
		yaw = yawOf(facing),
		bank = 0,
		lean = 0,
	}

	Sounds.play("tool.swing")
end

-- ---------------------------------------------------------------------------
-- Each step
-- ---------------------------------------------------------------------------

local landParams = RaycastParams.new()
landParams.FilterType = Enum.RaycastFilterType.Exclude
landParams.IgnoreWater = false

local function step(dt)
	local current = flight
	if not current then
		return
	end
	local character, humanoid, root = current.character, current.humanoid, current.root
	if not character.Parent or not root.Parent or humanoid.Health <= 0 or humanoid.Sit or not canFly() then
		stopFlight()
		return
	end

	local camera = Workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local flatLook = flatten(look, flatten(root.CFrame.LookVector, Vector3.new(0, 0, -1)))
	local flatRight = Vector3.new(-flatLook.Z, 0, flatLook.X)

	local menuOpen = MenuState.isAnyOpen()
	local forward, side = 0, 0
	if not menuOpen then
		forward, side = moveInput(humanoid, flatLook, flatRight)
	end
	local climbing = not menuOpen and jumpHeld(humanoid)
	local descending = not menuOpen and descendHeld()

	-- What the input asks for.
	local steer = flatLook * forward + flatRight * side
	if steer.Magnitude > 1 then
		steer = steer.Unit
	end
	local boosting = character:GetAttribute("Sprinting") == true and forward > 0.2
	local speed = if boosting then FLIGHT.boost else FLIGHT.cruise
	local wanted = steer * speed

	if forward > 0 then
		local pitch = look.Y
		local beyond = math.max(0, math.abs(pitch) - FLIGHT.pitchDeadzone) / (1 - FLIGHT.pitchDeadzone)
		wanted += Vector3.yAxis * (math.sign(pitch) * beyond * forward * speed * FLIGHT.pitchSteer)
	end
	local vertical = (if climbing then 1 else 0) - (if descending then 1 else 0)
	wanted += Vector3.yAxis * (vertical * FLIGHT.climb)

	-- Spend stamina; tired wings stop climbing and start to sink. Dev Flight
	-- spends nothing.
	local tired = 0
	if not infinite() then
		stamina = math.max(0, stamina - dt)
		if stamina <= 0 then
			stopFlight()
			return
		end
		tired = 1 - math.clamp(stamina / STAMINA.tiring, 0, 1)
	end
	if tired > 0 then
		local y = wanted.Y
		if y > 0 then
			y *= 1 - tired
		end
		wanted = Vector3.new(wanted.X, y - tired * STAMINA.tiredSink, wanted.Z)
	end

	-- Flare: coming down onto the ground slows over the last few studs, so a
	-- landing settles rather than slams. Still fast enough to count as landing.
	-- The cap shrinks with the gap, so the slowing is smooth, and it holds the
	-- eased velocity too, which would otherwise lag in at full speed.
	local sinkCap = -math.huge
	if wanted.Y < 0 or current.wanted.Y < 0 then
		local feet = humanoid.HipHeight + root.Size.Y / 2
		landParams.FilterDescendantsInstances = { character }
		local below = Workspace:Raycast(root.Position, Vector3.new(0, -(feet + FLIGHT.flareHeight), 0), landParams)
		if below then
			local gap = math.max(0, root.Position.Y - below.Position.Y - feet)
			sinkCap = -(FLIGHT.landSink + 2 + gap * 2.5)
			wanted = Vector3.new(wanted.X, math.max(wanted.Y, sinkCap), wanted.Z)
		end
	end

	-- Hovering bobs; the bob fades out as soon as anything is asked for.
	local stillness = 1 - math.clamp(wanted.Magnitude / 6, 0, 1)
	local omega = 2 * math.pi * FLIGHT.bobRate
	wanted += Vector3.yAxis * (stillness * FLIGHT.bobHeight * omega * math.cos(os.clock() * omega))

	-- Momentum: ease towards it, slower when coasting. Height eases at the
	-- quicker rate either way, so letting go of climb holds altitude.
	local rate = if Vector3.new(wanted.X, 0, wanted.Z).Magnitude > 1 then FLIGHT.response else FLIGHT.glide
	local eased = current.wanted:Lerp(wanted, 1 - math.exp(-rate * dt))
	local height = current.wanted.Y + (wanted.Y - current.wanted.Y) * (1 - math.exp(-FLIGHT.response * dt))
	current.wanted = Vector3.new(eased.X, math.max(height, sinkCap), eased.Z)

	-- A dash (WeaponClient) pushes the root itself; stand aside for it and pick
	-- up from wherever it leaves the body.
	if root:FindFirstChild("Dash") then
		current.velocity.Enabled = false
		current.wanted = root.AssemblyLinearVelocity
	else
		current.velocity.Enabled = true
		-- The wings' beat (WingAnimator's WingPulse, zero on average) lifts the
		-- body a touch on each downstroke and lets it settle on the upstroke.
		local pulse = tonumber(character:GetAttribute("WingPulse")) or 0
		current.velocity.VectorVelocity = current.wanted + Vector3.yAxis * (pulse * FLIGHT.beatLift)
	end

	local velocity = current.wanted
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local horizontalSpeed = horizontal.Magnitude

	-- Face the camera while hovering or strafing, the flight path once moving
	-- forwards at speed.
	local facing = flatLook
	if horizontalSpeed > 4 then
		local along = horizontal.Unit
		local weight = math.clamp((horizontalSpeed - 4) / 10, 0, 1) * math.clamp((along:Dot(flatLook) - 0.2) / 0.4, 0, 1)
		facing = flatten(flatLook:Lerp(along, weight), flatLook)
	end
	local facingRight = Vector3.new(-facing.Z, 0, facing.X)

	-- Bank into turns and strafes.
	local yaw = yawOf(facing)
	local turnRate = wrapAngle(yaw - current.yaw) / math.max(dt, 1e-3)
	current.yaw = yaw
	local sideways = velocity:Dot(facingRight) / FLIGHT.cruise
	local bankTarget = math.clamp(turnRate * FLIGHT.bankPerTurn - sideways * 20, -FLIGHT.maxBank, FLIGHT.maxBank)
	current.bank += (bankTarget - current.bank) * (1 - math.exp(-6 * dt))

	-- Lean into speed: more on a boost or a dive, less climbing, back reversing.
	local ahead = velocity:Dot(facing)
	local lean
	if ahead >= 0 then
		lean = FLIGHT.maxLean * math.clamp(ahead / FLIGHT.cruise, 0, 1)
			+ (FLIGHT.boostLean - FLIGHT.maxLean) * math.clamp((ahead - FLIGHT.cruise) / (FLIGHT.boost - FLIGHT.cruise), 0, 1)
		lean += FLIGHT.diveLean * math.clamp(-velocity.Y / FLIGHT.cruise, -1, 1) * math.clamp(ahead / 8, 0, 1)
	else
		lean = -FLIGHT.backLean * math.clamp(-ahead / FLIGHT.cruise, 0, 1)
	end
	current.lean += (lean - current.lean) * (1 - math.exp(-5 * dt))

	current.align.CFrame = CFrame.lookAt(Vector3.zero, facing)
		* CFrame.Angles(-math.rad(current.lean), 0, 0)
		* CFrame.Angles(0, 0, math.rad(current.bank))

	-- Hover pose to flying pose by speed.
	local flying = math.clamp((horizontalSpeed - 5) / 16, 0, 1)
	if current.tracks.hover then
		current.tracks.hover:AdjustWeight(math.max(1 - flying, 0.01), 0.15)
	end
	if current.tracks.fly then
		current.tracks.fly:AdjustWeight(math.max(flying, 0.01), 0.15)
	end

	-- Field of view and wisps by speed.
	local speedNow = velocity.Magnitude
	local rush = math.clamp((speedNow - FLIGHT.cruise * 0.6) / (FLIGHT.boost - FLIGHT.cruise * 0.6), 0, 1)
	local fov = FLIGHT.fovBase + FLIGHT.fovBoost * rush
	camera.FieldOfView += (fov - camera.FieldOfView) * (1 - math.exp(-4 * dt))
	local streaming = speedNow > FLIGHT.cruise * FLIGHT.trailSpeed
	for _, wisp in ipairs(current.wisps) do
		wisp.trail.Enabled = streaming
	end

	-- Touching down: only while coming down (descend, or a dive), and once the
	-- take-off is clear.
	if not climbing and os.clock() - current.startedAt > FLIGHT.landGrace and current.wanted.Y < -FLIGHT.landSink then
		landParams.FilterDescendantsInstances = { character }
		local reach = humanoid.HipHeight + root.Size.Y / 2 + FLIGHT.landProbe
		local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), landParams)
		if hit and hit.Material ~= Enum.Material.Water then
			stopFlight()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Stamina meter
-- ---------------------------------------------------------------------------

--[[
	A slim bar low in the middle of the screen: shown while flying or
	refilling, faded out once full. Pale like the wind wisps, turning warm as
	the wings tire.
]]
local meter = nil
local meterAlpha = 0
local METER_FULL = Color3.fromRGB(214, 232, 255)
local METER_TIRED = Color3.fromRGB(255, 150, 96)

local function buildMeter()
	local gui = Instance.new("ScreenGui")
	gui.Name = "FlightMeter"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -96)
	back.Size = UDim2.fromOffset(200, 10)
	back.BackgroundColor3 = Color3.fromRGB(16, 20, 30)
	back.BorderSizePixel = 0
	back.Parent = gui
	Instance.new("UICorner", back).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = METER_FULL
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, back = back, fill = fill, stroke = stroke }
end

local function updateMeter(dt, maximum)
	if maximum <= 0 and not meter then
		return
	end
	meter = meter or buildMeter()
	local fraction = if maximum > 0 then stamina / maximum else 0
	local show = maximum > 0 and (flight ~= nil or fraction < 0.999)
	meterAlpha += ((if show then 1 else 0) - meterAlpha) * (1 - math.exp(-8 * dt))

	local tired = 1 - math.clamp(stamina / STAMINA.tiring, 0, 1)
	meter.fill.Size = UDim2.fromScale(fraction, 1)
	meter.fill.BackgroundColor3 = METER_FULL:Lerp(METER_TIRED, tired)
	meter.back.BackgroundTransparency = 1 - 0.55 * meterAlpha
	meter.fill.BackgroundTransparency = 1 - meterAlpha
	meter.stroke.Transparency = 1 - 0.6 * meterAlpha
	meter.gui.Enabled = meterAlpha > 0.01
end

RunService.PreSimulation:Connect(function(dt)
	-- Double-tap jump, read every frame on the press edge.
	local character = player.Character
	local held = jumpHeld(character and character:FindFirstChildOfClass("Humanoid")) and not MenuState.isAnyOpen()
	if held and not wasJumpHeld and canFly() then
		local now = os.clock()
		if now - lastJumpTap <= FLIGHT.doubleTap then
			lastJumpTap = -math.huge
			if flight then
				stopFlight()
			else
				startFlight()
			end
		else
			lastJumpTap = now
		end
	end
	wasJumpHeld = held

	-- Refill on the ground; never hold more than the worn wings carry.
	local maximum = flightTime()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not flight and humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
		stamina += dt * maximum / STAMINA.refillTime
	end
	stamina = math.clamp(stamina, 0, maximum)

	-- Terminal velocity (WingParticles.Fall): there is no air resistance, so a
	-- long fall would otherwise speed up for ever. WingAnimator draws the speed
	-- lines once a fall gets close to it.
	local root = humanoid and humanoid.RootPart
	if not flight and root and humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		local v = root.AssemblyLinearVelocity
		if v.Y < -WingParticles.Fall.terminal then
			root.AssemblyLinearVelocity = Vector3.new(v.X, -WingParticles.Fall.terminal, v.Z)
		end
	end
	updateMeter(dt, if infinite() then 0 else maximum)

	local ok, err = pcall(step, dt)
	if not ok then
		warn("[FlightClient] step failed:", err)
		stopFlight()
	end
end)

player:GetAttributeChangedSignal("CanFly"):Connect(function()
	if not canFly() then
		stopFlight()
	end
end)

player.CharacterAdded:Connect(function()
	-- The old body's constraints went with it; only the state needs clearing.
	if flight then
		pcall(stopFlight)
	end
	flight = nil
end)
