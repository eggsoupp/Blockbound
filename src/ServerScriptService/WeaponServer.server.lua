-- Server-authoritative melee: validated press/release input, one animation/damage clock.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponConfig"))
local SwordCombo = require(Shared.Combat:WaitForChild("SwordCombo"))
local WeaponAnimations = require(Shared.Combat:WaitForChild("WeaponAnimations"))
local ToolAnimation = require(Shared.Tools:WaitForChild("ToolAnimation"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local GearService = require(ServerScriptService:WaitForChild("GearService"))
local WeaponShotService = require(ServerScriptService:WaitForChild("WeaponShotService"))
local WeaponShots = require(Shared.Combat:WaitForChild("WeaponShots"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

--[[
	Tells the swinger how a swing that did NOT land went, so their client can
	tell "nothing there" apart from a hit. Hits and kills are reported by
	EnemyService once the damage is real; see the note there. A receipt only.
]]
local CombatFeedback = Remotes.ensure("CombatFeedback", "RemoteEvent")
local WeaponInput = Remotes.ensure("WeaponInput", "RemoteEvent")
local nextAttackAt, lastPressAt = {}, {}

local DEBUG = false
local function log(...)
	if DEBUG then
		print("[WeaponServer]", ...)
	end
end

-- player -> { tool, combo } for the weapon they are swinging.
local combos = {}

-- tool -> connections, so a tool that is equipped, unequipped and equipped
-- again is listened to once rather than three times.
--
-- Weak-keyed: a character destroyed wholesale on respawn does not raise
-- ChildRemoved for each tool inside it, so the explicit cleanup below cannot be
-- relied on to catch every one. The connections themselves die with their
-- instances either way; this stops the table holding the keys forever.
local connections = setmetatable({}, { __mode = "k" })

-- model -> how far its body reaches out from its pivot, capped. Weak, so a
-- dead enemy's entry goes with it; asked of each enemy once.
local bodyRadii = setmetatable({}, { __mode = "k" })

-- The same three sources, in the same order of trust, MiningServer and
-- HarvestServer use.
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

-- Facing is flattened to horizontal: looking up or down should not decide
-- whether a swing connects with something beside you. Distance stays full 3D,
-- so a ghost overhead is out of reach rather than out of arc.
local function swingFrame(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)

	-- A character whose facing is somehow straight up has no meaningful
	-- horizontal direction; treat every direction as in front rather than none.
	if flat.Magnitude < 1e-3 then
		return root.Position, nil
	end

	return root.Position, flat.Unit
end

local function bodyRadius(model)
	local radius = bodyRadii[model]
	if radius == nil then
		local ok, size = pcall(model.GetExtentsSize, model)
		radius = if ok then math.max(size.X, size.Z) * 0.5 else 0
		radius = math.min(radius, SwordCombo.BodyAllowance)
		bodyRadii[model] = radius
	end
	return radius
end

-- One blow, at the moment it lands.
local function strike(player, stats, step, hitModels, remaining)
	local origin, facing = swingFrame(player)
	if not origin then
		return
	end

	Profiler.enter("Weapon.swing")

	local arcCosine = math.cos(math.rad(math.min(step.arc or stats.arcDegrees, 360) * 0.5))
	local reach = stats.range

	-- Everything inside the hitbox, nearest first: forEachNear walks a hash,
	-- so taking the first found would make the target depend on table order.
	local found = {}
	EnemyService.forEachNear(origin, reach + SwordCombo.BodyAllowance, function(model, position)
		if hitModels[model] then return end
		local offset = position - origin
		local gap = offset.Magnitude - bodyRadius(model)
		if gap > reach then
			return
		end

		-- Something touching the player, or standing exactly on top of them,
		-- is hit whichever way they face.
		if facing and gap > SwordCombo.CloseRange then
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude > 1e-3 and flat.Unit:Dot(facing) < arcCosine then
				return
			end
		end

		table.insert(found, { model = model, gap = gap })
	end)

	if #found == 0 then
		Profiler.count("Weapon.miss")
		Profiler.leave("Weapon.swing")
		return 0
	end

	table.sort(found, function(a, b)
		return a.gap < b.gap
	end)

	-- Weapon damage gear (a Battle Ring) applies here, at the moment of the hit.
	local damage = math.max(1, math.floor(stats.damage * step.damage * GearService.weaponMultiplier(player) + 0.5))

	for i = 1, math.min(#found, remaining) do
		local model = found[i].model
		hitModels[model] = true
		local name = EnemyService.describe(model)
		local alive = EnemyService.damage(model, damage, player)

		Profiler.count("Weapon.hit")
		if not alive then
			Profiler.count("Weapon.kill")
		end

		log(string.format(
			"%s hit %s for %d with %s%s",
			player.Name, tostring(name), damage, stats.name,
			if alive then "" else " (killed)"
		))
	end

	Profiler.leave("Weapon.swing")
	return math.min(#found, remaining)
end

-- ---------------------------------------------------------------------------
-- The combo
-- ---------------------------------------------------------------------------

local function stopCombo(player)
	local state = combos[player]
	if state then
		state.combo:cancel()
		if state.playing then state.playing:Stop(0.08) end
		combos[player] = nil
	end
end

local function comboFor(player, tool, stats)
	local existing = combos[player]
	if existing and existing.tool == tool then return existing end
	stopCombo(player)
	local state = {tool = tool, ready = false, tracks = {}, pending = false, down = false}
	local combo
	local function valid(token)
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		return combos[player] == state and combo.token == token
			and tool.Parent == character and hum and hum.Health > 0
	end
	combo = SwordCombo.new(stats, function(index, step, token)
		if not valid(token) then combo:cancel() return end
		local track = state.tracks[index]
		if not track then combo:cancel() return end
		if state.playing then state.playing:Stop(0.04) end
		track.Looped = false
		track:Play(0.04, 1, combo.speed)
		state.playing = track
		local started = os.clock()
		nextAttackAt[player] = started + step.recover / combo.speed
		-- Exposed for timing diagnostics; never read from the client for damage.
		tool:SetAttribute("AttackStep", index)
		tool:SetAttribute("AttackStarted", workspace:GetServerTimeNow())
		tool:SetAttribute("AttackHitDelay", step.hit / combo.speed)
		local hitModels, count = {}, 0
		local cap = step.maxTargets or stats.maxTargets
		local hitAt = started + step.hit / combo.speed
		local endsAt = started + step.hitEnd / combo.speed
		task.wait(math.max(0, hitAt - os.clock()))
		-- A legendary throws its shot on the same beat the blade lands; the
		-- combo's last step throws the empowered one.
		if valid(token) and WeaponShots.profileFor(stats.name) then
			local swing = stats.damage * step.damage * GearService.weaponMultiplier(player)
			local steps = WeaponAnimations.forClass(stats.weaponClass).steps
			WeaponShotService.fire(player, stats.name, swing, index == #steps)
		end
		repeat
			if not valid(token) then return end
			count += strike(player, stats, step, hitModels, cap - count) or 0
			if count >= cap or os.clock() >= endsAt then break end
			task.wait(math.min(SwordCombo.SampleInterval, math.max(0, endsAt - os.clock())))
		until false
		if count == 0 then CombatFeedback:FireClient(player, "miss") end
		-- Some Glaive clips have an idle tail after their authored Reset.
		task.wait(math.max(0, started + step.recover / combo.speed - os.clock()))
		if valid(token) and state.playing == track then track:Stop(0.06) end
	end)
	state.combo = combo
	combos[player] = state
	-- Warm every track on equip, before starting its damage clock. A cold
	-- asset fetch must never consume the windup and make the first hit invisible.
	task.spawn(function()
		local character = player.Character
		for index, step in ipairs(WeaponAnimations.forClass(stats.weaponClass).steps) do
			if combos[player] ~= state or tool.Parent ~= character then return end
			local track = ToolAnimation.track(character, step.animationId)
			if not track then return end
			state.tracks[index] = track
		end
		local deadline = os.clock() + 10
		while os.clock() < deadline do
			if combos[player] ~= state then return end
			local ready = true
			for _, track in ipairs(state.tracks) do if track.Length <= 0 then ready = false end end
			if ready then state.ready = true break end
			task.wait(0.05)
		end
		if not state.ready then warn("[WeaponServer] weapon animations failed to load: " .. stats.name) return end
		if state.pending and tool.Parent == player.Character and os.clock() >= (nextAttackAt[player] or 0) then
			combo:press()
			if not state.down then combo:release() end
		end
	end)
	return state
end

WeaponInput.OnServerEvent:Connect(function(player, tool, down)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or type(down) ~= "boolean" then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if tool.Parent ~= character or not humanoid or humanoid.Health <= 0 then return end
	local stats = WeaponConfig.get(itemNameFor(tool))
	if not stats then return end
	local state = combos[player]
	if not state or state.tool ~= tool then state = comboFor(player, tool, stats) end
	if not down then
		state.down = false
		state.combo:release()
		return
	end
	local now = os.clock()
	if now - (lastPressAt[player] or -math.huge) < 0.03 then return end
	lastPressAt[player] = now
	-- Unequipping and re-equipping cannot bypass an attack's recovery.
	if not state.combo.busy and now < (nextAttackAt[player] or 0) then return end
	state.down = true
	if state.ready then state.combo:press() else state.pending = true end
end)

-- ---------------------------------------------------------------------------
-- Watching for tools
-- ---------------------------------------------------------------------------

local function untrack(player, tool)
	local connected = connections[tool]
	if connected then
		for _, connection in ipairs(connected) do
			connection:Disconnect()
		end
		connections[tool] = nil
	end

	local state = combos[player]
	if state and state.tool == tool then
		stopCombo(player)
	end
end

local function track(player, child)
	if not child:IsA("Tool") or connections[child] then
		return
	end

	-- Cheap gate: only weapons are worth a connection at all, and a tool cannot
	-- change what item it represents while it exists.
	local stats = WeaponConfig.get(itemNameFor(child))
	if not stats then
		-- A pickaxe or an axe. Mining and harvesting own those; this does not.
		return
	end

	connections[child] = {}
	comboFor(player, child, stats)
end

local function watchCharacter(player, character)
	stopCombo(player)

	for _, child in ipairs(character:GetChildren()) do
		track(player, child)
	end

	-- Only a Tool inside the CHARACTER can be activated; one sitting in the
	-- Backpack cannot. So equipping is what starts the listening, and
	-- unequipping is what stops it.
	character.ChildAdded:Connect(function(child)
		track(player, child)
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			untrack(player, child)
		end
	end)
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)

	if player.Character then
		watchCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	stopCombo(player)
	nextAttackAt[player], lastPressAt[player] = nil, nil
end)
