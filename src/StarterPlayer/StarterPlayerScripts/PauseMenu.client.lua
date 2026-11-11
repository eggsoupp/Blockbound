--[[
	PauseMenu

	Tab opens the loadout view: the world blurs and dims, the camera eases back
	to a third-person framing, and the player stops moving.

	Tab is owned here and published through Shared.UI.MenuState; anything that
	wants to show or hide with this menu follows that rather than binding the
	key itself, which is what used to let two of them disagree and leave a panel
	floating over an unblurred game.

	IT USED TO BE THE SETTINGS VIEW AS WELL

	Sound and view distance were in here, as StarterPlayerScripts.OptionsPanel
	and a slider authored in the place file. Both are gone: they are settings you
	change WHILE PLAYING, and a modal menu that stops you moving and swings the
	camera is a bad place to put them. They live behind the gear in the topbar
	now - see StarterPlayerScripts.SettingsButton.

	Movement stops through MenuState too, and MenuState force-clears everything
	on respawn, so an error mid-animation cannot leave the player frozen.

	The backdrop art - the drifting wireframe solid - is Shared.UI.MenuBackdrop,
	which animates only while it is up and wears the aspect's tier colour. The
	aspect in use, shown over it, is Shared.UI.AbilityPanel. Both are built into
	the same dim frame and shown and hidden with it; neither is filled from here,
	because neither has anything to do with the Tab key.
	StarterPlayerScripts.AbilityClient is what puts the aspect in them.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MenuState = require(Shared:WaitForChild("UI"):WaitForChild("MenuState"))
local Theme = require(Shared.UI:WaitForChild("Theme"))
local MenuBackdrop = require(Shared.UI:WaitForChild("MenuBackdrop"))
local AbilityPanel = require(Shared.UI:WaitForChild("AbilityPanel"))
local QuestWindow = require(Shared.UI:WaitForChild("QuestWindow"))
local BestiaryWindow = require(Shared.UI:WaitForChild("BestiaryWindow"))
local AspectInventoryWindow = require(Shared.UI:WaitForChild("AspectInventoryWindow"))
local Responsive = require(Shared.UI:WaitForChild("Responsive"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))

local MENU_NAME = "PauseMenu"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Camera framing while the menu is up.
local ZOOM_DISTANCE = 15
local ZOOM_HEIGHT = 10
local CAMERA_TIME = 0.45

local blur = Instance.new("BlurEffect")
blur.Name = "PauseBlur"
blur.Size = 0
blur.Parent = Lighting

-- A dim layer so the menu reads as a distinct mode rather than the game merely
-- going fuzzy. Low DisplayOrder, so any real menu draws over it.
local backdropGui = Instance.new("ScreenGui")
backdropGui.Name = "PauseBackdrop"
backdropGui.ResetOnSpawn = false
backdropGui.IgnoreGuiInset = true
backdropGui.DisplayOrder = -1

--[[
	Set explicitly, because Instance.new gives a ScreenGui the CLASS default -
	Global - and not the Sibling that Studio's own insert does.

	Under Global, a child's ZIndex is compared against every other GuiObject in
	the whole ScreenGui rather than against its siblings, so nesting stops
	meaning anything: the ability panel asks to sit at 6, over art that tops out
	at 4, and the cards inside it - which never name a ZIndex and so are at 1 -
	would be judged on their own and land under the wireframe. CraftingUI sets
	this for the same reason.
]]
backdropGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

backdropGui.Enabled = false
backdropGui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Theme.Color.Backdrop
backdrop.BackgroundTransparency = 1
backdrop.BorderSizePixel = 0
backdrop.Parent = backdropGui

-- The art: a drifting wireframe solid behind everything. Parented inside the
-- dim rather than beside it, so it stays under the hint and under any real
-- menu without another DisplayOrder to keep in step.
local art = MenuBackdrop.new(backdrop)

-- The loadout, over the art. After it, so it draws over it as a sibling, and
-- inside the same frame so it inherits the dim's position and nothing else.
local panel = AbilityPanel.new(backdrop)

--[[
	The menu's other pages, opened from the loadout (its QUEST line and its
	BESTIARY pill) and each with a BACK to it. One page shows at a time.
]]
local page = nil

local function showPage(window)
	if page == window then
		return
	end
	if page then
		page:setVisible(false)
	end
	page = window
	if window then
		panel:setVisible(false)
		window:setVisible(true)
	else
		panel:setVisible(true)
	end
end

local guide = QuestWindow.new(backdrop, function()
	showPage(nil)
end)
local bestiary = BestiaryWindow.new(backdrop, function()
	showPage(nil)
end)
panel.onGuide = function()
	showPage(guide)
end
panel.onBestiary = function()
	showPage(bestiary)
end
-- The stored aspects, where one is picked to replace the aspect in use.
local inventory = AspectInventoryWindow.new(backdrop, function()
	showPage(nil)
end)
panel.onInventory = function()
	showPage(inventory)
end

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -18)
hint.Size = UDim2.fromOffset(320, 22)
hint.BackgroundTransparency = 1
hint.FontFace = Theme.Fonts.Body
hint.TextSize = Theme.TextSize.Small
hint.TextColor3 = Theme.Color.TextDim
hint.TextTransparency = 1
hint.Text = "Tab to resume"
hint.Parent = backdropGui

--[[
	The hotbar stays over this menu (and on a touch screen its Menu button), so
	the panel - the storage column, the loadout and the bin - is centred in the
	room UNDER the hotbar rather than on the screen, and shrunk only if that
	room is too small: on a short window or a phone its top would otherwise be
	under the hotbar. On a touch screen the hint names the button that closes
	it rather than a key.
]]
local panelScale = Instance.new("UIScale")
panelScale.Name = "FitScale"
panelScale.Parent = panel.root

local function placeForScreen()
	local root = panel.root
	local safe = Responsive.safe()
	if Responsive.isTouch() then
		hint.Text = "Tap Menu to resume"
		hint.Position = UDim2.new(0.5, 0, 1, -(safe.bottom + 4))
	else
		hint.Text = "Tab to resume"
		hint.Position = UDim2.new(0.5, 0, 1, -18)
	end

	-- The hotbar is hidden while this is open (see setHudHidden), so the room
	-- starts under the top bar.
	local top = Responsive.topbarBottom() + 8
	local bottom = Responsive.viewport().Y - safe.bottom - hint.Size.Y.Offset - 8
	-- Shrunk only as far as the room needs.
	local wide = (Responsive.viewport().X - safe.left - safe.right - 16) / math.max(1, root.Size.X.Offset)
	panelScale.Scale = math.clamp(math.min((bottom - top) / math.max(1, root.Size.Y.Offset), wide), 0.5, 1)
	local height = root.Size.Y.Offset * panelScale.Scale
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, math.max(top, (top + bottom - height) / 2))

	local width = Responsive.viewport().X - safe.left - safe.right
	guide:place(top, bottom, width)
	bestiary:place(top, bottom, width)
	inventory:place(top, bottom, width)
end

Responsive.bind(placeForScreen)
panel.root:GetPropertyChangedSignal("Size"):Connect(placeForScreen)

local isOpen = false

--[[
	The hotbar and the island button are hidden while the menu is up: neither
	does anything here, and both sit in the room the panel wants. The settings
	gear stays, since settings are still worth reaching from the menu.
]]
local HIDDEN_HUD = { "InventoryUI", "IslandRecall" }

local function setHudHidden(hidden: boolean)
	for _, name in ipairs(HIDDEN_HUD) do
		local gui = playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") then
			gui.Enabled = not hidden
		end
	end
end
local previousCFrame = nil
local cameraTween = nil

local COOLDOWN = 0.25
local lastToggleAt = 0

local function getCamera()
	return workspace.CurrentCamera
end

local function getThirdPersonCFrame()
	local camera = getCamera()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return camera and camera.CFrame or CFrame.new()
	end

	local rootPos = hrp.Position
	local backDir = -hrp.CFrame.LookVector
	local camPos = rootPos + Vector3.new(0, ZOOM_HEIGHT, 0) + backDir * ZOOM_DISTANCE
	local lookTarget = rootPos + Vector3.new(0, ZOOM_HEIGHT * 0.5, 0)

	return CFrame.new(camPos, lookTarget)
end

local function cancelCameraTween()
	if cameraTween then
		cameraTween:Cancel()
		cameraTween = nil
	end
end

local function openMenu()
	local camera = getCamera()
	if not camera then
		return
	end

	isOpen = true
	previousCFrame = camera.CFrame
	setHudHidden(true)

	backdropGui.Enabled = true
	art:setVisible(true)
	panel:setVisible(true)
	TweenService:Create(blur, Theme.Tween.Fade, { Size = 18 }):Play()
	TweenService:Create(backdrop, Theme.Tween.Fade, {
		BackgroundTransparency = Theme.Transparency.Backdrop,
	}):Play()
	TweenService:Create(hint, Theme.Tween.Fade, { TextTransparency = 0 }):Play()

	cancelCameraTween()
	camera.CameraType = Enum.CameraType.Scriptable
	cameraTween = TweenService:Create(
		camera,
		TweenInfo.new(CAMERA_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = getThirdPersonCFrame() }
	)
	cameraTween:Play()

	Sounds.play("ui.open")
	MenuState.setOpen(MENU_NAME, true)
end

local function closeMenu()
	isOpen = false
	if page then
		page:setVisible(false)
		page = nil
	end
	setHudHidden(false)

	art:setVisible(false)
	panel:setVisible(false)
	TweenService:Create(blur, Theme.Tween.Fade, { Size = 0 }):Play()
	TweenService:Create(hint, Theme.Tween.Fade, { TextTransparency = 1 }):Play()

	local fade = TweenService:Create(backdrop, Theme.Tween.Fade, { BackgroundTransparency = 1 })
	fade.Completed:Connect(function()
		if not isOpen then
			backdropGui.Enabled = false
		end
	end)
	fade:Play()

	cancelCameraTween()

	local camera = getCamera()
	if camera then
		if previousCFrame then
			cameraTween = TweenService:Create(
				camera,
				TweenInfo.new(CAMERA_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = previousCFrame }
			)
			-- Control has to go back to the player whether the tween finished or
			-- was cancelled by another toggle, or the camera stays stuck.
			cameraTween.Completed:Connect(function(state)
				if not isOpen and state == Enum.PlaybackState.Completed then
					camera.CameraType = Enum.CameraType.Custom
				end
			end)
			cameraTween:Play()
		else
			camera.CameraType = Enum.CameraType.Custom
		end
	end

	Sounds.play("ui.close")

	-- Released last, so movement only comes back once the view is on its way
	-- home rather than while the camera is still swinging.
	MenuState.setOpen(MENU_NAME, false)
end

local function toggle()
	local now = os.clock()
	if now - lastToggleAt < COOLDOWN then
		return
	end
	lastToggleAt = now

	if isOpen then
		closeMenu()
	else
		openMenu()
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.Tab then
		return
	end
	toggle()
end)

-- Follow anything else that force-closes the menus - a respawn, a script
-- bailing out - rather than being left thinking the menu is still up.
MenuState.Changed:Connect(function(name, open)
	if name == MENU_NAME and not open and isOpen then
		closeMenu()
	end
end)

--[[
	Somebody else wants this menu up - today, AbilityClient when an ability is
	gained, so the backdrop's flourish is played to a screen the player is
	looking at.

	Straight to openMenu rather than through toggle(), because this is not a
	press: the toggle's cooldown exists to absorb a key being hit twice and
	would silently swallow a request that arrived just after one.
]]
MenuState.OpenRequested:Connect(function(name)
	if name == MENU_NAME and not isOpen then
		openMenu()
	end
end)

MenuState.CloseRequested:Connect(function(name)
	if name == MENU_NAME and isOpen then
		closeMenu()
	end
end)

player.CharacterAdded:Connect(function()
	if isOpen then
		closeMenu()
	end

	local camera = getCamera()
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end)
