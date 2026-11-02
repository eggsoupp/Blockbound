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
local GuiService = game:GetService("GuiService")

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

--[[
	The other half: "please close this menu", for the same kind of caller.

	Used by StarterPlayerScripts.TutorialClient, whose ability choice sits in
	the Tab menu and has a button to carry on - the only way out of it for a
	player with no Tab key to press.
]]
MenuState.CloseRequested = Signal.new()

function MenuState.requestClose(name)
	MenuState.CloseRequested:Fire(name)
end

local openMenus = {}
local openCount = 0

local isLocked = false
local controls = nil
local cursorRequests = {}
local cursorHeld = false
local recovery = false
local windowFocused = true
local cursorModal = nil

-- Cursor ownership is independent of movement: settings and the bag allow
-- walking, but must still release shift-lock / first-person mouse capture.
local function updateCursor()
	if not RunService:IsClient() then return end
	local release = openCount > 0 or next(cursorRequests) ~= nil or recovery
		or not windowFocused or GuiService.MenuIsOpen
		or UserInputService:GetFocusedTextBox() ~= nil
	if cursorModal then cursorModal.Visible = release end
	if release or cursorHeld then
		-- Never restore a snapshot of MouseBehavior. It may represent a shift
		-- lock or right-drag that ended while the menu was open. On release the
		-- camera computes its current intent again on the next frame.
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	cursorHeld = release
end

-- For non-modal UI, without changing isAnyOpen or gameplay input guards.
function MenuState.setCursorRequired(name, required)
	cursorRequests[name] = if required then true else nil
	updateCursor()
end

function MenuState.recoverCursor()
	recovery = true
	updateCursor()
end

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
	updateCursor()

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
	updateCursor()

	for _, name in ipairs(names) do
		MenuState.Changed:Fire(name, false, false)
	end
end

if RunService:IsClient() then
	-- Tell the standard camera that UI owns the cursor. This also avoids
	-- camera rotation under menus. A tiny transparent button captures no panel.
	task.spawn(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "MenuCursorGuard"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = -100
		local modal = Instance.new("TextButton")
		modal.Name = "CursorModal"
		modal.Size = UDim2.fromOffset(1, 1)
		modal.BackgroundTransparency = 1
		modal.Text = ""
		modal.Active = false
		modal.Selectable = false
		modal.Modal = true
		modal.Visible = false
		modal.Parent = gui
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		cursorModal = modal
		updateCursor()
	end)

	-- Failsafe after the camera update, including right-drag while UI is up.
	-- No work outside cursor ownership except checking the current intent.
	RunService:BindToRenderStep("BlockboundMenuCursor", Enum.RenderPriority.Last.Value, updateCursor)
	GuiService.MenuOpened:Connect(updateCursor)
	GuiService.MenuClosed:Connect(updateCursor)
	UserInputService.WindowFocusReleased:Connect(function()
		windowFocused = false
		updateCursor()
	end)
	UserInputService.WindowFocused:Connect(function()
		windowFocused = true
		updateCursor()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		-- Emergency escape hatch even if another GUI consumed the key. Remains
		-- free until the player deliberately requests camera control again.
		if input.KeyCode == Enum.KeyCode.F8 then
			MenuState.recoverCursor()
		-- Roblox's shift-lock action can mark Shift as processed itself.
		elseif UserInputService:GetFocusedTextBox() == nil and
			(input.KeyCode == Enum.KeyCode.LeftShift
			or input.KeyCode == Enum.KeyCode.RightShift
			or (not processed and input.UserInputType == Enum.UserInputType.MouseButton2)) then
			recovery = false
		end
	end)
	-- Respawning drops the old controls object, so a lock held across a death
	-- would never be released.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		controls = nil
		table.clear(cursorRequests)
		recovery = false
		MenuState.closeAll()
		updateCursor()
	end)
end

return MenuState
