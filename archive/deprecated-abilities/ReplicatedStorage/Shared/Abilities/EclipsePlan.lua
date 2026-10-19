--[[
	EclipsePlan

	The shape of one Eclipse cast: how long the wind-up is, how far the wave
	reaches, and what standing at a given distance costs.

	WHY THIS IS SHARED

	Same reason as SacredRainPlan. The server decides who was hurt and the
	client decides what that looked like, and the two have to agree about when
	the wave arrives and how far it went - or the ring passes through somebody a
	quarter of a second after their health dropped.

	Unlike Sacred Rain there is nothing random here, so there is no seed: the
	cast is entirely determined by where the caster was standing. The packet is
	one CFrame.

	NONE OF THESE NUMBERS COME FROM ANYWHERE

	Sacred Rain is a transcription of a reference place, and its tuning file says
	so on every line. This ability has no reference. Every number below was
	chosen here, and the reasoning is written next to it so the next person can
	disagree with the reasoning rather than guess at the intent.
]]

local EclipsePlan = {}

--[[
	WHAT THIS IS SIZED AGAINST

	The LightLance is the end of the game. It is drop-only, Legendary, and a
	player holding one has put hours into getting there - so the numbers below
	are written for the moment they press the key rather than for a spreadsheet.
	Every one of them was raised deliberately from the first pass, which was
	tuned like a mid-game defensive move and read like one.

	The shape of the reward is: a long, unmistakable wind-up that everyone
	nearby can see, and then something that clears the ground.
]]
local Tuning = {
	--[[
		THE WIND-UP.

		Deliberately long for an instant ability. Eight tenths of a second is
		enough to be a real telegraph - the people standing in it can leave -
		and, more to the point, it is long enough to be an EVENT: a black star
		the size of a car opens over the caster and the ground starts coming
		apart before anything has happened yet.

		Power in a game is mostly anticipation. This is where it lives.
	]]
	ChargeTime = 0.8,

	-- The orb's final radius at the end of the wind-up, in studs. Read as a
	-- radius rather than a size because everything else here is a radius.
	-- At 5.5 it is taller than the person casting it, which is the point.
	CoreRadius = 5.5,

	-- How high above the caster's root the orb hangs. High enough now that it
	-- reads as something summoned over them rather than something held.
	CoreHeight = 3,

	--[[
		HOW FAR THE WAVE GOES.

		44 studs, out from 26. That is wider than Sacred Rain's entire landing
		spread and about seven character-widths in every direction: cast into a
		group and there is no edge of it to stand on.

		This is the number that decides whether the ability feels endgame, and it
		is the one the ring, the scorch, the streaks and the smoke all scale
		themselves off - so moving it moves the whole effect with it rather than
		leaving the visuals describing a blast that is no longer that size.
	]]
	Radius = 44,

	-- How long the ring takes to reach that radius. Longer than before because
	-- the distance nearly doubled; the wave still crosses the ground at about
	-- seventy studs a second, which is faster than anything can run.
	RingTime = 0.62,

	--[[
		The aftermath: smoke standing in the crater, ash coming down, the scorch
		fading. Purely visual, and nothing during it is dangerous.

		Long on purpose. A blast that is over the instant it lands reads as a
		firework; one that leaves the place looking hit reads as a weapon.
	]]
	SettleTime = 3.6,

	--[[
		DAMAGE, AND WHY IT FALLS OFF.

		140 at the caster's feet down to 77 at the rim.

		Anchored against the weapon's other ability: Sacred Rain is 75 a blade
		with a 150 finale, fifteen blades scattered over 40 studs, and on a
		single target it lands one or two of them. So this is worth about two
		blades at the edge and about the finale at the centre - except that it
		cannot miss, hits everything at once, and is over in under a second.

		That is a lot. It is meant to be: it is the panic button on a weapon
		that takes hours to earn, and the twelve-second cooldown is what it
		costs. The falloff is the counterplay - standing on top of the caster is
		nearly twice as bad as being caught at the rim.
	]]
	Damage = 140,
	EdgeDamageScale = 0.55,

	--[[
		A ceiling on how many parts the server will look at when finding players.

		Doubled with the radius. Same reasoning as Sacred Rain's: in a world made
		of blocks a 44-stud sphere is mostly terrain, and the terrain is excluded
		from the query for exactly that reason - but a crowd standing in the
		middle of one is a lot of character parts, and the cap has to be able to
		see past them to the next person.
	]]
	MaxParts = 120,
}

EclipsePlan.Tuning = Tuning

--[[
	When the wave arrives, in seconds from the cast. One number, used by the
	server to time the damage and by the VFX to time the burst, so they cannot
	drift apart.
]]
function EclipsePlan.impactAt(): number
	return Tuning.ChargeTime
end

--[[
	What a target `distance` studs from the centre takes.

	Linear from Damage at the centre to Damage * EdgeDamageScale at the rim, and
	zero past it. Linear rather than inverse-square because inverse-square makes
	the outer two thirds of the radius meaningless, and the outer two thirds is
	where most people standing in it actually are.
]]
function EclipsePlan.damageAt(distance: number): number
	if distance >= Tuning.Radius then
		return 0
	end

	local t = math.clamp(distance / Tuning.Radius, 0, 1)
	local scale = 1 + (Tuning.EdgeDamageScale - 1) * t

	return Tuning.Damage * scale
end

--[[
	How long the whole cast takes, end to end. The server tears the cast's scope
	down after this, and the client tears the visuals down after it too.
]]
function EclipsePlan.duration(): number
	return Tuning.ChargeTime + Tuning.RingTime + Tuning.SettleTime
end

return EclipsePlan
