--[[
	WeaponServer

	Makes swinging a weapon hurt things.

	  the player activates a Tool
	  -> is it a weapon?            ItemDefinitions classification
	  -> is the swing off cooldown? WeaponConfig
	  -> what is in front of them?  EnemyService, within range and inside the arc
	  -> hurt the nearest one       EnemyService.damage

	NO REMOTE, ON PURPOSE. Tool.Activated fires on the SERVER too, so the whole
	path is server-side already. A RequestAttack remote would be a message a
	client could send whenever it liked, naming whatever target it liked, plus a
	pile of validation to undo that. Listening to the Tool means the only thing
	a client can do is activate one it is genuinely holding.

	The cost is that the server picks the swing direction itself, from the
	character's facing. Standing still and clicking at something behind you
	misses; the 120-degree arc keeps that from being fussy, and the alternative
	is trusting a direction the client sends.

	No loot - no enemy declares drops yet - and no player-versus-player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponConfig"))
local Profiler = require(Shared:WaitForChild("Debug"):WaitForChild("Profiler"))

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
local GearService = require(ServerScriptService:WaitForChild("GearService"))

local DEBUG = false
local function log(...)
	if DEBUG then
		print("[WeaponServer]", ...)
	end
end

-- player -> os.clock() of their last successful swing.
local lastSwingAt = {}

-- tool -> connection, so a tool that is equipped, unequipped and equipped again
-- is listened to once rather than three times.
--
-- Weak-keyed: a character destroyed wholesale on respawn does not raise
-- ChildRemoved for each tool inside it, so the explicit cleanup below cannot be
-- relied on to catch every one. The connections themselves die with their
-- instances either way; this stops the table holding the keys forever.
local connections = setmetatable({}, { __mode = "k" })

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

local function swing(player, tool)
	local stats = WeaponConfig.get(itemNameFor(tool))
	if not stats then
		-- A pickaxe or an axe. Mining and harvesting own those; this does not.
		return
	end

	local now = os.clock()
	local last = lastSwingAt[player]
	if last and now - last < stats.cooldown then
		return
	end

	local origin, facing = swingFrame(player)
	if not origin then
		return
	end

	lastSwingAt[player] = now
	Profiler.enter("Weapon.swing")

	-- Nearest, not first found: forEachNear walks a hash, so taking the first
	-- would make the target depend on table iteration order.
	local bestModel, bestDistance = nil, math.huge

	EnemyService.forEachNear(origin, stats.range, function(model, position)
		if facing then
			local offset = position - origin
			local flat = Vector3.new(offset.X, 0, offset.Z)

			-- Something standing exactly on top of the player has no direction
			-- to test; it is close enough to count.
			if flat.Magnitude > 1e-3 and flat.Unit:Dot(facing) < stats.arcCosine then
				return
			end
		end

		local distance = (position - origin).Magnitude
		if distance < bestDistance then
			bestModel, bestDistance = model, distance
		end
	end)

	if not bestModel then
		Profiler.count("Weapon.miss")
		Profiler.leave("Weapon.swing")
		return
	end

	local name = EnemyService.describe(bestModel)
	-- Weapon damage gear (a Battle Ring) applies here, at the moment of the hit.
	local alive = EnemyService.damage(bestModel, stats.damage * GearService.weaponMultiplier(player), player)

	Profiler.count("Weapon.hit")
	if not alive then
		Profiler.count("Weapon.kill")
	end

	log(string.format(
		"%s hit %s for %d with %s%s",
		player.Name, tostring(name), stats.damage, stats.name,
		if alive then "" else " (killed)"
	))

	Profiler.leave("Weapon.swing")
end

-- ---------------------------------------------------------------------------
-- Watching for tools
-- ---------------------------------------------------------------------------

local function untrack(tool)
	local connection = connections[tool]
	if connection then
		connection:Disconnect()
		connections[tool] = nil
	end
end

local function track(player, child)
	if not child:IsA("Tool") or connections[child] then
		return
	end

	-- Cheap gate: only weapons are worth a connection at all, and a tool cannot
	-- change what item it represents while it exists.
	local definition = ItemDefinitions[itemNameFor(child)]
	if not definition or definition.classification ~= "Weapon" then
		return
	end

	connections[child] = child.Activated:Connect(function()
		swing(player, child)
	end)
end

local function watchCharacter(player, character)
	for _, child in ipairs(character:GetChildren()) do
		track(player, child)
	end

	-- Only a Tool inside the CHARACTER can be activated; one sitting in the
	-- Backpack cannot. So equipping is what starts the listening, and
	-- unequipping is what stops it.
	character.ChildAdded:Connect(function(child)
		track(player, child)
	end)

	character.ChildRemoved:Connect(untrack)
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
	lastSwingAt[player] = nil
end)
