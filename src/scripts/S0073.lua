--[[
	SacredRainPlan

	The shape of one Sacred Rain cast: where each of the fifteen strikes starts,
	where it lands, and when everything happens.

	WHY THIS IS SHARED, AND WHY IT IS SEEDED

	The server has to know where the swords land, because that is where the
	damage is. The client has to know the same thing, because that is where the
	swords are drawn. If the server sent fifteen positions the packet would be
	fifteen times larger than it needs to be; if the client picked them, the
	client would be choosing where damage lands.

	So the server picks ONE number - a seed - and both sides expand it through
	this module. The packet is a seed, a CFrame and a position; the layouts are
	identical because the arithmetic is identical, and the client still decides
	nothing.

	That only holds while both sides draw from the stream in the same order, so
	`build` does all of its rolling up front, in one loop, and never branches on
	anything either side could disagree about.

	EVERY NUMBER BELOW IS THE REFERENCE'S

	Taken from the Script under StarterPack.Gate.Event in SacredSwords.rbxlx.
	Nothing here is retuned, rounded or invented; where the reference does
	something odd it is reproduced and the oddity is noted. Tuning the ability
	means editing this table.
]]

local SacredRainPlan = {}

local Tuning = {
	-- for i = 1, 15 ... task.wait(0.2)
	Strikes = 15,
	StrikeInterval = 0.2,

	-- Start.CFrame = RootPart.CFrame * CFrame.new(0, 45, 0)
	StartHeight = 45,

	--[[
		StartCFrame = Start.CFrame * CFrame.new(
			math.random(-75, 20), math.random(-20, 20), math.random(-20, 20))

		The X range really is asymmetric in the reference. It reads like a typo
		for -20..20, and it is what produces the barrage's characteristic sweep
		out to one side rather than a symmetrical dome, so it is kept.
	]]
	StartSpreadX = { -75, 20 },
	StartSpreadY = { -20, 20 },
	StartSpreadZ = { -20, 20 },

	-- EndPosition = End.Position + Vector3.new(math.random(-40, 40), 0, math.random(-40, 40))
	LandingSpread = 40,

	-- task.wait(0.5) between the portal opening and it bursting
	PortalBurstDelay = 0.5,

	-- TweenInfo.new(1, Linear, InOut) on the sword's Transparency, then task.wait(1)
	SwordFadeInTime = 1,

	--[[
		The reference plays that fade-in against a sword that is ALREADY opaque,
		so it is a one-second pause with no visual. Reproduced as a pause by
		default, because that is what the reference looks like.

		Set true to start the sword invisible so the tween actually reads. It is
		a deviation from the reference, which is why it is off.
	]]
	FadeSwordIn = false,

	-- TweenInfo.new(0.4, Back, In) on Position. The ease is what makes the
	-- launch snap; it is the single most recognisable part of the effect.
	TravelTime = 0.4,

	-- TweenInfo.new(1, Linear, InOut) back to Transparency = 1 after impact
	SwordFadeOutTime = 1,

	-- Debris:AddItem(CloneSword, 8) / (ClonePortal, 4)
	SwordLifetime = 8,
	PortalLifetime = 4,

	-- workspace:GetPartBoundsInBox(CloneSword.CFrame, Vector3.new(20, 20, 20))
	HitBoxSize = Vector3.new(20, 20, 20),

	--[[
		Damage per strike, once per humanoid per strike. The reference used 20.

		75 is a deviation, chosen so that a cast is worth roughly three melee
		swings of the lance that carries it (25 each).

		WHY PER STRIKE AND NOT PER CAST, GIVEN THERE ARE FIFTEEN OF THEM
		  Because a target is almost never hit by more than one. The strikes
		  scatter over LandingSpread (40 studs each way) while HitBoxSize only
		  reaches 10, so a stationary target standing dead centre is inside any
		  given strike about 6% of the time - which over fifteen strikes averages
		  slightly under one hit. Per-strike and per-cast damage are therefore
		  close to the same number here.

		  The consequence worth knowing: it is high variance. Roughly a third of
		  casts land nothing at all on a centred target, and an unlucky one lands
		  three. If you would rather the ability were reliable than dramatic,
		  LandingSpread is the dial - not this.
	]]
	Damage = 75,

	--[[
		Sounds are created in code by the reference; there are no Sound
		instances in the place file. Both are pitched 0.8 + math.random() * 0.4.
	]]
	PortalSound = {
		id = "rbxassetid://137782657646699",
		volume = 1,
		lifetime = 3,
	},
	ImpactSound = {
		id = "rbxassetid://105248065965594",
		volume = 2,
		lifetime = 1,
	},
	PitchMin = 0.8,
	PitchMax = 1.2,

	--[[
		THE RHYTHM. Not the reference's - this is the one deliberate rewrite of
		its timing, and the rest of the file stays a faithful record around it.

		The reference drops fifteen blades exactly 0.2s apart. That is a loop,
		and it reads as one: after the third blade there is no information left
		in the effect, and the remaining twelve are the same beat repeated while
		you wait for it to stop.

		This shapes the same fifteen into three movements.

		  HERALD  two or three blades, well spaced. Slow enough that each lands
		          alone and is read as a single event rather than as texture.
		          This is the telegraph, and it is what makes the next part feel
		          like it accelerated rather than like it merely continued.

		  FALL    the bulk, with the gap shrinking every blade. Nothing changes
		          about the blades themselves; the compression alone is what
		          turns a list into a collapse.

		  FINALE  a held silence, then one last blade. The pause is the whole
		          trick - a gap after an accelerating run reads as the thing
		          having finished, so the strike that follows arrives after the
		          listener has already relaxed.

		The finale also lands DEAD CENTRE, ignoring its scatter roll, and hits
		for FinaleDamageScale times the rest. That is a mechanical change as much
		as a dramatic one: every other blade scatters over LandingSpread and can
		miss entirely, so before this an unlucky cast did nothing at all. Now the
		last one always connects, and the barrage around it is the bonus.
	]]
	Rhythm = {
		HeraldStrikes = 3,
		HeraldInterval = 0.34,

		-- Gap between blades at the start and end of the fall. Interpolated
		-- linearly across it, so the acceleration is steady rather than sudden.
		FallIntervalStart = 0.18,
		FallIntervalEnd = 0.07,

		-- The silence before the last blade.
		FinaleGap = 0.55,
	},

	FinaleDamageScale = 2,

	--[[
		THE FINALE'S OWN LOOK.

		The other fourteen blades fall on a diagonal, from a scattered point
		high off the caster's shoulder. That reads as barrage - none of them is
		aimed, and the angle is what says so.

		The last one IS aimed, so it should not arrive on the same angle as the
		ones that were not. It opens its portal directly over the mark and drops
		straight down the vertical, at FinaleScale times the size of the rest
		and in FinaleColor. Three separate signals - line, size, colour - all
		saying the same thing about the same blade.

		FinaleStartHeight is measured from the TARGET, not from the caster the
		way StartHeight is, because the point of the change is that the finale's
		geometry stops referring to where the caster happens to be standing.
	]]
	FinaleStartHeight = 60,
	FinaleScale = 2.6,
	FinaleColor = Color3.fromRGB(8, 8, 10),
}

SacredRainPlan.Tuning = Tuning

--[[
	When the strike at `index` is cast, in seconds from the start.

	The single source of truth for the barrage's timing: `build` stamps it onto
	each strike and `duration` measures the tail from it, so the two cannot drift
	apart the way they would if each did its own arithmetic.
]]
local function castTimeFor(index: number): number
	local rhythm = Tuning.Rhythm
	local total = Tuning.Strikes

	local herald = math.min(rhythm.HeraldStrikes, total)

	-- Herald: evenly spaced, and the only part of the barrage that is.
	if index <= herald then
		return (index - 1) * rhythm.HeraldInterval
	end

	local time = (herald - 1) * rhythm.HeraldInterval

	-- Everything between the herald and the finale. One fewer than it looks,
	-- because the last strike is the finale and is timed off the gap instead.
	local fallCount = math.max(0, total - herald - 1)
	local fallIndex = math.min(index - herald, fallCount)

	for step = 1, fallIndex do
		local progress = if fallCount > 1 then (step - 1) / (fallCount - 1) else 0
		time += rhythm.FallIntervalStart
			+ (rhythm.FallIntervalEnd - rhythm.FallIntervalStart) * progress
	end

	if index > herald + fallCount then
		time += rhythm.FinaleGap
	end

	return time
end

SacredRainPlan.castTimeFor = castTimeFor

--[[
	How long a cast runs for, end to end.

	The last strike is cast at (Strikes - 1) * StrikeInterval and lands
	PortalBurstDelay + SwordFadeInTime + TravelTime later, and its own sword
	lingers after that. Used by the server to decide when a cast is over and its
	scope can be torn down.

	The reference's ground marker used to outlive all of it and set this on its
	own; it is no longer drawn, so the last sword is now the end of the cast.
]]
function SacredRainPlan.duration(): number
	-- Measured through castTimeFor rather than recomputed, so the rhythm above
	-- is the only place the barrage's length is decided.
	local lastCast = castTimeFor(Tuning.Strikes)

	local strikeLength = Tuning.PortalBurstDelay + Tuning.SwordFadeInTime + Tuning.TravelTime
	local swordTail = strikeLength + math.max(Tuning.SwordFadeOutTime, Tuning.SwordLifetime)

	return lastCast + swordTail
end

export type Strike = {
	index: number,
	finale: boolean,
	damageScale: number,
	castAt: number,
	startCFrame: CFrame,
	endPosition: Vector3,
	portalPitch: number,
	impactPitch: number,
}

export type Plan = {
	seed: number,
	origin: CFrame,
	target: Vector3,
	strikes: { Strike },
}

--[[
	Expands a seed into the full cast.

	`origin` is the caster's HumanoidRootPart CFrame at the moment of casting -
	the reference anchors an invisible part there and never moves it, so the
	barrage keeps its shape even if the caster runs off. `target` is where the
	marker goes.

	Deterministic for a given (seed, origin, target): call it on the server for
	the damage and on every client for the visuals and they agree exactly.
]]
function SacredRainPlan.build(seed: number, origin: CFrame, target: Vector3): Plan
	local rng = Random.new(seed)
	local startCFrame = origin * CFrame.new(0, Tuning.StartHeight, 0)

	local strikes = table.create(Tuning.Strikes)

	for index = 1, Tuning.Strikes do
		-- ORDER MATTERS. Seven draws per strike, always in this order, or the
		-- client and the server stop describing the same barrage.
		local offsetX = rng:NextInteger(Tuning.StartSpreadX[1], Tuning.StartSpreadX[2])
		local offsetY = rng:NextInteger(Tuning.StartSpreadY[1], Tuning.StartSpreadY[2])
		local offsetZ = rng:NextInteger(Tuning.StartSpreadZ[1], Tuning.StartSpreadZ[2])
		local landX = rng:NextInteger(-Tuning.LandingSpread, Tuning.LandingSpread)
		local landZ = rng:NextInteger(-Tuning.LandingSpread, Tuning.LandingSpread)
		local portalPitch = rng:NextNumber(Tuning.PitchMin, Tuning.PitchMax)
		local impactPitch = rng:NextNumber(Tuning.PitchMin, Tuning.PitchMax)

		local from = startCFrame * CFrame.new(offsetX, offsetY, offsetZ)

		--[[
			The last blade ignores its scatter and lands on the mark.

			Note that the two rolls above still HAPPEN for it - they are drawn
			and then discarded. That is deliberate: the seven draws per strike
			have to stay seven, in the same order, or the client's barrage stops
			matching the server's from this strike onward.
		]]
		local isFinale = index == Tuning.Strikes
		local to = if isFinale then target else target + Vector3.new(landX, 0, landZ)

		--[[
			And it falls straight down onto it, from directly overhead, rather
			than in off the same diagonal as the rest.

			CFrame.lookAt cannot build a straight-down frame on its own: its
			default up vector is +Y, which is the very axis it is being asked to
			look along, and a look direction parallel to up has no solution. So
			the finale passes its own up - the caster's facing, flattened. That
			decides only the blade's roll about the vertical, and being
			horizontal it cannot be parallel to the drop.
		]]
		local look: CFrame

		if isFinale then
			local above = to + Vector3.new(0, Tuning.FinaleStartHeight, 0)

			local facing = origin.LookVector * Vector3.new(1, 0, 1)
			local up = if facing.Magnitude > 1e-4 then facing.Unit else Vector3.new(0, 0, -1)

			look = CFrame.lookAt(above, to, up)
		else
			look = CFrame.lookAt(from.Position, to)
		end

		strikes[index] = {
			index = index,
			finale = isFinale,
			damageScale = if isFinale then Tuning.FinaleDamageScale else 1,
			castAt = castTimeFor(index),
			-- The reference orients both the portal and the sword with
			-- CFrame.lookAt(portalPosition, endPosition), so the blade points
			-- down its own flight path from the moment it appears. That still
			-- holds for the finale; its path is simply vertical.
			startCFrame = look,
			endPosition = to,
			portalPitch = portalPitch,
			impactPitch = impactPitch,
		}
	end

	return {
		seed = seed,
		origin = origin,
		target = target,
		strikes = strikes,
	}
end

return SacredRainPlan
