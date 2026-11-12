--[[
	AbilityClient

	The client half of the weapon ability system: it watches what the player is
	holding, turns input into a request, and draws whatever the server says
	happened.

	IT DECIDES NOTHING. Pressing a slot key sends the ability's name and where
	the mouse points, and that is the whole of the client's involvement. The
	local cooldown is politeness - it stops the client shouting at a server that
	will refuse anyway; AbilityService holds the real one, and the LOADOUT that
	says which three abilities exist for this player at all is the server's too.

	Drawing is driven by the server's broadcast, not by the keypress, so the
	effect a player sees for their own cast is the same message everyone else
	got and a refused cast is visibly refused rather than played and then
	contradicted.

	Nothing here names an ability: the loadout arrives over a remote and the VFX
	module named in AbilityConfig is loaded on demand. Effects are capped, and
	each runs inside a scope destroyed when its duration is up, so a buggy VFX
	module can leak neither instances nor threads.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local MenuState = require(Shared:WaitForChild("UI"):WaitForChild("MenuState"))
local Theme = require(Shared.UI:WaitForChild("Theme"))
local Motion = require(Shared.UI:WaitForChild("Motion"))
local PixelUI = require(Shared.UI:WaitForChild("PixelUI"))
local MenuBackdrop = require(Shared.UI:WaitForChild("MenuBackdrop"))
local AbilityPanel = require(Shared.UI:WaitForChild("AbilityPanel"))
local AbilityStorage = require(Shared.UI:WaitForChild("AbilityStorage"))
local Responsive = require(Shared.UI:WaitForChild("Responsive"))
local Pointer = require(Shared.UI:WaitForChild("Pointer"))
local TouchActions = require(Shared.UI:WaitForChild("TouchActions"))

local AbilitiesShared = Shared:WaitForChild("Abilities")
local AbilityConfig = require(AbilitiesShared:WaitForChild("AbilityConfig"))
local AspectConfig = require(AbilitiesShared:WaitForChild("AspectConfig"))
local AbilityScope = require(AbilitiesShared:WaitForChild("AbilityScope"))
local VFXFolder = AbilitiesShared:WaitForChild("VFX")
local LoadingGate = require(Shared:WaitForChild("Loading"):WaitForChild("LoadingGate"))

local RequestAbility = Remotes.wait("RequestAbility")
local AbilityEffect = Remotes.wait("AbilityEffect")
local LoadoutChanged = Remotes.wait("AbilityLoadoutChanged")

local player = Players.LocalPlayer

--[[
	How many casts may be drawn at once on this machine.

	Not a game rule - a frame-rate one. Fifteen swords carrying eighty-seven
	emitters each is a lot to have on screen; three of those overlapping is
	already more than anyone can read, and a full server of players casting into
	the same place should not be able to stall a client.
]]
local MAX_CONCURRENT_EFFECTS = 12

-- Fallback teardown for a VFX module that does not say how long it runs.
local DEFAULT_EFFECT_DURATION = 15

local DEBUG = false
local function log(...)
	if DEBUG then
		print("[AbilityClient]", ...)
	end
end

-- ---------------------------------------------------------------------------
-- VFX modules
-- ---------------------------------------------------------------------------

local vfxModules: { [string]: any } = {}

local function vfxFor(definition)
	local name = definition.vfx
	if type(name) ~= "string" then
		return nil
	end

	local cached = vfxModules[name]
	if cached ~= nil then
		return cached or nil
	end

	local moduleScript = VFXFolder:FindFirstChild(name)
	if not (moduleScript and moduleScript:IsA("ModuleScript")) then
		warn(string.format("[AbilityClient] no VFX module '%s' in Shared.Abilities.VFX", name))
		vfxModules[name] = false
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if not ok or type(result) ~= "table" or type(result.play) ~= "function" then
		--[[
			"Requested module experienced an error while loading" is all pcall
			gives back - Roblox keeps the real message for itself and prints it
			as its own line, immediately ABOVE this one, naming the module and
			the line that actually threw. Said out loud because a warning that
			looks like the whole story is worse than one that admits it is not.
		]]
		warn(string.format(
			"[AbilityClient] '%s' did not load as a VFX module (needs a `play` function): %s "
				.. "- the real error is the line above this one.",
			name, tostring(result)
		))
		vfxModules[name] = false
		return nil
	end

	vfxModules[name] = result
	return result
end

-- ---------------------------------------------------------------------------
-- The cooldown readout
-- ---------------------------------------------------------------------------
--
-- One row per filled slot, showing the key that casts it and how long until it
-- can be used again.
--
-- ONLY WHEN SOMETHING IS CARRIED. An empty loadout shows nothing at all rather
-- than three empty rows - a permanent widget reading "no ability" is worse than
-- no widget, because it takes up the same room and says less.
--
-- THE CLOCK IS THE SERVER'S, NOT THE KEYPRESS'S
--   Timing starts when the server CONFIRMS a cast, which is when AbilityEffect
--   arrives naming this player as the caster. Starting it on the keypress would
--   show a cooldown for a cast that was refused, which is the one moment a
--   player most needs to be told the truth.
--
-- DRAWN LIKE THE HEALTH AND MANA BARS
--   Each row is the pixel kit's wooden bar, with the key that casts it on a
--   parchment keycap over the left end where those bars have their icons. The
--   groove CHARGES: it fills in dim gold while the ability cools down and is
--   full, bright gold, when it is ready - so a usable ability is the brightest
--   thing in the column.

local HUD = {
	width = 230,
	-- The bar frame's art with a 4-texel groove, as the mana bar.
	rowHeight = 33,
	gap = 4,
	pad = 16,
	-- Clear of the mana bar, which sits at 85 and is 33 tall. That in turn sits
	-- on the health bar at 40. See ManaClient for the whole column.
	bottom = 126,
	-- As the health and mana bars: the frame starts under the keycap, and the
	-- fill starts clear of it.
	iconInset = 15,
	iconClear = 10,
}

local HUD_COLOR = {
	charging = Color3.fromRGB(196, 168, 112),
	ready = Theme.PixelColor.Selection,
}

local hudGui = Instance.new("ScreenGui")
hudGui.Name = "AbilityUI"
hudGui.ResetOnSpawn = false
hudGui.IgnoreGuiInset = true
hudGui.DisplayOrder = 5
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.Enabled = false
hudGui.Parent = player:WaitForChild("PlayerGui")

local hudRoot = Instance.new("Frame")
hudRoot.Name = "Abilities"
hudRoot.AnchorPoint = Vector2.new(0, 1)
hudRoot.Position = UDim2.new(0, HUD.pad, 1, -HUD.bottom)
hudRoot.Size = UDim2.fromOffset(HUD.width, HUD.rowHeight)
hudRoot.BackgroundTransparency = 1
hudRoot.Parent = hudGui

local hudLayout = Instance.new("UIListLayout")
hudLayout.FillDirection = Enum.FillDirection.Vertical
hudLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
hudLayout.SortOrder = Enum.SortOrder.LayoutOrder
hudLayout.Padding = UDim.new(0, HUD.gap)
hudLayout.Parent = hudRoot

-- abilityName -> { row, fill, label, definition }
local hudRows: { [string]: any } = {}

-- abilityName -> os.clock() when the server last confirmed a cast.
local castAt: { [string]: number } = {}

-- How a slot's key reads on screen. A KeyCode's Name is already the letter for
-- anything a player would bind.
local function slotKeyLabel(slot: number): string
	local key = AbilityConfig.keyForSlot(slot)
	return if key then key.Name else "-"
end

local function clearHudRows()
	for _, row in pairs(hudRows) do
		row.row:Destroy()
	end
	table.clear(hudRows)
end

--[[
	Rebuilds the panel from the loadout. Called whenever the server says it
	changed, which is rare enough that rebuilding beats diffing.
]]
local function rebuildHud(abilities: { string }?)
	clearHudRows()

	if not abilities or #abilities == 0 then
		hudGui.Enabled = false
		return
	end

	local count = 0

	for index, abilityName in ipairs(abilities) do
		local definition = AbilityConfig.get(abilityName)
		if definition then
			count += 1

			local row = Instance.new("Frame")
			row.Name = abilityName
			row.LayoutOrder = index
			row.Size = UDim2.new(1, 0, 0, HUD.rowHeight)
			row.BackgroundTransparency = 1
			row.Parent = hudRoot

			-- The key that casts it, on a parchment keycap over the bar's end.
			local keycap = Instance.new("ImageLabel")
			keycap.Name = "Keycap"
			keycap.BackgroundTransparency = 1
			keycap.Size = UDim2.fromOffset(HUD.rowHeight, HUD.rowHeight)
			keycap.ZIndex = 5
			keycap.Parent = row
			PixelUI.apply(keycap, "slot")

			local key = Instance.new("TextLabel")
			key.Name = "Key"
			key.Size = UDim2.fromScale(1, 1)
			key.BackgroundTransparency = 1
			key.FontFace = Theme.Fonts.Number
			key.TextSize = Theme.TextSize.Body
			key.TextColor3 = Theme.PixelColor.Ink
			key.Text = slotKeyLabel(index)
			key.Parent = keycap

			local frame = PixelUI.image(row, "bar_frame")
			frame.Name = "Frame"
			frame.Position = UDim2.fromOffset(HUD.iconInset, 0)
			frame.Size = UDim2.new(1, -HUD.iconInset, 1, 0)

			local grooveLeft, grooveTop, grooveRight, grooveBottom = PixelUI.groove("bar_frame")
			local fillLeft = HUD.iconInset + grooveLeft + HUD.iconClear

			local groove = Instance.new("Frame")
			groove.Name = "Groove"
			groove.BackgroundTransparency = 1
			groove.ClipsDescendants = true
			groove.Position = UDim2.fromOffset(fillLeft, grooveTop)
			groove.Size = UDim2.new(1, -(fillLeft + grooveRight), 1, -(grooveTop + grooveBottom))
			groove.ZIndex = 2
			groove.Parent = row

			-- Charges left to right underneath the text, so the readout is
			-- legible at a glance without anyone having to read the number.
			local fill = PixelUI.image(groove, "bar_fill")
			fill.Name = "Fill"
			fill.Size = UDim2.fromScale(1, 1)
			fill.ImageColor3 = HUD_COLOR.ready

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Position = groove.Position
			label.Size = groove.Size
			label.BackgroundTransparency = 1
			label.FontFace = Theme.Fonts.BodyBold
			label.TextSize = Theme.TextSize.Small
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = Theme.PixelColor.OnWood
			label.TextStrokeColor3 = Theme.PixelColor.Outline
			label.TextStrokeTransparency = 0
			label.Text = definition.displayName or abilityName
			label.ZIndex = 4
			label.Parent = row

			hudRows[abilityName] = {
				row = row,
				frame = frame,
				keycap = keycap,
				fill = fill,
				label = label,
				definition = definition,
				name = definition.displayName or abilityName,
			}
		end
	end

	hudRoot.Size = UDim2.fromOffset(
		HUD.width, count * HUD.rowHeight + math.max(0, count - 1) * HUD.gap
	)
	-- On a touch screen the ability buttons (TouchControls) carry the same
	-- readout, and these rows would sit where the thumbstick is.
	hudGui.Enabled = count > 0 and not Responsive.isTouch() and not MenuState.isOpen("PauseMenu")
end

--[[
	Ticks every visible row. Cheap enough to run per frame - it is at most a
	couple of rows - and driven off Heartbeat rather than a timer so the bar
	drains smoothly instead of stepping.
]]
local function updateHud()
	if not hudGui.Enabled then
		return
	end

	local now = os.clock()

	for abilityName, row in pairs(hudRows) do
		local cooldown = if player:GetAttribute("GodMode") then 0 else (row.definition.cooldown or 0)
		local since = now - (castAt[abilityName] or -math.huge)

		if cooldown <= 0 or since >= cooldown then
			-- Ready again: the frame flushes gold and the row bumps once, on the
			-- frame it comes off cooldown, so the moment is noticed without being
			-- watched.
			if row.cooling then
				row.cooling = false
				Motion.flash(row.frame, HUD_COLOR.ready, "ImageColor3")
				Motion.pulse(row.row, 1.06)
			end

			row.fill.Size = UDim2.fromScale(1, 1)
			row.fill.ImageColor3 = HUD_COLOR.ready
			row.keycap.ImageColor3 = Color3.new(1, 1, 1)
			row.label.Text = row.name
			row.label.TextColor3 = Theme.PixelColor.OnWood
		else
			row.cooling = true
			local remaining = cooldown - since
			row.fill.Size = UDim2.fromScale(1 - remaining / cooldown, 1)
			row.fill.ImageColor3 = HUD_COLOR.charging
			row.keycap.ImageColor3 = Theme.PixelColor.Disabled
			row.label.Text = string.format("%s  %.1fs", row.name, remaining)
			row.label.TextColor3 = Theme.PixelColor.OnWoodDim
		end
	end
end

RunService.Heartbeat:Connect(updateHud)

-- ---------------------------------------------------------------------------
-- The loadout
-- ---------------------------------------------------------------------------

--[[
	What this player is carrying, straight from the server.

	The client never decides this and never edits it - it is pushed by
	AbilityLoadout whenever it changes, and the panel and the keys are both
	drawn from whatever last arrived. So the readout cannot claim an ability the
	server would refuse, and slot 2 casts what slot 2 shows.
]]
local loadout: { string } = {}

-- The one before it, kept only to work out what changed. nil until the first
-- push arrives, which is what stops a join being announced as a gain.
local previousLoadout: { string }? = nil

-- The active aspect (AspectConfig name), or nil. The slots are its abilities.
local aspect: string? = nil

--[[
	Preloaded on a loadout change rather than on equip, because there is no
	equip any more.

	Built with AbilityConfig.DefaultCastWeapon, which is what the server picks
	for a caster holding nothing - and today also what it picks for a caster
	holding the only authored weapon. Anything else is built on first use by
	the VFX module itself, at the cost of one hitch.
]]
local function preload(abilities: { string })
	for _, abilityName in ipairs(abilities) do
		local definition = AbilityConfig.get(abilityName)
		if definition then
			local vfx = vfxFor(definition)
			if vfx and type(vfx.preload) == "function" then
				task.spawn(vfx.preload, AbilityConfig.DefaultCastWeapon)
			end
		end
	end
end

-- ability -> os.clock() of the last request, for the local cooldown.
local requestedAt: { [string]: number } = {}

local function cast(abilityName: string, definition)
	if MenuState.isAnyOpen() then
		return
	end

	local now = os.clock()
	local last = requestedAt[abilityName]
	if not player:GetAttribute("GodMode") and last and now - last < (definition.cooldown or 0) then
		-- Pressed too soon: the row says "not yet" in red rather than the key
		-- simply doing nothing.
		local row = hudRows[abilityName]
		if row then
			Motion.flash(row.row, Theme.Color.Bad, "BackgroundColor3")
		end
		return
	end
	requestedAt[abilityName] = if player:GetAttribute("GodMode") then nil else now

	-- The mouse on a computer; on a touch screen the enemy nearest the middle
	-- of the view, since a finger cannot hover. See Shared.UI.Pointer.
	local target = if definition.requiresTarget then Pointer.aim() else nil
	log("requesting", abilityName)
	RequestAbility:FireServer(abilityName, target)
end

--[[
	The aspect that just became active, if one did: a scroll, the tutorial or
	using one from the inventory.

	nil for the first push, which has nothing to compare against; for a
	"restore" (the saved aspect arriving on join, after an empty push sent
	while the save was loading); for a "wish" (the banner's reveal is the
	celebration, see WishClient); and when the aspect was cleared.
]]
local function newlyActive(newAspect: string?, reason: string?): string?
	if not previousLoadout or reason == "restore" or reason == "wish" then
		return nil
	end
	if newAspect ~= nil and newAspect ~= aspect then
		return newAspect
	end
	return nil
end

--[[
	The Tab menu: the aspect in use on its card, and its tier as the colour of
	the menu's wireframe solid. A newly active aspect also opens the menu and
	throws the solid outward in its colour.

	The tier travels as a NAME ("Legendary"), not a colour: Theme is the one
	place allowed to say which colour a tier is.
]]
local function refreshPanel(gainedAspect: string?)
	if gainedAspect then
		--[[
			OPENED BEFORE ANYTHING IS DRAWN INTO IT. The flourish refuses to play
			to a hidden backdrop, and a scroll is read out in the world with the
			menu shut. PauseMenu makes the backdrop visible synchronously, so by
			the time this returns there is something to flourish. A no-op when
			the menu is already up.
		]]
		MenuState.requestOpen("PauseMenu")
	end

	local definition = AspectConfig.get(aspect)
	AbilityPanel.setAspect(if definition then {
		name = aspect,
		displayName = definition.displayName or aspect,
		rarity = definition.rarity,
		abilityCount = #AspectConfig.abilitiesOf(aspect),
		permanent = AbilityStorage.isPermanent(aspect),
	} else nil)
	MenuBackdrop.setRestTint(definition and definition.rarity or nil)

	if gainedAspect and definition then
		MenuBackdrop.flourish(definition.rarity)
	end
end

-- Buying a permanent aspect changes how the one in use is labelled.
AbilityStorage.Changed:Connect(function()
	refreshPanel(nil)
end)

LoadoutChanged.OnClientEvent:Connect(function(abilities, reason, newAspect)
	if type(abilities) ~= "table" then
		return
	end
	newAspect = if type(newAspect) == "string" then newAspect else nil

	local gainedAspect = newlyActive(newAspect, reason)

	previousLoadout = abilities
	loadout = abilities
	aspect = newAspect
	-- Read by the inventory page to say which aspect a use would replace.
	player:SetAttribute("Aspect", newAspect)
	-- Local only: lets a VFX module find the key that casts its ability.
	player:SetAttribute("AbilityLoadout", table.concat(abilities, ","))
	rebuildHud(loadout)
	-- The loading screen fetches the equipped abilities' art itself, within
	-- its budget; the modules' own (whole-library) preloads wait for it.
	LoadingGate.defer(preload, loadout)
	refreshPanel(gainedAspect)

	log("loadout is now", #loadout, "abilit(ies)")
end)

--[[
	Slot keys.

	One connection for the whole script rather than one per slot: the keyboard
	is global, and the slot a key answers to is a lookup rather than a binding,
	so nothing has to be rebound when the loadout changes.
]]
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or MenuState.isAnyOpen() then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	for slot, key in ipairs(AbilityConfig.SlotKeys) do
		if key == input.KeyCode then
			local abilityName = loadout[slot]
			local definition = abilityName and AbilityConfig.get(abilityName)
			if definition then
				cast(abilityName, definition)
			end
			return
		end
	end
end)

-- The touch screen's ability buttons: the same cast as the slot's key.
TouchActions.castRequested:Connect(function(slot)
	local abilityName = loadout[slot]
	local definition = abilityName and AbilityConfig.get(abilityName)
	if definition then
		cast(abilityName, definition)
	end
end)

--[[
	What those buttons draw: each slot's name and cooldown, from the same
	server-confirmed clock as the rows above.
]]
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for slot = 1, AbilityConfig.SlotCount do
		local abilityName = loadout[slot]
		local definition = abilityName and AbilityConfig.get(abilityName)
		if definition then
			local cooldown = if player:GetAttribute("GodMode") then 0 else (definition.cooldown or 0)
			local since = now - (castAt[abilityName] or -math.huge)
			TouchActions.setSlot(slot, {
				name = definition.displayName or abilityName,
				cooldown = cooldown,
				remaining = math.max(0, cooldown - since),
			})
		else
			TouchActions.setSlot(slot, nil)
		end
	end
end)

-- Off on a touch screen, and under the Tab menu, which lists the same
-- abilities over the spot these rows sit in.
local function showHudRows()
	hudGui.Enabled = next(hudRows) ~= nil and not Responsive.isTouch() and not MenuState.isOpen("PauseMenu")
end
Responsive.Changed:Connect(showHudRows)
MenuState.Changed:Connect(showHudRows)

-- ---------------------------------------------------------------------------
-- Drawing what the server says happened
-- ---------------------------------------------------------------------------

local activeEffects = 0

--[[
	character -> ability name -> AnimationTrack.

	Loading an Animation is a round trip to the asset; an ability that can fire
	every second must not pay it every time. Weak-keyed on the character so a
	respawn drops the whole set rather than leaving tracks bound to a body that
	no longer exists.
]]
local animationTracks = setmetatable({}, { __mode = "k" })

--[[
	Plays an ability's animation on whoever cast it.

	Driven by the broadcast rather than by the keypress, so a cast the server
	refused does not animate, and so everyone sees it rather than only the
	caster. Silently does nothing for an ability with no animation configured,
	which is all of them until one is given an id.
]]
local function playAnimation(abilityName: string, definition, caster: Player?)
	local id = definition.animation
	if type(id) ~= "string" or id == "" or not caster then
		return
	end

	local character = caster.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not (character and animator) then
		return
	end

	local perCharacter = animationTracks[character]
	if not perCharacter then
		perCharacter = {}
		animationTracks[character] = perCharacter
	end

	local track = perCharacter[abilityName]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = id

		local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
		animation:Destroy()

		if not ok or not loaded then
			warn(string.format("[AbilityClient] could not load animation for %s", abilityName))
			return
		end

		track = loaded
		perCharacter[abilityName] = track
	end

	track:Play()
end

AbilityEffect.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	local definition = AbilityConfig.get(payload.ability)
	if not definition then
		return
	end

	-- The server accepted a cast of ours, so this is the moment its cooldown
	-- actually started. A refused cast never gets here and never shows one.
	if payload.caster == player then
		castAt[payload.ability] = if player:GetAttribute("GodMode") then nil else os.clock()
	end

	-- Before the effect budget check: the caster's animation is one track, it
	-- costs nothing, and dropping it would make a busy fight look like the
	-- ability was never used.
	playAnimation(payload.ability, definition, payload.caster)

	if activeEffects >= MAX_CONCURRENT_EFFECTS then
		log("dropping", payload.ability, "- already drawing", activeEffects)
		return
	end

	local vfx = vfxFor(definition)
	if not vfx then
		return
	end

	local scope = AbilityScope.new()
	activeEffects += 1

	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		activeEffects -= 1
		scope:destroy()
	end

	local ok, started = pcall(vfx.play, payload, scope)
	if not ok then
		warn(string.format("[AbilityClient] %s VFX errored: %s", tostring(payload.ability), tostring(started)))
		finish()
		return
	end

	if not started then
		finish()
		return
	end

	local duration = DEFAULT_EFFECT_DURATION
	if type(vfx.duration) == "function" then
		local okDuration, value = pcall(vfx.duration)
		if okDuration and type(value) == "number" then
			duration = value
		end
	end

	-- The backstop. The VFX module schedules its own cleanup through the scope;
	-- this guarantees the scope itself dies even if it did not.
	task.delay(duration + 1, finish)
end)

-- What the chat commands say back is StarterPlayerScripts.CommandFeedback,
-- shared with every other command in the game. It sits above this panel and
-- stays visible while this one is hidden, which is when the first /add lands.
