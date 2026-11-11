--[[
	AbilityCommands

	The chat commands for aspects.

	  /add <aspect>        grant one: active if you have none, else to storage
	  /aspect <aspect>     make it your active aspect now (the old one is gone)
	  /remove <aspect>     clear it if active, else drop one stored copy
	  /scroll <aspect>     drop a scroll for it on the ground in front of you
	  /abilities           your aspect, its slots, your storage, what exists

	An aspect can be named by itself ("ember") or by any of its abilities
	("fireball" means Ember) - see AspectConfig.resolveAny.

	ADMIN ONLY

	/add, /remove and /scroll are the place owner's, because handing every
	player a command that grants any ability in the game is not a progression
	system, it is a cheat menu - and /scroll is exactly that with one step in
	between, since anybody could then walk up to the thing they just dropped.
	/abilities stays open - it only reports what you are already carrying, which
	is a readout rather than a grant.

	That makes these a developer tool, not the equipping story: players earn
	aspects from wishes, scrolls and the tutorial, which call
	AbilityLoadout.grantAspect themselves.

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
local AspectConfig = require(Shared.Abilities:WaitForChild("AspectConfig"))
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
	local names = AspectConfig.names()

	local labels = table.create(#names)
	for index, name in ipairs(names) do
		labels[index] = AspectConfig.displayName(name)
	end

	return table.concat(labels, ", ")
end

local function describeLoadout(player: Player): string
	local aspect = AbilityLoadout.aspect(player)
	if not aspect then
		return "No aspect in use."
	end

	local carried = AbilityLoadout.get(player)
	local parts = table.create(#carried + 1)
	table.insert(parts, AspectConfig.displayName(aspect) .. ":")
	for slot, name in ipairs(carried) do
		local definition = AbilityConfig.Definitions[name]
		local key = AbilityConfig.keyForSlot(slot)
		parts[slot + 1] = string.format(
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
		command ~= "/add" and command ~= "/remove" and command ~= "/aspect"
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
		local stored = AbilityLoadout.stored(player)
		for index, name in ipairs(stored) do
			stored[index] = AspectConfig.displayName(name)
		end
		tell(player, "Stored: " .. (if #stored > 0 then table.concat(stored, ", ") else "nothing"))
		tell(player, "Aspects: " .. catalogue())
		return
	end

	-- Granting is the owner's. Said out loud rather than ignored, so a second
	-- account testing this is told why nothing happened.
	if not Permissions.isAdmin(player) then
		tell(player, "Only the place owner can change aspects.", "bad")
		return
	end

	if argument == "" then
		tell(player, string.format("Usage: %s <aspect>. Aspects: %s", command, catalogue()), "bad")
		return
	end

	local aspectName = AspectConfig.resolveAny(argument)
	if not aspectName then
		tell(player, string.format(
			"There is no aspect or ability called '%s'. Aspects: %s", argument, catalogue()
		), "bad")
		return
	end
	local label = AspectConfig.displayName(aspectName)

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
			aspectName, CFrame.new(spot.Position + Vector3.new(0, SCROLL_DROP_HEIGHT, 0))
		)

		if not instance then
			tell(player, problem or "Could not place that scroll.", "bad")
			return
		end

		tell(player, string.format("Dropped a %s aspect scroll.", label), "good")
		return
	end

	if command == "/add" then
		-- Overflow like a wish: an admin grant is not refused for want of slots.
		local where, second, line = AbilityLoadout.grantAspect(player, aspectName, nil, true)
		tell(player, if where then line else second, if where then "good" else "bad")
	elseif command == "/aspect" then
		AbilityLoadout.setAspect(player, aspectName)
		tell(player, string.format("%s is now your aspect.", label), "good")
	elseif AbilityLoadout.aspect(player) == aspectName then
		AbilityLoadout.clearAspect(player)
		tell(player, string.format("%s is no longer your aspect.", label), "good")
	elseif AbilityLoadout.unstore(player, aspectName) then
		tell(player, string.format("Removed a stored %s.", label), "good")
	else
		tell(player, string.format("You do not have %s.", label), "bad")
	end
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
