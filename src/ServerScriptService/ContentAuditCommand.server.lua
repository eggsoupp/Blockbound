--[[
	ContentAuditCommand

	  /contentaudit    run ServerScriptService.ContentAudit and report it

	The full report goes to the Output window - in Studio, the Output pane; in a
	live game, the Developer Console (F9) under Server. The player who asked
	gets the totals and the first few errors on screen.

	OWNER ONLY, by Permissions.isAdmin like every other developer command. The
	audit is read-only and safe on a live server, but it walks every instance in
	the place, so it is not something to hand every player a button for. A short
	cooldown stops it being run back to back.

	Chat is hidden during play and appears with the Tab menu (see
	Initialisation), so this is typed with the menu open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Permissions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Permissions"))
local ContentAudit = require(ServerScriptService:WaitForChild("ContentAudit"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

local COOLDOWN = 10

local running = false
local lastRunAt = -math.huge

local function onChatted(player, message)
	if string.lower(string.match(message, "^%s*(%S+)%s*$") or "") ~= "/contentaudit" then
		return
	end

	if not Permissions.isAdmin(player) then
		CommandFeedback.tell(player, "Only the game owner can run the content audit.", "bad")
		return
	end

	if running or os.clock() - lastRunAt < COOLDOWN then
		CommandFeedback.tell(player, "The content audit ran a moment ago; try again in a few seconds.", "bad")
		return
	end

	running = true
	lastRunAt = os.clock()
	CommandFeedback.tell(player, "Running the content audit...")

	local ok, report = pcall(ContentAudit.run)
	running = false

	if not ok then
		warn("[ContentAudit] the audit itself errored:", report)
		CommandFeedback.tell(player, "The content audit failed to run; see Output.", "bad")
		return
	end

	ContentAudit.printReport(report)

	local counts = ContentAudit.counts(report)
	for _, line in ipairs(ContentAudit.summarise(report, 3)) do
		CommandFeedback.tell(player, line, if counts.Errors > 0 then "bad" else "good")
	end
	CommandFeedback.tell(player, "Full report: Output window (in game: F9, Server tab).")
end

local function watch(player)
	player.Chatted:Connect(function(message)
		local ok, err = pcall(onChatted, player, message)
		if not ok then
			warn("[ContentAuditCommand] errored for", player.Name, err)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end
Players.PlayerAdded:Connect(watch)
