--[[
	IslandSlots

	Which islands a player owns, and which one the island button (and /island)
	takes them to.

		IslandSlots.count(player)    1, or 2 with the Second Island pass
		IslandSlots.active(player)   the island travel goes to

	Both are mirrored onto the player as attributes - IslandCount, ActiveIsland -
	so the client can word its button without asking.

	OWNERSHIP IS ROBLOX'S

	Island 2 is a Game Pass (Shared.IslandSlots.SecondIslandPassId). Whether a
	player has it is asked of MarketplaceService on join and is never saved:
	a pass belongs to the account, and a refund has to be able to take it
	away. A purchase is believed from PromptGamePassPurchaseFinished at once,
	because UserOwnsGamePassAsync is cached and lags behind a fresh purchase.
	Losing the pass never deletes island 2's save; it just stops being chosen.

	WHICH ONE IS ACTIVE IS OURS

	Saved with the player as the "islands" section of their InventoryStore
	record, so the choice follows them between servers and places.

	SWITCHING

	  /switchisland        to the other island
	  /switchisland 2      to island 2 (offers the pass if it is not owned)

	It changes where the island button goes; it does not move the player.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IslandSlots"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

local IslandSlots = {}

local PASS_ID = Config.SecondIslandPassId

local owned = {}
local chosen = setmetatable({}, { __mode = "k" })

function IslandSlots.count(player: Player): number
	return if owned[player] then Config.MaxIslands else 1
end

function IslandSlots.active(player: Player): number
	return math.clamp(chosen[player] or 1, 1, IslandSlots.count(player))
end

local function publish(player: Player)
	player:SetAttribute("IslandCount", IslandSlots.count(player))
	player:SetAttribute("ActiveIsland", IslandSlots.active(player))
end

-- The choice, saved with the player. Weak-keyed rather than cleared on leave,
-- so the leave-save can still read it (see AbilityLoadout's note on `stored`).
InventoryStore.registerSection("islands", function(player)
	return { active = chosen[player] or 1 }
end, function(player, value)
	local active = type(value) == "table" and tonumber(value.active) or 1
	chosen[player] = math.clamp(math.floor(active), 1, Config.MaxIslands)
	publish(player)
end)

local function checkPass(player: Player)
	if PASS_ID <= 0 then
		return
	end
	local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, PASS_ID)
	if ok and has and player.Parent then
		owned[player] = true
		publish(player)
	end
end

local function choose(player: Player, slot: number)
	if slot > IslandSlots.count(player) then
		if PASS_ID > 0 then
			MarketplaceService:PromptGamePassPurchase(player, PASS_ID)
		else
			CommandFeedback.tell(player, "A second island is not on sale yet.", "bad")
		end
		return
	end
	chosen[player] = slot
	InventoryStore.markDirty(player)
	publish(player)
	CommandFeedback.tell(player, string.format("The island button now takes you to island %d.", slot), "good")
end

local function onChatted(player: Player, message: string)
	local command, argument = string.match(message, "^%s*(/%a+)%s*(%d*)%s*$")
	if not command or string.lower(command) ~= "/switchisland" then
		return
	end
	local slot = tonumber(argument)
	if not slot then
		-- No number: the other island, or the offer of one.
		slot = if IslandSlots.active(player) == 1 then 2 else 1
	end
	if slot < 1 or slot > Config.MaxIslands then
		CommandFeedback.tell(player, string.format("Islands go from 1 to %d.", Config.MaxIslands), "bad")
		return
	end
	choose(player, slot)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if passId == PASS_ID and purchased then
		owned[player] = true
		chosen[player] = 2
		InventoryStore.markDirty(player)
		publish(player)
		CommandFeedback.tell(player, "Island 2 is yours. The island button now takes you there; /switchisland swaps back.", "good")
	end
end)

local function watch(player: Player)
	publish(player)
	task.spawn(checkPass, player)
	player.Chatted:Connect(function(message)
		local ok, err = pcall(onChatted, player, message)
		if not ok then
			warn("[IslandSlots]", err)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end

Players.PlayerRemoving:Connect(function(player)
	owned[player] = nil
end)

return IslandSlots
