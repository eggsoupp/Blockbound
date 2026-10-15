--[[
	WorldFeedback

	Motion's counterpart for the 3D world: the outline around whatever the
	player is about to act on, the flash that says an action landed, and the
	small shell of light that marks a break or a kill.

		WorldFeedback.focus("mine", proxyPart, "Mine")   -- claim the outline
		WorldFeedback.progress("mine", 0.4)              -- whiten as work climbs
		WorldFeedback.release("mine")                    -- let it go (fades)
		WorldFeedback.flash(model, "Hit")                -- one-shot emphasis
		WorldFeedback.impact(position, color, 4)         -- break / kill shell

	Presentation only. Nothing here decides what can be mined, hit or placed;
	the callers ask the same questions their actions ask and the server still
	answers every one of them.

	ONE OUTLINE, MANY ASKERS

	Mining, chopping, fighting, building and prompts all want to say "this
	one". Five Highlights would light five things at once, which is the
	opposite of telling the player which one their click goes to. So each
	system CLAIMS the focus under its own name and SOURCE_ORDER decides which
	claim is drawn. The held tool already makes the first four exclusive; a
	prompt only shows when no tool target does.

	A claim is cheap to repeat. Placement re-asserts its claim thirty times a
	second, and a call that changes nothing returns before touching anything -
	no tween, no table, no property write.

	NEVER THROUGH WALLS

	Every Highlight here is Occluded, so a target behind terrain shows only the
	parts of it the player can already see. An enemy round a corner stays
	round the corner.

	GONE MEANS GONE AT ONCE

	Looking away fades the outline over a few frames. A target that leaves the
	world - mined, felled, killed, collected, streamed out - drops its outline
	the same frame, because a ghost outline hanging where something used to be
	is a lie about the world.

	Highlights are a limited resource per client (31 drawn at once), which is
	why this module owns a fixed handful and re-adorns them rather than
	creating any per target.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local WorldFeedback = {}

local IS_CLIENT = RunService:IsClient()

-- ---------------------------------------------------------------------------
-- Tuning
-- ---------------------------------------------------------------------------
-- Every colour, transparency and duration the world feedback uses. Restrained
-- on purpose: an outline readable on snow, sand and stone without turning the
-- terrain into a colouring book.

local WHITE = Color3.new(1, 1, 1)

WorldFeedback.Tween = {
	FadeIn = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	FadeOut = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	-- Valid to invalid and back, on the same target.
	Restyle = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- How long a flash takes to decay back to the resting look.
WorldFeedback.FlashSeconds = 0.22

--[[
	outline / outlineAlpha   the edge colour and its transparency
	fill / fillAlpha         the body tint and its transparency (1 = none)
	fillPeak                 fill transparency at progress 1, for styles whose
	                         target shows work being done to it
]]
WorldFeedback.Styles = {
	-- Hover targets. Accent, because selection anywhere reads the same - the
	-- hotbar marker is this colour too.
	-- Mining is the most repeated action in the game, so its outlines are edges
	-- only: aimed at, a clear edge; being mined, a brighter one; too hard for
	-- the pickaxe in hand, a faint red one. No fill - the break cracks
	-- (Shared.Blocks.BreakOverlay) show progress, and a tint would wash them out.
	Mine = { outline = Theme.Color.Accent, outlineAlpha = 0.35, fill = WHITE, fillAlpha = 1 },
	MineActive = { outline = Theme.Color.Accent, outlineAlpha = 0.08, fill = WHITE, fillAlpha = 1 },
	MineBlocked = { outline = Theme.Color.Bad, outlineAlpha = 0.45, fill = Theme.Color.Bad, fillAlpha = 1 },
	Harvest = { outline = Theme.Color.Accent, outlineAlpha = 0.3, fill = WHITE, fillAlpha = 1, fillPeak = 0.6 },
	Enemy = { outline = Theme.Color.Accent, outlineAlpha = 0.35, fill = WHITE, fillAlpha = 1 },
	-- Prompts are pressed rather than clicked, so they read as a softer white.
	Interact = { outline = Theme.Color.Text, outlineAlpha = 0.4, fill = WHITE, fillAlpha = 0.93 },

	-- The build ghost already tints itself; the outline makes the verdict
	-- legible where the ghost overlaps something of a similar colour.
	PlaceValid = { outline = Theme.Color.Good, outlineAlpha = 0.15, fill = Theme.Color.Good, fillAlpha = 1 },
	PlaceInvalid = { outline = Theme.Color.Bad, outlineAlpha = 0.1, fill = Theme.Color.Bad, fillAlpha = 1 },

	-- One-shot flashes.
	Hit = { outline = WHITE, outlineAlpha = 0, fill = WHITE, fillAlpha = 0.7 },
	-- Bosses are flashed by their edge only, so a hit never paints over the
	-- body that is winding up the next telegraph.
	HitOutline = { outline = WHITE, outlineAlpha = 0, fill = WHITE, fillAlpha = 1 },
	Confirm = { outline = Theme.Color.Good, outlineAlpha = 0, fill = Theme.Color.Good, fillAlpha = 0.8 },
	Invalid = { outline = Theme.Color.Bad, outlineAlpha = 0, fill = Theme.Color.Bad, fillAlpha = 0.8 },
	-- "Not yet": a cooldown, not a mistake. Grey rather than red.
	Refused = { outline = Theme.Color.TextFaint, outlineAlpha = 0, fill = WHITE, fillAlpha = 1 },
}

--[[
	Which claim wins when several are live. Tool targets first - they are what
	the next click acts on - and the prompt last, since E works whatever the
	mouse is pointing at.
]]
local SOURCE_ORDER = { "mine", "harvest", "enemy", "place", "interact" }

-- Flash highlights for things that are not the focus. Round-robin; a burst of
-- hits on one enemy reuses the slot already on it.
local FLASH_POOL = 3

-- Impact shells. Round-robin too: rapid mining reuses the same few parts
-- rather than allocating one per block.
local IMPACT_POOL = 6
local IMPACT_ALPHA = 0.55
local IMPACT_GROWTH = 1.45
local IMPACT_SECONDS = 0.2

local PARKED = CFrame.new(0, -10000, 0)

-- ---------------------------------------------------------------------------
-- Instances
-- ---------------------------------------------------------------------------

local container = nil

local function getContainer()
	if container and container.Parent then
		return container
	end

	-- PlayerGui, like the mining outline always was: nothing renders the
	-- Highlights themselves, they only point at their Adornee.
	container = Instance.new("Folder")
	container.Name = "WorldFeedback"
	container.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return container
end

local function newHighlight(name)
	local highlight = Instance.new("Highlight")
	highlight.Name = name
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Enabled = false
	highlight.Parent = getContainer()
	return highlight
end

-- Recreated if something destroyed it (a PlayerGui reset), rather than
-- silently drawing nothing for the rest of the session.
local function alive(highlight)
	return highlight ~= nil and highlight.Parent ~= nil
end

local function inWorld(instance)
	return instance ~= nil and instance:IsDescendantOf(workspace)
end

-- ---------------------------------------------------------------------------
-- Focus
-- ---------------------------------------------------------------------------

local claims = {} -- source -> { adornee, style, progress }

local focus = {
	highlight = nil,
	adornee = nil,
	source = nil,
	style = nil,
	tween = nil,
	-- Whether the running tween writes the fill, which progress() also writes.
	tweenFill = false,
	watch = nil,
	-- Bumped on every change, so a fade-out finishing late cannot switch off
	-- a target that has been claimed since.
	token = 0,
}

local function cancelTween()
	if focus.tween then
		focus.tween:Cancel()
		focus.tween = nil
	end
	focus.tweenFill = false
end

local function play(info, goal)
	cancelTween()
	focus.tween = TweenService:Create(focus.highlight, info, goal)
	focus.tweenFill = goal.FillTransparency ~= nil
	focus.tween:Play()
end

local function fillAlphaFor(style, progress)
	if style.fillPeak and progress and progress > 0 then
		return style.fillAlpha + (style.fillPeak - style.fillAlpha) * math.clamp(progress, 0, 1)
	end
	return style.fillAlpha
end

local function restingGoal(style, progress)
	return {
		OutlineColor = style.outline,
		OutlineTransparency = style.outlineAlpha,
		FillColor = style.fill,
		FillTransparency = fillAlphaFor(style, progress),
	}
end

local recompute -- forward declared; the adornee watcher calls back into it

local function unwatch()
	if focus.watch then
		focus.watch:Disconnect()
		focus.watch = nil
	end
end

local function hideNow()
	focus.token += 1
	cancelTween()
	unwatch()

	if alive(focus.highlight) then
		focus.highlight.Enabled = false
		focus.highlight.Adornee = nil
	end

	focus.adornee, focus.source, focus.style = nil, nil, nil
end

local function fadeOut()
	if not focus.adornee then
		return
	end

	focus.token += 1
	local token = focus.token
	unwatch()
	focus.adornee, focus.source, focus.style = nil, nil, nil

	if not alive(focus.highlight) then
		return
	end

	play(WorldFeedback.Tween.FadeOut, { OutlineTransparency = 1, FillTransparency = 1 })
	focus.tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and focus.token == token then
			focus.highlight.Enabled = false
			focus.highlight.Adornee = nil
		end
	end)
end

local function show(source, claim)
	local style = WorldFeedback.Styles[claim.style]
	if not style then
		return
	end

	if not alive(focus.highlight) then
		focus.highlight = newHighlight("FocusHighlight")
	end
	local highlight = focus.highlight

	local sameTarget = focus.adornee == claim.adornee and highlight.Enabled

	focus.token += 1
	focus.source = source
	focus.style = claim.style

	if sameTarget then
		-- Same thing, new verdict (valid to invalid): blend, do not blink.
		play(WorldFeedback.Tween.Restyle, restingGoal(style, claim.progress))
		return
	end

	unwatch()
	focus.adornee = claim.adornee

	-- Leaving the world clears the outline in the same frame. See the note at
	-- the top: mined, felled, killed, collected and streamed out all land here.
	local adornee = claim.adornee
	focus.watch = adornee.AncestryChanged:Connect(function()
		if not adornee:IsDescendantOf(workspace) then
			for name, other in pairs(claims) do
				if other.adornee == adornee then
					claims[name] = nil
				end
			end
			hideNow()
			recompute()
		end
	end)

	highlight.Adornee = adornee
	highlight.OutlineColor = style.outline
	highlight.FillColor = style.fill
	highlight.OutlineTransparency = 1
	highlight.FillTransparency = 1
	highlight.Enabled = true

	play(WorldFeedback.Tween.FadeIn, restingGoal(style, claim.progress))
end

function recompute()
	for _, source in ipairs(SOURCE_ORDER) do
		local claim = claims[source]
		if claim then
			if inWorld(claim.adornee) then
				if focus.source ~= source or focus.adornee ~= claim.adornee or focus.style ~= claim.style then
					show(source, claim)
				end
				return
			end

			-- Gone since it was claimed, without this module seeing it go.
			claims[source] = nil
		end
	end

	fadeOut()
end

--[[
	Claims the outline for `source`. A nil adornee is the same as release.
	Repeating an identical claim is free; see the note at the top.
]]
function WorldFeedback.focus(source: string, adornee: Instance?, styleName: string)
	if not IS_CLIENT then
		return
	end

	if not adornee then
		WorldFeedback.release(source)
		return
	end

	local claim = claims[source]
	if claim and claim.adornee == adornee and claim.style == styleName then
		return
	end

	if claim then
		if claim.adornee ~= adornee then
			claim.progress = 0
		end
		claim.adornee = adornee
		claim.style = styleName
	else
		claims[source] = { adornee = adornee, style = styleName, progress = 0 }
	end

	recompute()
end

--[[
	Lets go of `source`'s claim. `instant` skips the fade, for a target that
	became invalid rather than one the player merely looked away from.
]]
function WorldFeedback.release(source: string, instant: boolean?)
	if not IS_CLIENT or not claims[source] then
		return
	end

	claims[source] = nil

	if instant and focus.source == source then
		hideNow()
	end

	recompute()
end

--[[
	How far along the work on `source`'s target is, 0..1. Written straight to
	the fill rather than tweened: mining calls it every frame and a Tween per
	frame would cost more than the thing it animates.
]]
function WorldFeedback.progress(source: string, fraction: number)
	local claim = claims[source]
	-- Unchanged is a no-op, so a reset to zero right after a flash (a refused
	-- swing clearing its bar) does not cut that flash short.
	if not claim or claim.progress == fraction then
		return
	end

	claim.progress = fraction

	if focus.source == source and alive(focus.highlight) and focus.highlight.Enabled then
		local style = WorldFeedback.Styles[claim.style]
		if style and style.fillPeak then
			-- A tween still writing the fill (the fade-in) would fight this
			-- write and win, so it is finished early rather than raced. An
			-- edge-only flash leaves the fill alone and is allowed to run.
			if focus.tweenFill then
				cancelTween()
				focus.highlight.OutlineColor = style.outline
				focus.highlight.OutlineTransparency = style.outlineAlpha
			end
			focus.highlight.FillTransparency = fillAlphaFor(style, fraction)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Flash
-- ---------------------------------------------------------------------------

local flashSlots = {}
local nextFlash = 1

local function pulseFocus(style, seconds)
	local claim = claims[focus.source]
	local resting = WorldFeedback.Styles[focus.style]
	if not (claim and resting and alive(focus.highlight)) then
		return
	end

	local highlight = focus.highlight
	highlight.OutlineColor = style.outline
	highlight.OutlineTransparency = style.outlineAlpha

	-- A target showing progress keeps its fill; the flash rides on the edge.
	local keepFill = resting.fillPeak and claim.progress and claim.progress > 0
	if not keepFill then
		highlight.FillColor = style.fill
		highlight.FillTransparency = style.fillAlpha
	end

	local goal = restingGoal(resting, claim.progress)
	if keepFill then
		goal.FillColor = nil
		goal.FillTransparency = nil
	end

	focus.token += 1
	play(TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
end

--[[
	A one-shot emphasis on `adornee`. If it is the focus target, the focus
	outline itself pulses - two Highlights on one object do not stack - and
	otherwise one of a small pool is borrowed.
]]
function WorldFeedback.flash(adornee: Instance?, styleName: string, seconds: number?)
	if not IS_CLIENT or not inWorld(adornee) then
		return
	end

	local style = WorldFeedback.Styles[styleName]
	if not style then
		return
	end

	seconds = seconds or WorldFeedback.FlashSeconds

	if focus.adornee == adornee and focus.highlight and focus.highlight.Enabled then
		pulseFocus(style, seconds)
		return
	end

	local slot = nil
	for _, candidate in ipairs(flashSlots) do
		if candidate.highlight.Adornee == adornee and alive(candidate.highlight) then
			slot = candidate
			break
		end
	end

	if not slot then
		slot = flashSlots[nextFlash]
		if not slot or not alive(slot.highlight) then
			slot = { highlight = newHighlight("FlashHighlight"), token = 0, tween = nil }
			flashSlots[nextFlash] = slot
		end
		nextFlash = nextFlash % FLASH_POOL + 1
	end

	slot.token += 1
	local token = slot.token
	if slot.tween then
		slot.tween:Cancel()
	end

	local highlight = slot.highlight
	highlight.Adornee = adornee
	highlight.OutlineColor = style.outline
	highlight.OutlineTransparency = style.outlineAlpha
	highlight.FillColor = style.fill
	highlight.FillTransparency = style.fillAlpha
	highlight.Enabled = true

	slot.tween = TweenService:Create(
		highlight,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ OutlineTransparency = 1, FillTransparency = 1 }
	)
	slot.tween.Completed:Connect(function(state)
		-- The token, so a slot borrowed again mid-fade is not switched off by
		-- the old fade finishing.
		if state == Enum.PlaybackState.Completed and slot.token == token then
			highlight.Enabled = false
			highlight.Adornee = nil
		end
	end)
	slot.tween:Play()
end

-- ---------------------------------------------------------------------------
-- Impact
-- ---------------------------------------------------------------------------

local impactParts = {}
local nextImpact = 1

local function impactPart(index)
	local entry = impactParts[index]
	if entry and entry.part.Parent then
		return entry
	end

	local part = Instance.new("Part")
	part.Name = "Impact"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.CFrame = PARKED
	part.Parent = workspace

	entry = { part = part, token = 0, tween = nil }
	impactParts[index] = entry
	return entry
end

--[[
	A shell of light that swells and fades: "that one went". `size` is the
	starting diameter in studs; `shape` is "Ball" (default) or "Block", the
	latter for a terrain cube so the flash reads as the block itself bursting.

	Pooled and token-guarded, so mining a row of blocks as fast as the server
	allows recycles the same handful of parts.
]]
function WorldFeedback.impact(position: Vector3, color: Color3?, size: number?, shape: string?, alpha: number?)
	if not IS_CLIENT or typeof(position) ~= "Vector3" then
		return
	end

	size = size or 3

	local entry = impactPart(nextImpact)
	nextImpact = nextImpact % IMPACT_POOL + 1

	entry.token += 1
	local token = entry.token
	if entry.tween then
		entry.tween:Cancel()
	end

	local part = entry.part
	part.Shape = if shape == "Block" then Enum.PartType.Block else Enum.PartType.Ball
	part.Color = color or WHITE
	part.Size = Vector3.one * size
	part.CFrame = CFrame.new(position)
	part.Transparency = alpha or IMPACT_ALPHA

	entry.tween = TweenService:Create(
		part,
		TweenInfo.new(IMPACT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * (size * IMPACT_GROWTH), Transparency = 1 }
	)
	entry.tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and entry.token == token then
			part.CFrame = PARKED
		end
	end)
	entry.tween:Play()
end

return WorldFeedback
