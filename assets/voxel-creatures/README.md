# Voxel creatures

Five rig-free creatures taken from the "55 voxel creatures" pack
(`Downloads/55_voxel_creatures/vox_files`, CC0 sources listed in its `links.txt`).
Each is a single rigid body - floating, hopping, slithering or gliding - so none
needs joints; all motion is scripted (`src/ServerScriptService/Creatures`).

| Asset (EnemyAssets) | Source vox | Voxel size | Biomes | Signature move |
|---|---|---|---|---|
| `Lasereye` | lasereye.vox | 0.095 | Swamp | charges, locks aim, fires a laser that cover blocks |
| `Snowman` | snowman.vox | 0.115 | Snow | lobs snowballs on a real arc; belly-flop lunge |
| `GreenWasp` | green_wasp.vox | 0.065 | Desert, Plains | buzzes, hangs, darts in a straight sting |
| `Shrike` | yellow-billed_shrike.vox (factor 2) | 0.2 | Hallow, Snow | circles overhead, swoops through you |
| `Cobra` | cobra.vox | 0.085 | Desert | slithers and sways, rears and strikes |

Picked because their poses work as one rigid piece. Anything with legs or arms
that has to walk (most of the pack) was left out.

## Pipeline

1. `source/vox.ps1` reads the pack's files: most are the old Build-engine dense
   `.vox` (int32 size, x-major bytes with z counting down, 255 = empty, 6-bit
   palette); `green_raptor` and `killer_snowman` are MagicaVoxel.
2. `source/export.ps1 -path <vox> [-factor 2] -out boxes/<Name>.lua` drops the
   256-colour palette swatch each model has lying beside it, optionally
   downsamples, and greedy-merges same-coloured voxels into boxes (hidden voxels
   merge with any colour), in Roblox axes (X = x, Y = up, Z = y; front = -Z).
3. `source/BuildCreature.lua` (Studio, Edit) turns a boxes file into Parts and
   unions them into one `PartOperation` with `UsePartColor` off, so each
   creature is one coloured, anchored part.
4. `source/sheet.ps1` renders front/side contact sheets (`previews/`) used to
   choose the creatures.

Facing corrections live in `EnemyConfig` (`modelRotation`): Cobra is 180.
GreenWasp and Shrike have their pivot moved to the body's centre so they bank
and pitch about it.
