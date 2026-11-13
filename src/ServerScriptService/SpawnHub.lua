--[[
	SpawnHub

	Builds the open world's spawn village on the level plateau the terrain
	generates round the origin (TerrainConfig.SpawnZones.VillageFlatBlocks,
	GeneratedColumns). Called once by SpawnServer with the plateau's surface
	height; islands have no village.

	  StarfallHub (Model, workspace)
	    Floor             tiles on the grass: flagstone plaza and market
	                      square, dirt roads that fray into the grass
	    StarfallShrine    the wishing star in the middle; its StarfallWish
	                      prompt opens the Starfall banner (WishClient), where
	                      wishes are made for aspects
	    MerchantStall     + StarfallMerchant, the rigged merchant, whose
	                      StarfallShop prompt opens the Aspect Shop of
	                      permanent aspects (ShopClient)
	    TradingStations   two trade booths in the market square east of the
	                      shrine; PositionA/PositionB mark the two pads
	                      (Trade/TradeStations: standing on both starts a trade)
	    Market, Buildings the market arch, gates, notice board
	    Dressing          placeable decor pieces (Shared.Building.DecorModels):
	                      the big well, lamps, a campfire, and a training yard
	                      whose dummies take hits like enemies
	                      (EnemyService.adopt)

	The village models are place assets: ServerStorage.VillageAssets, built
	from assets/voxel-village (see its README). A missing one is stood in for
	by a plain box so the layout and the prompts still work.

	Layout, in studs from the plateau centre. Blocks are 4 studs and the
	origin is a block corner, so a cell (bx, bz) is centred on (4bx+2, 4bz+2).
	Players spawn on the south road looking north (-Z): the shrine, and the
	merchant's stall behind it; the market is to the right, the training yard
	to the left.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DecorModels = require(Shared:WaitForChild("Building"):WaitForChild("DecorModels"))
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))

local Hub = {}

local CELL = 4
local PLAZA_TOP = 0.5
local PATH_TOP = 0.25

-- Neon is for lamps only, as in the village's own models (BuildVillage): a
-- decor piece on this list keeps its Neon glow; any other's glowing parts
-- (crystals and the like) are built as ordinary colour.
local DECOR_LAMPS = {
	LampPost = true, Lantern = true, StandingTorch = true, StoneLantern = true,
	FairyLantern = true, CrystalLamp = true, MushroomLamp = true, Candle = true,
	SkullCandle = true, LavaLamp = true, Brazier = true, Campfire = true,
	StoneFireplace = true, JackOLantern = true,
}

Hub.SpawnPoint = Vector3.new(0, 0, 18)

-- Sizes for the stand-in boxes, studs (x, y, z), from the asset build.
local FALLBACK_SIZE = {
	Merchant = Vector3.new(4, 8, 3),
	PlazaTile = Vector3.new(4, 0.5, 4),
	PlazaTileMoss = Vector3.new(4, 0.5, 4),
	PathTile = Vector3.new(4, 0.25, 4),
	PathEdge = Vector3.new(4, 0.25, 4),
	PathCorner = Vector3.new(4, 0.25, 4),
	MerchantStall = Vector3.new(13, 3, 3),
	StarfallShrine = Vector3.new(11, 6, 11),
	TradeBoothTeal = Vector3.new(4, 3, 2),
	TradeBoothCrimson = Vector3.new(4, 3, 2),
	MarketArch = Vector3.new(1, 12, 1),
	NoticeBoard = Vector3.new(6, 8, 1),
	VillageGate = Vector3.new(1, 12, 1),
}

local function invisible(parent, name, cf, size)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame = name, size or Vector3.new(1, 1, 1), cf
	p.Transparency, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = 1, true, false, false, false
	p.Parent = parent
	return p
end

local function standIn(name)
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("Placeholder", true)
	local size = FALLBACK_SIZE[name] or Vector3.new(4, 4, 4)
	local p = Instance.new("Part")
	p.Name = "Body"
	p.Size = size
	p.CFrame = CFrame.new(0, size.Y / 2, 0)
	p.Anchored = true
	p.Color = Color3.fromRGB(120, 110, 130)
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = m
	m.WorldPivot = CFrame.identity
	return m
end

local function template(name)
	local library = ServerStorage:FindFirstChild("VillageAssets")
	local found = library and library:FindFirstChild(name)
	if found then
		return found:Clone()
	end
	warn("[SpawnHub] ServerStorage.VillageAssets." .. name .. " is missing; using a stand-in box")
	return standIn(name)
end

-- A floating name over a landmark, readable from across the plaza.
local function label(part, title, subtitle, height)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	-- Sized in studs (a BillboardGui's Size scale is studs), so it shrinks
	-- with distance like a real sign instead of piling up on screen.
	gui.Size = UDim2.fromScale(12, 2.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = part
	local function line(text, y, h, color)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, h)
		t.Position = UDim2.fromScale(0, y)
		t.FontFace = Theme.Fonts.Heading
		t.TextScaled = true
		t.TextColor3 = color
		t.TextStrokeColor3 = Color3.fromRGB(30, 22, 18)
		t.TextStrokeTransparency = 0
		t.Text = text
		t.Parent = gui
	end
	line(title, 0, 0.58, Color3.fromRGB(255, 226, 150))
	if subtitle then
		line(subtitle, 0.6, 0.4, Color3.fromRGB(236, 232, 220))
	end
	gui.Parent = part
	return gui
end

-- The VFX pack's drifting sparkle (Radiant Treasure's "Sparkles", emitted
-- from a box volume), found once. Nil when the pack is not in this place.
local sparkleTemplate = nil
local function findSparkle()
	if sparkleTemplate == nil then
		sparkleTemplate = false
		local pack = ReplicatedStorage:FindFirstChild("assets(VFX for use)")
		for _, d in (if pack then pack:GetDescendants() else {}) do
			if d:IsA("ParticleEmitter") and d.Name == "Sparkles" and d.Parent and d.Parent.Name == "Area"
				and d.Parent.Parent and d.Parent.Parent.Name == "Day 14 - Radiant Treasure" then
				sparkleTemplate = d
				break
			end
		end
	end
	return sparkleTemplate or nil
end

-- Fills an invisible box with tinted sparkles.
local function sparkles(parent, cf, size, color, rate)
	local template = findSparkle()
	if not template then
		return
	end
	local host = invisible(parent, "Sparkles", cf, size)
	local emitter = template:Clone()
	emitter.Color = ColorSequence.new(color)
	emitter.Rate = rate
	emitter.Parent = host
end

-- Cell helpers ---------------------------------------------------------------

local function key(bx, bz)
	return bx .. "," .. bz
end

local function hash(bx, bz, salt)
	local h = bit32.bxor(bx * 73856093 % 4294967296, bz * 19349663 % 4294967296, salt * 83492791)
	h = bit32.bxor(h, bit32.rshift(h, 13)) * 1274126177 % 4294967296
	return bit32.band(bit32.bxor(h, bit32.rshift(h, 16)), 0xffff) / 65536
end

-- What the floor is, cell by cell: "plaza" | "path".
local function planFloor()
	local floor = {}
	local function set(bx, bz, kind)
		if floor[key(bx, bz)] ~= "plaza" then
			floor[key(bx, bz)] = kind
		end
	end
	local function rect(bx0, bz0, bx1, bz1, kind)
		for bx = math.min(bx0, bx1), math.max(bx0, bx1) do
			for bz = math.min(bz0, bz1), math.max(bz0, bz1) do
				set(bx, bz, kind)
			end
		end
	end
	-- The plaza round the shrine.
	for bx = -4, 3 do
		for bz = -4, 3 do
			local x, z = bx * CELL + 2, bz * CELL + 2
			if x * x + z * z <= 12.6 * 12.6 then
				set(bx, bz, "plaza")
			end
		end
	end
	-- The market square, east, with the road running through it.
	rect(4, -6, 9, 5, "plaza")
	-- Roads: south, east and west out to the gates; north to the stall.
	rect(-1, 3, 0, 11, "path")
	rect(3, -1, 11, 0, "path")
	rect(-12, -1, -4, 0, "path")
	rect(-1, -5, 0, -4, "path")
	rect(-3, -7, 2, -6, "path")
	-- The training yard, north-west, off the west road.
	rect(-8, -6, -4, -3, "path")
	rect(-6, -2, -5, -2, "path")
	-- Round the big well (south-west) and the campfire, joined to the road.
	rect(-8, 4, -5, 6, "path")
	rect(-4, 5, -2, 6, "path")
	rect(-6, 7, -3, 9, "path")
	-- The garden, south-east.
	rect(1, 7, 3, 8, "path")
	return floor
end

local DIRS = {
	{ 1, 0 }, -- +X
	{ 0, -1 }, -- -Z
	{ -1, 0 }, -- -X
	{ 0, 1 }, -- +Z
}

-- Turns of 90 degrees about +Y that take local +X to DIRS[i]: CFrame.Angles(0,
-- turn * pi/2, 0) sends +X to (cos, 0, -sin), so turn i-1.
local function layFloor(parent, floor, origin)
	local folder = Instance.new("Folder")
	folder.Name = "Floor"
	folder.Parent = parent
	local count = 0
	for k, kind in floor do
		local bx, bz = string.match(k, "(-?%d+),(-?%d+)")
		bx, bz = tonumber(bx), tonumber(bz)
		local open = {}
		for i, d in DIRS do
			open[i] = floor[key(bx + d[1], bz + d[2])] == nil
		end
		local name, turn
		if kind == "plaza" then
			name = if hash(bx, bz, 1) < 0.35 then "PlazaTileMoss" else "PlazaTile"
			turn = math.floor(hash(bx, bz, 2) * 4)
		else
			-- A corner: grass on local +X and +Z, i.e. on DIRS[i] and DIRS[i-1].
			for i = 1, 4 do
				local prev = if i == 1 then 4 else i - 1
				if open[i] and open[prev] then
					name, turn = "PathCorner", i - 1
					break
				end
			end
			if not name then
				for i = 1, 4 do
					if open[i] then
						name, turn = "PathEdge", i - 1
						break
					end
				end
			end
			if not name then
				name, turn = "PathTile", math.floor(hash(bx, bz, 3) * 4)
			end
		end
		local tile = template(name)
		tile:PivotTo(origin * CFrame.new(bx * CELL + 2, 0, bz * CELL + 2) * CFrame.Angles(0, turn * math.pi / 2, 0))
		tile.Parent = folder
		count += 1
		if count % 40 == 0 then
			task.wait()
		end
	end
	return folder
end

local function floorTop(floor, x, z)
	local kind = floor[key(math.floor(x / CELL), math.floor(z / CELL))]
	return if kind == "plaza" then PLAZA_TOP elseif kind == "path" then PATH_TOP else 0
end

function Hub.build(surfaceY)
	local previous = workspace:FindFirstChild("StarfallHub")
	if previous then
		previous:Destroy()
	end
	local hub = Instance.new("Model")
	hub.Name = "StarfallHub"
	hub.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local origin = CFrame.new(0, surfaceY, 0)
	local floor = planFloor()
	layFloor(hub, floor, origin)

	local function folder(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = hub
		return f
	end
	local market = folder("Market")
	local buildings = folder("Buildings")
	local dressing = folder("Dressing")

	-- A village model, front (-Z) looking along `facing`.
	local function asset(name, x, z, facing, parent)
		local model = template(name)
		local at = Vector3.new(x, floorTop(floor, x, z), z)
		model:PivotTo(origin * CFrame.lookAt(at, at + facing))
		model.Parent = parent or hub
		return model
	end
	-- A placeable decor piece, centred on (x, z). Their front is +Z, so it
	-- looks along `facing` with its back turned the other way. A piece of
	-- several cells pivots on its first cell and runs to its right and back,
	-- so it is shifted to centre its whole footprint.
	local function decor(id, x, z, facing)
		local model = DecorModels.build(id, true)
		if not model then
			warn("[SpawnHub] no decor piece " .. id)
			return
		end
		local cells = DecorModels.cells(id) or { 1, 1, 1 }
		local centre = Vector3.new((cells[1] - 1) * CELL / 2, 0, -(cells[3] - 1) * CELL / 2)
		local at = Vector3.new(x, floorTop(floor, x, z), z)
		local turn = CFrame.lookAt(at, at - facing)
		model:PivotTo(origin * turn * CFrame.new(-centre))
		if not DECOR_LAMPS[id] then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part:GetAttribute("Glow") then
					part.Material = Enum.Material.SmoothPlastic
				end
			end
		end
		model.Parent = dressing
		return model
	end
	local N, S, E, W = Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0)

	-- The shrine ---------------------------------------------------------------
	local shrine = asset("StarfallShrine", 0, 0, S)
	local wishSpot = shrine:GetAttribute("Anchor_WishSpot") or Vector3.new(0, 0, -4.5)
	local wishHost = invisible(shrine, "WishPrompt", shrine:GetPivot() * CFrame.new(wishSpot + Vector3.new(0, 3, 0)), Vector3.new(2, 2, 2))
	local wish = Instance.new("ProximityPrompt")
	wish.Name, wish.ActionText, wish.ObjectText = "StarfallWish", "Make a Wish", "Starfall Shrine"
	wish.MaxActivationDistance, wish.RequiresLineOfSight = 10, false
	wish.Parent = wishHost
	label(shrine:FindFirstChild("Star") or wishHost, "Starfall Shrine", "Wish for aspects", 4.8)
	-- Drifting sparkles from the VFX pack: gold round the star, violet over
	-- the dais.
	sparkles(shrine, shrine:GetPivot() * CFrame.new(0, 9.4, 0), Vector3.new(7, 6, 7), Color3.fromRGB(255, 214, 120), 6)
	sparkles(shrine, shrine:GetPivot() * CFrame.new(0, 2.5, 0), Vector3.new(10, 3, 10), Color3.fromRGB(170, 140, 255), 5)

	-- The merchant ---------------------------------------------------------------
	local stall = asset("MerchantStall", 0, -30, S)
	local spot = stall:GetAttribute("Anchor_MerchantSpot") or Vector3.new(0, 0, 0.5)
	local merchant = template("Merchant")
	merchant.Name = "StarfallMerchant"
	merchant:PivotTo(stall:GetPivot() * CFrame.new(spot))
	merchant.Parent = hub
	local root = merchant:FindFirstChild("HumanoidRootPart") or merchant.PrimaryPart
	if not root then
		root = invisible(merchant, "HumanoidRootPart", merchant:GetPivot() * CFrame.new(0, 3, 0))
		merchant.PrimaryPart = root
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText = "StarfallShop", "Browse Aspects", "Starfall Merchant"
	prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 12, false
	prompt.Parent = root
	-- Above the stall's canopy and sign, not inside it.
	label(root, "Starfall Merchant", "Permanent aspects", 12.5)
	decor("Barrel", -10, -32, S)
	decor("SupplyCrate", -10, -28, S)
	decor("Barrel", 10, -28, S)
	decor("CrystalCluster", 10, -32, S)

	-- The market square: two trade booths across the road. --------------------
	-- No prompts on the pads: standing on one is being ready (TradeStations).
	asset("MarketArch", 14, 0, E, market)
	local stations = Instance.new("Folder")
	stations.Name = "TradingStations"
	stations.Parent = hub
	for i, spec in { { "TradeBoothTeal", -11 }, { "TradeBoothCrimson", 11 } } do
		-- Facing east, so the trade line (the booth's Z) runs east-west.
		local station = asset(spec[1], 28, spec[2], E, stations)
		station.Name = "Exchange" .. i
		-- A Seat on each cushion, facing the table (a Seat seats you looking
		-- along its -Z, so the -Z cushion's is turned round). Walking into
		-- one sits you down; TradeStations starts the trade when both are taken.
		for _, side in { "A", "B" } do
			local at = station:GetAttribute("Anchor_Pad" .. side) or Vector3.new(0, 1.25, if side == "A" then -3 else 3)
			local seat = Instance.new("Seat")
			seat.Name = "Position" .. side
			seat.Size = Vector3.new(2.2, 0.4, 2.2)
			seat.CFrame = station:GetPivot() * CFrame.new(at - Vector3.new(0, 0.2, 0))
				* (if side == "A" then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
			seat.Transparency = 1
			seat.Anchored = true
			seat.CanCollide = false
			seat.Parent = station
		end
		if i == 1 then
			label(invisible(station, "LabelHost", station:GetPivot() * CFrame.new(0, 14, 0)), "Trading Post", "Sit on a cushion with your partner", 2)
		end
	end
	decor("SupplyCrate", 37, -20, W)
	decor("Barrel", 38, -16, W)
	decor("Barrel", 20, 20, E)
	decor("HayBale", 37, 20, W)
	decor("SupplyCrate", 20, -22, E)
	for _, l in { { 18, -16 }, { 18, 16 }, { 38, -10 }, { 38, 10 } } do
		decor("LampPost", l[1], l[2], if l[1] < 28 then W else E)
	end

	-- The notice board, by the spawn point and turned to face it: the first
	-- thing a player sees on the left. Its prompt opens the updates window
	-- (NoticeBoardClient, Shared.UI.Notices).
	local board = asset("NoticeBoard", -9, 14, (Vector3.new(0, 0, 18) - Vector3.new(-9, 0, 14)).Unit, buildings)
	local boardHost = invisible(board, "ReadPrompt", board:GetPivot() * CFrame.new(0, 4.5, -1.2), Vector3.new(4, 4, 1))
	local read = Instance.new("ProximityPrompt")
	read.Name, read.ActionText, read.ObjectText = "VillageNotices", "Read", "Notice Board"
	read.MaxActivationDistance, read.RequiresLineOfSight = 10, false
	read.Parent = boardHost
	label(boardHost, "Notice Board", "Updates and news", 6)

	-- Buildings ---------------------------------------------------------------
	for _, g in { { 0, 46, S }, { 46, 0, E }, { -46, 0, W } } do
		asset("VillageGate", g[1], g[2], g[3], buildings)
	end

	-- Training yard, north-west: dummies that take hits like enemies. ----------
	local EnemyService = require(ServerScriptService:WaitForChild("EnemyService"))
	for _, d in { { -20, -14 }, { -26, -18 }, { -20, -22 } } do
		local dummy = decor("TrainingDummy", d[1], d[2], E)
		if dummy then
			EnemyService.adopt("TrainingDummy", dummy)
		end
	end
	decor("WeaponRack", -30, -14, E)
	decor("ArcheryTarget", -30, -22, E)
	decor("HayBale", -16, -24, E)

	-- The big well, south-west, and the campfire. --------------------------------
	decor("Well", -26, 22, E)
	decor("FlowerPot", -20, 18, E)
	decor("FlowerPot", -20, 26, E)
	decor("WoodenBench", -26, 15, S)
	decor("Campfire", -18, 34, S)
	decor("WoodenBench", -18, 28, S)
	decor("WoodenBench", -18, 40, N)
	decor("WoodenBench", -24, 34, E)
	decor("FirewoodPile", -26, 40, E)
	-- The garden, south-east.
	decor("HayBale", 22, 38, W)
	decor("Scarecrow", 26, 34, W)
	decor("FlowerPot", 10, 30, W)
	-- Lamps along the roads and round the plaza.
	for _, l in { { 6, 26 }, { 6, 38 }, { -6, 38 }, { -26, 6 }, { -38, 6 }, { -38, -6 } } do
		decor("LampPost", l[1], l[2], if math.abs(l[1]) < 10 then (if l[1] > 0 then W else E) else (if l[2] > 0 then N else S))
	end
	decor("Signpost", 6, 42, S)

	hub.WorldPivot = origin
	hub.Parent = workspace
	return hub
end

return Hub
