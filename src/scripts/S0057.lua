--[[
	MenuState

	Which full-screen menus are open, and the one implementation of "the player
	cannot walk while a menu is up". Client-only.

		MenuState.setOpen("PauseMenu", true)
		MenuState.isAnyOpen()
		MenuState.Changed:Connect(function(name, open, anyOpen) ... end)

	Locking goes through the PlayerModule's own control object, which is the
	supported way and handles already-held keys, the mobile thumbstick and
	gamepads. Zeroing WalkSpeed would do none of that and would fight the
	sprint/crouch script over the same property.

	The lock is reference counted against the open set, so two menus closing in
	either order restore movement exactly once.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MenuState = {}

-- A BindableEvent would copy its arguments and need an instance to live in.
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(handler)
	table.insert(self.handlers, handler)

	return {
		Disconnect = function()
			local index = table.find(self.handlers, handler)
			if index then
				table.remove(self.handlers, index)
			end
		end,
	}
end

function Signal:Fire(...)
	-- Iterate a copy: a handler is allowed to disconnect itself.
	for _, handler in ipairs(table.clone(self.handlers)) do
		local ok, err = pcall(handler, ...)
		if not ok then
			warn("[MenuState] listener error:", err)
		end
	end
end

MenuState.Changed = Signal.new()

--[[
	"Please open this menu", for code that has a reason to but does not own the
	key.

		MenuState.requestOpen("PauseMenu")

	Separate from setOpen, which REPORTS that a menu is open and is only ever
	called by the menu itself. Nothing else can call setOpen honestly: writing
	it from outside would tell the movement lock a menu is up while the menu
	itself knows nothing about it, and the two would never agree again.

	The owner listens to this and does its own opening, so all the animation,
	the camera and the sound still happen exactly once, in the one place that
	knows how. A menu with nobody listening simply does not open, which is the
	right outcome for a request rather than an order.

	Used by StarterPlayerScripts.AbilityClient: gaining an ability opens the Tab
	menu, because the flourish it sets off is drawn in there and playing it to a
	closed menu means the player misses the one thing it exists to show them.
]]
MenuState.OpenRequested = Signal.new()

function MenuState.requestOpen(name)
	MenuState.OpenRequested:Fire(name)
end

local openMenus = {}
local openCount = 0

local isLocked = false
local controls = nil
local savedMouseBehavior = nil

-- ---------------------------------------------------------------------------
-- Movement lock
-- ---------------------------------------------------------------------------

-- Fetched lazily: PlayerScripts is populated a moment after the first
-- LocalScript runs.
local function getControls()
	if controls then
		return controls
	end

	if not RunService:IsClient() then
		return nil
	end

	local player = Players.LocalPlayer
	local playerScripts = player and player:FindFirstChild("PlayerScripts")
	local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not module then
		return nil
	end

	local ok, result = pcall(function()
		return require(module):GetControls()
	end)

	if ok and result then
		controls = result
	else
		warn("[MenuState] PlayerModule controls unavailable; movement will not lock.")
	end

	return controls
end

local function setLocked(shouldLock)
	if shouldLock == isLocked then
		return
	end
	isLocked = shouldLock

	local control = getControls()
	if control then
		if shouldLock then
			control:Disable()
		else
			control:Enable()
		end
	end

	-- Free the cursor so menus are clickable from shift-lock or first person,
	-- then put it back exactly as it was.
	if shouldLock then
		savedMouseBehavior = UserInputService.MouseBehavior
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	elseif savedMouseBehavior then
		UserInputService.MouseBehavior = savedMouseBehavior
		savedMouseBehavior = nil
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Menus that should not stop the player moving pass `locksMovement = false`.
function MenuState.setOpen(name, open, locksMovement)
	open = open == true

	local wasOpen = openMenus[name] ~= nil
	if wasOpen == open then
		return
	end

	if open then
		openMenus[name] = { locksMovement = locksMovement ~= false }
		openCount += 1
	else
		openMenus[name] = nil
		openCount -= 1
	end

	local shouldLock = false
	for _, entry in pairs(openMenus) do
		if entry.locksMovement then
			shouldLock = true
			break
		end
	end
	setLocked(shouldLock)

	MenuState.Changed:Fire(name, open, openCount > 0)
end

function MenuState.isOpen(name)
	return openMenus[name] ~= nil
end

function MenuState.isAnyOpen()
	return openCount > 0
end

-- The safety net for a menu whose owner errored mid-animation: without it, a
-- script error while a menu is open leaves the player unable to move.
function MenuState.closeAll()
	if openCount == 0 then
		return
	end

	local names = {}
	for name in pairs(openMenus) do
		table.insert(names, name)
	end

	table.clear(openMenus)
	openCount = 0
	setLocked(false)

	for _, name in ipairs(names) do
		MenuState.Changed:Fire(name, false, false)
	end
end

if RunService:IsClient() then
	-- Respawning drops the old controls object, so a lock held across a death
	-- would never be released.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		controls = nil
		MenuState.closeAll()
	end)
end

return MenuState
