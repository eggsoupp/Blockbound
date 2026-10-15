--[[
	ToolAnimation

	Loads a tool animation onto a character once and hands back the same track
	every time after. Client-side; animations played on your own character's
	Animator replicate to everyone else by themselves.

		local track = ToolAnimation.track(character, "rbxassetid://123")

	Used by ToolFeedback (a click's swing) and MiningClient (the mining swing,
	looped while the button is held), so both load the same way and warn the
	same way. It used to live inside ToolFeedback.
]]

local ToolAnimation = {}

--[[
	character -> animation id -> AnimationTrack, or false for one that failed.

	Loading an animation is a round trip to the asset and a tool can be clicked
	several times a second, so each is loaded once per body. Weak-keyed on the
	character, so a respawn drops the whole set rather than leaving tracks bound
	to a corpse.
]]
local tracksByCharacter = setmetatable({}, { __mode = "k" })

--[[
	A loaded, ready-to-play track for an id on this character, or nil.

	Failures are remembered as `false` rather than retried: an id that does not
	load will not start loading because somebody clicked again, and warning once
	per body per id is the difference between a message and a flood.

	`priority` defaults to Action, right for a swing. A walk asks for Movement:
	above the default walk, below any swing played over it.
]]
function ToolAnimation.track(character, id, priority)
	if not character or type(id) ~= "string" or id == "" then
		return nil
	end

	local perCharacter = tracksByCharacter[character]
	if not perCharacter then
		perCharacter = {}
		tracksByCharacter[character] = perCharacter
	end

	local cached = perCharacter[id]
	if cached ~= nil then
		return cached or nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = id

	local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
	animation:Destroy()

	if not ok or not loaded then
		warn(string.format(
			"[ToolAnimation] could not load the animation '%s' - check the id is an "
				.. "Animation you own. Tools using it will not move.",
			id
		))
		perCharacter[id] = false
		return nil
	end

	--[[
		Action priority, so the swing plays OVER walking and idling rather than
		being blended into a shrug by them. Set here rather than expected of the
		asset, because an animation uploaded with the wrong priority is the most
		common reason a swing does not appear to play at all.
	]]
	pcall(function()
		loaded.Priority = priority or Enum.AnimationPriority.Action
	end)

	perCharacter[id] = loaded
	return loaded
end

return ToolAnimation
