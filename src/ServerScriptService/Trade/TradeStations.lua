--[[
	TradeStations

	The trade booths in the spawn village (SpawnHub): each has a low table
	with a floor cushion either side, and a Seat on each cushion
	(PositionA / PositionB). Walking into a cushion sits you down, and
	sitting is being ready to trade, no prompt. When two different players
	sit at one booth, the trade starts for them (startTrade, from
	TradeService, which keeps every inventory, session, confirmation and
	settlement rule). It starts once per pairing: it can start again only
	after one of them has got up and sat down again.

	Who sits where is read on the server from the Seats, four times a second.
]]

local Players = game:GetService("Players")

local Stations = {}

local POLL = 0.25

-- The living player sitting on a cushion's Seat, or nil.
local function sitter(seat)
	local humanoid = seat:IsA("Seat") and seat.Occupant
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(humanoid.Parent)
	return if player and player.Parent == Players then player else nil
end

function Stations.bind(hub, startTrade, tell)
	local booths = {}
	for _, station in ipairs(hub.TradingStations:GetChildren()) do
		local a, b = station:FindFirstChild("PositionA"), station:FindFirstChild("PositionB")
		if a and b then
			-- who is on each seat now, and the pair this booth already started.
			table.insert(booths, { seats = { a, b }, on = {}, started = nil })
		end
	end

	task.spawn(function()
		while hub.Parent do
			for _, booth in ipairs(booths) do
				local onA = sitter(booth.seats[1])
				local onB = sitter(booth.seats[2])
				for i, now in ipairs({ onA, onB }) do
					if now and booth.on[i] ~= now then
						local other = if i == 1 then onB else onA
						if not other then
							tell(now, "Waiting for a partner on the other cushion. Jump to get up.", "good")
						end
					end
					booth.on[i] = now
				end
				if onA and onB and onA ~= onB then
					if not booth.started then
						booth.started = { onA, onB }
						startTrade(onA, onB)
					end
				elseif booth.started then
					-- Somebody got up: the next pairing may start again.
					booth.started = nil
				end
			end
			task.wait(POLL)
		end
	end)
end

return Stations
