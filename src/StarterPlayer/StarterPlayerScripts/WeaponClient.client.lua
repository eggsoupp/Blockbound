-- Tool input goes to the server; replicated attack tracks drive local trails and sound.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local WeaponAnimations = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponAnimations"))
local WeaponInput = require(Shared:WaitForChild("Net"):WaitForChild("Remotes")).wait("WeaponInput")
local WeaponConfig = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponConfig"))

local player = Players.LocalPlayer

--[[
	The wind trail. The texture and its tiling are the wisps from
	ReplicatedStorage["assets(VFX for use)"]["Slash VFX"].Workspace.Slash.
	Attachment1.Trail2, turned from that pack's violet to a pale wind and cut
	to a short streak: "slight", not a slash effect of its own. Static, as the
	pack has it: stretched over the whole ribbon the wisps all but vanish.
]]
local TRAIL = {
	texture = "rbxassetid://16892374733",
	textureLength = 5.14,
	color = ColorSequence.new(Color3.fromRGB(236, 244, 255), Color3.fromRGB(200, 222, 255)),
	transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	}),
	widthScale = NumberSequence.new(1, 0.35),
	lifetime = 0.18,
	lightEmission = 0.5,
	-- Where along the blade, from the grip (0) to the tip (1), the ribbon runs.
	from = 0.4,
	to = 0.98,
}

local function itemNameFor(tool)
	local attribute = tool:GetAttribute("ItemName") or tool:GetAttribute("itemName")
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end

	local value = tool:FindFirstChild("ItemName") or tool:FindFirstChild("itemName")
	if value and value:IsA("StringValue") and value.Value ~= "" then
		return value.Value
	end

	return tool.Name
end

-- ---------------------------------------------------------------------------
-- The trail
-- ---------------------------------------------------------------------------

-- tool -> Trail, or false for one that cannot have one.
local trails = setmetatable({}, { __mode = "k" })

-- trail -> which swing last claimed it, so a new swing takes it over cleanly.
local claims = setmetatable({}, { __mode = "k" })

--[[
	The blade's tip, in the handle's space: the corner of the weapon's own
	parts farthest from the grip. Each part's OWN corners, not a box around
	them all - a blade drawn diagonally across its mesh's square is longest
	corner to corner, and that corner is the point.
]]
local function tipOf(handle, tool)
	local tip = Vector3.zero
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") and part ~= handle then
			local relative = handle.CFrame:ToObjectSpace(part.CFrame)
			local half = part.Size * 0.5
			for _, corner in ipairs({
				Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
				Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1),
			}) do
				local point = relative * (half * corner)
				if point.Magnitude > tip.Magnitude then
					tip = point
				end
			end
		end
	end
	return tip
end

local function trailFor(tool)
	local existing = trails[tool]
	if existing ~= nil then
		return existing or nil
	end

	local handle = tool:FindFirstChild("Handle")
	local tip = handle and tipOf(handle, tool)
	if not tip or tip.Magnitude < 1 then
		trails[tool] = false
		return nil
	end

	local outer = Instance.new("Attachment")
	outer.Name = "WindTrailTip"
	outer.Position = tip * TRAIL.to
	outer.Parent = handle

	local inner = Instance.new("Attachment")
	inner.Name = "WindTrailBase"
	inner.Position = tip * TRAIL.from
	inner.Parent = handle

	local trail = Instance.new("Trail")
	trail.Name = "WindTrail"
	trail.Texture = TRAIL.texture
	trail.TextureMode = Enum.TextureMode.Static
	trail.TextureLength = TRAIL.textureLength
	trail.Color = TRAIL.color
	trail.Transparency = TRAIL.transparency
	trail.WidthScale = TRAIL.widthScale
	trail.Lifetime = TRAIL.lifetime
	trail.LightEmission = TRAIL.lightEmission
	trail.LightInfluence = 0
	trail.FaceCamera = false
	trail.MinLength = 0.05
	trail.Attachment0 = outer
	trail.Attachment1 = inner
	trail.Enabled = false
	trail.Parent = handle

	trails[tool] = trail
	return trail
end

-- Shows the held weapon's trail while `track` is inside the swing's window.
local function trailDuring(character, track, swing)
	local tool = character:FindFirstChildOfClass("Tool")
	local trail = tool and trailFor(tool)
	if not trail or not swing.trail then
		return
	end

	local claim = {}
	claims[trail] = claim
	local from, to = swing.trail[1], swing.trail[2]

	task.spawn(function()
		while claims[trail] == claim and track.IsPlaying and trail.Parent do
			local time = track.TimePosition
			local on = time >= from and time <= to
			if on ~= trail.Enabled then
				if on then
					-- Not joined to wherever the blade was at the end of the
					-- last swing.
					trail:Clear()
				end
				trail.Enabled = on
			end
			if time > to then
				break
			end
			RunService.RenderStepped:Wait()
		end
		if claims[trail] == claim then
			trail.Enabled = false
		end
	end)
end

-- An asset's number whichever way its id is written ("rbxassetid://1",
-- "http://www.roblox.com/asset/?id=1"); anything else, such as a Studio
-- preview's id, as it is.
local function assetKey(id)
	return string.match(id, "^rbxassetid://(%d+)$") or string.match(id, "[?&]id=(%d+)") or id
end

--[[
	Which sword swing a track is, or nil. By id: the published id, or this
	client's own Studio preview of it.
]]
local function swingNameFor(track)
	local animation = track.Animation
	local id = animation and animation.AnimationId
	if type(id) ~= "string" or id == "" then
		return nil
	end

	local key = assetKey(id)
	return WeaponAnimations.forId(key)
end

local function watchAnimator(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not animator then
		return
	end

	animator.AnimationPlayed:Connect(function(track)
		local swing = swingNameFor(track)
		if swing then
			trailDuring(character, track, swing)
			if character == player.Character then
				task.spawn(function()
					while track.IsPlaying and track.TimePosition < swing.swingTime do
						RunService.RenderStepped:Wait()
					end
					if track.IsPlaying then Sounds.play("tool.swing") end
				end)
			end
		end
	end)
end

local function watchPlayer(other)
	other.CharacterAdded:Connect(function(character)
		task.spawn(watchAnimator, character)
	end)
	if other.Character then
		task.spawn(watchAnimator, other.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end

-- Only input is sent. The client cannot choose damage, combo index or targets.
local held = nil
local function putAway()
	if not held then return end
	WeaponInput:FireServer(held.tool, false)
	for _, connection in ipairs(held.connections) do connection:Disconnect() end
	held = nil
end
local function takeOut(tool)
	if not WeaponConfig.get(itemNameFor(tool)) then return end
	putAway()
	held = {tool = tool, connections = {
		tool.Activated:Connect(function() WeaponInput:FireServer(tool, true) end),
		tool.Deactivated:Connect(function() WeaponInput:FireServer(tool, false) end),
	}}
end
local function watchCharacter(character)
	putAway()
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then takeOut(child) end
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then takeOut(child) end
	end)
	character.ChildRemoved:Connect(function(child)
		if held and held.tool == child then putAway() end
	end)
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then watchCharacter(player.Character) end
