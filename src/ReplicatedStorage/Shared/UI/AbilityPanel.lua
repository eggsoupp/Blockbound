--[[
	AbilityPanel

	The loadout, listed over the Tab menu's wireframe solid, and draggable: a
	card per slot, dragged up or down to change which key casts what, or
	sideways onto the bin to throw it away.

		local panel = AbilityPanel.new(someFrame)
		panel:setVisible(true)
		panel:destroy()

		AbilityPanel.setSlots(entries)                    -- what to list
		AbilityPanel.setHandlers({ reorder = , drop = })  -- where a drop goes

	THE LAYOUT IS THE REFERENCE'S

	A small line in capitals naming the slot and its key, the ability's name
	under it, and its tier under that, in the tier's own colour. No box until
	you point at one - the art behind it is a handful of pale hairlines, and a
	panel drawn over that stops being a readout and starts being a window.

	Shared.UI.MenuBackdrop used to draw this list itself, for a few seconds,
	when an ability was equipped. Now that the list is permanent it does the
	REACTION instead - it throws the solid outward in the new ability's colour -
	and the two halves no longer print the same three names in the same place.

	IT KNOWS NOTHING ABOUT ABILITIES

	Entries arrive already worded: { label, name, rarity, gained }, with name
	nil for an empty slot. So this file never reads AbilityConfig, never names
	an ability and never touches a remote - it draws what it is handed and
	reports which slot was dragged onto which. StarterPlayerScripts.AbilityClient
	owns all three of those and wires them together.

	DRAGGING IS OPTIMISTIC, AND THE SERVER IS STILL THE AUTHORITY

	A dropped card stays where it was dropped rather than snapping home to wait
	for a round trip. That is a guess, and it is corrected: AbilityLoadout
	answers EVERY reorder request with a push of the real order, including one
	it refused, so a wrong guess is overwritten a moment later rather than left
	on screen. The alternative - snap back, then jump forward 80ms later - looks
	broken every single time, including when it worked.

	Only the filled slots take part. The loadout is a dense array on the server
	(see AbilityLoadout), so there is no such thing as an ability on V with
	nothing on X, and a drop below the last filled card lands on that card
	rather than opening a hole the server would refuse to keep.

	THE BIN IS THE OTHER HALF OF THE THREE-SLOT LIMIT

	With every slot full, a scroll cannot be read: AbilityLoadout.add refuses
	and says so. The bin is what a player does about that, and it is why it is
	here rather than being another chat command - the moment you find out you
	are full is the moment a scroll is in your hand, and the fix should not be
	a thing you have to know the name of.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Confirm = require(script.Parent:WaitForChild("Confirm"))
local Sounds = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("Sounds")
)

local StorageUI = require(script.Parent.AbilityStorage)
local StorageAbilityConfig = require(ReplicatedStorage.Shared.Abilities.AbilityConfig)
local AbilityPanel = {}
AbilityPanel.__index = AbilityPanel

--[[
	The one that exists, what it is showing, and who to tell about a drag.

	Module level for the same reason MenuBackdrop's is: PauseMenu owns the
	instance and AbilityClient owns the data, and neither has any business
	holding a reference to the other. Keeping the slot list here as well is what
	makes the order of those two not matter - a push that arrives before the
	panel is built is applied when it is built, rather than dropped.
]]
local live = nil
local slots: { any } = {}

--[[
	What to do when a card is dropped somewhere: { reorder, drop }.

	One table rather than a setter each, because they are set together, by the
	same script, at the same moment - and a second setter is a second thing to
	forget.
]]
local handlers: { [string]: ((...any) -> ())? } = {}

-- ---------------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------------

-- Pixels. Fixed rather than proportional, like every other panel in the game:
-- text that scales with the window is text that is the wrong size twice.
local CARD_WIDTH = 340
local CARD_HEIGHT = 62
local CARD_GAP = 10
local PITCH = CARD_HEIGHT + CARD_GAP

-- Row offsets inside a card: the capitals line, the name, the tier.
local LABEL_Y, LABEL_HEIGHT = 3, 15
local NAME_Y, NAME_HEIGHT = 18, 26
local RARITY_Y, RARITY_HEIGHT = 44, 16

local HINT_GAP = 10
local HINT_HEIGHT = 16

--[[
	THE BIN, drawn a pixel at a time.

	Each '#' is one square Frame BIN_PIXEL across, so the thing is a sprite
	without being an image: no asset to upload, no id to go stale, and it is
	crisp at any size because it is made of rectangles rather than resampled
	from one. The two walls and the two slots in the body are what make it read
	as a bin rather than as a bucket at this size.

	Change the picture by editing the picture. Width and height are measured off
	it, so a wider or taller drawing needs nothing else changed.
]]
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

local BIN_PIXEL = 6
local BIN_GAP = 18
local BIN_WIDTH = #BIN_SPRITE[1] * BIN_PIXEL
local BIN_HEIGHT = #BIN_SPRITE * BIN_PIXEL

--[[
	The panel is CARD_WIDTH wide plus the bin's side TWICE - once for the bin
	and once for nothing at all.

	The empty column on the left is deliberate. The whole root is centred on the
	screen, so without it the cards would sit half a bin's width left of centre
	and stop being centred on the solid they are drawn over. Padding the other
	side costs a few pixels of transparent CanvasGroup and keeps the thing that
	is actually being looked at in the middle.
]]
local BIN_SIDE = BIN_WIDTH + BIN_GAP
local CARDS_X = BIN_SIDE
local BIN_X = BIN_SIDE + CARD_WIDTH + BIN_GAP

--[[
	How far right a card has to be dragged before the bin takes it: half the
	distance to it.

	Measured as a DISTANCE DRAGGED rather than by testing the cursor against the
	bin's rectangle on screen, because a delta needs no agreement about which of
	Roblox's coordinate spaces anything is in - the same reason pointerAt works
	the way it does. The card slides visibly toward the bin the whole time, so
	there is nothing hidden about where the threshold is.
]]
local BIN_REACH = BIN_SIDE * 0.5

local BIN_IDLE_TRANSPARENCY = 0.55
local BIN_ARMED_TRANSPARENCY = 0

--[[
	THE STORAGE BOX, the bin's opposite number.

	Same grid as BIN_SPRITE and drawn by the same code at the same pixel size,
	so the two controls come out identical in size and weight. They are the two
	things a card can be dragged onto and they sit one above the other; a pair
	that did not match would read as one control and one decoration.

	Three compartments, because that is what it holds. The bin says what happens
	to an ability and this says what happens to an ability, so neither carries a
	label - the drag hint underneath names them both.
]]
local STORAGE_SPRITE = {
	"...........",
	".#########.",
	".#.......#.",
	".#.......#.",
	".#########.",
	".#.......#.",
	".#.......#.",
	".#########.",
	".#.......#.",
	".#.......#.",
	".#########.",
	"...........",
}

-- Between the bin and the box. Smaller than BIN_GAP because that one separates
-- the cards from the controls, and these two belong together.
local STORAGE_GAP = 10

--[[
	The card's own box, which is invisible until it is pointed at.

	LIFTED is the one being dragged. It is the most opaque of the three on
	purpose: while it is in the air it has to read as a thing that came off the
	stack rather than as another row of it.
]]
local CARD_REST = 1
local CARD_HOVER = 0.55
local CARD_LIFTED = 0.3

local STROKE_REST = 1
local STROKE_HOVER = 0.45
local STROKE_LIFTED = 0.1

-- How far the pointer travels before a press stops being a click and becomes a
-- drag. Without it every click nudges the stack by a pixel and back.
local DRAG_THRESHOLD = 4

-- How long a newly equipped ability stays picked out in its card.
local GAIN_HOLD = 4

local EMPTY_TEXT = "Empty"
local DRAG_HINT = "drag to reorder, bin to drop, or storage to keep"
local DRAG_HINT_ONE = "drag to bin to drop, or storage to keep"

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

local function newText(
	parent: Instance,
	y: number,
	height: number,
	size: number,
	font: Font,
	color: Color3
): TextLabel
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	label.Text = ""
	label.Parent = parent
	return label
end

--[[
	Where the pointer is.

	Only ever used as a DIFFERENCE from where the drag started, so which of
	Roblox's several screen spaces this is measured in does not matter - only
	that the same one is used for the whole of one drag. That is also why the
	GUI inset never has to be corrected for here, which is the usual way a drag
	ends up sitting a topbar's height away from the cursor, and why the bin
	tests how far a card has been dragged rather than where the cursor is.
]]
local function pointerAt(input: InputObject): (number?, number?)
	local kind = input.UserInputType

	if kind == Enum.UserInputType.Touch then
		return input.Position.X, input.Position.Y
	end

	if
		kind == Enum.UserInputType.MouseMovement
		or kind == Enum.UserInputType.MouseButton1
	then
		local location = UserInputService:GetMouseLocation()
		return location.X, location.Y
	end

	return nil, nil
end

--[[
	Builds one of the drag targets out of its sprite, one Frame per '#'.

	Returns the container and the pixels, because the pixels are what get
	recoloured when a card is dragged over it - the container is only there to
	move and size them as one.

	Both the bin and the storage box come through here, which is the point: they
	are the same control in two flavours, so they are drawn by the same code at
	the same pixel size off two equally-sized grids. Give one of them its own
	builder and they drift apart on the first edit to either.

	A TextButton rather than a Frame so the box can also be CLICKED, which is
	how the storage panel opens. The bin has nothing to open, and a button
	nobody connects is inert.
]]
local function buildSprite(
	parent: Instance,
	sprite: { string },
	name: string,
	top: number
): (TextButton, { Frame })
	local field = Instance.new("TextButton")
	field.Name = name
	field.Text = ""
	field.AutoButtonColor = false
	field.Position = UDim2.fromOffset(BIN_X, top)
	field.Size = UDim2.fromOffset(#sprite[1] * BIN_PIXEL, #sprite * BIN_PIXEL)
	field.BackgroundTransparency = 1
	field.Parent = parent

	local pixels = {}

	for row, line in ipairs(sprite) do
		for column = 1, #line do
			if string.sub(line, column, column) == "#" then
				local pixel = Instance.new("Frame")
				pixel.Position = UDim2.fromOffset((column - 1) * BIN_PIXEL, (row - 1) * BIN_PIXEL)
				pixel.Size = UDim2.fromOffset(BIN_PIXEL, BIN_PIXEL)
				pixel.BackgroundColor3 = Theme.Color.TextDim
				pixel.BackgroundTransparency = BIN_IDLE_TRANSPARENCY
				pixel.BorderSizePixel = 0
				pixel.Parent = field
				table.insert(pixels, pixel)
			end
		end
	end

	return field, pixels
end

-- Lights one of them up while a card is over it. Armed is the accent colour at
-- full opacity, idle is dim and half faded - the same two states for both, so
-- "this is where it would land" reads the same wherever the card is going.
local function setSpriteArmed(pixels: { Frame }, armed: boolean, accent: Color3)
	local color = if armed then accent else Theme.Color.TextDim
	local transparency = if armed then BIN_ARMED_TRANSPARENCY else BIN_IDLE_TRANSPARENCY

	for _, pixel in ipairs(pixels) do
		pixel.BackgroundColor3 = color
		pixel.BackgroundTransparency = transparency
	end
end

local function isPressInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- ---------------------------------------------------------------------------
-- Instance
-- ---------------------------------------------------------------------------

function AbilityPanel.new(parent: Instance)
	local self = setmetatable({}, AbilityPanel)

	--[[
		A CanvasGroup, so the whole panel fades on ONE property.

		The alternative is tweening a background, a stroke and three labels per
		card and hoping none of them is mid-hover when the menu closes. Here the
		fade and the hover write different properties and cannot fight.
	]]
	local root = Instance.new("CanvasGroup")
	root.Name = "AbilityPanel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(CARD_WIDTH + BIN_SIDE * 2, PITCH)
	root.BackgroundTransparency = 1
	root.GroupTransparency = 1
	root.Visible = false

	-- Over MenuBackdrop's art, which tops out at 4 and is a sibling of this.
	root.ZIndex = 6
	root.Parent = parent

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, 0)
	hint.Size = UDim2.new(1, 0, 0, HINT_HEIGHT)
	hint.BackgroundTransparency = 1
	hint.FontFace = Theme.Fonts.Body
	hint.TextSize = Theme.TextSize.Small
	hint.TextColor3 = Theme.Color.TextFaint
	hint.TextStrokeTransparency = 1
	hint.Text = DRAG_HINT
	hint.Visible = false
	hint.Parent = root

	local bin, binPixels = buildSprite(root, BIN_SPRITE, "Bin", 0)
	local box, boxPixels = buildSprite(root, STORAGE_SPRITE, "AbilityStorage", 0)

	self.root = root
	self.hint = hint
	self.bin = bin
	self.binPixels = binPixels
	self.box = box
	self.boxPixels = boxPixels

	-- The box's LOOK belongs here, with the bin's; what opening it does belongs
	-- to AbilityStorage. So the button is built and armed on this side and
	-- handed over, and the two controls cannot drift apart no matter what the
	-- storage panel grows into.
	self.storage = StorageUI.create(root, box, CARDS_X, CARD_WIDTH, function()
		local names = {}
		for _, entry in ipairs(slots) do
			local name = entry.name and StorageAbilityConfig.resolve(entry.name)
			if name then
				table.insert(names, name)
			end
		end
		return names
	end)
	self.cards = {}
	self.filled = 0
	self.visible = false
	self.fade = nil
	self.drag = nil

	live = self

	-- Whatever was pushed before this existed is what it opens showing.
	self:_rebuild()

	return self
end

function AbilityPanel:_buildCard(index: number)
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. index
	button.Text = ""
	button.AutoButtonColor = false
	button.Position = UDim2.fromOffset(CARDS_X, (index - 1) * PITCH)
	button.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	button.BackgroundColor3 = Theme.Color.Panel
	button.BackgroundTransparency = CARD_REST
	button.BorderSizePixel = 0
	button.Parent = self.root

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Stroke
	stroke.Thickness = 1
	stroke.Transparency = STROKE_REST
	stroke.Parent = button

	local card = {
		button = button,
		stroke = stroke,
		label = newText(
			button, LABEL_Y, LABEL_HEIGHT,
			Theme.TextSize.Small, Theme.Fonts.BodyBold, Theme.Color.TextDim
		),
		name = newText(
			button, NAME_Y, NAME_HEIGHT,
			Theme.TextSize.Heading, Theme.Fonts.Heading, Theme.Color.Text
		),
		rarity = newText(
			button, RARITY_Y, RARITY_HEIGHT,
			Theme.TextSize.Small, Theme.Fonts.BodyBold, Theme.Color.TextDim
		),
		slot = index,
		filled = false,
		hovered = false,
		gained = false,
		rarityColor = nil,
		gainToken = 0,

		-- The tween carrying this card into the slot it was dropped on, while
		-- one is running. See _rebuild for why it is worth holding on to.
		settle = nil,
	}

	button.MouseEnter:Connect(function()
		card.hovered = true
		self:_refreshCard(card)

		-- Silent on an empty slot and mid-drag: the first is not a thing you
		-- can pick up, and the second already has the cursor making noise.
		if card.filled and not self.drag then
			Sounds.play("ui.hover")
		end
	end)

	button.MouseLeave:Connect(function()
		card.hovered = false
		self:_refreshCard(card)
	end)

	button.InputBegan:Connect(function(input)
		if isPressInput(input) then
			self:_beginDrag(card, pointerAt(input))
		end
	end)

	return card
end

--[[
	Colours a card from its own state.

	One function rather than a write at each of the places state changes: hover,
	drag and "just equipped" all want a say in the same two transparencies, and
	three handlers each writing what they think the answer is, is how a card
	ends up stuck looking hovered.
]]
function AbilityPanel:_refreshCard(card)
	local lifted = self.drag ~= nil and self.drag.card == card
	local raised = lifted or (card.filled and (card.hovered or card.gained))

	if lifted then
		card.button.BackgroundTransparency = CARD_LIFTED
		card.stroke.Transparency = STROKE_LIFTED
	elseif raised then
		card.button.BackgroundTransparency = CARD_HOVER
		card.stroke.Transparency = STROKE_HOVER
	else
		card.button.BackgroundTransparency = CARD_REST
		card.stroke.Transparency = STROKE_REST
	end

	if card.gained and card.rarityColor then
		card.stroke.Color = card.rarityColor
	elseif lifted then
		card.stroke.Color = Theme.Color.Accent
	else
		card.stroke.Color = Theme.Color.Stroke
	end

	card.label.TextColor3 = if card.gained then Theme.Color.Good else Theme.Color.TextDim
end

--[[
	Redraws the whole list from whatever was last pushed.

	The cards themselves are kept and refilled rather than destroyed and rebuilt.
	The list is SlotCount long and only changes length if SlotKeys does, so a
	rebuild is a fill - which also means a hover survives one, instead of the
	card under the cursor going flat every time the server pushes.
]]
function AbilityPanel:_rebuild()
	self:_cancelDrag()

	local count = #slots

	for index = #self.cards + 1, count do
		self.cards[index] = self:_buildCard(index)
	end

	for index = #self.cards, count + 1, -1 do
		self.cards[index].button:Destroy()
		self.cards[index] = nil
	end

	local filled = 0

	for index, entry in ipairs(slots) do
		local card = self.cards[index]
		local abilityName = if type(entry.name) == "string" then entry.name else ""
		local has = abilityName ~= ""

		if has then
			filled += 1
		end

		card.slot = index
		card.filled = has
		card.gained = has and entry.gained == true
		card.rarityColor = if entry.rarity then Theme.rarityColor(entry.rarity) else nil

		card.label.Text = string.upper(tostring(entry.label or ""))

		if has then
			card.name.Text = abilityName
			card.name.TextColor3 = Theme.Color.Text
			card.rarity.Text = if entry.rarity then string.upper(entry.rarity) else ""
			card.rarity.TextColor3 = card.rarityColor or Theme.Color.TextDim
		else
			card.name.Text = EMPTY_TEXT
			card.name.TextColor3 = Theme.Color.TextFaint
			card.rarity.Text = ""
		end

		--[[
			Cancelled before the position is written, not after.

			A card dropped a moment ago is still tweening into the slot the
			CLIENT guessed at. This is the server's answer arriving, and a tween
			left running would finish after it and quietly put the card back on
			the guess.
		]]
		if card.settle then
			card.settle:Cancel()
			card.settle = nil
		end

		card.button.Position = UDim2.fromOffset(CARDS_X, (index - 1) * PITCH)
		card.button.ZIndex = 1

		-- Bumped per fill, so an earlier card's hold cannot clear the pick-out
		-- on a later ability that has only just landed in the same card.
		card.gainToken += 1

		if card.gained then
			local token = card.gainToken
			task.delay(GAIN_HOLD, function()
				if card.gainToken == token and card.gained then
					card.gained = false
					self:_refreshCard(card)
				end
			end)
		end

		self:_refreshCard(card)
	end

	self.filled = filled

	-- Worth saying as soon as there is anything to drag, but only worth
	-- mentioning REORDERING once there are two things to put in an order.
	self.hint.Visible = filled > 0
	self.hint.Text = if filled > 1 then DRAG_HINT else DRAG_HINT_ONE

	local stack = math.max(PITCH, count * PITCH - CARD_GAP)

	--[[
		The two drag targets, stacked against the cards.

		The PAIR is centred rather than the bin alone, so that adding the
		storage box below it did not shove the bin off the middle of the stack.
	]]
	--[[
		Never above the top of the panel. The pair is taller than one card, so
		centring it against a SHORT stack puts the bin off the top - and a
		CanvasGroup does not overflow, it cuts. That state is real: the panel
		rebuilds itself once in the constructor, before the server has pushed
		anything, with no slots at all.
	]]
	local column = BIN_HEIGHT * 2 + STORAGE_GAP
	local binTop = math.max(0, math.floor((stack - column) * 0.5))
	local boxTop = binTop + BIN_HEIGHT + STORAGE_GAP

	self.bin.Position = UDim2.fromOffset(BIN_X, binTop)
	self.box.Position = UDim2.fromOffset(BIN_X, boxTop)

	-- Nothing to throw away with an empty loadout, and a bin with nothing that
	-- can reach it is a control that does not work. The box stays: it is worth
	-- opening even with nothing to put in it, to see what is already in there.
	self.bin.Visible = filled > 0

	--[[
		Where a dragged card stops being binned and starts being stored: the
		middle of the gap between the two, in the ROOT's coordinates.

		Kept as a number rather than tested against the box's AbsolutePosition,
		because a drag only ever knows how far it has travelled - see pointerAt.
		Mixing the two spaces is how a drop zone ends up a topbar's height away
		from the control it is drawn under.
	]]
	self.storageSplit = binTop + BIN_HEIGHT + STORAGE_GAP * 0.5

	self:_setBinArmed(false)

	self.root.Size = UDim2.fromOffset(
		CARD_WIDTH + BIN_SIDE * 2,
		math.max(stack, binTop + column) + HINT_GAP + HINT_HEIGHT
	)
end

-- ---------------------------------------------------------------------------
-- Dragging
-- ---------------------------------------------------------------------------

--[[
	Lays every card except the dragged one out for the order the drop would
	make, so the stack opens a gap under the card in the air.

	The permutation is a MOVE, not a swap: pulling slot 3 up to slot 1 pushes 1
	and 2 down rather than sending 1 to the bottom. That is what the server does
	with the same two numbers, so what the stack shows while the card is in the
	air is what will be there when it lands.
]]
function AbilityPanel:_layoutAround(from: number, to: number)
	local order = {}
	for slot = 1, self.filled do
		order[slot] = slot
	end

	table.remove(order, from)
	table.insert(order, to, from)

	for position, slot in ipairs(order) do
		if slot ~= from then
			local card = self.cards[slot]
			if card then
				TweenService:Create(card.button, Theme.Tween.Open, {
					Position = UDim2.fromOffset(CARDS_X, (position - 1) * PITCH),
				}):Play()
			end
		end
	end
end

function AbilityPanel:_beginDrag(card, startX: number?, startY: number?)
	if self.drag or not (startX and startY) then
		return
	end

	--[[
		Nothing to pick up in an empty slot.

		ONE filled slot is enough, though. There is nowhere to reorder it to and
		the vertical clamp below works that out for itself - `reach` comes to
		zero, so the card cannot move up or down at all - but it can still be
		carried sideways into the bin, which is the only way to make room for a
		scroll when the one ability you have is not the one you want.
	]]
	if not card.filled or self.filled < 1 or not self.visible then
		return
	end

	local drag = {
		card = card,
		from = card.slot,
		target = card.slot,
		startX = startX,
		startY = startY,
		moved = false,

		-- Whether the card is far enough right that letting go would bin it.
		-- While it is, the stack stops reordering: a card on its way out is not
		-- also being put somewhere.
		binned = false,
	}
	self.drag = drag

	--[[
		Listened for globally rather than on the card.

		A pointer moving faster than the card follows it leaves the button
		behind, and a button that only hears its own input loses the drag the
		instant that happens - the classic "it drops when I move quickly".
	]]
	drag.changed = UserInputService.InputChanged:Connect(function(input)
		local x, y = pointerAt(input)
		if x and y then
			self:_dragTo(x, y)
		end
	end)

	drag.ended = UserInputService.InputEnded:Connect(function(input)
		if isPressInput(input) then
			self:_endDrag()
		end
	end)
end

function AbilityPanel:_dragTo(x: number, y: number)
	local drag = self.drag
	if not drag then
		return
	end

	local sideways = x - drag.startX
	local delta = y - drag.startY

	if not drag.moved then
		-- Either axis starts the drag. Reaching for the bin is a sideways
		-- movement, and requiring vertical travel first would make the card
		-- jump the moment it finally began.
		if math.max(math.abs(delta), math.abs(sideways)) < DRAG_THRESHOLD then
			return
		end

		drag.moved = true
		drag.card.button.ZIndex = 10
		self:_refreshCard(drag.card)
		Sounds.play("ui.click")
	end

	--[[
		Sideways travel, held between the stack and the bin.

		Clamped for the same reason the vertical is: past the bin there is
		nothing to drop onto, and the CanvasGroup would cut the card in half on
		the way out.
	]]
	local lift = math.clamp(sideways, 0, BIN_SIDE)

	--[[
		Which of the two targets the card is over.

		Sideways decides whether it has left the stack at all; height decides
		which one it has reached. Both are measured as TRAVEL from where the
		drag began, added to where the card started in the root - never against
		a control's AbsolutePosition, which is in a different screen space than
		the pointer and would put the boundary a topbar's height out. See
		pointerAt.
	]]
	local carriedTop = (drag.from - 1) * PITCH + delta
	local storing = lift >= BIN_REACH
		and (carriedTop + CARD_HEIGHT * 0.5) >= (self.storageSplit or math.huge)

	self:_setStorageArmed(storing)
	drag.storing = storing

	local binned = lift >= BIN_REACH and not storing

	if binned ~= drag.binned then
		drag.binned = binned
		Sounds.play(if binned then "ui.hover" else "ui.close")
		self:_setBinArmed(binned)

		-- Coming back off the bin puts the stack back the way the current
		-- target left it; going onto it closes the gap up again.
		self:_layoutAround(drag.from, if binned then drag.from else drag.target)
	end

	--[[
		Held inside the stack rather than allowed to follow the cursor anywhere.

		Two reasons, and either would be enough. A CanvasGroup renders its
		descendants into a buffer its own size, so a card carried past the top
		of the panel is not merely off the list, it is cut in half. And there is
		nowhere outside the stack for it to go: this is a reorder, not a drag to
		discard, and a card that can be lifted somewhere it cannot be dropped is
		a card that lies about what happens when you let go.
	]]
	local reach = math.max(0, self.filled - 1) * PITCH
	local carried = math.clamp((drag.from - 1) * PITCH + delta, 0, reach)
	drag.card.button.Position = UDim2.fromOffset(CARDS_X + lift, carried)

	-- On its way to the bin it is not also choosing a slot. Leaving the target
	-- where it was means dragging back off the bin returns to the arrangement
	-- that was on screen before, rather than to wherever the pointer's height
	-- happens to be by then.
	if binned or storing then
		return
	end

	-- Which slot it would land in: whichever row its own top edge is nearest.
	-- Already inside the filled range, because `carried` is.
	local target = math.clamp(math.floor(carried / PITCH + 0.5) + 1, 1, self.filled)

	if target ~= drag.target then
		drag.target = target
		Sounds.play("ui.hover")
		self:_layoutAround(drag.from, target)
	end
end

-- Lights the bin up while a card is over it. Colour and opacity together,
-- because at its resting grey it has to be quiet enough to ignore.
-- Red, because binning is the one that cannot be undone.
function AbilityPanel:_setBinArmed(armed: boolean)
	if not self.drag then
		self:_setStorageArmed(false)
	end

	setSpriteArmed(self.binPixels, armed, Theme.Color.Bad)
end

-- Green against the bin's red: the two targets sit one above the other and the
-- colour is the fastest way to be sure which one a card is about to land on.
function AbilityPanel:_setStorageArmed(armed: boolean)
	setSpriteArmed(self.boxPixels, armed, Theme.Color.Good)
end

function AbilityPanel:_endDrag()
	local drag = self.drag
	if not drag then
		return
	end

	self:_disconnectDrag()
	self.drag = nil
	self:_setBinArmed(false)

	local card = drag.card
	self:_refreshCard(card)

	if not drag.moved then
		-- A click on a card, which this panel has nothing to do with. Left
		-- exactly where it was rather than treated as a drop onto itself.
		card.button.ZIndex = 1
		card.button.Position = UDim2.fromOffset(CARDS_X, (drag.from - 1) * PITCH)
		return
	end

	--[[
		Into the bin - asked about first.

		The card goes straight back into the stack while the question is up, so
		the panel is never showing a state nobody has agreed to. Only the answer
		moves anything.

		The slot is looked up AGAIN when the answer comes rather than being read
		from `drag`, because a server push can rebuild the whole panel while the
		dialog is open. What was slot 2 when the drag started may be a different
		ability by the time the player says yes, and dropping that one would be
		this feature doing the exact thing it exists to prevent.
	]]
 if drag.storing then
  local ability=StorageAbilityConfig.resolve(card.name.Text)
  self:_rebuild()
  self.storage.store(ability)
  return
 end
	if drag.binned then
		card.button.ZIndex = 1
		card.button.Position = UDim2.fromOffset(CARDS_X, (drag.from - 1) * PITCH)

		local name = card.name.Text

		Confirm.ask({
			title = string.format("Drop %s?", name),
			body = "It leaves your loadout. Getting it back means another scroll.",
			accept = "Drop",
			tone = "bad",
		}, function(accepted)
			if not accepted then
				return
			end

			local slot = table.find(self.cards, card)
			if not slot then
				return
			end

			self:_applyDrop(slot)

			if handlers.drop then
				handlers.drop(slot)
			end
		end)

		return
	end

	-- Settles into the gap the rest of the stack has already opened for it.
	local settle = TweenService:Create(card.button, Theme.Tween.Open, {
		Position = UDim2.fromOffset(CARDS_X, (drag.target - 1) * PITCH),
	})
	card.settle = settle

	--[[
		Still on top until it has actually landed.

		Dropped to ZIndex 1 here, it would slide UNDER every card it passes for
		the length of the settle - which is the one sixth of a second the player
		is watching most closely, because it is the answer to what their drag
		just did.
	]]
	settle.Completed:Connect(function()
		card.button.ZIndex = 1
		if card.settle == settle then
			card.settle = nil
		end
	end)

	settle:Play()

	if drag.target == drag.from then
		Sounds.play("ui.close")
		return
	end

	Sounds.play("ui.click")

	-- Before the request goes out, not after it comes back.
	self:_applyMove(drag.from, drag.target)

	if handlers.reorder then
		handlers.reorder(drag.from, drag.target)
	end
end

--[[
	Applies a move to the cards themselves, not only to where they are drawn.

	THIS IS WHAT STOPS TWO ABILITIES ENDING UP ON TOP OF EACH OTHER

	A drop moves a card optimistically and waits for the server to confirm it.
	Without this, `card.slot` still says where the card USED to be for the whole
	of that round trip, while the card is sitting somewhere else - and every
	part of the drag reads `card.slot`.

	Start a second drag inside that window and `_beginDrag` takes its origin
	from the stale slot, so the card teleports onto its neighbour the moment the
	threshold is crossed. Worse, merely CLICK inside it: the not-moved branch
	puts the card back at the stale slot, on top of the other one, and sends
	nothing - so no push comes back, no rebuild happens, and the two stay drawn
	over each other until something else changes the loadout. Closing and
	reopening the menu does not help, because showing the panel does not rebuild
	it.

	Permuting the array here keeps the one invariant everything else assumes:
	self.cards[i] is the card sitting at position i. The server still has the
	last word - its push rebuilds from scratch and overwrites this if it
	disagreed.
]]
--[[
	Takes a card out, for the same reasons and with the same caveat as
	_applyMove: the display must not disagree with `card.slot` for the length of
	a round trip, and the server still has the last word.

	The card is DESTROYED rather than hidden. _rebuild makes whatever cards it
	is short of, so if the server refuses the drop its push simply builds a new
	one - which is less state than keeping a dead card around and remembering
	that it is dead.
]]
function AbilityPanel:_applyDrop(slot: number)
	local card = table.remove(self.cards, slot)
	if not card then
		return
	end

	if card.settle then
		card.settle:Cancel()
		card.settle = nil
	end

	card.button:Destroy()

	for index, entry in ipairs(self.cards) do
		entry.slot = index
		entry.button.Position = UDim2.fromOffset(CARDS_X, (index - 1) * PITCH)
	end

	self.filled = math.max(0, self.filled - 1)
	self.hint.Visible = self.filled > 0
	self.hint.Text = if self.filled > 1 then DRAG_HINT else DRAG_HINT_ONE
	self.bin.Visible = self.filled > 0
end

function AbilityPanel:_applyMove(from: number, to: number)
	local card = table.remove(self.cards, from)
	if not card then
		return
	end

	table.insert(self.cards, to, card)

	for slot, entry in ipairs(self.cards) do
		entry.slot = slot
	end
end

function AbilityPanel:_disconnectDrag()
	local drag = self.drag
	if not drag then
		return
	end

	if drag.changed then
		drag.changed:Disconnect()
	end
	if drag.ended then
		drag.ended:Disconnect()
	end
end

--[[
	Drops a drag on the floor: the menu closed under it, or the server pushed a
	new loadout while a card was in the air.

	Every card is put back rather than only the one being carried, because the
	rest of the stack has been shuffled around to make room for it.
]]
function AbilityPanel:_cancelDrag()
	local drag = self.drag
	if not drag then
		return
	end

	self:_disconnectDrag()
	self.drag = nil
	self:_setBinArmed(false)

	drag.card.button.ZIndex = 1

	for slot, card in ipairs(self.cards) do
		-- Including any card still settling from an earlier drop, or "put back"
		-- would last exactly as long as it took that tween to finish.
		if card.settle then
			card.settle:Cancel()
			card.settle = nil
		end

		card.button.ZIndex = 1
		card.button.Position = UDim2.fromOffset(CARDS_X, (slot - 1) * PITCH)
		self:_refreshCard(card)
	end
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------

function AbilityPanel:setVisible(visible: boolean)
	visible = visible == true
	if visible == self.visible then
		return
	end
	self.visible = visible

	if self.fade then
		self.fade:Cancel()
		self.fade = nil
	end

	if visible then
		self.root.Visible = true
		self.fade = TweenService:Create(self.root, Theme.Tween.Fade, { GroupTransparency = 0 })
		self.fade:Play()
		return
	end

	self:_cancelDrag()

	-- Storage closes with the screen it lives on. Left open it is still open
	-- the next time the screen appears, which is a panel nobody asked for over
	-- the cards they did.
	self.storage.dismiss()

	local fade = TweenService:Create(self.root, Theme.Tween.Close, { GroupTransparency = 1 })
	self.fade = fade

	-- A CanvasGroup at full transparency still takes clicks; only Visible stops
	-- that, and it cannot be set until the fade has actually finished.
	fade.Completed:Connect(function(state)
		if not self.visible and state == Enum.PlaybackState.Completed then
			self.root.Visible = false
		end
	end)

	fade:Play()
end

function AbilityPanel:destroy()
	self:_cancelDrag()
	self.root:Destroy()

	if live == self then
		live = nil
	end
end

-- ---------------------------------------------------------------------------
-- The way in from outside
-- ---------------------------------------------------------------------------

--[[
	What to list. One entry per slot, in slot order:

	  label    the capitals line, already worded ("slot 1  ~  Z")
	  name     the ability's display name, or nil for an empty slot
	  rarity   its tier name, or nil
	  gained   true for the one that was just equipped

	Kept even when there is no panel to put it in, so the order in which
	PauseMenu and AbilityClient start does not decide whether the first loadout
	is drawn.
]]
function AbilityPanel.setSlots(entries: { any }?)
	slots = entries or {}

	if live then
		live:_rebuild()
	end
end

--[[
	Where a drop goes.

	  reorder(fromSlot, toSlot)   a card dropped on another slot
	  drop(slot)                  a card dropped on the bin

	Set once, at startup, by whoever owns the remotes. The panel does not care
	whether either request succeeds - see the note at the top about the push
	that follows every one of them either way.
]]
function AbilityPanel.setHandlers(next: { [string]: ((...any) -> ())? }?)
	handlers = next or {}
end

return AbilityPanel
