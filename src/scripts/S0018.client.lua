--[[
	CommandFeedback

	Puts what the server says into the feedback column.

	That column - the fading lines at the bottom left - is Shared.UI.Feedback
	now, and this is one of three things writing to it: the others are
	StarterPlayerScripts.ItemFeedback, which reports what the bag gained and
	lost, and StarterPlayerScripts.DropFlight, which reports what a kill dropped
	when it arrives.

	IT USED TO OWN THE COLUMN

	Every line in the game was built in here, which meant anything that wanted
	to tell the player something had to send itself a message from the server to
	get one - so the client-side things above could not have existed without a
	round trip they had no other reason to make. Moving the stack into Shared
	left this file with the job it actually has: listening to one remote.

	WHERE IT SITS is Shared.UI.Feedback, which owns the whole bottom-left
	column's geometry - and which has to stay clear of everything stacked under
	it. StarterPlayerScripts.ManaClient lists that column.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Feedback = require(Shared:WaitForChild("UI"):WaitForChild("Feedback"))

local CommandMessage = Remotes.wait("CommandMessage")

CommandMessage.OnClientEvent:Connect(function(text, tone)
	if type(text) ~= "string" or text == "" then
		return
	end

	Feedback.show(text, if type(tone) == "string" then tone else nil)
end)
