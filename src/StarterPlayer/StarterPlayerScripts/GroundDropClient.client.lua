--[[
	GroundDropClient

	Draws the items lying on the ground that this player is allowed to see: a
	small glowing cube in the item's rarity colour, floating a little above the
	floor, bobbing and turning slowly - the way a dropped item does in
	Minecraft.

	DRAWING ONLY

	Every cube here is this client's own, made from what ServerScriptService.
	GroundDrops chose to tell it. The server keeps the real record and decides
	every pickup by distance on its own side; nothing here is ever sent back
	except one "sync" asking for a fresh copy of the list. Deleting or moving a
	cube changes this screen and nothing else.

	Someone else's enemy loot never arrives here at all, so there is nothing to
	hide - privacy is the server not telling, not this script not drawing.

	ONE LOOP, NEAR DROPS ONLY

	A single RenderStepped pass moves every drop within DropConfig.
	AnimateDistance of the camera with one BulkMoveTo, reusing the same two
	arrays every frame. Further ones hold still until the camera comes back.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Theme = require(Shared:WaitForChild("UI"):WaitForChild("Theme"))
local DropConfig = require(Shared:WaitForChild("Inventory"):WaitForChild("DropConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local DropEvent = Remotes.wait("GroundDrops")

local TAU = math.pi * 2
local BOB_SPEED = TAU / DropConfig.BobSeconds
local SPIN_SPEED = TAU / DropConfig.SpinSeconds
local ANIMATE_SQUARED = DropConfig.AnimateDistance * DropConfig.AnimateDistance

local folder = Instance.new("Folder")
folder.Name = "GroundDrops"
folder.Parent = workspace

-- id -> { part, base, phase }
local drops = {}

local function colorFor(itemName)
	local definition = ItemDefinitions[itemName]
	return Theme.rarityColor(definition and definition.rarity)
end

local function poseAt(drop, now)
	local base = drop.base
	local t = now + drop.phase
	return CFrame.new(
		base.X,
		base.Y + DropConfig.Hover + math.sin(t * BOB_SPEED) * DropConfig.BobHeight,
		base.Z
	) * CFrame.Angles(0, t * SPIN_SPEED, 0)
end

local function add(id, itemName, position)
	if type(id) ~= "number" or type(itemName) ~= "string" or typeof(position) ~= "Vector3" then
		return
	end

	local existing = drops[id]
	if existing then
		existing.base = position
		return
	end

	local part = Instance.new("Part")
	part.Name = "Drop"
	part.Size = Vector3.one * DropConfig.Size
	part.Color = colorFor(itemName)
	part.Material = Enum.Material.Neon
	part.Transparency = DropConfig.Transparency
	part.Anchored = true
	part.CanCollide = false
	-- Out of every raycast and overlap query, so a drop never blocks a mining
	-- ray or a placement check.
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true

	-- Each drop starts at its own point in the bob and the turn, so a pile of
	-- them does not move in lockstep like one object.
	local drop = { part = part, base = position, phase = math.random() * DropConfig.BobSeconds * 4 }
	part.CFrame = poseAt(drop, os.clock())
	part.Parent = folder

	drops[id] = drop
end

local function remove(id)
	local drop = drops[id]
	if drop then
		drops[id] = nil
		drop.part:Destroy()
	end
end

local function clear()
	for id in pairs(drops) do
		remove(id)
	end
end

DropEvent.OnClientEvent:Connect(function(action, id, a, b, c)
	if action == "add" then
		-- (id, itemName, amount, position)
		add(id, a, c)
	elseif action == "move" then
		local drop = drops[id]
		if drop and typeof(a) == "Vector3" then
			drop.base = a
		end
	elseif action == "remove" then
		remove(id)
	elseif action == "snapshot" then
		clear()
		if type(id) == "table" then
			for _, row in ipairs(id) do
				if type(row) == "table" then
					add(row[1], row[2], row[4])
				end
			end
		end
	end
	-- "amount" changes nothing drawn: a stack of one and a stack of forty are
	-- the same cube.
end)

-- Listening first, THEN asking, so nothing sent in between is missed: the
-- snapshot replaces whatever arrived before it.
DropEvent:FireServer("sync")

-- ---------------------------------------------------------------------------
-- Animation
-- ---------------------------------------------------------------------------

local movedParts = {}
local movedFrames = {}
local movedCount = 0

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local eye = camera.CFrame.Position
	local now = os.clock()
	local count = 0

	for _, drop in pairs(drops) do
		local offset = drop.base - eye
		if offset:Dot(offset) <= ANIMATE_SQUARED then
			count += 1
			movedParts[count] = drop.part
			movedFrames[count] = poseAt(drop, now)
		end
	end

	-- Trim last frame's tail, so the arrays stay the same length as each other
	-- and nothing stale is moved.
	for index = count + 1, movedCount do
		movedParts[index] = nil
		movedFrames[index] = nil
	end
	movedCount = count

	if count > 0 then
		workspace:BulkMoveTo(movedParts, movedFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
