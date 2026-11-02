--[[
	IslandRecall

	The top bar's island button: five seconds of standing in a teleport aura,
	then home - or, from your own island, back to the world.

	THE SERVER KEEPS THE CLOCK

	The client only asks to start or to stop. Everything that decides whether
	the trip happens is here: the channel is RECALL_SECONDS long by the
	server's clock, any hit that lands cancels it (CombatService.onDamaged - a
	hit, not merely health going down, so taking armour off is not one), and
	so does dying or respawning. So does doing anything at all but look
	around: moving, jumping, using or changing a tool, any action request (an
	ability, a swing, mining, placing), and - reported by the client - any key
	or left click. Only a channel that runs its full length
	sends the player anywhere.

	EVERYONE SEES IT

	While a channel runs, the character carries RecallUntil (server time) and
	RecallTo. Every client draws the aura off those (IslandRecallClient), so
	other players see someone leaving, not only the one who is.

	The remote speaks both ways:
	  client -> server   "start" | "cancel"
	  server -> client   "started", seconds, destination
	                     "cancelled", reason ("damage" | "died" | "moved" | "input" | "player")
	                     "arrived", destination   (the teleport was sent)
	                     "failed"                 (it could not be; Travel said why)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Remotes"))
local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local Travel = require(ServerScriptService:WaitForChild("Travel"))

local Recall = Remotes.ensure("IslandRecall", "RemoteEvent")

local RECALL_SECONDS = 5

-- Between one channel ending and the next starting, so a held button or a
-- spammed one cannot start a second before the first has cleaned up.
local COOLDOWN = 1.5

-- player -> { token, character, connections }
local channels = {}
local lastEndedAt = {}
local nextToken = 0

local function clearCharacter(character: Model?)
	if character then
		character:SetAttribute("RecallUntil", nil)
		character:SetAttribute("RecallTo", nil)
	end
end

local function stop(player: Player, reason: string?)
	local channel = channels[player]
	if not channel then
		return
	end
	channels[player] = nil
	lastEndedAt[player] = os.clock()

	for _, connection in ipairs(channel.connections) do
		connection:Disconnect()
	end
	clearCharacter(channel.character)

	if reason and player.Parent then
		Recall:FireClient(player, "cancelled", reason)
	end
end

local function start(player: Player)
	if channels[player] or os.clock() - (lastEndedAt[player] or -math.huge) < COOLDOWN then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local destination = if Travel.onOwnIsland(player) then "world" else "island"

	nextToken += 1
	local token = nextToken
	local channel = { token = token, character = character, connections = {} }
	channels[player] = channel

	table.insert(channel.connections, humanoid.Died:Connect(function()
		stop(player, "died")
	end))
	table.insert(channel.connections, player.CharacterRemoving:Connect(function()
		stop(player, "died")
	end))

	-- Doing anything the server can see stops it: walking, jumping, taking out
	-- or using a tool. (Actions sent over remotes are below; keys and clicks
	-- the server cannot see are cancelled by the client.)
	table.insert(channel.connections, humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		if humanoid.MoveDirection.Magnitude > 0.05 then
			stop(player, "moved")
		end
	end))
	table.insert(channel.connections, humanoid.Jumping:Connect(function(active)
		if active then
			stop(player, "moved")
		end
	end))
	local function watchTool(tool: Instance)
		if tool:IsA("Tool") then
			table.insert(channel.connections, tool.Activated:Connect(function()
				stop(player, "input")
			end))
		end
	end
	for _, child in ipairs(character:GetChildren()) do
		watchTool(child)
	end
	table.insert(channel.connections, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			stop(player, "input")
		end
	end))
	table.insert(channel.connections, character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			stop(player, "input")
		end
	end))

	character:SetAttribute("RecallTo", destination)
	character:SetAttribute("RecallUntil", workspace:GetServerTimeNow() + RECALL_SECONDS)
	Recall:FireClient(player, "started", RECALL_SECONDS, destination)

	task.delay(RECALL_SECONDS, function()
		if channels[player] ~= channel then
			return
		end
		stop(player, nil)

		if Travel.go(player, destination) then
			Recall:FireClient(player, "arrived", destination)
		elseif player.Parent then
			Recall:FireClient(player, "failed")
		end
	end)
end

Recall.OnServerEvent:Connect(function(player, action, reason)
	if action == "start" then
		start(player)
	elseif action == "cancel" then
		-- "input": a key or click the client saw; anything else is the button.
		stop(player, if reason == "input" then "input" else "player")
	end
end)

--[[
	Any action request breaks it too: an ability, a swing, mining, placing,
	changing what is held. Listened to beside the scripts that own them, so
	none of those has to know a recall exists.
]]
local ACTION_REMOTES = {
	"RequestAbility", "WeaponInput", "RequestMineBlock", "RequestPlaceBlock",
	"RequestEquipTool", "AltarUseRequest",
}
for _, name in ipairs(ACTION_REMOTES) do
	task.spawn(function()
		local remote = Remotes.wait(name, 30)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnServerEvent:Connect(function(player)
				if channels[player] then
					stop(player, "input")
				end
			end)
		end
	end)
end

-- Any hit that lands breaks the channel. A fully absorbed one does not.
CombatService.onDamaged(function(player)
	if channels[player] then
		stop(player, "damage")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	stop(player, nil)
	lastEndedAt[player] = nil
end)
