--[[
	AbilityCommands

	The chat commands that fill a player's ability slots.

	  /add <ability>       put one in the first free slot
	  /remove <ability>    take one out
	  /scroll <ability>    drop a scroll for it on the ground in front of you
	  /abilities           what you are carrying, and what exists

	Names are matched loosely, so "/add sacred rain" works as well as
	"/add SacredRain" - see AbilityConfig.resolve.

	ADMIN ONLY

	/add, /remove and /scroll are the place owner's, because handing every
	player a command that grants any ability in the game is not a progression
	system, it is a cheat menu - and /scroll is exactly that with one step in
	between, since anybody could then walk up to the thing they just dropped.
	/abilities stays open - it only reports what you are already carrying, which
	is a readout rather than a grant.

	That makes these a developer tool, not the eventual equipping story: when
	abilities are earned, the earning is what should call AbilityLoadout.add and
	this file is what should go.

	WHERE THE REPLY GOES

	Through CommandFeedback, like every other command in the game - see that
	module for why not the output window and why not the chat.

	Worth knowing: chat is hidden during play and appears with the Tab menu (see
	Initialisation), so these are typed with the menu open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))
local Permissions = require(Shared:WaitForChild("Permissions"))

local AbilityLoadout = require(ServerScriptService:WaitForChild("AbilityLoadout"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local ScrollService = require(ServerScriptService:WaitForChild("ScrollService"))

-- Minimum gap between commands from one player. Generous, because a person
-- typing cannot reach it; it only stops a script hammering the parser.
local MIN_INTERVAL = 0.25

-- Where /scroll puts one, relative to the player's root part: far enough
-- forward to be clear of them, and a stud down so it hangs at about their waist
-- rather than in their face.
local SCROLL_DROP_DISTANCE = 6
local SCROLL_DROP_HEIGHT = -1

local lastCommandAt = {}

local tell = CommandFeedback.tell

--[[
	Everything the player could type, as one line.

	Shown on a miss rather than only on /abilities, because "there is no ability
	called 'sacredrain '" is only half an answer - the other half is what there
	IS.
]]
local function catalogue(): string
	local names = AbilityConfig.names()

	local labels = table.create(#names)
	for index, name in ipairs(names) do
		local definition = AbilityConfig.Definitions[name]
		labels[index] = definition.displayName or name
	end

	return table.concat(labels, ", ")
end

local function describeLoadout(player: Player): string
	local carried = AbilityLoadout.get(player)
	if #carried == 0 then
		return string.format("No abilities. %d slots free.", AbilityConfig.SlotCount)
	end

	local parts = table.create(#carried)
	for slot, name in ipairs(carried) do
		local definition = AbilityConfig.Definitions[name]
		local key = AbilityConfig.keyForSlot(slot)
		parts[slot] = string.format(
			"%d%s %s",
			slot,
			if key then " [" .. key.Name .. "]" else "",
			definition and definition.displayName or name
		)
	end

	return table.concat(parts, "   ")
end

local function onChatted(player: Player, message: string)
	local command, argument = string.match(message, "^%s*(/%a+)%s*(.*)$")
	if not command then
		return
	end

	command = string.lower(command)
	if
		command ~= "/add" and command ~= "/remove"
		and command ~= "/scroll" and command ~= "/abilities"
	then
		return
	end

	local now = os.clock()
	local last = lastCommandAt[player]
	if last and now - last < MIN_INTERVAL then
		return
	end
	lastCommandAt[player] = now

	if command == "/abilities" then
		tell(player, describeLoadout(player))
		tell(player, "Available: " .. catalogue())
		return
	end

	-- Granting is the owner's. Said out loud rather than ignored, so a second
	-- account testing this is told why nothing happened.
	if not Permissions.isAdmin(player) then
		tell(player, "Only the place owner can change abilities.", "bad")
		return
	end

	if argument == "" then
		tell(player, string.format("Usage: %s <ability>. Available: %s", command, catalogue()), "bad")
		return
	end

	local abilityName = AbilityConfig.resolve(argument)
	if not abilityName then
		tell(player, string.format(
			"There is no ability called '%s'. Available: %s", argument, catalogue()
		), "bad")
		return
	end

	if command == "/scroll" then
		--[[
			A few paces in front, floating at about waist height.

			Where they are LOOKING rather than where they are standing, so it
			does not appear inside them. It bobs and turns on its own - see
			ScrollService - so the height only has to be roughly right; a scroll
			hanging at eye level would read as being handed to them rather than
			as something they found.
		]]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if not root then
			tell(player, "You need to be in the world to drop a scroll.", "bad")
			return
		end

		local spot = (root :: BasePart).CFrame * CFrame.new(0, 0, -SCROLL_DROP_DISTANCE)
		local instance, problem = ScrollService.place(
			abilityName, CFrame.new(spot.Position + Vector3.new(0, SCROLL_DROP_HEIGHT, 0))
		)

		if not instance then
			tell(player, problem or "Could not place that scroll.", "bad")
			return
		end

		local definition = AbilityConfig.Definitions[abilityName]
		tell(player, string.format(
			"Dropped a %s scroll.", definition and definition.displayName or abilityName
		), "good")
		return
	end

	local ok, reply
	if command == "/add" then
		ok, reply = AbilityLoadout.add(player, abilityName)
	else
		ok, reply = AbilityLoadout.remove(player, abilityName)
	end

	tell(player, reply, if ok then "good" else "bad")
end

local function watch(player: Player)
	player.Chatted:Connect(function(message)
		local ok, err = pcall(onChatted, player, message)
		if not ok then
			warn("[AbilityCommands] errored for", player.Name, err)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastCommandAt[player] = nil
end)
