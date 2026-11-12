--[[
	AspectShop

	The server half of the Aspect Shop (StarterPlayerScripts.ShopClient):
	PERMANENT aspects, sold as Game Passes (Shared.Abilities.AspectShopConfig).

	  AspectShopBuy (RemoteEvent, client -> server)  aspectName
	      Prompts that aspect's Game Pass. The client never says it bought
	      anything: the grant comes from Roblox's own purchase event below.

	A PURCHASE BECOMES A PERMANENT PASS IN THE INVENTORY. A Game Pass is
	remembered by Roblox, so on every join each pass on sale is checked
	(UserOwnsGamePassAsync) and any not yet claimed is handed over
	(AbilityLoadout.claimPass), which also saves it. That is what makes a
	purchase survive a server crash between paying and saving.

	The pass in the inventory is then the player's to REDEEM (the aspect is
	permanently theirs, and stays theirs) or to TRADE while it is unredeemed
	(ServerScriptService.Trade). Roblox cannot move a Game Pass between
	accounts, so the buyer "owns" it for ever; the claimed mark is what stops
	it being handed over twice. The cost: nobody can buy the same Game Pass a
	second time - a second pass can only come from a trade.

	EQUIPPING is not here: it is AbilityLoadout's "use" request, the same one
	the inventory sends, which knows not to use a permanent aspect up.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local AspectConfig = require(Shared:WaitForChild("Abilities"):WaitForChild("AspectConfig"))
local ShopConfig = require(Shared.Abilities:WaitForChild("AspectShopConfig"))

local AbilityLoadout = require(ServerScriptService:WaitForChild("AbilityLoadout"))
local CommandFeedback = require(ServerScriptService:WaitForChild("CommandFeedback"))

local BuyRemote = Remotes.ensure("AspectShopBuy", "RemoteEvent")

-- The shortest gap between two buy requests from one player.
local BUY_COOLDOWN = 1
-- How long to wait for a player's save before giving up on the join check.
local READY_TIMEOUT = 90

local lastBuy = {}

-- A Game Pass is handed over exactly once, as a permanent pass in the
-- inventory, so one that has been traded away is not handed back by the next
-- join check.
local function grant(player: Player, aspectName: string, announce: boolean)
	if AbilityLoadout.claimPass(player, aspectName) and announce then
		CommandFeedback.tell(player, string.format(
			"A permanent %s pass is in your inventory. Redeem it to keep the aspect for good, or trade it.",
			AspectConfig.displayName(aspectName)
		), "good")
	end
end

BuyRemote.OnServerEvent:Connect(function(player, aspectName)
	if os.clock() - (lastBuy[player] or -10) < BUY_COOLDOWN then
		return
	end
	lastBuy[player] = os.clock()

	if type(aspectName) ~= "string" or not AspectConfig.get(aspectName) then
		return
	end
	local passId = ShopConfig.passFor(aspectName)
	if passId <= 0 then
		CommandFeedback.tell(player, "That aspect is not on sale yet.", "bad")
		return
	end
	if AbilityLoadout.passClaimed(player, aspectName) then
		-- Roblox still counts the Game Pass as theirs and will not sell it twice.
		CommandFeedback.tell(player, "You have already bought that pass. Another can only come from a trade.", "bad")
		return
	end
	if not AbilityLoadout.isReady(player) then
		CommandFeedback.tell(player, "Your save is not ready. Please try again.", "bad")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, passId)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	local aspectName = ShopConfig.aspectForPass(passId)
	if aspectName and AbilityLoadout.isReady(player) then
		grant(player, aspectName, true)
	end
	-- Not ready: the join check finds the pass next time.
end)

-- On join, once the save is in: every pass on sale that the player owns.
local function checkPasses(player: Player)
	local waited = 0
	while player.Parent and not AbilityLoadout.isReady(player) and waited < READY_TIMEOUT do
		waited += task.wait(1)
	end
	if not (player.Parent and AbilityLoadout.isReady(player)) then
		return
	end
	for aspectName, passId in pairs(ShopConfig.Passes) do
		if passId > 0 and not AbilityLoadout.passClaimed(player, aspectName) then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
			if ok and owns then
				grant(player, aspectName, false)
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(checkPasses, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(checkPasses, player)
end

Players.PlayerRemoving:Connect(function(player)
	lastBuy[player] = nil
end)
