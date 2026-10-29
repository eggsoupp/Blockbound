--[[
	Evil Rat - the Crimson's vermin. They come in packs and never just stand
	and trade blows: each rat darts in, bites, and scurries off to a few
	blocks away, circles, and comes again. One is a nuisance; a pack is a
	rhythm of bites from every side that rewards turning to meet each one.

	Its legs, head and tail are jointed (Shared.Enemies.CreatureRigs.EvilRat),
	trotting at the pace it actually runs.

	  approach  straight in at `dashSpeed`
	  bite      within `biteRange`: a quick head-down snap, `biteDamage`
	  flee      away from you at `fleeSpeed` for `fleeSeconds`, swerving
	  circle    hang about `circleDistance` off for `circleSeconds`, then
	            approach again

	It slides over the ground; a step it cannot slide up is handed to the
	ordinary hop movement for that tick, which jumps it.
]]

local CreatureKit = require(script.Parent.CreatureKit)

local Tuning = {
	dashSpeed = 15,
	fleeSpeed = 14,
	circleSpeed = 9,
	slideStep = 2,

	biteRange = 3.2,
	biteSeconds = 0.22,
	biteDamage = 5,

	fleeSeconds = NumberRange.new(0.6, 1.1),
	circleDistance = 9,
	circleSeconds = NumberRange.new(0.8, 1.8),
}

local Trait = {}
Trait.Tuning = Tuning

local function roll(range: NumberRange): number
	return range.Min + math.random() * (range.Max - range.Min)
end

local function run(entry, direction: Vector3, speed: number, dt: number, look: Vector3?): boolean
	return CreatureKit.slide(entry, direction * speed * dt, look or direction, nil, Tuning.slideStep)
end

function Trait.start(entry)
	entry.model:SetAttribute("Rig", "EvilRat")
	entry.mode = "approach"
	entry.swerve = if math.random() < 0.5 then 1 else -1
end

function Trait.step(entry, target, targetPosition, position, dt, now)
	if entry.state ~= "Grounded" then
		return false
	end
	if not (target and targetPosition) then
		CreatureKit.pose(entry, "walk")
		return false
	end

	local toward = CreatureKit.flat(targetPosition - position)
	local across = toward:Cross(Vector3.yAxis) * entry.swerve
	local distance = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z).Magnitude

	if entry.mode == "bite" then
		if now >= entry.modeUntil then
			entry.mode = "flee"
			entry.modeUntil = now + roll(Tuning.fleeSeconds)
			entry.swerve = if math.random() < 0.5 then 1 else -1
			CreatureKit.pose(entry, "flee")
		else
			CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		end
		return true
	end

	if entry.mode == "flee" then
		if now >= entry.modeUntil then
			entry.mode = "circle"
			entry.modeUntil = now + roll(Tuning.circleSeconds)
			CreatureKit.pose(entry, "walk")
		end
		local away = (-toward + across * 0.6).Unit
		return run(entry, away, Tuning.fleeSpeed, dt)
	end

	if entry.mode == "circle" then
		if now >= entry.modeUntil then
			entry.mode = "approach"
		end
		-- Round you, drifting back to its distance, watching you.
		local drift = math.clamp((distance - Tuning.circleDistance) / 4, -1, 1)
		local move = (across + toward * drift)
		move = if move.Magnitude > 1e-3 then move.Unit else across
		return run(entry, move, Tuning.circleSpeed, dt, toward)
	end

	-- Approach, and bite on arrival.
	if distance <= Tuning.biteRange then
		entry.mode = "bite"
		entry.modeUntil = now + Tuning.biteSeconds
		CreatureKit.pose(entry, "bite")
		CreatureKit.place(entry, CreatureKit.feet(entry), toward)
		local head = CreatureKit.feet(entry) + toward * 1.5 + Vector3.new(0, entry.height * 0.5, 0)
		CreatureKit.service().touch(entry, head, Tuning.biteDamage)
		return true
	end
	CreatureKit.pose(entry, "walk")
	return run(entry, toward, Tuning.dashSpeed, dt)
end

return Trait
