--[[
	AbilityStorage

	The client's view of the player's stored ASPECTS, and the requests that act
	on them. No drawing of its own: Shared.UI.AspectInventoryWindow is the page
	that shows them, and AbilityPanel shows the count on its INVENTORY button.

		AbilityStorage.state()            the last push: { slots, extras, capacity, canBuy, ... }
		AbilityStorage.groups()           { { name, count } } one per aspect, in AspectConfig order
		AbilityStorage.Changed            fires after every push
		AbilityStorage.use(aspectName)    make it the active aspect (the old one is lost)
		AbilityStorage.buy()              prompt the extra-slots product
		AbilityStorage.price()            "R$ 300" once Roblox has said, else ""
		AbilityStorage.icon(parent, aspectName, size) / setIcon(image, aspectName)

	One copy of every aspect is stored for free. Bought slots hold EXTRA copies
	- a spare is how a player switches back, since using an aspect destroys the
	one it replaces.

	THE SERVER OWNS EVERYTHING REAL (ServerScriptService.AbilityLoadout). It
	sends the stored aspects as a flat list, one entry per copy; this file only
	groups them for showing.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Theme = require(script.Parent.Theme)
local ItemSprites = require(script.Parent:WaitForChild("ItemSprites"))
local Config = require(Shared.Abilities.AspectConfig)
local StorageConfig = require(Shared.Abilities.StorageConfig)
local Remotes = require(Shared.Net.Remotes)

local Request = Remotes.wait("AbilityStorageRequest")
local Changed = Remotes.wait("AbilityStorageChanged")

local FALLBACK_ICON = "scroll_arcane"

local state = {
	slots = {},
	extras = 0,
	capacity = 0,
	maxSlots = StorageConfig.MaxSlots,
	perPurchase = StorageConfig.SlotsPerPurchase,
	productId = StorageConfig.AbilityStorageProductId,
	canBuy = false,
}

local changed = Instance.new("BindableEvent")

-- productId -> "R$ 300", once Roblox has said.
local prices: { [number]: string } = {}

local AbilityStorage = {}
AbilityStorage.Changed = changed.Event

function AbilityStorage.state()
	return state
end

--[[
	The stored copies as one entry per aspect, in AspectConfig order (commons
	first, legendaries last), so the list does not reshuffle when a wish lands.
]]
function AbilityStorage.groups(): { { name: string, count: number } }
	local counts = {}
	for _, name in ipairs(state.slots or {}) do
		counts[name] = (counts[name] or 0) + 1
	end
	local groups = {}
	for _, name in ipairs(Config.names()) do
		if counts[name] then
			table.insert(groups, { name = name, count = counts[name] })
		end
	end
	return groups
end

function AbilityStorage.use(aspectName: string)
	Request:FireServer("use", aspectName)
end

function AbilityStorage.buy()
	if state.canBuy then
		Request:FireServer("buy")
	end
end

function AbilityStorage.price(): string
	local productId = state.productId
	if type(productId) ~= "number" or productId <= 0 then
		return ""
	end
	if not prices[productId] then
		prices[productId] = ""
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
			if ok and info and info.PriceInRobux then
				prices[productId] = "R$ " .. tostring(info.PriceInRobux)
				changed:Fire(state)
			end
		end)
	end
	return prices[productId]
end

-- An aspect's picture off the item atlas, pixel-sharp.
function AbilityStorage.icon(parent: Instance, aspectName: string?, size: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.BackgroundTransparency = 1
	image.Image = Theme.ItemAtlas
	image.ResampleMode = Enum.ResamplerMode.Pixelated
	image.Size = UDim2.fromOffset(size, size)
	image.Parent = parent
	AbilityStorage.setIcon(image, aspectName)
	return image
end

function AbilityStorage.setIcon(image: ImageLabel, aspectName: string?)
	local definition = Config.get(aspectName)
	local sprite = ItemSprites.Sprites[definition and definition.icon or FALLBACK_ICON]
		or ItemSprites.Sprites[FALLBACK_ICON]
	image.Visible = definition ~= nil and sprite ~= nil
	if sprite then
		image.ImageRectOffset = sprite.offset
		image.ImageRectSize = sprite.size
	end
end

Changed.OnClientEvent:Connect(function(value)
	if type(value) ~= "table" or type(value.slots) ~= "table" then
		return
	end
	state = value
	changed:Fire(state)
end)

task.defer(function()
	Request:FireServer("sync")
end)

return AbilityStorage
