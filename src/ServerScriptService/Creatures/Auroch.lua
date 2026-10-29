--[[
	Auroch - a wild bull of the Plains, in herds. An animal: it grazes and
	minds its own business (EnemyConfig `passive`) until somebody hurts it.

	THE HERD. Hurt one and every auroch within `herdRadius` turns on you too,
	snorting - you do not pick a fight with one bull.

	Once roused it fights exactly like the Pentasaurus - paw the ground, then
	a charge that cannot turn and stuns it against a wall, and a horn toss up
	close - so it runs that creature's trait and rig with its own model
	(ServerScriptService.Creatures.Pentasaurus, Shared.Enemies.CreatureRigs.
	Auroch).
]]

local CreatureKit = require(script.Parent.CreatureKit)
local Pentasaurus = require(script.Parent.Pentasaurus)

local Tuning = {
	herdRadius = 30,
}

local Trait = {}
Trait.Tuning = Tuning

function Trait.start(entry)
	Pentasaurus.start(entry)
	entry.model:SetAttribute("Rig", "Auroch")
end

-- Any blow from a player rouses the herd against them. Takes the blow whole.
function Trait.guard(entry, _amount, dealer)
	if typeof(dealer) == "Instance" and dealer:IsA("Player") and not (entry.roused and entry.roused[dealer]) then
		entry.roused = entry.roused or {}
		entry.roused[dealer] = true
		local Service = CreatureKit.service()
		Service.forEachNear(entry.model:GetPivot().Position, Tuning.herdRadius, function(model)
			local name = Service.describe(model)
			if name == entry.name then
				Service.provoke(model, dealer)
				CreatureKit.fx("snort", model, 0.8)
			end
		end)
	end
	return 1
end

Trait.step = Pentasaurus.step

return Trait
