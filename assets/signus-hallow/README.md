# Signus — Hallowed Eclipse

Open **signus_hallowed_eclipse.vox** in MagicaVoxel's scene/world editor. The file
contains the complete assembled boss, with four named objects and a shared
24-colour opaque palette. No reference images or external dependencies are
needed to open the asset.

The sculpture uses the supplied Signus references for the recessed hood, wrapped
cowl, rear shadow thorns and floating tapered silhouette. Its palette combines
deep violet and plum with orchid, magenta and lavender. Pearl-pink eyes are the
primary focal point; the small chest clasp contains the only multicolour opal
accent. The back has a raised keel, folded shoulder reliefs and an inlaid sigil.

## Coordinates and assembly

- **Up: +Z. Forward: −Y.** X is the transverse axis.
- Occupied dimensions: **100 × 50 × 146 voxels** (X × Y × Z).
- Horizontal bounds: X = −50 to +50, Y = −25 to +25, using voxel boundaries.
- Vertical bounds: Z = 7 to 153. Root pivot: **(0, 0, 80)**.
- Neutral floating pose; no walking anatomy or animation clips.
- 167,352 occupied voxels; 672,069 bytes in the `.vox` file.

The scene's model centers are placed at useful rotation pivots. Preserve the
scene transforms and canvas padding when importing. Padding stores no voxels.
The translations below are relative to the root pivot.

| Object | Local translation | World pivot | Purpose |
| --- | --- | --- | --- |
| 01 Core and Thorn Mantle | (0, 0, 0) | (0, 0, 80) | Torso, cowl, rigid lower folds, rear thorns and clasp |
| 02 Hood and Visage | (0, −3, 28) | (0, −3, 108) | Small neck turns and tilts |
| 03 Left Crescent Sleeve | (−27, −2, 14) | (−27, −2, 94) | −X shoulder appendage |
| 04 Right Crescent Sleeve | (27, −2, 14) | (27, −2, 94) | +X shoulder appendage |

Hover, turn, tilt and lunge using the parent transform. The hood and sleeves may
receive small secondary rotations; their overlapping-looking forms are solid
sculptures, with no cloth, chains, particle ornaments or simulation required.
Each moving part has its own closed voxel volume. For game integration, mesh the
exposed surfaces per object, preserving hard edges and palette colours. Avoid
creating a separate engine object for every voxel. The assembled neutral pose
has 44,434 exposed unit faces before greedy meshing.

## Validation

The saved binary was parsed back, including its scene graph and parent/child
transforms. Every decoded position and palette index exactly matches the source.
Each object is one connected component. The assembled model has no duplicate
occupied positions, disconnected fragments, or enclosed empty cells. All palette
alpha values are 255. Eye materials have a subtle emissive property; their colour
and opacity remain readable in importers that ignore material extensions.

The asset uses the standard `SIZE`, `XYZI`, `RGBA`, `nTRN`, `nGRP`, `nSHP`, `LAYR`,
`MATL` and `NOTE` chunks in a VOX 150 container, following the
[official MagicaVoxel format](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt)
and [scene extensions](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox-extension.txt).
Validation was programmatic; the MagicaVoxel desktop application was not run.

`previews/signus_multiview.png`, `previews/signus_hero.png` and
`previews/signus_gameplay_scale.png` show the actual decoded `.vox` geometry.
Preview illumination and backgrounds are not stored in the model. The asset
contains no floor, pedestal, text, environment, baked shadows or attack effects.

`validation.json` contains the exact bounds, component pivots, voxel counts and
SHA-256 digest. `source/build_signus.py` is the editable sculpture and exporter;
it needs Python, NumPy and Pillow and rebuilds this asset and its previews.
