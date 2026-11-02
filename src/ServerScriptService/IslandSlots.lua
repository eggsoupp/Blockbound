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

	NAMES

	Each island has a name, "Island 1" until its owner changes it from the
	top bar's island picker (IslandPickerClient). Names are run through
	Roblox's text filter - anything a player types and others could see has to
	be - saved with the choice, and mirrored as IslandName1, IslandName2.
	The picker talks to this over the IslandMenu remote: "select", slot and
	"rename", slot, name.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IslandSlots"))
local InventoryStore = require(ServerScriptService:WaitForChild("InventoryStore"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))
local Remotes = require(ReplicatedStorage.Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local TextService = game:GetService("TextService")
local Menu = Remotes.ensure("IslandMenu", "RemoteEvent")

local NAME_LENGTH = 20
local MENU_COOLDOWN = 0.5

local IslandSlots = {}

local PASS_ID = Config.SecondIslandPassId

local owned = {}
local chosen = setmetatable({}, { __mode = "k" })
-- player -> { [slot] = name }, only for islands that have been renamed.
local names = setmetatable({}, { __mode = "k" })
local lastMenuAt = {}

function IslandSlots.name(player: Player, slot: number): string
	local custom = names[player] and names[player][slot]
	return if custom and custom ~= "" then custom else "Island " .. slot
end

function IslandSlots.count(player: Player): number
	return if owned[player] then Config.MaxIslands else 1
end

function IslandSlots.active(player: Player): number
	return math.clamp(chosen[player] or 1, 1, IslandSlots.count(player))
end

local function publish(player: Player)
	player:SetAttribute("IslandCount", IslandSlots.count(player))
	player:SetAttribute("ActiveIsland", IslandSlots.active(player))
	for slot = 1, Config.MaxIslands do
		player:SetAttribute("IslandName" .. slot, IslandSlots.name(player, slot))
	end
end

-- The choice, saved with the player. Weak-keyed rather than cleared on leave,
-- so the leave-save can still read it (see AbilityLoadout's note on `stored`).
InventoryStore.registerSection("islands", function(player)
	-- String keys: a table holding only [2] does not survive as JSON.
	local saved = {}
	for slot, name in pairs(names[player] or {}) do
		saved[tostring(slot)] = name
	end
	return { active = chosen[player] or 1, names = saved }
end, function(player, value)
	local active = type(value) == "table" and tonumber(value.active) or 1
	chosen[player] = math.clamp(math.floor(active), 1, Config.MaxIslands)
	local saved = {}
	if type(value) == "table" and type(value.names) == "table" then
		for slot = 1, Config.MaxIslands do
			local name = value.names[slot] or value.names[tostring(slot)]
			if type(name) == "string" then
				saved[slot] = string.sub(name, 1, NAME_LENGTH)
			end
		end
	end
	names[player] = saved
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

local function choose(player: Player, slot: number, quiet: boolean?)
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
	if not quiet then
		CommandFeedback.tell(player, string.format("The island button now takes you to %s.", IslandSlots.name(player, slot)), "good")
	end
end

--[[
	A new name for an island, filtered as text other players may see. Spaces
	are tidied, the length is capped, and an empty name puts the default back.
]]
local function rename(player: Player, slot: number, text: string)
	local tidy = string.sub(string.gsub(string.gsub(text, "%s+", " "), "^ ", ""), 1, NAME_LENGTH)
	tidy = string.gsub(tidy, " $", "")
	if tidy ~= "" then
		local ok, filtered = pcall(function()
			return TextService:FilterStringAsync(tidy, player.UserId, Enum.TextFilterContext.PublicChat)
				:GetNonChatStringForBroadcastAsync()
		end)
		if not ok then
			CommandFeedback.tell(player, "Could not check that name. Please try again.", "bad")
			return
		end
		tidy = filtered
	end
	names[player] = names[player] or {}
	names[player][slot] = if tidy ~= "" then tidy else nil
	InventoryStore.markDirty(player)
	publish(player)
end

Menu.OnServerEvent:Connect(function(player, action, slot, text)
	if os.clock() - (lastMenuAt[player] or -10) < MENU_COOLDOWN then
		return
	end
	lastMenuAt[player] = os.clock()
	slot = tonumber(slot)
	if not slot or slot ~= math.floor(slot) or slot < 1 or slot > Config.MaxIslands then
		return
	end
	if action == "select" then
		choose(player, slot, true)
	elseif action == "rename" and type(text) == "string" and #text <= 200 then
		if slot > IslandSlots.count(player) then
			return
		end
		rename(player, slot, text)
	end
end)

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
	lastMenuAt[player] = nil
end)

return IslandSlots
