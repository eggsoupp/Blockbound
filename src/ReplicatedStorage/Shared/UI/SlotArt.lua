--[[
	SlotArt

	Puts the game's slot frame art (Theme.SlotImage) on a tile or button, and
	draws a plain stand-in frame in code if that image cannot be loaded.

		SlotArt.apply(tile)   -- an ImageButton or ImageLabel

	WHY THE STAND-IN

	The art is an uploaded asset, and uploaded assets go missing: that is how the
	inventory once lost its frames. An ImageLabel pointed at an image that will
	not load draws nothing at all, silently, so every slot in the game vanishes
	and only the items float on screen. A plain frame is ugly by comparison, but
	every slot is still where it should be and can still be used.

	The check is made once per session. Tiles applied before the answer arrives
	wait for it; tiles applied after get the same treatment straight away.

	The stand-in follows ImageColor3, so the tints scripts already put on the
	art - hover, drop target, disabled - still show, on its border.
]]

local ContentProvider = game:GetService("ContentProvider")

local Theme = require(script.Parent:WaitForChild("Theme"))

local SlotArt = {}

local STAND_IN_CORNER = UDim.new(0, 6)
local STAND_IN_STROKE = 2
local STAND_IN_STROKE_TRANSPARENCY = 0.15

-- "unknown" until a tile asks, "checking" while the image loads, then
-- "loaded" or "failed" for the rest of the session.
local state = "unknown"

-- Tiles applied while the check is running. Weak, so a tile destroyed before
-- the answer arrives is not kept alive for it.
local waiting = setmetatable({}, { __mode = "k" })

local function drawStandIn(tile: GuiObject)
	if tile:FindFirstChild("SlotArtStroke") then
		return
	end

	tile.Image = ""
	tile.BackgroundColor3 = Theme.Color.PanelRaised
	tile.BackgroundTransparency = Theme.Transparency.Panel

	local corner = Instance.new("UICorner")
	corner.Name = "SlotArtCorner"
	corner.CornerRadius = STAND_IN_CORNER
	corner.Parent = tile

	local stroke = Instance.new("UIStroke")
	stroke.Name = "SlotArtStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = STAND_IN_STROKE
	stroke.Transparency = STAND_IN_STROKE_TRANSPARENCY
	stroke.Parent = tile

	local function followTint()
		stroke.Color = tile.ImageColor3
	end
	followTint()
	tile:GetPropertyChangedSignal("ImageColor3"):Connect(followTint)
end

local function check()
	state = "checking"

	task.spawn(function()
		local loaded = false

		if Theme.SlotImage ~= "" then
			local probe = Instance.new("ImageLabel")
			probe.Image = Theme.SlotImage
			pcall(function()
				ContentProvider:PreloadAsync({ probe }, function(_, status)
					loaded = status == Enum.AssetFetchStatus.Success
				end)
			end)
			probe:Destroy()
		end

		state = if loaded then "loaded" else "failed"

		if not loaded then
			warn(string.format(
				"[SlotArt] Theme.SlotImage (%q) did not load, so slots are drawn as plain frames. "
					.. "If it was uploaded as a Decal, its ID is not the image's: paste it into any "
					.. "ImageLabel's Image property in Studio, which swaps it for the image ID, and "
					.. "put that in Theme.SlotImage.",
				Theme.SlotImage
			))

			-- pcall because a tile may have been destroyed while it waited, and
			-- one dead tile should not leave the rest without a frame.
			for tile in pairs(waiting) do
				pcall(drawStandIn, tile)
			end
		end

		table.clear(waiting)
	end)
end

function SlotArt.apply(tile: GuiObject)
	tile.Image = Theme.SlotImage

	if state == "failed" then
		drawStandIn(tile)
		return
	end
	if state == "loaded" then
		return
	end

	waiting[tile] = true
	if state == "unknown" then
		check()
	end
end

return SlotArt
