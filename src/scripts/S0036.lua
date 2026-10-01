--[[
	NoiseField

	Thin, seedable fbm wrapper around ReplicatedStorage.Perlin.

	The bundled Perlin has a fixed permutation table, so it cannot be reseeded.
	Three tricks make it behave like several independent fields anyway:

	  * each field gets a random lattice offset, which slides the world through
	    the noise (this is the world seed);
	  * each field samples a different constant Y plane. Perlin's third axis is
	    continuous, so distinct planes are effectively decorrelated 2D fields;
	  * each field may be ROTATED in the XZ plane - see below.

	Sampling is in BLOCK coordinates; the caller supplies the scale in blocks.

	THE 256 PERIOD
	  Perlin repeats every 256 lattice units. A field is safe from that only if
	  its offset plus the world's own span stays inside one period, so `span`
	  says how many lattice units the world covers and the offset is drawn from
	  what is left. Without it a large world picks an offset near 256 and the
	  far side of the map is a verbatim copy of the near side.

	THE LATTICE IS VISIBLE IN A SLOW FIELD
	  Perlin noise is exactly zero at every integer lattice point. A field fine
	  enough that the world spans hundreds of cells hides that completely - the
	  zeros are a block apart and nobody can see them. A field slow enough to
	  shape continents does not: the continent field covers about SIX cells
	  across the whole map, so its zero crossings - which is to say the line
	  between upland and lowland - run along a square grid aligned with the
	  world axes, and that grid is the same one the chunks and the player's
	  compass use.

	  `rotate` turns the sampling frame by a fixed irrational angle, so the
	  lattice no longer lines up with anything the player can reference. It does
	  not remove the structure, it stops it being READABLE, which is the part
	  that matters. Two multiply-adds per sample.

	  A rotated square needs sqrt(2) times the room inside the period, and the
	  reach calculation accounts for that, so turning it on cannot silently
	  reintroduce the tiling it is there to hide.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Perlin = require(ReplicatedStorage:WaitForChild("Perlin"))

local PERIOD = 256

-- About 31.7 degrees. Deliberately not a nice fraction of a right angle: the
-- point is that no run of the lattice ever lines up with an axis.
local ROTATION_COS = 0.8508
local ROTATION_SIN = 0.5255

-- A rotated square's bounding box is sqrt(2) times its side, so a rotated
-- field reaches that much further across the period.
local ROTATION_REACH = 1.4143

local NoiseField = {}
NoiseField.__index = NoiseField

--[[
	seed        number  - combined with `plane` to pick the lattice offset
	plane       number  - constant Y slice; give every field a different one
	octaves     number  - 1 for smooth fields, 3+ for rugged ones
	persistence number  - amplitude falloff per octave (0.5 is standard)
	lacunarity  number  - frequency growth per octave (2.0 is standard)
	span        number  - lattice units the world covers at this field's scale,
	                      i.e. worldSpanBlocks / scale. Optional; without it the
	                      offset may put the world across the period boundary.
	rotate      boolean - turn the sampling frame off the world axes. Worth it
	                      for any field slow enough that the world covers only a
	                      handful of lattice cells; pointless, and a waste of
	                      the period budget, for a fine one.
]]
function NoiseField.new(seed, plane, octaves, persistence, lacunarity, span, rotate)
	local rng = Random.new(seed)

	octaves = math.max(1, math.floor(octaves or 1))
	lacunarity = lacunarity or 2.0

	--[[
		The highest octave is the one that reaches furthest across the period,
		so the room left for an offset is measured against that rather than
		against the base frequency.

		A span that already exceeds the period cannot be placed safely at all;
		the offset is then simply unconstrained, because no choice avoids the
		repeat. That is only reachable by a very fine field on a very large
		world - detail roughness, where a repeat of a one-block jitter is not
		visible - and the alternative would be to silently coarsen it.
	]]
	local reach = 0
	if span then
		reach = span * lacunarity ^ (octaves - 1)
		if rotate then
			reach *= ROTATION_REACH
		end
	end

	local room = PERIOD - reach
	if room < 1 then
		room = PERIOD
	end

	return setmetatable({
		offsetX = rng:NextNumber(0, room),
		offsetZ = rng:NextNumber(0, room),
		plane = plane,
		octaves = octaves,
		persistence = persistence or 0.5,
		lacunarity = lacunarity,

		-- Identity when rotation is off, so the sampling path is the same two
		-- multiply-adds either way and there is no branch in the hot loop.
		rotCos = if rotate then ROTATION_COS else 1,
		rotSin = if rotate then ROTATION_SIN else 0,
	}, NoiseField)
end

--[[
	Returns roughly [-1, 1]. Perlin's raw range is a little under that; callers
	that need a strict range should clamp after shaping.
]]
function NoiseField:sample(x, z, scale)
	local sx = x / scale
	local sz = z / scale

	local cos, sin = self.rotCos, self.rotSin
	local baseX = sx * cos - sz * sin + self.offsetX
	local baseZ = sx * sin + sz * cos + self.offsetZ

	local plane = self.plane
	local persistence = self.persistence
	local lacunarity = self.lacunarity

	local amplitude = 1.0
	local frequency = 1.0
	local total = 0.0
	local normalizer = 0.0

	for _ = 1, self.octaves do
		total += Perlin:noise(baseX * frequency, plane, baseZ * frequency) * amplitude
		normalizer += amplitude
		amplitude *= persistence
		frequency *= lacunarity
	end

	return total / normalizer
end

--[[
	Same as :sample but remapped to [0, 1].

	CAUTION: the name promises more than the field delivers. fbm does not fill
	[0, 1] - it is a bell clustered hard around 0.5, and the more octaves are
	summed the tighter that bell gets. Measured over this world at two octaves,
	the field spans about [0.23, 0.78], with a 90th percentile near 0.64.

	That matters because a THRESHOLD written against this reads as a fraction of
	the range and is not one. A gate at 0.60 sounds like "the top 40%" and is
	actually the top 8%; a gate that fades in to 0.76 never opens at all,
	because the field does not get there. Two of this generator's features -
	mountain belts and lake basins - were gated exactly that way and were
	effectively switched off. Use :shaped for anything with a threshold on it.
]]
function NoiseField:sample01(x, z, scale)
	local value = (self:sample(x, z, scale) + 1) * 0.5
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

--[[
	:sample01 with the bell stretched toward the ends, in [0, 1].

	`contrast` multiplies the deviation from the middle before clamping, so 1
	is exactly :sample01 and larger values push the field out to its ends. The
	clamp is the point rather than a safety net: the tails flatten into
	PLATEAUS, which is what turns a wobble into large coherent regions of
	"definitely yes" and "definitely no" with a graded band between them.

	This is what makes a threshold behave the way its number reads, and it is
	the right sampler for any field a `band()` is applied to - mountain belts,
	lake basins, continental elevation. Around 2.0 is enough to reach both ends
	of a two-octave field without spending most of the map clamped.
]]
function NoiseField:shaped(x, z, scale, contrast)
	local value = 0.5 + self:sample(x, z, scale) * (contrast or 1) * 0.5
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

--[[
	Ridged multifractal, in [0, 1], with 1 on the ridge line.

	WHY THIS AND NOT fbm

	Ordinary fbm is a field of independent bumps: it makes hills, and no amount
	of amplitude turns those hills into a mountain RANGE. Folding the noise
	about zero - 1 - |n| - turns its zero crossings into creases, and a zero
	crossing of a continuous field is a CURVE. So the high ground comes out as
	connected lines rather than blobs, which is what a range is, and the ground
	between two creases is a valley rather than a gap.

	Each octave is weighted by the one above it, so detail only appears where
	the coarse octave was already high. That is what puts jagged rock on the
	peaks and leaves the valley floors smooth, instead of sprinkling the same
	roughness everywhere.

	  gain  how strongly a high coarse octave lets the finer ones through.
	        Around 2 gives crisp ridges; 1 is nearly plain ridged fbm.
]]
function NoiseField:ridged(x, z, scale, gain)
	local sx = x / scale
	local sz = z / scale

	local cos, sin = self.rotCos, self.rotSin
	local baseX = sx * cos - sz * sin + self.offsetX
	local baseZ = sx * sin + sz * cos + self.offsetZ

	gain = gain or 2.0

	local plane = self.plane
	local persistence = self.persistence
	local lacunarity = self.lacunarity

	local amplitude = 1.0
	local frequency = 1.0
	local total = 0.0
	local normalizer = 0.0
	local weight = 1.0

	for _ = 1, self.octaves do
		local n = Perlin:noise(baseX * frequency, plane, baseZ * frequency)

		n = 1 - (if n < 0 then -n else n)
		n *= n
		n *= weight

		weight = n * gain
		if weight > 1 then
			weight = 1
		elseif weight < 0 then
			weight = 0
		end

		total += n * amplitude
		normalizer += amplitude
		amplitude *= persistence
		frequency *= lacunarity
	end

	local value = total / normalizer
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

return NoiseField
