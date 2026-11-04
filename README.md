# BlockBound

Rojo source for BlockBound's Scripts, LocalScripts and ModuleScripts.

## Layout

`src/` mirrors the Roblox tree, one file per script:

| Folder | Roblox location |
| --- | --- |
| `src/ServerScriptService/` | ServerScriptService |
| `src/ReplicatedStorage/` | ReplicatedStorage (shared modules live in `Shared/`) |
| `src/StarterPlayer/StarterPlayerScripts/` | client LocalScripts |
| `src/StarterPlayer/StarterCharacterScripts/` | per-character LocalScripts |
| `src/Workspace/` | Workspace |

Extensions set the class: `.server.lua` = Script, `.client.lua` = LocalScript, `.lua` = ModuleScript.

- `default.project.json` maps each file to its Roblox name (e.g. `Day-Night Cycle.server.lua` → `Day/Night Cycle`).
- `$ignoreUnknownInstances` is on for every container, so models, VFX, GUIs and other non-code instances stay in the place file and are never touched by Rojo.
- `scripts-manifest.json` is the record of the original export (Roblox path, class, file, SHA-256 of the exported source).

## Workflow

1. Open the place in Studio.
2. From this folder: `C:/Users/Elias/Documents/Rojo/rojo.exe serve`
3. Connect with the Rojo Studio plugin.

Sync is one-way (files → Studio). Edit scripts here, not in Studio, or your Studio edits will be overwritten.

New scripts need an entry in `default.project.json` (or put them under a folder you map with `$path`).

## Luau limit: 200 local variables per scope

Luau can only hold **200 local variables at once in one function scope**, and
a script's top level counts as one scope. Every `local x = ...` and
`local function f()` written at the top of a script uses one slot, and slots
are only freed when their scope ends, which for the top level is never.

Go over it and the **whole script fails to load** with:

```
Out of local registers when trying to allocate <name>: exceeded limit 200
```

When that script is a ModuleScript, everything that `require`s it breaks too.
Breaking TerrainManager took mining, enemies, weapons, crafting, spawning and
the debug console down with it.

The count is not exactly the number of `local` lines (temporaries use slots
too), so treat it as a budget and keep a margin. In practice:
TerrainManager ran fine at 215 top-level `local` lines and failed at 230.

**How to stay under it** when adding to a big script:

- Group related constants and helpers into one table:
  `local Faces = {}` then `function Faces.show(...)` uses one slot, not ten.
- Put helpers that are only used together inside a `do ... end` block. Locals
  declared there free their slots at `end`. Expose what the rest of the file
  needs through a table declared before the block.
- Or move a self-contained feature into its own ModuleScript.

Scripts closest to the limit (top-level `local` lines, 2026-11-04):

| Script | Count |
| --- | --- |
| `ServerScriptService/TerrainManager.lua` | 215 (at the limit) |
| `StarterPlayerScripts/CraftingClient.client.lua` | 166 |
| `Shared/Terrain/BiomeMap.lua` | 127 |

Count them with: `grep -cE '^local ' path/to/Script.lua`

## Places

BlockBound is one game with two places, both synced from this same project:

- **World**: the procedurally generated open world (start place).
- **Island**: each player's own persistent island, one private server per island.

`src/ReplicatedStorage/Shared/PlaceConfig.lua` holds both Place IDs and decides which place the code is running in. Systems that only belong in one place check `PlaceConfig.isIsland()`. To test the island in Studio without publishing, add a string attribute `PlaceKind` = `Island` to Workspace (Studio only; ignored in live servers).

The island's shape and the terrain overrides it needs live in `src/ReplicatedStorage/Shared/Terrain/IslandConfig.lua`.

### Island saving

`ServerScriptService/IslandService` runs an island server: the first player to arrive is the owner (until teleports exist), terrain generation is held until their save is loaded, and the island autosaves every minute, when the owner leaves, and on shutdown. `ServerScriptService/IslandStore` owns the DataStore (`PlayerIslands_v1`, key `island_<userId>`), session locking and the compact save format. Only changes from the shared template are stored: mined and placed blocks, and crafting stations.

To test saving in Studio, turn on **Game Settings > Security > Enable Studio Access to API Services**. Studio then reads and writes the live game's island saves.
