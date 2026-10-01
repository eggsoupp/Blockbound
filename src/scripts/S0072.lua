--[[
	AbilityScope

	One handle for everything an ability creates, so that ending it is a single
	call rather than a checklist somebody will eventually get wrong.

		local scope = AbilityScope.new()

		scope:add(part)                       -- Instance      -> :Destroy()
		scope:add(signal:Connect(fn))         -- Connection    -> :Disconnect()
		scope:add(function() ... end)         -- teardown fn   -> called
		scope:delay(0.5, fn)                  -- task.delay    -> cancelled
		scope:spawn(fn)                       -- task.spawn    -> cancelled
		scope:tween(part, info, { ... })      -- created, played, cancelled

		scope:destroy()                       -- all of the above, in reverse

	WHY THIS EXISTS

	Effects are the easiest thing in a Roblox game to leak. The reference this
	game's first ability is modelled on leans on Debris and a handful of
	task.wait calls, which is fine for one player pressing one key in an empty
	baseplate and is not fine here: a player who dies, unequips, or leaves
	mid-cast leaves connections listening, tweens playing and parts sitting in
	the workspace with nothing left that remembers they exist.

	So every ability - server side and client side - runs inside a scope, and
	the thing that ends the ability destroys the scope. There is exactly one
	place to get cleanup right, and adding an ability cannot get it wrong.

	REVERSE ORDER, AND WHY

	Teardown runs newest-first. Connections and delays created late usually
	depend on instances created early, so unwinding the other way round is what
	stops a handler firing against something that has just been destroyed.

	AFTER DESTRUCTION

	A dead scope accepts nothing: `add` destroys what it is handed, `delay` and
	`spawn` never run, `tween` returns nil. That means a callback that fires one
	frame after teardown cannot resurrect the effect, which is the failure this
	whole module is here to prevent.
]]

local TweenService = game:GetService("TweenService")

local AbilityScope = {}
AbilityScope.__index = AbilityScope

export type Scope = typeof(setmetatable({} :: {
	_items: { any },
	_dead: boolean,
}, AbilityScope))

function AbilityScope.new(): Scope
	return setmetatable({
		_items = {},
		_dead = false,
	}, AbilityScope) :: any
end

function AbilityScope:isDead(): boolean
	return self._dead
end

--[[
	Disposes of one tracked thing. Everything is pcall'd: teardown must not be
	able to abandon the rest of the list because one item was already gone.
]]
local function dispose(item)
	if typeof(item) == "Instance" then
		pcall(function()
			item:Destroy()
		end)
	elseif typeof(item) == "RBXScriptConnection" then
		pcall(function()
			item:Disconnect()
		end)
	elseif typeof(item) == "thread" then
		-- Cancelling a thread that has already finished throws, and a finished
		-- thread is the common case, so this is expected rather than exceptional.
		pcall(task.cancel, item)
	elseif type(item) == "function" then
		pcall(item)
	end
end

--[[
	Tracks something for teardown and returns it, so it can be used inline:

		local part = scope:add(Instance.new("Part"))
]]
function AbilityScope:add(item: any): any
	if self._dead then
		dispose(item)
		return item
	end

	table.insert(self._items, item)
	return item
end

--[[
	A tracked task.delay. The thread is cancelled by teardown, and the callback
	additionally re-checks the scope on entry - a thread can be resumed by the
	scheduler in the same frame teardown runs, and cancelling it then is too
	late.
]]
function AbilityScope:delay(seconds: number, callback: (...any) -> ()): thread?
	if self._dead then
		return nil
	end

	local thread
	thread = task.delay(seconds, function()
		if self._dead then
			return
		end
		callback()
	end)

	return self:add(thread)
end

function AbilityScope:spawn(callback: (...any) -> ()): thread?
	if self._dead then
		return nil
	end

	local thread = task.spawn(function()
		if self._dead then
			return
		end
		callback()
	end)

	return self:add(thread)
end

--[[
	Creates, plays and tracks a tween.

	Tracked as a teardown function rather than as an Instance: a tween that is
	merely destroyed keeps running to completion, and an ability that has ended
	should not still be moving things. Cancel, then destroy.
]]
function AbilityScope:tween(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween?
	if self._dead then
		return nil
	end

	local ok, tween = pcall(TweenService.Create, TweenService, instance, info, goals)
	if not ok or not tween then
		return nil
	end

	self:add(function()
		tween:Cancel()
		tween:Destroy()
	end)

	tween:Play()
	return tween
end

--[[
	Ends everything. Safe to call twice; the second call does nothing.
]]
function AbilityScope:destroy()
	if self._dead then
		return
	end
	self._dead = true

	local items = self._items
	for index = #items, 1, -1 do
		dispose(items[index])
		items[index] = nil
	end
end

return AbilityScope
