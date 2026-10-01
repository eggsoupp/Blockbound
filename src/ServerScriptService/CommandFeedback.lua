--[[
	CommandFeedback

	What a chat command says back to the person who typed it.

		CommandFeedback.tell(player, "5 x IronOre", "good")
		CommandFeedback.tell(player, "no item called 'irn'", "bad")

	WHY NOT print()

	Because print goes to the output window, and the output window is a Studio
	thing. Someone playing the game sees nothing at all, so a command that
	quietly did nothing and a command that worked look identical. Every reply
	that a person is meant to read goes through here.

	And not to the chat either: the server cannot write into a player's chat
	without going through TextChatService's own system messages, which are a
	different feature with their own formatting rules. A remote and a label the
	game owns is less machinery and looks like the rest of the game.

	The detailed dumps - stats tables, item lists, the profiler - still print.
	Those are for reading in Studio with a scrollbar, not for a corner of the
	screen; what goes here is the one-line receipt saying the command ran.

	Tones are "good", "bad", or nothing for neutral. The client picks the
	colour, so the wording and the colour cannot drift apart.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local CommandFeedback = {}

local CommandMessage = Remotes.ensure("CommandMessage", "RemoteEvent")

function CommandFeedback.tell(player: Player, text: string, tone: string?)
	if not player or type(text) ~= "string" or text == "" then
		return
	end

	CommandMessage:FireClient(player, text, tone or "info")
end

--[[
	A reply and an output-window copy in one call, which is what most debug
	commands want: the player sees the summary, Studio keeps the record.
]]
function CommandFeedback.report(player: Player, prefix: string, text: string, tone: string?)
	print(string.format("[%s] %s", prefix, text))
	CommandFeedback.tell(player, text, tone)
end

return CommandFeedback
