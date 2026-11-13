-- Run in Studio's edit command context. No real DataStore reads or writes.
local source = game.ServerScriptService.IslandService.Source
local first = assert(source:find("local function resolveOwner", 1, true))
local last = assert(source:find("local function beginLoading", first, true))
local resolver = source:sub(first, last - 1)
local factory = assert(loadstring([[return function(IslandDirectory, Players, game, os, task)
local OWNER_LOOKUP_SECONDS, OWNER_RETRY_DELAY = 45, 3
local IslandSlotConfig = {MaxIslands = 2}
local log, warn = function() end, function() end
]] .. resolver .. "\nreturn resolveOwner end"))()
local results = {}
local function run(name, reverse, forward, expectedOwner, expectedUnknown, expectedSlot, minimumRounds, privateId)
	local now, rounds = 0, 0
	local player = {UserId=123456789}
	local directory = {
		ownerOfServer = function(id) rounds += 1; return reverse(rounds, id) end,
		confirmOwner = forward or function() return false end,
	}
	local resolve = factory(directory, {GetPlayers=function() return {player} end},
		{PrivateServerId=privateId or "reserved", PrivateServerOwnerId=0},
		{clock=function() return now end}, {wait=function(seconds) assert(seconds>=0); now+=seconds end})
	local owner, unknown, slot = resolve(player)
	assert(owner==expectedOwner and unknown==expectedUnknown and slot==expectedSlot, name .. ": wrong resolution")
	assert(rounds >= minimumRounds and now <= 45, name .. ": retry budget")
	table.insert(results, {name=name, rounds=rounds, seconds=now})
end
run("new reservation becomes visible", function(round)
	if round < 3 then return nil, "not visible yet", "unlisted" end
	return 123456789, 1
end, nil, 123456789, false, 1, 3)
run("temporary directory error", function(round)
	if round == 1 then return nil, "unavailable", "error" end
	return 123456789, 1
end, nil, 123456789, false, 1, 2)
run("forward reservation verifies second island", function() return nil,"unlisted","unlisted" end,
	function(id, user, slot) return id=="reserved" and user==123456789 and slot==2 end,
	123456789, false, 2, 1)
run("unknown reservation never becomes writable", function() return nil,"unlisted","unlisted" end,
	nil, 123456789, true, nil, 16)
run("existing reservation immediately succeeds", function() return 987654321,2 end,
	nil, 987654321, false, 2, 1)
run("Studio/public fallback retained", function() error("must not query") end,
	nil, 123456789, false, nil, 0, "")
return results
