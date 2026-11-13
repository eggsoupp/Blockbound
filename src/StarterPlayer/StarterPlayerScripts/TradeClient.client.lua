--[[
	TradeClient

	The trade window (Shared.UI.TradeWindow), shown whenever the server says a
	trade is on.

	There is no button and no request: trades start only at the trade booths
	in the spawn village, when two players sit on the two cushions of one
	booth (ServerScriptService.Trade.TradeStations). Getting up from a cushion
	before the trade starts cancels being ready; inside a trade, the window's
	own Cancel ends it.

	Nothing here decides anything. Every button sends a request over the
	"Trade" remote and the server (ServerScriptService.Trade) answers with the
	trade as it now stands; that answer is all that is ever drawn. What the
	server has to say in words arrives as an ordinary CommandFeedback line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local TradeWindow = require(UI:WaitForChild("TradeWindow"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local Remote = Remotes.wait("Trade")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "Trade"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 21
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local tradeWindow = TradeWindow.create(screen, {
	setOffer = function(kind, name, count)
		Remote:FireServer("offer", kind, name, count)
	end,
	confirm = function(rev)
		Remote:FireServer("confirm", rev)
	end,
	unconfirm = function()
		Remote:FireServer("unconfirm")
	end,
	cancel = function()
		Remote:FireServer("cancel")
	end,
})

Remote.OnClientEvent:Connect(function(action, a)
	if action == "state" and type(a) == "table" then
		tradeWindow.show(a)
	elseif action == "closed" then
		tradeWindow.hide()
	end
end)
