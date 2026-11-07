--[[
	PreloadPlan

	What the loading screen preloads, and in which order: the jobs it hands to
	Shared.Loading.PreloadQueue. Client only.

		local plan = PreloadPlan.new(queue, "mobile")
		plan:essentials()            -- UI art, fonts, the player's own clips
		plan:inventory(snapshot)     -- the hotbar's tools, worn wings, shots
		plan:abilities({ "Fireball" })
		plan:firstPass()             -- what the device has time for
		plan:background()            -- everything else, after the screen

	THE ORDER
	  1 essential   Theme's pixel atlas and item atlas, the font, every
	                locomotion / weapon / tool / flight clip (small, and the
	                player's own body), the swing trail, and the hotbar's
	                tools. The screen waits for these, up to its deadline.
	  2 first pass  The equipped abilities' effects, worn wings, the weapon
	                shots of a legendary on the hotbar; on a computer also the
	                rest of the tools and the weapon shot library. Capped by
	                the device's budget; what does not fit drops to 3.
	  3 background  Boss and enemy assets, every other ability's effects, the
	                terrain props, wings nobody is wearing. Loaded after the
	                screen has faded, with fewer workers.

	Animations here are the published ones. LocomotionAnimations and
	SwingAnimations build KeyframeSequences in code, so there is nothing of
	theirs to download.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local PreloadPlan = {}

--[[
	Per device: workers while the screen is up, workers once playing, and how
	much first-pass weight (roughly, assets) the screen may take on. A phone
	gets fewer of each - a slower radio, and less to spare while it renders.

	Few workers on purpose. Measured in Studio (2026-11-07): 10 workers loaded
	no faster than 4 - the engine's own queue is the limit - but decoding that
	much at once halved the frame rate the screen animates at.
]]
PreloadPlan.Budgets = {
	desktop = { workers = 4, backgroundWorkers = 3, firstPassWeight = 1200 },
	mobile = { workers = 4, backgroundWorkers = 2, firstPassWeight = 160 },
}

--[[
	Ability VFX modules -> what they draw from. Modules not listed use their
	"<Name>Particles" twin when there is one (HeliosVFX -> HeliosParticles).
	The folders are the pack assemblies PackAssembly / LegendaryVFX clone.
]]
PreloadPlan.AbilitySources = {
	StarterVFX = { modules = { "StarterParticles", "CataclysmParticles" }, folders = { "AbilityVFXLibrary" } },
	CometVFX = { folders = { "AbilityVFXLibrary" } },
	AbyssVFX = { modules = { "AbyssParticles" }, folders = { "AbilityVFXLibrary" } },
	ThunderVFX = { folders = { "AbilityVFXLibrary" } },
	LegendaryVFX = { folders = { "LegendaryAbilitySources", "LegendaryExplosionSources", "ReferenceAbilitySources" } },
	ReferenceVFX = { folders = { "ReferenceAbilitySources" } },
}

-- FlightClient's clips (FLIGHT.animations there) and WeaponClient's wind
-- trail texture, which FlightClient's wisps share. They live in client
-- scripts, which cannot be required; keep these in step with them.
PreloadPlan.ScriptClips = {
	"rbxassetid://616006778", -- flight hover
	"rbxassetid://616010382", -- flight cruise
}
PreloadPlan.ScriptTextures = {
	"rbxassetid://16892374733", -- swing trail / flight wisps
}

-- Background order, most likely to be seen first. Folders of
-- ReplicatedStorage, one job per child; modules are scanned for texture ids.
PreloadPlan.Background = {
	{ folder = "Tools", label = "tools" },
	{ folder = "WeaponShotLibrary", label = "effects" },
	{ folder = "AbilityVFXLibrary", label = "effects" },
	{ modules = { "StarterParticles", "CataclysmParticles" }, label = "effects" },
	{ folder = "RecallAura", label = "effects", whole = true },
	{ folder = "WingAssets", label = "wings" },
	{ folder = "LegendaryAbilitySources", label = "effects" },
	{ folder = "LegendaryExplosionSources", label = "effects" },
	{ folder = "ReferenceAbilitySources", label = "effects" },
	{ folder = "TerrainAssets", label = "world" },
	{ folder = "WorldBorderForceField", label = "world", whole = true },
	{ allParticles = true, label = "effects", except = { BlightborerParticles = true, SignusParticles = true } },
	{ modules = { "PixelFlipbooks" }, label = "effects" },
	{ enemyModules = { "CreatureParticles" }, label = "creatures" },
	{ folder = "EnemyAssets", label = "creatures" },
	{ modules = { "BlightborerParticles", "SignusParticles" }, label = "bosses" },
	{ folder = "SignusLibrary", label = "bosses" },
	{ folder = "SignusEclipseLibrary", label = "bosses" },
}

-- ---------------------------------------------------------------------------
-- The device
-- ---------------------------------------------------------------------------

-- "mobile" for a phone or tablet (or the test harness's EmulateTouch), else
-- "desktop". A touch screen small enough to be a phone counts even with a
-- keyboard attached.
function PreloadPlan.device(): string
	local ok, Responsive = pcall(require, Shared:WaitForChild("UI"):WaitForChild("Responsive"))
	if ok then
		if Responsive.isTouch() or (UserInputService.TouchEnabled and Responsive.isSmall()) then
			return "mobile"
		end
		return "desktop"
	end
	return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "mobile" else "desktop"
end

-- ---------------------------------------------------------------------------
-- Finding assets
-- ---------------------------------------------------------------------------

-- Classes that carry something to download. Plain Parts, Models and
-- Attachments do not, and would make a job look heavier than it is.
local CONTENT_CLASSES = {
	"MeshPart", "SpecialMesh", "UnionOperation", "Decal", "ParticleEmitter", "Beam", "Trail",
	"Sound", "Animation", "SurfaceAppearance", "ImageLabel", "ImageButton", "Sky", "Clothing",
}

local function weigh(instance: Instance): number
	local weight = 0
	local function count(item)
		for _, class in ipairs(CONTENT_CLASSES) do
			if item:IsA(class) then
				weight += 1
				return
			end
		end
	end
	count(instance)
	for _, item in ipairs(instance:GetDescendants()) do
		count(item)
	end
	return math.max(1, weight)
end

-- "rbxassetid://1", "http://www.roblox.com/asset/?id=1" -> "rbxassetid://1"
local function normalise(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	local id = string.match(value, "^rbxassetid://(%d+)$") or string.match(value, "[?&]id=(%d+)")
	return if id then "rbxassetid://" .. id else nil
end

-- Every asset id string anywhere in a module's data. Functions and Instances
-- are skipped; cycles are not followed.
local function scan(value: any, out: { string }, seen: { [any]: boolean }, depth: number)
	if type(value) == "string" then
		local id = normalise(value)
		if id then
			table.insert(out, id)
		end
	elseif type(value) == "table" and not seen[value] and depth < 8 then
		seen[value] = true
		for _, child in pairs(value) do
			scan(child, out, seen, depth + 1)
		end
	end
end

local function idsIn(data: any): { string }
	local out = {}
	scan(data, out, {}, 0)
	return out
end

-- A module's return value, or nil. Never errors.
local function load(moduleScript: Instance?)
	if not (moduleScript and moduleScript:IsA("ModuleScript")) then
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	return if ok then result else nil
end

local VFX = Shared:WaitForChild("Abilities"):WaitForChild("VFX")

-- ---------------------------------------------------------------------------
-- The plan
-- ---------------------------------------------------------------------------

--[[
	BATCHES. Small things share a PreloadAsync call: at join every call takes a
	few hundred milliseconds to come back however small its asset, so one call
	per texture spends the screen's time waiting on calls. A batch stays small
	(a few entries, a little weight) so a slow asset in it holds up few others,
	and PreloadQueue writes off any job that runs long.
]]
local BATCH_ENTRIES = 6
local BATCH_WEIGHT = 16

local Plan = {}
Plan.__index = Plan

function PreloadPlan.new(queue, device: string)
	local self = setmetatable({}, Plan)
	self.queue = queue
	self.device = if PreloadPlan.Budgets[device] then device else "desktop"
	self.budget = PreloadPlan.Budgets[self.device]
	self.firstPassWeight = 0
	-- item (an Instance or an asset id) -> the job it was queued in
	self.owners = {}
	self.serial = 0
	return self
end

-- The job an Instance or asset id was queued in, if it was.
function Plan:owner(item)
	return self.owners[item]
end

--[[
	Queues one job, holding tier 2 to the device's budget: once the first pass
	is full, more first-pass work waits for the background instead.
]]
function Plan:_add(job, tier: number)
	local existing = self.queue:get(job.key)
	if existing and existing.tier <= tier then
		return existing
	end

	if tier == 2 then
		local weight = job.weight or 1
		if self.firstPassWeight + weight > self.budget.firstPassWeight then
			tier = 3
		else
			self.firstPassWeight += weight
		end
	end

	return self.queue:add(job, tier)
end

--[[
	Queues `entries` ({ key, weight, make }) in batches. `make` builds what
	PreloadAsync is given. An entry already queued is not queued again; if it
	is wanted sooner now, its whole job moves up (a hotbar tool found in the
	first pass's batch of tools becomes essential, batch and all).
]]
function Plan:_batch(entries, label: string, tier: number)
	local batch, weight, keys = {}, 0, {}

	local function flush()
		if #batch == 0 then
			return
		end
		local items = {}
		for _, entry in ipairs(batch) do
			table.insert(items, entry.make())
		end
		self.serial += 1
		local job = self:_add({ key = label .. "#" .. self.serial, label = label, items = items, weight = weight }, tier)
		for _, entry in ipairs(batch) do
			self.owners[entry.key] = job
		end
		batch, weight = {}, 0
	end

	for _, entry in ipairs(entries) do
		local owner = self.owners[entry.key]
		if owner then
			if tier < owner.tier then
				self.queue:add(owner, tier)
			end
		elseif not keys[entry.key] then
			keys[entry.key] = true
			if #batch > 0 and (#batch >= BATCH_ENTRIES or weight + entry.weight > BATCH_WEIGHT) then
				flush()
			end
			table.insert(batch, entry)
			weight += entry.weight
		end
	end
	flush()
end

function Plan:instances(list: { Instance }, label: string, tier: number)
	local entries = {}
	for _, instance in ipairs(list) do
		table.insert(entries, {
			key = instance,
			weight = weigh(instance),
			make = function()
				return instance
			end,
		})
	end
	self:_batch(entries, label, tier)
end

-- A folder's children, batched; `whole` keeps the folder as one item.
function Plan:folder(folder: Instance?, label: string, tier: number, whole: boolean?)
	if not folder then
		return
	end
	self:instances(if whole then { folder } else folder:GetChildren(), label, tier)
end

-- Images are fetched through unparented ImageLabels, the way PixelUI and
-- ItemThumbnails check theirs.
function Plan:images(ids: { string }, label: string, tier: number)
	local entries = {}
	for _, id in ipairs(ids) do
		table.insert(entries, {
			key = id,
			weight = 1,
			make = function()
				local probe = Instance.new("ImageLabel")
				probe.Image = id
				return probe
			end,
		})
	end
	self:_batch(entries, label, tier)
end

function Plan:clips(ids: { string }, tier: number)
	local entries = {}
	for _, id in ipairs(ids) do
		table.insert(entries, {
			key = id,
			weight = 1,
			make = function()
				local animation = Instance.new("Animation")
				animation.AnimationId = id
				return animation
			end,
		})
	end
	self:_batch(entries, "animations", tier)
end

function Plan:moduleTextures(moduleScript: Instance?, label: string, tier: number)
	local data = load(moduleScript)
	if data ~= nil then
		self:images(idsIn(data), label, tier)
	end
end

-- ---------------------------------------------------------------------------
-- 1. Essentials
-- ---------------------------------------------------------------------------

function Plan:essentials()
	local UI = Shared:WaitForChild("UI")
	local Theme = load(UI:WaitForChild("Theme"))

	-- The interface's art first: every window and the hotbar is drawn off
	-- these two images.
	if Theme then
		-- The pixel atlas alone, so the screen can re-skin the moment it is in.
		if Theme.Pixel and normalise(Theme.Pixel.Atlas) then
			self:images({ Theme.Pixel.Atlas }, "interface", 1)
		end
		local art = {}
		if normalise(Theme.ItemAtlas) then
			table.insert(art, Theme.ItemAtlas)
		end
		for _, id in pairs(Theme.Pixel and Theme.Pixel.Images or {}) do
			if normalise(id) then
				table.insert(art, id)
			end
		end
		self:images(art, "interface", 1)

		-- The font: a label in each of the game's faces.
		if type(Theme.Fonts) == "table" then
			local labels = {}
			for _, font in pairs(Theme.Fonts) do
				local label = Instance.new("TextLabel")
				label.FontFace = font
				label.Text = "Blockbound 0123456789"
				table.insert(labels, label)
			end
			self:_add({ key = "fonts", label = "interface", items = labels }, 1)
		end
	end

	self:images(PreloadPlan.ScriptTextures, "effects", 1)

	-- Every published clip the player's own character plays: walking and
	-- running per weapon class, the weapon combos and dashes, mining and
	-- chopping, flight. Each is a few kilobytes; all of them are cheaper than
	-- one wrong-looking first swing.
	local Combat = Shared:WaitForChild("Combat")
	local Tools = Shared:WaitForChild("Tools")
	local WeaponAnimations = load(Combat:WaitForChild("WeaponAnimations"))
	local LocomotionProfiles = load(Tools:WaitForChild("LocomotionProfiles"))
	local ToolConfig = load(Tools:WaitForChild("ToolConfig"))

	local clips = {}
	if LocomotionProfiles and type(LocomotionProfiles.forDefinition) == "function" then
		local definitions = { false, { classification = "Pickaxe" }, { classification = "Tool" } }
		for class in pairs(WeaponAnimations and WeaponAnimations.Classes or {}) do
			table.insert(definitions, { weaponClass = class })
		end
		for _, definition in ipairs(definitions) do
			local ok, profile = pcall(LocomotionProfiles.forDefinition, definition or nil)
			if ok then
				for _, id in ipairs(idsIn(profile)) do
					table.insert(clips, id)
				end
			end
		end
	end
	for _, id in ipairs(idsIn(WeaponAnimations)) do
		table.insert(clips, id)
	end
	for _, id in ipairs(idsIn(ToolConfig)) do
		table.insert(clips, id)
	end
	for _, id in ipairs(PreloadPlan.ScriptClips) do
		table.insert(clips, id)
	end
	self:clips(clips, 1)
end

-- ---------------------------------------------------------------------------
-- What the player carries
-- ---------------------------------------------------------------------------

--[[
	The hotbar's tools are essential: they are in the player's hand the moment
	the screen goes. Worn wings and the shots a legendary on the hotbar fires
	are the player's own effects, so they come in the first pass.
]]
function Plan:inventory(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	local hotbar = 9
	local constants = load(ReplicatedStorage:FindFirstChild("InventoryConstants"))
	if constants and type(constants.HotbarSlots) == "number" then
		hotbar = constants.HotbarSlots
	end

	local toolsFolder = ReplicatedStorage:FindFirstChild("Tools")
	local wingsFolder = ReplicatedStorage:FindFirstChild("WingAssets")
	local WeaponShots = load(Shared:WaitForChild("Combat"):FindFirstChild("WeaponShots"))

	local tools, wings = {}, {}
	local shotsOnHotbar = false
	for index, slot in pairs(snapshot) do
		local name = type(slot) == "table" and slot.name
		if type(name) == "string" and name ~= "" then
			local tool = index <= hotbar and toolsFolder and toolsFolder:FindFirstChild(name)
			if tool then
				table.insert(tools, tool)
			end
			if index <= hotbar and WeaponShots and type(WeaponShots.profileFor) == "function" and WeaponShots.profileFor(name) then
				shotsOnHotbar = true
			end
			local pair = wingsFolder and wingsFolder:FindFirstChild(name)
			if pair then
				table.insert(wings, pair)
			end
		end
	end

	self:instances(tools, "your hotbar", 1)
	self:instances(wings, "your wings", 2)
	if shotsOnHotbar then
		self:folder(ReplicatedStorage:FindFirstChild("WeaponShotLibrary"), "weapon effects", 2)
	end
end

function Plan:abilities(names: { string })
	local AbilityConfig = load(Shared:WaitForChild("Abilities"):FindFirstChild("AbilityConfig"))
	if not AbilityConfig or type(AbilityConfig.get) ~= "function" then
		return
	end

	for _, name in ipairs(names) do
		local ok, definition = pcall(AbilityConfig.get, name)
		local vfx = ok and type(definition) == "table" and definition.vfx
		if type(vfx) == "string" then
			local sources = PreloadPlan.AbilitySources[vfx]
			local modules = sources and sources.modules or { (string.gsub(vfx, "VFX$", "Particles")) }
			for _, moduleName in ipairs(modules) do
				self:moduleTextures(VFX:FindFirstChild(moduleName), "your abilities", 2)
			end
			for _, folderName in ipairs(sources and sources.folders or {}) do
				self:folder(ReplicatedStorage:FindFirstChild(folderName), "your abilities", 2)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- 2. The first pass
-- ---------------------------------------------------------------------------

-- What a computer has time for while the screen is up. A phone keeps its
-- budget for the player's own things above.
function Plan:firstPass()
	if self.device ~= "desktop" then
		return
	end
	self:folder(ReplicatedStorage:FindFirstChild("Tools"), "tools", 2)
	self:folder(ReplicatedStorage:FindFirstChild("WeaponShotLibrary"), "weapon effects", 2)
end

-- ---------------------------------------------------------------------------
-- 3. The background
-- ---------------------------------------------------------------------------

function Plan:background()
	for _, entry in ipairs(PreloadPlan.Background) do
		if entry.folder then
			self:folder(ReplicatedStorage:FindFirstChild(entry.folder), entry.label, 3, entry.whole)
		end
		for _, name in ipairs(entry.modules or {}) do
			self:moduleTextures(VFX:FindFirstChild(name), entry.label, 3)
		end
		for _, name in ipairs(entry.enemyModules or {}) do
			local enemies = Shared:FindFirstChild("Enemies")
			self:moduleTextures(enemies and enemies:FindFirstChild(name), entry.label, 3)
		end
		if entry.allParticles then
			for _, child in ipairs(VFX:GetChildren()) do
				if string.match(child.Name, "Particles$") and not entry.except[child.Name] then
					self:moduleTextures(child, entry.label, 3)
				end
			end
		end
	end
end

return PreloadPlan
