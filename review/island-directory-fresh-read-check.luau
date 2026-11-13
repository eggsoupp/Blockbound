-- Edit-context regression test with an in-memory store, never a real DataStore.
local realGame = game
local reads, repairs = {}, {}
local fakeStore = {}
function fakeStore:GetAsync(key, options)
	assert(options and options.UseCache == false, "ownership read used cached data")
	table.insert(reads, key)
	if key == "server_existing" then return 1749102129 end
	if key == "server_second" then return "1749102129_2" end
	if key == "owner_1749102129_2" then return {serverId="second",code="test-only"} end
	return nil
end
function fakeStore:SetAsync(key, value) repairs[key] = value end
local fakeGame = {}
function fakeGame:GetService(name)
	if name == "DataStoreService" then return {GetDataStore=function() return fakeStore end} end
	return realGame:GetService(name)
end
local factory = assert(loadstring("return function(game)\n" .. game.ServerScriptService.IslandDirectory.Source .. "\nend"))()
local directory = factory(fakeGame)
local owner, slot = directory.ownerOfServer("existing")
assert(owner==1749102129 and slot==1, "legacy island 1 mapping changed")
owner, slot = directory.ownerOfServer("second")
assert(owner==1749102129 and slot==2, "island 2 mapping changed")
assert(directory.confirmOwner("second",1749102129,2)==true)
assert(repairs.server_second=="1749102129_2", "reverse link not repaired")
assert(directory.confirmOwner("wrong-server",1749102129,2)==false, "wrong server accepted")
local missing, _, kind = directory.ownerOfServer("missing")
assert(missing==nil and kind=="unlisted", "unknown server accepted")
return {passed=true, freshReads=#reads, realDataStoreCalls=0}
