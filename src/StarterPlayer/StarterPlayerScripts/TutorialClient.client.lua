--[[
	TutorialClient

	Runs the tutorial: decides which step the guide shows and when, and keeps
	the guide out of the way of the menus. The guide itself is
	Shared.UI.TutorialPanel and the words are Shared.UI.TutorialSteps; this is
	the one place that holds the tutorial's current state.

	TODAY: THE WELCOME

	A second or two after the character and the HUD are up, the welcome step
	enters, once per play session. That is the whole sequence for now.

	LATER STEPS GO HERE

	Each step will be a small rule - what starts it and what finishes it - and
	the rules will drive the same three calls: panel:showStep(step) to move
	on, panel:hide() when the tutorial is done, and markSeen(id) so a step is
	not shown twice. Progress is a plain table of ids (`seen`) behind
	hasSeen/markSeen, so persisting it is a matter of loading that table from
	the player's save and writing it back; nothing in the DataStore format is
	touched yet, and nothing else in this file needs to change for it.

	THE MENUS

	Whenever any menu is open - the Tab menu, crafting, a chest, a confirm,
	the settings window - the guide is suppressed and fades out, so there is
	never a second wireframe competing with the Tab menu's own and no panel
	sitting under a window. It comes back as it was, expanded or collapsed,
	when the last menu closes. Done through MenuState.Changed, which is the
	one place that knows; nothing here touches the camera, the movement lock
	or any key.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local MenuState = require(UI:WaitForChild("MenuState"))
local TutorialSteps = require(UI:WaitForChild("TutorialSteps"))
local TutorialPanel = require(UI:WaitForChild("TutorialPanel"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- How long after the character and HUD are ready the welcome arrives. Long
-- enough that the player has seen the world and the HUD settle; short enough
-- that they have not wandered off before the game has said hello.
local WELCOME_DELAY = 1.6

-- ---------------------------------------------------------------------------
-- Progress
-- ---------------------------------------------------------------------------

-- Step ids this player has been shown. Per session for now; see the header
-- for how this becomes persistent.
local seen: { [string]: boolean } = {}

local function hasSeen(id: string): boolean
	return seen[id] == true
end

local function markSeen(id: string)
	seen[id] = true
end

-- ---------------------------------------------------------------------------
-- The guide
-- ---------------------------------------------------------------------------

local panel = TutorialPanel.new(playerGui)

-- Out of the way while any menu is up, back when none is. Checked against
-- the whole open set rather than the one that changed, so two menus closing
-- in either order restore the guide exactly once.
MenuState.Changed:Connect(function(_, _, anyOpen)
	panel:setSuppressed(anyOpen)
end)
panel:setSuppressed(MenuState.isAnyOpen())

local function showStep(id: string)
	local step = TutorialSteps.byId(id)
	if not step then
		warn(string.format("[TutorialClient] there is no tutorial step called %q", tostring(id)))
		return
	end

	markSeen(id)
	panel:showStep(step)
end

-- ---------------------------------------------------------------------------
-- The welcome
-- ---------------------------------------------------------------------------

-- The HUD scripts build as soon as they run and wait on nothing but the
-- character, so the character standing is the whole of "ready".
local function waitForCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart")
	character:WaitForChild("Humanoid")
end

task.spawn(function()
	if hasSeen("welcome") then
		return
	end

	waitForCharacter()
	task.wait(WELCOME_DELAY)

	showStep("welcome")
end)
