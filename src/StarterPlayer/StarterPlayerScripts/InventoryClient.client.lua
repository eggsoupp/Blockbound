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

	The screen itself - where every tile sits, and how big - is built by
	Shared.UI.InventoryLayout. This script only fills it and reacts to it.

	Set DEBUG to true to trace the equip flow.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
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
local InventoryLayout = require(Shared.UI:WaitForChild("InventoryLayout"))
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
local layout = InventoryLayout.build(gui)
local invUI  = layout.gui

-- Shows the equipped hotbar item.
local itemLabel = layout.itemLabel

local function playClick()
	Sounds.play("ui.click")
end

-- Slot tile tints. The tile art is light parchment, so "idle" is a touch dimmed
-- and hovering brings it back to full brightness. Only a touch: dimmed any
-- further, parchment turns to mud.
local SLOT_IDLE  = Color3.fromRGB(230, 230, 230)
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

--[[
	Where the pointer is, in the space GuiObject.AbsolutePosition is measured in.

	That space starts BELOW Roblox's top bar, even inside a ScreenGui that
	ignores the inset, while UserInputService:GetMouseLocation() starts at the
	very top of the window. Hit-testing one against the other put every drop
	target a top bar's height too high: you had to let go above a slot to land
	in it. An InputObject's Position is already in the AbsolutePosition space,
	so the tiles' hit boxes and the pointer are now compared in one space with
	no inset added or taken away anywhere. (AbilityPanel's notes describe the
	same trap.)
]]
local function pointerOf(input: InputObject): (number, number)
	return input.Position.X, input.Position.Y
end

-- From that space to an Offset inside InventoryUI, for placing the drag
-- preview: measured against the ScreenGui's own AbsolutePosition, so it is
-- right however the inset is reported.
local function toGuiOffset(x: number, y: number): (number, number)
	local origin = invUI.AbsolutePosition
	return x - origin.X, y - origin.Y
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
		-- A swap reads as a new name arriving rather than a hard text swap.
		Motion.fadeInText(itemLabel)
	else
		itemLabel.Text = ""
	end
end

-- The hotbar is always up; rows 2-6 are hidden until the inventory opens. This
-- is what keeps live slot views affordable - a closed inventory renders the
-- hotbar and nothing else.
local HOTBAR_SLOTS = InventoryConstants.HotbarSlots

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

--[[
	The slot a drag is over, by the cursor.

	Not only the square of a tile: the gap between two tiles, and a margin
	round the outside of the grid, count as the nearest tile. Letting go
	anywhere on the inventory lands the item in the slot it looks like it is
	over, rather than only when the cursor is squarely inside one. Far enough
	off the grid, it is nothing, and the drag is cancelled.
]]
local DROP_REACH = 0.4 -- of a tile's width, past its edge

local function slotAt(x: number, y: number): number?
	local best, bestDistance = nil, math.huge

	for _, range in pairs(coordinateRanges) do
		local dx = math.max(range.x1 - x, 0, x - range.x2)
		local dy = math.max(range.y1 - y, 0, y - range.y2)
		if dx == 0 and dy == 0 then
			return range.index
		end

		local distance = math.sqrt(dx * dx + dy * dy)
		if distance <= (range.x2 - range.x1) * DROP_REACH and distance < bestDistance then
			best, bestDistance = range.index, distance
		end
	end

	return best
end

local function toggleInventory()
	inventoryVisible = not inventoryVisible

	-- Rows closing under the cursor never fire MouseLeave, so the swollen tile
	-- and its tooltip have to be told directly or they would be left behind on a
	-- closed inventory.
	clearHover()
	for _, panel in ipairs(layout.openPanels) do
		panel.Visible = inventoryVisible
	end
	layout.setOpen(inventoryVisible)

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

-- Every tile, in slot order: the hotbar, the bag, the gear and the bin. Where
-- each one sits is InventoryLayout's business; this only needs to know which
-- index it is.
for index, slotUI in ipairs(layout.slots) do
	slots[index] = slotUI
	slotItemNames[index] = nil

	local icon, num = getSlotElements(slotUI)
	slotOrigSizes[index] = {
		iconSize = icon.Size,
		iconPos  = icon.Position,
		numSize  = num.Size,
		numPos   = num.Position,

		-- The tile's resting geometry, which the hover swell below grows from
		-- and puts back exactly.
		slotSize = slotUI.Size,
		slotPos  = slotUI.Position,
		slotZ    = slotUI.ZIndex,
	}
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

	The swell is an OFFSET added to the tile's resting UDim2, so leaving is an
	exact restore rather than an inverse guess. It is a share of the tile's own
	Offset size, NOT its AbsoluteSize: InventoryLayout scales the tiles to the
	screen with a UIScale, which multiplies the swell as well, so growing by
	on-screen pixels would count the screen's scale twice.
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

	local growX = orig.slotSize.X.Offset * SLOT_HOVER_SWELL
	local growY = orig.slotSize.Y.Offset * SLOT_HOVER_SWELL

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

--[[
	Starting a drag. From anywhere on the tile, not only the item picture in
	its middle: grabbing a slot by its frame used to do nothing at all.

	Both the tile and the picture listen, since the picture sits on top of the
	tile, so one click can arrive twice. The second is dropped by time rather
	than by `dragging`, so a drag whose release was never seen (let go outside
	the window) cannot block the next one.
]]
local dragStartedAt = -math.huge

for i = 1, #slots do
	local slot = slots[i]
	local icon, num = getSlotElements(slot)
	if icon then
		local function beginDrag(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and icon.Visible then
				if dragging and sourceIndex == i and os.clock() - dragStartedAt < 0.1 then
					return
				end
				dragStartedAt = os.clock()

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

				local x, y = toGuiOffset(pointerOf(input))
				dragIcon.Position = UDim2.fromOffset(x - icon.AbsoluteSize.X/2, y - icon.AbsoluteSize.Y/2)
				dragIcon.Size     = UDim2.new(0, icon.AbsoluteSize.X, 0, icon.AbsoluteSize.Y)
				dragNum.Position  = UDim2.fromOffset(x + icon.AbsoluteSize.X/2 - num.AbsoluteSize.X, y + icon.AbsoluteSize.Y/2 - num.AbsoluteSize.Y)
				dragNum.Size      = UDim2.new(0, num.AbsoluteSize.X, 0, num.AbsoluteSize.Y)
			end
		end

		slot.InputBegan:Connect(beginDrag)
		icon.InputBegan:Connect(beginDrag)
	end
end

-- The selection marker on the hotbar: drawn and moved by InventoryLayout, which
-- owns where the tiles sit. nil (or anything off the hotbar) hides it.
local function updateHotbarHighlight(index)
	if index and index >= 1 and index <= HOTBAR_SLOTS then
		layout.selectHotbar(index)
	else
		layout.selectHotbar(nil)
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

	-- The slot taken up bumps, so the eye lands on what is now in hand. Not on
	-- putting things away: empty hands are not an event.
	if equippedSlot and slots[equippedSlot] then
		Motion.pulse(slots[equippedSlot], 1.1)
	end

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
		-- The hit test reads the pointer in AbsolutePosition space; the preview
		-- is placed in the ScreenGui's own. See pointerOf.
		local x, y = pointerOf(input)
		local gx, gy = toGuiOffset(x, y)
		if dragIcon then
			local size = dragIcon.AbsoluteSize
			dragIcon.Position = UDim2.fromOffset(gx - size.X/2, gy - size.Y/2)
			if dragNum then
				dragNum.Position = UDim2.fromOffset(gx + size.X/2 - dragNum.AbsoluteSize.X, gy + size.Y/2 - dragNum.AbsoluteSize.Y)
			end
		end

		local overSlot = slotAt(x, y)

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
		local targetIndex = slotAt(pointerOf(input))

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

-- Hit boxes only move when the UI does: rows shown or hidden, or the layout
-- moving or rescaling with the window. This used to be recomputed every frame
-- to catch a change that happens a handful of times a session.
layout.onMoved(updateCoordinateRanges)

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
--[[
	The Gelatinous Crown is used the same way, but AT something: the click's
	target and hit point go up, and ServerScriptService.AltarSummon decides
	whether that was an altar. Only what was clicked is sent; the slot's
	contents, the reach and the block are all re-checked there.
]]
local AltarUseRequest=remotes:WaitForChild("AltarUseRequest")
local useMouse=player:GetMouse()
UserInputService.InputBegan:Connect(function(input,processed)
 if processed or MenuState.isAnyOpen() then return end
 if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
 if not equippedSlot then return end
 local held=slotItemNames[equippedSlot]
 if held=="ScrollChest" then ScrollChestRequest:FireServer("open",equippedSlot)
 elseif held=="GelatinousCrown" then AltarUseRequest:FireServer(equippedSlot,useMouse.Target,useMouse.Hit.Position) end
end)
