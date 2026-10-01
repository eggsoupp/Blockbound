--[[
    Implemented as described here:
    http://flafla2.github.io/2014/08/09/perlinnoise.html
    Fixed to ensure unskewed values by using 12 unique gradients.

    THE HOTTEST FUNCTION IN THE GENERATOR

    Every field in Shared.Terrain goes through :noise, and a chunk asks for it
    several hundred times. Three things used to be paid on every one of those
    calls and none of them bought anything:

      * `gradients` was a table of twelve CLOSURES, so each sample made eight
        table lookups and eight function calls just to add two numbers. It is
        now arithmetic, chosen by the same hash and producing the same twelve
        vectors.
      * `self.fade`, `self.lerp`, `self:grad` and `self.p` were all resolved
        through the module table on every use. They are locals now.
      * math.floor was called twice per axis - once for the lattice cell and
        again for the fractional part.

    The output is bit-for-bit what it was; nothing about the world changes.
]]--

-- Local, not global. This used to leak `perlin` into the shared global table,
-- where every script in the game could see and mutate the permutation table
-- that the whole world is generated from.
local perlin = {}

-- Hash lookup table as defined by Ken Perlin
-- Randomly arranged array of numbers from 0-255 inclusive
local permutation = {151,160,137,91,90,15,
	131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
	190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
	88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
	77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
	102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
	135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
	5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
	223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
	129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
	251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
	49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
	138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
}

-- Set up the permutation table for hashing. A local array, so the inner loop
-- indexes it directly instead of going through the module table.
local p = {}
for i = 0, 255 do
	p[i] = permutation[i + 1]
	p[i + 256] = permutation[i + 1] -- Repeat to avoid overflow
end

perlin.p = p -- kept public: callers have inspected it, and it costs nothing

--[[
	The twelve standard 3D Perlin gradients, as arithmetic rather than as a
	table of closures.

	Reading h in 0..11 as two bits of sign plus a choice of plane:

	    h < 4   ->  (+/-x, +/-y, 0)
	    h < 8   ->  (+/-x, 0, +/-z)
	    else    ->  (0, +/-y, +/-z)

	with the first component negated on odd h and the second on h % 4 >= 2.
	That reproduces the original table exactly, entry for entry.
]]
local function grad(hash, x, y, z)
	local h = hash % 12
	local u, v

	if h < 4 then
		u, v = x, y
	elseif h < 8 then
		u, v = x, z
	else
		u, v = y, z
	end

	if h % 2 == 1 then
		u = -u
	end
	if h % 4 >= 2 then
		v = -v
	end

	return u + v
end

-- Fade function for smooth transitions
local function fade(t)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

-- Linear interpolation
local function lerp(t, a, b)
	return a + t * (b - a)
end

local floor = math.floor
local band = bit32.band

-- Noise function, returns values in range [-1, 1]
function perlin:noise(x, y, z)
	y = y or 0
	z = z or 0

	-- Lattice cell and the fractional position inside it, from one floor each.
	local fx = floor(x)
	local fy = floor(y)
	local fz = floor(z)

	local xi = band(fx, 255)
	local yi = band(fy, 255)
	local zi = band(fz, 255)

	x -= fx
	y -= fy
	z -= fz

	-- Apply fade function for smooth interpolation
	local u = fade(x)
	local v = fade(y)
	local w = fade(z)

	-- Hash the 8 surrounding cube corners
	local A = p[xi] + yi
	local AA = p[A] + zi
	local AB = p[A + 1] + zi

	local B = p[xi + 1] + yi
	local BA = p[B] + zi
	local BB = p[B + 1] + zi

	local x1 = x - 1
	local y1 = y - 1
	local z1 = z - 1

	-- Interpolate between the 8 corner gradients
	return lerp(w,
		lerp(v,
			lerp(u,
				grad(p[AA], x, y, z),
				grad(p[BA], x1, y, z)
			),
			lerp(u,
				grad(p[AB], x, y1, z),
				grad(p[BB], x1, y1, z)
			)
		),
		lerp(v,
			lerp(u,
				grad(p[AA + 1], x, y, z1),
				grad(p[BA + 1], x1, y, z1)
			),
			lerp(u,
				grad(p[AB + 1], x, y1, z1),
				grad(p[BB + 1], x1, y1, z1)
			)
		)
	)
end

-- Kept for callers that used them through the module table.
perlin.fade = fade
perlin.lerp = lerp

function perlin:grad(hash, x, y, z)
	return grad(hash, x, y, z)
end

return perlin
