--[[
	EclipseVFX

	Draws one Eclipse, on the client.

		EclipseVFX.play(payload, scope)

	`payload` is one CFrame - where the caster was standing when the server
	accepted the cast. Everything else is read from EclipsePlan, which the
	server used to decide the damage, so the ring passes through somebody on the
	frame their health drops rather than a moment either side of it.

	THE SHAPE OF IT

	  t+0.00  GATHER. A black star opens over the caster and grows to eleven
	          studs across, white motes falling into it out of the air. Rock
	          lifts off the floor and hangs there. The world DARKENS - colour
	          and light drain out of everything the player can see, because an
	          eclipse is a light being taken away rather than one switched on.
	  t+0.08  a white ring closes on the caster across the floor from
	          twenty-four studs out, with ten spokes of light dragged inward
	          alongside it. This is the telegraph, and it is the part of this
	          that is fair to whoever is standing in it.
	  t+0.58  COLLAPSE. The star shrinks to nothing faster than it grew and
	          leaves a single white pinhole hanging in the dark.
	  t+0.58  ...and then nothing happens, for a seventh of a second. See
	          HOLD_TIME: the silence is the climax, the blast is only its
	          punchline.
	  t+0.80  DETONATION, on the frame the server applies the damage. A black
	          sphere and a white one expand together - a black disc ringed with
	          fire, which is what the ability is named after - inside a flash, a
	          hundred-and-thirty-stud pillar of light, a seven-stud wall of
	          white running out along the ground with a twelve-stud black one
	          behind it, a scorch, streaks, and every piece of rock that was
	          hanging in the air thrown outward on an arc. The camera is kicked,
	          and the world snaps from dark to blown-out white in one frame.
	  t+1.35  AFTERSHOCK. A second, thinner wave crosses the same ground with a
	          lower thump behind it and a kick at under half the strength, while
	          the smoke from the first one is still going up.
	  t+1.42  the first ring reaches EclipsePlan.Radius - forty-four studs -
	          which is exactly the edge of the damage.
	  t+5.00  the column of smoke and the ash have cleared and everything is
	          destroyed.

	THE POINT OF ALL THAT IS PACING

	Four beats, not one: the gather, the silence, the eclipse, and the
	aftershock. The two that do the work are the ones with nothing in them - the
	dark before the flash and the held breath before the blast - because an
	explosion is only as big as the quiet it interrupts. An ability that spends
	everything on the loud moment is over before the player has finished
	reacting to it, and this is the endgame weapon: the whole reason to have
	earned it is that pressing the key is an event.

	BLACK AND WHITE, AND HOW THAT IS MADE TO WORK

	Two colours and no others. The difficulty with black VFX is that black on a
	night sky is not an effect, it is a hole - so nothing here is only black.
	Every dark element is drawn against a white one: the star has a white rim,
	the black ring runs directly behind the white one, and the smoke is only
	ever seen against the flash that lights it. The white elements are Neon and
	the black ones are not, so they separate even where they overlap.

	WHY IT IS BUILT IN CODE AND NOT POOLED

	Sacred Rain is fifteen swords carrying eighty-seven emitters each, which is
	why FXBuilder exists and why its assemblies are pooled. One Eclipse is about
	a hundred and forty parts - a hundred and twenty of them ring segments the
	size of a plank, tweened once each and then untouched - plus eight emitters,
	on a twelve-second cooldown. Building them per cast still costs less than the
	machinery to avoid building them would, and this way the whole effect is one
	readable file rather than a file plus a data table.

	If that ever needs to come down, RING_SEGMENTS is the number: it is three of
	the rings, and dropping it from 34 to 24 costs about thirty parts and very
	little of the look.

	The textures are the only borrowed part: they are four the reference place
	already ships, reused rather than replaced with ids that would have to be
	invented and could not be checked.

	WHERE PARTICLES ARE PARENTED, AND WHY IT IS NOT ARBITRARY

	An emitter under an Attachment emits from a point. An emitter under a
	BasePart emits from that part's VOLUME, which is what makes the shaped
	emission below work - the motes are pulled inward across a sphere the size
	of the part they hang on. So the one emitter that needs a volume gets its
	own invisible part, and every other emitter sits on an attachment.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))

local Abilities = script.Parent.Parent
local EclipsePlan = require(Abilities:WaitForChild("EclipsePlan"))

local Tuning = EclipsePlan.Tuning

local EclipseVFX = {}

-- The only two colours in the effect. Everything below is one or the other.
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

--[[
	Textures, all of them out of SacredRainData - so they are ids this place is
	already known to load rather than ones chosen off a catalogue and never seen.

	  DUST    a soft round puff, for smoke
	  STREAK  a tapered streak, drawn along its own velocity
	  GLOW    a soft dot, for the motes
	  SCORCH  a 4x4 flipbook of an expanding ground ring, played once
]]
local DUST = "rbxassetid://7216854921"
local STREAK = "rbxassetid://9544366974"
local GLOW = "rbxassetid://9544354287"
local SCORCH = "rbxassetid://82556288879264"

-- How far down to look for the floor the ring runs along.
local GROUND_PROBE = 14

-- The collapse: faster than the growth, and the reason the burst reads as an
-- event rather than as the end of a swell.
local COLLAPSE_TIME = 0.08

-- How far out the motes are born, as a multiple of the star's final radius.
local FIELD_SCALE = 3

--[[
	The telegraph: a ring that runs INWARD across the ground during the second
	half of the wind-up and arrives under the star exactly as it collapses.

	It is the single most useful thing in the effect for anyone standing in it.
	The star says "something is happening"; a ring closing on a point says
	"something is happening THERE, and it is about to finish".
]]
local IMPLOSION_TIME = 0.5

--[[
	THE TWO THINGS THAT DO NOT HAPPEN IN THE WORLD

	A blast this size has to arrive somewhere other than the workspace, or it
	stays a picture of an explosion rather than one that happened to you.

	  The camera is kicked, hard at the centre and not at all past the reach
	  below. It decays as a square, so it hits and then lets go rather than
	  wobbling - a shake that outstays the sound it came from reads as a bug.

	  The world darkens through the whole wind-up and is then blown out white
	  at the detonation. Both are the ability's own two colours borrowed by the
	  entire screen, and the second one only lands because the first one spent
	  eight tenths of a second setting it up: the swing is worth far more than
	  either end of it.

	Both are local to the person watching and both are gated on distance, so
	somebody across the map sees the ring and feels nothing.
]]
local SHAKE_TIME = 0.85
local SHAKE_STUDS = 3.2
local SHAKE_ROLL = 2.4
local SHAKE_REACH = 2.2

local PUNCH_TIME = 0.5
local PUNCH_REACH = 2.6

--[[
	THE HELD BREATH.

	The star collapses, and then for a seventh of a second NOTHING HAPPENS. No
	particles, no motes, no dust - a single white pinhole hanging where an
	eleven-stud black star was a moment ago, over ground that has gone dark.

	This is the most important number in the file. A climax is not the loudest
	moment, it is the moment before it: an explosion that arrives on the beat
	you expect is an effect, and one that arrives after a gap you noticed is an
	event. Everything else here is scale; this is timing.

	It fits INSIDE ChargeTime, so the server's damage still lands on the same
	frame the blast does - the silence is taken out of the wind-up, not added
	to it.
]]
local HOLD_TIME = 0.14

--[[
	THE ECLIPSE ITSELF.

	At the detonation a black sphere and a slightly larger white one expand
	together. The black one is opaque and in front, so what anybody actually
	sees is a black disc with a ring of white fire around it - which is what an
	eclipse looks like, and what the ability has been called since before it
	looked like anything.

	The corona has to stay AHEAD of the void or the void swallows it, so the two
	radii below are a ratio rather than a pair of numbers to be tuned apart.
]]
local VOID_RADIUS = 0.5
local CORONA_EXTRA = 1.16

--[[
	The world going dark while the star gathers.

	An eclipse is not a light being switched on, it is one being taken away -
	so the wind-up drains the colour and the brightness out of everything the
	player can see, and the detonation is what gives it back, all at once and
	too much of it. The contrast between those two is worth more than either.
]]
local DIM_BRIGHTNESS = -0.28
local DIM_SATURATION = -0.55
local DIM_REACH = 3

-- Chunks of the ground thrown out by the wave, and the ones that lift off it
-- during the wind-up and hang there waiting.
local SHARDS = 14
local ROCKS = 12

-- Spokes of light dragged inward across the floor while the star gathers.
local SPOKES = 10

-- When the second, smaller wave arrives, in seconds after the first.
local AFTERSHOCK_AT = 0.55

local GROW = TweenInfo.new(Tuning.ChargeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local COLLAPSE = TweenInfo.new(COLLAPSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local IMPLODE = TweenInfo.new(IMPLOSION_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local WAVE = TweenInfo.new(Tuning.RingTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local WAVE_SLOW = TweenInfo.new(Tuning.RingTime * 1.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FLASH = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PILLAR = TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PUNCH = TweenInfo.new(PUNCH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHARD_UP = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHARD_DOWN = TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local ECLIPSE = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- The rock stops rising when the star collapses, not when the blast arrives:
-- during the held breath NOTHING may still be moving, or it is not a silence.
local LIFT = TweenInfo.new(
	math.max(0.1, Tuning.ChargeTime - HOLD_TIME - COLLAPSE_TIME),
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)
local SPOKE = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DIM = TweenInfo.new(Tuning.ChargeTime * 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local UNDIM = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ---------------------------------------------------------------------------
-- Small builders
-- ---------------------------------------------------------------------------

--[[
	An inert part: no collision, no queries, no shadow, no mass. The same
	treatment FXBuilder gives everything it builds, for the same reason - none
	of this is scenery the world should be able to notice.
]]
local function fxPart(name: string, shape: Enum.PartType, position: Vector3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(position)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.Locked = true
	part.Parent = parent
	return part
end

local function attachment(name: string, parent: BasePart): Attachment
	local point = Instance.new("Attachment")
	point.Name = name
	point.Visible = false
	point.Parent = parent
	return point
end

--[[
	One emitter, from a plain property table.

	Written this way rather than as twenty assignments per emitter because the
	interesting thing about an emitter is which properties it sets, and that
	reads far better as a table than as a paragraph.
]]
local function emitter(name: string, parent: Instance, props: { [string]: any }): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Name = name

	for key, value in pairs(props) do
		(particles :: any)[key] = value
	end

	particles.Parent = parent
	return particles
end

local function solid(color: Color3): ColorSequence
	return ColorSequence.new(color)
end

--[[
	A NumberSequence from (time, value) pairs: ramp({0, 1}, {1, 0}).
]]
local function ramp(...): NumberSequence
	local points = {}
	for index, pair in ipairs({ ... }) do
		points[index] = NumberSequenceKeypoint.new(pair[1], pair[2])
	end
	return NumberSequence.new(points)
end

--[[
	Where the effect's instances live. The same folder Sacred Rain uses, so a
	sweep of "everything an ability made" is still one place.
]]
local function effectsFolder(): Folder
	local existing = workspace:FindFirstChild("AbilityEffects")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "AbilityEffects"
	folder.Parent = workspace
	return folder
end

--[[
	The floor under the caster, for the ring to run along.

	A ray rather than the caster's own feet: the root is a fixed height above
	whatever they are standing on, and in a world made of blocks that can be a
	tower, a slope or the inside of a cave. Falls back to three studs below the
	root, which is about where the feet are, when the ray finds nothing.

	The cast's own folder is excluded, and so is the caster - a ray fired from
	inside somebody's chest otherwise stops at their chest.
]]
local function groundBelow(origin: CFrame, folder: Folder, character: Model?): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if character then { folder, character } else { folder }

	local hit = workspace:Raycast(origin.Position, Vector3.new(0, -GROUND_PROBE, 0), params)
	if hit then
		-- Lifted a hair off the surface, or the ring z-fights with the floor.
		return hit.Position + Vector3.new(0, 0.08, 0)
	end

	return origin.Position - Vector3.new(0, 3, 0)
end

-- ---------------------------------------------------------------------------
-- What the blast does to the person watching it
-- ---------------------------------------------------------------------------

--[[
	How much of this the local camera gets, from 1 on top of it to 0 outside
	`reach` times the blast radius. Squared, so the falloff is gentle near the
	middle and drops away sharply at the edge - the same shape as the pressure
	it is standing in for.
]]
local function nearness(centre: Vector3, reach: number): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end

	local distance = (camera.CFrame.Position - centre).Magnitude
	local falloff = 1 - math.clamp(distance / (Tuning.Radius * reach), 0, 1)

	return falloff * falloff
end

local shakeIndex = 0

--[[
	Kicks the camera.

	Bound one priority AFTER Enum.RenderPriority.Camera, which is the only way
	this works: the default camera scripts write CFrame every frame, so an
	offset applied before them is overwritten and an offset applied after them
	is what the player sees. It multiplies onto whatever the camera decided
	rather than replacing it, so mouse look, zoom and the shiftlock offset all
	keep working through the shake.

	Unbinds itself when it runs out, and is also unbound by the scope - a cast
	that is torn down mid-shake must not leave a render-step callback behind.
]]
local function shakeCamera(centre: Vector3, scope, scale: number?)
	local strength = nearness(centre, SHAKE_REACH) * (scale or 1)
	if strength <= 0.01 then
		return
	end

	shakeIndex += 1
	local name = "EclipseShake" .. shakeIndex
	local startedAt = os.clock()

	local function unbind()
		pcall(function()
			RunService:UnbindFromRenderStep(name)
		end)
	end

	local ok = pcall(function()
		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
			local progress = (os.clock() - startedAt) / SHAKE_TIME
			if progress >= 1 then
				unbind()
				return
			end

			local camera = workspace.CurrentCamera
			if not camera then
				return
			end

			-- Squared decay: most of the movement is in the first third.
			local decay = (1 - progress) * (1 - progress) * strength

			camera.CFrame = camera.CFrame
				* CFrame.new(
					(math.random() - 0.5) * SHAKE_STUDS * decay,
					(math.random() - 0.5) * SHAKE_STUDS * decay,
					0
				)
				* CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * SHAKE_ROLL * decay))
		end)
	end)

	if ok then
		scope:add(unbind)
	end
end

--[[
	Bleaches the screen.

	Saturation goes to nothing and comes back, with brightness and contrast
	punching up under it. On any other ability this would be a filter; on this
	one it is the effect's own two colours spreading to everything for half a
	second, which is as close as a Roblox client gets to being hit by something.

	Client-side instances in Lighting: they exist for half a second, are tweened
	back to neutral, and are destroyed by their own timer and by the scope, so
	neither a cancelled cast nor a dead player can leave the world grey.
]]
--[[
	Takes the light out of the world while the star gathers, and returns a
	function that gives it back.

	The returned function is what the detonation calls: it hands the world back
	its colour over a fifth of a second while the bleach below is blowing it out
	in the other direction, so the swing from "everything is grey and dim" to
	"everything is white" happens in one frame's worth of perception.

	Returns nil when the viewer is too far away to be worth touching, so callers
	have to tolerate that - which they do, because the whole thing is optional
	polish for whoever is standing near it.
]]
local function dimWorld(centre: Vector3, scope): (() -> ())?
	local strength = nearness(centre, DIM_REACH)
	if strength <= 0.01 then
		return nil
	end

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "EclipseDim"
	grade.Brightness = 0
	grade.Contrast = 0
	grade.Saturation = 0
	grade.Parent = Lighting
	scope:add(grade)

	scope:tween(grade, DIM, {
		Brightness = DIM_BRIGHTNESS * strength,
		Saturation = DIM_SATURATION * strength,
		Contrast = 0.12 * strength,
	})

	local released = false

	return function()
		if released then
			return
		end
		released = true

		scope:tween(grade, UNDIM, { Brightness = 0, Saturation = 0, Contrast = 0 })
		scope:delay(0.3, function()
			grade:Destroy()
		end)
	end
end

local function bleachScreen(centre: Vector3, scope)
	local strength = nearness(centre, PUNCH_REACH)
	if strength <= 0.01 then
		return
	end

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "EclipseBleach"
	grade.Brightness = 0.16 * strength
	grade.Contrast = 0.3 * strength
	grade.Saturation = -0.85 * strength
	grade.Parent = Lighting
	scope:add(grade)

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "EclipseBloom"
	bloom.Intensity = 1.4 * strength
	bloom.Size = 40
	bloom.Threshold = 0.85
	bloom.Parent = Lighting
	scope:add(bloom)

	scope:tween(grade, PUNCH, { Brightness = 0, Contrast = 0, Saturation = 0 })
	scope:tween(bloom, PUNCH, { Intensity = 0 })

	scope:delay(PUNCH_TIME + 0.1, function()
		grade:Destroy()
		bloom:Destroy()
	end)
end

-- ---------------------------------------------------------------------------
-- The wind-up
-- ---------------------------------------------------------------------------

--[[
	The star: a black sphere with a white rim, growing, pulling motes in out of
	the air while dust lifts off the floor beneath it.

	Returns the core and the rim, because the burst has to collapse them.
	Everything else it makes is cleaned up by the scope.
]]
local function buildStar(position: Vector3, ground: Vector3, folder: Folder, scope): (BasePart, BasePart)
	local core = fxPart("Core", Enum.PartType.Ball, position, folder)
	core.Color = BLACK
	core.Material = Enum.Material.SmoothPlastic
	scope:add(core)

	--[[
		The rim. A slightly larger, mostly transparent white shell around the
		black core - this is what stops the star being an invisible hole against
		a night sky, and what makes it read as an object rather than as a gap.
	]]
	local rim = fxPart("Rim", Enum.PartType.Ball, position, folder)
	rim.Color = WHITE
	rim.Material = Enum.Material.Neon
	rim.Transparency = 0.55
	rim.Size = Vector3.new(0.24, 0.24, 0.24)
	scope:add(rim)

	local light = Instance.new("PointLight")
	light.Color = WHITE
	light.Range = 34
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = rim

	--[[
		The field the motes fall out of.

		A sized, invisible part rather than an attachment, because a shaped
		emitter takes its shape from the volume it is parented to: this part's
		diameter IS the distance the motes travel. It does not grow with the
		star - a fixed field with a growing star in the middle of it reads as
		the star eating the field, which is the idea.
	]]
	local field = fxPart("Field", Enum.PartType.Ball, position, folder)
	field.Transparency = 1
	local reach = Tuning.CoreRadius * FIELD_SCALE
	field.Size = Vector3.new(reach * 2, reach * 2, reach * 2)
	scope:add(field)

	--[[
		Sphere / Surface / Inward is what does the work: motes are born on the
		surface of the field and travel towards its centre, so the wind-up reads
		as something being pulled in rather than as something being thrown out.

		Speed is set so a mote covers the field's radius in about its own
		lifetime, which is what stops them either piling up at the edge or
		arriving before they have been seen.
	]]
	local motes = emitter("Motes", field, {
		Texture = GLOW,
		Color = solid(WHITE),
		LightEmission = 1,
		Brightness = 2,
		Lifetime = NumberRange.new(0.4, 0.55),
		Rate = 90,
		Speed = NumberRange.new(reach / 0.55, reach / 0.4),
		SpreadAngle = Vector2.new(0, 0),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Orientation = Enum.ParticleOrientation.FacingCamera,
		Size = ramp({ 0, 0.9 }, { 1, 0 }),
		Transparency = ramp({ 0, 0.2 }, { 0.8, 0.2 }, { 1, 1 }),
		Enabled = true,
	})

	--[[
		Dust lifting off the floor under the star, drawn black.

		Not decoration: it is the only part of the wind-up that touches the
		ground, and it is what tells somebody standing nearby that the thing
		about to happen is going to happen down there with them.
	]]
	local base = fxPart("Base", Enum.PartType.Ball, ground, folder)
	base.Transparency = 1
	scope:add(base)

	local lift = emitter("Lift", attachment("Lift", base), {
		Texture = DUST,
		Color = solid(BLACK),
		LightEmission = 0,
		Lifetime = NumberRange.new(0.6, 1.1),
		Rate = 55,
		Speed = NumberRange.new(5, 12),
		SpreadAngle = Vector2.new(30, 30),
		Drag = 3,
		Acceleration = Vector3.new(0, 8, 0),
		EmissionDirection = Enum.NormalId.Top,
		Size = ramp({ 0, 1.2 }, { 1, 6.5 }),
		Transparency = ramp({ 0, 1 }, { 0.25, 0.45 }, { 1, 1 }),
		Rotation = NumberRange.new(-180, 180),
		RotSpeed = NumberRange.new(-40, 40),
		Enabled = true,
	})

	local size = Tuning.CoreRadius * 2
	scope:tween(core, GROW, { Size = Vector3.new(size, size, size) })
	scope:tween(rim, GROW, { Size = Vector3.new(size * 1.18, size * 1.18, size * 1.18) })
	scope:tween(light, GROW, { Brightness = 2.4 })

	--[[
		The star, and the one thing that can silence it.

		`quiet` is handed back rather than scheduled here, because WHEN the
		wind-up stops is the whole point of the held breath and that decision
		belongs to the timeline in `play`, not to the thing being switched off.
	]]
	return {
		core = core,
		rim = rim,
		quiet = function()
			motes.Enabled = false
			lift.Enabled = false
		end,
	}
end

--[[
	Lines of light dragged inward across the floor while the star gathers.

	Radial where the implosion ring is tangential, and slower, so the two read
	as one thing being pulled in from every direction rather than as two rings.
	They are what makes the ground look like it is feeding the star instead of
	merely being stood on.
]]
local function spawnSpokes(ground: Vector3, folder: Folder, scope)
	for index = 1, SPOKES do
		local angle = (index - 1) / SPOKES * math.pi * 2

		local length = Tuning.Radius * 0.42
		local spoke = fxPart("Spoke", Enum.PartType.Block, ground, folder)
		spoke.Color = WHITE
		spoke.Material = Enum.Material.Neon
		spoke.Transparency = 0.5
		spoke.Size = Vector3.new(0.7, 0.12, length)
		spoke.CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0))
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, 0, -(Tuning.Radius * 0.55))
		scope:add(spoke)

		scope:tween(spoke, SPOKE, {
			Size = Vector3.new(0.25, 0.12, length * 0.35),
			CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0))
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, 0, -Tuning.CoreRadius),
			Transparency = 1,
		})
	end
end

--[[
	Rock pulled off the ground by the gathering star, left hanging.

	Returns the pieces so the detonation can throw the same ones outward: they
	go up slowly while everything is being drawn in, hang through the silence,
	and are the first thing the blast moves. That continuity is the point -
	debris that only appears at the explosion is decoration, and debris that was
	already in the air is a consequence.
]]
local function liftRock(ground: Vector3, folder: Folder, scope): { BasePart }
	local rocks = {}

	for index = 1, ROCKS do
		local angle = (index - 1) / ROCKS * math.pi * 2 + math.random() * 0.5
		local distance = Tuning.CoreRadius * (1.2 + math.random() * 2.2)
		local at = ground + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

		local size = 0.8 + math.random() * 1.8
		local rock = fxPart("Rock", Enum.PartType.Block, at, folder)
		rock.Color = BLACK
		rock.Material = Enum.Material.Slate
		rock.Size = Vector3.new(size, size * 0.6, size)
		scope:add(rock)

		local hover = at + Vector3.new(0, 2.5 + math.random() * 7, 0)
		local spin = CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3)

		scope:tween(rock, LIFT, { CFrame = CFrame.new(hover) * spin })
		rocks[index] = rock
	end

	return rocks
end

-- ---------------------------------------------------------------------------
-- The burst
-- ---------------------------------------------------------------------------

--[[
	A ring, built out of wall segments standing on the floor.

	WHY NOT A CYLINDER

	Because a Cylinder part is a DISC. Scaling one outward along the ground
	draws a white circle growing to fill the radius - a pancake, not a
	shockwave. The eye reads a wave from its EDGE moving, and a filled disc has
	no edge to move; it just gets bigger. Roblox has no torus primitive and
	nothing in this project uploads meshes, so the ring is made the way rings
	are made without one: a circle of thin, straight segments.

	Each segment is a box whose local X lies along the tangent, so its width is
	its share of the circumference. Width therefore has to grow with the radius
	or the ring would tear itself into 22 separate dashes as it travelled - both
	are linear in the radius and both are tweened with the same easing, so the
	ring stays closed the whole way out.

	Slightly wider than its exact share (OVERLAP), because straight chords laid
	round a circle meet at an angle and leave a hairline at each corner.
]]
local RING_SEGMENTS = 34
local IMPLOSION_SEGMENTS = 20
local OVERLAP = 1.08

local function segmentWidth(radius: number, count: number): number
	return (2 * math.pi * radius / count) * OVERLAP
end

--[[
	Where one segment sits: on the circle at `angle`, standing ON the floor
	rather than half sunk into it - hence the lift by half its own height.

	The lift has to be part of the tweened frame, not applied once, because the
	segments get shorter as they travel. Height and lift are both linear in the
	same progress, so the wave stays exactly on the ground the whole way out.
]]
local function segmentFrame(centre: Vector3, angle: number, radius: number, height: number): CFrame
	return CFrame.new(centre + Vector3.new(0, height * 0.5, 0))
		* CFrame.Angles(0, angle, 0)
		* CFrame.new(0, 0, -radius)
end

type RingSpec = {
	name: string,
	centre: Vector3,
	color: Color3,
	material: Enum.Material,
	segments: number,
	fromRadius: number,
	toRadius: number,
	fromHeight: number,
	toHeight: number,
	thickness: number,
	transparency: number,
	info: TweenInfo,
	fadeOut: boolean,
}

local function spawnRing(spec: RingSpec, folder: Folder, scope)
	local count = spec.segments

	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2

		local segment = fxPart(spec.name, Enum.PartType.Block, spec.centre, folder)
		segment.Color = spec.color
		segment.Material = spec.material
		segment.Transparency = spec.transparency
		segment.Size = Vector3.new(segmentWidth(spec.fromRadius, count), spec.fromHeight, spec.thickness)
		segment.CFrame = segmentFrame(spec.centre, angle, spec.fromRadius, spec.fromHeight)
		scope:add(segment)

		scope:tween(segment, spec.info, {
			Size = Vector3.new(segmentWidth(spec.toRadius, count), spec.toHeight, spec.thickness * 0.6),
			CFrame = segmentFrame(spec.centre, angle, spec.toRadius, spec.toHeight),
			Transparency = if spec.fadeOut then 1 else spec.transparency,
		})
	end
end

--[[
	Chunks of the floor, thrown out and dropped back.

	Particles alone never quite sell scale, because they have no weight - they
	drift, and drifting is what smoke does. A dozen solid pieces going up on an
	arc and coming down again is the cheapest way to say that something heavy
	happened, and it is two tweens each: out and up under Quad Out, then down
	under Quad In, which is what an arc is.

	They are cosmetic and they are not physics. Nothing collides, nothing is
	simulated, and where they land is decided when they are thrown.
]]
local function throwDebris(ground: Vector3, folder: Folder, scope)
	for index = 1, SHARDS do
		local angle = (index - 1) / SHARDS * math.pi * 2 + math.random() * 0.4
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))

		local size = 0.9 + math.random() * 2.4
		local shard = fxPart("Shard", Enum.PartType.Block, ground, folder)
		shard.Color = BLACK
		shard.Material = Enum.Material.Slate
		shard.Size = Vector3.new(size, size * 0.7, size)
		shard.CFrame = CFrame.new(ground + direction * 2)
		scope:add(shard)

		local distance = Tuning.Radius * (0.35 + math.random() * 0.55)
		local peak = ground + direction * distance * 0.6 + Vector3.new(0, 14 + math.random() * 16, 0)
		local landing = ground + direction * distance

		local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)

		scope:tween(shard, SHARD_UP, { CFrame = CFrame.new(peak) * spin })

		scope:delay(0.45, function()
			scope:tween(shard, SHARD_DOWN, {
				CFrame = CFrame.new(landing) * spin * spin,
				Transparency = 1,
			})
		end)
	end
end

--[[
	Everything that happens on the frame the wave arrives.
]]
--[[
	The collapse, and the silence after it.

	Everything stops here: the star shrinks to nothing faster than it grew, its
	emitters go off, and what is left hanging over a darkened floor is a single
	white pinhole and a dozen rocks that never came back down.

	Nothing else happens until the detonation. That gap is HOLD_TIME and it is
	the reason this is a separate function rather than the first four lines of
	the next one - it is a beat, and beats are easier to keep honest when the
	code has to name them.
]]
local function collapseStar(star, position: Vector3, folder: Folder, scope): BasePart
	star.quiet()

	scope:tween(star.core, COLLAPSE, { Size = Vector3.new(0.05, 0.05, 0.05) })
	scope:tween(star.rim, COLLAPSE, { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })

	local pinhole = fxPart("Pinhole", Enum.PartType.Ball, position, folder)
	pinhole.Color = WHITE
	pinhole.Material = Enum.Material.Neon
	pinhole.Size = Vector3.new(0.01, 0.01, 0.01)
	pinhole.Transparency = 0.1
	scope:add(pinhole)

	local spark = Instance.new("PointLight")
	spark.Color = WHITE
	spark.Range = 18
	spark.Brightness = 1.4
	spark.Shadows = false
	spark.Parent = pinhole

	-- It arrives as the star vanishes and then just hangs there, which is the
	-- only thing on screen for the whole of the silence.
	scope:tween(pinhole, COLLAPSE, { Size = Vector3.new(1.1, 1.1, 1.1) })

	return pinhole
end

--[[
	The eclipse frame.

	A black sphere and a white one expanding together, the black one opaque and
	inside the white: from anywhere in the world that reads as a black disc
	ringed with fire, held for four tenths of a second in the middle of the
	blast. It is the one image the whole ability is named after, and everything
	around it - the rings, the pillar, the smoke - is what happens next.
]]
local function eclipseFrame(position: Vector3, folder: Folder, scope)
	local void = fxPart("Void", Enum.PartType.Ball, position, folder)
	void.Color = BLACK
	void.Material = Enum.Material.SmoothPlastic
	void.Size = Vector3.new(2, 2, 2)
	scope:add(void)

	local corona = fxPart("Corona", Enum.PartType.Ball, position, folder)
	corona.Color = WHITE
	corona.Material = Enum.Material.Neon
	corona.Transparency = 0.08
	corona.Size = Vector3.new(2.4, 2.4, 2.4)
	scope:add(corona)

	local voidSpan = Tuning.Radius * VOID_RADIUS
	local coronaSpan = voidSpan * CORONA_EXTRA

	scope:tween(void, ECLIPSE, {
		Size = Vector3.new(voidSpan, voidSpan, voidSpan),
		Transparency = 1,
	})
	scope:tween(corona, ECLIPSE, {
		Size = Vector3.new(coronaSpan, coronaSpan, coronaSpan),
		Transparency = 1,
	})
end

local function burst(pinhole: BasePart, rocks: { BasePart }, position: Vector3, ground: Vector3, folder: Folder, scope)
	-- The pinhole is what detonates; it does not survive its own blast.
	pinhole:Destroy()

	Sounds.playAt("ability.eclipse.burst", position)

	eclipseFrame(position, folder, scope)

	--[[
		The flash. White, Neon, and gone in a fifth of a second - it exists
		to light the smoke, which is black and would otherwise be a hole in
		the middle of the effect.
	]]
	local flash = fxPart("Flash", Enum.PartType.Ball, position, folder)
	flash.Color = WHITE
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.1
	flash.Size = Vector3.new(1, 1, 1)
	scope:add(flash)

	local glare = Instance.new("PointLight")
	glare.Color = WHITE
	-- Roblox caps a PointLight's range at 60; asking for more silently
	-- gets 60, so this is written as the maximum rather than as a number
	-- that looks bigger and is not.
	glare.Range = 60
	glare.Brightness = 9
	glare.Shadows = false
	glare.Parent = flash

	local reach = Tuning.Radius * 0.75
	scope:tween(flash, FLASH, { Size = Vector3.new(reach, reach, reach), Transparency = 1 })
	scope:tween(glare, FLASH, { Brightness = 0 })

	-- The two things that land on the player rather than on the ground.
	shakeCamera(position, scope)
	bleachScreen(position, scope)

	--[[
		A pillar of light where the star was, for a sixth of a second.

		The burst is otherwise entirely horizontal, and a purely horizontal
		effect reads as flat. One vertical accent is enough to give it a
		centre - and it is the shape somebody looking at the sky sees when
		they missed the wind-up.
	]]
	local pillarHeight = 130
	local pillarAt = ground + Vector3.new(0, pillarHeight * 0.5, 0)

	local pillar = fxPart("Pillar", Enum.PartType.Cylinder, pillarAt, folder)
	pillar.Color = WHITE
	pillar.Material = Enum.Material.Neon
	pillar.Transparency = 0.18
	pillar.Size = Vector3.new(pillarHeight, 11, 11)
	pillar.CFrame = CFrame.new(pillarAt) * CFrame.Angles(0, 0, math.pi / 2)
	scope:add(pillar)
	scope:tween(pillar, PILLAR, { Size = Vector3.new(pillarHeight, 0.4, 0.4), Transparency = 1 })

	--[[
		The wave itself: a hard white edge, and a taller black one chasing
		it two frames behind.

		The black ring is what gives the wave a direction. A single white
		ring expanding is a circle getting bigger; a bright edge with a dark
		mass behind it is something travelling outward, because that is the
		order those two things arrive in when a real one passes you.
	]]
	spawnRing({
		name = "Edge",
		centre = ground,
		color = WHITE,
		material = Enum.Material.Neon,
		segments = RING_SEGMENTS,
		fromRadius = 3,
		toRadius = Tuning.Radius,
		fromHeight = 7,
		toHeight = 0.6,
		thickness = 1.6,
		transparency = 0.05,
		info = WAVE,
		fadeOut = true,
	}, folder, scope)

	scope:delay(0.07, function()
		spawnRing({
			name = "Shadow",
			centre = ground,
			color = BLACK,
			material = Enum.Material.SmoothPlastic,
			segments = RING_SEGMENTS,
			fromRadius = 2.5,
			toRadius = Tuning.Radius * 0.95,
			fromHeight = 12,
			toHeight = 1.2,
			thickness = 3.2,
			transparency = 0.05,
			info = WAVE,
			fadeOut = true,
		}, folder, scope)
	end)

	--[[
		And a third, thin and slow, arriving after the other two have gone.

		The overpressure behind the front. Two rings is an explosion; a third
		one still coming while the smoke is going up is what makes the blast
		feel like it had more in it than the moment it happened - and it
		stops at exactly the same radius as the others, because the edge of
		the ring is a promise about where the damage was.
	]]
	scope:delay(0.2, function()
		spawnRing({
			name = "Echo",
			centre = ground,
			color = WHITE,
			material = Enum.Material.Neon,
			segments = RING_SEGMENTS,
			fromRadius = 4,
			toRadius = Tuning.Radius,
			fromHeight = 2.4,
			toHeight = 0.3,
			thickness = 0.7,
			transparency = 0.45,
			info = WAVE_SLOW,
			fadeOut = true,
		}, folder, scope)
	end)

	--[[
		Light spilling across the floor under the ring. THIS one is a disc,
		deliberately - it is the glow the wave drags along with it, and a
		glow has no edge.
	]]
	local spill = fxPart("Spill", Enum.PartType.Cylinder, ground, folder)
	spill.Color = WHITE
	spill.Material = Enum.Material.Neon
	spill.Transparency = 0.72
	spill.Size = Vector3.new(0.15, 5, 5)
	spill.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2)
	scope:add(spill)

	local span = Tuning.Radius * 2
	scope:tween(spill, WAVE, { Size = Vector3.new(0.1, span, span), Transparency = 1 })

	--[[
		Everything thrown out along the ground. One part carrying three
		point emitters: they sit in the same place and all fire once, so
		there is nothing to be gained by separating them.
	]]
	local wave = fxPart("Wave", Enum.PartType.Ball, ground, folder)
	wave.Transparency = 1
	scope:add(wave)

	local point = attachment("Burst", wave)

	--[[
		The scorch: one playthrough of a flipbook, flat on the floor, at
		nearly the full radius. It is the reference's own ground texture and
		the one thing here not drawn from a particle primitive - which is
		deliberate, because it is the frame this ability is recognisable in.
	]]
	local scorch = emitter("Scorch", point, {
		Texture = SCORCH,
		Color = solid(WHITE),
		LightEmission = 0.6,
		Brightness = 2,
		Lifetime = NumberRange.new(0.8, 0.8),
		Rate = 0,
		Speed = NumberRange.new(0, 0),
		SpreadAngle = Vector2.new(0, 0),
		LockedToPart = true,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(20, 20),
		FlipbookBlendFrames = true,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Size = ramp({ 0, Tuning.Radius * 0.7 }, { 1, Tuning.Radius * 1.9 }),
		Transparency = ramp({ 0, 0.15 }, { 0.7, 0.35 }, { 1, 1 }),
		Rotation = NumberRange.new(-180, 180),
		Enabled = false,
	})

	--[[
		Streaks, thrown outward along the floor and dragged to a stop.

		SpreadAngle's first component is the spread around the emission
		direction and the second is across it: 180 by 6 is a disc, not a
		dome. This is a wave, and anything with height in it reads as an
		explosion instead.
	]]
	local streaks = emitter("Streaks", point, {
		Texture = STREAK,
		Color = solid(WHITE),
		LightEmission = 1,
		Brightness = 3,
		Lifetime = NumberRange.new(0.28, 0.5),
		Rate = 0,
		Speed = NumberRange.new(Tuning.Radius * 1.6, Tuning.Radius * 2.6),
		SpreadAngle = Vector2.new(180, 6),
		Drag = 5,
		Squash = ramp({ 0, 2.5 }, { 1, 0 }),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Top,
		Size = ramp({ 0, 1.6 }, { 1, 0 }),
		Transparency = ramp({ 0, 0.1 }, { 1, 1 }),
		Enabled = false,
	})

	-- The smoke that is left. Black, slow, and lit for a fifth of a second
	-- by the flash above - which is the only time it is visible as anything
	-- other than a silhouette.
	local smoke = emitter("Smoke", point, {
		Texture = DUST,
		Color = solid(BLACK),
		LightEmission = 0,
		Lifetime = NumberRange.new(0.9, Tuning.SettleTime),
		Rate = 0,
		Speed = NumberRange.new(Tuning.Radius * 0.5, Tuning.Radius * 1.1),
		SpreadAngle = Vector2.new(180, 14),
		Drag = 4,
		Acceleration = Vector3.new(0, 3, 0),
		EmissionDirection = Enum.NormalId.Top,
		Size = ramp({ 0, 5 }, { 0.4, 16 }, { 1, 26 }),
		Transparency = ramp({ 0, 1 }, { 0.12, 0.25 }, { 1, 1 }),
		Rotation = NumberRange.new(-180, 180),
		RotSpeed = NumberRange.new(-25, 25),
		Enabled = false,
	})

	--[[
		The column: smoke going straight up out of the middle, slowly, for
		as long as the aftermath lasts.

		This is the part somebody sees from across the map after the ring
		has already gone, and it is what turns the cast into a landmark -
		"something happened over there" - rather than a flash they either
		caught or did not.
	]]
	local column = emitter("Column", point, {
		Texture = DUST,
		Color = solid(BLACK),
		LightEmission = 0,
		Lifetime = NumberRange.new(Tuning.SettleTime * 0.7, Tuning.SettleTime),
		Rate = 0,
		Speed = NumberRange.new(16, 34),
		SpreadAngle = Vector2.new(16, 16),
		Drag = 1.6,
		Acceleration = Vector3.new(0, 2.5, 0),
		EmissionDirection = Enum.NormalId.Top,
		Size = ramp({ 0, 6 }, { 0.45, 22 }, { 1, 38 }),
		Transparency = ramp({ 0, 1 }, { 0.1, 0.3 }, { 0.75, 0.55 }, { 1, 1 }),
		Rotation = NumberRange.new(-180, 180),
		RotSpeed = NumberRange.new(-14, 14),
		Enabled = false,
	})

	--[[
		Ash coming down over the whole radius, white against the smoke.

		Long-lived and slow. It is the only part of the effect that is still
		happening several seconds later, and it is what stops the aftermath
		being a static cloud sitting on the floor.
	]]
	local ash = emitter("Ash", point, {
		Texture = GLOW,
		Color = solid(WHITE),
		LightEmission = 0.5,
		Lifetime = NumberRange.new(Tuning.SettleTime * 0.6, Tuning.SettleTime),
		Rate = 0,
		Speed = NumberRange.new(Tuning.Radius * 0.45, Tuning.Radius * 0.95),
		SpreadAngle = Vector2.new(180, 45),
		Drag = 2.5,
		Acceleration = Vector3.new(0, -14, 0),
		EmissionDirection = Enum.NormalId.Top,
		Size = ramp({ 0, 1.1 }, { 1, 0.2 }),
		Transparency = ramp({ 0, 0.15 }, { 0.7, 0.35 }, { 1, 1 }),
		Enabled = false,
	})

	scorch:Emit(1)
	streaks:Emit(150)
	smoke:Emit(52)
	column:Emit(30)
	ash:Emit(90)

	throwDebris(ground, folder, scope)

	--[[
		And the rock that has been hanging in the air since the wind-up goes
		with it - outward and up, then down, on the same arc as everything
		the blast threw itself.

		Sent from where each piece actually IS rather than from the centre,
		so a rock that lifted off to one side leaves in that direction. It is
		the difference between debris and confetti.
	]]
	for _, rock in ipairs(rocks) do
		if rock.Parent then
			local away = rock.Position - ground
			local flat = Vector3.new(away.X, 0, away.Z)
			local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)

			local distance = Tuning.Radius * (0.5 + math.random() * 0.5)
			local spin = CFrame.Angles(math.random() * 8, math.random() * 8, math.random() * 8)
			local peak = ground + direction * distance * 0.65 + Vector3.new(0, 22 + math.random() * 18, 0)
			local landing = ground + direction * distance

			scope:tween(rock, SHARD_UP, { CFrame = CFrame.new(peak) * spin })

			local piece = rock
			scope:delay(0.45, function()
				scope:tween(piece, SHARD_DOWN, {
					CFrame = CFrame.new(landing) * spin * spin,
					Transparency = 1,
				})
			end)
		end
	end
end

--[[
	The aftershock: a second, smaller wave half a second behind the first.

	Not a repeat of the blast - a consequence of it. It is quieter, thinner and
	lower, it kicks the camera again at a fraction of the strength, and it
	arrives while the smoke from the first one is still going up. One explosion
	is a hit; a hit with something still collapsing behind it is a disaster,
	which is the register this ability is supposed to end in.

	It does no damage and it is drawn to the same radius as the wave that did,
	so it cannot be mistaken for a second hitbox.
]]
local function aftershock(position: Vector3, ground: Vector3, folder: Folder, scope)
	Sounds.playAt("ability.eclipse.aftershock", position)

	spawnRing({
		name = "Aftershock",
		centre = ground,
		color = WHITE,
		material = Enum.Material.Neon,
		segments = RING_SEGMENTS,
		fromRadius = 3,
		toRadius = Tuning.Radius,
		fromHeight = 3.5,
		toHeight = 0.4,
		thickness = 1,
		transparency = 0.25,
		info = WAVE_SLOW,
		fadeOut = true,
	}, folder, scope)

	local thump = fxPart("Thump", Enum.PartType.Ball, position, folder)
	thump.Color = WHITE
	thump.Material = Enum.Material.Neon
	thump.Transparency = 0.55
	thump.Size = Vector3.new(2, 2, 2)
	scope:add(thump)

	local span = Tuning.Radius * 0.4
	scope:tween(thump, FLASH, { Size = Vector3.new(span, span, span), Transparency = 1 })
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

--[[
	Plays a whole cast.

	The scope belongs to AbilityClient: everything here is added to it or
	scheduled through it, so a cast that is cut short - the player died, the
	effect budget filled, the character despawned - takes all of this with it.
]]
function EclipseVFX.play(payload, scope): boolean
	local origin = payload.origin
	if typeof(origin) ~= "CFrame" then
		--[[
			Said out loud rather than returned quietly. A VFX module that
			returns false is dropped without a word by AbilityClient, which is
			right for "this cast has nothing to draw" and wrong for "the packet
			was not what this expected" - the second one is a bug somewhere, and
			a bug that draws nothing and says nothing is the worst kind to own.
		]]
		warn(string.format(
			"[EclipseVFX] payload.origin is a %s, not a CFrame - nothing to draw.", typeof(origin)
		))
		return false
	end

	local folder = effectsFolder()

	local caster = payload.caster
	local character = if typeof(caster) == "Instance" and caster:IsA("Player") then caster.Character else nil

	local position = origin.Position + Vector3.new(0, Tuning.CoreHeight, 0)
	local ground = groundBelow(origin, folder, character)

	--[[
		THE TIMELINE, ALL OF IT IN ONE PLACE.

		Everything below is measured backwards from EclipsePlan.impactAt(),
		which is the frame the server applies the damage on. The silence, the
		collapse and the telegraph are taken OUT of the wind-up rather than
		added to it, so no amount of retiming here can make the blast and the
		damage disagree.
	]]
	local impactAt = Tuning.ChargeTime
	local collapseAt = math.max(0, impactAt - HOLD_TIME - COLLAPSE_TIME)
	local telegraphAt = math.max(0, collapseAt - IMPLOSION_TIME)

	Sounds.playAt("ability.eclipse.charge", position)

	-- GATHER. The star, the rock coming off the floor, and the light going out
	-- of the world.
	local star = buildStar(position, ground, folder, scope)
	local rocks = liftRock(ground, folder, scope)
	local restoreWorld = dimWorld(position, scope)

	-- TELEGRAPH. A ring closing across the floor and ten spokes dragged in with
	-- it, both arriving under the star exactly as it collapses.
	scope:delay(telegraphAt, function()
		spawnSpokes(ground, folder, scope)

		spawnRing({
			name = "Implosion",
			centre = ground,
			color = WHITE,
			material = Enum.Material.Neon,
			segments = IMPLOSION_SEGMENTS,
			fromRadius = Tuning.Radius * 0.55,
			toRadius = 1.5,
			fromHeight = 0.25,
			toHeight = 1.8,
			thickness = 0.5,
			transparency = 0.45,
			info = IMPLODE,
			fadeOut = true,
		}, folder, scope)
	end)

	-- COLLAPSE, then HOLD_TIME of nothing at all.
	local pinhole: BasePart? = nil
	scope:delay(collapseAt, function()
		pinhole = collapseStar(star, position, folder, scope)
	end)

	-- DETONATION, on the damage frame.
	scope:delay(impactAt, function()
		if restoreWorld then
			restoreWorld()
		end

		if pinhole then
			burst(pinhole, rocks, position, ground, folder, scope)
		end
	end)

	-- AFTERSHOCK, while the first one is still going up.
	scope:delay(impactAt + AFTERSHOCK_AT, function()
		aftershock(position, ground, folder, scope)

		-- Under half the first kick. An aftershock that hits as hard as the
		-- blast is not an aftershock, it is a second blast.
		shakeCamera(position, scope, 0.45)
	end)

	return true
end

function EclipseVFX.duration(): number
	return EclipsePlan.duration()
end

--[[
	Nothing to build ahead of time.

	Sacred Rain preloads because assembling its rig is a visible hitch; this
	effect is built on the frame it fires. The function exists
	because AbilityClient calls it on equip, and an ability that has no preload
	should say so rather than appear to be missing one.
]]
function EclipseVFX.preload(_itemName: string) end

return EclipseVFX
