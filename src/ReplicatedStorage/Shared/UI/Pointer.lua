--[[
	Pointer

	Where the player is pointing into the world, from a mouse or a finger.
	Client only.

		Pointer.screenPoint()   the pointer, in the space ScreenPointToRay takes
		Pointer.ray()           a unit ray from the camera through it
		Pointer.onTap(fn)       fn(screenPoint) for a quick tap on the world
		Pointer.onHold(fn)      fn(true) when a finger settles on the world,
		                        fn(false) when it lifts
		Pointer.aim(range)      a world position for an aimed ability

	ON A COMPUTER all of it is the mouse, and taps and holds never fire: the
	mining and placement scripts keep reading mouse buttons themselves.

	ON A TOUCH SCREEN THE SAME FINGER TURNS THE CAMERA

	A drag across the world is Roblox's camera control, so a touch is not an
	action until it proves it is not a drag:

	  tap   lifted within TAP_TIME, having moved less than STILL pixels
	  hold  still for HOLD_TIME; it then follows the finger until it lifts,
	        so mining carries on into the next block as the camera turns

	Touches on GUI - the thumbstick, the jump button, every button of ours -
	arrive already processed and are never seen here.

	AIMING

	A finger cannot hover over a target while the other thumb steers, so an
	aimed ability on a touch screen goes to the enemy nearest the middle of
	the view (within AIM_CONE of where the camera looks, and in range), or
	failing one, to whatever is under the middle of the screen.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Responsive = require(script.Parent:WaitForChild("Responsive"))

local Pointer = {}

local TAP_TIME = 0.3
local HOLD_TIME = 0.18
local STILL = 14

local AIM_CONE = math.rad(32)
local AIM_FALLBACK_DISTANCE = 120
local ENEMY_FOLDER = "Enemies"

local player = Players.LocalPlayer
local mouse = player and player:GetMouse()

local tapListeners = {}
local holdListeners = {}

-- The touch being watched, and the last place a finger was on the world.
local current: { input: InputObject, start: Vector2, at: number, holding: boolean, moved: boolean }? = nil
local lastTouch: Vector2? = nil

local function emit(list, ...)
	for _, listener in ipairs(list) do
		task.spawn(listener, ...)
	end
end

local function touchPoint(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

function Pointer.screenPoint(): Vector2
	if Responsive.isTouch() then
		if current then
			return touchPoint(current.input)
		end
		if lastTouch then
			return lastTouch
		end
		local size = Workspace.CurrentCamera.ViewportSize
		return Vector2.new(size.X / 2, size.Y / 2)
	end
	return Vector2.new(mouse.X, mouse.Y)
end

function Pointer.ray(): Ray
	if Responsive.isTouch() then
		local point = Pointer.screenPoint()
		return Workspace.CurrentCamera:ScreenPointToRay(point.X, point.Y)
	end
	return mouse.UnitRay
end

function Pointer.onTap(callback: (Vector2) -> ())
	table.insert(tapListeners, callback)
end

function Pointer.onHold(callback: (boolean) -> ())
	table.insert(holdListeners, callback)
end

function Pointer.isHolding(): boolean
	return current ~= nil and current.holding
end

-- ---------------------------------------------------------------------------
-- Aiming
-- ---------------------------------------------------------------------------

local function enemyPosition(model: Instance): Vector3?
	if model:IsA("Model") then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 0 then
			return nil
		end
		return model:GetPivot().Position
	elseif model:IsA("BasePart") then
		return model.Position
	end
	return nil
end

local function centreHit(range: number): Vector3
	local camera = Workspace.CurrentCamera
	local size = camera.ViewportSize
	local ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	params.IgnoreWater = true

	local result = Workspace:Raycast(ray.Origin, ray.Direction * range, params)
	return if result then result.Position else ray.Origin + ray.Direction * range
end

function Pointer.aim(range: number?): Vector3
	if not Responsive.isTouch() then
		return mouse.Hit.Position
	end

	range = range or AIM_FALLBACK_DISTANCE
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local from = if root then root.Position else camera.CFrame.Position
	local look = camera.CFrame.LookVector

	local folder = Workspace:FindFirstChild(ENEMY_FOLDER)
	local best, bestScore = nil, math.huge

	local function consider(candidate: Instance)
		local position = enemyPosition(candidate)
		if not position then
			return
		end
		local offset = position - from
		local distance = offset.Magnitude
		if distance > range or distance < 0.5 then
			return
		end
		local toward = position - camera.CFrame.Position
		local angle = math.acos(math.clamp(look:Dot(toward.Unit), -1, 1))
		if angle > AIM_CONE then
			return
		end
		-- Mostly the angle: the enemy you are looking at, not the nearest one.
		local score = angle + distance / range * 0.35
		if score < bestScore then
			best, bestScore = position, score
		end
	end

	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			consider(child)
		end
	end
	for _, tagged in ipairs(CollectionService:GetTagged("Enemy")) do
		consider(tagged)
	end

	return best or centreHit(range)
end

-- ---------------------------------------------------------------------------
-- Touches
-- ---------------------------------------------------------------------------

if player then
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Touch or current then
			return
		end

		local watched = { input = input, start = touchPoint(input), at = os.clock(), holding = false, moved = false }
		current = watched
		lastTouch = watched.start

		task.delay(HOLD_TIME, function()
			if current == watched and not watched.moved then
				watched.holding = true
				emit(holdListeners, true)
			end
		end)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if current and input == current.input then
			local point = touchPoint(input)
			lastTouch = point
			if not current.holding and (point - current.start).Magnitude > STILL then
				current.moved = true
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not (current and input == current.input) then
			return
		end
		local watched = current
		current = nil
		lastTouch = touchPoint(input)

		if watched.holding then
			emit(holdListeners, false)
		elseif not watched.moved and os.clock() - watched.at <= TAP_TIME then
			emit(tapListeners, lastTouch)
		end
	end)
end

return Pointer
