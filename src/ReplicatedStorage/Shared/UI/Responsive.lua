--[[
	Responsive

	What kind of screen this is, and where on it the game may draw. Client only.

		Responsive.isTouch()       a phone or tablet: no keyboard, fingers on glass
		Responsive.viewport()      the screen's size, in GUI pixels
		Responsive.safe()          insets from each edge that a notch or rounded
		                           corner takes: { left, top, right, bottom }
		Responsive.topbarBottom()  the y under Roblox's top bar
		Responsive.hudScale()      how big the HUD is drawn: 1 on a computer,
		                           smaller on a phone
		Responsive.jump()          centre and radius of Roblox's jump button
		Responsive.stickRight()    the right edge of the thumbstick's area
		Responsive.hotbarBottom()  the y under the hotbar, once it exists
		Responsive.canvas(gui)     a frame filling `gui` whose children are laid
		                           out in HUD pixels (see below)
		Responsive.bind(fn)        fn() now and whenever any of the above changes

	Everything is measured in the space of a ScreenGui that ignores the top bar
	inset, which is what every HUD here uses: (0, 0) is the window's corner.

	WHY THE HUD IS NOT JUST MOVED

	A phone in landscape is about 390 pixels tall, under half of the 1080 the
	HUD was drawn for. Drawn at full size the bars would cover a third of it,
	so the HUD is scaled, and moved out from under the thumbstick, which sits
	where the bars do. Menus fit themselves already; this is for what is always
	on screen.

	THE CANVAS

	A full-screen Frame with a UIScale of hudScale(), sized 1/scale so that,
	after scaling, it covers the screen exactly. Anything parented to it keeps
	its Offsets in HUD pixels and its Scales relative to the screen: a bar at
	UDim2.new(0, 16, 1, -40) lands 16*s in from the left and 40*s up from the
	bottom. So a HUD script only has to change its parent.

	ROBLOX'S OWN TOUCH CONTROLS

	jump() and stickRight() copy the PlayerModule's arithmetic, so the game's
	buttons can be laid out round the jump button and kept out of the
	thumbstick's corner without reading Roblox's GUI, which can be redrawn at
	any time.

	TESTING ON A COMPUTER

	Three attributes on the LocalPlayer stand in for a device, for a test
	harness: EmulateTouch (bool), EmulateViewport (Vector2) and EmulateSafe
	(Rect, its Min the left/top insets and its Max the right/bottom ones).
	Nothing in the game sets them.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Responsive = {}

-- Roblox's own line between a phone and a tablet, from its touch controls.
local SMALL_SCREEN = 500

-- Roblox reports no top bar for a moment while it sets up. 36 is its desktop
-- bar, the same floor InventoryLayout and SettingsButton use.
local MIN_TOPBAR_HEIGHT = 36

--[[
	The HUD's size on a touch screen: the height it is drawn full size at, and
	the smallest it may go. 0.62 keeps the 16-pixel body text at 10 on the
	smallest phone, the least that still reads at arm's length.
]]
local TOUCH_DESIGN_HEIGHT = 520
local TOUCH_DESIGN_WIDTH = 900
local MIN_TOUCH_SCALE = 0.62

local player = Players.LocalPlayer

local changed = Instance.new("BindableEvent")
Responsive.Changed = changed.Event

-- ---------------------------------------------------------------------------
-- The device
-- ---------------------------------------------------------------------------

local function emulated(name: string)
	return player and player:GetAttribute(name)
end

function Responsive.isTouch(): boolean
	local override = emulated("EmulateTouch")
	if type(override) == "boolean" then
		return override
	end

	-- PreferredInput follows a tablet with a keyboard plugged in; older
	-- clients without it fall back to "has touch and no keyboard".
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if ok and typeof(preferred) == "EnumItem" then
		return preferred == Enum.PreferredInput.Touch
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Responsive.viewport(): Vector2
	local override = emulated("EmulateViewport")
	if typeof(override) == "Vector2" then
		return override
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

function Responsive.isSmall(): boolean
	local size = Responsive.viewport()
	return math.min(size.X, size.Y) <= SMALL_SCREEN
end

-- ---------------------------------------------------------------------------
-- The safe area
-- ---------------------------------------------------------------------------

--[[
	Read off two invisible probes rather than asked for, because Roblox has no
	call that returns it: one ScreenGui keeps out of the notch and corners
	(DeviceSafeInsets), one does not, and the difference between their frames
	is the inset on each side.
]]
local probeSafe: Frame? = nil
local probeFull: Frame? = nil

local function makeProbe(name: string, insets: Enum.ScreenInsets): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ScreenInsets = insets
	gui.Enabled = true

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Active = false
	frame.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
	return frame
end

function Responsive.safe(): { left: number, top: number, right: number, bottom: number }
	local override = emulated("EmulateSafe")
	if typeof(override) == "Rect" then
		return { left = override.Min.X, top = override.Min.Y, right = override.Max.X, bottom = override.Max.Y }
	end
	if not (probeSafe and probeFull) then
		return { left = 0, top = 0, right = 0, bottom = 0 }
	end

	local full0, full1 = probeFull.AbsolutePosition, probeFull.AbsolutePosition + probeFull.AbsoluteSize
	local safe0, safe1 = probeSafe.AbsolutePosition, probeSafe.AbsolutePosition + probeSafe.AbsoluteSize
	return {
		left = math.max(0, safe0.X - full0.X),
		top = math.max(0, safe0.Y - full0.Y),
		right = math.max(0, full1.X - safe1.X),
		bottom = math.max(0, full1.Y - safe1.Y),
	}
end

function Responsive.topbarBottom(): number
	if typeof(emulated("EmulateViewport")) == "Vector2" then
		-- A phone's bar, for the harness: Roblox draws 58 on one.
		local safe = Responsive.safe()
		return safe.top + (if Responsive.isSmall() then 58 else MIN_TOPBAR_HEIGHT + 22)
	end
	local inset = GuiService.TopbarInset
	return inset.Min.Y + math.max(inset.Height, MIN_TOPBAR_HEIGHT)
end

--[[
	The right edge of what is drawn on the top bar's left: Roblox's own
	buttons end at TopbarInset.Min.X, and SettingsButton's gear sits just past
	them. The rest of the bar is empty, and a window may go up into it.
]]
local GEAR_ROOM = 60

function Responsive.topbarLeftUsed(): number
	return GuiService.TopbarInset.Min.X + GEAR_ROOM
end

-- ---------------------------------------------------------------------------
-- Windows
-- ---------------------------------------------------------------------------

--[[
	Fits a window drawn `width` x `height` pixels to a touch screen, where it
	must stay out of the notch, off the top bar's buttons and readable:

		scale, height, centre = Responsive.fitWindow(744, 650, 580, 0.66)

	Below `readable` scale it is drawn at `readable` and made shorter instead,
	down to `minHeight` - for windows whose middle scrolls. It tries two places
	and takes whichever draws it bigger: the full height of the screen beside
	the top bar's buttons, or the width of the screen under the bar. `right`
	is an optional right-hand limit (the tutorial guide). Never above 1.
]]
local WINDOW_MARGIN = 6

function Responsive.fitWindow(width: number, height: number, minHeight: number, readable: number, right: number?)
	local size = Responsive.viewport()
	local safe = Responsive.safe()
	local rightEdge = math.min(right or size.X, size.X - safe.right) - WINDOW_MARGIN
	local bottom = size.Y - safe.bottom - WINDOW_MARGIN

	local function attempt(top: number, left: number)
		local roomX, roomY = rightEdge - left, bottom - top
		local wide = roomX / width
		local fits = math.min(roomY / height, wide, 1)
		local h = height
		if fits < readable then
			h = math.clamp(roomY / math.min(readable, wide), minHeight, height)
			fits = math.min(roomY / h, wide, 1)
		end
		return fits, h, Vector2.new((left + rightEdge) / 2, (top + bottom) / 2)
	end

	local besideScale, besideHeight, besideCentre = attempt(
		safe.top + WINDOW_MARGIN,
		math.max(safe.left, Responsive.topbarLeftUsed()) + WINDOW_MARGIN
	)
	local underScale, underHeight, underCentre = attempt(
		Responsive.topbarBottom() + WINDOW_MARGIN,
		safe.left + WINDOW_MARGIN
	)
	if besideScale >= underScale then
		return besideScale, besideHeight, besideCentre
	end
	return underScale, underHeight, underCentre
end

-- ---------------------------------------------------------------------------
-- Scale
-- ---------------------------------------------------------------------------

function Responsive.hudScale(): number
	if not Responsive.isTouch() then
		return 1
	end
	local size = Responsive.viewport()
	return math.clamp(
		math.min(size.Y / TOUCH_DESIGN_HEIGHT, size.X / TOUCH_DESIGN_WIDTH),
		MIN_TOUCH_SCALE,
		1
	)
end

-- ---------------------------------------------------------------------------
-- Roblox's touch controls
-- ---------------------------------------------------------------------------

--[[
	Roblox's own jump button, when it is on screen. Its layout depends on
	which of Roblox's touch UIs the client has switched on, so the real one is
	measured whenever it exists, and the arithmetic below is only for before
	it is drawn (and for the test harness, which has none).
]]
local function realJumpButton(): GuiObject?
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local button = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if button and button:IsA("GuiObject") and button.AbsoluteSize.X > 0 then
		return button
	end
	return nil
end

--[[
	The jump button's centre and radius. Measured off the real button when
	there is one; otherwise as the PlayerModule's TouchJump places it by
	default: 70 across on a phone, 120 on a tablet, off the bottom-right corner
	of the safe area.
]]
function Responsive.jump(): (Vector2, number)
	local real = typeof(emulated("EmulateViewport")) ~= "Vector2" and realJumpButton()
	if real and probeFull then
		local origin = probeFull.AbsolutePosition
		local size = real.AbsoluteSize
		return real.AbsolutePosition - origin + size / 2, math.min(size.X, size.Y) / 2
	end

	local size = Responsive.viewport()
	local safe = Responsive.safe()
	local right = size.X - safe.right
	local bottom = size.Y - safe.bottom

	local diameter = if Responsive.isSmall() then 70 else 120
	local left = right - (diameter * 1.5 - 10)
	local top = if Responsive.isSmall() then bottom - diameter - 20 else bottom - diameter * 1.75
	return Vector2.new(left + diameter / 2, top + diameter / 2), diameter / 2
end

function Responsive.isPortrait(): boolean
	local size = Responsive.viewport()
	return size.Y > size.X
end

--[[
	The DynamicThumbstick takes touches in the left 40% of the screen, over its
	bottom two thirds - or, held upright, across the whole bottom 40%. Nothing
	that needs a tap belongs in there.
]]
function Responsive.stickRight(): number
	local size = Responsive.viewport()
	return if Responsive.isPortrait() then size.X else size.X * 0.4
end

function Responsive.stickTop(): number
	local size = Responsive.viewport()
	return if Responsive.isPortrait() then size.Y * 0.6 else size.Y / 3
end

-- ---------------------------------------------------------------------------
-- The hotbar
-- ---------------------------------------------------------------------------

local function hotbar(): GuiObject?
	local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("InventoryUI")
	local bag = gui and gui:FindFirstChild("Bag", true)
	local row = bag and bag:FindFirstChild("Row1")
	return if row and row:IsA("GuiObject") then row else nil
end

--[[
	Where the hotbar's bottom edge and right edge are, in this module's space.
	AbsolutePosition starts under the top bar even in a ScreenGui that ignores
	it, so the gui's own AbsolutePosition is taken off (see InventoryClient's
	pointerOf for the same trap).
]]
function Responsive.hotbarRect(): Rect?
	local row = hotbar()
	if not row then
		return nil
	end
	local gui = row:FindFirstAncestorOfClass("ScreenGui")
	local origin = if gui then gui.AbsolutePosition else Vector2.zero
	local min = row.AbsolutePosition - origin
	return Rect.new(min, min + row.AbsoluteSize)
end

function Responsive.hotbarBottom(): number
	local rect = Responsive.hotbarRect()
	return if rect then rect.Max.Y else Responsive.topbarBottom() + 48
end

-- ---------------------------------------------------------------------------
-- The health and mana column
-- ---------------------------------------------------------------------------

--[[
	Where HealthClient and ManaClient put their bars, in canvas pixels, so the
	two always agree:

		x, yScale, yOffset = Responsive.hudColumn(width)
		bar.Position = UDim2.new(0, x, yScale, yOffset - bottom)

	`bottom` is each bar's own height off the column's baseline (40 for
	health, 85 for mana), exactly as it is on a computer, where the baseline
	is the bottom of the screen and x is 16.

	On a touch screen the bottom left is the thumbstick's, so the column goes
	bottom centre, in the gap between the thumbstick's area and the buttons
	round the jump button, and above the home bar. Where that gap is too narrow
	(a phone held upright) it goes top left, under the hotbar.

	COLUMN_HEIGHT is the column from its baseline to the top of the mana bar.
]]
local DESKTOP_PAD = 16
local COLUMN_HEIGHT = 120
local COLUMN_GAP = 8
--[[
	How far TouchControls' buttons reach from the jump button's centre at phone
	size: left to the ATTACK button's edge (all that is level with the health
	column), left to the RUN button's edge (the cluster as a whole), and up to
	the top ability button's.
]]
local ACTIONS_REACH = 131
local CLUSTER_REACH_LEFT = 189
local ACTIONS_REACH_UP = 160
local MAX_CLUSTER_GROWTH = 1.4

--[[
	How big TouchControls draws the buttons round the jump button: they grow
	with it on a tablet, and shrink a little where the screen is too short for
	them all above it under the top bar - the newer jump button sits higher.
]]
function Responsive.clusterScale(): number
	local jump, radius = Responsive.jump()
	local grow = math.clamp(radius / 35, 1, MAX_CLUSTER_GROWTH)
	local room = jump.Y - Responsive.topbarBottom() - COLUMN_GAP
	return math.min(grow, room / ACTIONS_REACH_UP)
end

function Responsive.actionsLeft(): number
	local jump = Responsive.jump()
	return jump.X - ACTIONS_REACH * Responsive.clusterScale()
end

-- The box round every button of the cluster, for anything up top that has
-- to keep out of its way.
function Responsive.clusterRect(): Rect
	local jump, radius = Responsive.jump()
	local k = Responsive.clusterScale()
	return Rect.new(
		jump.X - CLUSTER_REACH_LEFT * k,
		jump.Y - ACTIONS_REACH_UP * k,
		jump.X + radius,
		jump.Y + radius
	)
end

--[[
	TouchControls' Bag, Craft and Menu row sits right of the hotbar where it
	fits, and under it where it does not (a phone held upright).
]]
Responsive.MenuRow = Vector2.new(3 * 60 + 2 * 6, 44)
local MENU_ROW_MARGIN = 10

function Responsive.menuRowBelow(): boolean
	local rect = Responsive.hotbarRect()
	if not rect then
		return false
	end
	local right = Responsive.viewport().X - Responsive.safe().right - MENU_ROW_MARGIN
	return rect.Max.X + MENU_ROW_MARGIN + Responsive.MenuRow.X > right
end

--[[
	The top of the free space under the hotbar: under the held item's name,
	which InventoryLayout hangs there on a touch screen, and under the menu
	row if that went there too.
]]
function Responsive.labelBottom(): number
	local bottom = Responsive.hotbarBottom()
	local row = hotbar()
	local label = row and row.Parent and row.Parent:FindFirstChild("ItemLabel")
	if Responsive.isTouch() and label and label:IsA("GuiObject") then
		local origin = label:FindFirstAncestorOfClass("ScreenGui").AbsolutePosition
		bottom = math.max(bottom, label.AbsolutePosition.Y - origin.Y + label.AbsoluteSize.Y)
	end
	return bottom
end

function Responsive.underHotbar(): number
	local bottom = Responsive.labelBottom()
	if Responsive.isTouch() and Responsive.menuRowBelow() then
		-- TouchControls hangs the row under the item's name.
		bottom += MENU_ROW_MARGIN + Responsive.MenuRow.Y
	end
	return bottom + COLUMN_GAP
end

local COLUMN_WIDTH = 260

-- Whether the health column had to go top left rather than bottom centre.
function Responsive.columnAtTop(): boolean
	if not Responsive.isTouch() then
		return false
	end
	local room = Responsive.actionsLeft() - Responsive.stickRight() - COLUMN_GAP * 2
	return room < COLUMN_WIDTH * Responsive.hudScale()
end

-- The bottom of everything stacked down the top left on a touch screen: the
-- boss bar goes under this.
function Responsive.topStackBottom(): number
	local bottom = Responsive.underHotbar()
	if Responsive.columnAtTop() then
		bottom += COLUMN_HEIGHT * Responsive.hudScale() + COLUMN_GAP
	end
	return bottom
end

function Responsive.hudColumn(width: number): (number, number, number)
	local safe = Responsive.safe()
	if not Responsive.isTouch() then
		return DESKTOP_PAD + safe.left, 1, -safe.bottom
	end

	local s = Responsive.hudScale()
	if not Responsive.columnAtTop() then
		local centre = (Responsive.stickRight() + Responsive.actionsLeft()) / 2
		return centre / s - width / 2, 1, -safe.bottom / s
	end

	return DESKTOP_PAD + safe.left / s, 0, Responsive.underHotbar() / s + COLUMN_HEIGHT
end

-- ---------------------------------------------------------------------------
-- Change
-- ---------------------------------------------------------------------------

local pending = false
local function fire()
	if pending then
		return
	end
	pending = true
	task.defer(function()
		pending = false
		changed:Fire()
	end)
end

function Responsive.bind(callback: () -> ()): RBXScriptConnection
	callback()
	return Responsive.Changed:Connect(callback)
end

--[[
	A full-screen frame in HUD pixels; see THE CANVAS above. One per ScreenGui,
	made on first ask.
]]
function Responsive.canvas(gui: ScreenGui): Frame
	local existing = gui:FindFirstChild("Canvas")
	if existing then
		return existing
	end

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Active = false

	local scale = Instance.new("UIScale")
	scale.Parent = canvas

	Responsive.bind(function()
		local s = Responsive.hudScale()
		scale.Scale = s
		canvas.Size = UDim2.fromScale(1 / s, 1 / s)
	end)

	canvas.Parent = gui
	return canvas
end

-- ---------------------------------------------------------------------------
-- Watching
-- ---------------------------------------------------------------------------

if player then
	probeSafe = makeProbe("SafeAreaProbe", Enum.ScreenInsets.DeviceSafeInsets)
	probeFull = makeProbe("FullScreenProbe", Enum.ScreenInsets.None)
	probeSafe:GetPropertyChangedSignal("AbsoluteSize"):Connect(fire)
	probeSafe:GetPropertyChangedSignal("AbsolutePosition"):Connect(fire)

	local function watchCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(fire)
		end
		fire()
	end
	watchCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fire)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(fire)
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(fire)
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(fire)
	end)

	for _, name in ipairs({ "EmulateTouch", "EmulateViewport", "EmulateSafe" }) do
		player:GetAttributeChangedSignal(name):Connect(fire)
	end

	-- Roblox's jump button: drawn once touch controls start, and redrawn
	-- when the screen turns.
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local function watchTouchGui(touchGui: Instance)
			if touchGui.Name ~= "TouchGui" then
				return
			end
			touchGui.DescendantAdded:Connect(function(descendant)
				if descendant.Name == "JumpButton" and descendant:IsA("GuiObject") then
					descendant:GetPropertyChangedSignal("AbsolutePosition"):Connect(fire)
					descendant:GetPropertyChangedSignal("AbsoluteSize"):Connect(fire)
					fire()
				end
			end)
			local existing = touchGui:FindFirstChild("JumpButton", true)
			if existing and existing:IsA("GuiObject") then
				existing:GetPropertyChangedSignal("AbsolutePosition"):Connect(fire)
				existing:GetPropertyChangedSignal("AbsoluteSize"):Connect(fire)
				fire()
			end
		end
		playerGui.ChildAdded:Connect(watchTouchGui)
		for _, child in ipairs(playerGui:GetChildren()) do
			watchTouchGui(child)
		end
	end)

	-- The hotbar is built after this module loads and moves when it rescales.
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local inventory = playerGui:WaitForChild("InventoryUI", 60)
		local bag = inventory and inventory:WaitForChild("Bag", 10)
		if bag then
			bag:GetPropertyChangedSignal("AbsoluteSize"):Connect(fire)
			bag:GetPropertyChangedSignal("AbsolutePosition"):Connect(fire)
			fire()
		end
	end)
end

return Responsive
