# Blockbound beginner equipment

Small, simple solid voxel models based on the supplied axe, pickaxe and sword
references. These replace the earlier detailed versions at the same filenames.

- `axe.vox`: wooden shaft, short iron poll and broad cutting blade.
- `pickaxe.vox`: wooden shaft and two curved iron points.
- `sword.vox`: short iron blade, simple guard, leather grip and small pommel.

All three retain the original identical 256-slot RGBA palette, with 22 named
colours. The simplified models use a small subset of those colours. Palette
indices remain unchanged; `palette.json` and `shared_palette.gpl` are included.

## Size and orientation

The shared canvas is now **32 x 8 x 40 voxels**. Tools are about 29 voxels tall;
the sword is about 36. Shafts and cutting edges are two voxels thick, with four
voxels at sockets and the sword spine. Ornate engravings, rivets and hanging ties
have been removed to suit beginner equipment.

Models point along +Z, with broad faces towards +/-Y. The handle axis is X=16,
Y=4; the raw base reference is (16,4,0). Each file contains one model, without a
backdrop or ground. Exact occupied bounds and voxel counts are in
`validation.json`. These are smaller voxel grids, so adjust the import scale if
you want to retain the previous versions' world-space height.

## Previews and validation

`previews/tools_lineup.png` shows the new models at the same voxel scale.
Individual transparent renders and four-view sheets have also been replaced.
Previews are rendered from the exported files; face lighting is preview-only.

The build checks binary readback against source geometry, valid bounds, unique
positions, valid palette indices, identical palettes, and one face-connected
component per model. The zip is checked for archive errors. MagicaVoxel and
game-engine UI import have not been tested here.

`source/build_tools.py` regenerates all three models, previews and the zip using
Python, NumPy and Pillow. Files use standard MagicaVoxel VOX 150 chunks.
