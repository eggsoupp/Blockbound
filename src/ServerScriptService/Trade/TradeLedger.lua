--[[
	TradeLedger

	The one fact about a trade that has to be true for both players at once:
	did it happen.

		TradeLedger.decide(tradeId, "committed") -> "committed" | "aborted" | nil, err
		TradeLedger.decide(tradeId, "aborted")   -> "committed" | "aborted" | nil, err

	WHY THIS EXISTS

	Each player's save is its own DataStore key, and Roblox cannot write two
	keys as one action. So a trade that simply saved player A and then player B
	could be cut in half by a failed call or a dead server, with one side's
	goods gone and the other side's never arrived (or both sides holding them).

	Instead each player's record carries the trade as PENDING - what they put
	in, what they are owed (see TradeEscrow) - and this ledger holds one small
	record per trade that says how it ended. Writing that record is a single
	write to a single key, so it either happened or it did not: that is the
	moment the trade is done.

	FIRST WRITER WINS

	`decide` writes the outcome it was asked for only if the trade has no
	outcome yet, and always returns the outcome that stands. So:

	  * the server running the trade asks for "committed" once both records
	    are safely saved as pending;
	  * anybody who finds a pending trade with nobody running it (a player
	    loading their save after a crash) asks for "aborted".

	Whichever gets there first settles it for everyone, and the other is told
	what was settled. Two servers can never reach different answers, which is
	the whole point. Asking again is always safe.

	nil means the ledger could not be reached and NOTHING is known. The caller
	must leave the goods held and ask again later - never guess.

	The records are a few dozen bytes each and are never deleted: a trade must
	stay decided for as long as any save might still list it as pending.
]]

local DataStoreService = game:GetService("DataStoreService")

local TradeLedger = {}

local DATASTORE_NAME = "TradeLedger_v1"
local KEY_PREFIX = "t_"

-- 1s, 2s, 4s between tries.
local MAX_ATTEMPTS = 4

local store = nil

local function getStore()
	if not store then
		local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, DATASTORE_NAME)
		if not ok then
			return nil, tostring(result)
		end
		store = result
	end
	return store
end

local function isOutcome(value): boolean
	return value == "committed" or value == "aborted"
end

function TradeLedger.decide(tradeId: string, wanted: string): (string?, string?)
	assert(type(tradeId) == "string" and tradeId ~= "", "[TradeLedger] decide needs a trade id")
	assert(isOutcome(wanted), "[TradeLedger] decide needs 'committed' or 'aborted'")

	-- Studio-only fault injection for testing an unreachable ledger.
	if workspace:GetAttribute("TradeTestLedgerDown") and game:GetService("RunService"):IsStudio() then
		return nil, "test: ledger down"
	end

	local dataStore, storeError = getStore()
	if not dataStore then
		return nil, storeError
	end

	local lastError = nil
	for attempt = 1, MAX_ATTEMPTS do
		local outcome = nil

		local ok, err = pcall(function()
			dataStore:UpdateAsync(KEY_PREFIX .. tradeId, function(old)
				if type(old) == "table" and isOutcome(old.state) then
					-- Already decided. Leave it exactly as it is.
					outcome = old.state
					return nil
				end
				outcome = wanted
				return { state = wanted, at = os.time() }
			end)
		end)

		if ok and outcome then
			return outcome
		end

		lastError = err
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ (attempt - 1))
		end
	end

	warn(string.format("[TradeLedger] Could not decide trade %s: %s", tradeId, tostring(lastError)))
	return nil, tostring(lastError)
end

return TradeLedger
