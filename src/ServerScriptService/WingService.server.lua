--[[
	WingService

	Puts the worn pair of wings on the wearer's back, and tells everyone when
	a player is flying.

	THE MODEL

	ReplicatedStorage.WingAssets holds one rigged model per wing item, built
	from assets/wing-accessories (roblox/BuildWings.lua): a Frame union with a
	WingMount attachment at the upper-back centre, and one union per piece
	(arms, fans, feathers, plumes, crystals, leaves, claws, lobes) on Motor6D
	joints at the rig's pivots. They are place assets, like EnemyAssets.

	Every half second each player's worn wings (GearService.wornInGroup) are
	compared with what their character carries. A change swaps the model: a
	clone named WornWings, parented to the character, its Frame held to the
	UpperTorso (Torso on R6) by a Motor6D from the BodyBackAttachment. All of
	it is massless and collides with nothing, so it changes neither physics
	nor hit boxes. StarterPlayerScripts.WingAnimator, on every client,
	moves the joints.

	FLYING

	Flight is the client's (FlightClient), so it reports take-off and landing
	on the FlightState remote. The server keeps the character's Flying
	attribute, which replicates to everyone: WingAnimator flaps by it, and
	WeaponServer refuses swings while it is set. A report from a player who
	cannot fly (no wings or Dev Flight worn) is ignored.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Remotes"))
local GearService = require(ServerScriptService:WaitForChild("GearService"))

local FlightState = Remotes.ensure("FlightState", "RemoteEvent")

local SWEEP_INTERVAL = 0.5
local MODEL_NAME = "WornWings"

-- Studs behind the back attachment the frame sits, so its straps clear the torso.
local MOUNT_OFFSET = CFrame.new(0, 0.05, 0.05)

local function assetFor(itemName)
	local assets = ReplicatedStorage:FindFirstChild("WingAssets")
	return itemName and assets and assets:FindFirstChild(itemName)
end

local function remove(character)
	local worn = character:FindFirstChild(MODEL_NAME)
	if worn then
		worn:Destroy()
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local mount = torso and torso:FindFirstChild("WingMount")
	if mount then
		mount:Destroy()
	end
end

local function attach(character, itemName)
	remove(character)
	local asset = assetFor(itemName)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not asset or not torso then
		return
	end

	local model = asset:Clone()
	model.Name = MODEL_NAME
	model:SetAttribute("ItemName", itemName)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end

	local frame = model.PrimaryPart or model:FindFirstChild("Frame")
	local wingMount = frame and frame:FindFirstChild("WingMount")
	if not frame or not wingMount then
		model:Destroy()
		return
	end

	local back = torso:FindFirstChild("BodyBackAttachment")
	local joint = Instance.new("Motor6D")
	joint.Name = "WingMount"
	joint.Part0 = torso
	joint.Part1 = frame
	joint.C0 = (if back then back.CFrame else CFrame.new(0, 0.2, torso.Size.Z / 2)) * MOUNT_OFFSET
	joint.C1 = wingMount.CFrame
	joint.Parent = torso

	-- Start the model where the joint will hold it, so it never flashes at the origin.
	local frameAt = torso.CFrame * joint.C0 * joint.C1:Inverse()
	model:PivotTo(frameAt * frame.CFrame:ToObjectSpace(model:GetPivot()))
	model.Parent = character
end

local function sweep()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			local wanted = GearService.wornInGroup(player, "Wings")
			-- Studio only: a DebugWings attribute on the player shows that pair
			-- without wearing it, for looking at the models.
			if RunService:IsStudio() and type(player:GetAttribute("DebugWings")) == "string" then
				wanted = player:GetAttribute("DebugWings")
			end
			if not assetFor(wanted) then
				wanted = nil
			end
			local worn = character:FindFirstChild(MODEL_NAME)
			local current = worn and worn:GetAttribute("ItemName")
			if wanted ~= current then
				if wanted then
					attach(character, wanted)
				else
					remove(character)
				end
			end
			-- Lost the means to fly (Dev Flight needs no wings, so this is CanFly).
			if player:GetAttribute("CanFly") ~= true and character:GetAttribute("Flying") then
				character:SetAttribute("Flying", false)
			end
		end
	end
end

FlightState.OnServerEvent:Connect(function(player, flying)
	if type(flying) ~= "boolean" then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	if flying and player:GetAttribute("CanFly") ~= true then
		flying = false
	end
	character:SetAttribute("Flying", flying)
end)

task.spawn(function()
	while true do
		task.wait(SWEEP_INTERVAL)
		local ok, err = pcall(sweep)
		if not ok then
			warn("[WingService] sweep failed:", err)
		end
	end
end)
