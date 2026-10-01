--[[
	ItemThumbnails

	The flat picture a slot shows for an item that has no live 3D view.

		ItemThumbnails.bind(icon, "LightLance")   -- set it, and keep it right
		ItemThumbnails.imageFor("LightLance")     -- one-shot, no follow-up

	`rbxthumb://` is why this is not a ViewportFrame: Roblox renders uploaded
	assets on its servers and hands back an ordinary image, costing nothing per
	frame.

	CANDIDATES, IN ORDER
	  1. definition.thumbnail   explicit override, any image content string
	  2. definition.modelId     uploaded Model/Mesh asset id -> rbxthumb
	  3. definition.icon        the hand-drawn icon
	  4. the item's own mesh    first MeshId in its Tool/block template
	  5. the item's own face    first Decal/Texture on that template, which for
	                            a block IS the picture of the block
	PreferModel moves 4 and 5 above 3.

	Each candidate is CHECKED in the background, because most of this project's
	icon ids are placeholders that do not resolve, and an ImageLabel pointed at
	a missing asset draws nothing at all - silently. The check fails OPEN: if
	preloading errors, the candidate is treated as good.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local ItemModels = require(script.Parent:WaitForChild("ItemModels"))

local ItemThumbnails = {}

-- One of the fixed set the thumbnail service accepts; the smallest that still
-- looks right on a slot at 2x display scaling.
local THUMB_SIZE = 150

-- On, so the flat fallback shows the same object at the same angle the live
-- slots do. Off puts authored icons back on top; a broken icon loses either
-- way, so this is taste rather than coverage.
ItemThumbnails.PreferModel = true

local resolved: { [string]: string } = {}
local pending: { [string]: boolean } = {}

-- Items whose every candidate failed, remembered only long enough to stop a
-- redraw storm re-checking them - the templates this derives from replicate a
-- moment after start-up, so an early "nothing" is not "nothing" for good.
local missAt: { [string]: number } = {}
local RETRY_AFTER = 20

-- Weak, so a destroyed slot drops out on its own.
local bindings = setmetatable({}, { __mode = "k" })

local queue: { string } = {}
local working = false

-- ---------------------------------------------------------------------------
-- Candidates
-- ---------------------------------------------------------------------------

local function thumbUrl(assetId: string): string
	return string.format("rbxthumb://type=Asset&id=%s&w=%d&h=%d", assetId, THUMB_SIZE, THUMB_SIZE)
end

-- 12345, "12345", "rbxassetid://12345" and the old asset URL all resolve.
local function assetId(value: any): string?
	if type(value) == "number" then
		return if value > 0 then string.format("%d", value) else nil
	end

	if type(value) == "string" then
		return string.match(value, "%d+")
	end

	return nil
end

local function candidatesFor(itemName: string): { string }
	local definition = ItemDefinitions[itemName]
	local list = {}

	local function add(image: string?)
		if type(image) == "string" and image ~= "" then
			table.insert(list, image)
		end
	end

	if definition then
		add(definition.thumbnail)

		local modelId = assetId(definition.modelId)
		if modelId then
			add(thumbUrl(modelId))
		end
	end

	local icon = definition and definition.icon

	local function addDerived()
		local meshId = ItemModels.meshId(itemName)
		if meshId then
			add(thumbUrl(meshId))
		end

		local faceId = ItemModels.faceTextureId(itemName)
		if faceId then
			add("rbxassetid://" .. faceId)
		end
	end

	if ItemThumbnails.PreferModel then
		addDerived()
		add(icon)
	else
		add(icon)
		addDerived()
	end

	return list
end

-- ---------------------------------------------------------------------------
-- Checking
-- ---------------------------------------------------------------------------

-- Yields. Anything short of Success is a miss, except a failure of the call
-- itself, which means "this engine will not tell us" and is answered yes.
local function loads(image: string): boolean
	local probe = Instance.new("ImageLabel")
	probe.Image = image

	local good = true

	local ok = pcall(function()
		ContentProvider:PreloadAsync({ probe }, function(_contentId, status)
			good = status == Enum.AssetFetchStatus.Success
		end)
	end)

	probe:Destroy()

	return if ok then good else true
end

-- `image` is "" when nothing worked, and that is reported rather than skipped:
-- a caller with a more expensive way to draw the item needs to know the cheap
-- way came up empty. See ItemPreview.fillSlot.
local function applyTo(itemName: string, image: string)
	for label, binding in pairs(bindings) do
		if binding.item == itemName and label.Parent then
			if image ~= "" then
				label.Image = image
			end

			if binding.onResolved then
				binding.onResolved(image)
			end
		end
	end
end

local function work()
	if working then
		return
	end
	working = true

	task.spawn(function()
		while #queue > 0 do
			local itemName = table.remove(queue, 1) :: string
			pending[itemName] = nil

			local winner = ""
			for _, candidate in ipairs(candidatesFor(itemName)) do
				if loads(candidate) then
					winner = candidate
					break
				end
			end

			if winner ~= "" then
				resolved[itemName] = winner
				missAt[itemName] = nil
			else
				missAt[itemName] = os.clock()
			end

			applyTo(itemName, winner)
		end

		working = false
	end)
end

local function request(itemName: string)
	if resolved[itemName] or pending[itemName] then
		return
	end

	local missed = missAt[itemName]
	if missed and os.clock() - missed < RETRY_AFTER then
		return
	end

	pending[itemName] = true
	table.insert(queue, itemName)
	work()
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

-- The best image known RIGHT NOW, plus a request for a better one. The first
-- call usually returns an unchecked candidate, so this is the wrong function
-- for anything long-lived; use `bind`.
function ItemThumbnails.imageFor(itemName: string?): string
	if type(itemName) ~= "string" or itemName == "" then
		return ""
	end

	local known = resolved[itemName]
	if known then
		return known
	end

	request(itemName)

	local candidates = candidatesFor(itemName)
	return candidates[1] or ""
end

--[[
	Points an ImageLabel at an item and keeps it pointed there. A nil item
	unbinds and clears, which is what an emptied slot wants.

	`onResolved` is called once the check finishes, with the winning image or ""
	if nothing loaded - the hook a caller uses to fall back to something more
	expensive for items with no picture anywhere.
]]
function ItemThumbnails.bind(label: any, itemName: string?, onResolved: ((string) -> ())?)
	if typeof(label) ~= "Instance" then
		return
	end

	if type(itemName) ~= "string" or itemName == "" then
		bindings[label] = nil
		label.Image = ""
		return
	end

	bindings[label] = { item = itemName, onResolved = onResolved }
	label.Image = ItemThumbnails.imageFor(itemName)

	-- An item already known to have nothing gets its answer now rather than
	-- never: the queue will not re-check it, so nobody else would say so.
	if onResolved and not resolved[itemName] and missAt[itemName] then
		onResolved("")
	end
end

-- Forgets every checked answer and re-checks whatever is on screen, for a live
-- session where somebody has just dropped a model in and would rather not
-- rejoin.
function ItemThumbnails.clear()
	table.clear(resolved)
	table.clear(missAt)

	local seen = {}
	for _, binding in pairs(bindings) do
		if not seen[binding.item] then
			seen[binding.item] = true
			request(binding.item)
		end
	end
end

return ItemThumbnails
