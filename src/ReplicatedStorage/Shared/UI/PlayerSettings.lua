--[[
	PlayerSettings

	The player's own settings: what each one is, what it starts at, and the one
	place it is changed. Client-side; the server keeps a copy in the save.

		PlayerSettings.get("musicVolume")            -- 0..1
		PlayerSettings.set("musicVolume", 0.5)
		PlayerSettings.reset()                       -- everything back to default
		PlayerSettings.Changed:Connect(function(key, value) ... end)

	View distance is NOT one of these. The server has to agree to it, so it has
	its own remotes (see ServerScriptService.SettingsServer), and the server
	saves the distance it applied rather than one a client asked for.

	APPLYING

	The two volumes are applied here, so nothing else has to: music through
	Music.setVolume, which owns Sound.Volume, and effects through
	Sounds.MasterVolume, which every sound reads as it plays. The combat toggles
	are only read - HealthClient asks before it draws a damage number or flashes
	the screen.

	SAVING

	Every change is sent to the server a moment after the last one, so dragging
	a slider is one save rather than sixty. The server stores them in the
	"settings" section of the player's save record, and sends them back when
	the record loads. Until it has - or if it never does, in Studio without API
	access - the defaults are used and changes simply do not persist.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Sounds = require(Shared:WaitForChild("Audio"):WaitForChild("Sounds"))
local Music = require(Shared.Audio:WaitForChild("Music"))

local PlayerSettings = {}

--[[
	Every setting, its kind and its default. The server checks what it is sent
	against the same kinds (SettingsServer.STORED); a setting added here has to
	be added there too, or it will not be saved.
]]
PlayerSettings.Definitions = {
	musicVolume = { kind = "volume", default = Music.DefaultVolume },
	sfxVolume = { kind = "volume", default = 1 },
	damageNumbers = { kind = "toggle", default = true },
	hitFlash = { kind = "toggle", default = true },
}

-- How long after the last change the save is sent.
local SAVE_DELAY = 1

PlayerSettings.Changed = Instance.new("BindableEvent")

local values = {}
for key, definition in pairs(PlayerSettings.Definitions) do
	values[key] = definition.default
end

local function valid(key: string, value: any): boolean
	local definition = PlayerSettings.Definitions[key]
	if not definition then
		return false
	end
	if definition.kind == "volume" then
		return type(value) == "number" and value == value and value >= 0 and value <= 1
	end
	return type(value) == "boolean"
end

local function apply(key: string, value: any)
	if key == "musicVolume" then
		Music.setVolume(value)
	elseif key == "sfxVolume" then
		Sounds.MasterVolume = value
	end
end

local syncRemote: RemoteEvent? = nil
local saveToken = 0

local function scheduleSave()
	saveToken += 1
	local token = saveToken
	task.delay(SAVE_DELAY, function()
		if token == saveToken and syncRemote then
			syncRemote:FireServer(table.clone(values))
		end
	end)
end

function PlayerSettings.get(key: string): any
	return values[key]
end

function PlayerSettings.getDefault(key: string): any
	local definition = PlayerSettings.Definitions[key]
	return definition and definition.default
end

-- Changes a setting, applies it, tells listeners, and saves it shortly after.
function PlayerSettings.set(key: string, value: any)
	if PlayerSettings.Definitions[key] and PlayerSettings.Definitions[key].kind == "volume" and type(value) == "number" then
		value = math.clamp(value, 0, 1)
	end
	if not valid(key, value) or values[key] == value then
		return
	end

	values[key] = value
	apply(key, value)
	PlayerSettings.Changed:Fire(key, value)
	scheduleSave()
end

function PlayerSettings.reset()
	for key, definition in pairs(PlayerSettings.Definitions) do
		PlayerSettings.set(key, definition.default)
	end
end

-- The defaults are applied straight away, so the game sounds right before the
-- save has come back.
for key, value in pairs(values) do
	apply(key, value)
end

--[[
	The saved values, when the server has them.

	Off the requiring thread: Remotes.wait yields until the server makes the
	remote, and a module everything requires must not hold its callers up on
	that. Asks once on start too, since the server's own push on load can land
	before this listener exists.
]]
task.spawn(function()
	local remote = Remotes.wait("SettingsSync", 30)
	if not remote then
		warn("[PlayerSettings] no SettingsSync remote; settings will not be saved this session.")
		return
	end
	syncRemote = remote

	remote.OnClientEvent:Connect(function(saved)
		if type(saved) ~= "table" then
			return
		end
		for key in pairs(PlayerSettings.Definitions) do
			local value = saved[key]
			if valid(key, value) and values[key] ~= value then
				values[key] = value
				apply(key, value)
				PlayerSettings.Changed:Fire(key, value)
			end
		end
	end)

	remote:FireServer(nil)
end)

return PlayerSettings
