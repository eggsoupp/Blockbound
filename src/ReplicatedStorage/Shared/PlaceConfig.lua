--[[
	PlaceConfig

	Which of BlockBound's places this server (or client) is running in.

		PlaceConfig.kind()      -> "World" | "Island"
		PlaceConfig.isIsland()  -> boolean
		PlaceConfig.isWorld()   -> boolean

	BlockBound is one game with two places built from the same code:

	  World   the procedurally generated open world everybody explores together
	  Island  a player's own persistent island, one private server per island

	Both places run every script in this project. A system that only belongs in
	one of them asks here and stands down in the other, rather than the two
	places carrying different copies of the code.

	HOW THE ANSWER IS DECIDED, IN ORDER

	  1. In Studio only: a "PlaceKind" attribute on Workspace, set to "Island" or
	     "World". Lets either place be tested as the other without publishing.
	     Ignored in live servers, so one left behind by accident cannot turn the
	     real world into an island.
	  2. game.PlaceId == IslandPlaceId  ->  "Island"
	  3. Anything else                  ->  "World"

	World is the fallback on purpose: an unconfigured or unknown place behaves
	exactly as the game did before islands existed.

	Fill the two IDs in from the Creator Dashboard (BlockBound -> Places).
]]

local RunService = game:GetService("RunService")

local PlaceConfig = {}

--[[
	Both must be places of THIS experience. A reserved server - which is what
	every island is - can only be made for a place in the experience asking for
	it, so an Island place from another experience can never be travelled to.

	The game moved to a group-owned experience in October 2026. The ids it had
	before, 82014616047124 (World) and 123514939860898 (Island), belong to the
	old one and do not work here.
]]

-- The open world. Also the game's start place.
PlaceConfig.WorldPlaceId = 127569658424596

-- The island place, "Island" in this experience (added 2026-10-18 as a copy of
-- the World place, assets and all). Set it to 0 to switch islands off: /island
-- then says so rather than attempting a teleport that cannot work.
PlaceConfig.IslandPlaceId = 93541670199012

local KINDS = { World = true, Island = true }

local cachedKind = nil

local function resolveKind()
	if RunService:IsStudio() then
		local override = workspace:GetAttribute("PlaceKind")
		if override ~= nil then
			if KINDS[override] then
				return override
			end
			warn(string.format(
				"[PlaceConfig] Workspace.PlaceKind is %q; expected \"World\" or \"Island\". Ignoring it.",
				tostring(override)
			))
		end
	end

	if PlaceConfig.IslandPlaceId ~= 0 and game.PlaceId == PlaceConfig.IslandPlaceId then
		return "Island"
	end

	return "World"
end

--[[
	Cached after the first call: other modules read it at require time to pick
	their configuration, and every one of them has to agree for the whole
	session. Changing the Studio attribute mid-test does nothing until the next
	play session.
]]
function PlaceConfig.kind(): string
	if not cachedKind then
		cachedKind = resolveKind()
	end
	return cachedKind
end

function PlaceConfig.isIsland(): boolean
	return PlaceConfig.kind() == "Island"
end

function PlaceConfig.isWorld(): boolean
	return PlaceConfig.kind() == "World"
end

return PlaceConfig
