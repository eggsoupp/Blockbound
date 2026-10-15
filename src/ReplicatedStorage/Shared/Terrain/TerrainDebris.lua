--[[
	TerrainDebris

	Client-side copies of blocks the SERVER has already removed, animated
	along a path and then thrown away. The presentation half of any terrain
	destruction in the game: the server decides what goes and persists it
	through TerrainManager and ChunkEdits, then tells clients which blocks
	went, and this draws them leaving.

		TerrainDebris.suction(blocks, mouth, seconds, startedAt)
		TerrainDebris.play(blocks, seconds, startedAt, pathFor)

	`blocks` is the server's sample of `{ position = Vector3, block = name }`
	records. Nothing here is ever a reason to remove a block, and nothing
	here is trusted by the server: a client that called this with a made-up
	list would see some cubes fly and the ground would stay exactly where it
	was.

	WHY IT IS NOT AnnihilationDebris

	Annihilation's debris is one effect - an outward blast - wired straight to
	its own remote with its own numbers in it. A boss that swallows the ground
	needs the same machinery (clone a block model by name, cap it, animate it,
	clean it up) with the opposite trajectory, and extending a payload that is
	documented as "what Annihilation blasted out" with boss fields would have
	made both harder to read. This is the small general seam under both ideas.
	Annihilation itself is left as it is; it works.

	BOUNDED, on purpose, three ways:

	  per play     at most MAX_PIECES blocks are drawn whatever the payload
	               says, so a payload cannot be a part bomb.
	  in total     at most MAX_LIVE pieces exist at once across every play on
	               this client; a play that would exceed it draws fewer. Several
	               casts in a row therefore cost a bounded number of parts.
	  in time      every play ends by its own clock, and every part it made
	               goes with it, whatever the animation did.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemModels = require(Shared:WaitForChild("UI"):WaitForChild("ItemModels"))
local Scope = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityScope"))
local TerrainConfig = require(Shared:WaitForChild("Terrain"):WaitForChild("TerrainConfig"))

local TerrainDebris = {}

local MAX_PIECES = 24
local MAX_LIVE = 72
local MAX_SECONDS = 4

-- A hair under a block, so a copy never z-fights with the ground beside the
-- hole it came out of on its first frame.
local PIECE_SIZE = TerrainConfig.StudSize * 0.95

local FALLBACK_COLOR = Color3.fromRGB(116, 103, 81)

local live = 0

local function buildPiece(record, folder: Folder): BasePart?
	if typeof(record) ~= "table" or typeof(record.position) ~= "Vector3" then
		return nil
	end

	local source = ItemModels.find(record.block)
	if source and not source:IsA("BasePart") then
		source = source:FindFirstChildWhichIsA("BasePart", true)
	end

	local part: BasePart
	if source then
		part = (source :: BasePart):Clone()
		for _, child in ipairs(part:GetChildren()) do
			if not (child:IsA("Decal") or child:IsA("SurfaceAppearance") or child:IsA("Texture")) then
				child:Destroy()
			end
		end
	else
		part = Instance.new("Part")
		part.Color = FALLBACK_COLOR
		part.Material = Enum.Material.Slate
	end

	part.Name = "Debris_" .. tostring(record.block)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 0
	part.Size = Vector3.one * PIECE_SIZE
	part.CFrame = CFrame.new(record.position)
	part.Parent = folder

	return part
end

--[[
	Draws `blocks` for `seconds` from `startedAt` (server time), placing each
	one every frame from `pathFor(record, index, alpha)`, which returns a
	CFrame, a size multiplier and a transparency. Ends itself.

	Returns the number of pieces actually drawn - zero when the play was too
	old to be worth starting or the client is already full of debris.
]]
function TerrainDebris.play(
	blocks,
	seconds: number,
	startedAt: number?,
	pathFor: (record: any, index: number, alpha: number) -> (CFrame, number, number)
): number
	if not RunService:IsClient() then
		return 0
	end
	if type(blocks) ~= "table" or type(pathFor) ~= "function" then
		return 0
	end

	seconds = math.clamp(tonumber(seconds) or 1, 0.1, MAX_SECONDS)

	local start = if type(startedAt) == "number" then startedAt else workspace:GetServerTimeNow()
	if workspace:GetServerTimeNow() - start >= seconds then
		return 0
	end

	local room = math.min(MAX_PIECES, MAX_LIVE - live)
	if room <= 0 then
		return 0
	end

	local scope = Scope.new()
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "TerrainDebris"
	folder.Parent = workspace

	local pieces = {}
	for index, record in ipairs(blocks) do
		if #pieces >= room then
			break
		end
		local part = buildPiece(record, folder)
		if part then
			table.insert(pieces, { part = part, record = record, index = index })
		end
	end

	if #pieces == 0 then
		scope:destroy()
		return 0
	end

	live += #pieces
	scope:add(function()
		live -= #pieces
	end)

	local function update()
		local alpha = math.clamp((workspace:GetServerTimeNow() - start) / seconds, 0, 1)
		if alpha >= 1 then
			scope:destroy()
			return
		end
		for _, piece in ipairs(pieces) do
			local cframe, scale, transparency = pathFor(piece.record, piece.index, alpha)
			piece.part.CFrame = cframe
			piece.part.Size = Vector3.one * (PIECE_SIZE * math.max(0.02, scale))
			piece.part.Transparency = math.clamp(transparency, 0, 1)
		end
	end

	update()
	if not scope:isDead() then
		scope:add(RunService.Heartbeat:Connect(update))
		-- The backstop. The clock above ends it; this ends it if the clock
		-- somehow does not.
		task.delay(seconds + 0.25, function()
			scope:destroy()
		end)
	end

	return #pieces
end

--[[
	Blocks pulled INTO a point and swallowed: a quadratic arc that lifts a
	little out of the hole, converges on `mouth`, and shrinks and tumbles as it
	goes so the last frame is a speck arriving rather than a cube vanishing.

	The inverse of Annihilation's blast, and the trajectory a thing that eats
	the ground wants.
]]
function TerrainDebris.suction(blocks, mouth: Vector3, seconds: number, startedAt: number?): number
	if typeof(mouth) ~= "Vector3" then
		return 0
	end

	return TerrainDebris.play(blocks, seconds, startedAt, function(record, index, alpha)
		local from = record.position :: Vector3
		-- Each piece lifts by a different amount so a bite's worth of blocks
		-- reads as a stream rather than a row, and higher for a longer pull.
		local lift = 3 + (index % 4) * 1.5 + (mouth - from).Magnitude * 0.08
		local control = (from + mouth) * 0.5 + Vector3.new(0, lift, 0)

		-- Easing in: slow out of the ground, fast into him.
		local eased = alpha * alpha
		local inverse = 1 - eased
		local at = from * (inverse * inverse) + control * (2 * inverse * eased) + mouth * (eased * eased)

		local spin = alpha * (2 + (index % 3))
		local cframe = CFrame.new(at) * CFrame.Angles(spin * 0.7, spin, spin * 0.4)

		-- Whole until halfway, then down to a speck as it goes in.
		local scale = 1 - math.clamp((alpha - 0.5) / 0.5, 0, 1) * 0.85
		local transparency = math.clamp((alpha - 0.85) / 0.15, 0, 1)

		return cframe, scale, transparency
	end)
end

return TerrainDebris
