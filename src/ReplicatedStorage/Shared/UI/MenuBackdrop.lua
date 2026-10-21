--[[
	MenuBackdrop

	The art behind the Tab menu: a slowly turning wireframe icosahedron drawn as
	flat UI, long light streaks crossing it, a glint at its centre and a faint
	starfield, over a green wash on the blurred world.

		local art = MenuBackdrop.new(someFrame)
		art:setVisible(true)   -- fades in
		art:setVisible(false)  -- fades out, then stops updating
		art:destroy()

		MenuBackdrop.flourish("Legendary")  -- throws it outward in that colour

	THE FLOURISH

	Equipping an ability throws the solid outward, flashes it, and turns it the
	colour of that ability's rarity for a couple of seconds.

		MenuBackdrop.flourish("Legendary")

	No text. The loadout is LISTED over this by Shared.UI.AbilityPanel, which is
	up the whole time the menu is - so the backdrop's job is the reaction, not
	the readout. It used to draw the list itself, and once the panel became
	permanent that was the same three names printed twice in the same place.

	It is a flourish on a screen the player is already looking at: /add is typed
	with this menu open, because that is the only time chat is visible. With the
	menu closed nothing plays, and the CommandFeedback line is what tells them.

	IT IS UI, NOT A MODEL

	No ViewportFrame and no parts. Every edge is a Frame a couple of pixels
	tall, rotated to its angle - the projection from 3D to the screen is done
	here, in about fifteen lines. That means the lines are exactly the weight
	asked for at any resolution rather than whatever a 3D camera happens to
	render a thin part as, the colour is exactly the colour asked for with no
	lighting in the way, and the whole thing sizes off screen height like the
	rest of the interface.

	The shape is still genuinely three-dimensional and genuinely rotating. Only
	the drawing is flat.

	SCALE

	The solid spans getting on for two thirds of the screen's height and the
	streaks run a third again past that. All of it is proportional to screen
	height, so it frames the same way on any monitor, and the streaks and the
	glint are written as multiples of the solid rather than as their own
	fractions - so resizing the art is one number, SHAPE_SPAN.

	The lines are thin but they are NOT hairlines. See EDGE_THICKNESS.

	THE GEOMETRY IS DERIVED, NOT TYPED OUT

	An icosahedron's twelve vertices are the cyclic permutations of (0, +-1,
	+-phi). Its thirty edges are then just the vertex pairs at the shortest
	distance - worth computing rather than listing, because a hand-copied edge
	table with one wrong pair is invisible in review and obvious on screen.

	Every edge is drawn, front and back, which is what gives the web of chords
	inside the silhouette. Depth is carried by brightness instead: the far side
	is dimmer than the near one.

	IT ONLY COSTS ANYTHING WHILE IT IS UP

	The render connection is made on the way in and dropped once the fade out
	has finished, so a closed menu is not animating. One eased alpha drives
	every transparency, which is why there are no tweens to cancel and no
	half-faded state to recover from if the menu is toggled fast.

	THE SAME SOLID IS ALSO THE TUTORIAL GUIDE

		local guide = MenuBackdrop.new(smallSquareFrame, { look = "guide" })
		guide:burst(nil, 0.5)  -- a gentle attention pulse

	Shared.UI.TutorialPanel puts a small copy of this on the gameplay HUD, so
	the shape the player meets behind the Tab menu is the one that talks to
	them. It is the same geometry, projection, drift and burst; what differs is
	a LOOK - how much of its host the solid fills, no wash and no starfield,
	fewer streaks, a smaller glint and a shorter throw - and those are the only
	things LOOKS parameterises. Everything else stays a module constant, so the
	menu's art is untouched by the guide existing.

	A guide instance never becomes `live` (below): MenuBackdrop.flourish is for
	the one behind the Tab menu, and an equipped ability must not set off the
	HUD copy as well.
]]

local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("Theme"))

--[[
	Set true and reopen the menu.

	Once a second it prints what the art actually IS rather than what it was
	asked to be: whether the render loop is running, how far the solid has
	turned, and - the part that matters - the measured position, size and
	transparency of a real edge on the real screen.

	It is here because "I cannot see it" and "it does not spin" are the same
	sentence from the outside and different bugs underneath, and no amount of
	reading the file distinguishes them. If spin climbs and the edge is where it
	should be at the transparency it should be, the art is fine and something is
	drawn over it. If spin is stuck, the loop is not running. If the edge has no
	size, the projection is.
]]
local DEBUG = false
local DEBUG_PERIOD = 1

local MenuBackdrop = {}
MenuBackdrop.__index = MenuBackdrop

--[[
	The one that exists.

	There is exactly one pause backdrop, PauseMenu owns it, and the thing that
	wants to set it off - AbilityClient, when the loadout gains an entry - has
	no reference to it and no business being handed one. A module level pointer
	is the smallest honest answer to that; the alternative is threading the
	instance through two scripts that otherwise have nothing to do with each
	other. Shared.UI.AbilityPanel does the same for the same reason.
]]
local live = nil

-- ---------------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------------

--[[
	How much of the screen's HEIGHT the solid spans, and then the streaks and
	the glint as multiples of the solid.

	The two multiples are the reference's own proportions and are the reason
	they are not written as fractions of the screen: change SHAPE_SPAN and the
	whole composition scales with it instead of the solid growing out of a
	streak field that stayed where it was.
]]
local SHAPE_SPAN = 0.64
local STREAK_SPAN = SHAPE_SPAN * 1.35
local GLINT_SPAN = SHAPE_SPAN * 0.42

--[[
	Transparency at FULL visibility.

	IT USED TO BE MUCH DIMMER, AND THAT WAS A MISTAKE

	The reference image is a video still, on a phone, of an almost black screen
	with a handful of pale lines on it - so these were set to match: near edges
	at 0.46, far edges at 0.93, which is to say the back half of the solid was
	seven per cent there. On an actual monitor, over a BLURRED DAYLIT WORLD
	rather than the reference's black, that is not subtle, it is absent. The
	only time the shape could be seen at all was mid-flourish, when the burst's
	flare multiplies all of this by two and drives the near edges opaque.

	These are what it looks like during that flourish, near enough: the solid is
	legible at rest, and the burst now reads as the far side coming UP to meet
	the near one rather than as the whole thing switching on.

	The wash is still the darkest of them. It goes UNDER everything and over
	PauseMenu's own black dim, and darkening it is half of what gives the pale
	lines something to be pale against.
]]
local WASH_TRANSPARENCY = 0.2

-- The near and far ends of the depth fade on the wireframe. The gap between
-- them is what reads as three dimensions without any shading, and it is the
-- gap that matters rather than either end - so both came up together.
local EDGE_NEAR_TRANSPARENCY = 0.12
local EDGE_FAR_TRANSPARENCY = 0.68
local VERTEX_TRANSPARENCY = 0.05

local STREAK_TRANSPARENCY = 0.52
local STAR_TRANSPARENCY = 0.78

-- The glint is the one thing allowed to be bright, because in the reference it
-- is the only thing that is.
local GLINT_TRANSPARENCY = 0.22
local HALO_TRANSPARENCY = 0.85

--[[
	Pixels, and offset rather than scale so a line is the same weight on any
	monitor instead of thickening with the window.

	Two, not one. One is a single DEVICE pixel: correct on the 1080p monitor
	this was written against and very nearly invisible on anything with a higher
	density, which is most things. Two is still a thin line and is one you can
	actually see.
]]
local EDGE_THICKNESS = 2
local STREAK_THICKNESS = 2
local VERTEX_SIZE = 5

-- The four-point star at the middle, in the same pixels. Up with everything
-- else: it was the one thing already bright enough to see, and leaving it
-- alone would have left it looking like a speck on a much bigger solid.
local GLINT_ARM_THICKNESS = 2
local GLINT_HALO_SIZE = 34
local GLINT_CORE_SIZE = 10

local STREAK_COUNT = 7
local STAR_COUNT = 46

--[[
	The projection.

	VIEW_DEPTH is how far the eye sits from the middle of the solid and FOCAL
	converts what is left into screen fractions, both in the solid's own units
	where its vertices are one unit out. Their ratio is the strength of the
	perspective: these two are close enough that the near face is only about a
	third larger than the far one, which is the nearly-flat look of the
	reference. Shrinking VIEW_DEPTH exaggerates it.
]]
local VIEW_DEPTH = 8
local FOCAL = 4

--[[
	Radians per second, and the size of the pitch sway.

	This wants to read as drifting rather than spinning, which it did not: 0.19
	is a full turn in THIRTY-THREE SECONDS, and on lines you could barely see in
	the first place that is indistinguishable from a still image. The only time
	the solid visibly moved was mid-flourish, when BURST_SPIN adds twenty times
	this to it.

	0.55 is a turn in eleven seconds. Still a drift - nothing in the menu is
	asking to be watched - but a drift you can tell is happening.
]]
local YAW_SPEED = 0.55
local PITCH_SPEED = 0.32
local PITCH_SWAY = 0.6

-- Degrees per second, against the shape so the two do not appear locked. Also
-- raised, and by more than the yaw was, so they stay obviously unrelated.
local STREAK_SPEED = -6

-- Radians per second of the glint's breathing, and how much of its brightness
-- that takes.
local GLINT_SPEED = 1.7
local GLINT_DEPTH = 0.3

--[[
	How fast the fade settles. Higher is snappier; 9 lands in about a quarter
	second, matching Theme.Tween.Fade.

	Out is deliberately much faster than in. The caller is free to disable the
	ScreenGui once ITS own fade finishes, and art still visible at that moment
	would not fade at all, it would vanish.
]]
local FADE_IN_SPEED = 9
local FADE_OUT_SPEED = 24

-- Fixed, so the starfield is the same every time the menu opens rather than
-- reshuffling itself behind the player's back.
local STAR_SEED = 20260904

--[[
	The flourish that plays when an ability is equipped.

	Two envelopes off one clock, which starts at zero on each flourish:
	BURST is how far the solid throws itself outward and how hard everything
	flashes, TINT is how much of the equipped rarity's colour it is wearing.
	One clock, so the punch, the flash and the colour cannot drift out of step.

	THE BURST IS A STRUCK SPRING, NOT A DECAY

	It used to be a single value snapped to 1 and decayed exponentially, which
	is a shape that can only ever grow and sag back. This reaches full extension
	in ATTACK, swings back THROUGH its resting size into a recoil about a fifth
	as deep, and settles at exactly zero. The overshoot is most of what makes it
	read as a hit rather than a grow, and it costs one cosine.

	EXPAND is the size of the throw as a fraction of the solid's resting span.
	It has come DOWN twice now while the throw itself has stayed the same size,
	because SHAPE_SPAN has gone up twice: 0.40 of today's solid is 0.256 of the
	screen's height, which is what 0.75 of the original one was. The throw is
	the same distance, it is just a smaller fraction of a much bigger shape -
	and it peaks at about nine tenths of the screen rather than off the top.

	SPIN is extra yaw velocity, radians per second at full extension. It whips
	the solid through about 180 degrees over the life of the burst against the
	64 it would drift through on its own, so a flourish is still visibly a
	different motion now that the resting drift is something you can see.

	GLOW is how much brighter everything gets, and it reads only the positive
	half of the swing: the recoil pulls the solid in, it does not dim the
	screen. It does less work than it used to - the near edges now rest close
	enough to opaque that there is little headroom left in them - so most of
	what a flourish reads as is the throw, the spin, and the far side of the
	solid coming up to meet the near one.
]]
local BURST_ATTACK = 0.14
local BURST_RELEASE = 1.9
local BURST_BOUNCE = 1.6
local BURST_EXPAND = 0.40
local BURST_SPIN = 5
local BURST_GLOW = 1.1

--[[
	How long the rarity's colour stays on the solid, and how long it takes to
	drain out. The hold covers the whole of the burst with time to spare, so the
	colour is still at full while the shape is still moving and the player never
	sees the two finish separately.

	The streaks take only part of it. They are the field the solid sits in
	rather than the solid itself, and carrying them the whole way turns "the
	wireframe went gold" into "the screen went gold", which is a different and
	much cheaper effect.
]]
local TINT_HOLD = 2
local TINT_RELEASE = 1.1
local STREAK_TINT = 0.5

-- The clock runs until BOTH envelopes are done with it, then stops.
local FLOURISH_LIFE = math.max(BURST_ATTACK + BURST_RELEASE, TINT_HOLD + TINT_RELEASE)

-- The shape also grows a little as the menu opens, from this up to full size.
local OPEN_SCALE = 0.94

--[[
	What differs between the art behind the Tab menu and the small guide on the
	HUD. `menu` is exactly the numbers above, so MenuBackdrop.new(parent) draws
	what it always has; `guide` is the same solid sized to fill a small square
	host instead of the screen.

	  shapeSpan / streakSpan / glintSpan  fractions of the host's HEIGHT
	  wash          the green wash's transparency; 1 is none at all
	  stars         how many in the starfield; 0 builds none
	  streaks       how many light streaks
	  burstExpand   how far a burst throws the solid, as a fraction of its span
	  openScale     the size it grows in from, as a fraction of full size
	  clips         whether the host clips the art. The menu's does, because its
	                streaks run past the solid and the screen edge is the frame;
	                the guide's must not, because its host IS the solid's size
	                and a burst or a streak is meant to reach past it.
	  haloSize / coreSize / vertexSize   pixels, see the menu values above

	The guide's shape span is below 1 because the projection lands a unit vertex
	about half the field out on the far side and nearer six tenths on the near
	side: the solid's silhouette is wider than its field, so 0.82 of the host
	fills most of it and a burst still has somewhere to go.
]]
local LOOKS = {
	menu = {
		shapeSpan = SHAPE_SPAN,
		streakSpan = STREAK_SPAN,
		glintSpan = GLINT_SPAN,
		wash = WASH_TRANSPARENCY,
		stars = STAR_COUNT,
		streaks = STREAK_COUNT,
		burstExpand = BURST_EXPAND,
		openScale = OPEN_SCALE,
		clips = true,
		haloSize = GLINT_HALO_SIZE,
		coreSize = GLINT_CORE_SIZE,
		vertexSize = VERTEX_SIZE,
	},
	guide = {
		shapeSpan = 0.82,
		streakSpan = 1.15,
		glintSpan = 0.36,
		wash = 1,
		stars = 0,
		streaks = 4,
		burstExpand = 0.14,
		openScale = 0.7,
		clips = false,
		haloSize = 18,
		coreSize = 6,
		vertexSize = 4,
	},
}

-- ---------------------------------------------------------------------------
-- Envelopes
-- ---------------------------------------------------------------------------

--[[
	The burst, against seconds since the flourish began.

	Up to 1 on an inverted cube - fast off the mark and easing into the extreme,
	which is what something thrown outward does - and then a cosine under a
	squared falloff, which carries it back through zero into the recoil and
	lands it on exactly 0 at the end of its life. Exactly, not nearly: that is
	why nothing downstream needs a threshold to decide the burst is over.
]]
local function burstEnvelope(elapsed: number): number
	if elapsed < BURST_ATTACK then
		local remaining = 1 - elapsed / BURST_ATTACK
		return 1 - remaining * remaining * remaining
	end

	local k = (elapsed - BURST_ATTACK) / BURST_RELEASE
	if k >= 1 then
		return 0
	end

	local falloff = 1 - k
	return math.cos(k * BURST_BOUNCE * math.pi) * falloff * falloff
end

--[[
	The tint, against the same clock: full through the hold, then smoothstepped
	away. Smooth at both ends of the release, so the colour neither snaps off
	nor appears to hesitate on its way out.
]]
local function tintEnvelope(elapsed: number): number
	if elapsed < TINT_HOLD then
		return 1
	end

	local k = (elapsed - TINT_HOLD) / TINT_RELEASE
	if k >= 1 then
		return 0
	end

	return 1 - k * k * (3 - 2 * k)
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

local PHI = (1 + math.sqrt(5)) / 2

-- Twelve unit vectors: (0, +-1, +-phi) and its two cyclic permutations.
local function icosahedronVertices(): { Vector3 }
	local vertices = {}

	for _, a in ipairs({ 1, -1 }) do
		for _, b in ipairs({ 1, -1 }) do
			table.insert(vertices, Vector3.new(0, a, b * PHI).Unit)
			table.insert(vertices, Vector3.new(a, b * PHI, 0).Unit)
			table.insert(vertices, Vector3.new(a * PHI, 0, b).Unit)
		end
	end

	return vertices
end

--[[
	Every pair at the shortest distance, which for this solid is exactly the
	thirty edges. The tolerance absorbs floating point only - the next distance
	up is more than half as far again, so there is no risk of catching it.

	Returned as index pairs, because the positions are recomputed every frame
	and only the pairing is fixed.
]]
local function edgesOf(vertices: { Vector3 }): { { number } }
	local shortest = math.huge
	for a = 1, #vertices do
		for b = a + 1, #vertices do
			local distance = (vertices[a] - vertices[b]).Magnitude
			if distance < shortest then
				shortest = distance
			end
		end
	end

	local limit = shortest * 1.01
	local edges = {}

	for a = 1, #vertices do
		for b = a + 1, #vertices do
			if (vertices[a] - vertices[b]).Magnitude <= limit then
				table.insert(edges, { a, b })
			end
		end
	end

	return edges
end

local VERTICES = icosahedronVertices()
local EDGES = edgesOf(VERTICES)

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

--[[
	Lays a Frame along the segment from (ax, ay) to (bx, by).

	Coordinates are fractions of the containing square, measured from its
	centre, x right and y down. The container is square - every one here is
	sized RelativeYY - so one unit means the same number of pixels on both axes
	and a length can be written as a scale on X alone.
]]
local function layLine(line: Frame, ax: number, ay: number, bx: number, by: number)
	local dx, dy = bx - ax, by - ay

	line.Position = UDim2.fromScale(0.5 + (ax + bx) * 0.5, 0.5 + (ay + by) * 0.5)
	line.Size = UDim2.new(math.sqrt(dx * dx + dy * dy), 0, 0, EDGE_THICKNESS)
	line.Rotation = math.deg(math.atan2(dy, dx))
end

local function newLine(parent: Instance, color: Color3, thickness: number): Frame
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Size = UDim2.new(0, 0, 0, thickness)
	line.BackgroundColor3 = color
	line.BackgroundTransparency = 1
	line.BorderSizePixel = 0
	line.Parent = parent
	return line
end

local function newSquare(parent: Instance, size: number, color: Color3): Frame
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(size, size)
	dot.BackgroundColor3 = color
	dot.BackgroundTransparency = 1
	dot.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	dot.Parent = parent
	return dot
end

-- A streak is brightest in the middle and gone at both ends, so it reads as
-- light passing through rather than a bar someone drew.
local function addStreakGradient(line: Frame, peak: number)
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = line
end

local function squareFrame(parent: Instance, span: number, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(span, span)
	frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
	frame.BackgroundTransparency = 1
	frame.ZIndex = zIndex
	frame.Parent = parent
	return frame
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

local function buildStars(parent: Instance, look): { Frame }
	local field = Instance.new("Frame")
	field.Name = "Stars"
	field.Size = UDim2.fromScale(1, 1)
	field.BackgroundTransparency = 1
	field.ZIndex = 1
	field.Parent = parent

	local random = Random.new(STAR_SEED)
	local stars = {}

	for _ = 1, look.stars do
		local star = newSquare(field, (if random:NextNumber() < 0.2 then 3 else 2), Theme.Color.MenuWire)
		star.Position = UDim2.fromScale(random:NextNumber(), random:NextNumber())
		star.ZIndex = 1

		-- Each keeps its own dimming on top of the shared one, so the field has
		-- depth rather than being one flat sheet of dots.
		table.insert(stars, { frame = star, dim = random:NextNumber(0.35, 1) })
	end

	return stars
end

--[[
	The long streaks.

	Deliberately irregular: a clean symmetric fan reads as a sunburst graphic,
	and the reference is a scatter of light passing through the solid at
	unrelated angles. Each one gets its own angle, length and sideways offset
	from a fixed seed, so it is a scatter that stays put.
]]
local function buildStreaks(parent: Instance, look): (Frame, { Frame })
	local field = squareFrame(parent, look.streakSpan, 2)
	field.Name = "Streaks"

	local random = Random.new(STAR_SEED + 1)
	local streaks = {}

	for index = 1, look.streaks do
		local streak = newLine(field, Theme.Color.MenuStreak, STREAK_THICKNESS)

		-- Spread over half a turn: a line and its opposite are the same line.
		local angle = (index - 1) * (180 / look.streaks) + random:NextNumber(-9, 9)
		local length = random:NextNumber(0.62, 1)
		local offset = random:NextNumber(-0.16, 0.16)

		streak.Rotation = angle
		streak.Size = UDim2.new(length, 0, 0, STREAK_THICKNESS)

		-- Pushed sideways from the centre, along its own normal, so they cross
		-- the solid instead of all meeting in one bright knot.
		local radians = math.rad(angle)
		streak.Position = UDim2.fromScale(
			0.5 - math.sin(radians) * offset,
			0.5 + math.cos(radians) * offset
		)

		addStreakGradient(streak, random:NextNumber(0, 0.45))

		table.insert(streaks, { frame = streak, dim = random:NextNumber(0.5, 1) })
	end

	return field, streaks
end

local function buildWire(parent: Instance, look): (Frame, { Frame }, { Frame })
	local field = squareFrame(parent, look.shapeSpan, 3)
	field.Name = "Wireframe"

	local lines = {}
	for _ = 1, #EDGES do
		table.insert(lines, newLine(field, Theme.Color.MenuWire, EDGE_THICKNESS))
	end

	local dots = {}
	for _ = 1, #VERTICES do
		table.insert(dots, newSquare(field, look.vertexSize, Theme.Color.MenuWire))
	end

	return field, lines, dots
end

--[[
	The four-point star at the middle.

	Two crossed streaks and a core, which is all a lens glint is. Its own square
	frame so the arms are sized off screen height like everything else.
]]
local function buildGlint(parent: Instance, look)
	local field = squareFrame(parent, look.glintSpan, 4)
	field.Name = "Glint"

	-- The arms are scaled with the field and grow with the solid; the halo and
	-- the core are in pixels and do not, so they are sized against the same
	-- monitor the thicknesses above are. A glint whose core scaled with the
	-- shape would stop being a point of light and become a disc.
	local arms = {}
	for index = 1, 2 do
		local arm = newLine(field, Theme.Color.MenuGlint, GLINT_ARM_THICKNESS)
		arm.Position = UDim2.fromScale(0.5, 0.5)
		arm.Size = UDim2.new(if index == 1 then 1 else 0.55, 0, 0, GLINT_ARM_THICKNESS)
		arm.Rotation = if index == 1 then 0 else 90
		addStreakGradient(arm, 0)
		arm.ZIndex = 4
		table.insert(arms, arm)
	end

	local halo = newSquare(field, look.haloSize, Theme.Color.MenuGlint)
	halo.Position = UDim2.fromScale(0.5, 0.5)
	halo.ZIndex = 4

	local core = newSquare(field, look.coreSize, Theme.Color.MenuGlint)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.ZIndex = 4

	-- The field comes back too: the burst resizes it alongside the wireframe,
	-- so the glint is thrown outward with the solid it sits at the middle of
	-- rather than staying put while everything around it moves.
	return { field = field, arms = arms, halo = halo, core = core }
end

-- ---------------------------------------------------------------------------
-- Instance
-- ---------------------------------------------------------------------------

--[[
	base is the transparency at full visibility; alpha 0 means fully gone.

	Clamped because the burst deliberately pushes alpha above 1 to flash
	something brighter than its resting state, and a negative transparency is
	not a brighter colour, it is undefined.
]]
local function fade(base: number, alpha: number): number
	return math.clamp(1 - (1 - base) * alpha, 0, 1)
end

--[[
	`options.look` is a key of LOOKS: "menu" (the default, and the art behind
	the Tab menu) or "guide" (the small copy the tutorial puts on the HUD).
]]
function MenuBackdrop.new(parent: Instance, options: { look: string? }?)
	local self = setmetatable({}, MenuBackdrop)

	local lookName = (options and options.look) or "menu"
	local look = LOOKS[lookName]
	assert(look, string.format("[MenuBackdrop] there is no look called %q", tostring(lookName)))
	self.look = look

	local root = Instance.new("Frame")
	root.Name = if lookName == "menu" then "MenuBackdrop" else "GuideBackdrop"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Theme.Color.MenuWash
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = look.clips
	root.Visible = false
	root.ZIndex = 1
	root.Parent = parent

	self.root = root
	self.stars = buildStars(root, look)
	self.streakField, self.streaks = buildStreaks(root, look)
	self.wireField, self.edgeLines, self.vertexDots = buildWire(root, look)
	self.glint = buildGlint(root, look)

	-- Scratch, reused every frame: the projected position of each vertex, and
	-- how far back it sits. Kept here so a frame allocates nothing.
	self.px = table.create(#VERTICES, 0)
	self.py = table.create(#VERTICES, 0)
	self.pz = table.create(#VERTICES, 0)

	self.alpha = 0
	self.target = 0
	self.appliedAlpha = -1
	self.appliedLit = -1
	self.appliedTint = -1
	self.clock = 0
	self.connection = nil

	-- See DEBUG. Behind the clock's start, so the first frame reports.
	self.reportedAt = -DEBUG_PERIOD

	--[[
		Seconds since the last flourish, or nil when nothing is playing, and the
		rarity colour it asked for. Both envelopes read the clock; see
		FLOURISH_LIFE.

		NOT NAMED `flourish`, WHICH IS A TRAP THIS FILE HAS ALREADY FALLEN INTO

		__index points at MenuBackdrop itself, so a field that is nil on the
		instance does not read as nil - it reads as whatever MenuBackdrop has
		under that name. There IS a MenuBackdrop.flourish, the module function
		callers use, so `self.flourish` was that FUNCTION from the moment the
		backdrop was built: `if self.flourish then` was always true and
		`self.flourish += deltaTime` threw on the first frame of every step,
		before anything was drawn.

		What made it hard to see is that it healed itself for about three
		seconds at a time. Announcing an ability assigned a real number to the
		field, which shadowed the function and let the whole step run - so the
		solid appeared and turned for exactly as long as the flourish lasted,
		and went back to being invisible and motionless when the clock was
		cleared to nil again.

		The rule the name now follows: no instance field may share a name with
		anything on MenuBackdrop. A nil colour is separately fine - there is no
		MenuBackdrop.tintColor for it to fall through to.
	]]
	self.flourishClock = nil
	self.tintColor = nil

	-- How hard the current burst hits, 1 being an equipped ability's. The
	-- guide's attention pulse asks for less. See burst().
	self.burstStrength = 1

	--[[
		The solid's yaw, accumulated rather than taken from the clock.

		It has to be, now that the burst adds VELOCITY to it: an angle computed
		as clock * speed would snap back to wherever the drift alone had reached
		the instant the burst stopped contributing, undoing the whole spin in
		one frame.
	]]
	self.spin = 0

	-- Only the menu's own art answers MenuBackdrop.flourish; see the header.
	if lookName == "menu" then
		live = self
	end

	return self
end

--[[
	Writes the alpha out to everything whose transparency does not otherwise
	change. The wireframe and the glint are written every frame anyway, so they
	fold the alpha in themselves.

	`flare` is the burst's extra brightness. The stars and the streaks take it
	on top of the alpha so the whole field lights up with the solid; the wash
	does not, because it goes UNDER everything and brightening it would only
	darken the world further, which is the opposite of a flash.

	Both numbers are tracked, so a frame where one moved and the other did not
	is still written. Skipped when neither has, which is the common case: with
	the fade in settled and no flourish playing there is nothing to do here.
]]
function MenuBackdrop:_applyAlpha(flare: number)
	local alpha = self.alpha
	local lit = alpha * flare

	if
		math.abs(alpha - self.appliedAlpha) < 0.002
		and math.abs(lit - self.appliedLit) < 0.002
	then
		return
	end

	self.appliedAlpha = alpha
	self.appliedLit = lit

	self.root.BackgroundTransparency = fade(self.look.wash, alpha)

	for _, star in ipairs(self.stars) do
		star.frame.BackgroundTransparency = fade(STAR_TRANSPARENCY, lit * star.dim)
	end

	for _, streak in ipairs(self.streaks) do
		streak.frame.BackgroundTransparency = fade(STREAK_TRANSPARENCY, lit * streak.dim)
	end
end

--[[
	Paints the solid, its vertices and the glint towards the equipped rarity,
	and the streaks part of the way there.

	Colour is the one thing here written only when it MOVES. Fifty-odd
	BackgroundColor3 writes is not much next to a frame of anything else, but it
	is also nothing that needs doing while the tint is sitting at full or has
	been zero since the menu opened, which between them is nearly all the time.

	Lerping from each element's own resting colour rather than to a flat rarity
	colour is what keeps the glint reading as the brightest thing on screen when
	it is gold, exactly as it does when it is white.
]]
function MenuBackdrop:_applyTint(tint: number)
	if math.abs(tint - self.appliedTint) < 0.004 then
		return
	end
	self.appliedTint = tint

	-- Irrelevant at tint 0, where every lerp returns its own starting colour;
	-- named anyway so this cannot be reached with a nil to interpolate to.
	local rarity = self.tintColor or Theme.Color.MenuWire

	local wire = Theme.Color.MenuWire:Lerp(rarity, tint)
	local glint = Theme.Color.MenuGlint:Lerp(rarity, tint)
	local streak = Theme.Color.MenuStreak:Lerp(rarity, tint * STREAK_TINT)

	for _, line in ipairs(self.edgeLines) do
		line.BackgroundColor3 = wire
	end

	for _, dot in ipairs(self.vertexDots) do
		dot.BackgroundColor3 = wire
	end

	for _, arm in ipairs(self.glint.arms) do
		arm.BackgroundColor3 = glint
	end
	self.glint.halo.BackgroundColor3 = glint
	self.glint.core.BackgroundColor3 = glint

	for _, entry in ipairs(self.streaks) do
		entry.frame.BackgroundColor3 = streak
	end
end

--[[
	Turns the solid, projects it and lays every line out.

	One rotation about Y then one about X, by hand rather than through CFrame:
	twelve vertices is small enough that the matrix would cost more to build
	than to skip.

	`yaw` is handed in because it is accumulated by the caller - the burst spins
	the solid faster while it plays, which an angle derived from the clock in
	here could not express. The pitch sway has no such kick and still comes off
	the clock.
]]
function MenuBackdrop:_drawWire(yaw: number, time: number, alpha: number)
	local pitch = math.sin(time * PITCH_SPEED) * PITCH_SWAY

	local cosYaw, sinYaw = math.cos(yaw), math.sin(yaw)
	local cosPitch, sinPitch = math.cos(pitch), math.sin(pitch)

	local px, py, pz = self.px, self.py, self.pz

	for index, vertex in ipairs(VERTICES) do
		local x = vertex.X * cosYaw + vertex.Z * sinYaw
		local zYawed = vertex.Z * cosYaw - vertex.X * sinYaw

		local y = vertex.Y * cosPitch - zYawed * sinPitch
		local z = vertex.Y * sinPitch + zYawed * cosPitch

		-- Nearer vertices divide by less, so they land further out: the whole
		-- of the perspective, in one line.
		local scale = FOCAL / (VIEW_DEPTH + z)

		px[index] = x * scale
		py[index] = y * scale
		pz[index] = z
	end

	local span = EDGE_FAR_TRANSPARENCY - EDGE_NEAR_TRANSPARENCY

	for index, edge in ipairs(EDGES) do
		local a, b = edge[1], edge[2]
		local line = self.edgeLines[index]

		layLine(line, px[a], py[a], px[b], py[b])

		-- Depth by brightness. z runs -1 (nearest) to 1, so this is 0 at the
		-- front and 1 at the back.
		local depth = (pz[a] + pz[b]) * 0.25 + 0.5
		line.BackgroundTransparency = fade(EDGE_NEAR_TRANSPARENCY + span * depth, alpha)
	end

	for index, dot in ipairs(self.vertexDots) do
		dot.Position = UDim2.fromScale(0.5 + px[index], 0.5 + py[index])

		local depth = pz[index] * 0.5 + 0.5
		dot.BackgroundTransparency = fade(VERTEX_TRANSPARENCY + span * depth, alpha)
	end
end

function MenuBackdrop:_step(deltaTime: number)
	self.clock += deltaTime

	local speed = if self.target == 1 then FADE_IN_SPEED else FADE_OUT_SPEED
	self.alpha += (self.target - self.alpha) * math.min(deltaTime * speed, 1)

	-- One clock for the whole flourish, dropped the moment both envelopes have
	-- finished with it, so an idle backdrop evaluates neither of them. See
	-- new() for why it is not called `flourish`.
	local burst, tint = 0, 0
	if self.flourishClock then
		self.flourishClock += deltaTime

		if self.flourishClock >= FLOURISH_LIFE then
			self.flourishClock = nil
		else
			burst = burstEnvelope(self.flourishClock) * self.burstStrength
			tint = if self.tintColor then tintEnvelope(self.flourishClock) else 0
		end
	end

	-- Only the outward half of the swing is allowed to brighten anything. The
	-- recoil pulls the solid in; taking the light down with it would read as
	-- the screen flickering rather than as the shape breathing back.
	local punch = math.max(burst, 0)
	local flare = 1 + BURST_GLOW * punch

	self:_applyAlpha(flare)
	self:_applyTint(tint)

	if self.target == 0 and self.alpha < 0.004 then
		self.alpha = 0
		self.flourishClock = nil
		self.tintColor = nil
		self:_applyAlpha(1)

		-- Explicitly back to white: the menu can be closed mid-flourish, and a
		-- wireframe left gold would still be gold the next time it opens.
		self:_applyTint(0)

		self.root.Visible = false
		self:_disconnect()
		return
	end

	local time = self.clock
	local alpha = self.alpha

	-- Drifts under its own speed, and is whipped round on top of that for as
	-- long as the burst is throwing the shape outward.
	self.spin += deltaTime * (YAW_SPEED + BURST_SPIN * punch)

	-- Grows in as the menu opens, then is thrown outward on each flourish.
	local look = self.look
	local throw = 1 + look.burstExpand * burst
	local span = look.shapeSpan * (look.openScale + (1 - look.openScale) * alpha) * throw
	self.wireField.Size = UDim2.fromScale(span, span)

	self:_drawWire(self.spin, time, alpha * flare)

	self.streakField.Rotation = (time * STREAK_SPEED) % 360

	local pulse = 1 - GLINT_DEPTH * (0.5 + 0.5 * math.sin(time * GLINT_SPEED))
	local glintAlpha = alpha * pulse * flare
	local glint = self.glint

	-- Thrown by the same factor as the solid, so the flash at the centre grows
	-- with the shape it is the centre of.
	local glintSpan = look.glintSpan * throw
	glint.field.Size = UDim2.fromScale(glintSpan, glintSpan)

	for _, arm in ipairs(glint.arms) do
		arm.BackgroundTransparency = fade(GLINT_TRANSPARENCY, glintAlpha)
	end
	glint.halo.BackgroundTransparency = fade(HALO_TRANSPARENCY, glintAlpha)
	glint.core.BackgroundTransparency = fade(GLINT_TRANSPARENCY, glintAlpha)

	if DEBUG then
		self:_report()
	end
end

--[[
	See DEBUG at the top of the file.

	Everything is printed with %.0f rather than %d because most of these are
	floats - AbsoluteSize is - and Luau's %d refuses a number with a fractional
	part rather than rounding it. A diagnostic that throws is worse than none.
]]
function MenuBackdrop:_report()
	if self.clock - self.reportedAt < DEBUG_PERIOD then
		return
	end
	self.reportedAt = self.clock

	local edge = self.edgeLines[1]
	local gui = self.root:FindFirstAncestorWhichIsA("ScreenGui")

	print(string.format(
		"[MenuBackdrop] alpha %.2f -> %.0f | spin %.0f deg | flourish %s | solid %.0fx%.0f px",
		self.alpha, self.target, math.deg(self.spin) % 360,
		if self.flourishClock then string.format("%.2fs", self.flourishClock) else "none",
		self.wireField.AbsoluteSize.X, self.wireField.AbsoluteSize.Y
	))

	print(string.format(
		"[MenuBackdrop]   edge1 at %.0f,%.0f size %.0fx%.0f transparency %.2f | "
			.. "root visible %s %.0fx%.0f | gui %s enabled %s order %.0f",
		edge.AbsolutePosition.X, edge.AbsolutePosition.Y,
		edge.AbsoluteSize.X, edge.AbsoluteSize.Y, edge.BackgroundTransparency,
		tostring(self.root.Visible), self.root.AbsoluteSize.X, self.root.AbsoluteSize.Y,
		if gui then gui.Name else "NONE",
		if gui then tostring(gui.Enabled) else "-",
		if gui then gui.DisplayOrder else 0
	))
end

-- ---------------------------------------------------------------------------
-- The flourish
-- ---------------------------------------------------------------------------

--[[
	Throws the solid outward and turns it the given rarity's colour.

	`rarity` is a TIER NAME - "Legendary" - and not a colour, because Theme is
	the one place allowed to say which colour a tier is. nil, or a tier Theme
	does not know, still bursts; it just does not recolour, which is the honest
	result for an ability that was never given a rarity.

	Nothing happens if the menu is not up. The burst is a reaction on a screen
	the player is already looking at, and playing it to a hidden backdrop would
	only mean they missed it; the CommandFeedback line is what tells them, and
	the panel will be showing the new loadout the next time they open the menu.
]]
function MenuBackdrop:_flourish(rarity: string?, strength: number?)
	if not self.root.Visible then
		return
	end

	--[[
		Restarts both envelopes from zero, and forces the colour to be written
		even if the previous flourish left the tint sitting at full - two /adds
		inside two seconds are otherwise a second burst in the first ability's
		colour.
	]]
	self.flourishClock = 0
	self.burstStrength = strength or 1
	self.tintColor = if rarity then Theme.rarityColor(rarity) else nil
	self.appliedTint = -1
end

--[[
	The way in from outside. See `live` at the top for why this is a module
	function rather than something you call on an instance you were handed.
]]
function MenuBackdrop.flourish(rarity: string?)
	if live then
		live:_flourish(rarity)
	end
end

--[[
	The same on an instance you DO hold - the tutorial's guide, which is not
	`live` and has no rarity to show. `strength` scales the throw, the whip and
	the flare together: 1 is a full flourish, 0.5 a nod. Nothing happens while
	the art is hidden, as with the menu's.
]]
function MenuBackdrop:burst(rarity: string?, strength: number?)
	self:_flourish(rarity, strength)
end

function MenuBackdrop:_disconnect()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
end

function MenuBackdrop:setVisible(visible: boolean)
	self.target = if visible then 1 else 0

	if visible then
		self.root.Visible = true
	end

	if not self.connection then
		self.connection = RunService.RenderStepped:Connect(function(deltaTime)
			self:_step(deltaTime)
		end)
	end
end

function MenuBackdrop:destroy()
	self:_disconnect()
	self.root:Destroy()

	if live == self then
		live = nil
	end
end

return MenuBackdrop
