--[[
	Feedback

	The column of fading lines at the bottom left, and the one way to put
	something in it.

		Feedback.show("Eclipse added to slot 2 (X).", "good")
		Feedback.item("Wood", 3)       -- "+3 Wood", in the item's rarity colour
		Feedback.item("Dirt", -1)      -- "-1 Dirt"

	Tones are "good", "bad", or nothing for neutral.

	IT USED TO BE PART OF CommandFeedback

	It was a LocalScript, so it was reachable only by the remote it listened to,
	and everything else that wanted to tell the player something had to go to
	the server and come back to get a line on screen. Now the stack is here and
	that script is a listener like any other - which is what lets the inventory
	watcher and the drop projectile write to it without a round trip.

	ITEM LINES COALESCE, AND THAT IS THE WHOLE REASON THEY ARE SEPARATE

	Mining is fast. A line per block would fill a five-line column in under two
	seconds and turn a receipt into a waterfall. So repeated gains of the SAME
	item inside COALESCE_WINDOW find the line already on screen and add to it -
	"+1 Stone" becomes "+7 Stone" in place, and its hold timer restarts.

	Gains and losses of the same item coalesce together, so picking a block up
	and putting it back down again nets to nothing rather than leaving two
	contradictory lines. A total that reaches zero retires the line: nothing
	happened, and the honest report of nothing happening is silence.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local Feedback = {}

local PAD_LEFT = 16
local BOTTOM = 270
local WIDTH = 620
local LINE_HEIGHT = 20
local GAP = 2

-- How many lines stay on screen. Enough for a two-part reply plus the tail of
-- what came before it; more than this and it stops being a receipt.
local MAX_LINES = 5

local HOLD = 6
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- How long an item line stays open to being added to. Comfortably longer than
-- the gap between two swings of a pickaxe.
local COALESCE_WINDOW = 4

local gui = nil
local root = nil

-- Rises forever; only the ordering matters, and a newer line must always sort
-- below an older one.
local nextOrder = 0

local lines = {}

-- itemName -> the line currently accumulating that item, while it is open.
local openItems = {}

local function colorFor(tone: string?): Color3
	if tone == "bad" then
		return Theme.Color.Bad
	elseif tone == "good" then
		return Theme.Color.Good
	end
	return Theme.Color.Text
end

--[[
	Built on the first line rather than at require time.

	This module is in Shared and a server-side require of it - by something that
	only wanted the constants - should not reach for PlayerGui and fail.
]]
local function build()
	if gui then
		return
	end

	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "Feedback"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	root = Instance.new("Frame")
	root.Name = "Lines"
	root.AnchorPoint = Vector2.new(0, 1)
	root.Position = UDim2.new(0, PAD_LEFT, 1, -BOTTOM)
	root.Size = UDim2.fromOffset(WIDTH, MAX_LINES * (LINE_HEIGHT + GAP))
	root.BackgroundTransparency = 1
	root.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = root
end

local function retire(entry)
	local index = table.find(lines, entry)
	if index then
		table.remove(lines, index)
	end

	if entry.item and openItems[entry.item] == entry then
		openItems[entry.item] = nil
	end

	local fade = TweenService:Create(entry.label, FADE, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	fade.Completed:Connect(function()
		entry.label:Destroy()
	end)
	fade:Play()
end

--[[
	Holds a line for HOLD seconds and then fades it.

	Token-guarded, so a line that has just been added to starts its wait again
	rather than being retired by the timer the first gain set going.
]]
local function hold(entry)
	entry.token += 1
	local token = entry.token

	task.delay(HOLD, function()
		if entry.token == token and entry.label.Parent then
			retire(entry)
		end
	end)
end

local function addLine(text: string, color: Color3, itemName: string?)
	build()

	nextOrder += 1

	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.LayoutOrder = nextOrder
	label.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Body
	label.TextSize = Theme.TextSize.Small
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	label.Parent = root

	local entry = { label = label, item = itemName, total = 0, token = 0, at = os.clock() }
	table.insert(lines, entry)

	-- Push the oldest out rather than letting the column grow past its frame,
	-- where a UIListLayout would simply draw the overflow off the top.
	while #lines > MAX_LINES do
		retire(lines[1])
	end

	hold(entry)
	return entry
end

function Feedback.show(text: string, tone: string?)
	if type(text) ~= "string" or text == "" then
		return
	end

	addLine(text, colorFor(tone), nil)
end

--[[
	What an item is called and what colour it is named in.

	The rarity colour, the same one the inventory names it in - so a Legendary
	scroll arriving reads as a Legendary arriving without anybody having to
	write "rare" in the text.
]]
local function itemLook(itemName: string): (string, Color3)
	local definition = ItemDefinitions[itemName]

	local label = (definition and definition.displayName) or itemName
	local color = Theme.rarityColor(definition and definition.rarity)

	return label, color
end

--[[
	A gain or a loss. `delta` is signed; zero does nothing.

	See the note at the top for why this coalesces and Feedback.show does not.
]]
function Feedback.item(itemName: string, delta: number)
	if type(itemName) ~= "string" or itemName == "" then
		return
	end

	delta = math.floor(tonumber(delta) or 0)
	if delta == 0 then
		return
	end

	local label, color = itemLook(itemName)

	local entry = openItems[itemName]

	-- An entry that is still on screen but past its window starts a new line:
	-- adding to it would silently rewrite a total the player has already read.
	if entry and (not entry.label.Parent or os.clock() - entry.at > COALESCE_WINDOW) then
		entry = nil
	end

	if not entry then
		entry = addLine("", color, itemName)
		openItems[itemName] = entry
	end

	entry.total += delta

	if entry.total == 0 then
		-- Taken and given back. Nothing happened, and the report of nothing
		-- happening is no line at all.
		retire(entry)
		return
	end

	entry.label.Text = string.format(
		"%s%d %s", if entry.total > 0 then "+" else "", entry.total, label
	)
	entry.label.TextColor3 = color

	hold(entry)
end

return Feedback
