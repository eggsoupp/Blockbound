--[[
	LoadingScreen  (ReplicatedFirst)

	Replaces Roblox's join screen with the game's own, preloads what the first
	minute of play needs, and gets out of the way: GONE WITHIN SIX SECONDS of
	this script starting, on any device, whatever the network is doing.

	THE CLOCK
	  0.0     the screen is up, plain-coloured (nothing has to download for it)
	  ~0.1    the pixel art is in: the screen re-skins itself with PixelUI
	  ...     essentials in -> PLAY appears (Space / Enter / A / tap)
	          essentials + first pass in -> it continues on its own (a
	          first-pass job stuck for over 1 s is not waited for)
	  4.8     DEADLINE: it continues regardless of what is still loading
	  +0.2    the bar runs to full
	  +0.4    the fade; at worst gone at 5.4
	  5.8     HARD CAP: the gui is destroyed even if a tween never finished

	What loads, in which order, and how much a phone takes on: Shared.Loading.
	PreloadPlan. The queue that keeps a slow asset from holding anything up:
	Shared.Loading.PreloadQueue. Whatever is unfinished when the screen goes,
	and everything in the background tier, keeps loading afterwards with fewer
	workers.

	THE BAR NEVER STALLS OR GOES BACKWARDS
	  It shows the greater of the real progress (weight of finished jobs over
	  queued ones, essentials and first pass) and a time floor that walks to
	  90% at the deadline, smoothed, and it only ever moves forward. New work
	  joining the queue (the hotbar arriving from the server) lowers the real
	  fraction for a moment; the floor and the max keep the bar moving.

	FOR OTHER SCRIPTS
	  LocalPlayer attribute LoadingScreenDone = true once the screen is gone,
	  LoadingReport = a one-line summary of the timings.

	TESTING (attributes on this script, set in Studio before pressing Play;
	nothing in the game sets them)
	  EmulateTouch (bool), EmulateViewport (Vector2)  copied to the
	      LocalPlayer, where Shared.UI.Responsive reads them, so the screen and
	      its budgets behave as on a phone
	  TestStall (number)  one essential that takes this many seconds, to check
	      the deadline holds
	  TestStallTier (number)  put that job in tier 2 instead, which holds the
	      screen on PLAY
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local START = os.clock()
-- How long the engine had been running before this script: the join itself,
-- which nothing here controls. Reported alongside the screen's own time.
local JOIN_TIME = time()

local player = Players.LocalPlayer

local TIMING = {
	minimum = 0.9, -- never a flash: the title is up at least this long
	deadline = 4.8, -- continue whatever is still loading
	fill = 0.2, -- the bar's run to full once continuing
	fade = 0.4,
	hardCap = 5.8, -- destroyed now even if something above went wrong
	waitInventory = 2.0, -- the hotbar is essential, but the server is not
	waitCharacter = 3.0, -- revealing an empty sky is worse than a short wait
	slowJob = 1.0, -- a first-pass job running longer is not waited for
	-- Nor an essential running longer than this. Longer than slowJob because
	-- at join even a cached image can take ~2.5 s to come back.
	slowEssential = 3.0,
}

-- The bar's time floor tops out here; the last stretch is the run to full.
local FLOOR_MAX = 0.9
local REAL_MAX = 0.97

local function elapsed(): number
	return os.clock() - START
end

for _, name in ipairs({ "EmulateTouch", "EmulateViewport" }) do
	local value = script:GetAttribute(name)
	if value ~= nil then
		player:SetAttribute(name, value)
	end
end
local TEST_STALL = tonumber(script:GetAttribute("TestStall"))

-- ---------------------------------------------------------------------------
-- Colours and fonts that need no download
-- ---------------------------------------------------------------------------
-- Theme's values, repeated so the first frame can be drawn before
-- ReplicatedStorage has replicated. Theme takes over once it is here.

local rgb = Color3.fromRGB
local COLOR = {
	washTop = rgb(24, 58, 44),
	washBottom = rgb(7, 20, 14), -- Theme.Color.MenuWash
	wood = rgb(107, 64, 38),
	woodEdge = rgb(43, 24, 16),
	slot = rgb(224, 198, 144), -- the parchment slot, as on the real hotbar
	slotEdge = rgb(156, 112, 69),
	groove = rgb(46, 26, 14),
	fill = rgb(120, 220, 110), -- Theme.PixelColor.HealthFill
	onWood = rgb(246, 231, 193),
	onWoodDim = rgb(205, 178, 138),
	outline = rgb(43, 24, 16),
}

local FONT = {
	heading = Font.new("rbxasset://fonts/families/HighwayGothic.json", Enum.FontWeight.Bold),
	body = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold),
}

local TIPS = {
	desktop = {
		"Press E to open your bag.",
		"Z, X and V cast your abilities.",
		"Tab opens your quests and the bestiary.",
	},
	mobile = {
		"Tap Bag to open your inventory.",
		"Your ability buttons sit beside ATTACK.",
		"Menu opens your quests and the bestiary.",
	},
}

local STATUS = {
	interface = "Loading the interface",
	animations = "Loading animations",
	effects = "Loading effects",
	tools = "Loading tools",
	["your hotbar"] = "Loading your hotbar",
	["your wings"] = "Loading your wings",
	["your abilities"] = "Loading your abilities",
	["weapon effects"] = "Loading weapon effects",
}

-- ---------------------------------------------------------------------------
-- The screen
-- ---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- The device area: the whole screen, or the emulated phone inside it.
local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromScale(1, 1)
-- White, so the gradient below is the colour (a UIGradient multiplies).
root.BackgroundColor3 = Color3.new(1, 1, 1)
root.BorderSizePixel = 0
root.ClipsDescendants = true
root.Parent = gui

local wash = Instance.new("UIGradient")
wash.Rotation = 90
wash.Color = ColorSequence.new(COLOR.washTop, COLOR.washBottom)
wash.Parent = root

-- Blocks drifting up behind everything: cheap motion that says "alive".
local blockLayer = Instance.new("Frame")
blockLayer.Name = "Blocks"
blockLayer.BackgroundTransparency = 1
blockLayer.Size = UDim2.fromScale(1, 1)
blockLayer.ZIndex = 0
blockLayer.Parent = root

local column = Instance.new("Frame")
column.Name = "Column"
column.AnchorPoint = Vector2.new(0.5, 0.5)
column.Position = UDim2.fromScale(0.5, 0.47)
column.Size = UDim2.fromOffset(520, 345)
column.BackgroundTransparency = 1
column.ZIndex = 5
column.Parent = root

local columnScale = Instance.new("UIScale")
columnScale.Parent = column

local function text(parent: Instance, name: string, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.Text = ""
	label.Parent = parent
	return label
end

local function outline(label: TextLabel, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR.outline
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return stroke
end

-- A flat stand-in in the sprite's own colours, until the atlas is here.
local function plain(frame: GuiObject, fill: Color3, edge: Color3?, thickness: number?)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	if edge then
		local stroke = Instance.new("UIStroke")
		stroke.Name = "PlainEdge"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = edge
		stroke.Thickness = thickness or 3
		stroke.Parent = frame
	end
end

local title = text(column, "Title", FONT.heading, 60, COLOR.onWood)
title.Size = UDim2.new(1, 0, 0, 70)
title.Text = "BLOCKBOUND"
outline(title, 4)

local panel = Instance.new("ImageLabel")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 82)
panel.Size = UDim2.fromOffset(460, 176)
panel.Image = ""
plain(panel, COLOR.wood, COLOR.woodEdge, 4)
panel.Parent = column

local inner = Instance.new("Frame")
inner.Name = "Inner"
inner.BackgroundTransparency = 1
inner.Size = UDim2.fromScale(1, 1)
inner.Parent = panel

local innerPadding = Instance.new("UIPadding")
for _, side in ipairs({ "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" }) do
	innerPadding[side] = UDim.new(0, 28)
end
innerPadding.Parent = inner

-- The hotbar, filling in as its tools arrive.
local HOTBAR = 9
local SLOT = 40
local SLOT_GAP = 4

local hotbarRow = Instance.new("Frame")
hotbarRow.Name = "Hotbar"
hotbarRow.AnchorPoint = Vector2.new(0.5, 0)
hotbarRow.Position = UDim2.fromScale(0.5, 0)
hotbarRow.Size = UDim2.fromOffset(HOTBAR * SLOT + (HOTBAR - 1) * SLOT_GAP, SLOT)
hotbarRow.BackgroundTransparency = 1
hotbarRow.Parent = inner

local slots = {}
for index = 1, HOTBAR do
	local slot = Instance.new("ImageLabel")
	slot.Name = "Slot" .. index
	slot.Position = UDim2.fromOffset((index - 1) * (SLOT + SLOT_GAP), 0)
	slot.Size = UDim2.fromOffset(SLOT, SLOT)
	slot.Image = ""
	plain(slot, COLOR.slot, COLOR.slotEdge, 2)
	slot.Parent = hotbarRow

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.new(1, -12, 1, -12)
	icon.BackgroundTransparency = 1
	icon.ImageTransparency = 1
	icon.Parent = slot

	local pop = Instance.new("UIScale")
	pop.Parent = slot

	slots[index] = { frame = slot, icon = icon, pop = pop, item = nil, ready = false }
end

-- The bar: a groove and a fill, 13 texels tall at 3 pixels a texel.
local bar = Instance.new("ImageLabel")
bar.Name = "Bar"
bar.Position = UDim2.fromOffset(0, SLOT + 10)
bar.Size = UDim2.new(1, 0, 0, 39)
bar.Image = ""
plain(bar, COLOR.groove, COLOR.woodEdge, 3)
bar.Parent = inner

-- Inside the groove: 4 texels in, 3 up from the bottom (PixelUI.Grooves).
local groove = Instance.new("Frame")
groove.Name = "Groove"
groove.BackgroundTransparency = 1
groove.Position = UDim2.fromOffset(12, 12)
groove.Size = UDim2.new(1, -24, 1, -21)
groove.Parent = bar

local fill = Instance.new("ImageLabel")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.Image = ""
fill.ImageColor3 = COLOR.fill
fill.ClipsDescendants = true
fill.Visible = false
plain(fill, COLOR.fill)
fill.Parent = groove

-- A glint running along the fill, so a slow stretch still moves.
local glint = Instance.new("Frame")
glint.Name = "Glint"
glint.BackgroundColor3 = Color3.new(1, 1, 1)
glint.BackgroundTransparency = 0.72
glint.BorderSizePixel = 0
glint.Size = UDim2.new(0, 15, 1, 0)
glint.Parent = fill

local statusRow = Instance.new("Frame")
statusRow.Name = "Status"
statusRow.BackgroundTransparency = 1
statusRow.Position = UDim2.fromOffset(0, SLOT + 10 + 39 + 8)
statusRow.Size = UDim2.new(1, 0, 0, 22)
statusRow.Parent = inner

local status = text(statusRow, "Label", FONT.body, 17, COLOR.onWood)
status.Size = UDim2.fromScale(0.8, 1)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextTruncate = Enum.TextTruncate.AtEnd
status.Text = "Loading"

local percent = text(statusRow, "Percent", FONT.heading, 19, COLOR.onWood)
percent.AnchorPoint = Vector2.new(1, 0)
percent.Position = UDim2.fromScale(1, 0)
percent.Size = UDim2.fromScale(0.2, 1)
percent.TextXAlignment = Enum.TextXAlignment.Right
percent.Text = "0%"

-- PLAY goes here once the essentials are in.
local playHolder = Instance.new("Frame")
playHolder.Name = "Play"
playHolder.AnchorPoint = Vector2.new(0.5, 0)
playHolder.Position = UDim2.new(0.5, 0, 0, 82 + 176 + 16)
playHolder.Size = UDim2.fromOffset(180, 42)
playHolder.BackgroundTransparency = 1
playHolder.Parent = column

local playScale = Instance.new("UIScale")
playScale.Parent = playHolder

local hint = text(column, "Hint", FONT.body, 15, COLOR.onWoodDim)
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 0, 82 + 176 + 16 + 42 + 6)
hint.Size = UDim2.fromOffset(300, 18)
outline(hint, 1.5)

-- The tip sits at the bottom of the screen, under its own scale.
local tipHolder = Instance.new("Frame")
tipHolder.Name = "Tip"
tipHolder.AnchorPoint = Vector2.new(0.5, 1)
tipHolder.Position = UDim2.new(0.5, 0, 1, -18)
tipHolder.Size = UDim2.fromOffset(600, 24)
tipHolder.BackgroundTransparency = 1
tipHolder.ZIndex = 5
tipHolder.Parent = root

local tipScale = Instance.new("UIScale")
tipScale.Parent = tipHolder

local tip = text(tipHolder, "Label", FONT.body, 18, COLOR.onWoodDim)
tip.Size = UDim2.fromScale(1, 1)
outline(tip, 1.5)

-- ---------------------------------------------------------------------------
-- Fitting the screen
-- ---------------------------------------------------------------------------

local COLUMN_SIZE = Vector2.new(520, 345)

local function deviceArea(): Vector2
	local emulated = player:GetAttribute("EmulateViewport")
	if typeof(emulated) == "Vector2" then
		return emulated
	end
	return gui.AbsoluteSize
end

local function layout()
	local area = deviceArea()
	if area.X < 2 or area.Y < 2 then
		return
	end

	if typeof(player:GetAttribute("EmulateViewport")) == "Vector2" then
		root.Size = UDim2.fromOffset(area.X, area.Y)
	else
		root.Size = UDim2.fromScale(1, 1)
	end

	-- As big as fits with a margin, up to a size where the pixel art still
	-- looks like pixel art.
	local scale = math.min((area.X - 32) / COLUMN_SIZE.X, (area.Y - 72) / COLUMN_SIZE.Y, 1.35)
	columnScale.Scale = math.max(scale, 0.4)
	tipScale.Scale = math.clamp(scale, 0.6, 1.2)
end

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
player:GetAttributeChangedSignal("EmulateViewport"):Connect(layout)

gui.Parent = player:WaitForChild("PlayerGui")
layout()
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local device = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "mobile" else "desktop"

local queue = nil -- Shared.Loading.PreloadQueue, once Shared is here
local plan = nil
local budget = nil
local planned = false

local inventoryKnown = false
local hotbarItems = {}
local essentialsAt = nil
-- When things happened, for the report: the first time each was seen.
local marks = {}
local function mark(name: string)
	marks[name] = marks[name] or elapsed()
end
local canContinue = false

local phase = "loading" -- "loading" -> "filling" -> "fading" -> "gone"
local phaseAt = START
local finishReason = nil
local finishedAt = nil
local shown = 0
local fadeTargets = nil

local connections = {}
local unsubscribeInventory = nil

local Modules = {} -- Theme, PixelUI, ItemThumbnails once required

-- ---------------------------------------------------------------------------
-- Drifting blocks
-- ---------------------------------------------------------------------------

local BLOCK_KINDS = {
	{ body = rgb(134, 96, 62), top = rgb(106, 170, 74) }, -- grass
	{ body = rgb(134, 96, 62), top = rgb(150, 110, 72) }, -- dirt
	{ body = rgb(118, 118, 124), top = rgb(140, 140, 146) }, -- stone
	{ body = rgb(219, 201, 140), top = rgb(232, 218, 165) }, -- sand
	{ body = rgb(150, 108, 64), top = rgb(176, 132, 82) }, -- log
}

local blocks = {}
local random = Random.new()

local function respawnBlock(block, startAnywhere: boolean)
	local depth = random:NextNumber()
	block.size = math.floor(12 + depth * 24) -- far = small, slow, faint
	block.speed = 0.035 + depth * 0.05 -- screen heights a second
	block.alpha = 0.55 - depth * 0.35
	block.x = random:NextNumber(0.03, 0.97)
	block.sway = random:NextNumber(0.004, 0.012)
	block.phase = random:NextNumber(0, math.pi * 2)
	block.y = if startAnywhere then random:NextNumber(-0.05, 1.05) else 1.08

	local kind = BLOCK_KINDS[random:NextInteger(1, #BLOCK_KINDS)]
	block.frame.Size = UDim2.fromOffset(block.size, block.size)
	block.frame.BackgroundColor3 = kind.body
	block.top.BackgroundColor3 = kind.top
	block.frame.ZIndex = 1 + math.floor(depth * 3)
	block.top.ZIndex = block.frame.ZIndex
end

local function makeBlocks(count: number)
	for _, block in ipairs(blocks) do
		block.frame:Destroy()
	end
	table.clear(blocks)

	for _ = 1, count do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		local top = Instance.new("Frame")
		top.BorderSizePixel = 0
		top.Size = UDim2.fromScale(1, 0.34)
		top.Parent = frame
		frame.Parent = blockLayer

		local block = { frame = frame, top = top }
		respawnBlock(block, true)
		table.insert(blocks, block)
	end
end

makeBlocks(if device == "mobile" then 8 else 16)

local function stepBlocks(dt: number, now: number, fade: number)
	for _, block in ipairs(blocks) do
		block.y -= block.speed * dt
		if block.y < -0.08 then
			respawnBlock(block, false)
		end
		-- Fade in from the bottom edge, out towards the top.
		local edge = math.clamp(math.min((1.08 - block.y) / 0.15, block.y / 0.25), 0, 1)
		local transparency = 1 - (1 - block.alpha) * edge * (1 - fade)
		block.frame.Position = UDim2.fromScale(block.x + math.sin(now * 0.8 + block.phase) * block.sway, block.y)
		block.frame.BackgroundTransparency = transparency
		block.top.BackgroundTransparency = transparency
	end
end

-- ---------------------------------------------------------------------------
-- Skinning, once Shared is here
-- ---------------------------------------------------------------------------

local function dropPlain(frame: GuiObject)
	frame.BackgroundTransparency = 1
	local edge = frame:FindFirstChild("PlainEdge")
	if edge then
		edge:Destroy()
	end
end

local skinned = false
local function skin()
	local PixelUI = Modules.PixelUI
	if skinned or not PixelUI then
		return
	end
	skinned = true

	dropPlain(panel)
	PixelUI.apply(panel, "frame_wood")
	innerPadding.PaddingLeft = UDim.new(0, 26)
	innerPadding.PaddingRight = UDim.new(0, 26)

	for _, slot in ipairs(slots) do
		dropPlain(slot.frame)
		PixelUI.apply(slot.frame, "slot", 2)
	end

	dropPlain(bar)
	PixelUI.apply(bar, "bar_frame")

	dropPlain(fill)
	PixelUI.apply(fill, "bar_fill")
end

local fontsApplied = false
local function applyFonts()
	local Theme = Modules.Theme
	if fontsApplied or not (Theme and Theme.Fonts) then
		return
	end
	fontsApplied = true
	title.FontFace = Theme.Fonts.Heading
	percent.FontFace = Theme.Fonts.Number
	status.FontFace = Theme.Fonts.BodyBold
	hint.FontFace = Theme.Fonts.Body
	tip.FontFace = Theme.Fonts.Body
end

-- ---------------------------------------------------------------------------
-- The hotbar row
-- ---------------------------------------------------------------------------

local function toolFor(itemName: string?): Instance?
	local tools = ReplicatedStorage:FindFirstChild("Tools")
	return itemName and tools and tools:FindFirstChild(itemName) or nil
end

local function refreshHotbar()
	local ItemThumbnails = Modules.ItemThumbnails
	for index, slot in ipairs(slots) do
		local item = hotbarItems[index]
		if item ~= slot.item then
			slot.item = item
			slot.ready = false
			if ItemThumbnails then
				pcall(ItemThumbnails.bind, slot.icon, item)
			end
			slot.icon.ImageTransparency = 1
		end
	end
end

local function stepHotbar()
	if not queue then
		return
	end
	for _, slot in ipairs(slots) do
		if slot.item and not slot.ready then
			local tool = toolFor(slot.item)
			local job = tool and plan and plan:owner(tool)
			if not tool or (job and job.state == "done") then
				slot.ready = true
				slot.pop.Scale = 1.22
				TweenService:Create(slot.pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		end
		if slot.item then
			slot.icon.ImageTransparency = if slot.ready then 0 else 0.65
		end
	end
end

-- ---------------------------------------------------------------------------
-- Progress
-- ---------------------------------------------------------------------------

local function essentialsDone(): boolean
	if not (planned and queue) then
		return false
	end
	-- An essential stuck this long (an asset failing or crawling) is not
	-- waited for either; it carries on loading underneath.
	if queue:waitingOn(1, TIMING.slowEssential) > 0 then
		return false
	end
	local t = elapsed()
	if not inventoryKnown and t < TIMING.waitInventory then
		return false
	end
	if not player.Character and t < TIMING.waitCharacter then
		return false
	end
	return true
end

-- The first pass counts as done once nothing in it is still worth waiting
-- for: a job that has run this long is a failing or crawling asset, and it
-- carries on loading after the screen instead of holding it up.
local function everythingDone(): boolean
	return essentialsDone() and queue:waitingOn(2, TIMING.slowJob) == 0
end

local function targetProgress(): number
	local floor = FLOOR_MAX * math.clamp(elapsed() / TIMING.deadline, 0, 1)
	local real = 0
	if queue and planned then
		local done, total = queue:progress(2)
		if total > 0 then
			real = done / total * REAL_MAX
		end
	end
	return math.max(floor, real)
end

local lastStatusAt = 0
local function statusText(): string
	if canContinue then
		if queue and queue:remaining(2) > 0 then
			return "Ready - loading extras"
		end
		return "Ready!"
	end
	if queue and planned and queue:remaining(1) == 0 and not player.Character then
		return "Finding your spawn"
	end
	local job = queue and queue.current
	if job and job.state == "running" then
		return STATUS[job.label] or ("Loading " .. tostring(job.label))
	end
	return "Loading"
end

local function setProgress(value: number)
	shown = math.clamp(value, shown, 1)
	fill.Visible = shown > 0.005
	fill.Size = UDim2.fromScale(shown, 1)
	percent.Text = string.format("%d%%", math.floor(shown * 100 + 0.5))
end

-- ---------------------------------------------------------------------------
-- Continuing
-- ---------------------------------------------------------------------------

-- The engine's own download queue, shared with every other script: how
-- crowded it got while the screen was up. And the longest frame, since a
-- main thread busy with start-up delays every PreloadAsync's return.
local engineQueuePeak = 0
local longestFrame = 0
local frames = 0
local gameLoadedAt = if game:IsLoaded() then 0 else nil
if not gameLoadedAt then
	task.spawn(function()
		game.Loaded:Wait()
		gameLoadedAt = elapsed()
	end)
end

-- The three slowest jobs so far, finished or not: what to look at when the
-- deadline is what ended the screen.
local function slowest(): string
	if not queue then
		return ""
	end
	local now = os.clock()
	local list = {}
	for _, job in pairs(queue.jobs) do
		if job.startedAt then
			table.insert(list, { job = job, took = (job.finishedAt or now) - job.startedAt })
		end
	end
	table.sort(list, function(a, b)
		return a.took > b.took
	end)
	local parts = {}
	local first = math.huge
	for _, job in pairs(queue.jobs) do
		if job.finishedAt then
			first = math.min(first, job.finishedAt - START)
		end
	end
	if first < math.huge then
		table.insert(parts, string.format("firstDone %.2fs", first))
	end
	for index = 1, math.min(3, #list) do
		local job = list[index].job
		local key = if typeof(job.key) == "Instance" then job.key.Name else string.sub(tostring(job.key), 1, 36)
		table.insert(parts, string.format("%s %.2fs%s", key, list[index].took, if job.state == "done" then "" else "+"))
	end
	return table.concat(parts, ", ")
end

local function report(): string
	local done, total, doneJobs, jobs = 0, 0, 0, 0
	local deferred = 0
	if queue then
		done, total, doneJobs, jobs = queue:progress(2)
		deferred = jobs - doneJobs
	end
	return string.format(
		"device=%s join=%.2fs essentials=%s finish=%.2fs(%s) gone=%.2fs screenJobs=%d/%d deferred=%d assetsOk=%d failed=%d engineQueuePeak=%d gameLoaded=%s frames=%d longestFrame=%.0fms marks=[%s] slowest=[%s]",
		device,
		JOIN_TIME,
		if essentialsAt then string.format("%.2fs", essentialsAt) else "never",
		finishedAt or -1,
		tostring(finishReason),
		elapsed(),
		doneJobs,
		jobs,
		deferred,
		queue and queue.loaded or 0,
		queue and queue.failed or 0,
		engineQueuePeak,
		if gameLoadedAt then string.format("%.2fs", gameLoadedAt) else "no",
		frames,
		longestFrame * 1000,
		(function()
			local parts = {}
			for _, name in ipairs({ "inventory", "character", "loadout", "firstPass" }) do
				if marks[name] then
					table.insert(parts, string.format("%s %.2fs", name, marks[name]))
				end
			end
			return table.concat(parts, ", ")
		end)(),
		slowest()
	)
end

local backgroundStarted = false
local function startBackground()
	if backgroundStarted or not (queue and plan and planned) then
		return
	end
	backgroundStarted = true

	queue:setWorkers(budget.backgroundWorkers)
	queue:setReserve(0)
	plan:background()
	queue:setMaxTier(3)

	print(string.format("[LoadingScreen] background: %d jobs left to load", queue:remaining(3)))

	local watch
	watch = queue.Progressed:Connect(function()
		if queue:remaining(3) == 0 then
			watch:Disconnect()
			print(string.format(
				"[LoadingScreen] background finished %.2fs after start: %d assets ok, %d failed",
				elapsed(),
				queue.loaded,
				queue.failed
			))
		end
	end)
end

local function gone()
	if phase == "gone" then
		return
	end
	phase = "gone"

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	if unsubscribeInventory then
		unsubscribeInventory()
	end
	gui:Destroy()

	local line = report()
	player:SetAttribute("LoadingReport", line)
	player:SetAttribute("LoadingScreenDone", true)
	print("[LoadingScreen] " .. line)

	startBackground()
end

local function proceed(reason: string)
	if phase ~= "loading" then
		return
	end
	phase = "filling"
	phaseAt = os.clock()
	finishReason = reason
	finishedAt = elapsed()
	canContinue = false
end

-- Every visible transparency on the screen, so the fade can take them all
-- to 1 together. The drifting blocks fade themselves.
local function collectFade()
	local targets = {}
	local function add(object, property)
		table.insert(targets, { object, property, object[property] })
	end
	for _, object in ipairs(column:GetDescendants()) do
		if object:IsA("GuiObject") then
			add(object, "BackgroundTransparency")
			if object:IsA("ImageLabel") or object:IsA("ImageButton") then
				add(object, "ImageTransparency")
			elseif object:IsA("TextLabel") or object:IsA("TextButton") then
				add(object, "TextTransparency")
			end
		elseif object:IsA("UIStroke") then
			add(object, "Transparency")
		end
	end
	for _, object in ipairs(tipHolder:GetDescendants()) do
		if object:IsA("TextLabel") then
			add(object, "TextTransparency")
		elseif object:IsA("UIStroke") then
			add(object, "Transparency")
		end
	end
	add(root, "BackgroundTransparency")
	return targets
end

local playButton = nil
local function showPlay()
	if canContinue or phase ~= "loading" then
		return
	end
	canContinue = true
	essentialsAt = essentialsAt or elapsed()
	-- The worker held back for late essentials has nothing left to wait for.
	if queue then
		queue:setReserve(0)
	end

	local PixelUI = Modules.PixelUI
	if PixelUI and not playButton then
		local ok, handle = pcall(PixelUI.button, playHolder, {
			name = "PlayButton",
			color = "green",
			text = "PLAY",
			textSize = 24,
			size = UDim2.fromScale(1, 1),
			onClick = function()
				proceed("player")
			end,
		})
		if ok then
			playButton = handle
		end
	end
	if not playButton then
		local button = Instance.new("TextButton")
		button.Name = "PlayButton"
		button.Size = UDim2.fromScale(1, 1)
		button.Text = "PLAY"
		button.FontFace = FONT.heading
		button.TextSize = 24
		button.TextColor3 = rgb(18, 48, 31)
		button.BackgroundColor3 = rgb(82, 184, 127)
		button.BorderSizePixel = 0
		button.Activated:Connect(function()
			proceed("player")
		end)
		button.Parent = playHolder
		playButton = { button = button }
	end

	playScale.Scale = 0.6
	TweenService:Create(playScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	if device == "desktop" then
		hint.Text = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "or press A" else "or press Space"
	end
end

table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not canContinue then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.Space or key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter
		or key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.ButtonStart then
		proceed("player")
	end
end))

-- ---------------------------------------------------------------------------
-- The frame loop
-- ---------------------------------------------------------------------------

local function step(dt: number)
	local now = os.clock()
	local t = now - START
	engineQueuePeak = math.max(engineQueuePeak, ContentProvider.RequestQueueSize)
	if phase == "loading" then
		frames += 1
		longestFrame = math.max(longestFrame, dt)
	end

	-- Alive: the title breathes, the glint runs, the blocks drift.
	title.Position = UDim2.fromOffset(0, math.sin(t * 2.2) * 3)
	glint.Position = UDim2.new((t * 0.8) % 1.5 - 0.25, 0, 0, 0)

	if phase == "loading" then
		if essentialsDone() then
			showPlay()
		end
		if player.Character then
			mark("character")
		end
		-- The last time the first pass emptied: late arrivals refill it.
		local empty = planned and queue and queue:remaining(2) == 0
		if empty and not marks.firstPassEmpty then
			marks.firstPass = elapsed()
		end
		marks.firstPassEmpty = empty
		if t >= TIMING.deadline then
			proceed("deadline")
		elseif t >= TIMING.minimum and everythingDone() then
			proceed("loaded")
		end
	end

	if phase == "loading" then
		local target = targetProgress()
		setProgress(shown + (target - shown) * (1 - math.exp(-dt * 9)))
		stepHotbar()
		if now - lastStatusAt > 0.12 then
			lastStatusAt = now
			status.Text = statusText()
		end
		stepBlocks(dt, t, 0)
	elseif phase == "filling" then
		local a = math.clamp((now - phaseAt) / TIMING.fill, 0, 1)
		setProgress(shown + (1 - shown) * a)
		status.Text = "Ready!"
		stepBlocks(dt, t, 0)
		if a >= 1 then
			phase = "fading"
			phaseAt = now
			fadeTargets = collectFade()
		end
	elseif phase == "fading" then
		local a = math.clamp((now - phaseAt) / TIMING.fade, 0, 1)
		local eased = a * a * (3 - 2 * a)
		for _, target in ipairs(fadeTargets) do
			local object, property, base = target[1], target[2], target[3]
			object[property] = base + (1 - base) * eased
		end
		columnScale.Scale *= 1 + 0.12 * dt / TIMING.fade -- a slight push in
		stepBlocks(dt, t, eased)
		if a >= 1 then
			gone()
		end
	end
end

table.insert(connections, RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(step, dt)
	if not ok then
		warn("[LoadingScreen] frame step failed, leaving now:", err)
		gone()
	end
end))

-- Independent of the frame loop: if rendering stalls, the clock still wins.
task.delay(TIMING.deadline, function()
	proceed("deadline")
end)
task.delay(TIMING.hardCap, function()
	if phase ~= "gone" then
		warn("[LoadingScreen] hard cap reached in phase " .. phase .. "; removing the screen")
		gone()
	end
end)

-- ---------------------------------------------------------------------------
-- Booting the preload, once Shared has replicated
-- ---------------------------------------------------------------------------

local function watchInventory(Shared: Instance)
	local ok, InventoryMirror = pcall(function()
		return require(Shared:WaitForChild("Inventory"):WaitForChild("InventoryMirror"))
	end)
	if not ok then
		inventoryKnown = true
		return
	end

	local function apply(snapshot)
		if phase == "gone" then
			return
		end
		inventoryKnown = true
		mark("inventory")
		plan:inventory(snapshot)
		for index = 1, HOTBAR do
			local slot = snapshot[index]
			hotbarItems[index] = if type(slot) == "table" and slot.name ~= "" then slot.name else nil
		end
		refreshHotbar()
	end

	unsubscribeInventory = InventoryMirror.onChanged(apply)
	local current = InventoryMirror.get()
	if next(current) ~= nil then
		apply(current)
	end
end

local function watchAbilities()
	local function apply()
		if phase == "gone" then
			return
		end
		local value = player:GetAttribute("AbilityLoadout")
		if type(value) == "string" and value ~= "" then
			mark("loadout")
			plan:abilities(string.split(value, ","))
		end
	end
	table.insert(connections, player:GetAttributeChangedSignal("AbilityLoadout"):Connect(apply))
	apply()
end

local function boot()
	local Shared = ReplicatedStorage:WaitForChild("Shared", TIMING.deadline)
	if not Shared then
		warn("[LoadingScreen] ReplicatedStorage.Shared did not arrive; nothing preloaded")
		return
	end

	local UI = Shared:WaitForChild("UI")
	local Loading = Shared:WaitForChild("Loading")
	local PreloadQueue = require(Loading:WaitForChild("PreloadQueue"))
	local PreloadPlan = require(Loading:WaitForChild("PreloadPlan"))
	Modules.Theme = require(UI:WaitForChild("Theme"))
	Modules.PixelUI = require(UI:WaitForChild("PixelUI"))

	device = PreloadPlan.device()
	budget = PreloadPlan.Budgets[device]
	queue = PreloadQueue.new(budget.workers)
	plan = PreloadPlan.new(queue, device)

	if device == "mobile" and #blocks > 8 then
		makeBlocks(8)
	end
	local tips = TIPS[device]
	tip.Text = tips[random:NextInteger(1, #tips)]
	if device == "mobile" then
		status.TextSize = 19
	end

	if TEST_STALL then
		queue:add({ key = "test:stall", label = "interface", holdScreen = true, run = function()
			task.wait(TEST_STALL)
		end }, tonumber(script:GetAttribute("TestStallTier")) or 1)
	end

	plan:essentials()

	-- Re-skin the moment the art is in; the fonts the same way.
	local function check()
		local atlas = Modules.Theme.Pixel and plan:owner(Modules.Theme.Pixel.Atlas)
		if not atlas or atlas.state == "done" then
			skin()
		end
		local fonts = queue:get("fonts")
		if not fonts or fonts.state == "done" then
			applyFonts()
		end
	end
	table.insert(connections, queue.Progressed:Connect(check))
	check()

	task.spawn(function()
		local ok, ItemThumbnails = pcall(function()
			return require(UI:WaitForChild("ItemThumbnails"))
		end)
		if ok then
			Modules.ItemThumbnails = ItemThumbnails
			refreshHotbar()
		end
	end)

	task.spawn(watchInventory, Shared)
	task.spawn(watchAbilities)
	plan:firstPass()
	planned = true

	-- The screen beat the boot (a very slow join): straight to background.
	if phase == "gone" then
		startBackground()
	end
end

task.spawn(function()
	local ok, err = pcall(boot)
	if not ok then
		warn("[LoadingScreen] preload did not start:", err)
		planned = true -- nothing to wait for: the screen continues on time
	end
end)
