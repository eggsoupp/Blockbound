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

## Places

BlockBound is one game with two places, both synced from this same project:

- **World**: the procedurally generated open world (start place).
- **Island**: each player's own persistent island, one private server per island.

`src/ReplicatedStorage/Shared/PlaceConfig.lua` holds both Place IDs and decides which place the code is running in. Systems that only belong in one place check `PlaceConfig.isIsland()`. To test the island in Studio without publishing, add a string attribute `PlaceKind` = `Island` to Workspace (Studio only; ignored in live servers).

The island's shape and the terrain overrides it needs live in `src/ReplicatedStorage/Shared/Terrain/IslandConfig.lua`.
