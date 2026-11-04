-- Run in Studio Edit via MCP. All travel, pass and persistence services are mocks.
local realGame = game
local results = {}
local function check(name, condition)
	assert(condition, name)
	table.insert(results, name)
end
local function signal()
	local s = { handlers = {} }
	function s:Connect(fn) table.insert(self.handlers, fn) return { Disconnect = function() end } end
	function s:Fire(...) for _, fn in ipairs(self.handlers) do fn(...) end end
	return s
end
local menu = { OnServerEvent = signal() }
local players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
local marketplace = { PromptGamePassPurchaseFinished = signal() }
local prompts, trips, messages = {}, {}, {}
local passOwned, failTeleport = true, false
function marketplace:UserOwnsGamePassAsync() return passOwned end
function marketplace:PromptGamePassPurchase(player) table.insert(prompts, player) end
local teleports = { TeleportInitFailed = signal() }
function teleports:TeleportAsync(placeId, list, options)
	table.insert(trips, { placeId = placeId, slot = list[1]:GetAttribute("ActiveIsland"), code = options.ReservedServerAccessCode })
	if failTeleport then error("mock teleport failure") end
end
local attrs, kind, now = {}, "Island", 100
local workspaceMock = { GetAttribute = function(_, key) return attrs[key] end }
local sections = {}
local inventory = { markDirty = function() end, registerSection = function(name, save, load) sections[name] = load end }
local modules = {}
local config = { MaxIslands = 2, SecondIslandPassId = 2064556930 }
local placeConfig = { IslandPlaceId = 93541670199012, WorldPlaceId = 127569658424596 }
function placeConfig.isIsland() return kind == "Island" end
function placeConfig.isWorld() return kind == "World" end
local fakeServices = {
	ReplicatedStorage = realGame.ReplicatedStorage, ServerScriptService = realGame.ServerScriptService,
	Players = players, MarketplaceService = marketplace, TeleportService = teleports,
	RunService = { IsStudio = function() return false end }, TextService = {},
}
local env = setmetatable({
	game = { GetService = function(_, name) return assert(fakeServices[name], name) end },
	workspace = workspaceMock, os = { clock = function() return now end },
	task = { spawn = function(fn, ...) fn(...) end },
}, { __index = getfenv() })
env.require = function(instance)
	local path = instance:GetFullName()
	if path == "ReplicatedStorage.Shared.IslandSlots" then return config end
	if path == "ReplicatedStorage.Shared.PlaceConfig" then return placeConfig end
	if instance.Name == "InventoryStore" then return inventory end
	if instance.Name == "CommandFeedback" then return { tell = function(_, message) table.insert(messages, message) end } end
	if instance.Name == "Remotes" then return { ensure = function() return menu end } end
	if instance.Name == "IslandDirectory" then return { accessCodeFor = function(_, slot) return "island-code-" .. slot end } end
	if modules[path] then return modules[path] end
	local chunk = assert(loadstring(instance.Source, path))
	setfenv(chunk, env)
	local value = chunk()
	modules[path] = value
	return value
end
local slots = env.require(realGame.ServerScriptService.IslandSlots)
local function newPlayer(id)
	local p = { UserId = id, Parent = true, Chatted = signal(), attributes = {} }
	function p:SetAttribute(key, value) self.attributes[key] = value end
	function p:GetAttribute(key) return self.attributes[key] end
	players.PlayerAdded:Fire(p)
	return p
end
local function selectIsland(player, slot)
	now += 1
	menu.OnServerEvent:Fire(player, "select", slot)
end
local owner = newPlayer(123)
attrs.IslandOwnerId, attrs.IslandSlot = owner.UserId, 1
selectIsland(owner, 1)
check("Selecting the current island does not teleport", #trips == 0)
selectIsland(owner, 2)
check("Selecting island 2 immediately routes to its reserved server", #trips == 1 and trips[1].code == "island-code-2" and trips[1].placeId == placeConfig.IslandPlaceId)
selectIsland(owner, 1)
check("Repeated selections cannot change a switch in progress", #trips == 1 and slots.active(owner) == 2)
teleports.TeleportInitFailed:Fire(owner)
selectIsland(owner, 2)
check("A failed teleport can be retried", #trips == 2)
teleports.TeleportInitFailed:Fire(owner)
selectIsland(owner, 1)
check("Current island comparison uses the loaded island, not the previous choice", #trips == 2 and slots.active(owner) == 1)
attrs.IslandSlot = 2
selectIsland(owner, 1)
check("Switching from island 2 back to island 1 routes correctly", #trips == 3 and trips[3].code == "island-code-1")
teleports.TeleportInitFailed:Fire(owner)
kind = "World"
selectIsland(owner, 1)
check("Shared switching logic also works from the main world", #trips == 4)
teleports.TeleportInitFailed:Fire(owner)
failTeleport = true
selectIsland(owner, 2)
failTeleport = false
selectIsland(owner, 2)
check("An immediate teleport error does not block retry", #trips == 6 and trips[6].code == "island-code-2")
passOwned = false
local locked = newPlayer(456)
selectIsland(locked, 2)
check("An unowned island offers the pass without selecting or teleporting", #prompts == 1 and #trips == 6 and slots.active(locked) == 1)
selectIsland(locked, 3)
check("Invalid island numbers are rejected", #trips == 6)
marketplace.PromptGamePassPurchaseFinished:Fire(locked, config.SecondIslandPassId, true)
check("Buying island 2 immediately switches to it", #trips == 7 and trips[7].code == "island-code-2")
return { passed = #results, checks = results }
