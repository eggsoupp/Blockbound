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
