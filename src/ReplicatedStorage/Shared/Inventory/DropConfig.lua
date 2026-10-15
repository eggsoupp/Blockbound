--[[
	DropConfig

	The numbers behind items lying on the ground: how they look and move on
	every client, and the rules the server picks them up by.

	Shared so the drawing and the rules cannot drift apart - the cube that flies
	to you starts exactly where the floating one was. Clients read the pickup
	rules too, which is harmless: they only ever describe what the server does.
	Nothing a client does with them changes a pickup. See ServerScriptService.
	GroundDrops.
]]

local DropConfig = {}

-- ---------------------------------------------------------------------------
-- Look and motion (drawn by each client; see GroundDropClient)
-- ---------------------------------------------------------------------------

-- Edge of the cube, in studs. DropFlight's flying cube is the same size, so a
-- pickup reads as this cube lifting off rather than being swapped for another.
DropConfig.Size = 0.7

-- Neon, a little see-through: a glow, not a lamp.
DropConfig.Transparency = 0.2

-- How high the cube's centre floats above where it would rest on the ground,
-- at the middle of its bob.
DropConfig.Hover = 0.45

-- The bob: up and down by this much either side, once every BobSeconds.
DropConfig.BobHeight = 0.16
DropConfig.BobSeconds = 2.4

-- One full turn about the vertical, every SpinSeconds.
DropConfig.SpinSeconds = 4.5

-- Past this distance from the camera a drop stops animating and just waits.
DropConfig.AnimateDistance = 160

-- ---------------------------------------------------------------------------
-- Rules (enforced by the server only)
-- ---------------------------------------------------------------------------

-- From the character's root to the drop. The root sits about three studs off
-- the ground, so this is roughly five and a half studs across the floor.
DropConfig.PickupRadius = 7

-- How long a drop lies still before it can be taken, so it is seen to land.
DropConfig.PickupDelay = 0.5

-- How long only the player who caused a public drop (mined, chopped, blasted)
-- can take it. Enemy loot is private for its whole life instead.
DropConfig.OwnerSeconds = 10

DropConfig.DespawnSeconds = 300

-- A ceiling on drops in the world at once. Past it the oldest goes.
DropConfig.MaxDrops = 300

return DropConfig
