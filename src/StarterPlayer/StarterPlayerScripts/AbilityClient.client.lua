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
local MenuBackdrop = require(Shared.UI:WaitForChild("MenuBackdrop"))
local AbilityPanel = require(Shared.UI:WaitForChild("AbilityPanel"))

local AbilitiesShared = Shared:WaitForChild("Abilities")
local AbilityConfig = require(AbilitiesShared:WaitForChild("AbilityConfig"))
local AbilityScope = require(AbilitiesShared:WaitForChild("AbilityScope"))
local VFXFolder = AbilitiesShared:WaitForChild("VFX")

local RequestAbility = Remotes.wait("RequestAbility")
local AbilityEffect = Remotes.wait("AbilityEffect")
local LoadoutChanged = Remotes.wait("AbilityLoadoutChanged")
local RequestReorder = Remotes.wait("RequestAbilityReorder")
local RequestDrop = Remotes.wait("RequestAbilityDrop")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

--[[
	How many casts may be drawn at once on this machine.

	Not a game rule - a frame-rate one. Fifteen swords carrying eighty-seven
	emitters each is a lot to have on screen; three of those overlapping is
	already more than anyone can read, and a full server of players casting into
	the same place should not be able to stall a client.
]]
local MAX_CONCURRENT_EFFECTS = 3

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

local HUD = {
	width = 190,
	rowHeight = 24,
	gap = 4,
	pad = 10,
	-- Clear of the mana bar, which sits at 141 and is 33 tall. That in turn
	-- sits on the health bar at 96. See ManaClient for the whole column.
	bottom = 176,
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
hudRoot.Position = UDim2.new(0, HUD.pad + 6, 1, -HUD.bottom)
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
			row.BackgroundColor3 = Theme.Color.Panel
			row.BackgroundTransparency = 0.2
			row.BorderSizePixel = 0
			row.Parent = hudRoot

			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.Color.Stroke
			stroke.Thickness = 1
			stroke.Parent = row

			-- The bar drains left to right underneath the text, so the readout
			-- is legible at a glance without anyone having to read the number.
			local fill = Instance.new("Frame")
			fill.Name = "Fill"
			fill.Size = UDim2.fromScale(0, 1)
			fill.BackgroundColor3 = Theme.Color.Accent
			fill.BackgroundTransparency = 0.75
			fill.BorderSizePixel = 0
			fill.ZIndex = row.ZIndex
			fill.Parent = row

			local key = Instance.new("TextLabel")
			key.Name = "Key"
			key.Size = UDim2.fromOffset(34, HUD.rowHeight)
			key.BackgroundTransparency = 1
			key.FontFace = Theme.Fonts.Number
			key.TextSize = Theme.TextSize.Small
			key.TextColor3 = Theme.Color.Accent
			key.Text = slotKeyLabel(index)
			key.ZIndex = row.ZIndex + 1
			key.Parent = row

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Position = UDim2.fromOffset(38, 0)
			label.Size = UDim2.new(1, -44, 1, 0)
			label.BackgroundTransparency = 1
			label.FontFace = Theme.Fonts.BodyBold
			label.TextSize = Theme.TextSize.Small
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = Theme.Color.Text
			label.Text = definition.displayName or abilityName
			label.ZIndex = row.ZIndex + 1
			label.Parent = row

			hudRows[abilityName] = {
				row = row,
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
	hudGui.Enabled = count > 0
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
			-- Ready again: the row lights up and bumps once, on the frame it
			-- comes off cooldown, so the moment is noticed without being watched.
			if row.cooling then
				row.cooling = false
				Motion.flash(row.row, Theme.Color.Accent, "BackgroundColor3")
				Motion.pulse(row.row, 1.06)
			end

			row.fill.Size = UDim2.fromScale(0, 1)
			row.label.Text = row.name
			row.label.TextColor3 = Theme.Color.Text
		else
			row.cooling = true
			local remaining = cooldown - since
			row.fill.Size = UDim2.fromScale(remaining / cooldown, 1)
			row.label.Text = string.format("%s  %.1fs", row.name, remaining)
			row.label.TextColor3 = Theme.Color.TextDim
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

	local target = if definition.requiresTarget then mouse.Hit.Position else nil
	log("requesting", abilityName)
	RequestAbility:FireServer(abilityName, target)
end

--[[
	What was gained since the last push, if it was exactly one thing.

	Worked out by comparing, rather than by the server saying so, because then
	every way of granting an ability announces itself - the chat command today,
	whatever earns them later - without any of them having to remember to.

	nil for the first push, which has nothing to compare against; nil for a
	removal; and nil when several arrive at once.

	nil for a "restore" too: the saved loadout arriving on join. It lands after
	an empty push sent while the save was still loading, so a save holding one
	ability looked exactly like picking one up - and opened the Tab menu with
	its flourish every time you joined.
]]
local function newlyGained(abilities: { string }, reason: string?): string?
	if not previousLoadout or reason == "restore" then
		return nil
	end

	local gained = nil

	for _, name in ipairs(abilities) do
		if not table.find(previousLoadout, name) then
			if gained then
				return nil
			end
			gained = name
		end
	end

	return gained
end

--[[
	The Tab menu's list: a line in capitals naming the slot and its key, the
	ability's name under it, and its rarity under that. The reference's own
	layout.

	EVERY slot, not every ability. The empty ones are listed too, because this
	is the screen the loadout is arranged on and a slot you cannot see is a slot
	you do not know you have - which is the opposite of the HUD readout, where
	an empty row would be a permanent widget saying nothing.

	The rarity travels as the TIER NAME and not as a colour. The panel prints the
	word and the backdrop tints the solid with it, and Theme is the one place
	allowed to say which colour a tier is.
]]
local function panelSlots(abilities: { string }, gained: string?)
	local entries = {}

	for slot = 1, AbilityConfig.SlotCount do
		local abilityName = abilities[slot]
		local definition = abilityName and AbilityConfig.get(abilityName)

		entries[slot] = {
			label = string.format("slot %d  ~  %s", slot, slotKeyLabel(slot)),

			-- The raw name for an ability this client has no definition for,
			-- which is a server newer than the client rather than nothing at
			-- all; nil only for a slot that is genuinely empty.
			name = if definition then definition.displayName or abilityName else abilityName,
			rarity = definition and definition.rarity or nil,
			gained = abilityName ~= nil and abilityName == gained,
		}
	end

	return entries
end

--[[
	Redraws the menu's list, and sets the backdrop off if this was a gain.

	Called on EVERY push, including the ones nobody did on purpose - a reorder,
	a removal, the restore on join - because the list has to match the keys
	whatever moved them. Only a gain flourishes, and a reorder is not one, so
	dragging a card rearranges the stack without the solid detonating each time.
]]
local function refreshPanel(abilities: { string }, gained: string?)
	if gained then
		--[[
			OPENED BEFORE ANYTHING IS DRAWN INTO IT.

			The flourish refuses to play to a hidden backdrop, and the menu is
			shut for the one way of gaining an ability that matters - reading a
			scroll, which happens out in the world. So the menu is asked for
			first and the two calls below then land on a screen that exists.

			It has to be this order and not a task.defer: PauseMenu.openMenu
			makes the backdrop visible synchronously, so by the time this
			returns there is something to flourish.

			A no-op when the menu is already up, which is the /add case - chat
			is only visible with it open.
		]]
		MenuState.requestOpen("PauseMenu")
	end

	AbilityPanel.setSlots(panelSlots(abilities, gained))

	if gained then
		local definition = AbilityConfig.get(gained)
		MenuBackdrop.flourish(definition and definition.rarity or nil)
	end
end

--[[
	What the Tab menu's drags mean.

	Sent, not applied: the loadout is the server's, and it answers every one of
	these with a push whether it accepted it or not. The panel has already moved
	or removed the card and is waiting to be told what really happened.
]]
AbilityPanel.setHandlers({
	reorder = function(from: number, to: number)
		log("requesting reorder", from, "->", to)
		RequestReorder:FireServer(from, to)
	end,

	drop = function(slot: number)
		log("requesting drop of slot", slot)
		RequestDrop:FireServer(slot)
	end,
})

LoadoutChanged.OnClientEvent:Connect(function(abilities, reason)
	if type(abilities) ~= "table" then
		return
	end

	local gained = newlyGained(abilities, reason)

	previousLoadout = abilities
	loadout = abilities
	rebuildHud(loadout)
	preload(loadout)
	refreshPanel(loadout, gained)

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
