--[[
	Initialisation

	Which pieces of Roblox's default interface this game keeps, and when.

	The game draws its own hotbar, its own inventory, its own health and its own
	pause menu, so most of the built-in chrome is not just redundant - it sits on
	top of the real thing and takes clicks meant for it. Everything below is
	either off permanently or tied to a state the player controls.

	CHAT IS A PAUSE-MENU FEATURE
	  Chat is hidden during play and appears with the Tab menu. In a game where
	  the mouse is aiming a pickaxe, a permanent chat bar is a permanent target
	  for clicks that were meant for the world, and the `/` keybind steals a key
	  from gameplay.

	  NOTE FOR ADMIN COMMANDS: DebugConsole listens on Player.Chatted, so
	  /bbstats, /bbbench, /give and the rest are now typed with the pause menu
	  open. They work exactly as before once it is.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MenuState = require(Shared:WaitForChild("UI"):WaitForChild("MenuState"))

-- Matches PauseMenu.MENU_NAME. The two have to agree or chat never appears.
local PAUSE_MENU = "PauseMenu"

-- Can throw if the CoreGui has not finished loading, which on a slow join can
-- happen after this script runs. Reported rather than swallowed.
local function setCoreGui(coreGuiType, enabled)
	local ok, err = pcall(function()
		StarterGui:SetCoreGuiEnabled(coreGuiType, enabled)
	end)

	if not ok then
		warn("[Initialisation] Could not set CoreGui", tostring(coreGuiType), err)
	end
end

-- ---------------------------------------------------------------------------
-- Permanently off
-- ---------------------------------------------------------------------------

-- The Tab player list would fight the pause menu for the same key.
setCoreGui(Enum.CoreGuiType.PlayerList, false)

-- The health bar; HealthClient draws this game's own.
setCoreGui(Enum.CoreGuiType.Health, false)

-- The default backpack: a second, competing view of the same tools sitting on
-- top of InventoryClient's hotbar. Hides the UI only - tools still live in
-- Player.Backpack and EquipServer still equips them.
setCoreGui(Enum.CoreGuiType.Backpack, false)

-- ---------------------------------------------------------------------------
-- Chat, gated on the pause menu
-- ---------------------------------------------------------------------------

-- Both chat implementations are addressed: SetCoreGuiEnabled hides the window
-- under either, but only the TextChatService configuration objects stop the
-- input bar being summoned with `/` while the window is hidden.
local usingTextChat = false
do
	local ok, version = pcall(function()
		return TextChatService.ChatVersion
	end)
	usingTextChat = ok and version == Enum.ChatVersion.TextChatService
end

-- Looked up per call, not cached: the engine creates these as TextChatService
-- comes up, which is not guaranteed to be before this script runs.
local function chatConfig(className)
	if not usingTextChat then
		return nil
	end
	return TextChatService:FindFirstChildOfClass(className)
end

local function setChatEnabled(enabled)
	setCoreGui(Enum.CoreGuiType.Chat, enabled)

	local window = chatConfig("ChatWindowConfiguration")
	if window then
		window.Enabled = enabled
	end

	local input = chatConfig("ChatInputBarConfiguration")
	if input then
		input.Enabled = enabled
	end
end

local function syncChatToMenu()
	setChatEnabled(MenuState.isOpen(PAUSE_MENU))
end

-- Read from MenuState rather than trusting the event's argument, so that a
-- close driven from somewhere else - MenuState.closeAll, a respawn - lands on
-- the same answer as a close driven by the Tab key.
MenuState.Changed:Connect(function(name)
	if name == PAUSE_MENU then
		syncChatToMenu()
	end
end)

syncChatToMenu()
