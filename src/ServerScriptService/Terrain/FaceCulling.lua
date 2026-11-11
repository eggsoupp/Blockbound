--[[
	FaceCulling

	Covered-face culling: which faces of each drawn Part show their images.
	Reads the block data (ChunkData) and the Parts' rectangles and face state
	(BlockParts); never decides what is drawn, only how. Part of
	TerrainManager; see TerrainManager for the map of terrain modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerrainShared = Shared:WaitForChild("Terrain")
local TerrainConfig = require(TerrainShared:WaitForChild("TerrainConfig"))
local BlockConfig = require(Shared:WaitForChild("Blocks"):WaitForChild("BlockConfig"))

local ChunkData = require(script.Parent:WaitForChild("ChunkData"))
local BlockParts = require(script.Parent:WaitForChild("BlockParts"))

local FaceCulling = {}

local CHUNK_SIZE = TerrainConfig.ChunkSize

local chunks = ChunkData.chunks
local isPresentInData = ChunkData.isPresentInData
local isBlockPresent = ChunkData.isBlockPresent
local getBlockPartTemplate = BlockParts.getBlockPartTemplate
local partRect = BlockParts.partRect
local Faces = BlockParts.Faces
--[[
	Inlinable copies of TerrainGrid helpers, on purpose. Luau's optimiser only
	inlines a `local function` defined in the same script, and these run per
	block in the visibility and face passes; calling TerrainGrid's versions
	across modules measured ~10% slower there. Keep them identical to
	TerrainGrid (the canonical definitions).
]]
local function chunkKey(cx, cz)
	return (cx + 8192) * 65536 + (cz + 8192)
end
local function normalizeCell(cx, cz, bx, bz)
	if bx < 0 or bx >= CHUNK_SIZE then
		local shift = bx // CHUNK_SIZE
		cx += shift
		bx -= shift * CHUNK_SIZE
	end
	if bz < 0 or bz >= CHUNK_SIZE then
		local shift = bz // CHUNK_SIZE
		cz += shift
		bz -= shift * CHUNK_SIZE
	end
	return cx, cz, bx, bz
end
local function cellOf(bx, bz)
	return bx * CHUNK_SIZE + bz + 1
end

--[[
	HIDDEN FACES

	Every block template carries an image on each of its six faces, and each
	image is an Instance the server sends to every client: a Part plus six
	Textures is seven objects, and the Textures were about 65% of everything the
	terrain replicated. Most of them can never be seen. The bottom of a surface
	block lies on the ground under it, and most sides press against the next
	column. Measured against the block data at view distance 7: 64% of face
	images in plains, 60% in snowy hills, were on faces covered completely.

	So a face shows its images only while something next to it is not a solid,
	opaque cube - air, water, the world's edge, or a block of another shape. A
	covered face looks exactly the same without its image, because nobody can
	see it. The images stay on the Part in Faces.textures, unparented, and go back
	the moment the face is uncovered:

	  * a new Part is decided as it is emitted, from the block data, before it
	    is in the world;
	  * every change to whether a cell is solid (ChunkData.noteSolidChange) re-decides the
	    Parts on all six sides of it, across chunk borders, in the same step
	    as the edit's own redraw (processFaceChanges);
	  * a chunk that finishes loading re-decides its neighbours' border Parts,
	    which were decided against the generated heightmap and may not have
	    seen its structures or player edits (refreshEdgeFaces);
	  * inside an edit zone every face keeps its images. Those Parts are drawn
	    early on purpose, so the block a swing uncovers is already whole on
	    every client before the swing lands.

	TerrainConfig.CullHiddenFaces = false draws every face again.
]]
local CULL_HIDDEN_FACES = TerrainConfig.CullHiddenFaces ~= false

-- NormalId name -> the step from a block to the cell that face looks at.
local FACE_STEP = {
	Top = { 0, 1, 0 },
	Bottom = { 0, -1, 0 },
	Right = { 1, 0, 0 },
	Left = { -1, 0, 0 },
	Back = { 0, 0, 1 },
	Front = { 0, 0, -1 },
}

-- Can a block of this name hide the face behind it? Full opaque cubes only:
-- water is see-through, and a wedge or mesh leaves gaps.
local opaqueByName = {}

local function isOpaqueBlock(name)
	local cached = opaqueByName[name]
	if cached == nil then
		local template = getBlockPartTemplate(name)
		cached = template ~= nil
			and template:IsA("Part")
			and template.Shape == Enum.PartType.Block
			and BlockConfig.surfaceFor(name) == nil
		opaqueByName[name] = cached
	end
	return cached
end

--[[
	Does the cell at (cx, cz, bx, bz, by) hide whatever face looks at it?
	bx/bz may have walked off the chunk. Natural ground is always an opaque
	cube; only blocks something put there or restyled are looked up by name.
	A chunk that is not loaded answers from the generated heightmap, and is
	corrected when it loads (Faces.refreshEdge).
]]
local function coversLocal(data, cell, by)
	if not isPresentInData(data, cell, by) then
		return false
	end

	local override = data.override[cell]
	local name = override and override[by]
	if not name then
		local extra = data.extra[cell]
		name = extra and extra[by]
	end
	return name == nil or isOpaqueBlock(name)
end

local function coversFace(cx, cz, bx, bz, by)
	cx, cz, bx, bz = normalizeCell(cx, cz, bx, bz)

	local data = chunks[chunkKey(cx, cz)]
	if not data then
		return isBlockPresent(cx, cz, bx, bz, by)
	end

	return coversLocal(data, bx * CHUNK_SIZE + bz + 1, by)
end

-- Is every block of this rectangle's face against something that hides it?
local function faceCovered(data, rect, step)
	local cx, cz = data.cx, data.cz
	local by = rect.by + step[2]
	local x0, z0 = rect.bx, rect.bz
	local x1, z1 = x0 + rect.sizeX - 1, z0 + rect.sizeZ - 1

	if step[1] > 0 then
		x0, x1 = x1 + 1, x1 + 1
	elseif step[1] < 0 then
		x0, x1 = x0 - 1, x0 - 1
	elseif step[3] > 0 then
		z0, z1 = z1 + 1, z1 + 1
	elseif step[3] < 0 then
		z0, z1 = z0 - 1, z0 - 1
	end

	-- Nearly every cell asked about is in this same chunk, which is always
	-- the one in `chunks` under these coordinates: read it directly.
	local own = chunks[chunkKey(cx, cz)] == data

	for x = x0, x1 do
		local inside = own and x >= 0 and x < CHUNK_SIZE
		for z = z0, z1 do
			if inside and z >= 0 and z < CHUNK_SIZE then
				if not coversLocal(data, x * CHUNK_SIZE + z + 1, by) then
					return false
				end
			elseif not coversFace(cx, cz, x, z, by) then
				return false
			end
		end
	end
	return true
end

local function rectIsHot(data, rect)
	local hot = data.hot
	for x = rect.bx, rect.bx + rect.sizeX - 1 do
		for z = rect.bz, rect.bz + rect.sizeZ - 1 do
			if hot[cellOf(x, z)] then
				return true
			end
		end
	end
	return false
end

local FACE_ORDER = { "Top", "Bottom", "Right", "Left", "Back", "Front" }
local FACE_BIT = Faces.BIT
local shownMask = Faces.shown

-- Which faces of this rectangle should show their images, as a mask.
local function maskFor(data, rect)
	if not CULL_HIDDEN_FACES or (data.hotCount > 0 and rectIsHot(data, rect)) then
		return 63
	end

	local mask = 0
	for i = 1, 6 do
		local face = FACE_ORDER[i]
		if not faceCovered(data, rect, FACE_STEP[face]) then
			mask += FACE_BIT[face]
		end
	end
	return mask
end

--[[
	Makes a Part show exactly the faces in `mask`: images go on or come off
	only for the faces that differ from what it shows now. An image the Part
	was never given (see FACE VARIANTS) is cloned from the block's own.
]]
local function applyMask(part, name, mask)
	local shown = shownMask[part]
	if shown == mask then
		return
	end

	local faces = Faces.textures[part]
	if not faces then
		return
	end

	for i = 1, 6 do
		local face = FACE_ORDER[i]
		local bit = FACE_BIT[face]
		local want = bit32.btest(mask, bit)

		if shown == nil or want ~= bit32.btest(shown, bit) then
			local list = faces[face]
			if not want then
				if list then
					for _, texture in ipairs(list) do
						texture.Parent = nil
					end
				end
			elseif list then
				for _, texture in ipairs(list) do
					texture.Parent = part
				end
			else
				local images = Faces.images[name]
				local source = images and images[face]
				if source then
					list = table.create(#source)
					for index, image in ipairs(source) do
						local texture = image:Clone()
						texture.Parent = part
						list[index] = texture
					end
					faces[face] = list
				end
			end
		end
	end

	shownMask[part] = mask
end

-- Puts each face's images on the Part or takes them off. See HIDDEN FACES.
local function showFaces(data, part)
	local rect = partRect[part]
	if not rect then
		return
	end
	applyMask(part, rect.name or part.Name, maskFor(data, rect))
end

-- The cells around a changed one whose Parts face it.
local FACE_NEIGHBOURS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, 1, 0 }, { 0, -1, 0 } }

-- Re-decides the faces of every drawn Part next to a recorded change (see
-- ChunkData.noteSolidChange).
local function processFaceChanges()
	local faceChanges, faceChangeCount = ChunkData.solidChanges()
	if faceChangeCount == 0 then
		return
	end

	local seen = {}

	for i = 1, faceChangeCount, 3 do
		local data, cell, by = faceChanges[i], faceChanges[i + 1], faceChanges[i + 2]

		-- A chunk that has since unloaded has no Parts left to fix.
		if chunks[chunkKey(data.cx, data.cz)] == data then
			local index = cell - 1
			local bx, bz = index // CHUNK_SIZE, index % CHUNK_SIZE

			for _, offset in ipairs(FACE_NEIGHBOURS) do
				local ncx, ncz, nbx, nbz = normalizeCell(data.cx, data.cz, bx + offset[1], bz + offset[3])
				local neighbour = chunks[chunkKey(ncx, ncz)]
				local bucket = neighbour and neighbour.layerParts[by + offset[2]]

				if bucket then
					for _, part in ipairs(bucket) do
						local rect = partRect[part]
						if
							rect
							and not seen[part]
							and nbx >= rect.bx and nbx < rect.bx + rect.sizeX
							and nbz >= rect.bz and nbz < rect.bz + rect.sizeZ
						then
							seen[part] = true
							showFaces(neighbour, part)
						end
					end
				end
			end
		end
	end

	ChunkData.clearSolidChanges()
end

--[[
	Re-decides the Parts of `data` along the edge facing (dx, dz), the step
	from data to the chunk that changed.
]]
local function refreshEdgeFaces(data, dx, dz)
	-- With every face drawn there is nothing a neighbour can change.
	if not CULL_HIDDEN_FACES then
		return
	end

	-- The one face that looks at the chunk that changed. Nothing that
	-- chunk did can cover or uncover any other face of these Parts.
	local face = if dx == 1 then "Right" elseif dx == -1 then "Left" elseif dz == 1 then "Back" else "Front"
	local bit = FACE_BIT[face]
	local step = FACE_STEP[face]
	local zoned = data.hotCount > 0

	for _, bucket in pairs(data.layerParts) do
		for _, part in ipairs(bucket) do
			local rect = partRect[part]
			if
				rect
				and (
					(dx == 1 and rect.bx + rect.sizeX == CHUNK_SIZE)
					or (dx == -1 and rect.bx == 0)
					or (dz == 1 and rect.bz + rect.sizeZ == CHUNK_SIZE)
					or (dz == -1 and rect.bz == 0)
				)
			then
				local shown = shownMask[part]
				if shown == nil then
					showFaces(data, part)
				elseif not (zoned and rectIsHot(data, rect)) then
					-- (A Part in an edit zone keeps every face.)
					local want = not faceCovered(data, rect, step)
					if want ~= bit32.btest(shown, bit) then
						applyMask(part, rect.name or part.Name, if want then shown + bit else shown - bit)
					end
				end
			end
		end
	end
end

FaceCulling.maskFor = maskFor
FaceCulling.apply = applyMask
FaceCulling.show = showFaces
FaceCulling.processChanges = processFaceChanges
FaceCulling.refreshEdge = refreshEdgeFaces

return FaceCulling
