--[[
	TutorialMarker

	A gold arrow bobbing over whatever the tutorial wants the player to go to:
	the nearest tree, then the training slime.

		local marker = TutorialMarker.new(playerGui)
		marker:point(modelOrPart, "TREE")   -- over its top; nil hides it
		marker:destroy()

	A BillboardGui, so it is UI rather than a part in the world, drawn on top
	of everything so a tree behind a hill can still be found; when the target
	is off screen altogether, the same arrow waits at the screen's edge,
	turned toward it. The arrow is
	drawn a pixel at a time with a dark edge round it, like the Tab menu's bin,
	so it reads against sky, grass and snow alike.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local TutorialMarker = {}
TutorialMarker.__index = TutorialMarker

local ARROW = {
	"...###...",
	"...###...",
	"...###...",
	"#########",
	".#######.",
	"..#####..",
	"...###...",
	"....#....",
}

local PIXEL = 4
local EDGE = 2
local BOB = 6
local LIFT = 2

-- The most the arrow hangs above its target's base, in studs. A tree is 25
-- studs of canopy; an arrow over the very top of it sits off the top of the
-- screen once you walk up to it. This keeps it at the trunk, where you click.
local MAX_HEIGHT = 9

-- How far in from the screen's edge the off-screen arrow sits, in pixels.
local EDGE_MARGIN = 56

-- The highest it goes, as a share of the screen's height: under the hotbar
-- on the left and the tutorial card on the right.
local EDGE_TOP = 0.42

local ARROW_COLOR = Theme.PixelColor.Selection
local EDGE_COLOR = Theme.PixelColor.Outline

-- How often the arrow re-measures its target. A slime hops; a tree does not.
local REAIM = 0.2

local function drawArrow(parent: Instance): Frame
	local width = #ARROW[1] * PIXEL + EDGE * 2
	local height = #ARROW * PIXEL + EDGE * 2

	local field = Instance.new("Frame")
	field.Name = "Arrow"
	field.BackgroundTransparency = 1
	field.AnchorPoint = Vector2.new(0.5, 0)
	field.Size = UDim2.fromOffset(width, height)
	field.Parent = parent

	-- The edge first, a square a little bigger under every pixel, then the
	-- pixels over it.
	for pass = 1, 2 do
		for row, line in ipairs(ARROW) do
			for column = 1, #line do
				if string.sub(line, column, column) == "#" then
					local pixel = Instance.new("Frame")
					pixel.BorderSizePixel = 0
					if pass == 1 then
						pixel.Position = UDim2.fromOffset((column - 1) * PIXEL, (row - 1) * PIXEL)
						pixel.Size = UDim2.fromOffset(PIXEL + EDGE * 2, PIXEL + EDGE * 2)
						pixel.BackgroundColor3 = EDGE_COLOR
					else
						pixel.Position = UDim2.fromOffset((column - 1) * PIXEL + EDGE, (row - 1) * PIXEL + EDGE)
						pixel.Size = UDim2.fromOffset(PIXEL, PIXEL)
						pixel.BackgroundColor3 = ARROW_COLOR
						pixel.ZIndex = 2
					end
					pixel.Parent = field
				end
			end
		end
	end

	return field
end

-- The part to hang the billboard on, and where over it the arrow goes: the
-- top of the whole thing, or MAX_HEIGHT above its base for a tall one.
local function anchorFor(target: Instance): (BasePart?, Vector3?)
	if target:IsA("BasePart") then
		local height = math.min(target.Size.Y, MAX_HEIGHT)
		return target, target.Position + Vector3.new(0, height - target.Size.Y / 2, 0)
	end

	if target:IsA("Model") then
		local part = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
		if not part then
			return nil, nil
		end
		local ok, frame, size = pcall(target.GetBoundingBox, target)
		if not ok then
			return part, part.Position
		end
		local height = math.min(size.Y, MAX_HEIGHT)
		return part, frame.Position + Vector3.new(0, height - size.Y / 2, 0)
	end

	return nil, nil
end

function TutorialMarker.new(playerGui: Instance)
	local self = setmetatable({}, TutorialMarker)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TutorialMarker"
	billboard.ResetOnSpawn = false
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(80, 80)
	billboard.SizeOffset = Vector2.new(0, 0.5)
	billboard.Enabled = false
	billboard.Parent = playerGui

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = billboard

	local arrow = drawArrow(holder)
	arrow.Position = UDim2.new(0.5, 0, 0, 22)

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.Size = UDim2.new(1, 0, 0, 18)
	caption.FontFace = Theme.Fonts.Heading
	caption.TextSize = 16
	caption.TextColor3 = ARROW_COLOR
	caption.TextStrokeColor3 = EDGE_COLOR
	caption.TextStrokeTransparency = 0
	caption.Text = ""
	caption.Parent = holder

	-- The bob, forever, while it is shown. Paused tweens cost nothing.
	local bob = TweenService:Create(
		arrow,
		TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.new(0.5, 0, 0, 22 + BOB) }
	)

	-- Off screen - behind the camera, or past an edge - the arrow moves to the
	-- edge of the screen nearest the target and turns to point at it, so the
	-- first tree is never lost because spawning faced the other way.
	local edgeGui = Instance.new("ScreenGui")
	edgeGui.Name = "TutorialMarkerEdge"
	edgeGui.ResetOnSpawn = false
	edgeGui.IgnoreGuiInset = true
	edgeGui.DisplayOrder = 4
	edgeGui.Enabled = false
	edgeGui.Parent = playerGui

	-- A CanvasGroup, so turning it turns the pixels drawn inside it.
	local edgeArrow = Instance.new("CanvasGroup")
	edgeArrow.Name = "Edge"
	edgeArrow.BackgroundTransparency = 1
	edgeArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	edgeArrow.Size = UDim2.fromOffset(#ARROW[1] * PIXEL + EDGE * 2, #ARROW * PIXEL + EDGE * 2)
	edgeArrow.Parent = edgeGui
	drawArrow(edgeArrow).Position = UDim2.fromScale(0.5, 0)

	self.billboard = billboard
	self.caption = caption
	self.bob = bob
	self.edgeGui = edgeGui
	self.edgeArrow = edgeArrow
	self.target = nil
	self.connection = nil
	self.elapsed = 0

	return self
end

function TutorialMarker:_aim(): boolean
	local target = self.target
	if not target or not target.Parent then
		return false
	end

	local part, top = anchorFor(target)
	if not part or not top then
		return false
	end

	self.billboard.Adornee = part
	self.billboard.StudsOffsetWorldSpace = (top + Vector3.new(0, LIFT, 0)) - part.Position
	return true
end

-- Every frame while pointing: the edge arrow, if the target is off screen.
function TutorialMarker:_edge()
	local camera = workspace.CurrentCamera
	local part = self.billboard.Adornee
	if not camera or not part or not part:IsA("BasePart") then
		self.edgeGui.Enabled = false
		return
	end

	local world = part.Position + self.billboard.StudsOffsetWorldSpace
	local point, onScreen = camera:WorldToViewportPoint(world)
	if onScreen and point.Z > 0 then
		self.edgeGui.Enabled = false
		return
	end

	local size = camera.ViewportSize
	local centre = size / 2
	local direction = Vector2.new(point.X, point.Y) - centre
	-- Behind the camera the projection comes out mirrored; and "behind you"
	-- reads as the bottom of the screen, clear of the hotbar along the top.
	if point.Z < 0 then
		direction = Vector2.new(-direction.X, math.max(math.abs(direction.Y), centre.Y * 0.5))
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, 1)
	end

	-- Along the ray from the middle of the screen to the edge of the band it
	-- may sit in: the sides and the bottom, kept under EDGE_TOP so it never
	-- lands on the hotbar or the guide card up there.
	local left, right = EDGE_MARGIN, size.X - EDGE_MARGIN
	local top, bottom = size.Y * EDGE_TOP, size.Y - EDGE_MARGIN
	local reachX = if direction.X > 0
		then (right - centre.X) / direction.X
		elseif direction.X < 0 then (left - centre.X) / direction.X
		else math.huge
	local reachY = if direction.Y > 0
		then (bottom - centre.Y) / direction.Y
		elseif direction.Y < 0 then (top - centre.Y) / direction.Y
		else math.huge
	local at = centre + direction * math.min(reachX, reachY)

	self.edgeArrow.Position = UDim2.fromOffset(at.X, at.Y)
	-- Drawn pointing down, which is 90 degrees.
	self.edgeArrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) - 90
	self.edgeGui.Enabled = true
end

function TutorialMarker:point(target: Instance?, caption: string?)
	self.caption.Text = caption or ""

	if target == self.target then
		return
	end
	self.target = target

	if not target or not self:_aim() then
		self.target = nil
		self.billboard.Enabled = false
		self.billboard.Adornee = nil
		self.edgeGui.Enabled = false
		self.bob:Pause()
		if self.connection then
			self.connection:Disconnect()
			self.connection = nil
		end
		return
	end

	self.billboard.Enabled = true
	self.bob:Play()

	if not self.connection then
		self.elapsed = 0
		self.connection = RunService.RenderStepped:Connect(function(deltaTime)
			self.elapsed += deltaTime
			if self.elapsed >= REAIM then
				self.elapsed = 0
				if not self:_aim() then
					self:point(nil)
					return
				end
			end
			self:_edge()
		end)
	end
end

function TutorialMarker:destroy()
	self:point(nil)
	self.bob:Cancel()
	self.billboard:Destroy()
	self.edgeGui:Destroy()
end

return TutorialMarker