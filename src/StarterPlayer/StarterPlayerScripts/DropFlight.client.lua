--[[
	DropFlight

	The thing a kill drops, flying to you: a small cube on a curve with a trail
	behind it, coloured by the item's rarity.

		EnemyService, on a kill  ->  EnemyDropFlight(from, item, amount)
		                             ...and the item lands in the bag
		                             EnemyConfig.DropFlightSeconds later

	THE ARRIVAL AND THE LINE ARE THE SAME MOMENT, WITHOUT BEING TOLD SO

	This does not write the "+1 Oak Log" line. The server holds the grant back
	for exactly the flight time, so the inventory changes as the cube lands and
	StarterPlayerScripts.ItemFeedback writes the line off that, the same way it
	writes every other one. Two things agreeing because they read one constant,
	rather than three messages that have to arrive in order.

	A QUADRATIC BEZIER, AND WHY IT IS RE-EVALUATED EVERY FRAME

	The target moves. A curve baked at launch would fly to where the player was
	standing half a second ago and stop in mid air, which is exactly what a
	pickup must never do - the whole point of the arc is that it ends ON you.
	So the endpoint is read from the character each frame and the curve is
	rebuilt around it; only the START and the lift are fixed.

	The control point is above the midpoint, so the cube leaves the corpse
	upward and comes down onto the player. Lift scales with distance, because a
	fixed height reads as a mortar shell across a room and as a flat line across
	a field.

	IT IS DRAWN, NOT SIMULATED. An anchored part moved by hand: no physics, no
	collisions, nothing to tunnel through terrain or shove anybody. It cannot
	miss and it cannot get stuck, which are the only two things a pickup
	animation has to promise.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))

local DropFlight = Remotes.wait("EnemyDropFlight")

local player = Players.LocalPlayer

local FLIGHT = EnemyConfig.DropFlightSeconds

local CUBE_SIZE = 0.7

-- How high the curve bulges, as a fraction of how far it has to travel, and
-- the floor under that so a drop at your feet still arcs.
local LIFT_FRACTION = 0.32
local LIFT_MINIMUM = 3

-- Where on the body it lands. Chest height rather than the feet: it reads as
-- being collected rather than as landing on the floor next to you.
local CATCH_HEIGHT = 2

--[[
	The trail. Wide at the cube and pinched to nothing behind it, which is what
	makes a short trail read as motion rather than as a stick being carried.
]]
local TRAIL_LIFETIME = 0.35
local TRAIL_WIDTH = 0.9

-- More than could plausibly be in the air at once from honest play, and a hard
-- stop on a server that decided to send a thousand.
local MAX_IN_FLIGHT = 24

local inFlight = 0

local function rarityColor(itemName: string): Color3
	local definition = ItemDefinitions[itemName]
	return Theme.rarityColor(definition and definition.rarity)
end

--[[
	Where the cube is heading, right now.

	Nil once there is nobody to fly to - a respawn mid-flight - which is what
	ends the flight early rather than sending the cube to the origin.
]]
local function catchPoint(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root then
		return nil
	end

	return root.Position + Vector3.new(0, CATCH_HEIGHT, 0)
end

local function build(color: Color3): Part
	local cube = Instance.new("Part")
	cube.Name = "Drop"
	cube.Size = Vector3.one * CUBE_SIZE
	cube.Color = color
	cube.Material = Enum.Material.Neon
	cube.Anchored = true
	cube.CanCollide = false
	cube.CanQuery = false
	cube.CanTouch = false
	cube.CastShadow = false

	--[[
		Two attachments a little apart across the cube, because a Trail needs a
		WIDTH and takes it from the gap between them. A single point would
		produce nothing at all - the commonest way a trail silently does not
		appear.
	]]
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, TRAIL_WIDTH * 0.5, 0)
	top.Parent = cube

	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -TRAIL_WIDTH * 0.5, 0)
	bottom.Parent = cube

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = TRAIL_LIFETIME
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true

	-- The rarity colour, fading out along its length rather than stopping dead.
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = cube

	return cube
end

--[[
	One flight, from a corpse to whoever is being flown to.

	Its own coroutine per drop rather than one loop over a list: a kill drops
	one or two things, they are gone in half a second, and a shared scheduler
	would be more machinery than the thing it schedules.
]]
local function fly(from: Vector3, itemName: string, color: Color3)
	local cube = build(color)
	cube.CFrame = CFrame.new(from)
	cube.Parent = workspace

	-- The backstop. Whatever happens to the loop below, the part goes.
	Debris:AddItem(cube, FLIGHT + 1)

	inFlight += 1

	local elapsed = 0
	local spin = Vector3.new(math.random(), math.random(), math.random()).Unit * 9

	local connection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime

		local target = catchPoint()

		if not target or elapsed >= FLIGHT then
			connection:Disconnect()
			inFlight -= 1
			cube:Destroy()

			-- Only if it actually arrived. A flight cut short by a respawn has
			-- nothing to announce, and the item is still on its way to the bag.
			if target then
				Sounds.play("ui.click")
			end
			return
		end

		local alpha = elapsed / FLIGHT

		--[[
			The control point, rebuilt around wherever the player is NOW.

			Above the midpoint by a fraction of the distance still being
			covered, so an item dropped across a field arcs high and one
			dropped at your feet hops.
		]]
		local span = (target - from).Magnitude
		local lift = math.max(LIFT_MINIMUM, span * LIFT_FRACTION)
		local control = (from + target) * 0.5 + Vector3.new(0, lift, 0)

		-- Quadratic bezier: lerp the two legs, then lerp between those.
		local inverse = 1 - alpha
		local position = from * (inverse * inverse)
			+ control * (2 * inverse * alpha)
			+ target * (alpha * alpha)

		cube.CFrame = CFrame.new(position)
			* CFrame.Angles(spin.X * elapsed, spin.Y * elapsed, spin.Z * elapsed)
	end)
end

--[[
	`amount` is deliberately not used.

	It is on the wire because the flight and the grant are the same event and
	splitting them would leave the message unable to describe itself - but what
	the player is told they got comes from the bag changing, not from here. One
	cube whatever the number, which is also what stops a stack of sixty-four
	turning into sixty-four projectiles.
]]
DropFlight.OnClientEvent:Connect(function(from, itemName, _amount)
	if typeof(from) ~= "Vector3" or type(itemName) ~= "string" or itemName == "" then
		return
	end

	if inFlight >= MAX_IN_FLIGHT then
		return
	end

	fly(from, itemName, rarityColor(itemName))
end)
