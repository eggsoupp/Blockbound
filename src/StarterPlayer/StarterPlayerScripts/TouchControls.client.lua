--[[
	TouchControls

	The buttons a phone or tablet needs in place of a keyboard. Nothing is
	built into the screen on a computer: the GUI exists but stays disabled
	unless Shared.UI.Responsive says this is a touch screen, and follows it if
	that changes (a tablet with a keyboard plugged in).

	WHAT IS WHERE

	  Round the jump button, bottom right, where the right thumb already is:
	    ATTACK      uses the held tool, the same as a click. Held down, it is
	                held down: the sword's combo runs for as long as it is.
	    abilities   one button per filled slot, named, with the cooldown
	                draining over it. They cast through AbilityClient, so a
	                tap obeys every rule a key press does.
	    RUN toggle, above the abilities.

	  Beside the hotbar, top left:
	    BAG, CRAFT, MENU   the E, B and Tab keys.

	Everything else already works with a finger: the hotbar's slots are
	tapped, the world is tapped to place and held to mine (Shared.UI.Pointer),
	and prompts and menus are ordinary buttons.

	THE ROUND BUTTONS ARE ROBLOX-SHAPED

	Dark translucent circles like the jump button they sit round, not the
	pixel kit's wood: they are controls over the world rather than a window,
	and next to the jump button anything else looks like two games. The menu
	buttons are the kit's, since they open the kit's windows.

	OUT OF THE WAY

	The cluster is laid out from Responsive.jump(), so it moves with the jump
	button between phone and tablet sizes. While the bag or a menu is open it
	is hidden, along with Roblox's thumbstick and jump button, so nothing is
	drawn over the window being used.

	Sizes are touch sizes in screen points, never HUD-scaled: a finger does not
	get smaller on a smaller phone. Nothing is under 44 points.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelUI = require(UI:WaitForChild("PixelUI"))
local MenuState = require(UI:WaitForChild("MenuState"))
local Responsive = require(UI:WaitForChild("Responsive"))
local TouchActions = require(UI:WaitForChild("TouchActions"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local AbilityConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- Measurements, in points on a phone, multiplied by Responsive.clusterScale():
-- bigger round a tablet's bigger jump button, a little smaller on a short screen.
-- ---------------------------------------------------------------------------

local ATTACK_SIZE = 72
local ATTACK_OFFSET = Vector2.new(-95, 0)

local ABILITY_SIZE = 56
local ABILITY_RADIUS = 132
local ABILITY_ANGLES = { 145, 115, 85 }

--[[
	Left of the ability arc rather than above it: above, they ran into the
	Bag/Craft/Menu row on a phone. RUN's bottom stays above the health column
	beside ATTACK, which is what lets that column sit bottom centre. Keep
	Responsive's ACTIONS_REACH numbers in step with these.
]]
local TOGGLE_SIZE = 48
local RUN_OFFSET = Vector2.new(-165, -60)

-- Apple's and Google's smallest comfortable target.
local MIN_TOUCH = 44

local MENU_BUTTON = Vector2.new(60, 44)
local MENU_GAP = 6
local MENU_MARGIN = 10

local FACE = Color3.fromRGB(20, 20, 24)
local FACE_IDLE = 0.4
local FACE_PRESSED = 0.15
local FACE_ON = Theme.PixelColor.Selection
local SHADE = Color3.fromRGB(0, 0, 0)

-- ---------------------------------------------------------------------------
-- The screen
-- ---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "TouchControls"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
-- Over the HUD (5-8) and under every window (10 and up), so a window's own
-- close button is never beneath one of these.
gui.DisplayOrder = 9
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local actions = Instance.new("Frame")
actions.Name = "Actions"
actions.BackgroundTransparency = 1
actions.Size = UDim2.fromScale(1, 1)
actions.Parent = gui

local menuRow = Instance.new("Frame")
menuRow.Name = "MenuRow"
menuRow.BackgroundTransparency = 1
menuRow.Parent = gui

-- ---------------------------------------------------------------------------
-- Round buttons
-- ---------------------------------------------------------------------------

--[[
	A circle with a label, and a face that darkens while a finger is on it.
	Pressed/released are reported for the whole time the finger is down, which
	is what holding ATTACK needs; a tap is just the two close together.

	The face is a CanvasGroup so the cooldown shade drawn inside it is clipped
	to the circle.
]]
local function roundButton(name: string, text: string)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Parent = actions

	local face = Instance.new("CanvasGroup")
	face.Name = "Face"
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundColor3 = FACE
	face.BackgroundTransparency = FACE_IDLE
	face.BorderSizePixel = 0
	face.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = face

	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = SHADE
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.Parent = face

	-- The ring is outside the CanvasGroup so it is not clipped by it.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.Parent = button

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.45
	stroke.Thickness = 2
	stroke.Parent = ring

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.84, 0.7)
	label.FontFace = Theme.Fonts.Heading
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = text
	label.ZIndex = 3
	label.Parent = button

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 9
	limit.MaxTextSize = 16
	limit.Parent = label

	local handle = { button = button, face = face, shade = shade, stroke = stroke, label = label, lit = false }
	local pressListeners, releaseListeners = {}, {}
	local down: InputObject? = nil

	local function paint()
		face.BackgroundColor3 = if handle.lit then FACE_ON else FACE
		face.BackgroundTransparency = if down then FACE_PRESSED elseif handle.lit then 0.25 else FACE_IDLE
	end
	handle.paint = paint

	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if down or (kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1) then
			return
		end
		down = input
		paint()
		for _, listener in ipairs(pressListeners) do
			task.spawn(listener)
		end
	end)

	local function release(input: InputObject)
		if input ~= down then
			return
		end
		down = nil
		paint()
		for _, listener in ipairs(releaseListeners) do
			task.spawn(listener)
		end
	end
	button.InputEnded:Connect(release)
	-- A finger sliding off the button still lets go of it.
	game:GetService("UserInputService").InputEnded:Connect(release)

	function handle.onPress(listener)
		table.insert(pressListeners, listener)
	end
	function handle.onRelease(listener)
		table.insert(releaseListeners, listener)
	end
	function handle.release()
		if down then
			release(down)
		end
	end

	paint()
	return handle
end

-- ---------------------------------------------------------------------------
-- ATTACK
-- ---------------------------------------------------------------------------

local function heldTool(): Tool?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Tool")
end

local function itemNameFor(tool: Tool): string
	local attribute = tool:GetAttribute("ItemName") or tool:GetAttribute("itemName")
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end
	local value = tool:FindFirstChild("ItemName") or tool:FindFirstChild("itemName")
	if value and value:IsA("StringValue") and value.Value ~= "" then
		return value.Value
	end
	return tool.Name
end

--[[
	What ATTACK says for the held tool, or nil to hide it. Weapons only: a
	sword swings at whatever is in front of the player, but an axe and a
	pickaxe act on the thing under the pointer, so they are used by touching
	the tree or the block itself - a button would chop whatever happened to be
	behind the button.
]]
local function attackLabel(tool: Tool?): string?
	if not tool then
		return nil
	end
	local definition = ItemDefinitions[itemNameFor(tool)]
	if definition and definition.classification == "Weapon" then
		return "ATTACK"
	end
	return nil
end

local attack = roundButton("Attack", "ATTACK")
local attackingWith: Tool? = nil

attack.onPress(function()
	local tool = heldTool()
	if tool and not MenuState.isAnyOpen() then
		attackingWith = tool
		tool:Activate()
	end
end)

attack.onRelease(function()
	local tool = attackingWith
	attackingWith = nil
	if tool and tool.Parent then
		tool:Deactivate()
	end
end)

-- ---------------------------------------------------------------------------
-- Abilities
-- ---------------------------------------------------------------------------

local abilityButtons = {}
for slot = 1, AbilityConfig.SlotCount do
	local handle = roundButton("Ability" .. slot, "")
	handle.onPress(function()
		TouchActions.requestCast(slot)
	end)
	abilityButtons[slot] = handle
end

-- ---------------------------------------------------------------------------
-- RUN
-- ---------------------------------------------------------------------------

--[[
	Toggles rather than holds: one thumb is on the stick and the other has the
	attack and ability buttons to reach. The character script reads these
	attributes (StarterCharacterScripts.spring-crouch-walk) and clears them
	itself when a menu stops a sprint, so the lit state is read back from them.
]]
local run = roundButton("Run", "RUN")

run.onPress(function()
	player:SetAttribute("TouchSprint", not player:GetAttribute("TouchSprint"))
	Sounds.play("ui.click")
end)

-- ---------------------------------------------------------------------------
-- BAG, CRAFT, MENU
-- ---------------------------------------------------------------------------

local function isMenuOpen(name: string): boolean
	if name == "Inventory" then
		return player:GetAttribute("InventoryOpen") == true
	end
	return MenuState.isOpen(name)
end

local menuButtons = {}

local function menuButton(order: number, text: string, menu: string)
	local handle = PixelUI.button(menuRow, {
		name = menu,
		text = text,
		textSize = Theme.TextSize.Body,
		size = UDim2.fromOffset(MENU_BUTTON.X, MENU_BUTTON.Y),
		sound = "ui.click",
		onClick = function()
			if isMenuOpen(menu) then
				MenuState.requestClose(menu)
			else
				-- One window at a time: whichever is up gives way.
				for _, other in ipairs(menuButtons) do
					if other.menu ~= menu and isMenuOpen(other.menu) then
						MenuState.requestClose(other.menu)
					end
				end
				MenuState.requestOpen(menu)
			end
		end,
	})
	handle.button.LayoutOrder = order
	handle.menu = menu
	table.insert(menuButtons, handle)
	return handle
end

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding = UDim.new(0, MENU_GAP)
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rowLayout.Parent = menuRow

menuButton(1, "Bag", "Inventory")
menuButton(2, "Craft", "Crafting")
menuButton(3, "Menu", "PauseMenu")

local MENU_ROW_WIDTH = #menuButtons * MENU_BUTTON.X + (#menuButtons - 1) * MENU_GAP

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local function place(handle, centre: Vector2, size: number)
	size = math.max(size, MIN_TOUCH)
	handle.button.Position = UDim2.fromOffset(centre.X, centre.Y)
	handle.button.Size = UDim2.fromOffset(size, size)
end

local function layout()
	gui.Enabled = Responsive.isTouch()
	if not gui.Enabled then
		return
	end

	local jump = Responsive.jump()
	-- Grows with the jump button on a tablet; shrinks a touch on a short
	-- screen. Shared with Responsive.hudColumn, which keeps clear of it.
	local k = Responsive.clusterScale()

	place(attack, jump + ATTACK_OFFSET * k, ATTACK_SIZE * k)
	for slot, handle in ipairs(abilityButtons) do
		local angle = math.rad(ABILITY_ANGLES[slot] or 90)
		local offset = Vector2.new(math.cos(angle), -math.sin(angle)) * ABILITY_RADIUS
		place(handle, jump + offset * k, ABILITY_SIZE * k)
	end
	place(run, jump + RUN_OFFSET * k, TOGGLE_SIZE * k)

	--[[
		Right of the hotbar, centred on it. A screen too narrow for that - a
		phone held upright - gets them under the top bar on the right instead.
	]]
	local viewport = Responsive.viewport()
	local safe = Responsive.safe()
	local hotbar = Responsive.hotbarRect()
	menuRow.Size = UDim2.fromOffset(MENU_ROW_WIDTH, MENU_BUTTON.Y)
	local right = viewport.X - safe.right - MENU_MARGIN
	if hotbar and not Responsive.menuRowBelow() then
		menuRow.AnchorPoint = Vector2.new(0, 0.5)
		menuRow.Position = UDim2.fromOffset(hotbar.Max.X + MENU_MARGIN, (hotbar.Min.Y + hotbar.Max.Y) / 2)
	else
		-- Under the held item's name, which hangs under the hotbar.
		local top = if hotbar then Responsive.labelBottom() else Responsive.topbarBottom()
		menuRow.AnchorPoint = Vector2.new(1, 0)
		menuRow.Position = UDim2.fromOffset(right, top + MENU_MARGIN)
	end
end

Responsive.bind(layout)

-- ---------------------------------------------------------------------------
-- Every frame: what shows, and the cooldowns
-- ---------------------------------------------------------------------------

local touchControlsHidden = false

--[[
	Roblox's thumbstick and jump button go with ours while a window is up.
	GuiService.TouchControlsEnabled is the current switch; older clients only
	have ModalEnabled.
]]
local function setRobloxControls(visible: boolean)
	if touchControlsHidden == not visible then
		return
	end
	touchControlsHidden = not visible
	local ok = pcall(function()
		GuiService.TouchControlsEnabled = visible
	end)
	if not ok then
		game:GetService("UserInputService").ModalEnabled = not visible
	end
end

local function windowUp(): boolean
	return MenuState.isAnyOpen() or player:GetAttribute("InventoryOpen") == true
end

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		setRobloxControls(true)
		return
	end

	local covered = windowUp()
	actions.Visible = not covered
	setRobloxControls(not covered)
	if covered then
		attack.release()
	end

	-- With the bag open, only Bag (to shut it) stays: the gear column goes up
	-- the right-hand side, where Craft and Menu would sit on it.
	local bagOpen = player:GetAttribute("InventoryOpen") == true
	for _, handle in ipairs(menuButtons) do
		handle.button.Visible = not bagOpen or handle.menu == "Inventory"
		local open = isMenuOpen(handle.menu)
		if handle.lit ~= open then
			handle.lit = open
			handle.setColor(if open then "green" else "tan")
		end
	end

	local label = attackLabel(heldTool())
	attack.button.Visible = label ~= nil
	if label then
		attack.label.Text = label
	end

	for slot, handle in ipairs(abilityButtons) do
		local info = TouchActions.getSlot(slot)
		handle.button.Visible = info ~= nil
		if info then
			local cooling = info.cooldown > 0 and info.remaining > 0
			handle.shade.Size = UDim2.fromScale(1, if cooling then info.remaining / info.cooldown else 0)
			handle.label.Text = if cooling then string.format("%s\n%.1f", info.name, info.remaining) else info.name
			handle.stroke.Color = if cooling then Color3.fromRGB(140, 140, 140) else FACE_ON
			handle.stroke.Transparency = if cooling then 0.5 else 0.1
		end
	end

	local on = player:GetAttribute("TouchSprint") == true
	if run.lit ~= on then
		run.lit = on
		run.paint()
	end
end)
