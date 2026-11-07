# Wing accessories in Roblox

How the seven wing pairs in this folder became the rigged models in
`ReplicatedStorage.WingAssets` (place assets: save the place to keep them).

1. `export_wings.ps1` reads each `<Item>.vox`, places every piece from the
   scene graph (piece `_t` = lo + size // 2; the 40-voxel lift is on the root
   node only, so it is not subtracted), converts to Roblox axes
   (X = x, Y = z, Z = y: wings behind a character facing -Z, `L_` on the
   wearer's left), greedy-merges each piece into coloured boxes and writes
   `data/<Item>.lua` with the pivots and parents from `../rigging.json`.
2. `BuildWings.lua` (Studio, Edit) unions each piece's boxes into one part
   at 0.05 studs per voxel, joins every piece to its parent with a Motor6D at
   its pivot, and adds a `WingMount` attachment at the Frame origin.
   Load a Folder holding `BuildWings` and `Data` (rojo-build them to an .rbxm,
   copy it into Studio's `content/` folder, `game:GetObjects("rbxasset://...")`),
   then `require(folder.BuildWings)(folder.Data, 0.05)`.

The GLBs in `../rigged` are not used: importing them needs Studio's 3D
importer and an upload, which this project's MCP route can't own for the
group game. The voxel unions keep the crisp look and the same joints.

Runtime: `ServerScriptService.WingService` mounts the worn pair on the
UpperTorso's BodyBackAttachment and keeps the character's `Flying` attribute;
`StarterPlayerScripts.WingAnimator` animates the joints on every client.
In Studio, a `DebugWings` attribute on the player (an item name) shows a pair
without wearing it.
