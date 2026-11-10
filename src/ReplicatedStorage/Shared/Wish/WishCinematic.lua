--[[
	WishCinematic

	The reveal that plays after a wish, client side. Results have already been
	granted by the server (WishService); this only shows them.

		WishCinematic.play(results)   -- yields until the player closes it
		WishCinematic.advance()       -- as a click would (gamepads, tests)

	THE BEATS - one thing on screen at a time, so it always reads

	  1. NIGHT FALLS. Letterbox bars slide in, the HUD goes, the camera lifts
	     into a violet night sky (the SoulShroud showcase skybox) with small
	     shooting stars crossing far away.
	  2. A STAR WAKES. A flash of light in the upper left, where it will come
	     from, with a rising tone.
	  3. THE METEOR. A big comet with a long tail crosses to the middle of the
	     screen in the colour of the best result - grey, green, blue, purple or
	     gold - and the whole sky is washed in that colour. A ten-wish brings
	     two smaller companions in the next colours down. The camera leans
	     after it.
	  4. IMPACT. Flash, radial burst, ring, spikes from Epic, the gold star
	     from Legendary; a shake, a punch of the lens, the screen flashes the
	     tier's colour and then white.
	  5. THE CARDS. Each result is a card in the middle of the screen. It
	     arrives face down in its tier's colour and charges (longer and harder
	     the rarer it is), then flips: the ability's icon, its name, its stars
	     popping in one at a time, NEW if it was not owned, and where it went.
	     Behind it the sky glows in its colour - a pillar of light from Rare,
	     star rays from Epic, a gold storm for a Legendary. Click for the next.
	  6. THE SUMMARY. A ten-wish ends on all ten, best first.

	Every beat has its sound (CombatSoundBank clips, played at the camera) and
	the music ducks under the whole thing.

	EVERY EFFECT IS A SOULSHROUD ASSEMBLY

	ReplicatedStorage.WishVFXLibrary (assets/vfx-library/WishVFXLibrary.rbxm,
	provenance in its .sources.json), mounted through PackAssembly: emitters,
	beams and flipbooks recoloured per tier, parts kept invisible. Nothing here
	draws a visible Part. The bars, the flashes and the cards are UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelUI = require(UI:WaitForChild("PixelUI"))
local ItemSprites = require(UI:WaitForChild("ItemSprites"))
local AbilityScope = require(Shared:WaitForChild("Abilities"):WaitForChild("AbilityScope"))
local AbilityConfig = require(Shared.Abilities:WaitForChild("AbilityConfig"))
local Pack = require(Shared.Abilities:WaitForChild("VFX"):WaitForChild("PackAssembly"))
local Audio = Shared:WaitForChild("Audio")
local CombatAudio = require(Audio:WaitForChild("CombatAudio"))
local Sounds = require(Audio:WaitForChild("Sounds"))
local Music = require(Audio:WaitForChild("Music"))
local DownloadedSounds = require(Audio:WaitForChild("DownloadedSounds"))
local WishConfig = require(script.Parent:WaitForChild("WishConfig"))

local player = Players.LocalPlayer

local Cinematic = {}

local library = ReplicatedStorage:WaitForChild("WishVFXLibrary", 10)

local active = false
-- Set by a press; the reveal consumes it. Also set by Cinematic.advance().
local advanceRequested = false

function Cinematic.advance()
	advanceRequested = true
end

function Cinematic.isPlaying(): boolean
	return active
end

-- ---------------------------------------------------------------------------
-- Tuning
-- ---------------------------------------------------------------------------

-- Recolours per tier for PackAssembly: deep end, main hue, hot end.
local TINT = {
	Common = { deep = Color3.fromRGB(58, 62, 78), main = Color3.fromRGB(205, 212, 226), hot = Color3.fromRGB(255, 255, 255) },
	Uncommon = { deep = Color3.fromRGB(16, 70, 34), main = Color3.fromRGB(110, 235, 120), hot = Color3.fromRGB(232, 255, 232) },
	Rare = { deep = Color3.fromRGB(10, 38, 120), main = Color3.fromRGB(64, 150, 255), hot = Color3.fromRGB(220, 240, 255) },
	Epic = { deep = Color3.fromRGB(52, 10, 96), main = Color3.fromRGB(184, 90, 255), hot = Color3.fromRGB(246, 222, 255) },
	Legendary = { deep = Color3.fromRGB(130, 62, 0), main = Color3.fromRGB(255, 194, 40), hot = Color3.fromRGB(255, 250, 222) },
}
local RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

-- Brighter than Theme's rarity colours, which are tuned for dark panels at
-- rest: these light a screen.
local GLOW = {
	Common = Color3.fromRGB(214, 220, 232),
	Uncommon = Color3.fromRGB(120, 230, 128),
	Rare = Color3.fromRGB(70, 156, 255),
	Epic = Color3.fromRGB(186, 96, 255),
	Legendary = Color3.fromRGB(255, 200, 48),
}

-- The ability's picture on its card, from the item icon atlas.
local ICONS = {
	Fireball = "tome_fire",
	WindBurst = "feather",
	WaterBlade = "tome_water",
	EchoStep = "potion_swiftness",
	BlockWall = "shield_iron",
	Dawnbreaker = "sun_charm",
	Deluge = "orb_water",
	SkyfallVolley = "arrows_holy",
	SumiWhirl = "orb_shadow",
	BlossomRoad = "fireblossom",
	HeliosLance = "tome_holy",
	AbyssGate = "tome_void",
	AzureComet = "fallen_star",
	Thunderhead = "tome_lightning",
	Tidecaller = "crystal_ball_frost",
	SerpentFlare = "orb_magma",
	AstralVerdict = "orb_light",
	VioletTempest = "tome_arcane",
	CelestialLance = "moon_charm_gold",
	WraithfireOrb = "orb_crimson",
	RiftMaelstrom = "void_core",
	Cataclysm = "tome_blood",
}
local FALLBACK_ICON = "scroll_arcane"

-- The violet night of the SoulShroud pack's own showcase place.
local NIGHT_SKY = {
	SkyboxBk = "rbxassetid://18351376859",
	SkyboxDn = "rbxassetid://18351374919",
	SkyboxFt = "rbxassetid://18351376800",
	SkyboxLf = "rbxassetid://18351376469",
	SkyboxRt = "rbxassetid://18351376457",
	SkyboxUp = "rbxassetid://18351377189",
	StarCount = 3000,
	CelestialBodiesShown = false,
}

-- How far in front of the camera the meteor lands and the cards hang.
local FOCUS = 95
local METEOR_TIME = { Common = 1.6, Uncommon = 1.6, Rare = 1.75, Epic = 1.95, Legendary = 2.3 }
local METEOR_SCALE = { Common = 1.6, Uncommon = 1.8, Rare = 2.0, Epic = 2.4, Legendary = 2.9 }
-- How long a card lies face down, charging, before it turns over.
local CHARGE = { Common = 0.35, Uncommon = 0.45, Rare = 0.6, Epic = 0.85, Legendary = 1.25 }

local CARD_W, CARD_H = 300, 420

-- The resting grade: a little cool, so the dusk reads as night.
local NIGHT_GRADE = Color3.fromRGB(225, 232, 255)

-- ---------------------------------------------------------------------------
-- Sound: each beat a short stack of bank clips, played at the camera
-- ---------------------------------------------------------------------------

-- { bank key, volume, pitch, delay }
local SFX = {
	open = { { "magic_warp", 0.5, 0.9 }, { "ability_magic_glow", 0.35, 0.8, 0.15 } },
	wake = { { "sparkle", 0.5, 0.8 }, { "power_up", 0.45, 0.9, 0.05 } },
	launch = { { "explosive_whoosh", 0.65, 0.85 }, { "swish_rise", 0.4, 0.75, 0.1 }, { "plasma_trail", 0.3, 0.7, 0.15 } },
	launchBig = { { "charge_short", 0.45, 0.7 }, { "ability_charge", 0.35, 0.9, 0.1 } },
	impact = {
		Common = { { "star_impact", 0.55, 1.0 }, { "poof_air", 0.4, 0.9 }, { "sparkle", 0.4, 1.0, 0.05 } },
		Uncommon = { { "star_impact", 0.55, 1.05 }, { "poof_punch", 0.4, 0.9 }, { "sparkle", 0.45, 1.1, 0.05 } },
		Rare = { { "starbar_impact", 0.6, 1.0 }, { "boom_deep1", 0.45, 1.0 }, { "sparkle", 0.45, 1.0, 0.08 } },
		Epic = { { "cine_hit", 0.6, 1.0 }, { "string_hit1", 0.5, 1.0 }, { "boom_deep2", 0.5, 0.95 }, { "sparkle", 0.5, 0.9, 0.1 } },
		Legendary = {
			{ "cine_hit", 0.75, 0.95 }, { "orchestra_hit", 0.65, 1.0 }, { "bass_drop", 0.6, 1.0 },
			{ "ring_hit", 0.5, 1.0, 0.05 }, { "distant_boom", 0.45, 1.0, 0.1 }, { "power_on", 0.35, 1.1, 0.35 },
		},
	},
	arrive = { { "poof_air", 0.4, 1.15 }, { "whoosh_thick", 0.3, 1.2 } },
	charge = {
		Common = {}, Uncommon = {},
		Rare = { { "recharge", 0.3, 1.2 } },
		Epic = { { "recharge", 0.35, 1.0 }, { "electric_hum", 0.25, 1.2 } },
		Legendary = { { "ability_charge", 0.45, 1.1 }, { "power_up", 0.4, 1.0, 0.2 } },
	},
	flip = { { "whoosh_thick", 0.45, 1.15 }, { "swing_air", 0.35, 1.3 } },
	reveal = {
		Common = { { "orb_chime", 0.45, 1.0 } },
		Uncommon = { { "orb_chime", 0.5, 1.1 }, { "sparkle", 0.4, 1.1 } },
		Rare = { { "starbar_impact", 0.5, 1.05 }, { "orb_chime", 0.45, 1.15, 0.05 } },
		Epic = { { "string_hit1", 0.55, 1.0 }, { "star_impact", 0.5, 1.0 }, { "orb_chime", 0.45, 1.2, 0.1 } },
		Legendary = {
			{ "orchestra_hit", 0.65, 1.0 }, { "ring_hit", 0.55, 1.0, 0.05 }, { "bass_drop", 0.5, 1.0 },
			{ "ability_magic_glow", 0.45, 1.1, 0.2 }, { "sparkle", 0.5, 1.2, 0.3 },
		},
	},
	new = { { "kill_pop", 0.5, 1.4 }, { "sparkle", 0.35, 1.5, 0.04 } },
	card = { { "whoosh_thick", 0.18, 1.35 } },
	summary = { { "orb_chime", 0.5, 0.9 }, { "starbar_impact", 0.35, 1.15, 0.05 } },
	close = { { "magic_warp", 0.3, 1.3 } },
}

local function sfx(layers, pitchScale)
	local camera = workspace.CurrentCamera
	for _, layer in ipairs(layers or {}) do
		local key, volume, pitch, delay = layer[1], layer[2], (layer[3] or 1) * (pitchScale or 1), layer[4] or 0
		local function go()
			CombatAudio.play(key, camera.CFrame.Position, volume, pitch, false, { near = 80, throttle = 0 })
		end
		if delay > 0 then
			task.delay(delay, go)
		else
			go()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Assets
-- ---------------------------------------------------------------------------

local function template(name)
	return library and library:FindFirstChild(name)
end

-- The Pillar's light-shaft beam, whose neutral texture the meteor tails
-- borrow: Starfall's own streak texture is blue in itself and turns green
-- under gold.
local shaftTexture = nil
do
	local pillar = template("Pillar")
	for _, beam in ipairs(pillar and pillar:GetDescendants() or {}) do
		if beam:IsA("Beam") and string.find(beam.Texture, "83970701945780", 1, true) then
			shaftTexture = beam
			break
		end
	end
end

-- Starts the library, the sky and the icons loading; the banner calls this
-- when it opens.
function Cinematic.preload()
	task.spawn(function()
		local list = {}
		if library then
			table.insert(list, library)
		end
		for _, id in pairs(NIGHT_SKY) do
			if type(id) == "string" then
				table.insert(list, id)
			end
		end
		table.insert(list, Theme.ItemAtlas)
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
	CombatAudio.preload()
end

local function mount(scope, stage, name, options)
	options = options or {}
	options.template = template(name)
	return Pack.mount(scope, stage, name, options)
end

-- ---------------------------------------------------------------------------
-- The night: sky, clock and grade held locally for the cinematic
-- ---------------------------------------------------------------------------

local function holdNight(scope)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local sky = Lighting:FindFirstChildOfClass("Sky")
	local saved = { clock = Lighting.ClockTime, exposure = Lighting.ExposureCompensation }
	local savedAir = atmosphere and { density = atmosphere.Density, haze = atmosphere.Haze, glare = atmosphere.Glare }
	local savedSky = {}
	if sky then
		for property, value in pairs(NIGHT_SKY) do
			savedSky[property] = sky[property]
			sky[property] = value
		end
	end

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "WishGrade"
	grade.TintColor = NIGHT_GRADE
	grade.Saturation = 0.15
	grade.Contrast = 0.15
	grade.Parent = Lighting
	scope:add(grade)

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "WishBloom"
	bloom.Intensity = 0.7
	bloom.Size = 36
	bloom.Threshold = 1.5
	bloom.Parent = Lighting
	scope:add(bloom)

	-- Every frame, because the server's day cycle replicates a new clock four
	-- times a second and would otherwise pull the sun back up mid-meteor.
	RunService:BindToRenderStep("WishNight", Enum.RenderPriority.First.Value, function()
		-- BiomeSky may set its own skybox on a biome change; keep ours.
		if sky and sky.SkyboxBk ~= NIGHT_SKY.SkyboxBk then
			for property, value in pairs(NIGHT_SKY) do
				sky[property] = value
			end
		end
		-- Dusk, not midnight: at midnight a custom skybox renders black, and
		-- this one (anime clouds) then shows as a void. At 18.3 the clouds stand
		-- dark on a navy sky with stars, and the effects, which ignore lighting,
		-- keep their full colour.
		Lighting.ClockTime = 18.3
		Lighting.ExposureCompensation = 0.1
		if atmosphere then
			atmosphere.Density = 0
			atmosphere.Haze = 0
			atmosphere.Glare = 0
		end
	end)

	scope:add(function()
		RunService:UnbindFromRenderStep("WishNight")
		Lighting.ClockTime = saved.clock
		Lighting.ExposureCompensation = saved.exposure
		if atmosphere and savedAir then
			atmosphere.Density, atmosphere.Haze, atmosphere.Glare = savedAir.density, savedAir.haze, savedAir.glare
		end
		if sky then
			for property, value in pairs(savedSky) do
				sky[property] = value
			end
		end
	end)

	return grade
end

-- ---------------------------------------------------------------------------
-- The stage: everything else on screen hidden, the character still
-- ---------------------------------------------------------------------------

local function takeStage(scope, ownGui)
	local playerGui = player:WaitForChild("PlayerGui")
	-- Checked every frame: some HUD scripts turn their own gui back on when
	-- they update, and a health bar over the meteor spoils it.
	local hidden = {}
	local function hideAll()
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("ScreenGui") and gui ~= ownGui and gui.Enabled then
				gui.Enabled = false
				hidden[gui] = true
			end
		end
	end
	hideAll()
	scope:add(RunService.Heartbeat:Connect(hideAll))
	scope:add(function()
		for gui in pairs(hidden) do
			if gui.Parent then
				gui.Enabled = true
			end
		end
	end)

	local core = {}
	for _, kind in ipairs({ Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health }) do
		local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, kind)
		if ok and enabled then
			table.insert(core, kind)
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, false)
		end
	end
	scope:add(function()
		for _, kind in ipairs(core) do
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, true)
		end
	end)

	-- Held in place for the reveal; the root is ours to anchor, and anchoring
	-- it locally keeps it where it is for everyone.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and not root.Anchored then
		root.Anchored = true
		scope:add(function()
			if root.Parent then
				root.Anchored = false
			end
		end)
	end

	local camera = workspace.CurrentCamera
	local savedType, savedFov = camera.CameraType, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	scope:add(function()
		camera.FieldOfView = savedFov
		camera.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
	end)

	-- The music steps back for the whole cinematic, and a quiet night bed
	-- plays under it.
	local duckUntil = 0
	scope:add(RunService.Heartbeat:Connect(function()
		if os.clock() > duckUntil then
			duckUntil = os.clock() + 0.5
			Music.duck(0.85, 1)
		end
	end))
	local bed = Instance.new("Sound")
	bed.Name = "WishNightBed"
	bed.SoundId = DownloadedSounds.ambience_night
	bed.Looped = true
	bed.Volume = 0
	bed.Parent = SoundService
	bed:Play()
	TweenService:Create(bed, TweenInfo.new(1.2), { Volume = Sounds.volume(0.22) }):Play()
	scope:add(bed)

	return root
end

-- ---------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------
-- Bright glitter, from GoldStar's sparkle dust: the template every shooting
-- star clones to shed sparks along its path.
local glitterTemplate = nil
do
	local star = template("GoldStar")
	for _, emitter in ipairs(star and star:GetDescendants() or {}) do
		if emitter:IsA("ParticleEmitter") and string.find(emitter.Texture, "113947103542396", 1, true) then
			glitterTemplate = emitter
			break
		end
	end
end

-- A point on the quadratic curve from `a` through the pull of `b` to `c`,
-- and the way it is heading there.
local function curve(a, b, c, t)
	local u = 1 - t
	local position = a * (u * u) + b * (2 * u * t) + c * (t * t)
	local heading = (b - a) * (2 * u) + (c - b) * (2 * t)
	return position, if heading.Magnitude > 1e-3 then heading.Unit else (c - a).Unit
end

--[[
	One layer of a tail: a chain of Beams, each from one point to the next, the
	points shared so the chain is one unbroken ribbon. Width, colour and
	opacity are set per link from `f`, 0 at the head and 1 at the tip.

	Beams, not Trails: a Trail here only ever drew its newest sliver, and a
	chain laid along the star's own curve also follows the arc exactly at any
	frame rate.
]]
local function tailLayer(anchor, count, props)
	local points = {}
	for i = 0, count do
		local point = Instance.new("Attachment")
		point.Parent = anchor
		points[i] = point
	end
	for i = 1, count do
		local f0, f1 = (i - 1) / count, i / count
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = points[i - 1], points[i]
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Brightness = props.brightness or 1
		beam.Width0 = props.width * (1 - f0) ^ props.taper
		beam.Width1 = props.width * (1 - f1) ^ props.taper
		beam.Color = ColorSequence.new(props.color(f0), props.color(f1))
		beam.Transparency = NumberSequence.new(props.alpha(f0), props.alpha(f1))
		if props.texture then
			beam.Texture = props.texture.Texture
			beam.TextureMode = Enum.TextureMode.Stretch
			beam.TextureLength = 1
			beam.TextureSpeed = props.texture.TextureSpeed
		end
		beam.Parent = anchor
	end
	return { points = points, count = count, span = props.span }
end

-- The tier's colour along a tail: white-hot at the head, deep at the tip.
local function tailColour(tint)
	return function(f)
		if f < 0.2 then
			return tint.hot:Lerp(tint.main, f / 0.2)
		end
		return tint.main:Lerp(tint.deep, (f - 0.2) / 0.8)
	end
end

--[[
	A shooting star from `from` to `to` over `duration`, on a curve that
	bulges up by `arc` studs, speeding up as it falls.

	  HEAD    GoldStar's four-pointed glint (its camera-facing layers only, so
	          no stray wedges), tinted to the tier - gold as it is for a
	          Legendary - in a soft Flash halo.
	  TAIL    four Beam chains laid back along the curve the star has just
	          flown (the last `span` of its flight): a white-hot core, a body in
	          the tier's colour, the Pillar's flowing light-shaft texture over
	          it, and a wide faint glow, all tapering to a point. It grows out
	          of the start, and folds into the landing point when it lands.
	  GLITTER GoldStar's sparkle dust, cloned onto a host that rides the head,
	          left behind in the world to drift and fall off the tail.

	`lite` (the far shooting stars) keeps the core, the body and a little
	glitter. `onMove(position)` hears where the head is every frame. Returns
	a function saying whether it has landed.
]]
local function meteor(scope, stage, from, to, duration, rarity, scale, onMove, options)
	options = options or {}
	local tint = TINT[rarity]
	local rank = RANK[rarity]
	local lite = options.lite == true
	local span = options.span or (if lite then 0.35 else 0.42)
	local count = if lite then 8 else 16

	local function part(name)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.CFrame = CFrame.new(from)
		p.Parent = stage
		scope:add(p)
		return p
	end
	local anchor = part("ShootingStarTail")
	local host = part("ShootingStar")

	local colour = tailColour(tint)
	local layers = {
		tailLayer(anchor, count, {
			width = 0.9 * scale, taper = 1, brightness = 3,
			color = function(f) return Color3.new(1, 1, 1):Lerp(tint.hot, f) end,
			alpha = function(f) return math.min(1, f ^ 0.7) end,
		}),
		tailLayer(anchor, count, {
			width = 2.6 * scale, taper = 1.1, brightness = 2,
			color = colour,
			alpha = function(f) return 0.05 + 0.95 * f ^ 1.4 end,
		}),
	}
	if not lite then
		-- A soft glow round the first stretch of tail; short, so the joins of
		-- its wide links never show as seams further back.
		table.insert(layers, tailLayer(anchor, 5, {
			width = 5 * scale, taper = 1.4, brightness = 1,
			color = function() return tint.main end,
			alpha = function(f) return 0.55 + 0.45 * f end,
			span = 0.08,
		}))
	end

	local glitter
	if glitterTemplate then
		glitter = glitterTemplate:Clone()
		glitter.Enabled = true
		glitter.LockedToPart = false
		glitter.LightEmission = 1
		glitter.LightInfluence = 0
		glitter.Rate = (if lite then 40 else 140 + rank * 30) * math.max(scale, 0.4)
		glitter.Lifetime = NumberRange.new(0.6, 1.4)
		glitter.Speed = NumberRange.new(0.5 * scale, 4 * scale)
		glitter.SpreadAngle = Vector2.new(180, 180)
		glitter.Drag = 2.5
		glitter.Acceleration = Vector3.new(0, -5 * scale, 0)
		glitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45 * scale),
			NumberSequenceKeypoint.new(0.4, 0.3 * scale),
			NumberSequenceKeypoint.new(1, 0),
		})
		glitter.Color = ColorSequence.new(tint.hot, tint.main)
		glitter.Parent = host
	end

	local handles = {}
	if not lite then
		local halo = mount(scope, stage, "Flash", { tint = tint, scale = 0.7 * scale, billboard = true, budget = 30, brightness = 2 })
		halo:stream(true)
		table.insert(handles, halo)
		local glint = mount(scope, stage, "GoldStar", {
			tint = if rank >= 5 then nil else tint,
			scale = 0.26 * scale,
			budget = 200,
		})
		-- Only the glint's camera-facing light: its velocity-aligned layers
		-- draw as stray wedges in flight, and its black layers as smudges.
		for i = #glint.emitters, 1, -1 do
			local emitter = glint.emitters[i].v
			local c = emitter.Color.Keypoints[1].Value
			if emitter.Orientation ~= Enum.ParticleOrientation.FacingCamera or math.max(c.R, c.G, c.B) < 0.1 then
				table.remove(glint.emitters, i)
			end
		end
		glint:stream(true)
		table.insert(handles, glint)
	end

	local arc = options.arc or (from - to).Magnitude * 0.25
	local bend = (from + to) / 2 + Vector3.yAxis * arc
	local function at(t)
		return curve(from, bend, to, 0.4 * t + 0.6 * t * t)
	end
	local function layTail(head, fold)
		for _, layer in ipairs(layers) do
			local points, links, length = layer.points, layer.count, layer.span or span
			for k = 0, links do
				local back = math.clamp(head - k * length / links * (1 - fold), 0, 1)
				points[k].WorldPosition = at(back)
			end
		end
	end
	layTail(0, 0)

	local started = os.clock()
	local done = false
	local landedAt = nil
	local connection
	connection = scope:add(RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / duration, 0, 1)
		-- Studio QA: hold the star part way to capture it in flight.
		t = math.min(t, workspace:GetAttribute("WishTestFreezeAt") or 1)
		local position, heading = at(t)
		host.CFrame = CFrame.lookAt(position, position + heading)
		for _, handle in ipairs(handles) do
			handle.model:PivotTo(CFrame.new(position))
		end
		if onMove and not done then
			onMove(position)
		end

		if t >= 1 and not done then
			done = true
			landedAt = os.clock()
			if glitter then
				glitter.Enabled = false
			end
			for _, handle in ipairs(handles) do
				handle:stream(false)
			end
		end
		-- Landed: the tail folds into the landing point over a quarter second.
		local fold = if landedAt then math.clamp((os.clock() - landedAt) / 0.25, 0, 1) else 0
		layTail(t, fold)
		if fold >= 1 then
			connection:Disconnect()
			anchor:Destroy()
			scope:delay(2, function()
				host:Destroy()
				for _, handle in ipairs(handles) do
					handle.model:Destroy()
				end
			end)
		end
	end))
	return function()
		return done
	end
end


--[[
	The landing at `at`, scaled with the tier: a flash, a radial burst and a
	ring for all; spikes from Epic; the gold star and a sparkling orb for a
	Legendary. `size` scales the lot.
]]
local function impact(scope, stage, at, rarity, size)
	local tint = TINT[rarity]
	local rank = RANK[rarity]
	local frame = CFrame.new(at)

	mount(scope, stage, "Flash", { cframe = frame, scale = (1.8 + rank * 0.35) * size, tint = tint, billboard = true }):burst(3)
	mount(scope, stage, "RadialBurst", { cframe = frame, scale = (1.6 + rank * 0.35) * size, tint = tint }):burst(1.8)
	mount(scope, stage, "RingBurst", { cframe = frame, scale = (2.6 + rank * 0.5) * size, tint = tint, billboard = true }):burst(1.6)
	if rank >= 4 then
		mount(scope, stage, "Spikes", { cframe = frame, scale = 2.8 * size, tint = tint }):burst(1.5)
	end
	if rank >= 5 then
		mount(scope, stage, "GoldStar", { cframe = frame, scale = 3.4 * size }):burst(1.6)
		mount(scope, stage, "GoldOrb", { cframe = frame, scale = 2.2 * size }):burst(2)
	end
end

--[[
	What glows in the sky behind a card, in its tier's colour: a soft halo for
	all, a pillar of light from Rare, star rays from Epic, a gold storm of
	sparkles for a Legendary. It frames the card rather than sitting under it.
	Returns a function that clears it.
]]
local function aura(scope, stage, at, rarity)
	local tint = TINT[rarity]
	local rank = RANK[rarity]
	local frame = CFrame.new(at + Vector3.new(0, 0, 0))
	local handles = {}
	local function keep(handle)
		table.insert(handles, handle)
		return handle
	end

	local halo = keep(mount(scope, stage, "Flash", { cframe = frame, scale = 2.6 + rank * 0.35, tint = tint, billboard = true, budget = 60, brightness = 1.6 }))
	halo:stream(true)

	if rank >= 3 then
		local pillar = keep(mount(scope, stage, "Pillar", { tint = if rank >= 5 then nil else tint, scale = 1.5 + rank * 0.15, budget = 500 }))
		-- Its first part is the top of the shaft: above the card, so the light
		-- pours down behind it and shows above and below.
		pillar:alignPart("Part", CFrame.new(0, 58, -6))
		pillar:place(frame)
		pillar:stream(true)
		pillar:beamsOn(true)
	end
	if rank == 3 or rank == 4 then
		keep(mount(scope, stage, "GoldStar", { cframe = frame, scale = if rank == 4 then 2.6 else 2.0, budget = if rank == 4 then 120 else 80, tint = tint })):stream(true)
	elseif rank >= 5 then
		keep(mount(scope, stage, "GoldStar", { cframe = frame, scale = 3.4, budget = 180 })):stream(true)
		keep(mount(scope, stage, "GoldOrb", { cframe = frame, scale = 2.6, budget = 300 })):stream(true)
	end

	return function()
		for _, handle in ipairs(handles) do
			handle:stream(false)
			handle:beamsOn(false)
			local model = handle.model
			task.delay(1.6, function()
				model:Destroy()
			end)
		end
	end
end

-- Little far-off shooting stars crossing the night while it waits.
local function shootingStar(scope, stage, focus, right, up, look)
	local side = if math.random() < 0.5 then -1 else 1
	local from = focus + right * side * (60 + math.random() * 90) + up * (45 + math.random() * 35) + look * (80 + math.random() * 120)
	local to = from + right * -side * (60 + math.random() * 50) - up * (30 + math.random() * 20)
	meteor(scope, stage, from, to, 0.6 + math.random() * 0.35, "Common", 0.4, nil, { lite = true, arc = 6 })
end

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

local function tween(object, time, goals, style, direction)
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goals)
	t:Play()
	return t
end

local function label(parent, props)
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.FontFace = props.font or Theme.Fonts.Heading
	text.TextColor3 = props.color or Color3.new(1, 1, 1)
	text.TextStrokeColor3 = props.stroke or Color3.fromRGB(10, 8, 20)
	text.TextStrokeTransparency = props.strokeT or 0.2
	text.TextSize = props.size or 24
	text.Text = props.text or ""
	text.TextXAlignment = props.align or Enum.TextXAlignment.Center
	text.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	text.Size = props.box or UDim2.new(1, 0, 0, (props.size or 24) + 6)
	text.Position = props.at or UDim2.new()
	text.AnchorPoint = props.anchor or Vector2.zero
	text.TextWrapped = props.wrap or false
	text.ZIndex = props.z or 5
	text.Parent = parent
	return text
end

-- The four-pointed star from the top-bar button, a Frame per texel, in any
-- colour: the pixel kit's own icons carry fixed colours that tint badly.
local STAR_SPRITE = {
	".....##.....",
	".....##.....",
	"....####....",
	"....####....",
	"############",
	".##########.",
	"...######...",
	"..########..",
	"..###..###..",
	".##......##.",
	".#........#.",
}
local function pixelStar(parent, color, size, z)
	local field = Instance.new("Frame")
	field.Name = "Emblem"
	field.BackgroundTransparency = 1
	field.Size = UDim2.fromOffset(size, size * #STAR_SPRITE / #STAR_SPRITE[1])
	field.ZIndex = z or 4
	field.Parent = parent
	local rows, columns = #STAR_SPRITE, #STAR_SPRITE[1]
	for row, line in ipairs(STAR_SPRITE) do
		for column = 1, columns do
			if string.sub(line, column, column) == "#" then
				local pixel = Instance.new("Frame")
				pixel.BackgroundColor3 = color
				pixel.BorderSizePixel = 0
				pixel.Position = UDim2.fromScale((column - 1) / columns, (row - 1) / rows)
				pixel.Size = UDim2.fromScale(1 / columns, 1 / rows)
				pixel.ZIndex = z or 4
				pixel.Parent = field
			end
		end
	end
	return field
end

-- The ability's picture, off the item icon atlas, drawn pixelated.
local function abilityIcon(parent, name, size, z)
	local sprite = ItemSprites.Sprites[ICONS[name] or FALLBACK_ICON] or ItemSprites.Sprites[FALLBACK_ICON]
	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.BackgroundTransparency = 1
	image.Image = Theme.ItemAtlas
	image.ImageRectOffset = sprite.offset
	image.ImageRectSize = sprite.size
	image.ResampleMode = Enum.ResamplerMode.Pixelated
	image.Size = UDim2.fromOffset(size, size)
	image.ZIndex = z or 6
	image.Parent = parent
	return image
end

local function starRow(parent, count, size, color, z)
	local row = Instance.new("Frame")
	row.Name = "Stars"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(count * (size + 6) - 6, size)
	row.ZIndex = z or 6
	row.Parent = parent
	local stars = {}
	for i = 1, count do
		local star = PixelUI.image(row, "icon_star")
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromOffset((i - 1) * (size + 6) + size / 2, size / 2)
		star.Size = UDim2.fromOffset(size, size)
		star.ImageColor3 = color
		star.ZIndex = (z or 6) + 1
		stars[i] = star
	end
	return row, stars
end

local function gradient(parent, top, bottom, rotation)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = parent
	return g
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WishCinematic"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Everything inside `root` is laid out for 1280x720 and scaled to fit.
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(1280, 720)
	root.ZIndex = 2
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function rescale()
		local view = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(view.X / 1280, view.Y / 720), 0.42, 1.5)
	end
	rescale()

	-- Cinematic bars and a darkened edge: it is a cutscene, and the eye goes
	-- to the middle.
	local bars = {}
	for i, anchor in ipairs({ 0, 1 }) do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0, anchor)
		bar.Position = UDim2.fromScale(0, anchor)
		bar.Size = UDim2.new(1, 0, 0, 0)
		bar.ZIndex = 15
		bar.Parent = gui
		bars[i] = bar
	end
	for i, spec in ipairs({
		{ size = UDim2.fromScale(1, 0.32), at = UDim2.fromScale(0, 0), rot = 90 },
		{ size = UDim2.fromScale(1, 0.32), at = UDim2.fromScale(0, 0.68), rot = -90 },
		{ size = UDim2.fromScale(0.22, 1), at = UDim2.fromScale(0, 0), rot = 0 },
		{ size = UDim2.fromScale(0.22, 1), at = UDim2.fromScale(0.78, 0), rot = 180 },
	}) do
		local edge = Instance.new("Frame")
		edge.Name = "Vignette" .. i
		edge.BackgroundColor3 = Color3.new(0, 0, 0)
		edge.BorderSizePixel = 0
		edge.Size = spec.size
		edge.Position = spec.at
		edge.ZIndex = 1
		edge.Parent = gui
		local fadeEdge = Instance.new("UIGradient")
		fadeEdge.Rotation = spec.rot
		fadeEdge.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1),
		})
		fadeEdge.Parent = edge
	end

	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BorderSizePixel = 0
	fade.Size = UDim2.fromScale(1, 1)
	fade.ZIndex = 20
	fade.Parent = gui

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 19
	flash.Parent = gui

	-- The whole screen is the "next" button.
	local clicker = Instance.new("TextButton")
	clicker.Name = "Next"
	clicker.BackgroundTransparency = 1
	clicker.Text = ""
	clicker.Size = UDim2.fromScale(1, 1)
	clicker.ZIndex = 1
	clicker.Modal = true
	clicker.Parent = gui

	local cards = Instance.new("Frame")
	cards.Name = "Cards"
	cards.BackgroundTransparency = 1
	cards.Size = UDim2.fromScale(1, 1)
	cards.ZIndex = 3
	cards.Parent = root

	local hint = label(root, {
		text = "Click to continue", size = 18, font = Theme.Fonts.BodyBold,
		color = Color3.fromRGB(220, 226, 255),
		at = UDim2.new(0.5, 0, 1, -34), anchor = Vector2.new(0.5, 0), box = UDim2.fromOffset(400, 24), z = 16,
	})
	hint.Visible = false
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		hint.Text = "Tap to continue"
	end

	local counter = label(root, {
		text = "", size = 20, font = Theme.Fonts.BodyBold, color = Color3.fromRGB(220, 226, 255),
		align = Enum.TextXAlignment.Left, at = UDim2.fromOffset(32, 64), box = UDim2.fromOffset(160, 24), z = 16,
	})

	local skip = PixelUI.button(root, { text = "Skip", size = UDim2.fromOffset(110, 42), color = "tan" })
	skip.button.Name = "Skip"
	skip.button.AnchorPoint = Vector2.new(1, 0)
	skip.button.Position = UDim2.new(1, -28, 0, 58)
	skip.button.ZIndex = 16
	skip.button.Visible = false

	return {
		gui = gui, root = root, fade = fade, flash = flash, clicker = clicker, bars = bars,
		cards = cards, hint = hint, skip = skip, counter = counter, rescale = rescale,
	}
end

local function showBars(view, on)
	for _, bar in ipairs(view.bars) do
		tween(bar, 0.5, { Size = UDim2.new(1, 0, if on then 0.085 else 0, 0) })
	end
end

--[[
	A card in the middle of the screen, face down in its tier's colour. Returns
	its parts; `turn(card)` flips it.
]]
local function buildCard(view, result)
	local color = GLOW[result.rarity] or Theme.rarityColor(result.rarity)
	local count = WishConfig.Stars[result.rarity] or 1

	local holder = Instance.new("Frame")
	holder.Name = "Card"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.48)
	holder.Size = UDim2.fromOffset(CARD_W, CARD_H)
	holder.ZIndex = 4
	holder.Parent = view.cards
	local grow = Instance.new("UIScale")
	grow.Scale = 0.2
	grow.Parent = holder

	-- The back: the tier's colour, a big star, the tier's stars.
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, 0.5)
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BorderSizePixel = 0
	back.ClipsDescendants = true
	back.ZIndex = 4
	back.Parent = holder
	gradient(back, color:Lerp(Color3.new(1, 1, 1), 0.15), color:Lerp(Color3.new(0, 0, 0), 0.55))
	local backEdge = Instance.new("UIStroke")
	backEdge.Color = color:Lerp(Color3.new(1, 1, 1), 0.45)
	backEdge.Thickness = 5
	backEdge.Parent = back
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -28, 1, -28)
	inner.ZIndex = 5
	inner.Parent = back
	local innerEdge = Instance.new("UIStroke")
	innerEdge.Color = Color3.new(1, 1, 1)
	innerEdge.Transparency = 0.55
	innerEdge.Thickness = 2
	innerEdge.Parent = inner
	local emblem = pixelStar(back, Color3.new(1, 1, 1), 150, 6)
	emblem.AnchorPoint = Vector2.new(0.5, 0.5)
	emblem.Position = UDim2.fromScale(0.5, 0.44)
	local backStars = starRow(back, count, 26, Color3.new(1, 1, 1), 6)
	backStars.AnchorPoint = Vector2.new(0.5, 0)
	backStars.Position = UDim2.fromScale(0.5, 0.76)

	-- The front: the ability.
	local front = Instance.new("Frame")
	front.Name = "Front"
	front.AnchorPoint = Vector2.new(0.5, 0.5)
	front.Position = UDim2.fromScale(0.5, 0.5)
	front.Size = UDim2.fromScale(0, 1)
	front.BackgroundColor3 = Color3.new(1, 1, 1)
	front.BorderSizePixel = 0
	front.ClipsDescendants = true
	front.Visible = false
	front.ZIndex = 4
	front.Parent = holder
	gradient(front, Color3.fromRGB(22, 20, 40), color:Lerp(Color3.fromRGB(22, 20, 40), 0.45))
	local frontEdge = Instance.new("UIStroke")
	frontEdge.Color = color
	frontEdge.Thickness = 5
	frontEdge.Parent = front

	local rarityText = label(front, {
		text = string.upper(result.rarity), size = 20, color = color, font = Theme.Fonts.BodyBold,
		at = UDim2.new(0.5, 0, 0, 18), anchor = Vector2.new(0.5, 0), box = UDim2.new(1, -20, 0, 24),
	})
	rarityText.TextStrokeTransparency = 0

	-- A soft disc of the tier's colour behind the icon.
	local halo = Instance.new("Frame")
	halo.Name = "Halo"
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(0.5, 0.34)
	halo.Size = UDim2.fromOffset(190, 190)
	halo.BackgroundColor3 = color
	halo.BackgroundTransparency = 0.72
	halo.ZIndex = 5
	halo.Parent = front
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = halo

	local icon = abilityIcon(front, result.name, 150, 6)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.34)

	local name = label(front, {
		text = result.displayName or result.name, size = 34, wrap = true,
		at = UDim2.new(0.5, 0, 0.56, 0), anchor = Vector2.new(0.5, 0), box = UDim2.new(1, -28, 0, 80),
	})
	name.TextStrokeColor3 = color:Lerp(Color3.new(0, 0, 0), 0.6)
	name.TextStrokeTransparency = 0
	name.TextYAlignment = Enum.TextYAlignment.Top
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 34
	fit.Parent = name
	name.TextScaled = true

	local starsRow, stars = starRow(front, count, 28, Color3.fromRGB(255, 214, 72), 6)
	starsRow.AnchorPoint = Vector2.new(0.5, 0)
	starsRow.Position = UDim2.fromScale(0.5, 0.76)
	for _, star in ipairs(stars) do
		star.Size = UDim2.fromOffset(0, 0)
	end

	local definition = AbilityConfig.get(result.name)
	label(front, {
		text = if result.where == "loadout" then "Added to your loadout" else "Sent to ability storage (Tab)",
		size = 15, font = Theme.Fonts.BodyBold, color = Color3.fromRGB(214, 220, 240),
		at = UDim2.new(0.5, 0, 0.86, 0), anchor = Vector2.new(0.5, 0), box = UDim2.new(1, -20, 0, 18),
	})
	label(front, {
		text = definition and AbilityConfig.statsText(definition) or "", size = 14, font = Theme.Fonts.Body,
		color = Color3.fromRGB(170, 178, 204),
		at = UDim2.new(0.5, 0, 0.92, 0), anchor = Vector2.new(0.5, 0), box = UDim2.new(1, -20, 0, 16),
	})

	local badge
	if result.isNew then
		badge = Instance.new("Frame")
		badge.Name = "New"
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.BackgroundColor3 = Color3.fromRGB(255, 214, 72)
		badge.BorderSizePixel = 0
		badge.Position = UDim2.new(1, -18, 0, 18)
		badge.Rotation = 12
		badge.Size = UDim2.fromOffset(78, 30)
		badge.ZIndex = 9
		badge.Visible = false
		badge.Parent = holder
		local edge = Instance.new("UIStroke")
		edge.Color = Theme.PixelColor.Outline
		edge.Thickness = 3
		edge.Parent = badge
		label(badge, {
			text = "NEW!", size = 20, color = Theme.PixelColor.Ink, strokeT = 1,
			box = UDim2.fromScale(1, 1), z = 10,
		})
	end

	return {
		holder = holder, grow = grow, back = back, front = front, backEdge = backEdge, emblem = emblem,
		icon = icon, halo = halo, stars = stars, badge = badge, color = color,
	}
end

-- Turns the card over: the back folds to nothing, the front opens from it.
local function turn(card)
	tween(card.back, 0.12, { Size = UDim2.fromScale(0, 1.04) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
	card.back.Visible = false
	card.front.Visible = true
	tween(card.front, 0.18, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)
	card.grow.Scale = 1.12
	tween(card.grow, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- The ten together, best first, flying in one after another.
local function showSummary(view, results)
	view.cards:ClearAllChildren()
	local sorted = table.clone(results)
	table.sort(sorted, function(a, b)
		return (RANK[a.rarity] or 0) > (RANK[b.rarity] or 0)
	end)

	local width, height, gap = 108, 300, 10
	local total = #sorted * width + (#sorted - 1) * gap
	local row = Instance.new("Frame")
	row.Name = "Summary"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.48)
	row.Size = UDim2.fromOffset(total, height)
	row.ZIndex = 4
	row.Parent = view.cards

	for i, result in ipairs(sorted) do
		local color = GLOW[result.rarity] or Theme.rarityColor(result.rarity)
		local card = Instance.new("Frame")
		card.Name = "Card" .. i
		card.BackgroundColor3 = Color3.new(1, 1, 1)
		card.BorderSizePixel = 0
		card.AnchorPoint = Vector2.new(0, 0.5)
		card.Position = UDim2.new(0, (i - 1) * (width + gap), 0.5, 60)
		card.Size = UDim2.fromOffset(width, height)
		card.BackgroundTransparency = 1
		card.ZIndex = 4
		card.Parent = row
		gradient(card, Color3.fromRGB(22, 20, 40), color:Lerp(Color3.fromRGB(22, 20, 40), 0.35))

		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 3
		stroke.Transparency = 1
		stroke.Parent = card

		local halo = Instance.new("Frame")
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromScale(0.5, 0.36)
		halo.Size = UDim2.fromOffset(84, 84)
		halo.BackgroundColor3 = color
		halo.BackgroundTransparency = 1
		halo.ZIndex = 5
		halo.Parent = card
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = halo

		local icon = abilityIcon(card, result.name, 72, 6)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.36)

		local nameText = label(card, {
			text = result.displayName or result.name, size = 18, wrap = true,
			at = UDim2.new(0, 6, 1, -98), box = UDim2.new(1, -12, 0, 50), alignY = Enum.TextYAlignment.Bottom,
		})
		nameText.TextScaled = true
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = 18
		fit.Parent = nameText

		local count = WishConfig.Stars[result.rarity] or 1
		local stars = starRow(card, count, 13, Color3.fromRGB(255, 214, 72), 6)
		stars.AnchorPoint = Vector2.new(0.5, 0)
		stars.Position = UDim2.new(0.5, 0, 1, -36)

		if result.isNew then
			label(card, {
				text = "NEW", size = 15, color = Color3.fromRGB(255, 226, 120), font = Theme.Fonts.BodyBold,
				at = UDim2.fromOffset(0, 8), box = UDim2.new(1, 0, 0, 18), z = 7,
			})
		end

		for _, child in ipairs(card:GetDescendants()) do
			if child:IsA("TextLabel") then
				child.TextTransparency = 1
				child.TextStrokeTransparency = 1
			elseif child:IsA("ImageLabel") then
				child.ImageTransparency = 1
			end
		end
		task.delay(0.08 * i, function()
			sfx(SFX.card, 1 + i * 0.03)
			tween(card, 0.4, { Position = UDim2.new(0, (i - 1) * (width + gap), 0.5, 0), BackgroundTransparency = 0 }, Enum.EasingStyle.Back)
			tween(stroke, 0.4, { Transparency = 0 })
			tween(halo, 0.4, { BackgroundTransparency = 0.75 })
			for _, child in ipairs(card:GetDescendants()) do
				if child:IsA("TextLabel") then
					tween(child, 0.4, { TextTransparency = 0, TextStrokeTransparency = 0.3 })
				elseif child:IsA("ImageLabel") then
					tween(child, 0.4, { ImageTransparency = 0 })
				end
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- The whole thing
-- ---------------------------------------------------------------------------

function Cinematic.play(results)
	if active or type(results) ~= "table" or #results == 0 then
		return
	end
	active = true

	local scope = AbilityScope.new()
	local ok, err = pcall(function()
		local view = buildGui()
		scope:add(view.gui)
		view.gui.Parent = player:WaitForChild("PlayerGui")
		scope:add(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(view.rescale))

		-- What advances it: a press (click, tap, Enter/Space/A) and the Skip
		-- button. A press counts once, on the way down, and only while a card
		-- is waiting for it - so a held button cannot run through the cards.
		local skipping = false
		advanceRequested = false
		-- Studio QA: with workspace attribute WishTestHold set, only
		-- Cinematic.advance() moves it on (Studio can feed phantom gamepad input).
		local function press()
			if not workspace:GetAttribute("WishTestHold") then
				advanceRequested = true
			end
		end
		scope:add(view.clicker.MouseButton1Down:Connect(press))
		scope:add(view.skip.button.MouseButton1Click:Connect(function()
			if workspace:GetAttribute("WishTestHold") then
				return
			end
			skipping = true
			advanceRequested = true
		end))
		scope:add(UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA then
				press()
			end
		end))

		local function wait(seconds)
			local untilTime = os.clock() + seconds
			while os.clock() < untilTime and not skipping do
				RunService.RenderStepped:Wait()
			end
		end
		local function waitClick(minimum)
			wait(minimum or 0)
			if not skipping then
				advanceRequested = false
			end
			view.hint.Visible = true
			local started = os.clock()
			while not advanceRequested do
				view.hint.TextTransparency = 0.2 + 0.4 * (1 + math.sin((os.clock() - started) * 4)) / 2
				RunService.RenderStepped:Wait()
			end
			view.hint.Visible = false
			advanceRequested = false
		end

		local sorted = table.clone(results)
		table.sort(sorted, function(a, b)
			return (RANK[a.rarity] or 0) > (RANK[b.rarity] or 0)
		end)
		local best = sorted[1].rarity
		local bestRank = RANK[best]

		-- 1. Night falls.
		local root = takeStage(scope, view.gui)
		local grade = holdNight(scope)
		sfx(SFX.open)

		local camera = workspace.CurrentCamera
		local base = if root then root.Position else camera.CFrame.Position
		local flat = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		local eye = Vector3.new(base.X, math.max(base.Y + 320, 900), base.Z)
		local look = (flat + Vector3.new(0, 0.3, 0)).Unit
		local focus = eye + look * FOCUS
		local right = look:Cross(Vector3.yAxis).Unit
		local up = right:Cross(look).Unit

		local stage = Instance.new("Folder")
		stage.Name = "WishStage"
		stage.Parent = workspace
		scope:add(stage)

		-- The camera: a slow push in, leaning after whatever it is told to
		-- follow, with a shake and a lens punch when asked.
		local shakeUntil, shakeStrength = 0, 0
		local follow = nil
		local lean = look
		local push = 0
		local fov = 62
		camera.FieldOfView = fov
		RunService:BindToRenderStep("WishCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
			camera.CameraType = Enum.CameraType.Scriptable
			push = math.min(push + dt * 1.2, 10)
			local position = eye + look * push
			local want = look
			if follow then
				want = look:Lerp((follow - position).Unit, 0.22).Unit
			end
			lean = lean:Lerp(want, math.min(1, dt * 4)).Unit
			local wobble = CFrame.new()
			local now = os.clock()
			if now < shakeUntil then
				local k = (shakeUntil - now) * shakeStrength
				wobble = CFrame.Angles(math.rad(math.noise(now * 24, 1) * k), math.rad(math.noise(now * 24, 2) * k), math.rad(math.noise(now * 24, 3) * k * 0.5))
			end
			camera.FieldOfView = camera.FieldOfView + (fov - camera.FieldOfView) * math.min(1, dt * 5)
			camera.CFrame = CFrame.lookAt(position, position + lean) * wobble
		end)
		scope:add(function()
			RunService:UnbindFromRenderStep("WishCamera")
		end)
		local function shake(strength, duration)
			shakeStrength = strength / duration
			shakeUntil = os.clock() + duration
		end
		local function punch(amount)
			camera.FieldOfView = fov + amount
		end

		-- Far shooting stars until the real one comes.
		local quiet = false
		scope:spawn(function()
			while not quiet do
				shootingStar(scope, stage, focus, right, up, look)
				task.wait(0.45 + math.random() * 0.4)
			end
		end)

		showBars(view, true)
		tween(view.fade, 0.7, { BackgroundTransparency = 1 })
		view.skip.button.Visible = true
		wait(1.0)

		-- 2. A star wakes where the meteor will come from.
		-- High in the upper left and at about the depth it lands at, so it
		-- crosses the view and its whole tail shows, arcing down to the middle.
		local start = focus - right * 150 + up * 60 + look * 20
		local tint = GLOW[best]
		if not skipping then
			sfx(SFX.wake)
			mount(scope, stage, "Flash", { cframe = CFrame.new(start), scale = 2.6, tint = TINT.Common, billboard = true }):burst(2)
			mount(scope, stage, "RadialBurst", { cframe = CFrame.new(start), scale = 2, tint = TINT.Common }):burst(1)
			follow = start
			wait(0.55)
		end
		quiet = true

		-- 3. The meteor, in the colour of the best result.
		local landing = focus
		local flight = METEOR_TIME[best] * (workspace:GetAttribute("WishTestSlow") or 1)
		sfx(SFX.launch, if bestRank >= 5 then 0.85 else 1)
		if bestRank >= 4 then
			sfx(SFX.launchBig)
		end
		tween(grade, flight, { TintColor = NIGHT_GRADE:Lerp(tint, if bestRank >= 5 then 0.4 else 0.28) })
		local landed = meteor(scope, stage, start, landing, flight, best, METEOR_SCALE[best], function(position)
			follow = position
			if bestRank >= 5 then
				-- A Legendary rumbles all the way in.
				shakeStrength, shakeUntil = 3, os.clock() + 0.2
			end
		end, { arc = 30 })
		if #results >= 10 then
			for n = 2, 3 do
				local companion = sorted[n * 2 - 1] or sorted[n]
				local side = if n == 2 then 1 else -1
				local from = start + up * (side * 20) + right * (side * 14) - look * 15
				local to = landing + right * (18 * side) + up * (6 * side) - look * 8
				scope:delay(0.12 * n, function()
					meteor(scope, stage, from, to, flight - 0.08 * n, companion.rarity, 0.9, nil, { arc = 22 })
				end)
			end
		end
		while not landed() and not skipping do
			RunService.RenderStepped:Wait()
		end
		follow = nil

		-- 4. Impact.
		if not skipping then
			impact(scope, stage, landing, best, 1)
			sfx(SFX.impact[best])
			shake(if bestRank >= 5 then 3.2 else 1 + bestRank * 0.35, if bestRank >= 5 then 0.9 else 0.5)
			punch(if bestRank >= 5 then 14 else 6 + bestRank)
			view.flash.BackgroundColor3 = tint
			view.flash.BackgroundTransparency = 0.25
			tween(view.flash, 0.25, { BackgroundTransparency = 0.85 })
			wait(if bestRank >= 5 then 0.75 else 0.5)
			view.flash.BackgroundColor3 = Color3.new(1, 1, 1)
			tween(view.flash, 0.15, { BackgroundTransparency = 0 })
			wait(0.2)
		end
		view.flash.BackgroundColor3 = Color3.new(1, 1, 1)
		view.flash.BackgroundTransparency = 0

		-- 5. The cards, one at a time.
		local function reveal(result, index, total)
			view.cards:ClearAllChildren()
			view.counter.Text = if total > 1 then string.format("%d / %d", index, total) else ""
			local rarity = result.rarity
			local rank = RANK[rarity]
			local glow = GLOW[rarity]
			local clear = aura(scope, stage, focus, rarity)
			tween(grade, 0.4, { TintColor = NIGHT_GRADE:Lerp(glow, 0.2) })
			tween(view.flash, 0.4, { BackgroundTransparency = 1 })

			-- Face down, arriving.
			local card = buildCard(view, result)
			card.holder.Rotation = -10
			tween(card.grow, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
			tween(card.holder, 0.4, { Rotation = 0 }, Enum.EasingStyle.Back)
			sfx(SFX.arrive)
			mount(scope, stage, "RadialBurst", { cframe = CFrame.new(focus), scale = 1.4 + rank * 0.2, tint = TINT[rarity] }):burst(1)
			wait(0.35)

			-- Charging: the rarer, the longer and the harder it shakes.
			sfx(SFX.charge[rarity])
			local chargeStart = os.clock()
			local charge = CHARGE[rarity]
			while os.clock() - chargeStart < charge and not skipping do
				local k = (os.clock() - chargeStart) / charge
				local jitter = rank * 1.2 * k
				card.holder.Position = UDim2.new(0.5, math.noise(os.clock() * 30, 1) * jitter, 0.48, math.noise(os.clock() * 30, 2) * jitter)
				card.backEdge.Thickness = 5 + 4 * k * (0.5 + 0.5 * math.sin(os.clock() * 30))
				local pulse = 150 * (1 + 0.12 * k * (0.5 + 0.5 * math.sin(os.clock() * 18)))
				card.emblem.Size = UDim2.fromOffset(pulse, pulse * 11 / 12)
				RunService.RenderStepped:Wait()
			end
			card.holder.Position = UDim2.fromScale(0.5, 0.48)

			-- Over.
			sfx(SFX.flip)
			turn(card)
			sfx(SFX.reveal[rarity])
			impact(scope, stage, focus, rarity, if rank >= 5 then 0.9 else 0.6)
			if rank >= 4 then
				shake(if rank >= 5 then 2 else 1, 0.5)
				punch(if rank >= 5 then 8 else 4)
			end
			view.flash.BackgroundColor3 = glow
			view.flash.BackgroundTransparency = 0.55
			tween(view.flash, 0.35, { BackgroundTransparency = 1 })
			for i, star in ipairs(card.stars) do
				task.delay(0.25 + i * 0.12, function()
					sfx({ { "sparkle", 0.35, 1 + i * 0.09 } })
					tween(star, 0.25, { Size = UDim2.fromOffset(28, 28) }, Enum.EasingStyle.Back)
				end)
			end
			if card.badge then
				task.delay(0.3 + #card.stars * 0.12, function()
					card.badge.Visible = true
					card.badge.Size = UDim2.fromOffset(0, 0)
					sfx(SFX.new)
					tween(card.badge, 0.3, { Size = UDim2.fromOffset(78, 30) }, Enum.EasingStyle.Back)
				end)
			end
			-- The icon floats.
			scope:add(RunService.RenderStepped:Connect(function()
				if card.icon.Parent then
					card.icon.Position = UDim2.new(0.5, 0, 0.34, math.sin(os.clock() * 2.4) * 5)
				end
			end))
			waitClick(0.7)
			clear()
		end

		for index, result in ipairs(results) do
			if skipping then
				break
			end
			reveal(result, index, #results)
		end

		-- 6. The summary, for more than one.
		skipping = false
		view.skip.button.Visible = false
		view.counter.Text = ""
		if #results > 1 then
			view.flash.BackgroundColor3 = Color3.new(1, 1, 1)
			tween(view.flash, 0.4, { BackgroundTransparency = 1 })
			tween(grade, 0.4, { TintColor = NIGHT_GRADE:Lerp(GLOW[best], 0.12) })
			local clear = aura(scope, stage, focus, best)
			sfx(SFX.summary)
			showSummary(view, results)
			waitClick(1.0)
			clear()
		elseif view.flash.BackgroundTransparency < 1 then
			-- A single wish skipped before its card: show the card after all.
			reveal(results[1], 1, 1)
		end

		sfx(SFX.close)
		showBars(view, false)
		tween(view.fade, 0.35, { BackgroundTransparency = 0 })
		task.wait(0.4)
	end)

	scope:destroy()
	active = false
	if not ok then
		warn("[WishCinematic]", err)
	end
end

return Cinematic
