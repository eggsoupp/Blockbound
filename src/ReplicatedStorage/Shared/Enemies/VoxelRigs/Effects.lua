--[[
	VoxelRigs.Effects

	Every visible (and audible) effect of the ten voxel creatures' moves,
	drawn on each client from the server's VoxelRigFX messages
	(ServerScriptService.Creatures.VoxelMoves). Built from complete pack
	assemblies - AbilityVFXLibrary, WeaponShotLibrary, WishVFXLibrary and
	the Signus libraries - through PackAssembly, recoloured per creature;
	ground telegraphs are the pack's magic-circle emitters (SignusFX). No
	visible parts: hosts are invisible.

	Effects[kind](style, ...) - see the handlers at the bottom for each kind's
	arguments. A style picks the assemblies, colours and sounds.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Scope = require(Shared.Abilities.AbilityScope)
local Pack = require(Shared.Abilities.VFX.PackAssembly)
local SignusFX = require(Shared.Abilities.VFX.SignusFX)
local CombatAudio = require(Shared.Audio.CombatAudio)
local Player = require(script.Parent.Player)

local Effects = {}

local rgb = Color3.fromRGB
local function tint(deep, main, hot)
	return { deep = deep, main = main, hot = hot }
end

local T = {
	soul = tint(rgb(10, 70, 140), rgb(80, 220, 255), rgb(220, 255, 255)),
	fire = tint(rgb(150, 30, 0), rgb(255, 120, 20), rgb(255, 225, 140)),
	jade = tint(rgb(10, 90, 40), rgb(90, 235, 120), rgb(225, 255, 225)),
	moon = tint(rgb(80, 70, 180), rgb(175, 190, 255), rgb(255, 255, 255)),
	spore = tint(rgb(60, 80, 10), rgb(170, 215, 60), rgb(240, 255, 170)),
	frost = tint(rgb(40, 120, 210), rgb(150, 225, 255), rgb(245, 255, 255)),
	abyss = tint(rgb(30, 10, 80), rgb(120, 70, 220), rgb(110, 255, 230)),
	tide = tint(rgb(10, 60, 120), rgb(60, 170, 230), rgb(220, 250, 255)),
	crystal = tint(rgb(70, 20, 150), rgb(190, 120, 255), rgb(250, 225, 255)),
	ghost = tint(rgb(10, 90, 60), rgb(110, 255, 170), rgb(230, 255, 240)),
	storm = tint(rgb(30, 100, 255), rgb(140, 215, 255), rgb(255, 255, 255)),
	dust = tint(rgb(70, 55, 40), rgb(150, 128, 100), rgb(220, 205, 180)),
	snow = tint(rgb(150, 175, 205), rgb(225, 238, 250), rgb(255, 255, 255)),
	ink = tint(rgb(5, 0, 15), rgb(40, 15, 70), rgb(90, 60, 140)),
	blood = tint(rgb(90, 0, 10), rgb(200, 10, 30), rgb(255, 80, 90)),
	mud = tint(rgb(40, 50, 20), rgb(110, 120, 60), rgb(190, 200, 140)),
}
Effects.Tints = T

local LIBS = {
	A = "AbilityVFXLibrary", W = "WeaponShotLibrary", S = "SignusLibrary",
	E = "SignusEclipseLibrary", G = "WishVFXLibrary",
}

local function template(lib, name)
	local folder = ReplicatedStorage:FindFirstChild(LIBS[lib] or lib)
	return folder and folder:FindFirstChild(name)
end

local stage = workspace:FindFirstChild("VoxelRigFX")
local function folder()
	if not stage or not stage.Parent then
		stage = Instance.new("Folder")
		stage.Name = "VoxelRigFX"
		stage.Parent = workspace
	end
	return stage
end

-- ---------------------------------------------------------------------------
-- Building blocks
-- ---------------------------------------------------------------------------

-- One layer: { lib, name, scale, tint, options }.
local function mount(scope, layer, cframe, size)
	local options = {}
	for k, v in pairs(layer[5] or {}) do options[k] = v end
	options.template = template(layer[1], layer[2])
	options.scale = (layer[3] or 1) * (size or 1)
	options.tint = layer[4]
	options.cframe = cframe
	options.brightness = options.brightness or 2.5
	if not options.template then
		return nil
	end
	local ok, handle = pcall(Pack.mount, scope, folder(), layer[2], options)
	if not ok then
		return nil
	end
	-- Black "core" layers read as holes cut in daylight: dropped where asked.
	if options.noDark then
		for i = #handle.emitters, 1, -1 do
			local e = handle.emitters[i].v
			local c = e.Color.Keypoints[1].Value
			if math.max(c.R, c.G, c.B) < 0.1 then
				e:Destroy()
				table.remove(handle.emitters, i)
			end
		end
	end
	return handle
end

-- Runs every layer of an assembly, whether the pack left it on or not.
local function run(handle, on)
	if not handle then return end
	for _, e in ipairs(handle.emitters) do
		if e.v.Enabled ~= on then e.v.Enabled = on end
	end
	handle:beamsOn(on)
end

local function longest(handle)
	local life = 0
	for _, e in ipairs(handle and handle.emitters or {}) do
		life = math.max(life, e.v.Lifetime.Max / math.max(e.v.TimeScale, 0.05))
	end
	return life
end

-- A scope that cleans itself up `seconds` after it is made.
local function timed(seconds)
	local scope = Scope.new()
	task.delay(seconds, function() scope:destroy() end)
	return scope
end

local function sound(entry, at)
	if entry then
		CombatAudio.play(entry[1], at, entry[2] or 0.6, entry[3] or 1)
	end
end

-- Bursts a list of layers once at `cframe`.
local function burstLayers(layers, cframe, size, strength)
	local scope = Scope.new()
	local life = 0.5
	local pending = {}
	for _, layer in ipairs(layers) do
		local handle = mount(scope, layer, cframe, size)
		if handle then
			table.insert(pending, { handle = handle, layer = layer })
			life = math.max(life, longest(handle) + (layer[7] or 0.25))
		end
	end
	-- One frame after parenting: an Emit on an emitter parented this same
	-- frame can be dropped.
	scope:add(RunService.Heartbeat:Once(function()
		for _, p in ipairs(pending) do
			local handle, layer = p.handle, p.layer
			if layer[6] == "stream" then
				run(handle, true)
				scope:delay(layer[7] or 0.25, function() run(handle, false) end)
			else
				handle:burst((strength or 1) * (layer[6] or 1))
				handle:beamsOn(true)
				scope:delay(0.15, function() handle:beamsOn(false) end)
			end
		end
	end))
	task.delay(life + 0.3, function() scope:destroy() end)
end

-- Where a named socket of a rig is right now, and the part's facing.
local function socketOf(model, rigName, socketName)
	local ok, spec = pcall(require, script.Parent:FindFirstChild(rigName))
	local socket = ok and spec.sockets and spec.sockets[socketName]
	if not socket then
		return model:GetPivot().Position, model:GetPivot().LookVector
	end
	local part = model:FindFirstChild(socket.part)
	local look = if part then part.CFrame.LookVector else model:GetPivot().LookVector
	return Player.socket(model, socket, spec.voxel), look
end

-- Keeps a handle on a socket for `seconds`, streaming.
local function follow(scope, handle, model, rigName, socketName, offset)
	scope:add(RunService.Heartbeat:Connect(function()
		if not model.Parent then
			run(handle, false)
			return
		end
		local at, look = socketOf(model, rigName, socketName)
		handle:place(CFrame.lookAt(at, at + look) * (offset or CFrame.identity))
	end))
end

-- ---------------------------------------------------------------------------
-- Styles
-- ---------------------------------------------------------------------------

local BURSTS = {
	soulHit = { { "E", "ImpactViolet", 0.3, T.soul }, sound = { "magic_warp", 0.45, 1.25 } },
	soulCast = { { "G", "Flash", 0.25, T.soul, { billboard = true } }, sound = { "plasma_cast", 0.55, 0.9 } },
	soulSlam = { { "A", "Rocks", 0.2, T.dust }, { "E", "VoidBurst", 0.25, T.soul }, sound = { "ground_slam", 0.6, 1.1 } },
	quake = { { "A", "Rocks", 0.35, T.dust }, { "A", "SmokePuff", 1.0, T.dust, nil, 4 }, { "A", "Impact1", 0.3, T.fire, { brightness = 1.4 } }, sound = { "ground_slam", 0.9, 0.8 } },
	clang = { { "A", "Impact9", 0.6, T.fire }, sound = { "metal_crash", 0.7, 1 } },
	jadeHit = { { "A", "SlashImpact1", 0.9, T.jade }, sound = { "sword_hit", 0.55, 0.9 } },
	eyespot = { { "G", "Flash", 0.8, T.moon, { billboard = true } }, { "G", "GoldStar", 0.3, T.moon }, { "G", "Twinkles", 0.5, T.moon }, sound = { "sparkle", 0.8, 0.8 } },
	mudQuake = { { "A", "Rocks", 0.35, T.mud }, { "A", "SmokePuff", 1.2, T.mud, nil, 4 }, { "A", "Droplets69", 1.0, T.spore }, sound = { "ground_slam", 0.9, 0.75 } },
	sporePuff = { { "A", "SmokePuff", 1.2, T.spore, nil, 3 }, { "A", "Droplets69", 0.8, T.spore }, sound = { "poof_air", 0.6, 0.8 } },
	frostBite = { { "A", "IceSplash", 0.5 }, { "A", "Impact12", 0.6, T.frost }, sound = { "ice_chunk", 0.7, 1 } },
	snowGust = { { "A", "SmokePuff", 1.6, T.snow, nil, 4 }, { "G", "Twinkles", 0.5, T.frost }, sound = { "heavy_whoosh", 0.8, 0.7 } },
	abyssBite = { { "A", "Impact20", 0.7, T.abyss }, { "A", "Droplets69", 0.8, T.tide }, sound = { "punch_heavy1", 0.7, 0.8 } },
	inkBurst = { { "A", "SmokePuff", 2.0, T.ink, nil, 4 }, { "E", "VoidBurst", 0.35, T.abyss }, sound = { "bass_drop", 0.8, 1 } },
	crystalSnap = { { "A", "SlashImpact3", 0.9, T.crystal }, sound = { "glass_crisp", 0.7, 0.9 } },
	venom = { { "W", "VoidImpact", 0.25, T.crystal }, { "A", "Impact36", 0.6, T.crystal }, sound = { "glass_break1", 0.6, 1.1 } },
	ghostImpact = { { "W", "LanceImpact", 0.45, T.ghost }, sound = { "cine_hit", 0.7, 1 } },
	ghostStomp = { { "A", "Rocks", 0.3, T.dust }, { "A", "SmokePuff", 1.0, T.dust, nil, 4 }, { "E", "ImpactViolet", 0.35, T.ghost }, sound = { "ground_slam", 0.9, 0.85 } },
	thunderclap = { { "W", "ThunderFlash", 0.4, T.storm, { billboard = true } }, { "A", "Impact41", 0.9, T.storm }, sound = { "lightning_close", 0.8, 1 } },
	stormPunch = { { "A", "Impact44", 0.8, T.storm }, sound = { "punch_heavy2", 0.6, 1.1 } },
}

local CASTS = {
	soul = { layer = { "S", "Orb", 2.5, T.soul, { locked = true, budget = 120 } }, sound = { "magic_cast", 0.5, 1 } },
	soulNova = { layer = { "E", "AuraViolet", 1.4, T.soul, { budget = 300 } }, sound = { "power_up", 0.6, 1 } },
	ember = { layer = { "A", "FlameCore", 0.15, T.fire, { locked = true, budget = 120 } }, sound = { "charge_short", 0.45, 0.8 } },
	brassShield = { layer = { "A", "FireVFX6", 0.6, T.fire, { budget = 80 } }, sound = { "magic_lock", 0.5, 0.7 } },
	furnace = { layer = { "A", "FlameCore", 0.22, T.fire, { locked = true, budget = 200 } }, sound = { "flame_blast1", 0.6, 0.7 } },
	jade = { layer = { "W", "LanceStar", 0.2, T.jade, { locked = true, budget = 80 } }, sound = { "alien_chirp", 0.6, 0.8 } },
	moon = { layer = { "G", "GoldStar", 0.25, T.moon, { budget = 200 } }, sound = { "sparkle", 0.6, 0.7 } },
	spore = { layer = { "A", "Droplets69", 0.8, T.spore, { budget = 60 } }, sound = { "bubbles", 0.6, 0.8 } },
	frost = { layer = { "S", "Orb", 2.0, T.frost, { locked = true, budget = 120 } }, sound = { "charge_short", 0.5, 1.2 } },
	abyss = { layer = { "E", "AuraViolet", 1.8, T.abyss, { budget = 300 } }, sound = { "bubbles", 0.7, 0.6 } },
	crystal = { layer = { "W", "LanceStar", 0.22, T.crystal, { locked = true, budget = 80 } }, sound = { "glass_crisp", 0.5, 1.2 } },
	ghost = { layer = { "A", "FireVFX6", 0.45, T.ghost, { budget = 80 } }, sound = { "monster_roar", 0.6, 0.8 } },
	storm = { layer = { "A", "LightningSurge", 0.2, T.storm, { locked = true, budget = 40 } }, sound = { "electric_hum", 0.6, 1 } },
	stormCall = { layer = { "A", "LightningSurge", 0.3, T.storm, { budget = 60 } }, sound = { "electric_shock", 0.7, 0.8 } },
}

local SHOTS = {
	soulBolt = { layer = { "W", "VoidOrb", 0.4, T.soul, { locked = true, budget = 70 } }, sound = { "laser_shot", 0.4, 0.8 } },
	sporePod = { layer = { "A", "BZ1Fireball", 0.3, T.spore, { visible = true, meshTint = T.spore, budget = 120 } }, sound = { "slime_pop", 0.6, 0.7 } },
	stormOrb = { layer = { "A", "LightningSurge", 0.18, T.storm, { locked = true, budget = 40 } }, sound = { "zap_quick", 0.6, 0.8 } },
}

local CIRCLE = {
	soul = T.soul, moon = T.moon, frost = T.frost, storm = T.storm, spore = T.spore,
	ghost = T.ghost, jade = T.jade, crystal = T.crystal, abyss = T.abyss,
}

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

-- One-shot impact: burst(style, position, size)
function Effects.burst(style, position, size)
	local spec = BURSTS[style]
	if not spec then return end
	burstLayers(spec, CFrame.new(position), size or 1)
	sound(spec.sound, position)
end

-- Charge-up glow riding a socket: cast(style, model, rigName, socket, seconds)
function Effects.cast(style, model, rigName, socketName, seconds)
	local spec = CASTS[style]
	if not spec or not model then return end
	local scope = timed(seconds + 1.5)
	local handle = mount(scope, spec.layer, model:GetPivot())
	if not handle then return end
	follow(scope, handle, model, rigName, socketName)
	run(handle, true)
	scope:delay(seconds, function() run(handle, false) end)
	local at = socketOf(model, rigName, socketName)
	sound(spec.sound, at)
end

-- A ground telegraph that holds, then fades: mark(style, position, radius, seconds)
function Effects.mark(style, position, radius, seconds)
	local color = CIRCLE[style] or T.soul
	local scope = timed(seconds + 1.4)
	local host = SignusFX.host(scope, position + Vector3.new(0, 0.25, 0), "VoxelRigMark")
	host.Parent = folder()
	local a = SignusFX.attachment(host)
	local up = { EmissionDirection = Enum.NormalId.Top, Brightness = 1.6, Rate = 2.4, Lifetime = NumberRange.new(0.9) }
	local outer = SignusFX.circle(a, "SigilOrnate", radius * 2.25, color.main, up)
	outer.RotSpeed = NumberRange.new(-30)
	local inner = SignusFX.circle(a, "SigilStar", radius * 1.6, color.hot, up)
	inner.RotSpeed = NumberRange.new(55)
	outer:Emit(1)
	inner:Emit(1)
	scope:delay(seconds, function()
		outer.Enabled = false
		inner.Enabled = false
	end)
	CombatAudio.play("magic_lock", position, 0.35, 1.3)
end

-- A column falling or bursting from the ground: pillar(style, position, radius)
function Effects.pillar(style, position, radius)
	if style == "moon" then
		burstLayers({
			{ "G", "Pillar", radius / 2.2, T.moon, { budget = 400 }, "stream", 0.45 },
			{ "G", "RingBurst", radius / 2.5, T.moon, { billboard = true } },
			{ "G", "Twinkles", 0.4, T.moon },
		}, CFrame.new(position), 1)
		CombatAudio.play("star_impact", position, 0.8, 0.9)
	else
		-- Column29 is authored lying along its X axis: stood up here.
		local up, side = Vector3.yAxis, Vector3.xAxis
		burstLayers({
			{ "A", "Column29", radius / 8, T.soul, { faceCamera = true, brightness = 2 }, "stream", 0.45 },
		}, CFrame.fromMatrix(position + up * 5, up, side, up:Cross(side)), 1)
		burstLayers({
			{ "E", "VoidBurst", 0.3, T.soul },
			{ "E", "ImpactViolet", 0.35, T.soul },
			{ "A", "Rocks", 0.2, T.dust },
		}, CFrame.new(position), 1)
		CombatAudio.play("blast_short", position, 0.7, 0.9)
	end
end

-- An expanding ring on the ground: ring(style, position, radius)
function Effects.ring(style, position, radius)
	local color = CIRCLE[style] or (if style == "dust" then T.dust else T.soul)
	local layers = {
		{ "G", "RadialBurst", radius / 30, color, { noDark = true }, 1.5 },
		{ "G", "RingBurst", radius / 2.5, color, { billboard = true }, 1.5 },
	}
	if style == "dust" or style == "spore" or style == "ghost" or style == "frost" then
		table.insert(layers, { "A", "SmokePuff", radius / 7, if style == "frost" then T.snow elseif style == "spore" then T.mud else T.dust, nil, 4 })
	end
	burstLayers(layers, CFrame.new(position + Vector3.new(0, 0.5, 0)), 1)
end

-- A crescent cut riding a socket: slash(style, model, rigName, socket, seconds)
function Effects.slash(style, model, rigName, socketName, seconds)
	if not model then return end
	local color = if style == "jadeCross" then T.jade else T.soul
	local scope = timed(seconds + 0.8)
	local at, look = socketOf(model, rigName, socketName)
	local side = if string.find(socketName, "left") then -1 else 1
	local frame = CFrame.lookAt(at, at + model:GetPivot().LookVector) * CFrame.Angles(0, 0, math.rad(55 * side))
	local handle = mount(scope, { "A", "CrescentSlash", 0.8, color, { visible = true, locked = true, budget = 60 } }, frame)
	if handle then
		run(handle, true)
		local started = os.clock()
		scope:add(RunService.Heartbeat:Connect(function()
			local t = (os.clock() - started) / seconds
			handle:fade(math.clamp(1 - t, 0, 1))
			handle:place(frame * CFrame.new(0, 0, -t * 4))
		end))
		scope:delay(seconds, function() run(handle, false) end)
	end
	CombatAudio.play("sword_swing", at, 0.6, if style == "jadeCross" then 1.2 else 0.8)
end

-- A streaming trail on a socket: trail(style, model, rigName, socket, seconds)
local TRAILS = {
	dust = { { "A", "SmokeDense", 0.5, T.dust, { budget = 60 } } },
	jadeWhirl = { { "W", "LanceStar", 0.16, T.jade, { budget = 120 } } },
	frostTail = { { "A", "SmokeDense", 0.5, T.snow, { budget = 80 } }, { "G", "Twinkles", 0.2, T.frost } },
	ghostCharge = { { "A", "FlameCore", 0.2, T.ghost, { budget = 220 } }, { "A", "FireVFX6", 0.8, T.ghost, { budget = 120 } } },
}
function Effects.trail(style, model, rigName, socketName, seconds)
	local layers = TRAILS[style]
	if not layers or not model then return end
	local scope = timed(seconds + 2)
	for _, layer in ipairs(layers) do
		local handle = mount(scope, layer, model:GetPivot())
		if handle then
			follow(scope, handle, model, rigName, socketName)
			run(handle, true)
			scope:delay(seconds, function() run(handle, false) end)
		end
	end
	local at = socketOf(model, rigName, socketName)
	CombatAudio.play(if style == "ghostCharge" then "explosive_whoosh" else "heavy_whoosh", at, 0.7, 0.8)
end

--[[
	A stream poured out of a socket along the model's facing: puffs of the
	style's assembly launched one after another, each flying out to `range`.
	cone(style, model, rigName, socket, range, halfAngle, seconds)
]]
local CONES = {
	fire = { layers = { { "A", "FlameCore", 0.12, T.fire, { budget = 90 } }, { "A", "FireVFX9", 0.5, T.fire, { budget = 60 } } }, every = 0.045, speed = 1, sound = { "flame_blast2", 0.8, 0.8 } },
	gale = { layers = { { "A", "SmokeDense", 0.35, T.moon, { budget = 40 } }, { "G", "Twinkles", 0.15, T.moon } }, every = 0.06, speed = 1.6, sound = { "heavy_whoosh", 0.9, 0.6 } },
	frost = { layers = { { "A", "SmokeDense", 0.6, T.snow, { budget = 50 } }, { "G", "Twinkles", 0.2, T.frost }, { "A", "IceSplash", 0.25 } }, every = 0.05, speed = 1.2, sound = { "air_suction", 0.8, 1.2 } },
}
local function pour(style, model, rigName, socketName, range, halfAngle, seconds, useHead)
	local spec = CONES[style]
	if not spec or not model then return end
	local scope = timed(seconds + 2.5)
	local started = os.clock()
	local nextAt = 0
	local flight = 0.55 / spec.speed
	scope:add(RunService.Heartbeat:Connect(function()
		local t = os.clock() - started
		if t > seconds or not model.Parent then return end
		if t < nextAt then return end
		nextAt = t + spec.every
		local at, look = socketOf(model, rigName, socketName)
		local dir = if useHead then (look - Vector3.new(0, 0.3, 0)).Unit else model:GetPivot().LookVector
		local spread = CFrame.Angles(math.rad((math.random() - 0.5) * halfAngle * 0.6), math.rad((math.random() - 0.5) * halfAngle * 1.6), 0)
		dir = (CFrame.lookAt(Vector3.zero, dir) * spread).LookVector
		for i, layer in ipairs(spec.layers) do
			local handle = mount(scope, layer, CFrame.new(at))
			if handle then
				run(handle, true)
				local born = os.clock()
				local link
				link = scope:add(RunService.Heartbeat:Connect(function()
					local a = (os.clock() - born) / flight
					if a >= 1 then
						run(handle, false)
						link:Disconnect()
						return
					end
					local eased = 1 - (1 - a) ^ 2
					handle:place(CFrame.new(at + dir * range * eased) * CFrame.new(0, i * 0.2, 0))
					handle:rescale((layer[3] or 1) * (0.6 + a * 1.4))
				end))
			end
		end
	end))
	local at = socketOf(model, rigName, socketName)
	sound(spec.sound, at)
end

function Effects.cone(style, model, rigName, socketName, range, halfAngle, seconds)
	pour(style, model, rigName, socketName, range, halfAngle, seconds, false)
end

-- Breath follows the head as it sweeps: breath(style, model, rigName, socket, range, seconds)
function Effects.breath(style, model, rigName, socketName, range, seconds)
	pour(style, model, rigName, socketName, range, 22, seconds, true)
end

-- A lingering area: zone(style, center, radius, seconds)
local ZONES = {
	sporeCloud = { { "A", "SmokeDense", 0.25, T.spore, { budget = 40 } }, { "A", "Droplets69", 0.5, T.spore, { budget = 30 } } },
	inkCloud = { { "A", "SmokeDense", 0.25, T.ink, { budget = 40 } }, { "G", "Twinkles", 0.2, T.abyss } },
	ghostFire = { { "A", "FireVFX6", 1.3, T.ghost, { budget = 80 } } },
	cyclone = { { "A", "SmokeDense", 0.25, T.snow, { budget = 40 } }, { "G", "Twinkles", 0.2, T.storm } },
}
function Effects.zone(style, center, radius, seconds)
	local layers = ZONES[style]
	if not layers then return end
	local scope = timed(seconds + 3)
	-- A ring of hosts round the edge and one in the middle, so a wide area
	-- is filled without one huge emitter.
	local points = { center }
	local count = math.clamp(math.floor(radius / 2.5), 4, 10)
	for i = 1, count do
		local a = i / count * math.pi * 2
		table.insert(points, center + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.75)
	end
	for _, p in ipairs(points) do
		for _, layer in ipairs(layers) do
			local handle = mount(scope, layer, CFrame.new(p + Vector3.new(0, 1, 0)), 1)
			if handle then
				run(handle, true)
				scope:delay(seconds, function() run(handle, false) end)
			end
		end
	end
	local color = if style == "sporeCloud" then T.spore elseif style == "inkCloud" then T.abyss elseif style == "ghostFire" then T.ghost else T.storm
	local host = SignusFX.host(scope, center + Vector3.new(0, 0.25, 0), "VoxelRigZone")
	host.Parent = folder()
	local ring = SignusFX.circle(SignusFX.attachment(host), "CoronaRing", radius * 2.2, color.main, {
		EmissionDirection = Enum.NormalId.Top, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Brightness = 1.2, Rate = 2, Lifetime = NumberRange.new(0.9),
	})
	ring:Emit(1)
	scope:delay(seconds, function() ring.Enabled = false end)
	CombatAudio.play(if style == "ghostFire" then "flame_blast3" elseif style == "cyclone" then "air_suction" else "bubbles", center, 0.6, 0.8)
end

-- Projectiles: shot(style, id, origin, velocity, gravity), shotEnd(style, id, at)
local shots = {}
function Effects.shot(style, id, origin, velocity, gravity)
	local spec = SHOTS[style]
	if not spec then return end
	local scope = timed(6)
	local handle = mount(scope, spec.layer, CFrame.new(origin))
	if not handle then return end
	run(handle, true)
	local started = os.clock()
	shots[id] = { scope = scope, handle = handle }
	scope:add(RunService.Heartbeat:Connect(function()
		local t = os.clock() - started
		local point = origin + velocity * t + Vector3.new(0, -0.5 * gravity * t * t, 0)
		local vel = velocity + Vector3.new(0, -gravity * t, 0)
		handle:place(CFrame.lookAt(point, point + vel))
	end))
	sound(spec.sound, origin)
end
function Effects.shotEnd(style, id, at)
	local shot = shots[id]
	shots[id] = nil
	if shot then
		run(shot.handle, false)
		shot.handle:fade(0)
		task.delay(1.5, function() shot.scope:destroy() end)
	end
end

-- Ice falling on a spot: fall(style, position)
function Effects.fall(style, position)
	local scope = timed(3)
	local from = position + Vector3.new(math.random() * 4 - 2, 28, math.random() * 4 - 2)
	local handle = mount(scope, { "G", "Comet", 0.35, T.frost, { budget = 80 } }, CFrame.new(from))
	if handle then
		run(handle, true)
		local started = os.clock()
		local link
		link = scope:add(RunService.Heartbeat:Connect(function()
			local a = math.clamp((os.clock() - started) / 0.32, 0, 1)
			local p = from:Lerp(position, a * a)
			handle:place(CFrame.lookAt(p, position))
			if a >= 1 then
				link:Disconnect()
				run(handle, false)
				burstLayers({ { "A", "IceSplash", 0.6 }, { "A", "Rocks", 0.15, T.frost }, { "G", "Twinkles", 0.2, T.frost } }, CFrame.new(position), 1)
				CombatAudio.play("glass_break2", position, 0.6, 0.9)
			end
		end))
	end
end

-- A crushing wave along a line: wave(style, a, b)
function Effects.wave(style, a, b)
	local steps = 5
	for i = 0, steps do
		task.delay(i * 0.04, function()
			local p = a:Lerp(b, i / steps)
			burstLayers({ { "A", "Droplets69", 1.0, T.tide }, { "A", "Impact20", 0.6, T.abyss } }, CFrame.new(p), 1)
		end)
	end
	burstLayers({ { "G", "RingBurst", 1.6, T.tide, { billboard = true }, 1.5 } }, CFrame.new(b), 1)
	CombatAudio.play("ground_slam", b, 0.8, 1.2)
	CombatAudio.play("water_walk", b, 0.8, 0.7)
end

-- A tentacle lash: a beam streaking from `from` to `to`: lash(style, from, to)
function Effects.lash(style, from, to)
	local scope = timed(1.5)
	local handle = mount(scope, { "A", "KiBlast2", 0.3, T.abyss, { faceCamera = true } }, CFrame.new(to))
	if handle then
		handle:stretch(to, from)
		handle:taper(0.4)
		run(handle, true)
		scope:delay(0.22, function() run(handle, false) end)
	end
	for i = 1, 4 do
		task.delay(i * 0.03, function()
			burstLayers({ { "A", "Droplets69", 0.7, T.tide } }, CFrame.new(from:Lerp(to, i / 4)), 1)
		end)
	end
	CombatAudio.play("swish_rise", from, 0.8, 0.8)
end

-- Crystals erupting from the ground: spike(style, position, radius)
function Effects.spike(style, position, radius)
	burstLayers({
		{ "G", "Spikes", radius / 14, T.crystal },
		{ "A", "Rocks", 0.2, T.crystal },
		{ "W", "VoidImpact", 0.15, T.crystal, { brightness = 1.2 } },
	}, CFrame.new(position), 1)
	CombatAudio.play("glass_break1", position, 0.6, 0.8 + math.random() * 0.2)
	CombatAudio.play("earth_crumble", position, 0.4, 1.1)
end

-- A broad flat cut in front of a point: arc(style, position, look, reach)
function Effects.arc(style, position, look, reach)
	local scope = timed(1.6)
	local frame = CFrame.lookAt(position, position + look) * CFrame.Angles(0, 0, math.rad(90))
	local handle = mount(scope, { "A", "CrescentSlash", reach / 14, T.ghost, { visible = true, budget = 80 } }, frame * CFrame.new(0, 0, -reach * 0.35))
	if handle then
		run(handle, true)
		local started = os.clock()
		scope:add(RunService.Heartbeat:Connect(function()
			local t = math.clamp((os.clock() - started) / 0.35, 0, 1)
			handle:fade(1 - t)
			handle:place(frame * CFrame.new(0, 0, -reach * (0.35 + t * 0.3)))
		end))
		scope:delay(0.3, function() run(handle, false) end)
	end
	CombatAudio.play("sword_swing", position, 0.8, 0.7)
end

-- Lightning on a spot: bolt(style, position)
function Effects.bolt(style, position)
	local scope = timed(2)
	pcall(Pack.bolt, scope, folder(), position, { scale = 0.6, tint = T.storm, height = 14, width = 3, duration = 0.3 })
	burstLayers({ { "W", "ThunderFlash", 0.35, T.storm, { billboard = true } }, { "A", "Rocks", 0.15, T.dust } }, CFrame.new(position), 1)
	CombatAudio.play("lightning_close", position, 0.8, 0.9 + math.random() * 0.2)
end

-- Something working on a player: afflict(character, style, seconds)
local AFFLICT = {
	bleed = { "A", "Droplets69", 0.3, T.blood, { budget = 20 } },
	poison = { "A", "Droplets69", 0.3, T.spore, { budget = 20 } },
	venom = { "A", "Droplets69", 0.3, T.crystal, { budget = 20 } },
}
function Effects.afflict(character, style, seconds)
	local layer = AFFLICT[style]
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not layer or not root then return end
	local scope = timed(seconds + 1.5)
	local handle = mount(scope, layer, root.CFrame)
	if handle then
		run(handle, true)
		scope:add(RunService.Heartbeat:Connect(function()
			if root.Parent then handle:place(root.CFrame) end
		end))
		scope:delay(seconds, function() run(handle, false) end)
	end
end

-- ---------------------------------------------------------------------------
-- Things done to the local player and their view
-- ---------------------------------------------------------------------------

local function localRoot()
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character and character:FindFirstChildOfClass("Humanoid")
end

-- Pushed: knock(velocity)
function Effects.knock(velocity)
	local root, humanoid = localRoot()
	if not root or not humanoid or humanoid.Health <= 0 then return end
	if velocity.Y > 5 then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
	root.AssemblyLinearVelocity = velocity
	task.defer(function()
		if root.Parent then root.AssemblyLinearVelocity = velocity end
	end)
end

-- The camera shakes for anyone near: shake(position, strength, radius)
local shaking = 0
function Effects.shake(position, strength, radius)
	local root, humanoid = localRoot()
	if not root or not humanoid then return end
	local near = 1 - (root.Position - position).Magnitude / radius
	if near <= 0 then return end
	local amount = strength * near
	local token = os.clock()
	shaking = token
	local started = os.clock()
	local link
	link = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > 0.4 or shaking ~= token then
			link:Disconnect()
			if shaking == token then humanoid.CameraOffset = Vector3.zero end
			return
		end
		local decay = (1 - t / 0.4) * amount
		humanoid.CameraOffset = Vector3.new(math.sin(t * 73) * decay, math.sin(t * 97) * decay * 0.7, 0)
	end)
end

local function grade(name, props, seconds)
	local effect = Lighting:FindFirstChild(name)
	if not effect then
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = name
		effect.Parent = Lighting
	end
	for k, v in pairs(props) do effect[k] = v end
	TweenService:Create(effect, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1),
	}):Play()
end

-- Dazzled by the eyespots: dazzle(seconds)
function Effects.dazzle(seconds)
	grade("VoxelRigDazzle", { Brightness = 0.7, Contrast = -0.4, Saturation = -0.3, TintColor = rgb(255, 245, 220) }, seconds)
end

-- Inked: ink(seconds)
function Effects.ink(seconds)
	grade("VoxelRigInk", { Brightness = -0.45, Contrast = 0.2, Saturation = -0.6, TintColor = rgb(150, 120, 200) }, seconds)
end

-- For tuning live from a client execute.
Effects.Styles = { bursts = BURSTS, casts = CASTS, shots = SHOTS, trails = TRAILS, cones = CONES, zones = ZONES, afflict = AFFLICT }

return Effects
