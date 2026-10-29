--[[
	Builds a winged creature as three unions - Body, LeftWing, RightWing - with
	each wing on a Motor6D hinged at its shoulder, so StarterPlayerScripts.
	CreatureFX can flap the wings independently of the body.

	A ModuleScript for Studio (Edit): require it and call
	  Build.build(boxesData, voxelSize, assetName, Build.Split.<Kind>, flap)
	The model carries ArticulatedRig = true, so EnemyService anchors only the
	body and the wings ride their joints; the pivot is the body's centre.

	`flap` = { rate = Hz, angle = degrees, glide = 0..1 } is stored as
	attributes the client reads (WingRate, WingAngle, WingGlide).
]]

local Build = {}

-- Which part a box belongs to: "Body", "LeftWing" or "RightWing".
-- Box fields are in the boxes file's voxel units: x, y, z, w, h, d, colour.
Build.Split = {
	-- The membrane is colour 1 above the body; a box straddling the middle
	-- is the root bar across the back and stays on the body.
	GreenWasp = function(x, y, _z, w, _h, _d, c)
		if c ~= 1 or y < 45 then return "Body" end
		if x + w <= 50 then return "LeftWing" end
		if x >= 50 then return "RightWing" end
		return "Body"
	end,
	-- For buildJointed: the coil on the ground, the raised neck, the hooded
	-- head. Boxes go by their bottom row.
	Cobra = function(_x, y)
		if y < 8 then return "Coil" end
		if y < 36 then return "Neck" end
		return "Head"
	end,
	-- Body is the middle band; every other box joins the leg whose line
	-- (root to tip, traced from a top-down map, voxel x/z) it is nearest.
	GreenSpider = (function()
		local legs = {
			L1 = { 70, 16, 40, 4 }, L2 = { 70, 21, 30, 20 }, L3 = { 68, 26, 30, 36 }, L4 = { 68, 32, 38, 50 },
			R1 = { 90, 16, 114, 4 }, R2 = { 90, 21, 126, 20 }, R3 = { 92, 26, 126, 35 }, R4 = { 92, 32, 116, 50 },
		}
		local function distance(px, pz, l)
			local ax, az, bx, bz = l[1], l[2], l[3], l[4]
			local dx, dz = bx - ax, bz - az
			local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz), 0, 1)
			return math.sqrt((ax + dx * t - px) ^ 2 + (az + dz * t - pz) ^ 2)
		end
		return function(x, _y, z, w, _h, d)
			local cx, cz = x + w / 2, z + d / 2
			if cx >= 70 and cx <= 91 then return "Body" end
			local best, bestDistance = "Body", math.huge
			for name, line in pairs(legs) do
				local dist = distance(cx, cz, line)
				if dist < bestDistance then best, bestDistance = name, dist end
			end
			return best
		end
	end)(),
	-- Head in front, tail behind, and below the belly (top at row 7 or
	-- lower) four legs, front or back by where they stand and left or right
	-- of the spine at x 43.
	EvilRat = function(x, y, z, w, h, d)
		local cz = z + d / 2
		if cz < 14 then return "Head" end
		if cz >= 51 then return "Tail" end
		if y + h <= 7 then
			local side = if x + w / 2 < 43 then "L" else "R"
			return (if cz < 32 then "F" else "B") .. side
		end
		return "Body"
	end,
	-- A horned imp holding a halberd across its waist: the halberd is its
	-- wood (colours 1 and 2) plus the blade end (x > 96), and rides the right
	-- arm; the head is above row 50; arms either side of x 58-82; legs below
	-- row 12.
	PitDevil = function(x, y, _z, w, h, _d, c)
		local cx = x + w / 2
		if c == 1 or c == 2 or cx > 96 then return "Weapon" end
		if y >= 50 then return "Head" end
		if y + h <= 12 and cx >= 54 and cx <= 84 then
			return if cx < 68 then "LeftLeg" else "RightLeg"
		end
		if cx < 58 then return "LeftArm" end
		if cx > 82 then return "RightArm" end
		return "Body"
	end,
	-- A crab-man: the purple pincers and everything beside the torso below row
	-- 54 are the claws, the shoulders above them the arms; head above row 69,
	-- the tail behind z 57 below row 36, legs below row 24.
	CrabMonster = function(x, y, z, w, h, _d, c)
		local cx = x + w / 2
		local side = if cx < 60 then "Left" else "Right"
		local flank = cx < 45 or cx > 76
		if c == 1 or c == 2 or (flank and y + h <= 54 and y >= 36) then return side .. "Claw" end
		if flank and y >= 54 then return side .. "Arm" end
		if z >= 57 and y + h <= 36 then return "Tail" end
		if y + h <= 24 then return side .. "Leg" end
		if y >= 69 then return "Head" end
		return "Body"
	end,
	-- A hunched stalker on four stilts: the head and neck hang forward of z 36
	-- between rows 39 and 60; legs below row 42, front ones before z 66.
	Longleg = function(x, y, z, w, h)
		local cx = x + w / 2
		if z + 1 <= 36 and y >= 39 and y < 60 then return "Head" end
		if y + h <= 42 then
			local side = if cx < 42 then "Left" else "Right"
			return (if z < 66 then "Front" else "Back") .. side .. "Leg"
		end
		return "Body"
	end,
	-- An ogre holding a double axe low in each hand: the axes are the flat
	-- layer in front of z 27; head above row 66 between x 14 and 36; arms
	-- outside x 13-37; legs below row 12.
	OgreBrute = function(x, y, z, w, h, d)
		local cx = x + w / 2
		local side = if cx < 25 then "Left" else "Right"
		if z + d <= 27 and y + h <= 40 then return side .. "Axe" end
		if y >= 66 and cx >= 14 and cx <= 36 then return "Head" end
		if y + h <= 12 then return side .. "Leg" end
		if cx < 13 or cx > 37 then return side .. "Arm" end
		return "Body"
	end,
	-- A top-hatted cat with a wand held out forward in its right hand: the
	-- wand's colours (12-15) are the wand; behind z 48 is the tail; head and
	-- hat above row 48; arms outside x 25-45; legs below row 14.
	CatMagician = function(x, y, z, w, h, _d, c)
		local cx = x + w / 2
		if c >= 12 then return "Wand" end
		if z >= 48 then return "Tail" end
		if y >= 48 then return "Head" end
		if y + h <= 14 then return if cx < 36 then "LeftLeg" else "RightLeg" end
		if cx < 25 then return "LeftArm" end
		if cx > 45 then return "RightArm" end
		return "Body"
	end,
	-- A robed goat with its staff held level in the right hand: the staff and
	-- its orb are colours 12-13; head and horns above row 50; arms outside
	-- x 34-62; legs below row 18.
	GoatShaman = function(x, y, _z, w, h, _d, c)
		local cx = x + w / 2
		if c >= 12 then return "Staff" end
		if y >= 50 then return "Head" end
		if y + h <= 18 then return if cx < 48 then "LeftLeg" else "RightLeg" end
		if cx < 34 then return "LeftArm" end
		if cx > 62 then return "RightArm" end
		return "Body"
	end,
	-- A caped tiger with its arms crossed holding two crossed swords: the arms
	-- and blades in front of z 12 between rows 18 and 72 are one part; head
	-- above row 72; legs below row 15.
	TigerBlademaster = function(x, y, z, w, h, d)
		local cx = x + w / 2
		if y >= 72 then return "Head" end
		if y + h <= 15 then return if cx < 50 then "LeftLeg" else "RightLeg" end
		if z + d <= 12 and y >= 18 then return "Blades" end
		return "Body"
	end,
	-- A hunched rotting rat: head in front of z 24 above row 20, tail behind
	-- z 62; below row 14 the front paws (before z 40) and hind legs.
	ZombieRat = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		if cz < 24 and y >= 20 then return "Head" end
		if cz >= 62 then return "Tail" end
		if y + h <= 14 then
			return (if cz < 40 then "F" else "B") .. (if cx < 46 then "L" else "R")
		end
		return "Body"
	end,
	-- A hulking lava golem: the head juts forward of z 9 above row 54; long
	-- arms outside x 7-40 below it; legs below row 22.
	LavaGolem = function(x, y, z, w, h, d)
		local cx = x + w / 2
		if y + h <= 22 then return if cx < 24 then "LeftLeg" else "RightLeg" end
		if y >= 54 and z + d <= 9 then return "Head" end
		if y + h <= 54 and cx < 7 then return "LeftArm" end
		if y + h <= 54 and cx > 40 then return "RightArm" end
		return "Body"
	end,
	-- A wingless bat standing upright: head and ears above row 45; stub arms
	-- outside x 36-69; legs below row 14.
	BatMutant = function(x, y, _z, w, h)
		local cx = x + w / 2
		if y >= 45 then return "Head" end
		if y + h <= 14 then return if cx < 52 then "LeftLeg" else "RightLeg" end
		if cx < 36 then return "LeftArm" end
		if cx > 69 then return "RightArm" end
		return "Body"
	end,
	-- A rooster: head and neck above row 32; tail behind z 32; legs below row
	-- 12; the wings are the flanks outside x 29-41.
	Rooster = function(x, y, z, w, h)
		local cx = x + w / 2
		if y >= 32 then return "Head" end
		if z >= 32 and y >= 18 then return "Tail" end
		if y + h <= 12 then return if cx < 35 then "LeftLeg" else "RightLeg" end
		if cx < 29 then return "LeftWing" end
		if cx > 41 then return "RightWing" end
		return "Body"
	end,
	-- A wild bull: head and horns in front of z 27 above row 27; tail behind
	-- z 93; legs below row 24, the front pair before z 66.
	Auroch = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		if cz < 27 and y >= 27 then return "Head" end
		if cz >= 93 then return "Tail" end
		if y + h <= 24 then
			return (if cz < 66 then "F" else "B") .. (if cx < 36 then "L" else "R")
		end
		return "Body"
	end,
	-- A lizard with a sickle raised in its right hand and a second, low in its
	-- left: the blades' greys (7, 8, 9, 16) and brown grips (1) above row 46
	-- are the right-hand Weapon, below it the OffWeapon; head above row 48;
	-- arms outside x 39-63 above row 30; tail behind z 44; legs below row 15.
	LizardWarrior = function(x, y, z, w, h, d, c)
		local cx, cz = x + w / 2, z + d / 2
		if c == 7 or c == 8 or c == 9 or c == 16 or c == 1 then
			return if y >= 46 then "Weapon" else "OffWeapon"
		end
		if y + h <= 15 then return if cx < 51 then "LeftLeg" else "RightLeg" end
		if cz >= 44 then return "Tail" end
		if y >= 48 and cx >= 42 and cx <= 60 then return "Head" end
		if y >= 30 and cx < 39 then return "LeftArm" end
		if y >= 30 and cx > 63 then return "RightArm" end
		return "Body"
	end,
	-- A vampire duck: head and long bill in front of z 24 above row 18, and
	-- the fangs hanging at its very front; legs
	-- below row 7.
	VampireDuck = function(x, y, z, w, h, d)
		local cx = x + w / 2
		if z + d <= 24 and (y >= 18 or z + d <= 6) then return "Head" end
		if y + h <= 7 then return if cx < 46 then "LeftLeg" else "RightLeg" end
		return "Body"
	end,
	-- A hunched spotted demon walking on its knuckles: head above row 54; the
	-- long arms are the outer limbs in front of z 42 (outside x 16-44); the
	-- legs are behind z 45 below row 21.
	SpottedDemon = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		if y >= 54 then return "Head" end
		if cz < 42 and cx < 16 then return "LeftArm" end
		if cz < 42 and cx > 44 then return "RightArm" end
		if cz >= 45 and y + h <= 21 then return if cx < 31 then "LeftLeg" else "RightLeg" end
		return "Body"
	end,
	-- A werewolf in a long coat with a long sword held out level in its right
	-- hand: the sword's colours (10 and up) are the Sword; head above row 62;
	-- arms outside x 25-53 above row 24; legs below row 15.
	WerewolfLord = function(x, y, _z, w, h, _d, c)
		local cx = x + w / 2
		if c >= 10 then return "Sword" end
		if y >= 62 then return "Head" end
		if y + h <= 15 then return if cx < 40 then "LeftLeg" else "RightLeg" end
		if y >= 24 and cx < 25 then return "LeftArm" end
		if y >= 24 and cx > 53 then return "RightArm" end
		return "Body"
	end,
	-- A beagle: head in front of z 16 above row 20, tail behind z 36 above
	-- row 18, legs below row 10 (front ones before z 22).
	Beagle = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		if cz < 16 and y >= 20 then return "Head" end
		if cz >= 36 and y >= 18 then return "Tail" end
		if y + h <= 10 then return (if cz < 22 then "F" else "B") .. (if cx < 35 then "L" else "R") end
		return "Body"
	end,
	-- An oryx: horned head in front of z 16 above row 32, tail behind z 46,
	-- long legs below row 20 (front ones before z 34).
	BeisaOryx = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		if cz < 16 and y >= 32 then return "Head" end
		if y + h <= 20 then return (if cz < 34 then "F" else "B") .. (if cx < 36 then "L" else "R") end
		if cz >= 46 and y >= 24 then return "Tail" end
		return "Body"
	end,
	-- A brontosaurus: neck in front of z 21 above row 42, its head above row
	-- 70; tail behind z 72; legs below row 15 (front ones before z 51).
	Bronto = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		if cz < 21 and y >= 42 then return if y >= 70 then "Head" else "Neck" end
		if cz >= 72 then return "Tail" end
		if y + h <= 15 then return (if cz < 51 then "F" else "B") .. (if cx < 28 then "L" else "R") end
		return "Body"
	end,
	-- A raptor, built facing +Z (turned round after the build): head beyond
	-- z 72 above row 30, tail before z 30, legs below row 15.
	GreenRaptor = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		if cz >= 72 and y >= 30 then return "Head" end
		if cz < 30 then return "Tail" end
		if y + h <= 15 then return if cx < 43 then "LeftLeg" else "RightLeg" end
		return "Body"
	end,
	-- A robed cat monk with a long staff held level along its left side: the
	-- staff is rows 23-29 outside the body (in front of z 31, behind z 45) or
	-- along its left flank (x < 23); head above row 57; arms outside x 23-44;
	-- legs below row 9.
	CatMonk = function(x, y, z, w, h, d)
		local cx = x + w / 2
		if y >= 23 and y + h <= 29 and (z + d <= 31 or z >= 45 or cx < 23) then return "Staff" end
		if y >= 57 then return "Head" end
		if y + h <= 9 then return if cx < 33 then "LeftLeg" else "RightLeg" end
		if cx < 23 then return "LeftArm" end
		if cx > 44 then return "RightArm" end
		return "Body"
	end,
	-- A cannon on a wheeled carriage: the iron (colours 3 and 4) is the
	-- barrel, on its own trunnion joint; the rest is the carriage.
	Cannon = function(_x, _y, _z, _w, _h, _d, c)
		return if c == 3 or c == 4 then "Barrel" else "Body"
	end,
	-- A hunched pink demon: the long arms hang outside x 46-98 between rows
	-- 12 and 50;
	-- the head is the top of it, above row 66; legs below row 16.
	PinkyDemon = function(x, y, _z, w, h)
		local cx = x + w / 2
		if y >= 12 and y + h <= 50 and cx < 46 then return "LeftArm" end
		if y >= 12 and y + h <= 50 and cx > 98 then return "RightArm" end
		if y + h <= 16 then return if cx < 78 then "LeftLeg" else "RightLeg" end
		if y >= 66 then return "Head" end
		return "Body"
	end,
	-- A tusked blob on thin legs: mouth and tusks in front of z 27, a stub of
	-- tail behind z 60, legs below row 12 between z 30 and 50.
	HandlessNorg = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		if cz < 27 then return "Head" end
		if y + h <= 12 and cz >= 30 and cz <= 50 then return if cx < 39 then "LeftLeg" else "RightLeg" end
		if cz >= 60 then return "Tail" end
		return "Body"
	end,
	-- A ring-tailed lemur with a long blade held level along its left side:
	-- the blade (colours 1 and 2) is the Sword; the tail is
	-- behind z 27 above row 21; head above row 54; arms the outer columns
	-- (outside x 3-21); legs below row 10.
	LemurianWarrior = function(x, y, z, w, h, d, c)
		local cx, cz = x + w / 2, z + d / 2
		if c == 1 or c == 2 then return "Sword" end
		if cz >= 27 and y >= 21 then return "Tail" end
		if y + h <= 10 then return if cx < 12 then "LeftLeg" else "RightLeg" end
		if y >= 54 then return "Head" end
		if cx < 3 then return "LeftArm" end
		if cx > 21 then return "RightArm" end
		return "Body"
	end,
	-- A robed bear: head above row 33, the staff arm left of x 30, the orb
	-- arm right of x 60, legs below row 9.
	BearidWizard = function(x, y, _z, w, h)
		local cx = x + w / 2
		if cx < 30 then return "LeftArm" end
		if cx > 60 then return "RightArm" end
		if y >= 33 then return "Head" end
		if y + h <= 9 then
			return if cx < 45 then "LeftLeg" else "RightLeg"
		end
		return "Body"
	end,
	-- An upright fish: tail fin behind z 29, a lower jaw (front, below row
	-- 13), and four short legs a side below row 8, in z bands.
	FootedPiranha = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		if cz >= 29 then return "Tail" end
		if y + h <= 8 then
			local band = if cz < 10 then 1 elseif cz < 17 then 2 elseif cz < 24 then 3 else 4
			return (if cx < 34 then "L" else "R") .. band
		end
		if cz < 12 and y >= 11 and y + h <= 13 and cx >= 29 and cx <= 39 then return "Jaw" end
		return "Body"
	end,
	-- A robed rabbit: two great ears spread above row 58, the head above row
	-- 43, an arm either side of the robe (the right one holding the staff),
	-- and short legs under the hem (row 15).
	RabbicCleric = function(x, y, _z, w, h)
		local cx = x + w / 2
		if y >= 58 then
			if cx < 44 then return "LeftEar" end
			if cx > 62 then return "RightEar" end
			return "Head"
		end
		if y >= 43 then return "Head" end
		if cx < 36 then return "LeftArm" end
		if cx > 66 then return "RightArm" end
		if y + h <= 15 then
			return if cx < 52 then "LeftLeg" else "RightLeg"
		end
		return "Body"
	end,
	-- A body down the middle (x 57-83), its mouth the front of it, and four
	-- long arched legs: every box outside the body joins the leg whose
	-- root-to-tip line it is nearest (traced from a top-down map).
	WormyHorror = (function()
		local legs = {
			FL = { 58, 16, 34, 2 }, FR = { 82, 16, 106, 2 },
			BL = { 56, 34, 24, 46 }, BR = { 84, 34, 116, 46 },
		}
		local function distance(px, pz, l)
			local ax, az, bx, bz = l[1], l[2], l[3], l[4]
			local dx, dz = bx - ax, bz - az
			local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz), 0, 1)
			return math.sqrt((ax + dx * t - px) ^ 2 + (az + dz * t - pz) ^ 2)
		end
		return function(x, _y, z, w, _h, d)
			local cx, cz = x + w / 2, z + d / 2
			if cx >= 57 and cx <= 83 then
				return if cz < 14 then "Head" else "Body"
			end
			local best, bestDistance = "Body", math.huge
			for name, line in pairs(legs) do
				local dist = distance(cx, cz, line)
				if dist < bestDistance then best, bestDistance = name, dist end
			end
			return best
		end
	end)(),
	-- Horned head and frill in front, a drooping tail behind, four stubby
	-- legs (top at row 11 or lower) under the front and back of the body.
	Pentasaurus = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		if cz < 28 then return "Head" end
		if cz >= 74 then return "Tail" end
		if y + h <= 11 then
			local side = if cx < 21.5 then "L" else "R"
			if cz >= 30 and cz <= 48 then return "F" .. side end
			if cz >= 56 and cz <= 72 then return "B" .. side end
		end
		return "Body"
	end,
	-- Knuckle-walker: the arms are the outer columns (x < 30, x > 41) from
	-- the shoulders to the ground, the head the middle above row 36, the
	-- legs the short columns under the back half.
	Gorilla = function(x, y, z, w, h, d)
		local cx, cz = x + w / 2, z + d / 2
		-- Front columns only: further back the same x is the torso's flank.
		if cx < 30 and cz < 18 then return "LeftArm" end
		if cx > 41 and cz < 18 then return "RightArm" end
		if y >= 36 then return "Head" end
		if y + h <= 19 and cz >= 28 then
			return if cx < 36 then "LeftLeg" else "RightLeg"
		end
		return "Body"
	end,
	-- Factor-2 boxes. The wings are the raised V above the shoulders and the
	-- feathers hanging down the outside of the body.
	Shrike = function(x, y, _z, w, _h, _d, _c)
		local centre = x + w / 2
		local outboard = x + w <= 26 or x >= 40
		if y >= 17 or (outboard and y >= 8) then
			return if centre < 33 then "LeftWing" else "RightWing"
		end
		return "Body"
	end,
}

--[[
	One part from many. The CSG kernel occasionally refuses a large set
	("Internal kernel Error -31" on the Shrike's body), so a refused set is
	unioned in halves and the halves unioned; halves that still refuse stay
	separate and are welded to the first, as `extras`.
]]
local function unionParts(parts)
	if #parts == 1 then
		return parts[1], {}
	end
	local first = parts[1]
	local rest = table.move(parts, 2, #parts, 1, {})
	local ok, result = pcall(function()
		return first:UnionAsync(rest, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	end)
	if ok then
		return result, {}
	end

	-- Halves are parented beside their parts: the kernel wants them in the world.
	local half = #parts // 2
	local a, extrasA = unionParts(table.move(parts, 1, half, 1, {}))
	local b, extrasB = unionParts(table.move(parts, half + 1, #parts, 1, {}))
	a.Parent, b.Parent = first.Parent, first.Parent
	local joined
	ok, joined = pcall(function()
		return a:UnionAsync({ b }, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	end)
	local extras = table.move(extrasB, 1, #extrasB, #extrasA + 1, extrasA)
	if ok then
		return joined, extras
	end
	table.insert(extras, b)
	return a, extras
end

local function union(parts, name)
	local result, extras = unionParts(parts)
	result.Name = name
	for _, part in ipairs({ result, table.unpack(extras) }) do
		if part:IsA("PartOperation") then part.UsePartColor = false end
		part.CanCollide, part.CanTouch, part.CanQuery = false, false, true
		part.Anchored = true
	end
	return result, extras
end

-- Welds pieces a union could not absorb onto it, keeping them in the model.
local function attach(model, main, extras)
	for i, piece in ipairs(extras) do
		piece.Name = main.Name .. "Piece" .. i
		piece.Anchored = false
		piece.Massless = true
		piece.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = main, piece
		weld.Parent = piece
	end
end

function Build.build(data, voxel, assetName, split, flap)
	local colors = {}
	for r, g, b in string.gmatch(data.colors, "(%d+),(%d+),(%d+)") do
		table.insert(colors, Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)))
	end
	local dims = data.dims
	local origin = Vector3.new(0, 500, 0)
	local folder = Instance.new("Folder")
	folder.Name = "_WingedBuild"

	local groups = { Body = {}, LeftWing = {}, RightWing = {} }
	for x, y, z, w, h, d, c in string.gmatch(data.boxes, "(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)") do
		x, y, z, w, h, d, c = tonumber(x), tonumber(y), tonumber(z), tonumber(w), tonumber(h), tonumber(d), tonumber(c)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide = true, false
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Color = colors[c]
		p.Size = Vector3.new(w, h, d) * voxel
		p.Position = origin + Vector3.new(x + w / 2 - dims[1] / 2, y + h / 2, z + d / 2 - dims[3] / 2) * voxel
		p.Parent = folder
		table.insert(groups[split(x, y, z, w, h, d, c)], p)
	end
	folder.Parent = workspace
	task.wait()

	local model = Instance.new("Model")
	model.Name = assetName
	local body, bodyExtras = union(groups.Body, "Body")
	body.Parent = model
	model.PrimaryPart = body
	attach(model, body, bodyExtras)

	for _, side in ipairs({ "LeftWing", "RightWing" }) do
		local wing, wingExtras = union(groups[side], side)
		wing.Anchored = false
		wing.Massless = true
		wing.Parent = model
		attach(model, wing, wingExtras)

		-- The shoulder: the wing's edge nearest the body, at its lowest
		-- point, halfway along it.
		local inner = if wing.Position.X < body.Position.X
			then wing.Position.X + wing.Size.X / 2
			else wing.Position.X - wing.Size.X / 2
		local hinge = CFrame.new(inner, wing.Position.Y - wing.Size.Y / 2 + 0.1, wing.Position.Z)

		local joint = Instance.new("Motor6D")
		joint.Name = side
		joint.Part0, joint.Part1 = body, wing
		joint.C0 = body.CFrame:ToObjectSpace(hinge)
		joint.C1 = wing.CFrame:ToObjectSpace(hinge)
		joint.Parent = body
	end
	folder:Destroy()

	model:SetAttribute("ArticulatedRig", true)
	model:SetAttribute("WingRate", flap.rate)
	model:SetAttribute("WingAngle", flap.angle)
	model:SetAttribute("WingGlide", flap.glide or 0)
	model.WorldPivot = CFrame.new(model:GetBoundingBox().Position)
	model:PivotTo(CFrame.new())
	return model
end

--[[
	A chain of unions on Motor6Ds, for a body that bends rather than flaps:
	`joints` is a list of { parent, child, hinge? } group names, the first
	group in `order` is the anchored root, and each child hinges at `hinge`
	(a point in the boxes file's voxel units: x, height, z) or, without one,
	at the bottom centre of its own box. The pivot is the root's feet,
	centred.
]]
function Build.buildJointed(data, voxel, assetName, split, order, joints, cuts)
	local colors = {}
	for r, g, b in string.gmatch(data.colors, "(%d+),(%d+),(%d+)") do
		table.insert(colors, Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)))
	end
	local dims = data.dims
	local origin = Vector3.new(0, 500, 0)
	local folder = Instance.new("Folder")
	folder.Name = "_WingedBuild"

	local groups = {}
	for _, name in ipairs(order) do groups[name] = {} end

	--[[
		`cuts` = { x = {...}, y = {...}, z = {...} } slices every box at those
		planes before it is classified. The exporter merges same-coloured
		voxels as far as they go, so a leg and the flank above it are often
		one tall box; cutting at the hip lets each half go to its own part.
	]]
	local function slices(start, length, planes)
		local pieces, from = {}, start
		for _, plane in ipairs(planes or {}) do
			if plane > from and plane < start + length then
				table.insert(pieces, { from, plane - from })
				from = plane
			end
		end
		table.insert(pieces, { from, start + length - from })
		return pieces
	end
	for _, axis in ipairs({ "x", "y", "z" }) do
		if cuts and cuts[axis] then table.sort(cuts[axis]) end
	end

	for bx, by, bz, bw, bh, bd, c in string.gmatch(data.boxes, "(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)") do
		bx, by, bz, bw, bh, bd, c = tonumber(bx), tonumber(by), tonumber(bz), tonumber(bw), tonumber(bh), tonumber(bd), tonumber(c)
		for _, sx in ipairs(slices(bx, bw, cuts and cuts.x)) do
			for _, sy in ipairs(slices(by, bh, cuts and cuts.y)) do
				for _, sz in ipairs(slices(bz, bd, cuts and cuts.z)) do
					local x, w, y, h, z, d = sx[1], sx[2], sy[1], sy[2], sz[1], sz[2]
					local p = Instance.new("Part")
					p.Anchored, p.CanCollide = true, false
					p.Material = Enum.Material.SmoothPlastic
					p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
					p.Color = colors[c]
					p.Size = Vector3.new(w, h, d) * voxel
					p.Position = origin + Vector3.new(x + w / 2 - dims[1] / 2, y + h / 2, z + d / 2 - dims[3] / 2) * voxel
					p.Parent = folder
					table.insert(groups[split(x, y, z, w, h, d, c)], p)
				end
			end
		end
	end
	folder.Parent = workspace
	task.wait()

	local model = Instance.new("Model")
	model.Name = assetName
	local parts = {}
	for i, name in ipairs(order) do
		local part, extras = union(groups[name], name)
		part.Parent = model
		if i == 1 then
			model.PrimaryPart = part
		else
			part.Anchored = false
			part.Massless = true
		end
		attach(model, part, extras)
		parts[name] = part
	end

	for _, pair in ipairs(joints) do
		local parent, child = parts[pair[1]], parts[pair[2]]
		local at = pair[3]
		local hinge = if at
			then CFrame.new(origin + Vector3.new(at[1] - dims[1] / 2, at[2], at[3] - dims[3] / 2) * voxel)
			else CFrame.new(child.Position - Vector3.new(0, child.Size.Y / 2, 0))
		local joint = Instance.new("Motor6D")
		joint.Name = pair[2]
		joint.Part0, joint.Part1 = parent, child
		joint.C0 = parent.CFrame:ToObjectSpace(hinge)
		joint.C1 = child.CFrame:ToObjectSpace(hinge)
		joint.Parent = parent
	end
	folder:Destroy()

	model:SetAttribute("ArticulatedRig", true)
	local bounds = model:GetBoundingBox()
	local root = model.PrimaryPart
	model.WorldPivot = CFrame.new(bounds.Position.X, root.Position.Y - root.Size.Y / 2, bounds.Position.Z)
	model:PivotTo(CFrame.new())
	return model
end

return Build
