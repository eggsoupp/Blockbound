--[[
	BreakOverlay

	The cracks that spread across a block while it is being mined, the way
	Minecraft draws them: ten stages of pixel-art cracking on every face, just
	proud of the block's own surface.

		BreakOverlay.show(blockCentre, blockSize)
		BreakOverlay.setProgress(0.4)      -- 0..1, picks the stage
		BreakOverlay.hide()

	Client-side presentation only. How long a block takes and whether it breaks
	are MiningServer's; this draws whatever fraction MiningClient hands it.

	NO TEXTURE ASSET

	Minecraft's destroy stages are sixteen-by-sixteen images. This project has
	none uploaded and an invented asset id would draw nothing, so the cracks are
	built from the same sixteen-by-sixteen grid out of pixels: one Frame per
	cracked pixel on a SurfaceGui per face. Each face grows its own crack -
	a few lines walking out from near the middle, wandering and branching - and
	the order the pixels were added in IS the stage order, so stage one is a
	hairline at the centre and stage ten has reached the edges.

	BUILT ONCE

	There is one overlay, built the first time it is shown and moved from block
	to block after that. Its pixels are made once and only ever shown or hidden,
	and a stage change touches only the pixels that stage adds, so mining a
	hundred blocks costs the same instances as mining one.
]]

local BreakOverlay = {}

-- ---------------------------------------------------------------------------
-- Tuning
-- ---------------------------------------------------------------------------

local GRID = 16
local STAGES = 10

-- How far the cracks sit off the block's faces, in studs. Enough to never
-- flicker into the surface, too little to see as a gap.
local LIFT = 0.03

-- How many of a face's 256 pixels are cracked by the last stage.
local PIXELS_PER_FACE = 92

-- Canvas resolution. Comfortably more than sixteen, so each crack pixel has
-- crisp edges instead of being blurred across its neighbours.
local PIXELS_PER_STUD = 32

-- Mostly near-black cracks, with the occasional lighter chip along them, the
-- way the Minecraft textures break up their lines.
local CRACK_COLOR = Color3.fromRGB(16, 16, 18)
local CHIP_COLOR = Color3.fromRGB(120, 120, 124)
local CHIP_CHANCE = 0.14
local CRACK_ALPHA = 0.22
local CHIP_ALPHA = 0.55

-- Crack heads wander: chance per step of bending 45 degrees, and of a new
-- branch splitting off. MAX_HEADS caps how busy one face can get.
local TURN_CHANCE = 0.3
local BRANCH_CHANCE = 0.09
local START_HEADS = 3
local MAX_HEADS = 7

local PARKED = CFrame.new(0, -10000, 0)

local FACES = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
}

-- The eight neighbours, in order round the compass, so turning 45 degrees is
-- stepping one along this list.
local DIRECTIONS = {
	{ 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
	{ -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
}

-- ---------------------------------------------------------------------------
-- The crack pattern
-- ---------------------------------------------------------------------------

--[[
	One face's crack, as pixels in the order they appear. Seeded, so every
	block cracks the same way - as every Minecraft block uses the same texture -
	while each face of a block differs from the others.
]]
local function crackPattern(seed)
	local rng = Random.new(seed)
	local taken = {}
	local order = {}

	local function take(x, y)
		local key = y * GRID + x
		if taken[key] then
			return
		end
		taken[key] = true
		table.insert(order, { x, y, rng:NextNumber() < CHIP_CHANCE })
	end

	local cx, cy = rng:NextInteger(6, 9), rng:NextInteger(6, 9)
	take(cx, cy)

	local heads = {}
	for _ = 1, START_HEADS do
		table.insert(heads, { x = cx, y = cy, dir = rng:NextInteger(1, 8) })
	end

	-- A ceiling on steps, in case a seed walks itself into a corner.
	for _ = 1, PIXELS_PER_FACE * 20 do
		if #order >= PIXELS_PER_FACE then
			break
		end

		local head = heads[rng:NextInteger(1, #heads)]

		if rng:NextNumber() < TURN_CHANCE then
			head.dir = (head.dir + (if rng:NextNumber() < 0.5 then 0 else 6)) % 8 + 1
		end

		local step = DIRECTIONS[head.dir]
		local nx, ny = head.x + step[1], head.y + step[2]

		if nx < 0 or nx >= GRID or ny < 0 or ny >= GRID then
			-- Reached the edge: carry on as a branch from somewhere already
			-- cracked, so the pattern fills in rather than stopping.
			local from = order[rng:NextInteger(1, #order)]
			head.x, head.y, head.dir = from[1], from[2], rng:NextInteger(1, 8)
		else
			head.x, head.y = nx, ny
			take(nx, ny)

			if #heads < MAX_HEADS and rng:NextNumber() < BRANCH_CHANCE then
				table.insert(heads, { x = nx, y = ny, dir = rng:NextInteger(1, 8) })
			end
		end
	end

	return order
end

-- ---------------------------------------------------------------------------
-- The overlay
-- ---------------------------------------------------------------------------

local part = nil
local faces = {} -- { pixels = { Frame }, count }
local shownStage = 0
local visible = false

local function build()
	part = Instance.new("Part")
	part.Name = "BreakOverlay"
	part.Anchored = true
	part.CanCollide = false
	-- Never in the way of the mining ray or a placement check.
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Transparency = 1
	part.CFrame = PARKED
	part.Parent = workspace

	for index, face in ipairs(FACES) do
		local surface = Instance.new("SurfaceGui")
		surface.Name = face.Name
		surface.Face = face
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = PIXELS_PER_STUD
		-- Lit like the world, so cracks in a dark cave are dark too.
		surface.LightInfluence = 1
		surface.ClipsDescendants = true
		surface.Parent = part

		local pixels = {}
		for _, pixel in ipairs(crackPattern(index * 7919)) do
			local frame = Instance.new("Frame")
			frame.BorderSizePixel = 0
			frame.Size = UDim2.fromScale(1 / GRID, 1 / GRID)
			frame.Position = UDim2.fromScale(pixel[1] / GRID, pixel[2] / GRID)
			frame.BackgroundColor3 = if pixel[3] then CHIP_COLOR else CRACK_COLOR
			frame.BackgroundTransparency = if pixel[3] then CHIP_ALPHA else CRACK_ALPHA
			frame.Visible = false
			frame.Parent = surface
			table.insert(pixels, frame)
		end

		faces[index] = { pixels = pixels, count = #pixels }
	end
end

-- The last pixel index showing at `stage` on a face of `count` pixels.
local function lastIndex(stage, count)
	return math.floor(stage / STAGES * count)
end

--[[
	Shows or hides only the pixels between the current stage and the new one,
	so climbing a stage touches roughly a tenth of the overlay.
]]
local function setStage(stage)
	if stage == shownStage or not part then
		return
	end

	local from, to, show = shownStage, stage, true
	if stage < shownStage then
		from, to, show = stage, shownStage, false
	end

	for _, face in ipairs(faces) do
		for i = lastIndex(from, face.count) + 1, lastIndex(to, face.count) do
			face.pixels[i].Visible = show
		end
	end

	shownStage = stage
end

--[[
	Puts the overlay on a block, at stage nothing. `blockSize` is the block's
	edge in studs; the overlay is that plus LIFT on every side.
]]
function BreakOverlay.show(centre: Vector3, blockSize: number)
	if typeof(centre) ~= "Vector3" then
		return
	end

	if not part or not part.Parent then
		faces = {}
		shownStage = 0
		build()
	end

	setStage(0)
	part.Size = Vector3.one * (blockSize + LIFT * 2)
	part.CFrame = CFrame.new(centre)
	visible = true
end

--[[
	How far the break has got, 0..1. Any progress at all shows the first
	stage, as Minecraft's first crack appears with the first hit.
]]
function BreakOverlay.setProgress(fraction: number)
	if not visible then
		return
	end

	local stage = 0
	if fraction > 0 then
		stage = math.clamp(math.floor(fraction * STAGES) + 1, 1, STAGES)
	end
	setStage(stage)
end

function BreakOverlay.hide()
	if not visible then
		return
	end

	visible = false
	setStage(0)
	if part then
		part.CFrame = PARKED
	end
end

return BreakOverlay
