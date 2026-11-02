--[[
	QuestWindow

	The Tab menu's QUESTS page: the quest tree from Shared.Quests.QuestBook as
	a map of nodes joined by lines, with the selected quest's story and tasks
	beside it.

		local quests = QuestWindow.new(parent, onBack)   a MenuWindow

	THE MAP. Each quest is a tile with its item's picture, placed by its `at`
	on a grid, with a line from each quest it needs. Complete quests are
	green, open ones gold and gently pulsing, locked ones dark. Drag to pan,
	scroll to zoom; it opens centred on the first open quest.

	THE SIDE PANEL. Title, state, the quest's line of flavour and its tasks
	with progress - or, while locked, what it is waiting on. Bosses nobody
	has met yet stay "???".

	Progress is drawn from QuestState; whether a quest is complete is only
	ever the server's word.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Theme = require(script.Parent:WaitForChild("Theme"))
local MenuWindow = require(script.Parent:WaitForChild("MenuWindow"))
local QuestState = require(script.Parent:WaitForChild("QuestState"))
local BestiaryState = require(script.Parent:WaitForChild("BestiaryState"))
local ItemThumbnails = require(script.Parent:WaitForChild("ItemThumbnails"))
local QuestBook = require(Shared:WaitForChild("Quests"):WaitForChild("QuestBook"))
local EnemyConfig = require(Shared:WaitForChild("Enemies"):WaitForChild("EnemyConfig"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local GOLD = Theme.PixelColor.Selection
local GREEN = Theme.Color.Good
local PALETTE = MenuWindow.Palette

local WIDTH, HEIGHT = 920, 580
local SIDE_WIDTH = 250
local NODE = 50
local ICON = 34
local COLUMN = 96
local ROW = 82
local MARGIN = 70
local LINE = 3
local ZOOM_MIN, ZOOM_MAX = 0.6, 1.3

local STATE_LOOK = {
	done = { fill = Color3.fromRGB(22, 58, 40), stroke = GREEN, icon = 0 },
	open = { fill = Color3.fromRGB(52, 42, 14), stroke = GOLD, icon = 0 },
	locked = { fill = Color3.fromRGB(16, 24, 24), stroke = Color3.fromRGB(46, 62, 60), icon = 0.65 },
}

local QuestWindow = {}

local function text(parent, font, size, color): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = ""
	label.Parent = parent
	return label
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function itemName(item: string): string
	local def = ItemDefinitions[item]
	return def and def.displayName or item
end

-- What a task says, given what the player has seen.
local function taskText(task): string
	if task.label then
		return task.label
	elseif task.item then
		return if (task.count or 1) > 1 then string.format("%s x%d", itemName(task.item), task.count) else itemName(task.item)
	elseif task.items then
		return "Any of " .. #task.items
	elseif task.kill then
		local def = EnemyConfig.Definitions[task.kill]
		local met = BestiaryState.get()[task.kill] ~= nil
		return "Defeat " .. (if met and def then def.displayName else "???")
	elseif task.discover then
		return string.format("Discover %d creatures", task.discover)
	elseif task.slay then
		return string.format("Defeat %d creatures", task.slay)
	end
	return ""
end

local function nodeCentre(quest): Vector2
	return Vector2.new(MARGIN + quest.at[1] * COLUMN, MARGIN + (quest.at[2] + 3) * ROW)
end

function QuestWindow.new(parent: Instance, onBack: () -> ())
	local window = MenuWindow.new(parent, "QUESTS", WIDTH, HEIGHT, onBack)
	local body = window.body

	-- The map: a clipped view onto a canvas that pans and zooms.
	local view = Instance.new("Frame")
	view.Name = "Map"
	view.Size = UDim2.new(1, -(SIDE_WIDTH + 14), 1, 0)
	view.BackgroundColor3 = PALETTE.Deep
	view.BorderSizePixel = 0
	view.ClipsDescendants = true
	view.Active = true
	view.Parent = body
	corner(view, UDim.new(0, 6))

	local maxColumn, minRow, maxRow = 0, 0, 0
	for _, quest in ipairs(QuestBook.Quests) do
		maxColumn = math.max(maxColumn, quest.at[1])
		minRow = math.min(minRow, quest.at[2])
		maxRow = math.max(maxRow, quest.at[2])
	end
	local canvasSize = Vector2.new(MARGIN * 2 + maxColumn * COLUMN, MARGIN * 2 + (maxRow + 3) * ROW)

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
	canvas.Parent = view

	local zoom = Instance.new("UIScale")
	zoom.Parent = canvas

	-- A faint dot grid, so panning reads as moving over something.
	local dots = Instance.new("Frame")
	dots.Name = "Grid"
	dots.BackgroundTransparency = 1
	dots.Size = UDim2.fromScale(1, 1)
	dots.Parent = canvas
	for column = 0, maxColumn do
		for row = minRow, maxRow do
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromOffset(MARGIN + column * COLUMN + COLUMN / 2, MARGIN + (row + 3) * ROW + ROW / 2)
			dot.Size = UDim2.fromOffset(2, 2)
			dot.BackgroundColor3 = PALETTE.Line
			dot.BorderSizePixel = 0
			dot.Parent = dots
		end
	end

	-- Lines first, so the nodes draw over their ends.
	local lines = {}
	for _, quest in ipairs(QuestBook.Quests) do
		for _, needId in ipairs(quest.needs) do
			local need = QuestBook.byId[needId]
			local from, to = nodeCentre(need), nodeCentre(quest)
			local delta = to - from
			local line = Instance.new("Frame")
			line.Name = needId .. ">" .. quest.id
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
			line.Size = UDim2.fromOffset(delta.Magnitude, LINE)
			line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			line.BorderSizePixel = 0
			line.Parent = canvas
			table.insert(lines, { frame = line, quest = quest, need = need })
		end
	end

	local nodes = {}
	local selected = nil
	local hovered = nil

	for _, quest in ipairs(QuestBook.Quests) do
		local centre = nodeCentre(quest)
		local isBoss = false
		for _, task in ipairs(quest.tasks) do
			isBoss = isBoss or task.kill ~= nil
		end

		local button = Instance.new("TextButton")
		button.Name = quest.id
		button.Text = ""
		button.AutoButtonColor = false
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromOffset(centre.X, centre.Y)
		button.Size = UDim2.fromOffset(NODE, NODE)
		button.BorderSizePixel = 0
		button.ZIndex = 2
		button.Parent = canvas
		-- Bosses are round; everything else is a rounded square.
		corner(button, if isBoss then UDim.new(0.5, 0) else UDim.new(0, 10))

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Parent = button

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromOffset(ICON, ICON)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 3
		icon.Parent = button
		ItemThumbnails.bind(icon, quest.icon)

		-- A small green corner once it is done.
		local tick = Instance.new("Frame")
		tick.Name = "Done"
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.new(1, -4, 1, -4)
		tick.Size = UDim2.fromOffset(14, 14)
		tick.BackgroundColor3 = GREEN
		tick.BorderSizePixel = 0
		tick.ZIndex = 4
		tick.Parent = button
		corner(tick, UDim.new(0.5, 0))
		local tickStroke = Instance.new("UIStroke")
		tickStroke.Color = PALETTE.Deep
		tickStroke.Thickness = 2
		tickStroke.Parent = tick

		local title = text(canvas, Theme.Fonts.BodyBold, 12, Theme.Color.TextDim)
		title.AnchorPoint = Vector2.new(0.5, 0)
		title.Position = UDim2.fromOffset(centre.X, centre.Y + NODE / 2 + 5)
		title.Size = UDim2.fromOffset(COLUMN - 6, 14)
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.TextWrapped = false
		title.TextScaled = true
		title.ZIndex = 2
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = 12
		fit.Parent = title
		title.Text = quest.title

		nodes[quest.id] = { quest = quest, button = button, stroke = stroke, icon = icon, tick = tick, title = title }
	end

	-- The side panel.
	local side = Instance.new("Frame")
	side.Name = "Details"
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.fromScale(1, 0)
	side.Size = UDim2.new(0, SIDE_WIDTH, 1, 0)
	side.BackgroundColor3 = PALETTE.Raised
	side.BorderSizePixel = 0
	side.Parent = body
	corner(side, UDim.new(0, 6))

	local sideIcon = Instance.new("ImageLabel")
	sideIcon.Position = UDim2.fromOffset(14, 14)
	sideIcon.Size = UDim2.fromOffset(44, 44)
	sideIcon.BackgroundTransparency = 1
	sideIcon.ScaleType = Enum.ScaleType.Fit
	sideIcon.Parent = side

	local sideState = text(side, Theme.Fonts.Heading, Theme.TextSize.Small, GOLD)
	sideState.Position = UDim2.fromOffset(68, 16)
	sideState.Size = UDim2.new(1, -82, 0, 16)

	local sideTitle = text(side, Theme.Fonts.Heading, Theme.TextSize.Subheading, Theme.Color.Text)
	sideTitle.Position = UDim2.fromOffset(68, 34)
	sideTitle.Size = UDim2.new(1, -82, 0, 40)

	local sideText = text(side, Theme.Fonts.Body, Theme.TextSize.Body, Theme.Color.TextDim)
	sideText.Position = UDim2.fromOffset(14, 80)
	sideText.Size = UDim2.new(1, -28, 0, 60)

	local tasksHeading = text(side, Theme.Fonts.Heading, Theme.TextSize.Small, Theme.Color.TextFaint)
	tasksHeading.Position = UDim2.fromOffset(14, 150)
	tasksHeading.Size = UDim2.new(1, -28, 0, 16)

	local taskList = Instance.new("Frame")
	taskList.Name = "Tasks"
	taskList.BackgroundTransparency = 1
	taskList.Position = UDim2.fromOffset(14, 172)
	taskList.Size = UDim2.new(1, -28, 1, -186)
	taskList.Parent = side

	local taskLayout = Instance.new("UIListLayout")
	taskLayout.Padding = UDim.new(0, 8)
	taskLayout.SortOrder = Enum.SortOrder.LayoutOrder
	taskLayout.Parent = taskList

	local function addRow(order: number, iconItem: string?, label: string, right: string, color: Color3)
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundColor3 = PALETTE.Deep
		row.BorderSizePixel = 0
		row.Parent = taskList
		corner(row, UDim.new(0, 4))

		local left = 8
		if iconItem then
			local image = Instance.new("ImageLabel")
			image.AnchorPoint = Vector2.new(0, 0.5)
			image.Position = UDim2.new(0, 6, 0.5, 0)
			image.Size = UDim2.fromOffset(20, 20)
			image.BackgroundTransparency = 1
			image.ScaleType = Enum.ScaleType.Fit
			image.Parent = row
			ItemThumbnails.bind(image, iconItem)
			left = 32
		end

		local name = text(row, Theme.Fonts.BodyBold, Theme.TextSize.Small, Theme.Color.Text)
		name.Position = UDim2.fromOffset(left, 0)
		name.Size = UDim2.new(1, -(left + 60), 1, 0)
		name.TextYAlignment = Enum.TextYAlignment.Center
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextWrapped = false
		name.Text = label

		local count = text(row, Theme.Fonts.BodyBold, Theme.TextSize.Small, color)
		count.AnchorPoint = Vector2.new(1, 0)
		count.Position = UDim2.new(1, -8, 0, 0)
		count.Size = UDim2.fromOffset(56, 28)
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.TextYAlignment = Enum.TextYAlignment.Center
		count.Text = right
	end

	local function showDetails(quest)
		for _, child in ipairs(taskList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		if not quest then
			ItemThumbnails.bind(sideIcon, nil)
			sideState.Text = ""
			sideTitle.Text = "Quests"
			sideText.Text = "Pick a quest on the map. Drag to look around, scroll to zoom."
			tasksHeading.Text = ""
			return
		end

		local status = QuestState.status(quest)
		ItemThumbnails.bind(sideIcon, quest.icon)
		sideIcon.ImageTransparency = if status == "locked" then 0.5 else 0
		sideTitle.Text = quest.title
		sideText.Text = quest.text
		sideState.Text = if status == "done" then "COMPLETE" elseif status == "open" then "IN PROGRESS" else "LOCKED"
		sideState.TextColor3 = if status == "done" then GREEN elseif status == "open" then GOLD else Theme.Color.TextFaint

		if status == "locked" then
			tasksHeading.Text = "NEEDS FIRST"
			for order, id in ipairs(quest.needs) do
				local need = QuestBook.byId[id]
				local needDone = QuestState.status(need) == "done"
				addRow(order, need.icon, need.title, if needDone then "DONE" else "", GREEN)
			end
			return
		end

		tasksHeading.Text = "TASKS"
		local context = QuestState.context()
		for order, task in ipairs(quest.tasks) do
			local current, needed = QuestBook.taskProgress(task, context)
			if status == "done" then
				current = needed
			end
			local iconItem = task.item or (task.items and task.items[1]) or nil
			addRow(
				order,
				iconItem,
				taskText(task),
				string.format("%d/%d", current, needed),
				if current >= needed then GREEN else Theme.Color.TextDim
			)
		end
	end

	local function paint(node)
		local status = QuestState.status(node.quest)
		local look = STATE_LOOK[status]
		local raised = node == selected or node == hovered
		node.button.BackgroundColor3 = look.fill
		node.stroke.Color = if raised and status == "locked" then Theme.Color.TextDim else look.stroke
		node.stroke.Thickness = if node == selected then 3 else 2
		node.icon.ImageTransparency = look.icon
		node.tick.Visible = status == "done"
		node.title.TextColor3 = if status == "done" then GREEN
			elseif status == "open" then GOLD
			elseif raised then Theme.Color.TextDim
			else Theme.Color.TextFaint
		node.status = status
	end

	local function paintLines()
		for _, line in ipairs(lines) do
			local questStatus = QuestState.status(line.quest)
			local needDone = QuestState.status(line.need) == "done"
			if questStatus == "done" then
				line.frame.BackgroundColor3 = GREEN
				line.frame.BackgroundTransparency = 0.35
			elseif needDone then
				line.frame.BackgroundColor3 = GOLD
				line.frame.BackgroundTransparency = 0.45
			else
				line.frame.BackgroundColor3 = PALETTE.Line
				line.frame.BackgroundTransparency = 0.2
			end
		end
	end

	local function refresh()
		local count, total = QuestState.counts()
		window.subtitle.Text = string.format("%d / %d COMPLETE", count, total)
		for _, node in pairs(nodes) do
			paint(node)
		end
		paintLines()
		showDetails(selected and selected.quest)
	end

	for _, node in pairs(nodes) do
		node.button.MouseEnter:Connect(function()
			hovered = node
			paint(node)
			Sounds.play("ui.hover")
		end)
		node.button.MouseLeave:Connect(function()
			if hovered == node then
				hovered = nil
			end
			paint(node)
		end)
		node.button.Activated:Connect(function()
			local was = selected
			selected = node
			if was then
				paint(was)
			end
			paint(node)
			showDetails(node.quest)
			Sounds.play("ui.click")
		end)
	end

	-- Panning and zooming.
	local offset = Vector2.zero

	local function clampOffset()
		local scaled = canvasSize * zoom.Scale
		local viewSize = view.AbsoluteSize / math.max(window.scale.Scale, 0.01)
		local minX = math.min(0, viewSize.X - scaled.X - 20)
		local minY = math.min(0, viewSize.Y - scaled.Y - 20)
		offset = Vector2.new(math.clamp(offset.X, minX, 20), math.clamp(offset.Y, minY, 20))
		canvas.Position = UDim2.fromOffset(offset.X, offset.Y)
	end

	local function centreOn(quest)
		local viewSize = view.AbsoluteSize / math.max(window.scale.Scale, 0.01)
		local point = nodeCentre(quest) * zoom.Scale
		offset = viewSize / 2 - point
		clampOffset()
	end

	local dragging = nil
	view.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = { from = Vector2.new(input.Position.X, input.Position.Y), start = offset, input = input }
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement or (kind == Enum.UserInputType.Touch and input == dragging.input) then
			local moved = (Vector2.new(input.Position.X, input.Position.Y) - dragging.from) / math.max(window.scale.Scale, 0.01)
			offset = dragging.start + moved
			clampOffset()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = nil
		end
	end)
	view.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		-- Zoom about the middle of the view, so what is looked at stays put.
		local viewSize = view.AbsoluteSize / math.max(window.scale.Scale, 0.01)
		local middle = (viewSize / 2 - offset) / zoom.Scale
		zoom.Scale = math.clamp(zoom.Scale + input.Position.Z * 0.1, ZOOM_MIN, ZOOM_MAX)
		offset = viewSize / 2 - middle * zoom.Scale
		clampOffset()
	end)

	-- Open quests breathe, so the eye finds the way on.
	local pulse = nil
	local function setPulsing(on: boolean)
		if pulse then
			pulse:Disconnect()
			pulse = nil
		end
		if not on then
			return
		end
		pulse = RunService.RenderStepped:Connect(function()
			local glow = 0.5 + 0.5 * math.sin(os.clock() * 3)
			for _, node in pairs(nodes) do
				if node.status == "open" and node ~= selected then
					node.stroke.Transparency = glow * 0.6
				else
					node.stroke.Transparency = 0
				end
			end
		end)
	end

	QuestState.Changed:Connect(refresh)
	BestiaryState.Changed:Connect(refresh)
	showDetails(nil)
	refresh()

	local show = window.setVisible
	function window:setVisible(visible: boolean)
		if visible then
			refresh()
			local focus = QuestState.focus()
			if focus and nodes[focus.id] then
				selected = nodes[focus.id]
				refresh()
			end
			-- After the window has a size to centre in.
			task.defer(function()
				centreOn(if focus then focus else QuestBook.Quests[1])
			end)
		end
		setPulsing(visible)
		show(self, visible)
	end

	return window
end

return QuestWindow
