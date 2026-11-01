--[[
	TouchActions

	What the on-screen touch buttons (StarterPlayerScripts.TouchControls) and
	the scripts that own each action say to one another, so neither has to
	know the other is there. Client only.

		TouchActions.castRequested    Event(slot): an ability button was pressed
		TouchActions.requestCast(slot)

		TouchActions.setSlot(slot, info)   AbilityClient's readout of a slot:
		                                   { name, cooldown, remaining } or nil
		TouchActions.getSlot(slot)

	Abilities still go through AbilityClient's own cast(), so a tap is held to
	exactly the cooldown, menu and target rules a key press is.
]]

local TouchActions = {}

local cast = Instance.new("BindableEvent")
TouchActions.castRequested = cast.Event

function TouchActions.requestCast(slot: number)
	cast:Fire(slot)
end

local slots: { [number]: { name: string, cooldown: number, remaining: number }? } = {}

function TouchActions.setSlot(slot: number, info)
	slots[slot] = info
end

function TouchActions.getSlot(slot: number)
	return slots[slot]
end

return TouchActions
