-- Tool input goes to the server; replicated attack tracks drive local trails and sound.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local WeaponAnimations = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponAnimations"))
local WeaponInput = require(Shared:WaitForChild("Net"):WaitForChild("Remotes")).wait("WeaponInput")
local WeaponConfig = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponConfig"))
local CombatAudio = require(Shared:WaitForChild("Audio"):WaitForChild("CombatAudio"))

-- The swing's air, by weapon class (CombatRecipes); anything else keeps the
-- plain tool swing.
local SWING_SOUNDS = { Sword = "whoosh.blade", HeavySword = "whoosh.heavy", Axe = "whoosh.heavy", Lance = "whoosh.light" }

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
					if track.IsPlaying then
						-- TargetFeedback reads this to tell a weapon's hit from an ability's.
						player:SetAttribute("WeaponSwingAt", workspace:GetServerTimeNow())
						local tool = character:FindFirstChildOfClass("Tool")
						local stats = tool and WeaponConfig.get(tool.Name)
						local key = stats and SWING_SOUNDS[stats.weaponClass]
						if key then
							CombatAudio.play(key, character:FindFirstChild("HumanoidRootPart"), 0.45, 1)
						else
							Sounds.play("tool.swing")
						end
					end
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

-- ---------------------------------------------------------------------------
-- Dash
-- ---------------------------------------------------------------------------

--[[
	Q, or the touch DASH button (it bumps the TouchDash attribute), dashes the
	way the character is moving, or the way it faces when standing still. Only
	with charges from worn gear: GearService mirrors them into DashCharges
	(Leather Boots give one). Each spent charge refills on its own.

	The clip goes by the held weapon (WeaponAnimations): a class with one
	`dash` clip turns to face the dash; empty hands, tools and lances use the
	rapier's four-way set, picked by the dash's angle to the facing. The
	character is the client's to move, so the dash and its clip replicate the
	same way walking does. The streak is the slash pack's wind trail again.
]]
local UserInputService = game:GetService("UserInputService")
local MenuState = require(Shared:WaitForChild("UI"):WaitForChild("MenuState"))

local DASH = {
	speed = 64,
	time = 0.2,
	recharge = 1.5,
	clipSpeed = 1.3,
	key = Enum.KeyCode.Q,
}

local refills = {} -- os.clock() at which each spent charge is back
local dashing = false
local loadedClips = setmetatable({}, { __mode = "k" }) -- animator -> id -> track

local function chargesLeft()
	local now = os.clock()
	for index = #refills, 1, -1 do
		if refills[index] <= now then table.remove(refills, index) end
	end
	return (tonumber(player:GetAttribute("DashCharges")) or 0) - #refills
end

local function dashClip(character, root, direction)
	local tool = character:FindFirstChildOfClass("Tool")
	local stats = tool and WeaponConfig.get(itemNameFor(tool))
	local profile = stats and WeaponAnimations.Classes[stats.weaponClass]
	if profile and profile.dash then
		return profile.dash, true
	end
	local set = profile and profile.dashes or WeaponAnimations.DefaultDashes
	local ahead = direction:Dot(root.CFrame.LookVector)
	local side = direction:Dot(root.CFrame.RightVector)
	if math.abs(ahead) >= math.abs(side) then
		return if ahead >= 0 then set.Forward else set.Back, false
	end
	return if side >= 0 then set.Right else set.Left, false
end

local function playClip(animator, id)
	local tracks = loadedClips[animator]
	if not tracks then
		tracks = {}
		loadedClips[animator] = tracks
	end
	local track = tracks[id]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action2
		track.Looped = false
		tracks[id] = track
	end
	track:Play(0.05, 1, DASH.clipSpeed)
end

local function streakFor(root)
	local trail = root:FindFirstChild("DashStreak")
	if trail then return trail end
	local top = Instance.new("Attachment")
	top.Name = "DashStreakTop"
	top.Position = Vector3.new(0, 1.1, 0.3)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "DashStreakBottom"
	bottom.Position = Vector3.new(0, -1.3, 0.3)
	bottom.Parent = root
	trail = Instance.new("Trail")
	trail.Name = "DashStreak"
	trail.Texture = TRAIL.texture
	trail.TextureMode = Enum.TextureMode.Static
	trail.TextureLength = TRAIL.textureLength
	trail.Color = TRAIL.color
	trail.Transparency = TRAIL.transparency
	trail.WidthScale = TRAIL.widthScale
	trail.Lifetime = 0.22
	trail.LightEmission = TRAIL.lightEmission
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Enabled = false
	trail.Parent = root
	return trail
end

local function dash()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if dashing or not animator or humanoid.Health <= 0 or humanoid.Sit or MenuState.isAnyOpen() then
		return
	end
	if chargesLeft() <= 0 then
		return
	end

	local direction = humanoid.MoveDirection * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	if direction.Magnitude < 0.1 then
		return
	end
	direction = direction.Unit

	dashing = true
	table.insert(refills, os.clock() + DASH.recharge)

	local clip, turns = dashClip(character, root, direction)
	local autoRotate = humanoid.AutoRotate
	if turns then
		humanoid.AutoRotate = false
		root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	end
	playClip(animator, clip)
	Sounds.play("tool.swing")

	local push = Instance.new("LinearVelocity")
	push.Name = "Dash"
	push.Attachment0 = root:FindFirstChild("RootAttachment") or root:FindFirstChildOfClass("Attachment")
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	push.PlaneVelocity = Vector2.new(direction.X, direction.Z) * DASH.speed
	push.MaxForce = root.AssemblyMass * 4000
	push.Parent = root

	local streak = streakFor(root)
	streak:Clear()
	streak.Enabled = true

	task.delay(DASH.time, function()
		push:Destroy()
		streak.Enabled = false
		if root.Parent then
			-- Leave the dash at a run rather than stopping dead.
			local velocity = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = direction * humanoid.WalkSpeed + Vector3.new(0, velocity.Y, 0)
		end
		if turns and humanoid.Parent then
			humanoid.AutoRotate = autoRotate
		end
		dashing = false
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == DASH.key then
		dash()
	end
end)
player:GetAttributeChangedSignal("TouchDash"):Connect(dash)

-- For the touch button's shade: how much of the next charge is still to come,
-- 0 with a charge in hand.
RunService.Heartbeat:Connect(function()
	local shade = 0
	if chargesLeft() <= 0 and #refills > 0 then
		local soonest = math.huge
		for _, at in ipairs(refills) do soonest = math.min(soonest, at) end
		shade = math.clamp((soonest - os.clock()) / DASH.recharge, 0, 1)
	end
	if player:GetAttribute("DashShade") ~= shade then
		player:SetAttribute("DashShade", shade)
	end
end)
