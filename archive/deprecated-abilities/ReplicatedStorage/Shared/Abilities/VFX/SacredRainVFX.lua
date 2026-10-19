--[[
	SacredRainVFX

	Draws one Sacred Rain cast, on the client, following the reference's own
	timeline beat for beat.

		SacredRainVFX.play(payload, scope)

	`payload` is what AbilityService broadcast: a seed, the caster's root CFrame
	and the target point. Every position is re-derived from those through
	SacredRainPlan, so this module never learns anything the server did not
	already decide, and the swords land exactly where the damage did.

	WHAT IT DOES, IN THE REFERENCE'S ORDER

	  t+0.0   portal opens on the flight line, Main emitters on, everything emits
	  t+0.5   portal bursts (Explode), portal sound at 0.8-1.2 pitch
	          the weapon appears in the portal, already aimed
	  t+1.5   weapon launches: 0.4s Position tween, Back / In
	  t+1.9   impact - fade out, emitters off, Explode burst, impact sound,
	          a hit flash on anything caught in the 20-stud box
	  ...     repeated fifteen times, on the rhythm in SacredRainPlan
	  t+7.5   everything is back in the pool

	WHAT IS DIFFERENT FROM THE REFERENCE, AND WHY

	  It runs on the client. The reference builds all of this on the server,
	  where every part and every one of its ninety-odd emitters replicates to
	  every player in the game. Here the server broadcasts a seed and each
	  client near enough to see it draws its own copy.

	  Assemblies are pooled rather than created and destroyed - see FXBuilder.

	  The last blade is its own rig: bigger, black, and dropped straight down
	  the vertical onto the mark rather than in off the barrage's diagonal. The
	  reference has no finale at all - see SacredRainPlan.Tuning.Rhythm for why
	  this one does, and FinaleScale / FinaleColor / FinaleStartHeight for the
	  numbers.

	  There is no damage here. The box query at impact exists only to decide
	  where to put a hit flash; the server ran its own, and that one is the one
	  that hurt.

	WHAT THE REFERENCE DOES THAT LOOKS LIKE A BUG, AND IS REPRODUCED ANYWAY

	  The "fade in" tweens the sword's Transparency to 0 while it is already 0,
	  so it is a one-second pause with nothing to see. Kept, because that is
	  what the reference looks like; SacredRainPlan.Tuning.FadeSwordIn turns it
	  into a real fade if you would rather have one.

	NO GROUND EFFECT

	  The reference puts an 80-stud marker on the ground under the barrage for
	  its whole length. It is not drawn here: it is gone by request, and with it
	  the marker's own hold / fade / cleanup timings. The data for it is still
	  in SacredRainData under "Marker", because that file is a verbatim
	  extraction and regenerating it would bring the marker back regardless -
	  nothing acquires it any more.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))

local Abilities = script.Parent.Parent
local SacredRainPlan = require(Abilities:WaitForChild("SacredRainPlan"))
local FXBuilder = require(script.Parent:WaitForChild("FXBuilder"))

local Tuning = SacredRainPlan.Tuning

local SacredRainVFX = {}

local FADE_IN = TweenInfo.new(Tuning.SwordFadeInTime, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
local FADE_OUT = TweenInfo.new(Tuning.SwordFadeOutTime, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
local TRAVEL = TweenInfo.new(Tuning.TravelTime, Enum.EasingStyle.Back, Enum.EasingDirection.In)

-- Debris:AddItem(HitFX, 3) in the reference.
local HIT_FX_LIFETIME = 3

--[[
	Where the effect's instances live.

	A folder rather than the workspace root so that everything a cast makes can
	be found, counted and - if something ever does leak - swept, without walking
	the whole world.
]]
local function effectsFolder(): Folder
	local existing = workspace:FindFirstChild("AbilityEffects")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "AbilityEffects"
	folder.Parent = workspace
	return folder
end

--[[
	Returns a release function that can be called any number of times and only
	does anything once.

	Assemblies are pooled, so releasing one twice would put the same instance in
	the pool twice and hand it to two strikes at once. Every path that can end a
	strike - the timeout, the impact, the scope being torn down - goes through
	one of these.
]]
local function releaser(key: string, instance: Instance)
	local done = false
	return function()
		if done then
			return
		end
		done = true
		FXBuilder.release(key, instance)
	end
end

--[[
	The pool key for a weapon rig. One per item, because the rig is built around
	that item's own model.
]]
local function weaponKey(itemName: string): string
	return "Weapon:" .. itemName
end

--[[
	The finale's blade is a second rig off the same model - bigger, and painted
	black - so it gets its own key and its own pool.

	A separate template rather than one rig resized on the way out: the flying
	weapon is a welded assembly, and a WeldConstraint holds the pose it was
	created with, so scaling a pooled one would mean unwelding and rewelding it
	fifteen times a cast. It is built once instead, at equip.
]]
local function finaleWeaponKey(itemName: string): string
	return "Weapon:" .. itemName .. ":Finale"
end

--[[
	Makes sure the flying weapon exists for this item, building it from the same
	template the equip path uses.

	Returns false when there is no model to fly. Deliberately no fallback: a
	stand-in blade would be indistinguishable from the real asset failing to
	load, and the whole point of this ability is that the thing raining down is
	the player's actual weapon.

	Builds the finale's variant alongside it. That one IS allowed to fall back -
	if it cannot be built the last blade flies as an ordinary one, which loses
	the emphasis but not the cast.
]]
local warnedMissing = {}

local function ensureWeaponTemplate(itemName: string): boolean
	local key = weaponKey(itemName)
	if FXBuilder.hasTemplate(key) then
		return true
	end

	local toolsFolder = ReplicatedStorage:FindFirstChild("Tools")
	local template = toolsFolder and toolsFolder:FindFirstChild(itemName)

	if not template then
		if not warnedMissing[itemName] then
			warnedMissing[itemName] = true
			warn(string.format(
				"[SacredRainVFX] no model in ReplicatedStorage.Tools for '%s', so there is "
					.. "nothing to rain down. The ability will not draw.",
				itemName
			))
		end
		return false
	end

	local built, reason = FXBuilder.buildWeapon(template)
	if not built then
		if not warnedMissing[itemName] then
			warnedMissing[itemName] = true
			warn(string.format(
				"[SacredRainVFX] could not build a flying '%s': %s", itemName, tostring(reason)
			))
		end
		return false
	end

	FXBuilder.setTemplate(key, built)

	local finale, finaleReason = FXBuilder.buildWeapon(template, {
		scale = Tuning.FinaleScale,
		color = Tuning.FinaleColor,
	})

	if finale then
		FXBuilder.setTemplate(finaleWeaponKey(itemName), finale)
	else
		warn(string.format(
			"[SacredRainVFX] could not build the finale's '%s': %s. The last blade will "
				.. "fall as an ordinary one.",
			itemName, tostring(finaleReason)
		))
	end

	return true
end

--[[
	Every BasePart in an assembly, for fading. Collected once per strike and
	reused by both fades rather than walked twice.
]]
local function collectParts(root: BasePart): { BasePart }
	local parts = { root }
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

--[[
	The reference's hit flash: Assets.HitFX.Attach, cloned onto whatever was
	caught, emitted once, gone after three seconds.

	Cosmetic only. The query is repeated here rather than sent by the server
	because sending it would mean a packet per strike per victim, and being one
	frame out about where a spark appeared costs nothing.
]]
local hitParams = OverlapParams.new()
hitParams.FilterType = Enum.RaycastFilterType.Exclude
hitParams.MaxParts = 24

local function flashHits(weapon: BasePart, folder: Folder, scope)
	local template = FXBuilder.template("HitFX")
	local attach = template and template:FindFirstChild("Attach")
	if not attach then
		return
	end

	-- The effect must not detect itself; the whole cast lives in one folder.
	hitParams.FilterDescendantsInstances = { folder }

	local hits = workspace:GetPartBoundsInBox(weapon.CFrame, Tuning.HitBoxSize, hitParams)
	local seen = {}

	for _, part in ipairs(hits) do
		local model = part.Parent
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local root = model and model:FindFirstChild("HumanoidRootPart")

		if humanoid and root and not seen[model] then
			seen[model] = true

			local flash = attach:Clone()
			flash.Parent = root
			scope:add(flash)

			FXBuilder.emitAll(flash, scope)
			scope:delay(HIT_FX_LIFETIME, function()
				flash:Destroy()
			end)
		end
	end
end

--[[
	One strike, from portal to impact.

	Everything it schedules goes through the scope, so a cast that is cancelled
	half way - the player died, the effect budget was hit, the character
	despawned - leaves nothing running and nothing in the workspace.
]]
local function runStrike(strike, itemName: string, scope, folder: Folder)
	local portal = FXBuilder.acquire("Portal") :: BasePart?
	if not portal then
		return
	end

	local releasePortal = releaser("Portal", portal)
	scope:add(releasePortal)

	portal.CFrame = strike.startCFrame
	portal.Parent = folder

	-- The reference enables only the Main attachment, then emits everything.
	FXBuilder.setEnabledUnder(portal, "Main", true)
	FXBuilder.emitAll(portal, scope)

	scope:delay(Tuning.PortalBurstDelay, function()
		local explode = portal:FindFirstChild("Explode", true)
		if explode then
			FXBuilder.emitAll(explode, scope)
		end

		Sounds.playAt("ability.sacredrain.portal", portal.Position)

		-- The finale flies the big black rig; if it was never built, it falls
		-- back to the ordinary one rather than not falling at all.
		local key = weaponKey(itemName)
		if strike.finale and FXBuilder.hasTemplate(finaleWeaponKey(itemName)) then
			key = finaleWeaponKey(itemName)
		end

		local weapon = FXBuilder.acquire(key) :: BasePart?
		if not weapon then
			return
		end

		local releaseWeapon = releaser(key, weapon)
		scope:add(releaseWeapon)

		weapon.CFrame = strike.startCFrame
		weapon.Parent = folder

		local parts = collectParts(weapon)

		-- The reference hides the portal the moment the sword appears, then
		-- lets Debris take it four seconds later.
		portal.Transparency = 1
		scope:delay(Tuning.PortalLifetime, releasePortal)

		if Tuning.FadeSwordIn then
			for _, part in ipairs(parts) do
				local rest = part:GetAttribute("_BBTransparency")
				part.Transparency = 1
				scope:tween(part, FADE_IN, { Transparency = if type(rest) == "number" then rest else 0 })
			end
		end

		scope:delay(Tuning.SwordFadeInTime, function()
			local travel = scope:tween(weapon, TRAVEL, { Position = strike.endPosition })
			if not travel then
				return
			end

			scope:add(travel.Completed:Connect(function(state)
				if state ~= Enum.PlaybackState.Completed or scope:isDead() then
					return
				end

				for _, part in ipairs(parts) do
					scope:tween(part, FADE_OUT, { Transparency = 1 })
				end

				FXBuilder.setEnabledUnder(portal, "Main", false)
				FXBuilder.setEnabled(weapon, false)

				local swordExplode = weapon:FindFirstChild("Explode", true)
				if swordExplode then
					FXBuilder.emitAll(swordExplode, scope)
				end

				Sounds.playAt("ability.sacredrain.impact", weapon.Position)
				flashHits(weapon, folder, scope)
			end))
		end)

		scope:delay(Tuning.SwordLifetime, releaseWeapon)
	end)
end

--[[
	Plays a whole cast.

	Returns true if it started. The scope belongs to the caller - AbilityClient
	owns it, times it out and destroys it - so this schedules into it and never
	tears it down itself.
]]
function SacredRainVFX.play(payload, scope): boolean
	local itemName = payload.item
	if type(itemName) ~= "string" or not ensureWeaponTemplate(itemName) then
		return false
	end

	local plan = SacredRainPlan.build(payload.seed, payload.origin, payload.target)
	local folder = effectsFolder()


	for _, strike in ipairs(plan.strikes) do
		scope:delay(strike.castAt, function()
			runStrike(strike, itemName, scope, folder)
		end)
	end

	return true
end

--[[
	How long a cast takes, end to end. AbilityClient uses it to decide when the
	scope it handed over can be torn down regardless of what happened inside.
]]
function SacredRainVFX.duration(): number
	return SacredRainPlan.duration()
end

--[[
	Builds and caches everything this effect needs, ahead of the first cast.

	Called when the weapon is equipped rather than when it is fired: assembling
	a hundred and fifty-nine emitters takes long enough to be visible as a hitch
	if it happens on the frame somebody presses the key.
]]
function SacredRainVFX.preload(itemName: string)
	FXBuilder.template("Portal")
	FXBuilder.template("HitFX")

	if type(itemName) == "string" then
		ensureWeaponTemplate(itemName)
	end
end

return SacredRainVFX
