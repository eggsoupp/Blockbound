--[[
	WeaponServer

	Makes swinging a weapon hurt things.

	  the player activates a Tool
	  -> is it a weapon?            ItemDefinitions classification
	  -> which swing of the combo?  SwordCombo, from the same clicks the client sees
	  -> at that swing's hit time:  SwingAnimations' `hit`, not the click
	  -> what is in front of them?  EnemyService, within reach and inside the arc
	  -> hurt it                    EnemyService.damage

	NO REMOTE, ON PURPOSE. Tool.Activated and Deactivated fire on the SERVER
	too, so the whole path is server-side already. A RequestAttack remote would
	be a message a client could send whenever it liked, naming whatever target
	it liked, plus a pile of validation to undo that. Listening to the Tool means
	the only thing a client can do is activate one it is genuinely holding - and
	the combo's own timing, not the click rate, decides how often that swings.

	The client runs the same SwordCombo on the same clicks to play the swings
	(WeaponClient), which is how the blow lands when the blade visibly passes.

	The cost is that the server picks the swing direction itself, from the
	character's facing at the moment of the hit. Hence a forgiving hitbox:
	reach to the near side of an enemy, a wide arc, anything touching counts.

	No player-versus-player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponConfig"))
local SwordCombo = require(Shared.Combat:WaitForChild("SwordCombo"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local GearService = require(ServerScriptService:WaitForChild("GearService"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

--[[
	Tells the swinger how a swing that did NOT land went, so their client can
	tell "nothing there" apart from a hit. Hits and kills are reported by
	EnemyService once the damage is real; see the note there. A receipt only.
]]
local CombatFeedback = Remotes.ensure("CombatFeedback", "RemoteEvent")

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
local function strike(player, stats, step)
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
		CombatFeedback:FireClient(player, "miss")
		return
	end

	table.sort(found, function(a, b)
		return a.gap < b.gap
	end)

	-- Weapon damage gear (a Battle Ring) applies here, at the moment of the hit.
	local damage = math.max(1, math.floor(stats.damage * step.damage * GearService.weaponMultiplier(player) + 0.5))

	for i = 1, math.min(#found, step.maxTargets or stats.maxTargets) do
		local model = found[i].model
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
end

-- ---------------------------------------------------------------------------
-- The combo
-- ---------------------------------------------------------------------------

local function stopCombo(player)
	local state = combos[player]
	if state then
		state.combo:cancel()
		combos[player] = nil
	end
end

local function comboFor(player, tool, stats)
	local state = combos[player]
	if state and state.tool == tool then
		return state.combo
	end
	stopCombo(player)

	local combo
	combo = SwordCombo.new(stats, function(_, step)
		task.wait(SwordCombo.hitDelay(step, combo.speed))

		-- Still swinging this weapon: not put away, not dead, not a new combo.
		local current = combos[player]
		if not current or current.combo ~= combo or tool.Parent ~= player.Character then
			return
		end
		strike(player, stats, step)
	end)

	combos[player] = { tool = tool, combo = combo }
	return combo
end

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

	connections[child] = {
		child.Activated:Connect(function()
			comboFor(player, child, stats):press()
		end),
		child.Deactivated:Connect(function()
			local state = combos[player]
			if state and state.tool == child then
				state.combo:release()
			end
		end),
	}
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

Players.PlayerRemoving:Connect(stopCombo)
