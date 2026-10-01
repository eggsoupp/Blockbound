--[[
	TerrainMesher

	Greedy rectangle merging over one horizontal layer of a chunk.

	WHY HORIZONTAL, AND WHY THIS IS THE SHAPE OF THE WIN

	The first benchmark sweep reported the server rendering exactly one part per
	loaded column - 6,400 parts for 6,400 columns at view distance 2, and the
	same ratio at every distance after it. That number says something specific
	about this world: the visible set is overwhelmingly the top surface, one
	block deep. Almost nothing is stacked.

	So merging VERTICALLY, within a column, would gain close to nothing - there
	is usually only one visible block there to merge. The parts to collapse are
	the ones lying next to each other across a flat surface, which is a 2D
	problem on each Y layer rather than a 1D problem down each column.

	A flat 16x16 chunk top of one material becomes ONE part instead of 256.
	Patchy ground does worse, sheer cliffs do worse again, but the direction is
	the same everywhere: fewer, larger boxes covering identical work.

	THE ALGORITHM

	Standard greedy meshing. Walk the layer in row-major order; at the first
	cell not yet consumed, extend as far as possible along Z, then extend that
	whole strip as far as possible along X, and consume the rectangle. Every
	cell is visited once and consumed once, so the layer costs O(cells) plus the
	probing, and the result is a small set of maximal-ish rectangles.

	It is not the theoretically minimal rectangle cover - that is much more
	expensive to compute and worth nothing here, because the cost being reduced
	is the count of Instances, not their optimality.

	OUTPUT FORMAT

	Rectangles are appended to a caller-supplied flat array, five entries each:

	    bx, bz, sizeX, sizeZ, name

	Flat rather than a table per rectangle because this runs for every layer of
	every chunk that loads, and a table per rectangle would allocate thousands
	of short-lived tables per chunk for no benefit.

	COORDINATES
	  bx, bz are chunk-local block coordinates of the rectangle's minimum
	  corner. sizeX spans +X, sizeZ spans +Z. Cell indexing matches
	  TerrainManager: cell = bx * size + bz + 1.
]]

local TerrainMesher = {}

-- Consumed-cell marks, reused between calls. Meshing never yields, so a single
-- module-level scratch buffer cannot be observed half-written by anything else.
local used = {}

--[[
	Meshes one layer.

	  grid   [cell] -> block name, or nil where nothing is visible
	  size   chunk edge in blocks
	  merge  false emits one rectangle per block, which is the unmerged
	         renderer. Kept as a mode of the same function rather than a
	         separate code path so that turning merging off exercises all the
	         same plumbing - a bug in the surrounding machinery then shows up in
	         both modes instead of hiding in one.
	  out    flat array to append to; caller owns it and normally reuses it

	Returns the number of rectangles appended.
]]
function TerrainMesher.meshLayer(grid, size, merge, out)
	table.clear(used)

	local count = 0
	local write = #out

	for bx = 0, size - 1 do
		local rowBase = bx * size

		for bz = 0, size - 1 do
			local index = rowBase + bz + 1
			local name = grid[index]

			if name ~= nil and not used[index] then
				local sizeX, sizeZ = 1, 1

				if merge then
					-- Extend along Z while the run stays the same block.
					while bz + sizeZ < size do
						local probe = rowBase + bz + sizeZ + 1
						if grid[probe] ~= name or used[probe] then
							break
						end
						sizeZ += 1
					end

					-- Extend the whole strip along X. A row only counts if
					-- every cell of it matches; a partial match would leave a
					-- notch that the rectangle cannot represent.
					while bx + sizeX < size do
						local probeBase = (bx + sizeX) * size + bz + 1
						local rowMatches = true

						for k = 0, sizeZ - 1 do
							local probe = probeBase + k
							if grid[probe] ~= name or used[probe] then
								rowMatches = false
								break
							end
						end

						if not rowMatches then
							break
						end
						sizeX += 1
					end

					for dx = 0, sizeX - 1 do
						local consumeBase = (bx + dx) * size + bz + 1
						for dz = 0, sizeZ - 1 do
							used[consumeBase + dz] = true
						end
					end
				else
					used[index] = true
				end

				out[write + 1] = bx
				out[write + 2] = bz
				out[write + 3] = sizeX
				out[write + 4] = sizeZ
				out[write + 5] = name
				write += 5
				count += 1
			end
		end
	end

	return count
end

return TerrainMesher
