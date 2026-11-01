--[[
	GrassRing

	Loose grass, grown on the client in a ring around the player, so the ground
	reads as thick with it while only a few hundred tufts exist at a time. The
	server never places grass: it would be thousands of parts per chunk that
	nobody can see past a few blocks.

	Where it grows is decided per block column, the same way every time, so
	walking back over a meadow finds the same tufts: only on the top face of a
	Grass block, and as thickly as a two-octave noise field says - meadows
	grassy, patches of nearly bare ground between them.

	Only at the High detail setting (Settings > World > Detail).

	The terrain is block parts in workspace.GeneratedTerrain, named after their
	block, so a ray down a column says whether it ends on grass. Mining or
	building under the ring changes those parts, which re-checks the columns
	they cover; a chunk that streams in late is caught the same way.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerSettings = require(Shared:WaitForChild("UI"):WaitForChild("PlayerSettings"))

local player = Players.LocalPlayer

local STUD = 4
-- Ring radius in blocks. Past it the ground is far enough away that the
-- missing tufts read as distance rather than as a hard edge.
local RADIUS = 11
-- Columns ray-cast per step at most, nearest first, so arriving somewhere new
-- fills in over a few frames rather than in one hitch.
local BUDGET = 90
local STEP_SECONDS = 0.1
-- Up to this many tufts on one column, in the grassiest places.
local MAX_PER_COLUMN = 5
-- Noise wavelengths in blocks: the large one makes meadows and bare patches,
-- the small one keeps a meadow's edge ragged.
local MEADOW_SCALE = 24
local DETAIL_SCALE = 7
local SCALE_VARIANCE = 0.2

local terrainFolder = workspace:WaitForChild("GeneratedTerrain")
local grassFolder = ReplicatedStorage:WaitForChild("TerrainAssets"):WaitForChild("Grass")

local holder = Instance.new("Folder")
holder.Name = "GrassRing"
holder.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { terrainFolder }

-- ---------------------------------------------------------------------------
-- Templates
-- ---------------------------------------------------------------------------

--[[
	Each grass model is one MeshPart. Kept as that part, its rotation relative to
	upright, and how far its centre sits above its lowest point - so a tuft can
	be stood on the ground with one CFrame and no measuring per tuft.
]]
local templates = {}

local function halfHeight(cf: CFrame, size: Vector3): number
	return 0.5 * (
		math.abs(cf.RightVector.Y) * size.X
		+ math.abs(cf.UpVector.Y) * size.Y
		+ math.abs(cf.LookVector.Y) * size.Z
	)
end

for _, model in ipairs(grassFolder:GetChildren()) do
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if part then
		local rotation = part.CFrame - part.CFrame.Position
		table.insert(templates, {
			part = part,
			rotation = rotation,
			half = halfHeight(rotation, part.Size),
			pool = {},
		})
	end
end

-- ---------------------------------------------------------------------------
-- Where grass grows
-- ---------------------------------------------------------------------------

local function hash(x: number, z: number, salt: number): number
	local v = math.sin(x * 127.1 + z * 311.7 + salt * 74.7) * 43758.5453
	return v - math.floor(v)
end

-- How grassy a column is, 0..1.
local function grassiness(bx: number, bz: number): number
	local n = math.noise(bx / MEADOW_SCALE, bz / MEADOW_SCALE, 7.31)
		+ 0.35 * math.noise(bx / DETAIL_SCALE, bz / DETAIL_SCALE, 3.77)
	return math.clamp((n + 0.45) * 1.2, 0, 1)
end

local function columnKey(bx: number, bz: number): number
	return (bx + 100000) * 200000 + (bz + 100000)
end

-- ---------------------------------------------------------------------------
-- The ring
-- ---------------------------------------------------------------------------

-- key -> { bx, bz, tufts = { {template, part} } } for every column checked.
local columns = {}
local queue = {}
local queued = {}
local centreX, centreZ = nil, nil
local enabled = false

local function take(template)
	local part = table.remove(template.pool)
	if not part then
		part = template.part:Clone()
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end
	return part
end

local function release(key: number)
	local column = columns[key]
	if not column then
		return
	end
	for _, tuft in ipairs(column.tufts) do
		tuft.part.Parent = nil
		table.insert(tuft.template.pool, tuft.part)
	end
	columns[key] = nil
end

local function grow(bx: number, bz: number)
	local key = columnKey(bx, bz)
	release(key)

	local column = { bx = bx, bz = bz, tufts = {} }
	columns[key] = column

	local chance = grassiness(bx, bz)
	if chance <= 0 or #templates == 0 then
		return
	end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local fromY = if root then root.Position.Y + 48 else 400
	local origin = Vector3.new(bx * STUD + STUD * 0.5, fromY, bz * STUD + STUD * 0.5)
	local hit = workspace:Raycast(origin, Vector3.new(0, -160, 0), rayParams)

	-- Trees and logs live in the same chunk folders as the blocks. A ray that
	-- lands on one carries on down from just under it, so a forest floor still
	-- gets its grass; a ray that starts inside a part does not hit that part.
	for _ = 1, 4 do
		if not hit or not hit.Instance.Parent or not hit.Instance.Parent:IsA("Model") then
			break
		end
		local from = hit.Position - Vector3.new(0, 0.05, 0)
		hit = workspace:Raycast(from, Vector3.new(0, origin.Y - 160 - from.Y, 0), rayParams)
	end

	if not hit or hit.Instance.Name ~= "Grass" or hit.Normal.Y < 0.9 then
		return
	end

	for slot = 1, MAX_PER_COLUMN do
		-- Each further tuft needs a grassier column.
		if hash(bx, bz, slot) >= chance - (slot - 1) * 0.18 then
			break
		end

		local template = templates[math.floor(hash(bx, bz, slot + 10) * #templates) + 1]
		local scale = 1 + (hash(bx, bz, slot + 20) * 2 - 1) * SCALE_VARIANCE
		local part = take(template)
		part.Size = template.part.Size * scale

		local x = bx * STUD + 0.4 + hash(bx, bz, slot + 30) * (STUD - 0.8)
		local z = bz * STUD + 0.4 + hash(bx, bz, slot + 40) * (STUD - 0.8)
		local yaw = hash(bx, bz, slot + 50) * math.pi * 2

		part.CFrame = CFrame.new(x, hit.Position.Y + template.half * scale - 0.05, z)
			* CFrame.Angles(0, yaw, 0)
			* template.rotation
		part.Parent = holder

		table.insert(column.tufts, { template = template, part = part })
	end
end

local function clearAll()
	for key in pairs(columns) do
		release(key)
	end
	table.clear(queue)
	table.clear(queued)
	centreX, centreZ = nil, nil
end

-- Re-queues the ring around a new centre: drops what fell outside, adds what
-- came inside, nearest first.
local function recentre(bx: number, bz: number)
	centreX, centreZ = bx, bz

	for key, column in pairs(columns) do
		local dx, dz = column.bx - bx, column.bz - bz
		if dx * dx + dz * dz > (RADIUS + 1) * (RADIUS + 1) then
			release(key)
		end
	end

	for dx = -RADIUS, RADIUS do
		for dz = -RADIUS, RADIUS do
			if dx * dx + dz * dz <= RADIUS * RADIUS then
				local key = columnKey(bx + dx, bz + dz)
				if not columns[key] and not queued[key] then
					queued[key] = true
					table.insert(queue, { bx + dx, bz + dz, key })
				end
			end
		end
	end

	table.sort(queue, function(a, b)
		local da = (a[1] - bx) ^ 2 + (a[2] - bz) ^ 2
		local db = (b[1] - bx) ^ 2 + (b[2] - bz) ^ 2
		return da < db
	end)
end

-- A terrain part changed: every checked column it covers is checked again.
local function markDirty(part: Instance)
	if not enabled or not part:IsA("BasePart") or not centreX then
		return
	end
	local half = part.Size * 0.5
	local p = part.Position
	for bx = math.floor((p.X - half.X) / STUD), math.floor((p.X + half.X - 0.01) / STUD) do
		for bz = math.floor((p.Z - half.Z) / STUD), math.floor((p.Z + half.Z - 0.01) / STUD) do
			local dx, dz = bx - centreX, bz - centreZ
			if dx * dx + dz * dz <= RADIUS * RADIUS then
				local key = columnKey(bx, bz)
				if not queued[key] then
					queued[key] = true
					table.insert(queue, 1, { bx, bz, key })
				end
			end
		end
	end
end

terrainFolder.DescendantAdded:Connect(markDirty)
terrainFolder.DescendantRemoving:Connect(markDirty)

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	if not enabled then
		return
	end
	elapsed += dt
	if elapsed < STEP_SECONDS then
		return
	end
	elapsed = 0

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local bx = math.floor(root.Position.X / STUD)
	local bz = math.floor(root.Position.Z / STUD)
	if bx ~= centreX or bz ~= centreZ then
		recentre(bx, bz)
	end

	for _ = 1, BUDGET do
		local entry = table.remove(queue, 1)
		if not entry then
			break
		end
		queued[entry[3]] = nil
		local dx, dz = entry[1] - centreX, entry[2] - centreZ
		if dx * dx + dz * dz <= RADIUS * RADIUS then
			grow(entry[1], entry[2])
		end
	end
end)

local function applySetting(level: string)
	local wanted = level == "High"
	if wanted == enabled then
		return
	end
	enabled = wanted
	if not enabled then
		clearAll()
	end
end

PlayerSettings.Changed.Event:Connect(function(key, value)
	if key == "detailLevel" then
		applySetting(value)
	end
end)
applySetting(PlayerSettings.get("detailLevel"))
