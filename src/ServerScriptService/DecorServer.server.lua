--[[
	DecorServer

	Answers the prompts on placed decor (Shared.Building.DecorCatalog), which
	StationService marks with a DecorId attribute:

	  door   swings its Swing parts a quarter turn about its Hinge part and
	         back, a little under a third of a second each way
	  light  douses and relights: every LightFx emitter and light, on or off
	(Seats have no prompt: their Seat part sits whoever walks into it.)

	Doors open away from whoever opens them, so a door never swings into the
	player's face. Neither state is saved - a door comes back shut and a
	light lit - since neither is worth an island save write.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DecorCatalog = require(Shared:WaitForChild("Building"):WaitForChild("DecorCatalog"))
local StationService = require(ServerScriptService:WaitForChild("StationService"))

local SWING_SECONDS = 0.28
local USE_SLACK = 6

-- model -> { open, busy, parts = { [part] = offset from the hinge }, hinge }
local doors = setmetatable({}, { __mode = "k" })
-- model -> lit
local lights = setmetatable({}, { __mode = "k" })

local function decorModel(prompt)
	local current = prompt.Parent
	while current and current.Parent do
		if current:IsA("Model") and current:GetAttribute("DecorId") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function inReach(player, prompt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local anchor = prompt.Parent
	if not (root and anchor and anchor:IsA("BasePart")) then
		return false
	end
	return (root.Position - anchor.Position).Magnitude <= prompt.MaxActivationDistance + USE_SLACK
end

-- ---------------------------------------------------------------------------
-- Doors
-- ---------------------------------------------------------------------------

local function doorState(model)
	local state = doors[model]
	if state then
		return state
	end
	local hinge = model:FindFirstChild("Hinge")
	if not hinge then
		return nil
	end
	state = { open = false, busy = false, hinge = hinge.CFrame, parts = {} }
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("Swing") then
			state.parts[part] = hinge.CFrame:ToObjectSpace(part.CFrame)
		end
	end
	doors[model] = state
	return state
end

local function toggleDoor(model, prompt, player)
	local state = doorState(model)
	if not state or state.busy then
		return
	end

	-- Swing away from the player: which side of the door they stand on, in
	-- the hinge's own frame.
	local target = 0
	if not state.open then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local side = if root then state.hinge:PointToObjectSpace(root.Position).Z else 1
		-- A turn of +90 degrees about Y carries the leaf (+X of the hinge)
		-- round to -Z, the side away from a player standing at +Z.
		target = if side >= 0 then math.pi / 2 else -math.pi / 2
	end

	local from = state.angle or 0
	state.busy = true
	state.open = target ~= 0
	prompt.ActionText = if state.open then "Close" else "Open"

	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not model.Parent then
			connection:Disconnect()
			return
		end
		local t = math.clamp((os.clock() - started) / SWING_SECONDS, 0, 1)
		local eased = 1 - (1 - t) * (1 - t)
		local angle = from + (target - from) * eased
		local frame = state.hinge * CFrame.Angles(0, angle, 0)
		for part, offset in pairs(state.parts) do
			part.CFrame = frame * offset
		end
		if t >= 1 then
			connection:Disconnect()
			state.angle = target
			state.busy = false
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Lights
-- ---------------------------------------------------------------------------

local function setLit(model, lit)
	lights[model] = lit
	for _, item in ipairs(model:GetDescendants()) do
		if item:GetAttribute("LightFx") and (item:IsA("ParticleEmitter") or item:IsA("Light")) then
			item.Enabled = lit
		elseif item:IsA("BasePart") and item:GetAttribute("Glow") then
			-- A lantern's glass, a crystal: glowing voxels go dull while out.
			item.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

local function toggleLight(model, prompt)
	local lit = lights[model]
	if lit == nil then
		lit = true
	end
	lit = not lit
	setLit(model, lit)
	prompt.ActionText = if lit then "Douse" else "Light"
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	local id = prompt:GetAttribute("DecorId")
	local entry = type(id) == "string" and DecorCatalog.get(id)
	if not entry or not inReach(player, prompt) then
		return
	end
	local model = decorModel(prompt)
	if not model or not StationService.fromInstance(prompt.Parent) then
		return
	end

	if entry.kind == "door" then
		toggleDoor(model, prompt, player)
	elseif entry.kind == "light" then
		toggleLight(model, prompt)
	end
end)

-- ---------------------------------------------------------------------------
-- Training dummies
-- ---------------------------------------------------------------------------
-- A placed Training Dummy is hit like an enemy: EnemyService registers the
-- model where it stands (EnemyConfig.Definitions.TrainingDummy, behaviour
-- Bosses.TrainingDummy). Picking it up removes the model, which ends the
-- registration on the enemy service's next tick.

local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local StationConfig = require(Shared:WaitForChild("Crafting"):WaitForChild("StationConfig"))

local function adoptDummy(instance)
	if instance:IsA("Model") and instance:GetAttribute("DecorId") == "TrainingDummy" then
		-- Deferred: the station is parented before its prompt and anchor are.
		task.defer(function()
			if instance.Parent then
				EnemyService.adopt("TrainingDummy", instance)
			end
		end)
	end
end

local stations = workspace:WaitForChild(StationConfig.WorldFolderName)
stations.ChildAdded:Connect(adoptDummy)
for _, child in ipairs(stations:GetChildren()) do
	adoptDummy(child)
end
