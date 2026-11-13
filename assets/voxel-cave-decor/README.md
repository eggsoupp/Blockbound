# Voxel cave decorations

The 21 cave decorations of `Shared.Terrain.CaveDecorConfig`, as MagicaVoxel
`.vox` models: one model per height a type can grow to (Icicle, Icicle2,
Icicle3), 42 in all. A voxel is 0.25 studs, so a block is 16 voxels and every
model is 4 x 4n x 4 studs. Colours are the game's block textures recoloured
(see `../voxel-decor`), so they speckle like the rock around them. Neon is
kept to crystal tips and mushroom gills.

Every model is mirror-symmetric: shapes are written in cell-centred
coordinates, and the build mirrors the result and reports any voxel that had
no mirror image (all report 0). FossilBones is mirrored left/right only; the
glowing mushroom across both axes; everything else under all eight mirrors
of the square.

## Files

- `vox/<Model>.vox`: the whole piece. A see-through part is its own object
  (`Ice`, `Glass`).
- `previews/<Model>.png`, `previews/_sheet.png` (a row per biome).
- `roblox/data/<Block>.lua`: box data for ONE block of a model. A tall piece is
  cut into one-block segments, named `<Type><tall>_<segment>` from the bottom
  (`Icicle3_1` is the tip block of a three-block icicle); a one-block piece
  keeps the plain name. 70 blocks. `CaveDecor.segmentName` makes the same names.
- `roblox/BuildCaveDecor.lua`: the Studio (Edit) builder.
- `source/CaveKit.pm` (shapes, symmetry, checks), `source/designs.pl` (the
  pieces), `source/build.pl`.

## Rebuilding

```
perl source/build.pl
```

Then into Studio (Edit):

1. `rojo build roblox/import.project.json -o <Studio>/content/cavedecor.rbxm`
2. `local f = game:GetObjects("rbxasset://cavedecor.rbxm")[1]`
3. For each `f.Data` module:
   `require(f.BuildCaveDecor)(require(module), { parent = ReplicatedStorage.TerrainAssets.Blocks })`
   (destroy the old template of that name first).

`TerrainAssets.Blocks` is a place asset: save the place to keep the templates.

## In the game

A template is an invisible 4-stud Part named after the block, with attribute
`CellArt`, carrying the art as unions (`Body`, `BodyGlow`, `Ice`/`Glass`) that
are unanchored, Massless, without collision or ray, and Welded to it. The
terrain pools and moves the cell Part like any block and the art follows.

- `BlockParts` keeps a `CellArt` cell invisible.
- `ChunkBuilder.applyDecor` lists decoration cells in `data.seeThrough`;
  `ColumnVisibility` and `FaceCulling` then keep drawing (and texturing) the
  floor, ceiling and walls they touch, since the art does not fill its cell.
- `BlockEdits:BreakBlock` breaks a whole piece when any of its blocks is mined.
- Without the templates (a place that lost them) each block falls back to the
  plain placeholder Part described in `CaveDecorConfig`.
