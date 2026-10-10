--[[
	InventoryClient

	Draws the inventory, handles drag-and-drop between slots, and asks the server
	to equip hotbar items. The server owns the actual inventory; everything here
	is presentation and requests.

	A slot draws a live render of the item's model where there is one (see
	Shared.UI.ItemPreview) and a checked flat image otherwise (ItemThumbnails).
	The check matters: most of this project's `icon` ids point at assets that do
	not exist, and an ImageLabel pointed at one draws nothing, silently.

	Hovering a filled slot swells the TILE - not the icon, which the drag system
	owns - and opens a tooltip under it.

	Set DEBUG to true to trace the equip flow.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local TweenService      = game:GetService("TweenService")

local DEBUG = false
local function log(...)
	if DEBUG then
		print("[InventoryClient]", ...)
	end
end

local ItemDefinitions   = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local InventoryConstants = require(ReplicatedStorage:WaitForChild("InventoryConstants"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme     = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local MenuState = require(Shared.UI:WaitForChild("MenuState"))
local ItemThumbnails = require(Shared.UI:WaitForChild("ItemThumbnails"))
local ItemPreview = require(Shared.UI:WaitForChild("ItemPreview"))
local Motion = require(Shared.UI:WaitForChild("Motion"))
local Sounds    = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local ToolConfig = require(Shared:WaitForChild("Tools"):WaitForChild("ToolConfig"))
local InventoryMirror =
	require(Shared:WaitForChild("Inventory"):WaitForChild("InventoryMirror"))

-- All remotes live in ReplicatedStorage.Remotes.
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestFullInv       = remotes:WaitForChild("RequestFullInventory")
local RequestSwapSlots     = remotes:WaitForChild("RequestSwapSlots")
local RequestTransferStack = remotes:WaitForChild("RequestTransferStack")
local RequestEquipTool     = remotes:WaitForChild("RequestEquipTool")

local player = Players.LocalPlayer
local gui    = player:WaitForChild("PlayerGui")
local invUI  = gui:WaitForChild("InventoryUI")

-- Shows the equipped hotbar item.
local itemLabel = invUI:WaitForChild("ItemLabel")

local function playClick()
	Sounds.play("ui.click")
end

-- Slot tile tints. The tile art is a light frame, so "idle" is slightly dimmed
-- and hovering brings it back to full brightness.
local SLOT_IDLE  = Color3.fromRGB(206, 206, 206)
local SLOT_HOVER = Color3.fromRGB(255, 255, 255)

--[[
	Which hotbar slot is selected, published on the LocalPlayer.

	Set on the client, so it stays on this client. PlacementClient reads it to
	know what the build preview should be showing. It replaces a pair of
	functions this script used to reach for through _G - which only worked if
	PlacementClient happened to have run first, and which no third reader could
	discover without being told the magic name.
]]
local EQUIPPED_SLOT_ATTRIBUTE = "EquippedSlot"

local slots            = {}
local slotItemNames    = {}
-- What each slot held last redraw, so a stack that GREW can be told apart from
-- one that merely changed. A pickup should be visible without the player
-- watching the number.
local slotCounts       = {}
local slotOrigSizes    = {}
local coordinateRanges = {}
local lastHoverSlot    = nil
local inventoryVisible = false
local inventory        = {}
local equippedSlot     = nil -- index 1..9 for hotbar; nil means nothing equipped
local lastToggleTime = 0
local lastDisplayedName = nil

-- Forward declaration: toggleInventory and the drag handler both need to put a
-- hovered tile back, and both are written above the hover code that defines it.
local clearHover

local keyToSlot = {
	[Enum.KeyCode.One]   = 1, [Enum.KeyCode.Two]   = 2,
	[Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four]  = 4,
	[Enum.KeyCode.Five]  = 5, [Enum.KeyCode.Six]   = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine]  = 9,
}

local function getSlotElements(slot)
	return slot:FindFirstChild("icon"), slot:FindFirstChild("num")
end

local function getMouseXY()
	local raw = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	return raw.X, raw.Y - inset.Y
end

-- nil for an item with no stack size, which is what marks it unstackable in
-- the count label below.
local function getMaxStack(def)
	return def and tonumber(def.maxStack)
end

local function clearSlot(i)
	slotItemNames[i] = nil
	slotCounts[i] = nil
	local slot = slots[i]
	if slot then
		local icon, num = getSlotElements(slot)
		if icon then
			icon.Visible = false
			-- Unbinds as well as clears; a slot that is emptied should stop
			-- being updated by whatever it used to hold, and give back its live
			-- view if it had one.
			ItemThumbnails.bind(icon, nil)
			ItemPreview.releaseSlot(icon)
		end
		if num then
			num.Text     = ""
		end
		slot.ImageColor3 = SLOT_IDLE
	end
end

local function clearSlots()
	for i = 1, #slots do
		clearSlot(i)
	end
	if itemLabel then
		itemLabel.Text = ""
		lastDisplayedName = nil
	end
end

local function updateItemLabelFromEquipped()
	local name = nil
	if equippedSlot and slotItemNames[equippedSlot] then
		name = slotItemNames[equippedSlot]
	end
	if name == lastDisplayedName then return end
	lastDisplayedName = name
	if name then
		itemLabel.Text = name
		local def = ItemDefinitions[name]
		local rarity = (def and def.rarity) or "Common"
		itemLabel.TextColor3 = Theme.rarityColor(rarity)
	else
		itemLabel.Text = ""
	end
end

-- The hotbar is always up; rows 2-6 are hidden until the inventory opens. This
-- is what keeps live slot views affordable - a closed inventory renders the
-- hotbar and nothing else.
local HOTBAR_SLOTS = InventoryConstants.HotbarSlots

local ACCESSORY_FIRST = InventoryConstants.AccessoryRange.first
local ACCESSORY_LAST = InventoryConstants.AccessoryRange.last

-- The row the accessory tiles were authored in. Emptied when they move to the
-- accessory column, and kept hidden after that; see THE ACCESSORY COLUMN.
local accessoryRowFrame: GuiObject? = nil

-- The column itself, shown and hidden with the rest of the inventory.
local accessoryColumn: GuiObject? = nil

local function slotIsVisible(index: number): boolean
	return index <= HOTBAR_SLOTS or inventoryVisible
end

-- Split out of updateSlots so a one-slot change costs one slot of work: mining
-- a block used to clear and redraw all forty-two.
local function renderSlot(i)
	local slotData = inventory[i]

	if not (slotData and slotData.name) then
		clearSlot(i)
		return
	end

	local itemName = slotData.name
	local count = slotData.count

	-- Grew, rather than simply changed: a stack that shrank, or an item that
	-- was dragged in from elsewhere, is not something to celebrate.
	local grew = slotItemNames[i] == itemName
		and type(count) == "number"
		and count > (slotCounts[i] or 0)

	slotItemNames[i] = itemName
	slotCounts[i] = count

	local slotUI = slots[i]
	if not slotUI then
		return
	end

	if grew and slotIsVisible(i) then
		Motion.pulse(slotUI, 1.12)
	end

	local icon, num = getSlotElements(slotUI)
	local def = ItemDefinitions[itemName]

	if icon then
		-- A live render first, because its camera is the only one this project
		-- controls - Roblox's own thumbnail angle cannot be edited and leaves
		-- these tools unidentifiable. A flat image covers items with no model,
		-- and `thumbnail` in ItemDefinitions overrides both.
		icon.Visible = (def ~= nil)

		local override = def and def.thumbnail
		local wantsImage = type(override) == "string" and override ~= ""

		local live = def ~= nil
			and not wantsImage
			and slotIsVisible(i)
			and ItemPreview.fillSlot(icon, itemName)

		if live then
			-- Clears the image and stops a pending check from putting one back
			-- underneath the view, where it would show around the model.
			ItemThumbnails.bind(icon, nil)
		else
			ItemPreview.releaseSlot(icon)

			ItemThumbnails.bind(icon, if def then itemName else nil, function(image)
				-- Nothing loaded either. Worth one more try at a live view: the
				-- cap may have freed up, or the model may have replicated since.
				if image == "" and not wantsImage and slotIsVisible(i) then
					ItemPreview.fillSlot(icon, itemName)
				end
			end)
		end
	end

	local maxStack = getMaxStack(def)
	if def and maxStack and maxStack > 1 and type(count) == "number" and count > 0 then
		if num then num.Text = tostring(count) end
	else
		if num then num.Text = "" end
	end

	slotUI.ImageColor3 = SLOT_IDLE
end

--[[
	Applies an inventory update.

	`changedIndices` is the list of slots the server said moved; when it is nil
	the whole bag is redrawn, which is what a full sync means.
]]
local function updateSlots(newInventory, changedIndices)
	inventory = newInventory or {}

	if changedIndices then
		for _, i in ipairs(changedIndices) do
			if i >= 1 and i <= #slots then
				renderSlot(i)
			end
		end
	else
		for i = 1, #slots do
			renderSlot(i)
		end
	end

	updateItemLabelFromEquipped()
end

local function updateCoordinateRanges()
	for i = 1, #slots do
		local slot = slots[i]
		-- A slot that is not on screen is not somewhere to drop things. Hidden
		-- rows still report where they would be, so without this a drag on the
		-- hotbar could land in an invisible inventory slot.
		if slot and slotIsVisible(i) then
			local absPos = slot.AbsolutePosition
			local absSize = slot.AbsoluteSize
			coordinateRanges[i] = {
				x1 = absPos.X,
				y1 = absPos.Y,
				x2 = absPos.X + absSize.X,
				y2 = absPos.Y + absSize.Y,
				index = i
			}
		else
			coordinateRanges[i] = nil
		end
	end
end

local function toggleInventory()
	inventoryVisible = not inventoryVisible

	-- Rows closing under the cursor never fire MouseLeave, so the swollen tile
	-- and its tooltip have to be told directly or they would be left behind on a
	-- closed inventory.
	clearHover()
	for row = 2, 7 do
		local rowFrame = invUI:FindFirstChild("Row"..row)
		if rowFrame and rowFrame ~= accessoryRowFrame then
			rowFrame.Visible = inventoryVisible
		end
	end
	if accessoryColumn then
		accessoryColumn.Visible = inventoryVisible
	end

	-- Rows appearing moves nothing that was already on screen, but the hit boxes
	-- for the rows that just became visible have to be measured now.
	task.defer(updateCoordinateRanges)

	-- The slots below the hotbar are redrawn either way: opening gives them
	-- their live views, closing takes those views back rather than leaving
	-- thirty-odd viewports rendering behind a hidden frame.
	for i = HOTBAR_SLOTS + 1, #slots do
		renderSlot(i)
	end
end

-- build slots
local slotsPerRow = {9, 9, 9, 9, 5, 1}
local index = 1
for row = 1, 6 do
	local rowFrame = invUI:WaitForChild("Row"..row)
	if row > 1 then
		rowFrame.Visible = false
	end
	local numSlots = slotsPerRow[row]
	for slot = 1, numSlots do
		local slotUI = rowFrame:WaitForChild("Slot"..slot)
		slots[index] = slotUI
		local icon, num = getSlotElements(slotUI)
		slotOrigSizes[index] = {
			iconSize = (icon and icon.Size) or UDim2.new(0,32,0,32),
			iconPos  = (icon and icon.Position) or UDim2.new(0,0,0,0),
			numSize  = (num and num.Size) or UDim2.new(0,16,0,16),
			numPos   = (num and num.Position) or UDim2.new(0,0,0,0),

			-- The tile's own resting geometry, for the hover swell below. Its
			-- ABSOLUTE size is measured later, on the first hover, because at
			-- this point the UI has not been laid out and it would be zero.
			slotSize = slotUI.Size,
			slotPos  = slotUI.Position,
			slotZ    = slotUI.ZIndex,
		}
		slotItemNames[index] = nil
		index = index + 1
	end
end

--[[
	THE ACCESSORY COLUMN.

	The accessory slots are authored as a row of the grid. They are shown
	instead as their own column in the bottom-right corner, so what you are
	wearing reads as a separate thing from what you are carrying. Like the rest
	of the inventory below the hotbar, the column only appears while the
	inventory is open (E).

	The authored TILES are moved, not copied: same instances, same slot
	indices. Dragging, the server's slot rules (only an Accessory fits), the
	tooltip and the save format all work on indices and never notice the move.
	Sized from Theme, which holds the grid's own slot measurements.
]]
do
	local count = ACCESSORY_LAST - ACCESSORY_FIRST + 1
	local titleHeight = Theme.TextSize.Small + 6

	local column = Instance.new("Frame")
	column.Name = "AccessoryColumn"
	column.BackgroundTransparency = 1
	-- Part of the inventory: shown when it opens (E), like every row but the
	-- hotbar.
	column.Visible = false
	accessoryColumn = column
	column.AnchorPoint = Vector2.new(1, 1)
	column.Position = UDim2.new(1, -Theme.Spacing.Edge, 1, -Theme.Spacing.Edge)
	column.Size = UDim2.fromOffset(Theme.SlotSize, titleHeight + (count - 1) * Theme.SlotPitch + Theme.SlotSize)
	column.Parent = invUI

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	-- Wider than the column and centred on it, so the word is never clipped by
	-- a slot-wide box.
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0)
	title.Size = UDim2.fromOffset(Theme.SlotSize * 2, titleHeight)
	title.FontFace = Theme.Fonts.Heading
	title.TextSize = Theme.TextSize.Small
	title.TextColor3 = Theme.Color.Text
	title.TextStrokeTransparency = 0.4
	title.Text = "ACCESSORIES"
	title.Parent = column

	for i = ACCESSORY_FIRST, ACCESSORY_LAST do
		local tile = slots[i]
		if tile then
			accessoryRowFrame = accessoryRowFrame or tile.Parent

			tile.AnchorPoint = Vector2.zero
			tile.Size = UDim2.fromOffset(Theme.SlotSize, Theme.SlotSize)
			tile.Position = UDim2.fromOffset(0, titleHeight + (i - ACCESSORY_FIRST) * Theme.SlotPitch)
			tile.Parent = column

			-- The hover swell restores to these, so they have to describe where
			-- the tile rests now rather than where it was authored.
			local orig = slotOrigSizes[i]
			if orig then
				orig.slotSize = tile.Size
				orig.slotPos = tile.Position
				orig.slotAbs = nil
			end
		end
	end

	-- Empty now. Hidden for good: toggleInventory skips it.
	if accessoryRowFrame then
		accessoryRowFrame.Visible = false
	end
end

--[[
	THE BIN, built by CLONING a real slot.

	The grid is authored in the place file, not here, so the only way to be sure
	the bin matches it - corner radius, stroke, padding, the size of the number,
	whatever it grows later - is to take one of the authored tiles and copy it.
	Anything built from scratch here matches the grid on the day it is written
	and drifts the first time the place file is touched.

	It is parented to the LAST row rather than to the screen, so it inherits
	that row's visibility and moves with the grid instead of needing its own
	copy of the show/hide.

	The bin ICON goes BEHIND whatever the slot draws rather than instead of it:
	an empty bin shows what it is, and a bin holding something shows the item
	over the picture - so the thing about to be destroyed is never hidden by the
	label saying it is about to be destroyed.
]]
local BIN_SLOT = InventoryConstants.BinSlot

-- The same drawing as the ability screen's bin, so the two mean the same thing
-- in both places. Shared.UI.AbilityPanel owns the original.
local BIN_SPRITE = {
	"....###....",
	".#########.",
	".#########.",
	"...........",
	"..#######..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#######..",
}

-- A fraction of the tile, so the icon scales with whatever the place file sized
-- a slot as rather than assuming pixels.
local BIN_ICON_SCALE = 0.62
local BIN_ICON_TRANSPARENCY = 0.55

local function buildBinIcon(tile)
	local art = Instance.new("Frame")
	art.Name = "BinIcon"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(BIN_ICON_SCALE, BIN_ICON_SCALE)
	art.BackgroundTransparency = 1

	-- Behind the slot's own icon and count, which sit at whatever ZIndex the
	-- place file gave them - at least the tile's.
	art.ZIndex = tile.ZIndex
	art.Parent = tile

	local rows = #BIN_SPRITE
	local columns = #BIN_SPRITE[1]

	for row, line in ipairs(BIN_SPRITE) do
		for column = 1, columns do
			if string.sub(line, column, column) == "#" then
				local pixel = Instance.new("Frame")
				pixel.BackgroundColor3 = Theme.Color.TextDim
				pixel.BackgroundTransparency = BIN_ICON_TRANSPARENCY
				pixel.BorderSizePixel = 0
				pixel.ZIndex = art.ZIndex
				pixel.Position = UDim2.fromScale((column - 1) / columns, (row - 1) / rows)
				pixel.Size = UDim2.fromScale(1 / columns, 1 / rows)
				pixel.Parent = art
			end
		end
	end
end

do
 -- The authored seventh-row tile is the bin. Do not create a second tile.
 local row = invUI:WaitForChild("Row7", 5)
 local tile = row and row:FindFirstChild("Slot1")
 if row then row.Visible = false end
 if tile then
		buildBinIcon(tile)

		slots[BIN_SLOT] = tile
		slotItemNames[BIN_SLOT] = nil

		local binIcon, binNum = getSlotElements(tile)
		slotOrigSizes[BIN_SLOT] = {
			iconSize = (binIcon and binIcon.Size) or UDim2.new(0, 32, 0, 32),
			iconPos = (binIcon and binIcon.Position) or UDim2.new(0, 0, 0, 0),
			numSize = (binNum and binNum.Size) or UDim2.new(0, 16, 0, 16),
			numPos = (binNum and binNum.Position) or UDim2.new(0, 0, 0, 0),
			slotSize = tile.Size,
			slotPos = tile.Position,
			slotZ = tile.ZIndex,
		}
	else
		warn("[InventoryClient] Row7/Slot1 is missing; the inventory bin cannot be shown")
	end
end
updateCoordinateRanges()

-- The one preview panel, under the inventory's own ScreenGui so it moves and
-- hides with it. Built here, after the slots, because it positions itself
-- against them.
ItemPreview.mount(invUI)

-- drag/drop state
local dragging    = false
local sourceIndex = nil
local dragIcon, dragNum

-- Puts a slot tile back to its resting tint. The drop-target colouring above
-- writes ImageColor3 directly, so leaving a drag has to undo it explicitly.
local function resetSlotTint(i)
	local slot = slots[i]
	if slot and (slot:IsA("ImageButton") or slot:IsA("ImageLabel")) then
		slot.ImageColor3 = SLOT_IDLE
	end
end

local function resetSlotSize(i)
	local slot = slots[i]
	if slot and slotOrigSizes[i] then
		local icon, num = getSlotElements(slot)
		if icon and slotOrigSizes[i].iconSize then
			icon.Size = slotOrigSizes[i].iconSize
			icon.Position = slotOrigSizes[i].iconPos
		end
		if num and slotOrigSizes[i].numSize then
			num.Size = slotOrigSizes[i].numSize
			num.Position = slotOrigSizes[i].numPos
		end
	end
end

--[[
	Hover feedback: the tile brightens, swells and steps forward, and the
	tooltip opens under it.

	The TILE, not the icon. Growing the icon inside a fixed tile makes the
	picture bigger and the slot no more noticeable, and it would fight the drag
	system, which owns icon Size and Position.

	The swell is an OFFSET added to the tile's resting UDim2, so it works
	whether the place file sized these in pixels or in scale and leaving is an
	exact restore rather than an inverse guess.
]]
local SLOT_HOVER_SWELL = 0.12

-- The slot the cursor is on, so it can be put back when the inventory closes
-- under it and no MouseLeave ever arrives.
local hoveredSlot: number? = nil

local function setSlotSwollen(index: number, swollen: boolean)
	local slot = slots[index]
	local orig = slotOrigSizes[index]
	if not (slot and orig and orig.slotSize) then
		return
	end

	-- Measured on the first hover, when the tile is laid out and at rest.
	if not orig.slotAbs or orig.slotAbs.X <= 0 then
		orig.slotAbs = slot.AbsoluteSize
	end

	local growX = orig.slotAbs.X * SLOT_HOVER_SWELL
	local growY = orig.slotAbs.Y * SLOT_HOVER_SWELL

	-- Raised while swollen so it steps in front of its neighbours rather than
	-- growing underneath them.
	slot.ZIndex = if swollen then orig.slotZ + 1 else orig.slotZ

	local size = if swollen then orig.slotSize + UDim2.fromOffset(growX, growY) else orig.slotSize
	local position = if swollen
		then orig.slotPos - UDim2.fromOffset(growX * 0.5, growY * 0.5)
		else orig.slotPos

	TweenService:Create(slot, Theme.Tween.Hover, { Size = size, Position = position }):Play()
end

-- Called on MouseLeave, and again when the inventory closes: a row hidden
-- under the cursor never fires one.
function clearHover()
	if hoveredSlot then
		setSlotSwollen(hoveredSlot, false)
		hoveredSlot = nil
	end
	ItemPreview.hide()
end

for i = 1, #slots do
	local slot = slots[i]
	if slot:IsA("ImageButton") or slot:IsA("ImageLabel") then
		slot.MouseEnter:Connect(function()
			-- While dragging, the drop-target tint owns this colour.
			if dragging then return end

			TweenService:Create(slot, Theme.Tween.Hover, { ImageColor3 = SLOT_HOVER }):Play()

			if slotItemNames[i] then
				Sounds.play("ui.hover")

				-- The previous tile is put back first rather than trusting its
				-- MouseLeave: moving quickly between neighbours can deliver Enter
				-- before Leave, which would leave the first one swollen for good.
				if hoveredSlot and hoveredSlot ~= i then
					setSlotSwollen(hoveredSlot, false)
				end

				hoveredSlot = i
				setSlotSwollen(i, true)
				ItemPreview.show(slotItemNames[i], slot)
			end
		end)

		slot.MouseLeave:Connect(function()
			-- Only if this is still the tile the cursor is on. A fast move
			-- between neighbours can deliver this one's Leave after the next
			-- one's Enter, and clearing then would shut the tooltip that had
			-- just opened.
			if hoveredSlot == i then
				clearHover()
			end

			if dragging then return end
			TweenService:Create(slot, Theme.Tween.Hover, { ImageColor3 = SLOT_IDLE }):Play()
		end)

		slot.ImageColor3 = SLOT_IDLE
	end
end

-- single handler for clicks (start dragging)
for i = 1, #slots do
	local slot = slots[i]
	local icon, num = getSlotElements(slot)
	if icon then
		icon.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and icon.Visible then
				log(("start drag from slot %d"):format(i))
				playClick()

				-- A tooltip hanging over the slots while a stack is being
				-- dragged across them is in the way of the thing being done.
				clearHover()
				if dragIcon and dragIcon.Parent then dragIcon:Destroy() end
				if dragNum and dragNum.Parent then dragNum:Destroy() end

				updateCoordinateRanges()
				dragging    = true
				sourceIndex = i
				dragIcon = icon:Clone()
				dragIcon.Parent = invUI
				dragIcon.ZIndex = 101
				dragNum = num:Clone()
				dragNum.Parent = invUI
				dragNum.ZIndex = 101

				local x, y = getMouseXY()
				dragIcon.Position = UDim2.fromOffset(x - icon.AbsoluteSize.X/2, y - icon.AbsoluteSize.Y/2)
				dragIcon.Size     = UDim2.new(0, icon.AbsoluteSize.X, 0, icon.AbsoluteSize.Y)
				dragNum.Position  = UDim2.fromOffset(x + icon.AbsoluteSize.X/2 - num.AbsoluteSize.X, y + icon.AbsoluteSize.Y/2 - num.AbsoluteSize.Y)
				dragNum.Size      = UDim2.new(0, num.AbsoluteSize.X, 0, num.AbsoluteSize.Y)
			end
		end)
	end
end

local hotbarHighlight = invUI:FindFirstChild("HotbarHighlight")
if not hotbarHighlight then
	hotbarHighlight = Instance.new("Frame")
	hotbarHighlight.Name = "HotbarHighlight"
	hotbarHighlight.BorderSizePixel = 0
	hotbarHighlight.ZIndex = 99
	hotbarHighlight.Parent = invUI
end
hotbarHighlight.BackgroundColor3 = Theme.Color.Accent
hotbarHighlight.BackgroundTransparency = Theme.Transparency.Selection

--[[
	Moves the selection marker onto a hotbar slot.

	It SLIDES between neighbouring slots rather than jumping, which is what
	makes running along the hotbar read as one marker moving instead of nine
	flickering on and off. Appearing from nothing still snaps - there is no
	previous slot to have come from.
]]
local function updateHotbarHighlight(index)
	if not (index and index >= 1 and index <= HOTBAR_SLOTS and slots[index]) then
		hotbarHighlight.Visible = false
		return
	end

	local slot = slots[index]
	local origin = invUI.AbsolutePosition
	local position = UDim2.fromOffset(
		slot.AbsolutePosition.X - origin.X,
		slot.AbsolutePosition.Y - origin.Y
	)
	local size = UDim2.fromOffset(slot.AbsoluteSize.X, slot.AbsoluteSize.Y)

	if hotbarHighlight.Visible then
		TweenService:Create(hotbarHighlight, Theme.Tween.Hover, {
			Position = position,
			Size = size,
		}):Play()
	else
		hotbarHighlight.Position = position
		hotbarHighlight.Size = size
		hotbarHighlight.Visible = true
	end
end

--[[
	Which classifications become a held Tool.

	Asked of ToolConfig rather than listed here. This used to be its own table
	of three - Tool, Pickaxe, Weapon - which was a second answer to a question
	ToolConfig already answers, and the moment a fourth holdable classification
	was added the two disagreed: the server built a tool template for a scroll
	and this refused to ask for it, so equipping one silently unequipped
	everything instead. A held item that cannot be held is not a thing that
	should be expressible twice.
]]
local function isEquippable(definition): boolean
	return definition ~= nil and ToolConfig.isHoldable(definition.classification)
end

--[[
	The hotbar keys.

	Selecting is a request, never a local edit. This used to destroy the held
	Tool on the client first, for instant feedback - but a Tool destroyed on the
	client is still there on the server, so "unequipping" by pressing an empty
	slot left MiningServer convinced you were still holding a pickaxe. The
	server owns tools; it is told what to hold, including nothing.

	Pressing the slot you are already on puts the tool away, which is the
	quickest way to get your hands free.
]]
UserInputService.InputBegan:Connect(function(input, processed)
	-- Number keys should not swap what you are holding while a menu is up.
	if processed or MenuState.isAnyOpen() then
		return
	end

	local idx = keyToSlot[input.KeyCode]
	if not idx then
		return
	end

	local name = slotItemNames[idx]
	local def = name and ItemDefinitions[name]

	if name and idx ~= equippedSlot then
		equippedSlot = idx
		RequestEquipTool:FireServer(if isEquippable(def) then name else nil)
	else
		-- An empty slot, or the one already selected: hands free.
		equippedSlot = nil
		RequestEquipTool:FireServer(nil)
	end

	log("hotbar", idx, "->", tostring(equippedSlot))

	updateHotbarHighlight(equippedSlot)
	updateItemLabelFromEquipped()

	player:SetAttribute(EQUIPPED_SLOT_ATTRIBUTE, equippedSlot)
end)

-- inventory toggle
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	-- E also triggers crafting-station prompts. Both firing at once is fine, but
	-- the inventory should not open behind a full-screen menu.
	if input.KeyCode == Enum.KeyCode.E and not MenuState.isAnyOpen() then
		local now = tick()
		if now - lastToggleTime >= 0.35 then
			lastToggleTime = now
			toggleInventory()
			Sounds.play(if inventoryVisible then "ui.open" else "ui.close")
			log("toggled inventory visibility:", inventoryVisible)
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local x, y = getMouseXY()
		if dragIcon then dragIcon.Position = UDim2.fromOffset(x - dragIcon.AbsoluteSize.X/2, y - dragIcon.AbsoluteSize.Y/2) end
		if dragNum then dragNum.Position  = UDim2.fromOffset(x + dragIcon.AbsoluteSize.X/2 - dragNum.AbsoluteSize.X, y + dragIcon.AbsoluteSize.Y/2 - dragNum.AbsoluteSize.Y) end

		local overSlot = nil
		for _, range in pairs(coordinateRanges) do
			if range and x >= range.x1 and x <= range.x2 and y >= range.y1 and y <= range.y2 then
				overSlot = range.index
				break
			end
		end

		if lastHoverSlot and lastHoverSlot ~= overSlot then
			resetSlotSize(lastHoverSlot)
			resetSlotTint(lastHoverSlot)
			lastHoverSlot = nil
		end

		if overSlot and overSlot ~= lastHoverSlot then
			local slot = slots[overSlot]
			local icon, num = getSlotElements(slot)
			local orig = slotOrigSizes[overSlot]
			local scale = 1.2
			local dw = (scale - 1) * orig.iconSize.X.Offset / 2
			local dh = (scale - 1) * orig.iconSize.Y.Offset / 2
			if icon then
				icon.Size     = UDim2.new(0, orig.iconSize.X.Offset * scale, 0, orig.iconSize.Y.Offset * scale)
				icon.Position = orig.iconPos - UDim2.new(0, dw, 0, dh)
			end
			if num then num.Position  = orig.numPos - UDim2.new(0, dw, 0, dh) end
			lastHoverSlot = overSlot
		end

		if overSlot then
			local restriction = InventoryConstants.getSlotRestriction(overSlot)
			local itemName = slotItemNames[sourceIndex]
			local itemDef = ItemDefinitions[itemName]

			if restriction and (not itemDef or itemDef.classification ~= restriction) then
				slots[overSlot].ImageColor3 = Theme.Color.Bad
			elseif InventoryConstants.isBinSlot(overSlot) and slotItemNames[overSlot] then
				-- The bin takes anything, so red here does not mean "refused" -
				-- it means something is about to be destroyed, which is the one
				-- case in this grid where letting go cannot be undone. An EMPTY
				-- bin stays green: nothing is lost by parking an item in it.
				slots[overSlot].ImageColor3 = Theme.Color.Bad
			else
				slots[overSlot].ImageColor3 = Theme.Color.Good
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
		log("drop event")
		playClick()

		if lastHoverSlot then
			resetSlotSize(lastHoverSlot)
			resetSlotTint(lastHoverSlot)
			lastHoverSlot = nil
		end
		updateCoordinateRanges()
		local mx, my = getMouseXY()
		local targetIndex
		for _, range in pairs(coordinateRanges) do
			if range and mx >= range.x1 and mx <= range.x2 and my >= range.y1 and my <= range.y2 then
				targetIndex = range.index
				break
			end
		end

		local willSwap = false
		local willTransfer = false
		local transferAmount = 0

		if targetIndex and targetIndex ~= sourceIndex then
			local restriction = InventoryConstants.getSlotRestriction(targetIndex)
			local itemName = slotItemNames[sourceIndex]
			local itemDef = ItemDefinitions[itemName]
			if restriction and (not itemDef or itemDef.classification ~= restriction) then
				log("cannot place due to slot restriction")
			elseif InventoryConstants.isBinSlot(targetIndex) then
				-- A drop onto the bin is always a REPLACEMENT, never a merge.
				-- Left to the stacking rule below, five stone onto ten stone
				-- would top the bin up to fifteen and keep the ten - and the
				-- one promise the bin makes is that what was in it is gone the
				-- moment something else goes in. The server refuses a transfer
				-- here too; this is so an honest client never asks.
				willSwap = true
			else
				local targetName = slotItemNames[targetIndex]
				if itemName and targetName and itemName == targetName then
					local def = ItemDefinitions[itemName]
					local maxStack = getMaxStack(def) or 1
					if maxStack > 1 then
						willTransfer = true
						transferAmount = (inventory[sourceIndex] and inventory[sourceIndex].count) or 1
					else
						willSwap = true
					end
				else
					willSwap = true
				end
			end
		end

		if dragIcon and dragIcon.Parent then dragIcon:Destroy() end
		if dragNum and dragNum.Parent then dragNum:Destroy() end
		dragIcon, dragNum = nil, nil

		if willTransfer then
			log(("requesting transfer %d -> %d amount %d"):format(sourceIndex, targetIndex, transferAmount))
			RequestTransferStack:FireServer(sourceIndex, targetIndex, transferAmount)
		elseif willSwap then
			log(("requesting swap %d <-> %d"):format(sourceIndex, targetIndex))
			RequestSwapSlots:FireServer(sourceIndex, targetIndex)
		end

		dragging = false
		sourceIndex = nil
	end
end)

-- Hit boxes only move when the UI does: rows shown or hidden, or the window
-- resized. This used to be recomputed every frame to catch a change that
-- happens a handful of times a session.
invUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCoordinateRanges)

clearSlots()
log("requesting full inventory from server")
RequestFullInv:FireServer()
-- A modal menu owning the screen should not have the inventory grid sitting
-- open behind it. E both toggles this and triggers crafting-station prompts, and
-- the order those two handlers run in is not defined, so this closes the grid
-- whichever way round they land.
MenuState.Changed:Connect(function(_, _, anyOpen)
	if anyOpen and inventoryVisible then
		toggleInventory()
	end
end)

-- Subscribed through the mirror rather than to the remote directly: the server
-- now sends only the slots that moved, and the mirror is what turns those back
-- into the whole bag this UI reads. `changed` lists the slots that actually
-- differ, so an ordinary pickup redraws one tile instead of forty-two.
InventoryMirror.onChanged(function(snapshot, changed)
	log("received inventory update from server")
	updateSlots(snapshot, changed)
	updateCoordinateRanges()
	updateHotbarHighlight(equippedSlot)
	player:SetAttribute(EQUIPPED_SLOT_ATTRIBUTE, equippedSlot)
end)

player.CharacterAdded:Connect(function()
	log("character added; clearing UI and requesting inventory")
	clearSlots()
	RequestFullInv:FireServer()

	equippedSlot = nil
	-- Roblox puts an equipped tool back in the Backpack on death, so without
	-- this the server is still holding one the hotbar no longer shows.
	RequestEquipTool:FireServer(nil)

	updateHotbarHighlight(equippedSlot)
	updateItemLabelFromEquipped()
	player:SetAttribute(EQUIPPED_SLOT_ATTRIBUTE, nil)
end)

log("loaded")

-- Scroll chests are used from the selected hotbar slot; the server verifies its contents.
local ScrollChestRequest=remotes:WaitForChild("ScrollChestRequest")
UserInputService.InputBegan:Connect(function(input,processed)
 if processed or MenuState.isAnyOpen() then return end
 if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
 if equippedSlot and slotItemNames[equippedSlot]=="ScrollChest" then ScrollChestRequest:FireServer("open",equippedSlot) end
end)
