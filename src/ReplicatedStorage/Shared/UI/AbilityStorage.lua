--[[
	AbilityStorage

	The panel behind the storage box in the ability screen: three slots an
	ability can be parked in instead of thrown away, and the swap that gets one
	back out when the loadout is already full.

	WHAT LIVES WHERE

	The BOX ITSELF is built by AbilityPanel, which also positions it, sizes it
	and lights it up while a card is over it. That is deliberate: the box and
	the bin are the two things a card can be dragged onto, they sit one above
	the other, and they have to be the same control in two flavours. Drawn from
	here they were half the bin's size and signalled "armed" a different way,
	which read as one control and one decoration.

	So this file owns the BEHAVIOUR - what opens, what the slots say, and which
	request goes to the server - and takes the finished button as an argument.

	THE SERVER OWNS EVERYTHING REAL. Nothing here decides whether a player has
	the gamepass, whether a slot is free, or what ends up stored; it asks, and
	redraws when AbilityLoadout pushes back. See the storage section there.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Theme = require(script.Parent.Theme)
local Config = require(Shared.Abilities.AbilityConfig)
local Remotes = require(Shared.Net.Remotes)

local Request = Remotes.wait("AbilityStorageRequest")
local Changed = Remotes.wait("AbilityStorageChanged")

-- Rows built. The server sends the capacity it actually enforces with every
-- push; anything past it is hidden rather than drawn as a slot that refuses.
local SLOT_ROWS = 3

local SLOT_HEIGHT = 48
local SLOT_GAP = 6
local SLOT_INSET = 8
local HEADING_HEIGHT = 35
local PANEL_HEIGHT = HEADING_HEIGHT + SLOT_ROWS * (SLOT_HEIGHT + SLOT_GAP)

-- The last thing the server said. One copy for every panel on screen, because
-- there is only ever one player.
local state = { slots = {}, owned = false, capacity = SLOT_ROWS }
local views = {}

local AbilityStorage = {}

--[[
	button      the box, already built and placed by AbilityPanel
	panelX      where the drop-down sits, which is over the cards
	panelWidth  and how wide, which is a card
	getActive   the loadout as it is on screen right now, for the swap list
]]
function AbilityStorage.create(parent, button, panelX, panelWidth, getActive)
	local panel = Instance.new("Frame")
	panel.Name = "StoredAbilities"
	panel.Position = UDim2.fromOffset(panelX, 0)
	panel.Size = UDim2.fromOffset(panelWidth, PANEL_HEIGHT)
	panel.BackgroundColor3 = Theme.Color.Panel
	panel.BorderSizePixel = 0
	panel.ZIndex = 30
	panel.Visible = false
	panel.Parent = parent

	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.new(1, -35, 0, HEADING_HEIGHT)
	heading.BackgroundTransparency = 1
	heading.FontFace = Theme.Fonts.BodyBold
	heading.TextColor3 = Theme.Color.Text
	heading.TextSize = 14
	heading.ZIndex = 31
	heading.Parent = panel

	local close = Instance.new("TextButton")
	close.Text = "×"
	close.Size = UDim2.fromOffset(30, 30)
	close.Position = UDim2.new(1, -32, 0, 2)
	close.BackgroundTransparency = 1
	close.TextColor3 = Theme.Color.Text
	close.TextSize = 20
	close.ZIndex = 31
	close.Parent = panel

	-- Set while a stored ability is waiting to be traded for an active one, so
	-- the same three buttons list the LOADOUT instead of the store.
	local swapName = nil
	local buttons = {}

	local function refresh()
		heading.Text = if swapName
			then "SWAP WITH ACTIVE ABILITY"
			elseif state.owned then "ABILITY STORAGE"
			else "+3 STORAGE · GAMEPASS"

		local list = if swapName then getActive() else state.slots

		local capacity = state.capacity or SLOT_ROWS

		for index, slot in ipairs(buttons) do
			slot.Visible = swapName ~= nil or index <= capacity

			local name = list[index]
			local def = name and Config.get(name)

			slot.Text = if def
				then (def.displayName or name) .. (if swapName then "" else "  ·  equip")
				elseif state.owned then "Empty slot"
				else "Locked · unlock +3 storage"

			slot.TextColor3 = if def then Theme.rarityColor(def.rarity) else Theme.Color.TextDim
		end
	end

	for index = 1, SLOT_ROWS do
		local slot = Instance.new("TextButton")
		slot.Size = UDim2.new(1, -SLOT_INSET * 2, 0, SLOT_HEIGHT)
		slot.Position = UDim2.fromOffset(
			SLOT_INSET, HEADING_HEIGHT + (index - 1) * (SLOT_HEIGHT + SLOT_GAP)
		)
		slot.BackgroundColor3 = Theme.Color.Panel
		slot.BorderSizePixel = 1
		slot.BorderColor3 = Theme.Color.Stroke
		slot.FontFace = Theme.Fonts.Body
		slot.TextSize = 14
		slot.ZIndex = 31
		slot.Parent = panel
		buttons[index] = slot

		slot.Activated:Connect(function()
			if not state.owned then
				Request:FireServer("unlock")
				return
			end

			if swapName then
				-- Second half of a swap: this row is an ACTIVE ability now.
				local active = getActive()[index]
				if active then
					Request:FireServer("swap", swapName, active)
					swapName = nil
					refresh()
				end
				return
			end

			local name = state.slots[index]
			if not name then
				return
			end

			-- A full loadout has nowhere to put this, so the click becomes the
			-- first half of a swap rather than a refusal.
			-- Config.SlotCount, not a 3: the server checks the same number, and two
			-- copies of it is how they come to disagree.
			if #getActive() >= Config.SlotCount then
				swapName = name
				refresh()
			else
				Request:FireServer("retrieve", name)
			end
		end)
	end

	close.Activated:Connect(function()
		panel.Visible = false
		swapName = nil
	end)

	button.Activated:Connect(function()
		swapName = nil
		refresh()
		panel.Visible = not panel.Visible
		Request:FireServer("sync")
	end)

	local view = { button = button, panel = panel, refresh = refresh }

	-- Called when the ability screen closes, so storage is not still hanging
	-- open the next time it is opened.
	function view.dismiss()
		panel.Visible = false
		swapName = nil
	end

	function view.store(name)
		if name then
			Request:FireServer("store", name)
		end
	end

	views[view] = true
	parent.Destroying:Connect(function()
		views[view] = nil
	end)

	refresh()
	return view
end

Changed.OnClientEvent:Connect(function(value)
	if type(value) ~= "table" or type(value.slots) ~= "table" then
		return
	end

	state = value
	for view in pairs(views) do
		view.refresh()
	end
end)

task.defer(function()
	Request:FireServer("sync")
end)

return AbilityStorage
