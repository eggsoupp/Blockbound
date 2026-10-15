--[[
	SlimeBody

	Makes a model behave like a body made of slime: squash, stretch, wobble,
	swell, shrink and flatten, with the ground under its feet staying where it
	was and anything riding on top of it - a crown - staying on top.

	IT IS NOT BOSS-ONLY, WHICH IS WHY IT NO LONGER LIVES UNDER Bosses

	It was written for the Slime Emperor and it now also gives ORDINARY slimes
	their bounce: EnemyService builds one for any Hop enemy whose definition
	says `bounce = true` and drives crouch, stretch and land off the same three
	state transitions the boss uses. Both arguments to `new` are optional for
	that reason - a spawned slime has no part named after it and is not wearing
	a hat.

		local body = SlimeBody.new(entry, "SlimeEmperor", "Crown")
		local body = SlimeBody.new(entry)   -- an ordinary slime

		body:shape(1.6, 0.4)          -- wide and flat, right now
		body:ease(1, 1, 0.25)         -- back to rest over a quarter second
		body:wobble(0.6)              -- the jelly settling after a landing
		body:setMass(0.7)             -- he is smaller now, and stays smaller
		body:flash(color, 0.15)       -- and the light he casts flashes with him
		body:setTrail(true)           -- the streak, while he is off the ground
		body:setCrownPose(3, tilt)    -- the crown lifted and leaning, still on him
		body:setCrownGlow(true)       -- and burning

	WIDTH AND HEIGHT ARE MULTIPLIERS OF HIS RESTING SHAPE, not sizes. 1, 1 is
	whatever the artist built; 1.6, 0.4 is that same body pushed flat. Nothing
	here needs to know how big he is, which is what lets the artist rescale the
	model without retuning a single attack.

	VOLUME IS NOT CONSERVED, ON PURPOSE

	A real blob pressed flat spreads by exactly the amount it lost in height.
	Doing that here would mean every squash silently changed his hitbox area,
	and his hitbox is a gameplay promise. So width and height are independent
	and the ATTACKS choose numbers that look like conservation - `squashJump`
	below is the shape you would get for free from physics, written down on
	purpose so it can be broken when an attack needs it.

	WHAT IT CAN AND CANNOT DO

	If the body is ONE BasePart - a sphere, a mesh, a union - it deforms for
	real, per axis, because Size is three numbers. That is the case this is
	written for and the one a slime is almost always built as.

	If the body is a MODEL of several parts, non-uniform scaling would have to
	move every part relative to a pivot and would mangle any rotated or offset
	geometry, so it falls back to Model:ScaleTo - uniform only. He will still
	pulse, swell and shrink; he will not flatten. The fight reads the difference
	from `body.deformable` and does not schedule the shape-based attacks when it
	is false, rather than playing them invisibly.

	THE FEET STAY PUT

	Every shape change measures the bottom of the model before and after and
	lifts the pivot by the difference, so a squash sinks nothing into the floor
	and a stretch does not leave him hovering. It also re-measures
	EnemyService's own feetOffset, which everything else places him by.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))

local SlimeBody = {}
SlimeBody.__index = SlimeBody

--[[
	The shape a blob makes when it is about to jump, and when it lands.

	Written down once because half the attacks want it and because they should
	all agree: a squash that is 1.35 wide in one attack and 1.5 in the next
	reads as two different creatures.
]]
SlimeBody.SquashJump = { width = 1.34, height = 0.58 }
SlimeBody.StretchFly = { width = 0.74, height = 1.52 }
SlimeBody.Pancake = { width = 2.9, height = 0.14 }
SlimeBody.Column = { width = 0.62, height = 2.1 }

--[[
	How brightly he burns, at rest and at the peak of a flash.

	Deliberately low at rest. He is lit from inside all fight and a light that
	is already at its ceiling has nowhere to go when something happens, which
	is the whole point of having one: the flash has to be a CHANGE.
]]
local GLOW_BRIGHTNESS = 1.6
local GLOW_FLASH = 2.6

-- How long the airborne streak hangs behind him, and how solid its head is.
-- Short: a slime is wet, not on fire, and a long trail turns a hop into a comet.
local TRAIL_LIFETIME = 0.28
local TRAIL_TRANSPARENCY = 0.4

--[[
	Finds the part that IS the slime.

	By name first, because the artist named it; then the model's PrimaryPart;
	then the largest BasePart, which for a slime with a crown on its head is the
	slime and not the crown. Three fallbacks because the one thing this must not
	do is silently deform the hat.

	`bodyName` is optional, and an ordinary slime is why. The boss knows the
	part is called "SlimeEmperor" because Elias named it; a spawned enemy is
	whatever the artist dropped into EnemyAssets under whatever names, so it
	skips straight to the PrimaryPart - which EnemyService has already insisted
	on for every enemy it will move.
]]
local function findBody(model: Model, bodyName: string?): (Instance?, boolean)
	local named = if bodyName then model:FindFirstChild(bodyName) else nil

	if named and named:IsA("BasePart") then
		return named, true
	end

	if named and named:IsA("Model") then
		-- A named sub-model of one part is still one part.
		local only = nil
		for _, descendant in ipairs(named:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if only then
					return named, false
				end
				only = descendant
			end
		end
		if only then
			return only, true
		end
		return named, false
	end

	if model.PrimaryPart then
		return model.PrimaryPart, true
	end

	local biggest, biggestVolume = nil, 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local size = descendant.Size
			local volume = size.X * size.Y * size.Z
			if volume > biggestVolume then
				biggest, biggestVolume = descendant, volume
			end
		end
	end

	if biggest then
		return biggest, true
	end

	return nil, false
end

--[[
	The underside of his BODY - not of the model.

	The crown must never be part of this. It rides on him, it is not what he
	stands on, and once he flattens it can easily be the lowest thing in the
	model's bounding box. Measuring the box then feeds the crown's position back
	into where his feet are, and he shakes.
]]
local function bottomOf(self): number
	if self.deformable then
		local part = self.body :: BasePart
		return part.Position.Y - part.Size.Y * 0.5
	end

	local cframe, size = self.model:GetBoundingBox()
	return cframe.Position.Y - size.Y * 0.5
end

function SlimeBody.new(entry, bodyName: string?, crownName: string?)
	local self = setmetatable({}, SlimeBody)

	local model = entry.model

	self.entry = entry
	self.model = model

	local body, deformable = findBody(model, bodyName)

	self.body = body
	self.deformable = deformable and body ~= nil and body:IsA("BasePart")

	--[[
		The resting shape, captured AFTER EnemyService has applied its size
		variance - which it does with ScaleTo before anything gets here. Reading
		it earlier would record the import size and every deform would snap him
		back to it on the first squash.
	]]
	self.baseSize = if self.deformable then (body :: BasePart).Size else Vector3.one
	self.baseScale = model:GetScale()

	-- Optional, like bodyName. Most slimes are not wearing anything.
	local crown = if crownName then model:FindFirstChild(crownName, true) else nil
	self.crown = if crown and (crown:IsA("BasePart") or crown:IsA("Model")) then crown else nil

	--[[
		Where the crown sits, IN THE BODY'S OWN FRAME.

		A whole CFrame rather than a height, so its sideways offset and its
		rotation survive as well - and so it turns with him, which a stored
		world rotation would not.

		THIS WAS MEASURED WRONG THE FIRST TIME and the crown ended up inside
		him. The lift was taken against the MODEL's bounding box, which contains
		the crown: on a slime wearing a hat the top of that box IS the top of
		the hat, so the offset came out roughly minus half a crown, and every
		reseat pushed it down into his head. Measuring against the body part is
		unambiguous - it is the thing the crown sits on.

		Only for a deformable body. A crown inside a multi-part model is moved
		by PivotTo along with everything else, so there is nothing to correct.
	]]
	if self.crown and self.deformable then
		self.crownOffset = (self.body :: BasePart).CFrame:ToObjectSpace(self:_crownCFrame())

		--[[
			And how big it started, so it can shrink with him.

			A crown is a RIGID object: it rides the deformation in position but
			must not squash when he flattens - a flattened crown is a puddle
			with a pattern on it. So it scales with his MASS only, which is the
			one thing that means "there is less of this king".

			Without this he loses a third of his mass over a fight and keeps a
			full-size hat, which looks exactly as wrong as it sounds.
		]]
		if self.crown:IsA("BasePart") then
			self.crownBaseSize = (self.crown :: BasePart).Size
		else
			self.crownBaseScale = (self.crown :: Model):GetScale()
		end
	end

	self.width = 1
	self.height = 1
	self.depth = 1
	self.mass = 1

	-- See flash(). Counted rather than captured per call, so overlapping
	-- flashes cannot make one of them the resting colour.
	self.flashDepth = 0
	self.restColor = nil

	--[[
		NO GLOW AND NO TRAIL UNLESS SOMEBODY ASKS. See lightUp().

		This used to happen here, when the Emperor was the only thing with a
		body. He is not any more: a plains slime gets one too, and giving every
		slime in the world its own PointLight and its own ribbon would be twenty
		dynamic lights on a hillside and a smear behind every hop. Neither is a
		bug exactly, which is what would have made it hard to notice.
	]]

	-- Set by wobble(), read by step(). Nil when he is not jiggling.
	self.wobbleUntil = nil
	self.wobbleFrom = 0
	self.wobbleAmplitude = 0

	-- Set by ease(), read by step().
	self.easing = nil

	return self
end

-- ---------------------------------------------------------------------------
-- Glow and trail
-- ---------------------------------------------------------------------------

--[[
	Gives this body the two things about it that are not shape: the light it
	casts, and the streak it leaves.

	OPT IN, and the Emperor is the only thing that does. A boss is one creature
	that the player is looking directly at for a minute; an ambient slime is one
	of twenty on a hillside, and what reads as presence on the first reads as
	noise on the twentieth.

	Both are built once, here, and switched by the fight afterwards - rather
	than being created and destroyed per attack, which is what turns a nice
	effect into a stutter when it happens eleven times a minute.
]]
function SlimeBody:lightUp()
	local host = if self.deformable
		then self.body :: BasePart
		else (self.model.PrimaryPart or self.model:FindFirstChildWhichIsA("BasePart"))

	if not host then
		return
	end

	--[[
		Measured off the HOST PART, not off baseSize.

		baseSize is already the post-ScaleTo world size for a deformable body,
		so multiplying it by baseScale again would double the scale - and for a
		body that is a whole model baseSize is Vector3.one, which would put both
		attachments in the same place and draw no ribbon at all. The part in
		front of us knows how big it is; ask it.
	]]
	local half = host.Size.Y * 0.5
	local reach = self:radius()

	--[[
		He lights his own fight.

		A boss made of glowing neon that casts no light reads as a decal stuck
		on the world; one that does reads as a thing standing in it, and the
		phase changes get to be felt on the walls rather than only seen on him.

		Range is derived from his size so it follows him down - a king who has
		thrown half of himself away should not still be lighting the room like a
		whole one. Shadows off: a light inside a translucent body with shadows
		on spends real frame time drawing the inside of him.
	]]
	local light = Instance.new("PointLight")
	light.Name = "EmperorGlow"
	light.Color = host.Color
	light.Brightness = GLOW_BRIGHTNESS
	light.Range = math.clamp(reach * 3, 12, 60)
	light.Shadows = false
	light.Parent = host

	self.light = light
	self.glowRange = light.Range

	--[[
		And the streak he leaves when he is off the ground.

		Two attachments most of a body apart, so the ribbon is as tall as he is
		and reads as HIM smeared through the air rather than as a line drawn
		behind him.

		Built disabled. It is switched on for the airborne half of a hop and for
		the attacks that throw him, because a trail that is always on turns
		every shuffle on the spot into a smear and stops meaning "he is moving
		fast" at all.
	]]
	local top = Instance.new("Attachment")
	top.Name = "EmperorTrailTop"
	top.Position = Vector3.new(0, half * 0.6, 0)
	top.Parent = host

	local bottom = Instance.new("Attachment")
	bottom.Name = "EmperorTrailBottom"
	bottom.Position = Vector3.new(0, -half * 0.6, 0)
	bottom.Parent = host

	local trail = Instance.new("Trail")
	trail.Name = "EmperorTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(host.Color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, TRAIL_TRANSPARENCY),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.12),
	})
	trail.Lifetime = TRAIL_LIFETIME
	trail.LightEmission = 0.6
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = host

	self.trail = trail

	--[[
		And one for the crown, for the one attack that throws it.

		Only when the crown is a single part - a crown built as a model has no
		obvious part to hang two attachments off, and guessing wrong would draw
		a ribbon off one jewel. It is a flourish; it does not get to be a
		correctness problem, so it simply does not happen there.

		Narrow and short-lived on purpose. This is a thin metal thing spinning
		through the air, not another body.
	]]
	if self.crown and self.crown:IsA("BasePart") then
		local crown = self.crown :: BasePart
		local lip = crown.Size.Y * 0.4

		local crownTop = Instance.new("Attachment")
		crownTop.Name = "CrownTrailTop"
		crownTop.Position = Vector3.new(0, lip, 0)
		crownTop.Parent = crown

		local crownBottom = Instance.new("Attachment")
		crownBottom.Name = "CrownTrailBottom"
		crownBottom.Position = Vector3.new(0, -lip, 0)
		crownBottom.Parent = crown

		local streak = Instance.new("Trail")
		streak.Name = "CrownTrail"
		streak.Attachment0 = crownTop
		streak.Attachment1 = crownBottom
		streak.Color = ColorSequence.new(crown.Color)
		streak.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		streak.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		streak.Lifetime = TRAIL_LIFETIME * 1.6
		streak.LightEmission = 0.9
		streak.LightInfluence = 0
		streak.FaceCamera = true
		streak.Enabled = false
		streak.Parent = crown

		self.crownTrail = streak
	end

	--[[
		And a light IN the crown, off until an attack asks for it.

		The crown is the one thing about him that is not slime, and two of his
		attacks are about it exercising authority: it should be able to burn
		gold for a moment when it commands something. Built once here, like
		the trail, and switched by setCrownGlow; a crown built as a model
		hangs it off its first part, which for a glow - unlike a trail - is a
		perfectly good answer.
	]]
	if self.crown then
		local crownHost = if self.crown:IsA("BasePart")
			then self.crown
			else self.crown:FindFirstChildWhichIsA("BasePart", true)

		if crownHost then
			local glow = Instance.new("PointLight")
			glow.Name = "CrownGlow"
			glow.Color = crownHost.Color
			glow.Brightness = 0
			glow.Range = math.clamp(reach * 1.5, 8, 30)
			glow.Shadows = false
			glow.Enabled = false
			glow.Parent = crownHost

			self.crownLight = glow
			self.crownLightColor = crownHost.Color
		end
	end
end

--[[
	The streak, on or off.

	Idempotent, because the hop cycle sets it every frame it is in the air and
	the attacks that borrow it do not know what the hop cycle wanted.
]]
function SlimeBody:setTrail(on: boolean)
	if self.trail then
		self.trail.Enabled = on
	end
end

-- The crown's own streak, for the throw in Coronation. Silently nothing when
-- the crown is a model, or when nothing called lightUp; see lightUp.
function SlimeBody:setCrownTrail(on: boolean)
	if self.crownTrail then
		self.crownTrail.Enabled = on
	end
end

-- The crown burning. `color` is optional; nil is the crown's own colour.
-- Idempotent and silently nothing without lightUp, like the trails.
function SlimeBody:setCrownGlow(on: boolean, color: Color3?)
	local glow = self.crownLight
	if not (glow and glow.Parent) then
		return
	end
	glow.Enabled = on
	glow.Brightness = if on then 3 else 0
	glow.Color = color or self.crownLightColor or glow.Color
end

--[[
	Poses the crown ON HIS HEAD without taking it off: lifted by `lift` studs
	and turned by `tilt`, applied on top of its resting seat by every reseat
	from now on, so it rides every squash and stretch exactly as before - just
	higher, or leaning.

	For the attacks where the crown does something but stays his: it rises
	when he commands, it leans toward the ground he is about to take. Clear
	with no arguments. Unlike detachCrown there is nothing to restore, which
	is the point: a pose cannot be left half-done by an error, the next
	setCrownPose() puts everything back.
]]
function SlimeBody:setCrownPose(lift: number?, tilt: CFrame?)
	self.crownLift = if lift and lift ~= 0 then lift else nil
	self.crownTilt = tilt
	if not self.crownDetached then
		self:reseatCrown()
	end
end

-- ---------------------------------------------------------------------------
-- The crown
-- ---------------------------------------------------------------------------

function SlimeBody:_crownCFrame(): CFrame
	if self.crown:IsA("Model") then
		return self.crown:GetPivot()
	end
	return (self.crown :: BasePart).CFrame
end

function SlimeBody:moveCrown(cframe: CFrame)
	if not self.crown then
		return
	end

	if self.crown:IsA("Model") then
		self.crown:PivotTo(cframe)
	else
		(self.crown :: BasePart).CFrame = cframe
	end
end

--[[
	Puts the crown back where it belongs on whatever shape he is currently in.

	The offset is scaled PER AXIS by how much the body has stretched on that
	axis, so the crown rides the deformation exactly as if it were welded on and
	scaled with him: it comes down when he flattens, rises when he stretches,
	and swings out when he bulges sideways. Rotation comes from the body's own
	CFrame, so it turns with him for free.
]]
function SlimeBody:reseatCrown()
	if not (self.crown and self.crownOffset) then
		return
	end

	local part = self.body :: BasePart
	local base = self.baseSize
	local size = part.Size
	local offset = self.crownOffset.Position

	local scaled = Vector3.new(
		offset.X * (size.X / base.X),
		offset.Y * (size.Y / base.Y),
		offset.Z * (size.Z / base.Z)
	)

	-- The pose, if any, sits between the seat and the crown's own rotation:
	-- lifted straight up his axis, then leaned, then the artist's rotation.
	local seat = part.CFrame * CFrame.new(scaled)
	if self.crownLift then
		seat = seat * CFrame.new(0, self.crownLift, 0)
	end
	if self.crownTilt then
		seat = seat * self.crownTilt
	end

	self:moveCrown(seat * self.crownOffset.Rotation)

	-- Rigid, so only mass touches it - never the squash.
	if self.crownBaseSize then
		(self.crown :: BasePart).Size = self.crownBaseSize * self.mass
	elseif self.crownBaseScale then
		(self.crown :: Model):ScaleTo(self.crownBaseScale * self.mass)
	end
end

--[[
	Takes the crown off and gives back a function that puts it exactly back.

	For the one attack that throws it. Returning the restore rather than
	remembering it internally means an attack that dies halfway through cannot
	leave the body believing the crown is somewhere it is not.
]]
function SlimeBody:detachCrown(): (() -> ())?
	if not self.crown then
		return nil
	end

	local held = true

	self.crownDetached = true

	return function()
		if not held then
			return
		end
		held = false
		self.crownDetached = false
		self:reseatCrown()
	end
end

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

--[[
	Sets his shape immediately. Everything else here is built on this.

	The order matters: resize, then lift by however much the bottom moved, then
	re-measure the feet, then put the crown back. Doing the lift after the
	re-measure would measure a body that is momentarily half in the floor.
]]
function SlimeBody:shape(width: number, height: number, depth: number?)
	self.width = math.max(0.05, width)
	self.height = math.max(0.05, height)

	--[[
		`depth` is along his FACING, and defaults to width.

		The body part is rotated by EnemyService.placeModel to look at whoever
		he is fighting, so its local Z axis points at them - which means a depth
		of 1.7 is a bulge reaching TOWARD the player and not just a fatter
		slime. Every attack that gathers itself on one side to throw something
		uses it, and it is the difference between a cannon that looks aimed and
		one that looks like a hiccup.
	]]
	self.depth = math.max(0.05, depth or width)

	local before = bottomOf(self)

	if self.deformable then
		local base = self.baseSize
		local part = self.body :: BasePart

		part.Size = Vector3.new(
			base.X * self.width * self.mass,
			base.Y * self.height * self.mass,
			base.Z * self.depth * self.mass
		)
	else
		-- Uniform only. See the note at the top about why.
		self.model:ScaleTo(
			self.baseScale * self.mass * ((self.width + self.height + self.depth) / 3)
		)
	end

	local after = bottomOf(self)
	self.model:PivotTo(self.model:GetPivot() + Vector3.new(0, before - after, 0))

	--[[
		Crown first, THEN measure.

		It was the other way round, which meant the measurement was taken and
		then immediately invalidated by moving the crown - so `feetOffset`
		described a model that no longer existed, by however far the crown had
		just travelled. The explicit bottom below makes that harmless anyway;
		doing it in the right order makes `height` right as well.
	]]
	if not self.crownDetached then
		self:reseatCrown()
	end

	EnemyService.remeasure(self.entry, bottomOf(self))
end

--[[
	How much of him there is.

	Separate from shape because it PERSISTS: a division leaves him smaller until
	he absorbs something back, through every squash and stretch in between.
	Multiplied into the shape rather than replacing it, so 0.7 mass in a pancake
	is a smaller pancake and not a sphere.
]]
function SlimeBody:setMass(mass: number)
	self.mass = math.clamp(mass, 0.25, 1.6)
	self:shape(self.width, self.height)

	-- His glow is how much of him there is, not what shape it is in. Mass only,
	-- for the same reason the crown scales on mass only: a flattened king still
	-- lights the room like a whole king, he is just lying down.
	if self.light and self.light.Parent then
		self.light.Range = math.clamp(self.glowRange * self.mass, 10, 60)
	end
end

function SlimeBody:getMass(): number
	return self.mass
end

--[[
	Animates to a shape over `seconds`.

	Stepped by hand rather than by TweenService, because the thing being
	animated is not a property - it is two numbers that have to be recomposed
	into a Size, a pivot lift and a crown position every frame. A tween on Size
	alone would sink him into the floor and leave his hat behind.
]]
function SlimeBody:ease(width: number, height: number, seconds: number, depth: number?)
	self.easing = {
		fromWidth = self.width,
		fromHeight = self.height,
		fromDepth = self.depth,
		toWidth = width,
		toHeight = height,
		toDepth = depth or width,
		started = os.clock(),
		seconds = math.max(0.01, seconds),
	}
end

--[[
	The two shapes a hop is made of, named.

	Every hopping thing in the game does the same three things - gather, throw
	itself, splat - and these are the first two. They exist as methods rather
	than as two call sites reaching into SlimeBody.SquashJump so that a caller
	which only wants a bounce never has to hold the module table, and so that
	retuning the crouch retunes it for the boss and for every slime at once.

	The third is `wobble`, below, which needs a number the caller chooses: how
	hard the landing was.
]]
function SlimeBody:crouch(seconds: number)
	self:ease(SlimeBody.SquashJump.width, SlimeBody.SquashJump.height, seconds)
end

function SlimeBody:stretch(seconds: number)
	self:ease(SlimeBody.StretchFly.width, SlimeBody.StretchFly.height, seconds)
end

--[[
	The jelly settling: a damped oscillation between squashed and stretched.

	It is what sells the whole thing. A blob that lands and is immediately a
	sphere again is a ball; a blob that lands, splats, overshoots, and rings
	down over half a second is made of slime. The amplitude is what a landing
	is worth, not the shape itself, so a big drop wobbles harder.
]]
function SlimeBody:wobble(seconds: number, amplitude: number?)
	self.easing = nil
	self.wobbleFrom = os.clock()
	self.wobbleUntil = self.wobbleFrom + math.max(0.05, seconds)
	self.wobbleAmplitude = amplitude or 0.3
end

--[[
	Advances whatever animation is running. Called every tick by the fight.

	Wobble beats ease, and both are dropped the moment an attack sets a shape
	outright - an attack has an opinion about what shape he is, and a settling
	jiggle underneath it would fight that opinion frame by frame.
]]
function SlimeBody:step()
	local now = os.clock()

	if self.wobbleUntil then
		if now >= self.wobbleUntil then
			self.wobbleUntil = nil
			self:shape(1, 1)
			return
		end

		local elapsed = now - self.wobbleFrom
		local life = self.wobbleUntil - self.wobbleFrom
		local decay = 1 - elapsed / life

		-- Three rings over the life of it, dying away. Width moves opposite to
		-- height, which is what makes it read as one volume rather than two
		-- independent numbers.
		local swing = math.sin(elapsed * math.pi * 2 * 3) * self.wobbleAmplitude * decay * decay

		self:shape(1 + swing, 1 - swing)
		return
	end

	local easing = self.easing
	if not easing then
		return
	end

	local alpha = (now - easing.started) / easing.seconds

	if alpha >= 1 then
		self.easing = nil
		self:shape(easing.toWidth, easing.toHeight, easing.toDepth)
		return
	end

	-- Smoothstep: a blob does not change shape linearly, it accelerates out of
	-- one form and settles into the next.
	local eased = alpha * alpha * (3 - 2 * alpha)

	self:shape(
		easing.fromWidth + (easing.toWidth - easing.fromWidth) * eased,
		easing.fromHeight + (easing.toHeight - easing.fromHeight) * eased,
		easing.fromDepth + (easing.toDepth - easing.fromDepth) * eased
	)
end

--[[
	How far his body reaches across the ground, right now, in studs.

	Read live off the part rather than computed from the multipliers, so it is
	true during an ease and true after the artist rescales the model. This is
	what contact damage and the pancake are measured against: the danger is the
	shape he is actually in, not a radius somebody wrote down.
]]
function SlimeBody:radius(): number
	if self.deformable then
		local size = (self.body :: BasePart).Size
		return math.max(size.X, size.Z) * 0.5
	end

	local _, size = self.model:GetBoundingBox()
	return math.max(size.X, size.Z) * 0.5
end

--[[
	Is he mid-transformation?

	The fight asks before starting anything that needs him to be a particular
	shape, so an attack cannot begin while the last one is still unfolding him.
]]
function SlimeBody:isAnimating(): boolean
	return self.easing ~= nil or self.wobbleUntil ~= nil
end

-- ---------------------------------------------------------------------------
-- Colour
-- ---------------------------------------------------------------------------

--[[
	A flash, and back to whatever colour the artist chose.

	The resting colour is read at the START OF A RUN of flashes rather than at
	each one, and only the last flash of the run restores it. Reading it fresh
	every time looks equivalent and is not: two flashes that overlap - which a
	phase change and a hit landing in the same second will do - have the second
	read the FIRST one's colour as the resting one, and he keeps it for the rest
	of the fight. The depth count is what makes the last one the only restorer.

	Nor is the resting colour stored at construction, so a model whose colour is
	changed for any other reason is not reverted to its import colour by this.

	The light goes with him. A body that flashes white while the room it is
	lighting stays green reads as a texture change rather than as the thing
	itself doing something.
]]
function SlimeBody:flash(color: Color3, seconds: number)
	if not self.deformable then
		return
	end

	local part = self.body :: BasePart

	if self.flashDepth == 0 then
		self.restColor = part.Color
	end
	self.flashDepth += 1

	local rest = self.restColor
	local light = self.light

	part.Color = color

	if light and light.Parent then
		light.Color = color
		light.Brightness = GLOW_BRIGHTNESS * GLOW_FLASH
	end

	task.delay(seconds, function()
		self.flashDepth -= 1

		if self.flashDepth > 0 or not part.Parent then
			return
		end

		part.Color = rest

		if light and light.Parent then
			light.Color = rest
			light.Brightness = GLOW_BRIGHTNESS
		end
	end)
end

return SlimeBody
