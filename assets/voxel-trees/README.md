# Blockbound biome trees

Three original voxel trees based on the supplied references: layered green
evergreen foliage, a crooked purple corruption tree, and a broad crimson tree.
Every visible surface is made of opaque, coloured unit cubes.

## Files

| File | Contents |
| --- | --- |
| `normal_tree.vox` | Complete normal tree, with **two separately selectable models/layers**: Leaves and Trunk and branches. |
| `normal_leaves.vox` | Normal foliage alone. |
| `normal_trunk.vox` | Normal trunk, roots and branches alone. |
| `corruption_tree.vox` | Complete purple tree, one model. |
| `crimson_tree.vox` | Complete red tree, one model. |

`Blockbound_Trees.zip` contains all five files, previews, this guide, validation
results and the editable generation script.

## Scale and alignment

All files use the same **80 x 80 x 112 voxel canvas** and palette. Trees are
approximately 100 voxels high. Z is up. There is no ground tile or backdrop in
the model files.

For the normal tree, open `normal_tree.vox` to get both models already assembled.
Alternatively, place the standalone leaves and trunk at **identical positions,
rotations and scales**. Preserve the full canvas when importing: the empty space
under the leaves is intentional and keeps the two models aligned. Disable
automatic trimming or individual recentering if your importer offers these.

The root pivot is `(40, 40, 0)` in raw voxel coordinates, or `(0, 0, 0)` in the
included MagicaVoxel scene. Every object has the same scene transform. If an
importer crops its models, use `occupied_min` in `validation.json` to restore the
original placement: a cropped model's minimum corner belongs at
`occupied_min - (40,40,0)` relative to the tree's ground pivot, scaled by your
chosen voxel size. Convert Z-up to the engine's up axis for the whole assembly.

## Previews

- `previews/tree_lineup.png`: all three trees at the same scale.
- `previews/normal_parts.png`: separate normal trunk, leaves and assembled tree.
- `previews/*_views.png`: front, side, back and three-quarter views.
- `previews/normal_tree.png`, `corruption_tree.png`, `crimson_tree.png`: individual
  renders with transparent backgrounds.

Previews show the actual voxel geometry, with directional face shading and no
smooth meshes. Lighting and the presentation sheet's ground shadows are not
baked into the assets.

## Validation and editable source

Each exported file was parsed back and compared voxel-for-voxel with its source.
Bounds, unique voxel coordinates, palette indices, named scene nodes, layer
references and transforms passed validation. Each model is one face-connected
component; the assembled normal tree is also connected, and its trunk and leaves
have no overlapping voxels. SHA-256 hashes and occupied bounds are recorded in
`validation.json`. The files have not been tested in the MagicaVoxel desktop UI
or imported into Roblox Studio during this task.

The files use the [MagicaVoxel VOX format](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt)
and its [scene extensions](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox-extension.txt).

`source/build_trees.py` contains the deterministic sculpt, palette, writer,
reader, validator and preview renderer. Run it with Python, NumPy and Pillow to
regenerate this tree pack. It only writes inside this asset folder.
