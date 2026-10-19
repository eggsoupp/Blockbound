--[[
	ChestClient

	The window a chest opens: what is in the chest above, your bag below, and
	moving things between them. ServerScriptService.ChestServer decides
	everything; this draws what it is told and asks.

	  CLICK a stack     sends it all to the other side, merging into what is
	                    already there first - the quick way to empty a chest
	                    or put a load away
	  DRAG a stack      puts it in exactly that slot: onto an empty slot or
	                    the same item it moves, onto something else it swaps

	It opens when the server says the chest is open (its prompt, server side)
	and shuts when the server says so - walked off, chest picked up - or on
	Escape, E or the close button.

	THE BAG HERE IS THE BAG. Its slots are drawn from InventoryMirror, the same
	copy of the inventory the hotbar draws from, and they are the inventory's
	own slot numbers: the hotbar along the bottom, the three bag rows above
	it. Gear and the bin are not here; nothing can be put straight into them
	from a chest.

	It is a modal menu (MenuState), so the ordinary inventory closes while it
	is up and movement is held. Prompts are switched off on this client while
	it is open: the E that closes it would otherwise open it again.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local GuiService = game:GetService("GuiService")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local InventoryConstants = require(ReplicatedStorage:WaitForChild("InventoryConstants"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local PixelUI = require(Shared.UI:WaitForChild("PixelUI"))
local SlotArt = require(Shared.UI:WaitForChild("SlotArt"))
local MenuState = require(Shared.UI:WaitForChild("MenuState"))
local ItemPreview = require(Shared.UI:WaitForChild("ItemPreview"))
local ItemThumbnails = require(Shared.UI:WaitForChild("ItemThumbnails"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local InventoryMirror = require(Shared:WaitForChild("Inventory"):WaitForChild("InventoryMirror"))

local ChestState = Remotes.wait("ChestState")
local ChestRequest = Remotes.wait("ChestRequest")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local P = Theme.PixelColor
local MENU_NAME = "Chest"

-- ---------------------------------------------------------------------------
-- Layout, in pixels on a 1080p screen; a UIScale fits it to the real one
-- ---------------------------------------------------------------------------

local COLUMNS = InventoryConstants.HotbarSlots
local SLOT = Theme.SlotSize
local PITCH = Theme.SlotPitch
local ICON = math.round(SLOT * 0.75)
local ICON_INSET = (SLOT - ICON) / 2

local GRID_WIDTH = COLUMNS * PITCH - (PITCH - SLOT)
local PAD = (PixelUI.border("frame_parchment")) + 14
local TITLE_HEIGHT = 26
local SECTION_GAP = 10
local HOTBAR_GAP = 8

-- The bag's three rows and the hotbar under them: inventory slots 10..36,
-- then 1..9.
local BAG_FIRST = COLUMNS + 1
local BAG_ROWS = 3
local BAG_LAST = BAG_FIRST + BAG_ROWS * COLUMNS - 1

-- Pixels the pointer has to travel with the button down before a press is a
-- drag rather than a click.
local DRAG_THRESHOLD = 6

-- After the window shuts on this client, prompts stay off this long, so the
-- key press that closed it cannot trigger the chest's prompt again.
local PROMPT_REST = 0.3

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "ChestUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 10
screen.Enabled = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- Modal dim. Active so a click outside the window is sunk rather than
-- swinging whatever is in hand at the world.
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Theme.Color.Backdrop
backdrop.BackgroundTransparency = 0.55
backdrop.BorderSizePixel = 0
backdrop.Active = true
backdrop.Parent = screen

local window = PixelUI.image(screen, "frame_parchment")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Active = true

local windowScale = Instance.new("UIScale")
windowScale.Parent = window

local banner, titleLabel = PixelUI.header(window, "CHEST")
banner.Position = UDim2.new(0.5, 0, 0, 0)
banner.ZIndex = 5
titleLabel.ZIndex = 6

local function sectionTitle(text: string, top: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(PAD, top)
	label.Size = UDim2.fromOffset(GRID_WIDTH, TITLE_HEIGHT)
	label.FontFace = Theme.Fonts.Heading
	label.TextSize = Theme.TextSize.Subheading
	label.TextColor3 = P.Heading
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = window
	return label
end

-- One square. The chest's are the wooden slot and the bag's the parchment
-- one, so which side a stack is on is never in doubt.
local function newTile(top: number, column: number, variant: string?): ImageButton
	local tile = Instance.new("ImageButton")
	tile.AutoButtonColor = false
	tile.BackgroundTransparency = 1
	tile.BorderSizePixel = 0
	tile.Size = UDim2.fromOffset(SLOT, SLOT)
	tile.Position = UDim2.fromOffset(PAD + (column - 1) * PITCH, top)
	tile.ZIndex = 2
	tile.Parent = window
	SlotArt.apply(tile, variant)

	local icon = Instance.new("ImageLabel")
	icon.Name = "icon"
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.Size = UDim2.fromOffset(ICON, ICON)
	icon.Position = UDim2.fromOffset(ICON_INSET, ICON_INSET)
	icon.ZIndex = 3
	icon.Parent = tile

	-- Drawn only when neither a live view nor a picture could be had, so an
	-- item is never an empty square.
	local fallback = Instance.new("TextLabel")
	fallback.Name = "fallback"
	fallback.BackgroundTransparency = 1
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.FontFace = Theme.Fonts.BodyBold
	fallback.TextSize = Theme.TextSize.Small
	fallback.TextColor3 = P.Ink
	fallback.TextWrapped = true
	fallback.Text = ""
	fallback.Visible = false
	fallback.ZIndex = 4
	fallback.Parent = tile

	local count = Instance.new("TextLabel")
	count.Name = "num"
	count.BackgroundTransparency = 1
	count.Size = UDim2.fromOffset(SLOT - 5, 20)
	count.Position = UDim2.fromOffset(0, SLOT - 23)
	count.FontFace = Theme.Fonts.Number
	count.TextSize = Theme.TextSize.Count
	count.TextColor3 = Color3.new(1, 1, 1)
	count.TextStrokeTransparency = 0.4
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Text = ""
	count.ZIndex = 5
	count.Parent = tile

	return tile
end

-- tiles.chest[slot] and tiles.bag[inventorySlot], each { tile, side, index, shown }.
local tiles = { chest = {}, bag = {} }
local allTiles = {}

local chestTitle = sectionTitle("Chest", PAD + 10)
local chestTop = PAD + 10 + TITLE_HEIGHT
local chestRows = 0
local bagTitle
local bagTop, hotbarTop, windowHeight = 0, 0, 0

local hoverLabel = Instance.new("TextLabel")
hoverLabel.Name = "Hover"
hoverLabel.BackgroundTransparency = 1
hoverLabel.FontFace = Theme.Fonts.BodyBold
hoverLabel.TextSize = Theme.TextSize.Small
hoverLabel.TextColor3 = P.InkSoft
hoverLabel.TextXAlignment = Enum.TextXAlignment.Right
hoverLabel.Size = UDim2.fromOffset(GRID_WIDTH, TITLE_HEIGHT)
hoverLabel.Text = ""
hoverLabel.Parent = window

local closeButton

local function addTile(side: string, index: number, top: number, column: number)
	local tile = newTile(top, column, if side == "chest" then "dark" else nil)
	local record = { tile = tile, side = side, index = index, shown = nil }
	tiles[side][index] = record
	table.insert(allTiles, record)
	return record
end

-- The window's shape depends on how big the chest is; built once per size.
local builtFor = nil

local function build(size: number)
	if builtFor == size then
		return
	end
	builtFor = size

	for _, record in ipairs(allTiles) do
		ItemPreview.releaseSlot(record.tile.icon)
		record.tile:Destroy()
	end
	table.clear(allTiles)
	tiles = { chest = {}, bag = {} }

	chestRows = math.ceil(size / COLUMNS)
	for slot = 1, size do
		local row = (slot - 1) // COLUMNS
		addTile("chest", slot, chestTop + row * PITCH, (slot - 1) % COLUMNS + 1)
	end

	local chestBottom = chestTop + chestRows * PITCH - (PITCH - SLOT)
	if not bagTitle then
		bagTitle = sectionTitle("Bag", 0)
	end
	bagTitle.Position = UDim2.fromOffset(PAD, chestBottom + SECTION_GAP)
	bagTop = chestBottom + SECTION_GAP + TITLE_HEIGHT

	for slot = BAG_FIRST, BAG_LAST do
		local offset = slot - BAG_FIRST
		addTile("bag", slot, bagTop + (offset // COLUMNS) * PITCH, offset % COLUMNS + 1)
	end

	hotbarTop = bagTop + BAG_ROWS * PITCH - (PITCH - SLOT) + HOTBAR_GAP
	for slot = 1, COLUMNS do
		addTile("bag", slot, hotbarTop, slot)
	end

	windowHeight = hotbarTop + SLOT + PAD + 6
	window.Size = UDim2.fromOffset(GRID_WIDTH + PAD * 2, windowHeight)
	hoverLabel.Position = UDim2.fromOffset(PAD, chestTop - TITLE_HEIGHT)

	if not closeButton then
		closeButton = PixelUI.closeButton(window, function()
			ChestRequest:FireServer("close")
			-- Shut at once; the server's answer would only say the same.
			task.defer(function()
				if screen.Enabled then
					MenuState.setOpen(MENU_NAME, false)
				end
			end)
		end)
		closeButton.Position = UDim2.new(1, -10, 0, 10)
		closeButton.ZIndex = 6
	end
end

-- Fits the window inside the screen, never above its 1080p size.
local function fit()
	local size = screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 or windowHeight <= 0 then
		return
	end
	local wide = (GRID_WIDTH + PAD * 2) / (size.X * 0.92)
	local tall = windowHeight / (size.Y * 0.9)
	windowScale.Scale = math.min(1, 1 / math.max(wide, tall))
end
screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

-- ---------------------------------------------------------------------------
-- Drawing stacks
-- ---------------------------------------------------------------------------

local chestSlots: { [number]: { name: string, count: number } } = {}
local isOpen = false

local function stackFor(record)
	if record.side == "chest" then
		local stack = chestSlots[record.index]
		return stack and stack.name, stack and stack.count or 0
	end
	local slot = InventoryMirror.get()[record.index]
	return slot and slot.name, slot and slot.count or 0
end

local function shortName(name: string): string
	local def = ItemDefinitions[name]
	local text = (def and def.displayName) or name
	-- "IronIngot" -> "Iron Ingot", so the stand-in label can wrap.
	return (string.gsub(text, "(%l)(%u)", "%1 %2"))
end

local function release(record)
	local tile = record.tile
	ItemPreview.releaseSlot(tile.icon)
	ItemThumbnails.bind(tile.icon, nil)
	tile.icon.Image = ""
	tile.fallback.Visible = false
	tile.num.Text = ""
	record.shown = nil
end

-- A live view first, then a picture, then the item's name - the same order
-- the inventory tries, so a stack looks the same in both.
local function draw(record)
	local name, count = stackFor(record)
	local tile = record.tile
	local key = if name then name .. "#" .. count else nil
	if key == record.shown then
		return
	end

	if not name then
		release(record)
		return
	end

	local sameItem = record.shown ~= nil and string.match(record.shown, "^(.-)#") == name
	tile.num.Text = if count > 1 then tostring(count) else ""

	if sameItem then
		record.shown = key
		return
	end

	release(record)
	-- Recorded before binding: a picture already known to be missing is
	-- answered straight away, inside bind, and the answer checks this.
	record.shown = key
	tile.num.Text = if count > 1 then tostring(count) else ""

	local def = ItemDefinitions[name]
	local wantsImage = def and type(def.thumbnail) == "string" and def.thumbnail ~= ""
	if not wantsImage and ItemPreview.fillSlot(tile.icon, name) then
		ItemThumbnails.bind(tile.icon, nil)
		return
	end

	ItemThumbnails.bind(tile.icon, name, function(image)
		local still = record.shown ~= nil and string.match(record.shown, "^(.-)#") == name
		if image == "" and isOpen and still and not ItemPreview.fillSlot(tile.icon, name) then
			tile.fallback.Text = shortName(name)
			tile.fallback.Visible = true
		end
	end)
end

local function drawAll()
	for _, record in ipairs(allTiles) do
		draw(record)
	end
end

local function releaseAll()
	for _, record in ipairs(allTiles) do
		release(record)
	end
end

-- ---------------------------------------------------------------------------
-- Pointer: hover, click and drag
-- ---------------------------------------------------------------------------

local pressed = nil -- the record the button went down on
local pressAt = nil
local dragging = false
local ghost: ImageLabel? = nil
local hovered = nil

local function recordAt(x: number, y: number)
	for _, record in ipairs(allTiles) do
		local position, size = record.tile.AbsolutePosition, record.tile.AbsoluteSize
		if x >= position.X and x <= position.X + size.X and y >= position.Y and y <= position.Y + size.Y then
			return record
		end
	end
	return nil
end

--[[
	Where the pointer is, in this screen's pixels. The screen ignores the top
	bar inset, so it measures from the very top of the window: the mouse's
	GetMouseLocation already does, and a touch's Position has the inset added.
]]
local function pointer(input: InputObject?): (number, number)
	if input and input.UserInputType == Enum.UserInputType.Touch then
		local inset = GuiService:GetGuiInset()
		return input.Position.X + inset.X, input.Position.Y + inset.Y
	end
	local location = UserInputService:GetMouseLocation()
	return location.X, location.Y
end

local function setHover(record)
	if hovered == record then
		return
	end
	if hovered and hovered.tile.Parent then
		hovered.tile.ImageColor3 = Color3.new(1, 1, 1)
	end
	hovered = record
	if record then
		record.tile.ImageColor3 = Color3.fromRGB(255, 244, 214)
		local name, count = stackFor(record)
		hoverLabel.Text = if name then string.format("%s%s", shortName(name), if count > 1 then "  x" .. count else "") else ""
	else
		hoverLabel.Text = ""
	end
end

local function endDrag()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if pressed and pressed.tile.Parent then
		pressed.tile.icon.ImageTransparency = 0
	end
	pressed, pressAt, dragging = nil, nil, false
end

local function beginDrag(record)
	dragging = true
	local tile = record.tile
	local copy = Instance.new("ImageLabel")
	copy.Name = "Dragging"
	copy.BackgroundTransparency = 1
	copy.AnchorPoint = Vector2.new(0.5, 0.5)
	copy.Size = UDim2.fromOffset(tile.icon.AbsoluteSize.X, tile.icon.AbsoluteSize.Y)
	copy.Image = tile.icon.Image
	copy.ZIndex = 20
	copy.Parent = screen

	-- A live view cannot be cloned into an image, so the drag carries a copy
	-- of the view itself.
	local view = tile.icon:FindFirstChildWhichIsA("ViewportFrame")
	if view then
		local viewCopy = view:Clone()
		viewCopy.ZIndex = 21
		viewCopy.Parent = copy
	end
	local name = stackFor(record)
	if copy.Image == "" and not view and name then
		local label = tile.fallback:Clone()
		label.Visible = true
		label.ZIndex = 21
		label.Parent = copy
	end
	ghost = copy
end

UserInputService.InputBegan:Connect(function(input)
	if not isOpen then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local x, y = pointer(input)
		local record = recordAt(x, y)
		if record and stackFor(record) then
			pressed, pressAt, dragging = record, Vector2.new(x, y), false
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not isOpen then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local x, y = pointer(input)
	setHover(recordAt(x, y))

	if pressed and not dragging and pressAt and (Vector2.new(x, y) - pressAt).Magnitude >= DRAG_THRESHOLD then
		beginDrag(pressed)
	end
	if ghost then
		ghost.Position = UDim2.fromOffset(x, y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not isOpen or not pressed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local source = pressed
	local wasDrag = dragging
	local x, y = pointer(input)
	local target = recordAt(x, y)
	endDrag()

	if wasDrag then
		if target and target ~= source then
			Sounds.play("ui.click")
			ChestRequest:FireServer("move", source.side, source.index, target.side, target.index)
		end
	elseif target == source then
		Sounds.play("ui.click")
		ChestRequest:FireServer("quick", source.side, source.index)
	end
end)

-- ---------------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------------

local promptsResting = false

local function restPrompts()
	ProximityPromptService.Enabled = false
	promptsResting = true
end

local function wakePrompts()
	task.delay(PROMPT_REST, function()
		if not isOpen and promptsResting then
			promptsResting = false
			ProximityPromptService.Enabled = true
		end
	end)
end

local function showWindow(state)
	build(state.size)
	titleLabel.Text = string.upper(tostring(state.title or "Chest"))
	chestTitle.Text = tostring(state.title or "Chest")

	if not isOpen then
		isOpen = true
		screen.Enabled = true
		fit()
		restPrompts()
		Sounds.play("ui.open")
		MenuState.setOpen(MENU_NAME, true)
	end
	drawAll()
end

local function hideWindow()
	if not isOpen then
		return
	end
	isOpen = false
	endDrag()
	setHover(nil)
	releaseAll()
	screen.Enabled = false
	Sounds.play("ui.close")
	MenuState.setOpen(MENU_NAME, false)
	wakePrompts()
end

ChestState.OnClientEvent:Connect(function(state)
	if type(state) ~= "table" or type(state.size) ~= "number" then
		hideWindow()
		return
	end

	table.clear(chestSlots)
	if type(state.slots) == "table" then
		for _, entry in ipairs(state.slots) do
			if type(entry) == "table" and type(entry.s) == "number" and type(entry.n) == "string" then
				chestSlots[entry.s] = { name = entry.n, count = tonumber(entry.c) or 1 }
			end
		end
	end

	showWindow(state)
end)

-- The bag half redraws whenever the bag changes, whatever changed it.
InventoryMirror.onChanged(function()
	if isOpen then
		for _, record in ipairs(allTiles) do
			if record.side == "bag" then
				draw(record)
			end
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not isOpen or processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.E then
		ChestRequest:FireServer("close")
		-- A moment later, so the inventory's own E handler - which runs for
		-- this same press, in no fixed order - still sees a menu open and
		-- does not spring the bag open as the chest shuts.
		task.defer(hideWindow)
	end
end)

-- The window above this one wins: the pause menu closes the chest.
MenuState.Changed:Connect(function(name, opened)
	if isOpen and opened and name ~= MENU_NAME then
		ChestRequest:FireServer("close")
		hideWindow()
	end
end)

-- The close button's path: MenuState says it shut, so the window follows.
MenuState.Changed:Connect(function(name, opened)
	if name == MENU_NAME and not opened and isOpen then
		hideWindow()
	end
end)

player.CharacterAdded:Connect(function()
	if isOpen then
		hideWindow()
	end
end)
