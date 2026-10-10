--[[
	GearService

	What a player's worn gear adds up to. One walk of the gear slots, read by
	everything a piece of gear can affect.

		GearService.get(player) -> bonuses
		GearService.weaponMultiplier(player) -> 1 + weapon damage bonus
		GearService.abilityMultiplier(player) -> 1 + ability damage bonus
		GearService.onChanged(function(player, bonuses) ... end)

	  bonuses.defense         flat, added to CombatConfig.BaseDefense
	  bonuses.maxHealth       flat, added to CombatConfig.BaseMaxHealth
	  bonuses.maxMana         flat, added to AbilityConfig.MaxMana
	  bonuses.abilityDamage   fraction: 0.15 is +15% ability damage
	  bonuses.weaponDamage    fraction: 0.15 is +15% weapon damage

	WHERE THE NUMBERS COME FROM

	The `buffs` table on whatever sits in a gear slot - the accessory and armour
	slots InventoryConstants defines - using the same shape armour already used
	for defense. A new accessory is an ItemDefinitions entry, never a code change
	here. Items in ordinary slots count for nothing: a ring in your bag is not a
	ring on your finger.

	THE SAME ACCESSORY TWICE COUNTS ONCE

	Otherwise the best build is five copies of the strongest ring, and every
	accessory after the first decision is just more of it. Different accessories
	stack freely.

	WHO HEARS ABOUT CHANGES

	Gear moves through the inventory, whose single change listener belongs to
	the save system. So, like CombatService's defense push, this sweeps a few
	times a second and reports only players whose totals actually changed -
	which is what CombatService (max health) and ManaService (max mana) listen
	for. Damage bonuses need no listener: they are read at the moment of each hit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local InventoryConstants = require(ReplicatedStorage:WaitForChild("InventoryConstants"))

local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))

local GearService = {}

-- The buffs this module adds up, and so the fields every bonuses table has.
local STATS = { "defense", "maxHealth", "maxMana", "abilityDamage", "weaponDamage" }

-- Read-only, for ServerScriptService.ContentAudit: which buffs gear actually does
-- something with, so a buff nothing reads can be reported.
GearService.Stats = STATS

local SWEEP_INTERVAL = 0.5

local listeners = {}
local sweeping = false

-- player -> the bonuses last reported, to tell a change from a repeat.
local lastReported = setmetatable({}, { __mode = "k" })

local function emptyBonuses()
	local bonuses = {}
	for _, stat in ipairs(STATS) do
		bonuses[stat] = 0
	end
	return bonuses
end

function GearService.get(player)
	local bonuses = emptyBonuses()

	local inventory = InventoryService.GetInventory(player)
	if not inventory then
		return bonuses
	end

	local slots = inventory:GetAll()
	local counted = {}

	for index = 1, #slots do
		if InventoryConstants.getSlotRestriction(index) ~= nil then
			local slot = slots[index]
			local name = slot and slot.name

			if name and not counted[name] then
				counted[name] = true

				local definition = ItemDefinitions[name]
				local buffs = definition and definition.buffs

				if type(buffs) == "table" then
					for _, stat in ipairs(STATS) do
						local value = tonumber(buffs[stat])
						if value then
							bonuses[stat] += value
						end
					end
				end
			end
		end
	end

	return bonuses
end

function GearService.weaponMultiplier(player)
	return math.max(0, 1 + GearService.get(player).weaponDamage)
end

function GearService.abilityMultiplier(player)
	return math.max(0, 1 + GearService.get(player).abilityDamage)
end

local function sameBonuses(a, b)
	if not a or not b then
		return false
	end
	for _, stat in ipairs(STATS) do
		if a[stat] ~= b[stat] then
			return false
		end
	end
	return true
end

local function sweep()
	for _, player in ipairs(Players:GetPlayers()) do
		local bonuses = GearService.get(player)
		if not sameBonuses(bonuses, lastReported[player]) then
			lastReported[player] = bonuses
			for _, listener in ipairs(listeners) do
				task.spawn(listener, player, bonuses)
			end
		end
	end
end

--[[
	Calls `listener(player, bonuses)` whenever a player's totals change,
	including the first time they are seen. Started by the first subscriber, so
	a place that needs none pays nothing.
]]
function GearService.onChanged(listener)
	table.insert(listeners, listener)

	if sweeping then
		return
	end
	sweeping = true

	task.spawn(function()
		while true do
			task.wait(SWEEP_INTERVAL)
			local ok, err = pcall(sweep)
			if not ok then
				warn("[GearService] sweep failed:", err)
			end
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	lastReported[player] = nil
end)

return GearService
