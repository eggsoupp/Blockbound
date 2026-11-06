--[[
	WeaponShotVFX

	Draws legendary weapon shots (Shared.Combat.WeaponShots) from the server's
	packets: the whole straight flight from the launch, a burst for every
	enemy a shot passes through, and its end. Every look is built from
	complete pack assemblies (ReplicatedStorage.WeaponShotLibrary, with two
	from AbilityVFXLibrary); see assets/vfx-library/WeaponShotLibrary.sources.json.

	A shot is a weapon attack, so it reads smaller than an ability: compact
	bodies, short tails and impact sounds a step quieter.

	A look is { build(scope, folder, scale) -> draw, launch, hit, pierce },
	where draw has place(frame, distance), impact(position, normal, final) and
	finish(), and the sound fields are CombatAudio layers { key, volume, pitch }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Scope = require(script.Parent.Parent.AbilityScope)
local Pack = require(script.Parent.PackAssembly)
local Shots = require(ReplicatedStorage.Shared.Combat.WeaponShots)
local CombatAudio = require(ReplicatedStorage.Shared.Audio.CombatAudio)

local Library = ReplicatedStorage:WaitForChild("WeaponShotLibrary")

local VFX = {}

-- Hot ends a little warm: pure white reads as nothing in particular in daylight.
local GOLD = { deep = Color3.fromRGB(190, 120, 30), main = Color3.fromRGB(255, 205, 100), hot = Color3.fromRGB(255, 240, 195) }
local ELECTRIC = { deep = Color3.fromRGB(30, 100, 255), main = Color3.fromRGB(140, 215, 255), hot = Color3.new(1, 1, 1) }
local FIRE = { deep = Color3.fromRGB(150, 25, 0), main = Color3.fromRGB(255, 105, 20), hot = Color3.fromRGB(255, 210, 120) }
-- Additive red over sky turns pink quickly, so even the hot end stays red.
local BLOOD = { deep = Color3.fromRGB(90, 0, 10), main = Color3.fromRGB(200, 10, 30), hot = Color3.fromRGB(255, 80, 90) }
local VOID = { deep = Color3.fromRGB(40, 0, 80), main = Color3.fromRGB(140, 55, 240), hot = Color3.fromRGB(200, 145, 255) }

local function mount(scope, folder, name, options)
	options = options or {}
	options.template = options.template or Library:FindFirstChild(name)
	options.brightness = options.brightness or 2.5
	return Pack.mount(scope, folder, name, options)
end

-- Runs every layer of an assembly, whether its showcase left it on or not.
local function streamAll(handle, on: boolean)
	for _, e in ipairs(handle.emitters) do
		if e.v.Enabled ~= on then
			e.v.Enabled = on
		end
	end
end

-- Lines the assembly up by where its emitters actually are: some pack models
-- keep their pivot well away from what shows.
local function centreOnEmitters(handle)
	local sum, count = Vector3.zero, 0
	for _, e in ipairs(handle.emitters) do
		local part = e.v.Parent
		local at = if part:IsA("Attachment") then part.WorldPosition elseif part:IsA("BasePart") then part.Position else nil
		if at then
			sum += at
			count += 1
		end
	end
	if count > 0 then
		handle.offset = CFrame.new(sum / count):ToObjectSpace(handle.model:GetPivot())
	end
end

-- One of the pack's crescent cards, by the colour its decal was authored in
-- (child order is not something a place file promises to keep).
local function crescent(color: Color3)
	local folder = Library:FindFirstChild("Crescents")
	local best, bestGap = nil, math.huge
	for _, card in ipairs(folder and folder:GetChildren() or {}) do
		local decal = card:FindFirstChildWhichIsA("Decal", true)
		if decal then
			local c = decal.Color3
			local gap = (c.R - color.R) ^ 2 + (c.G - color.G) ^ 2 + (c.B - color.B) ^ 2
			if gap < bestGap then
				best, bestGap = card, gap
			end
		end
	end
	return best
end

local function burstAt(scope, folder, name, position, normal, scale, tint, strength)
	local frame = CFrame.lookAt(position, position + (normal or Vector3.yAxis))
	local handle = mount(scope, folder, name, { cframe = frame, scale = scale, tint = tint })
	handle:burst(strength or 1)
	return handle
end

local Looks = {}

-- Light Lance: a radiant star at the head of a shaft of light.
Looks.Light = {
	launch = { { "whoosh.light", 0.42, 1.35 }, { "orb_chime", 0.22, 1.5 } },
	pierce = { { "impact.light", 0.42, 1.15 } },
	hit = { { "impact.light", 0.5, 1 } },
	light = Color3.fromRGB(255, 220, 140),
	build = function(scope, folder, s)
		local star = mount(scope, folder, "LanceStar", { scale = 0.22 * s, tint = GOLD, locked = true, budget = 80 })
		centreOnEmitters(star)
		local shaft = mount(scope, folder, "LanceBeam", { scale = 0.5 * s, tint = GOLD })
		shaft:slim(0.35)
		streamAll(star, true)
		shaft:beamsOn(true)
		return {
			place = function(frame, distance)
				star:place(frame)
				local head = frame.Position
				shaft:stretch(head, head - frame.LookVector * math.min(9 * s, distance))
			end,
			impact = function(position, normal, final)
				burstAt(scope, folder, "LanceImpact", position, normal, (if final then 0.5 else 0.35) * s, GOLD)
			end,
			finish = function()
				streamAll(star, false)
				shaft:beamsOn(false)
			end,
		}
	end,
}

-- Thunderveil: a short bolt, crackling, that bursts in a flash where it lands.
Looks.Thunder = {
	launch = { { "zap_quick", 0.42, 1.15 }, { "whoosh.light", 0.3, 1.5 } },
	pierce = { { "impact.lightning", 0.38, 1.2 } },
	hit = { { "impact.lightning", 0.48, 1.1 } },
	light = Color3.fromRGB(150, 210, 255),
	build = function(scope, folder, s)
		local bolt = Pack.mount(scope, folder, "KiBlast2", { scale = 0.3 * s, tint = ELECTRIC, brightness = 2.5 })
		bolt:slim(0.45)
		bolt:beamsOn(true)
		local surge = Pack.mount(scope, folder, "LightningSurge", { scale = 0.45 * s, tint = ELECTRIC, locked = true, brightness = 2.5, budget = 40 })
		streamAll(surge, true)
		return {
			place = function(frame, distance)
				local head = frame.Position
				bolt:stretch(head, head - frame.LookVector * math.min(8 * s, distance))
				surge:place(frame)
			end,
			impact = function(position, normal, final)
				-- The crackle is the hit; the ground scorch only where it stops.
				burstAt(scope, folder, "ThunderFlash", position, normal, (if final then 0.55 else 0.38) * s, ELECTRIC)
				if final then
					burstAt(scope, folder, "ThunderImpact", position, normal, 0.6 * s, ELECTRIC)
				end
			end,
			finish = function()
				bolt:beamsOn(false)
				streamAll(surge, false)
			end,
		}
	end,
}

-- Dragonfang: a blazing star ringed in embers, bursting into flame. The
-- assembly's white wisp beams stay off: on a flying shot they read as wind.
Looks.Dragon = {
	launch = { { "cast.launch", 0.42, 1.15 }, { "flame_blast3", 0.25, 1.4 } },
	pierce = { { "impact.fire", 0.38, 1.25 } },
	hit = { { "impact.fire", 0.48, 1.15 } },
	light = Color3.fromRGB(255, 150, 60),
	build = function(scope, folder, s)
		-- Its flares live 0.3s, so a tighter budget leaves gaps where the core blinks out.
		local orb = mount(scope, folder, "DragonOrb", { scale = 0.6 * s, locked = true, budget = 200 })
		centreOnEmitters(orb)
		streamAll(orb, true)
		return {
			place = function(frame)
				orb:place(frame)
			end,
			impact = function(position, normal, final)
				burstAt(scope, folder, "DragonImpact", position, normal, (if final then 0.5 else 0.36) * s, FIRE)
			end,
			finish = function()
				streamAll(orb, false)
			end,
		}
	end,
}

-- Valhalla Axe: a spirit-flame axe head, its cyan edge wheeling as it flies.
Looks.Valhalla = {
	launch = { { "whoosh.heavy", 0.48, 1.1 } },
	pierce = { { "impact.heavy", 0.4, 1.15 } },
	hit = { { "impact.heavy", 0.48, 1.05 }, { "impact.ice", 0.3, 1.1 } },
	light = Color3.fromRGB(90, 180, 255),
	build = function(scope, folder, s)
		local core = mount(scope, folder, "ValhallaOrb", { scale = 0.32 * s, locked = true, visible = true, budget = 60 })
		centreOnEmitters(core)
		streamAll(core, true)
		local edge = mount(scope, folder, "ValhallaEdge", { template = crescent(Color3.fromRGB(49, 252, 255)), scale = 0.42 * s })
		local spin = 0
		local last = os.clock()
		return {
			place = function(frame)
				local now = os.clock()
				spin += (now - last) * 18
				last = now
				core:place(frame)
				-- Wheeling end over end in the plane of its flight, as a thrown axe does.
				edge:place(frame * CFrame.Angles(spin, 0, 0) * CFrame.Angles(0, 0, math.pi / 2))
			end,
			impact = function(position, normal, final)
				burstAt(scope, folder, "ValhallaImpact", position, normal, (if final then 0.55 else 0.4) * s)
			end,
			finish = function()
				streamAll(core, false)
				core:fade(0)
				edge.model:Destroy()
			end,
		}
	end,
}

-- Bloodmoon Greatsword: a wide crescent of blood, cutting through a crowd.
Looks.Blood = {
	launch = { { "whoosh.blade", 0.5, 0.8 } },
	pierce = { { "impact.blade", 0.4, 0.85 } },
	hit = { { "impact.blade", 0.48, 0.8 }, { "impact.debris", 0.3, 0.9 } },
	light = Color3.fromRGB(255, 50, 60),
	build = function(scope, folder, s)
		local wave = mount(scope, folder, "BloodWave", { template = crescent(Color3.fromRGB(255, 0, 4)), scale = 0.62 * s })
		local slash = Pack.mount(scope, folder, "CrescentSlash", { scale = 0.55 * s, tint = BLOOD, visible = true, locked = true, brightness = 2.5, budget = 60 })
		streamAll(slash, true)
		return {
			place = function(frame)
				-- Both flat, arcs leading the flight: the card lies flat as
				-- authored, the slash mesh is a disc on its side.
				wave:place(frame)
				slash:place(frame * CFrame.Angles(0, 0, math.pi / 2))
			end,
			impact = function(position, normal, final)
				burstAt(scope, folder, "BloodImpact", position, normal, (if final then 0.6 else 0.45) * s, BLOOD)
			end,
			finish = function()
				streamAll(slash, false)
				slash:fade(0)
				wave.model:Destroy()
			end,
		}
	end,
}

-- Void Reaver: a swirling void orb.
Looks.Void = {
	launch = { { "cast.dark", 0.42, 1.25 } },
	pierce = { { "impact.dark", 0.36, 1.3 } },
	hit = { { "impact.dark", 0.44, 1.2 } },
	light = Color3.fromRGB(160, 90, 255),
	build = function(scope, folder, s)
		local orb = mount(scope, folder, "VoidOrb", { scale = 0.36 * s, tint = VOID, locked = true, budget = 70 })
		centreOnEmitters(orb)
		streamAll(orb, true)
		return {
			place = function(frame)
				orb:place(frame)
			end,
			impact = function(position, normal, final)
				burstAt(scope, folder, "VoidImpact", position, normal, (if final then 0.5 else 0.38) * s, VOID)
			end,
			finish = function()
				streamAll(orb, false)
			end,
		}
	end,
}

VFX.Looks = Looks

local function sound(layers, position)
	for _, layer in ipairs(layers or {}) do
		CombatAudio.play(layer[1], position, layer[2], layer[3])
	end
end

-- id -> { draw, look, packet, stopAt, scope }
local shots = {}

-- A shot leaving. Draws its whole flight until told where it stops.
function VFX.launch(packet)
	local profile = Shots.profileFor(packet.weapon)
	local look = profile and Looks[profile.look]
	if not look or typeof(packet.origin) ~= "Vector3" or typeof(packet.direction) ~= "Vector3" then
		return
	end
	local scope = Scope.new()
	local folder = scope:add(Instance.new("Folder"))
	folder.Name = "WeaponShot"
	folder.Parent = workspace
	local s = packet.scale or 1

	-- Its own soft light on the blocks it passes.
	local host = scope:add(Instance.new("Part"))
	host.Name = "WeaponShotLight"
	host.Anchored, host.CanCollide, host.CanQuery, host.CanTouch, host.CastShadow = true, false, false, false, false
	host.Transparency, host.Size = 1, Vector3.one * 0.2
	host.Parent = folder
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = look.light, 14 * s, 1.6, false
	light.Parent = host

	local ok, draw = pcall(look.build, scope, folder, s)
	if not ok then
		warn("[WeaponShotVFX] " .. tostring(packet.weapon) .. " failed to build: " .. tostring(draw))
		scope:destroy()
		return
	end
	local shot = { draw = draw, look = look, packet = packet, scope = scope, light = light }
	shots[packet.id] = shot
	sound(look.launch, packet.origin)

	local direction = packet.direction.Unit
	local function frameAt(distance)
		local position = packet.origin + direction * distance
		return CFrame.lookAt(position, position + direction)
	end
	scope:add(RunService.RenderStepped:Connect(function()
		local t = workspace:GetServerTimeNow() - packet.startedAt
		local distance = math.min(packet.speed * math.max(t, 0), shot.stopAt or packet.range)
		local frame = frameAt(distance)
		host.CFrame = frame
		draw.place(frame, distance)
	end))
	-- However it went, it is gone a little after it could last have landed.
	scope:delay(packet.range / packet.speed + 2.5, function()
		shots[packet.id] = nil
		scope:destroy()
	end)
end

-- Something happened to a shot already in flight.
function VFX.event(packet)
	local shot = shots[packet.id]
	if not shot or typeof(packet.position) ~= "Vector3" then
		return
	end
	if packet.event == "pierce" then
		shot.draw.impact(packet.position, packet.normal, false)
		sound(shot.look.pierce, packet.position)
		return
	end
	-- It stops where the server says, then fades.
	local direction = shot.packet.direction.Unit
	shot.stopAt = math.max(0, (packet.position - shot.packet.origin):Dot(direction))
	shot.draw.finish()
	shot.scope:tween(shot.light, TweenInfo.new(0.35), { Brightness = 0 })
	if packet.event == "hit" then
		shot.draw.impact(packet.position, packet.normal, true)
		sound(shot.look.hit, packet.position)
	end
	shots[packet.id] = nil
	shot.scope:delay(1.4, function()
		shot.scope:destroy()
	end)
end

function VFX.preload()
	Pack.preload()
	task.spawn(function()
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({ Library })
		end)
	end)
end

return VFX
